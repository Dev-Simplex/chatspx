import { getters } from '../../kanban/getters';

describe('#kanban getters', () => {
  describe('#getScheduledMessagesByConversation', () => {
    it('matches by conversation id with number and string values', () => {
      const state = {
        scheduledMessages: {
          1: { id: 1, conversationId: 10, status: 'pending' },
          2: { id: 2, conversationId: '10', status: 'pending' },
          3: { id: 3, conversationId: 11, status: 'pending' },
        },
      };

      const messages = getters.getScheduledMessagesByConversation(state)(10);
      const ids = messages.map(message => message.id);

      expect(ids).toEqual([1, 2]);
    });
  });
});
