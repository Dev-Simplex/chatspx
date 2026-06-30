<script setup>
import { computed, ref } from 'vue';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { useI18n } from 'vue-i18n';

const store = useStore();
const { t } = useI18n();
const currentChat = useMapGetter('getSelectedChat');

const customAttributes = computed(
  () => currentChat.value?.custom_attributes || {}
);
const items = computed(() => {
  const raw = customAttributes.value.assuntos_checklist;
  return Array.isArray(raw) ? raw : [];
});

const newText = ref('');
const saving = ref(false);

const persist = async nextItems => {
  saving.value = true;
  try {
    await store.dispatch('updateCustomAttributes', {
      conversationId: currentChat.value.id,
      customAttributes: {
        ...customAttributes.value,
        assuntos_checklist: nextItems,
      },
    });
  } catch (error) {
    useAlert(t('CONVERSATION_SIDEBAR.CHECKLIST.SAVE_ERROR'));
  } finally {
    saving.value = false;
  }
};

const generateId = () => window.crypto?.randomUUID?.() || `task-${Date.now()}`;

const addItem = () => {
  const text = newText.value.trim();
  if (!text) return;
  persist([
    ...items.value,
    { id: generateId(), text, done: false, source: 'human' },
  ]);
  newText.value = '';
};

const toggleItem = item => {
  persist(
    items.value.map(i => (i.id === item.id ? { ...i, done: !i.done } : i))
  );
};

const removeItem = item => {
  persist(items.value.filter(i => i.id !== item.id));
};
</script>

<template>
  <div class="flex flex-col px-4 pt-1 pb-3">
    <ul v-if="items.length" class="flex flex-col gap-1 mb-2">
      <li
        v-for="item in items"
        :key="item.id"
        class="flex items-start gap-2 group"
      >
        <button
          class="flex items-center justify-center mt-0.5 border rounded size-4 shrink-0"
          :class="
            item.done
              ? 'bg-n-brand border-n-brand text-white'
              : 'border-n-weak text-transparent hover:border-n-slate-8'
          "
          @click="toggleItem(item)"
        >
          <span class="i-lucide-check size-3" />
        </button>
        <span
          class="flex-1 text-xs leading-snug"
          :class="
            item.done ? 'line-through text-n-slate-10' : 'text-n-slate-12'
          "
        >
          {{ item.text }}
          <span
            v-if="item.source === 'ia'"
            class="ml-1 px-1 py-px text-[10px] rounded bg-n-brand/10 text-n-brand align-middle"
          >
            {{ $t('CONVERSATION_SIDEBAR.CHECKLIST.SOURCE_IA') }}
          </span>
        </span>
        <button
          class="opacity-0 group-hover:opacity-100 text-n-slate-10 hover:text-n-slate-12"
          :title="$t('CONVERSATION_SIDEBAR.CHECKLIST.REMOVE')"
          @click="removeItem(item)"
        >
          <span class="i-lucide-x size-3.5" />
        </button>
      </li>
    </ul>
    <p v-else class="mb-2 text-xs italic text-n-slate-10">
      {{ $t('CONVERSATION_SIDEBAR.CHECKLIST.EMPTY') }}
    </p>
    <div class="flex items-center gap-1.5">
      <input
        v-model="newText"
        type="text"
        :placeholder="$t('CONVERSATION_SIDEBAR.CHECKLIST.ADD_PLACEHOLDER')"
        class="flex-1 px-2 py-1 text-xs border rounded border-n-weak bg-n-solid-1 text-n-slate-12 focus:outline-none focus:border-n-brand"
        @keyup.enter="addItem"
      />
      <button
        class="flex items-center justify-center text-white rounded size-6 bg-n-brand disabled:opacity-50"
        :disabled="saving || !newText.trim()"
        :title="$t('CONVERSATION_SIDEBAR.CHECKLIST.ADD')"
        @click="addItem"
      >
        <span class="i-lucide-plus size-4" />
      </button>
    </div>
  </div>
</template>
