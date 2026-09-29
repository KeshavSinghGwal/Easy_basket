/**
 * Identify an image by its actual bytes rather than by what the uploader claims.
 *
 * The upload path trusted two client-controlled fields end to end:
 *
 *   - `file.mimetype` is the Content-Type of the multipart part, i.e. a string
 *     the client chose. It was checked against an allowlist in both
 *     upload.middleware and S3Service, then written verbatim onto the S3 object
 *     as its ContentType.
 *   - `file.originalname` supplied the stored file extension.
 *
 * So the bytes were never examined at any point. Deriving both from the content
 * instead means the object we store is described truthfully, whatever was sent.
 *
 * Deliberately dependency-free. `file-type` is ESM-only in current versions
 * (awkward from CommonJS TypeScript) and `sharp` is a native module that would
 * add real weight to builds on a t3.small. Three magic-number checks cover every
 * format this app accepts.
 */

export interface DetectedImage {
  /** Authoritative Content-Type, derived from the bytes. */
  mime: 'image/jpeg' | 'image/png' | 'image/webp';
  /** Canonical extension for that type — never taken from the filename. */
  ext: 'jpg' | 'png' | 'webp';
}

/**
 * Returns the detected type, or null when the buffer is not one of the three
 * formats we accept. Callers must treat null as a hard rejection.
 */
export function detectImageType(buffer: Buffer): DetectedImage | null {
  // Shortest signature we need to read is WebP's, at 12 bytes.
  if (!Buffer.isBuffer(buffer) || buffer.length < 12) return null;

  // JPEG — SOI marker followed by any segment marker: FF D8 FF
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return { mime: 'image/jpeg', ext: 'jpg' };
  }

  // PNG — the 8-byte signature: 89 'P' 'N' 'G' CR LF SUB LF
  if (
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47 &&
    buffer[4] === 0x0d &&
    buffer[5] === 0x0a &&
    buffer[6] === 0x1a &&
    buffer[7] === 0x0a
  ) {
    return { mime: 'image/png', ext: 'png' };
  }

  // WebP — RIFF container, with 'WEBP' at offset 8 (bytes 4..7 are the length).
  if (
    buffer.toString('ascii', 0, 4) === 'RIFF' &&
    buffer.toString('ascii', 8, 12) === 'WEBP'
  ) {
    return { mime: 'image/webp', ext: 'webp' };
  }

  return null;
}
