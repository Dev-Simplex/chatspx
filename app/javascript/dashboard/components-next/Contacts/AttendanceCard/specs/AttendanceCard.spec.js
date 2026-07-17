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

  // A visibilidade do botão é decidida no BACKEND (canRequest) — que espelha a
  // autorização do endpoint de pedido. O card só obedece: sem canRequest, nada
  // de botão prometendo uma ação que daria 403.
  it('shows the request button only when canRequest is true', () => {
    expect(
      mountCard({ canRequest: true }).findComponent({ name: 'Button' }).exists()
    ).toBe(true);
  });

  it('hides the request button when canRequest is false (default)', () => {
    expect(mountCard().findComponent({ name: 'Button' }).exists()).toBe(false);
  });

  it('emits requestAttendance with the conversation and contact ids', async () => {
    const wrapper = mountCard({ canRequest: true });

    await wrapper.findComponent({ name: 'Button' }).vm.$emit('click');

    expect(wrapper.emitted('requestAttendance')).toEqual([
      [{ conversationId: 11, contactId: 1 }],
    ]);
  });
});
