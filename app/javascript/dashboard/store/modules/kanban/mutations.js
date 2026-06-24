import types from './mutation-types';
import camelcaseKeys from 'camelcase-keys';

const buildStageKey = (funnelId, stageId) =>
  `${Number(funnelId)}:${Number(stageId)}`;

const normalizeBrazilianPhone = phone => {
  const digits = String(phone || '').replace(/\D/g, '');
  if (!digits) return '';
  if (digits.startsWith('55') && digits.length === 12) {
    return `${digits.slice(0, 4)}9${digits.slice(4, 12)}`;
  }
  return digits;
};

const dedupeKeyForItem = item => {
  const conversation = item?.conversation || {};
  const contact =
    conversation?.contact || conversation?.meta?.sender || conversation?.sender;
  const phone = normalizeBrazilianPhone(
    contact?.phoneNumber || contact?.phone_number || ''
  );
  if (phone) return `phone:${phone}`;

  const contactId =
    conversation?.contactId ||
    conversation?.contact_id ||
    contact?.id ||
    conversation?.meta?.sender?.id ||
    conversation?.sender?.id;
  if (contactId) return `contact:${contactId}`;

  const conversationId =
    item?.conversationId ||
    item?.conversation_id ||
    conversation?.id ||
    conversation?.displayId ||
    conversation?.display_id;
  return `conversation:${conversationId || item?.id}`;
};

const itemRecency = item => {
  const conversation = item?.conversation || {};
  const lastActivityAt =
    conversation?.lastActivityAt ||
    conversation?.last_activity_at ||
    conversation?.updatedAt ||
    conversation?.updated_at;
  return new Date(
    lastActivityAt || item?.createdAt || item?.created_at || 0
  ).getTime();
};

const ensureStageContainers = ($state, stageKey) => {
  if (!$state.stageItems[stageKey]) {
    $state.stageItems[stageKey] = [];
  }
  if (!$state.stageMeta[stageKey]) {
    $state.stageMeta[stageKey] = {
      hasMore: false,
      nextCursor: null,
      isLoading: false,
      loaded: false,
      error: false,
      limit: null,
    };
  }
  if (!$state.stageDedupeIndex[stageKey]) {
    $state.stageDedupeIndex[stageKey] = {};
  }
};

const removeStageItemId = ($state, stageKey, itemId) => {
  if (!$state.stageItems[stageKey]) return;
  $state.stageItems[stageKey] = $state.stageItems[stageKey].filter(
    id => id !== itemId
  );
};

const removeItemFromAllStageIndexes = ($state, itemId) => {
  Object.keys($state.stageItems).forEach(stageKey => {
    removeStageItemId($state, stageKey, itemId);
  });

  Object.keys($state.stageDedupeIndex).forEach(stageKey => {
    const dedupeMap = $state.stageDedupeIndex[stageKey];
    Object.keys(dedupeMap).forEach(key => {
      if (dedupeMap[key] === itemId) {
        delete dedupeMap[key];
      }
    });
  });
};

const sortStageByRecency = ($state, stageKey) => {
  $state.stageItems[stageKey].sort((itemIdA, itemIdB) => {
    const itemA = $state.funnelItems[itemIdA];
    const itemB = $state.funnelItems[itemIdB];
    return itemRecency(itemB) - itemRecency(itemA);
  });
};

const assignItemToStage = ($state, rawItem) => {
  const item = camelcaseKeys(rawItem, { deep: true });
  const funnelId = item?.funnelId || item?.funnel_id;
  const stageId = item?.funnelStageId || item?.funnel_stage_id;
  if (!funnelId || !stageId || !item?.id) return;

  const stageKey = buildStageKey(funnelId, stageId);
  ensureStageContainers($state, stageKey);

  const dedupeKey = dedupeKeyForItem(item);
  const existingItemId = $state.stageDedupeIndex[stageKey][dedupeKey];
  const existingItem = existingItemId
    ? $state.funnelItems[existingItemId]
    : null;

  if (
    existingItemId &&
    existingItemId !== item.id &&
    existingItem &&
    itemRecency(existingItem) > itemRecency(item)
  ) {
    return;
  }

  if (existingItemId && existingItemId !== item.id) {
    removeStageItemId($state, stageKey, existingItemId);
    delete $state.funnelItems[existingItemId];
  }

  removeItemFromAllStageIndexes($state, item.id);
  $state.funnelItems[item.id] = item;

  if (!$state.stageItems[stageKey].includes(item.id)) {
    $state.stageItems[stageKey].push(item.id);
  }
  $state.stageDedupeIndex[stageKey][dedupeKey] = item.id;

  sortStageByRecency($state, stageKey);
};

const resetStageData = ($state, funnelId, stageId) => {
  const stageKey = buildStageKey(funnelId, stageId);
  ensureStageContainers($state, stageKey);

  $state.stageItems[stageKey].forEach(itemId => {
    delete $state.funnelItems[itemId];
  });
  $state.stageItems[stageKey] = [];
  $state.stageDedupeIndex[stageKey] = {};
};

const stageIdsFromItems = items => {
  const stageMap = {};
  items.forEach(rawItem => {
    const item = camelcaseKeys(rawItem, { deep: true });
    const funnelId = item?.funnelId || item?.funnel_id;
    const stageId = item?.funnelStageId || item?.funnel_stage_id;
    if (!funnelId || !stageId) return;

    const key = buildStageKey(funnelId, stageId);
    if (!stageMap[key]) {
      stageMap[key] = {
        funnelId: Number(funnelId),
        stageId: Number(stageId),
        items: [],
      };
    }
    stageMap[key].items.push(item);
  });
  return Object.values(stageMap);
};

const defaultScheduledMeta = () => ({
  hasMore: false,
  nextCursor: null,
  limit: 50,
  loaded: false,
  error: false,
});

const defaultViewFilters = () => ({
  query: '',
  stageIds: [],
  labelIds: [],
  assigneeId: null,
  status: 'all',
  priority: [],
});

const defaultViewBootstrap = () => ({
  kanbanLoaded: false,
  listLoaded: false,
  calendarLoaded: false,
  listQueueStageIds: [],
});

const normalizeFilterIdList = values => {
  if (!Array.isArray(values)) return [];
  return [
    ...new Set(
      values.map(value => Number(value)).filter(value => !Number.isNaN(value))
    ),
  ];
};

const scheduledTimestamp = scheduledMessage =>
  new Date(
    scheduledMessage?.scheduledAt || scheduledMessage?.scheduled_at || 0
  ).getTime() || 0;

const sortScheduledTimeline = $state => {
  if (!Array.isArray($state.scheduledTimeline)) {
    $state.scheduledTimeline = [];
  }
  $state.scheduledTimeline.sort((idA, idB) => {
    const itemA = $state.scheduledById[idA];
    const itemB = $state.scheduledById[idB];
    const diff = scheduledTimestamp(itemB) - scheduledTimestamp(itemA);
    if (diff !== 0) return diff;
    return Number(idB) - Number(idA);
  });
};

const upsertScheduledMessage = ($state, rawMessage) => {
  const normalized = camelcaseKeys(rawMessage, { deep: true });
  const messageId = normalized?.id;
  if (!messageId) return;

  if (!$state.scheduledById) {
    $state.scheduledById = {};
  }
  if (!$state.scheduledMessages) {
    $state.scheduledMessages = {};
  }
  if (!Array.isArray($state.scheduledTimeline)) {
    $state.scheduledTimeline = [];
  }

  $state.scheduledById[messageId] = {
    ...($state.scheduledById[messageId] || {}),
    ...normalized,
  };
  // Backward-compatibility for parts of the UI still reading scheduledMessages map.
  $state.scheduledMessages[messageId] = $state.scheduledById[messageId];

  if (!$state.scheduledTimeline.includes(messageId)) {
    $state.scheduledTimeline.push(messageId);
  }
};

const resetScheduledTimeline = $state => {
  $state.scheduledMessages = {};
  $state.scheduledById = {};
  $state.scheduledTimeline = [];
};

export const mutations = {
  [types.SET_KANBAN_UI_FLAG]($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },

  [types.SET_FUNNELS]($state, funnels) {
    if (Array.isArray(funnels)) {
      funnels.forEach(funnel => {
        $state.funnels[funnel.id] = camelcaseKeys(funnel, { deep: true });
      });
    }
  },

  [types.SET_FUNNEL]($state, funnel) {
    $state.funnels[funnel.id] = camelcaseKeys(funnel, { deep: true });
  },

  [types.ADD_FUNNEL]($state, funnel) {
    $state.funnels[funnel.id] = camelcaseKeys(funnel, { deep: true });
  },

  [types.UPDATE_FUNNEL]($state, funnel) {
    if ($state.funnels[funnel.id]) {
      $state.funnels[funnel.id] = {
        ...$state.funnels[funnel.id],
        ...camelcaseKeys(funnel, { deep: true }),
      };
    }
  },

  [types.DELETE_FUNNEL]($state, funnelId) {
    delete $state.funnels[funnelId];
    delete $state.funnelStages[funnelId];

    Object.keys($state.stageItems).forEach(stageKey => {
      if (stageKey.startsWith(`${Number(funnelId)}:`)) {
        $state.stageItems[stageKey].forEach(itemId => {
          delete $state.funnelItems[itemId];
        });
        delete $state.stageItems[stageKey];
        delete $state.stageMeta[stageKey];
        delete $state.stageDedupeIndex[stageKey];
      }
    });
  },

  [types.SET_FUNNEL_CUSTOM_FIELDS]($state, { funnelId, fields }) {
    const funnel = $state.funnels[funnelId];
    if (!funnel) return;
    funnel.customFields = Array.isArray(fields)
      ? fields.map(field => camelcaseKeys(field, { deep: true }))
      : [];
  },

  [types.SET_FUNNEL_STAGES]($state, { funnelId, stages }) {
    if (!funnelId) return;
    $state.funnelStages[funnelId] = {};

    if (Array.isArray(stages)) {
      stages.forEach(stage => {
        if (stage && stage.id) {
          const normalizedStage = camelcaseKeys(stage, { deep: true });
          $state.funnelStages[funnelId][stage.id] = normalizedStage;
          ensureStageContainers($state, buildStageKey(funnelId, stage.id));
        }
      });
    }
  },

  [types.ADD_FUNNEL_STAGE]($state, stage) {
    if (!stage || !stage.id) return;
    const stageData = camelcaseKeys(stage, { deep: true });
    const funnelId =
      stageData.funnelId ||
      stageData.funnel_id ||
      stage.funnel_id ||
      stage.funnelId;
    if (!funnelId) return;
    if (!$state.funnelStages[funnelId]) {
      $state.funnelStages[funnelId] = {};
    }
    stageData.funnelId = funnelId;
    stageData.funnel_id = funnelId;
    $state.funnelStages[funnelId][stageData.id] = stageData;
    ensureStageContainers($state, buildStageKey(funnelId, stageData.id));
  },

  [types.UPDATE_FUNNEL_STAGE]($state, stage) {
    const stageData = camelcaseKeys(stage, { deep: true });
    const funnelId = stageData.funnelId || stageData.funnel_id;
    if (!funnelId) return;
    if (!$state.funnelStages[funnelId]) {
      $state.funnelStages[funnelId] = {};
    }
    $state.funnelStages[funnelId][stageData.id] = {
      ...($state.funnelStages[funnelId]?.[stageData.id] || {}),
      ...stageData,
    };
  },

  [types.DELETE_FUNNEL_STAGE]($state, { funnelId, stageId }) {
    if ($state.funnelStages[funnelId]) {
      delete $state.funnelStages[funnelId][stageId];
    }

    const stageKey = buildStageKey(funnelId, stageId);
    if ($state.stageItems[stageKey]) {
      $state.stageItems[stageKey].forEach(itemId => {
        delete $state.funnelItems[itemId];
      });
    }
    delete $state.stageItems[stageKey];
    delete $state.stageMeta[stageKey];
    delete $state.stageDedupeIndex[stageKey];
  },

  [types.RESET_STAGE_ITEMS]($state, { funnelId, stageId }) {
    if (!funnelId || !stageId) return;
    resetStageData($state, funnelId, stageId);
  },

  [types.UPSERT_STAGE_ITEMS](
    $state,
    { funnelId, stageId, items = [], append = false }
  ) {
    if (!funnelId || !stageId) return;
    if (!append) {
      resetStageData($state, funnelId, stageId);
    }

    items.forEach(item => assignItemToStage($state, item));
  },

  [types.SET_STAGE_META]($state, { funnelId, stageId, meta }) {
    if (!funnelId || !stageId) return;
    const stageKey = buildStageKey(funnelId, stageId);
    ensureStageContainers($state, stageKey);
    $state.stageMeta[stageKey] = {
      ...$state.stageMeta[stageKey],
      ...meta,
    };
  },

  [types.SET_FUNNEL_ITEMS]($state, items) {
    if (!Array.isArray(items)) return;

    const grouped = stageIdsFromItems(items);
    grouped.forEach(group => {
      resetStageData($state, group.funnelId, group.stageId);
      group.items.forEach(item => assignItemToStage($state, item));
    });
  },

  [types.MERGE_FUNNEL_ITEMS]($state, items) {
    if (!Array.isArray(items)) return;

    items.forEach(item => assignItemToStage($state, item));
  },

  [types.ADD_FUNNEL_ITEM]($state, item) {
    assignItemToStage($state, item);
  },

  [types.UPDATE_FUNNEL_ITEM]($state, item) {
    assignItemToStage($state, item);
  },

  [types.UPDATE_ITEM_CONVERSATION](
    $state,
    { displayId, id, patch, bumpRecency }
  ) {
    if (!patch || typeof patch !== 'object') return;

    const targetDisplay = displayId != null ? String(displayId) : null;
    const targetId = id != null ? String(id) : null;

    let matchedItemId = null;
    const itemMatches = item => {
      const conv = item?.conversation;
      if (!conv) return false;
      const convDisplay = String(
        conv?.displayId ??
          conv?.display_id ??
          item?.conversationId ??
          conv?.id ??
          ''
      );
      if (targetDisplay && convDisplay === targetDisplay) return true;
      // Fallback by numeric conversation id when displayId did not match.
      if (targetId) {
        const convId = String(conv?.id ?? item?.conversationId ?? '');
        if (convId && convId === targetId) return true;
      }
      return false;
    };

    const funnelItems = $state.funnelItems || {};
    const itemIds = Object.keys(funnelItems);
    for (let i = 0; i < itemIds.length; i += 1) {
      const itemId = itemIds[i];
      if (itemMatches(funnelItems[itemId])) {
        matchedItemId = itemId;
        break;
      }
    }

    if (matchedItemId == null) return;

    const targetItem = $state.funnelItems[matchedItemId];
    if (!targetItem || !targetItem.conversation) return;

    // Merge the patch in place, preserving the rest of the conversation.
    targetItem.conversation = {
      ...targetItem.conversation,
      ...patch,
    };

    if (!bumpRecency) return;

    // Re-sort only the stage(s) that hold this item by recency.
    Object.keys($state.stageItems || {}).forEach(stageKey => {
      if (($state.stageItems[stageKey] || []).includes(matchedItemId)) {
        if (typeof sortStageByRecency === 'function') {
          sortStageByRecency($state, stageKey);
        } else {
          $state.stageItems[stageKey].sort((itemIdA, itemIdB) => {
            const a = new Date(
              $state.funnelItems[itemIdA]?.conversation?.lastActivityAt || 0
            ).getTime();
            const b = new Date(
              $state.funnelItems[itemIdB]?.conversation?.lastActivityAt || 0
            ).getTime();
            return b - a;
          });
        }
      }
    });
  },

  [types.DELETE_FUNNEL_ITEM]($state, itemId) {
    removeItemFromAllStageIndexes($state, itemId);
    delete $state.funnelItems[itemId];
  },

  [types.SET_SCHEDULED_MESSAGES]($state, messages) {
    resetScheduledTimeline($state);
    if (Array.isArray(messages)) {
      messages.forEach(message => upsertScheduledMessage($state, message));
    }
    sortScheduledTimeline($state);
  },

  [types.RESET_SCHEDULED_TIMELINE]($state) {
    resetScheduledTimeline($state);
    $state.scheduledMeta = defaultScheduledMeta();
  },

  [types.UPSERT_SCHEDULED_MESSAGES_PAGE](
    $state,
    { messages = [], append = false }
  ) {
    if (!append) {
      resetScheduledTimeline($state);
    }

    messages.forEach(message => upsertScheduledMessage($state, message));
    sortScheduledTimeline($state);
  },

  [types.SET_SCHEDULED_META]($state, meta = {}) {
    $state.scheduledMeta = {
      ...defaultScheduledMeta(),
      ...$state.scheduledMeta,
      ...meta,
    };
  },

  [types.SET_SCHEDULED_FILTERS]($state, filters = {}) {
    $state.scheduledFilters = {
      ...$state.scheduledFilters,
      ...filters,
    };
  },

  [types.SET_SCHEDULED_UI]($state, payload = {}) {
    $state.scheduledUi = {
      ...$state.scheduledUi,
      ...payload,
    };
  },

  [types.ADD_SCHEDULED_MESSAGE]($state, message) {
    upsertScheduledMessage($state, message);
    sortScheduledTimeline($state);
  },

  [types.UPDATE_SCHEDULED_MESSAGE]($state, message) {
    upsertScheduledMessage($state, message);
    sortScheduledTimeline($state);
  },

  [types.DELETE_SCHEDULED_MESSAGE]($state, messageId) {
    delete $state.scheduledMessages[messageId];
    delete $state.scheduledById[messageId];
    $state.scheduledTimeline = $state.scheduledTimeline.filter(
      id => id !== messageId
    );
  },

  [types.SET_ACTIVE_FUNNEL_ID]($state, funnelId) {
    $state.activeFunnelId = funnelId;
  },

  [types.SET_VIEW_MODE]($state, mode) {
    $state.viewMode = mode;
  },

  [types.SET_SAVED_VIEWS]($state, views) {
    $state.savedViews = Array.isArray(views) ? views : [];
  },

  [types.ADD_SAVED_VIEW]($state, view) {
    if (!view?.id) return;
    $state.savedViews = [
      ...$state.savedViews.filter(v => v.id !== view.id),
      view,
    ];
  },

  [types.UPDATE_SAVED_VIEW]($state, view) {
    if (!view?.id) return;
    $state.savedViews = $state.savedViews.map(v =>
      v.id === view.id ? view : v
    );
  },

  [types.DELETE_SAVED_VIEW]($state, viewId) {
    $state.savedViews = $state.savedViews.filter(v => v.id !== viewId);
  },

  [types.SET_VIEW_FILTERS]($state, filters = {}) {
    $state.viewFilters = {
      ...defaultViewFilters(),
      ...$state.viewFilters,
      ...filters,
      query: String(
        filters.query ?? $state.viewFilters?.query ?? ''
      ).trimStart(),
      stageIds: normalizeFilterIdList(
        filters.stageIds ?? $state.viewFilters?.stageIds
      ),
      labelIds: normalizeFilterIdList(
        filters.labelIds ?? $state.viewFilters?.labelIds
      ),
      status: filters.status || $state.viewFilters?.status || 'all',
      priority: Array.isArray(filters.priority)
        ? [...filters.priority]
        : $state.viewFilters?.priority || [],
    };
  },

  [types.RESET_VIEW_FILTERS]($state) {
    $state.viewFilters = defaultViewFilters();
  },

  [types.SET_VIEW_BOOTSTRAP]($state, payload = {}) {
    $state.viewBootstrap = {
      ...defaultViewBootstrap(),
      ...$state.viewBootstrap,
      ...payload,
      listQueueStageIds: normalizeFilterIdList(
        payload.listQueueStageIds ?? $state.viewBootstrap?.listQueueStageIds
      ),
    };
  },

  [types.RESET_VIEW_BOOTSTRAP]($state) {
    $state.viewBootstrap = defaultViewBootstrap();
  },

  [types.SET_WAHA_INBOXES]($state, inboxes) {
    $state.wahaInboxes = Array.isArray(inboxes)
      ? inboxes.map(inbox => camelcaseKeys(inbox, { deep: true }))
      : [];
  },
};
