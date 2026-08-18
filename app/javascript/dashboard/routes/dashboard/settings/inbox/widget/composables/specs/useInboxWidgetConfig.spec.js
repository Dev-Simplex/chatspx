import { reactive, nextTick } from 'vue';
import {
  useInboxWidgetConfig,
  buildPayload,
  diffFields,
} from '../useInboxWidgetConfig';

const inboxFixture = () => ({
  id: 7,
  name: 'Site da Simplex',
  widget_color: '#009ce0',
  welcome_title: 'Ola',
  welcome_tagline: 'Fale com a gente',
  reply_time: 'in_a_few_minutes',
  selected_feature_flags: ['attachments', 'emoji_picker'],
  additional_attributes: {
    widget_profile: 'marketing',
    widget_appearance: { position: 'right', offset_x: 20 },
    // uma chave de OUTRA feature, para provar que o PATCH nao a leva junto
    pin_mode: 'manual',
  },
});

let storeState;
let dispatch;
let store;

vi.mock('dashboard/composables/store', () => ({
  useStore: () => store,
}));

beforeEach(() => {
  storeState = reactive({ inbox: inboxFixture(), uiFlags: {} });
  dispatch = vi.fn().mockResolvedValue();
  store = {
    getters: {
      'inboxes/getInbox': () => storeState.inbox,
      get 'inboxes/getUIFlags'() {
        return storeState.uiFlags;
      },
    },
    dispatch,
  };
});

describe('useInboxWidgetConfig', () => {
  it('lê o gravado e nasce limpo', () => {
    const { draft, isDirty, dirtyCount } = useInboxWidgetConfig(7);

    expect(draft.value.name).toBe('Site da Simplex');
    expect(draft.value.profile).toBe('marketing');
    // o que o banco nao tem vem do default de fabrica DO SERVIDOR, nao de
    // `undefined` e nao de uma segunda opiniao da tela
    expect(draft.value.appearance.theme).toBe('light');
    expect(draft.value.appearance.position).toBe('right');
    expect(isDirty.value).toBe(false);
    expect(dirtyCount.value).toBe(0);
  });

  it('inbox sem as chaves novas é lida como support + defaults, sem migration', () => {
    storeState.inbox = { id: 7, name: 'Antiga', additional_attributes: {} };
    const { draft, isDirty } = useInboxWidgetConfig(7);

    expect(draft.value.profile).toBe('support');
    expect(draft.value.appearance).toEqual({
      theme: 'light',
      position: 'right',
      offset_x: 0,
      offset_y: 0,
      launcher_type: 'standard',
      launcher_text: '',
      hide_bubble: false,
      panel_style: 'standard',
      launcher_icon: 'default',
      home_intents: [],
    });
    expect(draft.value.triggers.approach).toBe('bold');
    expect(isDirty.value).toBe(false);
  });

  it('editar NÃO suja o objeto do store (D2)', () => {
    const { setIn, set } = useInboxWidgetConfig(7);

    setIn('appearance', 'position', 'left');
    set('name', 'Outro nome');

    expect(storeState.inbox.name).toBe('Site da Simplex');
    expect(storeState.inbox.additional_attributes.widget_appearance).toEqual({
      position: 'right',
      offset_x: 20,
    });
    expect(dispatch).not.toHaveBeenCalled();
  });

  it('conta e NOMEIA cada alteração pendente, subcampo a subcampo', () => {
    const { setIn, set, dirtyCount, dirtyFields } = useInboxWidgetConfig(7);

    setIn('appearance', 'position', 'left');
    expect(dirtyCount.value).toBe(1);
    expect(dirtyFields.value).toEqual(['appearance.position']);

    setIn('appearance', 'offset_y', 40);
    set('widgetColor', '#2dc46f');
    expect(dirtyCount.value).toBe(3);
    expect(dirtyFields.value).toEqual([
      'widgetColor',
      'appearance.position',
      'appearance.offset_y',
    ]);
  });

  it('voltar o valor original zera a pendência', () => {
    const { setIn, isDirty } = useInboxWidgetConfig(7);

    setIn('appearance', 'position', 'left');
    expect(isDirty.value).toBe(true);

    setIn('appearance', 'position', 'right');
    expect(isDirty.value).toBe(false);
  });

  it('Descartar restaura o gravado', () => {
    const { setIn, set, discard, draft, isDirty } = useInboxWidgetConfig(7);

    setIn('appearance', 'position', 'left');
    set('welcomeTitle', 'Rascunho perdido');

    discard();

    expect(draft.value.appearance.position).toBe('right');
    expect(draft.value.welcomeTitle).toBe('Ola');
    expect(isDirty.value).toBe(false);
  });

  it('salva o mínimo que mudou, com o grupo inteiro e formData: false', async () => {
    const { setIn, save } = useInboxWidgetConfig(7);

    setIn('appearance', 'position', 'left');
    const result = await save();

    expect(dispatch).toHaveBeenCalledTimes(1);
    expect(dispatch).toHaveBeenCalledWith('inboxes/updateInbox', {
      id: 7,
      formData: false,
      additional_attributes: {
        widget_appearance: {
          theme: 'light',
          position: 'left',
          offset_x: 20,
          offset_y: 0,
          launcher_type: 'standard',
          launcher_text: '',
          hide_bubble: false,
          panel_style: 'standard',
          launcher_icon: 'default',
          home_intents: [],
        },
      },
    });
    expect(result.saved).toBe(true);
  });

  it('depois de salvar, a barra some (nada mais pendente)', async () => {
    const { setIn, save, isDirty, dirtyCount } = useInboxWidgetConfig(7);

    setIn('appearance', 'position', 'left');
    await save();

    expect(isDirty.value).toBe(false);
    expect(dirtyCount.value).toBe(0);
  });

  it('salvar sem alteração não chama a API', async () => {
    const { save } = useInboxWidgetConfig(7);

    const result = await save();

    expect(dispatch).not.toHaveBeenCalled();
    expect(result).toEqual({ saved: false, payload: null });
  });

  it('erro de gravação vira mensagem persistente e propaga', async () => {
    dispatch.mockRejectedValue(new Error('422: position inválida'));
    const { setIn, save, saveError, isDirty } = useInboxWidgetConfig(7);

    setIn('appearance', 'position', 'left');

    await expect(save()).rejects.toThrow('422: position inválida');
    expect(saveError.value).toBe('422: position inválida');
    // o rascunho continua de pé: o administrador nao perde o que digitou
    expect(isDirty.value).toBe(true);
  });

  it('atualização vinda do store não apaga rascunho pendente', async () => {
    const { setIn, draft, dirtyCount } = useInboxWidgetConfig(7);

    setIn('appearance', 'position', 'left');
    storeState.inbox = { ...inboxFixture(), name: 'Renomeada por outro admin' };
    await nextTick();

    expect(draft.value.appearance.position).toBe('left');
    // o campo que ELE nao estava editando passa a divergir do gravado
    expect(dirtyCount.value).toBe(2);
  });

  it('atualização vinda do store entra quando não há pendência', async () => {
    const { draft } = useInboxWidgetConfig(7);

    storeState.inbox = { ...inboxFixture(), name: 'Renomeada por outro admin' };
    await nextTick();

    expect(draft.value.name).toBe('Renomeada por outro admin');
  });

  it('recusa campo desconhecido em vez de gravar lixo', () => {
    const { set } = useInboxWidgetConfig(7);

    expect(() => set('naoExiste', 1)).toThrow(/campo desconhecido/);
  });
});

describe('buildPayload', () => {
  const saved = {
    name: 'A',
    widgetColor: '#009ce0',
    profile: 'support',
    appearance: { position: 'right', theme: 'auto' },
  };

  it('não manda nada do que não mudou', () => {
    expect(buildPayload(saved, { ...saved })).toEqual({});
  });

  it('separa raiz, canal e additional_attributes', () => {
    const draft = {
      ...saved,
      name: 'B',
      widgetColor: '#2dc46f',
      profile: 'marketing',
    };

    expect(buildPayload(saved, draft)).toEqual({
      name: 'B',
      channel: { widget_color: '#2dc46f' },
      additional_attributes: { widget_profile: 'marketing' },
    });
  });

  it('manda o grupo INTEIRO — o merge do servidor é raso', () => {
    const draft = { ...saved, appearance: { position: 'left', theme: 'auto' } };

    expect(buildPayload(saved, draft).additional_attributes).toEqual({
      widget_appearance: { position: 'left', theme: 'auto' },
    });
  });
});

describe('diffFields', () => {
  it('trata array como valor, não como objeto de chaves', () => {
    const saved = { featureFlags: ['emoji_picker'] };
    expect(diffFields(saved, { featureFlags: ['emoji_picker'] })).toEqual([]);
    expect(diffFields(saved, { featureFlags: [] })).toEqual(['featureFlags']);
  });
});
