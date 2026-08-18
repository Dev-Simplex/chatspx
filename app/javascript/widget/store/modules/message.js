import MessageAPI from '../../api/message';
import { reportWidgetError } from 'widget/helpers/telemetry';

const state = {
  uiFlags: {
    isUpdating: false,
  },
};

export const getters = {
  getUIFlags: $state => $state.uiFlags,
};

export const actions = {
  update: async (
    { commit, dispatch, getters: { getUIFlags: uiFlags } },
    { email, messageId, submittedValues }
  ) => {
    if (uiFlags.isUpdating) {
      return;
    }
    commit('toggleUpdateStatus', true);
    try {
      await MessageAPI.update({
        email,
        messageId,
        values: submittedValues,
      });
      commit(
        'conversation/updateMessage',
        {
          id: messageId,
          content_attributes: {
            submitted_email: email,
            submitted_values: email ? null : submittedValues,
          },
        },
        { root: true }
      );
      dispatch('contacts/get', {}, { root: true });
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, { origem: 'store/message' });
    }
    commit('toggleUpdateStatus', false);
  },
};

export const mutations = {
  toggleUpdateStatus($state, status) {
    $state.uiFlags.isUpdating = status;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
