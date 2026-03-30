<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { dynamicTime } from 'shared/helpers/timeHelper';

const props = defineProps({
  teamName: { type: String, required: true },
  messageType: { type: Number, default: 0 },
  createdAt: { type: Number, default: 0 },
});

const { t } = useI18n();

const isOutgoing = computed(() => props.messageType === 1);

const alignmentClass = computed(() =>
  isOutgoing.value ? 'justify-end' : 'justify-start'
);

const bubbleRoundingClass = computed(() =>
  isOutgoing.value
    ? 'rounded-2xl ltr:rounded-br-md rtl:rounded-bl-md'
    : 'rounded-2xl ltr:rounded-bl-md rtl:rounded-br-md'
);

const formattedTime = computed(() => dynamicTime(props.createdAt));
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
          <fluent-icon icon="lock-closed" size="12" class="text-n-amber-11" />
        </div>
        <div class="min-w-0">
          <p class="text-xs font-medium text-n-slate-12 truncate">
            {{
              t('CONVERSATION.TEAM_ISOLATION.RESTRICTED_TITLE', {
                team: teamName,
              })
            }}
          </p>
          <p class="text-[10px] text-n-slate-10 leading-tight">
            {{ t('CONVERSATION.TEAM_ISOLATION.RESTRICTED_SUBTITLE') }}
          </p>
        </div>
      </div>

      <!-- Timestamp -->
      <div class="mt-1.5 flex items-center justify-end">
        <span class="text-[10px] text-n-slate-9">{{ formattedTime }}</span>
      </div>
    </div>
  </div>
</template>
