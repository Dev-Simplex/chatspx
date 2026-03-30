import MessagesView from '../MessagesView.vue';

describe('MessagesView methods', () => {
  const { methods } = MessagesView;

  it('fetches previous messages when scrollTop is below threshold', async () => {
    const conversationPanel = {
      scrollHeight: 1000,
      scrollTop: 180,
    };
    const dispatch = vi.fn(async () => {
      conversationPanel.scrollHeight = 1180;
    });

    const vm = {
      currentChat: {
        id: 45,
        dataFetched: true,
        messages: [{ id: 321 }],
      },
      listLoadingStatus: false,
      isLoadingPrevious: false,
      conversationPanel,
      heightBeforeLoad: 0,
      scrollTopBeforeLoad: 0,
      $store: { dispatch },
      setScrollParams: methods.setScrollParams,
    };

    await methods.fetchPreviousMessages.call(vm, 50);

    expect(dispatch).toHaveBeenCalledWith('fetchPreviousMessages', {
      conversationId: 45,
      before: 321,
    });
    expect(vm.isLoadingPrevious).toBe(false);
  });

  it('does not fetch when scrollTop is above threshold', async () => {
    const dispatch = vi.fn();
    const vm = {
      currentChat: {
        id: 45,
        dataFetched: true,
        messages: [{ id: 321 }],
      },
      listLoadingStatus: false,
      isLoadingPrevious: false,
      conversationPanel: { scrollHeight: 1000, scrollTop: 200 },
      heightBeforeLoad: 0,
      scrollTopBeforeLoad: 0,
      $store: { dispatch },
      setScrollParams: methods.setScrollParams,
    };

    await methods.fetchPreviousMessages.call(vm, 300);

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('does not fetch when already loading previous messages', async () => {
    const dispatch = vi.fn();
    const vm = {
      currentChat: {
        id: 77,
        dataFetched: true,
        messages: [{ id: 120 }],
      },
      listLoadingStatus: false,
      isLoadingPrevious: true,
      conversationPanel: { scrollHeight: 800, scrollTop: 10 },
      heightBeforeLoad: 0,
      scrollTopBeforeLoad: 0,
      $store: { dispatch },
      setScrollParams: methods.setScrollParams,
    };

    await methods.fetchPreviousMessages.call(vm, 10);
    expect(dispatch).not.toHaveBeenCalled();
  });
});
