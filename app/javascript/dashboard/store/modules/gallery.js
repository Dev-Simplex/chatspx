import GalleryAPI from '../../api/gallery';

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

const state = {
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
};

const getters = {
  getFilters: $state => $state.filters,
  getCurrentTab: $state => $state.filters.tab,
  getRecords: $state => tab => $state.records[tab] || [],
  getMeta: $state => tab => $state.meta[tab],
  getUIFlags: $state => $state.uiFlags,
  hasMore: $state => tab => {
    const meta = $state.meta[tab];
    return meta.currentPage > 0 && meta.currentPage < meta.totalPages;
  },
};

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

const fetchAttachmentsPage = async ($state, page, types) => {
  const { data } = await GalleryAPI.list({
    types,
    inboxId: $state.filters.inboxId,
    contactId: $state.filters.contactId,
    sort: $state.filters.sort,
    before: $state.filters.before,
    after: $state.filters.after,
    q: $state.filters.q,
    page,
  });
  return {
    items: (data.payload || []).map(normalizeAttachment),
    meta: data.meta,
  };
};

const fetchLinksPage = async ($state, page) => {
  const { data } = await GalleryAPI.links({
    inboxId: $state.filters.inboxId,
    contactId: $state.filters.contactId,
    q: $state.filters.q,
    page,
  });
  return {
    items: (data.payload || []).map(normalizeLink),
    meta: data.meta,
  };
};

const actions = {
  setFilter({ commit, dispatch }, partial) {
    commit('SET_FILTERS', partial);
    dispatch('refresh');
  },

  setTab({ commit, dispatch, state: $state }, tab) {
    if (!Object.values(TAB).includes(tab)) return;
    if ($state.filters.tab === tab && $state.records[tab].length) return;
    commit('SET_FILTERS', { tab });
    dispatch('refresh');
  },

  resetFilters({ commit, dispatch }) {
    commit('RESET_FILTERS');
    dispatch('refresh');
  },

  async refresh({ commit, state: $state }) {
    const { tab } = $state.filters;
    const cacheKey = buildKey($state.filters);
    commit('SET_CACHE_KEY', cacheKey);

    if ($state.cache.has(cacheKey)) {
      const cached = $state.cache.get(cacheKey);
      commit('SET_RECORDS', { tab, items: cached.items });
      commit('SET_META', { tab, meta: cached.meta });
      return;
    }

    commit('SET_UI_FLAG', { isFetching: true });
    try {
      let result;
      if (tab === TAB.LINKS) {
        result = await fetchLinksPage($state, 1);
      } else {
        result = await fetchAttachmentsPage($state, 1, TAB_TYPES[tab]);
      }
      commit('SET_RECORDS', { tab, items: result.items });
      commit('SET_META', { tab, meta: result.meta });
      commit('CACHE_PAGE', {
        key: cacheKey,
        items: result.items,
        meta: result.meta,
      });
    } catch (error) {
      commit('SET_RECORDS', { tab, items: [] });
    } finally {
      commit('SET_UI_FLAG', { isFetching: false });
    }
  },

  async fetchNextPage({ commit, state: $state }) {
    const { tab } = $state.filters;
    const meta = $state.meta[tab];
    if (!meta || meta.currentPage >= meta.totalPages) return;
    if ($state.uiFlags.isFetching || $state.uiFlags.isFetchingMore) return;

    commit('SET_UI_FLAG', { isFetchingMore: true });
    try {
      const nextPage = meta.currentPage + 1;
      const result =
        tab === TAB.LINKS
          ? await fetchLinksPage($state, nextPage)
          : await fetchAttachmentsPage($state, nextPage, TAB_TYPES[tab]);
      commit('APPEND_RECORDS', { tab, items: result.items });
      commit('SET_META', { tab, meta: result.meta });
      commit('CACHE_APPEND', {
        key: $state.cacheKey,
        items: result.items,
        meta: result.meta,
      });
    } catch (error) {
      // silent
    } finally {
      commit('SET_UI_FLAG', { isFetchingMore: false });
    }
  },
};

const mutations = {
  SET_FILTERS($state, partial) {
    $state.filters = { ...$state.filters, ...partial };
  },
  RESET_FILTERS($state) {
    $state.filters = initialFilters();
    $state.cache = new Map();
  },
  SET_RECORDS($state, { tab, items }) {
    $state.records[tab] = items;
  },
  APPEND_RECORDS($state, { tab, items }) {
    $state.records[tab] = [...$state.records[tab], ...items];
  },
  SET_META($state, { tab, meta }) {
    $state.meta[tab] = {
      currentPage: meta.current_page,
      totalPages: meta.total_pages,
      totalCount: meta.total_count,
    };
  },
  SET_UI_FLAG($state, flag) {
    $state.uiFlags = { ...$state.uiFlags, ...flag };
  },
  SET_CACHE_KEY($state, key) {
    $state.cacheKey = key;
  },
  CACHE_PAGE($state, { key, items, meta }) {
    $state.cache.set(key, {
      items: [...items],
      meta: {
        currentPage: meta.current_page,
        totalPages: meta.total_pages,
        totalCount: meta.total_count,
      },
    });
  },
  CACHE_APPEND($state, { key, items, meta }) {
    if (!$state.cache.has(key)) return;
    const existing = $state.cache.get(key);
    $state.cache.set(key, {
      items: [...existing.items, ...items],
      meta: {
        currentPage: meta.current_page,
        totalPages: meta.total_pages,
        totalCount: meta.total_count,
      },
    });
  },
};

export const GALLERY_TAB = TAB;
export const GALLERY_TAB_TYPES = TAB_TYPES;

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
