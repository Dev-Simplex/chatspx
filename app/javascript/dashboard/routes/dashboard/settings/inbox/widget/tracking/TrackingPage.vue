<script setup>
import { computed, ref } from 'vue';
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
            :is-defined="false"
            disabled
            :disabled-reason="t('INBOX_WIDGET.TRACKING.BLOCKED_BY_502')"
            data-testid="meta-token"
          />
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
            :is-defined="false"
            disabled
            :disabled-reason="t('INBOX_WIDGET.TRACKING.BLOCKED_BY_502')"
            data-testid="ga4-api-secret"
          />
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

        <!--
          Bloco 5.10 (T-C4.3, decisao Q5). O toggle governa a PONTE, nao um destino — por isso
          mora aqui, junto do mapa de eventos, e nao repetido nas abas Meta e Google.

          Desligado, a ponte so dispara nas tags que JA existem na pagina do cliente. Ligado, ela
          instala a que falta — e mesmo assim sem `PageView`, porque a pagina do cliente ja conta
          a visita dela e contar de novo estraga o numero que ele mais olha.
        -->
        <SettingsFieldSection
          :label="t('INBOX_WIDGET.TRACKING.INSTALL_TAGS.LABEL')"
          :help-text="t('INBOX_WIDGET.TRACKING.INSTALL_TAGS.HINT')"
        >
          <Switch
            :model-value="tracking.install_tags === true"
            :aria-label="t('INBOX_WIDGET.TRACKING.INSTALL_TAGS.LABEL')"
            data-testid="install-tags"
            @update:model-value="set('install_tags', $event)"
          />
        </SettingsFieldSection>

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
          :deliveries="[]"
          :unavailable-reason="
            t('INBOX_WIDGET.TRACKING.DIAGNOSTICS.UNAVAILABLE')
          "
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
