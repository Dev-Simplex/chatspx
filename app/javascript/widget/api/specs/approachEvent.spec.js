/**
 * Bloco 4.21 — o lado do iframe.
 *
 * O que importa aqui, e é o que a armadilha herdada cobra: o ORDINAL da conversão
 * é o da abordagem que a produziu, não um número novo. É ele que vira `dedup_key`
 * no servidor, e é por isso que o visitante que manda três mensagens seguidas
 * conta como UMA conversão.
 */
import { API } from 'widget/helpers/axios';

vi.mock('widget/helpers/axios', () => ({
  API: { post: vi.fn(() => Promise.resolve()) },
}));

const CAMINHO = '/api/v1/widget/approach_events';

const EXIBICAO = {
  etapa: 'shown',
  approach: 'discreet',
  approach_configured: 'bold',
  ordinal: 2,
};

describe('4.21 — registro da abordagem a partir do iframe', () => {
  let registrarEtapaDaAbordagem;
  let registrarConversaoDaAbordagem;

  beforeEach(async () => {
    vi.resetModules();
    API.post.mockClear();
    ({ registrarEtapaDaAbordagem, registrarConversaoDaAbordagem } =
      await import('../approachEvent'));
  });

  it('manda a etapa com o nível efetivo e o configurado separados', async () => {
    await registrarEtapaDaAbordagem(EXIBICAO);

    expect(API.post).toHaveBeenCalledWith(CAMINHO, {
      stage: 'shown',
      approach: 'discreet',
      approach_configured: 'bold',
      ordinal: 2,
    });
  });

  it('a conversão carrega o ordinal da abordagem que a produziu', async () => {
    await registrarEtapaDaAbordagem(EXIBICAO);
    API.post.mockClear();

    await registrarConversaoDaAbordagem();

    expect(API.post).toHaveBeenCalledWith(CAMINHO, {
      stage: 'converted',
      approach: 'discreet',
      approach_configured: 'bold',
      ordinal: 2,
    });
  });

  it('três mensagens seguidas mandam o MESMO ordinal — a dedup do 5.03 faz o resto', async () => {
    await registrarEtapaDaAbordagem(EXIBICAO);
    API.post.mockClear();

    await registrarConversaoDaAbordagem();
    await registrarConversaoDaAbordagem();
    await registrarConversaoDaAbordagem();

    const ordinais = API.post.mock.calls.map(([, corpo]) => corpo.ordinal);
    expect(ordinais).toEqual([2, 2, 2]);
  });

  it('sem abordagem nesta página não há o que atribuir — não manda nada', async () => {
    await registrarConversaoDaAbordagem();

    expect(API.post).not.toHaveBeenCalled();
  });

  it('falha de rede é engolida: telemetria não pode aparecer para o visitante', async () => {
    API.post.mockRejectedValueOnce(new Error('offline'));

    await expect(registrarEtapaDaAbordagem(EXIBICAO)).resolves.toBeUndefined();
  });
});
