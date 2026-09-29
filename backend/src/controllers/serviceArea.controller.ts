import { Request, Response } from 'express';
import { AppDataSource } from '../config/database';
import { ServiceArea } from '../entities/ServiceArea';
import { RedisService } from '../services/redis.service';
import { ServiceabilityService, isValidLat, isValidLng } from '../services/serviceability.service';

const serviceAreaRepository = AppDataSource.getRepository(ServiceArea);

const SERVICE_AREA_CHECK_CACHE_PREFIX = 'cache:service-area:check:v1:';
const SERVICE_AREA_CHECK_CACHE_PATTERN = 'cache:service-area:check:*';
/** Pincode coverage changes rarely; invalidate on admin writes */
const SERVICE_AREA_CHECK_TTL_SEC = 3600;

type ServiceAreaCheckPayload =
  | {
      success: true;
      available: true;
      serviceArea: {
        id: number;
        pincode: string;
        city: string;
        state: string;
        country: string;
      };
    }
  | {
      success: true;
      available: false;
      message: string;
    };

function serviceAreaCheckCacheKey(cleanPincode: string, country: string): string {
  return `${SERVICE_AREA_CHECK_CACHE_PREFIX}${cleanPincode}:${country}`;
}

/**
 * Check if a pincode is serviceable
 * GET /api/service-area/check?pincode=123456&country=India
 */
export class ServiceAreaController {
  private static async invalidateServiceAreaCheckCache(): Promise<void> {
    try {
      const n = await RedisService.deleteKeysMatching(SERVICE_AREA_CHECK_CACHE_PATTERN);
      if (n > 0) {
        console.log(`🗑️ Service area check cache invalidated (${n} key(s))`);
      }
    } catch (e) {
      console.warn('Service area check cache invalidation failed:', e);
    }
  }

  static async checkAvailability(req: Request, res: Response): Promise<void> {
    try {
      const { pincode, country = 'India', lat, lng } = req.query;

      // Preferred path: GPS radius check against the single store. Falls back to
      // the pincode lookup when coordinates aren't supplied or the store radius
      // isn't configured (so no-GPS clients still work).
      const latNum = lat != null ? Number(lat) : NaN;
      const lngNum = lng != null ? Number(lng) : NaN;
      if (isValidLat(latNum) && isValidLng(lngNum)) {
        if (ServiceabilityService.isConfigured()) {
          const result = ServiceabilityService.check(latNum, lngNum);
          res.json({
            success: true,
            available: result.available,
            distanceKm: result.distanceKm,
            radiusKm: result.radiusKm,
            ...(result.available
              ? {}
              : { message: "We don't deliver to your location yet" }),
          });
          return;
        }
        console.warn(
          '[service-area] coordinates supplied but STORE_LAT/STORE_LNG/DELIVERY_RADIUS_KM not configured — falling back to pincode'
        );
      }

      if (!pincode || typeof pincode !== 'string') {
        res.status(400).json({
          success: false,
          message: 'Pincode or coordinates (lat, lng) are required',
        });
        return;
      }

      // Clean pincode (remove spaces, ensure 6 digits for India)
      const cleanPincode = pincode.trim().replace(/\s+/g, '');
      const countryStr = country as string;

      const cacheKey = serviceAreaCheckCacheKey(cleanPincode, countryStr);
      try {
        const cached = await RedisService.getJson<ServiceAreaCheckPayload>(cacheKey);
        if (cached && cached.success === true) {
          res.json(cached);
          return;
        }
      } catch {
        // Redis hiccup — fall through to DB
      }

      // Find service area
      const serviceArea = await serviceAreaRepository.findOne({
        where: {
          pincode: cleanPincode,
          country: countryStr,
          isActive: true,
        },
      });

      let payload: ServiceAreaCheckPayload;

      if (serviceArea) {
        payload = {
          success: true,
          available: true,
          serviceArea: {
            id: serviceArea.id,
            pincode: serviceArea.pincode,
            city: serviceArea.city,
            state: serviceArea.state,
            country: serviceArea.country,
          },
        };
      } else {
        payload = {
          success: true,
          available: false,
          message: 'Service not available in this location',
        };
      }

      try {
        await RedisService.setJson(cacheKey, payload, SERVICE_AREA_CHECK_TTL_SEC);
      } catch (e) {
        console.warn('Service area check cache set failed:', e);
      }

      res.json(payload);
    } catch (error) {
      console.error('Error checking service availability:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
      });
    }
  }

  /**
   * Get all service areas (for admin)
   * GET /api/service-area
   */
  static async getAllServiceAreas(req: Request, res: Response): Promise<void> {
    try {
      const { page = '1', limit = '50', search = '' } = req.query;
      const pageNum = parseInt(page as string, 10);
      const limitNum = parseInt(limit as string, 10);
      const skip = (pageNum - 1) * limitNum;

      const queryBuilder = serviceAreaRepository.createQueryBuilder('serviceArea');

      // Search filter
      if (search && typeof search === 'string') {
        queryBuilder.where(
          '(serviceArea.pincode LIKE :search OR serviceArea.city LIKE :search OR serviceArea.state LIKE :search)',
          { search: `%${search}%` }
        );
      }

      // Get total count
      const total = await queryBuilder.getCount();

      // Get paginated results
      const serviceAreas = await queryBuilder
        .orderBy('serviceArea.createdAt', 'DESC')
        .skip(skip)
        .take(limitNum)
        .getMany();

      res.json({
        success: true,
        data: serviceAreas,
        pagination: {
          page: pageNum,
          limit: limitNum,
          total,
          totalPages: Math.ceil(total / limitNum),
        },
      });
    } catch (error) {
      console.error('Error fetching service areas:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
      });
    }
  }

  /**
   * Create a new service area (admin only)
   * POST /api/service-area
   */
  static async createServiceArea(req: Request, res: Response): Promise<void> {
    try {
      const { pincode, city, state, country = 'India', isActive = true, notes } = req.body;

      if (!pincode || !city || !state) {
        res.status(400).json({
          success: false,
          message: 'Pincode, city, and state are required',
        });
        return;
      }

      // Clean pincode
      const cleanPincode = pincode.trim().replace(/\s+/g, '');

      // Check if already exists
      const existing = await serviceAreaRepository.findOne({
        where: {
          pincode: cleanPincode,
          country: country || 'India',
        },
      });

      if (existing) {
        res.status(400).json({
          success: false,
          message: 'Service area with this pincode already exists',
        });
        return;
      }

      const serviceArea = serviceAreaRepository.create({
        pincode: cleanPincode,
        city: city.trim(),
        state: state.trim(),
        country: country || 'India',
        isActive: isActive !== false,
        notes: notes || null,
      });

      await serviceAreaRepository.save(serviceArea);

      await ServiceAreaController.invalidateServiceAreaCheckCache();

      res.status(201).json({
        success: true,
        message: 'Service area created successfully',
        data: serviceArea,
      });
    } catch (error) {
      console.error('Error creating service area:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
      });
    }
  }

  /**
   * Update a service area (admin only)
   * PUT /api/service-area/:id
   */
  static async updateServiceArea(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const { pincode, city, state, country, isActive, notes } = req.body;

      const serviceArea = await serviceAreaRepository.findOne({
        where: { id: parseInt(id, 10) },
      });

      if (!serviceArea) {
        res.status(404).json({
          success: false,
          message: 'Service area not found',
        });
        return;
      }

      // Update fields
      if (pincode !== undefined) {
        serviceArea.pincode = pincode.trim().replace(/\s+/g, '');
      }
      if (city !== undefined) serviceArea.city = city.trim();
      if (state !== undefined) serviceArea.state = state.trim();
      if (country !== undefined) serviceArea.country = country;
      if (isActive !== undefined) serviceArea.isActive = isActive;
      if (notes !== undefined) serviceArea.notes = notes;

      await serviceAreaRepository.save(serviceArea);

      await ServiceAreaController.invalidateServiceAreaCheckCache();

      res.json({
        success: true,
        message: 'Service area updated successfully',
        data: serviceArea,
      });
    } catch (error) {
      console.error('Error updating service area:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
      });
    }
  }

  /**
   * Delete a service area (admin only)
   * DELETE /api/service-area/:id
   */
  static async deleteServiceArea(req: Request, res: Response): Promise<void> {
    try {
      const { id } = req.params;

      const serviceArea = await serviceAreaRepository.findOne({
        where: { id: parseInt(id, 10) },
      });

      if (!serviceArea) {
        res.status(404).json({
          success: false,
          message: 'Service area not found',
        });
        return;
      }

      await serviceAreaRepository.remove(serviceArea);

      await ServiceAreaController.invalidateServiceAreaCheckCache();

      res.json({
        success: true,
        message: 'Service area deleted successfully',
      });
    } catch (error) {
      console.error('Error deleting service area:', error);
      res.status(500).json({
        success: false,
        message: 'Internal server error',
      });
    }
  }
}
