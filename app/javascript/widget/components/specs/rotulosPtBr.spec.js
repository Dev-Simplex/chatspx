/**
 * Mecanismo de aceite do bloco 2.17 — a METADE DE MARCAÇÃO.
 *
 * ACEITE (§2.2): «nenhum rótulo acessível em inglês com interface em pt-BR» e,
 * no corpo do bloco, «erro específico por campo».
 *
 * Por que existe separado de `i18n/specs/ptBrQualidade.spec.js`: aquele confere
 * o DICIONÁRIO, este confere o que o componente de fato RENDERIZA. A distância
 * entre os dois foi o defeito: `PRE_CHAT_FORM.FIELDS.*.REQUIRED_ERROR` estava
 * traduzido em 40 idiomas e nenhum componente lia a chave — o formulário
 * mandava `PRE_CHAT_FORM.REQUIRED` ("Obrigatório") para todos os campos, então
 * quem deixasse três campos em branco via a mesma palavra três vezes, sem
 * saber qual campo, e o leitor de tela anunciava a mesma coisa três vezes.
 *
 * O i18n aqui é o REAL (`pt_BR.json`), não um dublê — é justamente a string
 * traduzida que está sob teste.
 */
import { mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';

// `ChatHeader.vue` é `<script setup>` e chama `useRouter()` no topo. Sem este
// dublê o composable devolve `undefined` e o componente quebra ao montar — o
// teste morreria por motivo alheio ao que ele mede.
vi.mock('vue-router', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), go: vi.fn() }),
  useRoute: () => ({ name: 'home', params: {}, query: {} }),
}));
import ptBR from 'widget/i18n/locale/pt_BR.json';
import ChatHeader from '../ChatHeader.vue';
import ChatHeaderExpanded from '../ChatHeaderExpanded.vue';
import ImageBubble from '../ImageBubble.vue';
import { getRequiredMessage } from 'widget/helpers/preChatFieldMessages';

// `legacy: false` + `globalInjection` de propósito: dois dos três componentes
// sob teste são `<script setup>`, e no modo legado o vue-i18n tenta ESCREVER
// `this.$t` na instância — o que o proxy de `<script setup>` recusa
// ("'set' on proxy: trap returned falsish for property '$t'"). Com injeção
// global, `$t` chega ao template pelo caminho que o app de verdade usa.
const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: 'pt_BR',
  messages: { pt_BR: ptBR },
  fallbackWarn: false,
  missingWarn: false,
});

// A chave chega por parâmetro porque quem chama é o helper sob teste, com a
// lista fechada de `CHAVE_POR_CAMPO`. É o mesmo caso justificado lá.
// eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
const t = (chave, params) => i18n.global.t(chave, params ?? {});

const montar = (componente, props = {}) =>
  mount(componente, {
    props,
    global: {
      plugins: [i18n],
      stubs: { FluentIcon: true, HeaderActions: true, Banner: true },
      directives: { dompurifyHtml: () => {} },
    },
  });

// Uma palavra em inglês num `alt` não é "detalhe de código": é o texto que o
// leitor de tela pronuncia. Com o documento em `lang="pt-BR"` (a view do widget
// declara isso desde a Onda 0), "Picture message" sai com fonemas portugueses.
const PARECE_INGLES = /^(avatar|picture message|image|attachment|photo)$/i;

describe('2.17 — rótulos acessíveis renderizados em pt-BR', () => {
  it('ChatHeader: o avatar do agente tem alt traduzido', () => {
    const img = montar(ChatHeader, {
      avatarUrl: 'https://exemplo.test/a.png',
      title: 'Suporte',
    }).find('img');

    expect(img.attributes('alt')).toBe(ptBR.A11Y.AGENT_AVATAR);
    expect(img.attributes('alt')).not.toMatch(PARECE_INGLES);
  });

  it('ChatHeaderExpanded: o avatar do agente tem alt traduzido', () => {
    const img = montar(ChatHeaderExpanded, {
      avatarUrl: 'https://exemplo.test/a.png',
    }).find('img');

    expect(img.attributes('alt')).toBe(ptBR.A11Y.AGENT_AVATAR);
    expect(img.attributes('alt')).not.toMatch(PARECE_INGLES);
  });

  it('ImageBubble: o anexo de imagem tem alt traduzido', () => {
    const img = montar(ImageBubble, {
      url: 'https://exemplo.test/a.png',
      thumb: 'https://exemplo.test/t.png',
      readableTime: '10:00',
    }).find('img');

    expect(img.attributes('alt')).toBe(ptBR.A11Y.IMAGE_ATTACHMENT);
    expect(img.attributes('alt')).not.toMatch(PARECE_INGLES);
  });
});

describe('2.17 — erro de obrigatoriedade é específico por campo', () => {
  it('usa a mensagem própria de cada campo padrão', () => {
    expect(getRequiredMessage({ field: { name: 'fullName' }, t })).toBe(
      'Nome completo é obrigatório'
    );
    expect(getRequiredMessage({ field: { name: 'emailAddress' }, t })).toBe(
      'Endereço de e-mail é obrigatório'
    );
    expect(getRequiredMessage({ field: { name: 'phoneNumber' }, t })).toBe(
      'O número de telefone é obrigatório'
    );
  });

  it('as três mensagens são DISTINTAS entre si', () => {
    // Esta é a asserção que reprova a implementação antiga: com
    // `$t('PRE_CHAT_FORM.REQUIRED')` as três valiam "Obrigatório" e o Set teria
    // tamanho 1.
    const mensagens = ['fullName', 'emailAddress', 'phoneNumber'].map(name =>
      getRequiredMessage({ field: { name }, t })
    );

    expect(new Set(mensagens).size).toBe(3);
  });

  it('campo personalizado nomeia o próprio rótulo, com concordância', () => {
    // "Empresa é obrigatório" seria a tradução mecânica de `{label} is
    // required` — errada em pt-BR, porque o adjetivo concordaria com o rótulo,
    // que pode ser feminino. Prefixar "O campo" faz a concordância fechar para
    // qualquer rótulo, sem uma chave por gênero.
    expect(
      getRequiredMessage({
        field: { name: 'empresa', label: 'Empresa' },
        t,
      })
    ).toBe('O campo Empresa é obrigatório');

    expect(
      getRequiredMessage({ field: { name: 'cpf', label: 'CPF' }, t })
    ).toBe('O campo CPF é obrigatório');
  });

  it('campo personalizado sem rótulo cai na mensagem genérica', () => {
    // Degradação declarada: sem `label` não há como nomear o campo, e uma
    // string "O campo  é obrigatório" com buraco no meio é pior que a genérica.
    expect(getRequiredMessage({ field: { name: 'x' }, t })).toBe('Obrigatório');
  });
});
