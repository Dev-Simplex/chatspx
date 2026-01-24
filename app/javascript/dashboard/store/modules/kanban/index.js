import { getters } from './getters';
import { actions } from './actions';
import { mutations } from './mutations';

const state = {
  funnels: {},
  funnelStages: {},
  funnelItems: {},
  scheduledMessages: {},
  activeFunnelId: null,
  viewMode: 'kanban', // 'kanban' | 'list' | 'calendar'
  wahaInboxes: [],
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};


