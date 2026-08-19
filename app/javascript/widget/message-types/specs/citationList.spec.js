/**
 * Bloco 6.03 — a citação de fonte no widget.
 *
 * O que este spec protege, em ordem de importância:
 *   1. link SÓ quando existe URL pública (documento interno não vira href quebrado);
 *   2. NOME ACESSÍVEL LIMPO — título com emoji continua com emoji na tela e sem
 *      emoji no `aria-label`, porque o leitor de tela anunciaria o símbolo;
 *   3. nenhum controle sem nome.
 */
import { mount } from '@vue/test-utils';
import CitationList from '../CitationList.vue';

const traduz = (chave, params = {}) => {
  if (chave === 'CITATION.SOURCE') return 'Fonte:';
  if (chave === 'CITATION.FALLBACK_NAME') return 'documento';
  if (chave === 'CITATION.OPEN_LABEL')
    return `Abrir o documento ${params.documento}`;
  return chave;
};

const montar = citations =>
  mount(CitationList, {
    props: { citations },
    global: { mocks: { $t: traduz } },
  });

const PICTOGRAFICO = /\p{Extended_Pictographic}/u;

describe('6.03 — CitationList', () => {
  it('não desenha nada quando a resposta não tem fonte', () => {
    expect(montar([]).find('.citation-list').exists()).toBe(false);
  });

  it('mostra de onde a resposta veio', () => {
    const wrapper = montar([
      {
        title: 'Política de trocas',
        url: 'https://exemplo.com/trocas',
        excerpt: '30 dias',
      },
    ]);

    expect(wrapper.text()).toContain('Política de trocas');
    expect(wrapper.text()).toContain('Fonte:');
  });

  it('abre o documento quando ele é público', () => {
    const wrapper = montar([
      {
        title: 'Política de trocas',
        url: 'https://exemplo.com/trocas',
        excerpt: '30 dias',
      },
    ]);
    const link = wrapper.get('a');

    expect(link.attributes('href')).toBe('https://exemplo.com/trocas');
    expect(link.attributes('target')).toBe('_blank');
    expect(link.attributes('rel')).toBe('noopener noreferrer');
  });

  it('não vira link quando o documento não é público', () => {
    const wrapper = montar([
      { title: 'Manual interno', url: null, excerpt: 'x' },
    ]);

    expect(wrapper.find('a').exists()).toBe(false);
    expect(wrapper.text()).toContain('Manual interno');
  });

  it('anuncia o documento pelo nome, e o nome é texto limpo', () => {
    const wrapper = montar([
      {
        title: '🔥 Política de trocas',
        url: 'https://exemplo.com/trocas',
        excerpt: 'x',
      },
    ]);
    const rotulo = wrapper.get('a').attributes('aria-label');

    expect(rotulo).toBe('Abrir o documento Política de trocas');
    expect(PICTOGRAFICO.test(rotulo)).toBe(false);
    // o símbolo continua na tela: ele é do visual, não do nome
    expect(wrapper.text()).toContain('🔥');
  });

  it('cai num nome genérico quando o título é só símbolo', () => {
    const wrapper = montar([
      { title: '🔥🔥', url: 'https://exemplo.com/x', excerpt: 'x' },
    ]);

    expect(wrapper.get('a').attributes('aria-label')).toBe(
      'Abrir o documento documento'
    );
  });

  it('descarta a citação sem título', () => {
    const wrapper = montar([
      { title: '', url: 'https://exemplo.com/x', excerpt: 'x' },
      { title: 'Política', url: null, excerpt: 'x' },
    ]);

    expect(wrapper.findAll('li')).toHaveLength(1);
  });

  it('lista todas as fontes que a resposta usou', () => {
    const wrapper = montar([
      { title: 'A', url: 'https://exemplo.com/a', excerpt: 'x' },
      { title: 'B', url: 'https://exemplo.com/b', excerpt: 'y' },
    ]);

    expect(wrapper.findAll('a')).toHaveLength(2);
  });

  it('põe o trecho no title, e nunca no lugar do nome', () => {
    const wrapper = montar([
      {
        title: 'Política',
        url: 'https://exemplo.com/x',
        excerpt: 'Troca em 30 dias.',
      },
    ]);

    expect(wrapper.get('a').attributes('title')).toBe('Troca em 30 dias.');
    expect(wrapper.get('a').text()).toBe('Política');
  });
});
