import { ref, computed, onMounted, onBeforeUnmount, watch, unref } from 'vue';

/**
 * Detecta drag-and-drop de ARQUIVOS no window inteiro (estilo WhatsApp Web).
 *
 * - Escuta `dragenter`/`dragover`/`dragleave`/`drop` em window
 * - Detecta arquivo via `dataTransfer.types.includes('Files')` (evita falso
 *   positivo com drag de texto ou de elementos internos)
 * - Resolve `dragleave` recursivo via contador (Dragster pattern):
 *   filhos disparam `dragleave` ao receber o cursor; sem o contador o overlay
 *   piscaria toda vez que cruzasse um filho
 *
 * @param {object} options
 * @param {Function} options.onDrop - callback(FileList, DragEvent)
 * @param {import('vue').Ref<boolean>|boolean} options.enabled - desativar dinamicamente
 * @returns {{ isOverDropZone: import('vue').ComputedRef<boolean> }}
 */
export function useGlobalDropZone({ onDrop, enabled = true } = {}) {
  const counter = ref(0);
  const hasFiles = ref(false);

  const isEnabled = computed(() => Boolean(unref(enabled)));
  const isOverDropZone = computed(
    () => isEnabled.value && counter.value > 0 && hasFiles.value
  );

  const eventHasFiles = event => {
    const types = event?.dataTransfer?.types;
    if (!types) return false;
    return Array.from(types).includes('Files');
  };

  const handleDragEnter = event => {
    if (!isEnabled.value) return;
    if (!eventHasFiles(event)) return;
    event.preventDefault();
    counter.value += 1;
    hasFiles.value = true;
  };

  const handleDragOver = event => {
    if (!isEnabled.value) return;
    if (!eventHasFiles(event)) return;
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = 'copy';
    }
  };

  const handleDragLeave = event => {
    if (!isEnabled.value) return;
    if (!eventHasFiles(event)) return;
    counter.value = Math.max(0, counter.value - 1);
    if (counter.value === 0) {
      hasFiles.value = false;
    }
  };

  const reset = () => {
    counter.value = 0;
    hasFiles.value = false;
  };

  const handleDrop = event => {
    if (!isEnabled.value) {
      reset();
      return;
    }
    if (!eventHasFiles(event)) {
      reset();
      return;
    }
    event.preventDefault();
    const files = event.dataTransfer?.files;
    reset();
    if (files && files.length > 0 && typeof onDrop === 'function') {
      onDrop(Array.from(files), event);
    }
  };

  // Reseta se a janela perder foco no meio de um drag
  const handleWindowBlur = () => reset();

  const attach = () => {
    window.addEventListener('dragenter', handleDragEnter);
    window.addEventListener('dragover', handleDragOver);
    window.addEventListener('dragleave', handleDragLeave);
    window.addEventListener('drop', handleDrop);
    window.addEventListener('blur', handleWindowBlur);
  };

  const detach = () => {
    window.removeEventListener('dragenter', handleDragEnter);
    window.removeEventListener('dragover', handleDragOver);
    window.removeEventListener('dragleave', handleDragLeave);
    window.removeEventListener('drop', handleDrop);
    window.removeEventListener('blur', handleWindowBlur);
  };

  onMounted(attach);
  onBeforeUnmount(detach);

  // Limpa estado quando desabilitado em runtime (ex: modal de nova conversa abre)
  watch(isEnabled, value => {
    if (!value) reset();
  });

  return { isOverDropZone };
}
