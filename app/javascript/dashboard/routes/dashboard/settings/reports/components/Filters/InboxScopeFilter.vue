<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import ActiveFilterChip from './v3/ActiveFilterChip.vue';

// Recorte por caixa de entrada — vale para a tela inteira, ao lado do periodo.
// Nao se confunde com o filtro de entidade: aqui a caixa e o corte, nao o
// assunto do relatorio. Reusa os rotulos de INBOX_REPORTS para falar a mesma
// lingua do resto do produto.
const props = defineProps({
  modelValue: {
    type: [Number, null],
    default: null,
  },
});

const emit = defineEmits(['update:modelValue', 'change']);

const { t } = useI18n();
const store = useStore();
const inboxes = useMapGetter('inboxes/getInboxes');
const showMenu = ref(false);

const options = computed(() =>
  (inboxes.value || []).map(inbox => ({ id: inbox.id, name: inbox.name }))
);

const selectedName = computed(() => {
  const selected = options.value.find(item => item.id === props.modelValue);
  return selected?.name || t('INBOX_REPORTS.ALL_INBOXES');
});

const toggleDropdown = () => {
  showMenu.value = !showMenu.value;
};

const closeDropdown = () => {
  showMenu.value = false;
};

const selectInbox = item => {
  showMenu.value = false;
  emit('update:modelValue', item.id);
  emit('change', item.id);
};

const clearInbox = () => {
  showMenu.value = false;
  emit('update:modelValue', null);
  emit('change', null);
};

onMounted(() => store.dispatch('inboxes/get'));
</script>

<template>
  <ActiveFilterChip
    :id="modelValue"
    :name="selectedName"
    type="inboxScope"
    :options="options"
    :active-filter-type="showMenu ? 'inboxScope' : ''"
    :show-menu="showMenu"
    :placeholder="$t('INBOX_REPORTS.SEARCH_INBOX')"
    enable-search
    @toggle-dropdown="toggleDropdown"
    @close-dropdown="closeDropdown"
    @add-filter="selectInbox"
    @remove-filter="clearInbox"
  />
</template>
