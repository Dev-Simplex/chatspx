<script setup>
import { ref, computed, nextTick } from 'vue';
import { useRouter } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts';
import { frontendURL } from 'dashboard/helper/URLHelper';

import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ContactsForm from 'dashboard/components-next/Contacts/ContactsForm/ContactsForm.vue';

const emit = defineEmits(['create']);

const { t } = useI18n();
const router = useRouter();
const accountId = useMapGetter('getCurrentAccountId');

const dialogRef = ref(null);
const contactsFormRef = ref(null);
const contact = ref(null);

const uiFlags = useMapGetter('contacts/getUIFlags');
const isCreatingContact = computed(() => uiFlags.value.isCreating);

// Número ou e-mail que já é de outra ficha: aviso fixo dentro do formulário, dizendo de QUEM é,
// em vez de um toast que some (SUP-1415). Some quando a pessoa muda o valor.
const duplicate = ref(null); // { field: 'phone_number' | 'email', value, owner: { id, name } | null }
const duplicateRef = ref(null);

const createNewContact = contactItem => {
  contact.value = { ...contactItem };
  if (!duplicate.value) return;
  const current =
    duplicate.value.field === 'email'
      ? contactItem.email
      : contactItem.phoneNumber;
  if (current !== duplicate.value.value) duplicate.value = null;
};

const duplicateMessage = computed(() => {
  if (!duplicate.value) return '';
  const isEmail = duplicate.value.field === 'email';
  const prefix = 'CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION';
  if (!duplicate.value.owner) {
    return t(
      `${prefix}.${isEmail ? 'EMAIL_ADDRESS_DUPLICATE' : 'PHONE_NUMBER_DUPLICATE'}`
    );
  }
  return t(
    `${prefix}.${isEmail ? 'DUPLICATE_EMAIL_OWNER' : 'DUPLICATE_PHONE_OWNER'}`,
    { name: duplicate.value.owner.name }
  );
});

// Chamado por quem cria o contato quando o servidor responde "já está em uso".
const showDuplicate = async fields => {
  const field = (fields || []).includes('email') ? 'email' : 'phone_number';
  const value =
    field === 'email' ? contact.value?.email : contact.value?.phoneNumber;
  duplicate.value = { field, value, owner: null };
  await nextTick();
  duplicateRef.value?.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
  if (!value) return;
  try {
    const { data } = await ContactAPI.search(value);
    const owner = (data?.payload || []).find(item =>
      field === 'email'
        ? item.email?.toLowerCase() === value.toLowerCase()
        : item.phone_number === value
    );
    if (owner && duplicate.value?.value === value) {
      duplicate.value = { ...duplicate.value, owner };
    }
  } catch {
    // Sem a busca, fica o aviso sem o nome: o essencial continua visível.
  }
};

const openOwner = () => {
  const ownerId = duplicate.value?.owner?.id;
  if (!ownerId) return;
  dialogRef.value.close();
  duplicate.value = null;
  router.push(frontendURL(`accounts/${accountId.value}/contacts/${ownerId}`));
};

const handleDialogConfirm = async () => {
  // SUP-1415: dois envios em 2 ms (clique duplo, Enter + clique) criavam duas fichas
  // do mesmo número. A criação liga `isCreating` antes da requisição sair.
  if (!contact.value || isCreatingContact.value) return;
  emit('create', contact.value);
};

const onSuccess = () => {
  duplicate.value = null;
  contactsFormRef.value?.resetForm();
  dialogRef.value.close();
};

const closeDialog = () => {
  dialogRef.value.close();
};

defineExpose({ dialogRef, contactsFormRef, onSuccess, showDuplicate });
</script>

<template>
  <Dialog
    ref="dialogRef"
    width="3xl"
    overflow-y-auto
    @confirm="handleDialogConfirm"
  >
    <ContactsForm
      ref="contactsFormRef"
      is-new-contact
      @update="createNewContact"
    />
    <template #footer>
      <div class="flex flex-col w-full gap-3">
        <div
          v-if="duplicate"
          ref="duplicateRef"
          role="alert"
          class="flex items-start gap-3 p-3 border rounded-lg border-n-ruby-7 bg-n-ruby-3 text-n-ruby-11"
        >
          <span class="i-lucide-circle-alert size-5 flex-shrink-0 mt-0.5" />
          <p class="flex-1 mb-0 text-sm font-medium">{{ duplicateMessage }}</p>
          <Button
            v-if="duplicate.owner"
            :label="
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.OPEN_EXISTING')
            "
            size="sm"
            color="ruby"
            variant="faded"
            type="button"
            @click="openOwner"
          />
        </div>
        <div class="flex items-center justify-between w-full gap-3">
          <Button
            :label="t('DIALOG.BUTTONS.CANCEL')"
            variant="link"
            type="reset"
            class="h-10 hover:!no-underline hover:text-n-brand"
            @click="closeDialog"
          />
          <Button
            type="submit"
            :label="
              t('CONTACTS_LAYOUT.HEADER.ACTIONS.CONTACT_CREATION.SAVE_CONTACT')
            "
            color="blue"
            :disabled="contactsFormRef?.isFormInvalid || isCreatingContact"
            :is-loading="isCreatingContact"
          />
        </div>
      </div>
    </template>
  </Dialog>
</template>
