import camelcaseKeys from 'camelcase-keys';

export const getters = {
  getFunnels($state) {
    const funnels = Object.values($state.funnels);
    return funnels.sort((a, b) => {
      const aIsDefault = a.teamId == null && a.team_id == null;
      const bIsDefault = b.teamId == null && b.team_id == null;
      if (aIsDefault !== bIsDefault) {
        return aIsDefault ? -1 : 1;
      }
      const posA = a.position ?? 0;
      const posB = b.position ?? 0;
      if (posA !== posB) {
        return posA - posB;
      }
      const createdA = new Date(a.createdAt || a.created_at || 0).getTime() || 0;
      const createdB = new Date(b.createdAt || b.created_at || 0).getTime() || 0;
      return createdA - createdB;
    });
  },
  getFunnel: $state => id => {
    return camelcaseKeys($state.funnels[id] || {}, { deep: true });
  },
  getFunnelStages: $state => funnelId => {
    if (!funnelId) return [];
    const stages = $state.funnelStages[funnelId] || {};
    const stagesArray = Object.values(stages);
    // Ordenar por position e depois por created_at para garantir ordem consistente
    return stagesArray.sort((a, b) => {
      const posA = a.position ?? 0;
      const posB = b.position ?? 0;
      if (posA !== posB) {
        return posA - posB;
      }
      // Se position for igual, ordenar por created_at
      const createdA = a.createdAt || a.created_at || 0;
      const createdB = b.createdAt || b.created_at || 0;
      return createdA - createdB;
    });
  },
  getFunnelItems: $state => (funnelId, stageId) => {
    if (funnelId == null || stageId == null) {
      return [];
    }

    const normalizedFunnelId = Number(funnelId);
    const normalizedStageId = Number(stageId);
    const items = Object.values($state.funnelItems).filter(item => {
      const itemFunnelId = Number(item.funnelId || item.funnel_id);
      const itemStageId = Number(item.funnelStageId || item.funnel_stage_id);
      return itemFunnelId === normalizedFunnelId && itemStageId === normalizedStageId;
    });
    return camelcaseKeys(items, { deep: true });
  },
  getScheduledMessages($state) {
    return Object.values($state.scheduledMessages);
  },
  getScheduledMessagesByConversation: $state => conversationId => {
    return Object.values($state.scheduledMessages).filter(
      msg => msg.conversationId === conversationId
    );
  },
  getActiveFunnelId($state) {
    return $state.activeFunnelId;
  },
  getViewMode($state) {
    return $state.viewMode;
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getWahaInboxes($state) {
    return $state.wahaInboxes;
  },
};
