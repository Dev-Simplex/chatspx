import actions from '../actions';
import types from '../../../mutation-types';
import { MESSAGE_STATUS } from 'shared/constants/messages';

const run = (chat, dispatch = vi.fn()) => {
  const commit = vi.fn();
  const state = { allConversations: chat ? [chat] : [] };
  return {
    commit,
    dispatch,
    promise: actions.reconcilePendingMessages(
      { commit, state, dispatch },
      { conversationId: 1 }
    ),
  };
};

describe('#reconcilePendingMessages', () => {
  it('drops the optimistic duplicate when the server copy is already present', async () => {
    const chat = {
      id: 1,
      messages: [
        { id: 'uuid-1', echo_id: 'uuid-1', status: MESSAGE_STATUS.PROGRESS },
        {
          id: 555,
          status: MESSAGE_STATUS.SENT,
          additional_attributes: { echo_id: 'uuid-1' },
        },
      ],
    };
    const { commit, dispatch, promise } = run(chat);
    await promise;

    expect(commit).toHaveBeenCalledWith(types.REMOVE_PENDING_MESSAGE, {
      conversationId: 1,
      echoId: 'uuid-1',
    });
    // Never resends when the server already has it.
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('resends a genuinely-unsent text message in progress', async () => {
    const pending = {
      id: 'uuid-2',
      echo_id: 'uuid-2',
      status: MESSAGE_STATUS.PROGRESS,
      content: 'hello',
    };
    const chat = { id: 1, messages: [pending] };
    const dispatch = vi.fn().mockResolvedValue({});
    const { promise } = run(chat, dispatch);
    await promise;

    expect(dispatch).toHaveBeenCalledWith('sendMessageWithData', pending);
  });

  it('marks an attachment message failed when its files are gone (cannot resend safely)', async () => {
    const pending = {
      id: 'uuid-3',
      echo_id: 'uuid-3',
      status: MESSAGE_STATUS.PROGRESS,
      attachments: [{ id: 'uuid-3' }], // placeholder only, no real files
    };
    const chat = { id: 1, messages: [pending] };
    const { commit, dispatch, promise } = run(chat);
    await promise;

    expect(dispatch).not.toHaveBeenCalled();
    expect(commit).toHaveBeenCalledWith(types.ADD_MESSAGE, {
      ...pending,
      status: MESSAGE_STATUS.FAILED,
    });
  });

  it('leaves an already-failed message with no server copy untouched', async () => {
    const pending = {
      id: 'uuid-4',
      echo_id: 'uuid-4',
      status: MESSAGE_STATUS.FAILED,
      content: 'oops',
    };
    const chat = { id: 1, messages: [pending] };
    const { commit, dispatch, promise } = run(chat);
    await promise;

    expect(dispatch).not.toHaveBeenCalled();
    expect(commit).not.toHaveBeenCalled();
  });

  it('does nothing for a fully reconciled conversation (numeric ids)', async () => {
    const chat = {
      id: 1,
      messages: [{ id: 1, echo_id: 'uuid-x', status: MESSAGE_STATUS.SENT }],
    };
    const { commit, dispatch, promise } = run(chat);
    await promise;

    expect(commit).not.toHaveBeenCalled();
    expect(dispatch).not.toHaveBeenCalled();
  });
});
