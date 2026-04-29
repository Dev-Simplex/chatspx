<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useAdmin } from 'dashboard/composables/useAdmin';
import ContactInfoRow from './ContactInfoRow.vue';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';
import SocialIcons from './SocialIcons.vue';
import EditContact from './EditContact.vue';
import ContactMergeModal from 'dashboard/modules/contact/ContactMergeModal.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import ExportConversationModal from 'dashboard/components-next/message/ExportConversationModal.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import { BUS_EVENTS } from 'shared/constants/busEvents';

import {
  isAConversationRoute,
  isAInboxViewRoute,
  getConversationDashboardRoute,
} from '../../../../helper/routeHelpers';
import { emitter } from 'shared/helpers/mitt';

export default {
  components: {
    ContactInfoRow,
    EditContact,
    Thumbnail,
    ComposeConversation,
    SocialIcons,
    ContactMergeModal,
    ExportConversationModal,
    VoiceCallButton,
  },
  props: {
    contact: {
      type: Object,
      default: () => ({}),
    },
    showAvatar: {
      type: Boolean,
      default: true,
    },
  },
  emits: ['panelClose'],
  setup() {
    const { isAdmin } = useAdmin();
    return {
      isAdmin,
    };
  },
  data() {
    return {
      showEditModal: false,
      showDeleteModal: false,
      showExportModal: false,
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'contacts/getUIFlags',
      currentChat: 'getSelectedChat',
    }),
    contactProfileLink() {
      return `/app/accounts/${this.$route.params.accountId}/contacts/${this.contact.id}`;
    },
    additionalAttributes() {
      return this.contact.additional_attributes || {};
    },
    location() {
      const {
        country = '',
        city = '',
        country_code: countryCode,
      } = this.additionalAttributes;
      const cityAndCountry = [city, country].filter(item => !!item).join(', ');

      if (!cityAndCountry) {
        return '';
      }
      return this.findCountryFlag(countryCode, cityAndCountry);
    },
    socialProfiles() {
      const {
        social_profiles: socialProfiles,
        screen_name: twitterScreenName,
        social_telegram_user_name: telegramUsername,
      } = this.additionalAttributes;

      const telegram = socialProfiles?.telegram || telegramUsername || '';
      const twitter = socialProfiles?.twitter || twitterScreenName || '';

      return {
        ...(socialProfiles || {}),
        twitter,
        telegram,
      };
    },
    // Delete Modal
    confirmDeleteMessage() {
      return ` ${this.contact.name}?`;
    },
  },
  watch: {
    'contact.id': {
      handler(id) {
        this.$store.dispatch('contacts/fetchContactableInbox', id);
      },
      immediate: true,
    },
  },
  methods: {
    dynamicTime,
    toggleEditModal() {
      this.showEditModal = !this.showEditModal;
    },
    openComposeConversationModal(toggleFn) {
      toggleFn();
      // Flag to prevent triggering drag n drop,
      // When compose modal is active
      emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, true);
    },
    closeComposeConversationModal() {
      // Flag to enable drag n drop,
      // When compose modal is closed
      emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, false);
    },
    toggleDeleteModal() {
      this.showDeleteModal = !this.showDeleteModal;
    },
    confirmDeletion() {
      this.deleteContact(this.contact);
      this.closeDelete();
    },
    closeDelete() {
      this.showDeleteModal = false;
      this.showEditModal = false;
    },
    findCountryFlag(countryCode, cityAndCountry) {
      try {
        if (!countryCode) {
          return `${cityAndCountry} 🌎`;
        }

        const code = countryCode?.toLowerCase();
        return `${cityAndCountry} <span class="fi fi-${code} size-3.5"></span>`;
      } catch (error) {
        return '';
      }
    },
    async deleteContact({ id }) {
      try {
        await this.$store.dispatch('contacts/delete', id);
        this.$emit('panelClose');
        useAlert(this.$t('DELETE_CONTACT.API.SUCCESS_MESSAGE'));

        if (isAConversationRoute(this.$route.name)) {
          this.$router.push({
            name: getConversationDashboardRoute(this.$route.name),
          });
        } else if (isAInboxViewRoute(this.$route.name)) {
          this.$router.push({
            name: 'inbox_view',
          });
        } else if (this.$route.name !== 'contacts_dashboard') {
          this.$router.push({
            name: 'contacts_dashboard',
          });
        }
      } catch (error) {
        useAlert(
          error.message
            ? error.message
            : this.$t('DELETE_CONTACT.API.ERROR_MESSAGE')
        );
      }
    },
    openMergeModal() {
      this.$refs.mergeModal?.open();
    },
  },
};
</script>

<template>
  <div class="relative w-full pt-10 pb-6 px-6">
    <div class="flex flex-col items-center w-full">
      <!-- Avatar centered 120px -->
      <Thumbnail
        v-if="showAvatar"
        :src="contact.thumbnail"
        size="120px"
        :username="contact.name"
        :status="contact.availability_status"
        allow-preview
      />

      <!-- Name centered -->
      <div v-if="showAvatar" class="flex items-center gap-2 mt-3">
        <h3
          class="my-0 text-[19px] font-semibold capitalize break-words text-n-slate-12 text-center"
        >
          {{ contact.name }}
        </h3>
        <span
          v-if="contact.created_at"
          v-tooltip.top="
            `${$t('CONTACT_PANEL.CREATED_AT_LABEL')} ${dynamicTime(
              contact.created_at
            )}`
          "
          class="i-lucide-info text-sm text-n-slate-10"
        />
        <a
          :href="contactProfileLink"
          target="_blank"
          rel="noopener nofollow noreferrer"
          class="leading-3"
        >
          <span class="i-lucide-external-link text-sm text-n-slate-10" />
        </a>
      </div>

      <!-- Email/Phone centered -->
      <div class="flex flex-col items-center gap-0.5 mt-1">
        <span
          v-if="contact.email"
          class="text-[14px] wa-contact-secondary text-center"
        >
          {{ contact.email }}
        </span>
        <span
          v-if="contact.phoneNumber"
          class="text-[14px] wa-contact-secondary text-center"
        >
          {{ contact.phoneNumber }}
        </span>
      </div>

      <!-- Social icons -->
      <div class="mt-3">
        <SocialIcons :social-profiles="socialProfiles" />
      </div>

      <!-- Action buttons (5-column grid, WA style) -->
      <div class="grid grid-cols-5 gap-2 mt-6 w-full max-w-[260px] mx-auto">
        <ComposeConversation
          :contact-id="String(contact.id)"
          is-modal
          @close="closeComposeConversationModal"
        >
          <template #trigger="{ toggle }">
            <button
              v-tooltip.top-end="$t('CONTACT_PANEL.NEW_MESSAGE')"
              class="wa-action-btn"
              @click="openComposeConversationModal(toggle)"
            >
              <span class="i-lucide-message-circle size-5" />
              <span class="wa-action-label">
                {{ $t('CONTACT_PANEL.NEW_MESSAGE') }}
              </span>
            </button>
          </template>
        </ComposeConversation>
        <VoiceCallButton
          :phone="contact.phoneNumber"
          :contact-id="contact.id"
          icon="i-ri-phone-fill"
          size="sm"
          :tooltip-label="$t('CONTACT_PANEL.CALL')"
          slate
          faded
        />
        <button
          v-tooltip.top-end="$t('EDIT_CONTACT.BUTTON_LABEL')"
          class="wa-action-btn"
          @click="toggleEditModal"
        >
          <span class="i-lucide-pencil size-5" />
          <span class="wa-action-label">
            {{ $t('EDIT_CONTACT.BUTTON_LABEL') }}
          </span>
        </button>
        <button
          v-tooltip.top-end="$t('CONTACT_PANEL.MERGE_CONTACT')"
          class="wa-action-btn"
          :disabled="uiFlags.isMerging"
          @click="openMergeModal"
        >
          <span class="i-lucide-merge size-5" />
          <span class="wa-action-label">
            {{ $t('CONTACT_PANEL.MERGE_CONTACT') }}
          </span>
        </button>
        <button
          v-if="isAdmin"
          v-tooltip.top-end="$t('DELETE_CONTACT.BUTTON_LABEL')"
          class="wa-action-btn wa-action-btn--danger"
          :disabled="uiFlags.isDeleting"
          @click="toggleDeleteModal"
        >
          <span class="i-lucide-trash-2 size-5" />
          <span class="wa-action-label">
            {{ $t('DELETE_CONTACT.BUTTON_LABEL') }}
          </span>
        </button>
      </div>

      <!-- Additional info rows -->
      <div
        v-if="
          contact.identifier ||
          additionalAttributes.company_name ||
          location ||
          additionalAttributes.location ||
          additionalAttributes.description
        "
        class="flex flex-col items-start w-full gap-2 mt-4 pt-4 border-t border-n-weak/50"
      >
        <p
          v-if="additionalAttributes.description"
          class="break-words mb-0 text-sm text-n-slate-11"
        >
          {{ additionalAttributes.description }}
        </p>
        <ContactInfoRow
          v-if="contact.identifier"
          :value="contact.identifier"
          icon="contact-identify"
          emoji="🪪"
          :title="$t('CONTACT_PANEL.IDENTIFIER')"
        />
        <ContactInfoRow
          v-if="additionalAttributes.company_name"
          :value="additionalAttributes.company_name"
          icon="building-bank"
          emoji="🏢"
          :title="$t('CONTACT_PANEL.COMPANY')"
        />
        <ContactInfoRow
          v-if="location || additionalAttributes.location"
          :value="location || additionalAttributes.location"
          icon="map"
          emoji="🌍"
          :title="$t('CONTACT_PANEL.LOCATION')"
        />
      </div>
    </div>

    <EditContact
      v-if="showEditModal"
      :show="showEditModal"
      :contact="contact"
      @cancel="toggleEditModal"
    />
    <ContactMergeModal ref="mergeModal" :primary-contact="contact" />
    <ExportConversationModal
      :show="showExportModal"
      :conversations="currentChat?.id ? [currentChat] : []"
      :contact="contact"
      @close="showExportModal = false"
    />
    <woot-delete-modal
      v-if="showDeleteModal"
      v-model:show="showDeleteModal"
      :on-close="closeDelete"
      :on-confirm="confirmDeletion"
      :title="$t('DELETE_CONTACT.CONFIRM.TITLE')"
      :message="$t('DELETE_CONTACT.CONFIRM.MESSAGE')"
      :message-value="confirmDeleteMessage"
      :confirm-text="$t('DELETE_CONTACT.CONFIRM.YES')"
      :reject-text="$t('DELETE_CONTACT.CONFIRM.NO')"
    />
  </div>
</template>
