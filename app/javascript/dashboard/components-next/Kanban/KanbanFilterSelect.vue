<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  ref,
  watch,
} from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  modelValue: {
    type: [String, Number],
    default: '',
  },
  options: {
    type: Array,
    default: () => [],
  },
  placeholder: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update:modelValue', 'change']);

const rootRef = ref(null);
const triggerRef = ref(null);
const listRef = ref(null);
const isOpen = ref(false);
const highlightedIndex = ref(-1);

const normalizedOptions = computed(() =>
  (props.options || []).map(option => ({
    value: option?.value ?? '',
    label: option?.label ?? String(option?.value ?? ''),
    disabled: Boolean(option?.disabled),
  }))
);

const selectedIndex = computed(() =>
  normalizedOptions.value.findIndex(
    option => String(option.value) === String(props.modelValue)
  )
);

const selectedOption = computed(() => {
  const selected = normalizedOptions.value[selectedIndex.value];
  return selected || null;
});

const triggerLabel = computed(() => {
  if (selectedOption.value) return selectedOption.value.label;
  return props.placeholder || normalizedOptions.value[0]?.label || '';
});

const firstEnabledIndex = computed(() =>
  normalizedOptions.value.findIndex(option => !option.disabled)
);

const lastEnabledIndex = computed(() => {
  for (let index = normalizedOptions.value.length - 1; index >= 0; index -= 1) {
    if (!normalizedOptions.value[index].disabled) return index;
  }
  return -1;
});

const closeMenu = () => {
  isOpen.value = false;
  highlightedIndex.value = -1;
};

const openMenu = async preferredIndex => {
  if (props.disabled || isOpen.value) return;
  isOpen.value = true;
  highlightedIndex.value =
    preferredIndex ?? selectedIndex.value ?? firstEnabledIndex.value;

  await nextTick();
  listRef.value?.focus();
};

const toggleMenu = async () => {
  if (isOpen.value) {
    closeMenu();
    return;
  }

  await openMenu();
};

const selectOption = option => {
  if (!option || option.disabled) return;

  emit('update:modelValue', option.value);
  emit('change', option.value);
  closeMenu();
  nextTick(() => triggerRef.value?.focus());
};

const moveHighlight = direction => {
  if (!normalizedOptions.value.length) return;

  let index = highlightedIndex.value;
  const step = direction === 'up' ? -1 : 1;

  if (index < 0 || index >= normalizedOptions.value.length) {
    index =
      direction === 'up' ? lastEnabledIndex.value : firstEnabledIndex.value;
  } else {
    index += step;
  }

  while (index >= 0 && index < normalizedOptions.value.length) {
    if (!normalizedOptions.value[index].disabled) {
      highlightedIndex.value = index;
      return;
    }
    index += step;
  }
};

const handleTriggerKeydown = async event => {
  if (props.disabled) return;

  if (event.key === 'ArrowDown') {
    event.preventDefault();
    await openMenu(firstEnabledIndex.value);
    return;
  }

  if (event.key === 'ArrowUp') {
    event.preventDefault();
    await openMenu(lastEnabledIndex.value);
    return;
  }

  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault();
    await toggleMenu();
  }
};

const handleListKeydown = event => {
  if (!isOpen.value) return;

  if (event.key === 'ArrowDown') {
    event.preventDefault();
    moveHighlight('down');
    return;
  }

  if (event.key === 'ArrowUp') {
    event.preventDefault();
    moveHighlight('up');
    return;
  }

  if (event.key === 'Enter') {
    event.preventDefault();
    selectOption(normalizedOptions.value[highlightedIndex.value]);
    return;
  }

  if (event.key === 'Escape' || event.key === 'Tab') {
    closeMenu();
    triggerRef.value?.focus();
  }
};

const handleClickOutside = event => {
  if (!rootRef.value || rootRef.value.contains(event.target)) return;
  closeMenu();
};

onMounted(() => {
  document.addEventListener('mousedown', handleClickOutside);
});

onBeforeUnmount(() => {
  document.removeEventListener('mousedown', handleClickOutside);
});

watch(
  () => props.modelValue,
  () => {
    if (!isOpen.value) return;
    highlightedIndex.value = selectedIndex.value;
  }
);
</script>

<template>
  <div ref="rootRef" class="relative">
    <button
      ref="triggerRef"
      type="button"
      class="kanban-filter-select-trigger"
      :disabled="disabled"
      :aria-expanded="isOpen"
      aria-haspopup="listbox"
      @click="toggleMenu"
      @keydown="handleTriggerKeydown"
    >
      <span class="truncate text-left">{{ triggerLabel }}</span>
      <Icon
        icon="i-lucide-chevron-down"
        class="size-4 shrink-0 text-n-slate-10 transition-transform"
        :class="{ 'rotate-180': isOpen }"
      />
    </button>

    <ul
      v-if="isOpen"
      ref="listRef"
      tabindex="-1"
      role="listbox"
      class="kanban-filter-select-options"
      @keydown="handleListKeydown"
    >
      <li
        v-for="(option, index) in normalizedOptions"
        :key="`${option.value}-${index}`"
      >
        <button
          type="button"
          role="option"
          class="kanban-filter-select-option"
          :class="{
            'is-selected': String(option.value) === String(modelValue),
            'is-highlighted': index === highlightedIndex,
          }"
          :aria-selected="String(option.value) === String(modelValue)"
          :disabled="option.disabled"
          @click="selectOption(option)"
          @mouseenter="highlightedIndex = index"
        >
          <span class="truncate">{{ option.label }}</span>
          <Icon
            v-if="String(option.value) === String(modelValue)"
            icon="i-lucide-check"
            class="size-4 text-n-blue-10"
          />
        </button>
      </li>
    </ul>
  </div>
</template>

<style scoped>
.kanban-filter-select-trigger {
  display: flex;
  height: 2.5rem;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  border-radius: 0.75rem;
  border: 1px solid var(--n-weak);
  background-color: var(--n-solid-2, #1f2937);
  color: var(--n-slate-12);
  padding: 0 0.75rem;
  font-size: 0.875rem;
  line-height: 1.25rem;
  -webkit-appearance: none;
  appearance: none;
  transition:
    border-color 0.2s ease,
    box-shadow 0.2s ease,
    background-color 0.2s ease;
}

.kanban-filter-select-trigger:focus-visible {
  outline: none;
  border-color: var(--n-blue-9);
  box-shadow: 0 0 0 2px var(--n-blue-5);
  background: var(--n-solid-1);
}

.kanban-filter-select-trigger:disabled {
  cursor: not-allowed;
  opacity: 0.7;
}

.kanban-filter-select-options {
  position: absolute;
  left: 0;
  right: 0;
  z-index: 30;
  margin: 0.5rem 0 0;
  max-height: 16rem;
  width: 100%;
  overflow-y: auto;
  list-style: none;
  border-radius: 0.75rem;
  border: 1px solid var(--n-weak);
  background-color: var(--n-solid-2, #1f2937);
  padding: 0.375rem;
  backdrop-filter: blur(8px);
  box-shadow:
    0 10px 20px rgba(2, 6, 23, 0.12),
    0 4px 8px rgba(2, 6, 23, 0.08);
}

.kanban-filter-select-options:focus-visible {
  outline: none;
}

.kanban-filter-select-option {
  display: flex;
  width: 100%;
  align-items: center;
  justify-content: space-between;
  gap: 0.5rem;
  border-radius: 0.5rem;
  padding: 0.5rem 0.625rem;
  font-size: 0.875rem;
  line-height: 1.25rem;
  background-color: transparent;
  color: var(--n-slate-12);
  text-align: left;
  -webkit-appearance: none;
  appearance: none;
}

.kanban-filter-select-option:hover,
.kanban-filter-select-option.is-highlighted {
  background-color: var(--n-solid-4, #334155);
}

.kanban-filter-select-option.is-selected {
  background-color: var(--n-blue-3);
  color: var(--n-blue-11);
}

.kanban-filter-select-option:disabled {
  cursor: not-allowed;
  opacity: 0.6;
}
</style>
