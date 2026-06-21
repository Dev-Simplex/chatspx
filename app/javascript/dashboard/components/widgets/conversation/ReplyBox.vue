<script>
import { defineAsyncComponent, useTemplateRef, ref, computed } from 'vue';
import { useGlobalDropZone } from 'dashboard/composables/useGlobalDropZone';
import GlobalDropOverlay from 'dashboard/components-next/message/GlobalDropOverlay.vue';
import AttachmentPreviewModal from 'dashboard/components-next/message/AttachmentPreviewModal.vue';
import ImageEditor from 'dashboard/components-next/message/ImageEditor.vue';
import { mapGetters } from 'vuex';
import { toast as sonnerToast } from 'vue-sonner';
import { useAlert } from 'dashboard/composables';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useTrack } from 'dashboard/composables';
import keyboardEventListenerMixins from 'shared/mixins/keyboardEventListenerMixins';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

import ReplyToMessage from './ReplyToMessage.vue';
import AttachmentPreview from 'dashboard/components/widgets/AttachmentsPreview.vue';
import ReplyTopPanel from 'dashboard/components/widgets/WootWriter/ReplyTopPanel.vue';
import ReplyEmailHead from './ReplyEmailHead.vue';
import ReplyBottomPanel from 'dashboard/components/widgets/WootWriter/ReplyBottomPanel.vue';
import CopilotReplyBottomPanel from 'dashboard/components/widgets/WootWriter/CopilotReplyBottomPanel.vue';
import ArticleSearchPopover from 'dashboard/routes/dashboard/helpcenter/components/ArticleSearch/SearchPopover.vue';
import CopilotEditorSection from './CopilotEditorSection.vue';
import CopilotMenuBar from 'dashboard/components/widgets/WootWriter/CopilotMenuBar.vue';
import { vOnClickOutside } from '@vueuse/components';
import ReplyBoxBanner from './ReplyBoxBanner.vue';
import AssignToReplyDialog from 'dashboard/components-next/Conversation/AssignToReplyDialog.vue';
import QuotedEmailPreview from './QuotedEmailPreview.vue';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';
import AudioRecorder from 'dashboard/components/widgets/WootWriter/AudioRecorder.vue';
import { AUDIO_FORMATS } from 'shared/constants/messages';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { CMD_AI_ASSIST } from 'dashboard/helper/commandbar/events';
import {
  getMessageVariables,
  getUndefinedVariablesInMessage,
  replaceVariablesInMessage,
} from '@chatwoot/utils';
import ContactAPI from 'dashboard/api/contacts';
import ConversationAPI from 'dashboard/api/conversations';
import WhatsappTemplates from './WhatsappTemplates/Modal.vue';
import WhatsappWindowExpired from './WhatsappTemplates/WhatsappWindowExpired.vue';
import ContentTemplates from './ContentTemplates/ContentTemplatesModal.vue';
import CannedResponseModal from 'dashboard/components-next/canned-response/CannedResponseModal.vue';
const LocationPickerModal = defineAsyncComponent(
  () => import('dashboard/components-next/location/LocationPickerModal.vue')
);
const ShareContactModal = defineAsyncComponent(
  () => import('dashboard/components-next/share-contact/ShareContactModal.vue')
);
import MessageApi from 'dashboard/api/inbox/message';
import { MESSAGE_MAX_LENGTH } from 'shared/helpers/MessageTypeHelper';
import inboxMixin, { INBOX_FEATURES } from 'shared/mixins/inboxMixin';
import { trimContent, debounce, getRecipients } from '@chatwoot/utils';
import wootConstants from 'dashboard/constants/globals';
import {
  extractQuotedEmailText,
  buildQuotedEmailHeader,
  truncatePreviewText,
  appendQuotedTextToMessage,
} from 'dashboard/helper/quotedEmailHelper';
import {
  CONVERSATION_EVENTS,
  CAPTAIN_EVENTS,
} from '../../../helper/AnalyticsHelper/events';
import fileUploadMixin from 'dashboard/mixins/fileUploadMixin';
import {
  appendSignature,
  removeSignature,
  getEffectiveChannelType,
} from 'dashboard/helper/editorHelper';
import { useCopilotReply } from 'dashboard/composables/useCopilotReply';
import { useCaptain } from 'dashboard/composables/useCaptain';
import { useKbd } from 'dashboard/composables/utils/useKbd';
import { useAIOnboarding } from 'dashboard/composables/useAIOnboarding';
import { useReducedMotion } from 'dashboard/composables/useReducedMotion';
import { useReplyAssignmentGate } from 'dashboard/composables/useReplyAssignmentGate';
import { useAIAssistantFlag } from 'dashboard/components-next/ai-assistant/composables/useAIAssistantFlag';
import { useAITour } from 'dashboard/components-next/ai-assistant/composables/useAITour';
import AIOnboardingCoachmark from './AIOnboardingCoachmark.vue';
import AISuggestionChip from 'dashboard/components-next/ai-assistant/AISuggestionChip.vue';
import { CAPTAIN_ERROR_TYPES } from 'dashboard/composables/captain/constants';
import {
  isFileTypeAllowedForChannel,
  buildAttachmentThumbUrl,
  revokeAttachmentThumbUrl,
} from 'shared/helpers/FileHelper';
import {
  DropdownContainer,
  DropdownBody,
  DropdownItem,
} from 'dashboard/components-next/dropdown-menu/base';

import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';
import { LocalStorage } from 'shared/helpers/localStorage';
import { emitter } from 'shared/helpers/mitt';
const EmojiInput = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiInput.vue')
);

const isWhatsAppValidationMessage = message =>
  typeof message === 'string' && message.toLowerCase().includes('whatsapp');

const whatsappAlertAction = message =>
  isWhatsAppValidationMessage(message)
    ? {
        variant: 'error',
        icon: 'i-lucide-message-circle-x',
        duration: 5000,
      }
    : null;

export default {
  components: {
    ArticleSearchPopover,
    AttachmentPreview,
    AttachmentPreviewModal,
    AudioRecorder,
    GlobalDropOverlay,
    ImageEditor,
    ReplyBoxBanner,
    AssignToReplyDialog,
    EmojiInput,
    ReplyBottomPanel,
    ReplyEmailHead,
    ReplyToMessage,
    ReplyTopPanel,
    ContentTemplates,
    WhatsappTemplates,
    WhatsappWindowExpired,
    CannedResponseModal,
    WootMessageEditor,
    QuotedEmailPreview,
    CopilotEditorSection,
    CopilotReplyBottomPanel,
    CopilotMenuBar,
    AIOnboardingCoachmark,
    AISuggestionChip,
    DropdownContainer,
    DropdownBody,
    DropdownItem,
    LocationPickerModal,
    ShareContactModal,
  },
  directives: {
    OnClickOutside: vOnClickOutside,
  },
  mixins: [inboxMixin, fileUploadMixin, keyboardEventListenerMixins],
  props: {
    popOutReplyBox: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['update:popOutReplyBox'],
  setup() {
    const {
      uiSettings,
      isEditorHotKeyEnabled,
      fetchSignatureFlagFromUISettings,
      setQuotedReplyFlagForInbox,
      fetchQuotedReplyFlagFromUISettings,
    } = useUISettings();

    const replyEditor = useTemplateRef('replyEditor');
    const messageEditor = useTemplateRef('messageEditor');
    const sparklesButtonRef = useTemplateRef('sparklesButtonRef');
    const copilot = useCopilotReply();

    // Drag-and-drop global estilo WhatsApp Web. Files arrastados sobre a
    // janela caem em `globalDropFiles`; o watcher abaixo (Options API)
    // processa cada arquivo via `onFileUpload` do fileUploadMixin e abre o
    // AttachmentPreviewModal automaticamente.
    const globalDropFiles = ref([]);
    const globalDropEnabled = ref(true);
    const { isOverDropZone: isGlobalDragActive } = useGlobalDropZone({
      enabled: computed(() => globalDropEnabled.value),
      onDrop: files => {
        globalDropFiles.value = files;
      },
    });
    const shortcutKey = useKbd(['$mod', '+', 'enter']);
    const { captainTasksEnabled, processEvent: captainProcessEvent } =
      useCaptain();
    const aiOnboarding = useAIOnboarding();
    const { prefersReducedMotion } = useReducedMotion();
    const aiAssistantFlag = useAIAssistantFlag();
    const aiTour = useAITour();
    const { isAssignmentGateEnabled } = useReplyAssignmentGate();

    return {
      uiSettings,
      isEditorHotKeyEnabled,
      fetchSignatureFlagFromUISettings,
      setQuotedReplyFlagForInbox,
      fetchQuotedReplyFlagFromUISettings,
      replyEditor,
      messageEditor,
      sparklesButtonRef,
      copilot,
      shortcutKey,
      captainTasksEnabled,
      captainProcessEvent,
      aiOnboarding,
      prefersReducedMotion,
      aiAssistantFlag,
      aiTour,
      isAssignmentGateEnabled,
      globalDropFiles,
      globalDropEnabled,
      isGlobalDragActive,
    };
  },
  data() {
    return {
      message: '',
      inReplyTo: {},
      isFocused: false,
      showEmojiPicker: false,
      attachedFiles: [],
      // Fase 3: modal de preview WhatsApp-fiel + editor de imagem
      showAttachmentModal: false,
      isSendingAttachment: false,
      showImageEditor: false,
      imageEditorFile: null,
      imageEditorMode: 'crop',
      imageEditorTargetIndex: -1,
      isRecordingAudio: false,
      recordingAudioState: '',
      recordingAudioDurationText: '00:00',
      replyType: REPLY_EDITOR_MODES.REPLY,
      bccEmails: '',
      ccEmails: '',
      toEmails: '',
      doAutoSaveDraft: () => {},
      showWhatsAppTemplatesModal: false,
      showContentTemplatesModal: false,
      showCannedResponseModal: false,
      showLocationPickerModal: false,
      showShareContactModal: false,
      updateEditorSelectionWith: '',
      undefinedVariableMessage: '',
      showMentions: false,
      showUserMentions: false,
      showCannedMenu: false,
      showVariablesMenu: false,
      showInlineCopilotMenu: false,
      newConversationModalActive: false,
      showArticleSearchPopover: false,
      hasRecordedAudio: false,
      pendingAudioAutoSend: false,
      pendingAudioConversationId: null,
      isUploadingAudio: false,
      // Envio "armado": fn de envio aguardando o término dos uploads em curso
      // (Enviar nunca bloqueia). Disparada por maybeFireArmedSend.
      armedSend: null,
      // Mapa uploadId → { echoId, pendingMessage, conversationId } das bolhas
      // "carregando" injetadas na conversa, para finalizar o POST ao concluir o
      // upload (mesmo echo_id) e atualizar progresso/falha na bolha certa.
      uploadBubbles: {},
      whatsappInvalidNotice: '',
      whatsappNoticeTimeoutId: null,
      isRevalidatingWhatsapp: false,
      copilotAcceptedMessages: {},
      isGhostSuggestionDismissed: false,
      remoteGhostSuggestion: '',
      ghostSuggestionFetchedFor: null,
      // === Phase 5 — AI suggestion chip preview state ===
      // null when no preview, or { text, isStreaming, errorType, action }
      aiSuggestionChip: null,
      aiSuggestionChipStartedAt: null,
      aiSuggestionChipAbortController: null,
      // D2/D6 — gate universal de resposta. `pendingGatePayloads` enfileira os
      // payloads que tomaram 422 `assignment_required` (multi-part empilha na
      // ordem); `gateConfirmedOnce` é o one-shot anti-loop do caminho proativo.
      pendingGatePayloads: [],
      gateConfirmedOnce: false,
    };
  },
  computed: {
    ...mapGetters({
      currentChat: 'getSelectedChat',
      messageSignature: 'getMessageSignature',
      currentUser: 'getCurrentUser',
      lastEmail: 'getLastEmailInSelectedChat',
      globalConfig: 'globalConfig/get',
      accountId: 'getCurrentAccountId',
      isFeatureEnabledonAccount: 'accounts/isFeatureEnabledonAccount',
    }),
    currentContact() {
      const senderId = this.currentChat?.meta?.sender?.id;
      if (!senderId) return {};
      return this.$store.getters['contacts/getContact'](senderId);
    },
    whatsappCustomAttributes() {
      const sender = this.currentChat?.meta?.sender || {};
      return (
        sender.custom_attributes ||
        sender.customAttributes ||
        this.currentContact?.customAttributes ||
        this.currentContact?.custom_attributes ||
        {}
      );
    },
    whatsappNumberExists() {
      const attributes = this.whatsappCustomAttributes || {};
      const snakeValue = attributes.whatsapp_number_exists;
      if (snakeValue !== undefined) return snakeValue;
      return attributes.whatsappNumberExists;
    },
    isWhatsappInvalid() {
      return this.whatsappNumberExists === false;
    },
    shouldBlockWhatsappSend() {
      return (
        !this.isPrivate &&
        (this.isAWhatsAppChannel || this.isAPIInbox) &&
        this.isWhatsappInvalid
      );
    },
    whatsappInvalidMessage() {
      return this.$t('CONVERSATION.REPLYBOX.WHATSAPP_INVALID');
    },
    whatsappBannerMessage() {
      if (this.whatsappInvalidNotice) return this.whatsappInvalidNotice;
      return this.shouldBlockWhatsappSend ? this.whatsappInvalidMessage : '';
    },
    shouldShowReplyToMessage() {
      // Phase 3.4: allow reply-to also on private notes so they thread.
      const featureAvailable =
        this.inboxHasFeature(INBOX_FEATURES.REPLY_TO) || this.isOnPrivateNote;
      return (
        this.inReplyTo?.id &&
        featureAvailable &&
        !this.is360DialogWhatsAppChannel &&
        !this.copilot.isActive.value
      );
    },
    showWhatsappTemplates() {
      // We support templates for API channels if someone updates templates manually via API
      // That's why we don't explicitly check for channel type here
      const templates = this.$store.getters['inboxes/getWhatsAppTemplates'](
        this.inboxId
      );
      return !!(templates && templates.length) && !this.isPrivate;
    },
    showContentTemplates() {
      return this.isATwilioWhatsAppChannel && !this.isPrivate;
    },
    isPrivate() {
      if (
        this.currentChat.can_reply ||
        this.isAWhatsAppChannel ||
        this.isAPIInbox
      ) {
        return this.isOnPrivateNote;
      }
      return true;
    },
    // D2: o gate de assunção é exigido quando o modo "atribuição obrigatória"
    // está ligado e a resposta NÃO é privada (DD-4: `isPrivate` cobre nota
    // explícita E nota forçada de canal sem `can_reply`). Variantes:
    //   (a) sem dono · (b) dono humano colega · (c) dona IA (agent_bot).
    // Variante (d) "fora do time" é resolvida dentro do dialog (myTeams).
    shouldShowAssignmentGate() {
      if (!this.isAssignmentGateEnabled) return false;
      if (this.isPrivate) return false;
      const assignee = this.currentChat?.meta?.assignee;
      if (!assignee) return true; // (a) sem dono
      if (assignee.type === 'agent_bot') return true; // (c) dona IA
      return assignee.id !== this.currentUser.id; // (b)/(d) colega/fora do time
    },
    isReplyRestricted() {
      return (
        !this.currentChat?.can_reply &&
        !(this.isAWhatsAppChannel || this.isAPIInbox)
      );
    },
    inboxId() {
      return this.currentChat.inbox_id;
    },
    inbox() {
      return this.$store.getters['inboxes/getInbox'](this.inboxId);
    },
    messagePlaceHolder() {
      if (this.isEditorDisabled) {
        if (this.isAWhatsAppChannel) {
          return this.$t('CONVERSATION.FOOTER.MESSAGING_RESTRICTED_WHATSAPP');
        }
        if (this.isAPIInbox) {
          return this.$t('CONVERSATION.FOOTER.MESSAGING_RESTRICTED_API');
        }
        return this.$t('CONVERSATION.FOOTER.MESSAGING_RESTRICTED');
      }
      // Email channels keep the verbose Chatwoot placeholder; everything else
      // adopts the WhatsApp-style "Mensagem" / "Message" copy from REPLYBOX.
      if (this.isAnEmailChannel) {
        return this.isPrivate
          ? this.$t('CONVERSATION.FOOTER.PRIVATE_MSG_INPUT')
          : this.$t('CONVERSATION.REPLYBOX.PLACEHOLDER_EMAIL');
      }
      return this.isPrivate
        ? this.$t('CONVERSATION.FOOTER.PRIVATE_MSG_INPUT')
        : this.$t('CONVERSATION.REPLYBOX.PLACEHOLDER');
    },
    isMessageLengthReachingThreshold() {
      return this.message.length > this.maxLength - 50;
    },
    charactersRemaining() {
      return this.maxLength - this.message.length;
    },
    isReplyButtonDisabled() {
      if (this.shouldBlockWhatsappSend) return true;
      if (this.isEditorDisabled) return true;
      if (this.isATwitterInbox) return true;
      // Com anexos: o envio NÃO bloqueia quando algo está subindo (arma e segue
      // em 2º plano, e a conversa continua). Bloqueia só se há anexo FALHO ainda
      // NÃO committed (no modal, antes de mandar) — aí força retry/remover. Uma
      // falha em 2º plano (committed) não interrompe a conversa.
      if (this.hasAttachments || this.hasRecordedAudio) {
        return this.attachedFiles.some(
          a => a.uploadStatus === 'failed' && !a.committed
        );
      }
      if (this.isRecordingAudio) {
        return this.recordingAudioState === 'processing';
      }

      return (
        this.isMessageEmpty ||
        this.message.length === 0 ||
        this.message.length > this.maxLength
      );
    },
    sender() {
      return {
        name: this.currentUser.name,
        thumbnail: this.currentUser.avatar_url,
      };
    },
    conversationType() {
      const { additional_attributes: additionalAttributes } = this.currentChat;
      const type = additionalAttributes ? additionalAttributes.type : '';
      return type || '';
    },
    maxLength() {
      if (this.isPrivate) {
        return MESSAGE_MAX_LENGTH.GENERAL;
      }
      if (this.isAFacebookInbox) {
        return MESSAGE_MAX_LENGTH.FACEBOOK;
      }
      if (this.isAnInstagramChannel) {
        return MESSAGE_MAX_LENGTH.INSTAGRAM;
      }
      if (this.isATiktokChannel) {
        return MESSAGE_MAX_LENGTH.TIKTOK;
      }
      if (this.isATwilioWhatsAppChannel) {
        return MESSAGE_MAX_LENGTH.TWILIO_WHATSAPP;
      }
      if (this.isAWhatsAppCloudChannel) {
        return MESSAGE_MAX_LENGTH.WHATSAPP_CLOUD;
      }
      if (this.isASmsInbox) {
        return MESSAGE_MAX_LENGTH.TWILIO_SMS;
      }
      if (this.isAnEmailChannel) {
        return MESSAGE_MAX_LENGTH.EMAIL;
      }
      if (this.isATwilioSMSChannel) {
        return MESSAGE_MAX_LENGTH.TWILIO_SMS;
      }
      if (this.isAWhatsAppChannel) {
        return MESSAGE_MAX_LENGTH.WHATSAPP_CLOUD;
      }
      return MESSAGE_MAX_LENGTH.GENERAL;
    },
    showFileUpload() {
      return (
        this.isAWebWidgetInbox ||
        this.isAFacebookInbox ||
        this.isAWhatsAppChannel ||
        this.isAPIInbox ||
        this.isAnEmailChannel ||
        this.isASmsInbox ||
        this.isATelegramChannel ||
        this.isALineChannel ||
        this.isAnInstagramChannel ||
        this.isATiktokChannel
      );
    },
    replyButtonLabel() {
      let sendMessageText = this.$t('CONVERSATION.REPLYBOX.SEND');
      if (this.isPrivate) {
        sendMessageText = this.$t('CONVERSATION.REPLYBOX.CREATE');
      }
      const keyLabel = this.isEditorHotKeyEnabled('cmd_enter')
        ? `(${this.shortcutKey})`
        : '(↵)';
      return `${sendMessageText} ${keyLabel}`;
    },
    replyBoxClass() {
      return {
        'is-private': this.isPrivate,
        'is-focused': this.isFocused || this.hasAttachments,
        'is-collapsed': this.isComposerCollapsed,
      };
    },
    // Visual compact mode à la WhatsApp Web: single-line input when empty AND
    // not focused. Expands as soon as the agent clicks/tabs in or types.
    isComposerCollapsed() {
      if (this.isFocused) return false;
      if (!this.isMessageEmpty) return false;
      if (this.hasAttachments) return false;
      if (this.isRecordingAudio || this.hasRecordedAudio) return false;
      if (this.copilot.isActive.value) return false;
      return true;
    },
    shouldShowGhostSuggestion() {
      if (this.isGhostSuggestionDismissed) return false;
      if (this.isComposerCollapsed) return false;
      if (!this.isMessageEmpty) return false;
      if (this.isEditorDisabled || this.isPrivate) return false;
      if (this.hasAttachments || this.isRecordingAudio) return false;
      const msg = this.lastIncomingMessage;
      if (!msg || !msg.created_at) return false;
      const ageMs = Date.now() - Number(msg.created_at) * 1000;
      return ageMs >= 0 && ageMs <= 30 * 1000;
    },
    lastIncomingMessage() {
      const messages = this.currentChat?.messages || [];
      for (let i = messages.length - 1; i >= 0; i -= 1) {
        const m = messages[i];
        if (m && m.message_type === 0 && !m.private) return m;
      }
      return null;
    },
    ghostSuggestionText() {
      if (this.remoteGhostSuggestion) return this.remoteGhostSuggestion;
      const suggestions = [
        'Obrigado pelo contato! Como posso ajudar?',
        'Oi! Tudo bem? Em que posso ajudar?',
        'Um momento, vou verificar aqui pra você.',
        'Perfeito, já tomei nota!',
      ];
      const id = Number(this.currentChat?.id) || 0;
      return suggestions[Math.abs(id) % suggestions.length];
    },
    hasAttachments() {
      return this.attachedFiles.length;
    },
    // Anexos que ainda estão SENDO COMPOSTOS (não committed). Os committed já
    // viraram bolha "carregando" na conversa e sobem em 2º plano — somem do
    // composer/modal e nunca entram num envio normal (evita duplicar).
    composerAttachedFiles() {
      return this.attachedFiles.filter(a => !a.committed);
    },
    hasComposerAttachments() {
      return this.composerAttachedFiles.length > 0;
    },
    // True while any attachment is still transferring (DirectUpload) or failed —
    // used to gate Send so we never post a message with a missing signed id.
    hasPendingAttachmentUpload() {
      return this.attachedFiles.some(
        a => a.uploadStatus === 'uploading' || a.uploadStatus === 'failed'
      );
    },
    // Anexo ainda subindo que AINDA NÃO foi "enviado" (committed): o primeiro
    // clique em Enviar arma o envio dele. Depois de committed, ele sobe em 2º
    // plano e não interfere mais nos envios de texto.
    hasUncommittedPendingUpload() {
      return this.attachedFiles.some(
        a => a.uploadStatus === 'uploading' && !a.committed
      );
    },
    showAudioRecorder() {
      return !this.isOnPrivateNote && this.showFileUpload;
    },
    showAudioRecorderEditor() {
      return this.showAudioRecorder && this.isRecordingAudio;
    },
    isOnPrivateNote() {
      return this.replyType === REPLY_EDITOR_MODES.NOTE;
    },
    isOnExpandedLayout() {
      const {
        LAYOUT_TYPES: { CONDENSED },
      } = wootConstants;
      const { conversation_display_type: conversationDisplayType = CONDENSED } =
        this.uiSettings;
      return conversationDisplayType !== CONDENSED;
    },
    isMessageEmpty() {
      if (!this.message) {
        return true;
      }
      return !this.message.trim().replace(/\n/g, '').length;
    },
    showReplyHead() {
      return !this.isOnPrivateNote && this.isAnEmailChannel;
    },
    enableMultipleFileUpload() {
      return (
        this.isAnEmailChannel ||
        this.isAWebWidgetInbox ||
        this.isAPIInbox ||
        this.isAWhatsAppChannel ||
        this.isATelegramChannel
      );
    },
    isSignatureEnabledForInbox() {
      return !this.isPrivate && this.sendWithSignature;
    },
    isSignatureAvailable() {
      return !!this.messageSignature;
    },
    sendWithSignature() {
      return this.fetchSignatureFlagFromUISettings(this.channelType);
    },
    conversationId() {
      return this.currentChat.id;
    },
    conversationIdByRoute() {
      return this.conversationId;
    },
    editorStateId() {
      return `draft-${this.conversationIdByRoute}-${this.replyType}`;
    },
    audioRecordFormat() {
      if (this.isAWhatsAppChannel || this.isATelegramChannel) {
        return AUDIO_FORMATS.MP3;
      }
      if (this.isAPIInbox) {
        return AUDIO_FORMATS.MP3;
      }
      return AUDIO_FORMATS.WAV;
    },
    messageVariables() {
      const variables = getMessageVariables({
        conversation: this.currentChat,
        contact: this.currentContact,
        inbox: this.inbox,
      });
      return variables;
    },
    connectedPortalSlug() {
      const { help_center: portal = {} } = this.inbox;
      const { slug = '' } = portal;
      return slug;
    },
    isQuotedEmailReplyEnabled() {
      return this.isFeatureEnabledonAccount(
        this.accountId,
        FEATURE_FLAGS.QUOTED_EMAIL_REPLY
      );
    },
    quotedReplyPreference() {
      if (!this.isAnEmailChannel || !this.isQuotedEmailReplyEnabled) {
        return false;
      }

      return !!this.fetchQuotedReplyFlagFromUISettings(this.channelType);
    },
    lastEmailWithQuotedContent() {
      if (!this.isAnEmailChannel) {
        return null;
      }

      const lastEmail = this.lastEmail;
      if (!lastEmail || lastEmail.private) {
        return null;
      }

      return lastEmail;
    },
    quotedEmailText() {
      return extractQuotedEmailText(this.lastEmailWithQuotedContent);
    },
    quotedEmailPreviewText() {
      return truncatePreviewText(this.quotedEmailText, 80);
    },
    shouldShowQuotedReplyToggle() {
      return (
        this.isAnEmailChannel &&
        !this.isOnPrivateNote &&
        this.isQuotedEmailReplyEnabled
      );
    },
    shouldShowQuotedPreview() {
      return (
        this.shouldShowQuotedReplyToggle &&
        this.quotedReplyPreference &&
        !!this.quotedEmailText
      );
    },
    isDefaultEditorMode() {
      return !this.showAudioRecorderEditor && !this.copilot.isActive.value;
    },
    isEditorDisabled() {
      return (
        (this.isAWhatsAppChannel || this.isAPIInbox) &&
        !this.isOnPrivateNote &&
        !this.currentChat.can_reply
      );
    },
    showWhatsappWindowExpired() {
      return (
        this.isAWhatsAppChannel &&
        !this.isOnPrivateNote &&
        !this.currentChat.can_reply
      );
    },
    // ==== WhatsApp single-row composer bar (Phase C true rewrite) ====
    // Renders a single horizontal pill [+ anexar][😀 emoji][input][🔒][✨][⛶][🎤/➤]
    // when none of the legacy alternative editors are active.
    useWaComposerBar() {
      // Pill é sempre o root quando não é email e a janela WA não expirou.
      // Conteúdo central (input, audio, copilot) é trocado DENTRO do pill —
      // não cai mais no fluxo legacy quando audio/copilot são ativados.
      return !this.isAnEmailChannel && !this.showWhatsappWindowExpired;
    },
    waMode() {
      // Estados visuais possíveis dentro do pill.
      if (this.showAudioRecorderEditor) return 'audio';
      if (this.copilot.isActive.value) return 'copilot';
      return 'input';
    },
    audioStateIcon() {
      switch (this.recordingAudioState) {
        case 'recording':
        case 'playing':
          return 'i-lucide-pause';
        case 'recording_paused':
        case 'paused':
        case 'stopped':
          return 'i-lucide-play';
        case 'processing':
          return 'i-lucide-square';
        default:
          return 'i-lucide-play';
      }
    },
    audioStateTitle() {
      if (this.recordingAudioState === 'processing') {
        return this.$t('CONVERSATION.REPLYBOX.RECORD');
      }
      return ['recording', 'playing'].includes(this.recordingAudioState)
        ? this.$t('CONVERSATION.REPLYBOX.RECORD')
        : this.$t('CONVERSATION.REPLYBOX.RECORD');
    },
    hasMessageContent() {
      const hasText = (this.message || '').trim().length > 0;
      return hasText || this.hasAttachments || this.hasRecordedAudio;
    },
    canShowCopilotInline() {
      return this.captainTasksEnabled && !this.isOnPrivateNote;
    },
    shouldShowAIOnboarding() {
      // Coachmark + pulse só fazem sentido se o sparkles está visível e o
      // menu inline ainda não foi aberto pela 1ª vez.
      return (
        this.canShowCopilotInline &&
        this.aiOnboarding.shouldShowOnboarding.value &&
        !this.showInlineCopilotMenu
      );
    },
    sparklesOnboardingClass() {
      if (!this.shouldShowAIOnboarding) return null;
      return this.prefersReducedMotion
        ? 'is-onboarding-static'
        : 'is-onboarding';
    },
    sparklesAriaDescribedBy() {
      return this.shouldShowAIOnboarding ? 'ai-onboarding-coachmark' : null;
    },
    waLockIcon() {
      return this.isOnPrivateNote ? 'i-lucide-lock' : 'i-lucide-lock-open';
    },
    waLockTooltip() {
      return this.isOnPrivateNote
        ? this.$t('CONVERSATION.REPLYBOX.LOCK_OFF_TOOLTIP')
        : this.$t('CONVERSATION.REPLYBOX.LOCK_ON_TOOLTIP');
    },
    showAttachInBar() {
      if (this.isEditorDisabled) return false;
      return (
        this.showFileUpload ||
        this.isOnPrivateNote ||
        this.showWhatsappTemplates ||
        this.showContentTemplates
      );
    },
    showAudioInBar() {
      if (this.isEditorDisabled) return false;
      if (this.isALineChannel || this.isATiktokChannel) return false;
      return (
        this.isFeatureEnabledonAccount(
          this.accountId,
          FEATURE_FLAGS.VOICE_RECORDER
        ) && this.showAudioRecorder
      );
    },
  },
  watch: {
    // Processa arquivos arrastados pelo overlay global (Fase 3 drag-drop WA).
    globalDropFiles(files) {
      if (!files || files.length === 0) return;
      files.forEach(file => this.handleGlobalDroppedFile(file));
      // Limpa o ref pra permitir novo drop sequencial
      this.globalDropFiles = [];
    },
    // Abre/fecha o modal conforme os anexos EM COMPOSIÇÃO (não-committed). Ao
    // enviar, os anexos viram bolha "carregando" na conversa (committed) e somem
    // do composer → o modal fecha sozinho e o usuário vê a bolha no chat.
    'composerAttachedFiles.length': function watchComposerAttachedFilesLength(
      newLen
    ) {
      if (newLen > 0 && !this.showAttachmentModal) {
        this.showAttachmentModal = true;
      } else if (newLen === 0) {
        this.showAttachmentModal = false;
      }
    },
    // Desativa drop global quando o modal de nova conversa está aberto
    newConversationModalActive(active) {
      this.globalDropEnabled = !active;
    },
    currentChat(conversation, oldConversation) {
      const { can_reply: canReply } = conversation;
      if (oldConversation && oldConversation.id !== conversation.id) {
        // Only update email fields when switching to a completely different conversation (by ID)
        // This prevents overwriting user input (e.g., CC/BCC fields) when performing actions
        // like self-assign or other updates that do not actually change the conversation context
        this.setCCAndToEmailsFromLastChat();
        // Reset Copilot editor state (includes cancelling ongoing generation)
        this.copilot.reset();
        // Phase 5 — clear chip preview when navigating to a different conversation
        this.discardAiSuggestionChip({ trackReason: 'context_switch' });
      }

      if (this.isOnPrivateNote) {
        return;
      }

      if (canReply || this.isAWhatsAppChannel || this.isAPIInbox) {
        this.replyType = REPLY_EDITOR_MODES.REPLY;
      } else {
        this.replyType = REPLY_EDITOR_MODES.NOTE;
      }

      this.clearWhatsappInvalidNotice();
      this.fetchAndSetReplyTo();
    },
    // When moving from one conversation to another, the store may not have the
    // list of all the messages. A fetch is subsequently made to get the messages.
    // This watcher handles two main cases:
    // 1. When switching conversations and messages are fetched/updated, ensures CC/BCC fields are set from the latest OUTGOING/INCOMING email (not activity/private messages).
    // 2. Fixes and issue where CC/BCC fields could be reset/lost after assignment/activity actions or message mutations that did not represent a true email context change.
    lastEmail: {
      handler(lastEmail) {
        if (!lastEmail) return;
        this.setCCAndToEmailsFromLastChat();
      },
      deep: true,
    },
    conversationIdByRoute(conversationId, oldConversationId) {
      if (conversationId !== oldConversationId) {
        this.setToDraft(oldConversationId, this.replyType);
        this.getFromDraft();
        this.resetRecorderAndClearAttachments();
        this.isGhostSuggestionDismissed = false;
        this.remoteGhostSuggestion = '';
        this.ghostSuggestionFetchedFor = null;
        this.focusReplyEditor();
      }
    },
    'lastIncomingMessage.id': {
      handler(newId) {
        if (!newId) return;
        if (this.ghostSuggestionFetchedFor === newId) return;
        if (this.isPrivate || this.isEditorDisabled) return;
        this.fetchRemoteGhostSuggestion(newId);
      },
      immediate: true,
    },
    message() {
      // Autosave the current message draft.
      this.doAutoSaveDraft();
    },
    replyType(updatedReplyType, oldReplyType) {
      this.setToDraft(this.conversationIdByRoute, oldReplyType);
      this.getFromDraft();
      // WhatsApp-style toast confirming the mode flip
      if (oldReplyType !== updatedReplyType) {
        const key =
          updatedReplyType === REPLY_EDITOR_MODES.NOTE
            ? 'CONVERSATION.REPLYBOX.PRIVATE_NOTE_TOAST_ON'
            : 'CONVERSATION.REPLYBOX.PRIVATE_NOTE_TOAST_OFF';
        useAlert(this.$t(key));
      }
    },
  },

  mounted() {
    this.getFromDraft();
    // Don't use the keyboard listener mixin here as the events here are supposed to be
    // working even if the editor is focussed.
    document.addEventListener('paste', this.onPaste);
    document.addEventListener('keydown', this.handleKeyEvents);
    this.setCCAndToEmailsFromLastChat();
    this.doAutoSaveDraft = debounce(
      () => {
        this.saveDraft(this.conversationIdByRoute, this.replyType);
      },
      500,
      true
    );

    this.fetchAndSetReplyTo();
    emitter.on(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.onReplyToMessage);

    // A hacky fix to solve the drag and drop
    // Is showing on top of new conversation modal drag and drop
    // TODO need to find a better solution
    emitter.on(
      BUS_EVENTS.NEW_CONVERSATION_MODAL,
      this.onNewConversationModalActive
    );
    emitter.on(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, this.addIntoEditor);
    emitter.on(
      BUS_EVENTS.OPEN_WHATSAPP_TEMPLATE_MODAL,
      this.openWhatsappTemplateModal
    );
    emitter.on(CMD_AI_ASSIST, this.executeCopilotAction);

    // Foco inicial ao montar o composer (abrir conversa direto pela URL/refresh).
    this.focusReplyEditor();
  },
  unmounted() {
    document.removeEventListener('paste', this.onPaste);
    document.removeEventListener('keydown', this.handleKeyEvents);
    emitter.off(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.onReplyToMessage);
    emitter.off(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, this.addIntoEditor);
    emitter.off(
      BUS_EVENTS.OPEN_WHATSAPP_TEMPLATE_MODAL,
      this.openWhatsappTemplateModal
    );
    emitter.off(
      BUS_EVENTS.NEW_CONVERSATION_MODAL,
      this.onNewConversationModalActive
    );
    if (this.whatsappNoticeTimeoutId) {
      clearTimeout(this.whatsappNoticeTimeoutId);
      this.whatsappNoticeTimeoutId = null;
    }
    emitter.off(CMD_AI_ASSIST, this.executeCopilotAction);
    // Release any pending attachment preview object URLs.
    this.attachedFiles.forEach(att => revokeAttachmentThumbUrl(att.thumb));
  },
  methods: {
    // Fase 3 — pipeline drag-drop WhatsApp-fiel
    handleGlobalDroppedFile(file) {
      if (!file || !file.size) return;
      const isAllowed = isFileTypeAllowedForChannel(file, {
        channelType: this.channelType || this.inbox?.channel_type,
        medium: this.inbox?.medium,
        conversationType: this.conversationType,
        isInstagramChannel: this.isAnInstagramChannel,
        isOnPrivateNote: this.isOnPrivateNote,
      });
      if (!isAllowed) {
        useAlert(
          this.$t('CONVERSATION.FILE_TYPE_NOT_SUPPORTED', {
            fileName: file.name,
          })
        );
        return;
      }
      const { name, type, size } = file;
      this.onFileUpload({ name, type, size, file });
    },
    onAttachmentModalSend() {
      if (this.isSendingAttachment) return;
      this.isSendingAttachment = true;
      try {
        this.onSendReply();
      } finally {
        this.$nextTick(() => {
          this.isSendingAttachment = false;
          // Ao enviar com anexo subindo, a mídia vira bolha "carregando" na
          // conversa (committed) e some do composer → o watcher de
          // composerAttachedFiles fecha o modal sozinho. Nada a fazer aqui.
        });
      }
    },
    onAttachmentModalClose() {
      this.clearAttachedFiles();
      this.showAttachmentModal = false;
    },
    onAttachmentModalAddMore() {
      // Reaproveita o input file do ReplyBottomPanel (vue-upload-component)
      const input = document.getElementById('conversationAttachment');
      if (input) input.click();
    },
    onEditImage({ file, action }) {
      if (!file) return;
      const idx = this.attachedFiles.findIndex(f => f === file);
      if (idx < 0) return;
      this.imageEditorTargetIndex = idx;
      this.imageEditorFile = file;
      this.imageEditorMode = action || 'crop';
      this.showImageEditor = true;
    },
    onImageEditorApply(blob) {
      const idx = this.imageEditorTargetIndex;
      if (idx >= 0 && blob) {
        const current = this.attachedFiles[idx];
        if (current) {
          const editedFile = new File(
            [blob],
            current.resource?.name || `edited_${Date.now()}.jpg`,
            { type: 'image/jpeg' }
          );
          // Drop the previous preview URL before replacing it.
          revokeAttachmentThumbUrl(current.thumb);
          this.attachedFiles.splice(idx, 1, {
            ...current,
            resource: editedFile,
            thumb: URL.createObjectURL(editedFile),
            blobSignedId: undefined,
          });
        }
      }
      this.closeImageEditor();
    },
    onImageEditorCancel() {
      this.closeImageEditor();
    },
    closeImageEditor() {
      this.showImageEditor = false;
      this.imageEditorFile = null;
      this.imageEditorTargetIndex = -1;
    },
    showWhatsappInvalidNotice(message) {
      this.whatsappInvalidNotice = message;
      if (this.whatsappNoticeTimeoutId) {
        clearTimeout(this.whatsappNoticeTimeoutId);
      }
      this.whatsappNoticeTimeoutId = setTimeout(() => {
        this.whatsappInvalidNotice = '';
        this.whatsappNoticeTimeoutId = null;
      }, 8000);
    },
    async revalidateWhatsappNumber() {
      if (this.isRevalidatingWhatsapp) return;

      const contactId =
        this.currentChat?.meta?.sender?.id || this.currentContact?.id;
      if (!contactId) return;

      this.isRevalidatingWhatsapp = true;
      try {
        const { data } = await ContactAPI.revalidateWhatsapp(contactId);
        if (data.whatsapp_number_exists) {
          this.clearWhatsappInvalidNotice();
          useAlert(
            this.$t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE_SUCCESS')
          );
          this.$store.dispatch('contacts/updateContact', {
            id: contactId,
            custom_attributes: {
              ...this.whatsappCustomAttributes,
              whatsapp_number_exists: true,
            },
          });
          const sender = this.currentChat?.meta?.sender;
          if (sender) {
            sender.custom_attributes = {
              ...sender.custom_attributes,
              whatsapp_number_exists: true,
            };
          }
        } else {
          this.showWhatsappInvalidNotice(
            this.$t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE_STILL_INVALID')
          );
        }
      } catch (error) {
        const status = error?.response?.status;
        const message =
          status === 429
            ? this.$t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE_COOLDOWN')
            : this.$t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE_ERROR');
        this.showWhatsappInvalidNotice(message);
      } finally {
        this.isRevalidatingWhatsapp = false;
      }
    },
    clearWhatsappInvalidNotice() {
      if (this.whatsappNoticeTimeoutId) {
        clearTimeout(this.whatsappNoticeTimeoutId);
      }
      this.whatsappNoticeTimeoutId = null;
      this.whatsappInvalidNotice = '';
    },
    getDraftKey(
      conversationId = this.conversationIdByRoute,
      replyType = this.replyType
    ) {
      return `draft-${conversationId}-${replyType}`;
    },
    getCopilotAcceptedMessage(replyType = this.replyType) {
      const key = this.getDraftKey(this.conversationIdByRoute, replyType);
      return this.copilotAcceptedMessages[key] || '';
    },
    setCopilotAcceptedMessage(message, replyType = this.replyType) {
      const key = this.getDraftKey(this.conversationIdByRoute, replyType);
      this.copilotAcceptedMessages[key] = trimContent(message || '');
    },
    clearCopilotAcceptedMessage(replyType = this.replyType) {
      const key = this.getDraftKey(this.conversationIdByRoute, replyType);
      delete this.copilotAcceptedMessages[key];
    },
    handleInsert(article) {
      const { url, title } = article;
      // Removing empty lines from the title
      const lines = title.split('\n');
      const nonEmptyLines = lines.filter(line => line.trim() !== '');
      const filteredMarkdown = nonEmptyLines.join(' ');
      emitter.emit(
        BUS_EVENTS.INSERT_INTO_RICH_EDITOR,
        `[${filteredMarkdown}](${url})`
      );

      useTrack(CONVERSATION_EVENTS.INSERT_ARTICLE_LINK);
    },
    toggleQuotedReply() {
      if (!this.isAnEmailChannel) {
        return;
      }

      const nextValue = !this.quotedReplyPreference;
      this.setQuotedReplyFlagForInbox(this.channelType, nextValue);
    },
    shouldIncludeQuotedEmail() {
      return (
        this.isQuotedEmailReplyEnabled &&
        this.quotedReplyPreference &&
        this.shouldShowQuotedReplyToggle &&
        !!this.quotedEmailText
      );
    },
    getMessageWithQuotedEmailText(message) {
      if (!this.shouldIncludeQuotedEmail()) {
        return message;
      }

      const quotedText = this.quotedEmailText || '';
      const header = buildQuotedEmailHeader(
        this.lastEmailWithQuotedContent,
        this.currentContact,
        this.inbox
      );

      return appendQuotedTextToMessage(message, quotedText, header);
    },
    resetRecorderAndClearAttachments() {
      // Reset audio recorder UI state
      this.resetAudioRecorderInput();
      // Reset attached files
      this.clearAttachedFiles();
    },
    saveDraft(conversationId, replyType) {
      if (this.message || this.message === '') {
        const key = this.getDraftKey(conversationId, replyType);
        const draftToSave = trimContent(this.message || '');

        this.$store.dispatch('draftMessages/set', {
          key,
          message: draftToSave,
        });
      }
    },
    setToDraft(conversationId, replyType) {
      this.saveDraft(conversationId, replyType);
      this.message = '';
    },
    getFromDraft() {
      if (this.conversationIdByRoute) {
        const key = this.getDraftKey();
        const messageFromStore =
          this.$store.getters['draftMessages/get'](key) || '';

        // ensure that the message has signature set based on the ui setting
        this.message = this.toggleSignatureForDraft(messageFromStore);
      }
    },
    toggleSignatureForDraft(message) {
      if (this.isPrivate) {
        return message;
      }

      const effectiveChannelType = getEffectiveChannelType(
        this.channelType,
        this.inbox?.medium || ''
      );
      return this.sendWithSignature
        ? appendSignature(message, this.messageSignature, effectiveChannelType)
        : removeSignature(message, this.messageSignature, effectiveChannelType);
    },
    removeFromDraft() {
      if (this.conversationIdByRoute) {
        const key = this.getDraftKey();
        this.$store.dispatch('draftMessages/delete', { key });
      }
    },
    getElementToBind() {
      return this.replyEditor;
    },
    getKeyboardEvents() {
      return {
        Escape: {
          action: () => {
            this.hideEmojiPicker();
            if (this.shouldShowGhostSuggestion) {
              this.dismissGhostSuggestion();
            }
          },
          allowOnFocusedInput: true,
        },
        Tab: {
          action: e => {
            if (this.shouldShowGhostSuggestion) {
              e.preventDefault();
              this.acceptGhostSuggestion();
            }
          },
          allowOnFocusedInput: true,
        },
        '$mod+KeyK': {
          action: e => {
            e.preventDefault();
            const ninja = document.querySelector('ninja-keys');
            ninja.open();
          },
          allowOnFocusedInput: true,
        },
        Enter: {
          action: e => {
            if (this.isAValidEvent('enter')) {
              this.onSendReply();
              e.preventDefault();
            }
          },
          allowOnFocusedInput: true,
        },
        '$mod+Enter': {
          action: () => {
            if (this.copilot.isActive.value && this.isFocused) {
              this.onSubmitCopilotReply();
            } else if (this.isAValidEvent('cmd_enter')) {
              this.onSendReply();
            }
          },
          allowOnFocusedInput: true,
        },
      };
    },
    isAValidEvent(selectedKey) {
      return (
        !this.showUserMentions &&
        !this.showMentions &&
        !this.showCannedMenu &&
        !this.showVariablesMenu &&
        this.isFocused &&
        this.isEditorHotKeyEnabled(selectedKey)
      );
    },
    onPaste(e) {
      // Don't handle paste if compose new conversation modal is open
      if (this.newConversationModalActive) return;

      // Don't handle paste if editor is disabled
      if (this.isEditorDisabled) return;

      // Filter valid files (non-zero size)
      Array.from(e.clipboardData.files)
        .filter(file => file.size > 0)
        .filter(file => {
          const isAllowed = isFileTypeAllowedForChannel(file, {
            channelType: this.channelType || this.inbox?.channel_type,
            medium: this.inbox?.medium,
            conversationType: this.conversationType,
            isInstagramChannel: this.isAnInstagramChannel,
            isOnPrivateNote: this.isOnPrivateNote,
          });

          if (!isAllowed) {
            useAlert(
              this.$t('CONVERSATION.FILE_TYPE_NOT_SUPPORTED', {
                fileName: file.name,
              })
            );
          }

          return isAllowed;
        })
        .forEach(file => {
          const { name, type, size } = file;
          this.onFileUpload({ name, type, size, file });
        });
    },
    toggleUserMention(currentMentionState) {
      this.showUserMentions = currentMentionState;
    },
    toggleCannedMenu(value) {
      this.showCannedMenu = value;
    },
    toggleVariablesMenu(value) {
      this.showVariablesMenu = value;
    },
    openWhatsappTemplateModal() {
      this.showWhatsAppTemplatesModal = true;
    },
    openScheduleMessage() {
      if (!this.currentChat?.id) return;
      emitter.emit('open-schedule-message-form');
    },
    hideWhatsappTemplatesModal() {
      this.showWhatsAppTemplatesModal = false;
    },
    onExpiredSendTemplate() {
      this.showWhatsAppTemplatesModal = true;
    },
    onExpiredSwitchToNote() {
      this.setReplyMode(REPLY_EDITOR_MODES.NOTE);
    },
    openContentTemplateModal() {
      this.showContentTemplatesModal = true;
    },
    hideContentTemplatesModal() {
      this.showContentTemplatesModal = false;
    },
    openCannedResponseModal() {
      this.showCannedResponseModal = true;
    },
    hideCannedResponseModal() {
      this.showCannedResponseModal = false;
    },
    onCannedResponseSelect({ content, attachments }) {
      this.hideCannedResponseModal();
      if (typeof content === 'string') {
        this.replaceText(content);
      }
      this.attachCannedResponseFiles(attachments);
    },
    async attachCannedResponseFiles(attachments) {
      if (!Array.isArray(attachments) || !attachments.length) return;
      await Promise.all(
        attachments.map(async att => {
          try {
            const response = await fetch(att.file_url);
            const blob = await response.blob();
            const file = new File([blob], att.filename || 'anexo', {
              type: att.file_type || blob.type,
            });
            this.onFileUpload({
              name: file.name,
              type: file.type,
              size: file.size,
              file,
            });
          } catch (error) {
            // best-effort: anexo da resposta rapida nao bloqueia o envio do texto
          }
        })
      );
    },
    openLocationPicker() {
      if (!this.currentChat?.id) return;
      this.showLocationPickerModal = true;
    },
    hideLocationPicker() {
      this.showLocationPickerModal = false;
    },
    async onLocationSelect({ latitude, longitude, address }) {
      this.hideLocationPicker();
      try {
        await MessageApi.shareLocation(this.currentChat.id, {
          latitude,
          longitude,
          address,
        });
        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
        emitter.emit(BUS_EVENTS.MESSAGE_SENT);
      } catch (error) {
        const errorMessage =
          error?.response?.data?.error || this.$t('CONVERSATION.MESSAGE_ERROR');
        useAlert(errorMessage);
      }
    },
    openShareContactModal() {
      if (!this.currentChat?.id) return;
      this.showShareContactModal = true;
    },
    hideShareContactModal() {
      this.showShareContactModal = false;
    },
    async onShareContactSelect(payload) {
      this.hideShareContactModal();
      try {
        await MessageApi.shareContact(this.currentChat.id, {
          source: payload.source,
          name: payload.name,
          phone: payload.phone,
          contact_id: payload.contactId,
          agent_id: payload.agentId,
        });
        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
        emitter.emit(BUS_EVENTS.MESSAGE_SENT);
      } catch (error) {
        const errorMessage =
          error?.response?.data?.error || this.$t('CONVERSATION.MESSAGE_ERROR');
        useAlert(errorMessage);
      }
    },
    confirmOnSendReply() {
      if (this.isReplyButtonDisabled) {
        return;
      }
      if (this.showMentions) return;

      this.pendingAudioAutoSend = false;

      // (1) PRIMEIRO envio com anexo(s) ainda subindo: a mídia entra JÁ na
      // conversa como uma bolha "carregando" (preview local + progresso) e o
      // composer é liberado. O POST real dispara sozinho quando o blob conclui,
      // reusando o MESMO echo_id da bolha (sem duplicar). A legenda, se houver,
      // sai como mensagem de texto própria na hora.
      if (
        this.globalConfig.directUploadsEnabled &&
        this.hasUncommittedPendingUpload
      ) {
        const caption = this.message;
        if (caption && caption.trim()) {
          this.sendStandaloneText(caption, this.getCopilotAcceptedMessage());
        }
        this.attachedFiles
          .filter(
            a =>
              (a.uploadStatus === 'uploading' ||
                a.uploadStatus === 'uploaded') &&
              !a.committed
          )
          .forEach(a => this.createUploadingBubble(a));
        this.clearComposerTextOnly();
        this.resetReplyToMessage();
        if (!this.isPrivate) this.clearEmailField();
        this.hideEmojiPicker();
        this.$emit('update:popOutReplyBox', false);
        this.$nextTick(() => {
          this.messageEditor?.focusEditorInputField?.('end');
          this.isFocused = true;
        });
        return;
      }

      // (2) Já existe anexo pendente em 2º plano (committed, subindo ou falho):
      // o texto digitado agora vai como mensagem INDEPENDENTE na hora (texto
      // puro, sem o anexo), preservando o anexo, para a atendente seguir a
      // conversa enquanto o arquivo carrega. Anexos pendentes não-committed já
      // foram tratados acima (path 1) ou bloqueiam o envio (falha no modal).
      if (this.hasPendingAttachmentUpload) {
        const message = this.message;
        if (message && message.trim()) {
          this.sendStandaloneText(message, this.getCopilotAcceptedMessage());
          this.clearComposerTextOnly();
          // Consome o reply-to (senão a barra fica e as próximas mensagens
          // re-encadeiam) e limpa os campos de e-mail, como no envio normal.
          this.resetReplyToMessage();
          if (!this.isPrivate) this.clearEmailField();
          this.hideEmojiPicker();
          this.$emit('update:popOutReplyBox', false);
          // Mantém o foco no editor para a próxima mensagem sair direto.
          this.$nextTick(() => {
            this.messageEditor?.focusEditorInputField?.('end');
            this.isFocused = true;
          });
        }
        return;
      }

      this.performConfirmedSend(this.message, this.getCopilotAcceptedMessage());
    },
    // Envia SÓ texto agora, ignorando anexos em 2º plano (committed). Usado
    // enquanto um arquivo ainda sobe, para não bloquear a conversa. Texto puro
    // é uma única mensagem em qualquer canal (sem split de mídia).
    sendStandaloneText(message, copilotAcceptedMessage = '') {
      const payload = this.getMessagePayload(message, this.currentChat.id, {
        excludeAttachments: true,
      });
      this.sendMessage(payload, message, copilotAcceptedMessage);
    },
    // file_type otimista a partir do mime — casa com ATTACHMENT_TYPES usados em
    // componentToRender (image/video/audio/file).
    optimisticFileType(resource) {
      const type = (
        resource?.content_type ||
        resource?.type ||
        ''
      ).toLowerCase();
      if (type.startsWith('image/')) return 'image';
      if (type.startsWith('video/')) return 'video';
      if (type.startsWith('audio/')) return 'audio';
      return 'file';
    },
    // Injeta a bolha "carregando" na conversa para um anexo em upload e guarda o
    // mapeamento uploadId → echo_id, para finalizar o POST quando o blob chegar.
    createUploadingBubble(attachment) {
      const conversationId = attachment.currentChatId || this.currentChat.id;
      const rawName =
        attachment.resource?.name ||
        attachment.rawFile?.name ||
        attachment.resource?.filename ||
        '';
      const data = {
        conversationId,
        message: '',
        private: this.isPrivate,
        sender: this.sender,
        pendingAttachments: [
          {
            fileType: this.optimisticFileType(attachment.resource),
            dataUrl: attachment.thumb || undefined,
            thumbUrl: attachment.thumb || undefined,
            fileName: rawName,
            fileSize: attachment.resource?.size,
            uploadId: attachment.uploadId,
            uploadProgress: attachment.uploadProgress,
          },
        ],
      };
      // Esconde do composer já (committed); o blob ainda sobe em 2º plano.
      this.patchAttachmentByUploadId(attachment.uploadId, { committed: true });
      this.$store
        .dispatch('addPendingAttachmentMessage', data)
        .then(pendingMessage => {
          if (!pendingMessage) return;
          this.patchAttachmentByUploadId(attachment.uploadId, {
            echoId: pendingMessage.echo_id,
          });
          this.uploadBubbles[attachment.uploadId] = {
            echoId: pendingMessage.echo_id,
            pendingMessage,
            conversationId,
          };
          // Anexo que já tinha concluído o upload antes de virar bolha (ex.:
          // irmão de outro ainda subindo): finaliza o POST agora.
          if (attachment.blobSignedId) {
            this.finalizeUploadBubble(
              attachment.uploadId,
              attachment.blobSignedId
            );
          }
        });
    },
    // Executa o envio de fato (texto + anexos já prontos). Extraído para ser
    // reutilizado tanto no envio imediato quanto no envio armado (pós-upload).
    performConfirmedSend(message, copilotAcceptedMessage = '') {
      const isOnWhatsApp =
        this.isATwilioWhatsAppChannel ||
        this.isAWhatsAppCloudChannel ||
        this.is360DialogWhatsAppChannel;
      // Instagram and TikTok do not support sending text and attachments in the same message.
      // For Instagram, combining them causes duplicate messages due to separate echo events per component.
      // For TikTok, the API rejects messages that mix text and media.
      // To handle both cases, text and attachments are always sent as separate messages.
      const isOnInstagram = this.isAnInstagramChannel;
      const isOnTiktok = this.isATiktokChannel;
      // Captura antes do clearMessage: WhatsApp/Instagram/TikTok quebram em
      // vários payloads (um por anexo), então o aviso precisa sair UMA vez aqui,
      // no nível da ação de envio, e não dentro de sendMessage (por payload).
      const hadAttachments = this.hasAttachments;
      if ((isOnWhatsApp || isOnInstagram || isOnTiktok) && !this.isPrivate) {
        this.sendMessageAsMultipleMessages(message, copilotAcceptedMessage);
      } else {
        const messagePayload = this.getMessagePayload(message);
        this.sendMessage(messagePayload, message, copilotAcceptedMessage);
      }

      if (!this.isPrivate) {
        this.clearEmailField();
      }

      // Confirmação clara de que a mensagem COM ANEXO entrou na conversa.
      // Limitada ao envio com anexo (ação deliberada, menos frequente) para não
      // virar ruído em cada mensagem de texto; dispara 1x por envio, em qualquer
      // canal (a mensagem otimista já aparece na conversa neste instante).
      if (hadAttachments) {
        useAlert(this.$t('CONVERSATION.MESSAGE_SENT_TO_CONVERSATION'));
      }

      this.clearMessage();
      this.hideEmojiPicker();
      this.$emit('update:popOutReplyBox', false);
      // Manter foco no editor depois de enviar (igual WhatsApp Web) — agente
      // consegue digitar a próxima mensagem direto sem novo clique.
      this.$nextTick(() => {
        this.messageEditor?.focusEditorInputField?.('end');
        this.isFocused = true;
      });
    },
    // Dispara o envio armado quando todos os anexos terminaram de subir.
    maybeFireArmedSend() {
      if (!this.armedSend || this.hasPendingAttachmentUpload) return;
      // Nada para enviar (anexos removidos e sem texto): apenas desarma.
      if (!this.attachedFiles.length && !this.message) {
        this.armedSend = null;
        return;
      }
      const fire = this.armedSend;
      this.armedSend = null;
      fire();
    },
    focusReplyEditor() {
      // Foca o editor ao abrir/trocar de conversa. Nos inboxes Channel::Api/WhatsApp
      // da Tozi o foco-na-troca dependia so do timing interno do Editor e falhava em
      // navegacao SPA -> a atendente precisava clicar manualmente na caixa pra digitar.
      if (this.isEditorDisabled) return;
      this.$nextTick(() => {
        this.messageEditor?.focusEditorInputField?.('end');
      });
    },
    sendToConversation(conversationId) {
      if (this.isReplyButtonDisabled && !this.attachedFiles.length) return;
      const isOnWhatsApp =
        this.isATwilioWhatsAppChannel ||
        this.isAWhatsAppCloudChannel ||
        this.is360DialogWhatsAppChannel;
      const isOnInstagram = this.isAnInstagramChannel;
      if ((isOnWhatsApp || isOnInstagram) && !this.isPrivate) {
        const messages = this.getMultipleMessagesPayload(
          this.message,
          conversationId
        );
        messages.forEach(mp => this.sendMessage(mp));
      } else {
        const messagePayload = this.getMessagePayload(
          this.message,
          conversationId
        );
        this.sendMessage(messagePayload);
      }
      this.clearMessage();
      this.hideEmojiPicker();
    },
    sendMessageAsMultipleMessages(message, copilotAcceptedMessage = '') {
      const messages = this.getMultipleMessagesPayload(message);
      messages.forEach(messagePayload => {
        this.sendMessage(
          messagePayload,
          messagePayload.message || '',
          copilotAcceptedMessage
        );
      });
    },
    sendMessageAnalyticsData(
      isPrivate,
      { editorMessage = '', copilotAcceptedMessage = '' } = {}
    ) {
      const normalizeForComparison = message => {
        let normalizedMessage = message || '';

        if (this.sendWithSignature && this.messageSignature && !isPrivate) {
          const effectiveChannelType = getEffectiveChannelType(
            this.channelType,
            this.inbox?.medium || ''
          );
          normalizedMessage = removeSignature(
            normalizedMessage,
            this.messageSignature,
            effectiveChannelType
          );
        }

        return trimContent(normalizedMessage);
      };

      const normalizedAcceptedMessage = normalizeForComparison(
        copilotAcceptedMessage
      );
      const normalizedEditorMessage = normalizeForComparison(editorMessage);

      if (normalizedAcceptedMessage && normalizedEditorMessage) {
        useTrack(CAPTAIN_EVENTS.AI_ASSISTED_MESSAGE_SENT, {
          conversationId: this.conversationIdByRoute,
          channelType: this.channelType,
          editedBeforeSend:
            normalizedAcceptedMessage !== normalizedEditorMessage,
          isPrivate,
        });
      }

      // Analytics data for message signature is enabled or not in channels
      return isPrivate
        ? useTrack(CONVERSATION_EVENTS.SENT_PRIVATE_NOTE)
        : useTrack(CONVERSATION_EVENTS.SENT_MESSAGE, {
            channelType: this.channelType,
            signatureEnabled: this.sendWithSignature,
            hasReplyTo: !!this.inReplyTo?.id,
          });
    },
    async onSendReply() {
      if (this.stopRecordingForSend()) {
        this.pendingAudioAutoSend = true;
        this.pendingAudioConversationId = this.currentChat.id;
        return;
      }
      if (this.isUploadingAudio) {
        this.pendingAudioAutoSend = true;
        this.pendingAudioConversationId = this.currentChat.id;
        return;
      }

      // D2: gate de assunção ANTES de confirmar o envio. O draft permanece
      // intacto (clearMessage só roda dentro de confirmOnSendReply) — após
      // confirmar, o dialog emite `confirm` e re-invoca onSendReply com o
      // one-shot `gateConfirmedOnce` (o assignee já sou eu → gate passa).
      if (this.shouldShowAssignmentGate && !this.gateConfirmedOnce) {
        this.$refs.assignToReplyDialog.show();
        return;
      }
      this.gateConfirmedOnce = false;

      const undefinedVariables = getUndefinedVariablesInMessage({
        message: this.message,
        variables: this.messageVariables,
      });
      if (undefinedVariables.length > 0) {
        const undefinedVariablesCount =
          undefinedVariables.length > 1 ? undefinedVariables.length : 1;
        this.undefinedVariableMessage = this.$t(
          'CONVERSATION.REPLYBOX.UNDEFINED_VARIABLES.MESSAGE',
          {
            undefinedVariablesCount,
            undefinedVariables: undefinedVariables.join(', '),
          }
        );

        const ok = await this.$refs.confirmDialog.showConfirmation();
        if (ok) {
          this.confirmOnSendReply();
        }
      } else {
        this.confirmOnSendReply();
      }
    },
    async onAssignmentGateConfirmed() {
      // Caminho REATIVO (D6): a mensagem já saiu do draft e tomou 422 —
      // reenvia os payloads enfileirados na ORDEM (multi-part WA/IG/TikTok).
      if (this.pendingGatePayloads.length) {
        const payloads = [...this.pendingGatePayloads];
        this.pendingGatePayloads = [];
        // sequencial de propósito: preserva a ordem das partes.
        // eslint-disable-next-line no-restricted-syntax
        for (const payload of payloads) {
          // eslint-disable-next-line no-await-in-loop
          await this.sendMessage(payload);
        }
        return;
      }
      // Caminho PROATIVO: o draft ainda está intacto — o assignee agora sou eu,
      // então o gate passa e o envio segue automático (one-shot anti-loop pra
      // cobrir o atraso de 1 tick do store).
      this.gateConfirmedOnce = true;
      this.onSendReply();
    },
    async sendMessage(
      messagePayload,
      editorMessage = '',
      copilotAcceptedMessage = ''
    ) {
      try {
        if (this.shouldBlockWhatsappSend) {
          this.showWhatsappInvalidNotice(this.whatsappInvalidMessage);
          useAlert(
            this.whatsappInvalidMessage,
            whatsappAlertAction(this.whatsappInvalidMessage)
          );
          return;
        }
        await this.$store.dispatch(
          'createPendingMessageAndSend',
          messagePayload
        );
        emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE);
        emitter.emit(BUS_EVENTS.MESSAGE_SENT);
        this.removeFromDraft();
        this.sendMessageAnalyticsData(messagePayload.private, {
          editorMessage,
          copilotAcceptedMessage,
        });
      } catch (error) {
        // D6: 422 `assignment_required` (gate) NÃO é erro de envio — empilha o
        // payload e reabre o dialog com o dono ATUALIZADO do meta (corrida P16).
        // Multi-part: N catches empilham na ordem; o dialog é idempotente.
        if (
          error?.response?.status === 422 &&
          error.response.data?.error_code === 'assignment_required'
        ) {
          this.pendingGatePayloads.push(messagePayload);
          this.$refs.assignToReplyDialog.show(error.response.data.meta);
          return;
        }
        const errorMessage =
          error?.response?.data?.error || this.$t('CONVERSATION.MESSAGE_ERROR');
        if (isWhatsAppValidationMessage(errorMessage)) {
          this.showWhatsappInvalidNotice(errorMessage);
        }
        useAlert(errorMessage, whatsappAlertAction(errorMessage));
      }
    },
    async onSendWhatsAppReply(messagePayload) {
      this.sendMessage({
        conversationId: this.currentChat.id,
        ...messagePayload,
      });
      this.hideWhatsappTemplatesModal();
    },
    async onSendContentTemplateReply(messagePayload) {
      this.sendMessage({
        conversationId: this.currentChat.id,
        ...messagePayload,
      });
      this.hideContentTemplatesModal();
    },
    replaceText(message) {
      if (this.sendWithSignature && !this.private) {
        // if signature is enabled, append it to the message
        // appendSignature ensures that the signature is not duplicated
        // so we don't need to check if the signature is already present
        const effectiveChannelType = getEffectiveChannelType(
          this.channelType,
          this.inbox?.medium || ''
        );
        message = appendSignature(
          message,
          this.messageSignature,
          effectiveChannelType
        );
      }

      const updatedMessage = replaceVariablesInMessage({
        message,
        variables: this.messageVariables,
      });

      setTimeout(() => {
        useTrack(CONVERSATION_EVENTS.INSERTED_A_CANNED_RESPONSE);
        this.message = updatedMessage;
      }, 100);
    },
    setReplyMode(mode = REPLY_EDITOR_MODES.REPLY) {
      // Clear attachments when switching between private note and reply modes
      // This is to prevent from breaking the upload rules
      if (this.attachedFiles.length > 0) this.clearAttachedFiles();

      const { can_reply: canReply } = this.currentChat;
      this.$store.dispatch('draftMessages/setReplyEditorMode', {
        mode,
      });
      if (canReply || this.isAWhatsAppChannel || this.isAPIInbox)
        this.replyType = mode;
      if (this.isRecordingAudio) {
        this.toggleAudioRecorder();
      }
    },
    clearEditorSelection() {
      this.updateEditorSelectionWith = '';
    },
    addIntoEditor(content) {
      this.updateEditorSelectionWith = content;
      this.onFocus();
    },
    executeCopilotAction(action, data) {
      // Phase 5 — when AI Assistant V2 is on, route inline rewrite/reply
      // actions through the suggestion chip preview instead of swapping the
      // composer in place. `ask_copilot` and `summarize` keep the legacy
      // behaviour (delegate to useCopilotReply, which opens the panel).
      const PANEL_BYPASS = ['ask_copilot', 'summarize'];
      if (this.aiAssistantFlag?.value && !PANEL_BYPASS.includes(action)) {
        this.startAiSuggestionChip(action, data || this.message || '');
        return;
      }
      this.copilot.execute(action, data);
    },

    // === Phase 5 — Suggestion chip lifecycle ===
    async startAiSuggestionChip(action, data) {
      // Cancel any in-flight chip generation before starting a new one.
      this.discardAiSuggestionChip({ trackReason: 'replaced' });
      const controller = new AbortController();
      this.aiSuggestionChipAbortController = controller;
      this.aiSuggestionChip = {
        text: '',
        isStreaming: true,
        errorType: null,
        action,
      };
      this.aiSuggestionChipStartedAt = Date.now();

      useTrack('ai.action.triggered', {
        action,
        surface: 'chip',
        conversation_id: this.currentChat?.id,
      });

      try {
        const { message, errorType } = await this.captainProcessEvent(
          action,
          data,
          { signal: controller.signal }
        );

        // Conversation switch / replaced: chip already cleared by watcher.
        if (this.aiSuggestionChipAbortController !== controller) return;

        if (errorType === CAPTAIN_ERROR_TYPES.ABORTED) return;
        if (errorType === CAPTAIN_ERROR_TYPES.PRIVATE_MODE_BLOCKED) {
          this.aiSuggestionChip = null;
          return;
        }
        if (errorType === CAPTAIN_ERROR_TYPES.RATE_LIMIT) {
          this.aiSuggestionChip = {
            ...this.aiSuggestionChip,
            isStreaming: false,
            errorType: 'rate_limit',
          };
          return;
        }
        if (errorType === CAPTAIN_ERROR_TYPES.TIMEOUT) {
          this.aiSuggestionChip = {
            ...this.aiSuggestionChip,
            isStreaming: false,
            errorType: 'timeout',
          };
          return;
        }
        if (errorType === CAPTAIN_ERROR_TYPES.NETWORK) {
          this.aiSuggestionChip = {
            ...this.aiSuggestionChip,
            isStreaming: false,
            errorType: 'network',
          };
          return;
        }
        if (errorType === CAPTAIN_ERROR_TYPES.EMPTY_RESPONSE || !message) {
          this.aiSuggestionChip = {
            ...this.aiSuggestionChip,
            isStreaming: false,
            errorType: 'empty_response',
          };
          return;
        }
        if (errorType) {
          this.aiSuggestionChip = {
            ...this.aiSuggestionChip,
            isStreaming: false,
            errorType: 'captain_unstable',
          };
          return;
        }

        this.aiSuggestionChip = {
          ...this.aiSuggestionChip,
          text: message,
          isStreaming: false,
          errorType: null,
        };
      } catch (error) {
        if (this.aiSuggestionChipAbortController !== controller) return;
        if (controller.signal.aborted) return;
        this.aiSuggestionChip = {
          ...this.aiSuggestionChip,
          isStreaming: false,
          errorType: 'captain_unstable',
        };
      } finally {
        if (this.aiSuggestionChipAbortController === controller) {
          this.aiSuggestionChipAbortController = null;
        }
      }
    },

    handleAiSuggestionAccept(text) {
      const elapsed = this.aiSuggestionChipStartedAt
        ? Date.now() - this.aiSuggestionChipStartedAt
        : 0;
      const action = this.aiSuggestionChip?.action;
      this.message = text || '';
      this.setCopilotAcceptedMessage(this.message);
      sonnerToast.success(
        this.$t('CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.USED_TOAST')
      );
      useTrack('ai.suggestion.applied', {
        action_id: action,
        time_to_apply_ms: elapsed,
        was_edited: false,
        conversation_id: this.currentChat?.id,
      });
      this.aiSuggestionChip = null;
      this.aiSuggestionChipStartedAt = null;
      this.$nextTick(() => {
        this.messageEditor?.focusEditorInputField?.('end');
        // Trigger first-time tour after agent accepts a suggestion.
        if (this.aiTour && !this.aiTour.isCompleted()) {
          this.aiTour.startTour({ resume: false });
        }
      });
    },

    handleAiSuggestionEdit(text) {
      const elapsed = this.aiSuggestionChipStartedAt
        ? Date.now() - this.aiSuggestionChipStartedAt
        : 0;
      const action = this.aiSuggestionChip?.action;
      this.message = text || '';
      this.setCopilotAcceptedMessage(this.message);
      sonnerToast(
        this.$t('CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.EDIT_TOAST')
      );
      useTrack('ai.suggestion.edited', {
        action_id: action,
        time_to_edit_ms: elapsed,
        conversation_id: this.currentChat?.id,
      });
      this.aiSuggestionChip = null;
      this.aiSuggestionChipStartedAt = null;
      this.$nextTick(() => {
        this.messageEditor?.focusEditorInputField?.('end');
        // Best-effort select-all so the agent can immediately overwrite.
        if (typeof this.messageEditor?.selectAll === 'function') {
          try {
            this.messageEditor.selectAll();
          } catch {
            /* editor may not expose selectAll — focus is enough */
          }
        }
      });
    },

    discardAiSuggestionChip({ trackReason = 'manual' } = {}) {
      const action = this.aiSuggestionChip?.action;
      const wasOpen = !!this.aiSuggestionChip;
      if (this.aiSuggestionChipAbortController) {
        try {
          this.aiSuggestionChipAbortController.abort();
        } catch {
          /* ignore */
        }
        this.aiSuggestionChipAbortController = null;
      }
      this.aiSuggestionChip = null;
      this.aiSuggestionChipStartedAt = null;
      if (wasOpen && trackReason === 'manual') {
        sonnerToast(
          this.$t(
            'CONVERSATION.AI_ASSISTANT_PANEL.SUGGESTION_CHIP.DISCARDED_TOAST'
          )
        );
      }
      if (wasOpen) {
        useTrack('ai.suggestion.dismissed', {
          action_id: action,
          reason: trackReason,
          conversation_id: this.currentChat?.id,
        });
      }
    },

    handleAiSuggestionDiscard() {
      this.discardAiSuggestionChip({ trackReason: 'manual' });
    },

    handleAiSuggestionRetry() {
      const action = this.aiSuggestionChip?.action;
      if (!action) return;
      this.startAiSuggestionChip(action, this.message || '');
    },

    handleAiSuggestionCancelStreaming() {
      if (this.aiSuggestionChipAbortController) {
        try {
          this.aiSuggestionChipAbortController.abort();
        } catch {
          /* ignore */
        }
        this.aiSuggestionChipAbortController = null;
      }
      // Keep the chip visible but in a non-streaming, no-content state so the
      // agent can retry or discard explicitly.
      if (this.aiSuggestionChip) {
        this.aiSuggestionChip = {
          ...this.aiSuggestionChip,
          isStreaming: false,
        };
      }
    },
    // Limpa apenas o texto do composer (e re-aplica assinatura), preservando os
    // anexos. Usado no envio "armado", onde os anexos ainda estão subindo.
    clearComposerTextOnly() {
      this.message = '';
      this.clearCopilotAcceptedMessage();
      if (this.sendWithSignature && !this.isPrivate) {
        const effectiveChannelType = getEffectiveChannelType(
          this.channelType,
          this.inbox?.medium || ''
        );
        this.message = appendSignature(
          this.message,
          this.messageSignature,
          effectiveChannelType
        );
      }
    },
    clearMessage() {
      this.message = '';
      this.pendingAudioAutoSend = false;
      this.pendingAudioConversationId = null;
      this.isUploadingAudio = false;
      this.clearCopilotAcceptedMessage();
      if (this.sendWithSignature && !this.isPrivate) {
        // if signature is enabled, append it to the message
        const effectiveChannelType = getEffectiveChannelType(
          this.channelType,
          this.inbox?.medium || ''
        );
        this.message = appendSignature(
          this.message,
          this.messageSignature,
          effectiveChannelType
        );
      }
      this.clearAttachedFiles();
      this.isRecordingAudio = false;
      this.resetReplyToMessage();
      this.resetAudioRecorderInput();
    },
    clearEmailField() {
      this.ccEmails = '';
      this.bccEmails = '';
      this.toEmails = '';
    },

    toggleEmojiPicker() {
      this.showEmojiPicker = !this.showEmojiPicker;
    },
    togglePrivateNote() {
      if (this.isReplyRestricted) return;
      const next =
        this.replyType === REPLY_EDITOR_MODES.NOTE
          ? REPLY_EDITOR_MODES.REPLY
          : REPLY_EDITOR_MODES.NOTE;
      this.setReplyMode(next);
    },
    closeCopilot() {
      // copilot.isActive é COMPUTED (showEditor || isGenerating), não pode
      // ser setado direto. reset() já zera showEditor + isGenerating + content.
      this.copilot.reset();
    },
    toggleInlineCopilotMenu() {
      this.showInlineCopilotMenu = !this.showInlineCopilotMenu;
      // Abrir o menu manualmente conta como onboarded (usuário já achou
      // o botão), evita que o coachmark continue piscando depois.
      if (
        this.showInlineCopilotMenu &&
        this.aiOnboarding?.shouldShowOnboarding?.value
      ) {
        this.aiOnboarding.markOnboarded('confirm');
      }
    },
    closeInlineCopilotMenu() {
      this.showInlineCopilotMenu = false;
    },
    handleAIOnboardingConfirm() {
      this.aiOnboarding.markOnboarded('confirm');
      sonnerToast.success(this.$t('COPILOT_ONBOARDING.TOAST_CONFIRMED'));
    },
    handleAIOnboardingDismiss(reason) {
      // 'auto' marca como onboarded silenciosamente (sem toast).
      // 'escape' / 'outside' / 'later' também marcam para não ficar piscando
      // sempre — mas só 'confirm' dispara toast.
      const method = reason === 'auto' ? 'auto' : 'true';
      this.aiOnboarding.markOnboarded(method);
    },
    handleInlineCopilotAction(actionKey, content) {
      this.showInlineCopilotMenu = false;
      const data = content || this.message || '';

      // Ações exploratórias (resposta longa) abrem o painel lateral do
      // Chatwoot — não ativam o pill copilot inline, evitando dois UIs.
      // Ações de rewrite/tone/grammar continuam inline porque substituem
      // o texto do input.
      const PANEL_ACTIONS = ['ask_copilot', 'summarize'];
      if (PANEL_ACTIONS.includes(actionKey)) {
        // Garante que qualquer copilot inline pendente seja resetado
        this.copilot.reset();
        // Abre o painel lateral existente
        this.$store.dispatch('updateUISettings', {
          uiSettings: {
            is_contact_sidebar_open: false,
            is_copilot_panel_open: true,
          },
        });
        return;
      }

      this.executeCopilotAction(actionKey, data);
    },
    triggerWaFileUpload() {
      const el = document.getElementById('conversationAttachment');
      if (el) el.click();
    },
    toggleAudioRecorder() {
      this.isRecordingAudio = !this.isRecordingAudio;
      this.recordingAudioState = this.isRecordingAudio ? 'recording' : '';
      if (!this.isRecordingAudio) {
        this.pendingAudioAutoSend = false;
        this.pendingAudioConversationId = null;
        this.isUploadingAudio = false;
        this.resetAudioRecorderInput();
      }
    },
    toggleAudioRecorderPlayPause() {
      if (!this.$refs.audioRecorderInput) return;
      if (this.recordingAudioState === 'processing') return;

      if (
        ['recording', 'recording_paused'].includes(this.recordingAudioState)
      ) {
        this.$refs.audioRecorderInput.toggleRecordingPauseResume();
        return;
      }

      if (['stopped', 'playing', 'paused'].includes(this.recordingAudioState)) {
        this.$refs.audioRecorderInput.playPause();
      }
    },
    stopRecordingForSend() {
      if (!this.$refs.audioRecorderInput || this.hasRecordedAudio) return false;
      if (this.recordingAudioState === 'processing') return true;

      if (
        ['recording', 'recording_paused'].includes(this.recordingAudioState)
      ) {
        this.$refs.audioRecorderInput.stopRecording();
        this.recordingAudioState = 'processing';
        return true;
      }

      return false;
    },
    hideEmojiPicker() {
      if (this.showEmojiPicker) {
        this.toggleEmojiPicker();
      }
    },
    onTypingOn() {
      this.toggleTyping('on');
    },
    onTypingOff() {
      this.toggleTyping('off');
    },
    onBlur() {
      this.isFocused = false;
      this.saveDraft(this.conversationIdByRoute, this.replyType);
    },
    onFocus() {
      this.isFocused = true;
      this.isGhostSuggestionDismissed = false;
    },
    acceptGhostSuggestion() {
      if (!this.shouldShowGhostSuggestion) return;
      this.message = this.ghostSuggestionText;
      this.isGhostSuggestionDismissed = true;
      this.$nextTick(() => {
        this.messageEditor?.focusEditorInputField?.('end');
      });
    },
    async fetchRemoteGhostSuggestion(messageId) {
      try {
        this.ghostSuggestionFetchedFor = messageId;
        const conversationId = this.currentChat?.id;
        if (!conversationId) return;
        const { data } =
          await ConversationAPI.getGhostSuggestion(conversationId);
        if (this.ghostSuggestionFetchedFor !== messageId) return;
        if (data?.suggestion) {
          this.remoteGhostSuggestion = data.suggestion;
        }
      } catch (error) {
        // silent — fallback hardcoded keeps working
      }
    },
    dismissGhostSuggestion() {
      this.isGhostSuggestionDismissed = true;
    },
    onRecordProgressChanged(duration) {
      this.recordingAudioDurationText = duration;
    },
    onFinishRecorder(file) {
      this.recordingAudioState = 'stopped';
      this.hasRecordedAudio = true;
      this.isUploadingAudio = true;
      const autoRecordedFile = {
        ...file,
        isRecordedAudio: true,
      };
      return file && this.onFileUpload(autoRecordedFile);
    },
    toggleTyping(status) {
      const conversationId = this.currentChat.id;
      const isPrivate = this.isPrivate;

      if (!conversationId) {
        return;
      }

      this.$store.dispatch('conversationTypingStatus/toggleTyping', {
        status,
        conversationId,
        isPrivate,
      });
    },
    attachFile({ blob, file, uploadId, uploadStatus, uploadProgress = null }) {
      // Build the preview synchronously via createObjectURL instead of reading
      // the whole file into a base64 string with FileReader: no main-thread
      // block and no memory spike when attaching large files (only image/video
      // get a thumb; everything else renders a static icon).
      const capturedChatId = file?.isRecordedAudio
        ? this.pendingAudioConversationId || this.currentChat.id
        : this.currentChat.id;

      this.attachedFiles.push({
        // Stable id used both as the v-for key and to match async DirectUpload
        // lifecycle callbacks (progress/complete/fail) back to this entry.
        id: uploadId || file?.id || `att-${Date.now()}`,
        uploadId,
        currentChatId: capturedChatId,
        resource: blob || file,
        // Keep the original upload wrapper so a failed upload can be retried.
        rawFile: file,
        isPrivate: this.isPrivate,
        thumb: buildAttachmentThumbUrl(file),
        blobSignedId: blob ? blob.signed_id : undefined,
        // 'uploading' → DirectUpload in flight (Send is gated); 'uploaded'/
        // undefined → ready to send; 'failed' → offer retry.
        uploadStatus: uploadStatus || (blob ? 'uploaded' : undefined),
        uploadProgress,
        isRecordedAudio: file?.isRecordedAudio || false,
      });

      if (file?.isRecordedAudio) {
        this.isUploadingAudio = false;
        if (this.pendingAudioAutoSend) {
          this.pendingAudioAutoSend = false;
          const savedConversationId = capturedChatId;
          this.$nextTick(() => {
            this.sendToConversation(savedConversationId);
          });
        }
      }
    },
    // Finds a pending attachment by its DirectUpload id and applies a patch.
    patchAttachmentByUploadId(uploadId, patch) {
      const idx = this.attachedFiles.findIndex(a => a.uploadId === uploadId);
      if (idx < 0) return;
      this.attachedFiles.splice(idx, 1, {
        ...this.attachedFiles[idx],
        ...patch,
      });
    },
    onAttachmentUploadProgress(uploadId, percent) {
      this.patchAttachmentByUploadId(uploadId, { uploadProgress: percent });
      // Reflete o progresso na bolha "carregando" da conversa (se já criada).
      // Throttle: cada update recommita a mensagem + re-cameliza tudo; só
      // despacha quando a % inteira de fato avança (evita trabalho redundante).
      const bubble = this.uploadBubbles[uploadId];
      if (!bubble) return;
      const rounded = typeof percent === 'number' ? Math.round(percent) : null;
      if (rounded !== null && bubble.lastPercent === rounded) return;
      bubble.lastPercent = rounded;
      this.$store.dispatch('updatePendingAttachmentProgress', {
        conversationId: bubble.conversationId,
        echoId: bubble.echoId,
        uploadId,
        percent,
      });
    },
    onAttachmentUploaded(uploadId, blob) {
      this.patchAttachmentByUploadId(uploadId, {
        blobSignedId: blob.signed_id,
        uploadStatus: 'uploaded',
        uploadProgress: 100,
      });
      // Se já existe bolha para este upload, finaliza o POST. Se a bolha ainda
      // está sendo criada (.then de createUploadingBubble), ela finaliza sozinha
      // ao detectar blobSignedId — então aqui só agimos quando a bolha existe.
      if (this.uploadBubbles[uploadId]) {
        this.finalizeUploadBubble(uploadId, blob.signed_id);
        return;
      }
      // Sem bolha (fluxo legado/armado): mantém compatibilidade.
      this.maybeFireArmedSend();
    },
    // POST real da bolha "carregando" (mesmo echo_id). No sucesso a cópia do
    // servidor substitui a bolha → pode revogar o preview local. Na falha a
    // bolha fica FAILED mostrando o preview LOCAL — NÃO revoga (senão quebra).
    finalizeUploadBubble(uploadId, blobSignedId) {
      const bubble = this.uploadBubbles[uploadId];
      if (!bubble) return;
      this.$store
        .dispatch('finalizePendingAttachmentMessage', {
          pendingMessage: bubble.pendingMessage,
          blobSignedId,
        })
        .then(() => {
          delete this.uploadBubbles[uploadId];
          this.discardCommittedAttachment(uploadId);
        })
        .catch(() => {
          delete this.uploadBubbles[uploadId];
          this.attachedFiles = this.attachedFiles.filter(
            a => a.uploadId !== uploadId
          );
        });
    },
    onAttachmentUploadFailed(uploadId) {
      this.patchAttachmentByUploadId(uploadId, { uploadStatus: 'failed' });
      const bubble = this.uploadBubbles[uploadId];
      if (bubble) {
        // Falha do upload: a própria bolha vira FAILED (com retry na bolha).
        this.$store.dispatch('markPendingAttachmentFailed', {
          conversationId: bubble.conversationId,
          echoId: bubble.echoId,
          error: this.$t('CONVERSATION.MESSAGE_ERROR'),
        });
        return;
      }
      if (this.armedSend) {
        this.armedSend = null;
        useAlert(this.$t('CONVERSATION.MESSAGE_ERROR'));
      }
    },
    // Remove um anexo já enviado (committed) de attachedFiles e revoga o preview
    // local — chamado após o POST concluir; a bolha já mostra o asset do servidor.
    discardCommittedAttachment(uploadId) {
      const entry = this.attachedFiles.find(a => a.uploadId === uploadId);
      if (!entry) return;
      revokeAttachmentThumbUrl(entry.thumb);
      this.attachedFiles = this.attachedFiles.filter(
        a => a.uploadId !== uploadId
      );
    },
    // Re-runs the DirectUpload for a previously-failed attachment using the
    // original file kept on the entry.
    retryAttachmentUpload(attachment) {
      const entry = this.attachedFiles.find(a => a === attachment);
      if (!entry?.rawFile || !entry.uploadId) return;
      this.patchAttachmentByUploadId(entry.uploadId, {
        uploadStatus: 'uploading',
        uploadProgress: null,
      });
      this.directUploadCreate(
        entry.rawFile,
        (error, blob) => {
          if (error) this.onAttachmentUploadFailed(entry.uploadId);
          else this.onAttachmentUploaded(entry.uploadId, blob);
        },
        percent => this.onAttachmentUploadProgress(entry.uploadId, percent)
      );
    },
    removeAttachment(attachments) {
      // `attachments` é o que sobrou no preview/modal (apenas anexos em
      // composição, não-committed). Preserva os committed (bolhas "carregando"
      // na conversa, que não aparecem ali) e revoga só o que saiu de verdade.
      const committed = this.attachedFiles.filter(a => a.committed);
      const next = [...attachments, ...committed];
      const remaining = new Set(next);
      this.attachedFiles.forEach(att => {
        if (!remaining.has(att)) revokeAttachmentThumbUrl(att.thumb);
      });
      this.attachedFiles = next;
      // Remover o anexo que faltava concluir pode destravar (ou esvaziar) um
      // envio armado — reavalia.
      this.maybeFireArmedSend();
    },
    // Limpa os anexos EM COMPOSIÇÃO (não-committed), revogando os previews. Os
    // committed (bolhas "carregando" subindo em 2º plano) são preservados —
    // seguem até o POST concluir (discardCommittedAttachment os remove depois).
    clearAttachedFiles() {
      this.attachedFiles
        .filter(a => !a.committed)
        .forEach(att => revokeAttachmentThumbUrl(att.thumb));
      this.attachedFiles = this.attachedFiles.filter(a => a.committed);
      // Limpeza de anexos (troca de conversa, reset, modo nota) cancela qualquer
      // envio armado para não disparar no contexto errado.
      this.armedSend = null;
    },
    setReplyToInPayload(payload) {
      if (this.inReplyTo?.id) {
        return {
          ...payload,
          contentAttributes: {
            ...payload.contentAttributes,
            in_reply_to: this.inReplyTo.id,
          },
        };
      }

      return payload;
    },
    getMultipleMessagesPayload(message, overrideConversationId) {
      const multipleMessagePayload = [];
      const conversationId = overrideConversationId || this.currentChat.id;

      if (this.composerAttachedFiles && this.composerAttachedFiles.length) {
        let caption =
          this.isAnInstagramChannel || this.isATiktokChannel ? '' : message;
        this.composerAttachedFiles.forEach(attachment => {
          const attachedFile = this.globalConfig.directUploadsEnabled
            ? attachment.blobSignedId
            : attachment.resource.file;
          // Pula anexos cujo upload não concluiu (sem signed id) — nunca manda
          // files:[undefined]. Anexos 'uploading'/'failed' ficam de fora.
          if (!attachedFile) return;
          let attachmentPayload = {
            conversationId: attachment.currentChatId || conversationId,
            files: [attachedFile],
            private: false,
            message: caption,
            sender: this.sender,
          };

          attachmentPayload = this.setReplyToInPayload(attachmentPayload);
          multipleMessagePayload.push(attachmentPayload);
          // For WhatsApp, only the first attachment gets a caption
          if (!this.isAnInstagramChannel) caption = '';
        });
      }

      const hasNoAttachments =
        !this.composerAttachedFiles || !this.composerAttachedFiles.length;
      // For Instagram and TikTok, text must always be sent as a separate message (no captions on attachments).
      // For WhatsApp, we only need a text message if there are no attachments.
      if (
        ((this.isAnInstagramChannel || this.isATiktokChannel) && message) ||
        (!(this.isAnInstagramChannel || this.isATiktokChannel) &&
          hasNoAttachments)
      ) {
        let messagePayload = {
          conversationId,
          message,
          private: false,
          sender: this.sender,
        };

        messagePayload = this.setReplyToInPayload(messagePayload);

        multipleMessagePayload.push(messagePayload);
      }

      return multipleMessagePayload;
    },
    getMessagePayload(message, overrideConversationId, opts = {}) {
      const messageWithQuote = this.getMessageWithQuotedEmailText(message);
      const conversationId =
        overrideConversationId ||
        this.attachedFiles?.[0]?.currentChatId ||
        this.currentChat.id;

      let messagePayload = {
        conversationId,
        message: messageWithQuote,
        private: this.isPrivate,
        sender: this.sender,
      };
      messagePayload = this.setReplyToInPayload(messagePayload);

      // excludeAttachments: usado no envio de texto independente enquanto um
      // arquivo sobe em 2º plano (o anexo committed não entra nessa mensagem).
      if (
        !opts.excludeAttachments &&
        this.composerAttachedFiles &&
        this.composerAttachedFiles.length
      ) {
        messagePayload.files = [];
        this.composerAttachedFiles.forEach(attachment => {
          if (this.globalConfig.directUploadsEnabled) {
            // Só anexos com upload concluído (signed id presente); evita
            // mandar files:[undefined] de um anexo ainda subindo/falho.
            if (attachment.blobSignedId) {
              messagePayload.files.push(attachment.blobSignedId);
            }
          } else {
            messagePayload.files.push(attachment.resource.file);
          }
        });
        if (!messagePayload.files.length) delete messagePayload.files;
      }

      if (this.ccEmails && !this.isOnPrivateNote) {
        messagePayload.ccEmails = this.ccEmails;
      }

      if (this.bccEmails && !this.isOnPrivateNote) {
        messagePayload.bccEmails = this.bccEmails;
      }

      if (this.toEmails && !this.isOnPrivateNote) {
        messagePayload.toEmails = this.toEmails;
      }
      return messagePayload;
    },
    setCcEmails(value) {
      this.bccEmails = value.bccEmails;
      this.ccEmails = value.ccEmails;
    },
    setCCAndToEmailsFromLastChat() {
      const conversationContact = this.currentChat?.meta?.sender?.email || '';
      const { email: inboxEmail, forward_to_email: forwardToEmail } =
        this.inbox;

      const { cc, bcc, to } = getRecipients(
        this.lastEmail,
        conversationContact,
        inboxEmail,
        forwardToEmail
      );

      this.toEmails = to.join(', ');
      this.ccEmails = cc.join(', ');
      this.bccEmails = bcc.join(', ');
    },
    fetchAndSetReplyTo() {
      const replyStorageKey = LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO;
      const replyToMessageId = LocalStorage.getFromJsonStore(
        replyStorageKey,
        this.conversationId
      );

      this.inReplyTo = this.currentChat?.messages?.find(message => {
        if (message.id === replyToMessageId) {
          return true;
        }
        return false;
      });
    },
    onReplyToMessage() {
      this.fetchAndSetReplyTo();
      if (this.inReplyTo) {
        this.$nextTick(() => {
          const pos = this.isSignatureEnabledForInbox ? 'start' : 'end';
          this.messageEditor?.focusEditorInputField(pos);
        });
      }
    },
    resetReplyToMessage() {
      const replyStorageKey = LOCAL_STORAGE_KEYS.MESSAGE_REPLY_TO;
      LocalStorage.deleteFromJsonStore(replyStorageKey, this.conversationId);
      emitter.emit(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE);
    },
    onNewConversationModalActive(isActive) {
      // Issue is if the new conversation modal is open and we drag and drop the file
      // then the file is not getting attached to the new conversation modal
      // and it is getting attached to the current conversation reply box
      // so to fix this we are removing the drag and drop event listener from the current conversation reply box
      // When new conversation modal is open
      this.newConversationModalActive = isActive;
    },
    onSearchPopoverClose() {
      this.showArticleSearchPopover = false;
    },
    toggleInsertArticle() {
      this.showArticleSearchPopover = !this.showArticleSearchPopover;
    },
    resetAudioRecorderInput() {
      this.recordingAudioDurationText = '00:00';
      this.isRecordingAudio = false;
      this.recordingAudioState = '';
      this.hasRecordedAudio = false;
      this.pendingAudioAutoSend = false;
      this.pendingAudioConversationId = null;
      this.isUploadingAudio = false;
      // Only clear the recorded audio when we click toggle button.
      this.attachedFiles = this.attachedFiles.filter(
        file => !file?.isRecordedAudio
      );
    },
    onRecordError() {
      // convertAudio failed inside the recorder (it already showed the toast +
      // logged to Sentry). Tear down the recording UI so we don't leave a stuck
      // "processing" state behind.
      this.resetAudioRecorderInput();
    },
    togglePopout() {
      this.$emit('update:popOutReplyBox', !this.popOutReplyBox);
    },
    onSubmitCopilotReply() {
      const acceptedMessage = this.copilot.accept();
      this.message = acceptedMessage;
      this.setCopilotAcceptedMessage(acceptedMessage);
    },
  },
};
</script>

<template>
  <ReplyBoxBanner
    :message="message"
    :is-on-private-note="isOnPrivateNote"
    @open-assign-dialog="$refs.assignToReplyDialog.show()"
  />
  <AssignToReplyDialog
    ref="assignToReplyDialog"
    @confirm="onAssignmentGateConfirmed"
  />
  <div
    ref="replyEditor"
    class="reply-box"
    :class="[replyBoxClass, { 'reply-box--popout': popOutReplyBox }]"
  >
    <ReplyTopPanel
      :mode="replyType"
      :conversation-id="conversationId"
      :is-reply-restricted="isReplyRestricted"
      :disabled="
        (copilot.isActive.value && copilot.isButtonDisabled.value) ||
        showAudioRecorderEditor
      "
      :is-editor-disabled="isEditorDisabled"
      :is-message-length-reaching-threshold="isMessageLengthReachingThreshold"
      :characters-remaining="charactersRemaining"
      :pop-out-reply-box="popOutReplyBox"
      :editor-content="message"
      :is-copilot-active="copilot.isActive.value"
      @set-reply-mode="setReplyMode"
      @close-popout="$emit('update:popOutReplyBox', false)"
      @toggle-popout="togglePopout"
      @toggle-copilot="copilot.toggleEditor"
      @execute-copilot-action="executeCopilotAction"
    />
    <transition name="whatsapp-invalid">
      <div
        v-if="whatsappBannerMessage"
        class="mx-3 mt-2 mb-1 flex items-center gap-2 rounded-lg border border-n-ruby-5/40 bg-n-ruby-3 px-3 py-2 text-sm font-medium text-n-ruby-12 shadow-sm"
      >
        <span
          class="i-lucide-message-circle-x size-4 text-n-ruby-9 animate-pulse"
        />
        <span class="flex-1">{{ whatsappBannerMessage }}</span>
        <button
          v-if="shouldBlockWhatsappSend"
          class="shrink-0 rounded-md bg-n-ruby-5/40 px-2.5 py-1 text-xs font-semibold text-n-ruby-12 transition-colors hover:bg-n-ruby-5/60 disabled:cursor-not-allowed disabled:opacity-50"
          :disabled="isRevalidatingWhatsapp"
          @click="revalidateWhatsappNumber"
        >
          {{
            isRevalidatingWhatsapp
              ? $t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATING')
              : $t('CONVERSATION.REPLYBOX.WHATSAPP_REVALIDATE')
          }}
        </button>
      </div>
    </transition>
    <ArticleSearchPopover
      v-if="showArticleSearchPopover && connectedPortalSlug"
      :selected-portal-slug="connectedPortalSlug"
      @insert="handleInsert"
      @close="onSearchPopoverClose"
    />
    <Transition
      mode="out-in"
      enter-active-class="transition-all duration-300 ease-out"
      enter-from-class="opacity-0 translate-y-2 scale-[0.98]"
      enter-to-class="opacity-100 translate-y-0 scale-100"
      leave-active-class="transition-all duration-200 ease-in"
      leave-from-class="opacity-100 translate-y-0 scale-100"
      leave-to-class="opacity-0 translate-y-2 scale-[0.98]"
    >
      <div :key="copilot.editorTransitionKey.value" class="reply-box__top">
        <WhatsappWindowExpired
          v-if="showWhatsappWindowExpired"
          :inbox-id="inboxId"
          @send-template="onExpiredSendTemplate"
          @switch-to-note="onExpiredSwitchToNote"
        />
        <template v-else>
          <!-- Phase 5 — Copilot suggestion chip preview (above composer) -->
          <div
            v-if="aiSuggestionChip"
            class="px-3 pt-2"
            data-testid="ai-suggestion-chip-wrap"
          >
            <AISuggestionChip
              :text="aiSuggestionChip.text"
              :is-streaming="aiSuggestionChip.isStreaming"
              :error-type="aiSuggestionChip.errorType"
              @accept="handleAiSuggestionAccept"
              @edit="handleAiSuggestionEdit"
              @discard="handleAiSuggestionDiscard"
              @cancel-streaming="handleAiSuggestionCancelStreaming"
              @retry="handleAiSuggestionRetry"
            />
          </div>
          <ReplyToMessage
            v-if="shouldShowReplyToMessage"
            :message="inReplyTo"
            @dismiss="resetReplyToMessage"
          />
          <EmojiInput
            v-if="showEmojiPicker"
            v-on-clickaway="hideEmojiPicker"
            :class="{
              'emoji-dialog--expanded': isOnExpandedLayout || popOutReplyBox,
            }"
            :on-click="addIntoEditor"
          />
          <ReplyEmailHead
            v-if="showReplyHead && isDefaultEditorMode"
            v-model:cc-emails="ccEmails"
            v-model:bcc-emails="bccEmails"
            v-model:to-emails="toEmails"
          />
          <!-- Audio e Copilot legacy só rendem quando NÃO estamos no pill
               (email ou WhatsApp expirado). No pill, ambos rendem inline. -->
          <AudioRecorder
            v-if="showAudioRecorderEditor && !useWaComposerBar"
            ref="audioRecorderInput"
            :audio-record-format="audioRecordFormat"
            @recorder-progress-changed="onRecordProgressChanged"
            @finish-record="onFinishRecorder"
            @record-error="onRecordError"
            @play="recordingAudioState = 'playing'"
            @pause="recordingAudioState = 'paused'"
          />
          <CopilotEditorSection
            v-if="
              copilot.isActive.value &&
              !showAudioRecorderEditor &&
              !useWaComposerBar
            "
            :show-copilot-editor="copilot.showEditor.value"
            :is-generating-content="copilot.isGenerating.value"
            :generated-content="copilot.generatedContent.value"
            :is-popout="popOutReplyBox"
            :placeholder="$t('CONVERSATION.FOOTER.COPILOT_MSG_INPUT')"
            @focus="onFocus"
            @blur="onBlur"
            @clear-selection="clearEditorSelection"
            @close="copilot.showEditor.value = false"
            @content-ready="copilot.setContentReady"
            @send="copilot.sendFollowUp"
          />
          <WootMessageEditor
            v-else-if="!showAudioRecorderEditor && !useWaComposerBar"
            ref="messageEditor"
            v-model="message"
            :conversation-id="conversationId"
            :editor-id="editorStateId"
            class="input popover-prosemirror-menu"
            :is-private="isOnPrivateNote"
            :placeholder="messagePlaceHolder"
            :update-selection-with="updateEditorSelectionWith"
            :min-height="isAnEmailChannel ? 4 : 1"
            :disabled="isEditorDisabled"
            enable-variables
            :variables="messageVariables"
            :signature="messageSignature"
            allow-signature
            :channel-type="channelType"
            :medium="inbox.medium"
            @typing-off="onTypingOff"
            @typing-on="onTypingOn"
            @focus="onFocus"
            @blur="onBlur"
            @toggle-user-mention="toggleUserMention"
            @toggle-canned-menu="toggleCannedMenu"
            @attach-canned-files="attachCannedResponseFiles"
            @toggle-variables-menu="toggleVariablesMenu"
            @clear-selection="clearEditorSelection"
            @execute-copilot-action="executeCopilotAction"
          />

          <div
            v-if="shouldShowGhostSuggestion"
            v-tooltip="'Pressione Tab para aceitar, Esc para dispensar'"
            class="wa-ghost-suggestion"
            role="button"
            tabindex="0"
            @click="acceptGhostSuggestion"
            @keydown.enter="acceptGhostSuggestion"
          >
            <span class="i-lucide-sparkles size-3 shrink-0 text-n-brand/70" />
            <span class="wa-ghost-suggestion__text italic">
              {{ ghostSuggestionText }}
            </span>
            <span class="wa-ghost-suggestion__hint">{{ 'Tab' }}</span>
          </div>

          <QuotedEmailPreview
            v-if="shouldShowQuotedPreview && isDefaultEditorMode"
            :quoted-email-text="quotedEmailText"
            :preview-text="quotedEmailPreviewText"
            class="mb-2"
            @toggle="toggleQuotedReply"
          />

          <div
            v-if="hasComposerAttachments && isDefaultEditorMode"
            class="bg-transparent py-0 mb-2"
            @paste="onPaste"
          >
            <AttachmentPreview
              class="mt-2"
              :attachments="composerAttachedFiles"
              @remove-attachment="removeAttachment"
              @retry-upload="retryAttachmentUpload"
            />
          </div>
        </template>
      </div>
    </Transition>

    <!--
      WhatsApp Web single-row composer (Phase C, take 2 — WA-fiel).
      Mirrors the real WhatsApp Web layout: 4 visible elements only,
        [+ anexar dropdown] [😀 emoji] [pill input com 🔒 lock dentro] [🎤 mic / ➤ send]
      Copilot, Expand, Templates etc. movidos pro dropdown do +.
    -->
    <div
      v-if="useWaComposerBar"
      class="wa-composer-bar group"
      :class="{
        'wa-composer-bar--focused': isFocused,
        'wa-composer-bar--disabled': isEditorDisabled,
        [`wa-composer-bar--mode-${waMode}`]: true,
      }"
    >
      <div
        class="wa-composer-bar__pill"
        :class="{
          'wa-composer-bar__pill--private': isOnPrivateNote,
          'wa-composer-bar__pill--copilot': waMode === 'copilot',
          'wa-composer-bar__pill--audio': waMode === 'audio',
        }"
      >
        <!-- MODO AUDIO: trash + waveform/duração + play-pause + send INLINE -->
        <template v-if="waMode === 'audio'">
          <button
            type="button"
            class="wa-composer-bar__icon"
            :title="$t('CONVERSATION.REPLYBOX.DISCARD_AUDIO_RECORDING')"
            @click="resetAudioRecorderInput"
          >
            <span class="i-lucide-trash-2 size-[20px]" />
          </button>
          <div class="wa-composer-bar__audio-area">
            <AudioRecorder
              ref="audioRecorderInput"
              class="wa-composer-bar__audio-recorder"
              :audio-record-format="audioRecordFormat"
              @recorder-progress-changed="onRecordProgressChanged"
              @finish-record="onFinishRecorder"
              @record-error="onRecordError"
              @play="recordingAudioState = 'playing'"
              @pause="recordingAudioState = 'paused'"
            />
            <span class="wa-composer-bar__audio-duration">{{
              recordingAudioDurationText
            }}</span>
          </div>
          <button
            type="button"
            class="wa-composer-bar__icon"
            :title="audioStateTitle"
            :disabled="recordingAudioState === 'processing'"
            @click="toggleAudioRecorderPlayPause"
          >
            <span :class="`${audioStateIcon} size-[20px]`" />
          </button>
          <button
            type="button"
            class="wa-composer-bar__send wa-send-btn"
            :class="{ 'wa-composer-bar__send--note': isOnPrivateNote }"
            :title="$t('CONVERSATION.REPLYBOX.SEND')"
            @click="onSendReply"
          >
            <span class="i-lucide-send size-[18px]" />
          </button>
        </template>

        <!-- MODO COPILOT: input do copilot inline + botão fechar -->
        <template v-else-if="waMode === 'copilot'">
          <button
            type="button"
            class="wa-composer-bar__icon"
            :title="$t('GENERAL.DISCARD')"
            @click="closeCopilot"
          >
            <span class="i-lucide-x size-[20px]" />
          </button>
          <div class="wa-composer-bar__input-wrap">
            <CopilotEditorSection
              class="wa-composer-bar__copilot-inline"
              :show-copilot-editor="copilot.showEditor.value"
              :is-generating-content="copilot.isGenerating.value"
              :generated-content="copilot.generatedContent.value"
              :is-popout="popOutReplyBox"
              :placeholder="$t('CONVERSATION.FOOTER.COPILOT_MSG_INPUT')"
              @focus="onFocus"
              @blur="onBlur"
              @clear-selection="clearEditorSelection"
              @close="copilot.showEditor.value = false"
              @content-ready="copilot.setContentReady"
              @send="copilot.sendFollowUp"
            />
          </div>
        </template>

        <!-- MODO INPUT (default): + emoji input lock send/mic -->
        <template v-else>
          <DropdownContainer placement="top">
            <template #trigger="{ toggle }">
              <button
                type="button"
                class="wa-composer-bar__icon"
                :title="$t('CONVERSATION.REPLYBOX.ATTACH')"
                :disabled="isEditorDisabled"
                @click="toggle"
              >
                <span class="i-lucide-plus size-[22px]" />
              </button>
            </template>
            <DropdownBody class="min-w-[14rem]">
              <DropdownItem
                v-if="showFileUpload || isOnPrivateNote"
                :label="$t('CONVERSATION.REPLYBOX.TIP_ATTACH_ICON')"
                icon="i-lucide-paperclip"
                :click="triggerWaFileUpload"
              />
              <DropdownItem
                v-if="currentChat.id"
                data-testid="replybox-schedule-message"
                :label="$t('CONVERSATION.REPLYBOX.SCHEDULE_MESSAGE')"
                icon="i-lucide-calendar-clock"
                :click="openScheduleMessage"
              />
              <DropdownItem
                v-if="showWhatsappTemplates"
                :label="$t('CONVERSATION.FOOTER.WHATSAPP_TEMPLATES')"
                icon="i-lucide-message-square-text"
                :click="openWhatsappTemplateModal"
              />
              <DropdownItem
                v-if="showContentTemplates"
                label="Content Templates"
                icon="i-lucide-message-square-text"
                :click="openContentTemplateModal"
              />
              <!-- F1 — Resposta pronta (Slot 5). F2 (localização) abaixo. F3 (contato) abaixo. -->
              <DropdownItem
                v-if="!isPrivate"
                data-testid="replybox-canned-response"
                :label="$t('CONVERSATION.REPLYBOX.CANNED_RESPONSE_MENU')"
                icon="i-lucide-message-square-quote"
                :click="openCannedResponseModal"
              />
              <!-- F2 — Compartilhar localização (Slot 6) -->
              <DropdownItem
                v-if="!isPrivate"
                data-testid="replybox-share-location"
                :label="$t('CONVERSATION.LOCATION.MENU')"
                icon="i-lucide-map-pin"
                :click="openLocationPicker"
              />
              <!-- F3 — Compartilhar contato (Slot 7) -->
              <DropdownItem
                v-if="!isPrivate"
                data-testid="replybox-share-contact"
                :label="$t('CONVERSATION.SHARE_CONTACT.MENU')"
                icon="i-lucide-user-round-plus"
                :click="openShareContactModal"
              />
            </DropdownBody>
          </DropdownContainer>
          <button
            type="button"
            class="wa-composer-bar__icon"
            :title="$t('CONVERSATION.REPLYBOX.EMOJI')"
            :disabled="isEditorDisabled"
            @click="toggleEmojiPicker"
          >
            <span class="i-lucide-smile size-[22px]" />
          </button>
          <div class="wa-composer-bar__input-wrap">
            <WootMessageEditor
              ref="messageEditor"
              v-model="message"
              :conversation-id="conversationId"
              :editor-id="editorStateId"
              class="wa-composer-bar__editor input popover-prosemirror-menu"
              :is-private="isOnPrivateNote"
              :placeholder="messagePlaceHolder"
              :update-selection-with="updateEditorSelectionWith"
              :min-height="1"
              :disabled="isEditorDisabled"
              enable-variables
              :variables="messageVariables"
              :signature="messageSignature"
              allow-signature
              :channel-type="channelType"
              :medium="inbox.medium"
              @typing-off="onTypingOff"
              @typing-on="onTypingOn"
              @focus="onFocus"
              @blur="onBlur"
              @toggle-user-mention="toggleUserMention"
              @toggle-canned-menu="toggleCannedMenu"
              @attach-canned-files="attachCannedResponseFiles"
              @toggle-variables-menu="toggleVariablesMenu"
              @clear-selection="clearEditorSelection"
              @execute-copilot-action="executeCopilotAction"
            />
            <button
              v-if="!isReplyRestricted"
              type="button"
              class="wa-composer-bar__lock"
              :class="{ 'is-active': isOnPrivateNote }"
              :title="waLockTooltip"
              :aria-pressed="isOnPrivateNote"
              @click="togglePrivateNote"
            >
              <span :class="`${waLockIcon} size-[18px]`" />
            </button>
            <div
              v-if="canShowCopilotInline"
              v-on-click-outside="closeInlineCopilotMenu"
              class="wa-composer-bar__sparkles-wrap"
            >
              <button
                ref="sparklesButtonRef"
                type="button"
                class="wa-composer-bar__sparkles"
                :class="[
                  { 'is-open': showInlineCopilotMenu },
                  sparklesOnboardingClass,
                ]"
                :title="$t('CONVERSATION.SIDEBAR.COPILOT')"
                :aria-pressed="showInlineCopilotMenu"
                :aria-describedby="sparklesAriaDescribedBy"
                data-ai-tour="sparkles-button"
                data-testid="ai-button"
                @click="toggleInlineCopilotMenu"
              >
                <span class="i-lucide-sparkles size-[18px]" />
              </button>
              <Transition name="wa-sparkles-menu">
                <CopilotMenuBar
                  v-if="showInlineCopilotMenu"
                  class="wa-composer-bar__sparkles-menu"
                  :has-selection="false"
                  :editor-content="message"
                  :conversation-id="conversationId"
                  :has-attachment="!!hasAttachments"
                  @execute-copilot-action="handleInlineCopilotAction"
                />
              </Transition>
              <AIOnboardingCoachmark
                v-if="shouldShowAIOnboarding"
                :anchor-ref="sparklesButtonRef"
                @confirm="handleAIOnboardingConfirm"
                @dismiss="handleAIOnboardingDismiss"
              />
            </div>
          </div>
          <Transition name="wa-action" mode="out-in">
            <button
              v-if="hasMessageContent"
              key="send"
              type="button"
              class="wa-composer-bar__send wa-send-btn"
              :class="{
                'wa-composer-bar__send--note': isOnPrivateNote,
                'is-disabled': isReplyButtonDisabled,
              }"
              :title="replyButtonLabel"
              :disabled="isReplyButtonDisabled"
              @click="onSendReply"
            >
              <span class="i-lucide-send size-[18px]" />
            </button>
            <button
              v-else-if="showAudioInBar"
              key="mic"
              type="button"
              class="wa-composer-bar__icon wa-composer-bar__icon--mic"
              :title="$t('CONVERSATION.REPLYBOX.RECORD')"
              @click="toggleAudioRecorder"
            >
              <span class="i-lucide-mic size-[22px]" />
            </button>
            <button
              v-else
              key="send-empty"
              type="button"
              class="wa-composer-bar__send is-disabled"
              disabled
            >
              <span class="i-lucide-send size-[18px]" />
            </button>
          </Transition>
        </template>
      </div>
    </div>

    <Transition
      v-if="!showWhatsappWindowExpired"
      mode="out-in"
      enter-active-class="transition-all duration-300 ease-out"
      enter-from-class="opacity-0 translate-y-2 scale-[0.98]"
      enter-to-class="opacity-100 translate-y-0 scale-100"
      leave-active-class="transition-all duration-200 ease-in"
      leave-from-class="opacity-100 translate-y-0 scale-100"
      leave-to-class="opacity-0 translate-y-2 scale-[0.98]"
    >
      <CopilotReplyBottomPanel
        v-if="copilot.isActive.value"
        key="copilot-bottom-panel"
        :is-generating-content="copilot.isButtonDisabled.value"
        @submit="onSubmitCopilotReply"
        @cancel="copilot.reset"
      />
      <ReplyBottomPanel
        v-else
        v-show="!useWaComposerBar"
        key="reply-bottom-panel"
        :conversation-id="conversationId"
        :enable-multiple-file-upload="enableMultipleFileUpload"
        :enable-whats-app-templates="showWhatsappTemplates"
        :enable-content-templates="showContentTemplates"
        :inbox="inbox"
        :is-on-private-note="isOnPrivateNote"
        :is-recording-audio="isRecordingAudio"
        :is-send-disabled="isReplyButtonDisabled"
        :is-note="isPrivate"
        :is-editor-disabled="isEditorDisabled"
        :on-file-upload="onFileUpload"
        :on-send="onSendReply"
        :conversation-type="conversationType"
        :recording-audio-duration-text="recordingAudioDurationText"
        :recording-audio-state="recordingAudioState"
        :send-button-text="replyButtonLabel"
        :show-audio-recorder="showAudioRecorder"
        :show-emoji-picker="showEmojiPicker"
        :show-file-upload="showFileUpload"
        :show-quoted-reply-toggle="shouldShowQuotedReplyToggle"
        :quoted-reply-enabled="quotedReplyPreference"
        :toggle-audio-recorder-play-pause="toggleAudioRecorderPlayPause"
        :on-discard-audio-recording="resetAudioRecorderInput"
        :toggle-audio-recorder="toggleAudioRecorder"
        :toggle-emoji-picker="toggleEmojiPicker"
        :message="message"
        :portal-slug="connectedPortalSlug"
        :new-conversation-modal-active="newConversationModalActive"
        @select-whatsapp-template="openWhatsappTemplateModal"
        @select-content-template="openContentTemplateModal"
        @replace-text="replaceText"
        @toggle-insert-article="toggleInsertArticle"
        @toggle-popout="togglePopout"
        @toggle-quoted-reply="toggleQuotedReply"
      />
    </Transition>

    <WhatsappTemplates
      :inbox-id="inbox.id"
      :show="showWhatsAppTemplatesModal"
      @close="hideWhatsappTemplatesModal"
      @on-send="onSendWhatsAppReply"
      @cancel="hideWhatsappTemplatesModal"
    />

    <ContentTemplates
      :inbox-id="inbox.id"
      :show="showContentTemplatesModal"
      @close="hideContentTemplatesModal"
      @on-send="onSendContentTemplateReply"
      @cancel="hideContentTemplatesModal"
    />

    <CannedResponseModal
      :show="showCannedResponseModal"
      @close="hideCannedResponseModal"
      @select="onCannedResponseSelect"
    />

    <LocationPickerModal
      v-if="showLocationPickerModal"
      :show="showLocationPickerModal"
      @close="hideLocationPicker"
      @select="onLocationSelect"
    />

    <ShareContactModal
      v-if="showShareContactModal"
      :show="showShareContactModal"
      @close="hideShareContactModal"
      @select="onShareContactSelect"
    />

    <woot-confirm-modal
      ref="confirmDialog"
      :title="$t('CONVERSATION.REPLYBOX.UNDEFINED_VARIABLES.TITLE')"
      :description="undefinedVariableMessage"
    />

    <!-- Fase 3 — Drag-and-drop premium WhatsApp Web -->
    <GlobalDropOverlay :show="isGlobalDragActive" />
    <AttachmentPreviewModal
      :show="showAttachmentModal"
      :files="composerAttachedFiles"
      :caption="message"
      :sending="isSendingAttachment"
      @update:caption="message = $event"
      @update:files="removeAttachment"
      @send="onAttachmentModalSend"
      @close="onAttachmentModalClose"
      @add-more="onAttachmentModalAddMore"
      @edit-image="onEditImage"
      @retry-upload="retryAttachmentUpload"
    />
    <ImageEditor
      :show="showImageEditor"
      :file="imageEditorFile"
      :initial-mode="imageEditorMode"
      @apply="onImageEditorApply"
      @cancel="onImageEditorCancel"
    />
  </div>
</template>

<style lang="scss" scoped>
.send-button {
  @apply mb-0;
}

.reply-box {
  @apply relative mb-2 mx-2 rounded-2xl;
  border: 1px solid transparent;
  box-shadow: 0 1px 2px rgba(11, 20, 26, 0.08);
  // Colors (light + dark) are owned by the WA skin (_wa-skin.scss).

  &.is-private {
    @apply bg-n-solid-amber dark:border-n-amber-3/10 border-n-amber-12/5;
  }
}

.send-button {
  @apply mb-0;
}

.reply-box__top {
  @apply relative py-0 px-3 -mt-px;
}

.whatsapp-invalid-enter-active,
.whatsapp-invalid-leave-active {
  transition:
    opacity 180ms ease,
    transform 220ms ease;
}

.whatsapp-invalid-enter-from,
.whatsapp-invalid-leave-to {
  opacity: 0;
  transform: translateY(-4px);
}

.emoji-dialog {
  @apply top-[unset] -bottom-10 ltr:-left-80 ltr:right-[unset] rtl:left-[unset] rtl:-right-80;

  &::before {
    filter: drop-shadow(0px 4px 4px rgba(0, 0, 0, 0.08));
    @apply ltr:-right-4 bottom-2 rtl:-left-4 ltr:rotate-[270deg] rtl:rotate-[90deg];
  }
}

.emoji-dialog--expanded {
  @apply left-[unset] bottom-0 absolute z-[100];

  &::before {
    transform: rotate(0deg);
    @apply ltr:left-1 rtl:right-1 -bottom-2;
  }
}
</style>
