import { mount } from '@vue/test-utils';
import AttendanceCard from '../AttendanceCard.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));

vi.mock('shared/helpers/timeHelper', () => ({
  dynamicTime: () => 'há 2 horas',
}));

const baseProps = {
  id: 11,
  status: 'open',
  createdAt: 1750000000,
  lastActivityAt: 1750000500,
  contact: { id: 1, name: 'Fulano', thumbnail: '', phoneNumber: '+5511999' },
  inbox: { id: 3, name: 'WhatsApp', channelType: 'Channel::Api' },
  assignee: { id: 7, name: 'Ana', availableName: 'Ana', type: 'user' },
  team: { id: 2, name: 'Suporte' },
};

const mountCard = (props = {}) =>
  mount(AttendanceCard, {
    props: { ...baseProps, ...props },
    global: { stubs: { Avatar: true, Button: true } },
  });

describe('AttendanceCard', () => {
  it('shows the contact, the human assignee, the team and the inbox', () => {
    const wrapper = mountCard();

    expect(wrapper.text()).toContain('Fulano');
    expect(wrapper.text()).toContain('Ana');
    expect(wrapper.text()).toContain('Suporte');
    expect(wrapper.text()).toContain('WhatsApp');
  });

  it('badges an AI assignee', () => {
    const wrapper = mountCard({
      assignee: {
        id: 9,
        name: 'Captain',
        availableName: 'Captain',
        type: 'agent_bot',
      },
    });

    expect(wrapper.text()).toContain('CONTACTS_LAYOUT.IN_ATTENDANCE.AI_BADGE');
  });

  it('does not badge a human assignee as AI', () => {
    expect(mountCard().text()).not.toContain(
      'CONTACTS_LAYOUT.IN_ATTENDANCE.AI_BADGE'
    );
  });

  it('falls back to "no assignee" and "no team"', () => {
    const wrapper = mountCard({ assignee: null, team: null });

    expect(wrapper.text()).toContain(
      'CONTACTS_LAYOUT.IN_ATTENDANCE.NO_ASSIGNEE'
    );
    expect(wrapper.text()).toContain('CONTACTS_LAYOUT.IN_ATTENDANCE.NO_TEAM');
  });

  // Sem trecho de conversa é o requisito do dono — o card nem recebe a prop.
  it('has no message content to render', () => {
    expect(Object.keys(AttendanceCard.props)).not.toContain('messages');
    expect(Object.keys(AttendanceCard.props)).not.toContain('lastMessage');
  });

  // A ação da linha é decidida pelas capacidades que o BACKEND manda — o card só
  // obedece. Assim o botão nunca promete algo que viraria 403/422 no clique.
  describe('ação contextual da linha', () => {
    const clickButton = async wrapper =>
      wrapper.findComponent({ name: 'Button' }).vm.$emit('click');

    it('offers "assumir" when the row can be assumed', async () => {
      const wrapper = mountCard({ canOpen: true, canAssume: true });
      await clickButton(wrapper);
      expect(wrapper.emitted('assumeAttendance')).toEqual([
        [{ conversationId: 11, contactId: 1 }],
      ]);
    });

    it('offers "solicitar" when the row can only be requested', async () => {
      const wrapper = mountCard({ canOpen: true, canRequest: true });
      await clickButton(wrapper);
      expect(wrapper.emitted('requestAttendance')).toEqual([
        [{ conversationId: 11, contactId: 1 }],
      ]);
    });

    it('offers "abrir" when I can only open it (my own conversation)', async () => {
      const wrapper = mountCard({ canOpen: true });
      await clickButton(wrapper);
      expect(wrapper.emitted('openConversation')).toEqual([
        [{ conversationId: 11, contactId: 1 }],
      ]);
    });

    // "já pedi" vence "posso pedir" — senão eu pediria duas vezes.
    it('shows the pending state with cancel when I already requested it', async () => {
      const wrapper = mountCard({
        canOpen: true,
        canRequest: true,
        myPendingRequestId: 77,
      });

      expect(wrapper.text()).toContain(
        'CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.PENDING_STATE'
      );
      await clickButton(wrapper);
      expect(wrapper.emitted('cancelRequest')).toEqual([
        [{ conversationId: 11, contactId: 1, requestId: 77 }],
      ]);
      expect(wrapper.emitted('requestAttendance')).toBeUndefined();
    });

    // A linha sem acesso NÃO some: explica o porquê (a ciência da duplicação é
    // metade do valor da aba) mas não oferece botão nenhum.
    it('explains why instead of offering a button when I have no access', () => {
      const wrapper = mountCard();
      expect(wrapper.findComponent({ name: 'Button' }).exists()).toBe(false);
      expect(wrapper.text()).toContain(
        'CONTACTS_LAYOUT.IN_ATTENDANCE.NO_ACCESS_TEAM'
      );
    });

    it('falls back to the inbox reason when the row has no team', () => {
      const wrapper = mountCard({ team: null });
      expect(wrapper.text()).toContain(
        'CONTACTS_LAYOUT.IN_ATTENDANCE.NO_ACCESS_INBOX'
      );
    });
  });

  describe('destaque de duplicação', () => {
    it('flags the contact when they have 2+ open attendances', () => {
      expect(mountCard({ duplicated: true }).text()).toContain(
        'CONTACTS_LAYOUT.IN_ATTENDANCE.DUPLICATED'
      );
    });

    it('does not flag a contact with a single attendance', () => {
      expect(mountCard().text()).not.toContain(
        'CONTACTS_LAYOUT.IN_ATTENDANCE.DUPLICATED'
      );
    });
  });
});
