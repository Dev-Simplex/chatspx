<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAccount } from 'dashboard/composables/useAccount';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const { t } = useI18n();
const router = useRouter();
const { currentAccount, updateAccount } = useAccount();

const STEPS = [
  {
    id: 'inbox',
    label: 'ONBOARDING.STEPS.INBOX',
    description: 'ONBOARDING.STEPS.INBOX_DESC',
    routeName: 'settings_inbox_list',
  },
  {
    id: 'team',
    label: 'ONBOARDING.STEPS.TEAM',
    description: 'ONBOARDING.STEPS.TEAM_DESC',
    routeName: 'agent_list',
  },
  {
    id: 'labels',
    label: 'ONBOARDING.STEPS.LABELS',
    description: 'ONBOARDING.STEPS.LABELS_DESC',
    routeName: 'labels_list',
  },
  {
    id: 'wallpaper',
    label: 'ONBOARDING.STEPS.WALLPAPER',
    description: 'ONBOARDING.STEPS.WALLPAPER_DESC',
    routeName: 'general_settings_index',
  },
];

const collapsed = ref(false);

const completed = computed(() => {
  return currentAccount.value?.settings?.onboarding_completed_steps || [];
});

const dismissed = computed(() => {
  return !!currentAccount.value?.settings?.onboarding_dismissed;
});

const total = STEPS.length;
const done = computed(() => completed.value.length);
const isComplete = computed(() => done.value >= total);
const visible = computed(() => !dismissed.value && !isComplete.value);

const isStepDone = id => completed.value.includes(id);

const markDone = async id => {
  if (isStepDone(id)) return;
  const next = [...completed.value, id];
  await updateAccount({ onboarding_completed_steps: next });
};

const dismiss = async () => {
  await updateAccount({ onboarding_dismissed: true });
};

const goTo = step => {
  router.push({ name: step.routeName }).catch(() => {});
  markDone(step.id);
};
</script>

<template>
  <div
    v-if="visible"
    class="fixed bottom-4 right-4 z-20 w-[320px] rounded-xl border border-n-weak bg-n-solid-1 dark:bg-n-solid-2 shadow-xl overflow-hidden"
  >
    <header
      class="flex items-center justify-between px-4 h-10 cursor-pointer hover:bg-n-alpha-1"
      @click="collapsed = !collapsed"
    >
      <div class="flex items-center gap-2">
        <span class="i-lucide-rocket size-4 text-n-brand" />
        <span class="text-sm font-semibold text-n-slate-12">
          {{ t('ONBOARDING.TITLE') }}
        </span>
        <span class="text-xs text-n-slate-10">{{ done }}/{{ total }}</span>
      </div>
      <div class="flex items-center gap-1">
        <Icon
          :icon="collapsed ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          class="size-4 text-n-slate-11"
        />
        <button
          type="button"
          class="!border-0 !p-0 size-6 grid place-content-center text-n-slate-10 hover:text-n-slate-12"
          :title="t('ONBOARDING.DISMISS')"
          @click.stop="dismiss"
        >
          <Icon icon="i-lucide-x" class="size-3.5" />
        </button>
      </div>
    </header>
    <div v-if="!collapsed" class="px-3 pb-3 space-y-2">
      <div class="h-1.5 bg-n-alpha-2 rounded-full overflow-hidden">
        <div
          class="h-full bg-n-brand-default transition-all"
          :style="{ width: `${(done / total) * 100}%` }"
        />
      </div>
      <ul class="space-y-1">
        <li
          v-for="step in STEPS"
          :key="step.id"
          class="flex items-start gap-2 px-2 py-2 rounded-lg cursor-pointer hover:bg-n-alpha-1"
          @click="goTo(step)"
        >
          <span
            class="size-4 mt-0.5 rounded-full grid place-content-center"
            :class="
              isStepDone(step.id)
                ? 'bg-n-brand-default text-white'
                : 'border border-n-weak'
            "
          >
            <Icon
              v-if="isStepDone(step.id)"
              icon="i-lucide-check"
              class="size-3"
            />
          </span>
          <div class="flex-1 min-w-0">
            <div
              class="text-sm font-medium"
              :class="
                isStepDone(step.id)
                  ? 'text-n-slate-10 line-through'
                  : 'text-n-slate-12'
              "
            >
              {{ t(step.label) }}
            </div>
            <div class="text-xs text-n-slate-11 truncate">
              {{ t(step.description) }}
            </div>
          </div>
        </li>
      </ul>
    </div>
  </div>
</template>
