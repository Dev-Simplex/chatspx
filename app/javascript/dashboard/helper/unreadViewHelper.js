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
  if (query.assignee_type === 'awaiting')
    return wootConstants.ASSIGNEE_TYPE.AWAITING;
  if (query.assignee_type === 'all') return wootConstants.ASSIGNEE_TYPE.ALL;
  if (UNREAD_ROUTES.includes(routeName)) return wootConstants.ASSIGNEE_TYPE.ALL;
  return wootConstants.ASSIGNEE_TYPE.ME;
};

/**
 * Like defaultAssigneeTab, but clamps the result to the set of tabs the user is
 * actually allowed to see. The "all" tab is permission-gated, so an Enterprise
 * custom-role agent (e.g. only conversation_unassigned_manage) can reach the
 * unread route while the ALL tab is filtered out — initializing the tab to ALL
 * would then leave no tab highlighted. When the resolved default is not among
 * the rendered tabs, fall back to the first available tab (else ME).
 *
 * @param {string} routeName - Vue route name.
 * @param {Object} [query] - Route query params.
 * @param {string[]} [allowedKeys] - Keys of the currently rendered assignee tabs.
 * @returns {string} One of wootConstants.ASSIGNEE_TYPE values.
 */
export const resolveAssigneeTab = (routeName, query = {}, allowedKeys = []) => {
  const desired = defaultAssigneeTab(routeName, query);
  if (!Array.isArray(allowedKeys) || allowedKeys.length === 0) return desired;
  if (allowedKeys.includes(desired)) return desired;
  return allowedKeys[0] ?? wootConstants.ASSIGNEE_TYPE.ME;
};
