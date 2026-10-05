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
const iReacted = emoji =>
  (props.message.reactions?.[emoji] || [])
    .map(Number)
    .includes(Number(props.currentUserId));
</script>

<template>
  <div
    class="flex items-end gap-2 group"
    :class="message.mine ? 'flex-row-reverse' : 'flex-row'"
    :data-msg-id="message.id"
  >
    <!-- Em grupo: avatar no 1º balão da sequência, espaço vazio nos seguintes -->
    <template v-if="!message.mine && message.inGroup">
      <Avatar
        v-if="message.showSender"
        :name="message.senderName || ''"
        :src="message.avatarSrc || ''"
        :size="28"
        rounded-full
        class="self-start mt-5"
      />
      <span v-else class="flex-shrink-0 w-7" />
    </template>

    <div
      class="flex flex-col max-w-[78%] md:max-w-[68%] min-w-0"
      :class="message.mine ? 'items-end' : 'items-start'"
    >
      <span
        v-if="message.showSender"
        class="px-1 mb-0.5 text-xs font-semibold text-n-slate-11"
      >
        {{ message.senderName }}
      </span>
      <!-- Apagada -->
      <div
        v-if="message.deleted"
        class="flex items-center gap-1.5 px-3.5 py-2 text-sm italic rounded-2xl text-n-slate-10 bg-n-alpha-1"
      >
        <span class="text-sm i-lucide-ban" />
        {{ t('INTERNAL_CHAT.DELETED') }}
      </div>

      <!-- Editar inline -->
      <div
        v-else-if="editing"
        class="flex flex-col gap-1.5 w-[260px] max-w-full"
      >
        <textarea
          ref="editRef"
          v-model="editDraft"
          rows="2"
          class="reset-base w-full px-3 py-2 text-sm border outline-none resize-none rounded-xl bg-n-alpha-1 border-n-weak text-n-slate-12 focus:border-n-brand"
          @keydown.enter.exact.prevent="saveEdit"
          @keydown.esc="cancelEdit"
        />
        <div class="flex gap-3 px-1 text-xs">
          <button
            type="button"
            class="font-medium text-n-brand"
            @click="saveEdit"
          >
            {{ t('INTERNAL_CHAT.SAVE_EDIT') }}
          </button>
          <button type="button" class="text-n-slate-10" @click="cancelEdit">
            {{ t('INTERNAL_CHAT.CANCEL') }}
          </button>
        </div>
      </div>

      <!-- Balão normal -->
      <div
        v-else
        class="relative px-3.5 py-2 text-sm shadow-sm rounded-2xl break-words min-w-0"
        :class="
          message.mine
            ? 'bubble-out rounded-br-md'
            : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-md'
        "
        @contextmenu.prevent="openMenuFromEvent"
        @touchstart.passive="startLongPress"
        @touchend="cancelLongPress"
        @touchmove.passive="cancelLongPress"
      >
        <!-- Gatilho ⌄ no canto do balão, no mesmo formato do chat normal:
             aparece no hover/foco, e o toque continua no long-press.
             A faixa repinta o fundo do balão para o botão não cair em cima do
             texto, mas em DEGRADÊ e só no topo: num balão curto (um emoji, um
             "ok") a faixa sólida de altura inteira engolia a mensagem e o
             horário no hover. Assim o ⌄ tem fundo onde precisa e o conteúdo
             continua legível por baixo.
             No balão recebido o tint alpha é recomposto por dentro — duas
             camadas de 12% empilhadas ficariam mais escuras que o balão, então
             o degradê é aplicado nas duas camadas.
             Só o ⌄ mora aqui (responder é o 1º item do menu): com dois botões a
             faixa cobria metade de um balão curto. -->
        <div
          v-if="!message.deleted"
          class="absolute top-0 right-0 z-20 flex items-start justify-end w-12 h-10 max-h-full p-1 transition-opacity duration-200 opacity-0 rounded-tr-2xl group-hover:opacity-100 focus-within:opacity-100"
          :class="
            message.mine
              ? 'bubble-out-fade'
              : 'bg-gradient-to-l to-transparent from-n-background from-55%'
          "
        >
          <span
            v-if="!message.mine"
            class="absolute inset-0 rounded-tr-2xl bg-gradient-to-l to-transparent from-n-alpha-2 from-55%"
          />
          <button
            ref="dropdownButtonRef"
            v-tooltip="t('INTERNAL_CHAT.MESSAGE_ACTIONS')"
            type="button"
            class="relative z-10 inline-flex items-center justify-center w-8 h-8 transition-colors rounded-md"
            :class="
              message.mine
                ? 'bubble-out-meta hover:bg-n-black/10 dark:hover:bg-white/10'
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
              :option="{
                icon: 'i-lucide-smile-plus',
                label: t('INTERNAL_CHAT.REACT'),
              }"
              variant="icon"
              @click.stop="toggleReactionPicker"
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
          class="absolute z-20 flex gap-1 px-2 py-1 border rounded-full shadow-md bottom-full mb-1.5 bg-n-solid-1 border-n-weak"
          :class="message.mine ? 'right-0' : 'left-0'"
        >
          <button
            v-for="e in reactionEmojis"
            :key="e"
            type="button"
            class="text-base leading-none rounded-md hover:bg-n-alpha-2 transition-colors"
            @click="react(e)"
          >
            {{ e }}
          </button>
        </div>

        <!-- Confirmação de apagar -->
        <div
          v-if="confirmDelete"
          class="absolute z-20 flex items-center gap-2 px-2 py-1 text-xs border rounded-lg shadow -top-9 bg-n-solid-1 border-n-weak"
          :class="message.mine ? 'right-1' : 'left-1'"
        >
          <span class="whitespace-nowrap text-n-slate-11">
            {{ t('INTERNAL_CHAT.DELETE_Q') }}
          </span>
          <button
            type="button"
            class="font-medium text-n-ruby-11"
            @click="doDelete"
          >
            {{ t('INTERNAL_CHAT.DELETE') }}
          </button>
          <button
            type="button"
            class="text-n-slate-10"
            @click="confirmDelete = false"
          >
            {{ t('INTERNAL_CHAT.CANCEL') }}
          </button>
        </div>

        <!-- Citação da mensagem respondida -->
        <button
          v-if="message.replyTo"
          type="button"
          class="block w-full pl-2 mb-1 text-left border-l-2 rounded-sm opacity-90 border-n-brand"
          @click="emit('scrollTo', message.replyTo.id)"
        >
          <span class="block text-[11px] font-semibold">
            {{ message.replyTo.user_name }}
          </span>
          <span class="block text-[11px] opacity-75 truncate">
            {{ message.replyTo.content || t('INTERNAL_CHAT.DELETED') }}
          </span>
        </button>

        <!-- Conversa de cliente compartilhada: card que abre a conversa -->
        <router-link
          v-if="message.sharedConversation"
          :to="conversationPath(message.sharedConversation.display_id)"
          class="flex items-center gap-2.5 p-2 mb-1.5 border rounded-xl border-n-weak bg-n-background/60 hover:bg-n-alpha-1 text-n-slate-12"
        >
          <span
            class="flex-shrink-0 text-lg i-lucide-message-square-share text-n-brand"
          />
          <span class="flex-1 min-w-0">
            <span class="block text-sm font-semibold truncate">
              #{{ message.sharedConversation.display_id }} –
              {{
                message.sharedConversation.contact_name ||
                t('INTERNAL_CHAT.SHARED.NO_NAME')
              }}
            </span>
            <span class="block text-xs truncate text-n-slate-11">
              {{ message.sharedConversation.inbox_name }}
            </span>
          </span>
          <span class="flex-shrink-0 text-xs font-medium text-n-brand">
            {{ t('INTERNAL_CHAT.SHARED.OPEN') }}
          </span>
        </router-link>

        <!-- Texto (links, #123 e @menções clicáveis) + "editado" -->
        <p v-if="message.content" class="leading-relaxed whitespace-pre-wrap">
          <template v-for="(part, i) in contentParts" :key="i">
            <a
              v-if="part.t === 'link'"
              :href="part.v"
              target="_blank"
              rel="noopener noreferrer"
              class="underline break-all"
              >{{ part.v }}</a
            ><a
              v-else-if="part.t === 'conv'"
              v-tooltip="t('INTERNAL_CHAT.BUBBLE.OPEN_CONVERSATION')"
              :href="conversationPath(part.id)"
              class="font-medium underline"
              @click.prevent="router.push(conversationPath(part.id))"
              >{{ part.v }}</a
            ><span
              v-else-if="part.t === 'mention'"
              class="px-0.5 font-semibold rounded bg-n-brand/15"
              >{{ part.v }}</span
            ><template v-else>{{ part.v }}</template>
          </template>
          <span
            v-if="message.edited"
            class="text-[10px] opacity-60 ml-1 align-baseline"
            >{{ t('INTERNAL_CHAT.EDITED') }}</span
          >
        </p>

        <!-- Anexos -->
        <div
          v-if="message.attachments.length"
          class="flex flex-col gap-1.5"
          :class="{ 'mt-1.5': message.content }"
        >
          <template v-for="att in message.attachments" :key="att.id">
            <a
              v-if="isImage(att)"
              :href="att.url"
              target="_blank"
              rel="noopener noreferrer"
              class="block"
            >
              <img
                :src="att.url"
                :alt="att.filename"
                class="max-w-[220px] max-h-[220px] rounded-lg object-cover"
              />
            </a>
            <AudioPlayer v-else-if="isAudio(att)" :src="att.url" />
            <a
              v-else
              :href="att.url"
              target="_blank"
              rel="noopener noreferrer"
              class="flex items-center gap-1.5 text-xs underline opacity-90"
            >
              <span class="i-lucide-paperclip" />
              {{ att.filename }}
            </a>
          </template>
        </div>

        <!-- Hora + status -->
        <span
          class="flex items-center justify-end gap-1 mt-1 text-[10px] leading-none"
          :class="message.mine ? 'bubble-out-meta' : 'text-n-slate-10'"
        >
          {{ message.time }}
          <span
            v-if="message.delivery === 'progress'"
            v-tooltip="t('INTERNAL_CHAT.SENDING')"
            class="inline-flex items-center gap-1"
          >
            <span class="text-sm i-lucide-clock" />
            <span v-if="message.uploadProgress != null">
              {{
                t('INTERNAL_CHAT.AUDIO.SENDING_PROGRESS', {
                  progress: message.uploadProgress,
                })
              }}
            </span>
          </span>
          <button
            v-else-if="message.delivery === 'failed'"
            type="button"
            class="font-medium text-n-ruby-11 hover:underline"
            @click="emit('retry', message)"
          >
            {{ t('INTERNAL_CHAT.SEND_FAILED_RETRY') }}
          </button>
          <span
            v-else-if="message.delivery === 'read'"
            v-tooltip="t('INTERNAL_CHAT.BUBBLE.READ')"
            class="text-sm i-lucide-check-check text-n-blue-11"
          />
          <span
            v-else-if="message.delivery === 'sent'"
            v-tooltip="t('INTERNAL_CHAT.BUBBLE.SENT')"
            class="text-sm i-lucide-check"
          />
        </span>
      </div>

      <!-- Chips de reação -->
      <div
        v-if="!message.deleted && reactionEntries.length"
        class="flex flex-wrap gap-1 mt-1"
        :class="message.mine ? 'justify-end' : 'justify-start'"
      >
        <button
          v-for="[emoji, users] in reactionEntries"
          :key="emoji"
          type="button"
          class="inline-flex items-center gap-1 px-1.5 h-5 text-xs border rounded-full transition-colors"
          :class="
            iReacted(emoji)
              ? 'border-n-brand bg-n-brand/10 text-n-slate-12'
              : 'border-n-weak text-n-slate-11 hover:bg-n-alpha-1'
          "
          @click="react(emoji)"
        >
          <span>{{ emoji }}</span>
          <span>{{ users.length }}</span>
        </button>
      </div>
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

/* Balão de saída: a mesma paleta do balão do chat normal (_wa-skin.scss), em
   vez do verde-brand. O brand é claro e saturado demais — sobre ele o ⌄, o
   horário e os ticks ficavam lavados, que foi a queixa. Estas variáveis já
   governam o balão da conversa com o cliente, então os dois chats passam a
   combinar, e cada tema traz o par fundo/texto com contraste próprio. */
.bubble-out {
  background-color: var(--wa-bubble-out);
  color: var(--wa-text-primary);
}

/* Texto secundário DENTRO do balão de saída: horário, ticks e o ⌄. */
.bubble-out-meta {
  color: var(--wa-text-secondary);
}

/* Fundo do gatilho ⌄ — repinta o balão em degradê (ver comentário no template). */
.bubble-out-fade {
  background-image: linear-gradient(
    to left,
    var(--wa-bubble-out) 55%,
    transparent
  );
}

.dark .bubble-out {
  background-color: var(--wa-bubble-out-dark);
  color: var(--wa-text-primary-dark);
}

.dark .bubble-out-meta {
  color: var(--wa-text-secondary-dark);
}

.dark .bubble-out-fade {
  background-image: linear-gradient(
    to left,
    var(--wa-bubble-out-dark) 55%,
    transparent
  );
}
</style>
