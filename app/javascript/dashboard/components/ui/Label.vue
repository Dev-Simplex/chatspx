<script>
import { getContrastingTextColor } from '@chatwoot/utils';

export default {
  props: {
    title: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      default: '',
    },
    href: {
      type: String,
      default: '',
    },
    bgColor: {
      type: String,
      default: '',
    },
    small: {
      type: Boolean,
      default: false,
    },
    showClose: {
      type: Boolean,
      default: false,
    },
    icon: {
      type: String,
      default: '',
    },
    color: {
      type: String,
      default: '',
    },
    colorScheme: {
      type: String,
      default: '',
    },
    variant: {
      type: String,
      default: '',
    },
  },
  emits: ['remove'],
  computed: {
    textColor() {
      if (this.variant === 'smooth') return '';
      if (this.variant === 'dashed') return '';
      return this.color || getContrastingTextColor(this.bgColor);
    },
    labelClass() {
      return `label ${this.colorScheme} ${this.variant} ${
        this.small ? 'small' : ''
      }`;
    },
    labelStyle() {
      if (this.variant === 'smooth' && this.color) {
        return {
          background: `${this.color}1A`,
          color: this.color,
          border: 'none',
        };
      }
      if (this.bgColor) {
        return {
          background: this.bgColor,
          color: this.textColor,
          border: `1px solid ${this.bgColor}`,
        };
      }
      return {};
    },
    anchorStyle() {
      if (this.bgColor) {
        return { color: this.textColor };
      }
      return {};
    },
  },
  methods: {
    onClick() {
      this.$emit('remove', this.title);
    },
  },
};
</script>

<template>
  <div
    class="inline-flex"
    :class="labelClass"
    :style="labelStyle"
    :title="description"
  >
    <span v-if="icon" class="label-action--button">
      <fluent-icon :icon="icon" size="12" class="label--icon cursor-pointer" />
    </span>
    <span
      v-if="variant === 'dashed' && title && !icon"
      :style="{ background: color }"
      class="label-color-dot flex-shrink-0"
    />
    <span v-if="!href" class="whitespace-nowrap text-ellipsis overflow-hidden">
      {{ title }}
    </span>
    <a v-else :href="href" :style="anchorStyle">{{ title }}</a>
    <button
      v-if="showClose"
      class="label-close--button p-0"
      :style="{ color: variant === 'smooth' && color ? color : textColor }"
      @click="onClick"
    >
      <fluent-icon
        icon="dismiss"
        size="12"
        class="close--icon opacity-60 hover:opacity-100"
      />
    </button>
  </div>
</template>

<style scoped lang="scss">
.label {
  @apply items-center font-medium text-xs rounded-[4px] gap-1 p-1 bg-n-slate-3 text-n-slate-12 border border-solid border-n-strong h-6;

  &.small {
    @apply text-xs py-0.5 px-1 leading-tight h-5;
  }

  &.small .label--icon,
  &.small .close--icon {
    @apply text-[0.5rem];
  }

  a {
    @apply text-xs;
    &:hover {
      @apply underline;
    }
  }

  /* Color Schemes */
  &.primary {
    @apply bg-n-blue-5 text-n-blue-12 border border-solid border-n-blue-7;

    a {
      @apply text-n-blue-12;
    }
    .label-color-dot {
      @apply bg-n-blue-9;
    }
  }
  &.secondary {
    @apply bg-n-slate-5 text-n-slate-12 border border-solid border-n-slate-7;

    a {
      @apply text-n-slate-12;
    }
    .label-color-dot {
      @apply bg-n-slate-9;
    }
  }
  &.success {
    @apply bg-n-teal-5 text-n-teal-12 border border-solid border-n-teal-7;

    a {
      @apply text-n-teal-12;
    }
    .label-color-dot {
      @apply bg-n-teal-9;
    }
  }
  &.alert {
    @apply bg-n-ruby-5 text-n-ruby-12 border border-solid border-n-ruby-7;

    a {
      @apply text-n-ruby-12;
    }
    .label-color-dot {
      @apply bg-n-ruby-9;
    }
  }
  &.warning {
    @apply bg-n-amber-5 text-n-amber-12 border border-solid border-n-amber-7;

    a {
      @apply text-n-amber-12;
    }
    .label-color-dot {
      @apply bg-n-amber-9;
    }
  }

  &.smooth {
    @apply bg-transparent text-n-slate-11 dark:text-n-slate-12 border-none rounded-full px-2;
  }

  &.dashed {
    @apply bg-transparent text-n-slate-11 dark:text-n-slate-12 border border-dashed border-n-weak rounded-full px-2 hover:border-n-slate-6;
  }
}

.label-close--button {
  @apply text-n-slate-11 -mb-0.5 rounded-sm cursor-pointer flex items-center justify-center hover:bg-n-slate-3;

  svg {
    @apply text-n-slate-11;
  }
}

.label-action--button {
  @apply flex mr-1;
}

.label-color-dot {
  @apply inline-block w-3 h-3 rounded-sm shadow-sm;
}
.label.small .label-color-dot {
  @apply w-2 h-2 rounded-sm shadow-sm;
}
</style>
