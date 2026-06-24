import { getters } from './getters';
import { actions } from './actions';
import { mutations } from './mutations';

const state = {
  funnels: {},
  funnelStages: {},
  funnelItems: {},
  stageItems: {},
  stageMeta: {},
  stageDedupeIndex: {},
  scheduledMessages: {},
  scheduledById: {},
  scheduledTimeline: [],
  scheduledMeta: {
    hasMore: false,
    nextCursor: null,
    limit: 50,
    loaded: false,
    error: false,
  },
  scheduledFilters: {
    status: 'all',
    conversationId: null,
    from: null,
    to: null,
  },
  scheduledUi: {
    lastFetchedAt: null,
  },
  activeFunnelId: null,
  viewMode: 'kanban',
  viewFilters: {
    query: '',
    stageIds: [],
    labelIds: [],
    assigneeId: null,
    status: 'all',
    priority: [],
  },
  savedViews: [],
  viewBootstrap: {
    kanbanLoaded: false,
    listLoaded: false,
    calendarLoaded: false,
    listQueueStageIds: [],
  },
  wahaInboxes: [],
  uiFlags: {
    isFetching: false,
    isFetchingScheduledMessages: false,
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
