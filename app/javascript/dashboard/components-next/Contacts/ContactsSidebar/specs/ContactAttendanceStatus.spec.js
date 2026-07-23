import { mount } from '@vue/test-utils';
import ContactAttendanceStatus from '../ContactAttendanceStatus.vue';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, params) => (params ? `${key}:${JSON.stringify(params)}` : key),
  }),
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: 10 }), // getCurrentUserID = 10
}));

vi.mock('shared/helpers/timeHelper', () => ({
  dynamicTime: () => 'há 2 horas',
}));

const att = (over = {}) => ({
  id: 100,
  status: 'open',
  createdAt: 1750000000,
  assignee: { id: 99, name: 'Ana', availableName: 'Ana', type: 'user' },
  team: { id: 2, name: 'Suporte' },
  inbox: { id: 3, name: 'WhatsApp' },
  ...over,
});

const mountTab = (props = {}) =>
  mount(ContactAttendanceStatus, {
    props,
    global: { stubs: { Avatar: true, Spinner: true } },
  });

describe('ContactAttendanceStatus', () => {
  it('renders the agent, team and inbox of each attendance', () => {
    const wrapper = mountTab({ attendances: [att()] });
    expect(wrapper.text()).toContain('Ana');
    expect(wrapper.text()).toContain('Suporte');
    expect(wrapper.text()).toContain('WhatsApp');
  });

  it('badges the attendance as "you" when it is mine', () => {
    const wrapper = mountTab({
      attendances: [att({ assignee: { id: 10, name: 'Eu', type: 'user' } })],
    });
    expect(wrapper.text()).toContain('CONTACTS_LAYOUT.IN_ATTENDANCE.YOU');
  });

  it('badges an AI attendance', () => {
    const wrapper = mountTab({
      attendances: [
        att({ assignee: { id: 9, name: 'Captain', type: 'agent_bot' } }),
      ],
    });
    expect(wrapper.text()).toContain('CONTACTS_LAYOUT.IN_ATTENDANCE.AI_BADGE');
  });

  it('shows an empty state when there is no active attendance', () => {
    const wrapper = mountTab({ attendances: [] });
    expect(wrapper.text()).toContain(
      'CONTACTS_LAYOUT.IN_ATTENDANCE.NO_ACTIVE_ATTENDANCE'
    );
  });

  // Sem trecho de conversa: a aba é só metadado (mesmo requisito da aba geral).
  it('never renders message content', () => {
    expect(Object.keys(ContactAttendanceStatus.props)).not.toContain(
      'messages'
    );
  });
});
