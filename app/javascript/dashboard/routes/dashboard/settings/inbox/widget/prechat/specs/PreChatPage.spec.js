import { config, mount } from '@vue/test-utils';
import { reactive, nextTick } from 'vue';
import PreChatPage from '../PreChatPage.vue';

const [i18n] = config.global.plugins;
const withLocale = locale => {
  i18n.global.locale.value = locale;
};

let storeState;
let store;
let push;
let dialogOpen;
let dialogClose;

vi.mock('dashboard/composables/store', async () => {
  const { computed } = await import('vue');
  return {
    useStore: () => store,
    // O `Dialog` monta `TeleportWithDirection`, que lê `accounts/isRTL`. Sem
    // este export o mock derruba o componente inteiro por um getter que nada
    // nesta tela usa.
    useMapGetter: () => computed(() => false),
  };
});

vi.mock('vue-router', () => ({
  useRouter: () => ({ push: (...args) => push(...args) }),
  onBeforeRouteLeave: () => {},
}));

const field = (name, extra = {}) => ({
  name,
  label: name,
  field_type: 'standard',
  type: 'text',
  enabled: true,
  required: false,
  ...extra,
});

// O formato real de quem está em produção: três campos ligados e a cauda de
// atributos personalizados que a tela antiga gravou desligados.
const inboxFixture = (options = {}) => ({
  id: 7,
  name: 'Site da Simplex',
  pre_chat_form_enabled: true,
  pre_chat_form_options: {
    pre_chat_message: 'Fale com a gente',
    pre_chat_fields: [
      field('fullName'),
      field('emailAddress', { type: 'email' }),
      field('phoneNumber'),
      ...Array.from({ length: 5 }, (_, i) =>
        field(`attr_${i}`, { enabled: false, field_type: 'contact_attribute' })
      ),
    ],
    ...options,
  },
  additional_attributes: {},
});

beforeEach(() => {
  push = vi.fn().mockResolvedValue();
  dialogOpen = vi.fn();
  dialogClose = vi.fn();
  storeState = reactive({ inbox: inboxFixture(), uiFlags: {} });
  store = {
    getters: {
      'inboxes/getInbox': () => storeState.inbox,
      get 'inboxes/getUIFlags'() {
        return storeState.uiFlags;
      },
    },
    dispatch: vi.fn().mockResolvedValue(),
  };
  withLocale('pt_BR');
});

afterEach(() => withLocale('en'));

// O `<dialog>` do jsdom não tem `showModal`, então montar o Dialog real
// derrubaria o teste por uma limitação do ambiente, e não por defeito do
// código. O stub expõe `open`/`close` como espiões — assim continua sendo
// verificável QUE a tela pediu confirmação, que é o que o aceite cobra.
const dialogStub = {
  name: 'Dialog',
  template: '<div data-testid="dialog-stub"><slot /></div>',
  setup(_props, { expose }) {
    expose({ open: dialogOpen, close: dialogClose });
  },
};

const build = () =>
  mount(PreChatPage, {
    props: { inboxId: 7 },
    global: { stubs: { Dialog: dialogStub } },
  });

const selectMode = async (wrapper, mode) => {
  await wrapper.find(`[data-testid="mode-${mode}"] input`).trigger('change');
  await nextTick();
};

const enabledNames = wrapper =>
  wrapper.vm.draft.preChat.pre_chat_fields
    .filter(f => f.enabled)
    .map(f => f.name);

describe('PreChatPage — os três modos', () => {
  it('formulário de sempre, sem `mode` gravado, abre em Simples', () => {
    const wrapper = build();

    expect(
      wrapper.find('[data-testid="mode-simple"] input').element.checked
    ).toBe(true);
    expect(wrapper.find('[data-testid="add-step"]').exists()).toBe(false);
  });

  it('`mode: builder` gravado abre em Construtor mesmo com conteúdo simples', () => {
    storeState.inbox = inboxFixture({ mode: 'builder' });
    const wrapper = build();

    expect(
      wrapper.find('[data-testid="mode-builder"] input').element.checked
    ).toBe(true);
    expect(wrapper.find('[data-testid="add-step"]').exists()).toBe(true);
  });

  it('o modo Fluxo troca a lista de campos por onde o alvo mora de verdade', async () => {
    const wrapper = build();

    await selectMode(wrapper, 'flow');

    const card = wrapper.find('[data-testid="flow-mode-card"]');
    expect(card.exists()).toBe(true);
    expect(card.text()).toContain(
      'Qual fluxo atende esta caixa não se escolhe aqui.'
    );
    expect(wrapper.find('[data-testid="field-counter"]').exists()).toBe(false);
    expect(wrapper.vm.draft.preChat.mode).toBe('flow');
  });

  it('o modo Fluxo NÃO grava um id de fluxo — o alvo é do motor, não desta tela', async () => {
    const wrapper = build();

    await selectMode(wrapper, 'flow');

    expect(Object.keys(wrapper.vm.draft.preChat)).not.toContain('flow_id');
  });

  it('o botão do modo Fluxo leva para Automações', async () => {
    const wrapper = build();
    await selectMode(wrapper, 'flow');

    await wrapper.find('[data-testid="flow-link"]').trigger('click');

    expect(push).toHaveBeenCalledWith({ name: 'automation_list' });
  });
});

describe('PreChatPage — migrar sem perder campo (aceite 28)', () => {
  it('Simples → Construtor mantém os campos e grava a intenção', async () => {
    const wrapper = build();
    const before = enabledNames(wrapper);

    await selectMode(wrapper, 'builder');

    expect(enabledNames(wrapper)).toEqual(before);
    expect(wrapper.vm.draft.preChat.mode).toBe('builder');
    expect(wrapper.vm.draft.preChat.pre_chat_fields).toHaveLength(8);
  });

  it('a volta para Simples, sem etapa extra, não pergunta nada e não perde campo', async () => {
    const wrapper = build();

    await selectMode(wrapper, 'builder');
    await selectMode(wrapper, 'simple');

    expect(enabledNames(wrapper)).toEqual([
      'fullName',
      'emailAddress',
      'phoneNumber',
    ]);
    expect(wrapper.vm.draft.preChat.mode).toBe('simple');
  });

  it('a volta com etapa 2 pergunta antes, dizendo o que sai', async () => {
    storeState.inbox = inboxFixture({
      mode: 'builder',
      pre_chat_fields: [
        field('fullName', { step: 1 }),
        field('emailAddress', {
          step: 2,
          show_if: { field: 'fullName', operator: 'filled' },
        }),
      ],
    });
    const wrapper = build();

    await selectMode(wrapper, 'simple');

    // O modo ainda NÃO mudou: a pergunta vem antes da mudança.
    expect(wrapper.vm.draft.preChat.mode).toBe('builder');
    expect(dialogOpen).toHaveBeenCalled();
    expect(wrapper.vm.migrationDescription).toBe(
      'Nenhum campo é apagado: todos passam para a etapa 1. O que deixa de valer são as etapas 2 e as condicionais destes campos: emailAddress.'
    );
  });

  it('confirmada a volta, nenhum campo some — só a etapa e a condicional', async () => {
    storeState.inbox = inboxFixture({
      mode: 'builder',
      pre_chat_fields: [
        field('fullName', { step: 1 }),
        field('emailAddress', {
          step: 2,
          show_if: { field: 'fullName', operator: 'filled' },
        }),
      ],
    });
    const wrapper = build();

    await selectMode(wrapper, 'simple');
    wrapper.vm.confirmMigration();
    await nextTick();

    const fields = wrapper.vm.draft.preChat.pre_chat_fields;
    expect(fields.map(f => f.name)).toEqual(['fullName', 'emailAddress']);
    expect(fields.every(f => f.step === 1)).toBe(true);
    expect(fields[1].show_if).toBeUndefined();
    expect(wrapper.vm.draft.preChat.mode).toBe('simple');
  });
});

describe('PreChatPage — o rascunho', () => {
  it('mexer no formulário não toca no objeto do store', async () => {
    const wrapper = build();

    await selectMode(wrapper, 'builder');

    expect(storeState.inbox.pre_chat_form_options.mode).toBeUndefined();
    expect(
      storeState.inbox.pre_chat_form_options.pre_chat_fields[0].position
    ).toBeUndefined();
  });

  it('a barra de salvar aparece com a alteração pendente', async () => {
    const wrapper = build();
    expect(wrapper.find('[data-testid="pending-count"]').exists()).toBe(false);

    await selectMode(wrapper, 'builder');

    expect(wrapper.find('[data-testid="pending-count"]').text()).toBe(
      '1 alteração não salva'
    );
  });

  it('desligar o pré-chat esconde o construtor inteiro', async () => {
    const wrapper = build();
    expect(wrapper.find('[data-testid="field-counter"]').exists()).toBe(true);

    wrapper.vm.set('preChatEnabled', false);
    await nextTick();

    expect(wrapper.find('[data-testid="field-counter"]').exists()).toBe(false);
  });
});
