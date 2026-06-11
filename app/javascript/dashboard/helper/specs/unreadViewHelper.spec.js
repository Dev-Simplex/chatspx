import {
  UNREAD_ROUTES,
  defaultAssigneeTab,
  resolveAssigneeTab,
} from '../unreadViewHelper';
import wootConstants from 'dashboard/constants/globals';

const { ME, UNASSIGNED, ALL } = wootConstants.ASSIGNEE_TYPE;

describe('unreadViewHelper', () => {
  describe('UNREAD_ROUTES', () => {
    it('lists both unread route names', () => {
      expect(UNREAD_ROUTES).toEqual([
        'conversation_unread',
        'conversation_through_unread',
      ]);
    });
  });

  describe('#defaultAssigneeTab', () => {
    it('defaults unread routes to ALL', () => {
      expect(defaultAssigneeTab('conversation_unread')).toBe(ALL);
      expect(defaultAssigneeTab('conversation_through_unread')).toBe(ALL);
    });

    it('defaults unattended route to ME', () => {
      expect(defaultAssigneeTab('conversation_unattended')).toBe(ME);
    });

    it('defaults other routes to ME', () => {
      expect(defaultAssigneeTab('home')).toBe(ME);
      expect(defaultAssigneeTab(undefined)).toBe(ME);
    });

    it('respects ?assignee_type=all over the route default', () => {
      expect(
        defaultAssigneeTab('conversation_unattended', { assignee_type: 'all' })
      ).toBe(ALL);
      expect(defaultAssigneeTab('home', { assignee_type: 'all' })).toBe(ALL);
    });

    it('respects ?assignee_type=unassigned', () => {
      expect(
        defaultAssigneeTab('conversation_unread', {
          assignee_type: 'unassigned',
        })
      ).toBe(UNASSIGNED);
    });

    it('respects ?assignee_type=me even on unread routes', () => {
      expect(
        defaultAssigneeTab('conversation_unread', { assignee_type: 'me' })
      ).toBe(ME);
    });

    it('ignores unknown assignee_type and falls back to the route default', () => {
      expect(
        defaultAssigneeTab('conversation_unread', { assignee_type: 'bogus' })
      ).toBe(ALL);
      expect(
        defaultAssigneeTab('conversation_unattended', {
          assignee_type: 'bogus',
        })
      ).toBe(ME);
    });
  });

  describe('#resolveAssigneeTab', () => {
    it('returns the route default when no allowedKeys are given', () => {
      expect(resolveAssigneeTab('conversation_unread')).toBe(ALL);
      expect(resolveAssigneeTab('conversation_unread', {}, [])).toBe(ALL);
    });

    it('keeps the default when it is among the allowed tabs', () => {
      expect(
        resolveAssigneeTab('conversation_unread', {}, [ME, UNASSIGNED, ALL])
      ).toBe(ALL);
    });

    it('clamps to the first allowed tab when the default is not permitted', () => {
      // Enterprise custom-role agent: only Mine/Unassigned tabs are rendered,
      // so the unread ALL default must fall back instead of leaving no tab.
      expect(
        resolveAssigneeTab('conversation_unread', {}, [ME, UNASSIGNED])
      ).toBe(ME);
      expect(resolveAssigneeTab('conversation_unread', {}, [UNASSIGNED])).toBe(
        UNASSIGNED
      );
    });

    it('clamps a deep-link assignee_type the user is not allowed to use', () => {
      expect(
        resolveAssigneeTab('conversation_unread', { assignee_type: 'all' }, [
          ME,
          UNASSIGNED,
        ])
      ).toBe(ME);
    });
  });
});
