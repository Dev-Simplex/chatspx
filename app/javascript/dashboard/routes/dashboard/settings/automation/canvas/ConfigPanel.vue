<script setup>
// Shell do painel de configuração à direita (~350px). Header com ícone + nome do tipo do
// nó (do nodeCatalog, via i18n) e botão fechar; corpo rola e renderiza o NodeConfigPanel.
// Aparece só quando há um nó selecionado (o FlowCanvasView controla a montagem).
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import NodeConfigPanel from './NodeConfigPanel.vue';
import {
  FAMILIES,
  familyForNode,
  iconForNode,
  labelForNode,
} from './nodeCatalog';

const props = defineProps({
  node: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['close', 'update']);

const { t } = useI18n();

const familyMeta = computed(
  () => FAMILIES[familyForNode(props.node)] || FAMILIES.action
);
const icon = computed(() => iconForNode(props.node));
const title = computed(() => t(labelForNode(props.node)));
const familyLabel = computed(() => t(familyMeta.value.labelKey));

const onUpdate = patch => emit('update', patch);
</script>

<template>
  <aside
    class="flex flex-col w-[350px] shrink-0 h-full border-l border-n-weak bg-n-solid-1"
    data-testid="flow-config-panel"
  >
    <header
      class="flex items-center gap-3 px-4 border-b h-14 shrink-0 border-n-weak"
    >
      <span
        class="grid rounded-lg size-8 place-items-center bg-n-alpha-1"
        :style="{ color: familyMeta.color }"
      >
        <span :class="icon" />
      </span>
      <div class="flex flex-col min-w-0">
        <span
          class="text-[10px] font-bold tracking-wider uppercase"
          :style="{ color: familyMeta.color }"
        >
          {{ familyLabel }}
        </span>
        <span class="text-sm font-semibold truncate text-n-slate-12">
          {{ title }}
        </span>
      </div>
      <button
        class="ml-auto text-n-slate-11 hover:text-n-slate-12 shrink-0"
        :aria-label="t('AUTOMATION.CANVAS.CONFIG.CLOSE')"
        data-testid="config-panel-close"
        @click="emit('close')"
      >
        <span class="i-lucide-x" />
      </button>
    </header>

    <div class="flex-1 min-h-0 p-4 overflow-y-auto">
      <NodeConfigPanel :node="node" @update="onUpdate" />
    </div>
  </aside>
</template>
