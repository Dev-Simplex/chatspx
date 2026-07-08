<script setup>
// Editor de `enroll_in_sequence`. action_params = [sequence_id]. Inscreve a conversa numa
// Message Sequence (drip). Não há store Vuex de sequências, então buscamos a lista sob demanda
// pelo API helper (MessageSequencesAPI.get → array de { id, name, active }) e mostramos só as
// ATIVAS (o EnrollService só inscreve em sequência ativa).
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import MessageSequencesAPI from 'dashboard/api/messageSequences';
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
const sequences = ref([]);

const options = computed(() =>
  sequences.value
    .filter(sequence => sequence.active)
    .map(sequence => ({ id: sequence.id, name: sequence.name }))
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

onMounted(async () => {
  try {
    const { data } = await MessageSequencesAPI.get();
    sequences.value = Array.isArray(data) ? data : [];
  } catch {
    sequences.value = [];
  }
});
</script>

<template>
  <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.ENROLL_SEQUENCE.LABEL')">
    <SingleSelect
      v-model="selected"
      :options="options"
      :placeholder="t('AUTOMATION.CANVAS.CONFIG.ENROLL_SEQUENCE.PLACEHOLDER')"
    />
    <p v-if="!options.length" class="mt-1 text-xs text-n-slate-10">
      {{ t('AUTOMATION.CANVAS.CONFIG.ENROLL_SEQUENCE.NO_SEQUENCES') }}
    </p>
  </ConfigField>
</template>
