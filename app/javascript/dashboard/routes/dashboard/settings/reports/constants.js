export const formatTime = timeInSeconds => {
  if (!timeInSeconds) {
    return '';
  }

  if (timeInSeconds < 60) {
    return `${timeInSeconds}s`;
  }

  if (timeInSeconds < 3600) {
    const minutes = Math.floor(timeInSeconds / 60);
    return `${minutes}m`;
  }

  if (timeInSeconds < 86400) {
    const hours = Math.floor(timeInSeconds / 3600);
    return `${hours}h`;
  }

  const days = Math.floor(timeInSeconds / 86400);
  return `${days}d`;
};

export const GROUP_BY_FILTER = {
  1: { id: 1, period: 'day' },
  2: { id: 2, period: 'week' },
  3: { id: 3, period: 'month' },
  4: { id: 4, period: 'year' },
};

export const GROUP_BY_OPTIONS = {
  DAY: {
    id: 'DAY',
    period: 'day',
    translationKey: 'REPORT.GROUPING_OPTIONS.DAY',
  },
  WEEK: {
    id: 'WEEK',
    period: 'week',
    translationKey: 'REPORT.GROUPING_OPTIONS.WEEK',
  },
  MONTH: {
    id: 'MONTH',
    period: 'month',
    translationKey: 'REPORT.GROUPING_OPTIONS.MONTH',
  },
  YEAR: {
    id: 'YEAR',
    period: 'year',
    translationKey: 'REPORT.GROUPING_OPTIONS.YEAR',
  },
};

export const DATE_RANGE_OPTIONS = {
  LAST_7_DAYS: {
    id: 'LAST_7_DAYS',
    translationKey: 'REPORT.DATE_RANGE_OPTIONS.LAST_7_DAYS',
    offset: 6,
    groupByOptions: [GROUP_BY_OPTIONS.DAY],
  },
  LAST_30_DAYS: {
    id: 'LAST_30_DAYS',
    translationKey: 'REPORT.DATE_RANGE_OPTIONS.LAST_30_DAYS',
    offset: 29,
    groupByOptions: [GROUP_BY_OPTIONS.DAY, GROUP_BY_OPTIONS.WEEK],
  },
  LAST_3_MONTHS: {
    id: 'LAST_3_MONTHS',
    translationKey: 'REPORT.DATE_RANGE_OPTIONS.LAST_3_MONTHS',
    offset: 89,
    groupByOptions: [
      GROUP_BY_OPTIONS.DAY,
      GROUP_BY_OPTIONS.WEEK,
      GROUP_BY_OPTIONS.MONTH,
    ],
  },
  LAST_6_MONTHS: {
    id: 'LAST_6_MONTHS',
    translationKey: 'REPORT.DATE_RANGE_OPTIONS.LAST_6_MONTHS',
    offset: 179,
    groupByOptions: [GROUP_BY_OPTIONS.WEEK, GROUP_BY_OPTIONS.MONTH],
  },
  LAST_YEAR: {
    id: 'LAST_YEAR',
    translationKey: 'REPORT.DATE_RANGE_OPTIONS.LAST_YEAR',
    offset: 364,
    groupByOptions: [GROUP_BY_OPTIONS.WEEK, GROUP_BY_OPTIONS.MONTH],
  },
  CUSTOM_DATE_RANGE: {
    id: 'CUSTOM_DATE_RANGE',
    translationKey: 'REPORT.DATE_RANGE_OPTIONS.CUSTOM_DATE_RANGE',
    offset: null,
    groupByOptions: [
      GROUP_BY_OPTIONS.DAY,
      GROUP_BY_OPTIONS.WEEK,
      GROUP_BY_OPTIONS.MONTH,
      GROUP_BY_OPTIONS.YEAR,
    ],
  },
};

export const CHART_FONT_FAMILY =
  'Inter,-apple-system,system-ui,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif';

const CHART_TICK_COLOR = '#475569';
const CHART_TICK_MUTED = '#64748b';
const CHART_GRID_COLOR = 'rgba(148, 163, 184, 0.25)';
const CHART_BORDER_COLOR = 'rgba(148, 163, 184, 0.5)';

export const DEFAULT_LINE_CHART = {
  type: 'line',
  fill: false,
  borderColor: '#64748b',
  pointBackgroundColor: '#64748b',
  borderWidth: 2,
  tension: 0.3,
};

export const DEFAULT_BAR_CHART = {
  type: 'bar',
  backgroundColor: 'rgba(45, 196, 111, 0.85)',
  borderRadius: 6,
  borderSkipped: false,
};

const createChartConfig = (yAxisTickCallback, withCountAxis = false) => ({
  datasets: withCountAxis
    ? [DEFAULT_BAR_CHART, DEFAULT_LINE_CHART]
    : [DEFAULT_BAR_CHART],
  scales: {
    x: {
      ticks: {
        fontFamily: CHART_FONT_FAMILY,
        maxRotation: 0,
        autoSkip: true,
        maxTicksLimit: 8,
      },
      grid: {
        drawOnChartArea: false,
        color: CHART_GRID_COLOR,
      },
    },
    y: {
      type: 'linear',
      position: 'left',
      ticks: {
        fontFamily: CHART_FONT_FAMILY,
        beginAtZero: true,
        callback: yAxisTickCallback,
        maxTicksLimit: 6,
        precision: 0,
        color: CHART_TICK_COLOR,
      },
      grid: {
        drawOnChartArea: false,
        color: CHART_GRID_COLOR,
      },
      border: {
        color: CHART_BORDER_COLOR,
      },
      grace: '10%',
    },
    ...(withCountAxis && {
      y1: {
        type: 'linear',
        position: 'right',
        ticks: {
          fontFamily: CHART_FONT_FAMILY,
          beginAtZero: true,
          maxTicksLimit: 5,
          precision: 0,
          color: CHART_TICK_MUTED,
        },
        grid: {
          drawOnChartArea: false,
          color: CHART_GRID_COLOR,
        },
        border: {
          color: CHART_BORDER_COLOR,
        },
        grace: '10%',
      },
    }),
  },
});

export const DEFAULT_CHART = createChartConfig((value, index, ticks) => {
  if (!index || index === ticks.length - 1) {
    return value;
  }
  return '';
});

export const TIME_CHART_CONFIG = createChartConfig((value, index, values) => {
  if (!index || index === values.length - 1) {
    return formatTime(value);
  }
  return '';
}, true);

export const METRIC_CHART = {
  conversations_count: DEFAULT_CHART,
  incoming_messages_count: DEFAULT_CHART,
  outgoing_messages_count: DEFAULT_CHART,
  avg_first_response_time: TIME_CHART_CONFIG,
  avg_first_response_time_after_assignment: TIME_CHART_CONFIG,
  reply_time: TIME_CHART_CONFIG,
  avg_resolution_time: TIME_CHART_CONFIG,
  resolutions_count: DEFAULT_CHART,
  bot_resolutions_count: DEFAULT_CHART,
  bot_handoffs_count: DEFAULT_CHART,
};

export const OVERVIEW_METRICS = {
  open: 'OPEN',
  unattended: 'UNATTENDED',
  unassigned: 'UNASSIGNED',
  pending: 'PENDING',
  online: 'ONLINE',
  busy: 'BUSY',
  offline: 'OFFLINE',
};
