import types from '../../../mutation-types';
import { UNREAD_ROUTES } from 'dashboard/helper/unreadViewHelper';

export const setPageFilter = ({
  dispatch,
  filter,
  page,
  nextCursor,
  markEndReached,
}) => {
  dispatch('conversationPage/setCurrentPage', { filter, page }, { root: true });
  if (nextCursor !== undefined) {
    dispatch(
      'conversationPage/setNextCursor',
      { filter, nextCursor },
      {
        root: true,
      }
    );
  }
  if (markEndReached) {
    dispatch('conversationPage/setEndReached', { filter }, { root: true });
  }
};

export const setContacts = (commit, chatList) => {
  commit(
    `contacts/${types.SET_CONTACTS}`,
    chatList.map(chat => chat.meta.sender)
  );
};

export const isOnMentionsView = ({ route: { name: routeName } }) => {
  const MENTION_ROUTES = [
    'conversation_mentions',
    'conversation_through_mentions',
  ];
  return MENTION_ROUTES.includes(routeName);
};

export const isOnUnattendedView = ({ route: { name: routeName } }) => {
  const UNATTENDED_ROUTES = [
    'conversation_unattended',
    'conversation_through_unattended',
  ];
  return UNATTENDED_ROUTES.includes(routeName);
};

export const isOnUnreadView = ({ route: { name: routeName } }) =>
  UNREAD_ROUTES.includes(routeName);

export const isOnParticipatingView = ({ route: { name: routeName } }) => {
  const PARTICIPATING_ROUTES = [
    'conversation_participating',
    'conversation_through_participating',
  ];
  return PARTICIPATING_ROUTES.includes(routeName);
};

export const isOnFoldersView = ({ route: { name: routeName } }) => {
  const FOLDER_ROUTES = [
    'folder_conversations',
    'conversations_through_folders',
  ];
  return FOLDER_ROUTES.includes(routeName);
};

const CONVERSATIONS_PER_PAGE = 25;

export const buildConversationList = (
  context,
  requestPayload,
  responseData,
  filterType
) => {
  const { payload: conversationList, meta: metaData } = responseData;
  context.commit(types.SET_ALL_CONVERSATION, conversationList);
  // Never update tab counts from the list API when an assignee filter is
  // active (me/unassigned/assigned), because the backend computes counts
  // on the already-filtered set (e.g. all_count=2 when only "mine" are
  // fetched). Correct counts come from the /conversations/meta endpoint,
  // which is called separately without assigneeType.
  const hasAssigneeFilter =
    requestPayload.assigneeType === 'me' ||
    requestPayload.assigneeType === 'unassigned' ||
    requestPayload.assigneeType === 'awaiting' ||
    requestPayload.assigneeType === 'assigned';
  if (!hasAssigneeFilter) {
    context.dispatch('conversationStats/set', metaData);
  }
  context.dispatch(
    'conversationLabels/setBulkConversationLabels',
    conversationList
  );
  context.commit(types.CLEAR_LIST_LOADING_STATUS);
  setContacts(context.commit, conversationList);

  // A gap-fill (ReconnectService, `updatedWithin`) is a point-in-time catch-up
  // — "what changed in the last N seconds?" — not a page of the list. The
  // backend answers it without a cursor, and a short/cursorless answer only
  // means little changed, never that the list ran out. Letting it write
  // pagination state would end the infinite scroll (and, for the `all` filter,
  // also for `me`/`unassigned`) until a reload, while wiping the real cursor
  // and rewinding the page to 1. Merging the fresh conversations above is the
  // whole job here; pagination stays owned by the paging fetches.
  if (requestPayload.updatedWithin) return;

  const hasNextCursor = !!metaData?.next_cursor;
  const markEndReached =
    conversationList.length < CONVERSATIONS_PER_PAGE || !hasNextCursor;
  setPageFilter({
    dispatch: context.dispatch,
    filter: filterType,
    page: requestPayload.page,
    nextCursor: metaData?.next_cursor,
    markEndReached,
  });
};
