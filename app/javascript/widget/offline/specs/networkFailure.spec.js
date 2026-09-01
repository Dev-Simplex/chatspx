/**
 * O porteiro da fila offline — bloco 2.16.
 *
 * `enqueueOnNetworkFailure` só guarda o que esta função aprova, então cada
 * classificação errada aqui é um defeito de produto inteiro:
 *
 *  · falso NEGATIVO → a mensagem que o visitante digitou sem rede é perdida
 *    para sempre, calada;
 *  · falso POSITIVO → uma recusa definitiva (ou um defeito nosso) entra na
 *    fila e é reenviada a cada reconexão pelo resto da sessão. E como a fila
 *    PARA no item que falha — e faz certo em parar —, ela trava: nenhuma
 *    mensagem posterior do visitante sai.
 *
 * Por isso os dois lados são medidos, com as formas REAIS que o axios produz.
 */
import { isNetworkFailure } from '../networkFailure';

const erroDoAxios = extras => Object.assign(new Error('falhou'), extras);

describe('2.16 — o que É queda de rede', () => {
  it('erro de rede do axios: sem resposta, com requisição e código ERR_NETWORK', () => {
    expect(
      isNetworkFailure(erroDoAxios({ code: 'ERR_NETWORK', request: {} }))
    ).toBe(true);
  });

  it('timeout: a requisição saiu e nada voltou', () => {
    expect(
      isNetworkFailure(erroDoAxios({ code: 'ECONNABORTED', request: {} }))
    ).toBe(true);
  });

  it('o navegador declarando que não há rede basta sozinho', () => {
    // `onLine` é otimista demais para ser condição NECESSÁRIA (diz `true` em
    // Wi-Fi sem saída), mas quando ele diz `false` não há dúvida: nem o
    // adaptador do axios chega a tentar, e o erro pode vir sem `request`.
    //
    // A restauração é `delete`, e não `defineProperty` com o descritor salvo:
    // `onLine` mora no PROTÓTIPO de `Navigator`, então
    // `getOwnPropertyDescriptor(navigator, 'onLine')` devolve `undefined` e não
    // há o que restaurar. Escrevendo por cima e não apagando, o `false` ficava
    // grudado na instância e contaminava os exemplos seguintes deste arquivo —
    // que passaram a "provar" que um 422 é queda de rede.
    try {
      Object.defineProperty(window.navigator, 'onLine', {
        value: false,
        configurable: true,
      });
      expect(isNetworkFailure(erroDoAxios({}))).toBe(true);
    } finally {
      delete window.navigator.onLine;
    }

    expect(window.navigator.onLine).toBe(true);
  });
});

describe('2.16 — o que NÃO é queda de rede', () => {
  it('422: o servidor recebeu e recusou — reenviar é repetir a recusa para sempre', () => {
    expect(
      isNetworkFailure(erroDoAxios({ response: { status: 422 }, request: {} }))
    ).toBe(false);
  });

  it('500 também não: tem resposta, logo o servidor falou', () => {
    expect(
      isNetworkFailure(erroDoAxios({ response: { status: 500 }, request: {} }))
    ).toBe(false);
  });

  it('defeito nosso ANTES do POST não vira item de fila eterno', () => {
    // FORÇANDO A CONDIÇÃO RUIM, e este caso é medido e não imaginado: montando
    // o teste de tela deste bloco, `endPoints.sendMessage` lançou um
    // `TypeError` lendo `window.WOOT_WIDGET.$root.$i18n.locale` — antes de
    // qualquer socket. Com a regra ingênua (`!error.response`), ele entrava na
    // fila, falhava idêntico a cada reconexão e travava a fila para sempre.
    const erroLocal = new TypeError(
      "Cannot read properties of undefined (reading '$root')"
    );

    expect(erroLocal.response).toBeUndefined();
    expect(erroLocal.request).toBeUndefined();
    expect(isNetworkFailure(erroLocal)).toBe(false);
  });

  it('nem `undefined` — ausência de erro não é motivo para enfileirar', () => {
    expect(isNetworkFailure(undefined)).toBe(false);
  });
});
