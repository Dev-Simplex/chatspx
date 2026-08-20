import { sendMessage } from 'widget/helpers/utils';
import ContactsAPI from '../../api/contacts';
import { SET_USER_ERROR } from '../../constants/errorTypes';
import { setHeader } from '../../helpers/axios';
import { reportWidgetError } from 'widget/helpers/telemetry';
import { emitLeadIdentified } from 'widget/helpers/sdkEventEmitter';
import { buildContactPayload } from 'widget/helpers/identityPayload';
const state = {
  currentUser: {},
};

const SET_CURRENT_USER = 'SET_CURRENT_USER';
const parseErrorData = error =>
  error && error.response && error.response.data ? error.response.data : error;
export const updateWidgetAuthToken = widgetAuthToken => {
  if (widgetAuthToken) {
    setHeader(widgetAuthToken);
    sendMessage({
      event: 'setAuthCookie',
      data: { widgetAuthToken },
    });
  }
};

export const getters = {
  getCurrentUser(_state) {
    return _state.currentUser;
  },
};

const identifyContact = async (
  dispatch,
  { identifier, user: userObject, merge }
) => {
  try {
    const user = buildContactPayload(userObject, { merge });
    const {
      data: { widget_auth_token: widgetAuthToken },
    } = await ContactsAPI.setUser(identifier, user);
    updateWidgetAuthToken(widgetAuthToken);
    dispatch('get');
    if (userObject.identifier_hash || widgetAuthToken) {
      dispatch('conversation/clearConversations', {}, { root: true });
      dispatch('conversation/fetchOldConversations', {}, { root: true });
      dispatch('conversationAttributes/getAttributes', {}, { root: true });
    }
  } catch (error) {
    const data = parseErrorData(error);
    sendMessage({ event: 'error', errorType: SET_USER_ERROR, data });
  }
};

export const actions = {
  get: async ({ commit }) => {
    try {
      const { data } = await ContactsAPI.get();
      commit(SET_CURRENT_USER, data);
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, { origem: 'store/contacts#get' });
    }
  },
  update: async ({ dispatch }, { user }) => {
    try {
      await ContactsAPI.update(user);
      dispatch('get');
      // Bloco 5.04 — `chatwoot:lead-identified`. Aqui, e NÃO em `get`.
      //
      // O fato do contrato é uma TRANSIÇÃO: "o contato PASSOU A TER e-mail ou
      // telefone". `get` é leitura de estado, não transição — emitir de lá
      // dispararia o evento no boot de todo visitante que já era identificado,
      // e a ponte de tags (5.10) contaria um Lead por carregamento de página.
      // Isso é conversão inflada, que é o defeito que este plano inteiro existe
      // para não cometer.
      //
      // `setUser` também fica de fora, pelo mesmo motivo e um agravante: o site
      // do cliente o chama em TODA página, para um visitante que ele já
      // conhecia. Identidade afirmada pelo site não é lead novo.
      //
      // Aqui é diferente: o visitante ACABOU de digitar. `user` é o que ele
      // enviou, e só os NOMES dos identificadores atravessam para o `window`.
      emitLeadIdentified({ contact: user });
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, { origem: 'store/contacts#update' });
    }
  },
  // Bloco 5.17 — a regra de verbo, explicita em vez de deduzida:
  //   setUser    SUBSTITUI (comportamento historico, mantido intacto — e o metodo LEGADO)
  //   updateUser MESCLA    (campo nao enviado nao viaja, entao o servidor nao o apaga)
  //
  // A diferenca importa porque o site que so quer corrigir o telefone chamava `setUser` com o
  // objeto inteiro e, se esquecesse um campo, o apagava sem aviso. E o mesmo formato do defeito
  // que apagava credencial ao abrir "Editar": ninguem pediu para apagar, e apagou.
  //
  // Os dois compartilham uma FUNCAO, nao uma action: action nova mudaria a lista de dispatches
  // que os specs deste store observam, e o contrato observavel do `setUser` nao muda neste bloco.
  setUser: async ({ dispatch }, { identifier, user: userObject }) => {
    await identifyContact(dispatch, {
      identifier,
      user: userObject,
      merge: false,
    });
  },
  updateUser: async ({ dispatch }, { identifier, user: userObject }) => {
    await identifyContact(dispatch, {
      identifier,
      user: userObject,
      merge: true,
    });
  },
  setCustomAttributes: async (_, customAttributes = {}) => {
    try {
      await ContactsAPI.setCustomAttributes(customAttributes);
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, {
        origem: 'store/contacts#setCustomAttributes',
      });
    }
  },
  deleteCustomAttribute: async (_, customAttribute) => {
    try {
      await ContactsAPI.deleteCustomAttribute(customAttribute);
    } catch (error) {
      // Bloco 2.13. Era `// Ignore error` — o widget quebrava no site do
      // cliente e ninguém ficava sabendo. O erro continua sem interromper o
      // visitante; passa apenas a ser CONTADO.
      reportWidgetError(error, {
        origem: 'store/contacts#deleteCustomAttribute',
      });
    }
  },
};

export const mutations = {
  [SET_CURRENT_USER]($state, user) {
    const { currentUser } = $state;
    $state.currentUser = { ...currentUser, ...user };
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
