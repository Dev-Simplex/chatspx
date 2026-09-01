import { sendMessage } from 'widget/helpers/utils';
import ContactsAPI from '../../api/contacts';
import { SET_USER_ERROR } from '../../constants/errorTypes';
import { setHeader } from '../../helpers/axios';
import { reportWidgetError } from 'widget/helpers/telemetry';
import { emitLeadIdentified } from 'widget/helpers/sdkEventEmitter';
import { buildContactPayload } from 'widget/helpers/identityPayload';
const state = {
  currentUser: {},
  // Bloco 5.19 — a credencial que o HOST mandou na identificacao.
  //
  // Vive aqui, e nao no `window` do site, porque o `window` e legivel por qualquer script de
  // terceiro da pagina (regra RC5): o token e credencial ao portador. Do lado de ca ele fica na
  // memoria do iframe, que e nosso, e some quando o frame recarrega — que e o comportamento
  // certo, porque na recarga o host pergunta de novo ao `identityTokenProvider`.
  //
  // Por que GUARDAR em vez de so repassar: o pre-chat com campanha escreve pelo
  // `PATCH /widget/contact` (`contacts/update`), que nasce de um formulario que o VISITANTE
  // preencheu — ali nao ha objeto do site nenhum trazendo credencial. Sem esta memoria, aquela
  // rota chegaria sempre sem prova, e o `hmac_verified` que o servidor passou a saber marcar
  // nela nunca teria como acontecer.
  identityToken: '',
};

const SET_CURRENT_USER = 'SET_CURRENT_USER';
const SET_IDENTITY_TOKEN = 'SET_IDENTITY_TOKEN';
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
  { dispatch, commit },
  { identifier, user: userObject, merge }
) => {
  try {
    // Bloco 5.19: guarda ANTES do envio, e so quando ha token. "So quando ha" nao e economia de
    // linha: um commit incondicional gravaria `''` por cima de um token bom sempre que o site
    // chamasse `setCustomAttributes` ou um `setUser` sem credencial no meio da sessao.
    if (userObject.identity_token) {
      commit(SET_IDENTITY_TOKEN, userObject.identity_token);
    }

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
  // Bloco 5.19: `state` entra na desestruturacao para ler o token guardado. O acesso e opcional
  // (`state?.`) porque esta action ja e chamada de contextos que passam so `{ dispatch }`.
  update: async ({ dispatch, state: $state }, { user }) => {
    try {
      // A credencial nao substitui nem mescla nada do contato: ela viaja ao lado, e so quando
      // existe. Chave de credencial vazia faria "sem prova" e "prova vazia" parecerem o mesmo
      // fato para o servidor, e eles nao sao.
      const identityToken = $state?.identityToken;
      await ContactsAPI.update(
        identityToken ? { ...user, identity_token: identityToken } : user
      );
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
  setUser: async ({ dispatch, commit }, { identifier, user: userObject }) => {
    await identifyContact(
      { dispatch, commit },
      {
        identifier,
        user: userObject,
        merge: false,
      }
    );
  },
  updateUser: async (
    { dispatch, commit },
    { identifier, user: userObject }
  ) => {
    await identifyContact(
      { dispatch, commit },
      {
        identifier,
        user: userObject,
        merge: true,
      }
    );
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

  // Bloco 5.19 — a credencial do host. Nao entra em `currentUser` de proposito: `currentUser` e
  // o que a tela le e o que os getters expoem, e credencial ao portador nao e dado de perfil.
  [SET_IDENTITY_TOKEN]($state, identityToken) {
    $state.identityToken = identityToken;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
