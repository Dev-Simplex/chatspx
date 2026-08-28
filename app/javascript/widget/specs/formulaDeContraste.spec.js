import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

/**
 * BLOCOS 1.03 e 1.04 — "nenhuma fórmula de contraste em JS".
 *
 * Esta é a metade do aceite que os três `grep` do 1.04 não alcançam. Eles
 * procuram NOMES — a classe da marca antiga, a função de contraste do upstream
 * e a custom property órfã. A heurística que sobreviveu a eles chamava-se
 * `isWidgetColorLighter` e vivia em `shared/helpers/colorHelper.js`: nome que
 * nenhum dos três casa. Um grep de nome só pega o que já se sabe procurar.
 *
 * (Os três literais NÃO são citados aqui de propósito: eles são o critério de
 * aceite medido por `grep` nestes mesmos diretórios, e escrevê-los num
 * comentário faria o critério voltar não-vazio por causa da documentação.)
 *
 * O que este spec procura é a CONTA, não o nome:
 *
 *   · os coeficientes do YIQ (299 / 587 / 114) — a heurística de brilho da TV
 *     analógica, que não mede razão de contraste nenhuma;
 *   · os limiares de "esta cor é clara?" (128, 186, 225) aplicados a brilho;
 *   · a fórmula de luminância relativa do WCAG (0.2126 / 0.7152 / 0.0722) e a
 *     razão `(L + 0,05)`, que é contraste calculado no cliente.
 *
 * Quem decide contraste é o SERVIDOR, uma vez, em `WidgetTokens` (bloco 1.02).
 * O front consome `--w-on-brand` e `--w-brand-readable`.
 *
 * ── DUAS ARMADILHAS QUE ESTE ARQUIVO EVITA ─────────────────────────────────
 *
 * 1. TESTE QUE PASSA NO VÁCUO. Uma varredura que não acha nada passa igual se o
 *    varredor estiver quebrado — se o glob não casar arquivo nenhum, se o
 *    strip de comentário comer o código todo. Por isso há CONTROLE POSITIVO:
 *    o mesmo varredor é apontado para um texto que contém a fórmula, e o teste
 *    exige que ele ACUSE. Varredor que não acusa o plantado não prova ausência.
 *
 * 2. CEGUEIRA A COMENTÁRIO — nos dois sentidos. Comentário é obrigatório
 *    ignorar: `sdk.js`, `IFrameHelper.js` e o spec do 1.03 EXPLICAM em prosa a
 *    fórmula que mataram, com os números dentro. Um varredor literal
 *    reprovaria a documentação da própria remoção. Mas o strip tem de ser
 *    conservador: ele só apaga `//…`, `/*…*\/` e `<!--…-->`, nunca conteúdo de
 *    string — foi dentro de uma template string (`SDK_CSS`) que já se escondeu
 *    CSS que ninguém revisava.
 */

const RAIZES = ['widget', 'sdk', 'shared'];
const EXTENSOES = /\.(js|vue|mjs|ts)$/;

// ── O QUE FICA FORA, E POR QUE NÃO É RECORTE PARA FICAR VERDE ───────────────
//
// Só arquivo de TESTE. Os verificadores em `specs/browser/*.check.mjs` calculam
// razão de contraste porque é o que eles MEDEM: `unread-bubble-contrast` afere
// 21:1, `bubble-geometry` afere 4,5:1. Proibi-los de calcular seria proibir a
// própria aferição — e este arquivo, com seus controles positivos, seria o
// primeiro a se reprovar.
//
// A fronteira é o BUNDLE: nada em `specs/` entra no artefato que o visitante
// baixa (o Rollup nunca os vê; a cobertura do vitest já os exclui). O defeito
// que este spec persegue vivia em `shared/helpers/colorHelper.js` — código de
// produção, e o teste `o varredor cobre o arquivo que tinha o defeito` existe
// para que nenhum recorte futuro o engula por acidente.
const E_TESTE = /(^|\/)specs?(\/|$)|\.(spec|test|check)\.[cm]?[jt]s$/;

// `app/javascript` no DISCO. Deliberadamente NÃO derivado de `import.meta.url`:
// sob o vitest esse URL é relativo à raiz do Vite, e `.pathname` sai
// `/app/javascript/...` — um caminho absoluto que não existe. O erro é ruidoso
// (ENOENT), mas a lição vale: caminho de arquivo vem de `process.cwd()`, que
// sob o vitest é a raiz do projeto.
const BASE = `${resolve(process.cwd(), 'app/javascript')}/`;

const arquivosDe = dir => {
  const achados = [];
  const ande = atual => {
    readdirSync(atual).forEach(nome => {
      const caminho = join(atual, nome);
      if (statSync(caminho).isDirectory()) {
        ande(caminho);
        return;
      }
      if (!EXTENSOES.test(nome)) return;
      const relativo = caminho.slice(BASE.length);
      if (E_TESTE.test(relativo)) return;
      achados.push(caminho);
    });
  };
  ande(join(BASE, dir));
  return achados;
};

/** Remove comentário de linha, de bloco e de HTML. Não toca em string. */
export const semComentarios = fonte =>
  fonte
    .replace(/<!--[\s\S]*?-->/g, ' ')
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');

/**
 * Cada padrão é uma conta, com o nome do defeito que ela produz. `bandeira`
 * aparece no erro do teste para que quem quebrar isto saiba o que fazer.
 */
const FORMULAS = [
  {
    bandeira: 'brilho YIQ (coeficientes 299/587/114)',
    re: /\*\s*299\b|\*\s*587\b|\*\s*114\b/,
  },
  {
    bandeira: 'limiar de "cor clara" sobre brilho (128/186/225)',
    re: /brightness[\s\S]{0,40}[<>]=?\s*(?:128|186|225)\b/i,
  },
  {
    bandeira:
      'luminância relativa WCAG calculada no cliente (0.2126/0.7152/0.0722)',
    re: /0\.2126|0\.7152|0\.0722/,
  },
  {
    bandeira:
      'razão de contraste WCAG calculada no cliente ((L1 + 0.05) / (L2 + 0.05))',
    re: /\+\s*0\.05\s*\)\s*\/\s*\(/,
  },
];

const acusacoes = texto =>
  FORMULAS.filter(({ re }) => re.test(texto)).map(({ bandeira }) => bandeira);

describe('nenhuma fórmula de contraste em JS (aceite dos blocos 1.03/1.04)', () => {
  // ── CONTROLE POSITIVO ─────────────────────────────────────────────────────
  // Sem isto, todo o resto deste arquivo passaria com o varredor quebrado.
  it('o varredor ACUSA a fórmula quando ela existe em código', () => {
    const plantado = `
      const isWidgetColorLighter = color => {
        const brightness = (c_r * 299 + c_g * 587 + c_b * 114) / 1000;
        return brightness > 225;
      };
    `;
    expect(acusacoes(semComentarios(plantado))).toEqual([
      'brilho YIQ (coeficientes 299/587/114)',
      'limiar de "cor clara" sobre brilho (128/186/225)',
    ]);
  });

  it('o varredor ACUSA luminância e razão de contraste escritas à mão', () => {
    const plantado = `
      const lum = ([r, g, b]) => 0.2126 * r + 0.7152 * g + 0.0722 * b;
      const ratio = (l1 + 0.05) / (l2 + 0.05);
    `;
    expect(acusacoes(semComentarios(plantado))).toEqual([
      'luminância relativa WCAG calculada no cliente (0.2126/0.7152/0.0722)',
      'razão de contraste WCAG calculada no cliente ((L1 + 0.05) / (L2 + 0.05))',
    ]);
  });

  // ── E o strip não pode ser tão agressivo a ponto de apagar o código ───────
  it('o strip de comentário preserva o código e some com a prosa', () => {
    const misto = `
      // (c_r * 299 + c_g * 587) — a conta que este bloco matou
      const cor = 'var(--w-brand-readable)';
    `;
    const limpo = semComentarios(misto);
    expect(limpo).toContain('var(--w-brand-readable)');
    expect(acusacoes(limpo)).toEqual([]);
  });

  // ── A MEDIÇÃO ─────────────────────────────────────────────────────────────
  it('o varredor enxerga os três diretórios do aceite', () => {
    // Guarda contra o glob vazio: `shared/` é justamente onde a fórmula estava,
    // e um caminho errado aqui produziria "nenhuma ocorrência" para sempre.
    RAIZES.forEach(dir => {
      expect(arquivosDe(dir).length).toBeGreaterThan(20);
    });
  });

  it('o varredor cobre o arquivo que TINHA o defeito', () => {
    // `shared/helpers/colorHelper.js` é onde `isWidgetColorLighter` morava. Se
    // um recorte futuro tirar este arquivo do conjunto varrido, a varredura
    // continua verde e para de significar coisa alguma — é a diferença entre
    // "não achei" e "não procurei".
    const varridos = arquivosDe('shared').map(c => c.slice(BASE.length));
    expect(varridos).toContain('shared/helpers/colorHelper.js');
  });

  it.each(RAIZES)('%s/ não tem fórmula de contraste em código', dir => {
    const culpados = arquivosDe(dir)
      .map(caminho => ({
        caminho: caminho.slice(BASE.length),
        bandeiras: acusacoes(semComentarios(readFileSync(caminho, 'utf8'))),
      }))
      .filter(({ bandeiras }) => bandeiras.length)
      .map(({ caminho, bandeiras }) => `${caminho} → ${bandeiras.join(' · ')}`);

    expect(culpados).toEqual([]);
  });
});
