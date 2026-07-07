<script setup>
// Editor de `assign_team`. action_params = [team_id].
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
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
const teams = useMapGetter('teams/getTeams');

const options = computed(() =>
  teams.value.map(team => ({ id: team.id, name: team.name }))
);

const selected = computed({
  get() {
    const current = props.node.action_params?.[0];
    if (current === undefined || current === null || current === '')
      return null;
    return (
      options.value.find(opt => String(opt.id) === String(current)) || null
    );
  },
  set(value) {
    emit('update', { action_params: value ? [value.id] : [] });
  },
});
</script>

<template>
  <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.ASSIGN_TEAM.LABEL')">
    <SingleSelect
      v-model="selected"
      :options="options"
      :placeholder="t('AUTOMATION.CANVAS.CONFIG.ASSIGN_TEAM.PLACEHOLDER')"
    />
  </ConfigField>
</template>
