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

const showDesktop = (title, body) => {
  if (!('Notification' in window) || !title) return;
  const spawn = () => {
    try {
      // eslint-disable-next-line no-new
      new Notification(title, { body, silent: true });
    } catch (e) {
      // ignore
    }
  };
  if (Notification.permission === 'granted') {
    spawn();
  } else if (Notification.permission === 'default') {
    Notification.requestPermission()
      .then(p => {
        if (p === 'granted') spawn();
      })
      .catch(() => {});
  }
};

export const internalChatNotify = ({
  title,
  body,
  sound = true,
  tone = DEFAULT_TONE,
} = {}) => {
  if (sound) playSound(tone);
  showDesktop(title, body);
};

export default internalChatNotify;
