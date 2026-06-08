/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import AssignmentPoliciesAPI from '../../api/assignmentPolicies';
import { throwErrorMessage } from '../utils/api';

// Espelho Pinia de store/modules/assignmentPolicies.js (Onda 2 P0-05).
export const useAssignmentPoliciesStore = defineStore('assignmentPolicies', {
  state: () => ({
    records: [],
    uiFlags: {
      isFetching: false,
      isFetchingItem: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    },
    inboxUiFlags: {
      isFetching: false,
      isDeleting: false,
    },
  }),

  getters: {
    getAssignmentPolicies: state => state.records,
    getUIFlags: state => state.uiFlags,
    getInboxUiFlags: state => state.inboxUiFlags,
    getAssignmentPolicyById: state => id =>
      state.records.find(r => r.id === Number(id)) || {},
  },

  actions: {
    _upsert(data) {
      const idx = this.records.findIndex(r => r.id === data.id);
      if (idx > -1) this.records.splice(idx, 1, data);
      else this.records.push(data);
    },

    _updateAttributes(data) {
      const idx = this.records.findIndex(r => r.id === data.id);
      if (idx > -1) {
        this.records.splice(idx, 1, { ...this.records[idx], ...data });
      }
    },

    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await AssignmentPoliciesAPI.get();
        this.records = camelcaseKeys(response.data);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async show(policyId) {
      this.uiFlags.isFetchingItem = true;
      try {
        const response = await AssignmentPoliciesAPI.show(policyId);
        this._upsert(camelcaseKeys(response.data));
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isFetchingItem = false;
      }
    },

    async create(policyObj) {
      this.uiFlags.isCreating = true;
      try {
        const response = await AssignmentPoliciesAPI.create(
          snakecaseKeys(policyObj)
        );
        this.records.push(camelcaseKeys(response.data));
        return response.data;
      } catch (error) {
        throwErrorMessage(error);
        throw error;
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async update({ id, ...policyParams }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await AssignmentPoliciesAPI.update(
          id,
          snakecaseKeys(policyParams)
        );
        this._updateAttributes(camelcaseKeys(response.data));
        return response.data;
      } catch (error) {
        throwErrorMessage(error);
        throw error;
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete(policyId) {
      this.uiFlags.isDeleting = true;
      try {
        await AssignmentPoliciesAPI.delete(policyId);
        this.records = this.records.filter(r => r.id !== policyId);
      } catch (error) {
        throwErrorMessage(error);
        throw error;
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    async getInboxes(policyId) {
      this.inboxUiFlags.isFetching = true;
      try {
        const response = await AssignmentPoliciesAPI.getInboxes(policyId);
        const policy = this.records.find(p => p.id === policyId);
        if (policy) policy.inboxes = camelcaseKeys(response.data.inboxes);
      } catch (error) {
        throwErrorMessage(error);
        throw error;
      } finally {
        this.inboxUiFlags.isFetching = false;
      }
    },

    async setInboxPolicy({ inboxId, policyId }) {
      try {
        const response = await AssignmentPoliciesAPI.setInboxPolicy(
          inboxId,
          policyId
        );
        this._updateAttributes(camelcaseKeys(response.data));
        return response.data;
      } catch (error) {
        throwErrorMessage(error);
        throw error;
      }
    },

    async getInboxPolicy({ inboxId }) {
      try {
        const response = await AssignmentPoliciesAPI.getInboxPolicy(inboxId);
        return camelcaseKeys(response.data);
      } catch (error) {
        throwErrorMessage(error);
        throw error;
      }
    },

    async updateInboxPolicy({ policy }) {
      try {
        this._updateAttributes(policy);
      } catch (error) {
        throwErrorMessage(error);
        throw error;
      }
    },

    async removeInboxPolicy({ policyId, inboxId }) {
      this.inboxUiFlags.isDeleting = true;
      try {
        await AssignmentPoliciesAPI.removeInboxPolicy(inboxId);
        const policy = this.records.find(p => p.id === policyId);
        if (policy) {
          policy.inboxes = policy?.inboxes?.filter(i => i.id !== inboxId);
        }
      } catch (error) {
        throwErrorMessage(error);
        throw error;
      } finally {
        this.inboxUiFlags.isDeleting = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useAssignmentPoliciesStore, import.meta.hot)
  );
}
