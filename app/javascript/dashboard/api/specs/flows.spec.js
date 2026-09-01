import flowsAPI from '../flows';
import ApiClient from '../ApiClient';

/**
 * Bloco 6.05 — O CLIENTE DO RELATÓRIO A/B, que é onde este tipo de tela morre calada.
 *
 * O endpoint é `get :experiment` no bloco `collection` de `resources :flows` — ou seja
 * `/flows/experiment`, e NÃO `/flows/:id/experiment`. Um experimento atravessa várias variantes
 * (vários flows), então não há id a pendurar. Errar esse detalhe dá 404 uniforme, igual ao de
 * "não existe": a mesma armadilha já paga nesta base no bloco 4.18.
 *
 * O segundo fato medido aqui é a JANELA AUSENTE. `FlowsController#experiment_period` devolve
 * `nil` — todo o histórico — quando `since` e `until` faltam, e é isso que faz um experimento
 * encerrado continuar legível. Um cliente que mandasse `since: undefined`/`''` estaria pedindo
 * uma janela e dependendo de o servidor tratar o branco; o teste trava a omissão.
 */
describe('#Flows API (6.05 — relatório do teste A/B)', () => {
  const originalAxios = window.axios;
  const axiosMock = {
    get: vi.fn(() => Promise.resolve()),
    post: vi.fn(() => Promise.resolve()),
  };

  beforeEach(() => {
    window.axios = axiosMock;
    // O `ApiClient` tira o id da conta do caminho da janela, como em produção.
    window.history.pushState({}, '', '/app/accounts/7/settings/automation');
  });

  afterEach(() => {
    window.axios = originalAxios;
  });

  it('é um ApiClient escopado na conta', () => {
    expect(flowsAPI).toBeInstanceOf(ApiClient);
  });

  it('lê o relatório na rota de COLEÇÃO, com a chave no query string', () => {
    flowsAPI.getExperiment('captura-2026');

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/7/flows/experiment',
      { params: { key: 'captura-2026' } }
    );
  });

  // A URL não pode ganhar segmento nenhum entre `flows` e `experiment`: não existe "o flow dono
  // do experimento", e a chave é DADO, não caminho. Medido pelo que o caminho NÃO contém e pelo
  // que os params contêm — uma asserção só sobre o formato do id passaria com a chave no
  // caminho, que é justamente o erro plausível aqui (a chave não é numérica).
  it('não pendura o relatório em nenhum flow: a chave vai no query, nunca no caminho', () => {
    flowsAPI.getExperiment('captura-2026');

    const [url, config] = axiosMock.get.mock.calls[0];
    expect(url).toMatch(/\/flows\/experiment$/);
    expect(url).not.toContain('captura-2026');
    expect(config.params.key).toBe('captura-2026');
  });

  it('sem janela, NÃO manda since nem until — é assim que se pede todo o histórico', () => {
    flowsAPI.getExperiment('captura-2026');

    const [, config] = axiosMock.get.mock.calls[0];
    expect(Object.keys(config.params)).toEqual(['key']);
  });

  it('com janela, manda since e until como o controller os lê', () => {
    flowsAPI.getExperiment('captura-2026', {
      since: '2026-08-01',
      until: '2026-08-31',
    });

    expect(axiosMock.get).toHaveBeenCalledWith(
      '/api/v1/accounts/7/flows/experiment',
      {
        params: {
          key: 'captura-2026',
          since: '2026-08-01',
          until: '2026-08-31',
        },
      }
    );
  });

  // Só uma das pontas é legítima (ex.: "de 1º de agosto até agora"), e o controller trata a
  // outra (`Time.zone.at(0)` / `Time.current`). O cliente não pode inventar a que falta.
  it('manda só a ponta que veio quando a janela é aberta de um lado', () => {
    flowsAPI.getExperiment('captura-2026', { since: '2026-08-01' });

    const [, config] = axiosMock.get.mock.calls[0];
    expect(config.params).toEqual({ key: 'captura-2026', since: '2026-08-01' });
  });
});
