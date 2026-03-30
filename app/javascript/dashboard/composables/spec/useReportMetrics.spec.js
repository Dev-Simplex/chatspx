import { ref } from 'vue';
import { useReportMetrics } from '../useReportMetrics';
import { useMapGetter } from 'dashboard/composables/store';
import { summary, botSummary } from './fixtures/reportFixtures';

vi.mock('dashboard/composables/store');
vi.mock('@chatwoot/utils', () => ({
  formatTime: vi.fn(time => `formatted_${time}`),
}));

describe('useReportMetrics', () => {
  const setupMock = (summaryData = summary) => {
    useMapGetter
      .mockReturnValueOnce(ref(summaryData))
      .mockReturnValueOnce(ref(false));
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('calculates trend correctly', () => {
    setupMock();
    const { calculateTrend } = useReportMetrics();

    expect(calculateTrend('conversations_count')).toBe(124900);
    expect(calculateTrend('incoming_messages_count')).toBe(0);
    expect(calculateTrend('avg_first_response_time')).toBe(123);
  });

  it('returns 0 for trend when previous value is not available', () => {
    setupMock();
    const { calculateTrend } = useReportMetrics();

    expect(calculateTrend('non_existent_key')).toBe(0);
  });

  it('identifies average metric types correctly', () => {
    setupMock();
    const { isAverageMetricType } = useReportMetrics();

    expect(isAverageMetricType('avg_first_response_time')).toBe(true);
    expect(isAverageMetricType('avg_resolution_time')).toBe(true);
    expect(isAverageMetricType('reply_time')).toBe(true);
    expect(isAverageMetricType('conversations_count')).toBe(false);
  });

  it('displays metrics correctly for account', () => {
    setupMock();
    const { displayMetric } = useReportMetrics();

    expect(displayMetric('conversations_count')).toBe(
      Number(5000).toLocaleString()
    );
    expect(displayMetric('incoming_messages_count')).toBe('5');
  });

  it('displays the metric for bot', () => {
    setupMock(botSummary);
    const customKey = 'getBotSummary';
    const { displayMetric } = useReportMetrics(customKey);

    expect(displayMetric('bot_resolutions_count')).toBe('10');
    expect(displayMetric('bot_handoffs_count')).toBe('20');
  });

  it('handles non-existent metrics', () => {
    setupMock();
    const { displayMetric } = useReportMetrics();

    expect(displayMetric('non_existent_key')).toBe('0');
  });
});
