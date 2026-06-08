import { defineStore, acceptHMRUpdate } from 'pinia';
import TeamsAPI from '../../api/teams';

// Espelho Pinia de store/modules/teamMembers.js (Onda 2 P0-05).
export const useTeamMembersStore = defineStore('teamMembers', {
  state: () => ({
    records: {},
    uiFlags: {
      isFetching: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    },
  }),

  getters: {
    getUIFlags: state => state.uiFlags,
    getTeamMembers: state => id => state.records[id] || [],
  },

  actions: {
    async get({ teamId }) {
      this.uiFlags.isFetching = true;
      try {
        const { data } = await TeamsAPI.getAgents({ teamId });
        this.records = { ...this.records, [teamId]: data };
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create({ agentsList, teamId }) {
      this.uiFlags.isCreating = true;
      try {
        const { data } = await TeamsAPI.addAgents({ agentsList, teamId });
        this.records = { ...this.records, [teamId]: data };
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async update({ agentsList, teamId }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await TeamsAPI.updateAgents({ agentsList, teamId });
        // response em Vuex original era passado direto sem teamId, manter compat
        if (response?.data && response?.teamId) {
          this.records = { ...this.records, [response.teamId]: response.data };
        }
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useTeamMembersStore, import.meta.hot));
}
