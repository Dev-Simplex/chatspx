const FALLBACK = '#94a3b8';

// Card aging thresholds (hours without activity). Tune here.
const HEAT_WARM_AFTER_H = 24; // >= 24h idle → warm
const HEAT_COLD_AFTER_H = 72; // >= 72h idle → cold

// Time-in-stage thresholds (hours since the card entered the current stage).
// Longer than the idle ones: sitting a couple of days in a stage is normal.
const STAGE_WARM_AFTER_H = 120; // >= 5 days in stage → warm
const STAGE_COLD_AFTER_H = 240; // >= 10 days in stage → cold

const toMillis = value => {
  if (value === null || value === undefined || value === '') return null;
  const ms = typeof value === 'number' ? value * 1000 : Date.parse(value);
  return Number.isNaN(ms) ? null : ms;
};

const normalizeHex = color => {
  if (!color || typeof color !== 'string') return FALLBACK;
  const hex = color.trim();
  return /^#([0-9a-f]{3}|[0-9a-f]{6})$/i.test(hex) ? hex : FALLBACK;
};

// Parse "rgb(r,g,b)" / "rgba(r,g,b,a)" into channels, or null if not that form.
const rgbStringToChannels = value => {
  if (typeof value !== 'string') return null;
  const match = value
    .trim()
    .match(/^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)/i);
  if (!match) return null;
  const clamp = n => Math.min(255, Math.max(0, Math.round(Number(n))));
  return {
    r: clamp(match[1]),
    g: clamp(match[2]),
    b: clamp(match[3]),
  };
};

const hexToRgb = hex => {
  // Accept rgb()/rgba() strings as-is instead of falling back to the default.
  const fromRgb = rgbStringToChannels(hex);
  if (fromRgb) return fromRgb;
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

  // Generic age level from a timestamp against warm/cold hour thresholds.
  // Returns 'fresh' | 'warm' | 'cold' (fresh shows no decoration).
  const ageLevel = (timestamp, warmAfterH, coldAfterH) => {
    const ms = toMillis(timestamp);
    if (ms === null) return 'fresh';
    const hours = (Date.now() - ms) / 3600000;
    if (hours >= coldAfterH) return 'cold';
    if (hours >= warmAfterH) return 'warm';
    return 'fresh';
  };

  // Idle signal — time since the conversation's last activity.
  const heatLevel = lastActivityAt =>
    ageLevel(lastActivityAt, HEAT_WARM_AFTER_H, HEAT_COLD_AFTER_H);

  // Pipeline signal — time the card has been sitting in its current stage.
  const stageAgeLevel = movedAt =>
    ageLevel(movedAt, STAGE_WARM_AFTER_H, STAGE_COLD_AFTER_H);

  // Proportional segments for the board-level funnel bar.
  // stages: [{ id, color, name }], countsByStage: { [id]: number }
  // Returns [{ id, name, color, count, pct }] (pct sums to ~100).
  const funnelSegments = (stages, countsByStage = {}) => {
    if (!Array.isArray(stages) || !stages.length) return [];
    const counts = stages.map(stage => ({
      stage,
      count: Math.max(0, Number(countsByStage[stage.id]) || 0),
    }));
    const total = counts.reduce((sum, c) => sum + c.count, 0);
    return counts.map(({ stage, count }) => ({
      id: stage.id,
      name: stage.name,
      color: normalizeHex(stage.color),
      count,
      pct: total ? Math.round((count / total) * 100) : 0,
    }));
  };

  return {
    accent,
    softBg,
    contrastText,
    normalizeHex,
    heatLevel,
    stageAgeLevel,
    funnelSegments,
  };
}

export default useStageColor;
