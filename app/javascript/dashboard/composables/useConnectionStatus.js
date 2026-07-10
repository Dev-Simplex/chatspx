import { ref } from 'vue';

// Thresholds tunáveis do aviso offline escalonado (KICKOFF §1):
//   N0 (< GRACE_MS ..............): grace — nada aparece (reconexão sub-segundo).
//   N1 (GRACE_MS .. SUSTAINED_MS ): pill discreto "Reconectando…" (topo-esquerda).
//   N2 (> SUSTAINED_MS ..........): barra full-width no topo + hint no composer.
export const GRACE_MS = 2500;
export const SUSTAINED_MS = 8000;

// Estado global (singleton de módulo): o app mantém UMA conexão realtime, então o
// nível "offline sustentado" (N2) é único e compartilhado entre os três indicadores
// — a barra do topo (ConnectionStatusBar), o pill (NetworkNotification, que é quem
// arma/desarma os relógios) e o hint do composer (ReplyBox). Um único ref evita
// timers duplicados e mantém os três em sincronia sem acoplá-los por eventos ad-hoc.
const isSustainedOffline = ref(false);

export function useConnectionStatus() {
  return { isSustainedOffline };
}

export default useConnectionStatus;
