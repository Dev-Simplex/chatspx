import { nextTick } from 'vue';
import { mount, flushPromises } from '@vue/test-utils';
import AttendanceModeToggle from '../AttendanceModeToggle.vue';

const { alertSpy, updateAccountSpy, currentAccountRef } = vi.hoisted(() => ({
  alertSpy: vi.fn(),
  updateAccountSpy: vi.fn(),
  currentAccountRef: { value: {} },
}));

vi.mock('dashboard/composables', () => ({
  useAlert: alertSpy,
}));

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({
    currentAccount: currentAccountRef,
    updateAccount: updateAccountSpy,
  }),
}));

const DialogStub = {
  name: 'Dialog',
  props: ['type', 'title', 'description', 'confirmButtonLabel', 'isLoading'],
  emits: ['confirm', 'close'],
  data() {
    return { isOpen: false };
  },
  methods: {
    open() {
      this.isOpen = true;
    },
    close() {
      this.isOpen = false;
    },
  },
  template: '<div data-testid="dialog" :data-open="isOpen" />',
};

const mountComponent = (settings = {}) => {
  currentAccountRef.value = { id: 1, settings };
  return mount(AttendanceModeToggle, {
    global: {
      stubs: { Dialog: DialogStub },
    },
  });
};

const modeCards = wrapper =>
  wrapper.findAll('button[type="button"][aria-pressed]');

describe('AttendanceModeToggle', () => {
  beforeEach(() => {
    alertSpy.mockClear();
    updateAccountSpy.mockReset();
    updateAccountSpy.mockResolvedValue();
  });

  describe('active card reflects settings.reply_assignment_gate', () => {
    it('marks gated as active when the flag is true', () => {
      const wrapper = mountComponent({ reply_assignment_gate: true });
      const [classic, gated] = modeCards(wrapper);
      expect(classic.attributes('aria-pressed')).toBe('false');
      expect(gated.attributes('aria-pressed')).toBe('true');
      expect(gated.text()).toContain('Active');
    });

    it('marks classic as active when the flag is false', () => {
      const wrapper = mountComponent({ reply_assignment_gate: false });
      const [classic, gated] = modeCards(wrapper);
      expect(classic.attributes('aria-pressed')).toBe('true');
      expect(classic.text()).toContain('Active');
      expect(gated.attributes('aria-pressed')).toBe('false');
    });

    it('falls back to classic when the setting is absent', () => {
      const wrapper = mountComponent({});
      const [classic, gated] = modeCards(wrapper);
      expect(classic.attributes('aria-pressed')).toBe('true');
      expect(gated.attributes('aria-pressed')).toBe('false');
    });
  });

  it('is a no-op when selecting the mode that is already active', async () => {
    const wrapper = mountComponent({ reply_assignment_gate: false });
    const [classic] = modeCards(wrapper);
    await classic.trigger('click');

    const dialog = wrapper.findComponent(DialogStub);
    expect(dialog.vm.isOpen).toBe(false);
    expect(updateAccountSpy).not.toHaveBeenCalled();
  });

  it('opens the confirmation dialog when selecting the other mode', async () => {
    const wrapper = mountComponent({ reply_assignment_gate: false });
    const [, gated] = modeCards(wrapper);
    await gated.trigger('click');

    const dialog = wrapper.findComponent(DialogStub);
    expect(dialog.vm.isOpen).toBe(true);
    expect(dialog.props('title')).toBe('Enable required assignment?');
    expect(updateAccountSpy).not.toHaveBeenCalled();
  });

  it('dispatches updateAccount({ reply_assignment_gate: true }) on confirm of gated', async () => {
    const wrapper = mountComponent({ reply_assignment_gate: false });
    const [, gated] = modeCards(wrapper);
    await gated.trigger('click');

    const dialog = wrapper.findComponent(DialogStub);
    dialog.vm.$emit('confirm');
    await flushPromises();

    expect(updateAccountSpy).toHaveBeenCalledWith({
      reply_assignment_gate: true,
    });
    expect(alertSpy).toHaveBeenCalledWith('Attendance mode updated');
    expect(dialog.vm.isOpen).toBe(false);
  });

  it('dispatches updateAccount({ reply_assignment_gate: false }) on confirm of classic', async () => {
    const wrapper = mountComponent({ reply_assignment_gate: true });
    const [classic] = modeCards(wrapper);
    await classic.trigger('click');

    const dialog = wrapper.findComponent(DialogStub);
    expect(dialog.props('title')).toBe('Back to classic mode?');
    dialog.vm.$emit('confirm');
    await flushPromises();

    expect(updateAccountSpy).toHaveBeenCalledWith({
      reply_assignment_gate: false,
    });
  });

  it('shows the error alert and keeps the visual mode on failure', async () => {
    updateAccountSpy.mockRejectedValueOnce(new Error('422'));
    const wrapper = mountComponent({ reply_assignment_gate: false });
    const [classic, gated] = modeCards(wrapper);
    await gated.trigger('click');

    const dialog = wrapper.findComponent(DialogStub);
    dialog.vm.$emit('confirm');
    await flushPromises();
    await nextTick();

    expect(alertSpy).toHaveBeenCalledWith("Couldn't update, please try again");
    // account settings never changed, so classic stays active
    expect(classic.attributes('aria-pressed')).toBe('true');
    expect(gated.attributes('aria-pressed')).toBe('false');
    expect(dialog.vm.isOpen).toBe(false);
  });
});
