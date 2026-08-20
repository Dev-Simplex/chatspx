import conversationLabels from '../../api/conversationLabels';
import { reportWidgetError } from 'widget/helpers/telemetry';

const state = {};

export const getters = {};

export const actions = {
  create: async ({ commit, rootGetters }, label) => {
    if (!rootGetters['conversationAttributes/getConversationParams']?.id) {
      commit('conversation/setPendingLabels', label, { root: true });
      return;
    }
    try {
      await conversationLabels.create(label);
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, { origem: 'store/conversationLabels#create' });
    }
  },
  destroy: async ({ commit, rootGetters }, label) => {
    if (!rootGetters['conversationAttributes/getConversationParams']?.id) {
      commit('conversation/removePendingLabel', label, { root: true });
      return;
    }
    try {
      await conversationLabels.destroy(label);
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, { origem: 'store/conversationLabels#destroy' });
    }
  },
};

export const mutations = {};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
