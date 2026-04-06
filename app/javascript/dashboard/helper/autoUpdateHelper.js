let initialVersion = null;

export function setInitialVersion(version) {
  initialVersion = version;
}

export function getInitialVersion() {
  return initialVersion;
}

export async function fetchVersion() {
  try {
    const response = await fetch(`/version.json?t=${Date.now()}`);
    const { version } = await response.json();
    return version;
  } catch {
    return null;
  }
}

export function forceCleanReload() {
  const preservePatterns = ['token', 'user_id', 'cw_d_', 'cw_just_updated'];

  if (navigator.serviceWorker) {
    navigator.serviceWorker.getRegistrations().then(registrations => {
      registrations.forEach(r => r.unregister());
    });
  }

  if (window.caches) {
    caches.keys().then(keys => {
      keys.forEach(key => caches.delete(key));
    });
  }

  const keysToRemove = [];
  for (let i = 0; i < localStorage.length; i += 1) {
    const key = localStorage.key(i);
    if (!preservePatterns.some(pattern => key.includes(pattern))) {
      keysToRemove.push(key);
    }
  }
  keysToRemove.forEach(key => localStorage.removeItem(key));

  sessionStorage.clear();

  localStorage.setItem('cw_just_updated', 'true');
  window.location.reload(true);
}
