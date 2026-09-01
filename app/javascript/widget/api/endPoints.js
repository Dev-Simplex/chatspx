import { buildSearchParamsWithLocale } from '../helpers/urlParamsHelper';
import { generateEventParams } from './events';

const createConversation = (params, { echoId } = {}) => {
  const referrerURL = window.referrerURL || '';
  const search = buildSearchParamsWithLocale(window.location.search);
  return {
    url: `/api/v1/widget/conversations${search}`,
    params: {
      contact: {
        name: params.fullName,
        email: params.emailAddress,
        phone_number: params.phoneNumber,
        custom_attributes: params.contactCustomAttributes,
      },
      message: {
        content: params.message,
        timestamp: new Date().toString(),
        referer_url: referrerURL,
        // Bloco 2.15. Este POST cria CONVERSA e mensagem de uma vez, e era o
        // unico dos tres que nao mandava chave — o controlador ja a permitia
        // (`conversations_controller.rb:141`) e ja a gravaria em `source_id`,
        // so que nada a enviava. Um reenvio deste corpo abria uma conversa nova
        // com a mesma primeira frase.
        echo_id: echoId,
      },
      custom_attributes: params.customAttributes,
    },
  };
};

const sendMessage = (
  content,
  replyTo,
  { customAttributes, labels, echoId } = {}
) => {
  const referrerURL = window.referrerURL || '';
  const search = buildSearchParamsWithLocale(window.location.search);
  const params = {
    message: {
      content,
      reply_to: replyTo,
      timestamp: new Date().toString(),
      referer_url: referrerURL,
      // Bloco 2.15: a chave de idempotencia. Ela nasce UMA vez por mensagem e
      // e reusada no retry — gerar outra a cada tentativa seria o mesmo que
      // nao ter chave, porque o servidor nao teria como reconhecer o reenvio.
      echo_id: echoId,
    },
  };
  if (customAttributes && Object.keys(customAttributes).length > 0) {
    params.custom_attributes = customAttributes;
  }
  if (labels && labels.length > 0) {
    params.labels = labels;
  }
  return { url: `/api/v1/widget/messages${search}`, params };
};

const sendAttachment = (
  { attachment, replyTo = null },
  { customAttributes, labels, echoId } = {}
) => {
  const { referrerURL = '' } = window;
  const timestamp = new Date().toString();
  const { file } = attachment;

  const formData = new FormData();
  if (typeof file === 'string') {
    formData.append('message[attachments][]', file);
  } else {
    formData.append('message[attachments][]', file, file.name);
  }

  formData.append('message[referer_url]', referrerURL);
  formData.append('message[timestamp]', timestamp);
  // Bloco 2.15. O anexo sobe para o MESMO endpoint da mensagem de texto
  // (`/api/v1/widget/messages`, logo abaixo), entao ele passa pelo mesmo
  // `existing_message_for_retry` do controlador — sempre que a chave viajar.
  // Ela nao viajava: o upload e o envio mais caro e mais sujeito a cair no meio,
  // e era o unico dos tres caminhos que subia sem nenhuma protecao.
  if (echoId) {
    formData.append('message[echo_id]', echoId);
  }
  if (replyTo !== null) {
    formData.append('message[reply_to]', replyTo);
  }
  if (customAttributes && Object.keys(customAttributes).length > 0) {
    Object.entries(customAttributes).forEach(([key, value]) => {
      formData.append(`custom_attributes[${key}]`, value);
    });
  }
  if (labels && labels.length > 0) {
    labels.forEach(label => {
      formData.append('labels[]', label);
    });
  }
  return {
    url: `/api/v1/widget/messages${window.location.search}`,
    params: formData,
  };
};

const getConversation = ({ before, after }) => ({
  url: `/api/v1/widget/messages${window.location.search}`,
  params: { before, after },
});

const updateMessage = id => ({
  url: `/api/v1/widget/messages/${id}${window.location.search}`,
});

const getAvailableAgents = token => ({
  url: '/api/v1/widget/inbox_members',
  params: {
    website_token: token,
  },
});
const getCampaigns = token => ({
  url: '/api/v1/widget/campaigns',
  params: {
    website_token: token,
  },
});
const triggerCampaign = ({ websiteToken, campaignId, customAttributes }) => ({
  url: '/api/v1/widget/events',
  data: {
    name: 'campaign.triggered',
    event_info: {
      campaign_id: campaignId,
      custom_attributes: customAttributes,
      ...generateEventParams(),
    },
  },
  params: {
    website_token: websiteToken,
  },
});

const getMostReadArticles = (slug, locale) => ({
  url: `/hc/${slug}/${locale}/articles.json`,
  params: {
    page: 1,
    sort: 'views',
    status: 1,
    per_page: 6,
  },
});

export default {
  createConversation,
  sendMessage,
  sendAttachment,
  getConversation,
  updateMessage,
  getAvailableAgents,
  getCampaigns,
  triggerCampaign,
  getMostReadArticles,
};
