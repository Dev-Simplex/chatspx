<script setup>
import { useI18n } from 'vue-i18n';
import Icon from 'next/icon/Icon.vue';

defineProps({
  show: { type: Boolean, default: false },
  // Quando true, restringe overlay para a area do main pane (esconde sob sidebar).
  // Quando false, cobre window inteira.
  scopeToMain: { type: Boolean, default: true },
});

const { t } = useI18n();
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-150 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition-opacity duration-120 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        role="region"
        :aria-label="t('GLOBAL_DROP.ARIA_LABEL')"
        class="fixed inset-0 z-[9000] pointer-events-none flex items-center justify-center p-6 bg-white/[0.92] dark:bg-[#0B141A]/[0.92]"
        :class="scopeToMain ? 'md:left-[20rem] lg:left-[24rem]' : 'left-0'"
      >
        <div
          class="flex flex-col items-center justify-center gap-4 px-10 py-12 rounded-2xl border-[2px] border-dashed border-wa-teal-dark dark:border-wa-teal w-full max-w-2xl min-h-[60vh]"
        >
          <span
            class="flex items-center justify-center size-20 rounded-full bg-wa-teal/10 dark:bg-wa-teal/20"
          >
            <Icon
              icon="i-lucide-file-down"
              class="size-12 text-wa-teal-dark dark:text-wa-teal"
            />
          </span>
          <p
            class="text-2xl font-semibold text-n-slate-12 text-center leading-tight"
          >
            {{ t('GLOBAL_DROP.TITLE') }}
          </p>
          <p class="text-sm text-wa-text-muted text-center">
            {{ t('GLOBAL_DROP.SUBTITLE') }}
          </p>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
