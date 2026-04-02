<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';
import ReplyPreview from './ReplyPreview.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';

import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const { variant, orientation, inReplyTo, shouldGroupWithNext } =
  useMessageContext();

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]:
    'bg-n-solid-blue dark:bg-n-solid-blue text-n-slate-12 shadow-bubble',
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-solid-amber dark:bg-n-solid-amber text-n-slate-12 shadow-bubble [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.SCHEDULED]:
    'bg-n-solid-amber dark:bg-n-solid-amber text-n-slate-12 shadow-bubble [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]:
    'bg-white dark:bg-n-slate-3 text-n-slate-12 shadow-bubble',
  [MESSAGE_VARIANTS.ACTIVITY]: 'bg-transparent text-n-slate-10 text-xs',
  [MESSAGE_VARIANTS.BOT]:
    'bg-n-solid-blue dark:bg-n-solid-blue text-n-slate-12 shadow-bubble',
  [MESSAGE_VARIANTS.TEMPLATE]:
    'bg-n-solid-blue dark:bg-n-solid-blue text-n-slate-12 shadow-bubble',
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12 rounded-lg',
  [MESSAGE_VARIANTS.EMAIL]:
    'w-full bg-white dark:bg-n-slate-3 border border-n-weak rounded-lg',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12 rounded-lg',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-bubble-in rtl:rounded-[8px_0_8px_8px]',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-bubble-out rtl:rounded-[0_8px_8px_8px]',
  [ORIENTATION.CENTER]: 'rounded-lg',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const NON_DIRECTIONAL_VARIANTS = [
  MESSAGE_VARIANTS.ACTIVITY,
  MESSAGE_VARIANTS.EMAIL,
  MESSAGE_VARIANTS.ERROR,
  MESSAGE_VARIANTS.UNSUPPORTED,
];

const messageClass = computed(() => {
  const classToApply = [varaintBaseMap[variant.value]];

  if (!NON_DIRECTIONAL_VARIANTS.includes(variant.value)) {
    classToApply.push(orientationMap[orientation.value]);
  }

  return classToApply;
});

const scrollToMessage = () => {
  emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, {
    messageId: inReplyTo.value.id,
  });
};

const shouldShowMeta = computed(
  () =>
    !props.hideMeta &&
    !shouldGroupWithNext.value &&
    variant.value !== MESSAGE_VARIANTS.ACTIVITY
);
</script>

<template>
  <div
    class="text-sm"
    :class="[
      messageClass,
      {
        'max-w-lg': variant !== MESSAGE_VARIANTS.EMAIL,
      },
    ]"
  >
    <div
      v-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-lg cursor-pointer bg-n-alpha-black1"
      @click="scrollToMessage"
    >
      <ReplyPreview :in-reply-to="inReplyTo" />
    </div>
    <slot />
    <MessageMeta
      v-if="shouldShowMeta"
      :class="[
        flexOrientationClass,
        variant === MESSAGE_VARIANTS.EMAIL ? 'px-3 pb-3' : '',
        [MESSAGE_VARIANTS.PRIVATE, MESSAGE_VARIANTS.SCHEDULED].includes(variant)
          ? 'text-n-amber-12/50'
          : 'text-n-slate-11',
      ]"
      class="mt-2"
    />
  </div>
</template>
