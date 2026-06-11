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
      class="flex h-10 w-full items-center justify-between gap-2 rounded-xl border border-n-weak bg-n-solid-2 text-n-slate-12 px-3 text-sm leading-5 appearance-none transition-colors focus-visible:outline-none focus-visible:border-n-blue-9 focus-visible:ring-2 focus-visible:ring-n-blue-5 focus-visible:bg-n-solid-1 disabled:cursor-not-allowed disabled:opacity-70"
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
      class="absolute inset-x-0 z-50 mt-2 max-h-64 w-full overflow-y-auto list-none rounded-xl border border-n-weak bg-n-solid-2 p-1.5 shadow-lg backdrop-blur-sm focus-visible:outline-none"
      @keydown="handleListKeydown"
    >
      <li
        v-for="(option, index) in normalizedOptions"
        :key="`${option.value}-${index}`"
      >
        <button
          type="button"
          role="option"
          class="flex w-full items-center justify-between gap-2 rounded-lg py-2 px-2.5 text-sm leading-5 bg-transparent text-n-slate-12 text-left appearance-none hover:bg-n-alpha-2 disabled:cursor-not-allowed disabled:opacity-60"
          :class="{
            '!bg-n-blue-3 !text-n-blue-11':
              String(option.value) === String(modelValue),
            'bg-n-alpha-2':
              index === highlightedIndex &&
              String(option.value) !== String(modelValue),
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
