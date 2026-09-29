import * as admin from 'firebase-admin';
import { AppDataSource } from '../config/database';
import { AuthRequest } from '../middleware/auth.middleware';
import { Campaign } from '../entities/Campaign';
import { Response } from 'express';
import { LessThanOrEqual, MoreThanOrEqual } from 'typeorm';
import { mapCampaignPublic, normalizeMediaForStorage } from '../utils/media-url.util';

/**
 * CampaignController — Admin creates campaigns, users fetch matching ones
 *
 * Admin:  POST /campaigns (create), PUT /campaigns/:id (update), DELETE /campaigns/:id
 * Public: GET /campaigns?pincode=243003 (fetch matching campaigns for homepage)
 * Admin:  POST /campaigns/:id/push (send push notification for campaign)
 */
export class CampaignController {

  /**
   * GET /api/campaigns?pincode=243003
   *
   * Returns campaigns grouped by placement, filtered by:
   * - pincode match (or global if no target_pincodes)
   * - active + not expired + started
   * - sorted by priority
   */
  static async getCampaigns(req: AuthRequest, res: Response): Promise<void> {
    try {
      const pincode = (req.query.pincode as string)?.trim() || '';
      const city = (req.query.city as string)?.trim() || '';

      const campaignRepo = AppDataSource.getRepository(Campaign);
      const now = new Date();

      // Fetch all active, started, not-expired campaigns
      const allCampaigns = await campaignRepo.find({
        where: {
          isActive: true,
          startsAt: LessThanOrEqual(now),
          expiresAt: MoreThanOrEqual(now),
        },
        order: { priority: 'ASC', createdAt: 'DESC' },
      });

      // Filter by pincode/city targeting
      const matched = allCampaigns.filter((c) => {
        // Pincode targeting
        const pincodes = c.targetPincodes;
        if (pincodes && pincodes.length > 0) {
          if (!pincode || !pincodes.includes(pincode)) return false;
        }

        // City targeting
        const cities = c.targetCities;
        if (cities && cities.length > 0) {
          if (!city || !cities.some((tc) => tc.toLowerCase() === city.toLowerCase())) return false;
        }

        return true;
      });

      // Group by placement
      const grouped: Record<string, Campaign[]> = {
        hero_banners: [],
        category_strips: [],
        product_spotlights: [],
        bottom_banners: [],
      };

      for (const c of matched) {
        switch (c.placement) {
          case 'hero_banner':
            if (grouped.hero_banners.length < 5) grouped.hero_banners.push(c);
            break;
          case 'category_strip':
            if (grouped.category_strips.length < 3) grouped.category_strips.push(c);
            break;
          case 'product_spotlight':
            if (grouped.product_spotlights.length < 3) grouped.product_spotlights.push(c);
            break;
          case 'bottom_banner':
            if (grouped.bottom_banners.length < 2) grouped.bottom_banners.push(c);
            break;
        }
      }

      const out: Record<string, ReturnType<typeof mapCampaignPublic>[]> = {
        hero_banners: grouped.hero_banners.map(mapCampaignPublic),
        category_strips: grouped.category_strips.map(mapCampaignPublic),
        product_spotlights: grouped.product_spotlights.map(mapCampaignPublic),
        bottom_banners: grouped.bottom_banners.map(mapCampaignPublic),
      };
      res.json(out);
    } catch (error) {
      console.error('❌ Error fetching campaigns:', error);
      res.status(500).json({ message: 'Error fetching campaigns' });
    }
  }

  /**
   * GET /api/admin/campaigns — All campaigns (admin view)
   */
  static async getAllCampaigns(req: AuthRequest, res: Response): Promise<void> {
    try {
      const campaignRepo = AppDataSource.getRepository(Campaign);
      const campaigns = await campaignRepo.find({
        order: { createdAt: 'DESC' },
        relations: ['createdBy'],
      });
      res.json(campaigns.map(mapCampaignPublic));
    } catch (error) {
      console.error('❌ Error fetching all campaigns:', error);
      res.status(500).json({ message: 'Error fetching campaigns' });
    }
  }

  /**
   * POST /api/admin/campaigns — Create new campaign
   */
  static async createCampaign(req: AuthRequest, res: Response): Promise<void> {
    try {
      const {
        title, subtitle, imageUrl, ctaText, ctaLink,
        targetPincodes, targetCities,
        placement, priority,
        startsAt, expiresAt,
        pushEnabled,
      } = req.body;

      if (!title || !startsAt || !expiresAt) {
        res.status(400).json({ message: 'title, startsAt, expiresAt required' });
        return;
      }

      const campaignRepo = AppDataSource.getRepository(Campaign);
      const campaign = campaignRepo.create({
        title,
        subtitle: subtitle || null,
        imageUrl: normalizeMediaForStorage(imageUrl),
        ctaText: ctaText || 'Shop Now',
        ctaLink: ctaLink || null,
        targetPincodes: targetPincodes || [],
        targetCities: targetCities || [],
        placement: placement || 'hero_banner',
        priority: priority || 0,
        startsAt: new Date(startsAt),
        expiresAt: new Date(expiresAt),
        isActive: true,
        pushEnabled: pushEnabled || false,
        createdBy: req.user || null,
      });

      await campaignRepo.save(campaign);

      // Auto-send push if enabled
      if (campaign.pushEnabled) {
        await CampaignController._sendCampaignPush(campaign);
      }

      console.log(`✅ [Campaign] Created: "${title}" (id=${campaign.id})`);
      res.status(201).json(mapCampaignPublic(campaign));
    } catch (error) {
      console.error('❌ Error creating campaign:', error);
      res.status(500).json({ message: 'Error creating campaign' });
    }
  }

  /**
   * PUT /api/admin/campaigns/:id — Update campaign
   */
  static async updateCampaign(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const campaignRepo = AppDataSource.getRepository(Campaign);
      const campaign = await campaignRepo.findOneBy({ id: Number(id) });

      if (!campaign) {
        res.status(404).json({ message: 'Campaign not found' });
        return;
      }

      // Update fields
      const fields = [
        'title', 'subtitle', 'imageUrl', 'ctaText', 'ctaLink',
        'targetPincodes', 'targetCities',
        'placement', 'priority',
        'startsAt', 'expiresAt', 'isActive', 'pushEnabled',
      ];

      for (const field of fields) {
        if (req.body[field] !== undefined) {
          if (field === 'startsAt' || field === 'expiresAt') {
            (campaign as any)[field] = new Date(req.body[field]);
          } else if (field === 'imageUrl') {
            (campaign as any)[field] = normalizeMediaForStorage(req.body[field]) ?? null;
          } else {
            (campaign as any)[field] = req.body[field];
          }
        }
      }

      await campaignRepo.save(campaign);
      console.log(`✅ [Campaign] Updated: "${campaign.title}" (id=${campaign.id})`);
      res.json(mapCampaignPublic(campaign));
    } catch (error) {
      console.error('❌ Error updating campaign:', error);
      res.status(500).json({ message: 'Error updating campaign' });
    }
  }

  /**
   * DELETE /api/admin/campaigns/:id — Delete campaign
   */
  static async deleteCampaign(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const campaignRepo = AppDataSource.getRepository(Campaign);
      const result = await campaignRepo.delete(Number(id));

      if (result.affected === 0) {
        res.status(404).json({ message: 'Campaign not found' });
        return;
      }

      console.log(`✅ [Campaign] Deleted id=${id}`);
      res.json({ message: 'Campaign deleted' });
    } catch (error) {
      console.error('❌ Error deleting campaign:', error);
      res.status(500).json({ message: 'Error deleting campaign' });
    }
  }

  /**
   * POST /api/admin/campaigns/:id/push — Send push for campaign
   */
  static async sendCampaignPush(req: AuthRequest, res: Response): Promise<void> {
    try {
      const { id } = req.params;
      const campaignRepo = AppDataSource.getRepository(Campaign);
      const campaign = await campaignRepo.findOneBy({ id: Number(id) });

      if (!campaign) {
        res.status(404).json({ message: 'Campaign not found' });
        return;
      }

      const result = await CampaignController._sendCampaignPush(campaign);
      res.json(result);
    } catch (error) {
      console.error('❌ Error sending campaign push:', error);
      res.status(500).json({ message: 'Error sending push notification' });
    }
  }

  /**
   * Internal: Send FCM topic push for a campaign
   */
  private static async _sendCampaignPush(
    campaign: Campaign
  ): Promise<{ sent: number; failed: number; totalTopics: number }> {
    const pincodes = campaign.targetPincodes || [];
    let sent = 0;
    const errors: string[] = [];

    if (pincodes.length === 0) {
      // Global campaign — send to "all_users" topic
      try {
        await admin.messaging().send({
          topic: 'all_users',
          notification: { title: campaign.title, body: campaign.subtitle || '' },
          data: { type: 'PROMO_OFFER', campaignId: String(campaign.id) },
        });
        sent++;
      } catch (e: unknown) {
        errors.push(`all_users: ${e instanceof Error ? e.message : String(e)}`);
      }
    } else {
      // Pincode-targeted campaign
      for (const pincode of pincodes) {
        try {
          await admin.messaging().send({
            topic: `pincode_${pincode}`,
            notification: { title: campaign.title, body: campaign.subtitle || '' },
            data: {
              type: 'PROMO_OFFER',
              campaignId: String(campaign.id),
              pincode: String(pincode),
            },
          });
          sent++;
        } catch (e: unknown) {
          errors.push(`pincode_${pincode}: ${e instanceof Error ? e.message : String(e)}`);
        }
      }
    }

    // Mark as sent
    const campaignRepo = AppDataSource.getRepository(Campaign);
    campaign.pushSent = true;
    campaign.pushSentAt = new Date();
    await campaignRepo.save(campaign);

    const totalTopics = pincodes.length || 1;
    console.log(`📤 [Campaign Push] "${campaign.title}" → ${sent}/${totalTopics} topics`);

    return { sent, failed: totalTopics - sent, totalTopics };
  }
}
