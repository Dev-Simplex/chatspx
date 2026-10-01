<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import IntegrationsAPI from 'dashboard/api/integrations';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({ hook: { type: Object, default: null } });
const { t } = useI18n();
const result = ref(null);
const loading = ref(false);
watch(
  () => props.hook,
  () => {
    result.value = null;
  }
);
const state = computed(() => ({
  ...props.hook?.captador_state,
  ...result.value,
}));
const status = computed(() => result.value?.status || 'untested');
const onboardingUrl = computed(() => {
  try {
    const url = new URL(props.hook?.settings?.captador_url);
    return url.protocol === 'https:' && !url.username && !url.password
      ? `${url.origin}/ajustes/conexoes`
      : null;
  } catch {
    return null;
  }
});
async function testConnection() {
  const hook = props.hook;
  loading.value = true;
  try {
    const { data } = await IntegrationsAPI.testCaptador(hook.id);
    if (props.hook === hook) result.value = data;
  } catch {
    if (props.hook === hook) result.value = { status: 'unavailable' };
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <section
    class="mt-4 flex flex-col gap-3 rounded-lg border border-n-weak p-4 text-n-slate-12"
  >
    <p>{{ t('CAPTADOR_HOOK.ONBOARDING') }}</p>
    <p>{{ t('CAPTADOR_HOOK.ROTATION') }}</p>
    <template v-if="hook">
      <p role="status">{{ t(`CAPTADOR_HOOK.STATUS.${status}`) }}</p>
      <p>{{ t('CAPTADOR_HOOK.EFFECTIVE') }}</p>
      <ul v-if="state.effective_inboxes?.length" class="list-disc pl-5">
        <li v-for="inbox in state.effective_inboxes" :key="inbox.id">
          {{ t('CAPTADOR_HOOK.INBOX', inbox) }}
        </li>
      </ul>
      <p v-else>{{ t('CAPTADOR_HOOK.EMPTY') }}</p>
      <p v-if="state.unavailable_inbox_ids?.length" role="alert">
        {{
          t('CAPTADOR_HOOK.UNAVAILABLE', {
            ids: state.unavailable_inbox_ids.join(', '),
          })
        }}
      </p>
      <a
        v-if="onboardingUrl"
        :href="onboardingUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="text-n-blue-text underline"
      >
        {{ t('CAPTADOR_HOOK.OPEN') }}
      </a>
      <Button
        :label="t('CAPTADOR_HOOK.TEST')"
        :is-loading="loading"
        :disabled="loading"
        @click="testConnection"
      />
    </template>
  </section>
</template>
