#!/usr/bin/env node
/* eslint-disable no-console -- Verificador de linha de comando: a saída no console É o
   resultado, lida por quem roda e colada no relatório do bloco. Mesmo tratamento dos outros
   `.check.mjs` desta base. */
/* eslint-disable no-restricted-syntax, no-continue -- `for…of` com `continue` é a forma
   legível de percorrer os cenários acumulando falhas; trocar por `reduce` aqui piora a
   leitura de um script que existe para ser lido quando algo reprova. */
/**
 * O ACEITE do bloco 0.11, executado — bloco 0.11 (D14, QUALITY-KIT §1.5).
 *
 * O aceite diz, literalmente: *"um teste que carrega uma página com `console.error` injetado
 * FALHA, nomeando a mensagem; um `fetch` que devolve 500 FALHA, nomeando método e URL"*.
 *
 * Um aceite cuja afirmação é "este teste falha" não pode ser verificado por um teste que
 * passa: seria preciso alguém rodar e olhar. Este verificador roda `fixture.sabotage.js` num
 * subprocesso e confere, cenário por cenário, **quem reprovou** e **se a mensagem nomeia o que
 * o aceite manda nomear**. Ele é verde quando o fixture está fazendo o trabalho dele.
 *
 * É o mesmo padrão dos outros `.check.mjs` desta base. Roda fora da tranca de portas fixas.
 *
 *   node spec/e2e/widget/fixture-antierro.check.mjs
 */
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const rodar = promisify(execFile);

// título do cenário -> o que a mensagem de reprovação TEM de conter
const DEVEM_REPROVAR = {
  'REPROVA: console.error': ['console', 'sabotagem-console-marcador'],
  'REPROVA: pageerror': ['pageerror', 'sabotagem-pageerror-marcador'],
  // o aceite exige método E URL, então as duas coisas são cobradas
  'REPROVA: HTTP 500 nomeando método e URL': [
    'http',
    '500',
    'GET',
    '/api/sabotagem-500',
  ],
  'REPROVA: falha de rede': ['rede', 'sabotagem-rede'],
  'REPROVA: console.error em janela NOVA': [
    'console',
    'sabotagem-popup-marcador',
  ],
  'REPROVA: errosEsperados obsoleto': [
    'NÃO aconteceram',
    'sabotagem-que-nunca-ocorre',
  ],
  'REPROVA: padrão catch-all é recusado': ['amplo demais'],
  // O achado desta execução: `[a, b]` vira tupla e perde o segundo padrão em silêncio.
  'REPROVA: array cru com dois padroes e detectado': ['tupla', 'padroes'],
};

const DEVEM_PASSAR = [
  'PASSA: página limpa',
  'PASSA: o erro que o próprio cenário provoca',
];

const saidaDe = async () => {
  try {
    const { stdout } = await rodar(
      'npx',
      [
        'playwright',
        'test',
        '--config',
        'spec/e2e/widget/sabotage.playwright.config.js',
      ],
      { maxBuffer: 64 * 1024 * 1024, cwd: process.cwd() }
    );
    return stdout;
  } catch (erro) {
    // reprovação é o resultado ESPERADO aqui: o subprocesso sai != 0 e a saída vem no erro
    return erro.stdout || '';
  }
};

const achatar = suites =>
  suites.flatMap(s => [...(s.specs ?? []), ...achatar(s.suites ?? [])]);

/**
 * A ARMADILHA DO GREP DO ACEITE, e por que ela vira verificação de verdade aqui.
 *
 * O aceite do 0.11 diz: `grep -rn "from '@playwright/test'" spec/e2e/widget/` -> vazio. Esse
 * grep dá vazio HOJE, antes de qualquer trabalho, porque esta base usa `require(...)` e não
 * `import ... from`. Um aceite que passa sozinho não mede nada.
 *
 * O que o aceite QUER é que nenhum teste pegue `test` fora do fixture. Config é outra coisa:
 * ele PRECISA de `defineConfig`/`devices` de `@playwright/test`, e não tem `page` para
 * observar. Então a regra verificada é: nenhum `*.spec.js` de `spec/e2e/**` importa `test`
 * de `@playwright/test`, nas duas sintaxes.
 */
const verificarImports = async () => {
  const { readdirSync, readFileSync, statSync } = await import('node:fs');
  const { join } = await import('node:path');

  const specs = [];
  const varrer = dir => {
    for (const nome of readdirSync(dir)) {
      const caminho = join(dir, nome);
      if (statSync(caminho).isDirectory()) varrer(caminho);
      else if (nome.endsWith('.spec.js')) specs.push(caminho);
    }
  };
  varrer('spec/e2e');

  const infratores = specs.filter(caminho => {
    const fonte = readFileSync(caminho, 'utf8');
    const importa =
      /const\s*\{[^}]*\btest\b[^}]*\}\s*=\s*require\(\s*'@playwright\/test'\s*\)/.test(
        fonte
      ) ||
      /import\s*\{[^}]*\btest\b[^}]*\}\s*from\s*'@playwright\/test'/.test(
        fonte
      );
    return importa;
  });

  return { total: specs.length, infratores };
};

const main = async () => {
  const stdout = await saidaDe();
  const inicio = stdout.indexOf('{');
  if (inicio === -1)
    throw new Error(
      `não achei JSON na saída do playwright:\n${stdout.slice(0, 800)}`
    );
  const relatorio = JSON.parse(stdout.slice(inicio));

  const specs = achatar(relatorio.suites ?? []);
  const porTitulo = new Map(specs.map(s => [s.title, s]));

  const falhas = [];
  const ok = [];

  for (const [titulo, exigidos] of Object.entries(DEVEM_REPROVAR)) {
    const spec = porTitulo.get(titulo);
    if (!spec) {
      falhas.push(`cenário ausente: "${titulo}"`);
      continue;
    }
    if (spec.ok) {
      falhas.push(
        `"${titulo}" PASSOU — o fixture não está medindo esta categoria`
      );
      continue;
    }
    const msg = JSON.stringify(spec.tests?.[0]?.results?.[0]?.error ?? {});
    const faltando = exigidos.filter(t => !msg.includes(t));
    if (faltando.length) {
      falhas.push(
        `"${titulo}" reprovou, mas a mensagem não nomeia: ${faltando.join(', ')}`
      );
      continue;
    }
    ok.push(
      `${titulo} — reprovou nomeando ${exigidos.map(e => `"${e}"`).join(', ')}`
    );
  }

  for (const titulo of DEVEM_PASSAR) {
    const spec = porTitulo.get(titulo);
    if (!spec) falhas.push(`cenário ausente: "${titulo}"`);
    else if (!spec.ok) {
      const msg = JSON.stringify(spec.tests?.[0]?.results?.[0]?.error ?? {});
      falhas.push(
        `"${titulo}" REPROVOU e deveria passar — falso positivo do fixture: ${msg.slice(0, 300)}`
      );
    } else ok.push(`${titulo} — passou`);
  }

  const imports = await verificarImports();
  const doWidget = imports.infratores.filter(c =>
    c.startsWith('spec/e2e/widget/')
  );
  if (doWidget.length) {
    falhas.push(
      `spec/e2e/widget/** ainda pega \`test\` de @playwright/test: ${doWidget.join(', ')}`
    );
  } else {
    ok.push(
      `nenhum dos ${imports.total} *.spec.js de spec/e2e/widget/** importa \`test\` de @playwright/test`
    );
  }
  // Fora do widget a adoção é decisão de escopo (ver o relatório); aqui só se informa.
  const foraDoWidget = imports.infratores.filter(
    c => !c.startsWith('spec/e2e/widget/')
  );
  if (foraDoWidget.length) {
    console.log(
      `AVISO ${foraDoWidget.length} spec(s) fora de spec/e2e/widget/ ainda sem o fixture:\n` +
        foraDoWidget.map(c => `      · ${c}`).join('\n')
    );
  }

  ok.forEach(l => console.log(`OK    ${l}`));
  falhas.forEach(l => console.log(`FALHA ${l}`));
  console.log(
    `\n${ok.length} de ${ok.length + falhas.length} verificações do aceite 0.11`
  );
  process.exit(falhas.length ? 1 : 0);
};

main().catch(e => {
  console.error(e);
  process.exit(1);
});
