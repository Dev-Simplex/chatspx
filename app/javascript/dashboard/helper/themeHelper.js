import { LocalStorage } from 'shared/helpers/localStorage';
import { LOCAL_STORAGE_KEYS } from 'dashboard/constants/localStorage';

const applyTheme = isOSOnDarkMode => {
  const selectedColorScheme =
    LocalStorage.get(LOCAL_STORAGE_KEYS.COLOR_SCHEME) || 'auto';
  if (
    (selectedColorScheme === 'auto' && isOSOnDarkMode) ||
    selectedColorScheme === 'dark'
  ) {
    document.body.classList.add('dark');
    document.documentElement.style.setProperty('color-scheme', 'dark');
  } else {
    document.body.classList.remove('dark');
    document.documentElement.style.setProperty('color-scheme', 'light');
  }
};

export const setColorTheme = isOSOnDarkMode => {
  // View Transitions API: cross-fade between theme states (Chrome 111+, Edge 111+)
  if (
    typeof document !== 'undefined' &&
    document.startViewTransition &&
    document.visibilityState === 'visible'
  ) {
    const transition = document.startViewTransition(() =>
      applyTheme(isOSOnDarkMode)
    );
    // The theme is already applied when the animation is skipped (tab hidden or
    // window resized mid-transition); the rejection is only a warning about the
    // animation, so it must not reach the error tracker.
    transition.ready.catch(() => {});
    transition.finished.catch(() => {});
    return;
  }
  applyTheme(isOSOnDarkMode);
};
