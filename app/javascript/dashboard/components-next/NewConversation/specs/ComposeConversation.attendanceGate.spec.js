import { mount, flushPromises } from '@vue/test-utils';

// Mocks ANTES do import do componente (hoisting do vi.mock).
const resolveGateMock = vi.fn();
vi.mock('dashboard/composables/useAttendanceGate', async () => {
  const actual = await vi.importActual(
    '../../../composables/useAttendanceGate'
  );
  return {
    ...actual,
    useAttendanceGate: () => ({
      resolveGate: resolveGateMock,
      isChecking: { value: false },
    }),
  };
});

const dispatchMock = vi.fn();
const pushMock = vi.fn();
// controlável por teste: liga/desliga o modo de pedido
let accountSettings = { takeover_request_gate: true };

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    dispatch: dispatchMock,
    // sem este getter o performCreateConversation estoura antes do create
    getters: {
      'contactConversations/getActiveConversationByInbox': () => null,
    },
  }),
  useMapGetter: key => {
    const values = {
      'contacts/getContactById': () => null,
      'contacts/getUIFlags': {},
      getCurrentAccountId: 1,
      getCurrentUser: { id: 1 },
      'globalConfig/get': { directUploadsEnabled: false },
      'contactConversations/getUIFlags': {},
      getMessageSignature: '',
      'inboxes/getInboxes': [],
    };
    return { value: values[key] };
  },
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: { value: { settings: accountSettings } },
  }),
}));
vi.mock('vue-router', () => ({ useRouter: () => ({ push: pushMock }) }));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({ fetchSignatureFlagFromUISettings: () => false }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useKeyboardEvents', () => ({
  useKeyboardEvents: vi.fn(),
}));
vi.mock(
  'dashboard/components-next/NewConversation/helpers/composeConversationHelper',
  () => ({
    createContactSearcher: () => vi.fn(),
    createNewContact: vi.fn(),
    fetchContactableInboxes: vi.fn(),
    processContactableInboxes: () => [],
    mergeInboxDetails: () => [],
  })
);

import ComposeConversation from '../ComposeConversation.vue';
import { ATTENDANCE_VARIANT } from '../../../composables/useAttendanceGate';

const FormStub = {
  name: 'ComposeNewConversationForm',
  props: ['formState'],
  template: '<div />',
};

const PAYLOAD = {
  payload: { contactId: 7, inboxId: 3 },
  isFromWhatsApp: false,
};

const mountCompose = () =>
  mount(ComposeConversation, {
    global: {
      stubs: {
        ComposeNewConversationForm: FormStub,
        AttendanceWarningDialog: {
          name: 'AttendanceWarningDialog',
          template: '<div />',
          methods: { open: vi.fn(), close: vi.fn() },
        },
      },
      directives: { 'on-click-outside': {} },
    },
  });

const triggerCreate = wrapper => wrapper.vm.createConversation(PAYLOAD);

describe('ComposeConversation — gate de atendimento (Fase 2)', () => {
  beforeEach(() => {
    dispatchMock.mockReset();
    pushMock.mockReset();
    resolveGateMock.mockReset();
    dispatchMock.mockResolvedValue({ id: 99, account_id: 1 });
  });

  // A promessa da Fase 2: nenhuma mensagem sai sem o agente confirmar.
  it('does not send anything when the contact is already in attendance', async () => {
    resolveGateMock.mockResolvedValue({
      blocked: true,
      attendance: { id: 55, assignee: { name: 'Ana', type: 'user' } },
      variant: ATTENDANCE_VARIANT.HUMAN,
      sameInbox: true,
    });
    const wrapper = mountCompose();
    wrapper.vm.showComposeNewConversation = true;
    await flushPromises();

    await triggerCreate(wrapper);
    await flushPromises();

    const dispatched = dispatchMock.mock.calls.map(c => c[0]);
    expect(dispatched).not.toContain('contactConversations/create');
    expect(dispatched).not.toContain(
      'contactConversations/sendToExistingConversation'
    );
  });

  it('sends normally when nobody is serving the contact', async () => {
    resolveGateMock.mockResolvedValue({
      blocked: false,
      attendance: null,
      variant: null,
      sameInbox: false,
    });
    const wrapper = mountCompose();
    wrapper.vm.showComposeNewConversation = true;
    await flushPromises();

    await triggerCreate(wrapper);
    await flushPromises();

    expect(dispatchMock.mock.calls.map(c => c[0])).toContain(
      'contactConversations/create'
    );
  });

  // Falha na checagem NÃO pode virar envio silencioso — seria o bug de volta.
  it('does not send when the attendance check itself failed', async () => {
    resolveGateMock.mockResolvedValue({
      blocked: true,
      attendance: null,
      variant: ATTENDANCE_VARIANT.UNKNOWN,
      sameInbox: false,
    });
    const wrapper = mountCompose();
    wrapper.vm.showComposeNewConversation = true;
    await flushPromises();

    await triggerCreate(wrapper);
    await flushPromises();

    expect(dispatchMock.mock.calls.map(c => c[0])).not.toContain(
      'contactConversations/create'
    );
  });
});

// Fase 3 na porta de "Todos os contatos": com o modo ligado, o aviso vira
// VALIDAÇÃO — oferece "Solicitar" e tira "Enviar mesmo assim".
describe('ComposeConversation — Solicitar no compose (modo ligado)', () => {
  const blockByColleague = (over = {}) =>
    resolveGateMock.mockResolvedValue({
      blocked: true,
      attendance: {
        id: 55,
        canRequest: true,
        myPendingRequestId: null,
        assignee: { name: 'Ana', type: 'user' },
        ...over,
      },
      variant: ATTENDANCE_VARIANT.HUMAN,
      sameInbox: true,
    });

  const openBlocked = async () => {
    const wrapper = mountCompose();
    wrapper.vm.showComposeNewConversation = true;
    await flushPromises();
    await triggerCreate(wrapper);
    await flushPromises();
    return wrapper;
  };

  beforeEach(() => {
    accountSettings = { takeover_request_gate: true };
    dispatchMock.mockReset();
    resolveGateMock.mockReset();
    dispatchMock.mockResolvedValue({ id: 99, account_id: 1 });
  });

  it('offers request and hides "send anyway" for a colleague (flag ON)', async () => {
    blockByColleague();
    const wrapper = await openBlocked();
    expect(wrapper.vm.attendanceCanRequest).toBe(true);
    expect(wrapper.vm.attendanceAllowSendAnyway).toBe(false);
  });

  it('keeps "send anyway" and no request when the flag is OFF', async () => {
    accountSettings = { takeover_request_gate: false };
    blockByColleague();
    const wrapper = await openBlocked();
    expect(wrapper.vm.attendanceCanRequest).toBe(false);
    expect(wrapper.vm.attendanceAllowSendAnyway).toBe(true);
  });

  it('cannot request (only blocks) when I have no access to the conversation', async () => {
    blockByColleague({ canRequest: false });
    const wrapper = await openBlocked();
    expect(wrapper.vm.attendanceCanRequest).toBe(false);
    expect(wrapper.vm.attendanceAllowSendAnyway).toBe(false); // sem "enviar mesmo assim"
  });

  it('shows the pending state instead of a new request when I already requested it', async () => {
    blockByColleague({ myPendingRequestId: 77 });
    const wrapper = await openBlocked();
    expect(wrapper.vm.attendanceHasPendingRequest).toBe(true);
    expect(wrapper.vm.attendanceCanRequest).toBe(false);
  });

  it('creates the takeover request and does NOT send a message', async () => {
    blockByColleague();
    const wrapper = await openBlocked();
    await wrapper.vm.onAttendanceRequest();
    await flushPromises();

    const dispatched = dispatchMock.mock.calls.map(c => c[0]);
    expect(dispatchMock).toHaveBeenCalledWith('takeoverRequests/create', {
      conversationId: 55,
    });
    expect(dispatched).not.toContain('contactConversations/create');
  });
});
