import { shallowMount } from '@vue/test-utils';
import { useAlert } from 'dashboard/composables';
import fileUploadMixin from 'dashboard/mixins/fileUploadMixin';
import { checkFileSizeLimit } from 'shared/helpers/FileHelper';
import { reactive } from 'vue';

vi.mock('shared/helpers/FileHelper', () => ({
  checkFileSizeLimit: vi.fn(),
  // Off-thread image compression runs before the size check; in the mock it is
  // a no-op that resolves to the same file.
  compressAttachmentInPlace: vi.fn(file => Promise.resolve(file)),
  resolveMaximumFileUploadSize: vi.fn(value => Number(value) || 40),
  DEFAULT_MAXIMUM_FILE_UPLOAD_SIZE: 40,
  HARD_MAXIMUM_FILE_UPLOAD_SIZE: 100,
  effectiveMaxUploadSize: vi.fn(limit => {
    const n = Number(limit);
    if (!Number.isFinite(n) || n <= 0) return 100;
    return Math.min(n, 100);
  }),
  formatBytes: vi.fn(bytes => `${bytes} Bytes`),
}));

vi.mock('activestorage', () => ({
  DirectUpload: vi.fn().mockImplementation(() => ({
    create: vi.fn(),
  })),
}));

vi.mock('dashboard/composables', () => ({
  useAlert: vi.fn(),
}));

describe('FileUploadMixin', () => {
  let wrapper;
  let mockGlobalConfig;
  let mockCurrentChat;
  let mockCurrentUser;

  beforeEach(() => {
    mockGlobalConfig = reactive({
      directUploadsEnabled: true,
      maximumFileUploadSize: 40,
    });

    mockCurrentChat = reactive({
      id: 456,
    });

    mockCurrentUser = reactive({
      access_token: 'token',
    });

    wrapper = shallowMount({
      mixins: [fileUploadMixin],
      data() {
        return {
          globalConfig: mockGlobalConfig,
          currentChat: mockCurrentChat,
          currentUser: mockCurrentUser,
          isATwilioSMSChannel: false,
        };
      },
      methods: {
        attachFile: vi.fn(),
        showAlert: vi.fn(),
        $t: msg => msg,
      },
      template: '<div />',
    });
  });

  it('should call onDirectFileUpload when direct uploads are enabled', () => {
    wrapper.vm.onDirectFileUpload = vi.fn();
    wrapper.vm.onFileUpload({});
    expect(wrapper.vm.onDirectFileUpload).toHaveBeenCalledWith({});
  });

  it('should call onIndirectFileUpload when direct uploads are disabled', () => {
    wrapper.vm.globalConfig.directUploadsEnabled = false;
    wrapper.vm.onIndirectFileUpload = vi.fn();
    wrapper.vm.onFileUpload({});
    expect(wrapper.vm.onIndirectFileUpload).toHaveBeenCalledWith({});
  });

  describe('maxSizeFor', () => {
    it('caps the effective limit at 100MB even when installation limit is higher', () => {
      wrapper.vm.globalConfig.maximumFileUploadSize = 500;
      expect(wrapper.vm.maxSizeFor('image/png')).toBe(100);
    });
  });

  describe('onDirectFileUpload', () => {
    it('returns early if no file is provided', async () => {
      const returnValue = await wrapper.vm.onDirectFileUpload(null);
      expect(returnValue).toBeUndefined();
    });

    it('shows an alert if the file size exceeds the maximum limit', async () => {
      const fakeFile = { size: 999999999 };
      checkFileSizeLimit.mockReturnValue(false); // Mock exceeding file size
      await wrapper.vm.onDirectFileUpload(fakeFile);
      expect(useAlert).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({ position: 'center' })
      );
    });
  });

  describe('onIndirectFileUpload', () => {
    it('returns early if no file is provided', async () => {
      const returnValue = await wrapper.vm.onIndirectFileUpload(null);
      expect(returnValue).toBeUndefined();
    });

    it('shows an alert if the file size exceeds the maximum limit', async () => {
      const fakeFile = { size: 999999999 };
      checkFileSizeLimit.mockReturnValue(false); // Mock exceeding file size
      await wrapper.vm.onIndirectFileUpload(fakeFile);
      expect(useAlert).toHaveBeenCalledWith(
        expect.any(String),
        expect.objectContaining({ position: 'center' })
      );
    });
  });
});
