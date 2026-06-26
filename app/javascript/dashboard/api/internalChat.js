/* global axios */
import ApiClient from './ApiClient';

class InternalChatAPI extends ApiClient {
  constructor() {
    super('internal_channels', { accountScoped: true });
  }

  getChannels() {
    return axios.get(this.url);
  }

  createDm(userId) {
    return axios.post(this.url, { user_id: userId });
  }

  createGroup(name, memberIds) {
    return axios.post(this.url, { name, member_ids: memberIds });
  }

  createTeamChannel(teamId) {
    return axios.post(this.url, { team_id: teamId });
  }

  markRead(channelId) {
    return axios.post(`${this.url}/${channelId}/read`);
  }

  sendTyping(channelId, isTyping) {
    return axios.post(`${this.url}/${channelId}/typing`, { typing: isTyping });
  }

  getMessages(channelId) {
    return axios.get(`${this.url}/${channelId}/internal_messages`);
  }

  sendMessage(channelId, { content, attachments = [], mentionedUserIds = [] }) {
    const formData = new FormData();
    formData.append('content', content || '');
    attachments.forEach(file => formData.append('attachments[]', file));
    mentionedUserIds.forEach(id => formData.append('mentioned_user_ids[]', id));
    return axios.post(`${this.url}/${channelId}/internal_messages`, formData);
  }

  editMessage(channelId, messageId, content) {
    return axios.patch(
      `${this.url}/${channelId}/internal_messages/${messageId}`,
      { content }
    );
  }

  deleteMessage(channelId, messageId) {
    return axios.delete(
      `${this.url}/${channelId}/internal_messages/${messageId}`
    );
  }

  reactToMessage(channelId, messageId, emoji) {
    return axios.post(
      `${this.url}/${channelId}/internal_messages/${messageId}/react`,
      { emoji }
    );
  }

  getAgents() {
    return axios.get(`${this.baseUrl()}/agents_for_internal_chat`);
  }
}

export default new InternalChatAPI();
