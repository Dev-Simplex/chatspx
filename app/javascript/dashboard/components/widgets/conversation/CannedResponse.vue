<script>
import { mapGetters } from 'vuex';
import MentionBox from '../mentions/MentionBox.vue';

export default {
  components: { MentionBox },
  props: {
    searchKey: {
      type: String,
      default: '',
    },
  },
  emits: ['replace', 'attach'],
  computed: {
    ...mapGetters({
      cannedMessages: 'getCannedResponses',
    }),
    items() {
      return this.cannedMessages.map(cannedMessage => ({
        label: cannedMessage.short_code,
        key: cannedMessage.short_code,
        description: cannedMessage.content,
      }));
    },
  },
  watch: {
    searchKey() {
      this.fetchCannedResponses();
    },
  },
  mounted() {
    this.fetchCannedResponses();
  },
  methods: {
    fetchCannedResponses() {
      this.$store.dispatch('getCannedResponse', { searchKey: this.searchKey });
    },
    // Strip HTML/whitespace for a compact single-source preview (mirrors the modal picker).
    previewText(content) {
      if (!content) return '';
      return String(content)
        .replace(/<[^>]*>/g, ' ')
        .replace(/\s+/g, ' ')
        .trim();
    },
    handleMentionClick(item = {}) {
      this.$emit('replace', item.description);
      const selected = this.cannedMessages.find(
        cannedMessage => cannedMessage.short_code === item.key
      );
      if (selected?.attachments?.length) {
        this.$emit('attach', selected.attachments);
      }
    },
  },
};
</script>

<!-- eslint-disable-next-line vue/no-root-v-if -->
<template>
  <MentionBox
    v-if="items.length"
    :items="items"
    @mention-select="handleMentionClick"
  >
    <template #default="{ item }">
      <div class="flex items-center justify-between w-full gap-3">
        <p
          class="flex-1 min-w-0 mb-0 overflow-hidden text-sm leading-snug text-n-slate-12 line-clamp-2 break-words"
        >
          {{ previewText(item.description) }}
        </p>
        <span
          class="inline-flex items-center flex-shrink-0 px-2 py-0.5 font-mono text-xs rounded-md bg-n-slate-4 dark:bg-n-slate-8 text-n-slate-11"
        >
          {{ `/${item.label}` }}
        </span>
      </div>
    </template>
  </MentionBox>
</template>
