import { mount } from '@vue/test-utils';
import SiteContext from '../SiteContext.vue';

/**
 * Bloco 5.23 — a seção que responde "de onde veio esta pessoa e o que o site já sabe dela".
 *
 * O que estes testes protegem, em ordem de importância:
 *  1. o que o SITE mandou não se mistura com o que o AGENTE digitou;
 *  2. ausência de origem é DITA (`nao_disponivel`), não escondida — regra do 1.19;
 *  3. seção sem nada não aparece — regra do aceite, e o oposto de aparecer vazia.
 */
const DEFINICOES = [
  {
    attribute_key: 'first_origin_kind',
    attribute_display_name: 'Tipo de origem (primeiro)',
  },
  {
    attribute_key: 'first_utm_campaign',
    attribute_display_name: 'Campanha (primeira)',
  },
  {
    attribute_key: 'last_page_path',
    attribute_display_name: 'Página em que o chat abriu (última)',
  },
  {
    attribute_key: 'last_gclid',
    attribute_display_name: 'Clique do Google Ads (gclid)',
  },
];

const montar = (props = {}) =>
  mount(SiteContext, {
    props: { definitions: DEFINICOES, ...props },
  });

describe('5.23 — a seção "recebido do site"', () => {
  describe('quando não há nada', () => {
    it('NÃO renderiza — seção vazia ocupa espaço prometendo dado', () => {
      const tela = montar();

      expect(tela.find('[data-testid="site-context"]').exists()).toBe(false);
      expect(tela.text()).toBe('');
    });

    it('não renderiza por causa de valor vazio ou nulo', () => {
      const tela = montar({
        contactAttributes: { first_utm_campaign: '', first_utm_source: null },
      });

      expect(tela.find('[data-testid="site-context"]').exists()).toBe(false);
    });
  });

  describe('origem', () => {
    it('separa a primeira origem (contato) do que trouxe esta conversa', () => {
      const tela = montar({
        contactAttributes: { first_utm_campaign: 'black-friday' },
        conversationAttributes: { last_page_path: '/precos' },
      });

      const primeira = tela.find('[data-testid="site-context-first"]');
      const atual = tela.find('[data-testid="site-context-last"]');

      expect(primeira.text()).toContain('black-friday');
      expect(primeira.text()).not.toContain('/precos');
      expect(atual.text()).toContain('/precos');
    });

    it('usa o rótulo traduzido que o SERVIDOR já definiu', () => {
      const tela = montar({
        contactAttributes: { first_utm_campaign: 'black-friday' },
      });

      expect(tela.text()).toContain('Campanha (primeira)');
    });

    it('sem definição carregada, mostra a chave crua — nunca um rótulo inventado', () => {
      const tela = montar({
        contactAttributes: { first_utm_term: 'tenis-corrida' },
        definitions: [],
      });

      expect(tela.text()).toContain('first_utm_term');
      expect(tela.text()).toContain('tenis-corrida');
    });

    /**
     * O ponto do bloco 1.19: quando não sabemos de onde a pessoa veio, o dado DIZ que não sabe.
     * Se esta linha sumisse, o painel ficaria calado — e silêncio, para quem lê, é
     * indistinguível de "veio direto", que é exatamente a mentira que o 1.22 proibiu.
     */
    it('`nao_disponivel` APARECE, traduzido — ausência tem nome', () => {
      const tela = montar({
        contactAttributes: { first_origin_kind: 'nao_disponivel' },
      });

      expect(tela.find('[data-testid="site-context"]').exists()).toBe(true);
      expect(tela.text()).toContain('Not available');
      expect(tela.text()).not.toContain('nao_disponivel');
    });

    it('traduz os outros tipos de origem', () => {
      const tela = montar({
        contactAttributes: { first_origin_kind: 'busca_paga' },
      });

      expect(tela.text()).toContain('Paid search');
    });

    it('tipo de origem DESCONHECIDO sai cru, em vez de sumir', () => {
      // Se o servidor passar a gravar um `origin_kind` novo antes de o front conhecê-lo, o
      // valor estranho na tela é um bug visível; a linha sumindo é um bug que ninguém abre.
      const tela = montar({
        contactAttributes: { first_origin_kind: 'quantum_search' },
      });

      expect(tela.text()).toContain('quantum_search');
    });
  });

  describe('o que o AGENTE digitou não entra aqui', () => {
    it('ignora atributo fora do vocabulário de origem, mesmo com o prefixo certo', () => {
      // `last_contato` tem o prefixo de origem mas NÃO é chave de origem. Varrer por prefixo
      // faria um atributo do agente aparecer sob o selo "recebido do site" — que é mentir
      // sobre quem escreveu o quê, justamente o que esta seção existe para evitar.
      const tela = montar({
        conversationAttributes: {
          last_page_path: '/precos',
          last_contato: 'ligar depois das 18h',
        },
      });

      expect(tela.text()).toContain('/precos');
      expect(tela.text()).not.toContain('ligar depois das 18h');
    });

    it('ignora atributo comum do agente', () => {
      const tela = montar({
        contactAttributes: { plano: 'ouro', first_utm_source: 'google' },
      });

      expect(tela.text()).toContain('google');
      expect(tela.text()).not.toContain('ouro');
    });
  });

  describe('escopo das chaves espelha o do servidor', () => {
    it('id de clique conta na CONVERSA', () => {
      const tela = montar({ conversationAttributes: { last_gclid: 'Cj0KCQ' } });

      expect(tela.find('[data-testid="site-context-last"]').text()).toContain(
        'Cj0KCQ'
      );
    });

    it('id de clique NÃO existe no escopo do contato', () => {
      // `CONTACT_BASE_KEYS` não inclui os ids de clique — o `OriginRecorder` não os grava lá.
      const tela = montar({ contactAttributes: { first_gclid: 'Cj0KCQ' } });

      expect(tela.find('[data-testid="site-context"]').exists()).toBe(false);
    });
  });

  describe('identidade (4.15)', () => {
    it('não aparece para visitante anônimo — ruído não é informação', () => {
      const tela = montar({
        contactAttributes: { first_utm_source: 'google' },
      });

      expect(tela.find('[data-testid="site-context-identity"]').exists()).toBe(
        false
      );
    });

    it('mostra o identificador e diz que a assinatura foi verificada', () => {
      const tela = montar({ identifier: 'CRM-4711', hmacVerified: true });
      const identidade = tela.find('[data-testid="site-context-identity"]');

      expect(identidade.text()).toContain('CRM-4711');
      expect(identidade.text()).toContain('Verified');
    });

    /**
     * Sem assinatura, qualquer visitante pode chamar `setUser` com o identificador de outro. O
     * agente precisa saber em qual dos dois casos está — por isso a linha existe nos DOIS.
     */
    it('sem assinatura, diz que o site apenas INFORMOU', () => {
      const tela = montar({ identifier: 'CRM-4711', hmacVerified: false });
      const identidade = tela.find('[data-testid="site-context-identity"]');

      expect(identidade.text()).toContain('Unsigned');
      expect(identidade.text()).not.toContain('proved');
    });

    it('identidade sozinha já faz a seção existir', () => {
      const tela = montar({ identifier: 'CRM-4711' });

      expect(tela.find('[data-testid="site-context"]').exists()).toBe(true);
    });
  });

  it('o selo aparece UMA vez, não por linha', () => {
    const tela = montar({
      contactAttributes: {
        first_utm_source: 'google',
        first_utm_medium: 'cpc',
      },
      conversationAttributes: { last_page_path: '/precos' },
    });

    expect(tela.findAll('[data-testid="site-context-badge"]')).toHaveLength(1);
  });
});
