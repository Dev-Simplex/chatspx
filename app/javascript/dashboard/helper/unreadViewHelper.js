import wootConstants from 'dashboard/constants/globals';

// Route names for the custom "Unread" view. They reuse the standard
// ConversationView/ChatList, but should default to the "All" assignee tab so
// admins/agents see every accessible unread conversation. The backend
// PermissionFilterService still scopes the result set per role.
export const UNREAD_ROUTES = [
  'conversation_unread',
  'conversation_through_unread',
];

/**
 * Resolve the initial/active assignee tab for a given route.
 *
 * Priority:
 *   1. Explicit `?assignee_type` query param (deep-link) wins.
 *   2. Unread routes default to ALL (admin/agent see everything accessible).
 *   3. Everything else (incl. unattended) defaults to ME.
 *
 * @param {string} routeName - Vue route name.
 * @param {Object} [query] - Route query params.
 * @returns {string} One of wootConstants.ASSIGNEE_TYPE values.
 */
export const defaultAssigneeTab = (routeName, query = {}) => {
  if (query.assignee_type === 'me') return wootConstants.ASSIGNEE_TYPE.ME;
  if (query.assignee_type === 'unassigned')
    return wootConstants.ASSIGNEE_TYPE.UNASSIGNED;
  if (query.assignee_type === 'all') return wootConstants.ASSIGNEE_TYPE.ALL;
  if (UNREAD_ROUTES.includes(routeName)) return wootConstants.ASSIGNEE_TYPE.ALL;
  return wootConstants.ASSIGNEE_TYPE.ME;
};
