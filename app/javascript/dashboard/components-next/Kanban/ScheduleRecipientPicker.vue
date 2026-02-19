<script setup>
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

defineProps({
  showSelector: {
    type: Boolean,
    default: false,
  },
  searchQuery: {
    type: String,
    default: '',
  },
  searchResults: {
    type: Array,
    default: () => [],
  },
  isSearching: {
    type: Boolean,
    default: false,
  },
  selectedContact: {
    type: Object,
    default: null,
  },
  selectedConversation: {
    type: Object,
    default: null,
  },
  contactInfo: {
    type: Object,
    default: null,
  },
  isFetchingConversations: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits([
  'update:searchQuery',
  'select-contact',
  'clear-contact',
]);

const { t } = useI18n();

const contactName = contact =>
  contact?.name ||
  contact?.identifier ||
  contact?.email ||
  t('KANBAN.ITEMS.UNNAMED_CONTACT');

const contactPhone = contact =>
  contact?.phone_number ||
  contact?.phoneNumber ||
  contact?.identifier ||
  contact?.email ||
  '';

const contactAvatar = contact =>
  contact?.thumbnail || contact?.avatar_url || contact?.avatar || '';
</script>

<template>
  <div class="space-y-3">
    <div
      v-if="contactInfo"
      class="rounded-lg border border-n-weak bg-n-solid-3 px-4 py-3"
    >
      <div class="flex items-center gap-3">
        <Avatar :src="contactInfo.avatar" :name="contactInfo.name" :size="40" />
        <div class="min-w-0">
          <p class="truncate text-sm font-semibold text-n-slate-12">
            {{ contactInfo.name }}
          </p>
          <p
            v-if="contactInfo.phone"
            class="truncate text-xs font-mono text-n-slate-10"
          >
            {{ contactInfo.phone }}
          </p>
        </div>
      </div>
    </div>

    <div v-if="showSelector" class="space-y-2">
      <label class="text-sm font-semibold text-n-slate-12">
        {{ t('KANBAN.SCHEDULED_MESSAGES.CONTACT') }}
      </label>

      <div v-if="!selectedContact" class="relative">
        <Icon
          icon="i-lucide-search"
          class="pointer-events-none absolute left-3.5 top-1/2 size-4 -translate-y-1/2 text-n-slate-10"
        />
        <input
          :value="searchQuery"
          type="search"
          :placeholder="
            t('KANBAN.SCHEDULED_MESSAGES.CONTACT_SEARCH_PLACEHOLDER')
          "
          class="schedule-contact-search-input w-full rounded-lg border border-n-weak bg-n-solid-2 py-2.5 !pl-11 pr-3 text-sm leading-5 text-n-slate-12 appearance-none"
          @input="emit('update:searchQuery', $event.target.value)"
        />
      </div>

      <div
        v-if="isSearching"
        class="flex items-center gap-2 py-2 text-sm text-n-slate-10"
      >
        <Spinner class="!size-4" />
        {{ t('KANBAN.LOADING') }}
      </div>

      <div
        v-else-if="
          !selectedContact && searchQuery.trim() && searchResults.length
        "
        class="max-h-60 overflow-y-auto rounded-lg border border-n-weak bg-n-solid-2"
      >
        <button
          v-for="contact in searchResults"
          :key="contact.id"
          type="button"
          class="flex w-full items-center gap-3 border-b border-n-weak px-3 py-2.5 text-left last:border-0 hover:bg-n-solid-3"
          @click="emit('select-contact', contact)"
        >
          <Avatar
            :src="contactAvatar(contact)"
            :name="contactName(contact)"
            :size="32"
          />
          <div class="min-w-0">
            <p class="truncate text-sm font-medium text-n-slate-12">
              {{ contactName(contact) }}
            </p>
            <p class="truncate text-xs font-mono text-n-slate-10">
              {{ contactPhone(contact) }}
            </p>
          </div>
        </button>
      </div>

      <div
        v-else-if="
          !selectedContact && searchQuery.trim() && !searchResults.length
        "
        class="rounded-lg border border-dashed border-n-weak px-3 py-4 text-center text-xs text-n-slate-10"
      >
        {{ t('KANBAN.SCHEDULED_MESSAGES.NO_CONTACTS_FOUND') }}
      </div>

      <div
        v-if="selectedContact"
        class="rounded-lg border border-n-blue-8 bg-n-blue-3 px-3 py-3"
      >
        <div class="flex items-center justify-between gap-3">
          <div class="flex min-w-0 items-center gap-2.5">
            <Avatar
              :src="contactAvatar(selectedContact)"
              :name="contactName(selectedContact)"
              :size="34"
            />
            <div class="min-w-0">
              <p class="truncate text-sm font-semibold text-n-blue-12">
                {{ contactName(selectedContact) }}
              </p>
              <p class="truncate text-xs font-mono text-n-blue-10">
                {{ contactPhone(selectedContact) }}
              </p>
            </div>
          </div>
          <button
            type="button"
            class="rounded p-1 text-n-blue-11 hover:bg-n-blue-4"
            @click="emit('clear-contact')"
          >
            <Icon icon="i-lucide-x" class="size-4" />
          </button>
        </div>
        <p v-if="isFetchingConversations" class="mt-2 text-xs text-n-blue-10">
          {{ t('KANBAN.LOADING') }}
        </p>
        <p
          v-else-if="!selectedConversation"
          class="mt-2 text-xs text-n-blue-10"
        >
          {{ t('KANBAN.SCHEDULED_MESSAGES.CONTACT_NO_CONVERSATION_HINT') }}
        </p>
      </div>
    </div>
  </div>
</template>

<style scoped>
.schedule-contact-search-input::-webkit-search-decoration,
.schedule-contact-search-input::-webkit-search-cancel-button,
.schedule-contact-search-input::-webkit-search-results-button,
.schedule-contact-search-input::-webkit-search-results-decoration {
  -webkit-appearance: none;
}
</style>
