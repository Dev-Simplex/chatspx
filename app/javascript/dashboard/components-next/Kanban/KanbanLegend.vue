<script setup>
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useKanbanGlossary } from './composables/useKanbanGlossary';

defineProps({
  show: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'replayTour']);

const { t } = useI18n();
const { groups } = useKanbanGlossary();
</script>

<template>
  <div v-if="show" class="fixed inset-0 z-50 flex justify-end">
    <button
      type="button"
      class="absolute inset-0 bg-n-alpha-black1 backdrop-blur-[2px]"
      :aria-label="t('KANBAN.CANCEL')"
      @click="emit('close')"
    />

    <div
      class="relative flex h-full w-full max-w-[30rem] flex-col border-l border-n-weak bg-n-solid-1 shadow-2xl"
    >
      <!-- Header -->
      <div
        class="border-b border-n-weak bg-n-slate-2/50 dark:bg-n-solid-3 px-5 py-4"
      >
        <div class="flex items-start justify-between gap-3">
          <div class="flex items-start gap-2.5">
            <Icon
              icon="i-lucide-help-circle"
              class="mt-0.5 size-5 text-n-brand"
            />
            <div>
              <h2 class="text-base font-semibold text-n-slate-12">
                {{ t('KANBAN.GLOSSARY.TITLE') }}
              </h2>
              <p class="mt-1 text-xs text-n-slate-10">
                {{ t('KANBAN.GLOSSARY.SUBTITLE') }}
              </p>
            </div>
          </div>
          <Button
            variant="ghost"
            icon="i-lucide-x"
            class="!h-8 !w-8 !p-0"
            :aria-label="t('KANBAN.CANCEL')"
            @click="emit('close')"
          />
        </div>
      </div>

      <!-- Glossary body -->
      <div class="flex-1 overflow-y-auto px-5 py-4">
        <section v-for="group in groups" :key="group.id" class="mb-6 last:mb-0">
          <h3
            class="mb-2 text-xs font-semibold uppercase tracking-wide text-n-slate-10"
          >
            {{ t(group.titleKey) }}
          </h3>
          <ul class="space-y-2.5">
            <li
              v-for="term in group.terms"
              :key="term.id"
              class="flex items-start gap-3 rounded-xl border border-n-weak/60 bg-n-solid-2/40 px-3 py-2.5"
            >
              <!-- Swatch + icon marker -->
              <span
                class="mt-0.5 flex size-7 shrink-0 items-center justify-center rounded-lg"
                :class="term.swatch || 'bg-n-slate-3'"
              >
                <Icon
                  v-if="term.icon"
                  :icon="term.icon"
                  class="size-4"
                  :class="term.swatch ? 'text-white' : 'text-n-slate-11'"
                />
              </span>

              <div class="min-w-0">
                <p class="text-sm font-semibold text-n-slate-12">
                  {{ t(term.labelKey) }}
                </p>
                <p class="mt-0.5 text-xs leading-relaxed text-n-slate-11">
                  {{ t(term.descKey) }}
                </p>
                <p
                  v-if="term.adviceKey"
                  class="mt-1 text-xs leading-relaxed text-n-slate-10"
                >
                  <span class="font-semibold text-n-slate-11">
                    {{ t('KANBAN.GLOSSARY.ADVICE_LABEL') }}:
                  </span>
                  {{ t(term.adviceKey) }}
                </p>
              </div>
            </li>
          </ul>
        </section>
      </div>

      <!-- Footer: replay the onboarding tour -->
      <div class="border-t border-n-weak px-5 py-3">
        <Button
          variant="ghost"
          size="sm"
          icon="i-lucide-rotate-ccw"
          :label="t('KANBAN.GLOSSARY.REPLAY_TOUR')"
          class="w-full justify-center"
          @click="emit('replayTour')"
        />
      </div>
    </div>
  </div>
</template>
