<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import CampaignsAPI from 'dashboard/api/campaigns';
import { useAlert } from 'dashboard/composables';

// A configuracao do MOTOR, que ate aqui so existia no console. O formulario de criacao
// coleta titulo, inbox, template e data; quem manda no disparo em si — o time que recebe
// as conversas, o ritmo, a janela de silencio, o freio por saude do numero — ficava de
// fora e valia o default. O caso que doi mais e o time: sem ele a conversa nasce com
// team_id nulo e a resposta do lead cai sem dono.

const props = defineProps({
  campaignId: { type: [String, Number], required: true },
  campaign: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['changed', 'dirty']);

const { t } = useI18n();

const teams = useMapGetter('teams/getTeams');
const agents = useMapGetter('agents/getAgents');

const saving = ref(false);
const carregado = ref(false);
// Fotografia do que veio do servidor. É o que distingue "o operador não mexeu" de
// "mexeu e não salvou" — sem isso as duas situações são indistinguíveis, e o formulário
// se apaga sozinho no meio da digitação.
const baseline = ref('');
const state = ref({
  targetTeamId: null,
  dispatchAssigneeId: null,
  pacingSeconds: 5,
  quietStart: null,
  quietEnd: null,
  healthGate: true,
});

// A janela de silencio e por HORA CHEIA (o motor compara Time.current.hour), entao
// 16:30 nao e expressavel — dizer isso na tela evita o pedido que nao se cumpre.
const HORAS = Array.from({ length: 24 }, (_, h) => ({
  value: h,
  label: `${String(h).padStart(2, '0')}:00`,
}));

const fotografia = valor => JSON.stringify(valor);

const carregar = campanha => {
  const config = campanha?.dispatch_config || {};
  const quiet = config.quiet_hours || {};
  state.value = {
    targetTeamId: campanha?.target_team_id ?? null,
    dispatchAssigneeId: campanha?.dispatch_assignee_id ?? null,
    pacingSeconds: campanha?.pacing_seconds ?? 5,
    quietStart: quiet.start ?? null,
    quietEnd: quiet.end ?? null,
    // Ausente significa LIGADO: o freio de saude e o padrao seguro, e so sai dele quem
    // desmarca de proposito.
    healthGate: config.health_gate !== false,
  };
  baseline.value = fotografia(state.value);
  carregado.value = true;
};

// Há alteração digitada e não salva.
const sujo = computed(
  () => carregado.value && fotografia(state.value) !== baseline.value
);

// O detalhe faz polling a cada 10s enquanto o disparo corre, e cada tick substitui o
// objeto `campaign`. Recarregar cegamente aqui APAGAVA o que o operador estava digitando,
// em silêncio e em menos de dez segundos — e a janela de silêncio é justo o campo que já
// quase fez uma campanha sair no horário errado. Recarrega quando não há edição pendente,
// ou quando o formulário passou a ser de outra campanha.
watch(
  () => props.campaign,
  (nova, anterior) => {
    const outraCampanha = nova?.display_id !== anterior?.display_id;
    if (!carregado.value || outraCampanha || !sujo.value) carregar(nova);
  },
  { immediate: true, deep: true }
);

// O painel de disparo precisa saber, porque iniciar com a configuração antiga é o erro
// que esta tela não pode deixar acontecer calado.
watch(sujo, valor => emit('dirty', valor));

// Janela so vale com as duas pontas: uma ponta so silenciaria pra sempre ou nunca.
const janelaIncompleta = computed(() => {
  const { quietStart: inicio, quietEnd: fim } = state.value;
  return (inicio === null) !== (fim === null);
});

const semTime = computed(() => !state.value.targetTeamId);

// `min`/`max` num input fora de um <form> não são aplicados por ninguém, e `Number('')`
// é 0: campo limpo gravaria pacing 0 no motor enquanto a dica ao lado anuncia
// "60 mensagens por minuto". Recusar é melhor que adivinhar um valor que ninguém pediu.
const PACING_MIN = 1;
const PACING_MAX = 60;
const pacingInvalido = computed(() => {
  const valor = Number(state.value.pacingSeconds);
  return (
    String(state.value.pacingSeconds).trim() === '' ||
    !Number.isFinite(valor) ||
    valor < PACING_MIN ||
    valor > PACING_MAX
  );
});

const naoPodeSalvar = computed(
  () =>
    saving.value ||
    janelaIncompleta.value ||
    pacingInvalido.value ||
    !sujo.value
);

const salvar = async () => {
  if (janelaIncompleta.value || pacingInvalido.value) return;
  saving.value = true;
  try {
    const quietHours =
      state.value.quietStart === null
        ? {}
        : {
            quiet_hours: {
              start: Number(state.value.quietStart),
              end: Number(state.value.quietEnd),
            },
          };
    await CampaignsAPI.update(props.campaignId, {
      campaign: {
        target_team_id: state.value.targetTeamId,
        dispatch_assignee_id: state.value.dispatchAssigneeId,
        pacing_seconds: Number(state.value.pacingSeconds),
        dispatch_config: {
          ...(props.campaign?.dispatch_config || {}),
          ...quietHours,
          health_gate: state.value.healthGate,
        },
      },
    });
    // A fotografia passa a ser o que acabou de ir pro servidor: sem isto o formulário
    // continuaria "sujo" depois de salvar, e o recarregamento do poll voltaria a ser
    // bloqueado para sempre.
    baseline.value = fotografia(state.value);
    useAlert(t('CAMPAIGN.WHATSAPP.SETTINGS.SAVED'));
    emit('changed');
  } catch (error) {
    useAlert(
      error?.response?.data?.error || t('CAMPAIGN.WHATSAPP.SETTINGS.ERROR')
    );
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <div class="p-4 border rounded-xl border-n-weak bg-n-solid-2">
    <h2 class="mb-4 text-sm font-medium text-n-slate-12">
      {{ t('CAMPAIGN.WHATSAPP.SETTINGS.TITLE') }}
    </h2>

    <div class="grid gap-4 sm:grid-cols-2">
      <label class="text-sm">
        <span class="block mb-1 text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.SETTINGS.TEAM') }}
        </span>
        <select
          v-model="state.targetTeamId"
          class="w-full text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option :value="null">
            {{ t('CAMPAIGN.WHATSAPP.SETTINGS.TEAM_NONE') }}
          </option>
          <option v-for="team in teams" :key="team.id" :value="team.id">
            {{ team.name }}
          </option>
        </select>
        <span v-if="semTime" class="block mt-1 text-xs text-n-amber-11">
          {{ t('CAMPAIGN.WHATSAPP.SETTINGS.TEAM_WARNING') }}
        </span>
      </label>

      <label class="text-sm">
        <span class="block mb-1 text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.SETTINGS.ASSIGNEE') }}
        </span>
        <select
          v-model="state.dispatchAssigneeId"
          class="w-full text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
        >
          <option :value="null">
            {{ t('CAMPAIGN.WHATSAPP.SETTINGS.ASSIGNEE_NONE') }}
          </option>
          <option v-for="agent in agents" :key="agent.id" :value="agent.id">
            {{ agent.name }}
          </option>
        </select>
        <span class="block mt-1 text-xs text-n-slate-10">
          {{ t('CAMPAIGN.WHATSAPP.SETTINGS.ASSIGNEE_HINT') }}
        </span>
      </label>

      <label class="text-sm">
        <span class="block mb-1 text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.SETTINGS.PACING') }}
        </span>
        <input
          v-model="state.pacingSeconds"
          type="number"
          min="1"
          max="60"
          class="w-full text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
        />
        <span
          class="block mt-1 text-xs"
          :class="pacingInvalido ? 'text-n-ruby-11' : 'text-n-slate-10'"
        >
          {{
            pacingInvalido
              ? t('CAMPAIGN.WHATSAPP.SETTINGS.PACING_INVALID')
              : t('CAMPAIGN.WHATSAPP.SETTINGS.PACING_HINT', {
                  rate: Math.floor(60 / Math.max(state.pacingSeconds, 1)),
                })
          }}
        </span>
      </label>

      <div class="text-sm">
        <span class="block mb-1 text-n-slate-11">
          {{ t('CAMPAIGN.WHATSAPP.SETTINGS.QUIET') }}
        </span>
        <div class="flex items-center gap-2">
          <select
            v-model="state.quietStart"
            class="flex-1 text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option :value="null">—</option>
            <option
              v-for="hora in HORAS"
              :key="`s${hora.value}`"
              :value="hora.value"
            >
              {{ hora.label }}
            </option>
          </select>
          <span class="text-n-slate-10">{{
            t('CAMPAIGN.WHATSAPP.SETTINGS.QUIET_TO')
          }}</span>
          <select
            v-model="state.quietEnd"
            class="flex-1 text-sm rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          >
            <option :value="null">—</option>
            <option
              v-for="hora in HORAS"
              :key="`e${hora.value}`"
              :value="hora.value"
            >
              {{ hora.label }}
            </option>
          </select>
        </div>
        <span
          class="block mt-1 text-xs"
          :class="janelaIncompleta ? 'text-n-ruby-11' : 'text-n-slate-10'"
        >
          {{
            janelaIncompleta
              ? t('CAMPAIGN.WHATSAPP.SETTINGS.QUIET_INCOMPLETE')
              : t('CAMPAIGN.WHATSAPP.SETTINGS.QUIET_HINT')
          }}
        </span>
      </div>
    </div>

    <label class="flex items-start gap-2 mt-4 text-sm cursor-pointer">
      <input v-model="state.healthGate" type="checkbox" class="mt-0.5" />
      <span>
        <span class="text-n-slate-12">{{
          t('CAMPAIGN.WHATSAPP.SETTINGS.HEALTH')
        }}</span>
        <span class="block text-xs text-n-slate-10">
          {{ t('CAMPAIGN.WHATSAPP.SETTINGS.HEALTH_HINT') }}
        </span>
      </span>
    </label>

    <div class="flex flex-wrap items-center gap-3 mt-4">
      <button
        class="px-3 py-1.5 text-sm rounded-lg bg-n-brand text-white disabled:opacity-50"
        :disabled="naoPodeSalvar"
        @click="salvar"
      >
        {{ t('CAMPAIGN.WHATSAPP.SETTINGS.SAVE') }}
      </button>
      <span v-if="sujo" class="text-xs text-n-amber-11">
        {{ t('CAMPAIGN.WHATSAPP.SETTINGS.UNSAVED') }}
      </span>
    </div>
  </div>
</template>
