export const getters = {
  getContacts($state) {
    return $state.sortOrder.map(contactId => $state.records[contactId]);
  },
  getContactsList($state) {
    return $state.sortOrder.map(contactId => $state.records[contactId]);
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getContact: $state => id => {
    const contact = $state.records[id];
    return contact || {};
  },
  getContactById: $state => id => {
    const contact = $state.records[id];
    return contact || {};
  },
  getContactAttachments: $state => id => $state.records[id]?.attachments || [],
  getMeta: $state => {
    return $state.meta;
  },
  getAppliedContactFilters: _state => {
    return _state.appliedFilters;
  },
  getAppliedContactFiltersV4: _state => {
    return _state.appliedFilters;
  },
};
