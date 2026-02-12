<script setup>
import { computed } from 'vue';

import MessageMeta from '../MessageMeta.vue';

import { emitter } from 'shared/helpers/mitt';
import { useMessageContext } from '../provider.js';
import { useI18n } from 'vue-i18n';

import { BUS_EVENTS } from 'shared/constants/busEvents';
import { MESSAGE_VARIANTS, ORIENTATION } from '../constants';

const props = defineProps({
  hideMeta: { type: Boolean, default: false },
});

const { variant, orientation, inReplyTo, shouldGroupWithNext } =
  useMessageContext();
const { t } = useI18n();

const varaintBaseMap = {
  [MESSAGE_VARIANTS.AGENT]: 'bg-n-solid-blue text-n-slate-12',
  [MESSAGE_VARIANTS.PRIVATE]:
    'bg-n-solid-amber text-n-amber-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.SCHEDULED]:
    'bg-n-solid-amber text-n-amber-12 [&_.prosemirror-mention-node]:font-semibold',
  [MESSAGE_VARIANTS.USER]: 'bg-n-slate-4 text-n-slate-12',
  [MESSAGE_VARIANTS.ACTIVITY]: 'bg-n-alpha-1 text-n-slate-11 text-sm',
  [MESSAGE_VARIANTS.BOT]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.TEMPLATE]: 'bg-n-solid-iris text-n-slate-12',
  [MESSAGE_VARIANTS.ERROR]: 'bg-n-ruby-4 text-n-ruby-12',
  [MESSAGE_VARIANTS.EMAIL]: 'w-full',
  [MESSAGE_VARIANTS.UNSUPPORTED]:
    'bg-n-solid-amber/70 border border-dashed border-n-amber-12 text-n-amber-12',
};

const orientationMap = {
  [ORIENTATION.LEFT]:
    'left-bubble rounded-xl ltr:rounded-bl-sm rtl:rounded-br-sm',
  [ORIENTATION.RIGHT]:
    'right-bubble rounded-xl ltr:rounded-br-sm rtl:rounded-bl-sm',
  [ORIENTATION.CENTER]: 'rounded-md',
};

const flexOrientationClass = computed(() => {
  const map = {
    [ORIENTATION.LEFT]: 'justify-start',
    [ORIENTATION.RIGHT]: 'justify-end',
    [ORIENTATION.CENTER]: 'justify-center',
  };

  return map[orientation.value];
});

const showTail = computed(
  () =>
    variant.value !== MESSAGE_VARIANTS.ACTIVITY &&
    variant.value !== MESSAGE_VARIANTS.EMAIL &&
    !shouldGroupWithNext.value
);

const messageClass = computed(() => {
  const classToApply = [
    'message-bubble shadow-bubble',
    varaintBaseMap[variant.value],
  ];

  if (variant.value !== MESSAGE_VARIANTS.ACTIVITY) {
    classToApply.push(orientationMap[orientation.value]);
    if (showTail.value) {
      classToApply.push(
        orientation.value === ORIENTATION.LEFT
          ? 'bubble-tail-left'
          : 'bubble-tail-right'
      );
    }
  } else {
    classToApply.push('rounded-lg');
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

const replyToPreview = computed(() => {
  if (!inReplyTo) return '';

  const { content, attachments } = inReplyTo.value;

  if (content) return content;
  if (attachments?.length) {
    const firstAttachment = attachments[0];
    const fileType = firstAttachment.fileType ?? firstAttachment.file_type;

    return t(`CHAT_LIST.ATTACHMENTS.${fileType}.CONTENT`);
  }

  return t('CONVERSATION.REPLY_MESSAGE_NOT_FOUND');
});
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
    :data-variant="variant"
  >
    <div
      v-if="inReplyTo"
      class="p-2 -mx-1 mb-2 rounded-lg cursor-pointer bg-n-alpha-black1"
      @click="scrollToMessage"
    >
      <span class="break-all line-clamp-2">
        {{ replyToPreview }}
      </span>
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

<style scoped lang="scss">
.message-bubble {
  position: relative;
}

.shadow-bubble {
  box-shadow: 0 1px 2px rgba(0, 0, 0, 0.08);
}

.bubble-tail-left::before,
.bubble-tail-right::before {
  content: '';
  position: absolute;
  bottom: 0;
  width: 0;
  height: 0;
  border-style: solid;
}

.bubble-tail-left::before {
  left: 0;
  border-width: 0 0 8px 8px;
  border-color: transparent transparent rgb(var(--slate-4)) transparent;
  filter: drop-shadow(-1px 1px 1px rgba(0, 0, 0, 0.06));
}

.bubble-tail-right::before {
  right: 0;
  border-width: 0 8px 8px 0;
  border-color: transparent rgb(var(--solid-blue)) transparent transparent;
  filter: drop-shadow(1px 1px 1px rgba(0, 0, 0, 0.06));
}

.bubble-tail-right[data-variant='private']::before,
.bubble-tail-right[data-variant='scheduled']::before {
  border-color: transparent rgb(var(--solid-amber)) transparent transparent;
}

:global(.dark) .bubble-tail-left::before {
  border-color: transparent transparent rgb(var(--slate-4)) transparent;
}

:global(.dark) .bubble-tail-right::before {
  border-color: transparent rgb(var(--solid-blue)) transparent transparent;
}

:global(.dark) .bubble-tail-right[data-variant='private']::before,
:global(.dark) .bubble-tail-right[data-variant='scheduled']::before {
  border-color: transparent rgb(var(--solid-amber)) transparent transparent;
}
</style>
