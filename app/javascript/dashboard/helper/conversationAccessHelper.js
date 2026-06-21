/**
 * Mirrors the backend team access rule (`authorize_team_access` in
 * api/v1/accounts/conversations_controller.rb): a non-administrator only keeps
 * access to a conversation while it has no team, they are its assignee, or
 * they are a member of its team. Keep both sides in sync.
 *
 * Not modeled here: `validate_team_param_access` (team-scoped routes also
 * require the conversation to still belong to the route's team).
 *
 * Team-change callers must pass `assigneeId: null` — on a team change the
 * backend clears or reassigns a non-member assignee (`ensure_assignee_is_from_team`
 * in app/models/concerns/assignment_handler.rb), so the pre-change assignee
 * cannot be trusted for the bypass.
 */
export const losesConversationAccess = ({
  isAdmin,
  userId,
  userTeamIds = [],
  teamId,
  assigneeId,
}) => {
  if (isAdmin) return false;
  if (!Number(teamId)) return false;
  if (assigneeId && userId && Number(assigneeId) === Number(userId)) {
    return false;
  }
  return !userTeamIds.some(id => Number(id) === Number(teamId));
};
