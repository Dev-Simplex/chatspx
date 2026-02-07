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
  getFunnelItems: ($state, _getters, _rootState, rootGetters) => (funnelId, stageId) => {
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

    const getContactById = rootGetters['contacts/getContactById'];
    const getConversationById = rootGetters['conversations/getConversationById'];
    const normalizeBrazilianPhone = (phone) => {
      const digits = phone.replace(/\D/g, '');
      if (!digits) return '';
      if (digits.startsWith('55') && digits.length === 12) {
        return digits.slice(0, 4) + '9' + digits.slice(4, 12);
      }
      return digits;
    };
    const getItemPhoneKey = (item) => {
      const conv = item?.conversation;
      const contact =
        conv?.contact || conv?.meta?.sender || conv?.sender;
      let phone =
        contact?.phone_number || contact?.phoneNumber;
      if (!phone && typeof getContactById === 'function') {
        const contactId =
          conv?.contact_id ?? conv?.contactId ?? contact?.id ??
          conv?.meta?.sender?.id ?? conv?.sender?.id;
        if (contactId) {
          const storeContact = getContactById(Number(contactId));
          phone =
            storeContact?.phone_number ?? storeContact?.phoneNumber ?? '';
        }
      }
      if (!phone && typeof getConversationById === 'function') {
        const convId = item?.conversation_id ?? item?.conversationId;
        if (convId) {
          const storeConv = getConversationById(Number(convId));
          const storeContact =
            storeConv?.meta?.sender || storeConv?.sender || storeConv?.contact;
          phone =
            storeContact?.phone_number ?? storeContact?.phoneNumber ?? '';
        }
      }
      const normalized = normalizeBrazilianPhone(String(phone || '').trim());
      if (normalized) return `phone:${normalized}`;
      const contactId =
        conv?.contact_id ?? conv?.contactId ?? contact?.id ??
        conv?.meta?.sender?.id ?? conv?.sender?.id;
      if (contactId) return `contact:${contactId}`;
      const convId = item?.conversation_id ?? item?.conversationId;
      return `conversation:${convId ?? item?.id}`;
    };

    const getItemRecency = (item) => {
      const conv = item?.conversation;
      const lastActivity =
        conv?.last_activity_at ?? conv?.lastActivityAt;
      const lastMsg = conv?.last_message ?? conv?.lastMessage;
      return new Date(
        lastActivity ?? lastMsg?.created_at ?? item?.created_at ?? 0
      ).getTime();
    };

    const byPhoneKey = new Map();
    for (const item of items) {
      const key = getItemPhoneKey(item);
      const existing = byPhoneKey.get(key);
      const recency = getItemRecency(item);
      if (!existing || recency > getItemRecency(existing)) {
        byPhoneKey.set(key, item);
      }
    }

    const deduplicated = Array.from(byPhoneKey.values());
    const movedAt = (item) =>
      new Date(item.moved_at ?? item.movedAt ?? item.created_at ?? item.createdAt ?? 0).getTime();
    deduplicated.sort((a, b) => movedAt(b) - movedAt(a));

    return camelcaseKeys(deduplicated, { deep: true });
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
