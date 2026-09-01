import { ref } from 'vue';
import { useGroupConversation } from '../useGroupConversation';
import { useMapGetter } from 'dashboard/composables/store';

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: vi.fn(),
}));

const buildConversation = ({
  sender = {},
  additionalAttributes = {},
} = {}) => ({
  id: 12,
  meta: { sender },
  additional_attributes: additionalAttributes,
});

describe('useGroupConversation', () => {
  beforeEach(() => {
    useMapGetter.mockReturnValue(ref({}));
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('isGroup', () => {
    it('reconhece grupo pelo identifier @g.us', () => {
      const { isGroup } = useGroupConversation(
        buildConversation({
          sender: { identifier: '556696571379-1634750731@g.us' },
        })
      );
      expect(isGroup.value).toBe(true);
    });

    it('reconhece grupo pelo custom attribute da WAHA', () => {
      const { isGroup } = useGroupConversation(
        buildConversation({
          sender: {
            custom_attributes: {
              waha_whatsapp_chat_id: '120363287968160641@g.us',
            },
          },
        })
      );
      expect(isGroup.value).toBe(true);
    });

    it('reconhece grupo por additional_attributes.type', () => {
      const { isGroup } = useGroupConversation(
        buildConversation({ additionalAttributes: { type: 'group' } })
      );
      expect(isGroup.value).toBe(true);
    });

    it('não trata conversa 1:1 como grupo', () => {
      const { isGroup } = useGroupConversation(
        buildConversation({
          sender: {
            identifier: '5566984351177@c.us',
            custom_attributes: { waha_whatsapp_chat_id: '5566984351177@c.us' },
          },
        })
      );
      expect(isGroup.value).toBe(false);
    });
  });

  describe('groupName', () => {
    it('remove o sufixo de integração só na exibição', () => {
      const { groupName } = useGroupConversation(
        buildConversation({ sender: { name: 'TI TOZI - Inovação (GROUP)' } })
      );
      expect(groupName.value).toBe('TI TOZI - Inovação');
    });
  });

  describe('snapshot de integrantes', () => {
    const snapshot = {
      waha_group: {
        participants: [
          { lid: '1', phone: '5566999991234', name: 'Rogerio', admin: false },
          { lid: '2', phone: '5566999991235', name: 'Angela', admin: true },
          { lid: '3', phone: null, name: null, admin: false },
          { lid: '4', phone: '5566999991236', name: 'ederson', admin: false },
        ],
        count: 12,
        synced_at: '2026-07-27T14:00:00Z',
      },
    };

    it('ordena admins, depois demais A-Z, e não identificados por último', () => {
      const { participants } = useGroupConversation(
        buildConversation({ additionalAttributes: snapshot })
      );
      expect(participants.value.map(p => p.label)).toEqual([
        'Angela',
        'ederson',
        'Rogerio',
        null,
      ]);
      expect(participants.value[0].admin).toBe(true);
      expect(participants.value[3].isUnknown).toBe(true);
    });

    it('formata o telefone e nunca expõe o identificador técnico', () => {
      const { participants } = useGroupConversation(
        buildConversation({ additionalAttributes: snapshot })
      );
      const angela = participants.value[0];
      expect(angela.formattedPhone).toBe('+55 66 9 9999-1235');
      expect(angela.label).not.toContain('@lid');
      expect(angela.label).not.toContain(angela.lid);
    });

    it('usa a contagem do snapshot, não o tamanho da lista', () => {
      const { participantCount, unresolvedCount, hasSnapshot } =
        useGroupConversation(
          buildConversation({ additionalAttributes: snapshot })
        );
      expect(participantCount.value).toBe(12);
      expect(unresolvedCount.value).toBe(1);
      expect(hasSnapshot.value).toBe(true);
    });

    it('degrada sem inventar contagem quando nunca sincronizou', () => {
      const { hasSnapshot, participantCount, participants, syncedAt } =
        useGroupConversation(
          buildConversation({ sender: { identifier: 'x@g.us' } })
        );
      expect(hasSnapshot.value).toBe(false);
      expect(participants.value).toEqual([]);
      expect(participantCount.value).toBe(0);
      expect(syncedAt.value).toBeNull();
    });
  });
});
