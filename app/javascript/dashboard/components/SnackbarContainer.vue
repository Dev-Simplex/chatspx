<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import WootSnackbar from './Snackbar.vue';
import { emitter } from 'shared/helpers/mitt';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  duration: {
    type: Number,
    default: 2500,
  },
});

const { t } = useI18n();

const snackMessages = ref([]);

const onNewToastMessage = ({ message: originalMessage, action }) => {
  const message = action?.usei18n ? t(originalMessage) : originalMessage;
  const duration = action?.duration || props.duration;

  snackMessages.value.push({
    key: Date.now(),
    message,
    action,
  });

  setTimeout(() => {
    snackMessages.value.shift();
  }, duration);
};

onMounted(() => {
  emitter.on('newToastMessage', onNewToastMessage);
});

onUnmounted(() => {
  emitter.off('newToastMessage', onNewToastMessage);
});
</script>

<template>
  <Teleport to="body">
    <div
      v-show="snackMessages.length > 0"
      class="wa-toast-stack fixed top-4 right-6 max-w-[22rem] min-w-[16rem] text-start bg-transparent pointer-events-none z-[9999]"
    >
      <transition-group
        name="toast-fade"
        tag="div"
        class="flex flex-col gap-2 items-end"
      >
        <WootSnackbar
          v-for="snackMessage in snackMessages"
          :key="snackMessage.key"
          :message="snackMessage.message"
          :action="snackMessage.action"
          class="pointer-events-auto"
        />
      </transition-group>
    </div>
  </Teleport>
</template>

<style scoped>
.toast-fade-enter-active,
.toast-fade-leave-active {
  transition:
    opacity 180ms ease,
    transform 220ms ease;
}

.toast-fade-enter-from,
.toast-fade-leave-to {
  opacity: 0;
  transform: translateY(-6px) scale(0.98);
}
</style>
