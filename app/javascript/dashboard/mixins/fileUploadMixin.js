import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { getMaxUploadSizeByChannel } from '@chatwoot/utils';
import { DirectUpload } from 'activestorage';
import {
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
  resolveMaximumFileUploadSize,
  effectiveMaxUploadSize,
  checkFileSizeLimit,
  formatBytes,
} from 'shared/helpers/FileHelper';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

export default {
  computed: {
    ...mapGetters({
      accountId: 'getCurrentAccountId',
    }),
    installationLimit() {
      return resolveMaximumFileUploadSize(
        this.globalConfig.maximumFileUploadSize
      );
    },
  },

  methods: {
    maxSizeFor(mime) {
      // The hard 100MB ceiling is always applied on top of the
      // channel/installation limit (see effectiveMaxUploadSize).
      let rawLimit = this.installationLimit;

      const channelType = this.inbox?.channel_type;

      if (
        !this.isOnPrivateNote &&
        channelType &&
        channelType !== INBOX_TYPES.WEB
      ) {
        const channelLimit = getMaxUploadSizeByChannel({
          channelType,
          medium: this.inbox?.medium, // e.g. 'sms' | 'whatsapp'
          mime, // e.g. 'image/png'
        });

        if (channelLimit !== DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE) {
          rawLimit = Math.min(channelLimit, this.installationLimit);
        }
      }

      return effectiveMaxUploadSize(rawLimit);
    },
    alertOverLimit(maxSizeMB, file) {
      const fileSize = file?.file?.size || file?.size;
      useAlert(
        this.$t('CONVERSATION.FILE_SIZE_LIMIT_HARD', {
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
    },
    onFileUpload(file) {
      if (this.globalConfig.directUploadsEnabled) {
        this.onDirectFileUpload(file);
      } else {
        this.onIndirectFileUpload(file);
      }
    },

    onDirectFileUpload(file) {
      if (!file) return;

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return;
      }

      const upload = new DirectUpload(
        file.file,
        `/api/v1/accounts/${this.accountId}/conversations/${this.currentChat.id}/direct_uploads`,
        {
          directUploadWillCreateBlobWithXHR: xhr => {
            xhr.setRequestHeader(
              'api_access_token',
              this.currentUser.access_token
            );
          },
        }
      );

      upload.create((error, blob) => {
        if (error) {
          useAlert(error);
        } else {
          this.attachFile({ file, blob });
        }
      });
    },

    onIndirectFileUpload(file) {
      if (!file) return;

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return;
      }

      this.attachFile({ file });
    },
  },
};
