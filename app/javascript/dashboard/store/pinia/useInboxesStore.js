import { defineStore, acceptHMRUpdate } from 'pinia';
import { INBOX_TYPES } from 'dashboard/helper/inbox';
import InboxesAPI from '../../api/inboxes';
import WebChannel from '../../api/channel/webChannel';
import FBChannel from '../../api/channel/fbChannel';
import TwilioChannel from '../../api/channel/twilioChannel';
import WhatsappChannel from '../../api/channel/whatsappChannel';
import { throwErrorMessage } from '../utils/api';
import AnalyticsHelper from '../../helper/AnalyticsHelper';
import { ACCOUNT_EVENTS } from '../../helper/AnalyticsHelper/events';

// Helper compartilhado com o Vuex (re-exportado para conveniencia).
export const buildInboxData = inboxParams => {
  const formData = new FormData();
  const { channel = {}, ...inboxProperties } = inboxParams;
  Object.keys(inboxProperties).forEach(key => {
    formData.append(key, inboxProperties[key]);
  });
  const { selectedFeatureFlags, ...channelParams } = channel;
  if (selectedFeatureFlags) {
    if (selectedFeatureFlags.length) {
      selectedFeatureFlags.forEach(featureFlag => {
        formData.append(`channel[selected_feature_flags][]`, featureFlag);
      });
    } else {
      formData.append('channel[selected_feature_flags][]', '');
    }
  }
  Object.keys(channelParams).forEach(key => {
    formData.append(`channel[${key}]`, channel[key]);
  });
  return formData;
};

const sendAnalyticsEvent = channelType => {
  AnalyticsHelper.track(ACCOUNT_EVENTS.ADDED_AN_INBOX, { channelType });
};

// Espelho Pinia de store/modules/inboxes.js + inboxes/channelActions.js (Onda 1 P0-05).
export const useInboxesStore = defineStore('inboxes', {
  state: () => ({
    records: [],
    uiFlags: {
      isFetching: false,
      isFetchingItem: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
      isUpdatingIMAP: false,
      isUpdatingSMTP: false,
    },
  }),

  getters: {
    getInboxes: state => state.records,
    getAllInboxes: state => state.records,
    getWhatsAppTemplates: state => inboxId => {
      const inbox = state.records.find(r => r.id === Number(inboxId));
      const {
        message_templates: whatsAppMessageTemplates,
        additional_attributes: additionalAttributes,
      } = inbox || {};
      const { message_templates: apiInboxMessageTemplates } =
        additionalAttributes || {};
      return whatsAppMessageTemplates || apiInboxMessageTemplates;
    },
    getFilteredWhatsAppTemplates: state => inboxId => {
      const inbox = state.records.find(r => r.id === Number(inboxId));
      const {
        message_templates: whatsAppMessageTemplates,
        additional_attributes: additionalAttributes,
      } = inbox || {};
      const { message_templates: apiInboxMessageTemplates } =
        additionalAttributes || {};
      const templates = whatsAppMessageTemplates || apiInboxMessageTemplates;
      if (!templates || !Array.isArray(templates)) return [];

      return templates.filter(template => {
        if (!template || !template.status || !template.components) return false;
        if (template.status.toLowerCase() !== 'approved') return false;
        if (template.category === 'AUTHENTICATION') return false;
        if (
          template.name &&
          template.name.startsWith('customer_satisfaction_survey')
        ) {
          return false;
        }
        const hasUnsupportedComponents = template.components.some(
          component =>
            ['LIST', 'PRODUCT', 'CATALOG', 'CALL_PERMISSION_REQUEST'].includes(
              component.type
            ) ||
            (component.type === 'HEADER' && component.format === 'LOCATION')
        );
        return !hasUnsupportedComponents;
      });
    },
    getNewConversationInboxes: state =>
      state.records.filter(inbox => {
        const { channel_type: channelType, phone_number: phoneNumber = '' } =
          inbox;
        const isEmailChannel = channelType === INBOX_TYPES.EMAIL;
        const isSmsChannel =
          channelType === INBOX_TYPES.TWILIO &&
          phoneNumber.startsWith('whatsapp');
        return isEmailChannel || isSmsChannel;
      }),
    getInbox: state => inboxId =>
      state.records.find(r => r.id === Number(inboxId)) || {},
    getInboxById: state => inboxId =>
      state.records.find(r => r.id === Number(inboxId)) || {},
    getUIFlags: state => state.uiFlags,
    getWebsiteInboxes: state =>
      state.records.filter(i => i.channel_type === INBOX_TYPES.WEB),
    getTwilioInboxes: state =>
      state.records.filter(i => i.channel_type === INBOX_TYPES.TWILIO),
    getSMSInboxes: state =>
      state.records.filter(
        i =>
          i.channel_type === INBOX_TYPES.SMS ||
          (i.channel_type === INBOX_TYPES.TWILIO && i.medium === 'sms')
      ),
    getWhatsAppInboxes: state =>
      state.records.filter(i => i.channel_type === INBOX_TYPES.WHATSAPP),
    dialogFlowEnabledInboxes: state =>
      state.records.filter(i => i.channel_type !== INBOX_TYPES.EMAIL),
    getFacebookInboxByInstagramId: state => instagramId =>
      state.records.find(
        i => i.instagram_id === instagramId && i.channel_type === INBOX_TYPES.FB
      ),
    getInstagramInboxByInstagramId: state => instagramId =>
      state.records.find(
        i =>
          i.instagram_id === instagramId &&
          i.channel_type === INBOX_TYPES.INSTAGRAM
      ),
    getTiktokInboxByBusinessId: state => businessId =>
      state.records.find(
        i =>
          i.business_id === businessId && i.channel_type === INBOX_TYPES.TIKTOK
      ),
  },

  actions: {
    upsertRecord(record) {
      const index = this.records.findIndex(r => r.id === record.id);
      if (index > -1) this.records.splice(index, 1, record);
      else this.records.push(record);
    },

    replaceRecord(record) {
      const index = this.records.findIndex(r => r.id === record.id);
      if (index > -1) this.records.splice(index, 1, record);
    },

    async revalidate({ newKey }) {
      try {
        const isExistingKeyValid = await InboxesAPI.validateCacheKey(newKey);
        if (!isExistingKeyValid) {
          const response = await InboxesAPI.refetchAndCommit(newKey);
          this.records = response.data.payload;
        }
      } catch (error) {
        // Ignore error
      }
    },

    async get() {
      this.uiFlags.isFetching = true;
      try {
        const response = await InboxesAPI.get(true);
        this.records = response.data.payload;
      } finally {
        this.uiFlags.isFetching = false;
      }
    },

    async createChannel(params) {
      this.uiFlags.isCreating = true;
      try {
        const response = await WebChannel.create(params);
        this.records.push(response.data);
        const { channel = {} } = params;
        sendAnalyticsEvent(channel.type);
        return response.data;
      } catch (error) {
        const errorMessage = error?.response?.data?.message;
        throw new Error(errorMessage);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async createWebsiteChannel(params) {
      this.uiFlags.isCreating = true;
      try {
        const response = await WebChannel.create(buildInboxData(params));
        this.records.push(response.data);
        sendAnalyticsEvent('website');
        return response.data;
      } catch (error) {
        return throwErrorMessage(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async createTwilioChannel(params) {
      this.uiFlags.isCreating = true;
      try {
        const response = await TwilioChannel.create(params);
        this.records.push(response.data);
        sendAnalyticsEvent('twilio');
        return response.data;
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async createFBChannel(params) {
      this.uiFlags.isCreating = true;
      try {
        const response = await FBChannel.create(params);
        this.records.push(response.data);
        sendAnalyticsEvent('facebook');
        return response.data;
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async createWhatsAppEmbeddedSignup(params) {
      this.uiFlags.isCreating = true;
      try {
        const response = await WhatsappChannel.createEmbeddedSignup(params);
        this.records.push(response.data);
        sendAnalyticsEvent('whatsapp');
        return response.data;
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async createVoiceChannel(params) {
      this.uiFlags.isCreating = true;
      try {
        const response = await InboxesAPI.create({
          name: params.name,
          channel: { ...params.voice, type: 'voice' },
        });
        this.records.push(response.data);
        sendAnalyticsEvent('voice');
        return response.data;
      } finally {
        this.uiFlags.isCreating = false;
      }
    },

    async updateInbox({ id, formData = true, ...inboxParams }) {
      this.uiFlags.isUpdating = true;
      try {
        const response = await InboxesAPI.update(
          id,
          formData ? buildInboxData(inboxParams) : inboxParams
        );
        this.replaceRecord(response.data);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isUpdating = false;
      }
    },

    async updateInboxIMAP({ id, ...inboxParams }) {
      this.uiFlags.isUpdatingIMAP = true;
      try {
        const response = await InboxesAPI.update(id, inboxParams);
        this.replaceRecord(response.data);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isUpdatingIMAP = false;
      }
    },

    async updateInboxSMTP({ id, ...inboxParams }) {
      this.uiFlags.isUpdatingSMTP = true;
      try {
        const response = await InboxesAPI.update(id, inboxParams);
        this.replaceRecord(response.data);
      } catch (error) {
        throwErrorMessage(error);
      } finally {
        this.uiFlags.isUpdatingSMTP = false;
      }
    },

    async delete(inboxId) {
      this.uiFlags.isDeleting = true;
      try {
        await InboxesAPI.delete(inboxId);
        this.records = this.records.filter(r => r.id !== inboxId);
      } catch (error) {
        throw new Error(error);
      } finally {
        this.uiFlags.isDeleting = false;
      }
    },

    async reauthorizeFacebookPage(params) {
      try {
        const response = await FBChannel.reauthorizeFacebookPage(params);
        this.replaceRecord(response.data);
      } catch (error) {
        throw new Error(error.message);
      }
    },

    async deleteInboxAvatar(inboxId) {
      try {
        await InboxesAPI.deleteInboxAvatar(inboxId);
      } catch (error) {
        throw new Error(error);
      }
    },

    async syncTemplates(inboxId) {
      try {
        await InboxesAPI.syncTemplates(inboxId);
      } catch (error) {
        throw new Error(error);
      }
    },

    async createCSATTemplate({ inboxId, template }) {
      const response = await InboxesAPI.createCSATTemplate(inboxId, template);
      return response.data;
    },

    async getCSATTemplateStatus({ inboxId }) {
      const response = await InboxesAPI.getCSATTemplateStatus(inboxId);
      return response.data;
    },

    async analyzeCSATTemplateUtility({ inboxId, template }) {
      const response = await InboxesAPI.analyzeCSATTemplateUtility(
        inboxId,
        template
      );
      return response.data;
    },
  },
});

if (import.meta.hot) {
  import.meta.hot.accept(acceptHMRUpdate(useInboxesStore, import.meta.hot));
}
