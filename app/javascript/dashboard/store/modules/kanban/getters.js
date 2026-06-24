import camelcaseKeys from 'camelcase-keys';

const buildStageKey = (funnelId, stageId) =>
  `${Number(funnelId)}:${Number(stageId)}`;

const sortByPositionAndCreatedAt = (a, b) => {
  const posA = a.position ?? 0;
  const posB = b.position ?? 0;
  if (posA !== posB) {
    return posA - posB;
  }
  const createdA = new Date(a.createdAt || a.created_at || 0).getTime() || 0;
  const createdB = new Date(b.createdAt || b.created_at || 0).getTime() || 0;
  return createdA - createdB;
};

export const getters = {
  getFunnels($state) {
    const funnels = Object.values($state.funnels);
    return funnels.sort((a, b) => {
      const aIsDefault = a.teamId == null && a.team_id == null;
      const bIsDefault = b.teamId == null && b.team_id == null;
      if (aIsDefault !== bIsDefault) {
        return aIsDefault ? -1 : 1;
      }
      return sortByPositionAndCreatedAt(a, b);
    });
  },

  getFunnel: $state => id => {
    return camelcaseKeys($state.funnels[id] || {}, { deep: true });
  },

  // Custom field definitions for a funnel (already camelCased in state).
  getFunnelCustomFields: $state => funnelId => {
    if (funnelId == null) return [];
    const fields = $state.funnels[funnelId]?.customFields;
    if (!Array.isArray(fields)) return [];
    return [...fields].sort(sortByPositionAndCreatedAt);
  },

  // Resolve the funnel_item id holding a given conversation (1:1 per funnel),
  // so the preview modal can persist custom field values by item.
  getItemIdByConversation: $state => (funnelId, conversationId) => {
    if (conversationId == null) return null;
    const targetConv = Number(conversationId);
    const targetFunnel = funnelId == null ? null : Number(funnelId);
    const match = Object.values($state.funnelItems || {}).find(item => {
      const itemFunnel = Number(item?.funnel_id ?? item?.funnelId);
      const convId = Number(
        item?.conversation?.id ?? item?.conversation_id ?? item?.conversationId
      );
      return (
        (targetFunnel == null || itemFunnel === targetFunnel) &&
        convId === targetConv
      );
    });
    return match ? match.id : null;
  },

  getFunnelStages: $state => funnelId => {
    if (!funnelId) return [];
    const stages = $state.funnelStages[funnelId] || {};
    return Object.values(stages).sort(sortByPositionAndCreatedAt);
  },

  getFunnelItems: $state => (funnelId, stageId) => {
    if (funnelId == null || stageId == null) {
      return [];
    }

    const stageKey = buildStageKey(funnelId, stageId);
    const stageItemIds = $state.stageItems[stageKey];
    if (!Array.isArray(stageItemIds)) return [];

    return stageItemIds
      .map(itemId => $state.funnelItems[itemId])
      .filter(Boolean);
  },

  getStageMeta: $state => (funnelId, stageId) => {
    if (funnelId == null || stageId == null) {
      return {
        hasMore: false,
        nextCursor: null,
        isLoading: false,
        loaded: false,
        error: false,
        limit: null,
      };
    }

    return (
      $state.stageMeta[buildStageKey(funnelId, stageId)] || {
        hasMore: false,
        nextCursor: null,
        isLoading: false,
        loaded: false,
        error: false,
        limit: null,
      }
    );
  },

  getScheduledMessages($state) {
    if (Array.isArray($state.scheduledTimeline)) {
      return $state.scheduledTimeline
        .map(messageId => $state.scheduledById?.[messageId])
        .filter(Boolean);
    }

    return Object.values($state.scheduledMessages || {}).sort((a, b) => {
      const aTime = new Date(a.scheduledAt || a.scheduled_at || 0).getTime();
      const bTime = new Date(b.scheduledAt || b.scheduled_at || 0).getTime();
      return bTime - aTime;
    });
  },

  getScheduledMessagesByConversation: $state => conversationId => {
    const normalizedConversationId = Number(conversationId);
    const source = Object.values(
      $state.scheduledById || $state.scheduledMessages
    );
    return source.filter(msg => {
      return (
        Number(msg.conversationId || msg.conversation_id) ===
        normalizedConversationId
      );
    });
  },

  getScheduledMeta($state) {
    return (
      $state.scheduledMeta || {
        hasMore: false,
        nextCursor: null,
        limit: 50,
        loaded: false,
        error: false,
      }
    );
  },

  getScheduledFilters($state) {
    return (
      $state.scheduledFilters || {
        status: 'all',
        conversationId: null,
        from: null,
        to: null,
      }
    );
  },

  getActiveFunnelId($state) {
    return $state.activeFunnelId;
  },

  getViewMode($state) {
    return $state.viewMode;
  },

  getViewFilters($state) {
    return (
      $state.viewFilters || {
        query: '',
        stageIds: [],
        labelIds: [],
        assigneeId: null,
        status: 'all',
      }
    );
  },

  getViewBootstrap($state) {
    return (
      $state.viewBootstrap || {
        kanbanLoaded: false,
        listLoaded: false,
        calendarLoaded: false,
        listQueueStageIds: [],
      }
    );
  },

  getUIFlags($state) {
    return $state.uiFlags;
  },

  getWahaInboxes($state) {
    return $state.wahaInboxes;
  },
};
