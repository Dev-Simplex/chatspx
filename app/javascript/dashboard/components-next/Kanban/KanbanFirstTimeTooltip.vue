<script setup>
// KANBAN-P3-07: tooltip educativo flutuante. Mostra UM por vez.
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useFirstTimeTooltip } from 'dashboard/composables/kanban/useFirstTimeTooltip';

const { t } = useI18n();
const { nextTooltip, dismiss } = useFirstTimeTooltip();

const visibleTip = computed(() => nextTooltip.value);

const onGotIt = () => {
  const tip = visibleTip.value;
  if (tip) dismiss(tip.key);
};
</script>

<template>
  <Transition
    enter-from-class="opacity-0 translate-y-2"
    enter-active-class="transition duration-200"
    leave-to-class="opacity-0 translate-y-2"
    leave-active-class="transition duration-200"
  >
    <div
      v-if="visibleTip"
      class="pointer-events-auto fixed bottom-4 right-4 z-[900] max-w-xs rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 shadow-xl p-3"
      role="status"
      aria-live="polite"
    >
      <div class="flex items-start gap-2">
        <div
          class="flex size-7 items-center justify-center rounded-md bg-iris-100 text-iris-700 dark:bg-iris-900/40 dark:text-iris-300"
        >
          <Icon :icon="visibleTip.icon" class="size-4" />
        </div>
        <p class="flex-1 text-xs text-slate-700 dark:text-slate-200">
          {{ t(visibleTip.messageKey) }}
        </p>
      </div>
      <div class="mt-2 flex justify-end">
        <button
          type="button"
          class="rounded-md bg-iris-600 px-2.5 py-1 text-[11px] font-semibold text-white hover:bg-iris-700"
          @click="onGotIt"
        >
          {{ t('KANBAN.TOOLTIPS.GOT_IT') }}
        </button>
      </div>
    </div>
  </Transition>
</template>
