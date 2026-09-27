<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { formatDistanceToNowStrict } from 'date-fns';
import { enUS, ptBR } from 'date-fns/locale';
import { useAlert } from 'dashboard/composables';
import CaptadorAPI from 'dashboard/api/integrations/captador';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

// Lead do Captador na lateral da conversa. Sem `leadId` (conversa comum) não sai
// nenhuma chamada. O Captador fora do ar vira um aviso aqui e nada mais: o
// atendimento segue.
const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
  leadId: {
    type: String,
    default: null,
  },
});

const { t, locale } = useI18n();

const data = ref(null);
const isLoading = ref(false);
const isMoving = ref(false);
// 'unavailable' (Captador fora do ar) | 'pending_access' (sem vínculo no Captador)
const errorKind = ref(null);
const isMenuOpen = ref(false);
const toggleMenu = () => {
  isMenuOpen.value = !isMenuOpen.value;
};
const closeMenu = () => {
  isMenuOpen.value = false;
};
let lastRequest = 0;

const lead = computed(() => data.value?.lead || null);
const empresa = computed(() => data.value?.empresa || {});
const etapas = computed(() => data.value?.etapas || []);
const currentStage = computed(() =>
  etapas.value.find(etapa => etapa.id === lead.value?.etapa_id)
);
const canMove = computed(() => data.value?.pode_mover !== false);
const stageMenuItems = computed(() =>
  etapas.value
    .filter(etapa => etapa.ativa !== false && etapa.id !== lead.value?.etapa_id)
    .map(etapa => ({ action: 'move', value: etapa.id, label: etapa.nome }))
);
const doNotContact = computed(
  () =>
    empresa.value.nao_contatar === true ||
    lead.value?.perdido?.motivo === 'pediu_nao_contatar'
);

const dateLocale = computed(() =>
  String(locale.value || '').startsWith('pt') ? ptBR : enUS
);

const formatCnpj = cnpj =>
  String(cnpj).replace(
    /^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/,
    '$1.$2.$3/$4-$5'
  );

// "2019-05-01" → "01/05/2019", sem passar por Date (o fuso puxaria para o dia anterior).
const formatDate = value =>
  value ? String(value).split('-').reverse().join('/') : null;

const relativeTime = value => {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return null;
  return formatDistanceToNowStrict(date, {
    addSuffix: true,
    locale: dateLocale.value,
  });
};

const originLabel = origem => {
  if (!origem) return null;
  return t(`CONVERSATION_SIDEBAR.CAPTADOR.ORIGIN.${origem.toUpperCase()}`);
};

const details = computed(() => {
  if (!lead.value) return [];
  const municipio = empresa.value.municipio || lead.value.municipio;
  const field = key => t(`CONVERSATION_SIDEBAR.CAPTADOR.FIELDS.${key}`);
  return [
    [field('OWNER'), lead.value.dono?.nome],
    [field('ORIGIN'), originLabel(lead.value.origem)],
    [field('LAST_ACTIVITY'), relativeTime(lead.value.ultima_atividade_em)],
    [field('STATUS'), empresa.value.situacao?.descricao],
    [field('ACTIVITY'), empresa.value.cnae_principal?.descricao],
    [field('SIZE'), empresa.value.porte?.descricao],
    [field('CITY'), municipio && `${municipio.nome}/${municipio.uf}`],
    [field('OPENED_ON'), formatDate(empresa.value.data_abertura)],
  ]
    .filter(([, value]) => value)
    .map(([label, value]) => ({ label, value }));
});

const fetchLead = async () => {
  lastRequest += 1;
  const request = lastRequest;
  data.value = null;
  errorKind.value = null;
  if (!props.leadId) return;

  isLoading.value = true;
  try {
    const response = await CaptadorAPI.getLead(props.conversationId);
    if (request !== lastRequest) return;
    data.value = response.data;
  } catch (error) {
    if (request !== lastRequest) return;
    if (error.response?.status === 404) {
      data.value = { lead: null };
    } else {
      errorKind.value =
        error.response?.data?.codigo === 'acesso_pendente'
          ? 'pending_access'
          : 'unavailable';
    }
  } finally {
    if (request === lastRequest) isLoading.value = false;
  }
};

const moveTo = async ({ value }) => {
  closeMenu();
  isMoving.value = true;
  try {
    const response = await CaptadorAPI.moveStage(props.conversationId, value);
    data.value = { ...data.value, ...response.data };
    useAlert(
      t('CONVERSATION_SIDEBAR.CAPTADOR.MOVED', {
        stage: currentStage.value?.nome || '',
      })
    );
  } catch (error) {
    useAlert(
      error.response?.data?.detail ||
        t('CONVERSATION_SIDEBAR.CAPTADOR.MOVE_ERROR')
    );
  } finally {
    isMoving.value = false;
  }
};

watch(() => [props.conversationId, props.leadId], fetchLead, {
  immediate: true,
});
</script>

<template>
  <div class="px-1 pb-1 text-n-slate-12">
    <div
      v-if="isLoading"
      class="flex justify-center py-3"
      role="status"
      :aria-label="t('CONVERSATION_SIDEBAR.CAPTADOR.LOADING')"
    >
      <Spinner class="text-n-brand" />
    </div>

    <div
      v-else-if="errorKind"
      class="flex flex-col items-center gap-2 py-3 text-center"
      role="alert"
    >
      <p class="text-xs text-n-slate-11">
        {{
          errorKind === 'pending_access'
            ? t('CONVERSATION_SIDEBAR.CAPTADOR.PENDING_ACCESS')
            : t('CONVERSATION_SIDEBAR.CAPTADOR.UNAVAILABLE')
        }}
      </p>
      <Button
        v-if="errorKind === 'unavailable'"
        size="sm"
        variant="ghost"
        color="slate"
        icon="i-lucide-refresh-cw"
        :label="t('CONVERSATION_SIDEBAR.CAPTADOR.RETRY')"
        @click="fetchLead"
      />
    </div>

    <div
      v-else-if="!lead"
      class="flex flex-col items-center gap-1 py-3 text-center"
    >
      <Icon icon="i-lucide-target" class="size-5 text-n-slate-8" />
      <p class="text-xs text-n-slate-10">
        {{ t('CONVERSATION_SIDEBAR.CAPTADOR.EMPTY') }}
      </p>
    </div>

    <div
      v-else
      class="flex flex-col gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3"
    >
      <div class="flex min-w-0 flex-col gap-0.5">
        <span class="truncate text-sm font-medium text-n-slate-12">
          {{ lead.nome }}
        </span>
        <span v-if="lead.cnpj" class="text-xs tabular-nums text-n-slate-11">
          {{ formatCnpj(lead.cnpj) }}
        </span>
      </div>

      <div class="flex flex-wrap items-center gap-1.5">
        <span
          v-if="currentStage"
          class="rounded-md bg-n-alpha-2 px-2 py-0.5 text-xs font-medium text-n-slate-12"
        >
          {{ currentStage.nome }}
        </span>
        <span
          v-if="lead.parado"
          class="rounded-md bg-n-amber-3 px-2 py-0.5 text-xs text-n-amber-11"
        >
          {{ t('CONVERSATION_SIDEBAR.CAPTADOR.STALLED') }}
        </span>
        <span
          v-if="lead.perdido"
          class="rounded-md bg-n-slate-3 px-2 py-0.5 text-xs text-n-slate-11"
        >
          {{ t('CONVERSATION_SIDEBAR.CAPTADOR.LOST') }}
        </span>
        <span
          v-if="doNotContact"
          class="rounded-md bg-n-ruby-3 px-2 py-0.5 text-xs text-n-ruby-11"
        >
          {{ t('CONVERSATION_SIDEBAR.CAPTADOR.DO_NOT_CONTACT') }}
        </span>
      </div>

      <dl
        v-if="details.length"
        class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-xs"
      >
        <template v-for="row in details" :key="row.label">
          <dt class="text-n-slate-10">{{ row.label }}</dt>
          <dd class="min-w-0 truncate text-n-slate-12" :title="row.value">
            {{ row.value }}
          </dd>
        </template>
      </dl>

      <div class="flex flex-wrap items-center gap-2">
        <div
          v-if="canMove && stageMenuItems.length"
          v-on-clickaway="closeMenu"
          class="relative"
        >
          <Button
            size="sm"
            variant="faded"
            color="slate"
            icon="i-lucide-arrow-right"
            :label="t('CONVERSATION_SIDEBAR.CAPTADOR.MOVE')"
            :is-loading="isMoving"
            :disabled="isMoving"
            aria-haspopup="menu"
            :aria-expanded="isMenuOpen"
            @click="toggleMenu"
          />
          <DropdownMenu
            v-if="isMenuOpen"
            :menu-items="stageMenuItems"
            class="top-full z-10 mt-1 ltr:left-0 rtl:right-0"
            @action="moveTo"
          />
        </div>
        <a
          v-if="data.url"
          :href="data.url"
          target="_blank"
          rel="noopener noreferrer"
          class="inline-flex min-h-8 items-center gap-1 rounded-lg px-2 text-xs font-medium text-n-blue-text hover:bg-n-alpha-2"
        >
          <Icon icon="i-lucide-external-link" class="size-3.5" />
          {{ t('CONVERSATION_SIDEBAR.CAPTADOR.OPEN') }}
        </a>
      </div>
    </div>
  </div>
</template>
