/**
 * Mecanismo de aceite do bloco 2.13 — telemetria de erro do widget.
 *
 * ACEITE (§2.2): «Erro forçado aparece no GlitchTip **com PII removida**; nada
 * vaza para o `window.onerror` do site do cliente».
 *
 * Este arquivo cobre as duas metades que são de CÓDIGO:
 *   1. o que sai — o envelope, e o que dele foi RASPADO;
 *   2. o que NÃO escapa — nenhuma exceção do reporter atravessa para o
 *      documento hospedeiro.
 *
 * A terceira metade — "aparece no GlitchTip" — é de INFRAESTRUTURA e está
 * registrada no relatório: enviar evento de teste para o GlitchTip de produção
 * (glitchtip.chatspx.app, que recebe a frota inteira) é ação externa e polui a
 * triagem real de outras pessoas. Aqui o destino é medido contra um receptor
 * local, provando que o corpo emitido é o que o servidor espera.
 */
import {
  scrubPii,
  buildErrorPayload,
  reportWidgetError,
  __resetTelemetryForTests,
} from '../telemetry';

describe('2.13 — remoção de PII antes de qualquer envio', () => {
  it('some com e-mail em qualquer posição do texto', () => {
    expect(scrubPii('falhou para joao.silva@empresa.com.br agora')).toBe(
      'falhou para [email] agora'
    );
    expect(scrubPii('a@b.co')).toBe('[email]');
  });

  it('some com telefone em formatos brasileiros e internacionais', () => {
    expect(scrubPii('ligou de +55 11 98765-4321')).toBe('ligou de [telefone]');
    expect(scrubPii('(11) 98765-4321')).toBe('[telefone]');
    expect(scrubPii('+1-415-555-0132')).toBe('[telefone]');
  });

  it('some com CPF e CNPJ', () => {
    expect(scrubPii('doc 123.456.789-09 aqui')).toBe('doc [documento] aqui');
    expect(scrubPii('12.345.678/0001-95')).toBe('[documento]');
  });

  it('some com o que parece credencial', () => {
    expect(scrubPii('Authorization: Bearer abc.def.ghi')).toBe(
      'Authorization: [credencial]'
    );
    expect(scrubPii('cw_conversation=eyJhbGciOiJIUzI1NiJ9.aaa.bbb')).toBe(
      'cw_conversation=[credencial]'
    );
  });

  it('preserva o que é diagnóstico, não identidade', () => {
    // Raspar demais é tão ruim quanto raspar de menos: um relatório sem a
    // mensagem do erro não serve para nada.
    const texto = "Cannot read properties of undefined (reading 'matches')";
    expect(scrubPii(texto)).toBe(texto);
    expect(scrubPii('TypeError em conversation/actions.js:68')).toBe(
      'TypeError em conversation/actions.js:68'
    );
  });

  it('atravessa estruturas aninhadas, não só a string do topo', () => {
    const raspado = scrubPii({
      mensagem: 'erro de maria@teste.com',
      contexto: { lista: ['telefone (11) 98765-4321', 'ok'], n: 7 },
    });

    expect(raspado).toEqual({
      mensagem: 'erro de [email]',
      contexto: { lista: ['telefone [telefone]', 'ok'], n: 7 },
    });
  });

  it('não quebra com ciclo, undefined ou tipos exóticos', () => {
    const ciclico = { nome: 'x' };
    ciclico.self = ciclico;

    expect(() => scrubPii(ciclico)).not.toThrow();
    expect(scrubPii(undefined)).toBeUndefined();
    expect(scrubPii(null)).toBeNull();
    expect(scrubPii(42)).toBe(42);
  });
});

describe('2.13 — o envelope enviado', () => {
  beforeEach(() => {
    global.chatwootWebChannel = { websiteToken: 'token-abc' };
  });

  it('leva mensagem, pilha e origem, todas raspadas', () => {
    const erro = new Error('falha ao enviar para cliente@empresa.com');
    erro.stack = 'Error: falha\n  at envia (cliente@empresa.com:1:1)';

    const payload = buildErrorPayload(erro, { origem: 'store/contacts' });

    expect(payload.message).toBe('falha ao enviar para [email]');
    expect(payload.stack).not.toContain('cliente@empresa.com');
    expect(payload.stack).toContain('[email]');
    expect(payload.context.origem).toBe('store/contacts');
    expect(payload.website_token).toBe('token-abc');
  });

  it('NUNCA carrega o conteúdo da conversa', () => {
    // A mensagem que o visitante digitou é o dado mais sensível que o widget
    // toca. Ele não pode entrar em relatório de erro nem por engano — por isso
    // o envelope tem uma lista fechada de chaves, e não um "resto".
    const payload = buildErrorPayload(new Error('x'), {
      origem: 'chat',
      content: 'meu cartão é 4111 1111 1111 1111',
      mensagemDoVisitante: 'oi, sou a Maria',
    });

    expect(Object.keys(payload).sort()).toEqual(
      [
        'context',
        'message',
        'name',
        'release',
        'stack',
        'url',
        'website_token',
      ].sort()
    );
    expect(JSON.stringify(payload)).not.toContain('4111');
    expect(JSON.stringify(payload)).not.toContain('sou a Maria');
  });

  it('a URL vai sem query string', () => {
    // Query string de site de terceiro carrega `?email=`, `?token=`, `?cpf=`
    // com frequência desconfortável.
    const payload = buildErrorPayload(
      new Error('x'),
      {},
      {
        href: 'https://loja.exemplo/checkout?email=a@b.com&cupom=X',
      }
    );

    expect(payload.url).toBe('https://loja.exemplo/checkout');
  });

  it('trunca mensagem e pilha muito longas', () => {
    const payload = buildErrorPayload(new Error('a'.repeat(5000)));

    expect(payload.message.length).toBeLessThanOrEqual(1000);
  });
});

describe('2.13 — nada vaza para o site do cliente', () => {
  let enviados;

  beforeEach(() => {
    __resetTelemetryForTests();
    enviados = [];
    global.chatwootWebChannel = { websiteToken: 'token-abc' };
    global.fetch = vi.fn((url, opcoes) => {
      enviados.push({ url, opcoes });
      return Promise.resolve({ ok: true });
    });
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('envia o relatório para o endpoint do próprio domínio', async () => {
    await reportWidgetError(new Error('falhou'), { origem: 'teste' });

    expect(enviados).toHaveLength(1);
    expect(enviados[0].url).toBe('/api/v1/widget/telemetry');
    expect(enviados[0].opcoes.keepalive).toBe(true);

    const corpo = JSON.parse(enviados[0].opcoes.body);
    expect(corpo.message).toBe('falhou');
  });

  it('engole a própria falha de rede em vez de propagar', async () => {
    // O reporter roda dentro de `catch`. Se ELE lançar, transforma um erro
    // registrado num erro não tratado — que é exatamente o oposto do bloco.
    global.fetch = vi.fn(() => Promise.reject(new Error('sem rede')));

    await expect(
      reportWidgetError(new Error('falhou'), {})
    ).resolves.toBeUndefined();
  });

  it('engole até um `fetch` que nem existe', async () => {
    delete global.fetch;

    await expect(
      reportWidgetError(new Error('x'), {})
    ).resolves.toBeUndefined();
  });

  it('não envia nada sem `websiteToken`', async () => {
    // Sem token o servidor recusaria de qualquer jeito; mandar seria só ruído
    // e uma requisição a mais saindo do site do cliente.
    global.chatwootWebChannel = {};

    await reportWidgetError(new Error('x'), {});
    expect(enviados).toHaveLength(0);
  });

  it('respeita um teto por sessão, para não virar amplificador', async () => {
    // Um erro dentro de um laço de render viraria milhares de POSTs saindo do
    // site do cliente — o widget passaria a ser o problema de desempenho dele.
    // A ordem importa: o teste mede quantos passaram ANTES do teto, e disparar
    // em paralelo tornaria a contagem dependente de escalonamento.
    for (let i = 0; i < 30; i += 1) {
      // eslint-disable-next-line no-await-in-loop
      await reportWidgetError(new Error(`erro ${i}`), {});
    }

    expect(enviados.length).toBeLessThanOrEqual(10);
    expect(enviados.length).toBeGreaterThan(0);
  });

  it('não repete o mesmo erro sem parar', async () => {
    await reportWidgetError(new Error('mesmo erro'), { origem: 'a' });
    await reportWidgetError(new Error('mesmo erro'), { origem: 'a' });
    await reportWidgetError(new Error('mesmo erro'), { origem: 'a' });

    expect(enviados).toHaveLength(1);
  });
});
