import { SDK_SET_BUBBLE_VISIBILITY } from 'shared/constants/sharedFrameEvents';

/**
 * Handlers do bridge site → widget.
 *
 * Cada handler é `(message, ctx) => void` e é testável SEM montar o App: `ctx` é
 * qualquer objeto com os métodos usados (na produção, a instância de `App.vue`).
 * A cadeia de 16 `else if` que vivia em `App.vue` virou este mapa — acrescentar
 * um evento passa a custar uma entrada, não uma edição no meio de um `if`.
 */

const UNREAD_OR_CAMPAIGN_ROUTES = ['unread-messages', 'campaigns'];

const websiteToken = () => window.chatwootWebChannel?.websiteToken;

export const createWidgetEvents = (message, ctx) => {
  const { eventName } = message;
  const isWidgetTriggerEvent = eventName === 'webwidget.triggered';
  if (
    isWidgetTriggerEvent &&
    UNREAD_OR_CAMPAIGN_ROUTES.includes(ctx.$route.name)
  ) {
    return;
  }
  ctx.$store.dispatch('events/create', { name: eventName });
};

export const handlers = {
  'config-set': (message, ctx) => {
    ctx.setLocale(message.locale);
    ctx.setBubbleLabel();
    ctx.fetchOldConversations().then(() => ctx.setUnreadView());
    ctx.fetchAvailableAgents(websiteToken());
    ctx.$store.dispatch('appConfig/setAppConfig', message);
    ctx.$store.dispatch('contacts/get');
    ctx.setCampaignReadData(message.campaignsSnoozedTill);
  },

  'widget-visible': (message, ctx) => {
    ctx.scrollConversationToBottom();
  },

  'change-url': (message, ctx) => {
    const { referrerURL, referrerHost } = message;
    ctx.$store.dispatch('campaign/initCampaigns', {
      currentURL: referrerURL,
      websiteToken: websiteToken(),
      isInBusinessHours: ctx.isInWorkingHours,
    });
    window.referrerURL = referrerURL;
    ctx.$store.dispatch('appConfig/setReferrerHost', referrerHost);
  },

  'toggle-close-button': (message, ctx) => {
    ctx.isMobile = message.isMobile;
  },

  'push-event': (message, ctx) => {
    createWidgetEvents(message, ctx);
  },

  'set-label': (message, ctx) => {
    ctx.$store.dispatch('conversationLabels/create', message.label);
  },

  'remove-label': (message, ctx) => {
    ctx.$store.dispatch('conversationLabels/destroy', message.label);
  },

  'set-user': (message, ctx) => {
    ctx.$store.dispatch('contacts/setUser', message);
  },

  'set-custom-attributes': (message, ctx) => {
    ctx.$store.dispatch(
      'contacts/setCustomAttributes',
      message.customAttributes
    );
  },

  'delete-custom-attribute': (message, ctx) => {
    ctx.$store.dispatch(
      'contacts/deleteCustomAttribute',
      message.customAttribute
    );
  },

  'set-conversation-custom-attributes': (message, ctx) => {
    ctx.$store.dispatch(
      'conversation/setCustomAttributes',
      message.customAttributes
    );
  },

  'delete-conversation-custom-attribute': (message, ctx) => {
    ctx.$store.dispatch(
      'conversation/deleteCustomAttribute',
      message.customAttribute
    );
  },

  'set-locale': (message, ctx) => {
    ctx.setLocale(message.locale);
    ctx.setBubbleLabel();
  },

  'set-color-scheme': (message, ctx) => {
    ctx.$store.dispatch('appConfig/setColorScheme', message.darkMode);
  },

  'toggle-open': (message, ctx) => {
    ctx.$store.dispatch('appConfig/toggleWidgetOpen', message.isOpen);

    const shouldShowMessageView =
      ['home'].includes(ctx.$route.name) && message.isOpen && ctx.messageCount;
    const shouldShowHomeView =
      !message.isOpen && UNREAD_OR_CAMPAIGN_ROUTES.includes(ctx.$route.name);

    if (shouldShowMessageView) {
      ctx.router.replace({ name: 'messages' });
    }
    if (shouldShowHomeView) {
      ctx.$store.dispatch('conversation/setUserLastSeen');
      ctx.unsetUnreadView();
      ctx.router.replace({ name: 'home' });
    }
    if (!message.isOpen) {
      ctx.$store.dispatch('campaign/resetCampaign');
    }
  },

  [SDK_SET_BUBBLE_VISIBILITY]: (message, ctx) => {
    ctx.$store.dispatch(
      'appConfig/setBubbleVisibility',
      message.hideMessageBubble
    );
  },
};

export default handlers;
