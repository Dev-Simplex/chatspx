import * as MutationHelpers from 'shared/helpers/vuex/mutationHelpers';
import types from '../mutation-types';
import UnitsAPI from '../../api/units';
import { throwErrorMessage } from '../utils/api';

export const state = {
  records: [],
  uiFlags: {
    isFetching: false,
    isFetchingItem: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export const getters = {
  getUnits($state) {
    return $state.records;
  },
  getUnit: $state => id => $state.records.find(r => r.id === Number(id)),
  // Unidade de uma caixa — é assim que a conversa descobre a dela: pela caixa em que
  // entrou, sem coluna nova em `conversations`.
  getUnitByInboxId: $state => inboxId =>
    $state.records.find(r => (r.inbox_ids || []).includes(Number(inboxId))),
  getUIFlags($state) {
    return $state.uiFlags;
  },
};

export const actions = {
  get: async ({ commit }) => {
    commit(types.SET_UNITS_UI_FLAG, { isFetching: true });
    try {
      const response = await UnitsAPI.get();
      commit(types.SET_UNITS, response.data);
    } catch (error) {
      // A tela trata a ausência mostrando o estado vazio.
    } finally {
      commit(types.SET_UNITS_UI_FLAG, { isFetching: false });
    }
  },
  create: async ({ commit }, unitObj) => {
    commit(types.SET_UNITS_UI_FLAG, { isCreating: true });
    try {
      const response = await UnitsAPI.create({ unit: unitObj });
      commit(types.ADD_UNIT, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.SET_UNITS_UI_FLAG, { isCreating: false });
    }
  },
  update: async ({ commit }, { id, ...unitObj }) => {
    commit(types.SET_UNITS_UI_FLAG, { isUpdating: true });
    try {
      const response = await UnitsAPI.update(id, { unit: unitObj });
      commit(types.EDIT_UNIT, response.data);
      return response.data;
    } catch (error) {
      return throwErrorMessage(error);
    } finally {
      commit(types.SET_UNITS_UI_FLAG, { isUpdating: false });
    }
  },
  delete: async ({ commit }, id) => {
    commit(types.SET_UNITS_UI_FLAG, { isDeleting: true });
    try {
      await UnitsAPI.delete(id);
      commit(types.DELETE_UNIT, id);
    } catch (error) {
      throwErrorMessage(error);
    } finally {
      commit(types.SET_UNITS_UI_FLAG, { isDeleting: false });
    }
  },
};

export const mutations = {
  [types.SET_UNITS_UI_FLAG]($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },
  [types.SET_UNITS]: MutationHelpers.set,
  [types.ADD_UNIT]: MutationHelpers.create,
  [types.EDIT_UNIT]: MutationHelpers.update,
  [types.DELETE_UNIT]: MutationHelpers.destroy,
};

export default { namespaced: true, state, getters, actions, mutations };
