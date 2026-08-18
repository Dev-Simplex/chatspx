<script>
import { IFrameHelper } from 'widget/helpers/utils';

export default {
  components: {},
  props: {
    action: {
      type: Object,
      default: () => {},
    },
  },
  computed: {
    isLink() {
      return this.action.type === 'link';
    },
  },
  methods: {
    onClick() {
      if (this.action.type === 'postback') {
        // Send message to parent iframe
        if (IFrameHelper.isIFrame()) {
          IFrameHelper.sendMessage({
            event: 'postback',
            data: { payload: this.action.payload },
          });
        }
      }
    },
  },
};
</script>

<template>
  <a
    v-if="isLink"
    :key="action.uri"
    class="action-button button"
    :href="action.uri"
    target="_blank"
    rel="noopener nofollow noreferrer"
  >
    {{ action.text }}
  </a>
  <button
    v-else
    :key="action.payload"
    class="action-button button !bg-n-background dark:!bg-n-alpha-black1 text-w-brand-readable border-w-brand-readable"
    @click="onClick"
  >
    {{ action.text }}
  </button>
</template>

<style scoped lang="scss">
.action-button {
  @apply items-center rounded-lg flex font-medium justify-center mt-1 p-0 w-full;
}
</style>
