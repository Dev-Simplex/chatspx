import fs from 'fs';
import path from 'path';

/**
 * Bloco 5.15 — o aceite e que **um integrador que nunca viu o produto instala,
 * identifica um usuario e dispara um evento so com o documento**.
 *
 * "So com o documento" nao e verificavel por um teste automatico do jeito que
 * um humano verificaria (sentando um integrador na frente dele). O que E
 * verificavel, e o que este spec cobra, e a condicao NECESSARIA: **tudo o que o
 * guia manda o integrador digitar tem de existir de verdade**.
 *
 * Guia que descreve API imaginaria e o jeito classico de um documento mentir —
 * e o integrador so descobre depois de perder a tarde.
 */
const raiz = relativo => path.resolve(process.cwd(), relativo);
const ler = relativo => fs.readFileSync(raiz(relativo), 'utf8');

const guia = ler('docs/tracking/guia-de-integracao.md');
const contrato = ler('docs/tracking/contrato-de-eventos.md');
const sdk = ler('app/javascript/entrypoints/sdk.js');
const webWidget = ler('app/models/channel/web_widget.rb');

describe('5.15 — o guia de integração', () => {
  it('existe, e aponta para o contrato em vez de reescrevê-lo', () => {
    expect(guia).toContain('Guia de integração');
    expect(guia).toContain('contrato-de-eventos.md');

    // a marca de que ele NAO duplicou: a tabela dos doze eventos aparece uma
    // vez so no repositorio, e e no contrato
    const eventosNoGuia = [...guia.matchAll(/^\| \d+ \| `chatspx_/gm)];
    expect(eventosNoGuia).toHaveLength(0);
    expect([...contrato.matchAll(/^\| \d+ \| `chatspx_/gm)]).toHaveLength(12);
  });

  it('todo método do SDK que ele manda chamar existe no SDK', () => {
    const metodos = [
      ...new Set(
        [...guia.matchAll(/\$chatwoot\.(\w+)\(/g)].map(([, metodo]) => metodo)
      ),
    ];

    expect(metodos.length).toBeGreaterThan(2);
    metodos.forEach(metodo =>
      expect({
        metodo,
        existeNoSdk: new RegExp(`\\n    ${metodo}\\(`).test(sdk),
      }).toEqual({
        metodo,
        existeNoSdk: true,
      })
    );
  });

  it('as chaves de `chatwootSettings` que ele documenta são as que o produto lê', () => {
    const bloco = /window\.chatwootSettings = \{([\s\S]*?)\};/.exec(guia)[1];
    const chaves = [...bloco.matchAll(/^\s{4}(\w+):/gm)].map(
      ([, chave]) => chave
    );

    // `OVERRIDABLE_BY_SITE` do schema da aparencia e a lista canonica
    const schema = ler('app/models/concerns/widget_appearance_schema.rb');
    const doServidor = [...schema.matchAll(/'[a-z_]+' => '(\w+)'/g)].map(
      ([, nome]) => nome
    );

    expect(chaves.length).toBeGreaterThan(3);
    chaves.forEach(chave =>
      expect({ chave, aceita: doServidor.includes(chave) }).toEqual({
        chave,
        aceita: true,
      })
    );
  });

  it('o evento que ele manda conferir de ponta a ponta é o que o servidor emite HOJE', () => {
    const listener = ler('app/listeners/tracking_event_listener.rb');
    const eventosCitados = [
      ...new Set(
        [...guia.matchAll(/`(chatspx_\w+)`/g)].map(([, nome]) => nome)
      ),
    ];

    expect(eventosCitados).toContain('chatspx_conversation_resolved');
    eventosCitados.forEach(nome =>
      expect({ nome, noContrato: contrato.includes(nome) }).toEqual({
        nome,
        noContrato: true,
      })
    );
    // e o caminho de ponta a ponta que o guia ensina realmente existe no servidor
    expect(listener).toContain('chatspx_conversation_resolved');
  });

  it('declara o que AINDA NÃO existe, com o bloco que o entrega', () => {
    expect(guia).toContain('5.02');
    expect(guia).toContain('5.14');
  });

  /**
   * Esta era a asserção "o SDK realmente NAO tem `track`, e se um dia tiver este teste avisa que
   * o guia precisa mudar". O 5.16 entregou `track()`, o teste avisou, e o guia mudou — que é
   * exatamente o mecanismo funcionando. A asserção continua existindo, invertida: agora ela cobra
   * que o guia ENSINE o que o SDK passou a ter.
   */
  it('ensina o `track()` que o 5.16 entregou, com as três regras do nome', () => {
    expect(/\n {4}track\(/.test(sdk)).toBe(true);
    expect(guia).toMatch(/\$chatwoot\.track\(/);

    // as tres regras do contrato aparecem no guia, porque sao elas que fazem a chamada falhar
    expect(guia).toContain('chatspx_');
    expect(guia).toContain('snake_case');
    expect(guia).toContain('40 caracteres');

    // e a recusa de PII, que e o que mais surpreende quem integra
    expect(guia).toMatch(/recusad[oa]s?/i);
    expect(guia).toContain('phone_number');
  });

  it('o trecho de instalação descreve o que o servidor realmente gera', () => {
    expect(guia).toContain('chatwootSDK.run');
    expect(webWidget).toContain('chatwootSDK.run');
    // o link de contato alternativo que o guia promete existe no snippet
    expect(guia).toMatch(/link de contato alternativo/);
    expect(webWidget).toContain('showFallback');
  });

  it('ensina o HMAC do lado do servidor, e diz por que não é no navegador', () => {
    expect(guia).toContain('identifier_hash');
    expect(guia).toContain('OpenSSL::HMAC');
    expect(guia).toMatch(/Nunca calcule o HMAC no navegador/);
  });
});
