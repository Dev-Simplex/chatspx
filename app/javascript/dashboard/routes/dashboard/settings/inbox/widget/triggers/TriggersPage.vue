<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import SettingsAccordion from 'dashboard/components-next/Settings/SettingsAccordion.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Banner from 'dashboard/components-next/banner/Banner.vue';
import { useAlert } from 'dashboard/composables';
import ApproachSelector from './ApproachSelector.vue';
import TriggerRow from './TriggerRow.vue';
import SegmentationField from './SegmentationField.vue';
import TeaserComposer from './TeaserComposer.vue';
import LegacyCampaigns from './LegacyCampaigns.vue';
import Widget from 'dashboard/modules/widget-preview/components/Widget.vue';
import WidgetProfileEscapeLink from '../WidgetProfileEscapeLink.vue';
import WidgetSaveBar from '../WidgetSaveBar.vue';
import WidgetUnsavedChangesDialog from '../WidgetUnsavedChangesDialog.vue';
import { useProfileVisibility } from '../composables/useProfileVisibility';
import { useInboxWidgetConfig } from '../composables/useInboxWidgetConfig';
import { useUnsavedChangesGuard } from '../composables/useUnsavedChangesGuard';
import { labelsForFields } from '../composables/widgetFieldLabels';
import {
  RECOMMENDED_TRIGGERS,
  TRIGGER_IDS,
  TRIGGER_LIMITS,
} from '../composables/widgetTriggersContract';

/**
 * Tela 2 — gatilhos e abordagem (bloco 4.04).
 *
 * Duas coisas diferentes moram aqui, e a tela nao pode confundi-las:
 * o **QUANDO** (os sete gatilhos, a frequencia e onde aparecer) e o **COMO**
 * (a abordagem em tres niveis, do bloco 3.20). A mensagem — o texto do teaser —
 * nao esta aqui: ela e campanha, e o vinculo e o bloco 4.05.
 *
 * O interruptor mestre comeca DESLIGADO em inbox que nunca abriu esta tela:
 * salvar outro campo qualquer nao pode ligar convite proativo sem alguem pedir.
 */
const props = defineProps({
  inboxId: { type: [String, Number], required: true },
});

const { t } = useI18n();

const teaserComposer = ref(null);
const simulandoGatilho = ref(false);

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
 * Bloco 3.07 — a segmentacao e secao de marketing
 * (`PROFILE_SECTIONS['triggers.segmentation']`). Quem esta em suporte nao a ve
 * por padrao, e o link de escape a traz de volta sem trocar o perfil: o perfil
 * ESCONDE, nunca remove.
 */
const profileVisibility = useProfileVisibility(
  computed(() => draft.value.profile)
);
const { isSectionVisible } = profileVisibility;

const triggers = computed(() => draft.value.triggers ?? {});
// 4.22 — o interruptor mestre lido do RASCUNHO, e nao do salvo: o aviso do modo antigo
// tem de acompanhar o que o administrador acabou de marcar, antes de salvar. Ele decide
// o texto do aviso, nunca a precedencia em si — quem decide isso e o widget, pelo que
// esta gravado (`shared/helpers/abordagemProativa`).
const gatilhoLigado = computed(() => Boolean(triggers.value.enabled));
const lista = computed(() => triggers.value.triggers ?? []);
const defaults = computed(() => triggers.value.defaults ?? {});

const porId = computed(() =>
  Object.fromEntries(lista.value.map(item => [item.id, item]))
);

/**
 * Modo: "Recomendado" e exatamente o preset composto (8 s E 30%). Qualquer
 * outra combinacao e "Avancado" — inclusive uma que por acaso tenha os dois,
 * porque o administrador que mexeu nos valores nao quer ser jogado de volta.
 */
const isRecommended = computed(() => {
  const ativos = lista.value.filter(
    item => item.desktop?.enabled || item.mobile?.enabled
  );
  if (ativos.length !== RECOMMENDED_TRIGGERS.length) return false;
  return RECOMMENDED_TRIGGERS.every(preset => {
    const atual = porId.value[preset.id];
    return (
      atual?.desktop?.enabled === true &&
      atual?.desktop?.value === preset.desktop.value
    );
  });
});

const modo = computed(() => (isRecommended.value ? 'recommended' : 'advanced'));

/**
 * O aviso do gatilho composto: so tempo ligado convida quem abriu a pagina e
 * saiu para pegar um cafe. O estudo prescreve tempo E rolagem.
 */
const onlyTimeEnabled = computed(() => {
  const ativos = lista.value.filter(
    item => item.desktop?.enabled || item.mobile?.enabled
  );
  return ativos.length === 1 && ativos[0].id === 'time_on_page';
});

const setTriggers = patch => {
  Object.entries(patch).forEach(([campo, valor]) =>
    setIn('triggers', campo, valor)
  );
};

const upsertTrigger = atualizado => {
  const existentes = lista.value.filter(item => item.id !== atualizado.id);
  const ordenados = [...existentes, atualizado].sort(
    (a, b) => TRIGGER_IDS.indexOf(a.id) - TRIGGER_IDS.indexOf(b.id)
  );
  setTriggers({ triggers: ordenados });
};

const applyRecommended = () =>
  setTriggers({ triggers: RECOMMENDED_TRIGGERS.map(item => ({ ...item })) });

const linhas = computed(() =>
  TRIGGER_IDS.map(id => porId.value[id] ?? { id, desktop: {}, mobile: {} })
);

const setDefaults = patch =>
  setTriggers({ defaults: { ...defaults.value, ...patch } });

/**
 * Bloco 4.07 — o teaser no preview, com o gatilho SIMULADO.
 *
 * O texto vem da campanha vinculada (4.05); os chips sao as opcoes nomeadas da
 * inbox (`home_intents`, do schema da aparencia), que sao as MESMAS que o
 * visitante ve — nao ha um segundo campo de chips a inventar, e o schema
 * recusaria chave nova de qualquer forma.
 */
const teaserDoPreview = computed(() => {
  const campanha = teaserComposer.value?.vinculada;
  const rascunhoDaCampanha = teaserComposer.value?.rascunho;
  const texto = rascunhoDaCampanha?.message || campanha?.message || '';
  if (!texto) return null;

  return {
    // Em celular o nivel e outro, e o preview de computador mostra o do
    // computador; `aggressive` nao tem teaser — ele e o auto-open (4.20).
    level: triggers.value.approach === 'discreet' ? 'discreet' : 'bold',
    text: texto,
    senderName: campanha?.sender?.available_name ?? inbox.value?.name ?? '',
    avatarUrl: campanha?.sender?.thumbnail ?? inbox.value?.avatar_url ?? '',
    intents: draft.value.appearance?.home_intents ?? [],
  };
});

const onSave = async () => {
  try {
    await save();
    useAlert(t('INBOX_WIDGET.TRIGGERS.SAVED'));
  } catch (error) {
    useAlert(error.message || t('INBOX_WIDGET.TRIGGERS.SAVE_ERROR'));
  }
};

defineExpose({ requestLeave: guard.requestLeave });
</script>

<template>
  <div class="flex flex-col h-full min-h-0 text-n-slate-12">
    <div
      class="flex flex-col flex-1 min-h-0 gap-2 px-6 py-4 overflow-y-auto max-w-4xl"
    >
      <SettingsFieldSection
        :label="t('INBOX_WIDGET.TRIGGERS.MASTER.LABEL')"
        :help-text="t('INBOX_WIDGET.TRIGGERS.MASTER.HINT')"
      >
        <Switch
          :model-value="Boolean(triggers.enabled)"
          :aria-label="t('INBOX_WIDGET.TRIGGERS.MASTER.LABEL')"
          data-testid="triggers-enabled"
          @update:model-value="setTriggers({ enabled: $event })"
        />
      </SettingsFieldSection>

      <h3 class="text-heading-2 text-n-slate-12">
        {{ t('INBOX_WIDGET.APPROACH.TITLE') }}
      </h3>
      <SettingsFieldSection :label="t('INBOX_WIDGET.APPROACH.TITLE')">
        <ApproachSelector
          :approach="triggers.approach"
          :approach-mobile="triggers.approach_mobile"
          :degrade-on-return="triggers.degrade_on_return !== false"
          @update="setTriggers"
        />
      </SettingsFieldSection>

      <h3 class="text-heading-2 text-n-slate-12">
        {{ t('INBOX_WIDGET.TRIGGERS.SECTIONS.MODE') }}
      </h3>
      <div class="grid gap-3 py-3 sm:grid-cols-2">
        <RadioCard
          id="mode-recommended"
          :label="t('INBOX_WIDGET.TRIGGERS.MODE.RECOMMENDED.LABEL')"
          :description="t('INBOX_WIDGET.TRIGGERS.MODE.RECOMMENDED.DESCRIPTION')"
          :is-active="modo === 'recommended'"
          data-testid="mode-recommended"
          @select="applyRecommended"
        />
        <RadioCard
          id="mode-advanced"
          :label="t('INBOX_WIDGET.TRIGGERS.MODE.ADVANCED.LABEL')"
          :description="t('INBOX_WIDGET.TRIGGERS.MODE.ADVANCED.DESCRIPTION')"
          :is-active="modo === 'advanced'"
          data-testid="mode-advanced"
        />
      </div>

      <!-- `text-n-amber-12` no conteudo: o Banner pinta o texto com o tom 11
           da escala, que no tema CLARO da 4,24:1 contra o proprio fundo
           [MEDIDO no Chromium]. O tom 12 e o mesmo aviso, legivel. -->
      <Banner
        v-if="onlyTimeEnabled"
        color="amber"
        data-testid="composite-warning"
      >
        <div class="flex flex-col gap-1 text-n-amber-12">
          <span class="font-medium">
            {{ t('INBOX_WIDGET.TRIGGERS.COMPOSITE_WARNING.TITLE') }}
          </span>
          <span>{{ t('INBOX_WIDGET.TRIGGERS.COMPOSITE_WARNING.BODY') }}</span>
        </div>
      </Banner>

      <SettingsAccordion
        :title="t('INBOX_WIDGET.TRIGGERS.SECTIONS.TRIGGERS')"
        :default-open="modo === 'advanced'"
      >
        <div class="flex flex-col">
          <TriggerRow
            v-for="linha in linhas"
            :key="linha.id"
            :trigger="linha"
            @update="upsertTrigger"
          />
        </div>
      </SettingsAccordion>

      <h3 class="text-heading-2 text-n-slate-12">
        {{ t('INBOX_WIDGET.TRIGGERS.TEASER.SECTION') }}
      </h3>
      <TeaserComposer ref="teaserComposer" :inbox-id="inboxId" />

      <!-- Bloco 4.22 — o modo antigo. Fica DEPOIS do convite de propósito: a ordem da
        tela conta a precedência. O que fala com o visitante vem primeiro; o que está
        em rampa de migração vem embaixo. -->
      <LegacyCampaigns :inbox-id="inboxId" :gatilho-ativo="gatilhoLigado" />

      <div class="flex flex-col gap-3 py-3">
        <div class="flex items-center gap-3">
          <Switch
            :model-value="simulandoGatilho"
            :aria-label="t('INBOX_WIDGET.TRIGGERS.TEASER.SIMULATE')"
            data-testid="simulate-trigger"
            @update:model-value="simulandoGatilho = $event"
          />
          <span class="text-sm font-medium text-n-slate-12">
            {{ t('INBOX_WIDGET.TRIGGERS.TEASER.SIMULATE') }}
          </span>
        </div>
        <p class="text-sm text-n-slate-11">
          {{ t('INBOX_WIDGET.TRIGGERS.TEASER.SIMULATE_HINT') }}
        </p>
        <div class="w-full max-w-md">
          <Widget
            :website-name="draft.name"
            :welcome-heading="draft.welcomeTitle"
            :welcome-tagline="draft.welcomeTagline"
            :reply-time="draft.replyTime"
            :color="draft.widgetColor"
            :logo="inbox.avatar_url"
            :theme-mode="draft.appearance?.theme"
            :widget-bubble-position="draft.appearance?.position"
            :hide-bubble="draft.appearance?.hide_bubble"
            :teaser="teaserDoPreview"
            :show-teaser="simulandoGatilho"
          />
        </div>
      </div>

      <h3 class="text-heading-2 text-n-slate-12">
        {{ t('INBOX_WIDGET.TRIGGERS.SECTIONS.FREQUENCY') }}
      </h3>
      <SettingsFieldSection
        :label="t('INBOX_WIDGET.TRIGGERS.FREQUENCY.MAX_PER_SESSION')"
        :help-text="
          t('INBOX_WIDGET.TRIGGERS.FREQUENCY.MAX_PER_SESSION_HINT', {
            max: TRIGGER_LIMITS.maxPerSessionMax,
          })
        "
      >
        <Input
          type="number"
          class="w-24"
          :model-value="defaults.max_per_session ?? 1"
          :aria-label="t('INBOX_WIDGET.TRIGGERS.FREQUENCY.MAX_PER_SESSION')"
          data-testid="max-per-session"
          @update:model-value="
            setDefaults({
              max_per_session: Math.min(
                TRIGGER_LIMITS.maxPerSessionMax,
                Math.max(TRIGGER_LIMITS.maxPerSessionMin, Number($event) || 0)
              ),
            })
          "
        />
      </SettingsFieldSection>
      <SettingsFieldSection
        :label="t('INBOX_WIDGET.TRIGGERS.FREQUENCY.COOLDOWN')"
        :help-text="
          t('INBOX_WIDGET.TRIGGERS.FREQUENCY.COOLDOWN_HINT', {
            max: TRIGGER_LIMITS.cooldownMax,
          })
        "
      >
        <Input
          type="number"
          class="w-32"
          :model-value="defaults.cooldown_seconds ?? 0"
          :aria-label="t('INBOX_WIDGET.TRIGGERS.FREQUENCY.COOLDOWN')"
          data-testid="default-cooldown"
          @update:model-value="
            setDefaults({
              cooldown_seconds: Math.min(
                TRIGGER_LIMITS.cooldownMax,
                Math.max(TRIGGER_LIMITS.cooldownMin, Number($event) || 0)
              ),
            })
          "
        />
      </SettingsFieldSection>

      <template v-if="isSectionVisible('triggers.segmentation')">
        <h3 class="text-heading-2 text-n-slate-12">
          {{ t('INBOX_WIDGET.TRIGGERS.SECTIONS.AUDIENCE') }}
        </h3>
        <SegmentationField
          :audience="triggers.audience ?? {}"
          @update="setTriggers({ audience: $event })"
        />
      </template>
      <WidgetProfileEscapeLink
        v-else
        :active-profile="profileVisibility.activeProfile.value"
        :other-profile="profileVisibility.otherProfile.value"
        :showing="profileVisibility.showOtherProfile.value"
        @toggle="profileVisibility.toggleOtherProfile"
      />
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
