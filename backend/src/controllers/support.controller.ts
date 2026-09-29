import { Response } from 'express';
import { AppDataSource } from '../config/database';
import { SupportRequest } from '../entities/SupportRequest';
import { User } from '../entities/User';
import { Order } from '../entities/Order';
import { AuthRequest } from '../middleware/auth.middleware';

export class SupportController {
  static async create(req: AuthRequest, res: Response): Promise<void> {
    try {
      const userId = req.user?.id;

      if (!userId) {
        res.status(401).json({
          message: 'Authentication required',
        });
        return;
      }

      const { category, description, orderId } = req.body;

      if (!category || !description?.trim()) {
        res.status(400).json({
          message: 'Category and description are required',
        });
        return;
      }

      const userRepo = AppDataSource.getRepository(User);
      const orderRepo = AppDataSource.getRepository(Order);
      const supportRepo = AppDataSource.getRepository(SupportRequest);

      const user = await userRepo.findOneBy({
        id: userId,
      });

      if (!user) {
        res.status(404).json({
          message: 'User not found',
        });
        return;
      }

      let order: Order | null = null;

      if (orderId) {
        order = await orderRepo.findOne({
          where: {
            id: Number(orderId),
            user: {
              id: userId,
            },
          },
        });

        if (!order) {
          res.status(404).json({
            message: 'Order not found',
          });
          return;
        }
      }

      const supportRequest = supportRepo.create({
        user,
        order,
        category,
        description: description.trim(),
        status: 'open',
      });

      await supportRepo.save(supportRequest);

      res.status(201).json({
        message: 'Support request submitted successfully',
        request: supportRequest,
      });
    } catch (error) {
      console.error('Create support request error:', error);

      res.status(500).json({
        message: 'Error submitting support request',
      });
    }
  }
  static async list(req: AuthRequest, res: Response): Promise<void> {
  try {
    if (req.user?.role !== 'admin') {
      res.status(403).json({
        message: 'Admin access required',
      });
      return;
    }

    const supportRepo = AppDataSource.getRepository(SupportRequest);

    const requests = await supportRepo.find({
      relations: ['user', 'order'],
      order: {
        createdAt: 'DESC',
      },
    });

    res.status(200).json({
      requests,
    });
  } catch (error) {
    console.error('List support requests error:', error);

    res.status(500).json({
      message: 'Error fetching support requests',
    });
  }
}

static async updateStatus(
  req: AuthRequest,
  res: Response,
): Promise<void> {
  try {
    if (req.user?.role !== 'admin') {
      res.status(403).json({
        message: 'Admin access required',
      });
      return;
    }

    const requestId = Number(req.params.id);
    const { status } = req.body;

    const allowedStatuses = [
      'open',
      'in_progress',
      'resolved',
      'closed',
    ];

    if (!Number.isInteger(requestId)) {
      res.status(400).json({
        message: 'Invalid support request ID',
      });
      return;
    }

    if (!allowedStatuses.includes(status)) {
      res.status(400).json({
        message: 'Invalid support request status',
        allowedStatuses,
      });
      return;
    }

    const supportRepo = AppDataSource.getRepository(SupportRequest);

    const request = await supportRepo.findOne({
      where: {
        id: requestId,
      },
      relations: ['user', 'order'],
    });

    if (!request) {
      res.status(404).json({
        message: 'Support request not found',
      });
      return;
    }

    request.status = status;

    await supportRepo.save(request);

    res.status(200).json({
      message: 'Support request status updated successfully',
      request,
    });
  } catch (error) {
    console.error('Update support request error:', error);

    res.status(500).json({
      message: 'Error updating support request',
    });
  }
}
}