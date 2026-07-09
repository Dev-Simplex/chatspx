import types from '../../../mutation-types';
import { mutations } from '../../flows';
import flowsList from './fixtures';

describe('#mutations', () => {
  describe('#SET_FLOWS', () => {
    it('replaces the records collection', () => {
      const state = { records: [] };
      mutations[types.SET_FLOWS](state, flowsList);
      expect(state.records).toEqual(flowsList);
    });
  });

  describe('#ADD_FLOW', () => {
    it('appends a newly created flow', () => {
      const state = { records: [flowsList[0]] };
      mutations[types.ADD_FLOW](state, flowsList[1]);
      expect(state.records).toEqual([flowsList[0], flowsList[1]]);
    });
  });

  describe('#EDIT_FLOW', () => {
    it('updates the matching record by id', () => {
      const state = { records: [{ id: 1, name: 'old' }] };
      mutations[types.EDIT_FLOW](state, { id: 1, name: 'new' });
      expect(state.records[0].name).toBe('new');
    });

    it('leaves records untouched when the id is not found', () => {
      const state = { records: [{ id: 1, name: 'old' }] };
      mutations[types.EDIT_FLOW](state, { id: 99, name: 'new' });
      expect(state.records).toEqual([{ id: 1, name: 'old' }]);
    });
  });

  describe('#DELETE_FLOW', () => {
    it('removes the record with the given id', () => {
      const state = { records: [{ id: 1 }, { id: 2 }] };
      mutations[types.DELETE_FLOW](state, 1);
      expect(state.records).toEqual([{ id: 2 }]);
    });
  });

  describe('#SET_FLOW_UI_FLAG', () => {
    it('merges partial flags into uiFlags', () => {
      const state = { uiFlags: { isFetching: false, isCreating: false } };
      mutations[types.SET_FLOW_UI_FLAG](state, { isFetching: true });
      expect(state.uiFlags).toEqual({ isFetching: true, isCreating: false });
    });
  });
});
