import types from '../../../mutation-types';
import { actions } from '../../flows';
import FlowsAPI from '../../../../api/flows';
import flowsList from './fixtures';

vi.mock('../../../../api/flows', () => ({
  default: {
    get: vi.fn(),
    show: vi.fn(),
    create: vi.fn(),
    update: vi.fn(),
    delete: vi.fn(),
    execute: vi.fn(),
    simulate: vi.fn(),
    getLogs: vi.fn(),
    getStats: vi.fn(),
    importLegacy: vi.fn(),
  },
}));

const commit = vi.fn();
const dispatch = vi.fn();

describe('#actions', () => {
  describe('#get', () => {
    it('commits fetch flags and SET_FLOWS on success', async () => {
      FlowsAPI.get.mockResolvedValue({ data: { payload: flowsList } });
      await actions.get({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isFetching: true }],
        [types.SET_FLOWS, flowsList],
        [types.SET_FLOW_UI_FLAG, { isFetching: false }],
      ]);
    });

    it('swallows the error and only toggles the fetch flag', async () => {
      FlowsAPI.get.mockRejectedValue(new Error('boom'));
      await actions.get({ commit });
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isFetching: true }],
        [types.SET_FLOW_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#show', () => {
    it('commits ADD_FLOW and returns the record on success', async () => {
      FlowsAPI.show.mockResolvedValue({ data: flowsList[0] });
      const result = await actions.show({ commit }, 2);
      expect(FlowsAPI.show).toHaveBeenCalledWith(2);
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isFetching: true }],
        [types.ADD_FLOW, flowsList[0]],
        [types.SET_FLOW_UI_FLAG, { isFetching: false }],
      ]);
      expect(result).toEqual(flowsList[0]);
    });

    it('propagates the error but still clears the fetch flag', async () => {
      FlowsAPI.show.mockRejectedValue(new Error('nope'));
      await expect(actions.show({ commit }, 2)).rejects.toThrow('nope');
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isFetching: true }],
        [types.SET_FLOW_UI_FLAG, { isFetching: false }],
      ]);
    });
  });

  describe('#create', () => {
    it('commits ADD_FLOW and returns the record on success', async () => {
      FlowsAPI.create.mockResolvedValue({ data: flowsList[0] });
      const result = await actions.create({ commit }, { name: 'novo' });
      expect(FlowsAPI.create).toHaveBeenCalledWith({ name: 'novo' });
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isCreating: true }],
        [types.ADD_FLOW, flowsList[0]],
        [types.SET_FLOW_UI_FLAG, { isCreating: false }],
      ]);
      expect(result).toEqual(flowsList[0]);
    });

    it('throws and clears the creating flag on error', async () => {
      FlowsAPI.create.mockRejectedValue(new Error('bad'));
      await expect(actions.create({ commit }, {})).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isCreating: true }],
        [types.SET_FLOW_UI_FLAG, { isCreating: false }],
      ]);
    });
  });

  describe('#update', () => {
    it('splits id from payload, commits EDIT_FLOW and returns the record', async () => {
      FlowsAPI.update.mockResolvedValue({ data: flowsList[1] });
      const result = await actions.update(
        { commit },
        { id: 1, name: 'renamed', active: true }
      );
      expect(FlowsAPI.update).toHaveBeenCalledWith(1, {
        name: 'renamed',
        active: true,
      });
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isUpdating: true }],
        [types.EDIT_FLOW, flowsList[1]],
        [types.SET_FLOW_UI_FLAG, { isUpdating: false }],
      ]);
      expect(result).toEqual(flowsList[1]);
    });

    it('throws and clears the updating flag on error', async () => {
      FlowsAPI.update.mockRejectedValue(new Error('bad'));
      await expect(actions.update({ commit }, { id: 1 })).rejects.toThrow(
        Error
      );
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isUpdating: true }],
        [types.SET_FLOW_UI_FLAG, { isUpdating: false }],
      ]);
    });
  });

  describe('#delete', () => {
    it('commits DELETE_FLOW with the id on success', async () => {
      FlowsAPI.delete.mockResolvedValue({});
      await actions.delete({ commit }, 7);
      expect(FlowsAPI.delete).toHaveBeenCalledWith(7);
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isDeleting: true }],
        [types.DELETE_FLOW, 7],
        [types.SET_FLOW_UI_FLAG, { isDeleting: false }],
      ]);
    });

    it('throws and clears the deleting flag on error', async () => {
      FlowsAPI.delete.mockRejectedValue(new Error('bad'));
      await expect(actions.delete({ commit }, 7)).rejects.toThrow(Error);
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isDeleting: true }],
        [types.SET_FLOW_UI_FLAG, { isDeleting: false }],
      ]);
    });
  });

  describe('#simulate', () => {
    it('returns the payload and toggles the simulating flag', async () => {
      FlowsAPI.simulate.mockResolvedValue({
        data: { steps: [], branch_path: [] },
      });
      const result = await actions.simulate(
        { commit },
        { id: 3, conversationId: 9 }
      );
      expect(FlowsAPI.simulate).toHaveBeenCalledWith(3, 9);
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isSimulating: true }],
        [types.SET_FLOW_UI_FLAG, { isSimulating: false }],
      ]);
      expect(result).toEqual({ steps: [], branch_path: [] });
    });

    it('lets the raw axios error propagate so response.status stays readable', async () => {
      const axiosError = { response: { status: 422 } };
      FlowsAPI.simulate.mockRejectedValue(axiosError);
      await expect(actions.simulate({ commit }, { id: 3 })).rejects.toEqual(
        axiosError
      );
      expect(commit.mock.calls).toEqual([
        [types.SET_FLOW_UI_FLAG, { isSimulating: true }],
        [types.SET_FLOW_UI_FLAG, { isSimulating: false }],
      ]);
    });
  });

  describe('#importLegacy', () => {
    it('refreshes the list via dispatch when it is not a dry run', async () => {
      FlowsAPI.importLegacy.mockResolvedValue({
        data: { dry_run: false, summary: {}, flows: [] },
      });
      const result = await actions.importLegacy(
        { commit, dispatch },
        { dryRun: false }
      );
      expect(FlowsAPI.importLegacy).toHaveBeenCalledWith(false);
      expect(dispatch).toHaveBeenCalledWith('get');
      expect(result).toEqual({ dry_run: false, summary: {}, flows: [] });
    });

    it('does not dispatch on a dry run', async () => {
      FlowsAPI.importLegacy.mockResolvedValue({ data: { dry_run: true } });
      await actions.importLegacy({ commit, dispatch }, { dryRun: true });
      expect(FlowsAPI.importLegacy).toHaveBeenCalledWith(true);
      expect(dispatch).not.toHaveBeenCalled();
    });
  });
});
