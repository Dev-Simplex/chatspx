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
    const { count, current_page: currentPage } = data;
    $state.meta.count = count;
    $state.meta.currentPage = currentPage;
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
    $state.records[data.id] = normalizeContact(data);
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
