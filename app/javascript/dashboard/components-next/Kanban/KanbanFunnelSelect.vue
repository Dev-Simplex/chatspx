<script setup>
// Combobox de funis: nome + cor + count de cards. P1-01.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  funnels: { type: Array, default: () => [] },
  modelValue: { type: [Number, String, null], default: null },
  itemCounts: { type: Object, default: () => ({}) }, // { [funnelId]: number }
});
const emit = defineEmits(['update:modelValue']);
const { t } = useI18n();

const open = ref(false);
const query = ref('');
const rootRef = ref(null);

const activeFunnel = computed(
  () => props.funnels.find(f => f.id === Number(props.modelValue)) || null
);

const filteredFunnels = computed(() => {
  const q = query.value.trim().toLowerCase();
  if (!q) return props.funnels;
  return props.funnels.filter(f => (f.name || '').toLowerCase().includes(q));
});

const toggle = () => {
  open.value = !open.value;
  query.value = '';
};

const select = funnel => {
  emit('update:modelValue', funnel.id);
  open.value = false;
};

const onDocClick = e => {
  if (!rootRef.value) return;
  if (!rootRef.value.contains(e.target)) open.value = false;
};

onMounted(() => document.addEventListener('mousedown', onDocClick));
onBeforeUnmount(() => document.removeEventListener('mousedown', onDocClick));
</script>

<template>
  <div ref="rootRef" class="relative inline-block">
    <button
      type="button"
      class="inline-flex items-center gap-2 px-3 h-9 rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 text-sm text-slate-800 dark:text-slate-100 hover:bg-slate-50 dark:hover:bg-slate-800 transition-colors min-w-[180px]"
      :aria-expanded="open"
      aria-haspopup="listbox"
      @click="toggle"
    >
      <span
        v-if="activeFunnel"
        class="inline-block size-2.5 rounded-full"
        :style="{ background: activeFunnel.color || '#6366f1' }"
        aria-hidden="true"
      />
      <span class="flex-1 text-left truncate">
        <span class="text-slate-500 dark:text-slate-400 mr-1">{{
          `${t('KANBAN.HEADER.FUNNEL_LABEL')}:`
        }}</span>
        <span class="font-medium">{{
          activeFunnel ? activeFunnel.name : t('KANBAN.HEADER.ALL_FUNNELS')
        }}</span>
      </span>
      <Icon icon="i-lucide-chevron-down" class="size-4 text-slate-500" />
    </button>

    <div
      v-if="open"
      class="absolute z-30 top-full left-0 mt-1 w-[300px] rounded-lg border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 shadow-lg"
      role="listbox"
    >
      <div class="p-2 border-b border-slate-100 dark:border-slate-800">
        <input
          v-model="query"
          type="text"
          :placeholder="t('KANBAN.HEADER.FUNNEL_SEARCH_PLACEHOLDER')"
          class="w-full px-2 h-8 text-sm rounded-md bg-slate-50 dark:bg-slate-800 border border-transparent focus:border-iris-500 focus:outline-none text-slate-800 dark:text-slate-100"
        />
      </div>
      <ul class="max-h-72 overflow-y-auto py-1">
        <li
          v-for="funnel in filteredFunnels"
          :key="funnel.id"
          class="px-3 h-9 flex items-center gap-2 cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-800 text-sm"
          :class="{
            'bg-iris-50 dark:bg-iris-900/30': funnel.id === Number(modelValue),
          }"
          role="option"
          :aria-selected="funnel.id === Number(modelValue)"
          @click="select(funnel)"
        >
          <span
            class="inline-block size-2.5 rounded-full"
            :style="{ background: funnel.color || '#6366f1' }"
            aria-hidden="true"
          />
          <span class="flex-1 truncate text-slate-800 dark:text-slate-100">
            {{ funnel.name }}
          </span>
          <span
            v-if="itemCounts[funnel.id] != null"
            class="text-xs text-slate-500 dark:text-slate-400"
          >
            {{ itemCounts[funnel.id] }}
          </span>
        </li>
      </ul>
    </div>
  </div>
</template>
