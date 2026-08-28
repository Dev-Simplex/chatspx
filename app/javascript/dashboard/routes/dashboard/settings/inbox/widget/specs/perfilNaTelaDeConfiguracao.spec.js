import {
  config,
  enableAutoUnmount,
  flushPromises,
  mount,
} from '@vue/test-utils';
import { reactive } from 'vue';
import AppearancePage from '../appearance/AppearancePage.vue';

/**
 * Bloco 3.07 — o seletor de perfil na TELA DE CONFIGURACAO.
 *
 * O diagnostico media que ele so existia no wizard de criacao
 * (`channels/Website.vue:110`) e que, no unico ponto de montagem, o
 * `allow-empty` desviava o dialogo — entao o aceite do bloco ("trocar o perfil
 * abre dialogo listando nominalmente o que muda e o que continua gravado")
 * nunca acontecia no produto. E o evento `apply` nao tinha ouvinte: cada
 * proposta que o administrador marcava caia no chao.
 *
 * Este arquivo monta a tela de configuracao de verdade — a mesma
 * `AppearancePage` que `Settings.vue` renderiza na aba do widget — e cobra as
 * quatro coisas: o seletor existe, o dialogo abre com o que esta GRAVADO, o
 * que foi marcado vira rascunho e chega no PATCH com a FORMA que o schema do
 * servidor exige, e o que nao foi marcado continua intacto.
 */

const inbox = reactive({
  id: 7,
  name: 'Site da Simplex',
  widget_color: '#2dc46f',
  welcome_title: 'Olá',
  welcome_tagline: 'Fale com a gente',
  reply_time: 'in_a_few_minutes',
  selected_feature_flags: ['attachments'],
  web_widget_script: '<script>oi</script>',
  csat_survey_enabled: false,
  continuity_via_email: true,
  pre_chat_form_enabled: false,
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

// jsdom nao implementa <dialog>: sem o polyfill o `showModal` explode antes de
// o teste chegar no conteudo do dialogo.
beforeAll(() => {
  HTMLDialogElement.prototype.showModal = function showModal() {
    this.open = true;
  };
  HTMLDialogElement.prototype.close = function close() {
    this.open = false;
    this.dispatchEvent(new Event('close'));
  };
});

beforeEach(() => {
  inbox.additional_attributes = {};
  inbox.csat_survey_enabled = false;
  inbox.continuity_via_email = true;
  inbox.pre_chat_form_enabled = false;
  alerts.length = 0;
});

afterEach(() => {
  i18n.global.locale.value = 'en';
  document.body.innerHTML = '';
});

const build = () => {
  i18n.global.locale.value = 'pt_BR';
  return mount(AppearancePage, {
    props: { inboxId: 7 },
    attachTo: document.body,
  });
};

const escolherPerfil = async (wrapper, profile) => {
  await wrapper
    .find(`[data-testid="profile-${profile}"] input`)
    .trigger('change');
};

/** jsdom nao submete o form ao clicar no botao; o evento vai direto. */
const confirmarDialogo = async wrapper => {
  document
    .querySelector('dialog form')
    .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
  await wrapper.vm.$nextTick();
};

const salvar = async wrapper => {
  await wrapper.find('[data-testid="save-button"]').trigger('click');
  await flushPromises();
  return dispatch.mock.calls.at(-1)[1];
};

describe('3.07 — o seletor de perfil na tela de configuração', () => {
  it('a tela de configuração monta o seletor (ele deixa de existir só no wizard)', () => {
    const wrapper = build();

    expect(wrapper.find('[data-testid="profile-support"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="profile-marketing"]').exists()).toBe(
      true
    );
    // `nil` é lido como `support` — sem backfill (A4). Aqui, ao contrário do
    // wizard, HÁ um valor: o radio nasce marcado.
    expect(
      wrapper.find('[data-testid="profile-support"] input').element.checked
    ).toBe(true);
  });

  it('trocar o perfil abre o diálogo — o `allow-empty` do wizard NÃO desvia aqui', async () => {
    const wrapper = build();

    await escolherPerfil(wrapper, 'marketing');

    expect(document.body.textContent).toContain('Trocar o perfil desta caixa');
    // Nada foi gravado ainda: a troca PROPÕE.
    expect(wrapper.find('[data-testid="pending-count"]').exists()).toBe(false);
  });

  it('o diálogo lista o que muda a partir do que está GRAVADO, não de um dublê', async () => {
    // CSAT já está desligado nesta caixa: propor "desligar o CSAT" seria
    // treinar o administrador a clicar sem ler.
    inbox.csat_survey_enabled = false;
    const wrapper = build();

    await escolherPerfil(wrapper, 'marketing');

    const texto = document.body.textContent;
    expect(texto).toContain('Ligar o formulário de pré-chat');
    expect(texto).toContain('Desligar a continuidade por e-mail');
    expect(document.querySelector('#proposal-csatSurveyEnabled')).toBeNull();
    // …e o que fica como está aparece na lista do que CONTINUA gravado.
    expect(
      document.querySelector('[data-testid="kept-values"]').textContent
    ).toContain('Desligar a pesquisa de satisfação (CSAT)');
  });

  it('o `apply` tem ouvinte: o que foi marcado vira rascunho e chega no PATCH', async () => {
    const wrapper = build();

    await escolherPerfil(wrapper, 'marketing');
    await confirmarDialogo(wrapper);

    expect(wrapper.find('[data-testid="pending-count"]').exists()).toBe(true);

    const payload = await salvar(wrapper);

    expect(payload.additional_attributes.widget_profile).toBe('marketing');
    expect(payload.channel.pre_chat_form_enabled).toBe(true);
    expect(payload.channel.continuity_via_email).toBe(false);
  });

  it('`triggersPreset` vai como ESTRUTURA, nunca como a string do preset', async () => {
    const wrapper = build();

    await escolherPerfil(wrapper, 'marketing');
    await confirmarDialogo(wrapper);
    const payload = await salvar(wrapper);

    const gatilhos = payload.additional_attributes.widget_triggers;
    // A string 'teaser_8s_30pct' num campo que o schema exige objeto derruba o
    // PATCH inteiro com 422 — e a tela diria "salvo" com o banco intacto.
    expect(typeof gatilhos).toBe('object');
    expect(gatilhos.enabled).toBe(true);
    expect(gatilhos.triggers.map(item => item.id)).toEqual([
      'time_on_page',
      'scroll_depth',
    ]);
    expect(gatilhos.triggers[0].desktop).toEqual({ enabled: true, value: 8 });
    expect(gatilhos.triggers[1].desktop).toEqual({ enabled: true, value: 30 });
  });

  it('o que foi DESMARCADO não é tocado — a troca propõe, não reescreve', async () => {
    const wrapper = build();
    await escolherPerfil(wrapper, 'marketing');

    const caixa = document.querySelector('#proposal-preChatFormEnabled');
    caixa.checked = false;
    caixa.dispatchEvent(new Event('change', { bubbles: true }));
    await wrapper.vm.$nextTick();

    await confirmarDialogo(wrapper);
    const payload = await salvar(wrapper);

    expect(payload.channel.pre_chat_form_enabled).toBeUndefined();
    expect(payload.channel.continuity_via_email).toBe(false);
  });

  it('nada é apagado: o PATCH não toca as chaves que a troca não propõe', async () => {
    inbox.additional_attributes = {
      widget_appearance: { position: 'left' },
      widget_tracking: { meta_pixel_id: '123' },
    };
    const wrapper = build();

    await escolherPerfil(wrapper, 'marketing');
    await confirmarDialogo(wrapper);
    const payload = await salvar(wrapper);

    expect(payload.additional_attributes.widget_appearance).toBeUndefined();
    expect(payload.additional_attributes.widget_tracking).toBeUndefined();
    // e o store não foi mutado no caminho
    expect(inbox.additional_attributes.widget_appearance).toEqual({
      position: 'left',
    });
  });

  it('cancelar mantém o perfil e não suja o rascunho', async () => {
    const wrapper = build();
    await escolherPerfil(wrapper, 'marketing');

    document.querySelector('dialog').dispatchEvent(new Event('close'));
    await wrapper.vm.$nextTick();

    expect(wrapper.find('[data-testid="pending-count"]').exists()).toBe(false);
    expect(
      wrapper.find('[data-testid="profile-support"] input').element.checked
    ).toBe(true);
  });
});

describe('3.07 — trocar o perfil muda o que a tela mostra', () => {
  it('o lançador expandido é de marketing: some no suporte e volta no marketing', async () => {
    const wrapper = build();

    // O sujeito EXISTE — a asserção negativa não passa por vácuo: o formato
    // "padrão" continua na tela, é só o expandido que o perfil esconde.
    expect(wrapper.find('[data-testid="launcher-standard"]').exists()).toBe(
      true
    );
    expect(
      wrapper.find('[data-testid="launcher-expanded_bubble"]').exists()
    ).toBe(false);

    await escolherPerfil(wrapper, 'marketing');
    await confirmarDialogo(wrapper);

    expect(
      wrapper.find('[data-testid="launcher-expanded_bubble"]').exists()
    ).toBe(true);
  });

  it('o perfil ESCONDE, não remove: o link de escape traz a seção de volta sem trocar nada', async () => {
    const wrapper = build();
    expect(
      wrapper.find('[data-testid="launcher-expanded_bubble"]').exists()
    ).toBe(false);

    await wrapper
      .find('[data-testid="profile-escape-toggle"]')
      .trigger('click');

    expect(
      wrapper.find('[data-testid="launcher-expanded_bubble"]').exists()
    ).toBe(true);
    // o perfil não mudou, e nada foi para o rascunho
    expect(
      wrapper.find('[data-testid="profile-support"] input').element.checked
    ).toBe(true);
    expect(wrapper.find('[data-testid="pending-count"]').exists()).toBe(false);
  });

  it('a tela não mente sobre o que está gravado: formato expandido continua à vista no suporte', () => {
    inbox.additional_attributes = {
      widget_appearance: { launcher_type: 'expanded_bubble' },
    };
    const wrapper = build();

    expect(
      wrapper.find('[data-testid="launcher-expanded_bubble"]').exists()
    ).toBe(true);
    expect(
      wrapper.find('[data-testid="launcher-expanded_bubble"] input').element
        .checked
    ).toBe(true);
  });
});
