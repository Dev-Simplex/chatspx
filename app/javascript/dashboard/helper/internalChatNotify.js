// Chat interno (v2 Fase 4) — light, best-effort notifications: a short sound +
// (when granted) a desktop notification. Used for @mentions and new DMs.

let audio = null;

const playSound = () => {
  try {
    if (!audio) audio = new Audio('/audio/dashboard/ping.mp3');
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

export const internalChatNotify = ({ title, body, sound = true } = {}) => {
  if (sound) playSound();
  showDesktop(title, body);
};

export default internalChatNotify;
