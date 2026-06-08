import { defineStore, acceptHMRUpdate } from 'pinia';
import GalleryAPI from '../../api/gallery';

// Espelho Pinia de store/modules/gallery.js (Onda 3 P0-05).
// Estrategia: state + getters + actions diretos; mutations fundidas em this.*

const TAB = {
  MEDIA: 'media',
  DOCUMENTS: 'documents',
  LINKS: 'links',
};

const TAB_TYPES = {
  [TAB.MEDIA]: ['image', 'video', 'ig_reel'],
  [TAB.DOCUMENTS]: ['file', 'audio'],
};

const initialFilters = () => ({
  tab: TAB.MEDIA,
  q: '',
  inboxId: null,
  contactId: null,
  sort: 'date_desc',
  before: null,
  after: null,
});

const buildKey = filters =>
  [
    filters.tab,
    filters.q || '',
    filters.inboxId || '',
    filters.contactId || '',
    filters.sort,
    filters.before || '',
    filters.after || '',
  ].join('|');

const normalizeAttachment = item => ({
  type: 'attachment',
  id: item.id,
  fileType: item.file_type,
  thumbUrl: item.thumb_url,
  dataUrl: item.data_url,
  fileSize: item.file_size,
  extension: item.extension,
  width: item.width,
  height: item.height,
  filename: item.filename,
  createdAt: item.created_at,
  messageId: item.message_id,
  conversation: item.conversation,
  sender: item.sender,
});

const normalizeLink = item => ({
  type: 'link',
  id: item.id,
  content: item.content,
  urls: item.urls || [],
  createdAt: item.created_at,
  conversation: item.conversation,
  sender: item.sender,
});

const fetchAttachmentsPage = async (filters, page, types) => {
  const { data } = await GalleryAPI.list({
    types,
    inboxId: filters.inboxId,
    contactId: filters.contactId,
    sort: filters.sort,
    before: filters.before,
    after: filters.after,
    q: filters.q,
    page,
  });
  return {
    items: (data.payload || []).map(normalizeAttachment),
    meta: data.meta,
  };
};

const fetchLinksPage = async (filters, page) => {
  const { data } = await GalleryAPI.links({
    inboxId: filters.inboxId,
    contactId: filters.contactId,
    q: filters.q,
    page,
  });
  return {
    items: (data.payload || []).map(normalizeLink),
    meta: data.meta,
  };
};

const normalizeMeta = meta => ({
  currentPage: meta.current_page,
  totalPages: meta.total_pages,
  totalCount: meta.total_count,
});

export const useGalleryStore = defineStore('gallery', {
  state: () => ({
    filters: initialFilters(),
    records: {
      [TAB.MEDIA]: [],
      [TAB.DOCUMENTS]: [],
      [TAB.LINKS]: [],
    },
    meta: {
      [TAB.MEDIA]: { currentPage: 0, totalPages: 0, totalCount: 0 },
      [TAB.DOCUMENTS]: { currentPage: 0, totalPages: 0, totalCount: 0 },
      [TAB.LINKS]: { currentPage: 0, totalPages: 0, totalCount: 0 },
    },
    uiFlags: {
      isFetching: false,
      isFetchingMore: false,
    },
    cache: new Map(),
    cacheKey: null,
  }),

  getters: {
    getFilters: state => state.filters,
    getCurrentTab: state => state.filters.tab,
    getRecords: state => tab => state.records[tab] || [],
    getMeta: state => tab => state.meta[tab],
    getUIFlags: state => state.uiFlags,
    hasMore: state => tab => {
      const meta = state.meta[tab];
      return meta.currentPage > 0 && meta.currentPage < meta.totalPages;
    },
  },

  actions: {
    setFilter(partial) {
      this.filters = { ...this.filters, ...partial };
      this.refresh();
    },

    setTab(tab) {
      if (!Object.values(TAB).includes(tab)) return;
      if (this.filters.tab === tab && this.records[tab].length) return;
      this.filters = { ...this.filters, tab };
      this.refresh();
    },

    resetFilters() {
      this.filters = initialFilters();
      this.cache = new Map();
      this.refresh();
    },

    async refresh() {
      const { tab } = this.filters;
      const cacheKey = buildKey(this.filters);
      this.cacheKey = cacheKey;

      if (this.cache.has(cacheKey)) {
        const cached = this.cache.get(cacheKey);
        this.records[tab] = cached.items;
        this.meta[tab] = cached.meta;
        return;
      }

      this.uiFlags = { ...this.uiFlags, isFetching: true };
      try {
        const result =
          tab === TAB.LINKS
            ? await fetchLinksPage(this.filters, 1)
            : await fetchAttachmentsPage(this.filters, 1, TAB_TYPES[tab]);

        this.records[tab] = result.items;
        this.meta[tab] = normalizeMeta(result.meta);
        this.cache.set(cacheKey, {
          items: [...result.items],
          meta: normalizeMeta(result.meta),
        });
      } catch (error) {
        this.records[tab] = [];
      } finally {
        this.uiFlags = { ...this.uiFlags, isFetching: false };
      }
    },

    async fetchNextPage() {
      const { tab } = this.filters;
      const meta = this.meta[tab];
      if (!meta || meta.currentPage >= meta.totalPages) return;
      if (this.uiFlags.isFetching || this.uiFlags.isFetchingMore) return;

      this.uiFlags = { ...this.uiFlags, isFetchingMore: true };
      try {
        const nextPage = meta.currentPage + 1;
        const result =
          tab === TAB.LINKS
            ? await fetchLinksPage(this.filters, nextPage)
            : await fetchAttachmentsPage(
                this.filters,
                nextPage,
                TAB_TYPES[tab]
              );

        this.records[tab] = [...this.records[tab], ...result.items];
        this.meta[tab] = normalizeMeta(result.meta);
        if (this.cache.has(this.cacheKey)) {
          const existing = this.cache.get(this.cacheKey);
          this.cache.set(this.cacheKey, {
            items: [...existing.items, ...result.items],
            meta: normalizeMeta(result.meta),
          });
        }
      } catch (error) {
        // silent
      } finally {
        this.uiFlags = { ...this.uiFlags, isFetchingMore: false };
      }
    },
  },
});

export const GALLERY_TAB = TAB;

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useGalleryStore, import.meta.hot));
}
