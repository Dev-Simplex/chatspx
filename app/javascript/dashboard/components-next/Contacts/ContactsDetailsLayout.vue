<script setup>
import { computed, useSlots, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { vOnClickOutside } from '@vueuse/components';

import Button from 'dashboard/components-next/button/Button.vue';
import Breadcrumb from 'dashboard/components-next/breadcrumb/Breadcrumb.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';

const props = defineProps({
  selectedContact: {
    type: Object,
    default: () => ({}),
  },
  // Ação do botão principal, decidida por useContactAttendance no pai:
  // { type: 'send' | 'request' | 'pending' | 'blocked', conversationId?, requestId? }
  // Default 'send' → a lista de contatos (que não passa isto) segue igual.
  sendAction: {
    type: Object,
    default: () => ({ type: 'send' }),
  },
  // { name, team } de quem atende — mostrado ao lado do botão. null = ninguém.
  statusLabel: {
    type: Object,
    default: null,
  },
  isRequesting: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'goToContactsList',
  'requestAttendance',
  'cancelRequest',
]);

const { t } = useI18n();
const slots = useSlots();
const route = useRoute();

// Texto "Atendido por Ana (suporte)" / "Atendido por Ana".
const attendedByText = computed(() => {
  if (!props.statusLabel) return '';
  return props.statusLabel.team
    ? t('CONTACTS_LAYOUT.IN_ATTENDANCE.ATTENDED_BY_TEAM', {
        name: props.statusLabel.name,
        team: props.statusLabel.team,
      })
    : t('CONTACTS_LAYOUT.IN_ATTENDANCE.ATTENDED_BY', {
        name: props.statusLabel.name,
      });
});

const isContactSidebarOpen = ref(false);

const contactId = computed(() => route.params.contactId);

const selectedContactName = computed(() => {
  return props.selectedContact?.name;
});

const breadcrumbItems = computed(() => {
  const items = [
    {
      label: t('CONTACTS_LAYOUT.HEADER.BREADCRUMB.CONTACTS'),
      link: '#',
    },
  ];
  if (props.selectedContact) {
    items.push({
      label: selectedContactName.value,
    });
  }
  return items;
});

const handleBreadcrumbClick = () => {
  emit('goToContactsList');
};

const handleConversationSidebarToggle = () => {
  isContactSidebarOpen.value = !isContactSidebarOpen.value;
};

const closeMobileSidebar = () => {
  if (!isContactSidebarOpen.value) return;
  isContactSidebarOpen.value = false;
};
</script>

<template>
  <section
    class="flex w-full h-full overflow-hidden justify-evenly bg-n-surface-1"
  >
    <div
      class="flex flex-col w-full h-full transition-all duration-300 ltr:2xl:ml-56 rtl:2xl:mr-56"
    >
      <header class="sticky top-0 z-10 px-6 3xl:px-0">
        <div class="w-full mx-auto max-w-[40.625rem]">
          <div
            class="flex flex-col xs:flex-row items-start xs:items-center justify-between w-full py-7 gap-2"
          >
            <Breadcrumb
              :items="breadcrumbItems"
              @click="handleBreadcrumbClick"
            />
            <div class="flex items-center gap-3 min-w-0">
              <!-- status "Atendido por Ana (suporte)" ao lado do botão -->
              <span
                v-if="attendedByText"
                class="hidden text-xs truncate sm:inline text-n-slate-11 max-w-52"
                :title="attendedByText"
              >
                {{ attendedByText }}
              </span>
              <VoiceCallButton
                :phone="selectedContact?.phoneNumber"
                :contact-id="contactId"
                :label="$t('CONTACT_PANEL.CALL')"
                size="sm"
              />
              <!-- Botão principal decidido por sendAction (fonte única no pai) -->
              <ComposeConversation
                v-if="sendAction.type === 'send'"
                :contact-id="contactId"
              >
                <template #trigger="{ toggle }">
                  <Button
                    :label="$t('CONTACTS_LAYOUT.HEADER.SEND_MESSAGE')"
                    size="sm"
                    @click="toggle"
                  />
                </template>
              </ComposeConversation>
              <Button
                v-else-if="sendAction.type === 'request'"
                :label="$t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST_ATTENDANCE')"
                size="sm"
                :is-loading="isRequesting"
                :disabled="isRequesting"
                @click="emit('requestAttendance', sendAction)"
              />
              <div
                v-else-if="sendAction.type === 'pending'"
                class="flex items-center gap-2"
              >
                <span class="text-xs text-n-slate-11">
                  {{
                    $t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.PENDING_STATE')
                  }}
                </span>
                <Button
                  :label="$t('CONTACTS_LAYOUT.IN_ATTENDANCE.REQUEST.CANCEL')"
                  size="sm"
                  variant="ghost"
                  slate
                  :is-loading="isRequesting"
                  :disabled="isRequesting"
                  @click="emit('cancelRequest', sendAction)"
                />
              </div>
              <Button
                v-else
                :label="$t('CONTACTS_LAYOUT.HEADER.SEND_MESSAGE')"
                size="sm"
                disabled
                :title="$t('CONTACTS_LAYOUT.IN_ATTENDANCE.SEND_BLOCKED')"
              />
            </div>
          </div>
        </div>
      </header>
      <main class="flex-1 px-6 overflow-y-auto 3xl:px-px">
        <div class="w-full py-4 mx-auto max-w-[40.625rem]">
          <slot name="default" />
        </div>
      </main>
    </div>

    <!-- Desktop sidebar -->
    <div
      v-if="slots.sidebar"
      class="hidden lg:block overflow-y-auto justify-end min-w-52 w-full py-6 max-w-md border-l border-n-weak bg-n-solid-2"
    >
      <slot name="sidebar" />
    </div>

    <!-- Mobile sidebar container -->
    <div
      v-if="slots.sidebar"
      class="lg:hidden fixed top-0 ltr:right-0 rtl:left-0 h-full z-50 flex justify-end transition-all duration-200 ease-in-out"
      :class="isContactSidebarOpen ? 'w-full' : 'w-16'"
    >
      <!-- Toggle button -->
      <div
        v-on-click-outside="[
          closeMobileSidebar,
          { ignore: ['#contact-sidebar-content'] },
        ]"
        class="flex items-start p-1 w-fit h-fit relative order-1 xs:top-24 top-28 transition-all bg-n-solid-2 border border-n-weak duration-500 ease-in-out"
        :class="[
          isContactSidebarOpen
            ? 'justify-end ltr:rounded-l-full rtl:rounded-r-full ltr:rounded-r-none rtl:rounded-l-none'
            : 'justify-center rounded-full ltr:mr-6 rtl:ml-6',
        ]"
      >
        <Button
          ghost
          slate
          sm
          class="!rounded-full rtl:rotate-180"
          :class="{ 'bg-n-alpha-2': isContactSidebarOpen }"
          :icon="
            isContactSidebarOpen
              ? 'i-lucide-panel-right-close'
              : 'i-lucide-panel-right-open'
          "
          data-contact-sidebar-toggle
          @click="handleConversationSidebarToggle"
        />
      </div>

      <Transition
        enter-active-class="transition-transform duration-200 ease-in-out"
        leave-active-class="transition-transform duration-200 ease-in-out"
        enter-from-class="ltr:translate-x-full rtl:-translate-x-full"
        enter-to-class="ltr:translate-x-0 rtl:-translate-x-0"
        leave-from-class="ltr:translate-x-0 rtl:-translate-x-0"
        leave-to-class="ltr:translate-x-full rtl:-translate-x-full"
      >
        <div
          v-if="isContactSidebarOpen"
          id="contact-sidebar-content"
          class="order-2 w-[85%] sm:w-[50%] bg-n-solid-2 ltr:border-l rtl:border-r border-n-weak overflow-y-auto py-6 shadow-lg"
        >
          <slot name="sidebar" />
        </div>
      </Transition>
    </div>
  </section>
</template>
