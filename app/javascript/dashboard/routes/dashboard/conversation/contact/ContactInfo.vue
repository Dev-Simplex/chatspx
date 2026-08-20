<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import {
  DuplicateContactException,
  ExceptionWithMessage,
} from 'shared/helpers/CustomErrors';
import { dynamicTime } from 'shared/helpers/timeHelper';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { stripGroupSuffix } from 'dashboard/helper/whatsappGroupHelper';
import { emitter } from 'shared/helpers/mitt';
import {
  isAConversationRoute,
  isAInboxViewRoute,
  getConversationDashboardRoute,
} from '../../../../helper/routeHelpers';

import ContactInfoRow from './ContactInfoRow.vue';
import Thumbnail from 'dashboard/components/widgets/Thumbnail.vue';
import SocialIcons from './SocialIcons.vue';
import EditContact from './EditContact.vue';
// União dos dois lados, com dois cuidados: `VoiceCallButton` aparecia nos DOIS
// (entra uma vez só) e `BUS_EVENTS` já está importado acima, fora deste bloco —
// repeti-lo aqui seria import duplicado — assim como `stripGroupSuffix` e o
// bloco de `routeHelpers`, que o merge automático já havia trazido acima.
import ContactMergeModal from 'dashboard/modules/contact/ContactMergeModal.vue';
import ComposeConversation from 'dashboard/components-next/NewConversation/ComposeConversation.vue';
import InlineInput from 'dashboard/components-next/inline-input/InlineInput.vue';
import VoiceCallButton from 'dashboard/components-next/Contacts/VoiceCallButton.vue';
import ExportConversationModal from 'dashboard/components-next/message/ExportConversationModal.vue';

export default {
  components: {
    ContactInfoRow,
    EditContact,
    Thumbnail,
    SocialIcons,
    ComposeConversation,
    ContactMergeModal,
    InlineInput,
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
    return { isAdmin };
  },
  data() {
    return {
      showEditModal: false,
      showDeleteModal: false,
      // Do lado da homologação, junto com o ExportConversationModal abaixo. O
      // merge automático ficou com este `data()` do nosso lado e a variável
      // sumiu, deixando o template a referenciar algo que não existe.
      // ⚠️ Nem no lado deles há quem a ponha em `true` — o modal existe e o
      // gatilho não. Preservado como estava; não inventei o acionador.
      showExportModal: false,
      isEditingName: false,
      editName: '',
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'contacts/getUIFlags',
    }),
    contactProfileLink() {
      return `/app/accounts/${this.$route.params.accountId}/contacts/${this.contact.id}`;
    },
    additionalAttributes() {
      return this.contact.additional_attributes || {};
    },
    isWhatsappGroup() {
      return String(this.contact.identifier || '').endsWith('@g.us');
    },
    displayName() {
      return stripGroupSuffix(this.contact.name || '');
    },
    visibleIdentifier() {
      return this.isWhatsappGroup ? '' : this.contact.identifier;
    },
    location() {
      const {
        country = '',
        city = '',
        country_code: countryCode,
      } = this.additionalAttributes;
      const cityAndCountry = [city, country].filter(Boolean).join(', ');

      return cityAndCountry
        ? this.findCountryFlag(countryCode, cityAndCountry)
        : '';
    },
    socialProfiles() {
      const {
        social_profiles: socialProfiles,
        screen_name: twitterScreenName,
        social_telegram_user_name: telegramUsername,
      } = this.additionalAttributes;

      return {
        ...(socialProfiles || {}),
        twitter: socialProfiles?.twitter || twitterScreenName || '',
        telegram: socialProfiles?.telegram || telegramUsername || '',
      };
    },
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
    // Restaurado: o merge automático ficou com o bloco `methods` do outro lado e
    // levou este junto. Sem ele, `ref="mergeModal"` fica sem quem o abra — foi o
    // eslint ("'mergeModal' is defined as ref, but never used") que denunciou.
    openMergeModal() {
      this.$refs.mergeModal?.open();
    },
    openComposeConversationModal(toggle) {
      toggle();
      emitter.emit(BUS_EVENTS.NEW_CONVERSATION_MODAL, true);
    },
    closeComposeConversationModal() {
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
        if (!countryCode) return `${cityAndCountry} 🌎`;
        return `${cityAndCountry} <span class="fi fi-${countryCode.toLowerCase()} size-3.5"></span>`;
      } catch {
        return '';
      }
    },
    startEditingName() {
      this.editName = this.contact.name || '';
      this.isEditingName = true;
      this.$nextTick(() => this.$refs.nameInput?.focus());
    },
    cancelNameEdit() {
      this.isEditingName = false;
    },
    saveNameEdit() {
      if (!this.isEditingName) return;
      this.isEditingName = false;
      const name = this.editName.trim();
      if (name && name !== this.contact.name) this.updateContactField({ name });
    },
    async updateContactField(attributes) {
      try {
        await this.$store.dispatch('contacts/update', {
          id: this.contact.id,
          ...attributes,
        });
        useAlert(this.$t('CONTACT_FORM.SUCCESS_MESSAGE'));
        await this.$store.dispatch(
          'contacts/fetchContactableInbox',
          this.contact.id
        );
      } catch (error) {
        if (error instanceof DuplicateContactException) {
          useAlert(
            error.contactErrorDetail || this.$t('CONTACT_FORM.ERROR_MESSAGE')
          );
        } else if (error instanceof ExceptionWithMessage) {
          useAlert(error.data);
        } else {
          useAlert(error.message || this.$t('CONTACT_FORM.ERROR_MESSAGE'));
        }
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
          this.$router.push({ name: 'inbox_view' });
        } else if (this.$route.name !== 'contacts_dashboard') {
          this.$router.push({ name: 'contacts_dashboard' });
        }
      } catch (error) {
        useAlert(error.message || this.$t('DELETE_CONTACT.API.ERROR_MESSAGE'));
      }
    },
  },
};
</script>

<template>
  <div class="relative w-full pt-10 pb-6 px-6">
    <div class="flex flex-col items-center w-full">
      <Thumbnail
        v-if="showAvatar"
        :src="contact.thumbnail"
        size="120px"
        :username="displayName"
        :status="contact.availability_status"
        allow-preview
      />

      <div v-if="showAvatar" class="flex items-center gap-2 mt-3">
        <InlineInput
          v-if="isEditingName"
          ref="nameInput"
          v-model="editName"
          custom-input-class="!text-[19px] !font-semibold !text-center"
          class="!w-fit"
          @enter-press="saveNameEdit"
          @escape-press="cancelNameEdit"
          @blur="saveNameEdit"
        />
        <h3
          v-else
          class="group/name my-0 text-[19px] font-semibold capitalize break-words text-n-slate-12 text-center cursor-pointer hover:text-n-slate-12/80"
          :title="$t('CONTACT_PANEL.CLICK_TO_EDIT')"
          @click="startEditingName"
        >
          {{ displayName }}
          <span
            class="i-lucide-pencil text-xs text-n-slate-10 opacity-0 group-hover/name:opacity-100 transition-opacity ml-1 align-middle"
          />
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

      <div class="mt-3">
        <SocialIcons :social-profiles="socialProfiles" />
      </div>

      <div
        class="flex items-stretch justify-center gap-1.5 mt-6 w-full max-w-[300px] mx-auto"
      >
        <div class="flex-1 min-w-0">
          <ComposeConversation
            :contact-id="String(contact.id)"
            @close="closeComposeConversationModal"
          >
            <template #trigger="{ toggle }">
              <button
                v-tooltip.top-end="$t('CONTACT_PANEL.NEW_MESSAGE')"
                class="wa-action-btn"
                :aria-label="$t('CONTACT_PANEL.NEW_MESSAGE')"
                @click="openComposeConversationModal(toggle)"
              >
                <span class="i-lucide-message-circle size-5" />
                <span class="wa-action-label">
                  {{ $t('CONTACT_PANEL.NEW_MESSAGE_SHORT') }}
                </span>
              </button>
            </template>
          </ComposeConversation>
        </div>
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
          :aria-label="$t('EDIT_CONTACT.BUTTON_LABEL')"
          @click="toggleEditModal"
        >
          <span class="i-lucide-pencil size-5" />
          <span class="wa-action-label">
            {{ $t('EDIT_CONTACT.BUTTON_LABEL_SHORT') }}
          </span>
        </button>
        <!-- Restaurado junto com `openMergeModal`: o modal de mesclar sobreviveu
             ao merge, mas o botão e o método que o abrem não. -->
        <button
          v-tooltip.top-end="$t('CONTACT_PANEL.MERGE_CONTACT')"
          class="wa-action-btn"
          :aria-label="$t('CONTACT_PANEL.MERGE_CONTACT')"
          :disabled="uiFlags.isMerging"
          @click="openMergeModal"
        >
          <span class="i-lucide-merge size-5" />
          <span class="wa-action-label">
            {{ $t('CONTACT_PANEL.MERGE_CONTACT_SHORT') }}
          </span>
        </button>
        <button
          v-if="isAdmin"
          v-tooltip.top-end="$t('DELETE_CONTACT.BUTTON_LABEL')"
          class="wa-action-btn wa-action-btn--danger"
          :aria-label="$t('DELETE_CONTACT.BUTTON_LABEL')"
          :disabled="uiFlags.isDeleting"
          @click="toggleDeleteModal"
        >
          <span class="i-lucide-trash-2 size-5" />
          <span class="wa-action-label">
            {{ $t('DELETE_CONTACT.BUTTON_LABEL_SHORT') }}
          </span>
        </button>
      </div>

      <div
        v-if="
          visibleIdentifier ||
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
          v-if="visibleIdentifier"
          :value="visibleIdentifier"
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
