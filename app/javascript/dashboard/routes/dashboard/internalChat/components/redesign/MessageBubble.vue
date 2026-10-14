<script setup>
import { ref, computed, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { frontendURL } from 'dashboard/helper/URLHelper';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { getRecentEmojis, addRecentEmoji } from 'shared/helpers/recentEmojis';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
// Mesmas peças do menu de mensagem do chat normal — o menu do chat interno
// passa a ser idêntico ao de lá (lista com rótulo, não uma pílula de ícones).
import AudioPlayer from './AudioPlayer.vue';
import { useEscClose } from './useEscClose';
import ContextMenu from 'dashboard/components/ui/ContextMenu.vue';
import MenuItem from 'dashboard/components/widgets/conversation/contextMenu/menuItem.vue';

const props = defineProps({
  message: { type: Object, required: true },
  currentUserId: { type: [Number, String], default: null },
  // Nomes de agentes que viram destaque quando aparecem como "@Nome".
  mentionNames: { type: Array, default: () => [] },
});

const emit = defineEmits([
  'react',
  'edit',
  'delete',
  'reply',
  'retry',
  'scrollTo',
  'forward',
  'info',
  'star',
  'replyPrivately',
]);

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');
const conversationPath = displayId =>
  frontendURL(`accounts/${accountId.value}/conversations/${displayId}`);

// ── Texto rico: links, #123 (conversa) e @menções ──────────────────────────
const TOKEN_RE = /(https?:\/\/[^\s]+|#\d+)/g;
const mentionRe = computed(() => {
  const names = props.mentionNames
    .slice()
    .sort((a, b) => b.length - a.length)
    .map(n => n.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'));
  return names.length ? new RegExp(`@(?:${names.join('|')})`, 'g') : null;
});
const splitMentions = text => {
  const re = mentionRe.value;
  if (!re) return [{ t: 'text', v: text }];
  const out = [];
  let last = 0;
  text.replace(re, (match, idx) => {
    if (idx > last) out.push({ t: 'text', v: text.slice(last, idx) });
    out.push({ t: 'mention', v: match });
    last = idx + match.length;
    return match;
  });
  if (last < text.length) out.push({ t: 'text', v: text.slice(last) });
  return out;
};
const contentParts = computed(() => {
  const s = String(props.message.content || '');
  const out = [];
  let last = 0;
  s.replace(TOKEN_RE, (match, _g, idx) => {
    if (idx > last) out.push(...splitMentions(s.slice(last, idx)));
    if (match[0] === '#') out.push({ t: 'conv', v: match, id: match.slice(1) });
    else out.push({ t: 'link', v: match });
    last = idx + match.length;
    return match;
  });
  if (last < s.length) out.push(...splitMentions(s.slice(last)));
  return out;
});

const QUICK_EMOJIS = ['👍', '❤️', '😂', '🎉', '✅', '🙏'];
const REACTION_SLOTS = QUICK_EMOJIS.length;
const IMAGE_RE = /\.(png|jpe?g|gif|webp|bmp|svg|avif)$/i;
const AUDIO_RE = /\.(mp3|wav|ogg|oga|m4a|aac|webm|opus)$/i;
const isImage = att => IMAGE_RE.test(att?.filename || '');
const isAudio = att => AUDIO_RE.test(att?.filename || '');

// ── Estado local do menu/edição (mantido no bubble, mais limpo) ──────────────
const showMenu = ref(false);
const showReactionPicker = ref(false);
const confirmDelete = ref(false);
const editing = ref(false);
const editDraft = ref('');
const editRef = ref(null);

const closeAll = () => {
  showMenu.value = false;
  showReactionPicker.value = false;
  confirmDelete.value = false;
};

useEscClose(
  () => showMenu.value || showReactionPicker.value || confirmDelete.value,
  closeAll
);

// O menu agora é o ContextMenu compartilhado: flutua em `position: fixed` num
// teleport para o body, então a posição vem em coordenadas de viewport
// (clientX/clientY), não de página.
const menuPosition = ref({ x: 0, y: 0 });
const dropdownButtonRef = ref(null);

const openMenuAt = (x, y) => {
  if (props.message.deleted) return;
  showReactionPicker.value = false;
  confirmDelete.value = false;
  menuPosition.value = { x, y };
  showMenu.value = true;
};

// Gatilho ⌄: o menu abre ancorado embaixo da seta, igual ao do chat normal.
const openMenuFromButton = () => {
  const el = dropdownButtonRef.value;
  if (!el?.getBoundingClientRect) return;
  const rect = el.getBoundingClientRect();
  openMenuAt(rect.right, rect.bottom + 4);
};

const openMenuFromEvent = event =>
  openMenuAt(event.clientX ?? 0, event.clientY ?? 0);

// Long-press abre o menu no toque (sem clique-direito no mobile).
let longPressTimer = null;
const startLongPress = event => {
  const touch = event.touches?.[0];
  clearTimeout(longPressTimer);
  longPressTimer = setTimeout(() => {
    if (touch) openMenuAt(touch.clientX, touch.clientY);
    else openMenuFromButton();
  }, 450);
};
const cancelLongPress = () => clearTimeout(longPressTimer);

const onReply = () => {
  closeAll();
  emit('reply', props.message);
};

// Só mensagem que já chegou ao servidor pode ser encaminhada (o balão
// otimista ainda não tem id de verdade).
const persisted = computed(
  () => !['progress', 'failed'].includes(props.message.status)
);
const forwarded = computed(() =>
  Boolean(props.message.contentAttributes?.forwarded)
);
// Prévia do link (o servidor busca e manda por tempo real). Some se a mensagem
// foi editada e o link saiu do texto.
const linkPreview = computed(() => {
  const preview = props.message.contentAttributes?.link_preview;
  if (!preview?.url || !preview.title) return null;
  return (props.message.content || '').includes(preview.url) ? preview : null;
});
const hidePreviewImage = ref(false);

const onForward = () => {
  closeAll();
  emit('forward', props.message);
};

const onReplyPrivately = () => {
  closeAll();
  emit('replyPrivately', props.message);
};

const onStar = () => {
  closeAll();
  emit('star', props.message);
};

const onInfo = () => {
  closeAll();
  emit('info', props.message);
};

const copyContent = async () => {
  closeAll();
  await copyTextToClipboard(props.message.content || '');
  useAlert(t('INTERNAL_CHAT.BUBBLE.COPIED'));
};

// Os emojis oferecidos na barra de reação: seus recentes primeiro, completando
// com os padrões até encher os slots (mantém a barra sempre do mesmo tamanho).
const recentEmojis = ref(getRecentEmojis());
const reactionEmojis = computed(() => {
  const recent = recentEmojis.value.slice(0, REACTION_SLOTS);
  const fallback = QUICK_EMOJIS.filter(emoji => !recent.includes(emoji));
  return [...recent, ...fallback].slice(0, REACTION_SLOTS);
});

const toggleReactionPicker = () => {
  showMenu.value = false;
  confirmDelete.value = false;
  // Relê ao abrir: o emoji pode ter sido usado no composer desde a última vez.
  if (!showReactionPicker.value) recentEmojis.value = getRecentEmojis();
  showReactionPicker.value = !showReactionPicker.value;
};
const react = emoji => {
  closeAll();
  recentEmojis.value = addRecentEmoji(emoji);
  emit('react', { messageId: props.message.id, emoji });
};

const startEdit = () => {
  closeAll();
  editing.value = true;
  editDraft.value = props.message.content || '';
  nextTick(() => editRef.value?.focus());
};
const cancelEdit = () => {
  editing.value = false;
  editDraft.value = '';
};
const saveEdit = () => {
  const content = editDraft.value.trim();
  if (!content) return;
  editing.value = false;
  emit('edit', { messageId: props.message.id, content });
};

const askDelete = () => {
  showMenu.value = false;
  showReactionPicker.value = false;
  confirmDelete.value = true;
};
const doDelete = () => {
  confirmDelete.value = false;
  emit('delete', props.message.id);
};

// ── Reações ──────────────────────────────────────────────────────────────────
const reactionEntries = computed(() =>
  Object.entries(props.message.reactions || {}).filter(([, u]) => u?.length)
);
// Só emoji (até 3): aparece grande e sem balão, como no iPhone.
const JUMBO_RE =
  /^(?:\p{Extended_Pictographic}|\p{Emoji_Modifier}|\uFE0F|\u200D|\s)+$/u;
const jumbo = computed(() => {
  const m = props.message;
  const text = (m.content || '').trim();
  if (!text || m.attachments?.length || m.replyTo || m.sharedConversation)
    return false;
  if (!JUMBO_RE.test(text)) return false;
  return (text.match(/\p{Extended_Pictographic}/gu) || []).length <= 3;
});

// Situação da conversa de cliente compartilhada (aberta, resolvida…).
const SHARED_STATUS = ['open', 'resolved', 'pending', 'snoozed'];
const sharedStatus = computed(() => {
  const status = props.message.sharedConversation?.status;
  return SHARED_STATUS.includes(status)
    ? t(`INTERNAL_CHAT.SHARED.STATUS.${status.toUpperCase()}`)
    : '';
});

// ── Aviso do sistema ─────────────────────────────────────────────────────────
const isSystem = computed(() => props.message.messageType === 'system');

const iReacted = emoji =>
  (props.message.reactions?.[emoji] || [])
    .map(Number)
    .includes(Number(props.currentUserId));
</script>

<template>
  <!-- Aviso do sistema: centralizado, discreto, sem autor -->
  <div
    v-if="isSystem"
    class="flex flex-col items-center gap-1.5 py-1"
    :data-msg-id="message.id"
  >
    <span
      v-tooltip="t('INTERNAL_CHAT.SYSTEM_MESSAGE')"
      class="inline-flex items-start gap-1.5 max-w-[90%] md:max-w-[75%] px-3 py-1.5 text-xs text-center rounded-2xl bg-n-alpha-2 text-n-slate-11"
    >
      <span
        class="flex-shrink-0 size-3.5 mt-px"
        :class="message.contentAttributes?.icon || 'i-lucide-info'"
      />
      <span class="whitespace-pre-wrap">{{ message.content }}</span>
      <span class="flex-shrink-0 tabular-nums text-n-slate-10">
        {{ message.time }}
      </span>
    </span>
    <router-link
      v-if="message.sharedConversation"
      :to="conversationPath(message.sharedConversation.display_id)"
      class="inline-flex items-center gap-1.5 px-3 py-1 text-xs font-semibold border rounded-full border-n-weak bg-n-solid-1 text-n-teal-11 hover:bg-n-alpha-1"
    >
      <span class="i-lucide-message-square-share size-3.5" />
      {{
        t('INTERNAL_CHAT.SYSTEM_CONVERSATION', {
          id: message.sharedConversation.display_id,
        })
      }}
      <span
        v-if="message.sharedConversation.contact_name"
        class="font-normal text-n-slate-11"
        >· {{ message.sharedConversation.contact_name }}</span
      >
      <span class="i-lucide-arrow-right size-3.5" />
    </router-link>
  </div>
  <div
    v-else
    class="flex items-end gap-2 group"
    :class="message.mine ? 'flex-row-reverse' : 'flex-row'"
    :data-msg-id="message.id"
  >
    <!-- Em grupo: avatar ao lado do ÚLTIMO balão da sequência (junto da cauda) -->
    <template v-if="!message.mine && message.inGroup">
      <Avatar
        v-if="message.tail"
        :name="message.senderName || ''"
        :src="message.avatarSrc || ''"
        :size="28"
        rounded-full
        class="flex-shrink-0 mb-0.5"
      />
      <span v-else class="flex-shrink-0 w-7" />
    </template>

    <div
      class="flex flex-col max-w-[78%] md:max-w-[66%] min-w-0"
      :class="message.mine ? 'items-end' : 'items-start'"
    >
      <span
        v-if="message.showSender || (message.mentionsMe && !message.mine)"
        class="flex items-center gap-1.5 px-3 mb-0.5 text-xs"
      >
        <span v-if="message.showSender" class="font-semibold text-n-slate-11">
          {{ message.senderName }}
        </span>
        <span
          v-if="message.mentionsMe && !message.mine"
          class="inline-flex items-center gap-0.5 px-1.5 rounded-full font-semibold bg-n-teal-9/15 text-n-teal-11"
        >
          <span class="i-lucide-at-sign size-3" />
          {{ t('INTERNAL_CHAT.BUBBLE.MENTIONED_YOU') }}
        </span>
      </span>
      <!-- Apagada -->
      <div
        v-if="message.deleted"
        class="flex items-center gap-1.5 px-3.5 py-2 text-sm italic border border-dashed rounded-[20px] text-n-slate-10 border-n-strong"
      >
        <span class="text-sm i-lucide-ban" />
        {{ t('INTERNAL_CHAT.DELETED') }}
      </div>

      <!-- Editar inline -->
      <div
        v-else-if="editing"
        class="flex flex-col gap-1.5 w-[280px] max-w-full"
      >
        <textarea
          ref="editRef"
          v-model="editDraft"
          rows="2"
          class="reset-base w-full h-auto !mb-0 px-3.5 py-2 text-[15px] !border !border-solid outline-none !outline-0 resize-none rounded-2xl !bg-n-solid-1 dark:!bg-n-solid-2 !border-n-strong text-n-slate-12 focus:!border-n-teal-9"
          @keydown.enter.exact.prevent="saveEdit"
          @keydown.esc.stop="cancelEdit"
        />
        <div class="flex justify-end gap-3 px-1 text-xs">
          <button type="button" class="text-n-slate-11" @click="cancelEdit">
            {{ t('INTERNAL_CHAT.CANCEL') }}
          </button>
          <button
            type="button"
            class="font-semibold text-n-teal-11 disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="!editDraft.trim()"
            @click="saveEdit"
          >
            {{ t('INTERNAL_CHAT.SAVE_EDIT') }}
          </button>
        </div>
      </div>

      <!-- Balão -->
      <div
        v-else
        class="relative min-w-0 break-words transition-shadow duration-300"
        :class="[
          jumbo
            ? 'px-1 text-4xl leading-tight'
            : 'px-3.5 py-[7px] text-[15px] leading-[1.35] rounded-[20px]',
          !jumbo &&
            (message.mine
              ? 'bg-n-teal-11 dark:bg-n-teal-4 text-white'
              : 'bg-n-slate-3 dark:bg-n-slate-4 text-n-slate-12'),
          !jumbo &&
            message.tail &&
            (message.mine ? 'rounded-br-md' : 'rounded-bl-md'),
          !jumbo && message.sharedConversation ? 'w-72 max-w-full' : '',
          !jumbo && message.mentionsMe && !message.mine
            ? 'ring-2 ring-n-teal-9/50'
            : '',
        ]"
        @contextmenu.prevent="openMenuFromEvent"
        @touchstart.passive="startLongPress"
        @touchend="cancelLongPress"
        @touchmove.passive="cancelLongPress"
      >
        <!-- Cauda do balão: só no último da sequência (estilo iMessage) -->
        <svg
          v-if="message.tail && !jumbo"
          viewBox="0 0 14 20"
          aria-hidden="true"
          class="absolute bottom-0 w-3.5 h-5 pointer-events-none"
          :class="
            message.mine
              ? '-right-[6px] text-n-teal-11 dark:text-n-teal-4'
              : '-left-[6px] -scale-x-100 text-n-slate-3 dark:text-n-slate-4'
          "
        >
          <path
            d="M0 0 H7 C7 9 9 15 14 20 C8 20.4 3.5 18.6 0 15.5 Z"
            fill="currentColor"
          />
        </svg>

        <!-- Gatilho ⌄ no canto: aparece no hover/foco (toque: long-press).
             O degradê repinta a cor do balão só no topo, para o botão não
             cobrir o texto de um balão curto. -->
        <div
          v-if="!message.deleted"
          class="absolute top-0 right-0 z-20 flex items-start justify-end w-12 h-9 max-h-full p-0.5 transition-opacity duration-200 opacity-0 rounded-tr-[20px] group-hover:opacity-100 focus-within:opacity-100"
          :class="
            jumbo
              ? ''
              : message.mine
                ? 'bg-gradient-to-l to-transparent from-55% from-n-teal-11 dark:from-n-teal-4'
                : 'bg-gradient-to-l to-transparent from-55% from-n-slate-3 dark:from-n-slate-4'
          "
        >
          <button
            ref="dropdownButtonRef"
            v-tooltip="t('INTERNAL_CHAT.MESSAGE_ACTIONS')"
            type="button"
            class="relative z-10 inline-flex items-center justify-center transition-colors rounded-full size-7"
            :class="
              jumbo
                ? 'bg-n-solid-1 shadow text-n-slate-11 text-base'
                : message.mine
                  ? 'text-white/85 hover:bg-white/15'
                  : 'text-n-slate-11 hover:bg-n-alpha-2'
            "
            :aria-label="t('INTERNAL_CHAT.MESSAGE_ACTIONS')"
            @click.stop="openMenuFromButton"
          >
            <span class="text-lg i-lucide-chevron-down" />
          </button>
        </div>

        <!-- Backdrop click-fora do picker de reação (o menu fecha sozinho) -->
        <div
          v-if="showReactionPicker"
          class="fixed inset-0 z-10"
          @click="closeAll"
          @contextmenu.prevent="closeAll"
        />

        <!-- Menu de ações — mesma lista com rótulo do chat normal -->
        <ContextMenu
          v-if="showMenu"
          :x="menuPosition.x"
          :y="menuPosition.y"
          @close="showMenu = false"
        >
          <div class="menu-container">
            <MenuItem
              :option="{
                icon: 'arrow-reply',
                label: t('INTERNAL_CHAT.BUBBLE.REPLY'),
              }"
              variant="icon"
              @click.stop="onReply"
            />
            <MenuItem
              v-if="
                message.inGroup && !message.mine && message.userId && persisted
              "
              :option="{
                icon: 'i-lucide-message-circle-reply',
                label: t('INTERNAL_CHAT.BUBBLE.REPLY_PRIVATELY'),
              }"
              variant="icon"
              @click.stop="onReplyPrivately"
            />
            <MenuItem
              :option="{
                icon: 'i-lucide-smile-plus',
                label: t('INTERNAL_CHAT.REACT'),
              }"
              variant="icon"
              @click.stop="toggleReactionPicker"
            />
            <MenuItem
              v-if="persisted"
              :option="{
                icon: 'i-lucide-forward',
                label: t('INTERNAL_CHAT.BUBBLE.FORWARD'),
              }"
              variant="icon"
              @click.stop="onForward"
            />
            <MenuItem
              v-if="persisted && message.canStar"
              :option="{
                icon: message.starred ? 'i-lucide-star-off' : 'i-lucide-star',
                label: message.starred
                  ? t('INTERNAL_CHAT.BUBBLE.UNSTAR')
                  : t('INTERNAL_CHAT.BUBBLE.STAR'),
              }"
              variant="icon"
              @click.stop="onStar"
            />
            <MenuItem
              v-if="message.content"
              :option="{
                icon: 'clipboard',
                label: t('INTERNAL_CHAT.BUBBLE.COPY'),
              }"
              variant="icon"
              @click.stop="copyContent"
            />
            <MenuItem
              v-if="message.mine && message.inGroup && persisted"
              :option="{
                icon: 'i-lucide-info',
                label: t('INTERNAL_CHAT.BUBBLE.INFO'),
              }"
              variant="icon"
              @click.stop="onInfo"
            />
            <hr v-if="message.mine" />
            <MenuItem
              v-if="message.mine"
              :option="{
                icon: 'i-lucide-pencil',
                label: t('INTERNAL_CHAT.BUBBLE.EDIT'),
              }"
              variant="icon"
              @click.stop="startEdit"
            />
            <MenuItem
              v-if="message.mine"
              :option="{
                icon: 'delete',
                label: t('INTERNAL_CHAT.BUBBLE.DELETE'),
              }"
              variant="icon"
              @click.stop="askDelete"
            />
          </div>
        </ContextMenu>

        <!-- Picker de reação -->
        <div
          v-if="showReactionPicker"
          class="absolute z-20 flex gap-0.5 p-1 border rounded-full shadow-xl bottom-full mb-2 bg-n-solid-1 border-n-weak"
          :class="message.mine ? 'right-0' : 'left-0'"
        >
          <button
            v-for="e in reactionEmojis"
            :key="e"
            type="button"
            class="inline-flex items-center justify-center text-xl leading-none transition-colors rounded-full size-9 hover:bg-n-alpha-2"
            @click="react(e)"
          >
            {{ e }}
          </button>
        </div>

        <!-- Confirmação de apagar -->
        <div
          v-if="confirmDelete"
          class="absolute z-20 flex items-center gap-3 px-3 py-1.5 text-xs border shadow-lg rounded-full -top-10 bg-n-solid-1 border-n-weak"
          :class="message.mine ? 'right-1' : 'left-1'"
        >
          <span class="whitespace-nowrap text-n-slate-12">
            {{ t('INTERNAL_CHAT.DELETE_Q') }}
          </span>
          <button
            type="button"
            class="text-n-slate-11"
            @click="confirmDelete = false"
          >
            {{ t('INTERNAL_CHAT.CANCEL') }}
          </button>
          <button
            type="button"
            class="font-semibold text-n-ruby-11"
            @click="doDelete"
          >
            {{ t('INTERNAL_CHAT.DELETE') }}
          </button>
        </div>

        <!-- Selo de mensagem encaminhada (como no WhatsApp) -->
        <span
          v-if="forwarded"
          v-tooltip="t('INTERNAL_CHAT.BUBBLE.FORWARDED_HINT')"
          class="flex items-center gap-1 mb-0.5 text-xs italic opacity-80"
          :class="jumbo ? 'not-italic text-n-slate-11' : ''"
        >
          <span class="flex-shrink-0 i-lucide-forward size-3.5" />
          {{ t('INTERNAL_CHAT.BUBBLE.FORWARDED') }}
        </span>

        <!-- Citação da mensagem respondida -->
        <button
          v-if="message.replyTo"
          type="button"
          class="block w-full px-2.5 py-1.5 mt-0.5 mb-1.5 text-left border-l-[3px] border-solid rounded-lg"
          :class="
            message.mine
              ? 'border-white/70 bg-white/15'
              : 'border-n-teal-9 bg-n-alpha-2'
          "
          @click="emit('scrollTo', message.replyTo.id)"
        >
          <span class="block text-xs font-semibold">
            {{ message.replyTo.user_name }}
          </span>
          <span class="block text-xs truncate opacity-80">
            {{ message.replyTo.content || t('INTERNAL_CHAT.DELETED') }}
          </span>
        </button>

        <!-- Texto (links, #123 e @menções clicáveis) + "editado" -->
        <p
          v-if="message.content"
          class="mb-0 whitespace-pre-wrap"
          :class="
            jumbo ? 'text-4xl leading-tight' : 'text-[15px] leading-[1.35]'
          "
        >
          <template v-for="(part, i) in contentParts" :key="i">
            <a
              v-if="part.t === 'link'"
              :href="part.v"
              target="_blank"
              rel="noopener noreferrer"
              class="underline break-all underline-offset-2"
              :class="message.mine ? '' : 'text-n-teal-11'"
              >{{ part.v }}</a
            ><a
              v-else-if="part.t === 'conv'"
              v-tooltip="t('INTERNAL_CHAT.BUBBLE.OPEN_CONVERSATION')"
              :href="conversationPath(part.id)"
              class="font-semibold underline underline-offset-2"
              :class="message.mine ? '' : 'text-n-teal-11'"
              @click.prevent="router.push(conversationPath(part.id))"
              >{{ part.v }}</a
            ><span
              v-else-if="part.t === 'mention'"
              class="px-1 font-semibold rounded-md"
              :class="
                message.mine ? 'bg-white/20' : 'bg-n-teal-9/15 text-n-teal-11'
              "
              >{{ part.v }}</span
            ><template v-else>{{ part.v }}</template>
          </template>
          <span
            v-if="message.edited"
            class="ml-1 text-[11px] align-baseline opacity-70"
            >{{ t('INTERNAL_CHAT.EDITED') }}</span
          >
        </p>

        <!-- Prévia do link: título, descrição, imagem e domínio -->
        <a
          v-if="linkPreview"
          :href="linkPreview.url"
          target="_blank"
          rel="noopener noreferrer"
          class="block w-72 max-w-full mt-2 mb-1 overflow-hidden transition-colors border rounded-2xl"
          :class="
            message.mine
              ? 'bg-white/10 border-white/25 hover:bg-white/15 text-white'
              : 'bg-n-solid-1 dark:bg-n-solid-2 border-n-weak hover:bg-n-alpha-1 text-n-slate-12'
          "
        >
          <img
            v-if="linkPreview.image && !hidePreviewImage"
            :src="linkPreview.image"
            alt=""
            loading="lazy"
            referrerpolicy="no-referrer"
            class="object-cover w-full h-36 bg-n-alpha-2"
            @error="hidePreviewImage = true"
          />
          <span class="block px-3 py-2">
            <span
              class="flex items-center gap-1 text-[11px] font-semibold uppercase tracking-wider opacity-75"
            >
              <span class="flex-shrink-0 i-lucide-globe size-3" />
              <span class="truncate">
                {{ linkPreview.site_name || linkPreview.domain }}
              </span>
            </span>
            <span
              class="block mt-0.5 text-sm font-semibold leading-snug line-clamp-2"
            >
              {{ linkPreview.title }}
            </span>
            <span
              v-if="linkPreview.description"
              class="block mt-0.5 text-xs leading-snug line-clamp-2 opacity-80"
            >
              {{ linkPreview.description }}
            </span>
          </span>
        </a>

        <!-- Conversa de cliente compartilhada: cartão que abre a conversa -->
        <router-link
          v-if="message.sharedConversation"
          :to="conversationPath(message.sharedConversation.display_id)"
          class="block p-3 mt-2 mb-1 transition-colors border rounded-2xl"
          :class="
            message.mine
              ? 'bg-white/10 border-white/25 hover:bg-white/15 text-white'
              : 'bg-n-solid-1 dark:bg-n-solid-2 border-n-weak hover:bg-n-alpha-1 text-n-slate-12'
          "
        >
          <span
            class="flex items-center gap-1.5 text-[11px] font-semibold uppercase tracking-wider opacity-80"
          >
            <span class="i-lucide-message-square-share size-3.5" />
            {{ t('INTERNAL_CHAT.SHARED.TITLE') }}
          </span>
          <span class="flex items-center gap-2 mt-1.5">
            <span class="flex-1 min-w-0 text-[15px] font-semibold truncate">
              {{
                message.sharedConversation.contact_name ||
                t('INTERNAL_CHAT.SHARED.NO_NAME')
              }}
            </span>
            <span
              v-if="sharedStatus"
              class="flex-shrink-0 px-2 py-0.5 text-[11px] font-semibold rounded-full"
              :class="
                message.mine ? 'bg-white/20' : 'bg-n-teal-9/15 text-n-teal-11'
              "
            >
              {{ sharedStatus }}
            </span>
          </span>
          <span class="block text-xs truncate opacity-80">
            #{{ message.sharedConversation.display_id }} ·
            {{ message.sharedConversation.inbox_name }}
          </span>
          <span
            class="flex items-center justify-between pt-2 mt-2 text-xs font-semibold border-t"
            :class="
              message.mine ? 'border-white/20' : 'border-n-weak text-n-teal-11'
            "
          >
            {{ t('INTERNAL_CHAT.SHARED.OPEN_FULL') }}
            <span class="i-lucide-arrow-right size-4" />
          </span>
        </router-link>

        <!-- Anexos -->
        <div
          v-if="message.attachments.length"
          class="flex flex-col gap-1.5 py-0.5"
          :class="{ 'mt-1.5': message.content }"
        >
          <template v-for="att in message.attachments" :key="att.id">
            <a
              v-if="isImage(att)"
              :href="att.url"
              target="_blank"
              rel="noopener noreferrer"
              class="block -mx-2"
            >
              <img
                :src="att.url"
                :alt="att.filename"
                class="max-w-[240px] max-h-[240px] rounded-2xl object-cover"
              />
            </a>
            <AudioPlayer
              v-else-if="isAudio(att)"
              :src="att.url"
              :heard-key="message.mine ? null : att.id"
            />
            <a
              v-else
              :href="att.url"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-2 px-2.5 py-2 text-sm rounded-xl"
              :class="message.mine ? 'bg-white/15' : 'bg-n-alpha-2'"
            >
              <span class="flex-shrink-0 i-lucide-file-text size-5" />
              <span class="flex-1 min-w-0 truncate" :title="att.filename">
                {{ att.filename }}
              </span>
              <span class="flex-shrink-0 i-lucide-download size-4 opacity-80" />
            </a>
          </template>
        </div>
      </div>

      <!-- Chips de reação: encostam no balão -->
      <div
        v-if="!message.deleted && reactionEntries.length"
        class="relative z-10 flex flex-wrap gap-1 -mt-1.5 px-2"
        :class="message.mine ? 'justify-end' : 'justify-start'"
      >
        <button
          v-for="[emoji, users] in reactionEntries"
          :key="emoji"
          type="button"
          class="inline-flex items-center gap-1 px-1.5 h-6 text-xs border border-solid rounded-full shadow-sm transition-colors bg-n-solid-1"
          :class="
            iReacted(emoji)
              ? 'border-n-teal-9 text-n-slate-12'
              : 'border-n-weak text-n-slate-11 hover:bg-n-solid-2'
          "
          @click="react(emoji)"
        >
          <span>{{ emoji }}</span>
          <span class="font-semibold">{{ users.length }}</span>
        </button>
      </div>

      <!-- Situação do envio, por extenso, embaixo do balão (como no iPhone):
           "Enviando…", "Não enviada · tentar de novo", "Entregue" ou "Lida". -->
      <span
        v-if="message.delivery"
        class="flex items-center gap-1 px-2 mt-1 text-[11px] font-medium leading-none"
      >
        <span
          v-if="message.delivery === 'progress'"
          class="inline-flex items-center gap-1 text-n-slate-10"
        >
          <span class="i-lucide-clock size-3" />
          {{
            message.uploadProgress != null
              ? t('INTERNAL_CHAT.AUDIO.SENDING_PROGRESS', {
                  progress: message.uploadProgress,
                })
              : t('INTERNAL_CHAT.SENDING')
          }}
        </span>
        <button
          v-else-if="message.delivery === 'failed'"
          type="button"
          class="inline-flex items-center gap-1 font-semibold text-n-ruby-11 hover:underline"
          @click="emit('retry', message)"
        >
          <span class="i-lucide-circle-alert size-3.5" />
          {{ t('INTERNAL_CHAT.SEND_FAILED_RETRY') }}
        </button>
        <span
          v-else-if="message.delivery === 'read'"
          v-tooltip="t('INTERNAL_CHAT.BUBBLE.READ_HINT')"
          class="inline-flex items-center gap-1 text-n-teal-11"
        >
          <span class="i-lucide-check-check size-3.5" />
          {{ t('INTERNAL_CHAT.BUBBLE.READ_LABEL') }}
        </span>
        <span
          v-else-if="message.delivery === 'sent'"
          v-tooltip="t('INTERNAL_CHAT.BUBBLE.DELIVERED_HINT')"
          class="inline-flex items-center gap-1 text-n-slate-10"
        >
          <span class="i-lucide-check size-3.5" />
          {{ t('INTERNAL_CHAT.BUBBLE.DELIVERED') }}
        </span>
      </span>
    </div>

    <!-- Estrela pequena: mensagem favorita (só para você) -->
    <span
      v-if="message.starred && !message.deleted"
      v-tooltip="t('INTERNAL_CHAT.BUBBLE.STARRED_HINT')"
      class="flex-shrink-0 self-center i-ph-star-fill size-3.5 text-n-amber-9"
      :aria-label="t('INTERNAL_CHAT.BUBBLE.STARRED_HINT')"
      role="img"
    />

    <!-- Ao lado do balão, no hover/foco: Responder e Reagir à vista (antes só
         pela setinha escondida dentro do balão) + o horário -->
    <div
      v-if="!editing"
      class="flex items-center self-center flex-shrink-0 gap-0.5 transition-opacity duration-200 opacity-0 group-hover:opacity-100 focus-within:opacity-100"
      :class="message.mine ? 'flex-row-reverse' : 'flex-row'"
    >
      <template v-if="!message.deleted">
        <button
          v-tooltip="t('INTERNAL_CHAT.BUBBLE.REPLY')"
          type="button"
          class="inline-flex items-center justify-center flex-shrink-0 transition-colors rounded-full size-7 border border-solid border-n-teal-9 hover:border-n-teal-10 bg-n-solid-1 dark:bg-n-solid-2 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="t('INTERNAL_CHAT.BUBBLE.REPLY')"
          @click="onReply"
        >
          <span class="flex-shrink-0 i-lucide-reply size-4" />
        </button>
        <button
          v-tooltip="t('INTERNAL_CHAT.REACT')"
          type="button"
          class="inline-flex items-center justify-center flex-shrink-0 transition-colors rounded-full size-7 border border-solid border-n-teal-9 hover:border-n-teal-10 bg-n-solid-1 dark:bg-n-solid-2 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="t('INTERNAL_CHAT.REACT')"
          @click.stop="toggleReactionPicker"
        >
          <span class="flex-shrink-0 i-lucide-smile-plus size-4" />
        </button>
      </template>
      <span
        class="px-1 text-[11px] tabular-nums text-n-slate-10"
        aria-hidden="true"
      >
        {{ message.time }}
      </span>
    </div>
  </div>
</template>

<style scoped lang="scss">
/* Mesma casca do menu de mensagem do chat normal (MessageContextMenu.vue). */
.menu-container {
  @apply p-1 rounded-md shadow-xl bg-n-background;

  hr {
    @apply m-1 border-b border-solid border-n-strong;
  }
}
</style>
