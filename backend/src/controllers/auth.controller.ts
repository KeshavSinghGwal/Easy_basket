import { Request, Response } from 'express';

import { AppDataSource } from '../config/database';
import { AuthRequest } from '../middleware/auth.middleware';
import { JWT_SECRET } from '../config/jwt';
import { RateLimitService } from '../services/rate-limit.service';
import { RefreshToken } from '../entities/RefreshToken';
import { TwilioService } from '../services/twilio.service';
import { User } from '../entities/User';
import { canonicalizeIndianMobile } from '../utils/phone.util';
import { S3Service } from '../services/s3.service';
import { detectImageType } from '../utils/image-type.util';
import crypto from 'crypto';
import jwt from 'jsonwebtoken';

function formatBirthday(birthday: Date | string | null | undefined): string | null {
  if (birthday == null) return null;
  if (birthday instanceof Date) return birthday.toISOString().split('T')[0];
  return String(birthday).split('T')[0];
}

function normalizePhoneNumber(input: unknown): string | null {
  if (input == null) return null;
  const s = String(input).replace(/\s/g, '').trim();
  return s.length > 0 ? s : null;
}

/** Coerce client payloads (JSON may send numbers or odd types). */
function normalizeFcmToken(input: unknown): string | null {
  if (input == null || input === '') return null;
  const s = typeof input === 'string' ? input.trim() : String(input).trim();
  return s.length >= 10 ? s : null;
}

export class AuthController {
  private static readonly LOGIN_TEST_OTP_VALUE = '123456';

  /** When `LOGIN_USE_TEST_OTP` is true, login skips Twilio and verify accepts only `1234`. Otherwise Twilio SMS + verification apply (if configured). */
  private static isLoginTestOtpEnabled(): boolean {
    const v = process.env.LOGIN_USE_TEST_OTP?.trim().toLowerCase();
    return v === 'true' || v === '1' || v === 'yes';
  }

  static async login(req: Request, res: Response): Promise<void> {
    const canonical = canonicalizeIndianMobile(req.body?.phoneNumber);
    if (!canonical) {
      res.status(400).json({ message: 'A valid 10-digit Indian mobile number is required' });
      return;
    }

    try {
      const useTestOtp = AuthController.isLoginTestOtpEnabled();
      const willSendSms = TwilioService.isConfigured() && !useTestOtp;

      // Rate-limit only when an SMS will actually be sent (cost + harassment defense).
      // Phone first: caps harassment of a specific number. IP second: caps cost-drain
      // attacks that rotate phone numbers from one source.
      if (willSendSms) {
        const phoneCheck = await RateLimitService.checkAndIncrement(
          `otp:phone:${canonical}`,
          3,
          15 * 60
        );
        if (!phoneCheck.allowed) {
          res.set('Retry-After', String(phoneCheck.resetInSec));
          res.status(429).json({
            message: 'Too many OTP requests for this number. Try again in a few minutes.',
            retryAfterSec: phoneCheck.resetInSec,
          });
          return;
        }

        const ip = req.ip ?? 'unknown';
        const ipCheck = await RateLimitService.checkAndIncrement(
          `otp:ip:${ip}`,
          10,
          60 * 60
        );
        if (!ipCheck.allowed) {
          res.set('Retry-After', String(ipCheck.resetInSec));
          res.status(429).json({
            message: 'Too many OTP requests from this device. Try again later.',
            retryAfterSec: ipCheck.resetInSec,
          });
          return;
        }
      }

      if (willSendSms) {
        await TwilioService.sendVerification(canonical, 'sms');
        console.log(`OTP sent via Twilio for ${canonical}`);
        res.json({ message: 'OTP sent successfully to your phone number.' });
      } else if (TwilioService.isConfigured() && useTestOtp) {
        console.log(
          `OTP test mode (LOGIN_USE_TEST_OTP) for ${canonical}; SMS not sent. Use ${AuthController.LOGIN_TEST_OTP_VALUE}.`
        );
        res.json({
          message: `OTP not sent (test mode). Use ${AuthController.LOGIN_TEST_OTP_VALUE} to verify.`,
        });
      } else {
        console.log(
          `OTP request for ${canonical}. Use OTP: ${AuthController.LOGIN_TEST_OTP_VALUE}`
        );
        res.json({
          message: `OTP sent successfully. Use ${AuthController.LOGIN_TEST_OTP_VALUE} for testing.`,
        });
      }
    } catch (error) {
      console.error('Error sending OTP:', error);
      const message = error instanceof Error ? error.message : 'Error sending OTP';
      res.status(500).json({
        message: 'Error sending OTP',
        error: process.env.NODE_ENV === 'development' ? message : undefined,
      });
    }
  }

  static async updateProfileImage(
  req: AuthRequest,
  res: Response
): Promise<void> {
  try {
    const userId = req.user?.id;

    if (!userId) {
      res.status(401).json({
        message: 'Authentication required',
      });
      return;
    }

    if (!req.file) {
      res.status(400).json({
        message: 'No image uploaded',
      });
      return;
    }

    // Verify actual image type using file bytes.
    const detected = detectImageType(req.file.buffer);

    if (!detected) {
      res.status(400).json({
        message: 'That file is not a JPEG, PNG or WebP image.',
        code: 'INVALID_IMAGE',
      });
      return;
    }

    req.file.mimetype = detected.mime;
    req.file.originalname = `profile.${detected.ext}`;

    const userRepository = AppDataSource.getRepository(User);

    const user = await userRepository.findOneBy({
      id: userId,
    });

    if (!user) {
      res.status(404).json({
        message: 'User not found',
      });
      return;
    }

    

    const result = await S3Service.uploadProfileImage(
      req.file,
      userId
    );

    user.profileImageUrl = result.url;

    await userRepository.save(user);

    res.status(200).json({
      success: true,
      message: 'Profile image updated successfully',
      user: {
        id: user.id,
        phoneNumber: user.phoneNumber,
        name: user.name,
        email: user.email,
        birthday: formatBirthday(user.birthday),
        role: user.role,
        isActive: user.isActive,
        profileImageUrl: user.profileImageUrl,
      },
    });
  } catch (error) {
    console.error('Error updating profile image:', error);

    const message =
      error instanceof Error
        ? error.message
        : 'Error updating profile image';

    res.status(500).json({
      message,
    });
  }
}

  static async verify(req: Request, res: Response): Promise<void> {
    const phoneNumber = normalizePhoneNumber(req.body?.phoneNumber);
    const otp = req.body?.otp != null ? String(req.body.otp).trim() : '';
    const fcmCandidate = normalizeFcmToken(req.body?.fcmToken);

    if (!phoneNumber || !otp) {
      res.status(400).json({ message: 'Phone number and OTP are required' });
      return;
    }

    try {
      let otpValid = false;
      const useTestOtp = AuthController.isLoginTestOtpEnabled();
      const expectedTest = AuthController.LOGIN_TEST_OTP_VALUE;

      if (TwilioService.isConfigured()) {
        if (useTestOtp) {
          if (otp !== expectedTest) {
            res.status(400).json({ message: `Invalid OTP. Use ${expectedTest} in test mode.` });
            return;
          }
          otpValid = true;
        } else {
          otpValid = await TwilioService.checkVerification(phoneNumber, otp);
          if (!otpValid) {
            res.status(400).json({ message: 'Invalid or expired OTP. Please request a new one.' });
            return;
          }
        }
      } else if (otp === expectedTest) {
        otpValid = true;
      } else {
        res.status(400).json({ message: `Invalid OTP. Please use ${expectedTest}` });
        return;
      }

      // Check database connection
      if (!AppDataSource.isInitialized) {
        console.error('❌ Database not initialized');
        res.status(500).json({ message: 'Database connection not available' });
        return;
      }

      console.log(`🔍 Verifying OTP for ${phoneNumber}...`);
      const userRepository = AppDataSource.getRepository(User);
      let user = await userRepository.findOneBy({ phoneNumber });
      console.log(`✅ User lookup completed: ${user ? 'found' : 'not found'}`);

      if (!user) {
        user = userRepository.create({ phoneNumber });
        await userRepository.save(user);
      }

      if (fcmCandidate) {
        try {
          console.log(`📱 [AUTH] Updating FCM token for user ${user.id} (${user.phoneNumber})`);
          user.fcmToken = fcmCandidate;
          await userRepository.save(user);
          console.log(`✅ [AUTH] FCM token updated successfully`);
        } catch (fcmErr: unknown) {
          const msg = fcmErr instanceof Error ? fcmErr.message : String(fcmErr);
          console.error(
            `❌ [AUTH] FCM token not saved for user ${user.id}: ${msg}. If ER_DATA_TOO_LONG, run: ALTER TABLE user MODIFY fcmToken VARCHAR(512) NULL;`
          );
        }
      } else {
        console.log(`⚠️ [AUTH] No FCM token provided for user ${user.id}`);
      }

      // Generate Access Token (short-lived: 15 minutes)
      const accessToken = jwt.sign(
        { userId: user.id, phoneNumber: user.phoneNumber, role: user.role },
        JWT_SECRET,
        { expiresIn: '15m' } // Access token expires in 15 minutes
      );

      // Generate Refresh Token (long-lived: 30 days)
      const refreshTokenValue = crypto.randomBytes(64).toString('hex');
      const refreshTokenExpiry = new Date();
      refreshTokenExpiry.setDate(refreshTokenExpiry.getDate() + 30); // 30 days

      // Save refresh token to database
      console.log(`💾 Saving refresh token for user ${user.id}...`);
      const refreshTokenRepository = AppDataSource.getRepository(RefreshToken);
      const refreshToken = refreshTokenRepository.create({
        token: refreshTokenValue,
        userId: user.id,
        expiresAt: refreshTokenExpiry,
        isActive: true,
      });
      await refreshTokenRepository.save(refreshToken);
      console.log(`✅ Refresh token saved successfully`);

      res.json({
        message: 'Login successful',
        accessToken,
        refreshToken: refreshTokenValue,
        user: {
          id: user.id,
          phoneNumber: user.phoneNumber,
          name: user.name,
          email: user.email,
          birthday: formatBirthday(user.birthday),
          role: user.role,
        },
      });
    } catch (error) {
      console.error('❌ Error in verify endpoint:', error);
      if (error instanceof Error) {
        console.error('Error message:', error.message);
        console.error('Error stack:', error.stack);
      }
      res.status(500).json({
        message: 'Internal server error',
        error:
          process.env.NODE_ENV === 'development' && error instanceof Error
            ? error.message
            : undefined,
      });
    }
  }

  static async updateProfile(req: AuthRequest, res: Response): Promise<void> {
    const { name, email, birthday, fcmToken } = req.body;
    const userId = req.user?.id;

    if (!userId) {
      res.status(401).json({ message: 'Authentication required' });
      return;
    }

    try {
      const userRepository = AppDataSource.getRepository(User);
      const user = await userRepository.findOneBy({ id: userId });

      if (!user) {
        res.status(404).json({ message: 'User not found' });
        return;
      }

      if (name !== undefined) user.name = name;
      if (email !== undefined) user.email = email;
      if (birthday !== undefined) {
        // Parse birthday string to Date if provided, or set to null to clear
        if (birthday === null || birthday === '') {
          user.birthday = null;
        } else {
          user.birthday = new Date(birthday);
        }
      }
      const profileFcm = normalizeFcmToken(fcmToken);
      if (profileFcm) {
        console.log(`📱 [AUTH] Updating FCM token via profile update for user ${userId}`);
        user.fcmToken = profileFcm;
        console.log(`✅ [AUTH] FCM token updated via profile update`);
      }

      await userRepository.save(user);

      res.json({
        message: 'Profile updated successfully',
        user: {
          id: user.id,
          phoneNumber: user.phoneNumber,
          name: user.name,
          email: user.email,
          birthday: formatBirthday(user.birthday),
          role: user.role,
        },
      });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error updating profile' });
    }
  }

  static async updateFcmToken(req: AuthRequest, res: Response): Promise<void> {
    const userId = req.user?.id;
    const normalized = normalizeFcmToken(req.body?.fcmToken);

    if (!userId) {
      res.status(401).json({ message: 'Authentication required' });
      return;
    }
    if (!normalized) {
      res.status(400).json({ message: 'Valid fcmToken is required' });
      return;
    }

    try {
      const userRepository = AppDataSource.getRepository(User);
      const user = await userRepository.findOneBy({ id: userId });
      if (!user) {
        res.status(404).json({ message: 'User not found' });
        return;
      }
      user.fcmToken = normalized;
      await userRepository.save(user);
      res.json({ message: 'FCM token updated' });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Error updating FCM token' });
    }
  }

  static async refresh(req: Request, res: Response): Promise<void> {
    const { refreshToken } = req.body;

    if (!refreshToken) {
      res.status(400).json({ message: 'Refresh token is required' });
      return;
    }

    try {
      const refreshTokenRepository = AppDataSource.getRepository(RefreshToken);
      const tokenRecord = await refreshTokenRepository.findOne({
        where: { token: refreshToken, isActive: true },
        relations: ['user'],
      });

      if (!tokenRecord) {
        res.status(401).json({ message: 'Invalid refresh token' });
        return;
      }

      // Check if token is expired
      if (new Date() > tokenRecord.expiresAt) {
        // Mark token as inactive
        tokenRecord.isActive = false;
        await refreshTokenRepository.save(tokenRecord);
        res.status(401).json({ message: 'Refresh token expired' });
        return;
      }

      // Check if user is active
      if (!tokenRecord.user.isActive) {
        res.status(401).json({ message: 'User account is inactive' });
        return;
      }

      // Generate new access token
      const accessToken = jwt.sign(
        {
          userId: tokenRecord.user.id,
          phoneNumber: tokenRecord.user.phoneNumber,
          role: tokenRecord.user.role,
        },
        JWT_SECRET,
        { expiresIn: '15m' } // Access token expires in 15 minutes
      );

      res.json({
        message: 'Token refreshed successfully',
        accessToken,
        user: {
          id: tokenRecord.user.id,
          phoneNumber: tokenRecord.user.phoneNumber,
          name: tokenRecord.user.name,
          email: tokenRecord.user.email,
          role: tokenRecord.user.role,
        },
      });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Internal server error' });
    }
  }

  static async logout(req: AuthRequest, res: Response): Promise<void> {
    const { refreshToken } = req.body;
    const userId = req.user?.id;

    try {
      if (refreshToken) {
        // Revoke refresh token
        const refreshTokenRepository = AppDataSource.getRepository(RefreshToken);
        const tokenRecord = await refreshTokenRepository.findOne({
          where: { token: refreshToken },
        });

        if (tokenRecord) {
          tokenRecord.isActive = false;
          await refreshTokenRepository.save(tokenRecord);
        }
      } else if (userId) {
        // Revoke all refresh tokens for this user
        const refreshTokenRepository = AppDataSource.getRepository(RefreshToken);
        await refreshTokenRepository.update({ userId, isActive: true }, { isActive: false });
      }

      res.json({ message: 'Logout successful' });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Internal server error' });
    }
  }
}
