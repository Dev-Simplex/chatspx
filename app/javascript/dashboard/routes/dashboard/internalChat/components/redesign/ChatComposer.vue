<script setup>
import { ref, computed, nextTick, defineAsyncComponent } from 'vue';
import { useAlert } from 'dashboard/composables';
import {
  checkFileSizeLimit,
  HARD_MAXIMUM_FILE_UPLOAD_SIZE,
} from 'shared/helpers/FileHelper';
import { AUDIO_FORMATS } from 'shared/constants/messages';
import CannedResponse from 'dashboard/components/widgets/conversation/CannedResponse.vue';

const props = defineProps({
  // Mensagem sendo respondida: { id, name, preview } (ou null).
  replyingTo: { type: Object, default: null },
});

const emit = defineEmits(['send', 'cancelReply']);

const EmojiPicker = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiPicker.vue')
);
const AudioRecorder = defineAsyncComponent(
  () => import('dashboard/components/widgets/WootWriter/AudioRecorder.vue')
);

const draft = ref('');
const showEmoji = ref(false);
const textareaRef = ref(null);
const fileInputRef = ref(null);
const attachedFiles = ref([]);
const recording = ref(false);
const audioRecorderRef = ref(null);

const autoResize = () => {
  const el = textareaRef.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, 112)}px`;
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

const onEmojiSelect = ({ value }) => {
  draft.value += value;
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
        `O arquivo "${file.name}" excede o limite de ${HARD_MAXIMUM_FILE_UPLOAD_SIZE} MB.`
      );
    }
  });
  event.target.value = '';
};
const removeFile = index => attachedFiles.value.splice(index, 1);

// ── Áudio ───────────────────────────────────────────────────────────────────
// O AudioRecorder começa a gravar assim que monta; paramos via ref exposto.
const startRecording = () => {
  showEmoji.value = false;
  recording.value = true;
};
const stopRecording = () => audioRecorderRef.value?.stopRecording();
const onFinishRecord = ({ file }) => {
  if (file) attachedFiles.value.push(file);
  recording.value = false;
};
const onRecordError = () => {
  recording.value = false;
  useAlert('Não foi possível gravar o áudio.');
};

const send = () => {
  const content = draft.value.trim();
  if (!content && !attachedFiles.value.length) return;
  emit('send', {
    content,
    attachments: [...attachedFiles.value],
    replyToId: props.replyingTo?.id || null,
  });
  draft.value = '';
  attachedFiles.value = [];
  showEmoji.value = false;
  nextTick(autoResize);
};

// Enter envia — a menos que o picker esteja REALMENTE aberto (com resultados), aí o
// Enter escolhe a resposta. Sem match (nenhuma .mention--box), envia normalmente —
// assim uma mensagem que começa com "/" e não é atalho ainda pode ser enviada.
const onEnter = () => {
  if (showCanned.value && document.querySelector('.mention--box')) return;
  send();
};
</script>

<template>
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="relative px-4 pb-3 md:px-6 flex-shrink-0 bg-n-background">
    <!-- Respostas prontas: aparece acima do compositor ao começar com "/" -->
    <CannedResponse
      v-if="showCanned"
      :search-key="cannedSearchKey"
      @replace="onCannedSelect"
    />

    <!-- Barra "respondendo a X" -->
    <div
      v-if="replyingTo"
      class="flex items-center gap-2 mb-2 px-2.5 py-1.5 bg-n-alpha-1 border-l-2 border-n-brand rounded-r-lg"
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
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 rounded-full w-7 h-7 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
        title="Cancelar resposta"
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
          type="button"
          class="inline-flex items-center justify-center rounded-full w-5 h-5 text-n-slate-10 hover:bg-n-alpha-2 hover:text-n-slate-12"
          title="Remover anexo"
          @click="removeFile(index)"
        >
          <span class="i-lucide-x" />
        </button>
      </span>
    </div>

    <!-- Gravação de áudio: substitui a barra do composer enquanto grava -->
    <div
      v-if="recording"
      class="relative z-20 flex items-center gap-2 px-3 py-2 border shadow-sm rounded-2xl bg-n-solid-1 border-n-weak"
    >
      <span class="flex-shrink-0 i-lucide-mic text-n-ruby-11 animate-pulse" />
      <div class="flex-1 min-w-0">
        <AudioRecorder
          ref="audioRecorderRef"
          :audio-record-format="AUDIO_FORMATS.MP3"
          @finish-record="onFinishRecord"
          @record-error="onRecordError"
        />
      </div>
      <button
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 w-9 h-9 text-white transition-all rounded-full shadow-sm bg-n-brand hover:bg-n-brand-hover active:scale-90"
        title="Concluir gravação"
        @click="stopRecording"
      >
        <span class="text-lg i-lucide-check" />
      </button>
    </div>

    <!-- Single-row composer pill -->
    <div
      v-else
      class="relative z-20 flex items-center gap-1 px-2 py-1 transition-colors border shadow-sm rounded-2xl bg-n-solid-1 border-n-weak focus-within:border-n-brand"
    >
      <!-- Emoji: o picker abre ACIMA do ícone (ancorado ao botão, à esquerda) -->
      <div class="relative flex-shrink-0">
        <button
          type="button"
          class="inline-flex items-center justify-center transition-colors rounded-full w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
          :class="showEmoji ? 'text-n-brand bg-n-alpha-2' : ''"
          title="Emoji"
          @click="toggleEmoji"
        >
          <span class="text-lg i-lucide-smile" />
        </button>
        <template v-if="showEmoji">
          <div class="fixed inset-0 z-10" @click="showEmoji = false" />
          <div class="absolute z-30 emoji-anchor bottom-full mb-2 left-0">
            <EmojiPicker class="!static" @select="onEmojiSelect" />
          </div>
        </template>
      </div>
      <!-- Anexo -->
      <button
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 transition-colors rounded-full w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        title="Anexar arquivo"
        @click="onPickFile"
      >
        <span class="text-lg i-lucide-paperclip" />
      </button>
      <input
        ref="fileInputRef"
        type="file"
        multiple
        class="hidden"
        @change="onFilesSelected"
      />
      <!-- Áudio -->
      <button
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 transition-colors rounded-full w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        title="Gravar áudio"
        @click="startRecording"
      >
        <span class="text-lg i-lucide-mic" />
      </button>
      <textarea
        ref="textareaRef"
        v-model="draft"
        rows="1"
        placeholder="Digite sua mensagem..."
        class="reset-base flex-1 h-auto min-h-0 px-1 py-1.5 mb-0 text-sm bg-transparent outline-none resize-none text-n-slate-12 placeholder:text-n-slate-10 max-h-28 leading-snug"
        @input="autoResize"
        @keydown.enter.exact.prevent="onEnter"
      />
      <button
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 w-9 h-9 text-white transition-all rounded-full shadow-sm bg-n-brand hover:bg-n-brand-hover active:scale-90 disabled:opacity-40 disabled:cursor-not-allowed disabled:active:scale-100"
        title="Enviar"
        :disabled="!draft.trim() && !attachedFiles.length"
        @click="send"
      >
        <span class="text-lg i-lucide-send-horizontal" />
      </button>
    </div>
  </div>
</template>
