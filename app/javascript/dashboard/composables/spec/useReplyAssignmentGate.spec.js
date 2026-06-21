import { defineComponent, h } from 'vue';
import { createStore } from 'vuex';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { mount } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import { useReplyAssignmentGate } from '../useReplyAssignmentGate';

vi.mock('vue-router');

const createComponent = () =>
  defineComponent({
    setup() {
      return useReplyAssignmentGate();
    },
    render() {
      return h('div');
    },
  });

const mountWithAccount = account => {
  const store = createStore({
    modules: {
      accounts: {
        namespaced: true,
        getters: {
          getAccount: () => () => account,
        },
      },
    },
  });
  return mount(createComponent(), { global: { plugins: [store] } });
};

describe('useReplyAssignmentGate', () => {
  beforeEach(() => {
    useRoute.mockReturnValue({
      params: { accountId: '1' },
    });
  });

  it('returns true when reply_assignment_gate is enabled', () => {
    const wrapper = mountWithAccount({
      id: 1,
      settings: { reply_assignment_gate: true },
    });
    expect(wrapper.vm.isAssignmentGateEnabled).toBe(true);
  });

  it('returns false when reply_assignment_gate is false', () => {
    const wrapper = mountWithAccount({
      id: 1,
      settings: { reply_assignment_gate: false },
    });
    expect(wrapper.vm.isAssignmentGateEnabled).toBe(false);
  });

  it('returns false when the setting is absent', () => {
    const wrapper = mountWithAccount({ id: 1, settings: {} });
    expect(wrapper.vm.isAssignmentGateEnabled).toBe(false);
  });

  it('returns false when the account has no settings', () => {
    const wrapper = mountWithAccount({ id: 1 });
    expect(wrapper.vm.isAssignmentGateEnabled).toBe(false);
  });

  it('returns false when the account is not loaded yet', () => {
    const wrapper = mountWithAccount(undefined);
    expect(wrapper.vm.isAssignmentGateEnabled).toBe(false);
  });
});
