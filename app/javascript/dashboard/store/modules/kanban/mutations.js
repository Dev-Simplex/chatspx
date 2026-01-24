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
    // Remove items deste funil
    Object.keys($state.funnelItems).forEach(key => {
      if ($state.funnelItems[key].funnelId === funnelId) {
        delete $state.funnelItems[key];
      }
    });
  },

  [types.SET_FUNNEL_STAGES]($state, { funnelId, stages }) {
    if (!funnelId) {
      console.warn('SET_FUNNEL_STAGES: funnelId não fornecido');
      return;
    }
    $state.funnelStages[funnelId] = {};
    if (Array.isArray(stages)) {
      console.log('SET_FUNNEL_STAGES: Processando etapas', { 
        funnelId, 
        count: stages.length,
        stages: stages.map(s => ({ id: s?.id, name: s?.name, position: s?.position }))
      });
      stages.forEach(stage => {
        if (stage && stage.id) {
          $state.funnelStages[funnelId][stage.id] = camelcaseKeys(stage, {
            deep: true,
          });
          console.log(`SET_FUNNEL_STAGES: Etapa adicionada - ${stage.name} (ID: ${stage.id}, posição: ${stage.position})`);
        } else {
          console.warn('SET_FUNNEL_STAGES: Etapa inválida ignorada', stage);
        }
      });
      console.log(`SET_FUNNEL_STAGES: Total de etapas no state para funil ${funnelId}: ${Object.keys($state.funnelStages[funnelId]).length}`);
    } else {
      console.warn('SET_FUNNEL_STAGES: stages não é um array', stages);
    }
  },

  [types.ADD_FUNNEL_STAGE]($state, stage) {
    if (!stage) {
      console.warn('ADD_FUNNEL_STAGE: stage é null ou undefined', stage);
      return;
    }
    
    // Se não tem id, não pode adicionar (mas vamos logar mais detalhes)
    if (!stage.id) {
      console.warn('ADD_FUNNEL_STAGE: stage sem id, ignorando', {
        stage,
        stageKeys: Object.keys(stage || {}),
        stageStringified: JSON.stringify(stage),
      });
      return;
    }
    
    const stageData = camelcaseKeys(stage, { deep: true });
    // Tentar obter funnelId de várias formas
    let funnelId = stageData.funnelId || stageData.funnel_id;
    
    // Se ainda não encontrou, tentar do stage original antes do camelcaseKeys
    if (!funnelId) {
      funnelId = stage.funnel_id || stage.funnelId;
    }
    
    if (!funnelId) {
      console.error('ADD_FUNNEL_STAGE: funnelId não encontrado', { stage, stageData });
      return;
    }
    
    if (!$state.funnelStages[funnelId]) {
      $state.funnelStages[funnelId] = {};
    }
    
    // Garantir que o funnelId está no stageData
    stageData.funnelId = funnelId;
    stageData.funnel_id = funnelId;
    
    $state.funnelStages[funnelId][stageData.id] = stageData;
    console.log('ADD_FUNNEL_STAGE: Etapa adicionada com sucesso', { 
      funnelId, 
      stageId: stageData.id, 
      stageName: stageData.name,
      totalStages: Object.keys($state.funnelStages[funnelId]).length,
    });
  },

  [types.UPDATE_FUNNEL_STAGE]($state, stage) {
    const stageData = camelcaseKeys(stage, { deep: true });
    const funnelId = stageData.funnelId || stageData.funnel_id;
    if (!funnelId) {
      console.error('UPDATE_FUNNEL_STAGE: funnelId não encontrado', stage);
      return;
    }
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
    // Remove items desta etapa
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
    if (Array.isArray(messages)) {
      messages.forEach(message => {
        $state.scheduledMessages[message.id] = camelcaseKeys(message, {
          deep: true,
        });
      });
    }
  },

  [types.ADD_SCHEDULED_MESSAGE]($state, message) {
    $state.scheduledMessages[message.id] = camelcaseKeys(message, {
      deep: true,
    });
  },

  [types.UPDATE_SCHEDULED_MESSAGE]($state, message) {
    if ($state.scheduledMessages[message.id]) {
      $state.scheduledMessages[message.id] = {
        ...$state.scheduledMessages[message.id],
        ...camelcaseKeys(message, { deep: true }),
      };
    }
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
    $state.wahaInboxes = inboxes.map(inbox => camelcaseKeys(inbox, { deep: true }));
  },
};

