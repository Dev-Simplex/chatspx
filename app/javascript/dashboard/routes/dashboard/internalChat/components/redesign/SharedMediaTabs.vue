<script setup>
// Painel Detalhes › "Mídia, links e docs": o que já circulou na conversa,
// em três abas. Clicar abre o arquivo/link; o botão ao lado leva à mensagem.
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import InternalChatAPI from 'dashboard/api/internalChat';

const props = defineProps({
  channelId: { type: [Number, String], required: true },
  // Muda quando chega mensagem nova: recarrega as abas.
  lastAt: { type: Number, default: 0 },
});
const emit = defineEmits(['openMessage']);
const { t } = useI18n();

const TABS = ['media', 'docs', 'links'];
const tab = ref('media');
const state = ref('loading'); // loading | ready | error
const data = ref({ media: [], docs: [], links: [] });
const query = ref('');
const SEARCH_MIN = 8;

const load = async () => {
  if (state.value !== 'ready') state.value = 'loading';
  try {
    const { data: result } = await InternalChatAPI.getSharedMedia(
      props.channelId
    );
    data.value = result;
    state.value = 'ready';
  } catch {
    state.value = 'error';
  }
};
watch(
  () => props.channelId,
  () => {
    state.value = 'loading';
    query.value = '';
    load();
  },
  { immediate: true }
);
watch(() => props.lastAt, load);

const labelFor = key =>
  ({
    media: t('INTERNAL_CHAT.SHARED_MEDIA.TAB_MEDIA'),
    docs: t('INTERNAL_CHAT.SHARED_MEDIA.TAB_DOCS'),
    links: t('INTERNAL_CHAT.SHARED_MEDIA.TAB_LINKS'),
  })[key];
const emptyFor = key =>
  ({
    media: t('INTERNAL_CHAT.SHARED_MEDIA.EMPTY_MEDIA'),
    docs: t('INTERNAL_CHAT.SHARED_MEDIA.EMPTY_DOCS'),
    links: t('INTERNAL_CHAT.SHARED_MEDIA.EMPTY_LINKS'),
  })[key];

const items = computed(() => {
  const list = data.value[tab.value] || [];
  const q = query.value.trim().toLowerCase();
  if (!q || tab.value === 'media') return list;
  return list.filter(i =>
    `${i.filename || ''} ${i.url || ''} ${i.title || ''} ${i.user_name || ''}`
      .toLowerCase()
      .includes(q)
  );
});
const showSearch = computed(
  () =>
    tab.value !== 'media' && (data.value[tab.value] || []).length > SEARCH_MIN
);

const isVideo = item => (item.content_type || '').startsWith('video/');
const docIcon = item => {
  const type = item.content_type || '';
  if (type.startsWith('audio/')) return 'i-lucide-audio-lines';
  if (type.includes('pdf')) return 'i-lucide-file-text';
  if (type.includes('sheet') || type.includes('excel') || type.includes('csv'))
    return 'i-lucide-file-spreadsheet';
  return 'i-lucide-file';
};
const dateOf = ts =>
  ts
    ? new Date(ts * 1000).toLocaleDateString('pt-BR', {
        day: '2-digit',
        month: '2-digit',
      })
    : '';
</script>

<template>
  <div>
    <p
      class="px-1 mb-1.5 text-[11px] font-semibold uppercase tracking-wider text-n-slate-10"
    >
      {{ t('INTERNAL_CHAT.SHARED_MEDIA.TITLE') }}
    </p>
    <div
      role="tablist"
      :aria-label="t('INTERNAL_CHAT.SHARED_MEDIA.TITLE')"
      class="flex items-center gap-0.5 p-0.5 mb-2 rounded-xl bg-n-alpha-2"
    >
      <button
        v-for="key in TABS"
        :key="key"
        type="button"
        role="tab"
        :aria-selected="tab === key"
        class="flex items-center justify-center flex-1 min-w-0 gap-1 px-1.5 py-1.5 text-xs font-semibold whitespace-nowrap transition-colors rounded-[10px] focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-teal-9"
        :class="
          tab === key
            ? 'bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-12 shadow-sm'
            : 'text-n-slate-11 hover:text-n-slate-12'
        "
        @click="
          tab = key;
          query = '';
        "
      >
        {{ labelFor(key) }}
        <span
          v-if="state === 'ready' && data[key].length"
          class="text-[10px] font-bold text-n-slate-10"
        >
          {{ data[key].length }}
        </span>
      </button>
    </div>

    <p
      v-if="state === 'loading'"
      class="flex items-center justify-center gap-2 px-3 py-4 mb-0 text-xs rounded-2xl bg-n-alpha-1 text-n-slate-11"
    >
      <span class="i-lucide-loader-circle animate-spin" />
      {{ t('INTERNAL_CHAT.LOADING') }}
    </p>
    <div
      v-else-if="state === 'error'"
      class="flex flex-col items-center gap-2 px-3 py-4 text-xs text-center rounded-2xl bg-n-alpha-1 text-n-slate-11"
    >
      {{ t('INTERNAL_CHAT.SHARED_MEDIA.ERROR') }}
      <button
        type="button"
        class="px-3 py-1 font-semibold rounded-lg text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
        @click="load"
      >
        {{ t('INTERNAL_CHAT.RETRY') }}
      </button>
    </div>
    <template v-else>
      <div v-if="showSearch" class="relative px-1 mb-1.5">
        <span
          class="absolute -translate-y-1/2 pointer-events-none i-lucide-search left-4 top-1/2 text-n-slate-10"
        />
        <input
          v-model="query"
          type="text"
          :placeholder="t('INTERNAL_CHAT.SHARED_MEDIA.SEARCH')"
          :aria-label="t('INTERNAL_CHAT.SHARED_MEDIA.SEARCH')"
          class="reset-base w-full h-9 pl-9 pr-3 text-sm border border-transparent outline-none rounded-xl bg-n-alpha-1 focus:border-n-teal-9 text-n-slate-12 placeholder:text-n-slate-10"
        />
      </div>
      <p
        v-if="!items.length"
        class="px-3 py-4 mb-0 text-xs text-center rounded-2xl bg-n-alpha-1 text-n-slate-10"
      >
        {{ query.trim() ? t('INTERNAL_CHAT.NO_RESULTS') : emptyFor(tab) }}
      </p>

      <!-- Mídia: grade de fotos e vídeos -->
      <div v-else-if="tab === 'media'" class="grid grid-cols-3 gap-1.5">
        <div
          v-for="item in items"
          :key="item.id"
          class="relative overflow-hidden rounded-xl aspect-square bg-n-alpha-2 group"
        >
          <a
            v-tooltip="t('INTERNAL_CHAT.SHARED_MEDIA.OPEN_FILE')"
            :href="item.url"
            target="_blank"
            rel="noopener noreferrer"
            class="block w-full h-full focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-n-teal-9"
            :aria-label="item.filename"
          >
            <video
              v-if="isVideo(item)"
              :src="item.url"
              preload="metadata"
              muted
              class="object-cover w-full h-full pointer-events-none"
            />
            <img
              v-else
              :src="item.url"
              :alt="item.filename"
              loading="lazy"
              class="object-cover w-full h-full"
            />
            <span
              v-if="isVideo(item)"
              class="absolute inset-0 flex items-center justify-center pointer-events-none"
            >
              <span
                class="inline-flex items-center justify-center text-white rounded-full size-8 bg-n-alpha-black1"
              >
                <span class="flex-shrink-0 i-lucide-play size-4" />
              </span>
            </span>
          </a>
          <button
            v-tooltip="t('INTERNAL_CHAT.SHARED_MEDIA.GO_TO_MESSAGE')"
            type="button"
            class="absolute inline-flex items-center justify-center transition-opacity rounded-full opacity-0 bottom-1 right-1 size-7 bg-n-solid-1 text-n-slate-12 shadow group-hover:opacity-100 focus-visible:opacity-100"
            :aria-label="t('INTERNAL_CHAT.SHARED_MEDIA.GO_TO_MESSAGE')"
            @click="emit('openMessage', item.message_id)"
          >
            <span class="flex-shrink-0 i-lucide-message-square-text size-4" />
          </button>
        </div>
      </div>

      <!-- Docs e links: lista -->
      <div v-else class="overflow-hidden rounded-2xl bg-n-alpha-1">
        <div
          v-for="item in items"
          :key="item.id || `${item.message_id}-${item.url}`"
          class="flex items-center gap-2 py-1.5 pl-3 pr-1.5 border-b last:border-b-0 border-n-weak"
        >
          <span
            class="flex-shrink-0 size-5 text-n-slate-10"
            :class="tab === 'docs' ? docIcon(item) : 'i-lucide-link'"
          />
          <a
            :href="item.url"
            target="_blank"
            rel="noopener noreferrer"
            class="flex flex-col flex-1 min-w-0 py-0.5 rounded-md hover:underline focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-teal-9"
          >
            <span
              class="text-sm truncate text-n-slate-12"
              :title="tab === 'docs' ? item.filename : item.url"
            >
              {{ tab === 'docs' ? item.filename : item.title || item.domain }}
            </span>
            <span class="text-[11px] truncate text-n-slate-10">
              {{ tab === 'links' ? `${item.domain} · ` : ''
              }}{{ item.user_name }} · {{ dateOf(item.created_at) }}
            </span>
          </a>
          <button
            v-tooltip="t('INTERNAL_CHAT.SHARED_MEDIA.GO_TO_MESSAGE')"
            type="button"
            class="inline-flex items-center justify-center flex-shrink-0 rounded-full size-8 text-n-slate-11 hover:bg-n-alpha-2 hover:text-n-slate-12 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-teal-9"
            :aria-label="t('INTERNAL_CHAT.SHARED_MEDIA.GO_TO_MESSAGE')"
            @click="emit('openMessage', item.message_id)"
          >
            <span class="flex-shrink-0 i-lucide-message-square-text size-4" />
          </button>
        </div>
      </div>
    </template>
  </div>
</template>
