/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import snakecaseKeys from 'snakecase-keys';
import AgentCapacityPoliciesAPI from '../../api/agentCapacityPolicies';
import { throwErrorMessage } from '../utils/api';

// Espelho Pinia de store/modules/agentCapacityPolicies.js (Onda 2 P0-05).
export const useAgentCapacityPoliciesStore = defineStore(
  'agentCapacityPolicies',
  {
    state: () => ({
      records: [],
      uiFlags: {
        isFetching: false,
        isFetchingItem: false,
        isCreating: false,
        isUpdating: false,
        isDeleting: false,
      },
      usersUiFlags: {
        isFetching: false,
        isDeleting: false,
      },
    }),

    getters: {
      getAgentCapacityPolicies: state => state.records,
      getUIFlags: state => state.uiFlags,
      getUsersUIFlags: state => state.usersUiFlags,
      getAgentCapacityPolicyById: state => id =>
        state.records.find(r => r.id === Number(id)) || {},
    },

    actions: {
      _upsert(data) {
        const idx = this.records.findIndex(r => r.id === data.id);
        if (idx > -1) this.records.splice(idx, 1, data);
        else this.records.push(data);
      },

      async get() {
        this.uiFlags.isFetching = true;
        try {
          const response = await AgentCapacityPoliciesAPI.get();
          this.records = camelcaseKeys(response.data, { deep: true });
        } catch (error) {
          throwErrorMessage(error);
        } finally {
          this.uiFlags.isFetching = false;
        }
      },

      async show(policyId) {
        this.uiFlags.isFetchingItem = true;
        try {
          const response = await AgentCapacityPoliciesAPI.show(policyId);
          this._upsert(camelcaseKeys(response.data, { deep: true }));
        } catch (error) {
          throwErrorMessage(error);
        } finally {
          this.uiFlags.isFetchingItem = false;
        }
      },

      async create(policyObj) {
        this.uiFlags.isCreating = true;
        try {
          const response = await AgentCapacityPoliciesAPI.create(
            snakecaseKeys(policyObj)
          );
          this.records.push(camelcaseKeys(response.data, { deep: true }));
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
          const response = await AgentCapacityPoliciesAPI.update(
            id,
            snakecaseKeys(policyParams)
          );
          const data = camelcaseKeys(response.data, { deep: true });
          const idx = this.records.findIndex(r => r.id === data.id);
          if (idx > -1) {
            this.records.splice(idx, 1, { ...this.records[idx], ...data });
          }
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
          await AgentCapacityPoliciesAPI.delete(policyId);
          this.records = this.records.filter(r => r.id !== policyId);
        } catch (error) {
          throwErrorMessage(error);
          throw error;
        } finally {
          this.uiFlags.isDeleting = false;
        }
      },

      async getUsers(policyId) {
        this.usersUiFlags.isFetching = true;
        try {
          const response = await AgentCapacityPoliciesAPI.getUsers(policyId);
          const users = camelcaseKeys(response.data);
          const policy = this.records.find(p => p.id === policyId);
          if (policy) policy.users = users;
          return response.data;
        } catch (error) {
          throwErrorMessage(error);
          throw error;
        } finally {
          this.usersUiFlags.isFetching = false;
        }
      },

      async addUser({ policyId, userData }) {
        try {
          const response = await AgentCapacityPoliciesAPI.addUser(
            policyId,
            userData
          );
          const user = camelcaseKeys(response.data);
          const policy = this.records.find(p => p.id === policyId);
          if (policy) {
            policy.users = policy.users || [];
            policy.users.push(user);
            policy.assignedAgentCount = policy.users.length;
          }
          return response.data;
        } catch (error) {
          throwErrorMessage(error);
          throw error;
        }
      },

      async removeUser({ policyId, userId }) {
        this.usersUiFlags.isDeleting = true;
        try {
          await AgentCapacityPoliciesAPI.removeUser(policyId, userId);
          const policy = this.records.find(p => p.id === policyId);
          if (policy) {
            policy.users = (policy.users || []).filter(u => u.id !== userId);
            policy.assignedAgentCount = policy.users.length;
          }
        } catch (error) {
          throwErrorMessage(error);
          throw error;
        } finally {
          this.usersUiFlags.isDeleting = false;
        }
      },

      async createInboxLimit({ policyId, limitData }) {
        try {
          const response = await AgentCapacityPoliciesAPI.createInboxLimit(
            policyId,
            limitData
          );
          const data = camelcaseKeys(response.data);
          const policy = this.records.find(
            p => p.id === data.agentCapacityPolicyId
          );
          policy?.inboxCapacityLimits.push({
            id: data.id,
            inboxId: data.inboxId,
            conversationLimit: data.conversationLimit,
          });
          return response.data;
        } catch (error) {
          throwErrorMessage(error);
          throw error;
        }
      },

      async updateInboxLimit({ policyId, limitId, limitData }) {
        try {
          const response = await AgentCapacityPoliciesAPI.updateInboxLimit(
            policyId,
            limitId,
            limitData
          );
          const data = camelcaseKeys(response.data);
          const policy = this.records.find(
            p => p.id === data.agentCapacityPolicyId
          );
          const limit = policy?.inboxCapacityLimits.find(l => l.id === data.id);
          if (limit)
            Object.assign(limit, { conversationLimit: data.conversationLimit });
          return response.data;
        } catch (error) {
          throwErrorMessage(error);
          throw error;
        }
      },

      async deleteInboxLimit({ policyId, limitId }) {
        try {
          await AgentCapacityPoliciesAPI.deleteInboxLimit(policyId, limitId);
          const policy = this.records.find(p => p.id === policyId);
          if (policy) {
            policy.inboxCapacityLimits = policy.inboxCapacityLimits.filter(
              l => l.id !== limitId
            );
          }
        } catch (error) {
          throwErrorMessage(error);
          throw error;
        }
      },
    },
  }
);

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useAgentCapacityPoliciesStore, import.meta.hot)
  );
}
