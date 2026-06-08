// Bridge entre Vuex e Pinia durante migracao P0-05.
// Usado por componentes que querem acessar getters/actions sem se preocupar
// se a store ja foi migrada. Quando todas as ondas terminarem (P0-05 onda 3
// cleanup), este bridge sera removido junto com o Vuex.

import { computed } from 'vue';
import { useStore as useVuexStore } from 'vuex';
import { storeToRefs } from 'pinia';

/**
 * Retorna um ref reativo apontando para o getter equivalente.
 * Tenta Pinia primeiro; se falhar, cai pra Vuex.
 *
 * @param {string} vuexGetter Caminho do getter Vuex (ex: 'auth/getCurrentUser')
 * @param {Function} piniaStoreFactory Factory (ex: useAuthStore)
 * @param {string} piniaGetter Nome do getter no store Pinia
 */
export function useBridgedGetter(vuexGetter, piniaStoreFactory, piniaGetter) {
  try {
    const piniaStore = piniaStoreFactory();
    const refs = storeToRefs(piniaStore);
    if (refs[piniaGetter]) return refs[piniaGetter];
  } catch (_) {
    // Pinia nao montado ainda ou store nao definida — fallback Vuex
  }
  const vuex = useVuexStore();
  return computed(() => vuex.getters[vuexGetter]);
}

/**
 * Retorna uma funcao que invoca a action Pinia se existir, senao dispatch Vuex.
 */
export function useBridgedAction(vuexAction, piniaStoreFactory, piniaAction) {
  return async (...args) => {
    try {
      const piniaStore = piniaStoreFactory();
      if (typeof piniaStore[piniaAction] === 'function') {
        return piniaStore[piniaAction](...args);
      }
    } catch (_) {
      // fallback Vuex abaixo
    }
    const vuex = useVuexStore();
    return vuex.dispatch(vuexAction, ...args);
  };
}
