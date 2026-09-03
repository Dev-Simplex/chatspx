<script>
import Spinner from 'shared/components/Spinner.vue';
import FluentIcon from 'shared/components/FluentIcon/Index.vue';

export default {
  components: {
    FluentIcon,
    Spinner,
  },
  props: {
    loading: {
      type: Boolean,
      default: false,
    },
    disabled: {
      type: Boolean,
      default: false,
    },
  },
};
</script>

<template>
  <button
    type="submit"
    :disabled="disabled"
    class="min-h-8 min-w-8 flex items-center justify-center ml-1 rounded-full bg-w-brand hover:bg-w-brand-hover transition-colors"
  >
    <FluentIcon v-if="!loading" icon="send" class="text-white" />
    <Spinner v-else size="small" />
  </button>
</template>
