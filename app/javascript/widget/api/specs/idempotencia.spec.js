/**
 * Mecanismo de aceite do bloco 2.15 — a ponta do FRONT.
 *
 * O servidor sabe recusar o reenvio (spec de request). Aqui se prova a outra
 * metade: que o widget MANDA uma chave, e que ela é a MESMA no retry. Gerar
 * chave nova a cada tentativa é o mesmo que não ter chave — o servidor não teria
 * como reconhecer o reenvio, e a proteção seria decorativa.
 */
import endPoints from 'widget/api/endPoints';
import { novaChaveDeEnvio } from '../conversation';

// `buildSearchParamsWithLocale` lê o locale da instância raiz do widget
// (`urlParamsHelper.js:3`). Fora do app ela não existe — o dublê é do AMBIENTE,
// não do que se mede.
beforeAll(() => {
  window.WOOT_WIDGET = { $root: { $i18n: { locale: 'pt_BR' } } };
});

describe('2.15 — a chave de envio', () => {
  it('vai no corpo da requisição, dentro de message', () => {
    const { params } = endPoints.sendMessage('oi', null, {
      echoId: 'chave-abc',
    });

    expect(params.message.echo_id).toBe('chave-abc');
  });

  it('duas chamadas com a MESMA chave montam o mesmo echo_id — é o retry', () => {
    const primeira = endPoints.sendMessage('oi', null, { echoId: 'k' });
    const segunda = endPoints.sendMessage('oi', null, { echoId: 'k' });

    expect(primeira.params.message.echo_id).toBe(
      segunda.params.message.echo_id
    );
  });

  it('cada mensagem nova ganha uma chave diferente', () => {
    const chaves = new Set(
      Array.from({ length: 50 }, () => novaChaveDeEnvio())
    );

    expect(chaves.size).toBe(50);
  });

  it('sem crypto.randomUUID a chave continua saindo — o widget roda em site http', () => {
    const original = window.crypto;
    // `randomUUID` exige contexto seguro. Num cliente ainda em http ele não
    // existe, e sem o fallback TODA mensagem iria com `undefined` — todas
    // colidiriam entre si, que é o oposto do que este bloco faz.
    Object.defineProperty(window, 'crypto', { value: {}, configurable: true });

    const chave = novaChaveDeEnvio();

    expect(typeof chave).toBe('string');
    expect(chave.length).toBeGreaterThan(8);
    expect(chave).not.toContain('undefined');

    Object.defineProperty(window, 'crypto', {
      value: original,
      configurable: true,
    });
  });
});
