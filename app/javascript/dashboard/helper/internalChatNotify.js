// Chat interno (v2 Fase 4) — light, best-effort notifications: a short sound +
// (when granted) a desktop notification. Used for @mentions and new DMs.

// Um Audio por toque (o toque é configurável nas UI settings do chat interno).
// O valor do toque já inclui a extensão (ex.: 'pop.wav', 'chime.mp3').
const DEFAULT_TONE = 'pop.wav';
const audioByTone = {};

const playSound = tone => {
  try {
    // valores antigos sem extensão (ex.: 'ding') caem no toque padrão
    const key = tone && tone.includes('.') ? tone : DEFAULT_TONE;
    if (!audioByTone[key]) {
      audioByTone[key] = new Audio(`/audio/internal_chat/${key}`);
    }
    const audio = audioByTone[key];
    audio.currentTime = 0;
    audio.play().catch(() => {});
  } catch (e) {
    // ignore — audio is non-critical
  }
};

// Clicar no aviso abre a conversa do chat interno (?channel= na tela do chat).
// Import tardio: o router importa o painel, que importa este helper.
const openChannel = async channelId => {
  window.focus();
  const { default: router } = await import('dashboard/routes');
  const { accountId } = router.currentRoute.value.params;
  if (!accountId) return;
  router.push({
    name: 'internal_chat_index',
    params: { accountId },
    query: { channel: String(channelId) },
  });
};

// A tag por canal é a mesma do push do servidor (InternalMessages::PushService):
// com a aba em segundo plano chegam os dois e o navegador mostra um só.
const showDesktop = (title, body, channelId) => {
  if (!('Notification' in window) || !title) return;
  const spawn = () => {
    try {
      const notification = new Notification(title, {
        body,
        silent: true,
        tag: channelId ? `internal-chat-${channelId}` : undefined,
      });
      if (channelId) {
        notification.onclick = () => {
          notification.close();
          openChannel(channelId);
        };
      }
    } catch (e) {
      // ignore
    }
  };
  // A permissão é pedida no convite da tela do chat (InternalChatPushPrompt),
  // nunca no meio de um aviso: pedido sem clique o navegador esconde ou bloqueia.
  if (Notification.permission === 'granted') spawn();
};

export const internalChatNotify = ({
  title,
  body,
  sound = true,
  tone = DEFAULT_TONE,
  channelId = null,
} = {}) => {
  if (sound) playSound(tone);
  showDesktop(title, body, channelId);
};

export default internalChatNotify;
