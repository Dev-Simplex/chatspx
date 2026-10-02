import { mount, flushPromises } from '@vue/test-utils';
import CaptadorHookStatus from '../CaptadorHookStatus.vue';
import IntegrationsAPI from 'dashboard/api/integrations';

vi.mock('dashboard/api/integrations', () => ({
  default: { testCaptador: vi.fn() },
}));
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key, vars) => `${key} ${vars?.ids || vars?.name || ''}`,
  }),
}));

const hook = id => ({
  id,
  settings: {
    captador_url: 'https://captador.example',
    shared_secret_configured: true,
  },
  captador_state: {
    effective_inboxes: [{ id, name: `Inbox ${id}` }],
    unavailable_inbox_ids: [],
  },
});
const render = () =>
  mount(CaptadorHookStatus, {
    props: { hook: hook(1) },
    global: { stubs: { Icon: true, Spinner: true } },
  });

describe('CaptadorHookStatus', () => {
  afterEach(() => vi.clearAllMocks());

  it('shows saved inboxes, setup link and coordinated rotation instructions without a secret', () => {
    const wrapper = render();
    expect(wrapper.text()).toContain('Inbox 1');
    expect(wrapper.text()).toContain('CAPTADOR_HOOK.ROTATION');
    expect(wrapper.find('a').attributes('href')).toBe(
      'https://captador.example/ajustes/conexoes'
    );
    expect(wrapper.find('input').exists()).toBe(false);
  });

  it.each([
    'ok',
    'degraded',
    'authentication_failed',
    'onboarding_required',
    'disabled',
  ])('shows %s and effective inbox feedback', async status => {
    IntegrationsAPI.testCaptador.mockResolvedValue({
      data: {
        status,
        effective_inboxes: [],
        unavailable_inbox_ids: [1],
      },
    });
    const wrapper = render();
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(IntegrationsAPI.testCaptador).toHaveBeenCalledWith(1);
    expect(wrapper.get('[role="status"]').text()).toContain(
      `CAPTADOR_HOOK.STATUS.${status}`
    );
    expect(wrapper.get('[role="alert"]').text()).toContain('1');
    expect(wrapper.text()).not.toContain('Inbox 1');
  });

  it('shows a retryable failure without rendering the server error', async () => {
    IntegrationsAPI.testCaptador.mockRejectedValue(new Error('private'));
    const wrapper = render();
    await wrapper.find('button').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('CAPTADOR_HOOK.STATUS.unavailable');
    expect(wrapper.text()).not.toContain('private');
    expect(wrapper.text()).toContain('Inbox 1');
    expect(wrapper.find('button').attributes('disabled')).toBeUndefined();
  });

  it('discards an in-flight result after switching accounts', async () => {
    let resolve;
    IntegrationsAPI.testCaptador.mockReturnValue(
      new Promise(done => {
        resolve = done;
      })
    );
    const wrapper = render();
    await wrapper.find('button').trigger('click');
    await wrapper.setProps({ hook: hook(2) });
    resolve({
      data: { status: 'ok', effective_inboxes: [{ id: 1, name: 'Private A' }] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain('Inbox 2');
    expect(wrapper.text()).not.toContain('Private A');
    expect(wrapper.text()).toContain('CAPTADOR_HOOK.STATUS.untested');
  });
});
