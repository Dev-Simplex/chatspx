import * as types from '../../mutation-types';
import InboxesAPI from '../../../api/inboxes';
import AnalyticsHelper from '../../../helper/AnalyticsHelper';
import { ACCOUNT_EVENTS } from '../../../helper/AnalyticsHelper/events';

/**
 * Um campo do FormData da inbox.
 *
 * FormData nao tem tipo: `append(key, [16])` grava a STRING "16" e `append(key, [])` grava "".
 * O Rails declara as chaves de lista como array (ex.: `{ team_message_isolation_team_ids: [] }`) e
 * o strong parameters DESCARTA EM SILENCIO o escalar que chega no lugar do array: a requisicao
 * volta 200, a tela mostra "salvo com sucesso" e o valor nunca chega ao banco. Foi assim que a
 * escolha de times do isolamento se perdia entre a tela e o banco.
 *
 * Array vai como `key[]`, um append por item. Array vazio vai como um unico `key[]` em branco, que
 * e a forma de dizer "lista vazia" em multipart; sem isso a chave simplesmente nao existiria no
 * payload e o backend nao teria como distinguir "o admin limpou" de "a tela nao mandou".
 * E o mesmo tratamento que `selected_feature_flags` ja fazia na mao aqui embaixo, agora valendo
 * para toda chave de lista em vez de uma so.
 */
const appendInboxField = (formData, key, value) => {
  if (!Array.isArray(value)) {
    formData.append(key, value);
    return;
  }

  if (!value.length) {
    formData.append(`${key}[]`, '');
    return;
  }

  value.forEach(item => formData.append(`${key}[]`, item));
};

export const buildInboxData = inboxParams => {
  const formData = new FormData();
  const { channel = {}, ...inboxProperties } = inboxParams;
  Object.keys(inboxProperties).forEach(key => {
    appendInboxField(formData, key, inboxProperties[key]);
  });
  const { selectedFeatureFlags, ...channelParams } = channel;
  // selectedFeatureFlags needs to be empty when creating a website channel
  if (selectedFeatureFlags) {
    appendInboxField(
      formData,
      'channel[selected_feature_flags]',
      selectedFeatureFlags
    );
  }
  Object.keys(channelParams).forEach(key => {
    appendInboxField(formData, `channel[${key}]`, channel[key]);
  });
  return formData;
};

const sendAnalyticsEvent = channelType => {
  AnalyticsHelper.track(ACCOUNT_EVENTS.ADDED_AN_INBOX, {
    channelType,
  });
};

export const channelActions = {
  createVoiceChannel: async ({ commit }, params) => {
    try {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: true });
      const response = await InboxesAPI.create({
        name: params.name,
        channel: { ...params.voice, type: 'voice' },
      });
      commit(types.default.ADD_INBOXES, response.data);
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      sendAnalyticsEvent('voice');
      return response.data;
    } catch (error) {
      commit(types.default.SET_INBOXES_UI_FLAG, { isCreating: false });
      throw error;
    }
  },
};
