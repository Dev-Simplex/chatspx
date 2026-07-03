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
  // A numeric 0 (or negative) is the serialized "no timestamp" sentinel
  // (e.g. waiting_since.to_i => 0 when nil) — treat it as absent, not 1970.
  if (typeof value === 'number') return value > 0 ? value * 1000 : null;
  const ms = Date.parse(value);
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

  // SLA signal — time-in-stage measured against a per-stage budget (hours).
  // Returns 'none' (no SLA configured) | 'ok' | 'risk' (>=80% of budget) |
  // 'breach' (budget exceeded). Drives conditional card coloring.
  const SLA_RISK_RATIO = 0.8;
  const slaLevel = (movedAt, slaHours) => {
    const budget = Number(slaHours);
    if (!Number.isFinite(budget) || budget <= 0) return 'none';
    const ms = toMillis(movedAt);
    if (ms === null) return 'none';
    const elapsedH = (Date.now() - ms) / 3600000;
    if (elapsedH >= budget) return 'breach';
    if (elapsedH >= budget * SLA_RISK_RATIO) return 'risk';
    return 'ok';
  };

  // Fraction of the SLA budget consumed (0..>1), for progress bars/tooltips.
  const slaProgress = (movedAt, slaHours) => {
    const budget = Number(slaHours);
    const ms = toMillis(movedAt);
    if (!Number.isFinite(budget) || budget <= 0 || ms === null) return 0;
    const elapsedH = (Date.now() - ms) / 3600000;
    return elapsedH / budget;
  };

  // Wait signal — the strongest "act on me" cue on the board.
  //  - 'awaiting': the customer is waiting on a reply (waiting_since set).
  //    Level escalates with the wait: >=8h→4, >=2h→3, >=30min→2, else 1.
  //  - 'stalled': nobody is waiting (waiting_since null) but the card has gone
  //    quiet — the agent/system spoke last and silence followed.
  //  - 'none': fresh enough, no decoration.
  // Returns { kind, level, seconds }. Pure — safe to call in render.
  const waitSignal = (waitingSince, lastActivityAt) => {
    const waitMs = toMillis(waitingSince);
    if (waitMs !== null) {
      const seconds = Math.max(0, (Date.now() - waitMs) / 1000);
      const hours = seconds / 3600;
      let level = 1;
      if (hours >= 8) level = 4;
      else if (hours >= 2) level = 3;
      else if (hours >= 0.5) level = 2;
      return { kind: 'awaiting', level, seconds };
    }
    const idleMs = toMillis(lastActivityAt);
    if (idleMs !== null) {
      const seconds = Math.max(0, (Date.now() - idleMs) / 1000);
      const hours = seconds / 3600;
      if (hours >= 72) return { kind: 'stalled', level: 3, seconds };
      if (hours >= 24) return { kind: 'stalled', level: 2, seconds };
      if (hours >= 8) return { kind: 'stalled', level: 1, seconds };
    }
    return { kind: 'none', level: 0, seconds: 0 };
  };

  // Sort key (DESC) for prioritizing waiting cards to the top of a column.
  // Banded so awaiting always outranks stalled, and stalled outranks none,
  // with the in-band wait length as the tiebreaker. seconds (~1e8 max) stays
  // far below the 1e12 band gap, so bands never collide.
  const waitSortKey = (waitingSince, lastActivityAt) => {
    const { kind, seconds } = waitSignal(waitingSince, lastActivityAt);
    const secs = Number.isFinite(seconds) ? seconds : 0;
    if (kind === 'awaiting') return 2e12 + secs;
    if (kind === 'stalled') return 1e12 + secs;
    return 0;
  };

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
    slaLevel,
    slaProgress,
    waitSignal,
    waitSortKey,
    funnelSegments,
  };
}

export default useStageColor;
