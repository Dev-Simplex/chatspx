<script>
import ConversationCard from 'dashboard/components/widgets/conversation/ConversationCard.vue';
import { mapGetters } from 'vuex';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

export default {
  components: {
    ConversationCard,
    Spinner,
  },
  props: {
    contactId: {
      type: [String, Number],
      required: true,
    },
    conversationId: {
      type: [String, Number],
      required: true,
    },
  },
  computed: {
    conversations() {
      return this.$store.getters['contactConversations/getContactConversation'](
        this.contactId
      );
    },
    previousConversations() {
      return this.conversations.filter(
        conversation => conversation.id !== Number(this.conversationId)
      );
    },
    ...mapGetters({
      uiFlags: 'contactConversations/getUIFlags',
    }),
  },
  watch: {
    contactId(newContactId, prevContactId) {
      if (newContactId && newContactId !== prevContactId) {
        this.$store.dispatch('contactConversations/get', newContactId);
      }
    },
  },
  mounted() {
    this.$store.dispatch('contactConversations/get', this.contactId);
  },
};
</script>

<template>
  <div v-if="!uiFlags.isFetching" class="px-2">
    <div
      v-if="!previousConversations.length"
      class="text-n-slate-11 text-sm text-center py-3"
    >
      {{ $t('CONTACT_PANEL.CONVERSATIONS.NO_RECORDS_FOUND') }}
    </div>
    <div v-else class="flex flex-col">
      <ConversationCard
        v-for="conversation in previousConversations"
        :key="conversation.id"
        :chat="conversation"
        :hide-inbox-name="false"
        hide-thumbnail
        enable-context-menu
        compact
        :allowed-context-menu-options="['open-new-tab', 'copy-link']"
      />
    </div>
  </div>
  <div v-else class="flex items-center justify-center py-5">
    <Spinner />
  </div>
</template>
