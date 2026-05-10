import { ref, onBeforeUnmount } from 'vue';

/**
 * Reactive flag for the user's `prefers-reduced-motion` media query.
 *
 * Returns `prefersReducedMotion` ref that automatically updates if the user
 * toggles their OS preference while the component is mounted. Components
 * should disable non-essential animations (stagger, scale, slide, shimmer)
 * when this is `true` and fall back to a simple opacity transition.
 */
export function useReducedMotion() {
  const prefersReducedMotion = ref(false);
  let mediaQuery = null;
  let cleanup = null;

  if (typeof window !== 'undefined' && window.matchMedia) {
    mediaQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    prefersReducedMotion.value = mediaQuery.matches;
    const handler = event => {
      prefersReducedMotion.value = event.matches;
    };
    mediaQuery.addEventListener('change', handler);
    cleanup = () => mediaQuery.removeEventListener('change', handler);
  }

  onBeforeUnmount(() => {
    if (cleanup) cleanup();
  });

  return { prefersReducedMotion };
}
