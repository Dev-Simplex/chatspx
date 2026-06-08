// Singleton snackbar para o módulo Kanban (P1-06).
// Substitui window.confirm/alert em ações reversíveis.
//
// Uso:
//   const { show, dismiss, snackbar } = useKanbanSnackbar();
//   show({ message: 'Card movido', action: { label: 'Desfazer', onClick: () => ... }, timeout: 5000 });
//
// O componente KanbanSnackbar.vue lê `snackbar` e renderiza o snackbar global.

import { reactive, computed } from 'vue';

const state = reactive({
  visible: false,
  message: '',
  action: null,
  timeout: 5000,
  variant: 'info', // 'info' | 'success' | 'warning' | 'error'
  timer: null,
});

const clearTimer = () => {
  if (state.timer) {
    clearTimeout(state.timer);
    state.timer = null;
  }
};

const dismiss = () => {
  clearTimer();
  state.visible = false;
  state.message = '';
  state.action = null;
};

const show = ({ message, action = null, timeout = 5000, variant = 'info' }) => {
  clearTimer();
  state.message = message;
  state.action = action;
  state.timeout = timeout;
  state.variant = variant;
  state.visible = true;
  if (timeout > 0) {
    state.timer = setTimeout(dismiss, timeout);
  }
};

export function useKanbanSnackbar() {
  return {
    show,
    dismiss,
    snackbar: computed(() => ({
      visible: state.visible,
      message: state.message,
      action: state.action,
      variant: state.variant,
    })),
  };
}
