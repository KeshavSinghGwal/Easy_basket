import 'reflect-metadata';

import { AppDataSource } from './config/database';
import { RequestTimingMiddleware } from './middleware/requestTiming.middleware';
import { S3Service } from './services/s3.service';
import { OrderAutoCancelService } from './services/order-auto-cancel.service';
import { OrderAcceptanceAlertService } from './services/order-acceptance-alert.service';
import { PaymentsReconcilerService } from './services/payments-reconciler.service';
import { ServiceabilityService } from './services/serviceability.service';
import { startPaymentWorker } from './services/queue/payment-reconcile.worker';
import { paymentQueue } from './services/queue/payment-queue';
import { startRefundWorker } from './services/queue/refund-retry.worker';
import { refundQueue } from './services/queue/refund-queue';
import { RedisService } from './services/redis.service';
import addressRoutes from './routes/address.routes';
import adminRoutes from './routes/admin.routes';
import authRoutes from './routes/auth.routes';
import categoryRoutes from './routes/category.routes';
import cors from 'cors';
import deliveryRoutes from './routes/delivery.routes';
import dotenv from 'dotenv';
import express, { NextFunction, Request, Response } from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import orderRoutes from './routes/order.routes';
import paymentRoutes from './routes/payment.routes';
import { PaymentController } from './controllers/payment.controller';
import productRoutes from './routes/product.routes';
import serviceAreaRoutes from './routes/serviceArea.routes';
import storeStatusRoutes from './routes/storeStatus.routes';
import supportRoutes from './routes/support.routes';
import variantRoutes from './routes/variant.routes';
import campaignRoutes from './routes/campaign.routes';
import { languageMiddleware } from "./middleware/language.middleware";
import { TranslationService } from "./services/translation.service";
import { responseMiddleware } from "./middleware/response.middleware";

// Load environment variables FIRST before importing any modules that use them
dotenv.config();

// Validate JWT_SECRET at boot — exits the process if missing or too short.
// Must run after dotenv.config() and before any route handlers can serve traffic.
require('./config/jwt');

// Same for the three Razorpay secrets. RAZORPAY_WEBHOOK_SECRET especially: it is
// read lazily and a missing value makes verifyWebhookSignature return false, so
// every webhook 401s silently and the authoritative payment-confirmation path
// quietly stops existing. Fail loudly at boot instead.
require('./config/razorpay-env');

// Re-initialize S3Service after dotenv.config() to ensure env vars are loaded
// (S3Service.initialize() is called on module load, but env vars might not be ready)
S3Service.initialize();

const app = express();
const PORT = process.env.PORT || 3000;

// Behind an ALB, so req.ip must come from X-Forwarded-For — otherwise every
// request looks like it originates from the load balancer and both the rate
// limiter above and AuthController's per-IP OTP limit would key every user in
// the country to one bucket. `1` = trust exactly one proxy hop (the ALB), which
// is right; `true` would trust a client-supplied header outright and let anyone
// spoof their way past the limits.
app.set('trust proxy', 1);

// Security headers. Cheap, and there were none at all before.
// crossOriginResourcePolicy is relaxed because product images are served from a
// different origin (S3/CDN) and embedded by the web front-ends.
app.use(
  helmet({
    crossOriginResourcePolicy: { policy: 'cross-origin' },
  })
);

// CORS.
//
// This was `origin: true` — reflect ANY origin — together with
// credentials: true. Low risk in practice because authentication is a bearer
// header rather than a cookie, so a hostile page could not ride an ambient
// session. But it costs nothing to close, so it is closed.
//
// The mobile app sends no Origin header at all, and neither does curl or a
// server-to-server call (the Razorpay webhook included), so requests without an
// origin must keep working — that is the majority of real traffic.
//
// CORS_ALLOWED_ORIGINS is a comma-separated list. Absent, only origin-less
// requests are accepted, which is exactly what the mobile app needs.
const allowedOrigins = (process.env.CORS_ALLOWED_ORIGINS ?? '')
  .split(',')
  .map((o) => o.trim())
  .filter(Boolean);

app.use(
  cors({
    origin(origin, callback) {
      if (!origin) return callback(null, true);
      if (allowedOrigins.includes(origin)) return callback(null, true);
      return callback(new Error('Not allowed by CORS'));
    },
    credentials: true,
    methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization', 'Idempotency-Key', 'Accept-Language'],
  })
);

// Razorpay webhook MUST use raw body for HMAC verification — mount BEFORE express.json()
// so the body stays an untouched Buffer. Any other route still gets JSON parsing below.
app.post(
  '/api/payment/webhook/razorpay',
  express.raw({ type: 'application/json', limit: '1mb' }),
  PaymentController.razorpayWebhook
);

app.use(express.json());

// Baseline rate limit.
//
// Only OTP send and the three payment endpoints were limited; product search,
// order creation, address writes and token refresh were all unbounded. This is
// the floor for everything, deliberately loose enough that no real user meets
// it — the per-endpoint limits in AuthController and PaymentController stay as
// the tight ones where abuse actually costs money.
//
// Keyed on IP. Behind an ALB that requires trust proxy (set below) so the key is
// the client address from X-Forwarded-For and not the load balancer's.
app.use(
  rateLimit({
    windowMs: 60 * 1000,
    limit: Number(process.env.RATE_LIMIT_PER_MINUTE) || 300,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    // The webhook is authenticated by HMAC and must never be throttled — losing
    // one costs a confirmed payment.
    skip: (req) => req.path === '/api/payment/webhook/razorpay',
    message: { message: 'Too many requests. Please slow down and try again shortly.' },
  })
);

app.use(languageMiddleware);
app.use(responseMiddleware);
app.use(RequestTimingMiddleware.handle);

// Routes
app.use('/api/auth', authRoutes);
app.use('/api/products', productRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/categories', categoryRoutes);
app.use('/api/addresses', addressRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/delivery', deliveryRoutes);
app.use('/api/payment', paymentRoutes);
app.use('/api/service-area', serviceAreaRoutes);
app.use('/api/store', storeStatusRoutes);
// Was never mounted, so every Help & Support call from the app 404'd with
// Express's default HTML body. The router and both screens already existed.
app.use('/api/support', supportRoutes);
// NOTE: upload routes now live inside adminRoutes (same /api/admin/upload-image
// URL). They used to be a second router on this prefix, which meant every upload
// ran authenticate + authorize twice.
app.use('/api', variantRoutes);
app.use('/api/campaigns', campaignRoutes);

app.get('/', (req, res) => {
  res.send('Easy Basket Backend is running');
});

// Health check that actually checks health.
//
// This used to return 200 {status:'ok'} without touching anything, so an
// instance whose database was unreachable stayed in the ALB target group and
// kept taking its share of traffic while failing every real request. Now it
// verifies both dependencies and answers 503 when either is down, so the load
// balancer can route around a sick instance.
app.get('/api/health', async (_req, res) => {
  const checks: Record<string, 'ok' | 'fail'> = { database: 'fail', redis: 'fail' };

  try {
    await AppDataSource.query('SELECT 1');
    checks.database = 'ok';
  } catch {
    // leave as 'fail'
  }

  try {
    await RedisService.ping();
    checks.redis = 'ok';
  } catch {
    // leave as 'fail'
  }

  const healthy = checks.database === 'ok' && checks.redis === 'ok';
  res.status(healthy ? 200 : 503).json({
    status: healthy ? 'ok' : 'degraded',
    checks,
    timestamp: new Date().toISOString(),
  });
});

// Terminal error handler. MUST be last — after every route.
//
// There was none, so anything thrown outside a controller's own try/catch fell
// to Express's default handler, which in a non-production NODE_ENV returns the
// stack trace to the caller. Multer is the most likely source: a file over the
// 5MB limit, or a rejected type, raises here rather than inside a handler.
//
// Four arguments is what marks this as an error handler to Express; `_next` is
// unused but required for that signature.
app.use((err: Error & { code?: string }, req: Request, res: Response, _next: NextFunction) => {
  console.error(`[error] unhandled on ${req.method} ${req.path}:`, err);

  if (res.headersSent) return;

  if (err?.code === 'LIMIT_FILE_SIZE') {
    res.status(413).json({ message: 'That file is too large. The limit is 5MB.' });
    return;
  }
  if (err?.message === 'Not allowed by CORS') {
    res.status(403).json({ message: 'Origin not allowed.' });
    return;
  }

  // Deliberately generic: never leak a stack or an internal message to a client.
  res.status(500).json({ message: 'Something went wrong on our side. Please try again.' });
});

AppDataSource.initialize()
  .then(async () => {
    console.log('✅ Database connected successfully');
    await TranslationService.loadCache();
    console.log("✅ Translation cache loaded");
    // Pick up translations saved by other API instances behind the LB.
    TranslationService.startCacheSync();
    console.log(`📊 Database: ${process.env.DB_NAME || 'easy_basket'}`);
    console.log(`🌐 Host: ${process.env.DB_HOST || 'localhost'}`);

    try {
      await RedisService.pingRequired();
      console.log('✅ Redis connected (required)');
    } catch (redisErr) {
      console.error('❌ Redis is required but unavailable:', (redisErr as Error).message);
      console.error(
        '💡 Set REDIS_URL or REDIS_HOST, REDIS_PORT, REDIS_PASSWORD (optional: REDIS_USERNAME, REDIS_TLS).'
      );
      await AppDataSource.destroy().catch(() => undefined);
      process.exit(1);
    }

    // Check S3 initialization status with detailed debugging
    console.log('');
    console.log('🔍 Checking AWS S3 configuration...');
    console.log(`   AWS_ACCESS_KEY_ID: ${process.env.AWS_ACCESS_KEY_ID ? '✅ Set' : '❌ Missing'}`);
    console.log(
      `   AWS_SECRET_ACCESS_KEY: ${process.env.AWS_SECRET_ACCESS_KEY ? '✅ Set' : '❌ Missing'}`
    );
    console.log(
      `   AWS_S3_BUCKET_NAME: ${process.env.AWS_S3_BUCKET_NAME ? `✅ Set (${process.env.AWS_S3_BUCKET_NAME})` : '❌ Missing'}`
    );
    console.log(
      `   AWS_REGION: ${process.env.AWS_REGION || 'ap-south-1 (Mumbai, India - default)'}`
    );

    if (
      process.env.AWS_ACCESS_KEY_ID &&
      process.env.AWS_SECRET_ACCESS_KEY &&
      process.env.AWS_S3_BUCKET_NAME
    ) {
      console.log('✅ AWS S3 credentials configured');
      console.log(`📦 S3 Bucket: ${process.env.AWS_S3_BUCKET_NAME}`);
      console.log(`🌍 S3 Region: ${process.env.AWS_REGION || 'ap-south-1 (Mumbai, India)'}`);
    } else {
      console.log('');
      console.log('⚠️  AWS S3 not configured - Image upload will be disabled');
      console.log('');
      console.log('💡 Troubleshooting:');
      console.log('   1. Check if .env file exists in backend directory');
      console.log('   2. Verify .env file contains all required variables');
      console.log('   3. If using PM2, check ecosystem.config.js for env vars');
      console.log('   4. Restart PM2 after updating .env: pm2 restart all');
      console.log('');
      console.log('📝 Required variables:');
      console.log('   AWS_ACCESS_KEY_ID=your_access_key_id');
      console.log('   AWS_SECRET_ACCESS_KEY=your_secret_access_key');
      console.log('   AWS_S3_BUCKET_NAME=your-bucket-name');
      console.log('   AWS_REGION=ap-south-1 (Mumbai, India - optional, default)');
    }
    console.log('');

    // Serviceability config visibility — GPS radius check falls back to pincode
    // when this isn't set, so make the mode obvious at boot.
    if (ServiceabilityService.isConfigured()) {
      console.log(
        `✅ Serviceability: GPS radius mode — store (${process.env.STORE_LAT}, ${process.env.STORE_LNG}), radius ${ServiceabilityService.radiusKm} km`
      );
    } else {
      console.warn(
        '⚠️  Serviceability: GPS radius NOT configured (STORE_LAT/STORE_LNG/DELIVERY_RADIUS_KM) — falling back to pincode checks.'
      );
    }

    // Auto-cancel: pending (unpaid) orders past ORDER_AUTO_CANCEL_MINUTES (default 30)
    OrderAutoCancelService.start();

    // Acceptance alert: PAID orders the store has not accepted yet. ALERTS ONLY —
    // unlike the sweep above it never changes an order's state. No automatic action
    // is taken on a non-terminal order; a human accepts or refuses.
    OrderAcceptanceAlertService.start();

    // Payments reconciler: coarse 30-min safety net for stale payments / pending refunds.
    PaymentsReconcilerService.start();

    // Payment reconcile worker: fast, restart-proof fallback when a webhook is missed.
    const paymentWorker = startPaymentWorker();

    // Refund retry worker: performs the single automatic refund retry before a
    // failed refund is parked for admin intervention.
    const refundWorker = startRefundWorker();

    // Graceful shutdown — let in-flight jobs finish and close Redis connections cleanly.
    const shutdown = async (signal: string) => {
      console.log(`[shutdown] ${signal} received — closing payment queue/worker`);
      try {
        await paymentWorker.close();
        await refundWorker.close();
        await paymentQueue.close();
        await refundQueue.close();
      } catch (err) {
        console.error('[shutdown] error closing queue/worker', err);
      } finally {
        process.exit(0);
      }
    };
    process.on('SIGTERM', () => void shutdown('SIGTERM'));
    process.on('SIGINT', () => void shutdown('SIGINT'));

    app.listen(PORT, () => {
      console.log(`🚀 Server is running on port ${PORT}`);
    });
  })
  .catch((error: any) => {
    console.error('❌ Database connection error:', error.message || error);
    // NOTE: this handler now EXITS rather than starting the listener — see the
    // process.exit(1) at the end. The hints below still print first so the cause
    // is visible in the PM2 logs.

    // Helpful hints for ETIMEDOUT (can't reach DB host)
    if (error.code === 'ETIMEDOUT' || error.message?.includes('ETIMEDOUT')) {
      console.error('');
      console.error('💡 ETIMEDOUT = Cannot reach the database host. Check:');
      console.error('   1. DB_HOST in .env – use localhost if MySQL is on this machine');
      console.error('   2. MySQL is running: mysql is running, or brew services start mysql');
      console.error('   3. If remote DB: firewall, security group, or VPN blocking port 3306');
      console.error('   4. DB_PORT (default 3306) matches your MySQL port');
      console.error(
        `   Current: host=${process.env.DB_HOST || 'localhost'} port=${process.env.DB_PORT || '3306'}`
      );
      console.error('');
    }

    // Check for specific index drop error
    if (error.code === 'ER_DROP_INDEX_FK' || error.errno === 1553) {
      console.error('');
      console.error('⚠️  TypeORM tried to drop an index required by a foreign key constraint.');
      console.error('💡 This is usually safe to ignore if the database schema is already correct.');
      console.error('💡 Solutions:');
      console.error('   1. The explicit @Index decorator in Category entity should prevent this');
      console.error('   2. If it persists, temporarily set synchronize: false in database.ts');
      console.error('   3. Or manually verify the database schema is correct');
      console.error('');
    }

    // Do NOT start the listener.
    //
    // This used to call app.listen() anyway "for health checks" — but the health
    // check did not test the database, so the instance passed the ALB probe,
    // stayed in the target group, and failed every real request it was handed.
    // A process that cannot serve traffic should exit and let PM2 restart it (or
    // let the ALB replace the instance), which is loud and self-correcting
    // rather than quiet and broken.
    console.error('❌ Refusing to start without a database. Exiting so PM2 can restart.');
    process.exit(1);
  });
