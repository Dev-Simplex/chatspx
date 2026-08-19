/**
 * O portão do esqueleto de carregamento — bloco 2.07.
 *
 * "Skeleton só acima de 600 ms". A razão é a mesma da carência da faixa: um
 * esqueleto que aparece e some em 200 ms é um flash — a tela pisca, o olho
 * persegue, e a impressão é de defeito, não de carregamento. Abaixo do limiar, a
 * resposta chega tão rápido que não há nada a comunicar.
 */
export const SKELETON_THRESHOLD_MS = 600;

export const createLoadingGate = ({
  thresholdMs = SKELETON_THRESHOLD_MS,
  schedule = setTimeout,
  cancel = clearTimeout,
} = {}) => {
  let visible = false;
  let timer = null;
  const listeners = new Set();

  const emit = () => listeners.forEach(fn => fn(visible));

  return {
    get isVisible() {
      return visible;
    },

    subscribe(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },

    start() {
      if (timer) return;
      timer = schedule(() => {
        visible = true;
        emit();
      }, thresholdMs);
    },

    stop() {
      if (timer) cancel(timer);
      timer = null;
      if (!visible) return;
      visible = false;
      emit();
    },
  };
};
