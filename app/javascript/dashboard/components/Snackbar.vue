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
    defaultIcon() {
      const iconMap = {
        success: 'i-lucide-check-circle',
        error: 'i-lucide-alert-circle',
        warning: 'i-lucide-alert-triangle',
        info: 'i-lucide-info',
      };
      return this.icon || iconMap[this.variant] || null;
    },
    containerClass() {
      const classMap = {
        success:
          'bg-n-brand/10 border border-n-brand/30 text-n-brand shadow-dropdown',
        error:
          'bg-n-ruby-3/50 border border-n-ruby-6/30 text-n-ruby-11 shadow-dropdown',
        warning:
          'bg-n-amber-3/50 border border-n-amber-6/30 text-n-amber-11 shadow-dropdown',
        info: 'bg-n-blue-3/50 border border-n-blue-6/30 text-n-blue-11 shadow-dropdown',
      };
      return (
        classMap[this.variant] ||
        'bg-n-slate-12 dark:bg-n-slate-7 text-white shadow-sm'
      );
    },
  },
  mounted() {},
  methods: {},
};
</script>

<template>
  <div>
    <div
      class="rounded-xl items-center gap-3 inline-flex mb-2 max-w-[25rem] min-h-[1.875rem] min-w-[15rem] px-4 py-3 text-left"
      :class="containerClass"
    >
      <Icon v-if="defaultIcon" :icon="defaultIcon" class="size-4 shrink-0" />
      <div class="text-sm font-medium">
        {{ message }}
      </div>
      <div v-if="action?.type === 'link'">
        <router-link
          :to="action.to"
          class="font-medium cursor-pointer select-none text-n-blue-10 hover:text-n-brand"
        >
          {{ action.message }}
        </router-link>
      </div>
    </div>
  </div>
</template>
