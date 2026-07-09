import { ref, computed } from 'vue';

// Histórico undo/redo da `definition` do canvas (Flow). Guarda SNAPSHOTS serializados da
// definition inteira — o FlowCanvasView muta a definition de forma imutável em vários pontos
// (addNode, onConnect, onEdgesChange, onNodeDragStop, updateSelectedNode), então um único
// watcher deep que chama `record` centraliza a captura sem instrumentar cada mutação.
//
// Coalescência: `record` é DEBOUNCED — uma rajada de mudanças rápidas (digitar num campo,
// arrastar) colapsa num único passo de undo. `commit` fixa a baseline (carga inicial / após
// salvar) e zera as pilhas; `markSaved` mantém o histórico mas marca o estado atual como salvo
// (dirty = false). `undo`/`redo` devolvem o snapshot alvo (desserializado) para o caller aplicar.

const EMPTY = { nodes: [], edges: [] };

const serialize = definition => JSON.stringify(definition ?? EMPTY);
const deserialize = snapshot => JSON.parse(snapshot);

export function useFlowHistory({ limit = 50, delay = 400 } = {}) {
  const undoStack = ref([]);
  const redoStack = ref([]);
  const baseline = ref(''); // último estado salvo — referência do dirty
  const currentSnap = ref(''); // último estado conhecido (imediato)
  const committedSnap = ref(''); // último estado empurrado para a timeline

  let burstBase = null; // snapshot no início da rajada de edições atual
  let timer = null;

  const canUndo = computed(() => undoStack.value.length > 0);
  const canRedo = computed(() => redoStack.value.length > 0);
  const isDirty = computed(() => currentSnap.value !== baseline.value);

  const clearTimer = () => {
    if (timer) {
      clearTimeout(timer);
      timer = null;
    }
  };

  // Fecha a rajada: empurra o snapshot-base da rajada para o undo e descarta o redo.
  const flush = () => {
    timer = null;
    if (burstBase === null || currentSnap.value === burstBase) {
      burstBase = null;
      return;
    }
    undoStack.value = [...undoStack.value, burstBase].slice(-limit);
    redoStack.value = [];
    committedSnap.value = currentSnap.value;
    burstBase = null;
  };

  // Registra uma mudança da definition (debounced). No-op se o estado não mudou de fato.
  const record = definition => {
    const snap = serialize(definition);
    if (snap === currentSnap.value) return;
    if (burstBase === null) burstBase = committedSnap.value;
    currentSnap.value = snap;
    clearTimer();
    timer = setTimeout(flush, delay);
  };

  // Baseline inicial (carga do flow): zera as pilhas e o dirty.
  const commit = definition => {
    const snap = serialize(definition);
    clearTimer();
    burstBase = null;
    baseline.value = snap;
    currentSnap.value = snap;
    committedSnap.value = snap;
    undoStack.value = [];
    redoStack.value = [];
  };

  // Marca o estado atual como salvo mantendo o histórico (dirty volta a false).
  const markSaved = definition => {
    if (timer) {
      clearTimer();
      flush();
    }
    const snap = serialize(definition);
    baseline.value = snap;
    currentSnap.value = snap;
    committedSnap.value = snap;
  };

  const undo = () => {
    if (timer) {
      clearTimer();
      flush();
    }
    if (!undoStack.value.length) return null;
    const previous = undoStack.value[undoStack.value.length - 1];
    undoStack.value = undoStack.value.slice(0, -1);
    redoStack.value = [...redoStack.value, currentSnap.value];
    currentSnap.value = previous;
    committedSnap.value = previous;
    return deserialize(previous);
  };

  const redo = () => {
    if (!redoStack.value.length) return null;
    const next = redoStack.value[redoStack.value.length - 1];
    redoStack.value = redoStack.value.slice(0, -1);
    undoStack.value = [...undoStack.value, currentSnap.value].slice(-limit);
    currentSnap.value = next;
    committedSnap.value = next;
    return deserialize(next);
  };

  return {
    canUndo,
    canRedo,
    isDirty,
    record,
    commit,
    markSaved,
    undo,
    redo,
  };
}
