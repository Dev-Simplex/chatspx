import scheduledMessagesAPI from '../scheduledMessages';

describe('#ScheduledMessagesAPI', () => {
  const originalAxios = window.axios;
  const axiosMock = { get: vi.fn(() => Promise.resolve()) };

  beforeEach(() => {
    window.axios = axiosMock;
  });

  afterEach(() => {
    window.axios = originalAxios;
    vi.clearAllMocks();
  });

  // CHAT-175: o front conhece a conversa pelo display_id; conversation_id na API é o id interno.
  it('#getByConversation filtra pelo display_id da conversa', () => {
    scheduledMessagesAPI.getByConversation(42);

    expect(axiosMock.get).toHaveBeenCalledWith(scheduledMessagesAPI.url, {
      params: { conversation_display_id: 42, status: 'pending' },
    });
  });
});
