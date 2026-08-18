<script>
import { mapGetters } from 'vuex';
import { IFrameHelper, RNHelper } from 'widget/helpers/utils';
import { popoutChatWindow } from '../helpers/popoutHelper';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import configMixin from 'widget/mixins/configMixin';
import { CONVERSATION_STATUS } from 'shared/constants/messages';

export default {
  name: 'HeaderActions',
  components: { FluentIcon },
  mixins: [configMixin],
  props: {
    showPopoutButton: {
      type: Boolean,
      default: false,
    },
    showEndConversationButton: {
      type: Boolean,
      default: true,
    },
  },
  computed: {
    ...mapGetters({
      conversationAttributes: 'conversationAttributes/getConversationParams',
      canUserEndConversation: 'appConfig/getCanUserEndConversation',
    }),
    canLeaveConversation() {
      return [
        CONVERSATION_STATUS.OPEN,
        CONVERSATION_STATUS.SNOOZED,
        CONVERSATION_STATUS.PENDING,
      ].includes(this.conversationStatus);
    },
    isIframe() {
      return IFrameHelper.isIFrame();
    },
    isRNWebView() {
      return RNHelper.isRNWebView();
    },
    showHeaderActions() {
      return this.isIframe || this.isRNWebView || this.hasWidgetOptions;
    },
    conversationStatus() {
      return this.conversationAttributes.status;
    },
    hasWidgetOptions() {
      return this.showPopoutButton || this.conversationStatus === 'open';
    },
  },
  methods: {
    popoutWindow() {
      this.closeWindow();
      const {
        location: { origin },
        chatwootWebChannel: { websiteToken },
        authToken,
      } = window;
      popoutChatWindow(
        origin,
        websiteToken,
        this.$root.$i18n.locale,
        authToken
      );
    },
    closeWindow() {
      if (IFrameHelper.isIFrame()) {
        IFrameHelper.sendMessage({ event: 'closeWindow' });
      } else if (RNHelper.isRNWebView) {
        RNHelper.sendMessage({ type: 'close-widget' });
      }
    },
    resolveConversation() {
      this.$store.dispatch('conversation/resolveConversation');
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <div v-if="showHeaderActions" class="actions flex items-center gap-3">
    <button
      v-if="
        canLeaveConversation &&
        canUserEndConversation &&
        hasEndConversationEnabled &&
        showEndConversationButton
      "
      class="button transparent compact flex items-center justify-center min-w-11 min-h-11 md:min-w-10 md:min-h-10"
      :title="$t('END_CONVERSATION')"
      :aria-label="$t('END_CONVERSATION')"
      @click="resolveConversation"
    >
      <FluentIcon icon="sign-out" size="22" class="text-w-on-brand" />
    </button>
    <!-- `title` E `aria-label`: o botão só tem ícone, então sem um nome ele é
         anunciado como "botão" e nada mais. `title` dá a dica visual no mouse;
         `aria-label` é o que o leitor de tela usa — e não depende de o ícone
         expor texto. -->
    <button
      v-if="showPopoutButton"
      class="button transparent compact new-window--button flex items-center justify-center min-w-11 min-h-11 md:min-w-10 md:min-h-10"
      :title="$t('A11Y.OPEN_IN_NEW_WINDOW')"
      :aria-label="$t('A11Y.OPEN_IN_NEW_WINDOW')"
      @click="popoutWindow"
    >
      <FluentIcon icon="open" size="22" class="text-w-on-brand" />
    </button>
    <button
      class="button transparent compact close-button flex items-center justify-center min-w-11 min-h-11 md:min-w-10 md:min-h-10"
      :class="{
        'rn-close-button': isRNWebView,
      }"
      :title="$t('A11Y.CLOSE_WIDGET')"
      :aria-label="$t('A11Y.CLOSE_WIDGET')"
      @click="closeWindow"
    >
      <FluentIcon icon="dismiss" size="24" class="text-w-on-brand" />
    </button>
  </div>
</template>

<style scoped lang="scss">
.actions {
  .close-button {
    display: none;
  }

  .rn-close-button {
    display: block !important;
  }
}
</style>
