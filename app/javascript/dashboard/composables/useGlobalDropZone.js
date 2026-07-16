import { ref, computed, onMounted, onBeforeUnmount, watch, unref } from 'vue';

// Enquanto um arraste está ativo o browser dispara `dragover` continuamente
// (~60x/s). Se ele parar, o arraste acabou em algum lugar que não observamos
// (soltou em outro app/monitor, ou quirk do browser que engole o `dragend`).
const STALE_DRAG_MS = 400;
const STALE_CHECK_MS = 200;

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
 * O contador é a parte perigosa: se ele não voltar a zero o overlay cobre o app
 * inteiro e parece que travou. Todo caminho de saída zera o estado — `drop`
 * (inclusive na captura), `dragend` (cancelar com ESC/soltar fora), sair da
 * janela, perder o foco, e um cão-de-guarda para o arraste que morre calado.
 *
 * @param {object} options
 * @param {Function} options.onDrop - callback(FileList, DragEvent)
 * @param {import('vue').Ref<boolean>|boolean} options.enabled - desativar dinamicamente
 * @returns {{ isOverDropZone: import('vue').ComputedRef<boolean> }}
 */
export function useGlobalDropZone({ onDrop, enabled = true } = {}) {
  const counter = ref(0);
  const hasFiles = ref(false);
  let lastDragOverAt = 0;
  let staleTimer = null;

  const isEnabled = computed(() => Boolean(unref(enabled)));
  const isOverDropZone = computed(
    () => isEnabled.value && counter.value > 0 && hasFiles.value
  );

  const eventHasFiles = event => {
    const types = event?.dataTransfer?.types;
    if (!types) return false;
    return Array.from(types).includes('Files');
  };

  const stopStaleWatch = () => {
    if (staleTimer) clearInterval(staleTimer);
    staleTimer = null;
  };

  const reset = () => {
    counter.value = 0;
    hasFiles.value = false;
    stopStaleWatch();
  };

  const startStaleWatch = () => {
    if (staleTimer) return;
    staleTimer = setInterval(() => {
      if (counter.value === 0) {
        stopStaleWatch();
        return;
      }
      if (Date.now() - lastDragOverAt > STALE_DRAG_MS) {
        reset();
        stopStaleWatch();
      }
    }, STALE_CHECK_MS);
  };

  const handleDragEnter = event => {
    if (!isEnabled.value) return;
    if (!eventHasFiles(event)) return;
    event.preventDefault();
    counter.value += 1;
    hasFiles.value = true;
    lastDragOverAt = Date.now();
    startStaleWatch();
  };

  const handleDragOver = event => {
    if (!isEnabled.value) return;
    if (!eventHasFiles(event)) return;
    event.preventDefault();
    lastDragOverAt = Date.now();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = 'copy';
    }
  };

  const handleDragLeave = event => {
    if (!isEnabled.value) return;
    // NÃO exigir `eventHasFiles` aqui: em alguns browsers o `dataTransfer` vem
    // vazio no `dragleave` (modo protegido). Se exigíssemos, o contador nunca
    // baixaria e o overlay ficaria preso. Só decrementa quem já estava contando.
    if (counter.value === 0) return;

    // relatedTarget nulo = o cursor saiu da janela inteira, não de um filho.
    if (event.relatedTarget == null) {
      reset();
      return;
    }
    counter.value = Math.max(0, counter.value - 1);
    if (counter.value === 0) {
      hasFiles.value = false;
    }
  };

  // O usuário cancelar o arraste (ESC, ou soltar fora da janela) dispara `dragend`
  // e NENHUM `drop`/`dragleave` que balance o contador. Sem tratar isso o overlay
  // ficava para sempre na tela cobrindo o app — parecia que tinha travado.
  const handleDragEnd = () => reset();

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

  // Só zera o visual; o envio fica com `handleDrop` (fase de bolha).
  const handleDropCapture = () => reset();

  // Reseta se a janela perder foco no meio de um drag
  const handleWindowBlur = () => reset();

  const attach = () => {
    window.addEventListener('dragenter', handleDragEnter);
    window.addEventListener('dragover', handleDragOver);
    window.addEventListener('dragleave', handleDragLeave);
    window.addEventListener('drop', handleDrop);
    // Reset do VISUAL na captura, separado do onDrop acima: um handler interno
    // que chame `stopPropagation` impediria o `drop` de chegar no window e
    // prenderia o overlay. Aqui só zeramos o estado — o envio continua saindo
    // pelo handler de bolha, então nada é anexado duas vezes.
    window.addEventListener('drop', handleDropCapture, true);
    window.addEventListener('dragend', handleDragEnd, true);
    window.addEventListener('blur', handleWindowBlur);
  };

  const detach = () => {
    window.removeEventListener('dragenter', handleDragEnter);
    window.removeEventListener('dragover', handleDragOver);
    window.removeEventListener('dragleave', handleDragLeave);
    window.removeEventListener('drop', handleDrop);
    window.removeEventListener('drop', handleDropCapture, true);
    window.removeEventListener('dragend', handleDragEnd, true);
    window.removeEventListener('blur', handleWindowBlur);
    stopStaleWatch();
  };

  onMounted(attach);
  onBeforeUnmount(detach);

  // Limpa estado quando desabilitado em runtime (ex: modal de nova conversa abre)
  watch(isEnabled, value => {
    if (!value) reset();
  });

  return { isOverDropZone };
}
