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
