<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { INPUT_TYPES } from 'dashboard/components-next/taginput/helper/tagInputHelper.js';
import {
  formatPhoneDisplay,
  isPhoneLikeInput,
} from 'dashboard/components-next/NewConversation/helpers/composeConversationHelper.js';

import TagInput from 'dashboard/components-next/taginput/TagInput.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  contacts: {
    type: Array,
    required: true,
  },
  selectedContact: {
    type: Object,
    default: null,
  },
  showContactsDropdown: {
    type: Boolean,
    required: true,
  },
  isLoading: {
    type: Boolean,
    required: true,
  },
  isCreatingContact: {
    type: Boolean,
    required: true,
  },
  contactId: {
    type: String,
    default: null,
  },
  contactableInboxesList: {
    type: Array,
    default: () => [],
  },
  showInboxesDropdown: {
    type: Boolean,
    required: true,
  },
  hasErrors: {
    type: Boolean,
    default: false,
  },
  mode: {
    type: String,
    default: 'search',
    validator: value => ['search', 'dial'].includes(value),
  },
});

const emit = defineEmits([
  'searchContacts',
  'setSelectedContact',
  'clearSelectedContact',
  'updateDropdown',
  'toggleInputMode',
]);

const i18nPrefix = 'COMPOSE_NEW_CONVERSATION.FORM.CONTACT_SELECTOR';
const { t } = useI18n();

const inputType = ref(INPUT_TYPES.EMAIL);
const currentInput = ref('');
const dialInput = ref('');
const dialInputRef = ref(null);

const isDialMode = computed(
  () =>
    props.mode === 'dial' && !props.selectedContact && !props.isCreatingContact
);

const phoneInfo = computed(() => {
  if (!isPhoneLikeInput(currentInput.value)) return null;
  return formatPhoneDisplay(currentInput.value);
});

const showPhoneCta = computed(() => {
  if (props.selectedContact || props.isCreatingContact) return false;
  return !!phoneInfo.value;
});

const contactsList = computed(() => {
  return props.contacts?.map(({ name, id, thumbnail, email, ...rest }) => ({
    id,
    label: email ? `${name} (${email})` : name,
    value: id,
    thumbnail: { name, src: thumbnail },
    ...rest,
    name,
    email,
    action: 'contact',
  }));
});

const selectedContactLabel = computed(() => {
  const { name, email = '', phoneNumber = '' } = props.selectedContact || {};
  if (email) {
    return `${name} (${email})`;
  }
  if (phoneNumber) {
    return `${name} (${phoneNumber})`;
  }
  return name || '';
});

const selectedContactInitial = computed(() => {
  const name = props.selectedContact?.name || '';
  const parts = name.trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return '?';
  if (parts.length === 1) return parts[0][0]?.toUpperCase() || '?';
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
});

const errorClass = computed(() => {
  return props.hasErrors
    ? '[&_input]:placeholder:!text-n-ruby-9 [&_input]:dark:placeholder:!text-n-ruby-9'
    : '';
});

const dialToggleTooltip = computed(() =>
  props.mode === 'dial'
    ? t(`${i18nPrefix}.SEARCH_TOGGLE_TOOLTIP`)
    : t(`${i18nPrefix}.DIAL_TOGGLE_TOOLTIP`)
);

const handleInput = value => {
  currentInput.value = value || '';
  inputType.value = isPhoneLikeInput(value)
    ? INPUT_TYPES.TEL
    : INPUT_TYPES.EMAIL;
  // Skip contact search when user is clearly entering a phone number —
  // the CTA card takes over and avoids confusing partial name matches.
  if (isPhoneLikeInput(value)) {
    emit('updateDropdown', 'contacts', false);
    return;
  }
  emit('searchContacts', value);
};

const confirmPhoneCta = () => {
  if (!phoneInfo.value) return;
  const value = phoneInfo.value.e164 || phoneInfo.value.formatted;
  if (!value) return;
  emit('setSelectedContact', {
    value,
    action: 'create',
    name: phoneInfo.value.formatted,
    phoneNumber: value,
  });
  currentInput.value = '';
  dialInput.value = '';
};

const onPhoneCtaKeydown = event => {
  if (event.key !== 'Enter') return;
  event.preventDefault();
  confirmPhoneCta();
};

const handleTagInputAdd = payload => {
  // When the user hits Enter on a phone-like input, prefer the normalized
  // E.164 we already compute so the backend receives a clean number.
  if (phoneInfo.value && payload?.action === 'create') {
    confirmPhoneCta();
    return;
  }
  emit('setSelectedContact', payload);
};

const onDialInput = event => {
  const value = event.target.value || '';
  dialInput.value = value;
  currentInput.value = value;
  inputType.value = INPUT_TYPES.TEL;
};

const onDialKeydown = event => {
  if (event.key !== 'Enter') return;
  if (!phoneInfo.value) return;
  event.preventDefault();
  confirmPhoneCta();
};

watch(
  () => props.mode,
  newMode => {
    if (newMode === 'dial') {
      nextTick(() => {
        dialInputRef.value?.focus();
      });
    } else {
      dialInput.value = '';
      currentInput.value = '';
      inputType.value = INPUT_TYPES.EMAIL;
    }
  }
);
</script>

<template>
  <div class="relative px-5 py-4 overflow-y-visible">
    <div
      class="flex items-center w-full gap-3 rounded-2xl border border-n-weak/70 bg-n-solid-1 px-4 py-3.5 shadow-sm transition-all duration-150 focus-within:border-n-brand/50 focus-within:ring-[3px] focus-within:ring-n-brand/25 focus-within:shadow-md"
      :class="{
        '!ring-2 !ring-n-ruby-9/40 !border-n-ruby-9/60': hasErrors,
      }"
    >
      <span
        v-if="isDialMode"
        class="i-lucide-phone size-[18px] text-n-slate-11 flex-shrink-0"
        aria-hidden="true"
      />
      <span
        v-else
        class="i-lucide-search size-[18px] text-n-slate-11 flex-shrink-0"
        aria-hidden="true"
      />

      <div
        v-if="isCreatingContact"
        class="flex items-center gap-2 min-h-7 flex-1"
      >
        <span
          class="i-lucide-loader-2 size-4 text-n-brand animate-spin"
          aria-hidden="true"
        />
        <span class="text-sm text-n-slate-12">
          {{ t(`${i18nPrefix}.CONTACT_CREATING`) }}
        </span>
      </div>
      <div
        v-else-if="selectedContact"
        class="flex items-center gap-2 rounded-full bg-n-alpha-1 border border-n-weak/60 min-h-7 min-w-0 pl-1 pr-3 py-0.5 flex-1"
      >
        <span
          class="size-6 rounded-full bg-n-brand/15 text-n-brand text-[11px] font-semibold grid place-items-center flex-shrink-0"
          aria-hidden="true"
        >
          {{ selectedContactInitial }}
        </span>
        <span class="text-sm font-medium truncate text-n-slate-12">
          {{ selectedContactLabel }}
        </span>
        <Button
          v-if="!contactId"
          variant="ghost"
          icon="i-lucide-x"
          color="slate"
          :disabled="contactId"
          size="xs"
          class="ltr:ml-auto rtl:mr-auto"
          @click="emit('clearSelectedContact')"
        />
      </div>
      <input
        v-else-if="isDialMode"
        ref="dialInputRef"
        :value="dialInput"
        type="tel"
        inputmode="tel"
        autocomplete="off"
        :placeholder="t(`${i18nPrefix}.DIAL_PLACEHOLDER`)"
        class="flex-1 min-h-7 bg-transparent outline-none border-0 text-base font-medium text-n-slate-12 placeholder:text-n-slate-10"
        @input="onDialInput"
        @keydown="onDialKeydown"
      />
      <TagInput
        v-else
        :placeholder="t(`${i18nPrefix}.TAG_INPUT_PLACEHOLDER`)"
        mode="single"
        :menu-items="contactsList"
        :show-dropdown="showContactsDropdown && !showPhoneCta"
        :is-loading="isLoading"
        :disabled="contactableInboxesList?.length > 0 && showInboxesDropdown"
        allow-create
        :type="inputType"
        class="flex-1 min-h-7 [&_input]:!text-base [&_input]:!font-medium"
        :class="errorClass"
        focus-on-mount
        @input="handleInput"
        @on-click-outside="emit('updateDropdown', 'contacts', false)"
        @add="handleTagInputAdd"
        @remove="emit('clearSelectedContact')"
      />
      <button
        v-if="!selectedContact && !isCreatingContact"
        type="button"
        class="size-8 rounded-lg grid place-items-center flex-shrink-0 transition-colors duration-150"
        :class="
          mode === 'dial'
            ? 'bg-n-brand/15 text-n-brand'
            : 'text-n-slate-10 hover:text-n-slate-12 hover:bg-n-alpha-2'
        "
        :title="dialToggleTooltip"
        :aria-label="dialToggleTooltip"
        :aria-pressed="mode === 'dial'"
        @click="emit('toggleInputMode')"
      >
        <svg
          v-if="mode !== 'dial'"
          viewBox="0 0 24 24"
          class="size-[18px]"
          fill="currentColor"
          aria-hidden="true"
        >
          <path
            d="M12 23C11.45 23 10.9792 22.8042 10.5875 22.4125C10.1958 22.0208 10 21.55 10 21C10 20.45 10.1958 19.9792 10.5875 19.5875C10.9792 19.1958 11.45 19 12 19C12.55 19 13.0208 19.1958 13.4125 19.5875C13.8042 19.9792 14 20.45 14 21C14 21.55 13.8042 22.0208 13.4125 22.4125C13.0208 22.8042 12.55 23 12 23ZM6 5C5.45 5 4.97917 4.80417 4.5875 4.4125C4.19583 4.02083 4 3.55 4 3C4 2.45 4.19583 1.97917 4.5875 1.5875C4.97917 1.19583 5.45 1 6 1C6.55 1 7.02083 1.19583 7.4125 1.5875C7.80417 1.97917 8 2.45 8 3C8 3.55 7.80417 4.02083 7.4125 4.4125C7.02083 4.80417 6.55 5 6 5ZM6 11C5.45 11 4.97917 10.8042 4.5875 10.4125C4.19583 10.0208 4 9.55 4 9C4 8.45 4.19583 7.97917 4.5875 7.5875C4.97917 7.19583 5.45 7 6 7C6.55 7 7.02083 7.19583 7.4125 7.5875C7.80417 7.97917 8 8.45 8 9C8 9.55 7.80417 10.0208 7.4125 10.4125C7.02083 10.8042 6.55 11 6 11ZM6 17C5.45 17 4.97917 16.8042 4.5875 16.4125C4.19583 16.0208 4 15.55 4 15C4 14.45 4.19583 13.9792 4.5875 13.5875C4.97917 13.1958 5.45 13 6 13C6.55 13 7.02083 13.1958 7.4125 13.5875C7.80417 13.9792 8 14.45 8 15C8 15.55 7.80417 16.0208 7.4125 16.4125C7.02083 16.8042 6.55 17 6 17ZM18 5C17.45 5 16.9792 4.80417 16.5875 4.4125C16.1958 4.02083 16 3.55 16 3C16 2.45 16.1958 1.97917 16.5875 1.5875C16.9792 1.19583 17.45 1 18 1C18.55 1 19.0208 1.19583 19.4125 1.5875C19.8042 1.97917 20 2.45 20 3C20 3.55 19.8042 4.02083 19.4125 4.4125C19.0208 4.80417 18.55 5 18 5ZM12 17C11.45 17 10.9792 16.8042 10.5875 16.4125C10.1958 16.0208 10 15.55 10 15C10 14.45 10.1958 13.9792 10.5875 13.5875C10.9792 13.1958 11.45 13 12 13C12.55 13 13.0208 13.1958 13.4125 13.5875C13.8042 13.9792 14 14.45 14 15C14 15.55 13.8042 16.0208 13.4125 16.4125C13.0208 16.8042 12.55 17 12 17ZM18 17C17.45 17 16.9792 16.8042 16.5875 16.4125C16.1958 16.0208 16 15.55 16 15C16 14.45 16.1958 13.9792 16.5875 13.5875C16.9792 13.1958 17.45 13 18 13C18.55 13 19.0208 13.1958 19.4125 13.5875C19.8042 13.9792 20 14.45 20 15C20 15.55 19.8042 16.0208 19.4125 16.4125C19.0208 16.8042 18.55 17 18 17ZM18 11C17.45 11 16.9792 10.8042 16.5875 10.4125C16.1958 10.0208 16 9.55 16 9C16 8.45 16.1958 7.97917 16.5875 7.5875C16.9792 7.19583 17.45 7 18 7C18.55 7 19.0208 7.19583 19.4125 7.5875C19.8042 7.97917 20 8.45 20 9C20 9.55 19.8042 10.0208 19.4125 10.4125C19.0208 10.8042 18.55 11 18 11ZM12 11C11.45 11 10.9792 10.8042 10.5875 10.4125C10.1958 10.0208 10 9.55 10 9C10 8.45 10.1958 7.97917 10.5875 7.5875C10.9792 7.19583 11.45 7 12 7C12.55 7 13.0208 7.19583 13.4125 7.5875C13.8042 7.97917 14 8.45 14 9C14 9.55 13.8042 10.0208 13.4125 10.4125C13.0208 10.8042 12.55 11 12 11ZM12 5C11.45 5 10.9792 4.80417 10.5875 4.4125C10.1958 4.02083 10 3.55 10 3C10 2.45 10.1958 1.97917 10.5875 1.5875C10.9792 1.19583 11.45 1 12 1C12.55 1 13.0208 1.19583 13.4125 1.5875C13.8042 1.97917 14 2.45 14 3C14 3.55 13.8042 4.02083 13.4125 4.4125C13.0208 4.80417 12.55 5 12 5Z"
          />
        </svg>
        <span v-else class="i-lucide-search size-[18px]" aria-hidden="true" />
      </button>
    </div>

    <p
      v-if="!selectedContact && !isCreatingContact && !showPhoneCta"
      class="mt-2 px-1 text-xs text-n-slate-10"
    >
      {{ t(`${i18nPrefix}.TAG_INPUT_HINT`) }}
    </p>

    <button
      v-if="showPhoneCta"
      type="button"
      class="mt-3 w-full flex items-center gap-3 rounded-2xl border border-n-weak/80 bg-gradient-to-br from-n-solid-1 to-n-alpha-1 px-4 py-3.5 text-left shadow-sm transition-all duration-150 hover:border-n-brand/40 hover:shadow-md focus:outline-none focus:ring-[3px] focus:ring-n-brand/25"
      @click="confirmPhoneCta"
      @keydown="onPhoneCtaKeydown"
    >
      <span
        class="size-9 rounded-xl bg-n-alpha-2 grid place-items-center text-xl leading-none flex-shrink-0"
        aria-hidden="true"
      >
        {{ phoneInfo.countryFlag || '📞' }}
      </span>
      <span class="flex-1 min-w-0">
        <span class="block text-sm font-semibold text-n-slate-12">
          {{ t(`${i18nPrefix}.PHONE_CTA.START_CONVERSATION`) }}
        </span>
        <span class="block text-sm font-medium text-n-slate-11 truncate">
          {{ phoneInfo.formatted }}
        </span>
      </span>
      <span class="flex items-center gap-1.5 flex-shrink-0">
        <kbd
          class="px-1.5 py-0.5 rounded-md border border-n-weak/80 bg-n-alpha-1 text-[10px] font-semibold text-n-slate-11 font-mono"
        >
          {{ 'Enter' }}
        </kbd>
      </span>
    </button>
  </div>
</template>
