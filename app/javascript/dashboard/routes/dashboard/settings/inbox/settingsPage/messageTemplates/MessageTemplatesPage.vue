<script setup>
import { ref, computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import InboxesAPI from 'dashboard/api/inboxes';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TemplateBuilder from './TemplateBuilder.vue';

const props = defineProps({
  inbox: { type: Object, default: () => ({}) },
});

const { t } = useI18n();

const templates = ref([]);
const isLoading = ref(false);
const isSyncing = ref(false);
const view = ref('list');
const selectedTemplate = ref(null);
const deleteDialogRef = ref(null);
const isDeleting = ref(false);

const inboxId = computed(() => Number(props.inbox.id));

const fetchTemplates = async () => {
  isLoading.value = true;
  try {
    const { data } = await InboxesAPI.getMessageTemplates(inboxId.value);
    templates.value = data.templates || [];
  } catch (error) {
    useAlert(error?.response?.data?.error || t('WHATSAPP_TEMPLATES_MGMT.LIST.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

const syncTemplates = async () => {
  isSyncing.value = true;
  try {
    await InboxesAPI.syncTemplates(inboxId.value);
    useAlert(t('WHATSAPP_TEMPLATES_MGMT.LIST.SYNC_SUCCESS'));
    await fetchTemplates();
  } catch (error) {
    useAlert(error?.response?.data?.error || t('WHATSAPP_TEMPLATES_MGMT.LIST.SYNC_ERROR'));
  } finally {
    isSyncing.value = false;
  }
};

const bodyPreview = template => {
  const comp = (template.components || []).find(c => c.type === 'BODY');
  return comp?.text || '';
};

const statusKey = template => (template.status || '').toUpperCase();

const statusBadgeClass = template => {
  const map = {
    APPROVED: 'bg-n-teal-9/10 text-n-teal-11',
    PENDING: 'bg-n-amber-9/10 text-n-amber-11',
    REJECTED: 'bg-n-ruby-9/10 text-n-ruby-11',
  };
  return map[statusKey(template)] || 'bg-n-slate-9/10 text-n-slate-11';
};

const statusDotClass = template => {
  const map = {
    APPROVED: 'bg-n-teal-9',
    PENDING: 'bg-n-amber-9',
    REJECTED: 'bg-n-ruby-9',
  };
  return map[statusKey(template)] || 'bg-n-slate-9';
};

const openDelete = template => {
  selectedTemplate.value = template;
  deleteDialogRef.value.open();
};

const confirmDelete = async () => {
  if (!selectedTemplate.value) return;
  isDeleting.value = true;
  try {
    await InboxesAPI.deleteMessageTemplate(inboxId.value, selectedTemplate.value.name);
    useAlert(t('WHATSAPP_TEMPLATES_MGMT.DELETE.SUCCESS'));
    deleteDialogRef.value.close();
    await fetchTemplates();
  } catch (error) {
    useAlert(error?.response?.data?.error || t('WHATSAPP_TEMPLATES_MGMT.DELETE.ERROR'));
  } finally {
    isDeleting.value = false;
    selectedTemplate.value = null;
  }
};

const onCreated = async () => {
  view.value = 'list';
  await fetchTemplates();
};

onMounted(fetchTemplates);
</script>

<template>
  <div class="py-4">
    <!-- BUILDER VIEW -->
    <TemplateBuilder
      v-if="view === 'builder'"
      :inbox-id="inboxId"
      @created="onCreated"
      @cancel="view = 'list'"
    />

    <!-- LIST VIEW -->
    <div v-else class="flex flex-col gap-4">
      <div class="flex items-start justify-between gap-4">
        <div class="flex flex-col gap-1">
          <h2 class="text-base font-medium text-n-slate-12">
            {{ t('WHATSAPP_TEMPLATES_MGMT.LIST.TITLE') }}
          </h2>
          <p class="mb-0 text-sm text-n-slate-11">
            {{ t('WHATSAPP_TEMPLATES_MGMT.LIST.DESCRIPTION') }}
          </p>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <Button
            variant="faded"
            color="slate"
            size="sm"
            icon="i-lucide-refresh-cw"
            :label="t('WHATSAPP_TEMPLATES_MGMT.LIST.SYNC')"
            :is-loading="isSyncing"
            @click="syncTemplates"
          />
          <Button
            size="sm"
            icon="i-lucide-plus"
            :label="t('WHATSAPP_TEMPLATES_MGMT.LIST.NEW')"
            @click="view = 'builder'"
          />
        </div>
      </div>

      <!-- Loading -->
      <div v-if="isLoading" class="flex items-center justify-center py-12 text-n-slate-11">
        <Icon icon="i-lucide-loader-circle" class="size-5 animate-spin" />
      </div>

      <!-- Empty -->
      <div
        v-else-if="!templates.length"
        class="flex flex-col items-center justify-center gap-2 py-12 text-center"
      >
        <Icon icon="i-lucide-message-square-dashed" class="size-8 text-n-slate-9" />
        <p class="mb-0 text-sm text-n-slate-11">
          {{ t('WHATSAPP_TEMPLATES_MGMT.LIST.EMPTY') }}
        </p>
      </div>

      <!-- Table -->
      <div v-else class="overflow-hidden border rounded-xl border-n-weak">
        <table class="w-full text-sm">
          <thead class="bg-n-solid-2 text-n-slate-11">
            <tr>
              <th class="px-4 py-2.5 font-medium text-start">{{ t('WHATSAPP_TEMPLATES_MGMT.LIST.COL_NAME') }}</th>
              <th class="px-4 py-2.5 font-medium text-start">{{ t('WHATSAPP_TEMPLATES_MGMT.LIST.COL_STATUS') }}</th>
              <th class="px-4 py-2.5 font-medium text-start">{{ t('WHATSAPP_TEMPLATES_MGMT.LIST.COL_CATEGORY') }}</th>
              <th class="px-4 py-2.5 font-medium text-start">{{ t('WHATSAPP_TEMPLATES_MGMT.LIST.COL_LANGUAGE') }}</th>
              <th class="px-4 py-2.5" />
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="template in templates"
              :key="template.id || template.name"
              class="border-t border-n-weak hover:bg-n-alpha-1"
            >
              <td class="px-4 py-3 align-top">
                <div class="flex flex-col gap-0.5 min-w-0">
                  <span class="font-medium text-n-slate-12 break-all">{{ template.name }}</span>
                  <span class="text-xs text-n-slate-10 line-clamp-2 max-w-md">{{ bodyPreview(template) }}</span>
                </div>
              </td>
              <td class="px-4 py-3 align-top">
                <span
                  class="inline-flex items-center gap-1.5 rounded-full px-2 py-0.5 text-xs font-medium"
                  :class="statusBadgeClass(template)"
                >
                  <span class="size-1.5 rounded-full" :class="statusDotClass(template)" />
                  {{ template.status }}
                </span>
              </td>
              <td class="px-4 py-3 align-top text-n-slate-11">{{ template.category }}</td>
              <td class="px-4 py-3 align-top text-n-slate-11">{{ template.language }}</td>
              <td class="px-4 py-3 align-top text-end">
                <Button
                  variant="ghost"
                  color="slate"
                  size="sm"
                  icon="i-lucide-trash-2"
                  class="hover:enabled:text-n-ruby-11"
                  @click="openDelete(template)"
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Delete confirm -->
    <Dialog
      ref="deleteDialogRef"
      type="alert"
      :title="t('WHATSAPP_TEMPLATES_MGMT.DELETE.TITLE')"
      :description="t('WHATSAPP_TEMPLATES_MGMT.DELETE.MESSAGE', { name: selectedTemplate?.name })"
      :confirm-button-label="t('WHATSAPP_TEMPLATES_MGMT.DELETE.CONFIRM')"
      :is-loading="isDeleting"
      @confirm="confirmDelete"
    />
  </div>
</template>
