import { defineStore, acceptHMRUpdate } from 'pinia';
import CampaignsAPI from '../../api/campaigns';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { CAMPAIGNS_EVENTS } from '../../helper/AnalyticsHelper/events';
import { CAMPAIGN_TYPES } from 'shared/constants/campaign';
import { INBOX_TYPES } from 'dashboard/helper/inbox';

// Espelho Pinia de store/modules/campaigns.js (Onda 2 P0-05).
export const useCampaignsStore = defineStore('campaigns', {
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
    getCampaigns:
      state =>
      (campaignType, inboxChannelTypes = null) => {
        let filtered = state.records.filter(
          r => r.campaign_type === campaignType
        );
        if (inboxChannelTypes && Array.isArray(inboxChannelTypes)) {
          filtered = filtered.filter(
            r => r.inbox && inboxChannelTypes.includes(r.inbox.channel_type)
          );
        }
        return filtered.sort((a, b) => a.id - b.id);
      },
    getSMSCampaigns() {
      return this.getCampaigns(CAMPAIGN_TYPES.ONE_OFF, [
        INBOX_TYPES.SMS,
        INBOX_TYPES.TWILIO,
      ]);
    },
    getWhatsAppCampaigns() {
      return this.getCampaigns(CAMPAIGN_TYPES.ONE_OFF, [INBOX_TYPES.WHATSAPP]);
    },
    getLiveChatCampaigns() {
      return this.getCampaigns(CAMPAIGN_TYPES.ONGOING, [INBOX_TYPES.WEB]);
    },
    getAllCampaigns: state => state.records,
  },

  actions: {
    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await CampaignsAPI.get();
        this.records = response.data;
      } catch (error) {
        // Ignore error
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async create(campaignObj) {
      this.uiFlags.isCreating = true;
      try {
        const response = await CampaignsAPI.create(campaignObj);
        this.records.push(response.data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async update({ id, ...updateObj }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await CampaignsAPI.update(id, updateObj);
        AnalyticsHelper.track(CAMPAIGNS_EVENTS.UPDATE_CAMPAIGN);
        const idx = this.records.findIndex(r => r.id === response.data.id);
        if (idx > -1) this.records.splice(idx, 1, response.data);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async delete(id) {
      this.uiFlags.isDeleting = true;
      try {
        await CampaignsAPI.delete(id);
        AnalyticsHelper.track(CAMPAIGNS_EVENTS.DELETE_CAMPAIGN);
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
  import.meta.hot.accept(acceptHMRUpdate(useCampaignsStore, import.meta.hot));
}
