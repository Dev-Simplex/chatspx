<script setup>
import { computed, nextTick, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import ContactAPI from 'dashboard/api/contacts.js';

const props = defineProps({
  show: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['close', 'select']);

const { t } = useI18n();

// === local state ===
const activeTab = ref('contact'); // 'contact' | 'manual'
const dialogRef = ref(null);

const contactSearch = ref('');
const contactResults = ref([]);
const contactsLoading = ref(false);
const selectedContactId = ref(null);
let contactSearchAbort = null;

const manualName = ref('');
const manualPhone = ref('');

const phoneRegex = /^\+?55?\d{10,11}$/;
const onlyDigits = value => (value || '').replace(/\D/g, '');

// === Aba "Contato salvo" ===
const fetchInitialContacts = async () => {
  if (contactSearchAbort) contactSearchAbort.abort();
  contactsLoading.value = true;
  try {
    const response = await ContactAPI.get(1, 'name', '');
    contactResults.value = response?.data?.payload || [];
  } catch {
    contactResults.value = [];
  } finally {
    contactsLoading.value = false;
  }
};

const doContactSearch = async term => {
  const trimmed = (term || '').trim();
  if (!trimmed) {
    fetchInitialContacts();
    return;
  }
  if (contactSearchAbort) contactSearchAbort.abort();
  contactSearchAbort = new AbortController();
  contactsLoading.value = true;
  try {
    const response = await ContactAPI.search(trimmed, 1, 'name', '', {
      signal: contactSearchAbort.signal,
    });
    contactResults.value = response?.data?.payload || [];
  } catch (error) {
    if (error?.name !== 'CanceledError' && error?.name !== 'AbortError') {
      contactResults.value = [];
    }
  } finally {
    contactsLoading.value = false;
  }
};

const debouncedContactSearch = (() => {
  let timer = null;
  return term => {
    clearTimeout(timer);
    timer = setTimeout(() => doContactSearch(term), 250);
  };
})();

const selectedContact = computed(() =>
  contactResults.value.find(c => c.id === selectedContactId.value)
);

// === Aba "Disque o número" (manual) ===
const formatBrPhone = digits => {
  const d = digits.slice(0, 13);
  if (!d) return '';
  let rest = d;
  let prefix = '';
  if (rest.startsWith('55')) {
    prefix = '+55 ';
    rest = rest.slice(2);
  }
  if (rest.length <= 2) return `${prefix}(${rest}`;
  if (rest.length <= 7) {
    return `${prefix}(${rest.slice(0, 2)}) ${rest.slice(2)}`;
  }
  if (rest.length <= 10) {
    return `${prefix}(${rest.slice(0, 2)}) ${rest.slice(2, 6)}-${rest.slice(6)}`;
  }
  return `${prefix}(${rest.slice(0, 2)}) ${rest.slice(2, 7)}-${rest.slice(7, 11)}`;
};

const onManualPhoneInput = event => {
  const digits = onlyDigits(event.target.value);
  manualPhone.value = formatBrPhone(digits);
};

const manualPhoneIsValid = computed(() => {
  const digits = onlyDigits(manualPhone.value);
  return phoneRegex.test(digits);
});

const manualReady = computed(
  () => manualName.value.trim().length > 0 && manualPhoneIsValid.value
);

// === Preview unificado ===
const previewName = computed(() => {
  if (activeTab.value === 'contact') return selectedContact.value?.name || '';
  return manualName.value.trim();
});

const previewPhone = computed(() => {
  if (activeTab.value === 'contact') {
    return selectedContact.value?.phone_number || '';
  }
  return manualPhone.value;
});

const previewAvatarUrl = computed(() => {
  if (activeTab.value === 'contact') {
    return (
      selectedContact.value?.thumbnail ||
      selectedContact.value?.avatar_url ||
      ''
    );
  }
  return '';
});

const previewInitials = computed(() => {
  const name = previewName.value || '?';
  const parts = name.trim().split(/\s+/);
  return ((parts[0]?.[0] || '') + (parts[1]?.[0] || '')).toUpperCase() || '?';
});

const previewSourceLabel = computed(() => {
  if (activeTab.value === 'contact') {
    return t('CONVERSATION.SHARE_CONTACT.TAB_CONTACT');
  }
  return t('CONVERSATION.SHARE_CONTACT.TAB_MANUAL');
});

const canSend = computed(() => {
  if (activeTab.value === 'contact') {
    return Boolean(selectedContactId.value && previewPhone.value);
  }
  return manualReady.value;
});

// === handlers ===
const close = () => emit('close');

const handleSubmit = () => {
  if (!canSend.value) return;
  let payload;
  if (activeTab.value === 'contact') {
    payload = {
      source: 'contact',
      name: selectedContact.value?.name,
      phone: selectedContact.value?.phone_number,
      contactId: selectedContact.value?.id,
    };
  } else {
    payload = {
      source: 'manual',
      name: manualName.value.trim(),
      phone: manualPhone.value,
    };
  }
  emit('select', payload);
};

const handleBackdropClick = event => {
  if (event.target === dialogRef.value) close();
};

const onKeyDown = event => {
  if (!props.show) return;
  if (event.key === 'Escape') {
    event.preventDefault();
    close();
  }
};

const resetState = () => {
  activeTab.value = 'contact';
  contactSearch.value = '';
  contactResults.value = [];
  selectedContactId.value = null;
  manualName.value = '';
  manualPhone.value = '';
};

watch(contactSearch, value => {
  selectedContactId.value = null;
  debouncedContactSearch(value);
});

watch(activeTab, async tab => {
  await nextTick();
  if (tab === 'contact' && contactResults.value.length === 0) {
    fetchInitialContacts();
  }
});

watch(
  () => props.show,
  isOpen => {
    if (isOpen) {
      resetState();
      // Carrega lista inicial automaticamente — sem precisar digitar.
      nextTick(() => fetchInitialContacts());
    }
  },
  { immediate: true }
);

onMounted(() => {
  if (props.show) {
    resetState();
    fetchInitialContacts();
  }
});
</script>

<template>
  <Teleport to="body">
    <Transition
      enter-active-class="transition-opacity duration-150 ease-out"
      enter-from-class="opacity-0"
      enter-to-class="opacity-100"
      leave-active-class="transition-opacity duration-100 ease-in"
      leave-from-class="opacity-100"
      leave-to-class="opacity-0"
    >
      <div
        v-if="show"
        ref="dialogRef"
        role="dialog"
        aria-modal="true"
        aria-labelledby="share-contact-modal-title"
        class="fixed inset-0 z-[1000] flex items-start justify-center px-4 pt-[10vh] pb-8 bg-n-alpha-black1 backdrop-blur-[4px]"
        @click="handleBackdropClick"
        @keydown="onKeyDown"
      >
        <div
          class="w-full max-w-xl flex flex-col bg-n-solid-1 dark:bg-[#233138] border border-n-slate-3 dark:border-n-slate-7 rounded-xl shadow-[0_8px_32px_rgba(11,20,26,0.18)] overflow-hidden max-h-[80vh]"
          @click.stop
        >
          <header
            class="flex items-center justify-between gap-3 px-5 py-4 border-b border-n-slate-3 dark:border-n-slate-7"
          >
            <div class="flex items-center gap-2">
              <span class="i-lucide-user-round-plus size-5 text-n-brand" />
              <h2
                id="share-contact-modal-title"
                class="text-base font-medium text-n-slate-12"
              >
                {{ t('CONVERSATION.SHARE_CONTACT.MODAL_TITLE') }}
              </h2>
            </div>
            <button
              type="button"
              class="flex items-center justify-center size-8 rounded-md text-n-slate-11 hover:bg-n-slate-3 dark:hover:bg-n-slate-7"
              :aria-label="t('GENERAL.CLOSE')"
              @click="close"
            >
              <span class="i-lucide-x size-5" />
            </button>
          </header>

          <nav
            class="flex items-center gap-1 px-3 pt-2 border-b border-n-slate-3 dark:border-n-slate-7"
            role="tablist"
            :aria-label="t('CONVERSATION.SHARE_CONTACT.MODAL_TITLE')"
          >
            <button
              v-for="tab in [
                {
                  id: 'contact',
                  label: t('CONVERSATION.SHARE_CONTACT.TAB_CONTACT'),
                },
                {
                  id: 'manual',
                  label: t('CONVERSATION.SHARE_CONTACT.TAB_MANUAL'),
                },
              ]"
              :key="tab.id"
              type="button"
              role="tab"
              :aria-selected="activeTab === tab.id"
              :data-tab="tab.id"
              class="relative px-3 py-2 text-sm font-medium transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-n-brand/40 rounded-md"
              :class="
                activeTab === tab.id
                  ? 'text-n-brand'
                  : 'text-n-slate-11 hover:text-n-slate-12'
              "
              @click="activeTab = tab.id"
            >
              {{ tab.label }}
              <span
                v-if="activeTab === tab.id"
                class="absolute left-2 right-2 -bottom-px h-[2px] bg-n-brand rounded-full"
              />
            </button>
          </nav>

          <div class="flex-1 flex flex-col min-h-0 overflow-hidden">
            <!-- ABA: Contato salvo -->
            <section
              v-if="activeTab === 'contact'"
              class="flex-1 flex flex-col gap-3 pb-4 min-h-0 overflow-hidden"
              role="tabpanel"
            >
              <div class="shrink-0 flex items-center px-3 py-[7px]">
                <div
                  class="flex items-center w-full h-[35px] rounded-lg px-3 gap-3 transition-colors duration-150 cursor-text bg-n-solid-1 dark:bg-[#202c33] border border-[rgba(11,20,26,0.08)] dark:border-[#2a3942]"
                >
                  <div
                    class="flex items-center justify-center shrink-0 transition-colors duration-200"
                  >
                    <span
                      class="i-lucide-search size-4 text-[#54656f] dark:text-[#aebac1]"
                      aria-hidden="true"
                    />
                  </div>
                  <input
                    v-model="contactSearch"
                    type="text"
                    autocomplete="off"
                    spellcheck="false"
                    :placeholder="
                      t('CONVERSATION.SHARE_CONTACT.SEARCH_CONTACT')
                    "
                    :aria-label="t('CONVERSATION.SHARE_CONTACT.SEARCH_CONTACT')"
                    class="reset-base no-margin flex-1 min-w-0 border-0 bg-transparent text-[15px] leading-[35px] p-0 m-0 shadow-none appearance-none rounded-none w-full font-normal cursor-text select-text focus:border-0 focus:bg-transparent focus:shadow-none focus:outline-none focus:ring-0 text-[#111b21] dark:text-[#e9edef] placeholder:text-[#8696a0] placeholder:font-normal caret-[var(--wa-primary)]"
                  />
                </div>
              </div>
              <div
                v-if="contactsLoading"
                class="shrink-0 flex items-center justify-center py-8 text-sm text-n-slate-11"
              >
                <span class="i-lucide-loader-2 size-5 animate-spin" />
              </div>
              <div
                v-else-if="contactResults.length === 0"
                class="shrink-0 flex flex-col items-center gap-2 py-8 text-sm text-n-slate-11 text-center"
              >
                <span class="i-lucide-search-x size-6 text-n-slate-9" />
                {{ t('CONVERSATION.SHARE_CONTACT.NO_CONTACTS_FOUND') }}
              </div>
              <ul
                v-else
                class="flex-1 min-h-0 overflow-y-auto flex flex-col gap-1 px-3"
              >
                <li
                  v-for="contact in contactResults"
                  :key="contact.id"
                  role="option"
                  :aria-selected="selectedContactId === contact.id"
                  class="flex items-center gap-3 px-3 py-2 rounded-lg cursor-pointer transition-colors"
                  :class="
                    selectedContactId === contact.id
                      ? 'bg-n-brand/10 ring-1 ring-n-brand/30'
                      : 'hover:bg-n-slate-2 dark:hover:bg-n-slate-8'
                  "
                  @click="selectedContactId = contact.id"
                >
                  <img
                    v-if="contact.thumbnail"
                    :src="contact.thumbnail"
                    alt=""
                    class="size-9 rounded-full object-cover"
                  />
                  <span
                    v-else
                    class="size-9 rounded-full bg-n-brand/15 text-n-brand text-sm font-medium flex items-center justify-center"
                  >
                    {{
                      (
                        (contact.name || '?')
                          .split(' ')
                          .map(p => p[0])
                          .slice(0, 2)
                          .join('') || '?'
                      ).toUpperCase()
                    }}
                  </span>
                  <div class="flex flex-col min-w-0">
                    <span class="text-sm font-medium text-n-slate-12 truncate">
                      {{ contact.name }}
                    </span>
                    <span class="text-xs text-n-slate-11 truncate">
                      {{ contact.phone_number || contact.email }}
                    </span>
                  </div>
                </li>
              </ul>
            </section>

            <!-- ABA: Disque o número -->
            <section
              v-else
              class="flex-1 flex flex-col gap-3 px-5 py-4 min-h-0 overflow-y-auto"
              role="tabpanel"
            >
              <label class="flex flex-col gap-1.5">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CONVERSATION.SHARE_CONTACT.MANUAL_NAME') }}
                </span>
                <input
                  v-model="manualName"
                  type="text"
                  autocomplete="off"
                  class="w-full px-3 py-2.5 text-sm bg-n-alpha-1 dark:bg-n-alpha-black2 border border-n-slate-4 dark:border-n-slate-7 rounded-lg text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2 focus:ring-n-brand/40 focus:border-n-brand"
                />
              </label>
              <label class="flex flex-col gap-1.5">
                <span class="text-xs font-medium text-n-slate-11">
                  {{ t('CONVERSATION.SHARE_CONTACT.MANUAL_PHONE') }}
                </span>
                <input
                  :value="manualPhone"
                  type="tel"
                  autocomplete="off"
                  inputmode="tel"
                  :placeholder="
                    t('CONVERSATION.SHARE_CONTACT.MANUAL_PHONE_PLACEHOLDER')
                  "
                  class="w-full px-3 py-2.5 text-sm bg-n-alpha-1 dark:bg-n-alpha-black2 border rounded-lg text-n-slate-12 placeholder:text-n-slate-10 focus:outline-none focus:ring-2"
                  :class="
                    manualPhone && !manualPhoneIsValid
                      ? 'border-n-ruby-9 focus:ring-n-ruby-9/40 focus:border-n-ruby-9'
                      : 'border-n-slate-4 dark:border-n-slate-7 focus:ring-n-brand/40 focus:border-n-brand'
                  "
                  @input="onManualPhoneInput"
                />
                <span
                  v-if="manualPhone && !manualPhoneIsValid"
                  class="text-xs text-n-ruby-11"
                >
                  {{ t('CONVERSATION.SHARE_CONTACT.PHONE_INVALID') }}
                </span>
              </label>
            </section>

            <!-- Preview unificado -->
            <section
              class="shrink-0 flex flex-col gap-2 px-5 pt-3 pb-4 border-t border-n-slate-3 dark:border-n-slate-7 bg-n-solid-1 dark:bg-[#233138]"
            >
              <span
                class="text-xs font-medium uppercase tracking-wide text-n-slate-10"
              >
                {{ t('CONVERSATION.SHARE_CONTACT.PREVIEW_HEADING') }}
              </span>
              <div
                class="flex items-center gap-3 px-4 py-3 rounded-xl bg-n-alpha-1 dark:bg-n-alpha-black2 border border-n-slate-3 dark:border-n-slate-7"
              >
                <img
                  v-if="previewAvatarUrl"
                  :src="previewAvatarUrl"
                  alt=""
                  class="size-12 rounded-full object-cover"
                />
                <span
                  v-else
                  class="size-12 rounded-full bg-n-brand/15 text-n-brand text-base font-semibold flex items-center justify-center"
                >
                  {{ previewInitials }}
                </span>
                <div class="flex flex-col min-w-0 flex-1">
                  <span class="text-sm font-semibold text-n-slate-12 truncate">
                    {{ previewName || '—' }}
                  </span>
                  <span class="text-xs text-n-slate-11 truncate">
                    {{ previewPhone || '—' }}
                  </span>
                </div>
                <span
                  class="shrink-0 inline-flex items-center px-2 py-0.5 rounded-md bg-n-brand/15 text-xs font-medium text-n-brand"
                >
                  {{ previewSourceLabel }}
                </span>
              </div>
            </section>
          </div>

          <footer
            class="flex items-center justify-end gap-2 px-5 py-3 border-t border-n-slate-3 dark:border-n-slate-7 bg-n-alpha-1 dark:bg-n-alpha-black2"
          >
            <button
              type="button"
              class="px-3 py-2 text-sm font-medium rounded-lg text-n-slate-11 hover:bg-n-slate-3 dark:hover:bg-n-slate-7"
              @click="close"
            >
              {{ t('CONVERSATION.SHARE_CONTACT.CANCEL') }}
            </button>
            <button
              type="button"
              class="px-3 py-2 text-sm font-medium rounded-lg bg-n-brand text-white hover:bg-n-brand/90 disabled:opacity-50 disabled:cursor-not-allowed"
              :disabled="!canSend"
              data-testid="share-contact-submit"
              @click="handleSubmit"
            >
              {{ t('CONVERSATION.SHARE_CONTACT.SEND') }}
            </button>
          </footer>
        </div>
      </div>
    </Transition>
  </Teleport>
</template>
