import axios from 'axios';
import { useAttendanceGate, ATTENDANCE_VARIANT } from '../useAttendanceGate';

global.axios = axios;
vi.mock('axios');

const attendance = ({ id = 11, inboxId = 3, assignee = undefined } = {}) => ({
  id,
  status: 'open',
  contact: { id: 1, name: 'Fulano' },
  inbox: {
    id: inboxId,
    name: `Caixa ${inboxId}`,
    channel_type: 'Channel::Api',
  },
  assignee,
  team: { id: 2, name: 'Suporte' },
});

const mockPayload = payload =>
  axios.get.mockResolvedValue({ data: { payload } });

describe('useAttendanceGate', () => {
  it('does not block when the contact has no active attendance', async () => {
    mockPayload([]);
    const { resolveGate } = useAttendanceGate();

    expect(await resolveGate({ contactId: 1, inboxId: 3 })).toEqual({
      blocked: false,
      attendance: null,
      variant: null,
      sameInbox: false,
    });
  });

  it('does not block when there is no contact yet', async () => {
    const { resolveGate } = useAttendanceGate();

    const result = await resolveGate({ contactId: null, inboxId: 3 });

    expect(result.blocked).toBe(false);
    expect(axios.get).not.toHaveBeenCalled();
  });

  it('flags a human owner', async () => {
    mockPayload([
      attendance({ assignee: { id: 7, name: 'Ana', type: 'user' } }),
    ]);
    const { resolveGate } = useAttendanceGate();

    const result = await resolveGate({ contactId: 1, inboxId: 3 });

    expect(result.blocked).toBe(true);
    expect(result.variant).toBe(ATTENDANCE_VARIANT.HUMAN);
    expect(result.attendance.assignee.name).toBe('Ana');
  });

  it('flags an AI owner', async () => {
    mockPayload([
      attendance({ assignee: { id: 9, name: 'Captain', type: 'agent_bot' } }),
    ]);
    const { resolveGate } = useAttendanceGate();

    expect((await resolveGate({ contactId: 1, inboxId: 3 })).variant).toBe(
      ATTENDANCE_VARIANT.BOT
    );
  });

  it('flags an unowned conversation sitting in the queue', async () => {
    mockPayload([attendance({ assignee: null })]);
    const { resolveGate } = useAttendanceGate();

    expect((await resolveGate({ contactId: 1, inboxId: 3 })).variant).toBe(
      ATTENDANCE_VARIANT.UNASSIGNED
    );
  });

  // O caso que o código de hoje ERRA: getActiveConversationByInbox filtra por
  // inbox, então atendimento em outra caixa passa batido — e é exatamente a
  // duplicação que a feature quer evitar.
  it('blocks when the attendance is in ANOTHER inbox, and says so', async () => {
    mockPayload([
      attendance({
        inboxId: 99,
        assignee: { id: 7, name: 'Ana', type: 'user' },
      }),
    ]);
    const { resolveGate } = useAttendanceGate();

    const result = await resolveGate({ contactId: 1, inboxId: 3 });

    expect(result.blocked).toBe(true);
    expect(result.sameInbox).toBe(false);
    expect(result.attendance.inbox.id).toBe(99);
  });

  it('prefers the attendance of the target inbox when there are several', async () => {
    mockPayload([
      attendance({ id: 50, inboxId: 99 }),
      attendance({ id: 51, inboxId: 3 }),
    ]);
    const { resolveGate } = useAttendanceGate();

    const result = await resolveGate({ contactId: 1, inboxId: 3 });

    expect(result.sameInbox).toBe(true);
    expect(result.attendance.id).toBe(51);
  });

  // Falhar aberto reintroduz o bug; falhar fechado trava trabalho legítimo.
  it('warns instead of silently passing when the check itself fails', async () => {
    axios.get.mockRejectedValue(new Error('boom'));
    const { resolveGate } = useAttendanceGate();

    const result = await resolveGate({ contactId: 1, inboxId: 3 });

    expect(result.blocked).toBe(true);
    expect(result.variant).toBe(ATTENDANCE_VARIANT.UNKNOWN);
    expect(result.attendance).toBeNull();
  });

  it('queries the attendances endpoint scoped by contact, not contactConversations', async () => {
    mockPayload([]);
    const { resolveGate } = useAttendanceGate();

    await resolveGate({ contactId: 42, inboxId: 3 });

    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('active_attendances')
    );
    expect(axios.get).toHaveBeenCalledWith(
      expect.stringContaining('contact_id=42')
    );
  });
});
