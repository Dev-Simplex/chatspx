const FALLBACK = '#94a3b8';

const normalizeHex = color => {
  if (!color || typeof color !== 'string') return FALLBACK;
  const hex = color.trim();
  return /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(hex) ? hex : FALLBACK;
};

const hexToRgb = hex => {
  let normalized = normalizeHex(hex).slice(1);
  if (normalized.length === 3) {
    normalized = normalized
      .split('')
      .map(char => char + char)
      .join('');
  }
  const int = parseInt(normalized, 16);
  return {
    r: Math.floor(int / 65536) % 256,
    g: Math.floor(int / 256) % 256,
    b: int % 256,
  };
};

/**
 * Helpers to derive a coherent visual palette from a single stage/label color.
 * Pure functions — no reactivity needed, safe to call in render.
 */
export function useStageColor() {
  const accent = color => normalizeHex(color);

  const softBg = (color, alpha = 0.12) => {
    const { r, g, b } = hexToRgb(color);
    return `rgba(${r}, ${g}, ${b}, ${alpha})`;
  };

  // Pick black/white text that stays legible over the given background color.
  const contrastText = color => {
    const { r, g, b } = hexToRgb(color);
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return luminance > 0.62 ? '#1f2933' : '#ffffff';
  };

  return { accent, softBg, contrastText, normalizeHex };
}

export default useStageColor;
