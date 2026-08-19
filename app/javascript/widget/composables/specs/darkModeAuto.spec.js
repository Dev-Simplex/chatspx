/**
 * Mecanismo de aceite do bloco 2.10 — dark mode completo.
 *
 * ACEITE (§2.2): «Sem `darkMode` configurado e SO escuro, o widget abre escuro;
 * trocar o tema do SO reflete **sem remount**».
 *
 * As duas metades do aceite viram duas asserções distintas aqui:
 *
 *   1. "abre escuro sem configurar"  → o DEFAULT, em todas as pontas por onde
 *      `darkMode` entra: o SDK que valida o valor do snippet, e o store do
 *      widget que recebe o `config-set`. Uma ponta só não basta — o default
 *      vivia repetido em três lugares como `'light'`, e é assim que uma metade
 *      corrigida convive com a outra errada sem ninguém notar.
 *
 *   2. "reflete sem remount"  → a preferência do SO precisa ser REATIVA. Era
 *      `computed(() => window.matchMedia(...).matches)`: um `computed` só
 *      recalcula quando uma dependência REATIVA muda, e `matchMedia().matches`
 *      não é uma. O valor congelava na primeira leitura e só se corrigia
 *      remontando o widget — que é exatamente o que o aceite proíbe.
 *      O teste força um `change` do MediaQueryList e lê o MESMO `ref` de
 *      antes: se ele não acompanhar, é porque só um remount resolveria.
 */
import { getDarkMode } from '../../../sdk/settingsHelper';
import { DEFAULT_DARK_MODE } from '../../../sdk/constants';
import appConfig from 'widget/store/modules/appConfig';
import { useDarkMode } from '../useDarkMode';

// `vi.hoisted` porque `vi.mock` é içado para o topo do arquivo: sem isto, a
// referência a `mockDarkMode` dentro da fábrica seria avaliada antes da
// declaração. O objeto é o MESMO em todos os testes, e cada um só troca
// `.value` — que é como o getter do Vuex se comporta para o composable.
const { mockDarkMode } = vi.hoisted(() => ({
  mockDarkMode: { value: 'auto' },
}));

vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => mockDarkMode,
}));

describe('2.10 — default do dark mode é "auto" nas duas pontas', () => {
  describe('ponta 1: o SDK, que valida o valor vindo do snippet do cliente', () => {
    it('cai em "auto" quando o cliente não configurou nada', () => {
      expect(getDarkMode(undefined)).toBe('auto');
      expect(getDarkMode(null)).toBe('auto');
      expect(getDarkMode('')).toBe('auto');
    });

    it('cai em "auto" quando o valor configurado é inválido', () => {
      expect(getDarkMode('escuro')).toBe('auto');
      expect(getDarkMode('DARK')).toBe('auto');
    });

    it('respeita a escolha explícita do cliente', () => {
      // Quem escreveu `darkMode: 'light'` no snippet continua com claro. A
      // mudança de default não pode virar mudança de comportamento de quem
      // já decidiu.
      expect(getDarkMode('light')).toBe('light');
      expect(getDarkMode('dark')).toBe('dark');
      expect(getDarkMode('auto')).toBe('auto');
    });

    it('a constante do default é a mesma que o helper aplica', () => {
      expect(DEFAULT_DARK_MODE).toBe('auto');
      expect(getDarkMode(undefined)).toBe(DEFAULT_DARK_MODE);
    });
  });

  describe('ponta 2: o store do widget, que recebe o `config-set`', () => {
    it('o estado inicial já é "auto"', () => {
      // Vale para o intervalo entre o mount do widget e a chegada do
      // `config-set` — em rede lenta, é o que o visitante vê primeiro.
      expect(appConfig.state.darkMode).toBe('auto');
    });

    it('setAppConfig sem `darkMode` grava "auto", não "light"', () => {
      const commits = [];
      const commit = (tipo, carga) => commits.push({ tipo, carga });

      appConfig.actions.setAppConfig({ commit }, {});

      const configCommit = commits.find(
        ({ tipo }) => tipo === 'SET_WIDGET_APP_CONFIG'
      );
      expect(configCommit.carga.darkMode).toBe('auto');
    });
  });
});

describe('2.10 — a preferência do SO é reativa (sem remount)', () => {
  // Dublê fiel de `MediaQueryList`: guarda os ouvintes e permite disparar o
  // `change` como o navegador faria quando o usuário troca o tema do SO.
  const criarMediaQueryList = (matchesInicial = false) => {
    const ouvintes = new Set();
    return {
      matches: matchesInicial,
      media: '(prefers-color-scheme: dark)',
      addEventListener: (evento, fn) => evento === 'change' && ouvintes.add(fn),
      removeEventListener: (evento, fn) =>
        evento === 'change' && ouvintes.delete(fn),
      // O que o SO faz: muda `matches` E notifica.
      trocarTemaDoSo(novo) {
        this.matches = novo;
        ouvintes.forEach(fn => fn({ matches: novo }));
      },
      get quantidadeDeOuvintes() {
        return ouvintes.size;
      },
    };
  };

  let mql;

  beforeEach(() => {
    mockDarkMode.value = 'auto';
    mql = criarMediaQueryList(false);
    vi.spyOn(window, 'matchMedia').mockReturnValue(mql);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  // `useDarkMode` é importado ESTATICAMENTE, e não por `await import()` depois
  // de um `vi.resetModules()`. A primeira versão fazia isso e ficou frágil: o
  // import dinâmico paga a transformação do módulo dentro do teste, o que
  // passou dos 5 s de timeout quando o arquivo rodou junto com o resto da
  // suíte (verde isolado, vermelho no pool). O composable lê `matchMedia` no
  // momento da CHAMADA, então o spy do `beforeEach` continua valendo sem
  // precisar recarregar o módulo.
  const carregar = () => useDarkMode();

  it('com "auto" e SO escuro, já nasce escuro', () => {
    mql.matches = true;
    const { prefersDarkMode } = carregar();

    expect(prefersDarkMode.value).toBe(true);
  });

  it('acompanha a troca de tema do SO na MESMA instância', () => {
    const { prefersDarkMode } = carregar();
    expect(prefersDarkMode.value).toBe(false);

    // Nada é remontado entre uma linha e outra: é o mesmo `ref` retornado
    // acima que precisa mudar de valor.
    mql.trocarTemaDoSo(true);
    expect(prefersDarkMode.value).toBe(true);

    mql.trocarTemaDoSo(false);
    expect(prefersDarkMode.value).toBe(false);
  });

  it('registra exatamente um ouvinte de `change`', () => {
    carregar();
    expect(mql.quantidadeDeOuvintes).toBe(1);
  });

  it('a escolha explícita do cliente ignora o SO', () => {
    // `darkMode: 'light'` cravado no snippet vence a preferência do sistema —
    // senão a reatividade nova viraria um defeito para quem já configurou.
    mockDarkMode.value = 'light';
    const { prefersDarkMode } = carregar();

    mql.trocarTemaDoSo(true);
    expect(prefersDarkMode.value).toBe(false);
  });

  it('sobrevive a um navegador sem `matchMedia`', () => {
    // Degradação declarada: sem a API, a preferência do SO é "claro" e o
    // widget não quebra. É o comportamento de hoje, preservado.
    vi.spyOn(window, 'matchMedia').mockReturnValue(undefined);
    const { prefersDarkMode } = carregar();

    expect(prefersDarkMode.value).toBe(false);
  });
});
