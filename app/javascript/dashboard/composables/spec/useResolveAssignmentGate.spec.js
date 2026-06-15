import { defineComponent, h } from 'vue';
import { createStore } from 'vuex';
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { mount } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import { useResolveAssignmentGate } from '../useResolveAssignmentGate';

vi.mock('vue-router');

const CURRENT_USER_ID = 7;

const buildStore = ({ gateEnabled = true } = {}) =>
  createStore({
    modules: {
      auth: {
        namespaced: false,
        getters: {
          getCurrentUserID: () => CURRENT_USER_ID,
        },
      },
      accounts: {
        namespaced: true,
        getters: {
          getAccount: () => () => ({
            id: 123,
            settings: { resolve_assignment_gate: gateEnabled },
          }),
        },
      },
    },
  });

const mountGate = store => {
  const wrapper = mount(
    defineComponent({
      setup() {
        return useResolveAssignmentGate();
      },
      render: () => h('div'),
    }),
    { global: { plugins: [store] } }
  );
  return wrapper.vm;
};

describe('useResolveAssignmentGate', () => {
  beforeEach(() => {
    useRoute.mockReturnValue({ params: { accountId: '123' } });
  });

  it('reflects the account flag', () => {
    expect(
      mountGate(buildStore({ gateEnabled: true })).isResolveGateEnabled
    ).toBe(true);
    expect(
      mountGate(buildStore({ gateEnabled: false })).isResolveGateEnabled
    ).toBe(false);
  });

  it('detects ownership via meta.assignee', () => {
    const gate = mountGate(buildStore());
    expect(
      gate.isAssignedToMe({ meta: { assignee: { id: CURRENT_USER_ID } } })
    ).toBe(true);
    expect(gate.isAssignedToMe({ meta: { assignee: { id: 99 } } })).toBe(false);
    expect(gate.isAssignedToMe({ meta: {} })).toBe(false);
  });

  it('requires assignment only for non-owned conversations when enabled', () => {
    const gate = mountGate(buildStore({ gateEnabled: true }));
    expect(
      gate.requiresAssignmentToResolve({
        meta: { assignee: { id: CURRENT_USER_ID } },
      })
    ).toBe(false);
    expect(
      gate.requiresAssignmentToResolve({ meta: { assignee: { id: 99 } } })
    ).toBe(true);
  });

  it('never requires assignment when the gate is disabled', () => {
    const gate = mountGate(buildStore({ gateEnabled: false }));
    expect(
      gate.requiresAssignmentToResolve({ meta: { assignee: { id: 99 } } })
    ).toBe(false);
  });

  it('maps the dialog variant from the assignee', () => {
    const gate = mountGate(buildStore());
    expect(gate.getResolveVariant({ meta: {} })).toBe('unassigned');
    expect(gate.getResolveVariant({ meta: { assignee: { id: 99 } } })).toBe(
      'colleague'
    );
    expect(
      gate.getResolveVariant({
        meta: { assignee: { id: 5, type: 'agent_bot' } },
      })
    ).toBe('ai');
  });

  it('detects team presence', () => {
    const gate = mountGate(buildStore());
    expect(gate.hasTeam({ meta: { team: { id: 1 } } })).toBe(true);
    expect(gate.hasTeam({ team_id: 3 })).toBe(true);
    expect(gate.hasTeam({ meta: {} })).toBe(false);
  });
});
