<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import SettingsToggleSection from 'dashboard/components-next/Settings/SettingsToggleSection.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import { useInboxWidgetConfig } from '../composables/useInboxWidgetConfig';
import { useUnsavedChangesGuard } from '../composables/useUnsavedChangesGuard';
import WidgetSaveBar from '../WidgetSaveBar.vue';
import WidgetUnsavedChangesDialog from '../WidgetUnsavedChangesDialog.vue';
import PreChatStepList from './PreChatStepList.vue';
import { MODES, resolveMode, toBuilder, toSimple } from './preChatModel';

/**
 * Tela 3 — pré-chat (bloco 3.14).
 *
 * Três modos, e o terceiro merece nota porque é onde é fácil errar: no modo
 * **Fluxo** esta tela **não escolhe qual fluxo**. Quem resolve isso é o motor
 * de Automações, pelo gatilho `widget_prechat` do próprio fluxo — é o que
 * permite dois fluxos ativos atenderem URLs diferentes. Guardar um `flow_id`
 * aqui criaria uma segunda fonte de verdade para a mesma pergunta.
 */
const props = defineProps({
  inboxId: { type: [Number, String], required: true },
});

const { t } = useI18n();
const router = useRouter();

const {
  draft,
  isDirty,
  dirtyCount,
  isSaving,
  isLoading,
  saveError,
  set,
  discard,
  save,
} = useInboxWidgetConfig(() => props.inboxId);

const { isPromptOpen, confirmLeave, cancelLeave } = useUnsavedChangesGuard({
  isDirty,
  onDiscard: discard,
});

const migration = ref(null);
const migrationDialog = ref(null);

// O `Dialog` de `components-next` abre por metodo no ref, nao por prop — e o
// mesmo padrao do `WidgetUnsavedChangesDialog` da trilha TELAS.
watch(migration, value =>
  value ? migrationDialog.value?.open() : migrationDialog.value?.close()
);

const options = computed(() => draft.value.preChat ?? {});
const fields = computed(() => options.value.pre_chat_fields ?? []);
const mode = computed(() => resolveMode(options.value));

const setOptions = change => set('preChat', { ...options.value, ...change });

const onFieldsUpdate = next => setOptions({ pre_chat_fields: next });

/**
 * A troca de modo grava a INTENÇÃO (`mode`) e ajusta o conteúdo — nas duas
 * direções sem perder campo (§B.4.1). A volta para Simples é a única que custa
 * algo, e por isso ela pergunta antes, listando nominalmente o que sai.
 */
const applyMode = nextMode => {
  if (nextMode === mode.value) return;

  if (nextMode === 'builder') {
    setOptions({ mode: 'builder', pre_chat_fields: toBuilder(fields.value) });
    return;
  }

  if (nextMode === 'flow') {
    setOptions({ mode: 'flow' });
    return;
  }

  const preview = toSimple(fields.value);
  if (preview.ignoredSteps.length || preview.droppedConditions.length) {
    migration.value = preview;
    return;
  }
  setOptions({ mode: 'simple', pre_chat_fields: preview.fields });
};

const confirmMigration = () => {
  setOptions({ mode: 'simple', pre_chat_fields: migration.value.fields });
  migration.value = null;
};

/**
 * O texto diz o que a volta custa, com os numeros: quais etapas somem e quais
 * condicionais deixam de valer. "Voce vai perder configuracao" sem dizer qual
 * e o mesmo tipo de opacidade que esta tela existe para corrigir.
 */
const migrationDescription = computed(() =>
  migration.value
    ? t('INBOX_WIDGET.PRE_CHAT_FORM.MIGRATION.DESCRIPTION', {
        steps: migration.value.ignoredSteps.join(', ') || '—',
        fields: migration.value.droppedConditions.join(', ') || '—',
      })
    : ''
);

const modeCards = computed(() =>
  MODES.map(id => ({
    id,
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    label: t(`INBOX_WIDGET.PRE_CHAT_FORM.MODES.${id.toUpperCase()}.LABEL`),
    // eslint-disable-next-line @intlify/vue-i18n/no-dynamic-keys
    description: t(
      `INBOX_WIDGET.PRE_CHAT_FORM.MODES.${id.toUpperCase()}.DESCRIPTION`
    ),
  }))
);

const goToAutomations = () =>
  router.push({ name: 'automation_list' }).catch(() => {});
</script>

<template>
  <div class="flex flex-col gap-8">
    <SettingsToggleSection
      :model-value="Boolean(draft.preChatEnabled)"
      :header="t('INBOX_MGMT.PRE_CHAT_FORM.ENABLE.LABEL')"
      :description="t('INBOX_MGMT.PRE_CHAT_FORM.DESCRIPTION')"
      @update:model-value="set('preChatEnabled', $event)"
    />

    <template v-if="draft.preChatEnabled">
      <div class="flex flex-col gap-3">
        <span class="text-sm font-medium text-n-slate-12">
          {{ t('INBOX_WIDGET.PRE_CHAT_FORM.MODES.TITLE') }}
        </span>
        <div class="grid grid-cols-1 gap-3 lg:grid-cols-3">
          <RadioCard
            v-for="card in modeCards"
            :id="card.id"
            :key="card.id"
            :data-testid="`mode-${card.id}`"
            :label="card.label"
            :description="card.description"
            :is-active="mode === card.id"
            @select="applyMode(card.id)"
          />
        </div>
      </div>

      <Input
        :model-value="options.pre_chat_message ?? ''"
        data-testid="pre-chat-message"
        :label="t('INBOX_WIDGET.PRE_CHAT_FORM.MESSAGE')"
        @update:model-value="setOptions({ pre_chat_message: $event })"
      />

      <div
        v-if="mode === 'flow'"
        class="flex flex-col gap-3 p-4 rounded-xl bg-n-alpha-1"
        data-testid="flow-mode-card"
      >
        <p class="text-sm text-n-slate-12">
          {{ t('INBOX_WIDGET.PRE_CHAT_FORM.FLOW.EXPLAINER') }}
        </p>
        <p class="text-sm text-n-slate-11">
          {{ t('INBOX_WIDGET.PRE_CHAT_FORM.FLOW.WHERE_TARGET_LIVES') }}
        </p>
        <NextButton
          faded
          slate
          sm
          class="w-fit"
          data-testid="flow-link"
          :label="t('INBOX_WIDGET.PRE_CHAT_FORM.FLOW.OPEN_AUTOMATIONS')"
          @click="goToAutomations"
        />
      </div>

      <PreChatStepList
        v-else
        :fields="fields"
        :disabled="isLoading"
        :show-steps="mode === 'builder'"
        @update:fields="onFieldsUpdate"
      />
    </template>

    <WidgetSaveBar
      :dirty-count="dirtyCount"
      :is-saving="isSaving"
      :error-message="saveError"
      @save="save"
      @discard="discard"
    />

    <WidgetUnsavedChangesDialog
      :open="isPromptOpen"
      @confirm="confirmLeave"
      @cancel="cancelLeave"
    />

    <Dialog
      ref="migrationDialog"
      type="alert"
      width="md"
      :title="t('INBOX_WIDGET.PRE_CHAT_FORM.MIGRATION.TITLE')"
      :description="migrationDescription"
      :confirm-button-label="t('INBOX_WIDGET.PRE_CHAT_FORM.MIGRATION.CONFIRM')"
      :cancel-button-label="t('INBOX_WIDGET.PRE_CHAT_FORM.MIGRATION.CANCEL')"
      data-testid="migration-dialog"
      @confirm="confirmMigration"
      @close="migration = null"
    />
  </div>
</template>
