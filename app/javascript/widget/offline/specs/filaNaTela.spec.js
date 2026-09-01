/**
 * Mecanismo de aceite do bloco 2.16 — a fila offline LIGADA NA TELA.
 *
 * ACEITE (§2.2): «3 mensagens digitadas offline chegam **em ordem** na volta;
 * nenhum evento de digitando em lote».
 *
 * ── POR QUE ESTE ARQUIVO EXISTE ──────────────────────────────────────────────
 *
 * `queue.spec.js` já era verde antes dele, com sete exemplos, e mesmo assim o
 * bloco estava morto: `grep createOfflineQueue` achava só o módulo e o próprio
 * spec. Ninguém instanciava a fila, ninguém enfileirava, ninguém drenava. Um
 * teste de unidade de módulo passa exatamente igual com o consumidor desligado
 * — foi assim que a fila atravessou uma onda inteira sem existir para o
 * visitante.
 *
 * Então aqui nada é medido por chamada de função nem por identidade de módulo.
 * A tela é a de mensagens de verdade (`Messages.vue` → `ConversationWrap`), o
 * store é o de produção (`widget/store`, com o plugin que liga a drenagem), o
 * caminho de envio é o `conversation/sendMessage` que o composer dispara, e a
 * volta da rede é o mesmo `reportConnected()` que `actionCable.js` chama. O que
 * se pergunta é o que está RENDERIZADO, e em que ordem.
 *
 * ── POR QUE O SERVIDOR FALSO ATRASA AO CONTRÁRIO ─────────────────────────────
 *
 * O id da mensagem é atribuído na RESOLUÇÃO, não na chamada, e o atraso
 * DIMINUI a cada envio (30 ms, 20 ms, 10 ms). Uma drenagem paralela dispararia
 * os três POSTs juntos e eles voltariam ao contrário — a terceira primeiro —,
 * ganhando os ids menores e aparecendo no topo da lista. Só a drenagem
 * sequencial põe as três na ordem em que foram escritas. Sem esse atraso
 * invertido, `Promise.all` passaria neste teste, porque os POSTs saem em ordem
 * de qualquer jeito: o que distingue os dois desenhos é a ORDEM DE CHEGADA.
 *
 * ── POR QUE OS IMPORTS SÃO DINÂMICOS ─────────────────────────────────────────
 *
 * A fila e o monitor são singletons de `widget/state`, criados na avaliação do
 * módulo, e o plugin do store se registra no monitor quando `widget/store` é
 * avaliado. Importando estático, o segundo exemplo herdaria a fila suja do
 * primeiro. `vi.resetModules()` antes de cada `import()` dá a cada exemplo um
 * par novo — e o mesmo par para o teste e para o store.
 */
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';

// ── A ARMADILHA QUE CUSTOU UMA RODADA INTEIRA ────────────────────────────────
//
// `vi.mock` fica registrado, mas `vi.resetModules()` faz o `import('widget/store')`
// abaixo REAVALIAR o grafo inteiro — inclusive o próprio dublê de
// `widget/helpers/axios`. O `API` de um `import` estático no topo deste arquivo
// seria a instância ANTIGA do dublê: configurar `API.post` nele não teria efeito
// nenhum sobre o store, que já estaria falando com outro objeto.
//
// O sintoma foi enganoso: a fila enfileirava (o `API.post` novo devolve
// `undefined`, o `await` estoura, o `catch` trata como falha de rede) e nunca
// drenava. Parecia bug da drenagem; era o dublê errado. Por isso o `API` vem do
// MESMO `import()` dinâmico do resto do ambiente.
vi.mock('widget/helpers/axios');

// Cada exemplo REAVALIA o grafo inteiro do store (`vi.resetModules()` + o
// `import()` de `widget/store`), e isso é trabalho de CPU: 30 s bastam sozinho e
// não bastam com a suíte inteira em paralelo — um vermelho que não fala do
// código. Mesma razão do teto de `estadosDeVerdade.spec.js`.
vi.setConfig({ testTimeout: 60000, hookTimeout: 60000 });

const i18n = createI18n({
  legacy: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

const URL_MENSAGEM = '/api/v1/widget/messages';
const URL_DIGITANDO = '/api/v1/widget/conversations/toggle_typing';

/** A forma REAL de uma queda de rede no axios: promessa rejeitada SEM `response`. */
const erroDeRede = () => {
  const erro = new Error('Network Error');
  erro.code = 'ERR_NETWORK';
  erro.request = {};
  return erro;
};

/** Um 422 tem `response` — é recusa do servidor, não queda de rede. */
const erroDeServidor = () => {
  const erro = new Error('Request failed with status code 422');
  erro.response = { status: 422, data: {} };
  return erro;
};

// A bolha real é assunto do 2.02; o que este arquivo precisa dela é o texto e o
// estado, na posição em que a lista a colocou.
const BolhaFalsa = {
  name: 'ChatMessage',
  props: { message: { type: Object, default: () => ({}) } },
  template:
    '<div class="bolha" :data-status="message.status">{{ message.content }}</div>',
};

const RodapeFalso = { name: 'ChatFooter', template: '<footer />' };

let ambiente;

/** O que está escrito na tela, de cima para baixo. */
const textosNaTela = tela => tela.findAll('.bolha').map(b => b.text());

const statusNaTela = tela =>
  tela.findAll('.bolha').map(b => b.attributes('data-status'));

/**
 * O visitante digitando e apertando enter, uma mensagem de cada vez.
 *
 * SEQUENCIAL de propósito: o aceite é sobre ORDEM, e disparar os três
 * `dispatch` em paralelo mediria uma coisa que o composer não faz.
 */
const digitar = conteudos =>
  conteudos.reduce(
    (anterior, content) =>
      anterior.then(() =>
        ambiente.store.dispatch('conversation/sendMessage', { content })
      ),
    Promise.resolve()
  );

const montarTela = async () => {
  const Messages = (await import('widget/views/Messages.vue')).default;
  return mount(Messages, {
    global: {
      plugins: [ambiente.store, i18n],
      mocks: { $t: chave => i18n.global.t(chave) },
      stubs: { ChatMessage: BolhaFalsa, ChatFooter: RodapeFalso },
    },
  });
};

beforeEach(async () => {
  vi.resetModules();

  // `endPoints.sendMessage` monta a URL lendo
  // `window.WOOT_WIDGET.$root.$i18n.locale` (`urlParamsHelper.js:3`). Sem este
  // global o montador da URL lança ANTES do POST, e o servidor falso deste
  // arquivo nunca chega a ser chamado: o teste mediria o `catch` do widget
  // reagindo a um defeito do próprio teste. O global é o que o widget de
  // verdade instala no boot.
  window.WOOT_WIDGET = { $root: { $i18n: { locale: 'pt_BR' } } };

  const recebidas = [];
  let rede = 'caida';
  let proximoId = 100;

  const { API } = await import('widget/helpers/axios');
  API.post.mockImplementation((url, params) => {
    if (rede === 'caida') return Promise.reject(erroDeRede());
    const atraso = 40 - 10 * recebidas.filter(r => r.url === url).length;
    return new Promise(resolve => {
      setTimeout(() => {
        proximoId += 1;
        recebidas.push({ url, params, id: proximoId });
        resolve({
          data: {
            id: proximoId,
            inbox_id: 7,
            conversation_id: 77,
            content: params?.message?.content,
            echo_id: params?.message?.echo_id,
            message_type: 0,
            status: 'sent',
            created_at: 1700000000 + proximoId,
          },
        });
      }, atraso);
    });
  });
  API.get.mockResolvedValue({ data: { payload: [], meta: {} } });

  ambiente = {
    API,
    recebidas,
    recusadas: [],
    voltarARede: () => {
      rede = 'boa';
    },
    ...(await import('widget/state')),
    store: (await import('widget/store')).default,
  };
  ambiente.pararDeOuvir = ambiente.onIntentRejected(r =>
    ambiente.recusadas.push(r)
  );
});

afterEach(() => {
  ambiente.pararDeOuvir?.();
});

const mensagensEntregues = () =>
  ambiente.recebidas
    .filter(r => r.url.startsWith(URL_MENSAGEM))
    .map(r => r.params.message.content);

const digitandoEntregues = () =>
  ambiente.recebidas.filter(r => r.url.startsWith(URL_DIGITANDO));

describe('2.16 — três mensagens digitadas offline chegam em ordem', () => {
  it('as três aparecem na tela, na ordem em que foram escritas, depois da volta da rede', async () => {
    const tela = await montarTela();

    await digitar(['primeira', 'segunda', 'terceira']);
    await vi.waitFor(() => expect(ambiente.widgetOfflineQueue.size).toBe(3));
    await tela.vm.$nextTick();

    // Antes da volta: as três estão na tela, escritas, e nenhuma foi entregue.
    expect(textosNaTela(tela)).toEqual(['primeira', 'segunda', 'terceira']);
    expect(statusNaTela(tela)).toEqual(['failed', 'failed', 'failed']);
    expect(mensagensEntregues()).toEqual([]);

    ambiente.voltarARede();
    ambiente.widgetConnectionMonitor.reportConnected();

    await vi.waitFor(() => expect(mensagensEntregues().length).toBe(3));
    await tela.vm.$nextTick();

    expect(mensagensEntregues()).toEqual(['primeira', 'segunda', 'terceira']);
    expect(textosNaTela(tela)).toEqual(['primeira', 'segunda', 'terceira']);
    expect(statusNaTela(tela)).toEqual(['sent', 'sent', 'sent']);
    expect(ambiente.widgetOfflineQueue.size).toBe(0);
  });

  it('a mensagem não fica duplicada: a que falhou some quando a entregue chega', async () => {
    const tela = await montarTela();

    await ambiente.store.dispatch('conversation/sendMessage', {
      content: 'única',
    });
    await vi.waitFor(() => expect(ambiente.widgetOfflineQueue.size).toBe(1));

    ambiente.voltarARede();
    ambiente.widgetConnectionMonitor.reportConnected();
    await vi.waitFor(() => expect(mensagensEntregues().length).toBe(1));
    await tela.vm.$nextTick();

    expect(textosNaTela(tela)).toEqual(['única']);
  });

  it('o reenvio usa a MESMA chave de idempotência da tentativa que falhou (2.15)', async () => {
    await montarTela();

    await ambiente.store.dispatch('conversation/sendMessage', {
      content: 'com chave',
    });
    await vi.waitFor(() => expect(ambiente.widgetOfflineQueue.size).toBe(1));

    const chaveDaPrimeiraTentativa =
      ambiente.API.post.mock.calls[0][1].message.echo_id;
    expect(chaveDaPrimeiraTentativa).toBeTruthy();

    ambiente.voltarARede();
    ambiente.widgetConnectionMonitor.reportConnected();
    await vi.waitFor(() => expect(mensagensEntregues().length).toBe(1));

    expect(ambiente.recebidas[0].params.message.echo_id).toBe(
      chaveDaPrimeiraTentativa
    );
  });
});

describe('2.16 — nenhum evento de digitando em lote', () => {
  it('digitar offline não vira rajada de digitando na volta — e as mensagens chegam', async () => {
    // Os dois fatos no MESMO exemplo de propósito. "Zero digitando" sozinho
    // passa com a fila desligada, porque aí nada é drenado; medido junto com a
    // entrega das mensagens, ele só pode passar com a drenagem funcionando.
    const tela = await montarTela();

    await ambiente.store.dispatch('conversation/toggleUserTyping', {
      typingStatus: 'on',
    });
    await ambiente.store.dispatch('conversation/sendMessage', {
      content: 'primeira',
    });
    await ambiente.store.dispatch('conversation/toggleUserTyping', {
      typingStatus: 'on',
    });
    await ambiente.store.dispatch('conversation/sendMessage', {
      content: 'segunda',
    });
    await ambiente.store.dispatch('conversation/toggleUserTyping', {
      typingStatus: 'off',
    });
    await vi.waitFor(() => expect(ambiente.widgetOfflineQueue.size).toBe(2));

    // A recusa é MEDIDA, não presumida: os três "digitando" foram mesmo
    // OFERECIDOS à fila e recusados por serem transitórios. Sem esta asserção,
    // "zero digitando na volta" também passaria se ninguém tivesse oferecido
    // nada — que é o falso verde que este bloco inteiro existe para não repetir.
    expect(ambiente.recusadas.map(r => r.reason)).toEqual([
      'transitorio',
      'transitorio',
      'transitorio',
    ]);

    ambiente.voltarARede();
    ambiente.widgetConnectionMonitor.reportConnected();
    await vi.waitFor(() => expect(mensagensEntregues().length).toBe(2));
    await tela.vm.$nextTick();

    expect(mensagensEntregues()).toEqual(['primeira', 'segunda']);
    expect(digitandoEntregues()).toEqual([]);
    expect(textosNaTela(tela)).toEqual(['primeira', 'segunda']);
  });
});

describe('2.16 — o que NÃO entra na fila', () => {
  it('recusa do servidor (422) não é queda de rede: não enfileira e não reenvia', async () => {
    // FORÇANDO A CONDIÇÃO RUIM: se `enfileirarNaFalhaDeRede` enfileirasse
    // qualquer erro, o visitante veria a mesma mensagem recusada ser reenviada
    // a cada reconexão, para sempre.
    ambiente.API.post.mockRejectedValue(erroDeServidor());
    const tela = await montarTela();

    await ambiente.store.dispatch('conversation/sendMessage', {
      content: 'recusada',
    });
    // `sendMessage` não espera o POST — ele dispara `sendMessageWithData` e
    // volta, para o composer limpar na hora. Um `$nextTick` só não alcança a
    // resposta do servidor.
    await vi.waitFor(() => expect(statusNaTela(tela)).toEqual(['failed']));

    expect(ambiente.widgetOfflineQueue.size).toBe(0);

    ambiente.widgetConnectionMonitor.reportConnected();
    await tela.vm.$nextTick();

    expect(mensagensEntregues()).toEqual([]);
  });

  it('a fila para na primeira falha e NÃO pula a mensagem — a ordem sobrevive', async () => {
    const tela = await montarTela();

    await digitar(['a', 'b', 'c']);
    await vi.waitFor(() => expect(ambiente.widgetOfflineQueue.size).toBe(3));

    // A rede volta pela metade: 'a' passa, 'b' cai de novo.
    let entregues = 0;
    ambiente.API.post.mockImplementation((url, params) => {
      if (params?.message?.content !== 'a') return Promise.reject(erroDeRede());
      entregues += 1;
      ambiente.recebidas.push({ url, params, id: 500 + entregues });
      return Promise.resolve({
        data: {
          id: 500 + entregues,
          conversation_id: 77,
          content: params.message.content,
          message_type: 0,
          status: 'sent',
          created_at: 1700000000 + entregues,
        },
      });
    });

    ambiente.widgetConnectionMonitor.reportConnected();
    await vi.waitFor(() => expect(ambiente.widgetOfflineQueue.size).toBe(2));
    await tela.vm.$nextTick();

    expect(mensagensEntregues()).toEqual(['a']);
    expect(
      ambiente.widgetOfflineQueue.peek().map(i => i.message.content)
    ).toEqual(['b', 'c']);
    expect(textosNaTela(tela)).toEqual(['a', 'b', 'c']);
  });
});
