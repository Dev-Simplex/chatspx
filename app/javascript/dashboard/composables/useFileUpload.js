import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { DirectUpload } from 'activestorage';
import { getMaxUploadSizeByChannel } from '@chatwoot/utils';
import {
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
  resolveMaximumFileUploadSize,
  effectiveMaxUploadSize,
  checkFileSizeLimit,
  formatBytes,
} from 'shared/helpers/FileHelper';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

/**
 * Composable for handling file uploads in conversations
 * @param {Object} options
 * @param {Object} options.inbox - Current inbox object (has channel_type, medium, etc.)
 * @param {Function} options.attachFile - Callback to handle file attachment
 * @param {boolean} options.isPrivateNote - Whether the upload is for a private note
 */
export const useFileUpload = ({ inbox, attachFile, isPrivateNote = false }) => {
  const { t } = useI18n();

  const accountId = useMapGetter('getCurrentAccountId');
  const currentUser = useMapGetter('getCurrentUser');
  const currentChat = useMapGetter('getSelectedChat');
  const globalConfig = useMapGetter('globalConfig/get');

  const installationLimit = resolveMaximumFileUploadSize(
    globalConfig.value?.maximumFileUploadSize
  );

  // helper: compute max upload size for a given file's mime. The hard 100MB
  // ceiling is always applied on top of the channel/installation limit.
  const maxSizeFor = mime => {
    let rawLimit = installationLimit;

    const channelType = inbox?.channel_type;

    if (!isPrivateNote && channelType && channelType !== INBOX_TYPES.WEB) {
      const channelLimit = getMaxUploadSizeByChannel({
        channelType,
        medium: inbox?.medium, // e.g. 'sms' | 'whatsapp' | etc.
        mime, // e.g. 'image/png'
      });

      if (channelLimit !== DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE) {
        rawLimit = Math.min(channelLimit, installationLimit);
      }
    }

    return effectiveMaxUploadSize(rawLimit);
  };

  const alertOverLimit = (maxSizeMB, file) => {
    const fileSize = file?.file?.size || file?.size;
    useAlert(
      t('CONVERSATION.FILE_SIZE_LIMIT_HARD', {
        MAXIMUM_SUPPORTED_FILE_UPLOAD_SIZE: maxSizeMB,
        fileSize: fileSize ? formatBytes(fileSize) : '',
      }),
      // Centered + error styling so the limit warning is hard to miss.
      {
        position: 'center',
        variant: 'error',
        icon: 'i-lucide-alert-triangle',
        duration: 4000,
      }
    );
  };

  const handleDirectFileUpload = file => {
    if (!file) return;

    const mime = file.file?.type || file.type;
    const maxSizeMB = maxSizeFor(mime);

    if (!checkFileSizeLimit(file, maxSizeMB)) {
      alertOverLimit(maxSizeMB, file);
      return;
    }

    const upload = new DirectUpload(
      file.file,
      `/api/v1/accounts/${accountId.value}/conversations/${currentChat.value.id}/direct_uploads`,
      {
        directUploadWillCreateBlobWithXHR: xhr => {
          xhr.setRequestHeader(
            'api_access_token',
            currentUser.value.access_token
          );
        },
      }
    );

    upload.create((error, blob) => {
      if (error) {
        useAlert(error);
      } else {
        attachFile({ file, blob });
      }
    });
  };

  const handleIndirectFileUpload = file => {
    if (!file) return;

    const mime = file.file?.type || file.type;
    const maxSizeMB = maxSizeFor(mime);

    if (!checkFileSizeLimit(file, maxSizeMB)) {
      alertOverLimit(maxSizeMB, file);
      return;
    }

    attachFile({ file });
  };

  const onFileUpload = file => {
    if (globalConfig.value.directUploadsEnabled) {
      handleDirectFileUpload(file);
    } else {
      handleIndirectFileUpload(file);
    }
  };

  return { onFileUpload };
};
