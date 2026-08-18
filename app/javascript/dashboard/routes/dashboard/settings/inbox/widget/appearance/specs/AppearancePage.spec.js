import {
  config,
  enableAutoUnmount,
  flushPromises,
  mount,
} from '@vue/test-utils';
import { reactive } from 'vue';
import AppearancePage from '../AppearancePage.vue';

const inbox = reactive({
  id: 7,
  name: 'Site da Simplex',
  widget_color: '#2dc46f',
  welcome_title: 'Olá',
  welcome_tagline: 'Fale com a gente',
  reply_time: 'in_a_few_minutes',
  selected_feature_flags: ['attachments'],
  web_widget_script: '<script>oi</script>',
  additional_attributes: {},
});

const dispatch = vi.fn().mockResolvedValue();

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getInbox': () => inbox,
      'inboxes/getUIFlags': {},
      'globalConfig/get': { logoThumbnail: '/logo.png' },
    },
    dispatch,
  }),
  useMapGetter: key =>
    key === 'globalConfig/get'
      ? { value: { logoThumbnail: '/logo.png' } }
      : { value: 'ltr' },
}));

const alerts = [];
vi.mock('dashboard/composables', () => ({
  useAlert: message => alerts.push(message),
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
  alerts.length = 0;
});

afterEach(() => {
  i18n.global.locale.value = 'en';
  document.body.innerHTML = '';
});

const build = () => {
  i18n.global.locale.value = 'pt_BR';
  return mount(AppearancePage, { props: { inboxId: 7 } });
};

describe('AppearancePage — o que a tela grava', () => {
  it('a posição do lançador vem da inbox, não do localStorage', () => {
    inbox.additional_attributes = { widget_appearance: { position: 'left' } };
    const wrapper = build();

    expect(
      wrapper.find('[data-testid="position-left"] input').element.checked
    ).toBe(true);
    // o defeito D1: hoje o valor vem de LOCAL_STORAGE_KEYS.WIDGET_BUILDER
    expect(window.localStorage.getItem('widget_builder_7')).toBeNull();
  });

  it('trocar a posição para esquerda e salvar manda `position` no PATCH', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="position-left"] input').trigger('change');
    expect(wrapper.find('[data-testid="pending-count"]').text()).toBe(
      '1 alteração não salva'
    );

    await wrapper.find('[data-testid="save-button"]').trigger('click');
    await flushPromises();

    expect(dispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 7,
      formData: false,
      additional_attributes: {
        widget_appearance: expect.objectContaining({ position: 'left' }),
      },
    });
  });

  it('o offset é preso na faixa do schema, e não vira valor inválido', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="offset-x"] input').setValue('500');

    expect(wrapper.find('[data-testid="offset-x"] input').element.value).toBe(
      '120'
    );
  });

  it('o texto do lançador só aparece no formato com texto', async () => {
    const wrapper = build();
    expect(wrapper.find('[data-testid="launcher-text"]').exists()).toBe(false);

    await wrapper
      .find('[data-testid="launcher-expanded_bubble"] input')
      .trigger('change');

    expect(wrapper.find('[data-testid="launcher-text"]').exists()).toBe(true);
  });

  it('editar e descartar devolve o gravado, sem tocar no store', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="position-left"] input').trigger('change');
    await wrapper.find('[data-testid="discard-button"]').trigger('click');

    expect(wrapper.find('[data-testid="pending-count"]').exists()).toBe(false);
    expect(inbox.additional_attributes.widget_appearance).toBeUndefined();
    expect(dispatch).not.toHaveBeenCalled();
  });
});

describe('AppearancePage — quando o site sobrescreve', () => {
  it('sem override, nenhum aviso — ausência de dado não vira aviso falso', () => {
    expect(build().find('[data-testid="override-banner"]').exists()).toBe(
      false
    );
  });

  it('com override, a tela avisa e NOMEIA o campo em vez de mentir', () => {
    inbox.additional_attributes = {
      widget_appearance: { position: 'right' },
      widget_appearance_overrides: ['position', 'theme'],
    };
    const wrapper = build();
    const banner = wrapper.find('[data-testid="override-banner"]');

    expect(banner.exists()).toBe(true);
    expect(banner.text()).toContain('O site sobrescreve esta configuração');
    expect(banner.text()).toContain('Posição do lançador');
    expect(banner.text()).toContain('Modo de tema');
  });
});

describe('AppearancePage — o medidor e o preview', () => {
  it('o medidor mostra a leitura da cor gravada', () => {
    const wrapper = build();

    expect(
      wrapper.find('[data-testid="contrast-brandAsTextLight"]').text()
    ).toContain('2,27:1');
  });

  it('o preview segue o RASCUNHO, não o store', async () => {
    const wrapper = build();

    await wrapper.find('[data-testid="welcome-title"] input').setValue('Novo');

    expect(wrapper.find('.widget-wrapper').text()).toContain('Novo');
    expect(inbox.welcome_title).toBe('Olá');
  });
});

describe('AppearancePage — sair da aba com pendência', () => {
  it('sem pendência, `requestLeave` deixa sair na hora', () => {
    const wrapper = build();
    const acao = vi.fn();

    expect(wrapper.vm.requestLeave(acao)).toBe(true);
    expect(acao).toHaveBeenCalledTimes(1);
  });

  it('com pendência, segura a saída e lista o que se perde', async () => {
    const wrapper = build();
    await wrapper.find('[data-testid="position-left"] input').trigger('change');
    const acao = vi.fn();

    expect(wrapper.vm.requestLeave(acao)).toBe(false);
    expect(acao).not.toHaveBeenCalled();

    await wrapper.vm.$nextTick();
    expect(document.body.textContent).toContain('Sair sem salvar?');
    expect(document.body.textContent).toContain('Posição do lançador');
  });
});
