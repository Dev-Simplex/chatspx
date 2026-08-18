import {
  config,
  enableAutoUnmount,
  flushPromises,
  mount,
} from '@vue/test-utils';
import { reactive } from 'vue';
import TriggersPage from '../TriggersPage.vue';

const inbox = reactive({
  id: 7,
  name: 'Site da Simplex',
  widget_color: '#2dc46f',
  additional_attributes: {},
});

const dispatch = vi.fn().mockResolvedValue();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getInbox': () => inbox,
      'inboxes/getUIFlags': {},
    },
    dispatch,
  }),
  useMapGetter: () => ({ value: 'ltr' }),
}));

const alertas = [];
vi.mock('dashboard/composables', () => ({
  useAlert: mensagem => alertas.push(mensagem),
}));

const [i18n] = config.global.plugins;
enableAutoUnmount(afterEach);

beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.open = true;
  };
  HTMLDialogElement.prototype.close = function close() {
    this.open = false;
  };
});

beforeEach(() => {
  inbox.additional_attributes = {};
  alertas.length = 0;
});

afterEach(() => {
  i18n.global.locale.value = 'en';
  document.body.innerHTML = '';
});

const build = () => {
  i18n.global.locale.value = 'pt_BR';
  return mount(TriggersPage, { props: { inboxId: 7 } });
};

const dialogo = () => document.body.textContent;

describe('4.04 — a abordagem em três níveis', () => {
  it('os três níveis aparecem, e Chamativo vem pré-selecionado', () => {
    const wrapper = build();

    expect(wrapper.find('[data-testid="approach-discreet"]').exists()).toBe(
      true
    );
    expect(wrapper.find('[data-testid="approach-bold"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="approach-aggressive"]').exists()).toBe(
      true
    );

    expect(
      wrapper.find('[data-testid="approach-bold"] input').element.checked
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="approach-discreet"] input').element.checked
    ).toBe(false);
    expect(
      wrapper.find('[data-testid="approach-aggressive"] input').element.checked
    ).toBe(false);
  });

  it('cada nível diz o que FAZ, não só o nome', () => {
    const wrapper = build();
    const texto = wrapper.text();

    // as strings sao as do namespace APPROACH, que a trilha do backend
    // declarou junto do schema de 3.20 — esta tela consome, nao duplica
    expect(texto).toContain('Um balão pequeno com uma frase');
    expect(texto).toContain('foto de quem atende');
    expect(texto).toContain('O painel abre sozinho');
  });

  it('escolher Agressivo NÃO grava nada antes do aviso', async () => {
    const wrapper = build();

    await wrapper
      .find('[data-testid="approach-aggressive"] input')
      .trigger('change');

    expect(dialogo()).toContain('Abrir o painel sozinho?');
    // ainda em `bold`: o clique abriu o aviso, não mudou o rascunho
    expect(
      wrapper.find('[data-testid="approach-bold"] input').element.checked
    ).toBe(true);
    expect(wrapper.find('[data-testid="pending-count"]').exists()).toBe(false);
  });

  it('o aviso do 4.20 lista as três consequências, e diz o nível do celular', async () => {
    const wrapper = build();
    await wrapper
      .find('[data-testid="approach-aggressive"] input')
      .trigger('change');

    const texto = document.querySelector(
      '[data-testid="auto-open-points"]'
    ).textContent;

    expect(texto).toContain('cobre parte da página');
    expect(texto).toContain('uma vez por sessão');
    expect(texto).toContain('Chamativo');
  });

  it('confirmar liga Agressivo no computador e NADA de agressivo no celular', async () => {
    const wrapper = build();
    await wrapper
      .find('[data-testid="approach-aggressive"] input')
      .trigger('change');

    document
      .querySelector('dialog form')
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
    await flushPromises();

    expect(
      wrapper.find('[data-testid="approach-aggressive"] input').element.checked
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="approach-mobile-note"]').text()
    ).toContain('Chamativo');

    await wrapper.find('[data-testid="save-button"]').trigger('click');
    await flushPromises();

    const [[, payload]] = dispatch.mock.calls;
    expect(payload.additional_attributes.widget_triggers.approach).toBe(
      'aggressive'
    );
    // o celular NUNCA recebe `aggressive` — nem por herança
    expect(payload.additional_attributes.widget_triggers.approach_mobile).toBe(
      'bold'
    );
  });

  it('cancelar o aviso mantém o nível anterior', async () => {
    const wrapper = build();
    await wrapper
      .find('[data-testid="approach-aggressive"] input')
      .trigger('change');

    document.querySelector('dialog').dispatchEvent(new Event('close'));
    await flushPromises();

    expect(
      wrapper.find('[data-testid="approach-bold"] input').element.checked
    ).toBe(true);
    expect(dispatch).not.toHaveBeenCalled();
  });
});

describe('4.04 — a degradação por familiaridade', () => {
  it('nasce ligada e a tela diz, em uma frase, o que ela faz com quem volta', () => {
    const wrapper = build();

    expect(
      wrapper.find('[data-testid="degrade-switch"]').attributes('aria-checked')
    ).toBe('true');
    expect(wrapper.find('[data-testid="degrade-sentence"]').text()).toContain(
      'vê, na próxima visita, uma versão mais discreta'
    );
    expect(wrapper.find('[data-testid="degrade-sentence"]').text()).toContain(
      'impede o convite de virar perseguição'
    );
  });

  it('desligar avisa o que passa a acontecer', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="degrade-switch"]').trigger('click');

    expect(
      wrapper.find('[data-testid="degrade-off-warning"]').text()
    ).toContain('recebe a abordagem cheia em toda visita');
  });
});

describe('4.04 — os sete gatilhos', () => {
  it('mostra os sete, e só o de intenção de saída não existe em celular', () => {
    const wrapper = build();

    [
      'time_on_page',
      'scroll_depth',
      'exit_intent',
      'idle',
      'element_click',
      'element_visible',
      'return_visit',
    ].forEach(id =>
      expect(wrapper.find(`[data-testid="trigger-${id}"]`).exists()).toBe(true)
    );

    expect(wrapper.find('[data-testid="mobile-na-exit_intent"]').text()).toBe(
      'não se aplica'
    );
    expect(wrapper.find('[data-testid="mobile-exit_intent"]').exists()).toBe(
      false
    );
  });

  it('ligar SÓ tempo mostra o aviso do gatilho composto', async () => {
    const wrapper = build();
    expect(wrapper.find('[data-testid="composite-warning"]').exists()).toBe(
      false
    );

    await wrapper.find('[data-testid="desktop-time_on_page"]').trigger('click');

    expect(wrapper.find('[data-testid="composite-warning"]').text()).toContain(
      'saiu para pegar um café'
    );
  });

  it('ligar tempo E rolagem tira o aviso', async () => {
    const wrapper = build();
    await wrapper.find('[data-testid="desktop-time_on_page"]').trigger('click');
    await wrapper.find('[data-testid="desktop-scroll_depth"]').trigger('click');

    expect(wrapper.find('[data-testid="composite-warning"]').exists()).toBe(
      false
    );
  });

  it('o modo Recomendado aplica o preset composto de 8 s E 30%', async () => {
    const wrapper = build();

    await wrapper
      .find('[data-testid="mode-recommended"] input')
      .trigger('change');
    await wrapper.find('[data-testid="save-button"]').trigger('click');
    await flushPromises();

    const [[, payload]] = dispatch.mock.calls;
    expect(payload.additional_attributes.widget_triggers.triggers).toEqual([
      {
        id: 'time_on_page',
        desktop: { enabled: true, value: 8 },
        mobile: { enabled: true, value: 8 },
      },
      {
        id: 'scroll_depth',
        desktop: { enabled: true, value: 30 },
        mobile: { enabled: true, value: 30 },
      },
    ]);
  });
});

describe('4.04 — o seletor CSS', () => {
  it('inválido é rejeitado no BLUR, com a razão do parser', async () => {
    const wrapper = build();
    const campo = wrapper.find('[data-testid="selector-input-element_click"]');

    await campo.setValue('#$%(((');
    // enquanto digita, nenhum erro
    expect(
      wrapper.find('[data-testid="selector-field-element_click"]').text()
    ).toContain('Conferimos só a escrita');

    await campo.trigger('blur');

    expect(
      wrapper.find('[data-testid="selector-field-element_click"]').text()
    ).toContain('Este seletor não é válido');
  });

  it('válido não reclama', async () => {
    const wrapper = build();
    const campo = wrapper.find('[data-testid="selector-input-element_click"]');

    await campo.setValue('[data-cta], #orcamento .btn');
    await campo.trigger('blur');

    expect(
      wrapper.find('[data-testid="selector-field-element_click"]').text()
    ).not.toContain('não é válido');
  });

  it('vazio no blur também é erro — o gatilho não funcionaria', async () => {
    const wrapper = build();
    const campo = wrapper.find('[data-testid="selector-input-element_click"]');

    await campo.setValue('  ');
    await campo.trigger('blur');

    expect(
      wrapper.find('[data-testid="selector-field-element_click"]').text()
    ).toContain('Informe o seletor');
  });
});

describe('4.04 — o que a tela grava', () => {
  it('inbox nova nasce com os convites DESLIGADOS', () => {
    const wrapper = build();

    expect(
      wrapper
        .find('[data-testid="triggers-enabled"]')
        .attributes('aria-checked')
    ).toBe('false');
  });

  it('o PATCH sai com as chaves do schema, e sem nenhuma a mais', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="triggers-enabled"]').trigger('click');
    await wrapper.find('[data-testid="save-button"]').trigger('click');
    await flushPromises();

    const [[acao, payload]] = dispatch.mock.calls;
    expect(acao).toBe('inboxes/updateInbox');
    // `additionalProperties: false` — chave a mais derruba o PATCH inteiro
    expect(
      Object.keys(payload.additional_attributes.widget_triggers).sort()
    ).toEqual(['approach', 'degrade_on_return', 'enabled', 'triggers']);
    expect(payload.additional_attributes.widget_triggers.enabled).toBe(true);
  });

  it('a segmentação avisa que as regras são públicas', () => {
    expect(build().find('[data-testid="public-warning"]').text()).toContain(
      'visíveis para quem inspecionar o código do site'
    );
  });

  it('tirar os dois dispositivos avisa que o convite some', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="device-desktop"]').setValue(false);
    await wrapper.find('[data-testid="device-mobile"]').setValue(false);

    expect(wrapper.find('[data-testid="device-empty"]').text()).toContain(
      'não aparece em lugar nenhum'
    );
  });
});
