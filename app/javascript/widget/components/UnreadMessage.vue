<script>
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
// Bloco 1.08 — era `dashboard/components-next/avatar/Avatar.vue`. Aquele
// componente arrastava, por import estático, `Icon.vue`, `GalleryView.vue`,
// `button/Button.vue` e `spinner/Spinner.vue`, e com eles 27.619 B de
// utilitárias para o CSS do widget — por cinco props. `WAvatar` é a réplica
// pixel a pixel do subconjunto que esta tela usa.
import Avatar from 'widget/components/WAvatar.vue';
import configMixin from '../mixins/configMixin';
import { isEmptyObject } from 'widget/helpers/utils';
import {
  ON_CAMPAIGN_MESSAGE_CLICK,
  ON_UNREAD_MESSAGE_CLICK,
} from '../constants/widgetBusEvents';
import { emitter } from 'shared/helpers/mitt';

export default {
  name: 'UnreadMessage',
  components: { Avatar },
  mixins: [configMixin],
  props: {
    message: {
      type: String,
      default: '',
    },
    showSender: {
      type: Boolean,
      default: false,
    },
    sender: {
      type: Object,
      default: () => {},
    },
    campaignId: {
      type: Number,
      default: null,
    },
    classeAgrupamento: {
      type: String,
      default: null,
    },
  },
  setup() {
    const { formatMessage, getPlainText, truncateMessage, highlightContent } =
      useMessageFormatter();
    return {
      formatMessage,
      getPlainText,
      truncateMessage,
      highlightContent,
    };
  },
  computed: {
    companyName() {
      return `${this.$t('UNREAD_VIEW.COMPANY_FROM')} ${
        this.channelConfig.websiteName
      }`;
    },
    avatarUrl() {
      // eslint-disable-next-line
      const displayImage = this.useInboxAvatarForBot
        ? this.inboxAvatarUrl
        : '/assets/images/chatwoot_bot.png';
      if (this.isSenderExist(this.sender)) {
        const { avatar_url: avatarUrl } = this.sender;
        return avatarUrl;
      }
      return displayImage;
    },
    agentName() {
      if (this.isSenderExist(this.sender)) {
        const { available_name: availableName, name } = this.sender;
        return availableName || name || '';
      }
      if (this.useInboxAvatarForBot) {
        return this.channelConfig.websiteName;
      }
      return this.$t('UNREAD_VIEW.BOT');
    },
    availabilityStatus() {
      if (this.isSenderExist(this.sender)) {
        const { availability_status: availabilityStatus } = this.sender;
        return availabilityStatus;
      }
      return null;
    },
  },
  methods: {
    isSenderExist(sender) {
      return sender && !isEmptyObject(sender);
    },
    onClickMessage() {
      if (this.campaignId) {
        emitter.emit(ON_CAMPAIGN_MESSAGE_CLICK, this.campaignId);
      } else {
        emitter.emit(ON_UNREAD_MESSAGE_CLICK);
      }
    },
  },
};
</script>

<template>
  <div class="chat-bubble-wrap" :class="classeAgrupamento">
    <!-- `bg-white` SEM variante `dark:` é INTENCIONAL. Não "conserte".
         Estas bolhas não vivem no painel: o holder do modo não-lidas é despido
         (`.has-unread-view` zera sombra, borda e raio no `SDK_CSS`), então elas
         flutuam sobre o SITE DO CLIENTE — cujo tema o widget não conhece e não
         controla. Branco com `text-n-black` (#000000, fixo, aplicado em
         `_conversation.scss` na regra `.unread-messages … .chat-bubble`) dá
         21:1, o contraste máximo possível, e é legível sobre qualquer página.
         A prova de que foi decisão e não esquecimento está na MESMA declaração
         do SCSS: ela dá variante escura à BORDA (`dark:border-n-slate-11/50`)
         para separar a bolha branca de um site escuro, e no mesmo gesto mantém
         o par branco/preto. Quem pensou no modo escuro ali resolveu-o pela
         borda, de propósito.
         Travado por `specs/browser/unread-bubble-contrast.check.mjs`. -->
    <button class="chat-bubble agent bg-white" @click="onClickMessage">
      <div v-if="showSender" class="row--agent-block">
        <Avatar
          :src="avatarUrl"
          :size="20"
          :name="agentName"
          :status="availabilityStatus"
          rounded-full
        />
        <span v-dompurify-html="agentName" class="agent--name" />
        <span v-dompurify-html="companyName" class="company--name" />
      </div>
      <div
        v-dompurify-html="formatMessage(message, false)"
        class="message-content"
      />
    </button>
  </div>
</template>

<style lang="scss" scoped>
.chat-bubble {
  @apply max-w-[85%] cursor-pointer p-4;
}

.row--agent-block {
  @apply items-center flex text-left pb-2 text-xs;

  .agent--name {
    @apply font-medium ml-1;
  }

  .company--name {
    @apply text-n-slate-11 dark:text-n-slate-10 ml-1;
  }
}
</style>
