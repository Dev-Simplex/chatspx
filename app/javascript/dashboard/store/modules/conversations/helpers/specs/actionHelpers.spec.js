import {
  isOnMentionsView,
  isOnFoldersView,
  buildConversationList,
} from '../actionHelpers';

describe('#isOnMentionsView', () => {
  it('return valid responses when passing the state', () => {
    expect(isOnMentionsView({ route: { name: 'conversation_mentions' } })).toBe(
      true
    );
    expect(isOnMentionsView({ route: { name: 'conversation_messages' } })).toBe(
      false
    );
  });
});

describe('#isOnFoldersView', () => {
  it('return valid responses when passing the state', () => {
    expect(isOnFoldersView({ route: { name: 'folder_conversations' } })).toBe(
      true
    );
    expect(
      isOnFoldersView({ route: { name: 'conversations_through_folders' } })
    ).toBe(true);
    expect(isOnFoldersView({ route: { name: 'conversation_messages' } })).toBe(
      false
    );
  });
});

describe('#buildConversationList', () => {
  const buildContext = () => ({ commit: vi.fn(), dispatch: vi.fn() });

  // The list API always emits `next_cursor` (jbuilder), so an absent cursor
  // arrives as an explicit `null` — never `undefined`.
  const buildResponse = ({ size, nextCursor = null }) => ({
    payload: Array.from({ length: size }, (_, index) => ({
      id: index + 1,
      meta: { sender: { id: index + 1 } },
    })),
    meta: { next_cursor: nextCursor, all_count: 255 },
  });

  const dispatchedActions = context =>
    context.dispatch.mock.calls.map(([action]) => action);

  const findDispatch = (context, action) =>
    context.dispatch.mock.calls.find(([name]) => name === action);

  describe('regular pagination', () => {
    it('does not mark end reached while the server hands back a cursor', () => {
      const context = buildContext();
      buildConversationList(
        context,
        { page: 1 },
        buildResponse({ size: 25, nextCursor: 'cursor-2' }),
        'all'
      );
      expect(dispatchedActions(context)).not.toContain(
        'conversationPage/setEndReached'
      );
      expect(
        findDispatch(context, 'conversationPage/setNextCursor')[1]
      ).toEqual({ filter: 'all', nextCursor: 'cursor-2' });
    });

    it('marks end reached on a full page with no further cursor', () => {
      const context = buildContext();
      buildConversationList(
        context,
        { page: 5 },
        buildResponse({ size: 25, nextCursor: null }),
        'all'
      );
      expect(dispatchedActions(context)).toContain(
        'conversationPage/setEndReached'
      );
    });

    it('marks end reached on a partial page', () => {
      const context = buildContext();
      buildConversationList(
        context,
        { page: 2 },
        buildResponse({ size: 7, nextCursor: 'cursor-3' }),
        'all'
      );
      expect(dispatchedActions(context)).toContain(
        'conversationPage/setEndReached'
      );
    });
  });

  describe('gap-fill (updatedWithin) responses', () => {
    // A gap-fill asks "what changed in the last N seconds?", so its cursorless
    // response says nothing about whether the list itself ran out.
    it('does not mark end reached even though the cursor is null', () => {
      const context = buildContext();
      buildConversationList(
        context,
        { page: 1, cursor: null, updatedWithin: 40 },
        buildResponse({ size: 25, nextCursor: null }),
        'all'
      );
      expect(dispatchedActions(context)).not.toContain(
        'conversationPage/setEndReached'
      );
    });

    it('does not mark end reached when fewer than a page changed', () => {
      const context = buildContext();
      buildConversationList(
        context,
        { page: 1, cursor: null, updatedWithin: 40 },
        buildResponse({ size: 3, nextCursor: null }),
        'all'
      );
      expect(dispatchedActions(context)).not.toContain(
        'conversationPage/setEndReached'
      );
    });

    it('leaves the pagination cursor and page untouched', () => {
      const context = buildContext();
      buildConversationList(
        context,
        { page: 1, cursor: null, updatedWithin: 40 },
        buildResponse({ size: 25, nextCursor: null }),
        'all'
      );
      expect(dispatchedActions(context)).not.toContain(
        'conversationPage/setNextCursor'
      );
      expect(dispatchedActions(context)).not.toContain(
        'conversationPage/setCurrentPage'
      );
    });

    it('still merges the refreshed conversations into the list', () => {
      const context = buildContext();
      const response = buildResponse({ size: 25, nextCursor: null });
      buildConversationList(
        context,
        { page: 1, cursor: null, updatedWithin: 40 },
        response,
        'all'
      );
      expect(context.commit).toHaveBeenCalledWith(
        'SET_ALL_CONVERSATION',
        response.payload
      );
      expect(findDispatch(context, 'conversationStats/set')[1]).toEqual(
        response.meta
      );
    });
  });
});
