<script setup>
import { computed, ref, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';

import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactLabels from 'dashboard/components-next/Contacts/ContactLabels/ContactLabels.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';
import ConfirmContactDeleteDialog from 'dashboard/components-next/Contacts/ContactsForm/ConfirmContactDeleteDialog.vue';

const props = defineProps({
  selectedContact: {
    type: Object,
    required: true,
  },
});

const emit = defineEmits(['goToContactsList']);

const { t } = useI18n();
const store = useStore();

const confirmDeleteContactDialogRef = ref(null);

const isContactBlocked = computed(() => props.selectedContact?.blocked);

// "Bloquear contato" mora aqui embaixo (junto de Excluir), não no topo: ação
// de gestão do contato, longe da ação primária (Enviar/Solicitar).
const toggleBlock = async () => {
  const blocked = isContactBlocked.value;
  try {
    await store.dispatch('contacts/update', {
      ...props.selectedContact,
      blocked: !blocked,
    });
    useAlert(
      blocked
        ? t('CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_SUCCESS_MESSAGE')
        : t('CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_SUCCESS_MESSAGE')
    );
  } catch (error) {
    useAlert(
      blocked
        ? t('CONTACTS_LAYOUT.HEADER.ACTIONS.UNBLOCK_ERROR_MESSAGE')
        : t('CONTACTS_LAYOUT.HEADER.ACTIONS.BLOCK_ERROR_MESSAGE')
    );
  }
};

const avatarFile = ref(null);
const avatarUrl = ref('');

const contactsFormRef = ref(null);

const uiFlags = useMapGetter('contacts/getUIFlags');
const isUpdating = computed(() => uiFlags.value.isUpdating);

const isFormInvalid = computed(() => contactsFormRef.value?.isFormInvalid);

const contactData = ref({});

const getInitialContactData = () => {
  if (!props.selectedContact) return {};
  return { ...props.selectedContact };
};

onMounted(() => {
  Object.assign(contactData.value, getInitialContactData());
});

const createdAt = computed(() => {
  return contactData.value?.createdAt
    ? dynamicTime(contactData.value.createdAt)
    : '';
});

const lastActivityAt = computed(() => {
  return contactData.value?.lastActivityAt
    ? dynamicTime(contactData.value.lastActivityAt)
    : '';
});

const isWhatsappInvalid = computed(
  () => contactData.value?.customAttributes?.whatsappNumberExists === false
);

const avatarSrc = computed(() => {
  return avatarUrl.value ? avatarUrl.value : contactData.value?.thumbnail;
});

const handleFormUpdate = updatedData => {
  Object.assign(contactData.value, updatedData);
};

const updateContact = async () => {
  try {
    const { customAttributes, ...basicContactData } = contactData.value;
    await store.dispatch('contacts/update', basicContactData);
    await store.dispatch(
      'contacts/fetchContactableInbox',
      props.selectedContact.id
    );
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.SUCCESS_MESSAGE'));
  } catch (error) {
    useAlert(t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.ERROR_MESSAGE'));
  }
};

const openConfirmDeleteContactDialog = () => {
  confirmDeleteContactDialogRef.value?.dialogRef.open();
};

const handleAvatarUpload = async ({ file, url }) => {
  avatarFile.value = file;
  avatarUrl.value = url;

  try {
    await store.dispatch('contacts/update', {
      ...contactsFormRef.value?.state,
      avatar: file,
      isFormData: true,
    });
    useAlert(t('CONTACTS_LAYOUT.DETAILS.AVATAR.UPLOAD.SUCCESS_MESSAGE'));
  } catch {
    useAlert(t('CONTACTS_LAYOUT.DETAILS.AVATAR.UPLOAD.ERROR_MESSAGE'));
  }
};

const handleAvatarDelete = async () => {
  try {
    if (props.selectedContact && props.selectedContact.id) {
      await store.dispatch('contacts/deleteAvatar', props.selectedContact.id);
      useAlert(t('CONTACTS_LAYOUT.DETAILS.AVATAR.DELETE.SUCCESS_MESSAGE'));
    }
    avatarFile.value = null;
    avatarUrl.value = '';
    contactData.value.thumbnail = null;
  } catch (error) {
    useAlert(
      error.message
        ? error.message
        : t('CONTACTS_LAYOUT.DETAILS.AVATAR.DELETE.ERROR_MESSAGE')
    );
  }
};
</script>

<template>
  <div class="flex flex-col items-start gap-8 pb-6">
    <div class="flex flex-col items-start gap-3">
      <Avatar
        :src="avatarSrc || ''"
        :name="selectedContact?.name || ''"
        :size="72"
        allow-upload
        allow-preview
        @upload="handleAvatarUpload"
        @delete="handleAvatarDelete"
      />
      <div class="flex flex-col gap-1">
        <div class="flex flex-wrap items-center gap-2">
          <h3 class="text-base font-medium text-n-slate-12">
            {{ selectedContact?.name }}
          </h3>
          <span
            v-if="isWhatsappInvalid"
            class="inline-flex items-center gap-1 px-2 py-0.5 text-xs font-medium text-white rounded-full bg-n-ruby-9 shadow-sm animate-pulse"
          >
            <span class="i-lucide-message-circle-x size-3" />
            {{ t('CONTACTS_LAYOUT.CARD.WHATSAPP.INVALID') }}
          </span>
        </div>
        <div class="flex flex-col gap-1.5">
          <span
            v-if="selectedContact?.identifier"
            class="inline-flex items-center gap-1 text-sm text-n-slate-11"
          >
            <span class="i-lucide-user-cog text-n-slate-10 size-4" />
            {{ selectedContact?.identifier }}
          </span>
          <span class="inline-flex items-center gap-1 text-sm text-n-slate-11">
            <span
              v-if="selectedContact?.identifier"
              class="i-lucide-activity text-n-slate-10 size-4"
            />
            {{ $t('CONTACTS_LAYOUT.DETAILS.CREATED_AT', { date: createdAt }) }}
            •
            {{
              $t('CONTACTS_LAYOUT.DETAILS.LAST_ACTIVITY', {
                date: lastActivityAt,
              })
            }}
          </span>
        </div>
      </div>
      <ContactLabels :contact-id="selectedContact?.id" />
    </div>
    <div class="flex flex-col items-start gap-6">
      <ContactsForm
        ref="contactsFormRef"
        :contact-data="contactData"
        is-details-view
        @update="handleFormUpdate"
      />
      <Button
        :label="t('CONTACTS_LAYOUT.CARD.EDIT_DETAILS_FORM.UPDATE_BUTTON')"
        size="sm"
        :is-loading="isUpdating"
        :disabled="isUpdating || isFormInvalid"
        @click="updateContact"
      />
    </div>
    <div
      class="flex flex-col items-start w-full gap-4 pt-6 border-t border-n-strong"
    >
      <div class="flex flex-col gap-2">
        <h6 class="text-base font-medium text-n-slate-12">
          {{
            isContactBlocked
              ? t('CONTACTS_LAYOUT.HEADER.UNBLOCK_CONTACT')
              : t('CONTACTS_LAYOUT.HEADER.BLOCK_CONTACT')
          }}
        </h6>
        <span class="text-sm text-n-slate-11">
          {{
            isContactBlocked
              ? t('CONTACTS_LAYOUT.DETAILS.UNBLOCK_CONTACT_DESCRIPTION')
              : t('CONTACTS_LAYOUT.DETAILS.BLOCK_CONTACT_DESCRIPTION')
          }}
        </span>
      </div>
      <Button
        :label="
          isContactBlocked
            ? t('CONTACTS_LAYOUT.HEADER.UNBLOCK_CONTACT')
            : t('CONTACTS_LAYOUT.HEADER.BLOCK_CONTACT')
        "
        size="sm"
        variant="faded"
        slate
        :is-loading="isUpdating"
        :disabled="isUpdating"
        @click="toggleBlock"
      />
    </div>
    <div
      class="flex flex-col items-start w-full gap-4 pt-6 border-t border-n-strong"
    >
      <div class="flex flex-col gap-2">
        <h6 class="text-base font-medium text-n-slate-12">
          {{ t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT') }}
        </h6>
        <span class="text-sm text-n-slate-11">
          {{ t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT_DESCRIPTION') }}
        </span>
      </div>
      <Button
        :label="t('CONTACTS_LAYOUT.DETAILS.DELETE_CONTACT')"
        color="ruby"
        @click="openConfirmDeleteContactDialog"
      />
    </div>
    <ConfirmContactDeleteDialog
      ref="confirmDeleteContactDialogRef"
      :selected-contact="selectedContact"
      @go-to-contacts-list="emit('goToContactsList')"
    />
  </div>
</template>
