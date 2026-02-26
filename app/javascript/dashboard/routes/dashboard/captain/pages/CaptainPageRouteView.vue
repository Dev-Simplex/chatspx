<script setup>
import { computed, watch, watchEffect } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';

const route = useRoute();
const router = useRouter();
const { uiSettings, updateUISettings } = useUISettings();
const currentAccountId = useMapGetter('getCurrentAccountId');
const isFeatureEnabledonAccount = useMapGetter(
  'accounts/isFeatureEnabledonAccount'
);

const isCaptainEnabled = computed(() =>
  isFeatureEnabledonAccount.value(
    currentAccountId.value || Number(route.params.accountId),
    FEATURE_FLAGS.CAPTAIN_V2
  )
);

watch(
  () => route.params.assistantId,
  newAssistantId => {
    if (
      newAssistantId &&
      newAssistantId !== String(uiSettings.value.last_active_assistant_id)
    ) {
      updateUISettings({
        last_active_assistant_id: Number(newAssistantId),
      });
    }
  }
);

watchEffect(() => {
  const accountId = Number(route.params.accountId);
  if (!accountId || isCaptainEnabled.value) return;

  router.replace({
    name: 'home',
    params: { accountId },
  });
});
</script>

<template>
  <div class="flex w-full h-full min-h-0">
    <section class="flex flex-1 h-full px-0 overflow-hidden bg-n-background">
      <router-view />
    </section>
  </div>
</template>
