import { defineStore, acceptHMRUpdate } from 'pinia';
import TeamsAPI from '../../api/teams';

// Espelho Pinia de store/modules/teams/ (Onda 1 P0-05).
// Agrega actions/getters/mutations/types do diretorio teams/.
export const useTeamsStore = defineStore('teams', {
  state: () => ({
    meta: {},
    records: {},
    uiFlags: {
      isFetching: false,
      isFetchingItem: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    },
  }),

  getters: {
    getTeams: state => Object.values(state.records).sort((a, b) => a.id - b.id),
    getMyTeams() {
      return this.getTeams.filter(team => team.is_member);
    },
    getUIFlags: state => state.uiFlags,
    getTeam: state => id => state.records[Number(id)] || {},
  },

  actions: {
    setTeamItem(team) {
      this.records = {
        ...this.records,
        [team.id]: {
          ...(this.records[team.id] || {}),
          ...team,
        },
      };
    },

    setTeams(data) {
      const updatedRecords = { ...this.records };
      data.forEach(team => {
        updatedRecords[team.id] = {
          ...(updatedRecords[team.id] || {}),
          ...team,
        };
      });
      this.records = updatedRecords;
    },

    async create(teamInfo) {
      this.uiFlags.isCreating = true;
      try {
        const response = await TeamsAPI.create(teamInfo);
        const team = response.data;
        this.setTeamItem(team);
        return team;
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async revalidate({ newKey }) {
      try {
        const isExistingKeyValid = await TeamsAPI.validateCacheKey(newKey);
        if (!isExistingKeyValid) {
          const response = await TeamsAPI.refetchAndCommit(newKey);
          this.setTeams(response.data);
        }
      } catch (error) {
        // Ignore error
      }
    },

    async get() {
      this.uiFlags.isFetching = true;
      try {
        const { data } = await TeamsAPI.get(true);
        this.records = {};
        this.setTeams(data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async show({ id }) {
      this.uiFlags.isFetchingItem = true;
      try {
        const response = await TeamsAPI.show(id);
        this.setTeamItem(response.data.payload);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isFetchingItem = false;
      }
    },

    async update({ id, ...updateObj }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await TeamsAPI.update(id, updateObj);
        this.records = {
          ...this.records,
          [response.data.id]: response.data,
        };
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete(teamId) {
      this.uiFlags.isDeleting = true;
      try {
        await TeamsAPI.delete(teamId);
        const { [teamId]: _toDelete, ...rest } = this.records;
        this.records = rest;
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useTeamsStore, import.meta.hot));
}
