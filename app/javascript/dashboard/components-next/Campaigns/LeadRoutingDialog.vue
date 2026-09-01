<script setup>
/**
 * Edita o roteamento de UMA campanha de captação: template da abertura, os campos do lead
 * que preenchem as variáveis dele, agente e time.
 *
 * A validação é o motivo deste diálogo existir. Configurar a abertura à mão é o caminho
 * curto para o erro #132000 da Meta — um parâmetro a mais ou a menos e a mensagem não sai,
 * o lead entra mudo e ninguém percebe. Por isso a QUANTIDADE de campos não se digita: ela é
 * derivada do template escolhido, e o formulário mostra um seletor por variável do corpo.
 * O servidor valida de novo, sobre a configuração RESULTANTE (override + padrão do hook).
 *
 * Campo em branco = herdar o padrão da integração, e a dica embaixo diz qual é esse padrão.
 */
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';

import LeadCampaignsAPI from 'dashboard/api/leadCampaigns';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Select from 'dashboard/components-next/select/Select.vue';

const props = defineProps({
  campanha: { type: Object, required: true },
  hook: { type: Object, default: null },
});

const emit = defineEmits(['salvo']);

defineOptions({ name: 'LeadRoutingDialog' });

const { t } = useI18n();

// Vazio significa "herda o padrão da integração" em todo o formulário — inclusive no que
// vai para a API, onde apagar a chave do override é o que devolve a campanha ao padrão.
const HERDAR = '';
const SEPARADOR = ' · ';
const SEM_VARIAVEL = 'none';

// Chaves escritas por extenso, e não montadas: é o que deixa o conjunto rastreável pelo
// lint de i18n e garante que a lista do backend e a tradução andem juntas.
const MOTIVO_I18N = {
  cabecalho_de_midia: 'CAMPAIGN.LEAD_ADS.EDIT.BLOCKED.cabecalho_de_midia',
  cabecalho_com_variavel:
    'CAMPAIGN.LEAD_ADS.EDIT.BLOCKED.cabecalho_com_variavel',
  botao_com_variavel: 'CAMPAIGN.LEAD_ADS.EDIT.BLOCKED.botao_com_variavel',
  parametro_nomeado: 'CAMPAIGN.LEAD_ADS.EDIT.BLOCKED.parametro_nomeado',
};

const CAMPO_I18N = {
  first_name: 'CAMPAIGN.LEAD_ADS.EDIT.FIELDS.first_name',
  full_name: 'CAMPAIGN.LEAD_ADS.EDIT.FIELDS.full_name',
  ad_name: 'CAMPAIGN.LEAD_ADS.EDIT.FIELDS.ad_name',
  campaign_name: 'CAMPAIGN.LEAD_ADS.EDIT.FIELDS.campaign_name',
  city: 'CAMPAIGN.LEAD_ADS.EDIT.FIELDS.city',
  email: 'CAMPAIGN.LEAD_ADS.EDIT.FIELDS.email',
  phone: 'CAMPAIGN.LEAD_ADS.EDIT.FIELDS.phone',
  empreendimento: 'CAMPAIGN.LEAD_ADS.EDIT.FIELDS.empreendimento',
};

const dialogRef = ref(null);
const salvando = ref(false);
const erros = ref([]);

const template = ref(HERDAR);
const templateLocale = ref(HERDAR);
const campos = ref([]);
const agente = ref(HERDAR);
const time = ref(HERDAR);

const opcoes = computed(() => props.hook?.opcoes || {});
const templates = computed(() => opcoes.value.templates || []);
const camposDoLead = computed(() => opcoes.value.campos || []);
const templateEditavel = computed(
  () => opcoes.value.template_editavel === true
);

const sobrescreve = chave =>
  (props.campanha.sobrescritos || []).includes(chave);

const camposConfigurados = valor => {
  const bruto = String(valor || '').trim();
  if (!bruto || bruto.toLowerCase() === SEM_VARIAVEL) return [];
  return bruto
    .split(',')
    .map(campo => campo.trim())
    .filter(Boolean);
};

// A linha da tabela mostra o valor EFETIVO (com a herança já aplicada). O formulário
// precisa do contrário: só o que ESTA campanha sobrescreve, para "em branco" continuar
// significando "herda" em vez de congelar o padrão de hoje dentro do override.
const preencher = () => {
  erros.value = [];
  template.value = sobrescreve('whatsapp_template_name')
    ? props.campanha.template || HERDAR
    : HERDAR;
  templateLocale.value = sobrescreve('whatsapp_template_locale')
    ? props.campanha.template_locale || HERDAR
    : HERDAR;
  campos.value = sobrescreve('whatsapp_template_body_fields')
    ? camposConfigurados(props.campanha.template_campos)
    : [];
  agente.value = sobrescreve('assign_agent_bot_id')
    ? props.campanha.agente?.id || HERDAR
    : HERDAR;
  time.value = sobrescreve('assign_team_id')
    ? props.campanha.time?.id || HERDAR
    : HERDAR;
};

// Nome e idioma viajam juntos numa chave só: a Meta trata o par como templates diferentes,
// então escolher "o template X" sem dizer o idioma não é uma escolha completa.
const chaveDoTemplate = descritor => `${descritor.nome}|${descritor.idioma}`;

const selecionado = computed(() =>
  templates.value.find(
    descritor =>
      descritor.nome === template.value &&
      (!templateLocale.value || descritor.idioma === templateLocale.value)
  )
);

const variaveis = computed(() => selecionado.value?.variaveis || []);

const bloqueados = computed(() =>
  templates.value.filter(descritor => descritor.impedimento)
);

const motivo = descritor =>
  t(
    MOTIVO_I18N[descritor.impedimento] ||
      'CAMPAIGN.LEAD_ADS.EDIT.BLOCKED.generico'
  );

const rotuloBloqueado = descritor =>
  `${descritor.nome} (${descritor.idioma})${SEPARADOR}${motivo(descritor)}`;

const opcoesDeTemplate = computed(() => [
  { value: HERDAR, label: t('CAMPAIGN.LEAD_ADS.EDIT.INHERIT') },
  ...templates.value.map(descritor => ({
    value: chaveDoTemplate(descritor),
    label: `${descritor.nome} (${descritor.idioma})${SEPARADOR}${t(
      'CAMPAIGN.LEAD_ADS.EDIT.VARIABLE_COUNT',
      { total: descritor.variaveis.length }
    )}`,
    disabled: Boolean(descritor.impedimento),
  })),
]);

const templateSelecionado = computed({
  get: () => (selecionado.value ? chaveDoTemplate(selecionado.value) : HERDAR),
  set: valor => {
    const [nome, idioma] = String(valor).split('|');
    template.value = nome || HERDAR;
    templateLocale.value = idioma || HERDAR;
  },
});

// Trocar de template redimensiona o formulário: uma escolha por variável do template novo,
// preservando o que já estava nas posições que sobreviveram. É isto que torna impossível
// montar aqui uma combinação com a contagem errada.
watch(selecionado, descritor => {
  if (!descritor) {
    campos.value = [];
    return;
  }
  const anterior = campos.value;
  campos.value = Array.from(
    { length: descritor.variaveis.length },
    (_, indice) => anterior[indice] || camposDoLead.value[0] || ''
  );
});

// Campo que o backend passe a oferecer sem tradução aqui aparece pelo nome cru, e não em
// branco: melhor um rótulo feio do que um seletor com opções vazias.
const opcoesDeCampo = computed(() =>
  camposDoLead.value.map(campo => ({
    value: campo,
    label: CAMPO_I18N[campo] ? t(CAMPO_I18N[campo]) : campo,
  }))
);

const opcoesDeAgente = computed(() => [
  { value: HERDAR, label: t('CAMPAIGN.LEAD_ADS.EDIT.INHERIT') },
  ...(opcoes.value.agentes || []).map(item => ({
    value: item.id,
    label: item.elegivel
      ? item.nome
      : `${item.nome}${SEPARADOR}${t('CAMPAIGN.LEAD_ADS.EDIT.AGENT_NOT_ELIGIBLE')}`,
    disabled: !item.elegivel,
  })),
]);

const opcoesDeTime = computed(() => [
  { value: HERDAR, label: t('CAMPAIGN.LEAD_ADS.EDIT.INHERIT') },
  ...(opcoes.value.times || []).map(item => ({
    value: item.id,
    label: item.nome,
  })),
]);

const padrao = valor =>
  valor
    ? t('CAMPAIGN.LEAD_ADS.EDIT.HOOK_DEFAULT', { valor })
    : t('CAMPAIGN.LEAD_ADS.EDIT.HOOK_DEFAULT_EMPTY');

const padraoDoTemplate = computed(() => padrao(props.hook?.template));
const padraoDoAgente = computed(() => padrao(props.hook?.agente?.nome));
const padraoDoTime = computed(() => padrao(props.hook?.time?.nome));

const erroDe = campo =>
  erros.value.find(item => item.campo === campo)?.mensagem;

const autoria = computed(() => {
  const quem = props.campanha.atualizado_por;
  const quando = props.campanha.atualizado_em;
  if (!quem && !quando) return '';
  const data = quando ? new Date(quando).toLocaleString() : '';
  return quem
    ? t('CAMPAIGN.LEAD_ADS.EDIT.LAST_CHANGE', { quem, quando: data })
    : t('CAMPAIGN.LEAD_ADS.EDIT.LAST_CHANGE_ANON', { quando: data });
});

const salvar = async () => {
  salvando.value = true;
  erros.value = [];
  try {
    const { data } = await LeadCampaignsAPI.atualizarRoteamento(
      props.campanha.campaign_id,
      {
        template: template.value,
        template_locale: templateLocale.value,
        campos: campos.value,
        agente: agente.value,
        time: time.value,
      }
    );
    emit('salvo', data.campanha);
    dialogRef.value?.close();
  } catch (error) {
    const devolvidos = error?.response?.data?.erros;
    erros.value =
      Array.isArray(devolvidos) && devolvidos.length
        ? devolvidos
        : [
            {
              campo: 'geral',
              mensagem: t('CAMPAIGN.LEAD_ADS.EDIT.SAVE_ERROR'),
            },
          ];
  } finally {
    salvando.value = false;
  }
};

const open = () => {
  preencher();
  dialogRef.value?.open();
};

defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="2xl"
    overflow-y-auto
    :title="t('CAMPAIGN.LEAD_ADS.EDIT.TITLE')"
    :description="campanha.nome || campanha.campaign_id"
    :confirm-button-label="t('CAMPAIGN.LEAD_ADS.EDIT.SAVE')"
    :is-loading="salvando"
    @confirm="salvar"
  >
    <div class="flex flex-col gap-5">
      <p
        v-if="!templateEditavel"
        class="px-3 py-2 text-sm rounded-lg bg-n-amber-3 text-n-amber-11"
      >
        {{ t('CAMPAIGN.LEAD_ADS.EDIT.NO_TEMPLATE_CHANNEL') }}
      </p>

      <div v-if="templateEditavel" class="flex flex-col gap-2 min-w-0">
        <label class="text-sm font-medium text-n-slate-12">
          {{ t('CAMPAIGN.LEAD_ADS.EDIT.TEMPLATE') }}
        </label>
        <Select
          v-model="templateSelecionado"
          class="max-w-full"
          :options="opcoesDeTemplate"
          :error="erroDe('template')"
        />
        <p class="text-xs text-n-slate-10">{{ padraoDoTemplate }}</p>
        <p v-if="erroDe('template')" class="text-xs text-n-ruby-11">
          {{ erroDe('template') }}
        </p>
        <div v-if="bloqueados.length" class="flex flex-col gap-0.5">
          <p class="text-xs text-n-slate-10">
            {{ t('CAMPAIGN.LEAD_ADS.EDIT.BLOCKED_TITLE') }}
          </p>
          <p
            v-for="descritor in bloqueados"
            :key="`${descritor.nome}-${descritor.idioma}`"
            class="text-xs text-n-slate-10"
          >
            {{ rotuloBloqueado(descritor) }}
          </p>
        </div>
      </div>

      <div
        v-if="selecionado"
        class="flex flex-col gap-3 p-3 border rounded-lg border-n-weak bg-n-alpha-1"
      >
        <p class="text-xs whitespace-pre-line text-n-slate-11">
          {{ selecionado.corpo }}
        </p>
        <p v-if="!variaveis.length" class="text-xs text-n-slate-10">
          {{ t('CAMPAIGN.LEAD_ADS.EDIT.NO_VARIABLES') }}
        </p>
        <div
          v-for="(variavel, indice) in variaveis"
          :key="variavel"
          class="flex flex-wrap items-center gap-2"
        >
          <span class="w-28 text-xs text-n-slate-11">
            {{ t('CAMPAIGN.LEAD_ADS.EDIT.VARIABLE', { numero: variavel }) }}
          </span>
          <Select v-model="campos[indice]" :options="opcoesDeCampo" />
        </div>
        <p v-if="erroDe('campos')" class="text-xs text-n-ruby-11">
          {{ erroDe('campos') }}
        </p>
      </div>

      <div class="flex flex-wrap gap-5">
        <div class="flex flex-col gap-2">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.LEAD_ADS.EDIT.AGENT') }}
          </label>
          <Select
            v-model="agente"
            :options="opcoesDeAgente"
            :error="erroDe('agente')"
          />
          <p class="text-xs text-n-slate-10">{{ padraoDoAgente }}</p>
          <p v-if="erroDe('agente')" class="text-xs text-n-ruby-11">
            {{ erroDe('agente') }}
          </p>
        </div>
        <div class="flex flex-col gap-2">
          <label class="text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.LEAD_ADS.EDIT.TEAM') }}
          </label>
          <Select
            v-model="time"
            :options="opcoesDeTime"
            :error="erroDe('time')"
          />
          <p class="text-xs text-n-slate-10">{{ padraoDoTime }}</p>
          <p v-if="erroDe('time')" class="text-xs text-n-ruby-11">
            {{ erroDe('time') }}
          </p>
        </div>
      </div>

      <p v-if="erroDe('geral')" class="text-sm text-n-ruby-11">
        {{ erroDe('geral') }}
      </p>
      <p v-if="erroDe('campanha')" class="text-sm text-n-ruby-11">
        {{ erroDe('campanha') }}
      </p>
      <p v-if="autoria" class="text-xs text-n-slate-10">{{ autoria }}</p>
    </div>
  </Dialog>
</template>
