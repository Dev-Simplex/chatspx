import types from '../../../mutation-types';
import { mutations } from '../../conversationStats';

describe('#mutations', () => {
  describe('#SET_CONV_TAB_META', () => {
    it('set conversation stats correctly', () => {
      const state = {};
      mutations[types.SET_CONV_TAB_META](state, {
        mine_count: 1,
        unassigned_count: 1,
        all_count: 2,
      });
      expect(state).toEqual({
        mineCount: 1,
        unAssignedCount: 1,
        allCount: 2,
        updatedOn: expect.any(Date),
      });
    });

    it('sets aiCount when ai_count is present in the payload', () => {
      const state = { aiCount: 0 };
      mutations[types.SET_CONV_TAB_META](state, {
        mine_count: 1,
        unassigned_count: 1,
        all_count: 2,
        ai_count: 3,
      });
      expect(state.aiCount).toEqual(3);
    });

    it('keeps the previous aiCount when ai_count is absent (partial payload guard)', () => {
      const state = { aiCount: 5 };
      mutations[types.SET_CONV_TAB_META](state, {
        mine_count: 1,
        unassigned_count: 1,
        all_count: 2,
      });
      expect(state.aiCount).toEqual(5);
    });

    it('falls back to zero when ai_count is present but null', () => {
      const state = { aiCount: 5 };
      mutations[types.SET_CONV_TAB_META](state, {
        mine_count: 1,
        unassigned_count: 1,
        all_count: 2,
        ai_count: null,
      });
      expect(state.aiCount).toEqual(0);
    });
  });
});
