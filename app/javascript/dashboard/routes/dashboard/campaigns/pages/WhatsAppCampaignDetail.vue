<script setup>
import { ref, onMounted, computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import CampaignsAPI from 'dashboard/api/campaigns';
import StatsCard from 'dashboard/components-next/agents/StatsCard.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import { useAlert } from 'dashboard/composables';

const props = defineProps({
  campaignId: { type: [String, Number], default: null },
});

const route = useRoute();
const router = useRouter();
const { t } = useI18n();

const loading = ref(true);
const data = ref(null);

const campaignId = computed(() => props.campaignId || route.params.campaignId);

const KNOWN_CODES = ['131026', '130472', '131049', 'outro'];
const codeLabel = code =>
  KNOWN_CODES.includes(code) ? t(`CAMPAIGN.WHATSAPP.DETAIL.CODES.${code}`) : '';

const fetchStats = async () => {
  loading.value = true;
  try {
    const res = await CampaignsAPI.getStats(campaignId.value);
    data.value = res.data;
  } catch (error) {
    useAlert(t('CAMPAIGN.WHATSAPP.DETAIL.ERROR'));
  } finally {
    loading.value = false;
  }
};

const goBack = () =>
  router.push({
    name: 'campaigns_whatsapp_index',
    params: { accountId: route.params.accountId },
  });

onMounted(fetchStats);
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-y-auto bg-n-surface-1">
    <div class="w-full max-w-5xl px-6 py-6 mx-auto">
      <button
        class="flex items-center gap-1 mb-4 text-sm text-n-slate-11 hover:text-n-slate-12"
        @click="goBack"
      >
        <i class="i-lucide-arrow-left size-4" />
        {{ t('CAMPAIGN.WHATSAPP.DETAIL.BACK') }}
      </button>

      <div v-if="loading" class="flex justify-center py-16">
        <Spinner />
      </div>

      <template v-else-if="data">
        <div class="flex items-start justify-between gap-3 mb-6">
          <div class="min-w-0">
            <h1 class="text-xl font-semibold truncate text-n-slate-12">
              {{ data.campaign.title }}
            </h1>
            <p class="text-sm text-n-slate-11">
              {{ t('CAMPAIGN.WHATSAPP.DETAIL.DELIVERY_RATE', { rate: data.delivery_rate }) }}
              ·
              {{ t('CAMPAIGN.WHATSAPP.DETAIL.READ_RATE', { rate: data.read_rate }) }}
            </p>
          </div>
          <span
            class="shrink-0 px-2 py-1 text-xs font-medium capitalize rounded-md bg-n-alpha-2 text-n-slate-11"
          >
            {{ data.campaign.status }}
          </span>
        </div>

        <div class="grid grid-cols-2 gap-3 mb-6 md:grid-cols-5">
          <StatsCard
            :value="data.total"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.TOTAL')"
            fallback-icon="i-lucide-send"
          />
          <StatsCard
            :value="data.reached"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.REACHED')"
            fallback-icon="i-lucide-check-check"
          />
          <StatsCard
            :value="data.read"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.READ')"
            fallback-icon="i-lucide-eye"
          />
          <StatsCard
            :value="data.replied"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.REPLIED')"
            fallback-icon="i-lucide-message-circle"
          />
          <StatsCard
            :value="data.failed"
            :label="t('CAMPAIGN.WHATSAPP.DETAIL.KPI.FAILED')"
            fallback-icon="i-lucide-triangle-alert"
          />
        </div>

        <div class="grid grid-cols-1 gap-4 mb-6 md:grid-cols-2">
          <div class="p-4 bg-white border rounded-xl border-n-weak dark:bg-n-solid-2">
            <h2 class="mb-3 text-sm font-medium text-n-slate-12">
              {{ t('CAMPAIGN.WHATSAPP.DETAIL.DISTRIBUTION') }}
            </h2>
            <table class="w-full text-sm">
              <tbody>
                <tr
                  v-for="d in data.distribution"
                  :key="d.id"
                  class="border-b border-n-weak last:border-0"
                >
                  <td class="py-2 text-n-slate-12">{{ d.name }}</td>
                  <td class="py-2 font-medium text-right tabular-nums text-n-slate-12">
                    {{ d.count }}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
          <div class="p-4 bg-white border rounded-xl border-n-weak dark:bg-n-solid-2">
            <h2 class="mb-3 text-sm font-medium text-n-slate-12">
              {{ t('CAMPAIGN.WHATSAPP.DETAIL.FAILURES') }}
            </h2>
            <table class="w-full text-sm">
              <tbody>
                <tr
                  v-for="f in data.failures"
                  :key="f.code"
                  class="border-b border-n-weak last:border-0"
                >
                  <td class="py-2 text-n-slate-11">
                    <code class="text-xs">{{ f.code }}</code>
                    {{ codeLabel(f.code) }}
                  </td>
                  <td class="py-2 font-medium text-right tabular-nums text-n-slate-12">
                    {{ f.count }}
                  </td>
                </tr>
                <tr v-if="!data.failures.length">
                  <td class="py-2 text-n-slate-10">—</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="p-4 bg-white border rounded-xl border-n-weak dark:bg-n-solid-2">
          <h2 class="mb-3 text-sm font-medium text-n-slate-12">
            {{ t('CAMPAIGN.WHATSAPP.DETAIL.CONVERSATIONS') }}
          </h2>
          <table class="w-full text-sm">
            <tbody>
              <tr
                v-for="c in data.recent"
                :key="c.id"
                class="border-b border-n-weak last:border-0"
              >
                <td class="py-2 whitespace-nowrap text-n-slate-12">{{ c.name || '—' }}</td>
                <td class="py-2 max-w-xs truncate text-n-slate-11">{{ c.last_reply }}</td>
                <td class="py-2 whitespace-nowrap text-n-slate-11">
                  {{ c.agent || t('CAMPAIGN.WHATSAPP.DETAIL.NO_AGENT') }}
                </td>
                <td class="py-2 text-xs capitalize text-n-slate-10">{{ c.status }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </template>
    </div>
  </section>
</template>
