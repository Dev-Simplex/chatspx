<script setup>
import { computed, ref, onMounted } from 'vue';
import { useRouter } from 'vue-router';
import camelcaseKeys from 'camelcase-keys';
import parsePhoneNumber from 'libphonenumber-js';
import { useAlert } from 'dashboard/composables';
import { useStore } from 'dashboard/composables/store';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useMessageContext } from '../provider.js';
import {
  useAttendanceGate,
  ATTENDANCE_VARIANT,
} from 'dashboard/composables/useAttendanceGate';

import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';

const props = defineProps({
  attachment: {
    type: Object,
    required: true,
  },
  // Suppress the timestamp on all but the last card when a single message
  // carries several shared contacts (avoids repeated timestamps).
  hideMeta: {
    type: Boolean,
    default: false,
  },
});

const $store = useStore();
const { t } = useI18n();
const router = useRouter();
const { inboxId } = useMessageContext();
const { resolveGate } = useAttendanceGate();

// Deterministic avatar palette (picked by name) so each contact keeps a
// consistent colour, à la WhatsApp/Google, instead of always the brand pink.
const AVATAR_COLORS = [
  'bg-[#D6409F]',
  'bg-[#6E56CF]',
  'bg-[#0091FF]',
  'bg-[#12A594]',
  'bg-[#E5484D]',
  'bg-[#F76B15]',
  'bg-[#46A758]',
  'bg-[#FFB224]',
];

const phoneNumber = computed(() => props.attachment?.fallbackTitle ?? '');

const meta = computed(() => props.attachment?.meta ?? {});

const contactName = computed(() => {
  const { fullName, firstName, lastName } = meta.value;
  if (fullName) return fullName;
  return `${firstName ?? ''} ${lastName ?? ''}`.trim();
});

const organization = computed(() => meta.value.organization ?? '');

const email = computed(() => meta.value.email ?? '');

const photo = computed(() => meta.value.photo ?? '');

// Fall back to the initial/icon avatar if the photo URL fails to load.
const photoFailed = ref(false);
const showPhoto = computed(() => Boolean(photo.value) && !photoFailed.value);

const rawPhoneNumber = computed(() => phoneNumber.value.replace(/\D/g, ''));

// E.164 form used both to look up an existing contact and to create one.
const e164 = computed(() =>
  rawPhoneNumber.value ? `+${rawPhoneNumber.value}` : ''
);

// Pretty international format (+55 92 99111-0002); falls back to the raw value.
const formattedPhone = computed(() => {
  try {
    const parsed = parsePhoneNumber(phoneNumber.value);
    return parsed ? parsed.formatInternational() : phoneNumber.value;
  } catch {
    return phoneNumber.value;
  }
});

// Title is the name; falls back to the (formatted) phone number.
const displayName = computed(() => contactName.value || formattedPhone.value);

// Only show the phone as a secondary line when it isn't already the title.
const showPhoneLine = computed(
  () => Boolean(contactName.value) && Boolean(phoneNumber.value)
);

const initial = computed(() => {
  const match = displayName.value.match(/[\p{L}\p{N}]/u);
  return match ? match[0].toUpperCase() : '';
});

const avatarColor = computed(() => {
  const key = contactName.value || phoneNumber.value;
  let hash = 0;
  for (let i = 0; i < key.length; i += 1) {
    hash = (hash * 31 + key.charCodeAt(i)) % 2147483647;
  }
  return AVATAR_COLORS[hash % AVATAR_COLORS.length];
});

const hasActions = computed(() => Boolean(e164.value));

// Smart "already saved" state: resolved once on mount so the action can read
// "View contact" instead of "Save contact" when the contact already exists.
const savedContactId = ref(null);
const isSaved = computed(() => Boolean(savedContactId.value));

const accountId = computed(() => window.location.pathname.split('/')[3]);

function getContactObject() {
  return {
    name: contactName.value,
    phone_number: e164.value,
  };
}

async function filterContactByNumber(searchCandidate) {
  const query = {
    attribute_key: 'phone_number',
    filter_operator: 'equal_to',
    values: [searchCandidate],
    attribute_model: 'standard',
    custom_attribute_type: '',
  };

  const contacts = await $store.dispatch('contacts/filter', {
    queryPayload: { payload: [query] },
    resetState: false,
  });
  return contacts.shift();
}

async function resolveContact() {
  let contact = isSaved.value
    ? { id: savedContactId.value }
    : await filterContactByNumber(e164.value);

  if (!contact) {
    contact = await $store.dispatch('contacts/create', getContactObject());
    useAlert(t('CONTACT_FORM.SUCCESS_MESSAGE'));
  }
  savedContactId.value = contact.id;
  return contact;
}

function openContactProfile(contactId) {
  const url = `/app/accounts/${accountId.value}/contacts/${contactId}`;
  window.open(url, '_blank');
}

function handleContactError(error) {
  if (error instanceof DuplicateContactException) {
    if (error.data.includes('phone_number')) {
      useAlert(t('CONTACT_FORM.FORM.PHONE_NUMBER.DUPLICATE'));
    }
  } else if (error instanceof ExceptionWithMessage) {
    useAlert(error.data);
  } else {
    useAlert(t('CONTACT_FORM.ERROR_MESSAGE'));
  }
}

// Used by the contact action button and by clicking the card body.
async function viewContact() {
  try {
    const contact = await resolveContact();
    openContactProfile(contact.id);
  } catch (error) {
    handleContactError(error);
  }
}

// Picks the inbox to open the conversation in: the inbox the contact was
// shared from when possible, otherwise the first inbox able to reach them.
async function resolveTargetInbox(contactId) {
  const { data } = await ContactAPI.getContactableInboxes(contactId);
  const inboxes = camelcaseKeys(data?.payload ?? [], { deep: true })
    .map(item => ({ id: item.inbox?.id, sourceId: item.sourceId }))
    .filter(item => item.id && item.sourceId);

  if (!inboxes.length) return null;

  return (
    inboxes.find(item => Number(item.id) === Number(inboxId?.value)) ||
    inboxes[0]
  );
}

// Flow: save the contact -> reuse an open conversation if one exists,
// otherwise create a new one -> navigate to it.
async function startConversation() {
  try {
    const contact = await resolveContact();
    const contactId = Number(contact.id);

    // Antes havia um findActiveConversation PRÓPRIO aqui, montado sobre o store
    // contactConversations — que passa pelo PermissionFilterService e devolve
    // vazio p/ conversa de outro time. Resultado: "não achei nada" → criava uma
    // conversa DUPLICADA justamente no caso que a feature existe pra evitar.
    // Agora a verdade é uma só: useAttendanceGate (ver o comentário lá).
    const { attendance, variant } = await resolveGate({
      contactId,
      inboxId: inboxId?.value,
    });

    if (variant === ATTENDANCE_VARIANT.UNKNOWN) {
      // Criar às cegas é o que produz o atendimento duplicado. Melhor avisar e
      // deixar o agente tentar de novo do que duplicar em silêncio.
      useAlert(t('CONVERSATION.ATTENDANCE_CHECK_FAILED'));
      return;
    }

    let conversation = attendance ? { id: attendance.id } : null;

    if (!conversation) {
      const targetInbox = await resolveTargetInbox(contactId);
      if (!targetInbox) {
        useAlert(t('CONVERSATION.NO_INBOX_FOR_CONTACT'));
        openContactProfile(contactId);
        return;
      }
      conversation = await $store.dispatch('contactConversations/create', {
        params: {
          inboxId: targetInbox.id,
          sourceId: targetInbox.sourceId,
          contactId,
          assigneeId: $store.getters.getCurrentUserID,
        },
        isFromWhatsApp: false,
      });
    }

    const conversationAccountId =
      conversation.accountId ?? conversation.account_id ?? accountId.value;
    const conversationId = conversation.id;
    if (conversationAccountId && conversationId) {
      router.push(
        `/app/accounts/${conversationAccountId}/conversations/${conversationId}`
      );
    }
  } catch (error) {
    handleContactError(error);
  }
}

onMounted(async () => {
  if (!e164.value) return;
  try {
    const contact = await filterContactByNumber(e164.value);
    if (contact) savedContactId.value = contact.id;
  } catch {
    // Best-effort: leave the action as "Save contact" if the lookup fails.
  }
});
</script>

<template>
  <BaseBubble
    class="p-3 overflow-hidden min-w-[17rem]"
    data-bubble-name="contact"
    :hide-meta="hideMeta"
  >
    <div class="flex items-center gap-1.5 mb-2 text-n-slate-10">
      <Icon icon="i-teenyicons-user-circle-solid" class="size-3.5" />
      <span class="text-xs font-medium tracking-wide uppercase">
        {{ t('CONVERSATION.SHARED_CONTACT_LABEL') }}
      </span>
    </div>

    <button
      type="button"
      class="flex items-center w-full gap-3 text-left transition-colors rounded-lg hover:opacity-90"
      @click="viewContact"
    >
      <img
        v-if="showPhoto"
        :src="photo"
        :alt="displayName"
        class="rounded-full size-12 object-cover shrink-0 bg-n-alpha-2"
        @error="photoFailed = true"
      />
      <div
        v-else
        class="grid text-white rounded-full size-12 shrink-0 place-content-center"
        :class="avatarColor"
      >
        <span v-if="initial" class="text-lg font-medium">{{ initial }}</span>
        <Icon v-else icon="i-teenyicons-user-circle-solid" class="size-6" />
      </div>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-medium truncate text-n-slate-12">
          {{ displayName }}
        </p>
        <p v-if="organization" class="text-xs truncate text-n-slate-10">
          {{ organization }}
        </p>
        <p v-if="showPhoneLine" class="text-sm truncate text-n-slate-11">
          {{ formattedPhone }}
        </p>
        <p v-if="email" class="text-xs truncate text-n-slate-10">
          {{ email }}
        </p>
      </div>
    </button>

    <div
      v-if="hasActions"
      class="grid grid-cols-2 gap-2 pt-3 mt-3 border-t border-n-weak"
    >
      <button
        class="py-1.5 text-sm font-medium transition-colors rounded-lg text-n-brand bg-n-alpha-2 hover:bg-n-alpha-3"
        @click="startConversation"
      >
        {{ t('CONVERSATION.START_CONVERSATION') }}
      </button>
      <button
        class="py-1.5 text-sm font-medium transition-colors rounded-lg text-n-brand bg-n-alpha-2 hover:bg-n-alpha-3"
        @click="viewContact"
      >
        {{
          isSaved
            ? t('CONVERSATION.VIEW_CONTACT')
            : t('CONVERSATION.SAVE_CONTACT')
        }}
      </button>
    </div>
  </BaseBubble>
</template>
