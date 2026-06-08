// KANBAN-P2-02: aging visual / deal rotting.
// Calcula daysInStage + nível ('fresh' | 'warning' | 'rotting') baseado em
// `last_stage_change_at` (do item) + `rot_after_days` (da stage).
//
// Regras:
// - <24h               => fresh   (verde/cinza)
// - 24h-3d, ou >=50% do rot_after_days => warning (amber)
// - >rot_after_days (ou >5d se sem config) => rotting (ruby)
//
// Retorno é reativo (computed). Aceita `item` e `stage` refs.

import { computed, unref } from 'vue';

const FALLBACK_ROT_DAYS = 5;

const parseDate = value => {
  if (!value) return null;
  if (typeof value === 'number') return new Date(value * 1000);
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
};

export const useKanbanAging = (itemRef, stageRef) => {
  const daysInStage = computed(() => {
    const item = unref(itemRef);
    if (!item) return 0;
    // Preferir last_stage_change_at; fallback p/ aging_days computado no backend.
    const ts =
      item.lastStageChangeAt ||
      item.last_stage_change_at ||
      item.movedAt ||
      item.moved_at;
    const date = parseDate(ts);
    if (date) {
      return Math.max(0, Math.floor((Date.now() - date.getTime()) / 86400000));
    }
    const fallback = Number(item.agingDays ?? item.aging_days);
    return Number.isFinite(fallback) ? fallback : 0;
  });

  const rotLimit = computed(() => {
    const stage = unref(stageRef);
    const limit = Number(stage?.rotAfterDays ?? stage?.rot_after_days);
    return Number.isFinite(limit) && limit > 0 ? limit : FALLBACK_ROT_DAYS;
  });

  const level = computed(() => {
    const days = daysInStage.value;
    const limit = rotLimit.value;
    if (days >= limit) return 'rotting';
    if (days >= 1 && days >= Math.ceil(limit * 0.5)) return 'warning';
    if (days >= 1) return 'fresh';
    return 'fresh';
  });

  const color = computed(() => {
    switch (level.value) {
      case 'rotting':
        return 'ruby';
      case 'warning':
        return 'amber';
      default:
        return 'slate';
    }
  });

  return { daysInStage, level, color, rotLimit };
};
