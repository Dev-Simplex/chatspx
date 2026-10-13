import { useI18n } from 'vue-i18n';
import { formatDuration, timesFromPct } from 'dashboard/helper/reportFormat';

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
  sla_hit_rate: false,
  bot_resolution_rate: false,
  bot_handoff_rate: true,
};

// Métricas exibidas como percentual (a meta recebe sufixo %); score (nps) cru; resto tempo.
const PERCENT_METRICS = [
  'resolution_rate',
  'csat',
  'sla_hit_rate',
  'bot_resolution_rate',
  'bot_handoff_rate',
];

const SEVERITY = { good: 0, warn: 1, bad: 2 };
const LEVEL_BY_SEVERITY = ['good', 'warn', 'bad'];

// Pontinho de status p/ células de tabela (apenas cor de fundo).
const DOT_BY_LEVEL = {
  good: 'bg-n-teal-9',
  warn: 'bg-n-amber-9',
  bad: 'bg-n-ruby-9',
};

// Normaliza um signal vindo de stores que aplicam camelCase (deep) nas chaves.
const normalizeSignal = signal => ({
  metric: signal.metric,
  value: signal.value,
  goal: signal.goal,
  level: signal.level,
  ratio: signal.ratio,
  delta_pct: signal.delta_pct ?? signal.deltaPct ?? null,
  is_highlight: signal.is_highlight ?? signal.isHighlight ?? false,
  is_attention: signal.is_attention ?? signal.isAttention ?? false,
});

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
    return formatDuration(signal.goal || 0, t);
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

  /** Classe de cor do pontinho de status (para células de tabela). */
  const dotClassFor = signal =>
    signal ? DOT_BY_LEVEL[signal.level] || '' : '';

  /** Frase curta de insight para o gráfico (variação vs período anterior + meta). */
  const phraseFor = rawSignal => {
    if (!rawSignal) return '';
    const signal = normalizeSignal(rawSignal);
    const improved = improvedVsPrevious(signal);
    const goal = t('REPORT.NARRATIVE.VS_GOAL', { goal: goalDisplay(signal) });

    if (improved === null) return goal;

    // "5422% pior" ninguem le: acima de +100% vira "N vezes".
    const pct = Math.abs(signal.delta_pct);
    const times = timesFromPct(pct);
    let trend;
    if (pct >= 100) {
      trend = improved
        ? t('REPORT.NARRATIVE.INSIGHT_BETTER_TIMES', { times })
        : t('REPORT.NARRATIVE.INSIGHT_WORSE_TIMES', { times });
    } else {
      trend = improved
        ? t('REPORT.NARRATIVE.INSIGHT_BETTER', { pct })
        : t('REPORT.NARRATIVE.INSIGHT_WORSE', { pct });
    }
    return `${trend} · ${goal}`;
  };

  /**
   * Agrega signals de várias entidades (tabelas) em um veredito médio por métrica,
   * pela severidade média (good<warn<bad). Usado no TL;DR das tabelas.
   */
  const aggregateSignals = signalArrays => {
    const byMetric = {};
    (signalArrays || [])
      .flat()
      .filter(Boolean)
      .forEach(raw => {
        const s = normalizeSignal(raw);
        if (!s.metric) return;
        (byMetric[s.metric] ||= []).push(s);
      });

    const agg = Object.entries(byMetric).map(([metric, sigs]) => {
      const avgSev =
        sigs.reduce((sum, s) => sum + (SEVERITY[s.level] ?? 1), 0) /
        sigs.length;
      const level = LEVEL_BY_SEVERITY[Math.round(avgSev)];
      const avgRatio =
        sigs.reduce((sum, s) => sum + (Number(s.ratio) || 0), 0) / sigs.length;
      return {
        metric,
        level,
        goal: sigs[0].goal,
        value: null,
        ratio: avgRatio,
        delta_pct: null,
        severity: SEVERITY[level],
        is_highlight: false,
        is_attention: false,
      };
    });

    if (agg.length) {
      const best = agg.reduce((a, b) =>
        a.severity < b.severity ||
        (a.severity === b.severity && a.ratio <= b.ratio)
          ? a
          : b
      );
      const worst = agg.reduce((a, b) =>
        a.severity > b.severity ||
        (a.severity === b.severity && a.ratio >= b.ratio)
          ? a
          : b
      );
      best.is_highlight = true;
      if (worst.level !== 'good') worst.is_attention = true;
    }
    return agg;
  };

  /** Extrai highlight/attention para o TL;DR. */
  const summaryFor = signals => {
    const list = (signals || []).map(normalizeSignal);
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

  /**
   * Veredito de uma tela em uma frase, a partir dos signals: 'good' (tudo na meta), 'warn' (algo
   * quase), 'bad' (algo longe, dito em palavras do dia a dia) ou 'empty' (sem dado para julgar).
   * Devolve { level, title, text }.
   */
  const verdictFor = rawSignals => {
    const list = (rawSignals || [])
      .map(normalizeSignal)
      .filter(signal => signal.metric && signal.level);
    if (!list.length) {
      return {
        level: 'empty',
        title: t('REPORT.VERDICT.EMPTY_TITLE'),
        text: t('REPORT.VERDICT.EMPTY_TEXT'),
      };
    }
    const bad = list.filter(signal => signal.level === 'bad');
    if (bad.length) {
      const [first] = bad;
      const more = bad.length - 1;
      const text = t(`REPORT.VERDICT.BAD.${first.metric.toUpperCase()}`, {
        goal: goalDisplay(first),
      });
      return {
        level: 'bad',
        title: t('REPORT.VERDICT.BAD_TITLE'),
        text: more
          ? `${text} ${t('REPORT.VERDICT.MORE', { n: more }, more)}`
          : text,
      };
    }
    const warn = list.find(signal => signal.level === 'warn');
    if (warn) {
      return {
        level: 'warn',
        title: t('REPORT.VERDICT.WARN_TITLE'),
        text: t('REPORT.VERDICT.WARN_TEXT', {
          label: metricLabel(warn),
          goal: goalDisplay(warn),
        }),
      };
    }
    return {
      level: 'good',
      title: t('REPORT.VERDICT.GOOD_TITLE'),
      text: t('REPORT.VERDICT.GOOD_TEXT'),
    };
  };

  return {
    verdictFor,
    signalForReportKey,
    signalByMetric,
    metricLabel,
    goalDisplay,
    pillFor,
    dotClassFor,
    phraseFor,
    aggregateSignals,
    summaryFor,
  };
}
