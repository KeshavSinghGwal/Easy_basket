import { NextFunction, Request, Response } from 'express';

/**
 * Logs per-request latency to help spot slow endpoints.
 */
export class RequestTimingMiddleware {
  public static handle(req: Request, res: Response, next: NextFunction): void {
    const start = process.hrtime.bigint();
    const { method, originalUrl } = req;

    res.on('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - start) / 1_000_000;
      const status = res.statusCode;
      const level = durationMs > 500 ? 'warn' : 'info';
      const message = `[${level.toUpperCase()}] ${method} ${originalUrl} ${status} - ${durationMs.toFixed(2)} ms`;

      console.log(message);
    });

    next();
  }
}
