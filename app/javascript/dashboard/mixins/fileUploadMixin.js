import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { DirectUpload } from 'activestorage';
import { setDirectUploadAuthHeaders } from 'dashboard/helper/directUploadsHelper';
import {
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE,
  getMaxUploadSizeByChannel,
  resolveMaximumFileUploadSize,
  effectiveMaxUploadSize,
  checkFileSizeLimit,
  compressAttachmentInPlace,
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
        return this.onDirectFileUpload(file);
      }
      return this.onIndirectFileUpload(file);
    },

    // Creates an ActiveStorage DirectUpload, authenticating the blob-create
    // request and (optionally) reporting real byte-transfer progress so the UI
    // can show a per-attachment ring.
    directUploadCreate(file, callback, onProgress) {
      const upload = new DirectUpload(
        file.file,
        `/api/v1/accounts/${this.accountId}/conversations/${this.currentChat.id}/direct_uploads`,
        {
          directUploadWillCreateBlobWithXHR: xhr => {
            setDirectUploadAuthHeaders(xhr);
          },
          directUploadWillStoreFileWithXHR: xhr => {
            if (!onProgress) return;
            xhr.upload.addEventListener('progress', event => {
              if (!event.lengthComputable) return;
              onProgress(
                Math.min(100, Math.round((event.loaded * 100) / event.total))
              );
            });
          },
        }
      );
      upload.create(callback);
    },

    async onDirectFileUpload(file) {
      if (!file) return;

      // Downscale oversized images first so both the size check and the actual
      // transfer work on the smaller file.
      file = await compressAttachmentInPlace(file);

      const mime = file.file?.type || file.type;
      const maxSizeMB = this.maxSizeFor(mime);

      if (!checkFileSizeLimit(file, maxSizeMB)) {
        this.alertOverLimit(maxSizeMB);
        return;
      }

      // Recorded audio keeps the legacy flow (attach only once the blob is
      // ready) because its auto-send depends on the attachment being
      // immediately sendable.
      if (file.isRecordedAudio) {
        this.directUploadCreate(file, (error, blob) => {
          if (error) useAlert(error);
          else this.attachFile({ file, blob });
        });
        return;
      }

      // Otherwise start the transfer right away and show the attachment
      // immediately with an 'uploading' status + live progress. The agent sees
      // feedback while it uploads, and by the time Send is clicked the blob is
      // already stored — the message POST carries only the signed id (instant).
      const uploadId = `up-${Date.now()}-${Math.round(Math.random() * 1e6)}`;
      this.attachFile({
        file,
        uploadId,
        uploadStatus: 'uploading',
        uploadProgress: null,
      });
      this.directUploadCreate(
        file,
        (error, blob) => {
          if (error) this.onAttachmentUploadFailed?.(uploadId);
          else this.onAttachmentUploaded?.(uploadId, blob);
        },
        percent => this.onAttachmentUploadProgress?.(uploadId, percent)
      );
    },

    async onIndirectFileUpload(file) {
      if (!file) return;

      // Downscale oversized images before they ride the multipart message POST,
      // cutting both the bytes on the wire and the time a Puma worker stays busy
      // receiving them.
      file = await compressAttachmentInPlace(file);

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
