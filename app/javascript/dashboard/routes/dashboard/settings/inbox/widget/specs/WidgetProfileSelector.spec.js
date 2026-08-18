import { config, enableAutoUnmount, mount } from '@vue/test-utils';
import WidgetProfileSelector from '../WidgetProfileSelector.vue';

// `Dialog` monta por `TeleportWithDirection`, que le a direcao do texto do
// store — sem isto o teste morre em `getters` antes de chegar no que interessa.
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: 'ltr' }),
  useStore: () => ({ getters: {}, dispatch: vi.fn() }),
}));

// jsdom nao implementa <dialog>: sem estes dois, `showModal` explode antes de o
// teste chegar no conteudo do dialogo. O polyfill so liga/desliga o atributo
// `open` e emite `close`, que e tudo o que o componente usa.
beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.open = true;
  };
  HTMLDialogElement.prototype.close = function close() {
    this.open = false;
    this.dispatchEvent(new Event('close'));
  };
});

const [i18n] = config.global.plugins;

// O dialogo e TELEPORTADO para o body: sem desmontar, o resto do arquivo
// encontra o dialogo do teste anterior em `document.querySelector`.
enableAutoUnmount(afterEach);
afterEach(() => {
  i18n.global.locale.value = 'en';
  document.body.innerHTML = '';
});

const build = (props = {}) => {
  i18n.global.locale.value = 'pt_BR';
  return mount(WidgetProfileSelector, {
    props: {
      modelValue: 'support',
      currentValues: {
        preChatFormEnabled: false,
        csatSurveyEnabled: true,
        continuityViaEmail: true,
        knowledgeBase: true,
      },
      ...props,
    },
    attachTo: document.body,
  });
};

const radio = (wrapper, profile) =>
  wrapper.find(`[data-testid="profile-${profile}"] input`);

describe('WidgetProfileSelector', () => {
  it('mostra os dois perfis com o nome e a explicação em pt-BR', () => {
    const wrapper = build();

    expect(wrapper.text()).toContain('Suporte');
    expect(wrapper.text()).toContain('Marketing');
    expect(wrapper.text()).toContain('O widget espera o clique');
  });

  it('trocar NÃO grava sozinho: abre o diálogo', async () => {
    const wrapper = build();

    await radio(wrapper, 'marketing').trigger('change');

    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(document.body.textContent).toContain('Trocar o perfil desta caixa');
  });

  it('o diálogo lista NOMINALMENTE cada mudança proposta', async () => {
    const wrapper = build();

    await radio(wrapper, 'marketing').trigger('change');

    const texto = document.body.textContent;
    expect(texto).toContain('Ligar o formulário de pré-chat');
    expect(texto).toContain('8 segundos na página E 30% de rolagem');
    expect(texto).toContain('Desligar a pesquisa de satisfação (CSAT)');
    expect(texto).toContain('Esconder a Central de Ajuda');
  });

  it('o diálogo diz, por escrito, que nada é apagado', async () => {
    const wrapper = build();

    await radio(wrapper, 'marketing').trigger('change');

    expect(document.body.textContent).toContain(
      'Nada é apagado. Toda configuração do perfil anterior fica no banco'
    );
  });

  it('desmarcar um item o tira do que será aplicado', async () => {
    const wrapper = build();
    await radio(wrapper, 'marketing').trigger('change');

    const caixa = document.querySelector('#proposal-csatSurveyEnabled');
    caixa.checked = false;
    caixa.dispatchEvent(new Event('change', { bubbles: true }));
    await wrapper.vm.$nextTick();

    // jsdom nao submete o form ao clicar no botao submit; o evento vai direto.
    document
      .querySelector('dialog form')
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await wrapper.vm.$nextTick();

    const [[payload]] = wrapper.emitted('apply');
    expect(payload.profile).toBe('marketing');
    expect(payload.accepted.map(item => item.id)).toEqual([
      'preChatFormEnabled',
      'triggersPreset',
      'continuityViaEmail',
      'knowledgeBase',
    ]);
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['marketing']);
  });

  it('cancelar mantém o perfil atual e não aplica nada', async () => {
    const wrapper = build();
    await radio(wrapper, 'marketing').trigger('change');

    await document.querySelector('dialog').dispatchEvent(new Event('close'));
    await wrapper.vm.$nextTick();

    expect(wrapper.emitted('update:modelValue')).toBeUndefined();
    expect(wrapper.emitted('apply')).toBeUndefined();
  });

  it('no wizard de criação nada vem pré-selecionado, e escolher é direto', async () => {
    const wrapper = build({ modelValue: '', allowEmpty: true });

    expect(radio(wrapper, 'support').element.checked).toBe(false);
    expect(radio(wrapper, 'marketing').element.checked).toBe(false);

    await radio(wrapper, 'marketing').trigger('change');

    // inbox nova nao tem valor gravado para preservar: sem dialogo
    expect(wrapper.emitted('update:modelValue').at(-1)).toEqual(['marketing']);
  });
});
