import fs from 'fs';
import path from 'path';

/**
 * Nenhuma string de tradução pode conter JavaScript executável.
 *
 * O defeito que este teste impede de voltar (D3) esteve em produção:
 * `INBOX_MGMT.WIDGET_BUILDER.SCRIPT_SETTINGS` guardava
 * `window.chatwootSettings = {options};`, e o preview cortava o snippet do
 * cliente no byte 13 para injetar essa string no meio. Um tradutor mexendo
 * numa chave de tradução quebrava o código que o cliente cola no site — em 57
 * idiomas, sem ninguém revisando JavaScript numa planilha de tradução.
 *
 * Os padrões abaixo são de CÓDIGO, não de prosa: uma frase pode falar de
 * "janela" (`window...`) ou pedir para colar uma tag `<script>`, e isso é
 * texto legítimo. O que não pode é atribuição, chamada de DOM ou o nome de uma
 * API nossa sendo invocada.
 */
const PADROES_DE_CODIGO = [
  { nome: 'atribuição em window', regex: /window\.\w+\s*=/ },
  { nome: 'atribuição em document', regex: /document\.\w+\s*=/ },
  {
    nome: 'chamada de DOM',
    regex: /document\.(createElement|getElementsBy\w+|querySelector\w*)\s*\(/,
  },
  { nome: 'chamada do SDK', regex: /chatwootSDK\.\w+\s*\(/ },
  { nome: 'objeto de configuração do widget', regex: /chatwootSettings\s*=/ },
  { nome: 'função anônima', regex: /function\s*\([^)]*\)\s*\{/ },
];

const localeDir = path.resolve(
  process.cwd(),
  'app/javascript/dashboard/i18n/locale'
);

const percorre = (node, prefixo, acc) => {
  if (typeof node === 'string') {
    acc.push([prefixo, node]);
  } else if (node && typeof node === 'object') {
    Object.entries(node).forEach(([chave, valor]) =>
      percorre(valor, prefixo ? `${prefixo}.${chave}` : chave, acc)
    );
  }
  return acc;
};

const todasAsMensagens = () => {
  const encontradas = [];
  fs.readdirSync(localeDir).forEach(locale => {
    const dir = path.join(localeDir, locale);
    if (!fs.statSync(dir).isDirectory()) return;
    fs.readdirSync(dir)
      .filter(file => file.endsWith('.json'))
      .forEach(file => {
        const conteudo = JSON.parse(
          fs.readFileSync(path.join(dir, file), 'utf8')
        );
        percorre(conteudo, '', []).forEach(([chave, texto]) =>
          encontradas.push({ locale, file, chave, texto })
        );
      });
  });
  return encontradas;
};

describe('nenhuma tradução carrega JavaScript executável (D3)', () => {
  const mensagens = todasAsMensagens();

  it('o corpus varrido é o corpus inteiro, não uma amostra', () => {
    expect(mensagens.length).toBeGreaterThan(30000);
    expect(new Set(mensagens.map(m => m.locale)).size).toBeGreaterThan(30);
  });

  it.each(PADROES_DE_CODIGO)('nenhuma string tem $nome', ({ regex }) => {
    const culpadas = mensagens
      .filter(({ texto }) => regex.test(texto))
      .map(({ locale, file, chave }) => `${locale}/${file}: ${chave}`);

    expect(culpadas).toEqual([]);
  });

  it('a chave que guardava o snippet não existe mais em idioma nenhum', () => {
    const sobreviventes = mensagens
      .filter(({ chave }) => chave.endsWith('WIDGET_BUILDER.SCRIPT_SETTINGS'))
      .map(({ locale }) => locale);

    expect(sobreviventes).toEqual([]);
  });
});
