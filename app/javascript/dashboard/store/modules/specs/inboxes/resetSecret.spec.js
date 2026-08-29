import axios from 'axios';
import { actions } from '../../inboxes';
import * as types from '../../../mutation-types';

const commit = vi.fn();
global.axios = axios;
vi.mock('axios');

/**
 * Bloco 4.13 — a rotacao do segredo do canal API.
 *
 * `Settings.vue` despachava `inboxes/resetSecret` e a action NAO existia. Vuex nao lanca
 * nesse caso: escreve `[vuex] unknown action type` no console e devolve `undefined` — o
 * componente caia no ramo de erro e mostrava "nao foi possivel" para uma operacao que
 * nunca chegou a ser tentada. Defeito mudo dos dois lados: nada no servidor, nada na tela.
 */
describe('4.13 — inboxes/resetSecret', () => {
  const RESPOSTA = {
    id: 42,
    name: 'Canal API',
    secret: 'segredo-novo-em-claro',
  };

  it('a action EXISTE — o dispatch da tela tem para onde ir', () => {
    expect(typeof actions.resetSecret).toBe('function');
  });

  it('bate no endpoint de rotacao da inbox', async () => {
    axios.post.mockResolvedValue({ data: RESPOSTA });

    await actions.resetSecret({ commit }, 42);

    expect(axios.post).toHaveBeenCalledWith('/api/v1/inboxes/42/reset_secret');
  });

  // Sem gravar a resposta no store, o campo da tela continuaria mostrando o segredo
  // ANTIGO — que acabou de deixar de valer.
  it('grava a inbox devolvida, com o segredo novo', async () => {
    axios.post.mockResolvedValue({ data: RESPOSTA });

    await actions.resetSecret({ commit }, 42);

    expect(commit).toHaveBeenCalledWith(types.default.EDIT_INBOXES, RESPOSTA);
  });

  // O componente decide a mensagem por `if (response)`. Devolver `undefined` num sucesso
  // faria a tela dizer que falhou.
  it('devolve a inbox para quem despachou', async () => {
    axios.post.mockResolvedValue({ data: RESPOSTA });

    await expect(actions.resetSecret({ commit }, 42)).resolves.toEqual(
      RESPOSTA
    );
  });

  it('propaga o erro em vez de fingir sucesso', async () => {
    axios.post.mockRejectedValue(new Error('403'));

    await expect(actions.resetSecret({ commit }, 42)).rejects.toThrow(Error);
  });
});
