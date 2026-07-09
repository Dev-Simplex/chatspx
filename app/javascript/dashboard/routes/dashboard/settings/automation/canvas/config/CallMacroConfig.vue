<script setup>
// Editor de `call_macro`. action_params = [macro_id]. Reusa a store de macros
// (`macros/getMacros` + `macros/get`) — a mesma lista do menu "Executar macro" da conversa.
import { computed, onMounted } from 'vue';
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
const macros = useMapGetter('macros/getMacros');

const options = computed(() =>
  macros.value.map(macro => ({ id: macro.id, name: macro.name }))
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

onMounted(() => {
  if (!macros.value.length) store.dispatch('macros/get');
});
</script>

<template>
  <ConfigField :label="t('AUTOMATION.CANVAS.CONFIG.CALL_MACRO.LABEL')">
    <SingleSelect
      v-model="selected"
      :options="options"
      :placeholder="t('AUTOMATION.CANVAS.CONFIG.CALL_MACRO.PLACEHOLDER')"
    />
    <p v-if="!options.length" class="mt-1 text-xs text-n-slate-10">
      {{ t('AUTOMATION.CANVAS.CONFIG.CALL_MACRO.NO_MACROS') }}
    </p>
  </ConfigField>
</template>
