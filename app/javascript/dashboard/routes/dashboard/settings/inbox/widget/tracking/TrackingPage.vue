<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { useAlert } from 'dashboard/composables';
import SecretField from './SecretField.vue';
import EventMapTable from './EventMapTable.vue';
import AccountScopeCard from './AccountScopeCard.vue';
import DiagnosticsPanel from './DiagnosticsPanel.vue';
import WidgetSaveBar from '../WidgetSaveBar.vue';
import WidgetUnsavedChangesDialog from '../WidgetUnsavedChangesDialog.vue';
import { useInboxWidgetConfig } from '../composables/useInboxWidgetConfig';
import { useUnsavedChangesGuard } from '../composables/useUnsavedChangesGuard';
import { labelsForFields } from '../composables/widgetFieldLabels';
import {
  DEFAULT_EVENT_MAP,
  LEAD_VALUE_MODES,
  TEST_MODE_MAX_DAYS,
  TRACKING_LIMITS,
  isTestModeExpired,
} from '../composables/widgetTrackingContract';
import { useTrackingDiagnostics } from './useTrackingDiagnostics';
import { useTrackingCredentials } from './useTrackingCredentials';

/**
 * Tela 4 — rastreio e conversoes (bloco 5.06).
 *
 * A REGRA QUE GOVERNA A TELA INTEIRA: `widget_tracking` e publicado no HTML de
 * TODA pagina do site do cliente. Por isso aqui so entram IDENTIFICADORES
 * PUBLICOS — Pixel ID e Measurement ID ja aparecem no HTML de qualquer site que
 * use as tags. Segredo (access token, api secret) permite ESCREVER em nome do
 * cliente: mora em tabela cifrada e a gravacao daqui o recusa com 422.
 *
 * O QUE ESTA TELA NAO FAZ, e esta declarado nela mesma: guardar credencial e
 * conectar por OAuth sao do bloco **5.02**, que depende do 0.10 (chaves de
 * cifra, infra). O `SecretField` ja existe e ja tem o contrato dos dois
 * sentidos testado — o que falta e o lugar seguro do outro lado.
 */
const props = defineProps({
  inboxId: { type: [String, Number], required: true },
});

const { t } = useI18n();

const {
  inbox,
  draft,
  isDirty,
  dirtyCount,
  dirtyFields,
  isSaving,
  saveError,
  setIn,
  discard,
  save,
} = useInboxWidgetConfig(computed(() => props.inboxId));

const guard = useUnsavedChangesGuard({ isDirty, onDiscard: discard });
const changedLabels = computed(() => labelsForFields(dirtyFields.value, t));

/**
 * O diagnostico (5.14) e o cofre (5.02) sao LEITURAS PROPRIAS, fora do rascunho
 * da tela. Nao entram em `useInboxWidgetConfig` de proposito: nenhum dos dois e
 * configuracao editavel da inbox — um e log, o outro e segredo que a tela nunca
 * ve. Misturar os tres no mesmo rascunho faria a barra de salvar contar como
 * "alteracao pendente" um evento que chegou do servidor.
 */
const diagnostics = useTrackingDiagnostics(props.inboxId);
const credentials = useTrackingCredentials(props.inboxId);

onMounted(() => {
  diagnostics.carregar();
  credentials.carregar();
});

const guardarCredencial = (chave, valor) => credentials.guardar(chave, valor);

const abaAtiva = ref(0);
const abas = computed(() => [
  { label: t('INBOX_WIDGET.TRACKING.TABS.META') },
  { label: t('INBOX_WIDGET.TRACKING.TABS.GOOGLE') },
  { label: t('INBOX_WIDGET.TRACKING.TABS.EVENTS') },
  { label: t('INBOX_WIDGET.TRACKING.TABS.DIAGNOSTICS') },
]);
const trocarAba = aba => {
  abaAtiva.value = abas.value.findIndex(item => item.label === aba.label);
};

const tracking = computed(() => draft.value.tracking ?? {});
const testMode = computed(() => tracking.value.test_mode ?? {});

const set = (campo, valor) => setIn('tracking', campo, valor);

/** O modo teste desliga sozinho: 7 dias, e a tela avisa quanto falta. */
const testModeExpired = computed(() =>
  isTestModeExpired(testMode.value.started_at)
);
const testModeActive = computed(
  () => Boolean(testMode.value.enabled) && !testModeExpired.value
);

const alternarModoTeste = ligado =>
  set('test_mode', {
    ...testMode.value,
    enabled: ligado,
    // A data de inicio e o que faz o desligamento automatico existir; sem ela,
    // "7 dias" seria uma frase na tela e nada no dado.
    started_at: ligado ? new Date().toISOString() : null,
  });

/**
 * O interruptor DESTA caixa (T-C8.4: kill switch por conta **e** por inbox).
 *
 * Os dois niveis existem porque respondem a incidentes diferentes. O da conta e
 * do operador da plataforma: "pare tudo agora". O da inbox e do administrador
 * do cliente: "este site esta mandando evento errado, desliga so ele" — sem
 * precisar apagar o Pixel ID e reconfigurar tudo depois.
 *
 * POR QUE ELE AINDA NAO TEM CONTROLE, e por que isso NAO e um esquecimento:
 * `kill_switch` so vale se chegar ao widget, e o que chega ao widget e a lista
 * branca `WidgetTrackingProjection::PUBLIC_KEYS` do bloco 5.01. A chave nao
 * esta la, e o schema recusa a gravacao com 422 (`additionalProperties:
 * false`). Pintar um botao que grava nada seria pior que nao ter botao: o
 * administrador desligaria o rastreio num incidente, veria o controle mudar de
 * estado, e os eventos continuariam saindo.
 *
 * Entao a tela diz o que ele faz, diz que ainda nao esta disponivel e nomeia o
 * bloco — a mesma convencao do campo de segredo com o 5.02, logo acima.
 */
const killSwitchDaConta = computed(() =>
  Boolean(inbox.value.additional_attributes?.tracking_kill_switch)
);

const pixelIdInvalido = computed(
  () =>
    Boolean(tracking.value.meta_pixel_id) &&
    !TRACKING_LIMITS.metaPixelIdPattern.test(tracking.value.meta_pixel_id)
);
const measurementIdInvalido = computed(
  () =>
    Boolean(tracking.value.ga4_measurement_id) &&
    !TRACKING_LIMITS.ga4MeasurementIdPattern.test(
      tracking.value.ga4_measurement_id
    )
);
const sendToInvalido = computed(
  () =>
    Boolean(tracking.value.google_ads_send_to) &&
    !TRACKING_LIMITS.googleAdsSendToPattern.test(
      tracking.value.google_ads_send_to
    )
);

const leadValueLabel = modo =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_WIDGET.TRACKING.LEAD_VALUE.${modo.toUpperCase()}`);
const leadValueHint = modo =>
  // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
  t(`INBOX_WIDGET.TRACKING.LEAD_VALUE.${modo.toUpperCase()}_HINT`);

const leadValue = computed(() => tracking.value.lead_value ?? {});
const leadValueMode = computed(() => leadValue.value.mode ?? 'off');
const setLeadValue = patch =>
  set('lead_value', { ...leadValue.value, ...patch });

/** O mapa e gravado COMPLETO — quem consome le o que esta la. */
const salvarMapa = mapa => {
  const completo = Object.fromEntries(
    Object.entries(DEFAULT_EVENT_MAP).map(([nome, padrao]) => [
      nome,
      { ...padrao, ...(mapa[nome] ?? {}) },
    ])
  );
  set('event_map', completo);
};

const onSave = async () => {
  try {
    await save();
    useAlert(t('INBOX_WIDGET.TRACKING.SAVED'));
  } catch (error) {
    useAlert(error.message || t('INBOX_WIDGET.TRACKING.SAVE_ERROR'));
  }
};

defineExpose({ requestLeave: guard.requestLeave });
</script>

<template>
  <div class="flex flex-col h-full min-h-0 text-n-slate-12">
    <div
      class="flex flex-col flex-1 min-h-0 gap-4 px-6 py-4 overflow-y-auto max-w-4xl"
    >
      <TabBar
        :tabs="abas"
        :initial-active-tab="abaAtiva"
        @tab-changed="trocarAba"
      />

      <AccountScopeCard
        :consent-mode="tracking.consent_mode"
        :kill-switch="
          Boolean(inbox.additional_attributes?.tracking_kill_switch)
        "
        :retention-days="
          Number(inbox.additional_attributes?.tracking_retention_days) || 0
        "
        :dpa-accepted="
          Boolean(inbox.additional_attributes?.tracking_dpa_accepted)
        "
      />

      <!-- ── O interruptor DESTA caixa (T-C8.4) ────────────────────────── -->
      <div
        class="flex flex-col gap-1 p-4 border rounded-xl border-n-weak"
        data-testid="inbox-kill-switch-card"
      >
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INBOX_WIDGET.TRACKING.KILL_SWITCH.TITLE') }}
        </span>
        <span class="text-sm text-n-slate-11">
          {{ t('INBOX_WIDGET.TRACKING.KILL_SWITCH.HINT') }}
        </span>
        <span
          class="text-sm text-n-amber-12"
          data-testid="kill-switch-blocked"
        >
          {{ t('INBOX_WIDGET.TRACKING.KILL_SWITCH.BLOCKED_BY_501') }}
        </span>
        <span
          v-if="killSwitchDaConta"
          class="text-sm text-n-amber-12"
          data-testid="kill-switch-account-wins"
        >
          {{ t('INBOX_WIDGET.TRACKING.KILL_SWITCH.ACCOUNT_WINS') }}
        </span>
      </div>

      <!-- ── Meta ─────────────────────────────────────────────────────── -->
      <div v-if="abaAtiva === 0" class="flex flex-col" data-testid="tab-meta">
        <SettingsFieldSection
          :label="t('INBOX_WIDGET.TRACKING.META.PIXEL_ID')"
          :help-text="t('INBOX_WIDGET.TRACKING.META.PIXEL_ID_HINT')"
        >
          <Input
            class="max-w-sm"
            :model-value="tracking.meta_pixel_id ?? ''"
            :aria-label="t('INBOX_WIDGET.TRACKING.META.PIXEL_ID')"
            :message="
              pixelIdInvalido
                ? t('INBOX_WIDGET.TRACKING.META.PIXEL_ID_INVALID')
                : ''
            "
            :message-type="pixelIdInvalido ? 'error' : 'info'"
            data-testid="meta-pixel-id"
            @update:model-value="set('meta_pixel_id', $event)"
          />
        </SettingsFieldSection>

        <SettingsFieldSection :label="t('INBOX_WIDGET.TRACKING.META.TOKEN')">
          <SecretField
            :label="t('INBOX_WIDGET.TRACKING.META.TOKEN')"
            :is-defined="credentials.credentials.value.meta_access_token.configured"
            :last-four="credentials.credentials.value.meta_access_token.lastFour"
            :disabled="credentials.vaultUnavailable.value"
            :disabled-reason="
              credentials.vaultUnavailable.value
                ? t('INBOX_WIDGET.TRACKING.BLOCKED_BY_502')
                : ''
            "
            data-testid="meta-token"
            @change="guardarCredencial('meta_access_token', $event)"
          />
          <p class="mt-2 text-sm text-n-slate-11" data-testid="meta-oauth">
            {{ t('INBOX_WIDGET.TRACKING.OAUTH_PENDING') }}
          </p>
        </SettingsFieldSection>

        <SettingsFieldSection
          :label="t('INBOX_WIDGET.TRACKING.META.TEST_MODE')"
          :help-text="
            t('INBOX_WIDGET.TRACKING.META.TEST_MODE_HINT', {
              days: TEST_MODE_MAX_DAYS,
            })
          "
        >
          <div class="flex flex-col gap-2">
            <Switch
              :model-value="testModeActive"
              :aria-label="t('INBOX_WIDGET.TRACKING.META.TEST_MODE')"
              data-testid="test-mode"
              @update:model-value="alternarModoTeste"
            />
            <Input
              v-if="testModeActive"
              class="max-w-xs"
              :model-value="testMode.code ?? ''"
              placeholder="TEST12345"
              :aria-label="t('INBOX_WIDGET.TRACKING.META.TEST_CODE')"
              data-testid="test-code"
              @update:model-value="
                set('test_mode', { ...testMode, code: $event })
              "
            />
            <Banner
              v-if="testModeExpired"
              color="amber"
              data-testid="test-mode-expired"
            >
              <span class="text-n-amber-12">
                {{
                  t('INBOX_WIDGET.TRACKING.META.TEST_MODE_EXPIRED', {
                    days: TEST_MODE_MAX_DAYS,
                  })
                }}
              </span>
            </Banner>
          </div>
        </SettingsFieldSection>
      </div>

      <!-- ── Google ───────────────────────────────────────────────────── -->
      <div v-if="abaAtiva === 1" class="flex flex-col" data-testid="tab-google">
        <SettingsFieldSection
          :label="t('INBOX_WIDGET.TRACKING.GOOGLE.MEASUREMENT_ID')"
          :help-text="t('INBOX_WIDGET.TRACKING.GOOGLE.MEASUREMENT_ID_HINT')"
        >
          <Input
            class="max-w-sm"
            :model-value="tracking.ga4_measurement_id ?? ''"
            :aria-label="t('INBOX_WIDGET.TRACKING.GOOGLE.MEASUREMENT_ID')"
            :message="
              measurementIdInvalido
                ? t('INBOX_WIDGET.TRACKING.GOOGLE.MEASUREMENT_ID_INVALID')
                : ''
            "
            :message-type="measurementIdInvalido ? 'error' : 'info'"
            data-testid="ga4-measurement-id"
            @update:model-value="set('ga4_measurement_id', $event)"
          />
        </SettingsFieldSection>

        <SettingsFieldSection
          :label="t('INBOX_WIDGET.TRACKING.GOOGLE.API_SECRET')"
        >
          <SecretField
            :label="t('INBOX_WIDGET.TRACKING.GOOGLE.API_SECRET')"
            :is-defined="credentials.credentials.value.ga4_api_secret.configured"
            :last-four="credentials.credentials.value.ga4_api_secret.lastFour"
            :disabled="credentials.vaultUnavailable.value"
            :disabled-reason="
              credentials.vaultUnavailable.value
                ? t('INBOX_WIDGET.TRACKING.BLOCKED_BY_502')
                : ''
            "
            data-testid="ga4-api-secret"
            @change="guardarCredencial('ga4_api_secret', $event)"
          />
          <p class="mt-2 text-sm text-n-slate-11" data-testid="google-oauth">
            {{ t('INBOX_WIDGET.TRACKING.OAUTH_PENDING') }}
          </p>
        </SettingsFieldSection>

        <SettingsFieldSection
          :label="t('INBOX_WIDGET.TRACKING.GOOGLE.SEND_TO')"
          :help-text="t('INBOX_WIDGET.TRACKING.GOOGLE.SEND_TO_HINT')"
        >
          <Input
            class="max-w-sm"
            :model-value="tracking.google_ads_send_to ?? ''"
            :aria-label="t('INBOX_WIDGET.TRACKING.GOOGLE.SEND_TO')"
            :message="
              sendToInvalido
                ? t('INBOX_WIDGET.TRACKING.GOOGLE.SEND_TO_INVALID')
                : ''
            "
            :message-type="sendToInvalido ? 'error' : 'info'"
            data-testid="google-ads-send-to"
            @update:model-value="set('google_ads_send_to', $event)"
          />
        </SettingsFieldSection>
      </div>

      <!-- ── Eventos ──────────────────────────────────────────────────── -->
      <div
        v-if="abaAtiva === 2"
        class="flex flex-col gap-4"
        data-testid="tab-events"
      >
        <EventMapTable
          :event-map="tracking.event_map ?? {}"
          @update="salvarMapa"
        />

        <h4 class="text-sm font-medium text-n-slate-12">
          {{ t('INBOX_WIDGET.TRACKING.LEAD_VALUE.TITLE') }}
        </h4>
        <div class="grid gap-3 sm:grid-cols-3">
          <RadioCard
            v-for="modo in LEAD_VALUE_MODES"
            :id="`lead-value-${modo}`"
            :key="modo"
            :label="leadValueLabel(modo)"
            :description="leadValueHint(modo)"
            :is-active="leadValueMode === modo"
            :data-testid="`lead-value-${modo}`"
            @select="setLeadValue({ mode: modo })"
          />
        </div>
        <Input
          v-if="leadValueMode === 'fixed'"
          type="number"
          class="max-w-[10rem]"
          :model-value="leadValue.amount ?? 0"
          :aria-label="t('INBOX_WIDGET.TRACKING.LEAD_VALUE.AMOUNT')"
          data-testid="lead-value-amount"
          @update:model-value="setLeadValue({ amount: Number($event) || 0 })"
        />
      </div>

      <!-- ── Diagnóstico ──────────────────────────────────────────────── -->
      <div v-if="abaAtiva === 3" data-testid="tab-diagnostics">
        <DiagnosticsPanel
          :deliveries="diagnostics.deliveries.value"
          :delivery-rate="diagnostics.deliveryRate.value"
          :error-groups="diagnostics.errorGroups.value"
          :emq-average="diagnostics.emqAverage.value"
          :retention-days="diagnostics.retentionDays.value"
          :is-loading="diagnostics.isLoading.value"
          :is-sending-test="diagnostics.isSendingTest.value"
          :missing-endpoint="diagnostics.missingEndpoint.value"
          :load-error="diagnostics.loadError.value"
          :test-result="diagnostics.testResult.value"
          @test="diagnostics.enviarEventoDeTeste"
          @refresh="diagnostics.carregar"
        />
      </div>
    </div>

    <WidgetSaveBar
      :dirty-count="dirtyCount"
      :is-saving="isSaving"
      :error-message="saveError"
      @save="onSave"
      @discard="discard"
    />

    <WidgetUnsavedChangesDialog
      :open="guard.isPromptOpen.value"
      :changed-labels="changedLabels"
      @confirm="guard.confirmLeave"
      @cancel="guard.cancelLeave"
    />
  </div>
</template>
