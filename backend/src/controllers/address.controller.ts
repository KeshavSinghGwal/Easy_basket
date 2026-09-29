import { Response } from 'express';
import { AppDataSource } from '../config/database';
import { Address } from '../entities/Address';
import { User } from '../entities/User';
import { AuthRequest } from '../middleware/auth.middleware';

// Helper function to calculate distance between two coordinates (Haversine formula)
function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371; // Radius of the Earth in km
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distance in km
}

// Helper function to calculate string similarity (Levenshtein distance based)
function calculateStringSimilarity(str1: string, str2: string): number {
  const longer = str1.length > str2.length ? str1 : str2;
  const shorter = str1.length > str2.length ? str2 : str1;

  if (longer.length === 0) return 1.0;

  const distance = levenshteinDistance(longer, shorter);
  return (longer.length - distance) / longer.length;
}

// Levenshtein distance calculation
function levenshteinDistance(str1: string, str2: string): number {
  const matrix: number[][] = [];

  for (let i = 0; i <= str2.length; i++) {
    matrix[i] = [i];
  }

  for (let j = 0; j <= str1.length; j++) {
    matrix[0][j] = j;
  }

  for (let i = 1; i <= str2.length; i++) {
    for (let j = 1; j <= str1.length; j++) {
      if (str2.charAt(i - 1) === str1.charAt(j - 1)) {
        matrix[i][j] = matrix[i - 1][j - 1];
      } else {
        matrix[i][j] = Math.min(
          matrix[i - 1][j - 1] + 1,
          matrix[i][j - 1] + 1,
          matrix[i - 1][j] + 1
        );
      }
    }
  }

  return matrix[str2.length][str1.length];
}

export class AddressController {
  static async getUserAddresses(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;

      if (!userId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const addressRepository = AppDataSource.getRepository(Address);
      const addresses = await addressRepository.find({
        where: { user: { id: userId } },
        order: { isDefault: 'DESC', createdAt: 'DESC' },
      });

      res.json(addresses);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error fetching addresses' });
    }
  }

  static async createAddress(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;

      if (!userId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const {
        addressLine1,
        addressLine2,
        city,
        state,
        pincode,
        landmark,
        isDefault,
        latitude,
        longitude,
        tag,
      } = req.body;

      if (!addressLine1 || !city || !state || !pincode) {
        res.status(400).json({
          message: 'Address line 1, city, state, and pincode are required',
        });
        return;
      }

      const userRepository = AppDataSource.getRepository(User);
      const user = await userRepository.findOneBy({ id: userId });

      if (!user) {
        res.status(404).json({ message: 'User not found' });
        return;
      }

      const addressRepository = AppDataSource.getRepository(Address);

      // Check for duplicate addresses (Blinkit-style: prevent duplicates)
      // Check by coordinates (if provided) or by address details
      let existingAddress = null;

      if (latitude && longitude) {
        // Check for addresses with same coordinates (within 50 meters tolerance)
        // Using approximate distance calculation
        const allAddresses = await addressRepository.find({
          where: { user: { id: userId } },
        });

        for (const addr of allAddresses) {
          if (addr.latitude && addr.longitude) {
            const distance = calculateDistance(
              parseFloat(latitude),
              parseFloat(longitude),
              parseFloat(addr.latitude),
              parseFloat(addr.longitude)
            );
            // If within 50 meters, consider it duplicate
            if (distance < 0.05) {
              // 0.05 km = 50 meters
              existingAddress = addr;
              break;
            }
          }
        }
      }

      // If no coordinate match, check by address details (same pincode + similar address)
      if (!existingAddress) {
        const similarAddresses = await addressRepository.find({
          where: {
            user: { id: userId },
            pincode: pincode,
          },
        });

        // Check if address line 1 is very similar (fuzzy match)
        for (const addr of similarAddresses) {
          const similarity = calculateStringSimilarity(
            addressLine1.toLowerCase().trim(),
            addr.addressLine1.toLowerCase().trim()
          );
          // If 80% similar, consider it duplicate
          if (similarity > 0.8) {
            existingAddress = addr;
            break;
          }
        }
      }

      // If duplicate found, update it instead of creating new one
      if (existingAddress) {
        // Update existing address
        existingAddress.addressLine1 = addressLine1;
        existingAddress.addressLine2 = addressLine2;
        existingAddress.city = city;
        existingAddress.state = state;
        existingAddress.pincode = pincode;
        existingAddress.landmark = landmark;
        existingAddress.latitude = latitude;
        existingAddress.longitude = longitude;
        existingAddress.tag = tag || null;

        // If setting as default, unset other defaults
        if (isDefault) {
          await addressRepository.update({ user: { id: userId } }, { isDefault: false });
          existingAddress.isDefault = true;
        } else {
          existingAddress.isDefault = isDefault || false;
        }

        await addressRepository.save(existingAddress);
        res.status(200).json({
          ...existingAddress,
          message: 'Address updated (duplicate prevented)',
        });
        return;
      }

      // If setting as default, unset other defaults
      if (isDefault) {
        await addressRepository.update({ user: { id: userId } }, { isDefault: false });
      }

      const address = addressRepository.create({
        user,
        addressLine1,
        addressLine2,
        city,
        state,
        pincode,
        landmark,
        isDefault: isDefault || false,
        latitude,
        longitude,
        tag: tag || null,
      });

      await addressRepository.save(address);
      res.status(201).json(address);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error creating address' });
    }
  }

  static async updateAddress(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      const { id } = req.params;

      if (!userId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const addressRepository = AppDataSource.getRepository(Address);
      const address = await addressRepository.findOne({
        where: { id: Number(id), user: { id: userId } },
      });

      if (!address) {
        res.status(404).json({ message: 'Address not found' });
        return;
      }

      const {
        addressLine1,
        addressLine2,
        city,
        state,
        pincode,
        landmark,
        isDefault,
        latitude,
        longitude,
        tag,
      } = req.body;

      if (addressLine1) address.addressLine1 = addressLine1;
      if (addressLine2 !== undefined) address.addressLine2 = addressLine2;
      if (city) address.city = city;
      if (state) address.state = state;
      if (pincode) address.pincode = pincode;
      if (landmark !== undefined) address.landmark = landmark;
      if (latitude !== undefined) address.latitude = latitude;
      if (longitude !== undefined) address.longitude = longitude;
      if (tag !== undefined) address.tag = tag;

      if (isDefault === true) {
        await addressRepository.update({ user: { id: userId } }, { isDefault: false });
        address.isDefault = true;
      }

      await addressRepository.save(address);
      res.json(address);
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error updating address' });
    }
  }

  static async deleteAddress(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;
      const { id } = req.params;

      if (!userId) {
        res.status(401).json({ message: 'Authentication required' });
        return;
      }

      const addressRepository = AppDataSource.getRepository(Address);
      const address = await addressRepository.findOne({
        where: { id: Number(id), user: { id: userId } },
      });

      if (!address) {
        res.status(404).json({ message: 'Address not found' });
        return;
      }

      await addressRepository.remove(address);
      res.json({ message: 'Address deleted successfully' });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error deleting address' });
    }
  }
}
