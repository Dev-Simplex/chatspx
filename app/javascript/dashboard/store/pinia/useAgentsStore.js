import { defineStore, acceptHMRUpdate } from 'pinia';
import AgentAPI from '../../api/agents';

// Espelho Pinia de store/modules/agents.js (Onda 1 P0-05).
export const useAgentsStore = defineStore('agents', {
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
    getAgents: state => state.records,
    getVerifiedAgents: state => state.records.filter(r => r.confirmed),
    getUIFlags: state => state.uiFlags,
    getAgentById: state => id =>
      state.records.find(r => r.id === Number(id)) || {},
    getAgentStatus: state => {
      const status = { online: 0, busy: 0, offline: 0 };
      state.records.forEach(agent => {
        const s = agent.availability_status || 'offline';
        if (s in status) status[s] += 1;
      });
      return status;
    },
  },

  actions: {
    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await AgentAPI.get();
        this.records = response.data;
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create(agentInfo) {
      this.uiFlags.isCreating = true;
      try {
        const response = await AgentAPI.create(agentInfo);
        this.records.push(response.data);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async update({ id, ...agentParams }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await AgentAPI.update(id, agentParams);
        const index = this.records.findIndex(r => r.id === response.data.id);
        if (index > -1) this.records.splice(index, 1, response.data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    updateSingleAgentPresence({ id, availabilityStatus }) {
      const index = this.records.findIndex(r => r.id === Number(id));
      if (index > -1) {
        this.records.splice(index, 1, {
          ...this.records[index],
          availability_status: availabilityStatus,
        });
      }
    },

    updatePresence(data) {
      this.records = this.records.map(element => ({
        ...element,
        availability_status: data[element.id] || 'offline',
      }));
    },

    async delete(agentId) {
      this.uiFlags.isDeleting = true;
      try {
        await AgentAPI.delete(agentId);
        this.records = this.records.filter(r => r.id !== agentId);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAgentsStore, import.meta.hot));
}
