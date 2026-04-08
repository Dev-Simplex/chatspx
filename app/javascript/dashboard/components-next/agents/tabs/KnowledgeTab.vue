<script setup>
import { ref, computed, onMounted } from 'vue';
import { useRoute } from 'vue-router';
import { useStore } from 'vuex';
import { useI18n } from 'vue-i18n';

const { t } = useI18n();
const route = useRoute();
const store = useStore();

const activeSubTab = ref('documents');
const assistantId = computed(() => Number(route.params.assistantId));

const documents = computed(() => store.getters['captainDocuments/getRecords']);
const responses = computed(() => store.getters['captainResponses/getRecords']);
const isFetchingDocs = computed(
  () => store.getters['captainDocuments/getUIFlags'].isFetching
);
const isFetchingResponses = computed(
  () => store.getters['captainResponses/getUIFlags'].isFetching
);

const DOC_TYPE_ICONS = {
  pdf: 'i-lucide-file-text',
  url: 'i-lucide-link',
  text: 'i-lucide-file-edit',
};

function docTypeIcon(docType) {
  return DOC_TYPE_ICONS[docType] || 'i-lucide-file';
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
