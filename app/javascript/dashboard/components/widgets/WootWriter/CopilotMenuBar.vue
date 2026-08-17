<script setup>
import { computed, nextTick, ref, useTemplateRef, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useElementSize } from '@vueuse/core';
import { useMapGetter } from 'dashboard/composables/store';
import { REPLY_EDITOR_MODES } from 'dashboard/components/widgets/WootWriter/constants';
import { useCaptain } from 'dashboard/composables/useCaptain';
import DropdownBody from 'next/dropdown-menu/base/DropdownBody.vue';

import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  hasSelection: {
    type: Boolean,
    default: false,
  },
  isEditorMenuPopover: {
    type: Boolean,
    default: false,
  },
  editorContent: {
    type: String,
    default: undefined,
  },
  // Signature-aware emptiness can be supplied by the parent. Null preserves
  // the per-editor/global-draft fallback for callers that do not supply it.
  hasContent: {
    type: Boolean,
    default: null,
  },
  conversationId: {
    type: Number,
    default: null,
  },
  // Bloqueia operacoes REWRITE quando o composer carrega anexos — IA atual so
  // aceita texto. Tooltip explicativo via DISABLED.ATTACHMENT.
  hasAttachment: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['executeCopilotAction']);

const { t } = useI18n();

const { draftMessage } = useCaptain();

const replyMode = useMapGetter('draftMessages/getReplyEditorMode');

// When editorContent prop is passed, use it exclusively (even if empty)
// This ensures each editor instance shows menu items based on its own content
// Falls back to global draftMessage only when editorContent is not provided
const effectiveContent = computed(() =>
  props.editorContent !== undefined ? props.editorContent : draftMessage.value
);

const isReplyMode = computed(
  () => replyMode.value === REPLY_EDITOR_MODES.REPLY
);
const isNoteMode = computed(() => replyMode.value === REPLY_EDITOR_MODES.NOTE);
const hasInputContent = computed(() =>
  props.hasContent === null ? Boolean(effectiveContent.value) : props.hasContent
);

// 3 categorias visiveis sempre (estados disabled controlam interacao).
// Ordem de "Sobre a conversa": Analisar tom (1o, conforme reordenacao §15).
const sections = computed(() => {
  const understandItems = [
    {
      key: 'sentiment',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.SENTIMENT.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.SENTIMENT.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.SENTIMENT.TOOLTIP',
      icon: 'i-fluent-emoji-meh-24-regular',
      // Sentiment agora tem backend (Fase 2.5). Em notas privadas continua bloqueado.
      disabled: !props.conversationId || isNoteMode.value,
      disabledTooltipKey: isNoteMode.value
        ? 'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.DISABLED.PRIVATE_NOTE'
        : null,
    },
    {
      key: 'summarize',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.SUMMARIZE.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.SUMMARIZE.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.SUMMARIZE.TOOLTIP',
      icon: 'i-fluent-text-bullet-list-square-sparkle-32-regular',
      disabled: !props.conversationId,
    },
  ];

  const rewriteItems = [
    {
      key: 'improve',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.IMPROVE.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.IMPROVE.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.IMPROVE.TOOLTIP',
      icon: 'i-fluent-pen-sparkle-24-regular',
      requiresInput: true,
    },
    {
      key: 'professional',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.PROFESSIONAL.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.PROFESSIONAL.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.PROFESSIONAL.TOOLTIP',
      icon: 'i-fluent-briefcase-24-regular',
      requiresInput: true,
    },
    {
      key: 'friendly',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.FRIENDLY.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.FRIENDLY.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.FRIENDLY.TOOLTIP',
      icon: 'i-fluent-emoji-smile-slight-24-regular',
      requiresInput: true,
    },
    {
      key: 'casual',
      label: t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.CASUAL.LABEL'),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.CASUAL.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.CASUAL.TOOLTIP',
      icon: 'i-fluent-chat-multiple-24-regular',
      requiresInput: true,
    },
    {
      key: 'confident',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.CONFIDENT.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.CONFIDENT.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.CONFIDENT.TOOLTIP',
      icon: 'i-fluent-shield-checkmark-24-regular',
      requiresInput: true,
    },
    {
      key: 'straightforward',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.STRAIGHTFORWARD.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.STRAIGHTFORWARD.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.STRAIGHTFORWARD.TOOLTIP',
      icon: 'i-fluent-arrow-right-24-regular',
      requiresInput: true,
    },
    {
      key: 'shorten',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.SHORTEN.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.SHORTEN.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.SHORTEN.TOOLTIP',
      icon: 'i-fluent-text-collapse-24-regular',
      requiresInput: true,
    },
    {
      key: 'expand',
      label: t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.EXPAND.LABEL'),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.EXPAND.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.EXPAND.TOOLTIP',
      icon: 'i-fluent-text-expand-24-regular',
      requiresInput: true,
    },
    {
      key: 'fix_spelling_grammar',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.FIX_SPELLING.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.FIX_SPELLING.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.FIX_SPELLING.TOOLTIP',
      icon: 'i-fluent-flow-sparkle-24-regular',
      requiresInput: true,
    },
  ].map(item => {
    const inputMissing = item.requiresInput && !hasInputContent.value;
    const hasAttachment = item.requiresInput && props.hasAttachment;
    let disabledTooltipKey = null;
    if (hasAttachment) {
      disabledTooltipKey =
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.DISABLED.ATTACHMENT';
    } else if (inputMissing) {
      disabledTooltipKey =
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.DISABLED.EMPTY_INPUT';
    }
    return {
      ...item,
      disabled: inputMissing || hasAttachment,
      disabledTooltipKey,
    };
  });

  const createItems = [
    {
      key: 'reply_suggestion',
      label: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.REPLY_SUGGESTION.LABEL'
      ),
      description: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.REPLY_SUGGESTION.DESCRIPTION'
      ),
      tooltipKey:
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.REPLY_SUGGESTION.TOOLTIP',
      icon: 'i-fluent-chat-sparkle-16-regular',
      // Sugestao so faz sentido em modo reply, com conversa carregada.
      disabled: !props.conversationId || !isReplyMode.value,
      disabledTooltipKey: isNoteMode.value
        ? 'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.DISABLED.PRIVATE_NOTE'
        : null,
    },
  ];

  return [
    {
      id: 'understand',
      title: t(
        'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.CATEGORIES.UNDERSTAND'
      ),
      items: understandItems,
    },
    {
      id: 'rewrite',
      title: t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.CATEGORIES.REWRITE'),
      items: rewriteItems,
    },
    {
      id: 'create',
      title: t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.CATEGORIES.CREATE'),
      items: createItems,
    },
  ];
});

const askCopilotItem = computed(() => ({
  key: 'ask_copilot',
  label: t(
    'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.ASK_COPILOT.LABEL'
  ),
  description: t(
    'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.ASK_COPILOT.DESCRIPTION'
  ),
  tooltipKey:
    'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.ITEMS.ASK_COPILOT.TOOLTIP',
  icon: 'i-fluent-circle-sparkle-24-regular',
  disabled: false,
}));

// Busca em tempo real sobre todas as sections.
const searchQuery = ref('');

// Promptbook: 4 acoes destacadas no topo (oculto durante busca).
const PROMPTBOOK_KEYS = ['summarize', 'reply_suggestion', 'improve', 'shorten'];

const promptbookItems = computed(() => {
  const allItems = sections.value.flatMap(s => s.items);
  return PROMPTBOOK_KEYS.map(key => allItems.find(i => i.key === key)).filter(
    Boolean
  );
});

const filteredSections = computed(() => {
  if (!searchQuery.value.trim()) return sections.value;
  const q = searchQuery.value.toLowerCase();
  return sections.value
    .map(section => ({
      ...section,
      items: section.items.filter(
        i =>
          i.label.toLowerCase().includes(q) ||
          i.description.toLowerCase().includes(q)
      ),
    }))
    .filter(s => s.items.length > 0);
});

// Sub-agrupamento da categoria "rewrite": exibe chips inline por sub-grupo
// (Polir / Mudar tom / Mudar tamanho) — so quando nao ha busca ativa.
const REWRITE_SUBGROUPS = {
  polish: {
    labelKey: 'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.SUBGROUPS.POLISH',
    keys: ['improve', 'fix_spelling_grammar'],
  },
  tone: {
    labelKey: 'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.SUBGROUPS.TONE',
    keys: [
      'professional',
      'friendly',
      'casual',
      'confident',
      'straightforward',
    ],
  },
  size: {
    labelKey: 'INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.SUBGROUPS.SIZE',
    keys: ['shorten', 'expand'],
  },
};

const buildRewriteSubgroups = rewriteItems =>
  Object.entries(REWRITE_SUBGROUPS).map(([key, group]) => ({
    key,
    label: t(group.labelKey),
    items: group.keys
      .map(k => rewriteItems.find(i => i.key === k))
      .filter(Boolean),
  }));

// Lista achatada (com tipo) para keyboard navigation entre todos os itens visiveis.
// Usa filteredSections para refletir o filtro de busca; quando nao ha busca,
// filteredSections === sections, mantendo o comportamento original.
const flatItems = computed(() => {
  const all = [];
  filteredSections.value.forEach(section => {
    section.items.forEach(item => all.push(item));
  });
  all.push(askCopilotItem.value);
  return all.filter(item => !item.disabled);
});

const focusedIndex = ref(-1);
const itemRefs = ref({});

const setItemRef = (key, el) => {
  if (el) itemRefs.value[key] = el;
};

const focusByIndex = index => {
  if (index < 0 || index >= flatItems.value.length) return;
  focusedIndex.value = index;
  const item = flatItems.value[index];
  const el = itemRefs.value[item.key];
  if (el) el.focus();
};

const handleMenuItemClick = item => {
  if (!item || item.disabled) return;
  emit('executeCopilotAction', item.key);
};

const handleKeydown = event => {
  if (flatItems.value.length === 0) return;

  if (event.key === 'ArrowDown') {
    event.preventDefault();
    const next =
      focusedIndex.value + 1 >= flatItems.value.length
        ? 0
        : focusedIndex.value + 1;
    focusByIndex(next);
  } else if (event.key === 'ArrowUp') {
    event.preventDefault();
    const prev =
      focusedIndex.value <= 0
        ? flatItems.value.length - 1
        : focusedIndex.value - 1;
    focusByIndex(prev);
  } else if (event.key === 'Enter' && focusedIndex.value >= 0) {
    event.preventDefault();
    const item = flatItems.value[focusedIndex.value];
    if (item) handleMenuItemClick(item);
  } else if (event.key === 'Escape') {
    event.preventDefault();
    emit('executeCopilotAction', '__close__');
  }
};

const menuRef = useTemplateRef('menuRef');
const { height: menuHeight } = useElementSize(menuRef);

const selectionMenuStyle = computed(() => {
  // Fallback usado quando a abertura e por selection (offset dinamico relativo a altura)
  const dynamicOffset = menuHeight.value > 0 ? menuHeight.value + 10 : 60;

  return {
    top: `calc(var(--selection-top) - ${dynamicOffset}px)`,
  };
});

// Foca o primeiro item habilitado quando o dropdown abre, garantindo keyboard nav imediata.
watch(
  () => menuRef.value,
  el => {
    if (!el) return;
    nextTick(() => {
      if (flatItems.value.length > 0) {
        focusByIndex(0);
      }
    });
  }
);
</script>

<template>
  <DropdownBody
    ref="menuRef"
    class="min-w-[20rem] max-w-[22rem] z-50 [&>ul]:gap-0 [&>ul]:px-0 [&>ul]:py-0 origin-top motion-safe:animate-copilot-menu-in max-md:fixed max-md:bottom-0 max-md:left-0 max-md:right-0 max-md:rounded-t-2xl max-md:rounded-b-none max-md:max-w-full max-md:min-w-full max-md:max-h-[80vh]"
    :class="{
      'absolute ltr:left-[var(--selection-left)] rtl:right-[var(--selection-right)]':
        hasSelection && isEditorMenuPopover,
    }"
    :style="hasSelection && isEditorMenuPopover ? selectionMenuStyle : {}"
    role="menu"
    :aria-label="t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.MENU_LABEL')"
    @keydown="handleKeydown"
  >
    <div class="flex flex-col">
      <!-- Mobile handle (bottom sheet visual cue) -->
      <div class="md:hidden flex justify-center pt-2 pb-1">
        <div class="w-10 h-1 rounded-full bg-n-slate-6" />
      </div>

      <!-- Search -->
      <div class="px-3 py-2 border-b border-n-weak">
        <div class="relative">
          <span
            class="i-lucide-search absolute left-2.5 top-1/2 -translate-y-1/2 size-3.5 text-n-slate-10"
            aria-hidden="true"
          />
          <input
            v-model="searchQuery"
            type="text"
            :placeholder="
              t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.SEARCH_PLACEHOLDER')
            "
            class="w-full reset-base pl-8 pr-2 py-1.5 text-xs bg-n-slate-2 border border-transparent rounded-md focus:outline-none focus:border-n-brand/50 focus:bg-n-solid-1 placeholder:text-n-slate-9 text-n-slate-12"
          />
        </div>
      </div>

      <!-- Promptbook (oculto durante busca) -->
      <div v-if="!searchQuery && promptbookItems.length" class="px-2 pt-2 pb-1">
        <div
          class="px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-n-slate-10"
        >
          {{ t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.QUICK_ACTIONS') }}
        </div>
        <div class="grid grid-cols-2 gap-1.5 px-1 pb-1">
          <button
            v-for="item in promptbookItems"
            :key="`pb-${item.key}`"
            v-tooltip="{
              content:
                item.disabled && item.disabledTooltipKey
                  ? t(item.disabledTooltipKey)
                  : t(item.tooltipKey),
              delay: { show: 500, hide: 100 },
              theme: 'ai-action',
              triggers: ['hover', 'focus'],
            }"
            type="button"
            class="group flex items-start gap-2 p-2 rounded-lg border border-n-weak text-left transition-all duration-150"
            :class="
              item.disabled
                ? 'opacity-40 cursor-not-allowed'
                : 'cursor-pointer hover:border-n-brand/40 hover:bg-n-brand/5 motion-safe:hover:-translate-y-0.5'
            "
            :aria-disabled="item.disabled ? 'true' : 'false'"
            :tabindex="item.disabled ? -1 : 0"
            @click="handleMenuItemClick(item)"
          >
            <Icon
              :icon="item.icon"
              class="size-4 mt-0.5 shrink-0 text-n-brand"
            />
            <span class="text-xs font-medium text-n-slate-12 leading-tight">
              {{ item.label }}
            </span>
          </button>
        </div>
      </div>

      <!-- Sections -->
      <div class="flex flex-col py-1 max-h-[60vh] overflow-y-auto">
        <template
          v-for="(section, sectionIndex) in filteredSections"
          :key="section.id"
        >
          <div
            v-if="sectionIndex > 0 || !searchQuery"
            class="mx-3 my-1 h-px bg-n-strong/40"
            aria-hidden="true"
          />

          <div
            class="px-4 pt-2 pb-1 text-[10px] font-semibold uppercase tracking-wider text-n-slate-10"
          >
            {{ section.title }}
          </div>

          <!-- Rewrite com sub-grupos (apenas sem busca) -->
          <template v-if="section.id === 'rewrite' && !searchQuery">
            <div
              v-for="subgroup in buildRewriteSubgroups(section.items)"
              :key="`sg-${subgroup.key}`"
              class="px-4 py-1.5"
            >
              <span class="text-[11px] font-medium text-n-slate-11 mb-1 block">
                {{ subgroup.label }}
              </span>
              <div class="flex flex-wrap gap-1.5">
                <button
                  v-for="item in subgroup.items"
                  :key="item.key"
                  :ref="el => setItemRef(item.key, el)"
                  v-tooltip="{
                    content:
                      item.disabled && item.disabledTooltipKey
                        ? t(item.disabledTooltipKey)
                        : t(item.tooltipKey),
                    delay: { show: 500, hide: 100 },
                    theme: 'ai-action',
                    triggers: ['hover', 'focus'],
                  }"
                  type="button"
                  role="menuitem"
                  class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-medium transition-all duration-150"
                  :class="
                    item.disabled
                      ? 'opacity-40 cursor-not-allowed border-n-weak text-n-slate-10'
                      : 'cursor-pointer border-n-weak text-n-slate-11 hover:border-n-brand/50 hover:bg-n-brand/10 hover:text-n-brand'
                  "
                  :aria-disabled="item.disabled ? 'true' : 'false'"
                  :tabindex="item.disabled ? -1 : 0"
                  @click="handleMenuItemClick(item)"
                >
                  <Icon :icon="item.icon" class="size-3 shrink-0" />
                  {{ item.label }}
                </button>
              </div>
            </div>
          </template>

          <!-- Outras categorias OU busca ativa: lista padrao -->
          <template v-else>
            <button
              v-for="(item, itemIndex) in section.items"
              :key="item.key"
              :ref="el => setItemRef(item.key, el)"
              v-tooltip="{
                content:
                  item.disabled && item.disabledTooltipKey
                    ? t(item.disabledTooltipKey)
                    : t(item.tooltipKey),
                delay: { show: 500, hide: 100 },
                theme: 'ai-action',
                triggers: ['hover', 'focus'],
              }"
              type="button"
              role="menuitem"
              class="group flex w-full items-start gap-3 px-4 py-2 min-h-[40px] text-left transition-all duration-150 ease-out outline-none focus:ring-2 focus:ring-n-brand/40 focus:ring-inset"
              :class="
                item.disabled
                  ? 'opacity-40 cursor-not-allowed'
                  : 'cursor-pointer hover:bg-n-brand/5 active:bg-n-brand/10'
              "
              :aria-disabled="item.disabled ? 'true' : 'false'"
              :tabindex="item.disabled ? -1 : 0"
              :data-ai-tour="
                sectionIndex === 0 && itemIndex === 0
                  ? 'dropdown-first-item'
                  : null
              "
              @click="handleMenuItemClick(item)"
            >
              <Icon
                :icon="item.icon"
                class="mt-0.5 size-4 shrink-0 text-n-slate-11 transition-colors duration-150"
                :class="{ 'group-hover:text-n-brand': !item.disabled }"
              />
              <div class="flex min-w-0 flex-1 flex-col gap-0.5">
                <span class="text-xs font-medium text-n-slate-12 leading-tight">
                  {{ item.label }}
                </span>
                <span class="text-[11px] leading-snug text-n-slate-10">
                  {{ item.description }}
                </span>
              </div>
            </button>
          </template>
        </template>

        <div
          v-if="filteredSections.length === 0"
          class="px-4 py-6 text-center text-xs text-n-slate-10"
        >
          {{ t('INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.NO_RESULTS') }}
        </div>
      </div>

      <div class="mx-3 my-1 h-px bg-n-strong/40" aria-hidden="true" />

      <button
        :ref="el => setItemRef(askCopilotItem.key, el)"
        v-tooltip="{
          content: t(askCopilotItem.tooltipKey),
          delay: { show: 500, hide: 100 },
          theme: 'ai-action',
          triggers: ['hover', 'focus'],
        }"
        type="button"
        role="menuitem"
        class="group mx-3 my-1 flex items-center justify-center gap-2 rounded-lg border border-dashed border-n-strong px-3 py-2 min-h-[40px] text-xs font-medium text-n-slate-11 transition-all duration-150 ease-out outline-none cursor-pointer hover:border-n-brand/50 hover:bg-n-brand/5 hover:text-n-brand"
        @click="handleMenuItemClick(askCopilotItem)"
      >
        <Icon :icon="askCopilotItem.icon" class="size-4 shrink-0" />
        <span>{{ askCopilotItem.label }}</span>
      </button>
    </div>
  </DropdownBody>
</template>
