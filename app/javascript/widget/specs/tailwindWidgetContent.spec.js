/**
 * Guarda do bloco 1.08 — o `content` restrito não pode deixar arquivo de fora.
 *
 * O 1.08 troca o `content` global (que varria dashboard, portal, survey e v3)
 * por um restrito ao que o widget renderiza. O ganho é enorme — 1.692.204 B →
 * 73.098 B — e o risco é de um tipo específico e traiçoeiro: se um arquivo que o
 * widget REALMENTE renderiza ficar fora do `content`, o Tailwind não gera as
 * classes dele. Nada falha no build, nada aparece no console: o componente
 * simplesmente perde o estilo em produção.
 *
 * Este teste fecha esse buraco pelo caminho oposto ao do glob: parte de
 * `entrypoints/widget.js` e percorre o fecho de imports estáticos, obtendo a
 * lista do que o widget de fato carrega. Depois exige que todo `.vue`/`.js` desse
 * fecho esteja coberto pelo `content` do config do widget.
 *
 * Não é tautológico: o fecho vem dos `import` do código, e o `content` vem do
 * config — duas fontes independentes. Se alguém importar um componente de
 * `dashboard/` ou de `shared/components/ui/` dentro do widget, o teste vermelhece
 * apontando o arquivo, em vez de a tela chegar sem estilo no cliente.
 */
import { readFileSync, existsSync, statSync, globSync } from 'node:fs';
import path from 'node:path';

// O `content` é LIDO do arquivo, não importado. Importar puxaria
// `tailwind.config.js`, que faz `import { colors } from './theme/colors'` — sem
// extensão, resolvido em produção pelo jiti do Tailwind e irresolúvel aqui. Ler
// o array declarado é suficiente e tem a vantagem de não depender da cadeia
// inteira de configs para testar uma lista de caminhos.
const configTexto = readFileSync('tailwind.widget.config.js', 'utf8');
const bloco = configTexto.match(/content:\s*\[([\s\S]*?)\n\s*\],/);
if (!bloco)
  throw new Error('não localizei o array `content` no config do widget');
const widgetConfig = {
  content: [...bloco[1].matchAll(/'([^']+)'/g)].map(m => m[1]),
};

const RAIZ = 'app/javascript';
const ENTRADA = `${RAIZ}/entrypoints/widget.js`;

// Os aliases que o Vite resolve (ver `vite.config.ts`): caminhos que começam com
// `widget/`, `shared/` e `dashboard/` são relativos a `app/javascript`.
const resolver = (imp, origem) => {
  let base;
  if (/^(widget|shared|dashboard|survey|portal|v3)\//.test(imp)) {
    base = path.join(RAIZ, imp);
  } else if (imp.startsWith('.')) {
    base = path.normalize(path.join(path.dirname(origem), imp));
  } else {
    return null; // pacote de node_modules — não entra no `content`
  }
  return (
    ['', '.vue', '.js', '.ts', '/index.js']
      .map(suf => base + suf)
      .find(cand => existsSync(cand) && statSync(cand).isFile()) || null
  );
};

const IMPORT = /(?:import[^'"]*?from\s*|import\s*\(\s*)['"]([^'"]+)['"]/g;

const fechoDeImports = () => {
  const vistos = new Set();
  const fila = [ENTRADA];
  while (fila.length) {
    const arq = fila.pop();
    if (!vistos.has(arq)) {
      vistos.add(arq);
      let src = null;
      try {
        src = readFileSync(arq, 'utf8');
      } catch {
        src = null;
      }
      if (src) {
        [...src.matchAll(IMPORT)].forEach(m => {
          const alvo = resolver(m[1], arq);
          if (alvo) fila.push(alvo);
        });
      }
    }
  }
  return vistos;
};

// Expande o `content` do config nos arquivos que ele cobre, respeitando os
// padrões de exclusão (os que começam com `!`).
const cobertosPeloContent = () => {
  const positivos = widgetConfig.content.filter(p => !p.startsWith('!'));
  const negativos = widgetConfig.content
    .filter(p => p.startsWith('!'))
    .map(p =>
      p
        .slice(1)
        .replace(/^\.\//, '')
        .replace(/\/\*\*$/, '')
    );

  const cobertos = new Set();
  positivos.forEach(padrao => {
    globSync(padrao.replace(/^\.\//, '')).forEach(f => {
      if (!negativos.some(n => f.startsWith(n))) cobertos.add(f);
    });
  });
  return cobertos;
};

describe('1.08 — o `content` do widget cobre tudo o que o widget renderiza', () => {
  const fecho = fechoDeImports();
  const cobertos = cobertosPeloContent();

  // Só arquivos que podem conter classe utilitária. `.json` (i18n) e módulos de
  // node_modules não entram no `content` e não geram classe.
  const relevantes = [...fecho].filter(
    f => (f.endsWith('.vue') || f.endsWith('.js')) && f.startsWith(RAIZ)
  );

  it('o fecho de imports foi calculado de verdade', () => {
    // Piso alto: se o resolvedor quebrar e devolver só a entrada, os testes
    // abaixo passariam sem ter olhado nada.
    expect(relevantes.length).toBeGreaterThan(150);
    expect(relevantes).toContain(ENTRADA);
    // Âncoras conhecidas: componentes que o widget comprovadamente renderiza.
    expect(relevantes).toContain(
      `${RAIZ}/shared/components/CustomerSatisfaction.vue`
    );
    expect(relevantes).toContain(
      `${RAIZ}/shared/components/emoji/EmojiPicker.vue`
    );
  });

  // Nem todo arquivo do fecho precisa estar no `content`: um helper de datas não
  // tem classe nenhuma, e listá-lo só poluiria o config. O que precisa é o
  // arquivo que PODE contribuir com classe — e é isso que esta heurística marca.
  // Ela é deliberadamente generosa: na dúvida, exige cobertura.
  const PARECE_CLASSE =
    /\bclass=|:class|\b(?:bg|text|border|rounded|shadow|flex|grid|gap|px|py|pt|pb|ps|pe|mx|my|mt|mb|w|h|min-w|max-w|items|justify|outline|ring)-[a-z0-9[]/;

  const comClasses = relevantes.filter(f => {
    try {
      return PARECE_CLASSE.test(readFileSync(f, 'utf8'));
    } catch {
      return false;
    }
  });

  it('todo arquivo com classe que o widget carrega está coberto pelo content', () => {
    const descobertos = comClasses.filter(f => !cobertos.has(f));
    // Lista os culpados na mensagem: quem quebrar isso precisa saber QUAL
    // arquivo ficará sem CSS, não só que algo ficou.
    //
    // Foi esta asserção que pegou, na primeira execução, que o widget renderiza
    // `dashboard/components-next/avatar/Avatar.vue` (via a tela de mensagens não
    // lidas) e mais três componentes do dashboard atrás dele. Sem eles no
    // `content`, a tela `unread` — uma das quatro dos 16 snapshots — chegaria
    // sem estilo, e o build não diria nada.
    expect(descobertos).toEqual([]);
  });

  it('nada de shared/components/ui/ entrou no fecho — é a exclusão do bloco', () => {
    // Se este teste falhar, a exclusão do `content` deixou de ser segura: algum
    // componente de `ui/` passou a ser renderizado no widget e vai chegar sem
    // estilo. O conserto é remover a exclusão (e aceitar os ~8,5 kB de ícones),
    // não apagar este teste.
    const ui = relevantes.filter(f =>
      f.startsWith(`${RAIZ}/shared/components/ui/`)
    );
    expect(ui).toEqual([]);
  });

  it('não varre superfície alheia por glob amplo', () => {
    // O ganho do bloco vem de NÃO varrer o projeto inteiro. Caminhos nomeados de
    // `dashboard/` são legítimos — o widget renderiza alguns componentes dele —,
    // mas um glob que abra a superfície toda traz de volta os 1,6 MB.
    const globAmplo = widgetConfig.content.filter(p =>
      /(dashboard|portal|survey|v3|enterprise)\/\*\*/.test(p)
    );
    expect(globAmplo).toEqual([]);

    // E portal/survey/v3/enterprise não têm por que aparecer de forma nenhuma:
    // o widget não renderiza nada deles.
    const proibidos = widgetConfig.content.filter(p =>
      /(portal|survey|v3|enterprise)\//.test(p)
    );
    expect(proibidos).toEqual([]);
  });
});
