<script setup>
import { computed, getCurrentInstance } from 'vue';

/**
 * Single quick-prompt card rendered inside `AIAssistantPanel`. Idle state
 * is intentionally subtle (matches the surrounding panel surface). On hover
 * the card lifts slightly and the icon shifts to the brand purple to signal
 * affordance without being noisy when several cards are stacked.
 *
 * Disabled state shows a `cursor-not-allowed` pointer and surfaces an
 * optional reason via `aria-describedby` so screen reader users get the
 * context (e.g. "Disponível só para texto" when an image is attached).
 */

const props = defineProps({
  icon: { type: String, default: '' },
  label: { type: String, required: true },
  description: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  disabledReason: { type: String, default: '' },
});

const emit = defineEmits(['click']);

// Local stable id per instance — avoids relying on Vue 3.5 `useId` which is
// not exported by all bundler builds in our pinned version.
const __uid = getCurrentInstance()?.uid ?? Math.floor(Math.random() * 1e9);
const descriptionId = `aiqp-${__uid}-desc`;
const reasonId = `aiqp-${__uid}-reason`;

const ariaDescribedBy = computed(() => {
  if (props.disabled && props.disabledReason) return reasonId;
  if (props.description) return descriptionId;
  return undefined;
});

function handleClick() {
  if (props.disabled) return;
  emit('click');
}
</script>

<template>
  <button
    type="button"
    :aria-label="label"
    :aria-describedby="ariaDescribedBy"
    :aria-disabled="disabled ? 'true' : 'false'"
    :disabled="disabled"
    :title="disabled && disabledReason ? disabledReason : undefined"
    class="group flex w-full items-start gap-3 rounded-xl border border-n-weak bg-n-solid-1 p-3 text-left transition-all duration-200 ease-out min-h-[44px] focus:outline-none focus-visible:ring-2 focus-visible:ring-n-violet-8 focus-visible:ring-offset-2 focus-visible:ring-offset-n-solid-1 forced-colors:border-2 forced-colors:border-current"
    :class="
      disabled
        ? 'cursor-not-allowed opacity-40'
        : 'hover:scale-[1.01] hover:border-n-violet-6 hover:bg-n-violet-3 hover:shadow-sm active:scale-[0.98] active:bg-n-violet-4 dark:hover:border-n-violet-6 dark:hover:bg-n-violet-3 dark:active:bg-n-violet-3'
    "
    @click="handleClick"
  >
    <span
      v-if="icon"
      aria-hidden="true"
      class="mt-0.5 inline-flex size-5 shrink-0 items-center justify-center text-base text-n-slate-10 transition-colors group-hover:text-n-violet-11 dark:group-hover:text-n-violet-11"
      :class="icon"
    />
    <span class="flex min-w-0 flex-1 flex-col gap-0.5">
      <span class="text-sm font-semibold leading-snug text-n-slate-12">
        {{ label }}
      </span>
      <span
        v-if="description"
        :id="descriptionId"
        class="text-xs leading-snug text-n-slate-10"
      >
        {{ description }}
      </span>
      <span
        v-if="disabled && disabledReason"
        :id="reasonId"
        class="text-[11px] leading-snug text-n-slate-9"
      >
        {{ disabledReason }}
      </span>
    </span>
  </button>
</template>
