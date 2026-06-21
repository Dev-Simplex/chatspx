import { useFileUpload } from '../useFileUpload';
import { useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';
import { DirectUpload } from 'activestorage';
import {
  checkFileSizeLimit,
  getMaxUploadSizeByChannel,
} from 'shared/helpers/FileHelper';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(message => message),
}));
vi.mock('vue-i18n');
vi.mock('activestorage');
vi.mock('shared/helpers/FileHelper', () => ({
  checkFileSizeLimit: vi.fn(),
  getMaxUploadSizeByChannel: vi.fn(),
  resolveMaximumFileUploadSize: vi.fn(value => Number(value) || 40),
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE: 40,
  HARD_MAXIMUM_FILE_UPLOAD_SIZE: 100,
  effectiveMaxUploadSize: vi.fn(limit => {
    const n = Number(limit);
    if (!Number.isFinite(n) || n <= 0) return 100;
    return Math.min(n, 100);
  }),
  // Pass-through: image compression is exercised in FileHelper's own specs.
  compressAttachmentInPlace: vi.fn(file => Promise.resolve(file)),
  formatBytes: vi.fn(bytes => `${bytes} Bytes`),
}));

describe('useFileUpload', () => {
  const mockAttachFile = vi.fn();
  const mockTranslate = vi.fn();

  const mockFile = {
    file: new File(['test'], 'test.jpg', { type: 'image/jpeg' }),
  };

  const inbox = {
    channel_type: 'Channel::WhatsApp',
    medium: 'whatsapp',
  };

  beforeEach(() => {
    vi.clearAllMocks();

    useMapGetter.mockImplementation(getter => {
      const getterMap = {
        getCurrentAccountId: { value: '123' },
        getCurrentUser: { value: { access_token: 'test-token' } },
        getSelectedChat: { value: { id: '456' } },
        'globalConfig/get': {
          value: { directUploadsEnabled: true, maximumFileUploadSize: 40 },
        },
      };
      return getterMap[getter];
    });

    useI18n.mockReturnValue({ t: mockTranslate });
    checkFileSizeLimit.mockReturnValue(true);
    getMaxUploadSizeByChannel.mockReturnValue(25); // default max size MB for tests
  });

  it('handles direct file upload when direct uploads enabled', async () => {
    const { onFileUpload } = useFileUpload({
      inbox,
      attachFile: mockAttachFile,
    });

    const mockBlob = { signed_id: 'test-blob' };
    DirectUpload.mockImplementation(() => ({
      create: callback => callback(null, mockBlob),
    }));

    await onFileUpload(mockFile);

    // size rules called with inbox + mime
    expect(getMaxUploadSizeByChannel).toHaveBeenCalledWith({
      channelType: inbox.channel_type,
      medium: inbox.medium,
      mime: 'image/jpeg',
    });

    // size check called with max from helper
    expect(checkFileSizeLimit).toHaveBeenCalledWith(mockFile, 25);

    expect(DirectUpload).toHaveBeenCalledWith(
      mockFile.file,
      '/api/v1/accounts/123/conversations/456/direct_uploads',
      expect.any(Object)
    );
    expect(mockAttachFile).toHaveBeenCalledWith({
      file: mockFile,
      blob: mockBlob,
    });
  });

  it('handles indirect file upload when direct upload disabled', async () => {
    useMapGetter.mockImplementation(getter => {
      const getterMap = {
        getCurrentAccountId: { value: '123' },
        getCurrentUser: { value: { access_token: 'test-token' } },
        getSelectedChat: { value: { id: '456' } },
        'globalConfig/get': {
          value: { directUploadsEnabled: false, maximumFileUploadSize: 40 },
        },
      };
      return getterMap[getter];
    });

    const { onFileUpload } = useFileUpload({
      inbox,
      attachFile: mockAttachFile,
    });

    await onFileUpload(mockFile);

    expect(DirectUpload).not.toHaveBeenCalled();
    expect(getMaxUploadSizeByChannel).toHaveBeenCalled();
    expect(checkFileSizeLimit).toHaveBeenCalledWith(mockFile, 25);
    expect(mockAttachFile).toHaveBeenCalledWith({ file: mockFile });
  });

  it('shows alert when file size exceeds limit', async () => {
    checkFileSizeLimit.mockReturnValue(false);
    mockTranslate.mockReturnValue('File size exceeds limit');

    const { onFileUpload } = useFileUpload({
      inbox,
      attachFile: mockAttachFile,
    });

    await onFileUpload(mockFile);

    expect(useAlert).toHaveBeenCalledWith(
      'File size exceeds limit',
      expect.objectContaining({ position: 'center' })
    );
    expect(mockAttachFile).not.toHaveBeenCalled();
  });

  it('uses per-mime limits from helper', async () => {
    getMaxUploadSizeByChannel.mockImplementation(({ mime }) =>
      mime.startsWith('image/') ? 10 : 50
    );
    const { onFileUpload } = useFileUpload({
      inbox,
      attachFile: mockAttachFile,
    });

    DirectUpload.mockImplementation(() => ({
      create: cb => cb(null, { signed_id: 'blob' }),
    }));

    await onFileUpload(mockFile);

    expect(getMaxUploadSizeByChannel).toHaveBeenCalledWith({
      channelType: inbox.channel_type,
      medium: inbox.medium,
      mime: 'image/jpeg',
    });
    expect(checkFileSizeLimit).toHaveBeenCalledWith(mockFile, 10);
  });

  it('handles direct upload errors', async () => {
    const mockError = 'Upload failed';
    DirectUpload.mockImplementation(() => ({
      create: callback => callback(mockError, null),
    }));

    const { onFileUpload } = useFileUpload({
      inbox,
      attachFile: mockAttachFile,
    });

    await onFileUpload(mockFile);

    expect(useAlert).toHaveBeenCalledWith(mockError);
    expect(mockAttachFile).not.toHaveBeenCalled();
  });

  it('caps the effective limit at 100MB even when installation limit is higher', async () => {
    useMapGetter.mockImplementation(getter => {
      const getterMap = {
        getCurrentAccountId: { value: '123' },
        getCurrentUser: { value: { access_token: 'test-token' } },
        getSelectedChat: { value: { id: '456' } },
        'globalConfig/get': {
          value: { directUploadsEnabled: true, maximumFileUploadSize: 500 },
        },
      };
      return getterMap[getter];
    });
    // Channel reports a large limit; the hard ceiling must still win.
    getMaxUploadSizeByChannel.mockReturnValue(300);

    DirectUpload.mockImplementation(() => ({
      create: cb => cb(null, { signed_id: 'blob' }),
    }));

    const { onFileUpload } = useFileUpload({
      inbox,
      attachFile: mockAttachFile,
    });

    await onFileUpload(mockFile);

    // min(channel 300, installation 500) = 300, then hard-capped to 100.
    expect(checkFileSizeLimit).toHaveBeenCalledWith(mockFile, 100);
  });

  it('does nothing when file is null', async () => {
    const { onFileUpload } = useFileUpload({
      inbox,
      attachFile: mockAttachFile,
    });

    await onFileUpload(null);

    expect(checkFileSizeLimit).not.toHaveBeenCalled();
    expect(getMaxUploadSizeByChannel).not.toHaveBeenCalled();
    expect(mockAttachFile).not.toHaveBeenCalled();
    expect(useAlert).not.toHaveBeenCalled();
  });
});
