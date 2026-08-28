<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsAccordion from 'dashboard/components-next/Settings/SettingsAccordion.vue';
import SelectInput from 'dashboard/components-next/select/Select.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Widget from 'dashboard/modules/widget-preview/components/Widget.vue';
import { useAlert } from 'dashboard/composables';
import BrandColorField from './BrandColorField.vue';
import ThemeModeField from './ThemeModeField.vue';
import LauncherField from './LauncherField.vue';
import AppearanceOverrideBanner from './AppearanceOverrideBanner.vue';
import WidgetProfileSelector from '../WidgetProfileSelector.vue';
import WidgetProfileEscapeLink from '../WidgetProfileEscapeLink.vue';
import WidgetSaveBar from '../WidgetSaveBar.vue';
import WidgetUnsavedChangesDialog from '../WidgetUnsavedChangesDialog.vue';
import { useInboxWidgetConfig } from '../composables/useInboxWidgetConfig';
import { useUnsavedChangesGuard } from '../composables/useUnsavedChangesGuard';
import { labelsForFields } from '../composables/widgetFieldLabels';
import {
  currentValuesFromDraft,
  profileWrites,
  useProfileVisibility,
} from '../composables/useProfileVisibility';

/**
 * Tela 1 — Aparência.
 *
 * O que ela junta: a cor da marca com o medidor de contraste (3.08), o tema, o
 * lançador (posição, offsets, formato, texto, esconder), os textos, os recursos
 * e o avançado — com o preview ao vivo do lado, consumindo o RASCUNHO, não o
 * store.
 *
 * O ponto que justifica a tela existir: tema, posição, offsets, formato e texto
 * do lançador viviam no `localStorage` do navegador do administrador (D1). O
 * admin A configurava "esquerda" e o admin B, em outro navegador, via
 * "direita" — e o visitante via o que o snippet dissesse. Aqui isso vira
 * configuração da inbox, gravada em `widget_appearance`.
 *
 * E quando o site do cliente sobrescreve por `chatwootSettings`, a tela
 * **avisa** em vez de mentir (`AppearanceOverrideBanner`).
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
  set,
  setIn,
  discard,
  save,
} = useInboxWidgetConfig(computed(() => props.inboxId));

const guard = useUnsavedChangesGuard({ isDirty, onDiscard: discard });

const changedLabels = computed(() => labelsForFields(dirtyFields.value, t));

/* ── O perfil (bloco 3.07) ───────────────────────────────────────────────────
 *
 * Ele mora AQUI, no topo da primeira aba, e não numa aba própria: o perfil não
 * é uma configuração entre outras — ele determina QUAIS configurações existem,
 * então precisa estar visível antes das outras escolhas.
 *
 * Até 3.07 o seletor só existia no wizard de criação (`channels/Website.vue`),
 * onde o `allow-empty` desvia o diálogo. Resultado medido: o aceite do bloco
 * ("trocar o perfil abre diálogo listando o que muda e o que continua gravado")
 * nunca acontecia no produto, e o `@apply` não tinha ouvinte — cada caixa que o
 * administrador marcava caía no chão.
 * ────────────────────────────────────────────────────────────────────────── */
const profileVisibility = useProfileVisibility(
  computed(() => draft.value.profile)
);
const { isSectionVisible } = profileVisibility;

/** O que já está gravado, para o diálogo não propor o que já é assim. */
const currentValues = computed(() => currentValuesFromDraft(draft.value));

/**
 * O ouvinte do `@apply`. A troca PROPÕE: só o que o administrador deixou
 * marcado vira escrita, e a escrita vai para o RASCUNHO — nada vai ao servidor
 * antes de ele salvar.
 */
const onProfileApply = ({ accepted }) => {
  profileWrites(accepted, draft.value).forEach(({ key, value }) =>
    set(key, value)
  );
};

/**
 * O formato expandido é um dispositivo de captura (perfil marketing). Mas se
 * ele é o que ESTÁ gravado, continua à vista mesmo no perfil suporte: esconder
 * a opção selecionada faria a tela mentir sobre o estado atual da caixa.
 */
const showExpandedLauncher = computed(
  () =>
    isSectionVisible('appearance.launcherExpanded') ||
    draft.value.appearance?.launcher_type === 'expanded_bubble'
);

/**
 * Os campos que o `chatwootSettings` do site sobrescreve. Quem informa é o
 * servidor (bloco 3.18); enquanto a chave não existir, a lista vem vazia e o
 * aviso não aparece — ausência de dado nunca vira aviso falso.
 */
const overriddenFields = computed(
  () => inbox.value?.additional_attributes?.widget_appearance_overrides ?? []
);

const REPLY_TIMES = ['in_a_few_minutes', 'in_a_few_hours', 'in_a_day'];
const PANEL_STYLES = ['standard', 'flat'];
const FEATURES = [
  'attachments',
  'emoji_picker',
  'end_conversation',
  'use_inbox_avatar_for_bot',
];

const replyTimeOptions = computed(() =>
  REPLY_TIMES.map(value => ({
    value,
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(
      `INBOX_WIDGET.APPEARANCE.TEXTS.REPLY_TIMES.${value.toUpperCase()}`
    ),
  }))
);

const panelStyleOptions = computed(() =>
  PANEL_STYLES.map(value => ({
    value,
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(
      `INBOX_WIDGET.APPEARANCE.ADVANCED.PANEL_STYLES.${value.toUpperCase()}`
    ),
  }))
);

const toggleFeature = feature => {
  const current = draft.value.featureFlags ?? [];
  set(
    'featureFlags',
    current.includes(feature)
      ? current.filter(item => item !== feature)
      : [...current, feature]
  );
};

/**
 * Exposto para `Settings.vue`: a troca de aba nao passa pelo router, entao quem
 * troca precisa perguntar antes. Devolve `true` quando pode sair na hora.
 */
defineExpose({ requestLeave: guard.requestLeave });

const onSave = async () => {
  try {
    await save();
    useAlert(t('INBOX_WIDGET.APPEARANCE.SAVED'));
  } catch (error) {
    // A faixa persistente fica na barra: um toast que some não basta para quem
    // acabou de configurar dez campos.
    useAlert(error.message || t('INBOX_WIDGET.APPEARANCE.SAVE_ERROR'));
  }
};
</script>

<template>
  <!-- A tela define a própria cor de texto: `body` no dashboard não define
       nenhuma, então um texto sem classe herdaria o preto do navegador — que
       no tema escuro dá 1,13:1. Medido no Chromium. -->
  <div class="flex flex-col h-full min-h-0 text-n-slate-12">
    <div
      class="flex flex-col flex-1 min-h-0 gap-6 px-6 py-4 overflow-y-auto lg:flex-row"
    >
      <div class="flex flex-col flex-1 min-w-0 max-w-3xl">
        <AppearanceOverrideBanner
          v-if="overriddenFields.length"
          class="mb-4"
          :overridden-fields="overriddenFields"
        />

        <h3 class="text-heading-2 text-n-slate-12">
          {{ t('INBOX_WIDGET.PROFILE.SECTION_TITLE') }}
        </h3>
        <SettingsFieldSection
          :help-text="t('INBOX_WIDGET.PROFILE.SECTION_HELP')"
        >
          <WidgetProfileSelector
            :model-value="draft.profile"
            :current-values="currentValues"
            @update:model-value="set('profile', $event)"
            @apply="onProfileApply"
          />
        </SettingsFieldSection>

        <h3 class="text-heading-2 text-n-slate-12">
          {{ t('INBOX_WIDGET.APPEARANCE.SECTIONS.BRAND') }}
        </h3>
        <SettingsFieldSection
          :label="t('INBOX_WIDGET.APPEARANCE.BRAND_COLOR.LABEL')"
        >
          <BrandColorField
            :model-value="draft.widgetColor"
            @update:model-value="set('widgetColor', $event)"
          />
        </SettingsFieldSection>

        <h3 class="text-heading-2 text-n-slate-12">
          {{ t('INBOX_WIDGET.APPEARANCE.SECTIONS.THEME') }}
        </h3>
        <SettingsFieldSection
          :label="t('INBOX_WIDGET.APPEARANCE.THEME.LABEL')"
          :help-text="t('INBOX_WIDGET.APPEARANCE.THEME.HELP')"
        >
          <ThemeModeField
            :model-value="draft.appearance.theme"
            @update:model-value="setIn('appearance', 'theme', $event)"
          />
        </SettingsFieldSection>

        <h3 class="text-heading-2 text-n-slate-12">
          {{ t('INBOX_WIDGET.APPEARANCE.SECTIONS.LAUNCHER') }}
        </h3>
        <LauncherField
          :appearance="draft.appearance"
          :overridden-fields="overriddenFields"
          :show-expanded-launcher="showExpandedLauncher"
          @update="(field, value) => setIn('appearance', field, value)"
        />
        <WidgetProfileEscapeLink
          v-if="!showExpandedLauncher"
          :active-profile="profileVisibility.activeProfile.value"
          :other-profile="profileVisibility.otherProfile.value"
          :showing="profileVisibility.showOtherProfile.value"
          @toggle="profileVisibility.toggleOtherProfile"
        />

        <h3 class="text-heading-2 text-n-slate-12">
          {{ t('INBOX_WIDGET.APPEARANCE.SECTIONS.TEXTS') }}
        </h3>
        <SettingsFieldSection
          :label="t('INBOX_WIDGET.APPEARANCE.TEXTS.WELCOME_TITLE')"
        >
          <!-- `aria-label` porque o rótulo do `SettingsFieldSection` é um
               `<label>` SEM `for` (é assim no componente do dashboard). Sem
               isto o campo fica sem nome acessível — o defeito que a §B.0.5
               manda não repetir. -->
          <Input
            id="welcome-title"
            class="max-w-md"
            :model-value="draft.welcomeTitle"
            :aria-label="t('INBOX_WIDGET.APPEARANCE.TEXTS.WELCOME_TITLE')"
            data-testid="welcome-title"
            @update:model-value="set('welcomeTitle', $event)"
          />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="t('INBOX_WIDGET.APPEARANCE.TEXTS.WELCOME_TAGLINE')"
        >
          <Input
            id="welcome-tagline"
            class="max-w-md"
            :model-value="draft.welcomeTagline"
            :aria-label="t('INBOX_WIDGET.APPEARANCE.TEXTS.WELCOME_TAGLINE')"
            data-testid="welcome-tagline"
            @update:model-value="set('welcomeTagline', $event)"
          />
        </SettingsFieldSection>
        <SettingsFieldSection
          :label="t('INBOX_WIDGET.APPEARANCE.TEXTS.REPLY_TIME')"
        >
          <label class="block max-w-xs">
            <span class="sr-only">
              {{ t('INBOX_WIDGET.APPEARANCE.TEXTS.REPLY_TIME') }}
            </span>
            <SelectInput
              id="reply-time"
              :model-value="draft.replyTime"
              :options="replyTimeOptions"
              data-testid="reply-time"
              @update:model-value="set('replyTime', $event)"
            />
          </label>
        </SettingsFieldSection>

        <h3 class="text-heading-2 text-n-slate-12">
          {{ t('INBOX_WIDGET.APPEARANCE.SECTIONS.FEATURES') }}
        </h3>
        <div class="flex flex-col gap-2 py-3">
          <!-- `id` no input E `for` no label: o clique no rótulo tem de focar o
               campo. A aba antiga tem `for` sem `id` correspondente. -->
          <div
            v-for="feature in FEATURES"
            :key="feature"
            class="flex items-center gap-2"
          >
            <input
              :id="`feature-${feature}`"
              type="checkbox"
              :checked="(draft.featureFlags || []).includes(feature)"
              :data-testid="`feature-${feature}`"
              @change="toggleFeature(feature)"
            />
            <label :for="`feature-${feature}`" class="text-sm text-n-slate-11">
              <!-- eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys -->
              {{
                t(`INBOX_WIDGET.APPEARANCE.FEATURES.${feature.toUpperCase()}`)
              }}
            </label>
          </div>
        </div>

        <SettingsAccordion
          :title="t('INBOX_WIDGET.APPEARANCE.SECTIONS.ADVANCED')"
          :default-open="false"
        >
          <SettingsFieldSection
            :label="t('INBOX_WIDGET.APPEARANCE.ADVANCED.PANEL_STYLE')"
            :help-text="t('INBOX_WIDGET.APPEARANCE.ADVANCED.PANEL_STYLE_HINT')"
          >
            <label class="block max-w-xs">
              <span class="sr-only">
                {{ t('INBOX_WIDGET.APPEARANCE.ADVANCED.PANEL_STYLE') }}
              </span>
              <SelectInput
                id="panel-style"
                :model-value="draft.appearance.panel_style"
                :options="panelStyleOptions"
                data-testid="panel-style"
                @update:model-value="setIn('appearance', 'panel_style', $event)"
              />
            </label>
          </SettingsFieldSection>
        </SettingsAccordion>
      </div>

      <div class="w-full lg:w-[26rem] lg:sticky lg:top-4 lg:self-start">
        <Widget
          :website-name="draft.name"
          :welcome-heading="draft.welcomeTitle"
          :welcome-tagline="draft.welcomeTagline"
          :reply-time="draft.replyTime"
          :color="draft.widgetColor"
          :logo="inbox.avatar_url"
          :theme-mode="draft.appearance.theme"
          :widget-bubble-position="draft.appearance.position"
          :widget-bubble-type="draft.appearance.launcher_type"
          :widget-bubble-launcher-title="draft.appearance.launcher_text"
          :offset-x="draft.appearance.offset_x"
          :offset-y="draft.appearance.offset_y"
          :hide-bubble="draft.appearance.hide_bubble"
          :web-widget-script="inbox.web_widget_script"
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
