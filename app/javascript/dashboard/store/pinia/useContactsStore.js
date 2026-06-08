/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import ContactAPI from '../../api/contacts';
import AccountActionsAPI from '../../api/accountActions';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { CONTACTS_EVENTS } from '../../helper/AnalyticsHelper/events';

// Espelho Pinia de store/modules/contacts/* (Onda 2 P0-05).
const normalizeContact = contact =>
  camelcaseKeys(contact, { deep: true, stopPaths: ['custom_attributes'] });

const buildContactFormData = contactParams => {
  const formData = new FormData();
  const { additional_attributes = {}, ...contactProperties } = contactParams;
  Object.keys(contactProperties).forEach(key => {
    if (contactProperties[key]) {
      formData.append(key, contactProperties[key]);
    }
  });
  const { social_profiles = {}, ...additionalAttributesProperties } =
    additional_attributes;
  Object.keys(additionalAttributesProperties).forEach(key => {
    formData.append(
      `additional_attributes[${key}]`,
      additionalAttributesProperties[key]
    );
  });
  Object.keys(social_profiles).forEach(key => {
    formData.append(
      `additional_attributes[social_profiles][${key}]`,
      social_profiles[key]
    );
  });
  return formData;
};

const handleContactOperationErrors = error => {
  const responseMessage = error.response?.data?.message;
  const responseAttributes = error.response?.data?.attributes;
  if (error.response?.status === 422) {
    if (responseAttributes)
      throw new DuplicateContactException(responseAttributes);
    if (responseMessage) throw new ExceptionWithMessage(responseMessage);
    throw new Error(error);
  }
  if (responseMessage) throw new ExceptionWithMessage(responseMessage);
  throw new Error(error);
};

export const useContactsStore = defineStore('contacts', {
  state: () => ({
    meta: { count: 0, currentPage: 1, hasMore: false },
    records: {},
    uiFlags: {
      isFetching: false,
      isFetchingItem: false,
      isFetchingInboxes: false,
      isUpdating: false,
      isMerging: false,
      isDeleting: false,
      isExporting: false,
      isImporting: false,
      isInitiatingCall: false,
    },
    sortOrder: [],
    appliedFilters: [],
  }),

  getters: {
    getContacts: state => state.sortOrder.map(id => state.records[id]),
    getContactsList: state => state.sortOrder.map(id => state.records[id]),
    getUIFlags: state => state.uiFlags,
    getContact: state => id => state.records[id] || {},
    getContactById: state => id => state.records[id] || {},
    getMeta: state => state.meta,
    getAppliedContactFilters: state => state.appliedFilters,
    getAppliedContactFiltersV4: state => state.appliedFilters,
  },

  actions: {
    _clearContacts() {
      this.records = {};
      this.sortOrder = [];
    },

    _setMeta(data) {
      const { count, current_page: currentPage, has_more: hasMore } = data;
      this.meta.count = count;
      this.meta.currentPage = currentPage;
      if (hasMore !== undefined) this.meta.hasMore = hasMore;
    },

    _appendContacts(data) {
      data.forEach(contact => {
        const normalized = normalizeContact(contact);
        this.records[normalized.id] = {
          ...(this.records[normalized.id] || {}),
          ...normalized,
        };
        if (!this.sortOrder.includes(normalized.id)) {
          this.sortOrder.push(normalized.id);
        }
      });
    },

    _setContacts(data) {
      this.sortOrder = data.map(contact => {
        const normalized = normalizeContact(contact);
        this.records[normalized.id] = {
          ...(this.records[normalized.id] || {}),
          ...normalized,
        };
        return normalized.id;
      });
    },

    _setContactItem(data) {
      const normalized = normalizeContact(data);
      this.records[normalized.id] = {
        ...(this.records[normalized.id] || {}),
        ...normalized,
      };
      if (!this.sortOrder.includes(normalized.id)) {
        this.sortOrder.push(normalized.id);
      }
    },

    _editContact(data) {
      this.records[data.id] = normalizeContact(data);
    },

    _deleteContact(id) {
      const idx = this.sortOrder.findIndex(item => item === id);
      if (idx !== -1) this.sortOrder.splice(idx, 1);
      delete this.records[id];
    },

    async search({ search, page, sortAttr, label, append = false }) {
      this.uiFlags.isFetching = true;
      try {
        const {
          data: { payload, meta },
        } = await ContactAPI.search(search, page, sortAttr, label);
        if (!append) this._clearContacts();
        if (append) this._appendContacts(payload);
        else this._setContacts(payload);
        this._setMeta(meta);
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async get({ page = 1, sortAttr, label } = {}) {
      this.uiFlags.isFetching = true;
      try {
        const {
          data: { payload, meta },
        } = await ContactAPI.get(page, sortAttr, label);
        this._clearContacts();
        this._setContacts(payload);
        this._setMeta(meta);
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async active({ page = 1, sortAttr } = {}) {
      this.uiFlags.isFetching = true;
      try {
        const {
          data: { payload, meta },
        } = await ContactAPI.active(page, sortAttr);
        this._clearContacts();
        this._setContacts(payload);
        this._setMeta(meta);
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async show({ id }) {
      this.uiFlags.isFetchingItem = true;
      try {
        const response = await ContactAPI.show(id);
        this._setContactItem(response.data.payload);
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetchingItem = false;
      }
    },

    async update({ id, isFormData = false, ...contactParams }) {
      const { avatar, customAttributes, ...paramsToDecamelize } = contactParams;
      const decamelizedContactParams = {
        ...snakecaseKeys(paramsToDecamelize, { deep: true }),
        ...(customAttributes && { custom_attributes: customAttributes }),
        ...(avatar && { avatar }),
      };
      this.uiFlags.isUpdating = true;
      try {
        const response = await ContactAPI.update(
          id,
          isFormData
            ? buildContactFormData(decamelizedContactParams)
            : decamelizedContactParams
        );
        this._editContact(response.data.payload);
      } catch (error) {
        handleContactOperationErrors(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async create({ isFormData = false, ...contactParams }) {
      const decamelizedContactParams = snakecaseKeys(contactParams, {
        deep: true,
      });
      this.uiFlags.isCreating = true;
      try {
        const response = await ContactAPI.create(
          isFormData
            ? buildContactFormData(decamelizedContactParams)
            : decamelizedContactParams
        );
        AnalyticsHelper.track(CONTACTS_EVENTS.CREATE_CONTACT);
        this._setContactItem(response.data.payload.contact);
        return response.data.payload.contact;
      } catch (error) {
        return handleContactOperationErrors(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async import(file) {
      this.uiFlags.isImporting = true;
      try {
        await ContactAPI.importContacts(file);
      } catch (error) {
        if (error.response?.data?.message) {
          throw new ExceptionWithMessage(error.response.data.message);
        }
      } finally {
        this.uiFlags.isImporting = false;
      }
    },

    async export({ payload, label }) {
      this.uiFlags.isExporting = true;
      try {
        await ContactAPI.exportContacts({ payload, label });
      } catch (error) {
        if (error.response?.data?.message) {
          throw new Error(error.response.data.message);
        }
        throw new Error(error);
      } finally {
        this.uiFlags.isExporting = false;
      }
    },

    async delete(id) {
      this.uiFlags.isDeleting = true;
      try {
        await ContactAPI.delete(id);
      } catch (error) {
        if (error.response?.data?.message) {
          throw new Error(error.response.data.message);
        }
        throw new Error(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    async deleteCustomAttributes({ id, customAttributes }) {
      try {
        const response = await ContactAPI.destroyCustomAttributes(
          id,
          customAttributes
        );
        this._editContact(response.data.payload);
      } catch (error) {
        throw new Error(error);
      }
    },

    async deleteAvatar(id) {
      try {
        const response = await ContactAPI.destroyAvatar(id);
        this._editContact(response.data.payload);
      } catch (error) {
        throw new Error(error);
      }
    },

    async fetchContactableInbox(id) {
      this.uiFlags.isFetchingInboxes = true;
      try {
        const response = await ContactAPI.getContactableInboxes(id);
        this._setContactItem({
          id: Number(id),
          contact_inboxes: response.data.payload,
        });
      } catch (error) {
        if (error.response?.data?.message) {
          throw new ExceptionWithMessage(error.response.data.message);
        }
        throw new Error(error);
      } finally {
        this.uiFlags.isFetchingInboxes = false;
      }
    },

    updatePresence(data) {
      Object.keys(data).forEach(contactId => {
        if (this.records[contactId]) {
          this.records[contactId] = {
            ...this.records[contactId],
            availability_status: data[contactId] || null,
          };
        }
      });
    },

    setContact(data) {
      this._setContactItem(data);
    },

    async merge({ childId, parentId }) {
      this.uiFlags.isMerging = true;
      try {
        const response = await AccountActionsAPI.merge(parentId, childId);
        this._setContactItem(response.data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isMerging = false;
      }
    },

    deleteContactThroughConversations(id) {
      this._deleteContact(id);
    },

    async updateContact(updateObj) {
      this.uiFlags.isUpdating = true;
      try {
        this._editContact(updateObj);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async filter({ page = 1, sortAttr, queryPayload, resetState = true } = {}) {
      this.uiFlags.isFetching = true;
      try {
        const {
          data: { payload, meta },
        } = await ContactAPI.filter(page, sortAttr, queryPayload);
        if (resetState) {
          this._clearContacts();
          this._setContacts(payload);
          this._setMeta(meta);
          this.uiFlags.isFetching = false;
        }
        return payload;
      } catch (error) {
        this.uiFlags.isFetching = false;
      }
      return [];
    },

    setContactFilters(data) {
      this.appliedFilters = data.map(filter => camelcaseKeys(filter));
    },

    clearContactFilters() {
      this.appliedFilters = [];
    },

    async initiateCall({ contactId, inboxId }) {
      this.uiFlags.isInitiatingCall = true;
      try {
        const response = await ContactAPI.initiateCall(contactId, inboxId);
        return response.data;
      } catch (error) {
        if (error.response?.data?.message) {
          throw new ExceptionWithMessage(error.response.data.message);
        } else if (error.response?.data?.error) {
          throw new ExceptionWithMessage(error.response.data.error);
        } else {
          throw new Error(error);
        }
      } finally {
        this.uiFlags.isInitiatingCall = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useContactsStore, import.meta.hot));
}
