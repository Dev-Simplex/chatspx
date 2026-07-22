<script setup>
import { computed } from 'vue';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import wootConstants from 'dashboard/constants/globals';

const props = defineProps({
  items: {
    type: Array,
    default: () => [],
  },
  activeTab: {
    type: String,
    default: wootConstants.ASSIGNEE_TYPE.ME,
  },
});

const emit = defineEmits(['chatTabChange']);

// Layout em 2 linhas agrupadas (modo IA / gate ON), escopado ao chat-list:
//   Linha 1 (primário, sempre): Minhas, IA, Todas
//   Linha 2 (filas, dinâmicas): Aguardando atendimento, Aguardando encerramento
// As filas só existem no array `items` quando têm conteúdo (count > 0) — a
// filtragem já acontece em ChatList.vue. Aqui só reordenamos e separamos os
// grupos. No modo clássico (sem filas) só sobra a linha 1.
const QUEUE_KEYS = [
  wootConstants.ASSIGNEE_TYPE.AWAITING,
  wootConstants.ASSIGNEE_TYPE.PENDING_CLOSURE,
];

const isQueueKey = key => QUEUE_KEYS.includes(key);

// Reordena para que o grupo primário (Minhas, Todas, e quaisquer outras abas
// não-fila como "Não atribuídas" no modo clássico) venha antes do grupo de
// filas (Aguardando atendimento, IA), preservando a ordem relativa dentro de
// cada grupo. O active/teclado seguem ESTE array reordenado (mesma fonte do
// findIndex e do :index), então a seleção continua correta.
const orderedItems = computed(() => {
  const queue = props.items.filter(item => isQueueKey(item.key));
  // Dinâmico: só agrupa as filas ao final (linha 2) quando há 2+ filas
  // (Aguardando atendimento + IA). Com UMA fila só (ex.: Aguardando sem IA),
  // mantém a ordem natural — assim ela "sobe" para a linha de cima quando há
  // espaço, em vez de ficar presa sozinha na 2ª linha.
  if (queue.length < 2) {
    return [...props.items];
  }
  const primary = props.items.filter(item => !isQueueKey(item.key));
  return [...primary, ...queue];
});

const activeTabIndex = computed(() => {
  return orderedItems.value.findIndex(item => item.key === props.activeTab);
});

const onTabChange = selectedTabIndex => {
  if (selectedTabIndex >= 0 && selectedTabIndex < orderedItems.value.length) {
    const selectedItem = orderedItems.value[selectedTabIndex];
    if (selectedItem.key !== props.activeTab) {
      emit('chatTabChange', selectedItem.key);
    }
  }
};

const keyboardEvents = {
  'Alt+KeyN': {
    action: () => {
      if (props.activeTab === wootConstants.ASSIGNEE_TYPE.ALL) {
        onTabChange(0);
      } else {
        const nextIndex =
          (activeTabIndex.value + 1) % orderedItems.value.length;
        onTabChange(nextIndex);
      }
    },
  },
};

useKeyboardEvents(keyboardEvents);
</script>

<template>
  <woot-tabs
    :index="activeTabIndex"
    class="w-full py-0 conversation-list-tabs chat-list-tabs [&_ul]:flex-wrap [&_ul]:items-center [&_ul]:gap-2 [&_ul]:py-1.5 [&_ul]:overflow-x-visible"
    @change="onTabChange"
  >
    <!-- Quebra natural (flex-wrap): com a ordem reordenada (primário antes das
         filas), o "Aguardando atendimento" (rótulo longo) só desce para a 2ª
         linha quando não cabe; com abas curtas (sem ele), tudo fica em 1 linha. -->
    <woot-tabs-item
      v-for="(item, index) in orderedItems"
      :key="item.key"
      class="text-sm [&_a]:font-medium"
      :class="{ 'tab-alert animate-jump-in': item.variant === 'alert' }"
      :index="index"
      :name="item.name"
      :count="item.count"
      :icon="item.icon"
      animated-count
      is-compact
    />
  </woot-tabs>
</template>

<style lang="scss" scoped>
// Alert variant (conditional "Unassigned" tab — DC-6). Tokens only, so dark
// mode comes for free. `!important` is required to win over the global
// `.wa-tab-item` skin rules (_wa-skin.scss). Written as plain declarations
// (not `@apply !...`) because the `!` prefix is parsed as a Sass flag inside
// a scss block and breaks the build.
.tab-alert :deep(.wa-tab-item) {
  color: rgb(var(--ruby-11)) !important;
}

.tab-alert :deep(.wa-tab-item:hover) {
  color: rgb(var(--ruby-12)) !important;
}

.tab-alert :deep(.wa-tab-item__badge) {
  background-color: rgb(var(--ruby-9) / 0.2) !important;
  color: rgb(var(--ruby-11)) !important;
}
</style>
