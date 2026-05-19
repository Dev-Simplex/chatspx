<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const activeSubTab = ref('documents');
const assistantId = computed(() => Number(route.params.assistantId));

const documents = computed(() => store.getters['captainDocuments/getRecords']);
const responses = computed(() => store.getters['captainResponses/getRecords']);
const isFetchingDocs = computed(
  () => store.getters['captainDocuments/getUIFlags'].fetchingList
);
const isFetchingResponses = computed(
  () => store.getters['captainResponses/getUIFlags'].fetchingList
);

const DOC_TYPE_ICONS = {
  pdf: 'i-lucide-file-text',
  url: 'i-lucide-link',
  text: 'i-lucide-file-edit',
};

function docTypeIcon(docType) {
  return DOC_TYPE_ICONS[docType] || 'i-lucide-file';
}

// --- Criacao de documento (URL) ---
const showDocForm = ref(false);
const docForm = ref({ name: '', externalLink: '' });
const savingDoc = ref(false);

async function createDocument() {
  if (!docForm.value.externalLink.trim() || savingDoc.value) return;
  savingDoc.value = true;
  try {
    await store.dispatch('captainDocuments/create', {
      name: docForm.value.name.trim() || docForm.value.externalLink.trim(),
      externalLink: docForm.value.externalLink.trim(),
      assistantId: assistantId.value,
    });
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_CREATED'));
    docForm.value = { name: '', externalLink: '' };
    showDocForm.value = false;
    store.dispatch('captainDocuments/get', { assistantId: assistantId.value });
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_CREATE_ERROR'));
  } finally {
    savingDoc.value = false;
  }
}

// --- Criacao de FAQ ---
const showFaqForm = ref(false);
const faqForm = ref({ question: '', answer: '' });
const savingFaq = ref(false);

async function createFaq() {
  if (
    !faqForm.value.question.trim() ||
    !faqForm.value.answer.trim() ||
    savingFaq.value
  ) {
    return;
  }
  savingFaq.value = true;
  try {
    await store.dispatch('captainResponses/create', {
      question: faqForm.value.question.trim(),
      answer: faqForm.value.answer.trim(),
      assistantId: assistantId.value,
      status: 'approved',
    });
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_CREATED'));
    faqForm.value = { question: '', answer: '' };
    showFaqForm.value = false;
    store.dispatch('captainResponses/get', { assistantId: assistantId.value });
  } catch {
    useAlert(t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_CREATE_ERROR'));
  } finally {
    savingFaq.value = false;
  }
}

onMounted(() => {
  const params = { assistantId: assistantId.value };
  store.dispatch('captainDocuments/get', params);
  store.dispatch('captainResponses/get', params);
});

async function deleteDocument(id) {
  await store.dispatch('captainDocuments/delete', id);
}
</script>

<template>
  <div class="p-6">
    <!-- Sub-tab toggle -->
    <div class="mb-4 flex gap-1 border-b border-n-weak">
      <button
        type="button"
        class="border-b-2 px-3 py-2 text-sm transition-colors"
        :class="
          activeSubTab === 'documents'
            ? 'border-n-brand font-semibold text-n-brand'
            : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
        "
        @click="activeSubTab = 'documents'"
      >
        <i
          class="i-lucide-file-text mr-1.5 inline-block size-3.5 align-text-bottom"
        />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOCUMENTS') }}
      </button>
      <button
        type="button"
        class="border-b-2 px-3 py-2 text-sm transition-colors"
        :class="
          activeSubTab === 'faqs'
            ? 'border-n-brand font-semibold text-n-brand'
            : 'border-transparent text-n-slate-10 hover:text-n-slate-12'
        "
        @click="activeSubTab = 'faqs'"
      >
        <i
          class="i-lucide-help-circle mr-1.5 inline-block size-3.5 align-text-bottom"
        />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQS') }}
      </button>
    </div>

    <!-- Documents -->
    <div v-if="activeSubTab === 'documents'">
      <div class="mb-3 flex justify-end">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95"
          @click="showDocForm = !showDocForm"
        >
          <i class="i-lucide-plus size-3.5" />
          {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.ADD_DOCUMENT') }}
        </button>
      </div>

      <div
        v-if="showDocForm"
        class="mb-4 space-y-2 rounded-xl border border-n-weak bg-n-alpha-1 p-4"
      >
        <input
          v-model="docForm.name"
          type="text"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_NAME_PLACEHOLDER')"
        />
        <input
          v-model="docForm.externalLink"
          type="url"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.DOC_URL_PLACEHOLDER')"
        />
        <div class="flex gap-2">
          <button
            type="button"
            class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95 disabled:opacity-60"
            :disabled="savingDoc"
            @click="createDocument"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.SAVE') }}
          </button>
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-1.5 text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-3"
            @click="showDocForm = false"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
          </button>
        </div>
      </div>

      <div
        v-if="isFetchingDocs"
        class="flex items-center gap-2 text-sm text-n-slate-10"
      >
        <i class="i-lucide-loader-2 size-3.5 animate-spin" />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.LOADING') }}
      </div>
      <div v-else-if="!documents.length" class="py-16 text-center">
        <i class="i-lucide-file-text mx-auto mb-4 size-12 text-n-slate-9" />
        <p class="text-base font-medium text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.NO_DOCUMENTS') }}
        </p>
      </div>
      <div v-else class="space-y-3">
        <div
          v-for="doc in documents"
          :key="doc.id"
          class="flex items-center justify-between rounded-xl border border-n-weak bg-white p-4 transition-shadow duration-200 hover:shadow-md dark:bg-n-solid-2"
        >
          <div class="flex items-center gap-3">
            <div
              class="flex size-8 items-center justify-center rounded-lg bg-n-alpha-2"
            >
              <i
                class="size-4 text-n-slate-11"
                :class="docTypeIcon(doc.document_type)"
              />
            </div>
            <div>
              <p class="text-sm font-medium text-n-slate-12">
                {{ doc.name || doc.title }}
              </p>
              <p class="text-xs text-n-slate-10">
                {{ doc.document_type }}
              </p>
            </div>
          </div>
          <button
            type="button"
            class="rounded-lg p-2 text-n-slate-10 transition-colors hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-900/20 dark:hover:text-red-400"
            @click="deleteDocument(doc.id)"
          >
            <i class="i-lucide-trash-2 size-3.5" />
          </button>
        </div>
      </div>
    </div>

    <!-- FAQs -->
    <div v-if="activeSubTab === 'faqs'">
      <div class="mb-3 flex justify-end">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95"
          @click="showFaqForm = !showFaqForm"
        >
          <i class="i-lucide-plus size-3.5" />
          {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.ADD_FAQ') }}
        </button>
      </div>

      <div
        v-if="showFaqForm"
        class="mb-4 space-y-2 rounded-xl border border-n-weak bg-n-alpha-1 p-4"
      >
        <input
          v-model="faqForm.question"
          type="text"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="
            t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_QUESTION_PLACEHOLDER')
          "
        />
        <textarea
          v-model="faqForm.answer"
          rows="3"
          class="w-full rounded border border-n-weak bg-white px-2 py-1.5 text-sm dark:bg-n-solid-3 dark:text-n-slate-12"
          :placeholder="t('CAPTAIN.AGENT_TABS.KNOWLEDGE.FAQ_ANSWER_PLACEHOLDER')"
        />
        <div class="flex gap-2">
          <button
            type="button"
            class="rounded-lg bg-n-brand px-3 py-1.5 text-sm font-medium text-white transition-colors hover:brightness-95 disabled:opacity-60"
            :disabled="savingFaq"
            @click="createFaq"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.SAVE') }}
          </button>
          <button
            type="button"
            class="rounded-lg bg-n-alpha-2 px-3 py-1.5 text-sm text-n-slate-12 transition-colors hover:bg-n-alpha-3"
            @click="showFaqForm = false"
          >
            {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.CANCEL') }}
          </button>
        </div>
      </div>

      <div
        v-if="isFetchingResponses"
        class="flex items-center gap-2 text-sm text-n-slate-10"
      >
        <i class="i-lucide-loader-2 size-3.5 animate-spin" />
        {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.LOADING') }}
      </div>
      <div v-else-if="!responses.length" class="py-16 text-center">
        <i class="i-lucide-help-circle mx-auto mb-4 size-12 text-n-slate-9" />
        <p class="text-base font-medium text-n-slate-12">
          {{ t('CAPTAIN.AGENT_TABS.KNOWLEDGE.NO_FAQS') }}
        </p>
      </div>
      <div v-else class="space-y-3">
        <div
          v-for="faq in responses"
          :key="faq.id"
          class="rounded-xl border border-n-weak bg-white p-4 transition-shadow duration-200 hover:shadow-md dark:bg-n-solid-2"
        >
          <div class="flex items-center justify-between">
            <p class="text-sm font-medium text-n-slate-12">
              {{ faq.question }}
            </p>
            <span
              class="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium"
              :class="
                faq.status === 'approved'
                  ? 'bg-green-50 text-green-700 dark:bg-green-400/10 dark:text-green-400'
                  : 'bg-amber-50 text-amber-700 dark:bg-amber-400/10 dark:text-amber-400'
              "
            >
              <span
                class="size-1.5 rounded-full"
                :class="
                  faq.status === 'approved' ? 'bg-green-500' : 'bg-amber-500'
                "
              />
              {{
                faq.status === 'approved'
                  ? t('CAPTAIN.AGENT_TABS.KNOWLEDGE.APPROVED')
                  : t('CAPTAIN.AGENT_TABS.KNOWLEDGE.PENDING')
              }}
            </span>
          </div>
          <p class="mt-1 line-clamp-2 text-sm text-n-slate-10">
            {{ faq.answer }}
          </p>
        </div>
      </div>
    </div>
  </div>
</template>
