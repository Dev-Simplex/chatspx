import { useTeamIsolation } from '../useTeamIsolation';
import { useStore } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store');

// `teams/getVisibleTeams` é membro ∪ supervisionado (getter da F4). O agente comum
// recebe só os times de que é membro; o supervisor recebe também os supervisionados.
const buildStore = ({
  role = 'agent',
  accountId = 100,
  visibleTeams = [],
} = {}) => ({
  getters: {
    getCurrentUser: { id: 1, accounts: [{ id: accountId, role }] },
    getCurrentAccount: { id: accountId },
    'teams/getVisibleTeams': visibleTeams,
  },
});

describe('useTeamIsolation', () => {
  const inboxOn = { team_message_isolation: true };
  const inboxOff = { team_message_isolation: false };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('returns false when isolation is disabled on the inbox', () => {
    useStore.mockReturnValue(buildStore());
    const { isMessageRestricted } = useTeamIsolation();
    expect(isMessageRestricted({ team_id: 7 }, inboxOff)).toBe(false);
  });

  it('returns false for a team the user belongs to', () => {
    useStore.mockReturnValue(buildStore({ visibleTeams: [{ id: 7 }] }));
    const { isMessageRestricted } = useTeamIsolation();
    expect(isMessageRestricted({ team_id: 7 }, inboxOn)).toBe(false);
  });

  it('returns true for a team the user does not belong to', () => {
    useStore.mockReturnValue(buildStore({ visibleTeams: [{ id: 9 }] }));
    const { isMessageRestricted } = useTeamIsolation();
    expect(isMessageRestricted({ team_id: 7 }, inboxOn)).toBe(true);
  });

  it('returns false for public messages (team_id null)', () => {
    useStore.mockReturnValue(buildStore({ visibleTeams: [] }));
    const { isMessageRestricted } = useTeamIsolation();
    expect(isMessageRestricted({ team_id: null }, inboxOn)).toBe(false);
  });

  it('returns false for activity messages even from another team', () => {
    useStore.mockReturnValue(buildStore({ visibleTeams: [] }));
    const { isMessageRestricted } = useTeamIsolation();
    expect(isMessageRestricted({ team_id: 7, message_type: 2 }, inboxOn)).toBe(
      false
    );
  });

  it('returns false for admins (they see everything)', () => {
    useStore.mockReturnValue(
      buildStore({ role: 'administrator', visibleTeams: [] })
    );
    const { isMessageRestricted } = useTeamIsolation();
    expect(isMessageRestricted({ team_id: 7 }, inboxOn)).toBe(false);
  });

  it('supports camelCase fields (teamId / teamMessageIsolation)', () => {
    useStore.mockReturnValue(buildStore({ visibleTeams: [] }));
    const { isMessageRestricted } = useTeamIsolation();
    expect(
      isMessageRestricted({ teamId: 7 }, { teamMessageIsolation: true })
    ).toBe(true);
  });

  // Supervisão de time: o supervisor não é membro, mas getVisibleTeams o inclui,
  // então a bolha do time supervisionado deixa de ser mascarada.
  describe('supervisão de time', () => {
    it('supervisor vê a mensagem do time que supervisiona', () => {
      // membro do 9, supervisor do 7 -> getVisibleTeams devolve os dois
      useStore.mockReturnValue(
        buildStore({ visibleTeams: [{ id: 9 }, { id: 7 }] })
      );
      const { isMessageRestricted } = useTeamIsolation();
      expect(isMessageRestricted({ team_id: 7 }, inboxOn)).toBe(false);
    });

    it('agente comum (só membro do 9) continua vendo 🔒 na mesma mensagem', () => {
      useStore.mockReturnValue(buildStore({ visibleTeams: [{ id: 9 }] }));
      const { isMessageRestricted } = useTeamIsolation();
      expect(isMessageRestricted({ team_id: 7 }, inboxOn)).toBe(true);
    });

    it('supervisor continua bloqueado no time que não supervisiona', () => {
      useStore.mockReturnValue(
        buildStore({ visibleTeams: [{ id: 9 }, { id: 7 }] })
      );
      const { isMessageRestricted } = useTeamIsolation();
      expect(isMessageRestricted({ team_id: 12 }, inboxOn)).toBe(true);
    });
  });
});
