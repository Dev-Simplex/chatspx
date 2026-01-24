<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../../provider.js';

import MessageFormatter from 'shared/helpers/MessageFormatter.js';
import { linkifyPhoneNumbers } from 'dashboard/helper/phoneNumberLinkify';
import { MESSAGE_VARIANTS } from '../../constants';
import { useRouter } from 'vue-router';
import { useStore } from 'dashboard/composables/store';

const props = defineProps({
  content: {
    type: String,
    required: true,
  },
});

const { variant } = useMessageContext();
const router = useRouter();
const store = useStore();

const formattedContent = computed(() => {
  if (variant.value === MESSAGE_VARIANTS.ACTIVITY) {
    return props.content;
  }

  const formatted = new MessageFormatter(props.content).formattedMessage;
  return linkifyPhoneNumbers(formatted);
});

const handlePhoneClick = (phoneNumber) => {
  const accountId = store.getters.getCurrentAccountId;
  // Navigate to contacts with search query
  router.push({
    name: 'contacts_dashboard',
    params: { accountId },
    query: { search: phoneNumber },
  });
};
</script>

<template>
  <span
    v-dompurify-html="formattedContent"
    class="prose prose-bubble"
    @click="(e) => {
      if (e.target.classList.contains('phone-number-link')) {
        e.preventDefault();
        handlePhoneClick(e.target.dataset.phone);
      }
    }"
  />
</template>
