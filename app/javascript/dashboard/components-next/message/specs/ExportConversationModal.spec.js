import { mount, flushPromises } from '@vue/test-utils';
import ExportConversationModal from '../ExportConversationModal.vue';
import ConversationPdfExportApi from 'dashboard/api/conversationPdfExport';

vi.mock('dashboard/api/conversationPdfExport', () => ({
  default: { create: vi.fn(), show: vi.fn() },
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const renderCompletedExport = async sha256 => {
  ConversationPdfExportApi.create.mockResolvedValue({
    data: { id: 7, status: 'pending' },
  });
  ConversationPdfExportApi.show.mockResolvedValue({
    data: { status: 'completed', download_url: '/export.pdf', sha256 },
  });
  const wrapper = mount(ExportConversationModal, {
    props: { show: true, conversations: [{ id: 42, display_id: 99 }] },
    attachTo: document.body,
    global: { stubs: { Icon: true } },
  });
  const exportButton = [...document.body.querySelectorAll('button')].find(
    button => button.textContent.trim() === 'EXPORT_CONVERSATION.EXPORT_PDF'
  );
  exportButton.click();
  await flushPromises();
  await vi.runOnlyPendingTimersAsync();
  await flushPromises();
  return wrapper;
};

describe('ExportConversationModal', () => {
  beforeEach(() => vi.useFakeTimers());
  afterEach(() => {
    document.body.innerHTML = '';
    vi.clearAllMocks();
    vi.useRealTimers();
  });

  it('shows the SHA-256 returned by a completed export', async () => {
    const hash = 'a'.repeat(64);
    const wrapper = await renderCompletedExport(hash);
    expect(document.body.textContent).toContain(hash);
    expect(document.body.textContent).toContain('EXPORT_CONVERSATION.SHA256');
    wrapper.unmount();
  });

  it('completes without a SHA-256', async () => {
    const wrapper = await renderCompletedExport(null);
    expect(document.body.textContent).toContain(
      'EXPORT_CONVERSATION.READY_TITLE'
    );
    expect(document.body.textContent).not.toContain(
      'EXPORT_CONVERSATION.SHA256'
    );
    wrapper.unmount();
  });
});
