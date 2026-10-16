<script setup>
import { computed } from 'vue';
import ReportScopeFilters from 'dashboard/components-next/reports/ui/ReportScopeFilters.vue';

// Recorte por caixa de entrada — vale para a tela inteira, ao lado do periodo. E o botao Caixa do
// ReportScopeFilters (com quantas conversas cada uma recebeu no periodo), com a mesma interface de
// antes: v-model com o id da caixa (ou null) e o evento change.
const props = defineProps({
  modelValue: {
    type: [Number, null],
    default: null,
  },
  // { since, until } para as contagens; sem ele (telas ao vivo) a lista vem sem numero
  period: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['update:modelValue', 'change']);

const selection = computed({
  get: () => ({ inbox: props.modelValue }),
  set: value => {
    emit('update:modelValue', value.inbox);
    emit('change', value.inbox);
  },
});
</script>

<template>
  <ReportScopeFilters
    v-model="selection"
    :groups="['inbox']"
    :period="period"
  />
</template>
