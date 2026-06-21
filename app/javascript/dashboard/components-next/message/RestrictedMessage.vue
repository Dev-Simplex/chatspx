<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  // teamName: caminho legado do team isolation (fallback). Novos chamadores devem
  // passar title/subtitle já resolvidos (suporta tanto team quanto agente).
  teamName: { type: String, default: '' },
  title: { type: String, default: '' },
  subtitle: { type: String, default: '' },
  messageType: { type: Number, default: 0 },
  // createdAt: recebido do Message.vue mas NÃO exibido — mensagens restritas não mostram
  // horário (decisão de produto). Declarado p/ não vazar como atributo no DOM via $attrs.
  createdAt: { type: Number, default: 0 }, // eslint-disable-line vue/no-unused-properties
});

const { t } = useI18n();

const restrictedTitle = computed(
  () =>
    props.title ||
    t('CONVERSATION.TEAM_ISOLATION.RESTRICTED_TITLE', { team: props.teamName })
);
const restrictedSubtitle = computed(
  () => props.subtitle || t('CONVERSATION.TEAM_ISOLATION.RESTRICTED_SUBTITLE')
);

const isOutgoing = computed(() => props.messageType === 1);

const alignmentClass = computed(() =>
  isOutgoing.value ? 'justify-end' : 'justify-start'
);

const bubbleRoundingClass = computed(() =>
  isOutgoing.value
    ? 'rounded-2xl ltr:rounded-br-md rtl:rounded-bl-md'
    : 'rounded-2xl ltr:rounded-bl-md rtl:rounded-br-md'
);
</script>

<template>
  <div class="flex w-full animate-fade-in-up" :class="alignmentClass">
    <div
      class="group relative max-w-[65%] overflow-hidden border border-n-slate-5 dark:border-n-slate-7 bg-n-slate-2 dark:bg-n-slate-3 px-4 py-3"
      :class="bubbleRoundingClass"
    >
      <!-- Blurred fake content -->
      <div class="mb-3 select-none space-y-2">
        <div
          class="h-2.5 w-full rounded-full bg-n-slate-5/60 dark:bg-n-slate-6/40 blur-[5px]"
        />
        <div
          class="h-2.5 w-4/5 rounded-full bg-n-slate-5/60 dark:bg-n-slate-6/40 blur-[5px]"
        />
        <div
          class="h-2.5 w-3/5 rounded-full bg-n-slate-5/40 dark:bg-n-slate-6/30 blur-[5px]"
        />
      </div>

      <!-- Lock badge -->
      <div
        class="flex items-center gap-2 rounded-lg bg-n-slate-3 dark:bg-n-slate-4 px-2.5 py-1.5"
      >
        <div
          class="flex items-center justify-center size-6 rounded-full bg-n-amber-3 dark:bg-n-amber-4"
        >
          <span class="i-lucide-lock size-3 text-n-amber-11" />
        </div>
        <div class="min-w-0">
          <p class="text-xs font-medium text-n-slate-12 truncate">
            {{ restrictedTitle }}
          </p>
          <p class="text-[10px] text-n-slate-10 leading-tight">
            {{ restrictedSubtitle }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
