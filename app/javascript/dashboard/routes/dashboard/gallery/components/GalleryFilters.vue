<script setup>
import { computed, ref } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

const props = defineProps({
  filters: { type: Object, required: true },
});
const emit = defineEmits(['change']);

const store = useStore();
const { t } = useI18n();

const inboxes = computed(() => store.getters['inboxes/getInboxes']);
const openMenu = ref(null);
const close = () => {
  openMenu.value = null;
};

const inboxLabel = computed(() => {
  if (!props.filters.inboxId) return t('GALLERY.FILTERS.ALL_INBOXES');
  const inbox = inboxes.value.find(i => i.id === props.filters.inboxId);
  return inbox?.name || t('GALLERY.FILTERS.ALL_INBOXES');
});

const sortLabel = computed(() => {
  return props.filters.sort === 'date_asc'
    ? t('GALLERY.SORT.DATE_ASC')
    : t('GALLERY.SORT.DATE_DESC');
});

const setInbox = id => {
  emit('change', { inboxId: id });
  close();
};
const setSort = sort => {
  emit('change', { sort });
  close();
};
</script>

<template>
  <div class="flex items-center gap-2 flex-shrink-0">
    <!-- Inbox chip -->
    <div v-on-click-outside="close" class="relative">
      <button
        type="button"
        class="!inline-flex items-center gap-1.5 !h-11 !px-4 !rounded-xl !text-sm !font-medium !border !border-n-weak !bg-n-solid-1 dark:!bg-n-solid-2 !text-n-slate-12 hover:!bg-n-alpha-1 dark:hover:!bg-n-slate-9/30 !transition-colors !m-0"
        :class="{ '!border-n-brand !text-n-brand': props.filters.inboxId }"
        @click="openMenu = openMenu === 'inbox' ? null : 'inbox'"
      >
        <span class="i-lucide-inbox size-4 opacity-70" />
        <span class="truncate max-w-[140px]">{{ inboxLabel }}</span>
        <span
          class="i-lucide-chevron-down size-3.5 opacity-60 transition-transform"
          :class="{ 'rotate-180': openMenu === 'inbox' }"
        />
      </button>
      <div
        v-if="openMenu === 'inbox'"
        class="absolute z-30 ltr:right-0 rtl:left-0 top-full mt-2 min-w-[220px] max-h-72 overflow-y-auto p-1.5 rounded-2xl bg-n-solid-1 dark:bg-n-solid-2 border border-n-weak shadow-xl ring-1 ring-n-black/5 dark:ring-white/5"
      >
        <button
          type="button"
          class="!w-full !flex !items-center !justify-between gap-2 !px-3 !py-2 !text-sm !font-normal !rounded-lg !border-0 !bg-transparent hover:!bg-n-alpha-1 dark:hover:!bg-n-slate-9/30 !text-left !m-0 !h-auto !leading-normal"
          :class="{
            'bg-n-brand/10 text-n-brand font-medium': !props.filters.inboxId,
            'text-n-slate-12': props.filters.inboxId,
          }"
          @click="setInbox(null)"
        >
          <span>{{ t('GALLERY.FILTERS.ALL_INBOXES') }}</span>
          <span
            v-if="!props.filters.inboxId"
            class="i-lucide-check size-4 text-n-brand"
          />
        </button>
        <div class="h-px my-1.5 bg-n-weak/40" />
        <button
          v-for="inbox in inboxes"
          :key="inbox.id"
          type="button"
          class="!w-full !flex !items-center !justify-between gap-2 !px-3 !py-2 !text-sm !font-normal !rounded-lg !border-0 !bg-transparent hover:!bg-n-alpha-1 dark:hover:!bg-n-slate-9/30 !text-left !m-0 !h-auto !leading-normal"
          :class="{
            'bg-n-brand/10 text-n-brand font-medium':
              props.filters.inboxId === inbox.id,
            'text-n-slate-12': props.filters.inboxId !== inbox.id,
          }"
          @click="setInbox(inbox.id)"
        >
          <span class="truncate">{{ inbox.name }}</span>
          <span
            v-if="props.filters.inboxId === inbox.id"
            class="i-lucide-check size-4 text-n-brand flex-shrink-0"
          />
        </button>
      </div>
    </div>

    <!-- Sort chip (não aparece em links) -->
    <div
      v-if="props.filters.tab !== 'links'"
      v-on-click-outside="close"
      class="relative"
    >
      <button
        type="button"
        class="!inline-flex items-center gap-1.5 !h-11 !px-4 !rounded-xl !text-sm !font-medium !border !border-n-weak !bg-n-solid-1 dark:!bg-n-solid-2 !text-n-slate-12 hover:!bg-n-alpha-1 dark:hover:!bg-n-slate-9/30 !transition-colors !m-0"
        @click="openMenu = openMenu === 'sort' ? null : 'sort'"
      >
        <span class="i-lucide-arrow-down-up size-4 opacity-70" />
        <span class="truncate">{{ sortLabel }}</span>
        <span
          class="i-lucide-chevron-down size-3.5 opacity-60 transition-transform"
          :class="{ 'rotate-180': openMenu === 'sort' }"
        />
      </button>
      <div
        v-if="openMenu === 'sort'"
        class="absolute z-30 ltr:right-0 rtl:left-0 top-full mt-2 min-w-[200px] p-1.5 rounded-2xl bg-n-solid-1 dark:bg-n-solid-2 border border-n-weak shadow-xl ring-1 ring-n-black/5 dark:ring-white/5"
      >
        <button
          v-for="opt in [
            { key: 'date_desc', label: t('GALLERY.SORT.DATE_DESC') },
            { key: 'date_asc', label: t('GALLERY.SORT.DATE_ASC') },
          ]"
          :key="opt.key"
          type="button"
          class="!w-full !flex !items-center !justify-between gap-2 !px-3 !py-2 !text-sm !font-normal !rounded-lg !border-0 !bg-transparent hover:!bg-n-alpha-1 dark:hover:!bg-n-slate-9/30 !text-left !m-0 !h-auto !leading-normal"
          :class="{
            'bg-n-brand/10 text-n-brand font-medium':
              props.filters.sort === opt.key,
            'text-n-slate-12': props.filters.sort !== opt.key,
          }"
          @click="setSort(opt.key)"
        >
          <span>{{ opt.label }}</span>
          <span
            v-if="props.filters.sort === opt.key"
            class="i-lucide-check size-4 text-n-brand"
          />
        </button>
      </div>
    </div>
  </div>
</template>
