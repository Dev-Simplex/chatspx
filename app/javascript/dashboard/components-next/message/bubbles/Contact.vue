<script setup>
import { computed } from 'vue';
import { useMessageContext } from '../provider.js';
import { ATTACHMENT_TYPES } from '../constants.js';
import ContactCard from './ContactCard.vue';

const { attachments } = useMessageContext();

// A single message may carry several shared contacts (a .vcf with multiple
// cards) — render one rich card per contact.
const contactAttachments = computed(() => {
  return (attachments.value ?? []).filter(
    attachment => attachment.fileType === ATTACHMENT_TYPES.CONTACT
  );
});
</script>

<template>
  <div class="flex flex-col gap-2">
    <ContactCard
      v-for="(attachment, index) in contactAttachments"
      :key="attachment.id"
      :attachment="attachment"
      :hide-meta="index < contactAttachments.length - 1"
    />
  </div>
</template>
