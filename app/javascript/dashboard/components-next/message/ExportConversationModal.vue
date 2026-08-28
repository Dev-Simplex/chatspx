<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import ConversationPdfExportApi from 'dashboard/api/conversationPdfExport';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  conversations: { type: Array, default: () => [] },
});

const emit = defineEmits(['close']);

const { t } = useI18n();

const POLL_INTERVAL_MS = 3000;
const POLL_MAX_TRIES = 80; // ~4 min de polling

const dateFrom = ref('');
const dateTo = ref('');
const includeIncoming = ref(true);
const includeOutgoing = ref(true);
const includePrivate = ref(false);
const includeActivity = ref(false);

const isExporting = ref(false);
const status = ref(''); // pending | processing | completed | failed
const exportId = ref(null);
const downloadUrl = ref(null);
const errorMessage = ref('');

let pollTimer = null;
let pollTries = 0;

const conversationCount = computed(() => props.conversations.length);
const hasMultiple = computed(() => conversationCount.value > 1);

const targetConversation = computed(() => props.conversations[0] || null);

const conversationLabel = computed(() => {
  const c = targetConversation.value;
  if (!c) return '';
  return `#${c.display_id || c.id}`;
});

const canExport = computed(() => {
  if (!targetConversation.value) return false;
  if (isExporting.value) return false;
  // pelo menos um tipo de mensagem precisa estar marcado
  return (
    includeIncoming.value ||
    includeOutgoing.value ||
    includePrivate.value ||
    includeActivity.value
  );
});

const resetState = () => {
  dateFrom.value = '';
  dateTo.value = '';
  includeIncoming.value = true;
  includeOutgoing.value = true;
  includePrivate.value = false;
  includeActivity.value = false;
  isExporting.value = false;
  status.value = '';
  exportId.value = null;
  downloadUrl.value = null;
  errorMessage.value = '';
  pollTries = 0;
  if (pollTimer) {
    clearTimeout(pollTimer);
    pollTimer = null;
  }
};

const handleClose = () => {
  if (isExporting.value && !downloadUrl.value) return;
  resetState();
  emit('close');
};

const filtersPayload = () => ({
  include_incoming: includeIncoming.value,
  include_outgoing: includeOutgoing.value,
  include_private: includePrivate.value,
  include_activity: includeActivity.value,
  date_from: dateFrom.value || null,
  date_to: dateTo.value || null,
});

const resetExportOnly = () => {
  exportId.value = null;
  downloadUrl.value = null;
  errorMessage.value = '';
  pollTries = 0;
  if (pollTimer) {
    clearTimeout(pollTimer);
    pollTimer = null;
  }
};

const pollStatus = async () => {
  pollTries += 1;
  if (pollTries > POLL_MAX_TRIES) {
    status.value = 'failed';
    errorMessage.value = t('EXPORT_CONVERSATION.TIMEOUT');
    isExporting.value = false;
    return;
  }
  try {
    const { data } = await ConversationPdfExportApi.show(
      targetConversation.value.id,
      exportId.value
    );
    status.value = data.status;
    if (data.status === 'completed') {
      downloadUrl.value = data.download_url;
      isExporting.value = false;
    } else if (data.status === 'failed') {
      errorMessage.value = data.error_message || t('EXPORT_CONVERSATION.ERROR');
      isExporting.value = false;
    } else {
      pollTimer = setTimeout(pollStatus, POLL_INTERVAL_MS);
    }
  } catch (e) {
    status.value = 'failed';
    errorMessage.value =
      e?.response?.data?.message || t('EXPORT_CONVERSATION.ERROR');
    isExporting.value = false;
  }
};

const handleExport = async () => {
  if (!canExport.value) return;

  resetExportOnly();
  isExporting.value = true;
  status.value = 'pending';

  try {
    const { data } = await ConversationPdfExportApi.create(
      targetConversation.value.id,
      filtersPayload()
    );
    exportId.value = data.id;
    status.value = data.status;
    pollTimer = setTimeout(pollStatus, POLL_INTERVAL_MS);
  } catch (e) {
    isExporting.value = false;
    status.value = 'failed';
    errorMessage.value =
      e?.response?.data?.message || t('EXPORT_CONVERSATION.ERROR');
    useAlert(errorMessage.value);
  }
};

const handleDownload = () => {
  if (!downloadUrl.value) return;
  window.open(downloadUrl.value, '_blank');
};

watch(
  () => props.show,
  val => {
    if (!val) resetState();
  }
);

onBeforeUnmount(() => {
  if (pollTimer) clearTimeout(pollTimer);
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition ease-out duration-200"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition ease-in duration-150"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        class="fixed inset-0 z-[10000] overflow-y-auto"
        @click.self="handleClose"
      >
        <div class="fixed inset-0 bg-n-slate-12/60 dark:bg-n-black/70" />

        <div class="relative flex min-h-full items-center justify-center p-4">
          <div
            class="relative w-full max-w-md bg-n-background rounded-2xl shadow-2xl ring-1 ring-n-slate-12/5"
          >
            <!-- Header -->
            <div
              class="flex items-center gap-3 px-5 py-4 border-b border-n-weak"
            >
              <span
                class="flex items-center justify-center size-9 rounded-full bg-n-teal-2 dark:bg-n-teal-3"
              >
                <Icon icon="i-lucide-file-down" class="size-4 text-n-teal-11" />
              </span>
              <div class="flex-1 min-w-0">
                <h3 class="text-sm font-semibold text-n-slate-12">
                  {{ t('EXPORT_CONVERSATION.TITLE') }}
                </h3>
                <p class="text-xs text-n-slate-11 truncate">
                  {{ conversationLabel }}
                </p>
              </div>
              <button
                :disabled="isExporting && !downloadUrl"
                class="p-1.5 rounded-full hover:bg-n-slate-3 transition-colors disabled:opacity-30"
                @click="handleClose"
              >
                <Icon icon="i-lucide-x" class="size-4 text-n-slate-10" />
              </button>
            </div>

            <!-- Multi-conv warning -->
            <div
              v-if="hasMultiple"
              class="mx-5 mt-4 px-3 py-2 rounded-lg bg-n-amber-3 border border-n-amber-6"
            >
              <p class="text-xs text-n-amber-11">
                {{
                  t('EXPORT_CONVERSATION.MULTI_WARNING', {
                    count: conversationCount,
                  })
                }}
              </p>
            </div>

            <!-- Body -->
            <div v-if="!downloadUrl" class="px-5 py-4 space-y-4">
              <!-- Date range -->
              <div>
                <label class="block text-xs font-medium text-n-slate-11 mb-2">
                  {{ t('EXPORT_CONVERSATION.DATE_RANGE') }}
                </label>
                <div class="grid grid-cols-2 gap-2">
                  <div>
                    <span class="block text-[10px] text-n-slate-10 mb-1">
                      {{ t('EXPORT_CONVERSATION.DATE_FROM') }}
                    </span>
                    <input
                      v-model="dateFrom"
                      type="date"
                      :disabled="isExporting"
                      class="w-full px-3 py-2 text-sm border border-n-weak rounded-lg bg-n-background text-n-slate-12 focus:ring-1 focus:ring-n-brand focus:border-n-brand"
                    />
                  </div>
                  <div>
                    <span class="block text-[10px] text-n-slate-10 mb-1">
                      {{ t('EXPORT_CONVERSATION.DATE_TO') }}
                    </span>
                    <input
                      v-model="dateTo"
                      type="date"
                      :disabled="isExporting"
                      class="w-full px-3 py-2 text-sm border border-n-weak rounded-lg bg-n-background text-n-slate-12 focus:ring-1 focus:ring-n-brand focus:border-n-brand"
                    />
                  </div>
                </div>
              </div>

              <!-- Filter toggles -->
              <div>
                <label class="block text-xs font-medium text-n-slate-11 mb-2">
                  {{ t('EXPORT_CONVERSATION.FILTERS_LABEL') }}
                </label>
                <div class="space-y-1.5">
                  <label
                    class="flex items-center gap-2.5 px-3 py-2 rounded-lg border border-n-weak cursor-pointer hover:bg-n-slate-3 transition-colors"
                  >
                    <input
                      v-model="includeIncoming"
                      type="checkbox"
                      :disabled="isExporting"
                      class="size-4 text-n-brand rounded border-n-weak focus:ring-n-brand"
                    />
                    <Icon
                      icon="i-lucide-message-square"
                      class="size-3.5 text-n-blue-11"
                    />
                    <span class="text-xs text-n-slate-11 flex-1">
                      {{ t('EXPORT_CONVERSATION.INCLUDE_INCOMING') }}
                    </span>
                  </label>
                  <label
                    class="flex items-center gap-2.5 px-3 py-2 rounded-lg border border-n-weak cursor-pointer hover:bg-n-slate-3 transition-colors"
                  >
                    <input
                      v-model="includeOutgoing"
                      type="checkbox"
                      :disabled="isExporting"
                      class="size-4 text-n-brand rounded border-n-weak focus:ring-n-brand"
                    />
                    <Icon
                      icon="i-lucide-send"
                      class="size-3.5 text-n-teal-11"
                    />
                    <span class="text-xs text-n-slate-11 flex-1">
                      {{ t('EXPORT_CONVERSATION.INCLUDE_OUTGOING') }}
                    </span>
                  </label>
                  <label
                    class="flex items-center gap-2.5 px-3 py-2 rounded-lg border border-n-weak cursor-pointer hover:bg-n-slate-3 transition-colors"
                  >
                    <input
                      v-model="includePrivate"
                      type="checkbox"
                      :disabled="isExporting"
                      class="size-4 text-n-brand rounded border-n-weak focus:ring-n-brand"
                    />
                    <Icon
                      icon="i-lucide-lock"
                      class="size-3.5 text-n-amber-11"
                    />
                    <span class="text-xs text-n-slate-11 flex-1">
                      {{ t('EXPORT_CONVERSATION.INCLUDE_PRIVATE') }}
                    </span>
                  </label>
                  <label
                    class="flex items-center gap-2.5 px-3 py-2 rounded-lg border border-n-weak cursor-pointer hover:bg-n-slate-3 transition-colors"
                  >
                    <input
                      v-model="includeActivity"
                      type="checkbox"
                      :disabled="isExporting"
                      class="size-4 text-n-brand rounded border-n-weak focus:ring-n-brand"
                    />
                    <Icon
                      icon="i-lucide-info"
                      class="size-3.5 text-n-slate-10"
                    />
                    <span class="text-xs text-n-slate-11 flex-1">
                      {{ t('EXPORT_CONVERSATION.INCLUDE_ACTIVITY') }}
                    </span>
                  </label>
                </div>
              </div>

              <!-- Status -->
              <div
                v-if="isExporting"
                class="flex items-center gap-2.5 px-3 py-2.5 rounded-lg bg-n-teal-2 dark:bg-n-teal-3/30"
              >
                <Icon
                  icon="i-lucide-loader-2"
                  class="size-4 text-n-teal-11 animate-spin shrink-0"
                />
                <span class="text-xs text-n-teal-11">
                  {{
                    status === 'processing'
                      ? t('EXPORT_CONVERSATION.PROGRESS.GENERATING')
                      : t('EXPORT_CONVERSATION.PROGRESS.QUEUED')
                  }}
                </span>
              </div>

              <div
                v-if="errorMessage"
                class="flex items-start gap-2.5 px-3 py-2.5 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800"
              >
                <Icon
                  icon="i-lucide-alert-circle"
                  class="size-4 text-red-600 shrink-0"
                />
                <span class="text-xs text-red-700 dark:text-red-300">{{
                  errorMessage
                }}</span>
              </div>
            </div>

            <!-- Ready state -->
            <div v-else class="px-5 py-6 text-center space-y-3">
              <Icon
                icon="i-lucide-check-circle-2"
                class="size-10 text-n-teal-11 mx-auto"
              />
              <div>
                <p class="text-sm font-medium text-n-slate-12">
                  {{ t('EXPORT_CONVERSATION.READY_TITLE') }}
                </p>
                <p class="text-xs text-n-slate-11 mt-1">
                  {{ t('EXPORT_CONVERSATION.READY_HINT') }}
                </p>
              </div>
            </div>

            <!-- Footer -->
            <div
              class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-weak"
            >
              <button
                :disabled="isExporting && !downloadUrl"
                class="px-4 py-2 text-sm font-medium text-n-slate-11 rounded-lg hover:bg-n-slate-3 transition-colors disabled:opacity-30"
                @click="handleClose"
              >
                {{
                  downloadUrl
                    ? t('EXPORT_CONVERSATION.CLOSE')
                    : t('EXPORT_CONVERSATION.CANCEL')
                }}
              </button>
              <button
                v-if="!downloadUrl"
                :disabled="!canExport"
                class="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-n-teal-9 rounded-lg hover:bg-n-teal-10 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
                @click="handleExport"
              >
                <Icon
                  v-if="isExporting"
                  icon="i-lucide-loader-2"
                  class="size-4 animate-spin"
                />
                <Icon v-else icon="i-lucide-download" class="size-4" />
                {{ t('EXPORT_CONVERSATION.EXPORT_PDF') }}
              </button>
              <button
                v-else
                class="flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-n-teal-9 rounded-lg hover:bg-n-teal-10 transition-colors"
                @click="handleDownload"
              >
                <Icon icon="i-lucide-download" class="size-4" />
                {{ t('EXPORT_CONVERSATION.DOWNLOAD') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
