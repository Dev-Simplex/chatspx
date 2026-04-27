<script>
import Icon from 'dashboard/components-next/icon/Icon.vue';

export default {
  components: {
    Icon,
  },
  props: {
    message: { type: String, default: '' },
    action: {
      type: Object,
      default: () => ({}),
    },
  },
  data() {
    return {
      toggleAfterTimeout: false,
    };
  },
  computed: {
    variant() {
      return this.action?.variant || 'default';
    },
    icon() {
      return this.action?.icon;
    },
    containerClass() {
      if (this.variant === 'error') {
        return 'bg-n-ruby-9 text-white ring-1 ring-n-ruby-7/40 shadow-lg';
      }
      if (this.variant === 'warning') {
        return 'bg-n-amber-9 text-white ring-1 ring-n-amber-7/40 shadow-lg';
      }
      if (this.variant === 'success') {
        return 'bg-n-teal-9 text-white ring-1 ring-n-teal-7/40 shadow-lg';
      }
      // Default WA-fiel: header escuro (#233138) em ambos temas — alto contraste e consistente.
      return 'bg-[#233138] text-white shadow-lg ring-1 ring-black/10';
    },
  },
  mounted() {},
  methods: {},
};
</script>

<template>
  <div>
    <div
      class="rounded-lg items-center gap-3 inline-flex mb-2 max-w-[25rem] min-h-[1.875rem] min-w-[15rem] px-6 py-3 text-left"
      :class="containerClass"
    >
      <Icon v-if="icon" :icon="icon" class="text-white/90 size-4" />
      <div class="text-sm font-medium text-white dark:text-white">
        {{ message }}
      </div>
      <div v-if="action?.type === 'link'">
        <router-link
          v-if="action.type == 'link'"
          :to="action.to"
          class="font-medium cursor-pointer select-none text-n-blue-10 hover:text-n-brand"
        >
          {{ action.message }}
        </router-link>
      </div>
    </div>
  </div>
</template>
