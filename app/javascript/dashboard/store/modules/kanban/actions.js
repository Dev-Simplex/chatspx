import types from './mutation-types';
import KanbanAPI from '../../../api/kanban';

export const actions = {
  async fetchFunnels({ commit }) {
    commit(types.SET_KANBAN_UI_FLAG, { isFetching: true });
    try {
      const response = await KanbanAPI.getFunnels();
      commit(types.SET_FUNNELS, response.data);
      return response;
    } catch (error) {
      throw error;
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
    } catch (error) {
      throw error;
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
    } catch (error) {
      throw error;
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
    } catch (error) {
      throw error;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isUpdating: false });
    }
  },

  async deleteFunnel({ commit }, funnelId) {
    commit(types.SET_KANBAN_UI_FLAG, { isDeleting: true });
    try {
      await KanbanAPI.deleteFunnel(funnelId);
      commit(types.DELETE_FUNNEL, funnelId);
    } catch (error) {
      throw error;
    } finally {
      commit(types.SET_KANBAN_UI_FLAG, { isDeleting: false });
    }
  },

  async reorderStages({ commit }, { funnelId, stageIds }) {
    try {
      await KanbanAPI.reorderStages(funnelId, stageIds);
      // Recarregar stages após reordenar
      const response = await KanbanAPI.getFunnelStages(funnelId);
      commit(types.SET_FUNNEL_STAGES, {
        funnelId,
        stages: response.data,
      });
    } catch (error) {
      throw error;
    }
  },

  async fetchFunnelStages({ commit }, funnelId) {
    try {
      if (!funnelId) {
        console.warn('fetchFunnelStages: funnelId não fornecido');
        return { data: [] };
      }
      const response = await KanbanAPI.getFunnelStages(funnelId);
      console.log('fetchFunnelStages: Resposta completa da API', {
        response,
        responseData: response.data,
        responseDataType: typeof response.data,
        isArray: Array.isArray(response.data),
        responseDataStringified: JSON.stringify(response.data),
        responseStatus: response.status,
        responseHeaders: response.headers,
      });
      
      // A resposta pode vir em diferentes formatos
      let stages = [];
      
      // Se response.data é uma string vazia, tratar como array vazio
      if (response.data === '' || response.data === null || response.data === undefined) {
        console.warn('fetchFunnelStages: Resposta vazia, retornando array vazio');
        stages = [];
      } else if (Array.isArray(response.data)) {
        stages = response.data;
        console.log(`fetchFunnelStages: Resposta é array com ${stages.length} itens`);
      } else if (response.data && typeof response.data === 'object') {
        // Pode ser um objeto com uma propriedade stages ou funnel_stages
        stages = response.data.stages || response.data.funnel_stages || [];
        // Se ainda não é array, pode ser que response.data seja o próprio array
        if (!Array.isArray(stages) && Array.isArray(response.data)) {
          stages = response.data;
        }
        console.log(`fetchFunnelStages: Resposta é objeto, extraído ${stages.length} etapas`);
      }
      
      // Garantir que é um array
      if (!Array.isArray(stages)) {
        console.warn('fetchFunnelStages: stages não é um array, convertendo', {
          stages,
          stagesType: typeof stages,
          stagesStringified: JSON.stringify(stages),
        });
        stages = [];
      }
      
      // Log detalhado de cada etapa recebida
      console.log(`fetchFunnelStages: Total de ${stages.length} etapas recebidas`);
      stages.forEach((stage, index) => {
        console.log(`fetchFunnelStages: Etapa ${index + 1} - ID: ${stage?.id}, Nome: ${stage?.name}, Posição: ${stage?.position}`);
      });
      
      console.log('fetchFunnelStages: Etapas extraídas', { 
        funnelId, 
        stages, 
        count: stages.length,
        stageIds: stages.map(s => s?.id),
        stageNames: stages.map(s => s?.name),
      });
      commit(types.SET_FUNNEL_STAGES, {
        funnelId,
        stages,
      });
      return { data: stages };
    } catch (error) {
      console.error('fetchFunnelStages: Erro ao buscar etapas', error);
      // Retornar array vazio em caso de erro para não quebrar a UI
      commit(types.SET_FUNNEL_STAGES, { funnelId, stages: [] });
      return { data: [] };
    }
  },

  async createStage({ commit, dispatch }, { funnelId, data }) {
    try {
      console.log('createStage: Iniciando criação', { funnelId, data });
      const response = await KanbanAPI.createStage(funnelId, data);
      console.log('createStage: Resposta completa da API', {
        response,
        responseData: response.data,
        responseStatus: response.status,
        responseHeaders: response.headers,
        responseDataStringified: JSON.stringify(response.data),
      });
      
      // Verificar se houve erro na resposta
      if (response.status >= 400) {
        console.error('createStage: Erro na resposta da API', response);
        throw new Error(response.data?.errors?.join(', ') || `Erro ${response.status} ao criar etapa`);
      }
      
      // A resposta do axios vem em response.data
      // A view jbuilder retorna o objeto diretamente
      let stageData = response.data;
      
      // Se não tem id, pode ser que a resposta esteja em outro formato
      if (!stageData || !stageData.id) {
        console.warn('createStage: Resposta sem id, tentando extrair de response', response);
        // Tentar encontrar o stage na resposta
        if (response.data && typeof response.data === 'object') {
          // Pode estar em response.data.funnel_stage ou response.data.stage
          stageData = response.data.funnel_stage || response.data.stage || response.data;
        }
      }
      
      // Se ainda não tem id, buscar novamente do servidor após um delay
      if (!stageData || !stageData.id) {
        console.log('createStage: Resposta sem id, aguardando e buscando do servidor...');
        // Aguardar um pouco para garantir que o servidor processou
        await new Promise(resolve => setTimeout(resolve, 800));
        
        // Tentar múltiplas vezes
        let attempts = 0;
        let foundStage = null;
        
        while (attempts < 3 && !foundStage) {
          attempts++;
          console.log(`createStage: Tentativa ${attempts}/3 de buscar etapa...`);
          
          // Buscar todas as etapas do funil
          const stagesResponse = await KanbanAPI.getFunnelStages(funnelId);
          console.log('createStage: Resposta ao buscar etapas', {
            response: stagesResponse,
            data: stagesResponse.data,
            isArray: Array.isArray(stagesResponse.data),
            dataType: typeof stagesResponse.data,
          });
          
          let stages = [];
          if (Array.isArray(stagesResponse.data)) {
            stages = stagesResponse.data;
          } else if (stagesResponse.data && Array.isArray(stagesResponse.data.funnel_stages)) {
            stages = stagesResponse.data.funnel_stages;
          } else if (stagesResponse.data && typeof stagesResponse.data === 'object') {
            // Tentar outras propriedades
            stages = stagesResponse.data.stages || [];
          }
          
          console.log('createStage: Etapas encontradas', { count: stages.length, stages });
          
          // Procurar a etapa pelo nome (mais confiável que pegar a última)
          foundStage = stages.find(s => {
            const stageName = (s.name || '').trim();
            const dataName = (data.name || '').trim();
            return stageName === dataName;
          });
          
          if (foundStage && foundStage.id) {
            stageData = foundStage;
            console.log('createStage: Stage encontrado após buscar do servidor', stageData);
            break;
          } else if (stages.length > 0) {
            // Se não encontrou pelo nome, pegar a última (pode ser a recém criada)
            const lastStage = stages[stages.length - 1];
            if (lastStage.id) {
              stageData = lastStage;
              console.log('createStage: Usando última etapa encontrada', stageData);
              foundStage = lastStage;
              break;
            }
          }
          
          // Aguardar antes da próxima tentativa
          if (attempts < 3) {
            await new Promise(resolve => setTimeout(resolve, 500));
          }
        }
        
        if (!stageData || !stageData.id) {
          console.error('createStage: Não foi possível obter stage com id após múltiplas tentativas', {
            response,
            attempts,
            data,
          });
          throw new Error(`Não foi possível criar a etapa "${data.name}". Verifique se ela foi criada no servidor.`);
        }
      }
      
      // Garantir que o funnelId está no objeto
      if (!stageData.funnel_id && !stageData.funnelId) {
        stageData.funnel_id = funnelId;
      }
      
      console.log('createStage: StageData antes de commitar', stageData);
      commit(types.ADD_FUNNEL_STAGE, stageData);
      
      // Também atualizar a lista completa de etapas
      await dispatch('fetchFunnelStages', funnelId);
      
      return { data: stageData };
    } catch (error) {
      console.error('createStage: Erro ao criar etapa', error);
      throw error;
    }
  },

  async updateStage({ commit }, { funnelId, stageId, data }) {
    try {
      console.log('updateStage: Iniciando atualização', { funnelId, stageId, data });
      const response = await KanbanAPI.updateStage(funnelId, stageId, data);
      console.log('updateStage: Resposta completa da API', response);
      
      let stageData = response.data;
      if (!stageData || !stageData.id) {
        stageData = response.data.funnel_stage || response.data.stage || response.data;
      }
      
      if (stageData && stageData.id) {
        if (!stageData.funnel_id && !stageData.funnelId) {
          stageData.funnel_id = funnelId;
          stageData.funnelId = funnelId;
        }
        commit(types.UPDATE_FUNNEL_STAGE, stageData);
        return { data: stageData };
      } else {
        throw new Error('Resposta da API inválida: stage sem id');
      }
    } catch (error) {
      console.error('updateStage: Erro ao atualizar etapa', error);
      throw error;
    }
  },

  async deleteStage({ commit }, { funnelId, stageId }) {
    try {
      await KanbanAPI.deleteStage(funnelId, stageId);
      commit(types.DELETE_FUNNEL_STAGE, { funnelId, stageId });
    } catch (error) {
      throw error;
    }
  },

  async fetchFunnelItems({ commit }, { funnelId, stageId = null }) {
    try {
      const response = await KanbanAPI.getFunnelItems(funnelId, stageId);
      // Garantir que response.data seja um array
      const items = Array.isArray(response.data) ? response.data : [];
      commit(types.SET_FUNNEL_ITEMS, items);
      return response;
    } catch (error) {
      throw error;
    }
  },

  async createItem({ commit }, { funnelId, data }) {
    try {
      const response = await KanbanAPI.createItem(funnelId, data);
      commit(types.ADD_FUNNEL_ITEM, response.data);
      return response;
    } catch (error) {
      throw error;
    }
  },

  async updateItem({ commit }, { funnelId, itemId, data }) {
    try {
      const response = await KanbanAPI.updateItem(funnelId, itemId, data);
      commit(types.UPDATE_FUNNEL_ITEM, response.data);
      return response;
    } catch (error) {
      throw error;
    }
  },

  async deleteItem({ commit }, { funnelId, itemId }) {
    try {
      await KanbanAPI.deleteItem(funnelId, itemId);
      commit(types.DELETE_FUNNEL_ITEM, itemId);
    } catch (error) {
      throw error;
    }
  },

  async bulkMoveItems({ commit }, { funnelId, conversationIds, stageId }) {
    try {
      await KanbanAPI.bulkMoveItems(funnelId, conversationIds, stageId);
      // Recarregar items após mover
      const response = await KanbanAPI.getFunnelItems(funnelId);
      commit(types.SET_FUNNEL_ITEMS, response.data);
    } catch (error) {
      throw error;
    }
  },

  async fetchScheduledMessages({ commit }, conversationId = null) {
    try {
      const response = await KanbanAPI.getScheduledMessages(conversationId);
      // Garantir que response.data seja um array
      const messages = Array.isArray(response.data) ? response.data : [];
      commit(types.SET_SCHEDULED_MESSAGES, messages);
      return response;
    } catch (error) {
      // Se der erro 404, não quebrar a aplicação
      console.warn('Error fetching scheduled messages:', error);
      commit(types.SET_SCHEDULED_MESSAGES, []);
      return { data: [] };
    }
  },

  async createScheduledMessage({ commit }, data) {
    try {
      const response = await KanbanAPI.createScheduledMessage(data);
      commit(types.ADD_SCHEDULED_MESSAGE, response.data);
      return response;
    } catch (error) {
      throw error;
    }
  },

  async updateScheduledMessage({ commit }, { messageId, data }) {
    try {
      const response = await KanbanAPI.updateScheduledMessage(messageId, data);
      commit(types.UPDATE_SCHEDULED_MESSAGE, response.data);
      return response;
    } catch (error) {
      throw error;
    }
  },

  async deleteScheduledMessage({ commit }, messageId) {
    try {
      await KanbanAPI.deleteScheduledMessage(messageId);
      commit(types.DELETE_SCHEDULED_MESSAGE, messageId);
    } catch (error) {
      throw error;
    }
  },

  async fetchWahaInboxes({ commit }) {
    try {
      const response = await KanbanAPI.getWahaInboxes();
      commit(types.SET_WAHA_INBOXES, response.data);
      return response;
    } catch (error) {
      throw error;
    }
  },

  setActiveFunnelId({ commit }, funnelId) {
    commit(types.SET_ACTIVE_FUNNEL_ID, funnelId);
  },

  setViewMode({ commit }, mode) {
    commit(types.SET_VIEW_MODE, mode);
  },
};
