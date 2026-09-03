import MessageAPI from '../../api/message';
import { reportWidgetError } from 'widget/helpers/telemetry';
import {
  emitLeadIdentified,
  emitSdkEventOnce,
} from 'widget/helpers/sdkEventEmitter';
import { CHATWOOT_CSAT_SUBMITTED } from 'widget/constants/sdkEvents';

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

      // ── Bloco 5.04 ────────────────────────────────────────────────────────
      //
      // Esta ação atende DOIS fatos diferentes, e é por isso que a emissão vive
      // aqui e não no componente: `CustomerSatisfaction.vue` mora em
      // `shared/` e é renderizado também pelo dashboard e pela pesquisa
      // avulsa — emitir de lá mandaria evento de widget de dentro de telas que
      // não têm SDK nenhum do outro lado.
      //
      // CSAT: a chave do `once` é a mensagem, não o evento. O visitante
      // responde a nota e depois escreve o comentário, e as duas submissões
      // passam por aqui; o fato "esta pesquisa foi respondida" é um só.
      const rating = submittedValues?.csat_survey_response?.rating;
      if (rating !== undefined && rating !== null) {
        emitSdkEventOnce(
          CHATWOOT_CSAT_SUBMITTED,
          { rating },
          `${CHATWOOT_CSAT_SUBMITTED}:${messageId}`
        );
      }

      // `input_email` respondido no meio da conversa: o visitante acabou de
      // entregar o e-mail. É transição, ao contrário do `contacts/get` logo
      // acima — ver o comentário longo em `store/modules/contacts.js`.
      emitLeadIdentified({ contact: { email } });
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
