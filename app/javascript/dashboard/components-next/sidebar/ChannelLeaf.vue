<script setup>
import { computed } from 'vue';
import Icon from 'next/icon/Icon.vue';
import ChannelIcon from 'next/icon/ChannelIcon.vue';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  active: {
    type: Boolean,
    default: false,
  },
  inbox: {
    type: Object,
    required: true,
  },
  isCollapsed: {
    type: Boolean,
    default: false,
  },
});

const reauthorizationRequired = computed(() => {
  return props.inbox.reauthorization_required;
});
</script>

<template>
  <span
    class="size-5 grid place-content-center rounded-full bg-n-alpha-2"
    :class="{ 'bg-n-solid-blue': active }"
    :title="isCollapsed ? label : undefined"
  >
    <ChannelIcon :inbox="inbox" class="size-3" />
  </span>
  <div v-if="!isCollapsed" class="flex-1 truncate min-w-0">{{ label }}</div>
  <div
    v-if="reauthorizationRequired && !isCollapsed"
    v-tooltip.top-end="$t('SIDEBAR.REAUTHORIZE')"
    class="grid place-content-center size-5 bg-n-ruby-5/60 rounded-full"
  >
    <Icon icon="i-woot-alert" class="size-3 text-n-ruby-9" />
  </div>
</template>
