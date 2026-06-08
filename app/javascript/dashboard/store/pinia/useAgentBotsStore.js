/* eslint-disable no-underscore-dangle, no-useless-catch */
import { defineStore, acceptHMRUpdate } from 'pinia';
import AgentBotsAPI from '../../api/agentBots';
import InboxesAPI from '../../api/inboxes';
import { throwErrorMessage } from '../utils/api';

// Espelho Pinia de store/modules/agentBots.js (Onda 2 P0-05).
export const useAgentBotsStore = defineStore('agentBots', {
  state: () => ({
    records: [],
    uiFlags: {
      isFetching: false,
      isFetchingItem: false,
      isCreating: false,
      isDeleting: false,
      isUpdating: false,
      isUpdatingAvatar: false,
      isFetchingAgentBot: false,
      isSettingAgentBot: false,
      isDisconnecting: false,
    },
    agentBotInbox: {},
  }),

  getters: {
    getBots: state => state.records,
    getUIFlags: state => state.uiFlags,
    getBot: state => botId =>
      state.records.find(r => r.id === Number(botId)) || {},
    getActiveAgentBot: state => inboxId => {
      const botId = state.agentBotInbox[Number(inboxId)];
      return state.records.find(r => r.id === Number(botId)) || {};
    },
  },

  actions: {
    _upsert(data) {
      const index = this.records.findIndex(r => r.id === data.id);
      if (index > -1) this.records.splice(index, 1, data);
      else this.records.push(data);
    },

    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await AgentBotsAPI.get();
        this.records = response.data;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create(botData) {
      this.uiFlags.isCreating = true;
      try {
        const formData = new FormData();
        formData.append('name', botData.name);
        formData.append('description', botData.description);
        formData.append('bot_type', botData.bot_type || 'webhook');
        formData.append('outgoing_url', botData.outgoing_url);
        if (botData.avatar) formData.append('avatar', botData.avatar);
        const response = await AgentBotsAPI.create(formData);
        this._upsert(response.data);
        return response.data;
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
      return null;
    },

    async update({ id, data }) {
      this.uiFlags.isUpdating = true;
      try {
        const formData = new FormData();
        formData.append('name', data.name);
        formData.append('description', data.description);
        formData.append('bot_type', data.bot_type || 'webhook');
        formData.append('outgoing_url', data.outgoing_url);
        if (data.avatar) formData.append('avatar', data.avatar);
        const response = await AgentBotsAPI.update(id, formData);
        const index = this.records.findIndex(r => r.id === response.data.id);
        if (index > -1) this.records.splice(index, 1, response.data);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete(id) {
      this.uiFlags.isDeleting = true;
      try {
        await AgentBotsAPI.delete(id);
        this.records = this.records.filter(r => r.id !== id);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    async deleteAgentBotAvatar(id) {
      this.uiFlags.isUpdatingAvatar = true;
      try {
        await AgentBotsAPI.deleteAgentBotAvatar(id);
        const botIndex = this.records.findIndex(b => b.id === id);
        if (botIndex !== -1) this.records[botIndex].thumbnail = '';
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isUpdatingAvatar = false;
      }
    },

    async show(id) {
      this.uiFlags.isFetchingItem = true;
      try {
        const { data } = await AgentBotsAPI.show(id);
        this._upsert(data);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isFetchingItem = false;
      }
    },

    async fetchAgentBotInbox(inboxId) {
      this.uiFlags.isFetchingAgentBot = true;
      try {
        const { data } = await InboxesAPI.getAgentBot(inboxId);
        const { agent_bot: agentBot = {} } = data || {};
        this.agentBotInbox = { ...this.agentBotInbox, [inboxId]: agentBot.id };
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isFetchingAgentBot = false;
      }
    },

    async setAgentBotInbox({ inboxId, botId }) {
      this.uiFlags.isSettingAgentBot = true;
      try {
        await InboxesAPI.setAgentBot(inboxId, botId);
        this.agentBotInbox = { ...this.agentBotInbox, [inboxId]: botId };
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isSettingAgentBot = false;
      }
    },

    async disconnectBot({ inboxId }) {
      this.uiFlags.isDisconnecting = true;
      try {
        await InboxesAPI.setAgentBot(inboxId, null);
        this.agentBotInbox = { ...this.agentBotInbox, [inboxId]: '' };
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isDisconnecting = false;
      }
    },

    async resetAccessToken(botId) {
      try {
        const response = await AgentBotsAPI.resetAccessToken(botId);
        const index = this.records.findIndex(r => r.id === response.data.id);
        if (index > -1) this.records.splice(index, 1, response.data);
        return response.data;
      } catch (error) {
        throwErrorMessage(error);
        return null;
      }
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useAgentBotsStore, import.meta.hot));
}
