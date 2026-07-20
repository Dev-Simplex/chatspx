import { ref, nextTick } from 'vue';
import { useContactAttendance, SEND_ACTION } from '../useContactAttendance';

// controles dos mocks
let fetchResult = [];
let flagOn = true;
let role = 'agent';
const MY_ID = 10;

vi.mock('dashboard/composables/useAttendanceGate', () => ({
  useAttendanceGate: () => ({
    fetchAttendances: vi.fn(() => Promise.resolve(fetchResult)),
  }),
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: { value: { settings: { takeover_request_gate: flagOn } } },
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({}),
  useMapGetter: key => {
    const map = {
      getCurrentUserID: { value: MY_ID },
      getCurrentRole: { value: role },
      'takeoverRequests/getIncoming': { value: [] },
    };
    return map[key];
  },
}));

const att = (over = {}) => ({
  id: 100,
  status: 'open',
  assignee: { id: 99, name: 'Ana', availableName: 'Ana', type: 'user' },
  team: { id: 2, name: 'Suporte' },
  inbox: { id: 3, name: 'WhatsApp' },
  canRequest: true,
  myPendingRequestId: null,
  ...over,
});

const resolve = async attendances => {
  fetchResult = attendances;
  const { sendAction, statusLabel } = useContactAttendance(ref(1));
  await nextTick();
  await nextTick();
  return { sendAction, statusLabel };
};

describe('useContactAttendance — sendAction', () => {
  beforeEach(() => {
    flagOn = true;
    role = 'agent';
    fetchResult = [];
  });

  it('is SEND when nobody else is serving the contact', async () => {
    const { sendAction } = await resolve([]);
    expect(sendAction.value.type).toBe(SEND_ACTION.SEND);
  });

  it('is SEND when I already serve the contact somewhere', async () => {
    const { sendAction } = await resolve([
      att({ assignee: { id: MY_ID, name: 'Eu', type: 'user' } }),
    ]);
    expect(sendAction.value.type).toBe(SEND_ACTION.SEND);
  });

  it('is REQUEST when a colleague serves it and I can request', async () => {
    const { sendAction, statusLabel } = await resolve([att()]);
    expect(sendAction.value).toEqual({
      type: SEND_ACTION.REQUEST,
      conversationId: 100,
    });
    expect(statusLabel.value).toEqual({ name: 'Ana', team: 'Suporte' });
  });

  it('is PENDING when I already have a pending request on it', async () => {
    const { sendAction } = await resolve([att({ myPendingRequestId: 77 })]);
    expect(sendAction.value).toEqual({
      type: SEND_ACTION.PENDING,
      requestId: 77,
    });
  });

  it('is BLOCKED when a colleague serves it and I cannot request (other team)', async () => {
    const { sendAction } = await resolve([att({ canRequest: false })]);
    expect(sendAction.value.type).toBe(SEND_ACTION.BLOCKED);
  });

  it('is SEND for an AI-owned conversation (not a human takeover)', async () => {
    const { sendAction } = await resolve([
      att({ assignee: { id: 9, name: 'Captain', type: 'agent_bot' } }),
    ]);
    expect(sendAction.value.type).toBe(SEND_ACTION.SEND);
  });

  it('is SEND for an admin (exempt)', async () => {
    role = 'administrator';
    const { sendAction } = await resolve([att()]);
    expect(sendAction.value.type).toBe(SEND_ACTION.SEND);
  });

  it('is SEND when the mode is OFF (no surprise for accounts without it)', async () => {
    flagOn = false;
    const { sendAction } = await resolve([att()]);
    expect(sendAction.value.type).toBe(SEND_ACTION.SEND);
  });
});
