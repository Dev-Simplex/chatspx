// D8 / D-L6 — Confetti de celebração ao assumir conversa (D2).
// SEMPRE lazy: `import()` dinâmico (molde `ensureLeaflet`,
// LocationPickerModal.vue) mantém canvas-confetti FORA do bundle inicial.
// `disableForReducedMotion: true` respeita prefers-reduced-motion (DD-10).

let firedThisSession = false;

// D-L5: canvas-confetti instalado (1.9.4). Specifier literal — o Vite analisa
// o import e gera o chunk lazy (a indireção via variável do pré-D-L5 NÃO gerava
// chunk e quebrava o bare specifier no browser; ver Licao - Vite Dynamic Import
// Lib Nao Instalada no vault).
const defaultImporter = () => import('canvas-confetti');
let importConfetti = defaultImporter;

/**
 * Dispara um confetti sutil — apenas na PRIMEIRA assunção da sessão.
 *
 * @returns {Promise<boolean>} true se o confetti disparou nesta chamada.
 */
export async function fireTakeoverConfetti() {
  if (firedThisSession) return false;
  // Marca ANTES do import: evita double-fire em chamadas concorrentes
  // enquanto o chunk carrega (receita do design §9.2).
  firedThisSession = true;
  try {
    const { default: confetti } = await importConfetti();
    confetti({
      particleCount: 30,
      scalar: 0.8,
      spread: 60,
      origin: { y: 0.8 },
      disableForReducedMotion: true,
    });
    return true;
  } catch {
    // Lib ausente (pré D-L5) ou chunk falhou — sem confetti, sem erro.
    return false;
  }
}

// --- Test seams (somente specs) -------------------------------------------

export function setConfettiImporterForTesting(importer) {
  importConfetti = importer;
}

export function resetConfettiForTesting() {
  firedThisSession = false;
  importConfetti = defaultImporter;
}
