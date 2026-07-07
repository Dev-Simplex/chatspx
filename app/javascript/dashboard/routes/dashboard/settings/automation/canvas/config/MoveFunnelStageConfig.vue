<script setup>
// Editor de `move_funnel_stage`. action_params = [{ funnel_id, stage_id }].
// Cascata funil → etapa reusando a store do Kanban (a MESMA fonte do board): `kanban/
// getFunnels` lista os funis e `kanban/fetchFunnelStages` carrega as etapas do funil
// escolhido (o serializer do funil não embute stages, então buscamos sob demanda). O
// funnel_id É persistido — em runtime a conversa pode estar em vários funis, então o
// Flows::ActionService precisa saber em qual mover.
import { computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import SingleSelect from 'dashboard/components-next/filter/inputs/SingleSelect.vue';
import ConfigField from './ConfigField.vue';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['update']);

const { t } = useI18n();
const store = useStore();
const funnels = useMapGetter('kanban/getFunnels');
const stagesFor = useMapGetter('kanban/getFunnelStages');

const config = computed(() => {
  const params = props.node.action_params;
  return Array.isArray(params) && params[0] ? params[0] : {};
});

const funnelOptions = computed(() =>
  funnels.value.map(funnel => ({ id: funnel.id, name: funnel.name }))
);

const stageOptions = computed(() => {
  const funnelId = config.value.funnel_id;
  if (!funnelId) return [];
  return stagesFor.value(funnelId).map(stage => ({
    id: stage.id,
    name: stage.name,
  }));
});

const funnelModel = computed({
  get() {
    return (
      funnelOptions.value.find(
        opt => String(opt.id) === String(config.value.funnel_id)
      ) || null
    );
  },
  set(value) {
    const funnelId = value ? value.id : null;
    // Trocar o funil zera a etapa (as etapas são específicas de cada funil).
    emit('update', {
      action_params: [{ funnel_id: funnelId, stage_id: null }],
    });
    if (funnelId) store.dispatch('kanban/fetchFunnelStages', funnelId);
  },
});

const stageModel = computed({
  get() {
    return (
      stageOptions.value.find(
        opt => String(opt.id) === String(config.value.stage_id)
      ) || null
    );
  },
  set(value) {
    emit('update', {
      action_params: [{ ...config.value, stage_id: value ? value.id : null }],
    });
  },
});

const ensureStages = () => {
  if (config.value.funnel_id) {
    store.dispatch('kanban/fetchFunnelStages', config.value.funnel_id);
  }
};

onMounted(() => {
  store.dispatch('kanban/fetchFunnels');
  ensureStages();
});
watch(() => props.node.id, ensureStages);
</script>

<template>
  <div class="flex flex-col gap-4">
    <p
      v-if="!funnelOptions.length"
      class="p-3 text-sm rounded-lg text-n-slate-11 bg-n-alpha-1"
    >
      {{ t('AUTOMATION.CANVAS.CONFIG.MOVE_FUNNEL_STAGE.NO_FUNNELS') }}
    </p>
    <template v-else>
      <ConfigField
        :label="t('AUTOMATION.CANVAS.CONFIG.MOVE_FUNNEL_STAGE.FUNNEL_LABEL')"
      >
        <SingleSelect
          v-model="funnelModel"
          :options="funnelOptions"
          :placeholder="
            t('AUTOMATION.CANVAS.CONFIG.MOVE_FUNNEL_STAGE.FUNNEL_PLACEHOLDER')
          "
        />
      </ConfigField>

      <ConfigField
        v-if="config.funnel_id"
        :label="t('AUTOMATION.CANVAS.CONFIG.MOVE_FUNNEL_STAGE.STAGE_LABEL')"
      >
        <SingleSelect
          v-model="stageModel"
          :options="stageOptions"
          :placeholder="
            t('AUTOMATION.CANVAS.CONFIG.MOVE_FUNNEL_STAGE.STAGE_PLACEHOLDER')
          "
        />
      </ConfigField>
    </template>
  </div>
</template>
