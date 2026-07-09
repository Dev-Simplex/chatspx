<script setup>
// Galeria de MODELOS (Fase 3.3): overlay que lista fluxos prontos (flowTemplates.js) para o
// usuário começar já montado. Segue o padrão de overlay do canvas (SimulationOverlay/LogsPanel):
// `fixed inset-0 z-50`, backdrop que fecha, montado via v-if no pai (Index.vue) que escuta
// `close`/`select`. Escolher um card → emite `select(template)`; o pai navega para o canvas
// semeado (automation_canvas_new?templateKey=...). "Começar do zero" → emite `select(null)`.
//
// Tokens n-* (light/dark-aware) como o resto do canvas. As cores de família saem do nodeCatalog
// (FAMILIES[x].color) inline — mesmo tratamento da paleta do FlowCanvasView.
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { FLOW_TEMPLATES } from './canvas/flowTemplates';
import {
  FAMILIES,
  familyForNode,
  iconForNode,
  labelForNode,
} from './canvas/nodeCatalog';

const emit = defineEmits(['close', 'select']);

const { t } = useI18n();

const searchQuery = ref('');
const activeFilter = ref('all');

const FILTERS = [
  { id: 'all', labelKey: 'AUTOMATION.TEMPLATES.FILTERS.ALL' },
  { id: 'whatsapp', labelKey: 'AUTOMATION.TEMPLATES.FILTERS.WHATSAPP' },
  { id: 'ai', labelKey: 'AUTOMATION.TEMPLATES.FILTERS.AI' },
];

const familyMeta = family => FAMILIES[family] || FAMILIES.action;

// Um modelo tem IA se qualquer nó pertence à família 'ai' (ex.: ai_classify).
const templateHasAi = template =>
  (template.definition?.nodes || []).some(node => familyForNode(node) === 'ai');

// Blocos da MINIATURA: percorre os nós na ordem autorada, colapsando repetidos consecutivos
// (as rotas irmãs de um router viram um bloco só). Cada bloco carrega ícone + cor da família +
// rótulo (resolvido do nodeCatalog). Espelha como o canvas nomeia/colore cada nó.
const previewBlocks = template => {
  const nodes = template.definition?.nodes || [];
  const blocks = [];
  let prevSig = null;
  nodes.forEach(node => {
    const sig = `${node.type}:${node.action_name || ''}`;
    if (sig === prevSig) return;
    prevSig = sig;
    const meta = familyMeta(familyForNode(node));
    blocks.push({
      id: node.id,
      icon: iconForNode(node),
      color: meta.color,
      label: t(labelForNode(node)),
    });
  });
  return blocks.slice(0, 6);
};

// Chips de família (únicas) presentes no modelo — dá a "leitura" das capacidades do fluxo.
const familyChips = template => {
  const seen = new Set();
  const chips = [];
  (template.definition?.nodes || []).forEach(node => {
    const family = familyForNode(node);
    if (seen.has(family)) return;
    seen.add(family);
    const meta = familyMeta(family);
    chips.push({ family, color: meta.color, label: t(meta.labelKey) });
  });
  return chips;
};

const badgeLabel = badge =>
  badge === 'official'
    ? t('AUTOMATION.TEMPLATES.BADGE.OFFICIAL')
    : t('AUTOMATION.TEMPLATES.BADGE.POPULAR');

const filteredTemplates = computed(() => {
  const query = searchQuery.value.trim().toLowerCase();
  return FLOW_TEMPLATES.filter(template => {
    if (activeFilter.value === 'whatsapp' && !template.whatsapp) return false;
    if (activeFilter.value === 'ai' && !templateHasAi(template)) return false;
    if (!query) return true;
    const haystack = [
      t(template.nameKey),
      t(template.descriptionKey),
      t(`AUTOMATION.TEMPLATES.CATEGORIES.${template.category.toUpperCase()}`),
    ]
      .join(' ')
      .toLowerCase();
    return haystack.includes(query);
  });
});

const onSelect = template => emit('select', template);
const onStartBlank = () => emit('select', null);
const onClose = () => emit('close');

// Esc fecha o overlay (UX de modal). Registrado/limpo no ciclo de vida do componente.
const onKeydown = event => {
  if (event.key === 'Escape') onClose();
};
onMounted(() => window.addEventListener('keydown', onKeydown));
onBeforeUnmount(() => window.removeEventListener('keydown', onKeydown));
</script>

<template>
  <div
    class="fixed inset-0 z-50 flex items-center justify-center p-4"
    data-testid="flow-templates-gallery"
  >
    <div
      class="absolute inset-0 bg-n-alpha-black2 backdrop-blur-[2px]"
      @click="onClose"
    />

    <div
      class="relative z-10 flex flex-col w-full h-full overflow-hidden border shadow-xl max-w-5xl max-h-[88vh] rounded-xl border-n-weak bg-n-solid-1"
    >
      <header
        class="flex items-center gap-3 px-5 border-b h-14 shrink-0 border-n-weak"
      >
        <span
          class="grid rounded-lg size-8 place-items-center bg-n-alpha-1 text-n-brand"
        >
          <span class="i-lucide-layout-grid" />
        </span>
        <div class="flex flex-col min-w-0">
          <span class="text-sm font-semibold truncate text-n-slate-12">
            {{ t('AUTOMATION.TEMPLATES.TITLE') }}
          </span>
          <span class="text-xs truncate text-n-slate-11">
            {{ t('AUTOMATION.TEMPLATES.SUBTITLE') }}
          </span>
        </div>
        <button
          type="button"
          class="inline-flex items-center gap-1.5 px-3 py-1.5 ml-auto text-sm font-medium rounded-lg shrink-0 text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
          data-testid="templates-start-blank"
          @click="onStartBlank"
        >
          <span class="i-lucide-plus" />
          {{ t('AUTOMATION.TEMPLATES.START_BLANK') }}
        </button>
        <button
          type="button"
          class="shrink-0 text-n-slate-11 hover:text-n-slate-12"
          :aria-label="t('AUTOMATION.TEMPLATES.CLOSE')"
          data-testid="templates-close"
          @click="onClose"
        >
          <span class="i-lucide-x" />
        </button>
      </header>

      <div
        class="flex flex-wrap items-center gap-2 px-5 py-3 border-b shrink-0 border-n-weak"
      >
        <div
          class="flex items-center flex-1 min-w-[200px] gap-2 px-3 rounded-lg h-9 bg-n-alpha-1 outline outline-1 outline-n-weak dark:outline-n-strong focus-within:outline-n-brand"
        >
          <span class="text-n-slate-10 i-lucide-search shrink-0" />
          <input
            v-model="searchQuery"
            type="text"
            class="w-full text-sm bg-transparent outline-none text-n-slate-12 placeholder:text-n-slate-10"
            :placeholder="t('AUTOMATION.TEMPLATES.SEARCH_PLACEHOLDER')"
            data-testid="templates-search"
          />
        </div>
        <div class="flex items-center gap-1.5">
          <button
            v-for="filter in FILTERS"
            :key="filter.id"
            type="button"
            class="px-3 py-1.5 text-xs font-semibold rounded-full border transition-colors"
            :class="
              activeFilter === filter.id
                ? 'bg-n-slate-12 text-n-solid-1 border-transparent'
                : 'text-n-slate-11 border-n-weak hover:bg-n-alpha-2'
            "
            :data-testid="`templates-filter-${filter.id}`"
            @click="activeFilter = filter.id"
          >
            {{ t(filter.labelKey) }}
          </button>
        </div>
      </div>

      <div class="flex-1 min-h-0 p-5 overflow-y-auto">
        <div
          v-if="filteredTemplates.length"
          class="grid gap-4 grid-cols-[repeat(auto-fill,minmax(280px,1fr))]"
        >
          <article
            v-for="template in filteredTemplates"
            :key="template.key"
            class="flex flex-col overflow-hidden transition-colors border rounded-xl border-n-weak bg-n-solid-2 hover:border-n-slate-6"
            :data-testid="`template-card-${template.key}`"
          >
            <!-- Miniatura do fluxo (blocos derivados da definition real) -->
            <div
              class="relative flex items-center justify-center px-4 py-5 border-b min-h-[104px] border-n-weak bg-n-solid-1"
            >
              <span
                v-if="template.badge"
                class="absolute top-2.5 left-3 inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-bold tracking-wide uppercase rounded-full"
                :class="
                  template.badge === 'official'
                    ? 'text-n-teal-11 bg-n-teal-3'
                    : 'text-n-brand bg-n-alpha-2'
                "
              >
                <span
                  :class="
                    template.badge === 'official'
                      ? 'i-lucide-check'
                      : 'i-lucide-star'
                  "
                />
                {{ badgeLabel(template.badge) }}
              </span>
              <div class="flex flex-wrap items-center justify-center gap-1.5">
                <template
                  v-for="(block, index) in previewBlocks(template)"
                  :key="block.id"
                >
                  <span
                    v-if="index > 0"
                    class="text-n-slate-8 i-lucide-chevron-right shrink-0"
                  />
                  <span
                    class="inline-flex items-center gap-1.5 px-2 py-1 text-xs font-medium border rounded-lg border-n-weak bg-n-solid-2 text-n-slate-12"
                  >
                    <span :class="block.icon" :style="{ color: block.color }" />
                    <span class="whitespace-nowrap">{{ block.label }}</span>
                  </span>
                </template>
              </div>
            </div>

            <!-- Corpo do card -->
            <div class="flex flex-col flex-1 gap-2 p-4">
              <div class="flex items-center gap-2">
                <span
                  class="grid rounded-lg size-7 shrink-0 place-items-center bg-n-alpha-1"
                  :style="{ color: familyMeta(template.family).color }"
                >
                  <span :class="template.icon" />
                </span>
                <h3 class="text-sm font-semibold text-n-slate-12">
                  {{ t(template.nameKey) }}
                </h3>
              </div>
              <p class="flex-1 text-xs leading-relaxed text-n-slate-11">
                {{ t(template.descriptionKey) }}
              </p>
              <div class="flex flex-wrap items-center gap-1.5">
                <span
                  v-if="template.whatsapp"
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-semibold rounded-full text-n-teal-11 bg-n-teal-3"
                >
                  <span class="i-lucide-message-circle" />
                  {{ t('AUTOMATION.TEMPLATES.FILTERS.WHATSAPP') }}
                </span>
                <span
                  v-for="chip in familyChips(template)"
                  :key="chip.family"
                  class="inline-flex items-center gap-1 px-2 py-0.5 text-[10px] font-medium rounded-full border border-n-weak text-n-slate-11"
                >
                  <span
                    class="rounded-full size-1.5"
                    :style="{ backgroundColor: chip.color }"
                  />
                  {{ chip.label }}
                </span>
              </div>
              <button
                type="button"
                class="mt-1 inline-flex items-center justify-center gap-1.5 w-full px-3 py-2 text-sm font-medium text-white rounded-lg bg-n-brand hover:opacity-90"
                :data-testid="`template-use-${template.key}`"
                @click="onSelect(template)"
              >
                <span class="i-lucide-sparkles" />
                {{ t('AUTOMATION.TEMPLATES.USE') }}
              </button>
            </div>
          </article>
        </div>

        <div
          v-else
          class="flex flex-col items-center justify-center gap-2 py-16 text-center text-n-slate-10"
          data-testid="templates-empty"
        >
          <span class="text-3xl i-lucide-search-x" />
          <p class="text-sm">{{ t('AUTOMATION.TEMPLATES.EMPTY') }}</p>
        </div>
      </div>
    </div>
  </div>
</template>
