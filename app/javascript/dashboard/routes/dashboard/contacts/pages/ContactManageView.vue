<script setup>
import { onMounted, computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useRoute, useRouter } from 'vue-router';

import ContactsDetailsLayout from 'dashboard/components-next/Contacts/ContactsDetailsLayout.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import ContactDetails from 'dashboard/components-next/Contacts/Pages/ContactDetails.vue';
import TabBar from 'dashboard/components-next/tabbar/TabBar.vue';
import ContactHistory from 'dashboard/components-next/Contacts/ContactsSidebar/ContactHistory.vue';
import ContactMerge from 'dashboard/components-next/Contacts/ContactsSidebar/ContactMerge.vue';
import ContactCustomAttributes from 'dashboard/components-next/Contacts/ContactsSidebar/ContactCustomAttributes.vue';
import ContactAttendanceStatus from 'dashboard/components-next/Contacts/ContactsSidebar/ContactAttendanceStatus.vue';
import { useContactAttendance } from 'dashboard/composables/useContactAttendance';

const store = useStore();
const route = useRoute();
const router = useRouter();

const contact = useMapGetter('contacts/getContactById');
const uiFlags = useMapGetter('contacts/getUIFlags');

const activeTab = ref('attributes');
const contactMergeRef = ref(null);

const isFetchingItem = computed(() => uiFlags.value.isFetchingItem);
const isMergingContact = computed(() => uiFlags.value.isMerging);

const selectedContact = computed(() => contact.value(route.params.contactId));

const contactId = computed(() => route.params.contactId);
// Fonte única do botão do header + da aba "Andamento" (reusa o endpoint da Fase 1).
const {
  attendances,
  isFetching: isFetchingAttendance,
  refetch: refetchAttendance,
  statusLabel,
  sendAction,
} = useContactAttendance(contactId);
const isRequestingAttendance = ref(false);

const showSpinner = computed(
  () => isFetchingItem.value || isMergingContact.value
);

const { t } = useI18n();

const CONTACT_TABS_OPTIONS = [
  { key: 'ATTRIBUTES', value: 'attributes' },
  { key: 'HISTORY', value: 'history' },
  // "Notas" saiu da página de contato (segue disponível dentro das conversas,
  // via ContactPanel) e deu lugar a "Andamento": quem atende este contato agora.
  { key: 'ATTENDANCE', value: 'attendance' },
  { key: 'MERGE', value: 'merge' },
];

const tabs = computed(() => {
  return CONTACT_TABS_OPTIONS.map(tab => ({
    label: t(`CONTACTS_LAYOUT.SIDEBAR.TABS.${tab.key}`),
    value: tab.value,
  }));
});

const activeTabIndex = computed(() => {
  return CONTACT_TABS_OPTIONS.findIndex(v => v.value === activeTab.value);
});

const goToContactsList = () => {
  if (window.history.state?.back || window.history.length > 1) {
    router.back();
  } else {
    router.push(`/app/accounts/${route.params.accountId}/contacts?page=1`);
  }
};

const fetchActiveContact = async () => {
  if (route.params.contactId) {
    await store.dispatch('contacts/show', { id: route.params.contactId });
    await store.dispatch(
      'contacts/fetchContactableInbox',
      route.params.contactId
    );
  }
};

const handleTabChange = tab => {
  activeTab.value = tab.value;
};

// Solicitar/cancelar o atendimento direto da página de contato — mesmos handlers
// do AttendanceIndex: age, avisa e refaz o status (o botão troca de estado).
const runAttendanceAction = async ({ action, successKey }) => {
  if (isRequestingAttendance.value) return;
  isRequestingAttendance.value = true;
  try {
    await action();
    useAlert(t(successKey));
  } catch (error) {
    const status = error?.response?.status;
    useAlert(
      status === 403
        ? t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.ERRORS.NO_ACCESS')
        : t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.ERRORS.GENERIC')
    );
  } finally {
    isRequestingAttendance.value = false;
    await refetchAttendance();
  }
};

const onRequestAttendance = ({ conversationId }) =>
  runAttendanceAction({
    successKey: 'CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.SENT',
    action: () => store.dispatch('takeoverRequests/create', { conversationId }),
  });

const onCancelRequest = ({ requestId }) =>
  runAttendanceAction({
    successKey: 'CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.CANCELLED',
    action: () => store.dispatch('takeoverRequests/cancel', { id: requestId }),
  });

const fetchContactConversations = () => {
  if (contactId.value)
    store.dispatch('contactConversations/get', contactId.value);
};

const fetchAttributes = () => {
  store.dispatch('attributes/get');
};

// Bloquear/desbloquear migrou para a seção de gestão em ContactDetails (junto de
// "Excluir contato"), longe da ação primária do topo.

onMounted(() => {
  fetchActiveContact();
  fetchContactConversations();
  fetchAttributes();
  // o atendimento (status + botão) é buscado pelo useContactAttendance (watch
  // immediate no contactId).
});
</script>

<template>
  <div
    class="flex flex-col justify-between flex-1 h-full m-0 overflow-auto bg-n-surface-1"
  >
    <ContactsDetailsLayout
      :button-label="$t('CONTACTS_LAYOUT.HEADER.SEND_MESSAGE')"
      :selected-contact="selectedContact"
      is-detail-view
      :show-pagination-footer="false"
      :send-action="sendAction"
      :status-label="statusLabel"
      :is-requesting="isRequestingAttendance"
      @go-to-contacts-list="goToContactsList"
      @request-attendance="onRequestAttendance"
      @cancel-request="onCancelRequest"
    >
      <div
        v-if="showSpinner"
        class="flex items-center justify-center py-10 text-n-slate-11"
      >
        <Spinner />
      </div>
      <ContactDetails
        v-else-if="selectedContact"
        :selected-contact="selectedContact"
        @go-to-contacts-list="goToContactsList"
      />
      <template #sidebar>
        <div class="px-6">
          <TabBar
            :tabs="tabs"
            :initial-active-tab="activeTabIndex"
            class="w-full [&>button]:w-full bg-n-alpha-black2"
            @tab-changed="handleTabChange"
          />
        </div>
        <div
          v-if="isFetchingItem"
          class="flex items-center justify-center py-10 text-n-slate-11"
        >
          <Spinner />
        </div>
        <template v-else>
          <ContactCustomAttributes
            v-if="activeTab === 'attributes'"
            :selected-contact="selectedContact"
          />
          <ContactAttendanceStatus
            v-if="activeTab === 'attendance'"
            :attendances="attendances"
            :is-fetching="isFetchingAttendance"
          />
          <ContactHistory v-if="activeTab === 'history'" />
          <ContactMerge
            v-if="activeTab === 'merge'"
            ref="contactMergeRef"
            :selected-contact="selectedContact"
            @go-to-contacts-list="goToContactsList"
            @reset-tab="handleTabChange(CONTACT_TABS_OPTIONS[0])"
          />
        </template>
      </template>
    </ContactsDetailsLayout>
  </div>
</template>
