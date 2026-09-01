import { createStore } from 'vuex';

import agent from 'widget/store/modules/agent';
import appConfig from 'widget/store/modules/appConfig';
import contacts from 'widget/store/modules/contacts';
import conversation from 'widget/store/modules/conversation';
import conversationAttributes from 'widget/store/modules/conversationAttributes';
import conversationLabels from 'widget/store/modules/conversationLabels';
import events from 'widget/store/modules/events';
import globalConfig from 'shared/store/globalConfig';
import message from 'widget/store/modules/message';
import campaign from 'widget/store/modules/campaign';
import article from 'widget/store/modules/articles';
import { ligarFilaOffline } from 'widget/store/plugins/offlineQueue';

export default createStore({
  // Bloco 2.16 — quem drena a fila offline na volta da rede. Ver a nota do
  // plugin: sem esta linha a fila enfileira e nunca entrega, que é o estado em
  // que o bloco vivia.
  plugins: [ligarFilaOffline],
  modules: {
    agent,
    appConfig,
    contacts,
    conversation,
    conversationAttributes,
    conversationLabels,
    events,
    globalConfig,
    message,
    campaign,
    article,
  },
});
