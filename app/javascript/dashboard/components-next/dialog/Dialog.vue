<script setup>
import { ref, computed } from 'vue';
import { OnClickOutside } from '@vueuse/components';
import { useI18n } from 'vue-i18n';

import Button from 'dashboard/components-next/button/Button.vue';
import TeleportWithDirection from 'dashboard/components-next/TeleportWithDirection.vue';

const props = defineProps({
  type: {
    type: String,
    default: 'edit',
    validator: value => ['alert', 'edit'].includes(value),
  },
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  cancelButtonLabel: {
    type: String,
    default: '',
  },
  confirmButtonLabel: {
    type: String,
    default: '',
  },
  disableConfirmButton: {
    type: Boolean,
    default: false,
  },
  isLoading: {
    type: Boolean,
    default: false,
  },
  showCancelButton: {
    type: Boolean,
    default: true,
  },
  showConfirmButton: {
    type: Boolean,
    default: true,
  },
  overflowYAuto: {
    type: Boolean,
    default: false,
  },
  // Opt-in: caps the dialog at the viewport and turns it into a flex column, so
  // the title and the footer stay put and the CONTENT is what gives way. Without
  // it a tall body just grows the dialog past the screen. Off by default — every
  // other dialog keeps its current auto-height behaviour untouched.
  fullHeight: {
    type: Boolean,
    default: false,
  },
  width: {
    type: String,
    default: 'lg',
    validator: value =>
      ['5xl', '4xl', '3xl', '2xl', 'xl', 'lg', 'md', 'sm'].includes(value),
  },
  position: {
    type: String,
    default: 'center',
    validator: value => ['center', 'top'].includes(value),
  },
});

const emit = defineEmits(['confirm', 'close']);

const { t } = useI18n();

const dialogRef = ref(null);
const dialogContentRef = ref(null);
const isOpen = ref(false);

const maxWidthClass = computed(() => {
  const classesMap = {
    '5xl': 'max-w-5xl',
    '4xl': 'max-w-4xl',
    '3xl': 'max-w-3xl',
    '2xl': 'max-w-2xl',
    xl: 'max-w-xl',
    lg: 'max-w-lg',
    md: 'max-w-md',
    sm: 'max-w-sm',
  };

  return classesMap[props.width] ?? 'max-w-md';
});

const positionClass = computed(() =>
  props.position === 'top' ? 'dialog-position-top' : ''
);

const open = () => {
  isOpen.value = true;
  dialogRef.value?.showModal();
};

const close = () => {
  emit('close');
  dialogRef.value?.close();
  isOpen.value = false;
};

// Only close if the close event originated from this dialog,
// not from a child dialog (e.g. ProseMirror prompt) bubbling up.
const handleDialogClose = e => e.target === dialogRef.value && close();

// Only close on click-outside if this dialog is the topmost one.
// If another dialog (e.g. ProseMirror prompt) is open on top, ignore.
const handleClickOutside = () => {
  const dialogs = document.querySelectorAll('dialog[open]');
  if (dialogs[dialogs.length - 1] === dialogRef.value) close();
};

const confirm = () => {
  emit('confirm');
};

defineExpose({ open, close });
</script>

<template>
  <TeleportWithDirection to="body">
    <dialog
      ref="dialogRef"
      class="w-full transition-all duration-300 ease-in-out shadow-xl rounded-xl"
      :class="[
        maxWidthClass,
        positionClass,
        overflowYAuto ? 'overflow-y-auto' : 'overflow-visible',
        fullHeight ? 'dialog-full-height' : '',
      ]"
      @close.prevent="handleDialogClose"
    >
      <OnClickOutside
        :class="fullHeight ? 'flex w-full min-h-0 max-h-full' : ''"
        @trigger="handleClickOutside"
      >
        <form
          ref="dialogContentRef"
          class="flex flex-col w-full gap-6 p-6 overflow-visible text-start align-middle transition-all duration-300 ease-in-out transform bg-n-solid-1 dark:bg-[#233138] border border-[var(--wa-list-border)] dark:border-[var(--wa-list-border-dark)] shadow-[0_2px_8px_rgba(11,20,26,0.12)] rounded-lg"
          :class="fullHeight ? 'min-h-0 max-h-full' : 'h-auto'"
          @submit.prevent="confirm"
          @click.stop
        >
          <div
            v-if="title || description"
            class="flex flex-col gap-2"
            :class="{ 'shrink-0': fullHeight }"
          >
            <h3 class="text-base font-medium leading-6 text-n-slate-12">
              {{ title }}
            </h3>
            <slot name="description">
              <p v-if="description" class="mb-0 text-sm text-n-slate-11">
                {{ description }}
              </p>
            </slot>
          </div>
          <!-- Dialog content will be injected here. In fullHeight mode it gets a
               flex-1/min-h-0 wrapper so the content — not the dialog — absorbs
               the leftover height and can scroll inside. -->
          <template v-if="isOpen">
            <div v-if="fullHeight" class="flex flex-col flex-1 min-h-0">
              <slot />
            </div>
            <slot v-else />
          </template>
          <slot name="footer">
            <div
              v-if="showCancelButton || showConfirmButton"
              class="flex items-center justify-between w-full gap-3"
              :class="{ 'shrink-0': fullHeight }"
            >
              <Button
                v-if="showCancelButton"
                variant="faded"
                color="slate"
                :label="cancelButtonLabel || t('DIALOG.BUTTONS.CANCEL')"
                class="w-full"
                type="button"
                @click="close"
              />
              <Button
                v-if="showConfirmButton"
                :color="type === 'edit' ? 'blue' : 'ruby'"
                :label="confirmButtonLabel || t('DIALOG.BUTTONS.CONFIRM')"
                class="w-full"
                :is-loading="isLoading"
                :disabled="disableConfirmButton || isLoading"
                type="submit"
              />
            </div>
          </slot>
        </form>
      </OnClickOutside>
    </dialog>
  </TeleportWithDirection>
</template>

<style scoped>
dialog::backdrop {
  @apply bg-n-alpha-black1 backdrop-blur-[4px];
}

/* fullHeight: the dialog owns the height budget and the form distributes it.
   `dvh` (not `vh`) so the mobile URL bar can't push the footer off-screen. */
.dialog-full-height {
  display: flex;
  max-height: 90dvh;
}

.dialog-position-top {
  margin-top: clamp(2rem, 5vh, 5rem);
  margin-bottom: auto;
}
</style>
