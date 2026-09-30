import { mount, flushPromises } from '@vue/test-utils';
import { ref, defineComponent, h } from 'vue';
import WhatsAppCampaignForm from '../WhatsAppCampaignForm.vue';

const TEMPLATE = {
  id: 'tpl-1',
  name: 'aniversario_v2',
  language: 'pt_BR',
  category: 'MARKETING',
  namespace: '',
};

vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: getter => {
    const values = {
      'campaigns/getUIFlags': { isCreating: false },
      'labels/getLabels': [{ id: 1, title: 'vip' }],
      'inboxes/getWhatsAppInboxes': [{ id: 7, name: 'Loja', read_only: false }],
      'inboxes/getFilteredWhatsAppTemplates': () => [TEMPLATE],
    };
    return ref(values[getter]);
  },
}));

// Stubs sem props: o v-model do formulário chega como listener `onUpdate:modelValue`, e o
// teste o aciona emitindo o evento, como o componente real faria.
const ComboBoxStub = defineComponent({
  name: 'ComboBoxStub',
  render: () => h('div'),
});

const InputStub = defineComponent({
  name: 'InputStub',
  props: { label: { type: String, default: '' } },
  setup: props => () => h('label', props.label),
});

// O parser real monta o corpo a partir do template; aqui basta o que o formulário lê dele.
const ParserStub = defineComponent({
  name: 'WhatsAppTemplateParser',
  setup: () => ({
    renderedTemplate: 'Olá, feliz aniversário',
    processedParams: {},
    v$: { $invalid: false },
  }),
  render: () => h('div'),
});

const montar = () =>
  mount(WhatsAppCampaignForm, {
    global: {
      stubs: {
        ComboBox: ComboBoxStub,
        Input: InputStub,
        WhatsAppTemplateParser: ParserStub,
        TagMultiSelectComboBox: true,
        Button: true,
      },
    },
  });

const preencher = async wrapper => {
  const [titulo] = wrapper.findAllComponents(InputStub);
  titulo.vm.$emit('update:modelValue', 'Aniversário');
  const [inbox] = wrapper.findAllComponents(ComboBoxStub);
  inbox.vm.$emit('update:modelValue', 7);
  await flushPromises();
  const [, template] = wrapper.findAllComponents(ComboBoxStub);
  template.vm.$emit('update:modelValue', TEMPLATE.id);
  await flushPromises();
};

describe('WhatsAppCampaignForm', () => {
  // Quem recebe o disparo vem da lista ou do segmento carregados no detalhe; a etiqueta
  // escolhida aqui era ignorada pelo motor e fazia o operador achar que escolheu o público.
  it('não oferece público por etiqueta', () => {
    const wrapper = montar();

    expect(wrapper.text()).not.toContain(
      'CAMPAIGN.WHATSAPP.CREATE.FORM.AUDIENCE.LABEL'
    );
    expect(
      wrapper.findComponent({ name: 'TagMultiSelectComboBox' }).exists()
    ).toBe(false);
  });

  it('cria sem etiqueta e sem horário, mandando o template escolhido', async () => {
    const wrapper = montar();
    await preencher(wrapper);

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    const [[payload]] = wrapper.emitted('submit');
    expect(payload).not.toHaveProperty('audience');
    expect(payload.scheduled_at).toBeNull();
    expect(payload.inbox_id).toBe(7);
    expect(payload.template_params).toMatchObject({
      name: 'aniversario_v2',
      language: 'pt_BR',
    });
  });

  it('manda o horário quando o operador agenda', async () => {
    const wrapper = montar();
    await preencher(wrapper);
    const agendamento = wrapper.findAllComponents(InputStub).at(-1);
    agendamento.vm.$emit('update:modelValue', '2030-01-10T09:00');

    await wrapper.find('form').trigger('submit');
    await flushPromises();

    const [[payload]] = wrapper.emitted('submit');
    expect(payload.scheduled_at).toBe(
      new Date('2030-01-10T09:00').toISOString()
    );
  });
});
