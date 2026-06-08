import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import AttributeAPI from '../../api/attributes';

// Espelho Pinia de store/modules/attributes.js (Onda 2 P0-05).
export const useAttributesStore = defineStore('attributes', {
  state: () => ({
    records: [],
    uiFlags: {
      isFetching: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    },
  }),

  getters: {
    getUIFlags: state => state.uiFlags,
    getAttributes: state => state.records,
    getConversationAttributes: state =>
      state.records
        .filter(r => r.attribute_model === 'conversation_attribute')
        .map(camelcaseKeys),
    getContactAttributes: state =>
      state.records
        .filter(r => r.attribute_model === 'contact_attribute')
        .map(camelcaseKeys),
    getAttributesByModel: state => attributeModel =>
      state.records.filter(r => r.attribute_model === attributeModel),
  },

  actions: {
    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await AttributeAPI.getAttributesByModel();
        this.records = response.data;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create(attributeObj) {
      this.uiFlags.isCreating = true;
      try {
        const response = await AttributeAPI.create(attributeObj);
        this.records.push(response.data);
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        throw new Error(errorMessage);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async update({ id, ...updateObj }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await AttributeAPI.update(id, updateObj);
        const index = this.records.findIndex(r => r.id === response.data.id);
        if (index > -1) this.records.splice(index, 1, response.data);
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        throw new Error(errorMessage);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete(id) {
      this.uiFlags.isDeleting = true;
      try {
        await AttributeAPI.delete(id);
        this.records = this.records.filter(r => r.id !== id);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAttributesStore, import.meta.hot));
}
