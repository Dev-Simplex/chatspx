<script setup>
import {
  ref,
  computed,
  watch,
  nextTick,
  onMounted,
  defineAsyncComponent,
} from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import {
  checkFileSizeLimit,
  HARD_MAXIMUM_FILE_UPLOAD_SIZE,
} from 'shared/helpers/FileHelper';
import AudioRecorder from './AudioRecorder.vue';
import CannedResponse from 'dashboard/components/widgets/conversation/CannedResponse.vue';

const props = defineProps({
  // Mensagem sendo respondida: { id, name, preview } (ou null).
  replyingTo: { type: Object, default: null },
  // Rascunho salvo desta conversa (o composer remonta a cada troca de conversa).
  initialDraft: { type: String, default: '' },
  // Quem pode ser @mencionado: [{ id, name, avatar_url }] (vazio = sem menção).
  mentionCandidates: { type: Array, default: () => [] },
});

const emit = defineEmits(['send', 'cancelReply', 'draftChange']);
const { t } = useI18n();

const EmojiInput = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiInput.vue')
);

const draft = ref(props.initialDraft);
const showEmoji = ref(false);
const textareaRef = ref(null);
const fileInputRef = ref(null);
const attachedFiles = ref([]);
const recording = ref(false);

const autoResize = () => {
  const el = textareaRef.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, 112)}px`;
};

// Rascunho por conversa: cada mudança sobe para o pai guardar.
watch(draft, value => emit('draftChange', value));

// Abriu a conversa → já dá para digitar.
onMounted(() =>
  nextTick(() => {
    autoResize();
    textareaRef.value?.focus();
  })
);

// ── @menção ────────────────────────────────────────────────────────────────
// Digitou "@" (no começo ou depois de espaço) → lista dos membros; escolher
// insere "@Nome " e o id vai junto no envio, o que avisa a pessoa.
const mentionQuery = ref(null);
const mentionIndex = ref(0);
const updateMentionQuery = () => {
  const el = textareaRef.value;
  if (!el || !props.mentionCandidates.length) {
    mentionQuery.value = null;
    return;
  }
  const before = draft.value.slice(0, el.selectionStart);
  const match = before.match(/(?:^|\s)@([^\s@]*)$/);
  mentionQuery.value = match ? match[1].toLowerCase() : null;
  mentionIndex.value = 0;
};
const mentionOptions = computed(() => {
  if (mentionQuery.value === null) return [];
  return props.mentionCandidates
    .filter(m => (m.name || '').toLowerCase().includes(mentionQuery.value))
    .slice(0, 6);
});
const pickMention = member => {
  const el = textareaRef.value;
  const caret = el.selectionStart;
  const before = draft.value
    .slice(0, caret)
    .replace(/@[^\s@]*$/, `@${member.name} `);
  draft.value = before + draft.value.slice(caret);
  mentionQuery.value = null;
  nextTick(() => {
    el.focus();
    el.setSelectionRange(before.length, before.length);
    autoResize();
  });
};
const moveMention = step => {
  const total = mentionOptions.value.length;
  mentionIndex.value = (mentionIndex.value + step + total) % total;
};
// Setas/Tab navegam na lista de menção só enquanto ela está aberta.
const onMentionKey = (event, action) => {
  if (!mentionOptions.value.length) return;
  event.preventDefault();
  action();
};
const mentionedIdsIn = text =>
  props.mentionCandidates
    .filter(m => m.name && text.includes(`@${m.name}`))
    .map(m => m.id);

const onInput = () => {
  autoResize();
  updateMentionQuery();
};

// ── Respostas prontas (picker "/") ────────────────────────────────────────────
// Mesmo componente do compositor de conversas; já respeita a visibilidade
// (pública/privada/de-time) via índice escopado. Aparece quando a mensagem começa
// com "/"; o texto após a barra vira o filtro de busca.
const showCanned = computed(
  () => !recording.value && draft.value.startsWith('/')
);
const cannedSearchKey = computed(() =>
  showCanned.value ? draft.value.slice(1) : ''
);

// O conteúdo da resposta pronta é rich text (HTML); no textarea entra como texto puro.
const stripHtml = html => {
  const tmp = document.createElement('div');
  tmp.innerHTML = html || '';
  return (tmp.textContent || tmp.innerText || '').trim();
};

const onCannedSelect = content => {
  draft.value = stripHtml(content);
  nextTick(() => {
    textareaRef.value?.focus();
    autoResize();
  });
};

const toggleEmoji = () => {
  showEmoji.value = !showEmoji.value;
};

const onEmojiSelect = emoji => {
  draft.value += emoji;
  showEmoji.value = false;
  nextTick(() => {
    textareaRef.value?.focus();
    autoResize();
  });
};

// ── Anexos ──────────────────────────────────────────────────────────────────
const onPickFile = () => fileInputRef.value?.click();
const onFilesSelected = event => {
  Array.from(event.target.files || []).forEach(file => {
    // Rejeita acima do teto rígido com mensagem clara (senão o backend falha o
    // envio inteiro). HARD_MAXIMUM_FILE_UPLOAD_SIZE é em MB.
    if (checkFileSizeLimit(file, HARD_MAXIMUM_FILE_UPLOAD_SIZE)) {
      attachedFiles.value.push(file);
    } else {
      useAlert(
        t('INTERNAL_CHAT.ATTACHMENT_TOO_LARGE', {
          name: file.name,
          size: HARD_MAXIMUM_FILE_UPLOAD_SIZE,
        })
      );
    }
  });
  event.target.value = '';
};
const removeFile = index => attachedFiles.value.splice(index, 1);

// ── Áudio ───────────────────────────────────────────────────────────────────
// Grava, deixa ouvir e envia so o audio; o texto digitado continua no campo.
const startRecording = () => {
  showEmoji.value = false;
  recording.value = true;
};
const onAudioSend = file => {
  recording.value = false;
  emit('send', {
    content: '',
    attachments: [file],
    replyToId: props.replyingTo?.id || null,
  });
};

const canSend = computed(
  () => Boolean(draft.value.trim()) || attachedFiles.value.length > 0
);

const send = () => {
  const content = draft.value.trim();
  if (!content && !attachedFiles.value.length) return;
  emit('send', {
    content,
    attachments: [...attachedFiles.value],
    replyToId: props.replyingTo?.id || null,
    mentionedUserIds: mentionedIdsIn(content),
  });
  mentionQuery.value = null;
  draft.value = '';
  attachedFiles.value = [];
  showEmoji.value = false;
  nextTick(autoResize);
};

// Enter envia — a menos que o picker esteja REALMENTE aberto (com resultados), aí o
// Enter escolhe a resposta. Sem match (nenhuma .mention--box), envia normalmente —
// assim uma mensagem que começa com "/" e não é atalho ainda pode ser enviada.
const onEnter = () => {
  if (mentionOptions.value.length) {
    pickMention(mentionOptions.value[mentionIndex.value]);
    return;
  }
  if (showCanned.value && document.querySelector('.mention--box')) return;
  send();
};
</script>

<template>
  <div class="relative px-3 pt-2 pb-2.5 md:px-5 flex-shrink-0 bg-n-background">
    <!-- @menção: lista acima do campo enquanto digita "@nome" -->
    <div
      v-if="mentionOptions.length"
      class="absolute z-30 p-1 mb-1 overflow-hidden border shadow-xl left-20 md:left-24 bottom-full w-72 rounded-2xl bg-n-solid-1 border-n-weak"
    >
      <p class="mb-0 px-3 pt-1 pb-1.5 text-[11px] text-n-slate-10">
        {{ t('INTERNAL_CHAT.COMPOSER.MENTION_HINT') }}
      </p>
      <button
        v-for="(member, i) in mentionOptions"
        :key="member.id"
        type="button"
        class="flex items-center w-full gap-2.5 px-2.5 py-1.5 text-sm text-left rounded-xl text-n-slate-12"
        :class="i === mentionIndex ? 'bg-n-alpha-2' : 'hover:bg-n-alpha-1'"
        @mousedown.prevent="pickMention(member)"
      >
        <Avatar
          :name="member.name || ''"
          :src="member.avatar_url || ''"
          :size="24"
          rounded-full
        />
        <span class="truncate">{{ member.name }}</span>
      </button>
    </div>

    <!-- Respostas prontas: aparece acima do compositor ao começar com "/" -->
    <CannedResponse
      v-if="showCanned"
      :search-key="cannedSearchKey"
      @replace="onCannedSelect"
    />

    <!-- Barra "respondendo a X" -->
    <div
      v-if="replyingTo"
      class="flex items-center gap-2 mb-2 px-3 py-1.5 bg-n-alpha-1 border-l-[3px] border-n-teal-9 rounded-xl"
    >
      <span class="flex-shrink-0 i-lucide-reply text-n-slate-10" />
      <span class="flex-1 min-w-0">
        <span class="block text-xs font-medium text-n-slate-12">
          {{ replyingTo.name }}
        </span>
        <span class="block text-xs truncate text-n-slate-10">
          {{ replyingTo.preview }}
        </span>
      </span>
      <button
        v-tooltip="t('INTERNAL_CHAT.COMPOSER.CANCEL_REPLY')"
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 rounded-full w-7 h-7 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :aria-label="t('INTERNAL_CHAT.COMPOSER.CANCEL_REPLY')"
        @click="emit('cancelReply')"
      >
        <span class="i-lucide-x" />
      </button>
    </div>

    <!-- Preview de anexos (chips) -->
    <div v-if="attachedFiles.length" class="flex flex-wrap gap-2 mb-2">
      <span
        v-for="(file, index) in attachedFiles"
        :key="index"
        class="inline-flex items-center gap-1.5 pl-2 pr-1 py-1 text-xs rounded-full bg-n-alpha-2 text-n-slate-12"
      >
        <span class="i-lucide-paperclip text-n-slate-10" />
        <span class="max-w-[160px] truncate">{{ file.name }}</span>
        <button
          v-tooltip="t('INTERNAL_CHAT.COMPOSER.REMOVE_FILE')"
          type="button"
          class="inline-flex items-center justify-center rounded-full w-5 h-5 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :aria-label="t('INTERNAL_CHAT.COMPOSER.REMOVE_FILE')"
          @click="removeFile(index)"
        >
          <span class="i-lucide-x" />
        </button>
      </span>
    </div>

    <!-- Gravação de áudio: substitui a barra do composer enquanto grava -->
    <AudioRecorder
      v-if="recording"
      @send="onAudioSend"
      @cancel="recording = false"
    />

    <!-- Barra de escrita: ações discretas à esquerda, pílula com o texto e o
         botão de enviar redondo, que só ganha cor quando há o que enviar. -->
    <div v-else class="flex items-end gap-1">
      <button
        v-tooltip="t('INTERNAL_CHAT.ATTACH')"
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 mb-0.5 transition-colors rounded-full size-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :aria-label="t('INTERNAL_CHAT.ATTACH')"
        @click="onPickFile"
      >
        <span class="text-xl i-lucide-paperclip" />
      </button>
      <input
        ref="fileInputRef"
        type="file"
        multiple
        class="hidden"
        @change="onFilesSelected"
      />
      <button
        v-tooltip="t('INTERNAL_CHAT.COMPOSER.RECORD')"
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 mb-0.5 transition-colors rounded-full size-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :aria-label="t('INTERNAL_CHAT.COMPOSER.RECORD')"
        @click="startRecording"
      >
        <span class="text-xl i-lucide-mic" />
      </button>

      <div
        class="relative z-20 flex items-end flex-1 min-w-0 gap-1 py-1 pl-4 pr-1 transition-colors border rounded-[22px] bg-n-solid-1 dark:bg-n-solid-2 border-n-strong focus-within:border-n-teal-9"
      >
        <textarea
          ref="textareaRef"
          v-model="draft"
          rows="1"
          :placeholder="
            mentionCandidates.length
              ? t('INTERNAL_CHAT.COMPOSER.PLACEHOLDER_GROUP')
              : t('INTERNAL_CHAT.PLACEHOLDER')
          "
          :aria-label="t('INTERNAL_CHAT.PLACEHOLDER')"
          class="reset-base flex-1 h-auto min-h-0 px-0 py-[7px] mb-0 text-[15px] bg-transparent dark:!bg-transparent outline-none !outline-0 resize-none text-n-slate-12 placeholder:text-n-slate-10 max-h-28 leading-snug"
          @input="onInput"
          @click="updateMentionQuery"
          @keydown.enter.exact.prevent="onEnter"
          @keydown.tab="onMentionKey($event, onEnter)"
          @keydown.up="onMentionKey($event, () => moveMention(-1))"
          @keydown.down="onMentionKey($event, () => moveMention(1))"
          @keydown.esc="mentionQuery = null"
        />
        <!-- Emoji: o picker abre ACIMA do ícone -->
        <div class="relative flex-shrink-0">
          <button
            v-tooltip="t('INTERNAL_CHAT.EMOJI')"
            type="button"
            class="inline-flex items-center justify-center transition-colors rounded-full size-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
            :class="showEmoji ? 'text-n-teal-11 bg-n-alpha-2' : ''"
            :aria-label="t('INTERNAL_CHAT.EMOJI')"
            @click="toggleEmoji"
          >
            <span class="text-xl i-lucide-smile" />
          </button>
          <template v-if="showEmoji">
            <div class="fixed inset-0 z-10" @click="showEmoji = false" />
            <div class="absolute z-30 mb-3 emoji-anchor bottom-full right-0">
              <EmojiInput :on-click="onEmojiSelect" />
            </div>
          </template>
        </div>
        <button
          v-tooltip="
            canSend
              ? t('INTERNAL_CHAT.SEND')
              : t('INTERNAL_CHAT.COMPOSER.SEND_EMPTY')
          "
          type="button"
          class="inline-flex items-center justify-center flex-shrink-0 transition-colors duration-200 rounded-full size-9"
          :class="
            canSend
              ? 'bg-n-teal-10 dark:bg-n-teal-9 text-white hover:bg-n-teal-11 shadow-sm'
              : 'bg-n-slate-4 text-n-slate-11 cursor-not-allowed'
          "
          :aria-label="t('INTERNAL_CHAT.SEND')"
          :disabled="!canSend"
          @click="send"
        >
          <span class="text-xl i-lucide-arrow-up" />
        </button>
      </div>
    </div>
    <p
      v-if="!recording"
      class="mb-0 hidden mt-1.5 text-[11px] text-center truncate md:block text-n-slate-10"
    >
      {{
        mentionCandidates.length
          ? t('INTERNAL_CHAT.COMPOSER.HINT_GROUP')
          : t('INTERNAL_CHAT.COMPOSER.HINT_DM')
      }}
    </p>
  </div>
</template>

<style scoped>
/* O EmojiInput já vem com posição própria (absolute right-0 -top-[95px]).
   Neutralizamos para o nosso wrapper (.emoji-anchor) mandar: o quadro abre
   ACIMA do ícone de emoji, alinhado à esquerda, dentro da conversa. */
.emoji-anchor :deep(.emoji-dialog) {
  position: static;
  inset: auto;
}
</style>
