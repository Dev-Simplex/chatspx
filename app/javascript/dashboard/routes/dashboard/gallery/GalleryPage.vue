<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';

import GalleryTabs from './components/GalleryTabs.vue';
import GalleryFilters from './components/GalleryFilters.vue';
import GallerySelectToolbar from './components/GallerySelectToolbar.vue';
import MediaGrid from './components/MediaGrid.vue';
import DocumentList from './components/DocumentList.vue';
import LinkList from './components/LinkList.vue';
import MediaLightbox from './components/MediaLightbox.vue';
import MediaGridSkeleton from './components/MediaGridSkeleton.vue';
import DocumentListSkeleton from './components/DocumentListSkeleton.vue';
import LinkListSkeleton from './components/LinkListSkeleton.vue';
import { GALLERY_TAB_TYPES } from 'dashboard/store/modules/gallery';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

const filters = computed(() => store.getters['gallery/getFilters']);
const tab = computed(() => store.getters['gallery/getCurrentTab']);
const uiFlags = computed(() => store.getters['gallery/getUIFlags']);
const records = computed(() => store.getters['gallery/getRecords'](tab.value));
const meta = computed(() => store.getters['gallery/getMeta'](tab.value));
const hasMore = computed(() => store.getters['gallery/hasMore'](tab.value));

const searchInput = ref(filters.value.q || '');
const selection = ref(new Set());
// Modo "todos do filtro": baixa o conjunto inteiro que o filtro retorna no
// servidor (não só os registros carregados na tela). Reseta a cada mudança.
const selectAllFilter = ref(false);
const lightboxItem = ref(null);

let searchTimer = null;

const updateSearch = value => {
  searchInput.value = value;
  selectAllFilter.value = false;
  if (searchTimer) clearTimeout(searchTimer);
  searchTimer = setTimeout(() => {
    store.dispatch('gallery/setFilter', { q: value });
  }, 300);
};

const setTab = newTab => {
  selection.value = new Set();
  selectAllFilter.value = false;
  store.dispatch('gallery/setTab', newTab);
};

const setFilter = partial => {
  selectAllFilter.value = false;
  store.dispatch('gallery/setFilter', partial);
};

// Filtros atuais em snake_case para o backend (modo "todos do filtro").
const currentFilters = computed(() => {
  const f = filters.value;
  const types = GALLERY_TAB_TYPES[f.tab];
  return {
    type: types ? types.join(',') : undefined,
    inbox_id: f.inboxId || undefined,
    contact_id: f.contactId || undefined,
    before: f.before || undefined,
    after: f.after || undefined,
    q: f.q || undefined,
  };
});

const fetchMore = () => {
  if (hasMore.value && !uiFlags.value.isFetchingMore) {
    store.dispatch('gallery/fetchNextPage');
  }
};

const toggleSelect = id => {
  const next = new Set(selection.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  selection.value = next;
};

const clearSelection = () => {
  selection.value = new Set();
  selectAllFilter.value = false;
};

const selectAll = () => {
  selection.value = new Set(records.value.map(r => r.id));
  selectAllFilter.value = false;
};

// "Selecionar todos os N do filtro": mantém a seleção visível (toolbar segue
// montada) e marca o modo para o download enviar filtros em vez de IDs.
const enableSelectAllFilter = () => {
  selection.value = new Set(records.value.map(r => r.id));
  selectAllFilter.value = true;
};

const openLightbox = item => {
  lightboxItem.value = item;
};

const closeLightbox = () => {
  lightboxItem.value = null;
};

const openConversation = item => {
  if (!item?.conversation?.id) return;
  router.push({
    name: 'inbox_conversation',
    params: { conversation_id: item.conversation.id },
  });
};

onMounted(() => {
  store.dispatch('gallery/refresh');
});

watch(
  () => tab.value,
  () => {
    selection.value = new Set();
    selectAllFilter.value = false;
  }
);

const selectedItems = computed(() =>
  records.value.filter(r => selection.value.has(r.id))
);

// Nota: NÃO há botão global "Baixar todas (.zip)" no header. O download em massa
// na galeria é acionado exclusivamente pela seleção de cards (duplo-clique nas
// imagens / clique nos documentos) -> GallerySelectToolbar, que oferece tanto o
// ZIP da seleção quanto o "selecionar todos do filtro". A lógica de bulk download
// vive no GallerySelectToolbar (useBulkDownload), não aqui.

const emptyMeta = computed(() => {
  if (tab.value === 'documents') {
    return {
      icon: 'i-lucide-file-text',
      title: t('GALLERY.EMPTY.DOCUMENTS_TITLE'),
      hint: t('GALLERY.EMPTY.DOCUMENTS'),
    };
  }
  if (tab.value === 'links') {
    return {
      icon: 'i-lucide-link-2',
      title: t('GALLERY.EMPTY.LINKS_TITLE'),
      hint: t('GALLERY.EMPTY.LINKS'),
    };
  }
  return {
    icon: 'i-lucide-image-off',
    title: t('GALLERY.EMPTY.MEDIA_TITLE'),
    hint: t('GALLERY.EMPTY.MEDIA'),
  };
});
</script>

<template>
  <div
    class="flex flex-col h-full w-full bg-n-background dark:bg-n-solid-1 overflow-hidden"
  >
    <!-- Header espaçoso estilo Linear/Notion -->
    <header
      class="flex flex-col gap-5 px-8 lg:px-10 pt-8 pb-5 border-b border-n-weak flex-shrink-0"
    >
      <!-- Row 1: Título + tabs -->
      <div class="flex items-end justify-between gap-6 flex-wrap">
        <div class="flex flex-col gap-1">
          <h1
            class="text-2xl font-bold text-n-slate-12 m-0 leading-tight tracking-tight"
          >
            {{ t('GALLERY.TITLE') }}
          </h1>
          <p class="text-sm text-n-slate-10 m-0">
            {{ t('GALLERY.SUBTITLE') }}
            <span
              v-if="meta.totalCount"
              class="ltr:ml-2 rtl:mr-2 tabular-nums font-medium text-n-slate-11"
            >
              <span aria-hidden="true">&middot;</span>
              {{ t('GALLERY.TOTAL_COUNT', { count: meta.totalCount }) }}
            </span>
          </p>
        </div>
        <GalleryTabs :tab="tab" @change="setTab" />
      </div>

      <!-- Row 2: Search + filter chips -->
      <div class="flex items-center gap-3 flex-wrap">
        <div class="relative flex-1 min-w-[260px] h-11">
          <span
            class="i-lucide-search size-4 absolute top-1/2 -translate-y-1/2 ltr:left-4 rtl:right-4 text-n-slate-10 pointer-events-none z-10"
          />
          <input
            :value="searchInput"
            type="text"
            class="w-full !h-11 ltr:!pl-11 rtl:!pr-11 ltr:!pr-4 rtl:!pl-4 text-sm !rounded-xl !border !border-n-weak !bg-n-solid-1 dark:!bg-n-solid-2 !text-n-slate-12 placeholder:!text-n-slate-10 focus:!outline-none focus:!border-n-brand focus:!ring-2 focus:!ring-n-brand/20 transition-all !m-0"
            :placeholder="t('GALLERY.SEARCH_PLACEHOLDER')"
            @input="updateSearch($event.target.value)"
          />
        </div>
        <GalleryFilters :filters="filters" @change="setFilter" />
      </div>
    </header>

    <GallerySelectToolbar
      v-if="selection.size"
      :count="selection.size"
      :items="selectedItems"
      :total-count="meta.totalCount"
      :select-all-filter-active="selectAllFilter"
      :filters="currentFilters"
      @clear="clearSelection"
      @select-all="selectAll"
      @select-all-filter="enableSelectAllFilter"
    />

    <main
      :aria-busy="uiFlags.isFetching"
      class="flex-1 overflow-y-auto overflow-x-hidden min-h-0 px-6 sm:px-8 lg:px-10 pt-6 pb-10"
    >
      <!-- Loading inicial — skeleton por tab -->
      <MediaGridSkeleton
        v-if="uiFlags.isFetching && !records.length && tab === 'media'"
      />
      <DocumentListSkeleton
        v-else-if="uiFlags.isFetching && !records.length && tab === 'documents'"
      />
      <LinkListSkeleton
        v-else-if="uiFlags.isFetching && !records.length && tab === 'links'"
      />

      <!-- Empty state ilustrativo -->
      <div
        v-else-if="!records.length"
        class="flex flex-col items-center justify-center min-h-[400px] gap-4 text-center max-w-md mx-auto"
      >
        <div
          class="size-20 rounded-2xl bg-n-solid-2 dark:bg-n-solid-3 flex items-center justify-center"
        >
          <span :class="emptyMeta.icon" class="size-10 text-n-slate-10" />
        </div>
        <div class="flex flex-col gap-1.5">
          <h3 class="text-lg font-semibold text-n-slate-12 m-0">
            {{ emptyMeta.title }}
          </h3>
          <p class="text-sm text-n-slate-10 m-0">{{ emptyMeta.hint }}</p>
        </div>
      </div>

      <MediaGrid
        v-else-if="tab === 'media'"
        :items="records"
        :selected-ids="selection"
        :selection-active="selection.size > 0"
        :is-loading-more="uiFlags.isFetchingMore"
        :has-more="hasMore"
        @toggle-select="toggleSelect"
        @open="openLightbox"
        @open-conversation="openConversation"
        @load-more="fetchMore"
      />

      <DocumentList
        v-else-if="tab === 'documents'"
        :items="records"
        :selected-ids="selection"
        :selection-active="selection.size > 0"
        :is-loading-more="uiFlags.isFetchingMore"
        :has-more="hasMore"
        @toggle-select="toggleSelect"
        @open-conversation="openConversation"
        @load-more="fetchMore"
      />

      <LinkList
        v-else
        :items="records"
        :is-loading-more="uiFlags.isFetchingMore"
        :has-more="hasMore"
        @open-conversation="openConversation"
        @load-more="fetchMore"
      />
    </main>

    <MediaLightbox
      v-if="lightboxItem"
      :item="lightboxItem"
      @close="closeLightbox"
      @open-conversation="openConversation"
    />
  </div>
</template>
