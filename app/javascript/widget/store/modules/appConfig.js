import {
  SET_BUBBLE_VISIBILITY,
  SET_COLOR_SCHEME,
  SET_REFERRER_HOST,
  SET_WIDGET_APP_CONFIG,
  SET_WIDGET_COLOR,
  TOGGLE_WIDGET_OPEN,
  SET_ROUTE_UPDATE_STATE,
  SET_PROFILE_CONFIG,
} from '../types';
import {
  PROFILE_CONFIG_DEFAULTS,
  profileConfigFromChannel,
} from 'widget/helpers/profileConfigHelper';

const state = {
  hideMessageBubble: false,
  isCampaignViewClicked: false,
  showUnreadMessagesDialog: true,
  isWebWidgetTriggered: false,
  isWidgetOpen: false,
  position: 'right',
  referrerHost: '',
  showPopoutButton: false,
  widgetColor: '',
  widgetStyle: 'standard',
  // Bloco 2.10. `auto` também aqui, e não só no SDK: este é o valor que vale no
  // intervalo entre o mount do widget e a chegada do `config-set` do host. Em
  // rede lenta esse intervalo é visível, e era ele que produzia o flash claro
  // antes do painel escurecer.
  darkMode: 'auto',
  isUpdatingRoute: false,
  welcomeTitle: '',
  welcomeDescription: '',
  availableMessage: '',
  unavailableMessage: '',
  enableFileUpload: undefined,
  enableEmojiPicker: true,
  enableEndConversation: true,
  // As 11 flags planas da §B.3. Nasce nos defaults do perfil `support` (A4) e é
  // re-hidratada a cada `setAppConfig` a partir de `window.chatwootWebChannel`.
  // Espelha o que `configMixin.profileConfig` entrega — os dois leem o MESMO
  // resolvedor, para não repetir o defeito produtor/consumidor da Onda 0.
  profileConfig: { ...PROFILE_CONFIG_DEFAULTS },
};

export const getters = {
  getAppConfig: $state => $state,
  isRightAligned: $state => $state.position === 'right',
  getHideMessageBubble: $state => $state.hideMessageBubble,
  getIsWidgetOpen: $state => $state.isWidgetOpen,
  getWidgetColor: $state => $state.widgetColor,
  getReferrerHost: $state => $state.referrerHost,
  isWidgetStyleFlat: $state => $state.widgetStyle === 'flat',
  darkMode: $state => $state.darkMode,
  getShowUnreadMessagesDialog: $state => $state.showUnreadMessagesDialog,
  getIsUpdatingRoute: _state => _state.isUpdatingRoute,
  getWelcomeHeading: $state => $state.welcomeTitle,
  getWelcomeTagline: $state => $state.welcomeDescription,
  getAvailableMessage: $state => $state.availableMessage,
  getUnavailableMessage: $state => $state.unavailableMessage,
  getShouldShowFilePicker: $state => $state.enableFileUpload,
  getShouldShowEmojiPicker: $state => $state.enableEmojiPicker,
  getCanUserEndConversation: $state => $state.enableEndConversation,
  getProfileConfig: $state => $state.profileConfig,
  getShowKnowledgeBase: $state => $state.profileConfig.showKnowledgeBase,
  getShowConversationList: $state => $state.profileConfig.showConversationList,
  getHomeLayout: $state => $state.profileConfig.homeLayout,
  isMarketingHome: $state => $state.profileConfig.homeLayout === 'marketing',
  getCaptureFlow: $state => $state.profileConfig.captureFlow,
  getPrimaryExit: $state => $state.profileConfig.primaryExit,
  getIsTeaserEnabled: $state => $state.profileConfig.teaserEnabled,
  getTeaserDelayMs: $state => $state.profileConfig.teaserDelayMs,
  getTeaserScrollPercent: $state => $state.profileConfig.teaserScrollPercent,
  getHasCsatOnResolve: $state => $state.profileConfig.csatOnResolve,
  getHasEmailContinuity: $state => $state.profileConfig.emailContinuity,
  getIsAiLabelPersistent: $state => $state.profileConfig.aiLabelPersistent,
};

export const actions = {
  setAppConfig(
    { commit },
    {
      showPopoutButton,
      position,
      hideMessageBubble,
      showUnreadMessagesDialog,
      widgetStyle = 'rounded',
      darkMode = 'auto',
      welcomeTitle = '',
      welcomeDescription = '',
      availableMessage = '',
      unavailableMessage = '',
      enableFileUpload = undefined,
      enableEmojiPicker = true,
      enableEndConversation = true,
      profileConfig,
    }
  ) {
    // `profileConfig` não vem pela ponte: o servidor o escreve em
    // `window.chatwootWebChannel` (3.04). O parâmetro existe para o teste e para um
    // eventual produtor futuro; quando ausente, lê da janela — e quando a janela também
    // não tem, o resolvedor devolve os defaults do perfil `support`.
    commit(
      SET_PROFILE_CONFIG,
      profileConfig
        ? profileConfigFromChannel({ profileConfig })
        : profileConfigFromChannel(window.chatwootWebChannel)
    );
    commit(SET_WIDGET_APP_CONFIG, {
      hideMessageBubble: !!hideMessageBubble,
      position: position || 'right',
      showPopoutButton: !!showPopoutButton,
      showUnreadMessagesDialog: !!showUnreadMessagesDialog,
      widgetStyle,
      darkMode,
      welcomeTitle,
      welcomeDescription,
      availableMessage,
      unavailableMessage,
      enableFileUpload,
      enableEmojiPicker,
      enableEndConversation,
    });
  },
  toggleWidgetOpen({ commit }, isWidgetOpen) {
    commit(TOGGLE_WIDGET_OPEN, isWidgetOpen);
  },
  setWidgetColor({ commit }, widgetColor) {
    commit(SET_WIDGET_COLOR, widgetColor);
  },
  setColorScheme({ commit }, darkMode) {
    commit(SET_COLOR_SCHEME, darkMode);
  },
  setReferrerHost({ commit }, referrerHost) {
    commit(SET_REFERRER_HOST, referrerHost);
  },
  setBubbleVisibility({ commit }, hideMessageBubble) {
    commit(SET_BUBBLE_VISIBILITY, hideMessageBubble);
  },
  setRouteTransitionState: async ({ commit }, status) => {
    // Handles the routing state during navigation to different screen
    // Called before the navigation starts and after navigation completes
    // Handling this state in app/javascript/widget/router.js
    // See issue: https://github.com/chatwoot/chatwoot/issues/10736
    commit(SET_ROUTE_UPDATE_STATE, status);
  },
};

export const mutations = {
  [SET_WIDGET_APP_CONFIG]($state, data) {
    $state.showPopoutButton = data.showPopoutButton;
    $state.position = data.position;
    $state.hideMessageBubble = data.hideMessageBubble;
    $state.widgetStyle = data.widgetStyle;
    $state.darkMode = data.darkMode;
    $state.locale = data.locale || $state.locale;
    $state.showUnreadMessagesDialog = data.showUnreadMessagesDialog;
    $state.welcomeTitle = data.welcomeTitle;
    $state.welcomeDescription = data.welcomeDescription;
    $state.availableMessage = data.availableMessage;
    $state.unavailableMessage = data.unavailableMessage;
    $state.enableFileUpload = data.enableFileUpload;
    $state.enableEmojiPicker = data.enableEmojiPicker;
    $state.enableEndConversation = data.enableEndConversation;
  },
  [TOGGLE_WIDGET_OPEN]($state, isWidgetOpen) {
    $state.isWidgetOpen = isWidgetOpen;
  },
  [SET_WIDGET_COLOR]($state, widgetColor) {
    $state.widgetColor = widgetColor;
  },
  [SET_REFERRER_HOST]($state, referrerHost) {
    $state.referrerHost = referrerHost;
  },
  [SET_BUBBLE_VISIBILITY]($state, hideMessageBubble) {
    $state.hideMessageBubble = hideMessageBubble;
  },
  [SET_COLOR_SCHEME]($state, darkMode) {
    $state.darkMode = darkMode;
  },
  [SET_ROUTE_UPDATE_STATE]($state, status) {
    $state.isUpdatingRoute = status;
  },
  [SET_PROFILE_CONFIG]($state, profileConfig) {
    $state.profileConfig = profileConfig;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
