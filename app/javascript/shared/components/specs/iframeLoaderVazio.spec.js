/**
 * Bloco 2.17 — a tela de artigo mostrava a CHAVE CRUA `PORTAL.IFRAME_ERROR`.
 *
 * O `IframeLoader.vue` é compartilhado por dois aplicativos com catálogos de
 * mensagens diferentes, e pedia `t('PORTAL.IFRAME_ERROR')` — uma chave que não
 * existe em NENHUM dos dois:
 *
 *   · widget  → os 56 `widget/i18n/locale/*.json` têm `PORTAL`, e dentro dele
 *               `IFRAME_LOAD_ERROR` (traduzido nos 56, lido por ninguém).
 *   · painel  → não tem `PORTAL` no topo; a frase mora em
 *               `HELP_CENTER.ARTICLE_SEARCH.IFRAME_ERROR` (também órfã).
 *
 * Ou seja: duas frases traduzidas em produção, nenhuma das duas alcançada, e o
 * visitante lendo `PORTAL.IFRAME_ERROR` em letra de fôrma. É o oposto exato de
 * uma tradução faltando — a tradução existia e a marcação apontava para o
 * vazio, o mesmo formato de defeito que o `REQUIRED_ERROR` teve neste bloco.
 *
 * O destino escolhido é o texto vir do HOSPEDEIRO, por prop: a frase é do
 * catálogo de quem monta, e uma cadeia de chaves testadas em tempo de execução
 * dentro do componente esconderia justamente o mapeamento que quebrou aqui.
 */
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import IframeLoader from 'shared/components/IframeLoader.vue';
import ArticleViewer from 'widget/views/ArticleViewer.vue';

const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

// Uma chave de i18n que vazou para a tela tem forma reconhecível: só
// maiúsculas, dígitos, `_` e pelo menos um ponto.
const PARECE_CHAVE_CRUA = /^[A-Z0-9_]+(\.[A-Z0-9_]+)+$/;

const montarViewer = () =>
  mount(ArticleViewer, {
    global: {
      plugins: [i18n],
      mocks: { $route: { query: { link: '' } } },
      stubs: { ArticleSkeletonLoader: true },
    },
  });

describe('2.17 — o estado vazio do artigo não mostra chave crua', () => {
  it('a frase que o widget usa existe traduzida no locale', () => {
    // Guarda contra o vácuo: se a chave sumisse do locale, o teste de
    // marcação abaixo passaria a medir a ausência de texto, não a presença
    // de tradução.
    expect(ptBR.PORTAL.IFRAME_LOAD_ERROR).toMatch(/^Ocorreu um erro/);
  });

  it('IframeLoader sem URL renderiza a mensagem recebida', () => {
    const wrapper = mount(IframeLoader, {
      props: { url: '', errorMessage: 'Não deu para abrir o artigo.' },
      global: { plugins: [i18n], stubs: { ArticleSkeletonLoader: true } },
    });
    expect(wrapper.text()).toContain('Não deu para abrir o artigo.');
  });

  it('ArticleViewer sem link mostra português, não a chave', () => {
    const texto = montarViewer().text();

    // Sem esta guarda, um estado vazio que renderizasse NADA passaria na
    // asserção negativa seguinte.
    expect(texto.trim().length).toBeGreaterThan(0);
    expect(texto).not.toMatch(/PORTAL\.IFRAME/);
    expect(texto.trim()).not.toMatch(PARECE_CHAVE_CRUA);
    expect(texto).toContain(ptBR.PORTAL.IFRAME_LOAD_ERROR);
  });
});
