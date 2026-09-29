/**
 * GPS radius-based serviceability for a single store.
 *
 * An address is deliverable if it lies within DELIVERY_RADIUS_KM (+ optional
 * buffer) of the store's coordinates. Config comes from the environment, read
 * live on each call so a restart with new ENV takes effect without code changes:
 *
 *   STORE_LAT=31.1250
 *   STORE_LNG=76.4351
 *   DELIVERY_RADIUS_KM=7
 *   DELIVERY_RADIUS_BUFFER_KM=0.2   # optional; absorbs GPS jitter at the edge
 *
 * The backend is the source of truth: the app sends coordinates and receives a
 * yes/no, so the radius lives in exactly one place.
 */

export interface ServiceabilityResult {
  available: boolean;
  distanceKm: number;
  radiusKm: number;
}

export class ServiceabilityService {
  private static readConfig(): {
    lat: number;
    lng: number;
    radiusKm: number;
    bufferKm: number;
  } {
    const lat = Number(process.env.STORE_LAT);
    const lng = Number(process.env.STORE_LNG);
    const radiusKm = Number(process.env.DELIVERY_RADIUS_KM);
    const bufferRaw = Number(process.env.DELIVERY_RADIUS_BUFFER_KM ?? '0');
    return {
      lat,
      lng,
      radiusKm,
      bufferKm: Number.isFinite(bufferRaw) && bufferRaw >= 0 ? bufferRaw : 0,
    };
  }

  /** True only when store coords + a positive radius are validly set. */
  static isConfigured(): boolean {
    const { lat, lng, radiusKm } = this.readConfig();
    return (
      isValidLat(lat) &&
      isValidLng(lng) &&
      Number.isFinite(radiusKm) &&
      radiusKm > 0
    );
  }

  static get radiusKm(): number {
    return this.readConfig().radiusKm;
  }

  /** Great-circle distance (km) from the store to the given point. */
  static distanceFromStoreKm(lat: number, lng: number): number {
    const { lat: sLat, lng: sLng } = this.readConfig();
    return haversineKm(sLat, sLng, lat, lng);
  }

  /**
   * Decide serviceability for a coordinate. Caller should first check
   * isConfigured() / validate inputs; this trusts finite lat/lng.
   */
  static check(lat: number, lng: number): ServiceabilityResult {
    const { radiusKm, bufferKm } = this.readConfig();
    const d = this.distanceFromStoreKm(lat, lng);
    return {
      available: d <= radiusKm + bufferKm,
      distanceKm: Math.round(d * 100) / 100,
      radiusKm,
    };
  }
}

export function isValidLat(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v) && v >= -90 && v <= 90;
}

export function isValidLng(v: unknown): v is number {
  return typeof v === 'number' && Number.isFinite(v) && v >= -180 && v <= 180;
}

/** Haversine great-circle distance in kilometers. */
function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371; // earth radius km
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}
