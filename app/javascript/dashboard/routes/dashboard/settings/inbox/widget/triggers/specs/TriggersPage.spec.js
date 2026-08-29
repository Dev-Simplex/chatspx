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

/**
 * A tela despacha mais de uma coisa: a seção "modo antigo" (4.22) carrega as
 * campanhas ao montar, e o PATCH da inbox só vem depois. Pescar
 * `dispatch.mock.calls[0]` pegava esse carregamento em vez do PATCH — a asserção
 * tem de dizer QUAL chamada ela mede, e não a ordem em que ela por acaso caiu.
 */
const chamadasDeSalvar = () =>
  dispatch.mock.calls.filter(([acao]) => acao === 'inboxes/updateInbox');

// A pagina monta o TeaserComposer (4.05), que le as campanhas de chat ao vivo:
// um mock que devolve a mesma coisa para toda chave faria `campanhas.find`
// explodir antes de o teste chegar no que ele mede.
const campanhas = [
  { id: 31, title: 'Convite', message: 'Posso ajudar?', inbox: { id: 7 } },
];

vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({
    getters: {
      'inboxes/getInbox': () => inbox,
      'inboxes/getUIFlags': {},
      'globalConfig/get': { logoThumbnail: '' },
    },
    dispatch,
  }),
  useMapGetter: chave => {
    if (chave === 'campaigns/getLiveChatCampaigns') return { value: campanhas };
    if (chave === 'campaigns/getUIFlags') return { value: {} };
    if (chave === 'globalConfig/get') return { value: { logoThumbnail: '' } };
    return { value: 'ltr' };
  },
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

    const [[, payload]] = chamadasDeSalvar();
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
    expect(chamadasDeSalvar()).toEqual([]);
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

    const [[, payload]] = chamadasDeSalvar();
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
    const campo = wrapper.find(
      'input[data-testid="selector-input-element_click"]'
    );

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
    const campo = wrapper.find(
      'input[data-testid="selector-input-element_click"]'
    );

    await campo.setValue('[data-cta], #orcamento .btn');
    await campo.trigger('blur');

    expect(
      wrapper.find('[data-testid="selector-field-element_click"]').text()
    ).not.toContain('não é válido');
  });

  it('vazio no blur também é erro — o gatilho não funcionaria', async () => {
    const wrapper = build();
    const campo = wrapper.find(
      'input[data-testid="selector-input-element_click"]'
    );

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

    const [[acao, payload]] = chamadasDeSalvar();
    expect(acao).toBe('inboxes/updateInbox');
    // `additionalProperties: false` — chave a mais derruba o PATCH inteiro
    expect(
      Object.keys(payload.additional_attributes.widget_triggers).sort()
    ).toEqual(['approach', 'degrade_on_return', 'enabled', 'triggers']);
    expect(payload.additional_attributes.widget_triggers.enabled).toBe(true);
  });

  it('a segmentação avisa que as regras são públicas', () => {
    // A segmentação é seção de marketing desde o bloco 3.07
    // (`PROFILE_SECTIONS['triggers.segmentation']`): no perfil suporte ela sai
    // da tela e no lugar fica o link de escape.
    inbox.additional_attributes = { widget_profile: 'marketing' };
    expect(build().find('[data-testid="public-warning"]').text()).toContain(
      'visíveis para quem inspecionar o código do site'
    );
  });

  it('tirar os dois dispositivos avisa que o convite some', async () => {
    // Idem: os dispositivos moram na segmentação (bloco 3.07).
    inbox.additional_attributes = { widget_profile: 'marketing' };
    const wrapper = build();

    await wrapper.find('[data-testid="device-desktop"]').setValue(false);
    await wrapper.find('[data-testid="device-mobile"]').setValue(false);

    expect(wrapper.find('[data-testid="device-empty"]').text()).toContain(
      'não aparece em lugar nenhum'
    );
  });
});

/**
 * Bloco 4.07 — o teaser no preview, com o gatilho SIMULADO.
 *
 * `WidgetTeaser.spec.js` monta o balão sozinho e passa. Ele não podia detectar
 * o defeito real: `Widget.vue` não declarava `teaser` nem `showTeaser` no
 * `defineProps`, então o Vue DESCARTAVA as duas props que esta tela passa e o
 * teaser nunca chegava ao DOM — com a suíte inteira verde. Por isso o teste
 * daqui monta a TELA de verdade (sem stub do preview), liga o interruptor e
 * exige o balão no DOM.
 */
describe('4.07 — o teaser no preview', () => {
  // A forma é a do schema REAL, não uma inventada para o teste: em
  // `WidgetAppearanceSchema`, `home_intents` é array de `{ id, label }` com
  // `required: [id, label]`, `additionalProperties: false`, `id` casando
  // `^[a-z][a-z0-9_]{0,31}$` e no máximo 4 itens. Um dublê com outro formato
  // deixaria o preview verde aqui e vazio no cliente.
  const comIntents = () => {
    inbox.additional_attributes = {
      widget_appearance: {
        home_intents: [
          { id: 'pricing', label: 'Preços' },
          { id: 'demo', label: 'Agendar demo' },
        ],
      },
    };
  };

  const simular = async wrapper => {
    await wrapper.find('[data-testid="simulate-trigger"]').trigger('click');
    await flushPromises();
  };

  it('é o interruptor que decide: desligado o teaser some, ligado ele volta', async () => {
    // Asserção negativa escrita para NÃO passar no vácuo. Só afirmar "sem
    // simular não há teaser" logo após montar passaria pelo motivo errado —
    // `teaserDoPreview` lê o composer por template ref, que ainda é `null` no
    // primeiro render, e o teste ficaria verde até com o `v-if` do interruptor
    // arrancado. Aqui o mesmo wrapper prova que o teaser EXISTE (ligado) e que
    // é o interruptor, e nada mais, que o tira do DOM.
    comIntents();
    const wrapper = build();
    await flushPromises();

    expect(wrapper.find('[data-testid="teaser-bold"]').exists()).toBe(false);

    await simular(wrapper);
    expect(wrapper.find('[data-testid="teaser-bold"]').exists()).toBe(true);

    await simular(wrapper);
    expect(wrapper.find('[data-testid="teaser-bold"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="teaser-discreet"]').exists()).toBe(
      false
    );
  });

  it('simular o gatilho mostra o teaser com texto, remetente, avatar e chips reais', async () => {
    comIntents();
    const wrapper = build();

    await simular(wrapper);

    const teaser = wrapper.find('[data-testid="teaser-bold"]');
    expect(teaser.exists()).toBe(true);

    // o texto é o da campanha vinculada (4.05), não um exemplo inventado
    expect(teaser.find('[data-testid="teaser-text"]').text()).toBe(
      'Posso ajudar?'
    );
    // sem remetente na campanha, o nome da inbox — como no site do visitante
    expect(teaser.find('[data-testid="teaser-sender"]').text()).toBe(
      'Site da Simplex'
    );
    expect(teaser.find('[data-testid="teaser-avatar"]').exists()).toBe(true);

    // os chips são os `home_intents` da aparência, as MESMAS opções que o
    // visitante vê — não há um segundo campo de chips
    const chips = teaser.find('[data-testid="teaser-chips"]');
    expect(chips.text()).toContain('Preços');
    expect(chips.text()).toContain('Agendar demo');
  });

  it('o preview segue a abordagem escolhida: Discreto tira foto e chips', async () => {
    comIntents();
    const wrapper = build();

    await wrapper
      .find('[data-testid="approach-discreet"] input')
      .trigger('change');
    await simular(wrapper);

    expect(wrapper.find('[data-testid="teaser-discreet"]').exists()).toBe(true);
    expect(wrapper.find('[data-testid="teaser-bold"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="teaser-chips"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="teaser-avatar"]').exists()).toBe(false);
  });

  it('o preview não descarta em silêncio nenhuma prop que a tela lhe passa', async () => {
    // A asserção que faltava. O Vue não QUEBRA quando uma prop não está
    // declarada: ele avisa no console e segue com `undefined`. Era esse aviso
    // — 60 vezes nesta suíte — que a tela verde vinha imprimindo.
    const avisos = [];
    const espia = vi.spyOn(console, 'warn').mockImplementation((...args) => {
      avisos.push(args.join(' '));
    });

    comIntents();
    await simular(build());
    espia.mockRestore();

    expect(
      avisos.filter(aviso =>
        aviso.includes('was accessed during render but is not defined')
      )
    ).toEqual([]);
  });
});
