<script setup>
import Modal from '../../Modal.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({
  onClose: { type: Function, default: () => {} },
  onConfirm: { type: Function, default: () => {} },
  title: { type: String, default: '' },
  message: { type: String, default: '' },
  messageValue: { type: String, default: '' },
  confirmText: { type: String, default: '' },
  rejectText: { type: String, default: '' },
});

const show = defineModel('show', { type: Boolean, default: false });
</script>

<template>
  <Modal v-model:show="show" :on-close="onClose">
    <woot-modal-header
      :header-title="title"
      :header-content="message"
      :header-content-value="messageValue"
    />
    <!-- Slot opcional entre o aviso e os botoes, para exclusao que precisa de uma ESCOLHA (ex.:
         "levar a caixa de entrada junto?"). Sem nada no slot o modal fica identico ao de antes,
         entao os usos existentes nao mudam. -->
    <div v-if="$slots.default" class="px-6 pb-2">
      <slot />
    </div>
    <div
      class="flex items-center justify-end gap-2 px-6 py-4 border-t border-n-weak"
    >
      <Button faded slate type="reset" :label="rejectText" @click="onClose" />
      <Button ruby type="submit" :label="confirmText" @click="onConfirm" />
    </div>
  </Modal>
</template>
