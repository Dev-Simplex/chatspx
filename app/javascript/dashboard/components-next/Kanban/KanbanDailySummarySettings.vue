<script setup>
// KANBAN-P3-04: settings de resumo diário WhatsApp.
// Lê/grava `kanban.settings.daily_summary` via PATCH /kanbans/:id (settings é JSONB).
import { ref, computed, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import KanbanAPI from 'dashboard/api/kanban';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { useKanbanSnackbar } from 'dashboard/composables/kanban/useKanbanSnackbar';

const props = defineProps({
  funnelId: { type: [Number, String], required: true },
  kanban: { type: Object, default: () => ({}) },
});

const { t } = useI18n();
const snackbar = useKanbanSnackbar();

const config = ref({
  enabled: false,
  recipient_phone: '',
  time_local: '08:00',
  inbox_id: null,
  template: '',
});
const inboxes = ref([]);
const saving = ref(false);
const sendingNow = ref(false);

const loadConfig = () => {
  const ds =
    props.kanban?.settings?.daily_summary ||
    props.kanban?.settings?.dailySummary ||
    {};
  config.value = {
    enabled: !!ds.enabled,
    recipient_phone: ds.recipient_phone || '',
    time_local: ds.time_local || '08:00',
    inbox_id: ds.inbox_id || null,
    template: ds.template || '',
  };
};

const fetchInboxes = async () => {
  try {
    const { data } = await KanbanAPI.getWahaInboxes();
    inboxes.value = data?.inboxes || data || [];
  } catch {
    inboxes.value = [];
  }
};

onMounted(() => {
  loadConfig();
  fetchInboxes();
});
watch(() => props.kanban, loadConfig);

const save = async () => {
  saving.value = true;
  try {
    const settings = {
      ...(props.kanban.settings || {}),
      daily_summary: { ...config.value },
    };
    await KanbanAPI.updateFunnel(props.funnelId, { settings });
    snackbar.show({
      message: t('KANBAN.DAILY_SUMMARY.SAVED'),
      variant: 'success',
    });
  } catch (e) {
    snackbar.show({ message: e?.message || 'Error', variant: 'error' });
  } finally {
    saving.value = false;
  }
};

const sendNow = async () => {
  sendingNow.value = true;
  try {
    const { data } = await KanbanAPI.sendSummaryNow(props.funnelId);
    snackbar.show({
      message: data?.ok
        ? t('KANBAN.DAILY_SUMMARY.SENT_NOW')
        : t('KANBAN.DAILY_SUMMARY.SAVED'),
      variant: data?.ok ? 'success' : 'warning',
    });
  } catch (e) {
    snackbar.show({ message: e?.message || 'Error', variant: 'error' });
  } finally {
    sendingNow.value = false;
  }
};

const previewText = computed(() => {
  const tpl = config.value.template || t('KANBAN.DAILY_SUMMARY.TEMPLATE');
  return tpl
    .replace('{total_cards}', '42')
    .replace('{new_leads}', '7')
    .replace('{moved}', '12')
    .replace('{won_yesterday}', '3')
    .replace('{lost_yesterday}', '1')
    .replace('{aging_critical}', '5');
});
</script>

<template>
  <section
    class="flex flex-col gap-3 rounded-xl border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 p-4"
  >
    <header>
      <h3
        class="text-base font-semibold text-slate-900 dark:text-white flex items-center gap-2"
      >
        <Icon icon="i-lucide-clock-3" class="size-4 text-iris-600" />
        {{ t('KANBAN.DAILY_SUMMARY.SETTINGS_TITLE') }}
      </h3>
      <p class="text-xs text-slate-500 dark:text-slate-400">
        {{ t('KANBAN.DAILY_SUMMARY.SETTINGS_DESCRIPTION') }}
      </p>
    </header>

    <label class="flex items-center gap-2">
      <input
        v-model="config.enabled"
        type="checkbox"
        class="size-4 rounded text-iris-600"
      />
      <span class="text-sm text-slate-700 dark:text-slate-200">
        {{ t('KANBAN.DAILY_SUMMARY.ENABLED') }}
      </span>
    </label>

    <div class="grid gap-3 sm:grid-cols-2">
      <label class="flex flex-col gap-1">
        <span
          class="text-[11px] font-medium text-slate-500 dark:text-slate-400"
        >
          {{ t('KANBAN.DAILY_SUMMARY.RECIPIENT_LABEL') }}
        </span>
        <input
          v-model="config.recipient_phone"
          type="tel"
          :placeholder="t('KANBAN.DAILY_SUMMARY_FIELDS.PHONE_PLACEHOLDER')"
          class="rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-iris-500"
        />
      </label>
      <label class="flex flex-col gap-1">
        <span
          class="text-[11px] font-medium text-slate-500 dark:text-slate-400"
        >
          {{ t('KANBAN.DAILY_SUMMARY.TIME_LABEL') }}
        </span>
        <input
          v-model="config.time_local"
          type="time"
          class="rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-2 py-1 text-sm focus:outline-none focus:ring-1 focus:ring-iris-500"
        />
      </label>
      <label class="flex flex-col gap-1 sm:col-span-2">
        <span
          class="text-[11px] font-medium text-slate-500 dark:text-slate-400"
        >
          {{ t('KANBAN.DAILY_SUMMARY.INBOX_LABEL') }}
        </span>
        <select
          v-model="config.inbox_id"
          class="rounded border border-slate-200 dark:border-slate-700 bg-white dark:bg-slate-900 px-2 py-1 text-sm"
        >
          <option :value="null">
            {{ t('KANBAN.DAILY_SUMMARY_FIELDS.EMPTY_OPTION') }}
          </option>
          <option v-for="i in inboxes" :key="i.id" :value="i.id">
            {{ i.name }}
          </option>
        </select>
      </label>
    </div>

    <div>
      <p
        class="mb-1 text-[11px] font-medium text-slate-500 dark:text-slate-400"
      >
        {{ t('KANBAN.DAILY_SUMMARY.PREVIEW_TITLE') }}
      </p>
      <div
        class="whitespace-pre-wrap rounded-lg bg-slate-50 dark:bg-slate-800 px-3 py-2 text-xs text-slate-800 dark:text-slate-100 border border-slate-200 dark:border-slate-700 font-mono"
      >
        {{ previewText }}
      </div>
    </div>

    <div class="flex items-center justify-end gap-2">
      <button
        type="button"
        :disabled="sendingNow"
        class="inline-flex items-center gap-1.5 rounded-md border border-slate-200 dark:border-slate-700 px-3 py-1.5 text-sm font-medium text-slate-600 dark:text-slate-300 hover:bg-slate-50 dark:hover:bg-slate-800 disabled:opacity-50"
        @click="sendNow"
      >
        <Icon
          v-if="sendingNow"
          icon="i-lucide-loader-circle"
          class="size-3.5 animate-spin"
        />
        <Icon v-else icon="i-lucide-send" class="size-3.5" />
        {{ t('KANBAN.DAILY_SUMMARY.SEND_NOW') }}
      </button>
      <button
        type="button"
        :disabled="saving"
        class="inline-flex items-center gap-1.5 rounded-md bg-iris-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-iris-700 disabled:opacity-60"
        @click="save"
      >
        {{ t('KANBAN.DAILY_SUMMARY.SAVE') }}
      </button>
    </div>
  </section>
</template>
