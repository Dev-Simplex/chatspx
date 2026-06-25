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
//   Linha 1 (primário, sempre): Minhas, Todas
//   Linha 2 (filas, dinâmicas): Aguardando atendimento, IA
// As filas só existem no array `items` quando têm conteúdo (count > 0) — a
// filtragem já acontece em ChatList.vue. Aqui só reordenamos e separamos os
// grupos. No modo clássico (sem filas) só sobra a linha 1.
const QUEUE_KEYS = [
  wootConstants.ASSIGNEE_TYPE.AWAITING,
  wootConstants.ASSIGNEE_TYPE.AI,
];

const isQueueKey = key => QUEUE_KEYS.includes(key);

// Reordena para que o grupo primário (Minhas, Todas, e quaisquer outras abas
// não-fila como "Não atribuídas" no modo clássico) venha antes do grupo de
// filas (Aguardando atendimento, IA), preservando a ordem relativa dentro de
// cada grupo. O active/teclado seguem ESTE array reordenado (mesma fonte do
// findIndex e do :index), então a seleção continua correta.
const orderedItems = computed(() => {
  const primary = props.items.filter(item => !isQueueKey(item.key));
  const queue = props.items.filter(item => isQueueKey(item.key));
  return [...primary, ...queue];
});

// Índice do primeiro item de fila no array reordenado — usado para inserir o
// "quebra-linha" flex logo antes dele. -1 quando não há filas (1 linha só).
const queueStartIndex = computed(() =>
  orderedItems.value.findIndex(item => isQueueKey(item.key))
);

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
    <template v-for="(item, index) in orderedItems" :key="item.key">
      <!-- Quebra-linha flex: força o grupo de filas (Aguardando atendimento,
           IA) para a 2ª linha, deixando o grupo primário (Minhas, Todas) na 1ª.
           Renderizado só quando há filas; não é uma tab (sem :index, sem
           button) então não interfere no active nem na navegação por teclado. -->
      <li
        v-if="index === queueStartIndex && queueStartIndex > 0"
        class="wa-tab-row-break"
        aria-hidden="true"
        role="presentation"
      />
      <woot-tabs-item
        class="text-sm [&_a]:font-medium"
        :class="{ 'tab-alert animate-jump-in': item.variant === 'alert' }"
        :index="index"
        :name="item.name"
        :count="item.count"
        :icon="item.icon"
        animated-count
        is-compact
      />
    </template>
  </woot-tabs>
</template>

<style lang="scss" scoped>
// Quebra-linha flex do layout em 2 grupos (chat-list). Ocupa 100% da largura
// disponível dentro do ul (flex-wrap:wrap), empurrando o grupo de filas para a
// linha de baixo. height:0 + margin:0 evita criar uma "linha fantasma" alta.
.wa-tab-row-break {
  flex-basis: 100%;
  width: 100%;
  height: 0;
  margin: 0;
  padding: 0;
  // Garante left-pack de ambos os grupos: o ul mantém os items à esquerda; o
  // break apenas reseta a linha. (basis 100% > basis dos chips ⇒ ele "ganha" a
  // linha sozinho e os próximos quebram.)
  pointer-events: none;
}

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
