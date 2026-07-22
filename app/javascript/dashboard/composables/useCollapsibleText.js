import { ref, nextTick, onMounted, watch } from 'vue';

/**
 * Colapsa um texto longo com clamp de linhas + toggle "ler mais/menos".
 *
 * O estado é LOCAL e NÃO persiste: nasce colapsado e volta a colapsar toda vez
 * que o texto observado muda (troca de conversa) ou o componente remonta
 * (refresh). O toggle só é oferecido quando o texto de fato transborda o clamp.
 *
 * @param {import('vue').Ref<string>} source Texto observado (recolhe ao mudar).
 * @returns {{ contentRef: import('vue').Ref, isExpanded: import('vue').Ref<boolean>, isOverflowing: import('vue').Ref<boolean>, toggle: () => void }}
 */
export function useCollapsibleText(source) {
  const contentRef = ref(null);
  const isExpanded = ref(false);
  const isOverflowing = ref(false);

  const measure = () => {
    const el = contentRef.value;
    // Medido enquanto colapsado: scrollHeight > clientHeight indica corte.
    isOverflowing.value = el ? el.scrollHeight - el.clientHeight > 1 : false;
  };

  const toggle = () => {
    isExpanded.value = !isExpanded.value;
  };

  onMounted(() => nextTick(measure));
  watch(
    () => source.value,
    () => {
      isExpanded.value = false;
      nextTick(measure);
    }
  );

  return { contentRef, isExpanded, isOverflowing, toggle };
}
