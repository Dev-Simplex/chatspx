import types from '../../mutation-types';
import camelcaseKeys from 'camelcase-keys';

const normalizeContact = contact =>
  camelcaseKeys(contact, { deep: true, stopPaths: ['custom_attributes'] });

export const mutations = {
  [types.SET_CONTACT_UI_FLAG]($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },

  [types.CLEAR_CONTACTS]: $state => {
    $state.records = {};
    $state.sortOrder = [];
  },

  [types.SET_CONTACT_META]: ($state, data) => {
    const { count, current_page: currentPage, has_more: hasMore } = data;
    $state.meta.count = count;
    $state.meta.currentPage = currentPage;
    if (hasMore !== undefined) {
      $state.meta.hasMore = hasMore;
    }
  },

  [types.APPEND_CONTACTS]: ($state, data) => {
    data.forEach(contact => {
      const normalized = normalizeContact(contact);
      $state.records[normalized.id] = {
        ...($state.records[normalized.id] || {}),
        ...normalized,
      };
      if (!$state.sortOrder.includes(normalized.id)) {
        $state.sortOrder.push(normalized.id);
      }
    });
  },

  [types.SET_CONTACTS]: ($state, data) => {
    const sortOrder = data.map(contact => {
      const normalized = normalizeContact(contact);
      $state.records[normalized.id] = {
        ...($state.records[normalized.id] || {}),
        ...normalized,
      };
      return normalized.id;
    });
    $state.sortOrder = sortOrder;
  },

  [types.SET_CONTACT_ITEM]: ($state, data) => {
    const normalized = normalizeContact(data);
    $state.records[normalized.id] = {
      ...($state.records[normalized.id] || {}),
      ...normalized,
    };

    if (!$state.sortOrder.includes(normalized.id)) {
      $state.sortOrder.push(normalized.id);
    }
  },

  [types.EDIT_CONTACT]: ($state, data) => {
    const existingAttachments = $state.records[data.id]?.attachments;
    const normalizedContact = normalizeContact(data);
    $state.records[data.id] = existingAttachments
      ? { ...normalizedContact, attachments: existingAttachments }
      : normalizedContact;
  },

  [types.SET_CONTACT_ATTACHMENTS]: ($state, { id, data }) => {
    if (!$state.records[id]) $state.records[id] = {};
    $state.records[id].attachments = data;
  },

  [types.DELETE_CONTACT]: ($state, id) => {
    const index = $state.sortOrder.findIndex(item => item === id);
    $state.sortOrder.splice(index, 1);
    delete $state.records[id];
  },

  [types.UPDATE_CONTACTS_PRESENCE]: ($state, data) => {
    Object.keys(data).forEach(contactId => {
      if ($state.records[contactId]) {
        $state.records[contactId] = {
          ...$state.records[contactId],
          availability_status: data[contactId] || null,
        };
      }
    });
  },

  [types.SET_CONTACT_FILTERS](_state, data) {
    _state.appliedFilters = data.map(filter => camelcaseKeys(filter));
  },

  [types.CLEAR_CONTACT_FILTERS](_state) {
    _state.appliedFilters = [];
  },
};
