<script setup>
import { ref, computed, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { generateConversationsPDF } from 'dashboard/helper/ConversationPDFExporter';
import Icon from 'next/icon/Icon.vue';

const props = defineProps({
  show: { type: Boolean, default: false },
  conversations: { type: Array, default: () => [] },
  contact: { type: Object, default: () => ({}) },
});

const emit = defineEmits(['close']);

const { t } = useI18n();
const store = useStore();

const dateFrom = ref('');
const dateTo = ref('');
const includePrivateNotes = ref(false);
const isExporting = ref(false);
const exportProgress = ref('');

const MAX_CONVERSATIONS = 5;

const conversationCount = computed(() => props.conversations.length);
const exceedsLimit = computed(
  () => conversationCount.value > MAX_CONVERSATIONS
);

const handleClose = () => {
  if (isExporting.value) return;
  dateFrom.value = '';
  dateTo.value = '';
  includePrivateNotes.value = false;
  isExporting.value = false;
  exportProgress.value = '';
  emit('close');
};

const dateToUnix = dateStr => {
  if (!dateStr) return null;
  return Math.floor(new Date(dateStr).getTime() / 1000);
};

const dateToEndOfDayUnix = dateStr => {
  if (!dateStr) return null;
  const d = new Date(dateStr);
  d.setHours(23, 59, 59, 999);
  return Math.floor(d.getTime() / 1000);
};

const currentAccount = computed(() => store.getters.getCurrentAccount || {});

const handleExport = async () => {
  if (props.conversations.length === 0 || exceedsLimit.value) return;

  isExporting.value = true;
  exportProgress.value = t('EXPORT_CONVERSATION.PROGRESS.FETCHING');

  try {
    const inboxes = store.getters['inboxes/getInboxes'] || [];
    const inboxesById = {};
    inboxes.forEach(inbox => {
      inboxesById[inbox.id] = inbox;
    });
    const accountLabels = store.getters['labels/getLabels'] || [];

    await generateConversationsPDF({
      conversations: props.conversations,
      contact: props.contact,
      inboxesById,
      labelsById: {},
      accountLabels,
      user: store.getters.getCurrentUser,
      account: currentAccount.value,
      dateFrom: dateToUnix(dateFrom.value),
      dateTo: dateToEndOfDayUnix(dateTo.value),
      includePrivateNotes: includePrivateNotes.value,
      onProgress: progress => {
        if (progress.status === 'fetching') {
          const loaded = progress.messagesLoaded || 0;
          exportProgress.value = t(
            'EXPORT_CONVERSATION.PROGRESS.LOADING_MESSAGES',
            { count: loaded }
          );
        } else if (progress.status === 'generating') {
          exportProgress.value = t('EXPORT_CONVERSATION.PROGRESS.GENERATING');
        }
      },
    });

    useAlert(t('EXPORT_CONVERSATION.SUCCESS'));
    handleClose();
  } catch {
    useAlert(t('EXPORT_CONVERSATION.ERROR'));
  } finally {
    isExporting.value = false;
    exportProgress.value = '';
  }
};

watch(
  () => props.show,
  val => {
    if (!val) {
      dateFrom.value = '';
      dateTo.value = '';
      includePrivateNotes.value = false;
      exportProgress.value = '';
    }
  }
);
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
        <div class="fixed inset-0 bg-slate-900/60 dark:bg-black/70" />

        <div class="relative flex min-h-full items-center justify-center p-4">
          <div
            class="relative w-full max-w-sm bg-white dark:bg-slate-800 rounded-2xl shadow-2xl ring-1 ring-slate-900/5"
          >
            <!-- Header -->
            <div
              class="flex items-center gap-3 px-5 py-4 border-b border-slate-200 dark:border-slate-700"
            >
              <span
                class="flex items-center justify-center size-9 rounded-full bg-n-teal-2 dark:bg-n-teal-3"
              >
                <Icon icon="i-lucide-file-down" class="size-4 text-n-teal-11" />
              </span>
              <div class="flex-1 min-w-0">
                <h3
                  class="text-sm font-semibold text-slate-900 dark:text-slate-100"
                >
                  {{ t('EXPORT_CONVERSATION.TITLE') }}
                </h3>
                <p class="text-xs text-slate-500 dark:text-slate-400 truncate">
                  {{
                    conversationCount === 1
                      ? `#${conversations[0]?.display_id || conversations[0]?.id}`
                      : t('EXPORT_CONVERSATION.CONVERSATIONS_COUNT', {
                          count: conversationCount,
                        })
                  }}
                </p>
              </div>
              <button
                :disabled="isExporting"
                class="p-1.5 rounded-full hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors disabled:opacity-30"
                @click="handleClose"
              >
                <Icon icon="i-lucide-x" class="size-4 text-slate-400" />
              </button>
            </div>

            <!-- Limit warning -->
            <div
              v-if="exceedsLimit"
              class="mx-5 mt-4 px-3 py-2 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800"
            >
              <p class="text-xs text-amber-700 dark:text-amber-300">
                {{
                  t('EXPORT_CONVERSATION.LIMIT_WARNING', {
                    max: MAX_CONVERSATIONS,
                    count: conversationCount,
                  })
                }}
              </p>
            </div>

            <!-- Body -->
            <div class="px-5 py-4 space-y-4">
              <!-- Date range -->
              <div>
                <label
                  class="block text-xs font-medium text-slate-600 dark:text-slate-300 mb-2"
                >
                  {{ t('EXPORT_CONVERSATION.DATE_RANGE') }}
                </label>
                <div class="grid grid-cols-2 gap-2">
                  <div>
                    <span class="block text-[10px] text-slate-400 mb-1">
                      {{ t('EXPORT_CONVERSATION.DATE_FROM') }}
                    </span>
                    <input
                      v-model="dateFrom"
                      type="date"
                      class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100 focus:ring-1 focus:ring-woot-500 focus:border-woot-500"
                    />
                  </div>
                  <div>
                    <span class="block text-[10px] text-slate-400 mb-1">
                      {{ t('EXPORT_CONVERSATION.DATE_TO') }}
                    </span>
                    <input
                      v-model="dateTo"
                      type="date"
                      class="w-full px-3 py-2 text-sm border border-slate-200 dark:border-slate-600 rounded-lg bg-white dark:bg-slate-900 text-slate-900 dark:text-slate-100 focus:ring-1 focus:ring-woot-500 focus:border-woot-500"
                    />
                  </div>
                </div>
                <p class="mt-1.5 text-[10px] text-slate-400">
                  {{ t('EXPORT_CONVERSATION.DATE_HINT') }}
                </p>
              </div>

              <!-- Private notes toggle -->
              <label
                class="flex items-center gap-3 px-3 py-3 rounded-lg border border-slate-200 dark:border-slate-700 cursor-pointer hover:bg-slate-50 dark:hover:bg-slate-700/30 transition-colors"
              >
                <input
                  v-model="includePrivateNotes"
                  type="checkbox"
                  class="size-4 text-woot-500 rounded border-slate-300 focus:ring-woot-500"
                />
                <div class="flex-1 min-w-0">
                  <span class="text-sm text-slate-700 dark:text-slate-200">
                    {{ t('EXPORT_CONVERSATION.INCLUDE_PRIVATE') }}
                  </span>
                </div>
                <Icon icon="i-lucide-lock" class="size-3.5 text-slate-400" />
              </label>

              <!-- Progress -->
              <div
                v-if="isExporting"
                class="flex items-center gap-2.5 px-3 py-2.5 rounded-lg bg-n-teal-2 dark:bg-n-teal-3/30"
              >
                <Icon
                  icon="i-lucide-loader-2"
                  class="size-4 text-n-teal-11 animate-spin shrink-0"
                />
                <span class="text-xs text-n-teal-11">
                  {{ exportProgress }}
                </span>
              </div>
            </div>

            <!-- Footer -->
            <div
              class="flex items-center justify-end gap-2 px-5 py-3 border-t border-slate-200 dark:border-slate-700"
            >
              <button
                :disabled="isExporting"
                class="px-4 py-2 text-sm font-medium text-slate-500 dark:text-slate-400 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-700 transition-colors disabled:opacity-30"
                @click="handleClose"
              >
                {{ t('EXPORT_CONVERSATION.CANCEL') }}
              </button>
              <button
                :disabled="
                  isExporting || exceedsLimit || conversationCount === 0
                "
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
            </div>
          </div>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
