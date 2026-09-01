/**
 * Bloco 2.17 — a caixa de emoji renderizava os títulos de seção em INGLÊS.
 *
 * O defeito e por que o instrumento anterior não o via: o aceite do 2.17 é
 * «nenhum rótulo acessível em inglês com interface em pt-BR», e a trilha
 * anterior o mediu comparando chaves DENTRO de `widget/i18n/`. Esse
 * instrumento é cego por construção para rótulo que não vem de um arquivo de
 * locale: os nove nomes de categoria da caixa de emoji vêm de
 * `shared/components/emoji/emojisGroup.json` — dados, não tradução — e
 * chegavam à tela crus ("Smileys & Emotion", "People & Body", …) com o
 * documento declarando `lang="pt-BR"`.
 *
 * O dicionário JÁ EXISTIA: `EMOJI.CATEGORIES.<SLUG>` está traduzido e é lido
 * pelo `EmojiInput.vue` do painel desde sempre. Quem não o lia era o
 * `EmojiPicker.vue` — o componente que o WIDGET carrega sob a feature
 * `emoji_picker`. Mesmo dado, dois componentes, um só traduzia.
 *
 * Este arquivo mede o MECANISMO (o helper puro, sem layout) e a MARCAÇÃO (o
 * texto que o componente monta de fato). Os dois, porque um helper certo com
 * um template que não o chama é exatamente o defeito que estamos consertando.
 */
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';

// O `Virtualizer` do `virtua` decide QUANTOS itens desenhar a partir de
// tamanhos medidos. No jsdom todo elemento mede 0×0, então ele desenha ZERO —
// e uma lista vazia faz qualquer asserção negativa passar sem medir nada. O
// dublê tem a FORMA REAL do contrato usado pelo componente:
// `<Virtualizer v-slot="{ item }" :data="…">`, um slot por entrada de `data`.
// A virtualização não está sob teste aqui; o texto do título está.
vi.mock('virtua/vue', () => ({
  Virtualizer: {
    name: 'Virtualizer',
    props: { data: { type: Array, default: () => [] } },
    setup(props, { slots }) {
      return () => props.data.map(item => slots.default?.({ item }));
    },
  },
}));
import ptBR from 'widget/i18n/locale/pt_BR.json';
import grupos from 'shared/components/emoji/emojisGroup.json';
import {
  buildEmojiSections,
  translateCategoryName,
} from 'shared/components/emoji/pickerHelper';
import EmojiPicker from 'shared/components/emoji/EmojiPicker.vue';

const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

// A chave chega montada porque é isso que o helper sob teste faz — a lista de
// slugs é fechada e vem do próprio `emojisGroup.json`.
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const t = chave => i18n.global.t(chave);

const OS_NOVE_EM_INGLES = grupos.map(g => g.name);

describe('2.17 — títulos de seção da caixa de emoji em pt-BR', () => {
  beforeEach(() => localStorage.clear());

  describe('o mecanismo', () => {
    it('os nove grupos do JSON estão em inglês (é o dado de entrada)', () => {
      // Guarda contra o vácuo: se um dia o JSON vier traduzido, o resto deste
      // arquivo passaria sem medir nada.
      expect(OS_NOVE_EM_INGLES).toHaveLength(9);
      expect(OS_NOVE_EM_INGLES).toContain('Smileys & Emotion');
    });

    it('translateCategoryName devolve o nome do locale', () => {
      expect(translateCategoryName(t, grupos[0])).toBe('Carinhas e emoções');
    });

    it('cai no nome original quando o slug não está no locale', () => {
      // O "Usados com frequência" é uma seção sintética, sem slug. Ela não
      // pode virar chave crua na tela.
      expect(translateCategoryName(t, { name: 'Usados com frequência' })).toBe(
        'Usados com frequência'
      );
      expect(
        translateCategoryName(t, { name: 'Xyz', slug: 'nao_existe' })
      ).toBe('Xyz');
    });

    it('a busca preserva o slug de cada seção', () => {
      // Era aqui que o slug morria: o ramo de busca remontava `{ name, emojis }`
      // e descartava o `slug`, então nem um template correto teria como
      // traduzir enquanto o visitante digitasse.
      const secoes = buildEmojiSections('grinning', [], 'Usados');
      expect(secoes.length).toBeGreaterThan(0);
      expect(secoes.every(s => typeof s.slug === 'string')).toBe(true);
    });
  });

  describe('a marcação', () => {
    const montar = () => mount(EmojiPicker, { global: { plugins: [i18n] } });

    it('nenhum título de seção renderizado está em inglês', () => {
      const wrapper = montar();
      const titulos = wrapper.findAll('h5').map(h => h.text());

      // Guarda contra o vácuo: o `Virtualizer` pode não renderizar nada num
      // ambiente sem layout, e um `[]` passaria em qualquer asserção negativa.
      expect(titulos.length).toBeGreaterThan(0);

      expect(
        titulos.filter(titulo => OS_NOVE_EM_INGLES.includes(titulo))
      ).toEqual([]);
    });

    it('o primeiro título é o traduzido', () => {
      const wrapper = montar();
      expect(wrapper.findAll('h5')[0].text()).toBe('Carinhas e emoções');
    });
  });
});
