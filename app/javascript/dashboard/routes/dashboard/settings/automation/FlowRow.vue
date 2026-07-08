<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import ToggleSwitch from 'dashboard/components-next/switch/Switch.vue';
import { BaseTableRow, BaseTableCell } from 'dashboard/components-next/table';

const props = defineProps({
  flow: {
    type: Object,
    required: true,
  },
  loading: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['toggle', 'edit', 'delete']);

const { t } = useI18n();

// A coluna "Tipo" deriva SÓ do enum `trigger_type` do Flow (manual/conversation_event/
// keyword/schedule/external_webhook) — cada um mapeia para um rótulo i18n estático. Valor
// desconhecido cai no genérico, nunca vaza a string crua do backend.
const triggerTypeLabel = computed(() => {
  switch (props.flow.trigger_type) {
    case 'manual':
      return t('AUTOMATION.TRIGGER_TYPES.MANUAL');
    case 'conversation_event':
      return t('AUTOMATION.TRIGGER_TYPES.EVENT');
    case 'keyword':
      return t('AUTOMATION.TRIGGER_TYPES.KEYWORD');
    case 'schedule':
      return t('AUTOMATION.TRIGGER_TYPES.SCHEDULE');
    case 'external_webhook':
      return t('AUTOMATION.TRIGGER_TYPES.WEBHOOK');
    default:
      return t('AUTOMATION.TRIGGER_TYPES.UNKNOWN');
  }
});

// Espelha AutomationRuleRow: o setter recebe o valor NOVO desejado pelo switch e emite o
// estado ATUAL (`status`) — o pai confirma antes de aplicar, sem tocar o registro até lá.
const flowActive = computed({
  get: () => props.flow.active,
  set: active => {
    const { id, name } = props.flow;
    emit('toggle', {
      id,
      name,
      status: !active,
    });
  },
});
</script>

<template>
  <BaseTableRow :item="flow">
    <template #default>
      <BaseTableCell class="max-w-0 w-full">
        <div class="flex items-center gap-2 min-w-0">
          <span class="text-body-main text-n-slate-12 truncate">
            {{ flow.name }}
          </span>
          <template v-if="flow.description">
            <div class="w-px h-3 rounded-lg bg-n-weak flex-shrink-0" />
            <span class="text-body-main text-n-slate-11 truncate">
              {{ flow.description }}
            </span>
          </template>
        </div>
      </BaseTableCell>

      <BaseTableCell>
        <span
          class="inline-flex items-center px-2 py-0.5 rounded-md text-xs font-medium whitespace-nowrap bg-n-slate-3 text-n-slate-12"
        >
          {{ triggerTypeLabel }}
        </span>
      </BaseTableCell>

      <BaseTableCell>
        <ToggleSwitch v-model="flowActive" />
      </BaseTableCell>

      <BaseTableCell align="end">
        <div class="flex gap-3 justify-end flex-shrink-0">
          <Button
            v-tooltip.top="$t('AUTOMATION.FORM.EDIT')"
            icon="i-woot-edit-pen"
            slate
            sm
            :is-loading="loading"
            @click="$emit('edit', flow)"
          />
          <Button
            v-tooltip.top="$t('AUTOMATION.FORM.DELETE')"
            :is-loading="loading"
            icon="i-woot-bin"
            slate
            sm
            class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
            @click="$emit('delete', flow)"
          />
        </div>
      </BaseTableCell>
    </template>
  </BaseTableRow>
</template>
