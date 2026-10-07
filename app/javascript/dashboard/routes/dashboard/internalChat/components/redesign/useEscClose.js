import { watch, onBeforeUnmount } from 'vue';

// Esc fecha a camada aberta (menu, janela, seletor). Escuta na fase de captura
// e segura o evento: só a camada de cima fecha e o resto da tela não reage ao
// mesmo Esc (busca, Detalhes, resposta continuam como estão).
export const useEscClose = (isOpen, close) => {
  const onKey = event => {
    if (event.key !== 'Escape') return;
    event.stopPropagation();
    close();
  };
  const stop = () => window.removeEventListener('keydown', onKey, true);
  watch(
    isOpen,
    open => {
      if (open) window.addEventListener('keydown', onKey, true);
      else stop();
    },
    { immediate: true }
  );
  onBeforeUnmount(stop);
};
