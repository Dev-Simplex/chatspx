<script>
import AgentMessageBubble from 'widget/components/AgentMessageBubble.vue';
import UserMessageBubble from 'widget/components/UserMessageBubble.vue';
import MessageReplyButton from 'widget/components/MessageReplyButton.vue';
import ImageBubble from 'widget/components/ImageBubble.vue';
import VideoBubble from 'widget/components/VideoBubble.vue';
import FileBubble from 'widget/components/FileBubble.vue';
import ReplyToChip from 'widget/components/ReplyToChip.vue';
import DragWrapper from 'widget/components/DragWrapper.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';
import Avatar from 'widget/ui/WAvatar.vue';
import { messageStamp } from 'shared/helpers/timeHelper';
import { isASubmittedFormMessage } from 'shared/helpers/MessageTypeHelper';
import { MESSAGE_TYPE } from 'widget/helpers/constants';
import { ATTENDANT, attendantOf } from 'widget/helpers/aiIdentity';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { emitter } from 'shared/helpers/mitt';
import configMixin from '../mixins/configMixin';
import messageMixin from '../mixins/messageMixin';

/**
 * A LINHA da conversa — bloco 2.02.
 *
 * Antes eram dois componentes que se pareciam de longe e divergiam de perto:
 * `AgentMessage.vue` (335 linhas) e `UserMessage.vue` (179). O que eles tinham
 * em comum não era pouco — a citação, o botão de responder, o laço de anexos,
 * o horário fora do balão, a invalidação de imagem/vídeo com erro — e estava
 * escrito duas vezes, com diferenças que ninguém escolheu: só o lado do agente
 * tratava `audio`, só o lado do visitante repassava `isInProgress` ao
 * `FileBubble`. Corrigir um lado deixava o outro para trás.
 *
 * Aqui os dois viram UMA linha com `variant`. O que é genuinamente diferente
 * continua diferente, e agora está lado a lado onde dá para ver: o avatar e o
 * rótulo de IA só existem no agente; o arrastar-para-citar, o estado de falha e
 * o botão de reenvio só existem no visitante; o carimbo de hora do agente traz
 * a data por extenso porque a linha dele pode estar longe do separador.
 *
 * ⚠️ MARCAÇÃO PRESERVADA À RISCA. As quatro telas do widget são cobertas por
 * 20 snapshots de pixel, e a régua não se move para acomodar refatoração:
 * classe, ordem de nó e encadeamento de `v-if` saíram dos dois originais
 * copiados, incluindo o encadeamento de anexos em que `ImageBubble` abre uma
 * cadeia própria e `FileBubble` fecha a outra.
 *
 * `AgentMessage.vue` e `UserMessage.vue` continuam existindo como cascas — é
 * por elas que `ChatMessage.vue` escolhe o lado, e é o nome delas que aparece
 * na árvore de componentes.
 */
export default {
  name: 'MessageRow',
  components: {
    AgentMessageBubble,
    UserMessageBubble,
    MessageReplyButton,
    ImageBubble,
    VideoBubble,
    FileBubble,
    ReplyToChip,
    DragWrapper,
    FluentIcon,
    Avatar,
  },
  mixins: [configMixin, messageMixin],
  props: {
    /** `agent` desenha o lado de quem atende; `user`, o lado de quem visita. */
    variant: {
      type: String,
      default: 'user',
      validator: valor => ['agent', 'user'].includes(valor),
    },
    message: { type: Object, default: () => {} },
    replyTo: { type: Object, default: () => {} },
    classeAgrupamento: { type: String, default: null },
  },
  data() {
    return { hasImageError: false, hasVideoError: false };
  },
  computed: {
    isAgent() {
      return this.variant === 'agent';
    },
    hasReplyTo() {
      return this.replyTo && (this.replyTo.content || this.replyTo.attachments);
    },
    // O carimbo do agente traz a data por extenso; o do visitante, só a hora.
    // Os dois formatos vêm dos componentes originais e um snapshot os separa.
    readableTime() {
      const { created_at: createdAt = '' } = this.message;
      return this.isAgent
        ? messageStamp(createdAt, 'LLL d yyyy, h:mm a')
        : messageStamp(createdAt);
    },
    // ── Só do agente ──────────────────────────────────────────────────────────
    messageType() {
      const { message_type: type = 1 } = this.message;
      return type;
    },
    contentType() {
      const { content_type: type = '' } = this.message;
      return type;
    },
    shouldDisplayAgentMessage() {
      if (
        this.contentType === 'input_select' &&
        this.messageContentAttributes.submitted_values &&
        !this.message.content
      ) {
        return false;
      }
      return this.message.content;
    },
    // Bloco 4.09 — a 3a das tres marcacoes: o rotulo colado na BOLHA.
    //
    // Derivado da propria mensagem, nao herdado do pai: numa conversa que trocou
    // de atendente, cada bolha tem de dizer quem a escreveu — inclusive as
    // antigas, quando o visitante rola para tras. Herdar do estado atual faria a
    // conversa inteira parecer ter vindo de quem atende agora.
    attendant() {
      return attendantOf(this.message);
    },
    isFromAI() {
      return this.attendant === ATTENDANT.AI;
    },
    // `aiLabelPersistent` e uma das 11 flags planas da secao B.3 (bloco 3.05).
    // Sem a chave, o resolvedor devolve `true` — o rotulo aparece por padrao,
    // que e a decisao de produto: quem fala com maquina tem direito de saber.
    shouldShowAiLabel() {
      return this.isFromAI && this.isAiLabelPersistent;
    },
    agentName() {
      if (this.message.sender) {
        return this.message.sender.available_name || this.message.sender.name;
      }
      if (this.message.additional_attributes?.sender_name) {
        return this.message.additional_attributes.sender_name;
      }
      if (this.useInboxAvatarForBot) {
        return this.channelConfig.websiteName;
      }
      return this.$t('UNREAD_VIEW.BOT');
    },
    avatarUrl() {
      const displayImage = this.useInboxAvatarForBot
        ? this.inboxAvatarUrl
        : '/assets/images/chatwoot_bot.png';

      if (this.message.message_type === MESSAGE_TYPE.TEMPLATE) {
        return displayImage;
      }
      if (this.message.sender) {
        return this.message.sender.avatar_url;
      }
      return (
        this.message.additional_attributes?.sender_avatar_url || displayImage
      );
    },
    // 4.01 — quando o backend materializou a resposta do visitante como mensagem `incoming`
    // (`reply_message_id`), ela chega pela lista e se desenha sozinha. O balão local seria
    // uma DUPLICATA na tela. Sem o motor Flow a chave nunca existe e o widget é o de hoje.
    hasVisitorReplyMessage() {
      return !!this.messageContentAttributes.reply_message_id;
    },
    hasRecordedResponse() {
      if (this.hasVisitorReplyMessage) return false;
      return (
        this.messageContentAttributes.submitted_email ||
        (this.messageContentAttributes.submitted_values &&
          !['form', 'input_csat'].includes(this.contentType))
      );
    },
    responseMessage() {
      if (this.messageContentAttributes.submitted_email) {
        return { content: this.messageContentAttributes.submitted_email };
      }
      if (
        this.messageContentAttributes.submitted_values &&
        this.contentType === 'input_select'
      ) {
        const [selectionOption = {}] =
          this.messageContentAttributes.submitted_values;
        return { content: selectionOption.title || selectionOption.value };
      }
      return '';
    },
    isASubmittedForm() {
      if (this.hasVisitorReplyMessage) return false;
      return isASubmittedFormMessage(this.message);
    },
    submittedFormValues() {
      return this.messageContentAttributes.submitted_values.map(valor => ({
        id: valor.name,
        content: valor.value,
      }));
    },
    wrapClass() {
      return { 'has-text': this.shouldDisplayAgentMessage };
    },
    // ── Só do visitante ───────────────────────────────────────────────────────
    isInProgress() {
      const { status = '' } = this.message;
      return status === 'in_progress';
    },
    isFailed() {
      const { status = '' } = this.message;
      return status === 'failed';
    },
    showTextBubble() {
      return !!this.message.content;
    },
  },
  watch: {
    message() {
      this.hasImageError = false;
      this.hasVideoError = false;
    },
  },
  mounted() {
    this.hasImageError = false;
    this.hasVideoError = false;
  },
  methods: {
    onImageLoadError() {
      this.hasImageError = true;
    },
    onVideoLoadError() {
      this.hasVideoError = true;
    },
    toggleReply() {
      emitter.emit(BUS_EVENTS.TOGGLE_REPLY_TO_MESSAGE, this.message);
    },
    async retrySendMessage() {
      await this.$store.dispatch('conversation/sendMessageWithData', {
        message: this.message,
      });
    },
  },
};
</script>

<template>
  <!-- `has-response` SAIU com o bloco 2.03. Ela existia só para alimentar
       `.has-response + .user-message-wrap`, um dos seis seletores de irmão que
       decidiam agrupamento; quem decide agora é `useMessageGrouping.js`, e o
       que chega aqui é a classe pronta. -->
  <div
    v-if="isAgent"
    class="agent-message-wrap group"
    :class="classeAgrupamento"
  >
    <div v-if="!isASubmittedForm" class="agent-message">
      <div class="avatar-wrap">
        <div class="user-thumbnail-box">
          <Avatar
            v-if="message.showAvatar || hasRecordedResponse"
            :src="avatarUrl"
            :size="24"
            :name="agentName"
            rounded-full
          />
        </div>
      </div>
      <div class="message-wrap">
        <!--
          Rotulo persistente de IA. Texto LIMPO, sem simbolo: ele e lido por
          leitor de tela, e emoji dentro do nome acessivel faz anunciar o desenho
          antes da palavra — foi o que esta trilha achou no CSAT.RATINGS.
        -->
        <div
          v-if="shouldShowAiLabel"
          class="agent-message__ai-label"
          data-ai-label="true"
        >
          {{ $t('AI_IDENTITY.AI_LABEL') }}
        </div>
        <div v-if="hasReplyTo" class="flex mt-2 mb-1 text-xs">
          <ReplyToChip :reply-to="replyTo" />
        </div>
        <div class="flex w-full gap-1">
          <div
            class="space-y-2"
            :class="{
              'w-full':
                contentType === 'form' &&
                !messageContentAttributes?.submitted_values,
            }"
          >
            <AgentMessageBubble
              v-if="shouldDisplayAgentMessage"
              :content-type="contentType"
              :message-content-attributes="messageContentAttributes"
              :message-id="message.id"
              :message-type="messageType"
              :message="message.content"
            />
            <div
              v-if="hasAttachments"
              class="space-y-2 chat-bubble has-attachment agent bg-n-background dark:bg-n-solid-3"
              :class="wrapClass"
            >
              <div
                v-for="attachment in message.attachments"
                :key="attachment.id"
              >
                <ImageBubble
                  v-if="attachment.file_type === 'image' && !hasImageError"
                  :url="attachment.data_url"
                  :thumb="attachment.data_url"
                  @error="onImageLoadError"
                />

                <VideoBubble
                  v-if="attachment.file_type === 'video' && !hasVideoError"
                  :url="attachment.data_url"
                  @error="onVideoLoadError"
                />

                <audio
                  v-else-if="attachment.file_type === 'audio'"
                  controls
                  class="h-10 dark:invert"
                >
                  <source :src="attachment.data_url" />
                </audio>
                <FileBubble v-else :url="attachment.data_url" />
              </div>
            </div>
          </div>
          <div class="flex flex-col justify-end">
            <MessageReplyButton
              class="transition-opacity delay-75 opacity-0 group-hover:opacity-100 sm:opacity-0"
              @click="toggleReply"
            />
          </div>
        </div>
        <!-- Bloco 2.03 — o horário FORA do balão, na linha do agente. -->
        <p v-if="hasAttachments" class="message-time">{{ readableTime }}</p>
        <p
          v-if="message.showAvatar || hasRecordedResponse"
          v-dompurify-html="agentName"
          class="agent-name text-n-slate-11"
        />
      </div>
    </div>

    <!-- A resposta do visitante que o widget desenha localmente é uma LINHA DE
         VISITANTE dentro da linha do agente: mesma variante, mesmo componente.
         Enquanto eram dois arquivos, isto era `AgentMessage` importando
         `UserMessage` — a dependência que amarrava os dois. -->
    <MessageRow v-if="hasRecordedResponse" :message="responseMessage" />
    <!-- Estes balões eram irmãos adjacentes de verdade, e o
         `.user-message-wrap + .user-message-wrap` os agrupava. Aqui a
         continuação não precisa de composable: são todos do visitante, em
         sequência, então tudo que não é o primeiro continua. -->
    <div v-if="isASubmittedForm">
      <MessageRow
        v-for="(submittedValue, indice) in submittedFormValues"
        :key="submittedValue.id"
        :message="submittedValue"
        :classe-agrupamento="indice > 0 ? 'is-continuacao' : null"
      />
    </div>
  </div>

  <div v-else class="user-message-wrap group" :class="classeAgrupamento">
    <div class="flex gap-1 user-message">
      <div
        class="message-wrap"
        :class="{ 'in-progress': isInProgress, 'is-failed': isFailed }"
      >
        <div v-if="hasReplyTo" class="flex justify-end mt-2 mb-1 text-xs">
          <ReplyToChip :reply-to="replyTo" />
        </div>
        <div class="flex justify-end gap-1">
          <div class="flex flex-col justify-end">
            <MessageReplyButton
              v-if="!isInProgress && !isFailed"
              class="transition-opacity delay-75 opacity-0 group-hover:opacity-100 sm:opacity-0"
              @click="toggleReply"
            />
          </div>
          <DragWrapper direction="left" @dragged="toggleReply">
            <UserMessageBubble
              v-if="showTextBubble"
              :message="message.content"
              :status="message.status"
            />
            <div
              v-if="hasAttachments"
              class="chat-bubble has-attachment user bg-w-brand"
            >
              <div
                v-for="attachment in message.attachments"
                :key="attachment.id"
              >
                <ImageBubble
                  v-if="attachment.file_type === 'image' && !hasImageError"
                  :url="attachment.data_url"
                  :thumb="attachment.data_url"
                  @error="onImageLoadError"
                />

                <VideoBubble
                  v-if="attachment.file_type === 'video' && !hasVideoError"
                  :url="attachment.data_url"
                  @error="onVideoLoadError"
                />

                <FileBubble
                  v-else
                  :url="attachment.data_url"
                  :is-in-progress="isInProgress"
                  is-user-bubble
                />
              </div>
            </div>
          </DragWrapper>
        </div>
        <!-- Bloco 2.03 — o horário fora do balão, do lado do visitante. -->
        <p v-if="hasAttachments" class="message-time message-time--fim">
          {{ readableTime }}
        </p>
        <div
          v-if="isFailed"
          class="flex justify-end px-4 py-2 text-n-ruby-9 align-middle"
        >
          <button
            v-if="!hasAttachments"
            :title="$t('COMPONENTS.MESSAGE_BUBBLE.RETRY')"
            class="inline-flex items-center justify-center ltr:ml-2 rtl:mr-2"
            @click="retrySendMessage"
          >
            <FluentIcon icon="arrow-clockwise" size="14" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped lang="scss">
.agent-message__ai-label {
  // Sem cor propria de "marca de IA": o rotulo e TEXTO, e texto e o que sobrevive
  // a daltonismo, a sol na tela e a leitor de tela. O aceite proibe roxo porque
  // ele colapsa contra o azul em deuteranopia — mas trocar de cor so mudaria a
  // colisao de lugar. A resposta e nao depender de cor nenhuma para distinguir.
  @apply text-[0.6875rem] leading-3 text-n-slate-11 mb-1 ltr:ml-1 rtl:mr-1;
}
</style>
