import { getters } from '../../teams/getters';
import teamsList from './fixtures';

describe('#getters', () => {
  it('getTeams', () => {
    const state = {
      records: teamsList,
    };
    expect(getters.getTeams(state)).toEqual([teamsList[1], teamsList[2]]);
  });

  it('getMyTeams', () => {
    const state = {
      records: teamsList,
    };
    expect(
      getters.getMyTeams(state, {
        getTeams: [teamsList[1], teamsList[2]],
      })
    ).toEqual([teamsList[1]]);
  });

  it('getSupervisedTeams', () => {
    const state = {
      records: teamsList,
    };
    expect(
      getters.getSupervisedTeams(state, {
        getTeams: [teamsList[1], teamsList[2]],
      })
    ).toEqual([teamsList[2]]);
  });

  it('getVisibleTeams', () => {
    const state = {
      records: teamsList,
    };
    // membro ∪ supervisionado: o time 2 entra por supervisão, sem ser membro
    expect(
      getters.getVisibleTeams(state, {
        getTeams: [teamsList[1], teamsList[2]],
      })
    ).toEqual([teamsList[1], teamsList[2]]);
  });

  it('getVisibleTeams falls back to membership when nobody supervises', () => {
    const plainTeams = [
      { ...teamsList[1], is_supervisor: false },
      { ...teamsList[2], is_supervisor: false },
    ];
    expect(
      getters.getVisibleTeams({ records: plainTeams }, { getTeams: plainTeams })
    ).toEqual([plainTeams[0]]);
  });

  it('getTeam', () => {
    const state = {
      records: teamsList,
    };
    expect(getters.getTeam(state)(1)).toEqual({
      id: 1,
      account_id: 1,
      name: 'Test',
      description: 'Some team',
      is_member: true,
      is_supervisor: false,
    });
  });

  it('getUIFlags', () => {
    const state = {
      uiFlags: {
        isFetching: false,
        isCreating: false,
        isUpdating: false,
        isDeleting: false,
      },
    };
    expect(getters.getUIFlags(state)).toEqual({
      isFetching: false,
      isCreating: false,
      isUpdating: false,
      isDeleting: false,
    });
  });
});
