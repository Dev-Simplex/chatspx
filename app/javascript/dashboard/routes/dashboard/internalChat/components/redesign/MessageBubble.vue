<script setup>
import { ref, computed, nextTick } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  message: { type: Object, required: true },
  currentUserId: { type: [Number, String], default: null },
});

const emit = defineEmits([
  'react',
  'edit',
  'delete',
  'reply',
  'retry',
  'scrollTo',
]);

const QUICK_EMOJIS = ['👍', '❤️', '😂', '🎉', '✅', '🙏'];
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

const openMenu = () => {
  if (props.message.deleted) return;
  showReactionPicker.value = false;
  confirmDelete.value = false;
  showMenu.value = !showMenu.value;
};

// Long-press abre o menu no toque (sem clique-direito no mobile).
let longPressTimer = null;
const startLongPress = () => {
  clearTimeout(longPressTimer);
  longPressTimer = setTimeout(openMenu, 450);
};
const cancelLongPress = () => clearTimeout(longPressTimer);

const onReply = () => {
  closeAll();
  emit('reply', props.message);
};

const toggleReactionPicker = () => {
  showMenu.value = false;
  confirmDelete.value = false;
  showReactionPicker.value = !showReactionPicker.value;
};
const react = emoji => {
  closeAll();
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
  <!-- eslint-disable vue/no-bare-strings-in-template -->
  <div
    class="flex items-end gap-2 group"
    :class="message.mine ? 'flex-row-reverse' : 'flex-row'"
    :data-msg-id="message.id"
  >
    <Avatar
      v-if="!message.mine"
      :name="message.senderName || ''"
      :src="message.avatarSrc || ''"
      :size="28"
      rounded-full
      class="mb-1"
    />

    <div
      class="flex flex-col max-w-[78%] md:max-w-[68%] min-w-0"
      :class="message.mine ? 'items-end' : 'items-start'"
    >
      <!-- Apagada -->
      <div
        v-if="message.deleted"
        class="flex items-center gap-1.5 px-3.5 py-2 text-sm italic rounded-2xl text-n-slate-10 bg-n-alpha-1"
      >
        <span class="text-sm i-lucide-ban" />
        Mensagem apagada
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
            Salvar
          </button>
          <button type="button" class="text-n-slate-10" @click="cancelEdit">
            Cancelar
          </button>
        </div>
      </div>

      <!-- Balão normal -->
      <div
        v-else
        class="relative px-3.5 py-2 text-sm shadow-sm rounded-2xl break-words min-w-0"
        :class="
          message.mine
            ? 'bg-n-brand text-white rounded-br-md'
            : 'bg-n-alpha-2 text-n-slate-12 rounded-bl-md'
        "
        @contextmenu.prevent="openMenu"
        @touchstart.passive="startLongPress"
        @touchend="cancelLongPress"
        @touchmove.passive="cancelLongPress"
      >
        <!-- Gatilho ⋯ (hover/foco); toque usa long-press, desktop tem right-click -->
        <button
          type="button"
          class="absolute z-20 inline-flex items-center justify-center transition-opacity -translate-y-1/2 border rounded-full opacity-0 top-1/2 w-7 h-7 bg-n-solid-1 border-n-weak text-n-slate-11 shadow-sm group-hover:opacity-100 focus:opacity-100"
          :class="message.mine ? '-left-9' : '-right-9'"
          title="Ações da mensagem"
          @click.stop="openMenu"
        >
          <span class="text-base i-lucide-ellipsis" />
        </button>

        <!-- Backdrop click-fora do menu/picker -->
        <div
          v-if="showMenu || showReactionPicker"
          class="fixed inset-0 z-10"
          @click="closeAll"
          @contextmenu.prevent="closeAll"
        />

        <!-- Menu de ações -->
        <div
          v-if="showMenu"
          class="absolute z-20 flex items-center gap-1 px-1.5 py-1.5 border rounded-full shadow-lg bottom-full mb-1.5 bg-n-solid-1 border-n-weak"
          :class="message.mine ? 'right-0' : 'left-0'"
        >
          <button
            type="button"
            class="inline-flex items-center justify-center transition-colors rounded-full w-9 h-9 text-n-slate-12 hover:bg-n-alpha-2"
            title="Responder"
            @click="onReply"
          >
            <span class="text-xl i-lucide-reply" />
          </button>
          <button
            type="button"
            class="inline-flex items-center justify-center transition-colors rounded-full w-9 h-9 text-n-slate-12 hover:bg-n-alpha-2"
            title="Reagir"
            @click="toggleReactionPicker"
          >
            <span class="text-xl i-lucide-smile-plus" />
          </button>
          <button
            v-if="message.mine"
            type="button"
            class="inline-flex items-center justify-center transition-colors rounded-full w-9 h-9 text-n-slate-12 hover:bg-n-alpha-2"
            title="Editar"
            @click="startEdit"
          >
            <span class="text-xl i-lucide-pencil" />
          </button>
          <button
            v-if="message.mine"
            type="button"
            class="inline-flex items-center justify-center transition-colors rounded-full w-9 h-9 text-n-slate-12 hover:bg-n-ruby-3 hover:text-n-ruby-11"
            title="Apagar"
            @click="askDelete"
          >
            <span class="text-xl i-lucide-trash-2" />
          </button>
        </div>

        <!-- Picker de reação -->
        <div
          v-if="showReactionPicker"
          class="absolute z-20 flex gap-1 px-2 py-1 border rounded-full shadow-md bottom-full mb-1.5 bg-n-solid-1 border-n-weak"
          :class="message.mine ? 'right-0' : 'left-0'"
        >
          <button
            v-for="e in QUICK_EMOJIS"
            :key="e"
            type="button"
            class="text-base leading-none transition-transform hover:scale-125"
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
          <span class="whitespace-nowrap text-n-slate-11">Apagar?</span>
          <button
            type="button"
            class="font-medium text-n-ruby-11"
            @click="doDelete"
          >
            Apagar
          </button>
          <button
            type="button"
            class="text-n-slate-10"
            @click="confirmDelete = false"
          >
            Cancelar
          </button>
        </div>

        <!-- Citação da mensagem respondida -->
        <button
          v-if="message.replyTo"
          type="button"
          class="block w-full pl-2 mb-1 text-left border-l-2 rounded-sm opacity-90"
          :class="message.mine ? 'border-white/60' : 'border-n-brand'"
          @click="emit('scrollTo', message.replyTo.id)"
        >
          <span class="block text-[11px] font-semibold">
            {{ message.replyTo.user_name }}
          </span>
          <span class="block text-[11px] opacity-75 truncate">
            {{ message.replyTo.content || 'Mensagem apagada' }}
          </span>
        </button>

        <!-- Texto + "editado" -->
        <p v-if="message.content" class="leading-relaxed whitespace-pre-wrap">
          {{ message.content
          }}<span
            v-if="message.edited"
            class="text-[10px] opacity-60 ml-1 align-baseline"
            >editado</span
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
            <audio
              v-else-if="isAudio(att)"
              :src="att.url"
              controls
              class="max-w-[240px] h-9"
            />
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
          :class="message.mine ? 'text-white/70' : 'text-n-slate-10'"
        >
          {{ message.time }}
          <span
            v-if="message.mine && message.status === 'progress'"
            class="text-sm i-lucide-clock"
            title="Enviando…"
          />
          <button
            v-else-if="message.mine && message.status === 'failed'"
            type="button"
            class="font-medium text-n-ruby-11 hover:underline"
            @click="emit('retry', message)"
          >
            Falhou — tentar de novo
          </button>
          <span
            v-else-if="message.mine"
            class="text-sm"
            :class="message.read ? 'i-lucide-check-check' : 'i-lucide-check'"
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
