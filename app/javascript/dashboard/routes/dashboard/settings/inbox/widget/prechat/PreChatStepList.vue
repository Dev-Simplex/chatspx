<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import Select from 'dashboard/components-next/select/Select.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import PreChatFieldEditor from './PreChatFieldEditor.vue';
import {
  MAX_ENABLED_FIELDS,
  MAX_STEPS,
  applyOrder,
  canAddStep,
  conditionSources,
  danglingConditions,
  disableField,
  enableField,
  enabledCount,
  groupByStep,
  isAtFieldLimit,
  stepCount,
  updateField,
} from './preChatModel';

/**
 * As etapas do construtor, o teto de 8 e a ordem por arrastar.
 *
 * O TETO APARECE SEMPRE, e não só quando estoura (aceite 21): o contador
 * `5/8` fica visível o tempo todo e, no limite, o botão de adicionar
 * desabilita **com o motivo escrito ao lado** — não em `title`, não em tooltip.
 * Botão cinza sem explicação é a forma mais rápida de fazer alguém achar que a
 * tela quebrou.
 */
const props = defineProps({
  fields: { type: Array, default: () => [] },
  disabled: { type: Boolean, default: false },
  showSteps: { type: Boolean, default: true },
});

const emit = defineEmits(['update:fields']);

const { t } = useI18n();

const groups = computed(() =>
  props.showSteps
    ? groupByStep(props.fields)
    : [{ step: 1, fields: groupByStep(props.fields).flatMap(g => g.fields) }]
);

const usedCount = computed(() => enabledCount(props.fields));
const atLimit = computed(() => isAtFieldLimit(props.fields));
const stepsUsed = computed(() => stepCount(props.fields));
const canGrowSteps = computed(() => canAddStep(props.fields));

const counterLabel = computed(() =>
  t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.FIELD_COUNTER', {
    count: usedCount.value,
    max: MAX_ENABLED_FIELDS,
  })
);

const availableFields = computed(() =>
  props.fields.filter(field => !field.enabled)
);

const addOptions = computed(() =>
  availableFields.value.map(field => ({
    value: field.name,
    label: field.label || field.name,
  }))
);

const broken = computed(() => danglingConditions(props.fields));

const sourcesFor = step => conditionSources(props.fields, step);

const onAdd = (name, step) => {
  if (!name || atLimit.value) return;
  emit('update:fields', enableField(props.fields, name, step));
};

const onRemove = name =>
  emit('update:fields', disableField(props.fields, name));

const onFieldUpdate = (name, patch) =>
  emit('update:fields', updateField(props.fields, name, patch));

const onReorder = (step, ordered) =>
  emit(
    'update:fields',
    applyOrder(
      props.fields,
      step,
      ordered.map(field => field.name)
    )
  );

const onAddStep = () => {
  if (!canGrowSteps.value || atLimit.value) return;
  const next = availableFields.value[0];
  if (!next) return;
  emit(
    'update:fields',
    enableField(props.fields, next.name, stepsUsed.value + 1)
  );
};
</script>

<template>
  <div class="flex flex-col gap-6">
    <div class="flex flex-wrap items-center justify-between gap-2">
      <span
        class="text-sm font-medium text-n-slate-12"
        data-testid="field-counter"
      >
        {{ counterLabel }}
      </span>
      <p
        v-if="atLimit"
        class="text-sm text-n-amber-11"
        data-testid="field-limit-reason"
      >
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.AT_LIMIT') }}
      </p>
    </div>

    <p
      v-if="broken.length"
      class="text-sm text-n-ruby-11"
      data-testid="dangling-conditions"
    >
      {{
        t('INBOX_WIDGET.PRE_CHAT_FORM.CONDITION.DANGLING', {
          fields: broken.map(item => item.name).join(', '),
        })
      }}
    </p>

    <section
      v-for="group in groups"
      :key="group.step"
      class="flex flex-col gap-3"
      data-testid="step-section"
    >
      <h4 v-if="showSteps" class="text-sm font-medium text-n-slate-12">
        {{
          t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.STEP_TITLE', {
            step: group.step,
          })
        }}
      </h4>

      <p
        v-if="!group.fields.length"
        class="text-sm text-n-slate-11"
        data-testid="empty-step"
      >
        {{ t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.EMPTY_STEP') }}
      </p>

      <Draggable
        v-else
        :model-value="group.fields"
        item-key="name"
        :disabled="disabled"
        class="flex flex-col gap-3"
        @update:model-value="onReorder(group.step, $event)"
      >
        <template #item="{ element }">
          <PreChatFieldEditor
            :field="element"
            :sources="sourcesFor(group.step)"
            :disabled="disabled"
            @update="onFieldUpdate(element.name, $event)"
            @remove="onRemove(element.name)"
          />
        </template>
      </Draggable>

      <div class="flex flex-wrap items-center gap-2">
        <Select
          v-if="addOptions.length && !atLimit"
          model-value=""
          :data-testid="`add-field-step-${group.step}`"
          :options="addOptions"
          :placeholder="t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.ADD_FIELD')"
          :disabled="disabled"
          @update:model-value="onAdd($event, group.step)"
        />
        <NextButton
          v-else
          faded
          slate
          sm
          disabled
          :data-testid="`add-field-disabled-${group.step}`"
          :label="t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.ADD_FIELD')"
        />
        <span
          v-if="!addOptions.length && !atLimit"
          class="text-xs text-n-slate-11"
          data-testid="no-field-available"
        >
          {{ t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.NO_FIELD_AVAILABLE') }}
        </span>
      </div>
    </section>

    <div v-if="showSteps" class="flex items-center gap-3">
      <NextButton
        faded
        slate
        sm
        data-testid="add-step"
        :disabled="disabled || !canGrowSteps || atLimit || !addOptions.length"
        :label="t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.ADD_STEP')"
        @click="onAddStep"
      />
      <span class="text-xs text-n-slate-11" data-testid="step-counter">
        {{
          t('INBOX_WIDGET.PRE_CHAT_FORM.BUILDER.STEP_COUNTER', {
            count: stepsUsed,
            max: MAX_STEPS,
          })
        }}
      </span>
    </div>
  </div>
</template>
