const BASE = 'KANBAN.GLOSSARY';

// Build the i18n key set for one glossary term from its id. `advice` is opt-in
// because not every term carries a "what to do" line (e.g. status colors).
const term = (id, { icon = null, swatch = null, advice = false } = {}) => ({
  id,
  icon,
  swatch,
  labelKey: `${BASE}.TERMS.${id}.LABEL`,
  descKey: `${BASE}.TERMS.${id}.DESC`,
  adviceKey: advice ? `${BASE}.TERMS.${id}.ADVICE` : null,
});

/**
 * Single source of truth for the Kanban legend/help system.
 *
 * Returns the canonical, grouped list of every signal, color, icon and number
 * the board uses — each entry points at the same i18n keys the cards/columns
 * already render, plus the matching swatch color class (the `n-*` tokens from
 * KanbanCard/KanbanColumn) and lucide icon. Consumed by KanbanLegend.vue and,
 * where useful, by tooltips, so the explanation never drifts from the UI.
 *
 * Pure data — no reactivity. Components translate the *Key fields with t().
 */
export function useKanbanGlossary() {
  const groups = [
    {
      id: 'card-signals',
      titleKey: `${BASE}.GROUPS.CARD_SIGNALS`,
      terms: [
        term('AWAITING', {
          icon: 'i-lucide-bell-ring',
          swatch: 'bg-n-ruby-9',
          advice: true,
        }),
        term('STALLED', {
          icon: 'i-lucide-moon',
          swatch: 'bg-n-blue-9',
          advice: true,
        }),
        term('AGING_WARM', {
          icon: 'i-lucide-alarm-clock',
          swatch: 'bg-n-amber-9',
          advice: true,
        }),
        term('AGING_COLD', {
          icon: 'i-lucide-snowflake',
          swatch: 'bg-n-ruby-9',
          advice: true,
        }),
        term('SLA_RISK', {
          icon: 'i-lucide-gauge',
          swatch: 'bg-n-amber-9',
          advice: true,
        }),
        term('SLA_BREACH', {
          icon: 'i-lucide-gauge',
          swatch: 'bg-n-ruby-9',
          advice: true,
        }),
        term('STAGE_AGE', {
          icon: 'i-lucide-hourglass',
          swatch: 'bg-n-amber-9',
          advice: true,
        }),
        term('SCHEDULED', {
          icon: 'i-lucide-send',
          swatch: 'bg-n-teal-9',
          advice: true,
        }),
      ],
    },
    {
      id: 'status',
      titleKey: `${BASE}.GROUPS.STATUS`,
      terms: [
        term('STATUS_OPEN', { swatch: 'bg-n-teal-9' }),
        term('STATUS_PENDING', { swatch: 'bg-n-amber-9' }),
        term('STATUS_RESOLVED', { swatch: 'bg-n-slate-9' }),
        term('STATUS_SNOOZED', { swatch: 'bg-n-blue-9' }),
      ],
    },
    {
      id: 'priority',
      titleKey: `${BASE}.GROUPS.PRIORITY`,
      terms: [term('PRIORITY', { icon: 'i-lucide-signal-high', advice: true })],
    },
    {
      id: 'column',
      titleKey: `${BASE}.GROUPS.COLUMN`,
      terms: [
        term('WIP', { icon: 'i-lucide-layers', advice: true }),
        term('FOOTER_AWAITING', { icon: 'i-lucide-bell-ring' }),
        term('FOOTER_UNASSIGNED', { icon: 'i-lucide-user-x' }),
        term('FOOTER_COLD', { icon: 'i-lucide-snowflake' }),
        term('FOOTER_OVERDUE', { icon: 'i-lucide-gauge' }),
        term('FOOTER_SCHEDULED', { icon: 'i-lucide-send' }),
      ],
    },
    {
      id: 'funnel-bar',
      titleKey: `${BASE}.GROUPS.FUNNEL_BAR`,
      terms: [
        term('FUNNEL_SEGMENT', {
          icon: 'i-lucide-bar-chart-horizontal',
          advice: true,
        }),
      ],
    },
    {
      id: 'actions',
      titleKey: `${BASE}.GROUPS.ACTIONS`,
      terms: [
        term('ASSIGNEE', { icon: 'i-lucide-user-round', advice: true }),
        term('PREVIEW', { icon: 'i-lucide-eye' }),
        term('SCHEDULE_ACTION', { icon: 'i-lucide-send' }),
        term('MOVE_ACTION', { icon: 'i-lucide-arrow-right-left' }),
        term('REMOVE_ACTION', { icon: 'i-lucide-trash-2' }),
        term('ADD_ACTION', { icon: 'i-lucide-plus' }),
      ],
    },
  ];

  // Flat list of every term — handy for specs and lookups.
  const allTerms = groups.flatMap(group => group.terms);

  return { groups, allTerms };
}

export default useKanbanGlossary;
