import { profileConfigFromChannel } from 'widget/helpers/profileConfigHelper';

export default {
  computed: {
    useInboxAvatarForBot() {
      return this.channelConfig.enabledFeatures.includes(
        'use_inbox_avatar_for_bot'
      );
    },
    hasAConnectedAgentBot() {
      return !!window.chatwootWebChannel.hasAConnectedAgentBot;
    },
    inboxAvatarUrl() {
      return window.chatwootWebChannel.avatarUrl;
    },
    channelConfig() {
      return window.chatwootWebChannel;
    },
    hasEmojiPickerEnabled() {
      return this.channelConfig.enabledFeatures.includes('emoji_picker');
    },
    hasAttachmentsEnabled() {
      return this.channelConfig.enabledFeatures.includes('attachments');
    },
    hasEndConversationEnabled() {
      return this.channelConfig.enabledFeatures.includes('end_conversation');
    },
    preChatFormEnabled() {
      return window.chatwootWebChannel.preChatFormEnabled;
    },
    preChatFormOptions() {
      let preChatMessage = '';
      const options = window.chatwootWebChannel.preChatFormOptions || {};
      preChatMessage = options.pre_chat_message;
      const { pre_chat_fields: preChatFields = [] } = options;
      return {
        preChatMessage,
        preChatFields,
      };
    },
    /**
     * As flags planas do perfil (22-plano-widget §B.3, lista canônica de 11 chaves).
     *
     * Produtor: `WidgetProfile.resolve` (3.03) → os dois montadores (3.04).
     * Enquanto 3.04 não entrega a chave, isto devolve os defaults do perfil `support`,
     * que é o comportamento de hoje (A4) — a ausência não muda pixel nenhum.
     *
     * `widgetProfile` (o NOME do perfil) fica de fora de propósito: o widget lê flags,
     * nunca o nome. Ver o lint em `widget/specs/profileFlagsLint.spec.js`.
     */
    profileConfig() {
      return profileConfigFromChannel(this.channelConfig);
    },
    showKnowledgeBase() {
      return this.profileConfig.showKnowledgeBase;
    },
    showConversationList() {
      return this.profileConfig.showConversationList;
    },
    isMarketingHome() {
      return this.profileConfig.homeLayout === 'marketing';
    },
    isSupportHome() {
      return this.profileConfig.homeLayout === 'support';
    },
    isConversationalCapture() {
      return this.profileConfig.captureFlow === 'conversational';
    },
    hasWhatsAppExit() {
      return this.profileConfig.primaryExit === 'whatsapp';
    },
    isTeaserEnabled() {
      return this.profileConfig.teaserEnabled;
    },
    hasCsatOnResolve() {
      return this.profileConfig.csatOnResolve;
    },
    hasEmailContinuity() {
      return this.profileConfig.emailContinuity;
    },
    isAiLabelPersistent() {
      return this.profileConfig.aiLabelPersistent;
    },
    shouldShowPreChatForm() {
      const { preChatFields } = this.preChatFormOptions;
      // Check if at least one enabled field in pre-chat fields
      const hasEnabledFields =
        preChatFields.filter(field => field.enabled).length > 0;
      return this.preChatFormEnabled && hasEnabledFields;
    },
  },
};
