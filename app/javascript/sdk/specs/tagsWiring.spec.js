import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

/**
 * A JUNCAO dos blocos 5.05/5.10/5.16 — e o unico lugar onde ela pode ser medida.
 *
 * Cada lado ja tem o proprio verde: o store do widget monta a mensagem e a testa; a ponte de
 * tags recebe `{ name, properties, eventId }` e a testa. O que nenhum dos dois enxerga e se o
 * NOME da mensagem bate. Renomear `trackingEvent` de um lado so deixa os dois arquivos verdes
 * e a medicao do cliente morta — e o sintoma seria uma queda de conversao num relatorio de
 * midia, semanas depois. Este arquivo pega a mensagem que o store REALMENTE produz e a entrega
 * ao roteador que o host REALMENTE usa.
 */
describe('5.10 — a mensagem do iframe encontra a ponte no host', () => {
  let IFrameHelper;
  let ponte;

  beforeEach(async () => {
    vi.resetModules();
    ({ IFrameHelper } = await import('../IFrameHelper'));
    ponte = { onTrackingEvent: vi.fn(), onWindowEvent: vi.fn() };
    IFrameHelper.tags = ponte;
  });

  afterEach(() => {
    delete IFrameHelper.tags;
    vi.restoreAllMocks();
  });

  /** A mensagem exatamente como `widget/store/modules/events.js` a monta. */
  const mensagemDoStore = {
    event: 'trackingEvent',
    name: 'chatspx_orcamento_pedido',
    properties: { plano: 'pro' },
    eventId: 'uuid-9',
  };

  it('o roteador do host tem um handler para o nome que o store envia', () => {
    expect(typeof IFrameHelper.events[mensagemDoStore.event]).toBe('function');
  });

  it('e esse handler entrega o fato inteiro a ponte', () => {
    IFrameHelper.events[mensagemDoStore.event](mensagemDoStore);

    expect(ponte.onTrackingEvent).toHaveBeenCalledWith(mensagemDoStore);
  });

  it('onEvent alimenta a ponte com o evento de window ANTES de publica-lo', () => {
    IFrameHelper.events.onEvent({
      eventIdentifier: 'chatwoot:conversation-created',
      data: { conversation_id: 7 },
    });

    expect(ponte.onWindowEvent).toHaveBeenCalledWith(
      'chatwoot:conversation-created',
      { conversation_id: 7 }
    );
  });

  // Sem tracking configurado o coletor nunca e buscado e `IFrameHelper.tags` fica indefinido.
  // O `?.` e o que faz "sem configuracao, nenhuma tag nossa" nao custar um `if` — mas so
  // vale se ele estiver la, e um refactor descuidado o remove sem nenhum teste reclamar.
  it('sem ponte carregada, os dois caminhos nao lancam', () => {
    delete IFrameHelper.tags;

    expect(() =>
      IFrameHelper.events.trackingEvent({ name: 'chatspx_a' })
    ).not.toThrow();
    expect(() =>
      IFrameHelper.events.onEvent({
        eventIdentifier: 'chatwoot:ready',
        data: {},
      })
    ).not.toThrow();
  });
});

describe('5.10 — a ponte viaja no artefato sob demanda, nunca no sdk.js', () => {
  it('o barril do coletor exporta createTagsBridge', async () => {
    const coletor = await import('../tracking/index');

    expect(typeof coletor.createTagsBridge).toBe('function');
  });

  /**
   * T-C4.9 / A13. O `sdk.js` e baixado por 100% dos visitantes de todos os sites; a ponte so
   * serve a quem configurou tracking. Se alguem importar `./tracking/tags` no `IFrameHelper`
   * ou no entrypoint, o Rollup a INLINA no `sdk.js` (`inlineDynamicImports: true`) e o custo
   * cai sobre quem nunca vai usa-la — sem nenhum erro de build para avisar.
   */
  it('nem o IFrameHelper nem o entrypoint importam tags.js', async () => {
    const { readFileSync } = await import('node:fs');

    [
      'app/javascript/sdk/IFrameHelper.js',
      'app/javascript/entrypoints/sdk.js',
    ].forEach(caminho => {
      const fonte = readFileSync(caminho, 'utf8');
      expect(fonte).not.toMatch(/from\s+'[^']*tracking\/tags'/);
    });
  });
});
