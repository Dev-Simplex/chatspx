/**
 * MECANISMO DE ACEITE DO BLOCO 4.10 — a parte que jsdom PODE provar.
 *
 * Aceite (§2.2): `role="radiogroup"` com rótulo textual por opção; alvos 44×44;
 * máximo 3 botões por card.
 *
 * O alvo de 44×44 NÃO está aqui: jsdom não faz layout e devolveria 0×0 para
 * tudo. Ele é medido em Chromium real, com valor computado, em
 * `shared/components/specs/browser/csat-target-size.check.mjs`.
 */
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import StarRating from '../StarRating.vue';
import ChatCard from '../ChatCard.vue';
import { MAX_CARD_ACTIONS } from '../ChatCard.vue';
import { CSAT_RATINGS } from 'shared/constants/messages';
import ptBR from 'widget/i18n/locale/pt_BR.json';
import en from 'widget/i18n/locale/en.json';

const i18n = createI18n({
  legacy: false,
  locale: 'pt_BR',
  fallbackLocale: 'en',
  messages: { pt_BR: ptBR, en },
});

const montarEstrelas = (props = {}) =>
  mount(StarRating, { props, global: { plugins: [i18n] } });

const resolve = (dicionario, chave) =>
  chave.split('.').reduce((no, parte) => (no ?? {})[parte], dicionario);

describe('4.10 — CSAT acessível', () => {
  describe('as chaves de rótulo existem NAS DUAS línguas', () => {
    // Defeito de junção encontrado neste bloco: `CSAT_RATINGS[].translationKey`
    // aponta para `CSAT.RATINGS.*`, que existia no bundle do DASHBOARD e não no
    // do widget — e o componente é renderizado nos dois. Enquanto ninguém usava
    // o rótulo, nada quebrava; usá-lo sem esta correção mostraria a chave crua
    // na tela do visitante.
    it.each(CSAT_RATINGS.map(r => [r.key, r.translationKey]))(
      'a opção %s tem texto em pt_BR e en',
      (_key, chave) => {
        expect(typeof resolve(ptBR, chave)).toBe('string');
        expect(resolve(ptBR, chave).length).toBeGreaterThan(0);
        expect(typeof resolve(en, chave)).toBe('string');
      }
    );

    it('as cinco estrelas também', () => {
      ['ONE', 'TWO', 'THREE', 'FOUR', 'FIVE'].forEach(pos => {
        expect(typeof ptBR.CSAT.STARS[pos]).toBe('string');
        expect(typeof en.CSAT.STARS[pos]).toBe('string');
      });
    });

    it('e o rótulo do grupo', () => {
      expect(ptBR.CSAT.RATING_GROUP_LABEL).toBe('Como foi o atendimento?');
      expect(typeof en.CSAT.RATING_GROUP_LABEL).toBe('string');
    });

    it('o rótulo do widget NÃO carrega emoji dentro do texto', () => {
      // O do dashboard traz ("😞Ruim"), e como nome acessível isso faz o leitor
      // de tela anunciar o símbolo antes da palavra.
      Object.values(ptBR.CSAT.RATINGS).forEach(texto => {
        expect(texto).toMatch(/^[\p{L}\s]+$/u);
      });
    });
  });

  describe('StarRating é um grupo de rádio de verdade', () => {
    it('o container tem role=radiogroup e rótulo traduzido', () => {
      const grupo = montarEstrelas().find('[role="radiogroup"]');
      expect(grupo.exists()).toBe(true);
      expect(grupo.attributes('aria-label')).toBe('Como foi o atendimento?');
    });

    it('cada estrela é role=radio com rótulo TEXTUAL que diz a escala', () => {
      const opcoes = montarEstrelas().findAll('[role="radio"]');
      expect(opcoes).toHaveLength(5);
      expect(opcoes.map(o => o.attributes('aria-label'))).toEqual([
        '1 estrela de 5',
        '2 estrelas de 5',
        '3 estrelas de 5',
        '4 estrelas de 5',
        '5 estrelas de 5',
      ]);
    });

    it("o literal inglês 'Star N' não existe mais", () => {
      const html = montarEstrelas().html();
      expect(html).not.toContain('Star 1');
      expect(html).not.toContain('Star 5');
    });

    it('aria-checked marca só a escolhida', () => {
      const opcoes = montarEstrelas({ selectedRating: 3 }).findAll(
        '[role="radio"]'
      );
      expect(opcoes.map(o => o.attributes('aria-checked'))).toEqual([
        'false',
        'false',
        'true',
        'false',
        'false',
      ]);
    });

    it('o grupo tem UM ponto de parada no Tab — tabindex rotativo', () => {
      const semEscolha = montarEstrelas()
        .findAll('[role="radio"]')
        .map(o => o.attributes('tabindex'));
      expect(semEscolha).toEqual(['0', '-1', '-1', '-1', '-1']);

      const comEscolha = montarEstrelas({ selectedRating: 4 })
        .findAll('[role="radio"]')
        .map(o => o.attributes('tabindex'));
      expect(comEscolha).toEqual(['-1', '-1', '-1', '0', '-1']);
    });

    it('seta para a direita ESCOLHE a próxima, não só move o foco', async () => {
      const wrapper = montarEstrelas({ selectedRating: 2 });
      await wrapper.find('[role="radiogroup"]').trigger('keydown.right');

      expect(wrapper.emitted('selectRating')).toEqual([[3]]);
    });

    it('seta para a esquerda escolhe a anterior', async () => {
      const wrapper = montarEstrelas({ selectedRating: 2 });
      await wrapper.find('[role="radiogroup"]').trigger('keydown.left');

      expect(wrapper.emitted('selectRating')).toEqual([[1]]);
    });

    it('as setas não passam das pontas da escala', async () => {
      const primeira = montarEstrelas({ selectedRating: 1 });
      await primeira.find('[role="radiogroup"]').trigger('keydown.left');
      expect(primeira.emitted('selectRating')).toEqual([[1]]);

      const ultima = montarEstrelas({ selectedRating: 5 });
      await ultima.find('[role="radiogroup"]').trigger('keydown.right');
      expect(ultima.emitted('selectRating')).toEqual([[5]]);
    });

    it('desabilitado não emite escolha, nem por clique nem por seta', async () => {
      const wrapper = montarEstrelas({ isDisabled: true, selectedRating: 2 });
      await wrapper.find('[role="radiogroup"]').trigger('keydown.right');
      await wrapper.findAll('[role="radio"]')[4].trigger('click');

      expect(wrapper.emitted('selectRating')).toBeUndefined();
      expect(
        wrapper.find('[role="radiogroup"]').attributes('aria-disabled')
      ).toBe('true');
    });

    it('o ícone da estrela é decorativo — o nome vive no botão', () => {
      const wrapper = montarEstrelas();
      expect(wrapper.findAll('[aria-hidden="true"]')).toHaveLength(5);
    });
  });

  describe('ChatCard — no máximo 3 botões', () => {
    const acoes = n =>
      Array.from({ length: n }, (_, i) => ({
        id: i + 1,
        type: 'link',
        text: `Ação ${i + 1}`,
        uri: 'https://exemplo.test',
      }));

    const montarCard = quantas =>
      mount(ChatCard, {
        props: { title: 'T', description: 'D', actions: acoes(quantas) },
        global: {
          plugins: [i18n],
          stubs: { CardButton: { template: '<button class="cb" />' } },
        },
      });

    it('o teto é 3, e está declarado como constante', () => {
      expect(MAX_CARD_ACTIONS).toBe(3);
    });

    it('duas ações renderizam duas', () => {
      expect(montarCard(2).findAll('.cb')).toHaveLength(2);
    });

    it('três renderizam três', () => {
      expect(montarCard(3).findAll('.cb')).toHaveLength(3);
    });

    it('SEIS renderizam três — o corte é do consumidor', () => {
      expect(montarCard(6).findAll('.cb')).toHaveLength(3);
    });

    it('e são as três PRIMEIRAS, não três quaisquer', () => {
      const wrapper = mount(ChatCard, {
        props: { title: 'T', description: 'D', actions: acoes(6) },
        global: {
          plugins: [i18n],
          stubs: {
            CardButton: {
              props: ['action'],
              template: '<button class="cb">{{ action.text }}</button>',
            },
          },
        },
      });
      expect(wrapper.findAll('.cb').map(b => b.text())).toEqual([
        'Ação 1',
        'Ação 2',
        'Ação 3',
      ]);
    });

    it('sem ações não renderiza botão nenhum', () => {
      expect(montarCard(0).findAll('.cb')).toHaveLength(0);
    });

    it('a imagem do card é decorativa, e some quando não há URL', () => {
      const semImagem = montarCard(1);
      expect(semImagem.find('img').exists()).toBe(false);

      const comImagem = mount(ChatCard, {
        props: {
          title: 'T',
          description: 'D',
          mediaUrl: 'https://x.test/a.png',
        },
        global: { plugins: [i18n], stubs: { CardButton: true } },
      });
      expect(comImagem.find('img').attributes('alt')).toBe('');
      expect(comImagem.find('img').attributes('aria-hidden')).toBe('true');
    });
  });
});
