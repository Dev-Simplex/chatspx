/**
 * Bloco 4.21 — o lado do iframe.
 *
 * O que importa aqui, e é o que a armadilha herdada cobra: o ORDINAL da conversão
 * é o da abordagem que a produziu, não um número novo. É ele que vira `dedup_key`
 * no servidor, e é por isso que o visitante que manda três mensagens seguidas
 * conta como UMA conversão.
 *
 * O QUE ESTE ARQUIVO **NÃO** PROVA, e por que isso precisa estar escrito
 *
 * Aqui o `API.post` é um dublê, então o corpo afirmado abaixo é o corpo que o módulo
 * MONTA — nunca o corpo que o servidor ACEITA. Foi por essa fresta que o bloco passou
 * inteiro: o módulo não mandava `website_token`, o `BaseController` procurava o canal
 * por `nil`, toda chamada morria em 404 e o `.catch` do módulo engolia o 404. Estes
 * cinco exemplos ficavam verdes, os 16 do rspec também, e nenhum evento de abordagem
 * era gravado. Quem mede a junta é `approachEventJunta.spec.js` (axios de verdade,
 * requisição gravada em fixture) com `spec/requests/widget_approach_event_junta_spec.rb`
 * (a mesma fixture, enviada ao Rails de verdade). Este arquivo mede a LÓGICA do módulo.
 */
import { API } from 'widget/helpers/axios';

vi.mock('widget/helpers/axios', () => ({
  API: { post: vi.fn(() => Promise.resolve()) },
}));

const CAMINHO = '/api/v1/widget/approach_events';
const TOKEN_DO_CANAL = 'token-do-canal';

const EXIBICAO = {
  etapa: 'shown',
  approach: 'discreet',
  approach_configured: 'bold',
  ordinal: 2,
};

// O corpo que o módulo monta, com o `website_token` na frente porque é a chave que o
// `set_web_widget` consome antes de qualquer ação rodar.
const corpo = stage => ({
  website_token: TOKEN_DO_CANAL,
  stage,
  approach: 'discreet',
  approach_configured: 'bold',
  ordinal: 2,
});

describe('4.21 — registro da abordagem a partir do iframe', () => {
  let registrarEtapaDaAbordagem;
  let registrarConversaoDaAbordagem;

  beforeEach(async () => {
    vi.resetModules();
    API.post.mockClear();
    // `app/views/widgets/show.html.erb` escreve este objeto no documento do iframe, com
    // `websiteToken` entre as chaves, antes de o widget subir. Não é global inventado
    // para o teste: é a mesma fonte que `configMixin`, `telemetry.js` e `handlers.js` leem.
    window.chatwootWebChannel = { websiteToken: TOKEN_DO_CANAL };
    ({ registrarEtapaDaAbordagem, registrarConversaoDaAbordagem } =
      await import('../approachEvent'));
  });

  afterEach(() => {
    delete window.chatwootWebChannel;
  });

  it('manda a etapa com o nível efetivo e o configurado separados', async () => {
    await registrarEtapaDaAbordagem(EXIBICAO);

    expect(API.post).toHaveBeenCalledWith(CAMINHO, corpo('shown'));
  });

  it('a conversão carrega o ordinal da abordagem que a produziu', async () => {
    await registrarEtapaDaAbordagem(EXIBICAO);
    API.post.mockClear();

    await registrarConversaoDaAbordagem();

    expect(API.post).toHaveBeenCalledWith(CAMINHO, corpo('converted'));
  });

  it('três mensagens seguidas mandam o MESMO ordinal — a dedup do 5.03 faz o resto', async () => {
    await registrarEtapaDaAbordagem(EXIBICAO);
    API.post.mockClear();

    await registrarConversaoDaAbordagem();
    await registrarConversaoDaAbordagem();
    await registrarConversaoDaAbordagem();

    const ordinais = API.post.mock.calls.map(([, body]) => body.ordinal);
    expect(ordinais).toEqual([2, 2, 2]);
  });

  it('sem abordagem nesta página não há o que atribuir — não manda nada', async () => {
    await registrarConversaoDaAbordagem();

    expect(API.post).not.toHaveBeenCalled();
    // O par positivo, na mesma linha do tempo: sem ele esta asserção ficaria verde num
    // módulo que nunca manda nada — que é literalmente o estado em que o bloco estava.
    await registrarEtapaDaAbordagem(EXIBICAO);
    expect(API.post).toHaveBeenCalledTimes(1);
  });

  it('falha de rede é engolida: telemetria não pode aparecer para o visitante', async () => {
    API.post.mockRejectedValueOnce(new Error('offline'));

    await expect(registrarEtapaDaAbordagem(EXIBICAO)).resolves.toBeUndefined();
    // A promessa resolvida sozinha não prova engolimento: um módulo que nem chega a
    // chamar o `post` também resolve. O que prova é a chamada ter saído e rejeitado.
    expect(API.post).toHaveBeenCalledTimes(1);
  });
});
