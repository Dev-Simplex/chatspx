import {
  getAllowedFileTypesByChannel,
  getMaxUploadSizeByChannel as getMaxUploadSizeByChannelBase,
} from '@chatwoot/utils';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import { ALLOWED_FILE_TYPES } from 'shared/constants/messages';

export const DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE = 40;

// Absolute ceiling for any attachment upload, in MB. Enforced regardless of the
// channel rules or the configured `maximumFileUploadSize` so that files larger
// than this never reach the backend (where the send would fail silently).
export const HARD_MAXIMUM_FILE_UPLOAD_SIZE = 100;

export const formatBytes = (bytes, decimals = 2) => {
  if (bytes === 0) return '0 Bytes';

  const k = 1024;
  const dm = decimals < 0 ? 0 : decimals;
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];

  const i = Math.floor(Math.log(bytes) / Math.log(k));

  return parseFloat((bytes / k ** i).toFixed(dm)) + ' ' + sizes[i];
};

export const fileSizeInMegaBytes = bytes => {
  return bytes / (1024 * 1024);
};

export const checkFileSizeLimit = (file, maximumUploadLimit) => {
  const fileSize = file?.file?.size || file?.size;
  const fileSizeInMB = fileSizeInMegaBytes(fileSize);
  return fileSizeInMB <= maximumUploadLimit;
};

export const resolveMaximumFileUploadSize = value => {
  const parsedValue = Number(value);

  if (!Number.isFinite(parsedValue) || parsedValue <= 0) {
    return DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE;
  }

  return parsedValue;
};

/**
 * Resolves the effective maximum upload size (in MB) for a given channel /
 * installation limit, enforcing the hard 100MB ceiling. Returns
 * min(channelLimit, HARD_MAXIMUM_FILE_UPLOAD_SIZE) so smaller channel limits
 * (e.g. SMS) are still respected while large/unset limits are capped at 100MB.
 * @param {number} channelLimit - the channel/installation limit in MB
 * @returns {number}
 */
export const effectiveMaxUploadSize = channelLimit => {
  const limit = Number(channelLimit);

  if (!Number.isFinite(limit) || limit <= 0) {
    return HARD_MAXIMUM_FILE_UPLOAD_SIZE;
  }

  return Math.min(limit, HARD_MAXIMUM_FILE_UPLOAD_SIZE);
};

// WAHA (Channel::Api) per-category upload limits, in MB.
//
// The upstream @chatwoot/utils has NO rule node for Channel::Api, so its
// getMaxUploadSizeByChannel falls back to the 40MB default. That means
// oversized media slips past the client check and the WhatsApp engine rejects
// it later — a silent late failure. We mirror the WhatsApp Cloud limits here,
// with video capped at 16MB (the value the WAHA engine reliably accepts;
// raise WAHA_VIDEO once the engine owner confirms a higher ceiling).
const WAHA_VIDEO = 16;
const WAHA_MAX_SIZE_BY_CATEGORY = {
  image: 16,
  video: WAHA_VIDEO,
  audio: 16,
  document: 100,
};

const DOCUMENT_MIME_HEADS = new Set(['application', 'text']);

const categoryFromMime = mime => {
  const head = mime?.split('/')?.[0] ?? '';
  if (DOCUMENT_MIME_HEADS.has(head)) return 'document';
  return head;
};

/**
 * Resolves the maximum upload size (in MB) for a channel/medium/mime.
 *
 * Thin wrapper over @chatwoot/utils' getMaxUploadSizeByChannel that adds the
 * WAHA (Channel::Api) rules the upstream package is missing. Every non-API
 * channel is delegated unchanged, so this stays a drop-in replacement for the
 * package import across all call sites.
 * @param {Object} params
 * @param {string} [params.channelType] - Channel type (from INBOX_TYPES).
 * @param {string} [params.medium] - Medium under the channel.
 * @param {string} [params.mime] - MIME type string (for category lookup).
 * @returns {number} Maximum file size in MB.
 */
export const getMaxUploadSizeByChannel = ({
  channelType,
  medium,
  mime,
} = {}) => {
  if (channelType === INBOX_TYPES.API) {
    const category = categoryFromMime(mime);
    return (
      WAHA_MAX_SIZE_BY_CATEGORY[category] ?? DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE
    );
  }

  return getMaxUploadSizeByChannelBase({ channelType, medium, mime });
};

/**
 * Validates if a file type is allowed for a specific channel
 * @param {File} file - The file to validate
 * @param {Object} options - Validation options
 * @param {string} options.channelType - The channel type
 * @param {string} options.medium - The channel medium
 * @param {string} options.conversationType - The conversation type (for Instagram DM detection)
 * @param {boolean} options.isInstagramChannel - Whether it's an Instagram channel
 * @param {boolean} options.isOnPrivateNote - Whether composing a private note (uses broader file type list)
 * @returns {boolean} - True if file type is allowed, false otherwise
 */
export const isFileTypeAllowedForChannel = (file, options = {}) => {
  if (!file || file.size === 0) return false;

  const {
    channelType: originalChannelType,
    medium,
    conversationType,
    isInstagramChannel,
    isOnPrivateNote,
  } = options;

  // Use broader file types for private notes (matches file picker behavior)
  const allowedFileTypes = isOnPrivateNote
    ? ALLOWED_FILE_TYPES
    : getAllowedFileTypesByChannel({
        channelType:
          isInstagramChannel || conversationType === 'instagram_direct_message'
            ? INBOX_TYPES.INSTAGRAM
            : originalChannelType,
        medium,
      });

  // Convert to array and validate
  const allowedTypesArray = allowedFileTypes.split(',').map(t => t.trim());
  const fileExtension = `.${file.name.split('.').pop()}`;

  return allowedTypesArray.some(allowedType => {
    // Check for exact file extension match
    if (allowedType === fileExtension) return true;

    // Check for wildcard MIME type (e.g., image/*)
    if (allowedType.endsWith('/*')) {
      const prefix = allowedType.slice(0, -2); // Remove '/*'
      return file.type.startsWith(prefix + '/');
    }

    // Check for exact MIME type match
    return allowedType === file.type;
  });
};

// Raster images we may downscale. GIF (animation breaks on a 2D canvas) and SVG
// (vector) are deliberately excluded.
const COMPRESSIBLE_IMAGE_MIME = /^image\/(jpe?g|png|webp)$/;

const isCompressibleImage = type => COMPRESSIBLE_IMAGE_MIME.test(type || '');

/**
 * Builds a lightweight preview URL for an attachment thumbnail.
 *
 * Only image/video attachments render a visual preview (as <img>/<video> src);
 * documents, audio, etc. show a static icon, so we skip the work entirely.
 * URL.createObjectURL is synchronous and only creates a reference to the file —
 * unlike FileReader.readAsDataURL it does NOT read the whole file into a base64
 * string on the main thread, so attaching a large file never blocks the UI nor
 * duplicates the file in memory. Callers must revoke the URL (see
 * revokeAttachmentThumbUrl) when the attachment is dropped.
 * @param {Object|File} file - upload wrapper ({ file: File }) or a raw File/Blob
 * @returns {string|undefined}
 */
export const buildAttachmentThumbUrl = file => {
  const blob = file?.file || file;
  if (!(blob instanceof Blob)) return undefined;
  const type = blob.type || '';
  if (type.startsWith('image/') || type.startsWith('video/')) {
    return URL.createObjectURL(blob);
  }
  return undefined;
};

/**
 * Releases an object URL previously created by buildAttachmentThumbUrl. No-op
 * for data URLs / remote URLs so it is safe to call on any thumb value.
 * @param {string} thumb
 */
export const revokeAttachmentThumbUrl = thumb => {
  if (typeof thumb === 'string' && thumb.startsWith('blob:')) {
    URL.revokeObjectURL(thumb);
  }
};

/**
 * Downscales an oversized raster image on the client before upload.
 *
 * Only images whose longest side exceeds `maxDimension` are touched, so normal
 * screenshots and already-small images are returned untouched (preserving
 * fidelity — important for a support tool). PNGs are re-encoded as PNG to keep
 * transparency and crisp text; JPEG/WebP are re-encoded as JPEG at `quality`.
 * If the result is not smaller than the original (or anything fails) the
 * ORIGINAL file is returned unchanged.
 * @param {File} file
 * @param {Object} [opts]
 * @param {number} [opts.maxDimension=1920]
 * @param {number} [opts.quality=0.82]
 * @returns {Promise<File>}
 */
// Shared resize+encode step. `source` is anything drawImage accepts (an
// ImageBitmap or an <img>). Uses OffscreenCanvas.convertToBlob when available so
// the JPEG/PNG ENCODE also runs off the main thread; otherwise a normal canvas.
const resizeAndEncodeImage = async (
  source,
  width,
  height,
  file,
  maxDimension,
  quality
) => {
  const scale = Math.min(1, maxDimension / Math.max(width, height));
  // Within bounds already: not worth re-encoding (could grow the file or
  // soften text). Leave it alone.
  if (scale >= 1) return file;

  const w = Math.round(width * scale);
  const h = Math.round(height * scale);

  let canvas;
  if (typeof OffscreenCanvas !== 'undefined') {
    canvas = new OffscreenCanvas(w, h);
  } else {
    canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
  }
  const ctx = canvas.getContext('2d');
  if (!ctx) return file;
  ctx.drawImage(source, 0, 0, w, h);

  const outType = file.type === 'image/png' ? 'image/png' : 'image/jpeg';
  const q = outType === 'image/jpeg' ? quality : undefined;
  const blob = canvas.convertToBlob
    ? await canvas.convertToBlob({ type: outType, quality: q })
    : await new Promise(res => {
        canvas.toBlob(res, outType, q);
      });

  if (!blob || blob.size >= file.size) return file;
  return new File([blob], file.name, { type: outType });
};

// Fallback path: decode with an <img> element (main-thread decode). Used only
// when createImageBitmap is unavailable.
const compressImageWithImageElement = (file, maxDimension, quality) =>
  new Promise(resolve => {
    const objectUrl = URL.createObjectURL(file);
    const img = new Image();
    img.onload = async () => {
      try {
        const out = await resizeAndEncodeImage(
          img,
          img.width,
          img.height,
          file,
          maxDimension,
          quality
        );
        resolve(out);
      } catch {
        resolve(file);
      } finally {
        URL.revokeObjectURL(objectUrl);
      }
    };
    img.onerror = () => {
      URL.revokeObjectURL(objectUrl);
      resolve(file);
    };
    img.src = objectUrl;
  });

export const compressImage = async (
  file,
  { maxDimension = 1920, quality = 0.82 } = {}
) => {
  if (!file || !isCompressibleImage(file.type)) return file;

  // Prefer createImageBitmap: it decodes the image OFF the main thread, unlike
  // `new Image()` which decodes synchronously and janks the UI for large
  // photos. Combined with OffscreenCanvas above, the whole resize+encode stays
  // off the main thread so attaching never freezes the composer.
  if (typeof createImageBitmap === 'function') {
    try {
      const bitmap = await createImageBitmap(file);
      const out = await resizeAndEncodeImage(
        bitmap,
        bitmap.width,
        bitmap.height,
        file,
        maxDimension,
        quality
      );
      bitmap.close?.();
      return out;
    } catch {
      // Fall through to the <img> path on any failure (e.g. EXIF/codec quirks).
    }
  }

  return compressImageWithImageElement(file, maxDimension, quality);
};

/**
 * Compresses the File inside an upload wrapper ({ file, name, type, size, ... })
 * when it is an oversized image, returning a new wrapper with the downscaled
 * file and refreshed metadata. Returns the input untouched when nothing was
 * compressed, so it is safe to await on every attachment regardless of type.
 * @param {Object} fileObj
 * @returns {Promise<Object>}
 */
export const compressAttachmentInPlace = async fileObj => {
  const original = fileObj?.file;
  if (!(original instanceof Blob)) return fileObj;

  const compressed = await compressImage(original);
  if (compressed === original) return fileObj;

  return {
    ...fileObj,
    file: compressed,
    name: compressed.name || fileObj.name,
    type: compressed.type || fileObj.type,
    size: compressed.size,
  };
};
