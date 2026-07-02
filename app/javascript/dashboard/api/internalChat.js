/* global axios */
import ApiClient from './ApiClient';

class InternalChatAPI extends ApiClient {
  constructor() {
    super('internal_channels', { accountScoped: true });
  }

  getChannels() {
    return axios.get(this.url);
  }

  // Admin: lista TODOS os canais da conta (modo auditoria).
  getAllChannels() {
    return axios.get(this.url, { params: { scope: 'all' } });
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

  getMessages(channelId, before) {
    return axios.get(`${this.url}/${channelId}/internal_messages`, {
      params: before ? { before } : {},
    });
  }

  sendMessage(
    channelId,
    {
      content,
      attachments = [],
      mentionedUserIds = [],
      replyToId = null,
      sharedConversationId = null,
      echoId = null,
    }
  ) {
    const formData = new FormData();
    formData.append('content', content || '');
    attachments.forEach(file => formData.append('attachments[]', file));
    mentionedUserIds.forEach(id => formData.append('mentioned_user_ids[]', id));
    if (replyToId) formData.append('reply_to_id', replyToId);
    if (sharedConversationId)
      formData.append('shared_conversation_id', sharedConversationId);
    if (echoId) formData.append('echo_id', echoId);
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

  renameChannel(channelId, name) {
    return axios.patch(`${this.url}/${channelId}`, { name });
  }

  addMember(channelId, userId) {
    return axios.post(`${this.url}/${channelId}/add_member`, {
      user_id: userId,
    });
  }

  removeMember(channelId, userId) {
    return axios.delete(`${this.url}/${channelId}/remove_member`, {
      params: { user_id: userId },
    });
  }

  leaveChannel(channelId) {
    return axios.post(`${this.url}/${channelId}/leave`);
  }
}

export default new InternalChatAPI();
