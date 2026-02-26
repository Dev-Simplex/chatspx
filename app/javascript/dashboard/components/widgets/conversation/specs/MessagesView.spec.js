import MessagesView from '../MessagesView.vue';

describe('MessagesView methods', () => {
  const { methods } = MessagesView;

  it('uses optimized pagination params and restores scroll anchor', async () => {
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
      optimizedMessageScrollLoading: true,
      inFlightBeforeCursor: null,
      conversationPanel,
      heightBeforeLoad: 0,
      scrollTopBeforeLoad: 0,
      $store: { dispatch },
      captureScrollSnapshot: methods.captureScrollSnapshot,
    };

    await methods.fetchPreviousMessages.call(vm, { forceLoad: true });

    expect(dispatch).toHaveBeenCalledWith('fetchPreviousMessages', {
      conversationId: 45,
      before: 321,
      limit: 40,
      includeMeta: false,
    });
    expect(conversationPanel.scrollTop).toBe(360);
    expect(vm.isLoadingPrevious).toBe(false);
    expect(vm.inFlightBeforeCursor).toBeNull();
  });

  it('dedupes in-flight requests for the same before cursor', async () => {
    const dispatch = vi.fn();
    const vm = {
      currentChat: {
        id: 45,
        dataFetched: true,
        messages: [{ id: 321 }],
      },
      listLoadingStatus: false,
      isLoadingPrevious: false,
      optimizedMessageScrollLoading: true,
      inFlightBeforeCursor: 321,
      conversationPanel: { scrollHeight: 1000, scrollTop: 20 },
      $store: { dispatch },
      captureScrollSnapshot: methods.captureScrollSnapshot,
    };

    await methods.fetchPreviousMessages.call(vm, { forceLoad: true });

    expect(dispatch).not.toHaveBeenCalled();
  });

  it('keeps legacy scroll threshold behavior when optimization flag is off', async () => {
    const dispatch = vi.fn();
    const vm = {
      currentChat: {
        id: 77,
        dataFetched: true,
        messages: [{ id: 120 }],
      },
      listLoadingStatus: false,
      isLoadingPrevious: false,
      optimizedMessageScrollLoading: false,
      inFlightBeforeCursor: null,
      conversationPanel: { scrollHeight: 800, scrollTop: 120 },
      $store: { dispatch },
      captureScrollSnapshot: methods.captureScrollSnapshot,
    };

    await methods.fetchPreviousMessages.call(vm, { scrollTop: 300 });
    expect(dispatch).not.toHaveBeenCalled();

    dispatch.mockResolvedValue({});
    await methods.fetchPreviousMessages.call(vm, { scrollTop: 80 });
    expect(dispatch).toHaveBeenCalledWith('fetchPreviousMessages', {
      conversationId: 77,
      before: 120,
      includeMeta: true,
    });
  });
});
