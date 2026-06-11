import { losesConversationAccess } from '../conversationAccessHelper';

describe('losesConversationAccess', () => {
  const base = {
    isAdmin: false,
    userId: 7,
    userTeamIds: [1, 2],
    teamId: 3,
    assigneeId: 9,
  };

  it('keeps access for administrators', () => {
    expect(losesConversationAccess({ ...base, isAdmin: true })).toBe(false);
  });

  it('keeps access when the conversation has no team', () => {
    expect(losesConversationAccess({ ...base, teamId: null })).toBe(false);
    expect(losesConversationAccess({ ...base, teamId: 0 })).toBe(false);
  });

  it('keeps access when the user is the assignee', () => {
    expect(losesConversationAccess({ ...base, assigneeId: 7 })).toBe(false);
  });

  it('keeps access when the user is a member of the team', () => {
    expect(losesConversationAccess({ ...base, teamId: 2 })).toBe(false);
  });

  it('loses access when non-admin, not assignee and not a team member', () => {
    expect(losesConversationAccess(base)).toBe(true);
  });

  it('compares team ids loosely across string/number types', () => {
    expect(
      losesConversationAccess({ ...base, userTeamIds: ['3'], teamId: 3 })
    ).toBe(false);
    expect(
      losesConversationAccess({ ...base, userTeamIds: [3], teamId: '3' })
    ).toBe(false);
  });

  it('treats the "0" string team like the numeric 0 (no team)', () => {
    expect(losesConversationAccess({ ...base, teamId: '0' })).toBe(false);
    expect(losesConversationAccess({ ...base, teamId: undefined })).toBe(false);
  });

  it('compares assignee ids loosely across string/number types', () => {
    expect(losesConversationAccess({ ...base, assigneeId: '7' })).toBe(false);
    expect(
      losesConversationAccess({ ...base, userId: '7', assigneeId: 7 })
    ).toBe(false);
  });

  it('never matches assignee on degenerate identities', () => {
    expect(
      losesConversationAccess({
        ...base,
        userId: undefined,
        assigneeId: undefined,
      })
    ).toBe(true);
    expect(
      losesConversationAccess({ ...base, userId: null, assigneeId: null })
    ).toBe(true);
    expect(losesConversationAccess({ ...base, userId: 0, assigneeId: 0 })).toBe(
      true
    );
  });

  it('treats an unassigned conversation with a foreign team as lost', () => {
    expect(losesConversationAccess({ ...base, assigneeId: null })).toBe(true);
  });

  it('defaults to empty team membership', () => {
    expect(
      losesConversationAccess({
        isAdmin: false,
        userId: 7,
        teamId: 3,
        assigneeId: null,
      })
    ).toBe(true);
  });
});
