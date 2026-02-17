import types from './mutation-types';
import camelcaseKeys from 'camelcase-keys';

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
    Object.keys($state.funnelItems).forEach(key => {
      if ($state.funnelItems[key].funnelId === funnelId) {
        delete $state.funnelItems[key];
      }
    });
  },

  [types.SET_FUNNEL_STAGES]($state, { funnelId, stages }) {
    if (!funnelId) return;
    $state.funnelStages[funnelId] = {};
    if (Array.isArray(stages)) {
      stages.forEach(stage => {
        if (stage && stage.id) {
          $state.funnelStages[funnelId][stage.id] = camelcaseKeys(stage, { deep: true });
        }
      });
    }
  },

  [types.ADD_FUNNEL_STAGE]($state, stage) {
    if (!stage || !stage.id) return;
    const stageData = camelcaseKeys(stage, { deep: true });
    let funnelId = stageData.funnelId || stageData.funnel_id || stage.funnel_id || stage.funnelId;
    if (!funnelId) return;
    if (!$state.funnelStages[funnelId]) {
      $state.funnelStages[funnelId] = {};
    }
    stageData.funnelId = funnelId;
    stageData.funnel_id = funnelId;
    $state.funnelStages[funnelId][stageData.id] = stageData;
  },

  [types.UPDATE_FUNNEL_STAGE]($state, stage) {
    const stageData = camelcaseKeys(stage, { deep: true });
    const funnelId = stageData.funnelId || stageData.funnel_id;
    if (!funnelId) return;
    if (!$state.funnelStages[funnelId]) {
      $state.funnelStages[funnelId] = {};
    }
    if ($state.funnelStages[funnelId]?.[stageData.id]) {
      $state.funnelStages[funnelId][stageData.id] = {
        ...$state.funnelStages[funnelId][stageData.id],
        ...stageData,
      };
    } else {
      $state.funnelStages[funnelId][stageData.id] = stageData;
    }
  },

  [types.DELETE_FUNNEL_STAGE]($state, { funnelId, stageId }) {
    if ($state.funnelStages[funnelId]) {
      delete $state.funnelStages[funnelId][stageId];
    }
    Object.keys($state.funnelItems).forEach(key => {
      if ($state.funnelItems[key].funnelStageId === stageId) {
        delete $state.funnelItems[key];
      }
    });
  },

  [types.SET_FUNNEL_ITEMS]($state, items) {
    if (Array.isArray(items)) {
      items.forEach(item => {
        $state.funnelItems[item.id] = camelcaseKeys(item, { deep: true });
      });
    }
  },

  [types.MERGE_FUNNEL_ITEMS]($state, items) {
    if (Array.isArray(items)) {
      items.forEach(item => {
        $state.funnelItems[item.id] = camelcaseKeys(item, { deep: true });
      });
    }
  },

  [types.ADD_FUNNEL_ITEM]($state, item) {
    $state.funnelItems[item.id] = camelcaseKeys(item, { deep: true });
  },

  [types.UPDATE_FUNNEL_ITEM]($state, item) {
    if ($state.funnelItems[item.id]) {
      $state.funnelItems[item.id] = {
        ...$state.funnelItems[item.id],
        ...camelcaseKeys(item, { deep: true }),
      };
    }
  },

  [types.DELETE_FUNNEL_ITEM]($state, itemId) {
    delete $state.funnelItems[itemId];
  },

  [types.SET_SCHEDULED_MESSAGES]($state, messages) {
    $state.scheduledMessages = {};
    if (Array.isArray(messages)) {
      messages.forEach(message => {
        $state.scheduledMessages[message.id] = camelcaseKeys(message, { deep: true });
      });
    }
  },

  [types.ADD_SCHEDULED_MESSAGE]($state, message) {
    $state.scheduledMessages[message.id] = camelcaseKeys(message, { deep: true });
  },

  [types.UPDATE_SCHEDULED_MESSAGE]($state, message) {
    const normalizedMessage = camelcaseKeys(message, { deep: true });
    $state.scheduledMessages[message.id] = {
      ...($state.scheduledMessages[message.id] || {}),
      ...normalizedMessage,
    };
  },

  [types.DELETE_SCHEDULED_MESSAGE]($state, messageId) {
    delete $state.scheduledMessages[messageId];
  },

  [types.SET_ACTIVE_FUNNEL_ID]($state, funnelId) {
    $state.activeFunnelId = funnelId;
  },

  [types.SET_VIEW_MODE]($state, mode) {
    $state.viewMode = mode;
  },

  [types.SET_WAHA_INBOXES]($state, inboxes) {
    $state.wahaInboxes = Array.isArray(inboxes) ? inboxes.map(inbox => camelcaseKeys(inbox, { deep: true })) : [];
  },
};
