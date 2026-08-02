export default {
  1: {
    id: 1,
    account_id: 1,
    name: 'Test',
    description: 'Some team',
    is_member: true,
    is_supervisor: false,
  },
  2: {
    id: 2,
    account_id: 1,
    name: 'Test 1',
    description: 'Some team',
    is_member: false,
    // supervisiona sem ser membro (D1): é exatamente o caso que separa
    // getVisibleTeams de getMyTeams
    is_supervisor: true,
  },
};
