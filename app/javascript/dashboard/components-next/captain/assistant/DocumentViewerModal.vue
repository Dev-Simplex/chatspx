<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import {
  isPdfDocument,
  formatDocumentLink,
} from 'shared/helpers/documentHelper';
import AiSheet from 'dashboard/components-next/agents-ui/AiSheet.vue';

const props = defineProps({
  modelValue: { type: Boolean, default: false },
  captainDocument: { type: Object, default: () => ({}) },
});
defineEmits(['update:modelValue']);

const { t } = useI18n();

const doc = computed(() => props.captainDocument || {});
const name = computed(
  () => doc.value.name || formatDocumentLink(doc.value.external_link)
);
const isPdf = computed(() => isPdfDocument(doc.value.external_link));
const displayUrl = computed(() => doc.value.display_url || '');
const content = computed(() => doc.value.content || '');
const sourceUrl = computed(() =>
  isPdf.value ? displayUrl.value : doc.value.external_link || ''
);
</script>

<template>
  <AiSheet
    :model-value="modelValue"
    :title="name"
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <template #actions>
      <a
        v-if="sourceUrl"
        :href="sourceUrl"
        target="_blank"
        rel="noopener noreferrer"
        :download="isPdf ? name : undefined"
        class="inline-flex gap-1.5 items-center px-3 py-1.5 text-sm font-medium rounded-lg text-n-slate-12 bg-n-alpha-2 hover:bg-n-alpha-3"
      >
        <span
          :class="isPdf ? 'i-lucide-download' : 'i-lucide-external-link'"
          class="size-4"
        />
        {{
          isPdf
            ? t('CAPTAIN.DOCUMENTS.VIEWER.DOWNLOAD')
            : t('CAPTAIN.DOCUMENTS.VIEWER.OPEN_LINK')
        }}
      </a>
    </template>

    <iframe
      v-if="isPdf && displayUrl"
      :src="displayUrl"
      :title="name"
      class="w-full h-[68vh] rounded-xl border border-n-weak bg-n-solid-1"
    />
    <div
      v-else-if="content"
      class="overflow-y-auto p-4 max-h-[68vh] text-sm leading-relaxed whitespace-pre-wrap rounded-xl border text-n-slate-12 bg-n-solid-1 border-n-weak"
    >
      {{ content }}
    </div>
    <div
      v-else
      class="flex flex-col gap-2 justify-center items-center py-16 text-center text-n-slate-11"
    >
      <span class="text-2xl i-lucide-file-question" />
      <p class="text-sm">{{ t('CAPTAIN.DOCUMENTS.VIEWER.NO_PREVIEW') }}</p>
    </div>
  </AiSheet>
</template>
