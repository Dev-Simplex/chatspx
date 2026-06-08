import { defineStore, acceptHMRUpdate } from 'pinia';
import camelcaseKeys from 'camelcase-keys';
import ContactAPI from '../../api/contacts';
import ConversationApi from '../../api/conversations';
import MessageApi from '../../api/inbox/message';

// Espelho Pinia de store/modules/contactConversations.js (Onda 2 P0-05).
const ACTIVE_STATUSES = ['open', 'pending', 'snoozed'];

const createMessagePayload = (payload, message) => {
  const { content, cc_emails, bcc_emails } = message;
  payload.append('message[content]', content);
  if (cc_emails) payload.append('message[cc_emails]', cc_emails);
  if (bcc_emails) payload.append('message[bcc_emails]', bcc_emails);
};

const createConversationPayload = ({ params, contactId, files }) => {
  const { inboxId, message, sourceId, mailSubject, assigneeId } = params;
  const payload = new FormData();
  if (message) createMessagePayload(payload, message);
  if (files && files.length > 0) {
    files.forEach(file => payload.append('message[attachments][]', file));
  }
  payload.append('inbox_id', inboxId);
  payload.append('contact_id', contactId);
  payload.append('source_id', sourceId);
  payload.append('additional_attributes[mail_subject]', mailSubject);
  payload.append('assignee_id', assigneeId);
  return payload;
};

const createWhatsAppConversationPayload = ({ params }) => {
  const { inboxId, message, contactId, sourceId, assigneeId } = params;
  return {
    inbox_id: inboxId,
    contact_id: contactId,
    source_id: sourceId,
    message,
    assignee_id: assigneeId,
  };
};

const setNewConversationPayload = ({
  isFromWhatsApp,
  params,
  contactId,
  files,
}) => {
  if (isFromWhatsApp) return createWhatsAppConversationPayload({ params });
  return createConversationPayload({ params, contactId, files });
};

export const useContactConversationsStore = defineStore(
  'contactConversations',
  {
    state: () => ({
      records: {},
      uiFlags: {
        isFetching: false,
        isCreating: false,
      },
    }),

    getters: {
      getUIFlags: state => state.uiFlags,
      getContactConversation: state => id => state.records[Number(id)] || [],
      getAllConversationsByContactId: state => id => {
        const records = state.records[Number(id)] || [];
        return camelcaseKeys(records, { deep: true });
      },
      getActiveConversationByInbox() {
        return (contactId, inboxId) => {
          const conversations = this.getAllConversationsByContactId(contactId);
          const normalized = Array.isArray(conversations) ? conversations : [];
          return (
            normalized.find(
              c =>
                Number(c.inboxId) === Number(inboxId) &&
                ACTIVE_STATUSES.includes(String(c.status || '').toLowerCase())
            ) || null
          );
        };
      },
    },

    actions: {
      async create({ params, isFromWhatsApp }) {
        this.uiFlags.isCreating = true;
        const { contactId, files } = params;
        try {
          const payload = setNewConversationPayload({
            isFromWhatsApp,
            params,
            contactId,
            files,
          });
          const { data } = await ConversationApi.create(payload);
          const conversations = this.records[contactId] || [];
          const updated = [...conversations];
          const idx = conversations.findIndex(c => c.id === data.id);
          if (idx !== -1) updated[idx] = { ...conversations[idx], ...data };
          else updated.push(data);
          this.records = { ...this.records, [contactId]: updated };
          return data;
        } catch (error) {
          throw new Error(error);
        } finally {
          this.uiFlags.isCreating = false;
        }
      },

      async sendToExistingConversation({ conversation, params }) {
        this.uiFlags.isCreating = true;
        const conversationId = conversation.id;
        const { message, files } = params;
        const msg = message || {};
        try {
          await MessageApi.create({
            conversationId,
            message: msg.content,
            files: files || [],
            ccEmails: msg.cc_emails || '',
            bccEmails: msg.bcc_emails || '',
            templateParams: msg.template_params,
          });
          return {
            id: conversationId,
            account_id: conversation.accountId ?? conversation.account_id,
          };
        } catch (error) {
          throw new Error(error);
        } finally {
          this.uiFlags.isCreating = false;
        }
      },

      async get(contactId) {
        this.uiFlags.isFetching = true;
        try {
          const response = await ContactAPI.getConversations(contactId);
          this.records = {
            ...this.records,
            [contactId]: response.data.payload,
          };
        } finally {
          this.uiFlags.isFetching = false;
        }
      },
    },
  }
);

if (import.meta.hot) {
  import.meta.hot.accept(
    acceptHMRUpdate(useContactConversationsStore, import.meta.hot)
  );
}
