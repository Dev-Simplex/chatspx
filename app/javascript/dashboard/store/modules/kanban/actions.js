import types from './mutation-types';
import KanbanAPI from '../../../api/kanban';

const DEFAULT_STAGE_PAGE_LIMIT = 30;
const DEFAULT_SCHEDULED_PAGE_LIMIT = 50;
const stageRequestLocks = new Map();
const scheduledRequestLocks = new Map();

const defaultScheduledWindow = () => {
  const now = new Date();
  const past = new Date(now);
  past.setDate(past.getDate() - 30);
  past.setHours(0, 0, 0, 0);
  const future = new Date(now);
  future.setDate(future.getDate() + 30);
  future.setHours(23, 59, 59, 999);
  return {
    from: past.toISOString(),
    to: future.toISOString(),
  };
};

const resolveScheduledMessagesQuery = (payload, fallbackFilters = {}) => {
  const fallbackWindow = defaultScheduledWindow();

  if (payload && typeof payload === 'object' && !Array.isArray(payload)) {
    const resolvedMode = Object.prototype.hasOwnProperty.call(payload, 'mode')
      ? payload.mode
      : 'cursor';

    return {
      mode: resolvedMode,
      conversationId:
        payload.conversationId ?? fallbackFilters.conversationId ?? null,
      status: payload.status || fallbackFilters.status || 'all',
      from: payload.from || fallbackFilters.from || fallbackWindow.from,
      to: payload.to || fallbackFilters.to || fallbackWindow.to,
      limit:
        payload.limit != null
          ? Number(payload.limit)
          : Number(fallbackFilters.limit || DEFAULT_SCHEDULED_PAGE_LIMIT),
      cursor: payload.cursor || null,
      append: Boolean(payload.append),
    };
  }

  return {
    conversationId: payload || null,
    mode: 'cursor',
    status: fallbackFilters.status || 'all',
    from: fallbackFilters.from || fallbackWindow.from,
    to: fallbackFilters.to || fallbackWindow.to,
    limit: Number(fallbackFilters.limit || DEFAULT_SCHEDULED_PAGE_LIMIT),
    cursor: null,
    append: false,
  };
};

const isResolvedStage = stage => {
  const automationType = stage?.automationType || stage?.automation_type;
  if (automationType === 'resolved') return true;
  const name = (stage?.name || '').toLowerCase();
  return name === 'resolved' || name === 'resolvido';
};

const shouldUseCursorLoading = ({ rootState, rootGetters }) => {
  const accountId = Number(rootState?.route?.params?.accountId);
  const featureGetter = rootGetters?.['accounts/isFeatureEnabledonAccount'];

  if (typeof featureGetter === 'function' && accountId) {
    return featureGetter(accountId, 'kanban_cursor_loading');
  }

  return true;
};

const shouldUseKanbanUxV2 = ({ rootState, rootGetters }) => {
  const accountId = Number(rootState?.route?.params?.accountId);
  const featureGetter = rootGetters?.['accounts/isFeatureEnabledonAccount'];

  if (typeof featureGetter === 'function' && accountId) {
    return featureGetter(accountId, 'kanban_ux_v2');
  }

  return true;
};

const parseStagePayload = response => {
  const data = response?.data;
  if (Array.isArray(data)) return data;
  if (data?.stages && Array.isArray(data.stages)) return data.stages;
  if (data?.funnel_stages && Array.isArray(data.funnel_stages)) {
    return data.funnel_stages;
  }
  return [];
};

const parseCursorResponse = (response, fallbackLimit) => {
  const data = response?.data;
  if (Array.isArray(data)) {
    return {
      items: data,
      meta: {
        hasMore: false,
        nextCursor: null,
        limit: fallbackLimit,
      },
    };
  }

  return {
    items: Array.isArray(data?.payload) ? data.payload : [],
    meta: {
      hasMore: Boolean(data?.meta?.has_more),
      nextCursor: data?.meta?.next_cursor || null,
      limit: Number(data?.meta?.limit || fallbackLimit),
      stageId: data?.meta?.stage_id,
    },
  };
};

const parseScheduledResponse = (response, fallbackLimit) => {
  const data = response?.data;
  if (Array.isArray(data)) {
    return {
      items: data,
      meta: {
        hasMore: false,
        nextCursor: null,
        limit: fallbackLimit,
        status: 'all',
        from: null,
        to: null,
      },
    };
  }

  return {
    items: Array.isArray(data?.payload) ? data.payload : [],
    meta: {
      hasMore: Boolean(data?.meta?.has_more),
      nextCursor: data?.meta?.next_cursor || null,
      limit: Number(data?.meta?.limit || fallbackLimit),
      status: data?.meta?.status || 'all',
      from: data?.meta?.from || null,
      to: data?.meta?.to || null,
    },
  };
};

const defaultViewFilters = () => ({
  query: '',
  stageIds: [],
  labelIds: [],
  assigneeId: null,
  status: 'all',
});

const isViewBootstrapped = (viewBootstrap, view) => {
  if (view === 'kanban') return Boolean(viewBootstrap?.kanbanLoaded);
  if (view === 'list') return Boolean(viewBootstrap?.listLoaded);
  if (view === 'calendar') return Boolean(viewBootstrap?.calendarLoaded);
  return false;
};

const sanitizeStageQueue = stageIds => [
  ...new Set(
    (stageIds || []).map(id => Number(id)).filter(id => !Number.isNaN(id))
  ),
];

export const actions = {
  async fetchFunnels({ commit }) {
    commit(types.SET_KANBAN_UI_FLAG, { isFetching: true });
    try {
      const response = await KanbanAPI.getFunnels();
      commit(types.SET_FUNNELS, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isFetching: false });
    }
  },

  async fetchFunnel({ commit }, funnelId) {
    commit(types.SET_KANBAN_UI_FLAG, { isFetching: true });
    try {
      const response = await KanbanAPI.getFunnel(funnelId);
      commit(types.SET_FUNNEL, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isFetching: false });
    }
  },

  async createFunnel({ commit }, data) {
    commit(types.SET_KANBAN_UI_FLAG, { isCreating: true });
    try {
      const response = await KanbanAPI.createFunnel(data);
      commit(types.ADD_FUNNEL, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isCreating: false });
    }
  },

  async updateFunnel({ commit }, { funnelId, data }) {
    commit(types.SET_KANBAN_UI_FLAG, { isUpdating: true });
    try {
      const response = await KanbanAPI.updateFunnel(funnelId, data);
      commit(types.UPDATE_FUNNEL, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isUpdating: false });
    }
  },

  async deleteFunnel({ commit }, funnelId) {
    commit(types.SET_KANBAN_UI_FLAG, { isDeleting: true });
    try {
      await KanbanAPI.deleteFunnel(funnelId);
      commit(types.DELETE_FUNNEL, funnelId);
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isDeleting: false });
    }
  },

  async reorderStages({ commit }, { funnelId, stageIds }) {
    await KanbanAPI.reorderStages(funnelId, stageIds);
    const response = await KanbanAPI.getFunnelStages(funnelId);
    commit(types.SET_FUNNEL_STAGES, {
      funnelId,
      stages: parseStagePayload(response),
    });
  },

  async fetchFunnelStages({ commit }, funnelId) {
    if (!funnelId) return { data: [] };

    const response = await KanbanAPI.getFunnelStages(funnelId);
    const stages = parseStagePayload(response);
    commit(types.SET_FUNNEL_STAGES, { funnelId, stages });
    return { data: stages };
  },

  async createStage({ commit }, { funnelId, data }) {
    const response = await KanbanAPI.createStage(funnelId, data);
    commit(types.ADD_FUNNEL_STAGE, response.data);
    return response;
  },

  async updateStage({ commit }, { funnelId, stageId, data }) {
    const response = await KanbanAPI.updateStage(funnelId, stageId, data);
    commit(types.UPDATE_FUNNEL_STAGE, {
      ...response.data,
      funnel_id: response.data?.funnel_id || funnelId,
    });
    return response;
  },

  async deleteStage({ commit }, { funnelId, stageId }) {
    await KanbanAPI.deleteStage(funnelId, stageId);
    commit(types.DELETE_FUNNEL_STAGE, { funnelId, stageId });
  },

  async fetchFunnelItemsPage(
    { commit, rootState, rootGetters, getters },
    {
      funnelId,
      stageId,
      excludeAutomationType,
      cursor = null,
      limit = DEFAULT_STAGE_PAGE_LIMIT,
      append = false,
    }
  ) {
    if (!funnelId || !stageId) {
      return { data: { payload: [], meta: {} } };
    }

    const requestKey = `${Number(funnelId)}:${Number(stageId)}`;
    const inFlightRequest = stageRequestLocks.get(requestKey);
    if (inFlightRequest) return inFlightRequest;

    const meta = getters.getStageMeta(funnelId, stageId);
    if (meta?.isLoading) return null;

    const requestPromise = (async () => {
      commit(types.SET_STAGE_META, {
        funnelId,
        stageId,
        meta: { isLoading: true, error: false },
      });

      try {
        const useCursor = shouldUseCursorLoading({ rootState, rootGetters });
        const options = {
          stageId,
          excludeAutomationType,
        };

        if (useCursor) {
          options.mode = 'cursor';
          options.limit = limit;
          options.cursor = cursor;
        }

        const response = await KanbanAPI.getFunnelItems(funnelId, options);
        const parsed = parseCursorResponse(response, limit);

        commit(types.UPSERT_STAGE_ITEMS, {
          funnelId,
          stageId,
          items: parsed.items,
          append,
        });
        commit(types.SET_STAGE_META, {
          funnelId,
          stageId,
          meta: {
            hasMore: parsed.meta.hasMore,
            nextCursor: parsed.meta.nextCursor,
            limit: parsed.meta.limit,
            loaded: true,
            isLoading: false,
            error: false,
          },
        });

        return response;
      } catch (error) {
        commit(types.SET_STAGE_META, {
          funnelId,
          stageId,
          meta: { isLoading: false, error: true },
        });
        throw error;
      } finally {
        stageRequestLocks.delete(requestKey);
      }
    })();

    stageRequestLocks.set(requestKey, requestPromise);
    return requestPromise;
  },

  async loadNextStagePage(
    { dispatch, getters },
    {
      funnelId,
      stageId,
      excludeAutomationType,
      limit = DEFAULT_STAGE_PAGE_LIMIT,
    }
  ) {
    const meta = getters.getStageMeta(funnelId, stageId);
    if (!meta?.hasMore || meta?.isLoading) return null;

    return dispatch('fetchFunnelItemsPage', {
      funnelId,
      stageId,
      excludeAutomationType,
      cursor: meta.nextCursor,
      limit,
      append: true,
    });
  },

  async bootstrapFunnel(
    { commit, getters, dispatch },
    {
      funnelId,
      excludeAutomationType = 'resolved',
      limit = DEFAULT_STAGE_PAGE_LIMIT,
      includeResolved = false,
    }
  ) {
    if (!funnelId) return;

    commit(types.SET_KANBAN_UI_FLAG, { isFetching: true });
    try {
      const stages = getters.getFunnelStages(funnelId);
      if (!Array.isArray(stages) || stages.length === 0) return;

      const stagesToLoad = includeResolved
        ? stages
        : stages.filter(stage => !isResolvedStage(stage));

      await Promise.all(
        stagesToLoad.map(stage =>
          dispatch('fetchFunnelItemsPage', {
            funnelId,
            stageId: stage.id,
            excludeAutomationType,
            limit,
            append: false,
          })
        )
      );
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isFetching: false });
    }
  },

  async fetchFunnelItems(
    { dispatch, getters, commit },
    {
      funnelId,
      stageId = null,
      excludeAutomationType,
      page = null,
      perPage = null,
      merge = false,
    }
  ) {
    if (!funnelId) return { data: [] };

    if (page != null || perPage != null) {
      const response = await KanbanAPI.getFunnelItems(funnelId, {
        stageId,
        excludeAutomationType,
        page,
        perPage,
      });
      const items = Array.isArray(response.data) ? response.data : [];
      if (stageId) {
        commit(types.UPSERT_STAGE_ITEMS, {
          funnelId,
          stageId,
          items,
          append: merge,
        });
        commit(types.SET_STAGE_META, {
          funnelId,
          stageId,
          meta: {
            hasMore: items.length >= (perPage || DEFAULT_STAGE_PAGE_LIMIT),
            nextCursor: null,
            limit: perPage || DEFAULT_STAGE_PAGE_LIMIT,
            loaded: true,
            isLoading: false,
            error: false,
          },
        });
      } else {
        commit(
          merge ? types.MERGE_FUNNEL_ITEMS : types.SET_FUNNEL_ITEMS,
          items
        );
      }
      return { ...response, data: items };
    }

    if (stageId) {
      const meta = getters.getStageMeta(funnelId, stageId);
      return dispatch('fetchFunnelItemsPage', {
        funnelId,
        stageId,
        excludeAutomationType,
        cursor: merge ? meta?.nextCursor : null,
        limit: perPage || DEFAULT_STAGE_PAGE_LIMIT,
        append: merge,
      });
    }

    await dispatch('bootstrapFunnel', {
      funnelId,
      excludeAutomationType,
      limit: perPage || DEFAULT_STAGE_PAGE_LIMIT,
      includeResolved: !excludeAutomationType,
    });
    return { data: [] };
  },

  async createItem({ commit }, { funnelId, data }) {
    const response = await KanbanAPI.createItem(funnelId, data);
    commit(types.ADD_FUNNEL_ITEM, response.data);
    return response;
  },

  async updateItem({ commit }, { funnelId, itemId, data }) {
    const response = await KanbanAPI.updateItem(funnelId, itemId, data);
    commit(types.UPDATE_FUNNEL_ITEM, response.data);
    return response;
  },

  async deleteItem({ commit }, { funnelId, itemId }) {
    await KanbanAPI.deleteItem(funnelId, itemId);
    commit(types.DELETE_FUNNEL_ITEM, itemId);
  },

  // Bridges the central websocket events to the kanban store so cards reflect
  // status/assignee/priority/labels/new-message changes in real time without a
  // full reload. Self-protecting: bails out cheaply when the board is inactive
  // or the payload is unusable, and never touches stage placement (the realtime
  // conversation payload carries no funnel_stage_id).
  syncConversationFromRealtime({ state, commit }, data) {
    try {
      if (!state?.activeFunnelId) return;
      if (!data || typeof data !== 'object') return;

      const displayId = data?.conversation_id ?? data?.id;
      if (displayId == null || displayId === '') return;

      const patch = {};

      // message.created carries the message itself, not a conversation object.
      const isMessageCreated =
        data?.message_type !== undefined &&
        (data?.content !== undefined || data?.created_at !== undefined);

      if (data?.status !== undefined) {
        patch.status = data.status;
      }

      const hasAssignee =
        data?.assignee_id !== undefined ||
        data?.meta?.assignee !== undefined ||
        data?.meta?.assignee?.id !== undefined;
      if (hasAssignee) {
        patch.assigneeId =
          data?.assignee_id ?? data?.meta?.assignee?.id ?? null;
        if (data?.meta?.assignee !== undefined) {
          patch.meta = {
            ...(data?.meta || {}),
            assignee: data?.meta?.assignee ?? null,
          };
        }
      }

      if (data?.priority !== undefined) {
        patch.priority = data.priority;
      }

      if (data?.labels !== undefined) {
        patch.labels = data.labels;
      }

      let bumpRecency = false;

      if (isMessageCreated) {
        const lastActivityAt =
          data?.conversation?.last_activity_at ?? data?.created_at;
        if (lastActivityAt !== undefined && lastActivityAt !== null) {
          patch.lastActivityAt = lastActivityAt;
        }
        if (data?.content !== undefined || data?.created_at !== undefined) {
          patch.lastMessage = {
            content: data?.content,
            created_at: data?.created_at,
          };
        }
        bumpRecency = true;
      } else if (data?.last_activity_at !== undefined) {
        patch.lastActivityAt = data.last_activity_at;
      }

      if (Object.keys(patch).length === 0) return;

      commit(types.UPDATE_ITEM_CONVERSATION, {
        displayId,
        // For message.created, data.id is the MESSAGE id (not a conversation
        // id) — don't let the numeric fallback match an unrelated card.
        id: isMessageCreated ? null : data?.id,
        patch,
        bumpRecency,
      });
    } catch (error) {
      // Realtime sync is best-effort; never let it break websocket handling.
    }
  },

  async bulkMoveItems({ dispatch }, { funnelId, conversationIds, stageId }) {
    await KanbanAPI.bulkMoveItems(funnelId, conversationIds, stageId);
    await dispatch('bootstrapFunnel', {
      funnelId,
      excludeAutomationType: 'resolved',
      limit: DEFAULT_STAGE_PAGE_LIMIT,
    });
  },

  setViewFilters({ commit }, filters = {}) {
    commit(types.SET_VIEW_FILTERS, filters);
  },

  resetViewFilters({ commit }) {
    commit(types.RESET_VIEW_FILTERS);
  },

  resetViewBootstrap({ commit }) {
    commit(types.RESET_VIEW_BOOTSTRAP);
  },

  async bootstrapListView(
    { commit, dispatch, getters },
    { funnelId, force = false, limit = 15 } = {}
  ) {
    if (!funnelId) return;

    const stages = getters
      .getFunnelStages(funnelId)
      .filter(stage => !isResolvedStage(stage));
    if (!stages.length) {
      commit(types.SET_VIEW_BOOTSTRAP, {
        listLoaded: true,
        listQueueStageIds: [],
      });
      return;
    }

    const stageIds = stages.map(stage => Number(stage.id)).filter(Boolean);

    if (force || !getters.getViewBootstrap?.listLoaded) {
      await Promise.all(
        stageIds.map(stageId =>
          dispatch('fetchFunnelItemsPage', {
            funnelId,
            stageId,
            excludeAutomationType: 'resolved',
            limit,
            append: false,
          })
        )
      );
    }

    const queue = sanitizeStageQueue(
      stageIds.filter(
        stageId => getters.getStageMeta(funnelId, stageId)?.hasMore
      )
    );

    commit(types.SET_VIEW_BOOTSTRAP, {
      listLoaded: true,
      listQueueStageIds: queue,
    });
  },

  async loadMoreListQueue(
    { commit, dispatch, getters },
    { funnelId, limit = 15 } = {}
  ) {
    if (!funnelId) return null;

    const currentQueue = sanitizeStageQueue(
      getters.getViewBootstrap?.listQueueStageIds || []
    );
    if (!currentQueue.length) return null;

    const stageId = currentQueue[0];
    await dispatch('loadNextStagePage', {
      funnelId,
      stageId,
      excludeAutomationType: 'resolved',
      limit,
    });

    const stageMeta = getters.getStageMeta(funnelId, stageId);
    const nextQueue = stageMeta?.hasMore
      ? [...currentQueue.slice(1), stageId]
      : currentQueue.slice(1);

    commit(types.SET_VIEW_BOOTSTRAP, {
      listQueueStageIds: sanitizeStageQueue(nextQueue),
    });

    return stageId;
  },

  async bootstrapView(
    { commit, dispatch, getters },
    { view, funnelId, force = false } = {}
  ) {
    if (!funnelId) return;
    const viewName = view || getters.getViewMode;
    if (!viewName) return;

    const alreadyLoaded = isViewBootstrapped(
      getters.getViewBootstrap,
      viewName
    );
    if (alreadyLoaded && !force) return;

    if (viewName === 'kanban') {
      await dispatch('bootstrapFunnel', {
        funnelId,
        excludeAutomationType: 'resolved',
      });
      commit(types.SET_VIEW_BOOTSTRAP, { kanbanLoaded: true });
      return;
    }

    if (viewName === 'list') {
      await dispatch('bootstrapListView', {
        funnelId,
        force,
      });
      return;
    }

    if (viewName === 'calendar') {
      await dispatch('bootstrapScheduledTimeline', {
        status: 'all',
      });
      commit(types.SET_VIEW_BOOTSTRAP, { calendarLoaded: true });
    }
  },

  async fetchScheduledMessagesPage(
    { commit, getters, rootState, rootGetters },
    payload = null
  ) {
    const uiFlags = getters.getUIFlags || {};
    if (uiFlags.isCreating || uiFlags.isUpdating) {
      return { data: { payload: [], meta: {} } };
    }

    const currentFilters = getters.getScheduledFilters || {};
    const query = resolveScheduledMessagesQuery(payload, currentFilters);
    const useKanbanUxV2 = shouldUseKanbanUxV2({ rootState, rootGetters });
    const requestedMode =
      query.mode === undefined ? 'cursor' : query.mode || null;
    const effectiveMode = useKanbanUxV2 ? requestedMode || 'cursor' : null;
    const requestKey = JSON.stringify({
      mode: effectiveMode,
      status: query.status,
      from: query.from,
      to: query.to,
      limit: query.limit,
      cursor: query.cursor,
      conversationId: query.conversationId,
      append: query.append,
    });

    const inFlightRequest = scheduledRequestLocks.get(requestKey);
    if (inFlightRequest) return inFlightRequest;

    const requestPromise = (async () => {
      commit(types.SET_KANBAN_UI_FLAG, { isFetchingScheduledMessages: true });

      if (!query.append) {
        commit(types.SET_SCHEDULED_FILTERS, {
          status: query.status,
          conversationId: query.conversationId,
          from: query.from,
          to: query.to,
          limit: query.limit,
        });
      }

      try {
        const response = await KanbanAPI.getScheduledMessages({
          mode: effectiveMode,
          status: query.status,
          from: query.from,
          to: query.to,
          limit: query.limit,
          cursor: query.cursor,
          conversationId: query.conversationId,
        });

        const parsed = parseScheduledResponse(response, query.limit);
        commit(types.UPSERT_SCHEDULED_MESSAGES_PAGE, {
          messages: parsed.items,
          append: query.append,
        });
        commit(types.SET_SCHEDULED_META, {
          hasMore: parsed.meta.hasMore,
          nextCursor: parsed.meta.nextCursor,
          limit: parsed.meta.limit,
          loaded: true,
          error: false,
          status: parsed.meta.status,
          from: parsed.meta.from || query.from,
          to: parsed.meta.to || query.to,
        });
        commit(types.SET_SCHEDULED_UI, { lastFetchedAt: Date.now() });
        return response;
      } catch (error) {
        commit(types.SET_SCHEDULED_META, { loaded: true, error: true });
        return { data: { payload: [], meta: {} } };
      } finally {
        commit(types.SET_KANBAN_UI_FLAG, {
          isFetchingScheduledMessages: false,
        });
        scheduledRequestLocks.delete(requestKey);
      }
    })();

    scheduledRequestLocks.set(requestKey, requestPromise);
    return requestPromise;
  },

  async bootstrapScheduledTimeline({ dispatch }, payload = null) {
    return dispatch('fetchScheduledMessagesPage', {
      ...resolveScheduledMessagesQuery(payload),
      append: false,
      cursor: null,
    });
  },

  async loadMoreScheduledMessages({ dispatch, getters }, payload = {}) {
    const meta = getters.getScheduledMeta;
    if (!meta?.hasMore || !meta?.nextCursor) return null;

    const filters = getters.getScheduledFilters;
    return dispatch('fetchScheduledMessagesPage', {
      ...filters,
      ...payload,
      limit: payload?.limit || meta.limit || DEFAULT_SCHEDULED_PAGE_LIMIT,
      cursor: meta.nextCursor,
      append: true,
    });
  },

  async refreshPendingStatuses({ dispatch, getters }, payload = {}) {
    const filters = getters.getScheduledFilters;
    return dispatch('fetchScheduledMessagesPage', {
      ...filters,
      ...payload,
      cursor: null,
      append: false,
    });
  },

  async fetchScheduledMessages({ dispatch, getters }, payload = null) {
    const filters = getters.getScheduledFilters;
    const query = resolveScheduledMessagesQuery(payload, filters);
    return dispatch('fetchScheduledMessagesPage', {
      ...query,
      mode: query.mode || 'cursor',
      append: false,
      cursor: null,
    });
  },

  async createScheduledMessage({ commit }, data) {
    commit(types.SET_KANBAN_UI_FLAG, { isCreating: true });
    try {
      const response = await KanbanAPI.createScheduledMessage(data);
      commit(types.ADD_SCHEDULED_MESSAGE, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isCreating: false });
    }
  },

  async updateScheduledMessage({ commit }, { messageId, data }) {
    commit(types.SET_KANBAN_UI_FLAG, { isUpdating: true });
    try {
      const response = await KanbanAPI.updateScheduledMessage(messageId, data);
      commit(types.UPDATE_SCHEDULED_MESSAGE, response.data);
      return response;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isUpdating: false });
    }
  },

  async deleteScheduledMessage({ commit }, messageId) {
    commit(types.SET_KANBAN_UI_FLAG, { isDeleting: true });
    try {
      await KanbanAPI.deleteScheduledMessage(messageId);
      commit(types.DELETE_SCHEDULED_MESSAGE, messageId);
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isDeleting: false });
    }
  },

  async fetchWahaInboxes({ commit }) {
    const response = await KanbanAPI.getWahaInboxes();
    const data = response?.data;
    const inboxes = Array.isArray(data) ? data : data?.payload || [];
    commit(types.SET_WAHA_INBOXES, inboxes);
    return { ...response, data: inboxes };
  },

  setActiveFunnelId({ commit }, funnelId) {
    commit(types.SET_ACTIVE_FUNNEL_ID, funnelId);
    commit(types.RESET_VIEW_BOOTSTRAP);
    commit(types.SET_VIEW_FILTERS, {
      ...defaultViewFilters(),
    });
  },

  setViewMode({ commit }, mode) {
    commit(types.SET_VIEW_MODE, mode);
  },
};
