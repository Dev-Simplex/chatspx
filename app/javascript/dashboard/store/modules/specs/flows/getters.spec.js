import { getters } from '../../flows';
import flowsList from './fixtures';

describe('#getters', () => {
  it('getFlows returns records sorted ascending by id', () => {
    const state = { records: [...flowsList] };
    const result = getters.getFlows(state);
    expect(result.map(flow => flow.id)).toEqual([1, 2]);
  });

  it('getFlow finds a record by numeric id', () => {
    const state = { records: [...flowsList] };
    expect(getters.getFlow(state)(1).name).toBe('Boas-vindas');
  });

  it('getFlow coerces a string id to a number', () => {
    const state = { records: [...flowsList] };
    expect(getters.getFlow(state)('2').name).toBe('Follow-up automático');
  });

  it('getFlow returns undefined for a missing id', () => {
    const state = { records: [...flowsList] };
    expect(getters.getFlow(state)(999)).toBeUndefined();
  });

  it('getUIFlags returns the ui flags object', () => {
    const state = { uiFlags: { isFetching: true, isCreating: false } };
    expect(getters.getUIFlags(state)).toEqual({
      isFetching: true,
      isCreating: false,
    });
  });
});
