import { useI18n } from 'vue-i18n';
import { formatTime } from '@chatwoot/utils';

/**
 * Camada narrativa dos relatórios: transforma os `signals` estruturados que o
 * backend devolve (level/value/goal/ratio/delta_pct/is_highlight/is_attention)
 * em pílulas de semáforo e frases de insight — SEM texto hardcoded, tudo via i18n.
 *
 * O backend nunca devolve texto traduzido; a frase é montada aqui.
 */

// Mapeia a chave de relatório (usada nos cards/gráficos) para a métrica do signal.
export const SIGNAL_METRIC_BY_REPORT_KEY = {
  avg_first_response_time: 'first_response',
  avg_resolution_time: 'resolution',
  reply_time: 'reply',
  resolutions_count: 'resolution_rate',
};

// Direção do "bom": tempos = menor é melhor; taxas/scores = maior é melhor.
const LOWER_BETTER = {
  first_response: true,
  resolution: true,
  reply: true,
  resolution_rate: false,
  csat: false,
  nps: false,
};

// Métricas exibidas como percentual (a meta recebe sufixo %); demais tempos viram formatTime.
const PERCENT_METRICS = ['resolution_rate', 'csat'];

// Apresentação visual da pílula por nível (tokens do design system n-*).
const TONE_BY_LEVEL = {
  good: {
    tone: 'good',
    icon: '🟢',
    colorClass: 'border-n-teal-7 bg-n-teal-3 text-n-teal-11',
  },
  warn: {
    tone: 'warn',
    icon: '🟡',
    colorClass: 'border-n-amber-7 bg-n-amber-3 text-n-amber-11',
  },
  bad: {
    tone: 'bad',
    icon: '🔴',
    colorClass: 'border-n-ruby-8 bg-n-ruby-3 text-n-ruby-11',
  },
};

const LEVEL_KEY = { good: 'GOOD', warn: 'WARN', bad: 'BAD' };

export function useReportNarrative() {
  const { t } = useI18n();

  /** Encontra o signal de uma chave de relatório dentro do array de signals. */
  const signalForReportKey = (signals, reportKey) => {
    const metric = SIGNAL_METRIC_BY_REPORT_KEY[reportKey];
    if (!metric) return null;
    return (signals || []).find(signal => signal.metric === metric) || null;
  };

  /** Nome humano da métrica, traduzido. */
  const metricLabel = signal =>
    t(`REPORT.NARRATIVE.METRIC.${signal.metric.toUpperCase()}`);

  /** Encontra um signal pela métrica (ex.: 'csat', 'nps'). */
  const signalByMetric = (signals, metric) =>
    (signals || []).find(signal => signal.metric === metric) || null;

  /** Valor da meta formatado (% p/ taxas, número cru p/ score, tempo p/ segundos). */
  const goalDisplay = signal => {
    if (PERCENT_METRICS.includes(signal.metric)) return `${signal.goal}%`;
    if (signal.metric === 'nps') return `${signal.goal}`;
    return formatTime(signal.goal || 0);
  };

  /** Pílula de semáforo: { tone, icon, colorClass, label }. */
  const pillFor = signal => {
    if (!signal) return null;
    const tone = TONE_BY_LEVEL[signal.level] || TONE_BY_LEVEL.warn;
    return {
      ...tone,
      label: t(`REPORT.NARRATIVE.LEVEL.${LEVEL_KEY[signal.level] || 'WARN'}`),
    };
  };

  /** Foi melhor que o período anterior? (direção-aware). Null se sem delta. */
  const improvedVsPrevious = signal => {
    if (signal.delta_pct === null || signal.delta_pct === undefined)
      return null;
    if (signal.delta_pct === 0) return null;
    return LOWER_BETTER[signal.metric]
      ? signal.delta_pct < 0
      : signal.delta_pct > 0;
  };

  /** Frase curta de insight para o gráfico (variação vs período anterior + meta). */
  const phraseFor = signal => {
    if (!signal) return '';
    const improved = improvedVsPrevious(signal);
    const goal = t('REPORT.NARRATIVE.VS_GOAL', { goal: goalDisplay(signal) });

    if (improved === null) return goal;

    const pct = Math.abs(signal.delta_pct);
    const trend = improved
      ? t('REPORT.NARRATIVE.INSIGHT_BETTER', { pct })
      : t('REPORT.NARRATIVE.INSIGHT_WORSE', { pct });
    return `${trend} · ${goal}`;
  };

  /** Extrai highlight/attention para o TL;DR. */
  const summaryFor = signals => {
    const list = signals || [];
    const highlight = list.find(signal => signal.is_highlight) || null;
    const attention = list.find(signal => signal.is_attention) || null;
    return {
      highlight: highlight
        ? {
            signal: highlight,
            label: metricLabel(highlight),
            phrase: phraseFor(highlight),
          }
        : null,
      attention: attention
        ? {
            signal: attention,
            label: metricLabel(attention),
            phrase: phraseFor(attention),
          }
        : null,
      allGood: list.length > 0 && !attention,
    };
  };

  return {
    signalForReportKey,
    signalByMetric,
    metricLabel,
    goalDisplay,
    pillFor,
    phraseFor,
    summaryFor,
  };
}
