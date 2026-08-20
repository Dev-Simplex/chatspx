import fs from 'fs';
import path from 'path';

/**
 * Bloco 5.22 — instalação em WordPress, Wix e GTM.
 *
 * O aceite herdado do 5.15 é *"uma pessoa que nunca viu o produto instala seguindo só o
 * documento"*. Isso não é verificável por robô do jeito que um humano verificaria — sentando
 * alguém na frente de um WordPress limpo. O que É verificável, e o que este spec cobra, é a
 * condição NECESSÁRIA: **tudo o que o documento afirma sobre o produto tem de ser verdade
 * agora**, e continuar verdade quando o produto mudar.
 *
 * Documento de instalação que descreve um snippet que o servidor não gera mais é o jeito mais
 * caro de mentir: o integrador segue os passos, não funciona, e a conclusão dele é que o
 * produto está quebrado.
 */
const raiz = relativo => path.resolve(process.cwd(), relativo);
const ler = relativo => fs.readFileSync(raiz(relativo), 'utf8');

const doc = ler('docs/tracking/instalacao-por-plataforma.md');
const guia = ler('docs/tracking/guia-de-integracao.md');
const contrato = ler('docs/tracking/contrato-de-eventos.md');
const webWidget = ler('app/models/channel/web_widget.rb');
const sdk = ler('app/javascript/entrypoints/sdk.js');

describe('5.22 — o documento de instalação por plataforma', () => {
  it('cobre as três plataformas do bloco, cada uma com seção própria', () => {
    expect(doc).toMatch(/^## 1\. WordPress$/m);
    expect(doc).toMatch(/^## 2\. Wix$/m);
    expect(doc).toMatch(/^## 3\. Google Tag Manager$/m);
  });

  it('aponta para o guia e o contrato em vez de reescrevê-los', () => {
    expect(doc).toContain('guia-de-integracao.md');
    expect(doc).toContain('contrato-de-eventos.md');

    // A marca de que ele não duplicou o contrato: a tabela dos doze eventos aparece uma vez só
    // no repositório, e é no contrato.
    expect([...doc.matchAll(/^\| \d+ \| `chatspx_/gm)]).toHaveLength(0);
    expect([...contrato.matchAll(/^\| \d+ \| `chatspx_/gm)]).toHaveLength(12);
  });

  /**
   * A REGRA QUE MAIS PROTEGE O DOCUMENTO: ele NÃO carrega uma cópia do snippet.
   *
   * O trecho de instalação é gerado pelo servidor (`web_widget_script`, bloco 3.11) e contém o
   * token do site e a URL do servidor. Uma cópia colada aqui envelheceria em silêncio na
   * primeira mudança do carregador — e o integrador colaria a versão velha, que é pior do que
   * não ter documento nenhum.
   */
  it('NÃO cola uma cópia do trecho — ele manda copiar do painel', () => {
    const blocosDeCodigo = [...doc.matchAll(/```(\w*)\n([\s\S]*?)```/g)];
    const comCarregador = blocosDeCodigo.filter(([, , corpo]) =>
      /chatwootSDK\.run|packs\/js\/sdk\.js|createElement\(t\)/.test(corpo)
    );

    expect(comCarregador).toHaveLength(0);
    // o `[\s>]+` tolera a quebra de linha e o `>` do blockquote no meio da frase
    expect(doc).toMatch(
      /Caixas de entrada →[\s>]+sua caixa →[\s>]+Configuração/
    );
  });

  it('cada plataforma tem a SUA armadilha escrita, não uma nota genérica', () => {
    // WordPress: a atualização do tema apaga o `footer.php`
    expect(doc).toMatch(/atualização do tema/i);
    expect(doc).toContain('footer.php');
    // Wix: código personalizado exige plano pago, e não roda antes de publicar
    expect(doc).toMatch(/plano pago/i);
    expect(doc).toMatch(
      /só no site \*\*publicado\*\*|não executa código personalizado/i
    );
    // GTM: HTML personalizado, não template de galeria
    expect(doc).toMatch(/sandbox/i);
    expect(doc).toMatch(/HTML personalizado/i);

    // e nenhuma saída pela tangente
    expect(doc).not.toMatch(
      /consulte seu desenvolvedor|fale com um desenvolvedor/i
    );
  });

  /**
   * O aceite nomeia esta garantia (regra R9): o snippet do GTM não sobrescreve o `dataLayer` do
   * cliente. Aqui ela é cobrada na PORTA DE ENTRADA — o texto do trecho que o servidor gera.
   * O comportamento do SDK que ele carrega é medido em navegador real
   * (`sdk/specs/browser/gtm-datalayer.check.mjs`).
   */
  it('a promessa sobre o `dataLayer` é verdade no trecho que o servidor gera', () => {
    const trecho = webWidget.slice(webWidget.indexOf('def web_widget_script'));

    expect(doc).toMatch(/window\.dataLayer = window\.dataLayer \|\| \[\]/);
    // o trecho de instalação não escreve no dataLayer nem no gtag — ele só baixa o sdk.js
    expect(trecho).not.toMatch(/dataLayer\s*=/);
    expect(trecho).not.toMatch(/window\.gtag\s*=/);
  });

  it('o que ele promete sobre a degradação existe no trecho do servidor', () => {
    // o link de contato alternativo e o prazo, que a §1.2 e a §4 mandam procurar
    expect(doc).toMatch(/link de contato alternativo/);
    expect(webWidget).toContain('showFallback');
    const prazoNoDoc = /(\d+) segundos/.exec(doc)?.[1];
    expect(webWidget).toContain(`}},${Number(prazoNoDoc) * 1000})`);
  });

  it('todo método do SDK que ele manda chamar existe no SDK', () => {
    const metodos = [
      ...new Set(
        [...doc.matchAll(/\$chatwoot\s*\n?\s*\.?(\w+)\(/g)].map(([, m]) => m)
      ),
    ];

    expect(metodos).toContain('track');
    metodos.forEach(metodo =>
      expect({
        metodo,
        existeNoSdk: new RegExp(`\\n {4}${metodo}\\(`).test(sdk),
      }).toEqual({ metodo, existeNoSdk: true })
    );
  });

  /**
   * A garantia que o documento usa para convencer o integrador a chamar do GTM: nada lança de
   * forma síncrona, porque uma exceção ali derruba as tags SEGUINTES do contêiner dele.
   *
   * O spec não confia na prosa: ele lê o SDK e exige que os métodos citados passem pelo
   * envelope que converte erro em `Promise` rejeitada (`chamadaDeDados`).
   */
  it('a garantia de "nunca lança" que ele promete está no código', () => {
    expect(doc).toMatch(/nunca lançam exceção síncrona|nunca lança/i);
    expect(doc).toContain('Promise');

    ['track', 'setUser', 'updateUser', 'setCustomAttributes'].forEach(
      metodo => {
        const corpo = new RegExp(
          `\\n {4}${metodo}\\([^)]*\\) \\{\\n\\s*return chamadaDeDados\\(`
        );
        expect({ metodo, envelopado: corpo.test(sdk) }).toEqual({
          metodo,
          envelopado: true,
        });
      }
    );
  });

  it('todo evento `chatspx_*` que ele cita existe no contrato ou é exemplo do próprio site', () => {
    const citados = [
      ...new Set(
        [...doc.matchAll(/`?(chatspx_[a-z0-9_]+)`?/g)].map(([, n]) => n)
      ),
    ];

    citados.forEach(nome =>
      expect({
        nome,
        conhecido: contrato.includes(nome) || guia.includes(nome),
      }).toEqual({ nome, conhecido: true })
    );
  });

  it('o guia principal aponta para ele — senão ninguém o encontra', () => {
    expect(guia).toContain('instalacao-por-plataforma.md');
  });
});
