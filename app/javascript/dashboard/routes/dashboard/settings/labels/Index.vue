<script setup>
import { useAlert } from 'dashboard/composables';
import { computed, onBeforeMount, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStoreGetters, useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { picoSearch } from '@scmmishra/pico-search';

import AddLabel from './AddLabel.vue';
import EditLabel from './EditLabel.vue';
import BaseSettingsHeader from '../components/BaseSettingsHeader.vue';
import SettingsLayout from '../SettingsLayout.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  BaseTable,
  BaseTableRow,
  BaseTableCell,
} from 'dashboard/components-next/table';

const getters = useStoreGetters();
const store = useStore();
const { t } = useI18n();
const { isAdmin } = useAdmin();

const currentUser = computed(() => getters.getCurrentUser.value);
const myTeams = computed(() => getters['teams/getMyTeams'].value);

// Mirrors the backend LabelPolicy#manage? rule so we only surface actions the
// user is actually allowed to perform (backend still 403s as the source of truth).
const canManage = label => {
  if (isAdmin.value) return true;
  if (label.visibility === 'team') {
    return myTeams.value.some(team => team.id === label.team_id);
  }
  // everyone (public) and personal are both author-only for non-admins.
  return !!label.created_by && currentUser.value?.id === label.created_by.id;
};

const visibilityBadge = label => {
  const visibility = label.visibility || 'everyone';
  if (visibility === 'team') {
    const team = getters['teams/getTeam'].value(label.team_id);
    return {
      icon: 'i-lucide-users',
      text: team?.name
        ? `${t('LABEL_MGMT.FORM.VISIBILITY.TEAM.LABEL')} «${team.name}»`
        : t('LABEL_MGMT.FORM.VISIBILITY.TEAM.LABEL'),
    };
  }
  if (visibility === 'personal') {
    return {
      icon: 'i-lucide-lock',
      text: t('LABEL_MGMT.FORM.VISIBILITY.PERSONAL.LABEL'),
    };
  }
  return {
    icon: 'i-lucide-globe',
    text: t('LABEL_MGMT.FORM.VISIBILITY.EVERYONE.LABEL'),
  };
};

const loading = ref({});
const showAddPopup = ref(false);
const showEditPopup = ref(false);
const showDeleteConfirmationPopup = ref(false);
const selectedLabel = ref({});
const searchQuery = ref('');

const records = computed(() => getters['labels/getLabels'].value);

const filteredRecords = computed(() => {
  const query = searchQuery.value.trim();
  if (!query) return records.value;
  return picoSearch(records.value, query, [
    { name: 'title', weight: 4 },
    'description',
  ]);
});
const uiFlags = computed(() => getters['labels/getUIFlags'].value);

const deleteMessage = computed(() => ` ${selectedLabel.value.title}?`);

const openAddPopup = () => {
  showAddPopup.value = true;
};
const hideAddPopup = () => {
  showAddPopup.value = false;
};

const openEditPopup = response => {
  showEditPopup.value = true;
  selectedLabel.value = response;
};
const hideEditPopup = () => {
  showEditPopup.value = false;
};

const openDeletePopup = response => {
  showDeleteConfirmationPopup.value = true;
  selectedLabel.value = response;
};
const closeDeletePopup = () => {
  showDeleteConfirmationPopup.value = false;
};

const deleteLabel = async id => {
  try {
    await store.dispatch('labels/delete', id);
    useAlert(t('LABEL_MGMT.DELETE.API.SUCCESS_MESSAGE'));
  } catch (error) {
    const errorMessage =
      error?.message || t('LABEL_MGMT.DELETE.API.ERROR_MESSAGE');
    useAlert(errorMessage);
  } finally {
    loading.value[selectedLabel.value.id] = false;
  }
};

const confirmDeletion = () => {
  loading.value[selectedLabel.value.id] = true;
  closeDeletePopup();
  deleteLabel(selectedLabel.value.id);
};

const tableHeaders = computed(() => {
  return [
    t('LABEL_MGMT.LIST.TABLE_HEADER.NAME'),
    t('LABEL_MGMT.LIST.TABLE_HEADER.DESCRIPTION'),
    t('LABEL_MGMT.LIST.TABLE_HEADER.COLOR'),
    t('LABEL_MGMT.LIST.TABLE_HEADER.VISIBILITY'),
    t('LABEL_MGMT.LIST.TABLE_HEADER.ACTION'),
  ];
});

onBeforeMount(() => {
  store.dispatch('labels/get');
  store.dispatch('teams/get');
});
</script>

<template>
  <SettingsLayout
    :is-loading="uiFlags.isFetching"
    :loading-message="$t('LABEL_MGMT.LOADING')"
    :no-records-found="!records.length"
    :no-records-message="$t('LABEL_MGMT.LIST.404')"
  >
    <template #header>
      <BaseSettingsHeader
        v-model:search-query="searchQuery"
        :title="$t('LABEL_MGMT.HEADER')"
        :description="$t('LABEL_MGMT.DESCRIPTION')"
        :link-text="$t('LABEL_MGMT.LEARN_MORE')"
        :search-placeholder="$t('LABEL_MGMT.SEARCH_PLACEHOLDER')"
        feature-name="labels"
      >
        <template v-if="records?.length" #count>
          <span class="text-body-main text-n-slate-11">
            {{ $t('LABEL_MGMT.COUNT', { n: records.length }) }}
          </span>
        </template>
        <template #actions>
          <Button
            :label="$t('LABEL_MGMT.HEADER_BTN_TXT')"
            size="sm"
            @click="openAddPopup"
          />
        </template>
      </BaseSettingsHeader>
    </template>
    <template #body>
      <BaseTable
        :headers="tableHeaders"
        :items="filteredRecords"
        :no-data-message="
          searchQuery ? $t('LABEL_MGMT.NO_RESULTS') : $t('LABEL_MGMT.LIST.404')
        "
      >
        <template #row="{ items }">
          <BaseTableRow
            v-for="(label, index) in items"
            :key="label.title"
            :item="label"
          >
            <template #default>
              <BaseTableCell>
                <span
                  class="inline-flex items-center h-7 gap-2 px-2.5 font-medium rounded-lg max-w-full text-body-main text-n-slate-12"
                  :style="{
                    backgroundColor: `${label.color}1a`,
                    boxShadow: `inset 0 0 0 1px ${label.color}33`,
                  }"
                >
                  <span
                    class="label-dot rounded-full size-2 flex-shrink-0"
                    :style="{
                      backgroundColor: label.color,
                      animationDelay: `${(index % 6) * 0.18}s`,
                    }"
                  />
                  <span class="truncate min-w-0">{{ label.title }}</span>
                </span>
              </BaseTableCell>

              <BaseTableCell>
                <span
                  v-if="label.description"
                  class="text-body-main text-n-slate-11"
                >
                  {{ label.description }}
                </span>
                <span v-else class="text-n-slate-9" aria-hidden="true">—</span>
              </BaseTableCell>

              <BaseTableCell>
                <span
                  v-tooltip.top="label.color"
                  class="inline-block rounded-md size-5 flex-shrink-0 ring-1 ring-inset ring-n-black/10 dark:ring-white/20"
                  :style="{ backgroundColor: label.color }"
                />
              </BaseTableCell>

              <BaseTableCell>
                <span
                  class="inline-flex items-center gap-1.5 text-body-main text-n-slate-11"
                >
                  <span
                    class="size-4 flex-shrink-0 text-n-slate-10"
                    :class="visibilityBadge(label).icon"
                  />
                  <span>{{ visibilityBadge(label).text }}</span>
                </span>
              </BaseTableCell>

              <BaseTableCell align="end">
                <div class="flex gap-3 justify-end flex-shrink-0">
                  <Button
                    v-if="canManage(label)"
                    v-tooltip.top="$t('LABEL_MGMT.FORM.EDIT')"
                    icon="i-woot-edit-pen"
                    slate
                    sm
                    :is-loading="loading[label.id]"
                    @click="openEditPopup(label)"
                  />
                  <Button
                    v-if="canManage(label)"
                    v-tooltip.top="$t('LABEL_MGMT.FORM.DELETE')"
                    icon="i-woot-bin"
                    slate
                    sm
                    class="hover:enabled:text-n-ruby-11 hover:enabled:bg-n-ruby-2"
                    :is-loading="loading[label.id]"
                    @click="openDeletePopup(label)"
                  />
                </div>
              </BaseTableCell>
            </template>
          </BaseTableRow>
        </template>
      </BaseTable>
    </template>

    <woot-modal v-model:show="showAddPopup" :on-close="hideAddPopup">
      <AddLabel @close="hideAddPopup" />
    </woot-modal>

    <woot-modal v-model:show="showEditPopup" :on-close="hideEditPopup">
      <EditLabel :selected-response="selectedLabel" @close="hideEditPopup" />
    </woot-modal>

    <woot-delete-modal
      v-model:show="showDeleteConfirmationPopup"
      :on-close="closeDeletePopup"
      :on-confirm="confirmDeletion"
      :title="$t('LABEL_MGMT.DELETE.CONFIRM.TITLE')"
      :message="$t('LABEL_MGMT.DELETE.CONFIRM.MESSAGE')"
      :message-value="deleteMessage"
      :confirm-text="$t('LABEL_MGMT.DELETE.CONFIRM.YES')"
      :reject-text="$t('LABEL_MGMT.DELETE.CONFIRM.NO')"
    />
  </SettingsLayout>
</template>

<style scoped>
/* Gentle "live" blink on each label's color dot. Staggered per row via an
   inline animation-delay so they don't pulse in robotic lockstep. */
.label-dot {
  animation: label-dot-blink 1.4s ease-in-out infinite;
}

@keyframes label-dot-blink {
  0%,
  100% {
    opacity: 1;
    transform: scale(1);
  }
  50% {
    opacity: 0.25;
    transform: scale(0.82);
  }
}

/* Respect users who prefer less motion. */
@media (prefers-reduced-motion: reduce) {
  .label-dot {
    animation: none;
  }
}
</style>
