<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useToggle } from '@vueuse/core';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';

// Um recorte por botao (Caixa, Time ou Atendente): botao + DropdownMenu, o mesmo seletor do funil
// do Painel. O primeiro item ("Todas as caixas"...) desfaz a escolha.
const props = defineProps({
  icon: { type: String, required: true },
  label: { type: String, required: true },
  allLabel: { type: String, required: true },
  // [{ id, name, count }] — count null enquanto nao carregou
  options: { type: Array, default: () => [] },
});

const emit = defineEmits(['open']);
const selected = defineModel({ type: [Number, String, null], default: null });

const { t } = useI18n();
const [open, toggleOpen] = useToggle();

const ALL = 'all';

const buttonLabel = computed(
  () =>
    props.options.find(option => option.id === selected.value)?.name ||
    props.label
);

const menuItems = computed(() => [
  {
    action: 'pick',
    value: ALL,
    label: props.allLabel,
    isSelected: !selected.value,
  },
  ...props.options.map(option => ({
    action: 'pick',
    value: option.id,
    label: option.name,
    description:
      option.count === null
        ? ''
        : t('REPORTS_UI.FILTERS.COUNT', { n: option.count }, option.count),
    isSelected: option.id === selected.value,
  })),
]);

const toggle = () => {
  toggleOpen();
  if (open.value) emit('open');
};

const pick = ({ value }) => {
  selected.value = value === ALL ? null : value;
  toggleOpen(false);
};
</script>

<template>
  <div v-on-clickaway="() => toggleOpen(false)" class="relative">
    <!-- Pilula como as do seletor de periodo: apagada sem escolha, azul com uma. -->
    <Button
      sm
      :ghost="!selected"
      :faded="!!selected"
      :slate="!selected"
      :blue="!!selected"
      :label="buttonLabel"
      :icon="icon"
      :aria-label="label"
      :aria-expanded="open"
      class="max-w-56 rounded-full"
      @click="toggle"
    />
    <DropdownMenu
      v-if="open"
      :menu-items="menuItems"
      show-search
      :search-placeholder="t('REPORTS_UI.FILTERS.SEARCH')"
      class="mt-1 top-full ltr:left-0 rtl:right-0 w-64 max-h-80 overflow-y-auto"
      @action="pick"
    />
  </div>
</template>
