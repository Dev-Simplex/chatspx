<script setup>
import { ref, nextTick, defineAsyncComponent } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import { availableContacts } from './mockData.js';

const emit = defineEmits(['send']);

const EmojiInput = defineAsyncComponent(
  () => import('shared/components/emoji/EmojiInput.vue')
);

const draft = ref('');
const attachments = ref([]);
const showEmoji = ref(false);
const attachView = ref(null); // null | 'menu' | 'contacts'
const showPoll = ref(false);
const pollQuestion = ref('');
const pollOptions = ref(['', '']);
const textareaRef = ref(null);
const fileInputRef = ref(null);
const imageInputRef = ref(null);

const closeAll = () => {
  showEmoji.value = false;
  attachView.value = null;
  showPoll.value = false;
};

// Os popovers do composer são mutuamente exclusivos.
const toggleAttach = () => {
  showEmoji.value = false;
  showPoll.value = false;
  attachView.value = attachView.value ? null : 'menu';
};
const toggleEmoji = () => {
  attachView.value = null;
  showPoll.value = false;
  showEmoji.value = !showEmoji.value;
};

const autoResize = () => {
  const el = textareaRef.value;
  if (!el) return;
  el.style.height = 'auto';
  el.style.height = `${Math.min(el.scrollHeight, 112)}px`;
};

const onEmojiSelect = emoji => {
  draft.value += emoji;
  showEmoji.value = false;
  nextTick(() => {
    textareaRef.value?.focus();
    autoResize();
  });
};

const openPicker = kind => {
  attachView.value = null;
  const input = kind === 'image' ? imageInputRef.value : fileInputRef.value;
  input?.click();
};

const onFilesSelected = event => {
  Array.from(event.target.files || []).forEach(f => {
    attachments.value.push({
      icon: (f.type || '').startsWith('image/')
        ? 'i-lucide-image'
        : 'i-lucide-file-text',
      label: f.name,
    });
  });
  event.target.value = '';
};

const attachContact = contact => {
  attachments.value.push({ icon: 'i-lucide-user-round', label: contact.name });
  attachView.value = null;
};

const removeAttachment = index => attachments.value.splice(index, 1);

const openPoll = () => {
  attachView.value = null;
  showPoll.value = true;
  pollQuestion.value = '';
  pollOptions.value = ['', ''];
};

const createPoll = () => {
  const opts = pollOptions.value.map(o => o.trim()).filter(Boolean);
  if (!pollQuestion.value.trim() || opts.length < 2) return;
  const text = `📊 Enquete: ${pollQuestion.value.trim()}\n${opts
    .map(o => `• ${o}`)
    .join('\n')}`;
  emit('send', text);
  showPoll.value = false;
};

const send = () => {
  const content = draft.value.trim();
  if (!content && !attachments.value.length) return;
  const suffix = attachments.value.length
    ? ` (${attachments.value.length} anexo${attachments.value.length > 1 ? 's' : ''})`
    : '';
  emit('send', (content || '📎 Anexo') + (content ? '' : suffix));
  draft.value = '';
  attachments.value = [];
  closeAll();
  nextTick(autoResize);
};

const ATTACH_ACTIONS = [
  { key: 'document', icon: 'i-lucide-file-text', label: 'Documento' },
  { key: 'photos', icon: 'i-lucide-image', label: 'Fotos' },
  { key: 'contact', icon: 'i-lucide-user-round', label: 'Contato' },
  { key: 'poll', icon: 'i-lucide-bar-chart-3', label: 'Enquete' },
];

const runAttach = key => {
  if (key === 'document') openPicker('file');
  else if (key === 'photos') openPicker('image');
  else if (key === 'contact') attachView.value = 'contacts';
  else if (key === 'poll') openPoll();
};
</script>

<template>
  <!-- Protótipo visual (dados fictícios); i18n entra na versão final. -->
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div class="relative px-4 pb-3 md:px-6 flex-shrink-0 bg-n-background">
    <!-- "+" attach menu / contacts submenu -->
    <template v-if="attachView">
      <div class="fixed inset-0 z-10" @click="attachView = null" />
      <div
        class="absolute z-20 overflow-hidden border shadow-lg left-4 md:left-6 bottom-full mb-2 w-60 rounded-xl bg-n-solid-1 border-n-weak"
      >
        <template v-if="attachView === 'menu'">
          <button
            v-for="a in ATTACH_ACTIONS"
            :key="a.key"
            type="button"
            class="flex items-center w-full gap-3 px-3 py-2.5 text-sm text-left text-n-slate-12 hover:bg-n-alpha-1"
            @click="runAttach(a.key)"
          >
            <span class="text-lg text-n-brand" :class="a.icon" />
            {{ a.label }}
          </button>
        </template>
        <template v-else-if="attachView === 'contacts'">
          <div
            class="flex items-center gap-2 px-2 py-1.5 border-b border-n-weak"
          >
            <button
              type="button"
              class="inline-flex items-center justify-center rounded-lg w-7 h-7 text-n-slate-11 hover:bg-n-alpha-2"
              @click="attachView = 'menu'"
            >
              <span class="i-lucide-arrow-left" />
            </button>
            <span class="text-xs font-semibold text-n-slate-11">
              Enviar contato
            </span>
          </div>
          <div class="py-1 overflow-y-auto max-h-56">
            <button
              v-for="c in availableContacts"
              :key="c.id"
              type="button"
              class="flex items-center w-full gap-2.5 px-3 py-2 text-left hover:bg-n-alpha-1"
              @click="attachContact(c)"
            >
              <Avatar :name="c.name" :size="28" rounded-full />
              <span class="text-sm text-n-slate-12">{{ c.name }}</span>
            </button>
          </div>
        </template>
      </div>
    </template>

    <!-- Poll form -->
    <template v-if="showPoll">
      <div class="fixed inset-0 z-10" @click="showPoll = false" />
      <div
        class="absolute z-20 p-3 border shadow-lg left-4 right-4 md:left-6 md:right-6 bottom-full mb-2 rounded-xl bg-n-solid-1 border-n-weak"
      >
        <p class="mb-2 text-sm font-semibold text-n-slate-12">Nova enquete</p>
        <input
          v-model="pollQuestion"
          type="text"
          placeholder="Pergunta"
          class="reset-base w-full h-9 px-3 mb-2 text-sm border rounded-lg outline-none bg-n-alpha-1 border-transparent focus:border-n-brand text-n-slate-12 placeholder:text-n-slate-10"
        />
        <input
          v-for="(opt, i) in pollOptions"
          :key="i"
          v-model="pollOptions[i]"
          type="text"
          :placeholder="`Opção ${i + 1}`"
          class="reset-base w-full h-9 px-3 mb-2 text-sm border rounded-lg outline-none bg-n-alpha-1 border-transparent focus:border-n-brand text-n-slate-12 placeholder:text-n-slate-10"
        />
        <div class="flex items-center justify-between">
          <button
            type="button"
            class="text-xs font-medium text-n-brand hover:underline"
            @click="pollOptions.push('')"
          >
            + Adicionar opção
          </button>
          <button
            type="button"
            class="px-3 py-1.5 text-xs font-semibold text-white rounded-lg bg-n-brand hover:bg-n-brand-hover disabled:opacity-40"
            @click="createPoll"
          >
            Criar enquete
          </button>
        </div>
      </div>
    </template>

    <!-- Attachment chips -->
    <div v-if="attachments.length" class="flex flex-wrap gap-1.5 mb-1.5 px-1">
      <span
        v-for="(a, i) in attachments"
        :key="i"
        class="inline-flex items-center gap-1.5 py-1 pl-2 pr-1 text-xs rounded-lg bg-n-alpha-2 text-n-slate-12"
      >
        <span :class="a.icon" />
        <span class="max-w-[140px] truncate">{{ a.label }}</span>
        <button
          type="button"
          class="inline-flex items-center justify-center w-4 h-4 rounded hover:bg-n-alpha-2 text-n-slate-11"
          @click="removeAttachment(i)"
        >
          <span class="i-lucide-x text-[11px]" />
        </button>
      </span>
    </div>

    <!-- Single-row composer pill -->
    <div
      class="relative z-20 flex items-center gap-1 px-2 py-1 transition-colors border shadow-sm rounded-2xl bg-n-solid-1 border-n-weak focus-within:border-n-brand"
    >
      <button
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 transition-colors rounded-full w-9 h-9 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12"
        :class="attachView ? 'text-n-brand bg-n-alpha-2' : ''"
        title="Anexar"
        @click="toggleAttach"
      >
        <span class="text-xl i-lucide-plus" />
      </button>
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
          <div class="absolute z-20 bottom-full mb-2 left-0">
            <EmojiInput :on-click="onEmojiSelect" />
          </div>
        </template>
      </div>
      <textarea
        ref="textareaRef"
        v-model="draft"
        rows="1"
        placeholder="Digite sua mensagem..."
        class="reset-base flex-1 h-auto min-h-0 px-1 py-1.5 mb-0 text-sm bg-transparent outline-none resize-none text-n-slate-12 placeholder:text-n-slate-10 max-h-28 leading-snug"
        @input="autoResize"
        @keydown.enter.exact.prevent="send"
      />
      <button
        type="button"
        class="inline-flex items-center justify-center flex-shrink-0 w-9 h-9 text-white transition-all rounded-full shadow-sm bg-n-brand hover:bg-n-brand-hover active:scale-90 disabled:opacity-40 disabled:cursor-not-allowed disabled:active:scale-100"
        title="Enviar"
        :disabled="!draft.trim() && !attachments.length"
        @click="send"
      >
        <span class="text-lg i-lucide-send-horizontal" />
      </button>
    </div>

    <input
      ref="fileInputRef"
      type="file"
      multiple
      class="hidden"
      @change="onFilesSelected"
    />
    <input
      ref="imageInputRef"
      type="file"
      accept="image/*"
      multiple
      class="hidden"
      @change="onFilesSelected"
    />
  </div>
</template>
