# O proposito deste helper e gerar markup SVG/HTML; os valores interpolados sao
# numericos calculados internamente — dai o html_safe controlado.
# rubocop:disable Rails/OutputSafety
# Graficos como SVG calculado em Ruby — o Chromium do ferrum nao roda Chart.js
# de forma confiavel no fluxo server-side. Zero JS.
module Reports::PdfChartHelper
  BAND_COLORS = {
    'detractor' => '#e54666',
    'passive' => '#ffc53d',
    'promoter' => '#2dc46f'
  }.freeze

  # Zonas padrao do NPS (-100..+100), espelhando o laudo Tozi.
  NPS_ZONES = [
    { label: 'Crítico', from: -100, to: 0, color: '#e54666' },
    { label: 'Aperfeiçoar', from: 0, to: 50, color: '#ffc53d' },
    { label: 'Qualidade', from: 50, to: 75, color: '#95de64' },
    { label: 'Excelência', from: 75, to: 100, color: '#2dc46f' }
  ].freeze

  # Paletas sequenciais (5 passos) para o heatmap — quantis crescentes.
  HEATMAP_PALETTES = {
    traffic: %w[#eef3f8 #c5d9ec #8fb8dd #4f8fc6 #1f5e9e],
    resolutions: %w[#eafaf0 #c2efd4 #87dca8 #46c47c #1ea65b]
  }.freeze

  # Barra horizontal proporcional (0..1). Usada na tabela por atendente.
  def pdf_progress_bar(ratio, color: '#2dc46f', width: 120, height: 8)
    ratio = ratio.to_f.clamp(0.0, 1.0)
    filled = (width * ratio).round
    <<~SVG.html_safe
      <svg width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}" style="display:block;">
        <rect x="0" y="0" width="#{width}" height="#{height}" rx="#{height / 2}" fill="#eef1f3"/>
        <rect x="0" y="0" width="#{filled}" height="#{height}" rx="#{height / 2}" fill="#{color}"/>
      </svg>
    SVG
  end

  # Distribuicao de notas 0-10 como barras horizontais com rotulo e contagem,
  # cor por faixa (detrator/passivo/promotor) — espelha a pag. 2 do laudo.
  def pdf_nps_distribution(distribution, bar_width: 360)
    max = distribution.pluck(:count).max.to_f
    rows = distribution.map { |row| distribution_row(row, max, bar_width) }.join
    %(<div class="dist">#{rows}</div>).html_safe
  end

  # Gauge -100..+100 com faixa gradiente, marcador na posicao do score e
  # rotulos de zona (Critico/Aperfeicoar/Qualidade/Excelencia). Espelha o
  # medidor da pag. 1 do laudo Tozi.
  def pdf_gauge(value:, min: -100, max: 100, zones: NPS_ZONES, width: 540)
    height = 18
    value = value.to_f.clamp(min, max)
    ratio = (max - min).zero? ? 0.5 : ((value - min).to_f / (max - min)).clamp(0.0, 1.0)
    marker_x = (width * ratio).round
    label = value.round
    bubble = gauge_bubble(marker_x, label, width)
    <<~SVG.html_safe
      <svg class="chart-gauge" width="#{width}" height="#{height + 56}" viewBox="0 0 #{width} #{height + 56}">
        <defs>#{gauge_gradient(zones)}</defs>
        #{bubble[:value_text]}
        <rect x="0" y="26" width="#{width}" height="#{height}" rx="#{height / 2}" fill="url(#gaugeGrad)"/>
        #{gauge_zone_ticks(zones, min, max, width, height)}
        <polygon points="#{marker_x - 6},20 #{marker_x + 6},20 #{marker_x},26" fill="#111b21"/>
        <rect x="#{marker_x - 2}" y="24" width="4" height="#{height + 2}" rx="2" fill="#111b21"/>
        #{gauge_zone_labels(zones, min, max, width, height)}
      </svg>
    SVG
  end

  # Barras verticais para serie temporal: series => [{label:, value:}].
  # Inclui eixo Y (linhas-guia + valores) e rótulo em cada barra — auto-explicativo.
  def pdf_bar_chart(series, color: '#2dc46f', width: 540, height: 150, value_format: nil, goal: nil, goal_label: nil)
    return empty_chart('Sem dados no período') if series.blank?

    pad_l = 40
    plot_h = height - 34
    max = [series.map { |point| point[:value].to_f }.max, 1.0].max
    step = (width - pad_l).to_f / series.size
    ctx = { x0: pad_l, step: step, bar_w: [step * 0.62, 26].min, plot_h: plot_h, max: max, color: color,
            value_format: value_format, label_every: [(series.size / 12.0).ceil, 1].max, last: series.size - 1 }
    bars = series.each_with_index.map { |point, i| bar_chart_column(point, i, ctx) }.join
    y_for = ->(value) { (plot_h - ((value / max) * (plot_h - 14))).round }
    goal_y = goal ? y_for.call(goal.to_f) : nil
    <<~SVG.html_safe
      <svg class="chart-bars" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
        #{chart_y_axis(y_for, [max, max / 2.0], pad_l, width, value_format)}
        <line x1="#{pad_l}" y1="#{plot_h}" x2="#{width}" y2="#{plot_h}" stroke="#e9edef" stroke-width="1"/>
        #{bars}
        #{goal_line(goal_y, goal, goal_label, pad_l, width, value_format)}
      </svg>
    SVG
  end

  # Linha de tendencia (area): series => [{label:, value:}]. Eixo Y + rótulos no pico/vale/pontas.
  def pdf_line_chart(series, color: '#2dc46f', width: 540, height: 130, value_format: nil, goal: nil, goal_label: nil)
    return empty_chart('Sem dados no período') if series.blank?

    pad_l = 44
    plot_h = height - 30
    values = series.map { |point| point[:value].to_f }
    scale = line_chart_scale(values + Array(goal && goal.to_f))
    points = values.each_index.map { |i| [line_x(i, values.size, pad_l, width - 6), line_y(values[i], scale, plot_h)] }
    line = points.map { |x, y| "#{x},#{y}" }.join(' ')
    area = "#{pad_l},#{plot_h} #{line} #{points.last[0]},#{plot_h}"
    y_for = ->(value) { line_y(value, scale, plot_h) }
    highlight = [values.index(values.max), values.index(values.min)].compact
    dots = line_chart_dots(points, series, color: color, value_format: value_format, highlight: highlight)
    goal_y = goal ? y_for.call(goal.to_f) : nil
    <<~SVG.html_safe
      <svg class="chart-line" width="#{width}" height="#{height}" viewBox="0 0 #{width} #{height}">
        #{chart_y_axis(y_for, [scale[:min] + scale[:span], scale[:min] + (scale[:span] / 2), scale[:min]], pad_l, width, value_format)}
        <line x1="#{pad_l}" y1="#{plot_h}" x2="#{width}" y2="#{plot_h}" stroke="#e9edef" stroke-width="1"/>
        <polygon points="#{area}" fill="#{color}" fill-opacity="0.10"/>
        <polyline points="#{line}" fill="none" stroke="#{color}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>
        #{dots}
        #{goal_line(goal_y, goal, goal_label, pad_l, width, value_format)}
      </svg>
    SVG
  end

  # Eixo Y: linhas-guia horizontais + rótulo de valor à esquerda (compacto p/ tempos).
  def chart_y_axis(y_for, ticks, x_left, x_right, value_format)
    ticks.map do |value|
      pos_y = y_for.call(value)
      label = value_format == :seconds ? compact_duration(value) : value.round.to_s
      %(<line x1="#{x_left}" y1="#{pos_y}" x2="#{x_right}" y2="#{pos_y}" stroke="#f0f2f5" stroke-width="1"/>) +
        chart_text(x_left - 5, pos_y + 3, label, color: '#aab4ba', size: 7, anchor: 'end')
    end.join
  end

  # Linha de meta tracejada + rótulo (reusada por barras e linha).
  def goal_line(goal_y, goal, goal_label, x_left, width, value_format)
    return '' if goal_y.nil?

    label = goal_label || "meta #{format_chart_value(goal, value_format)}"
    %(<line x1="#{x_left}" y1="#{goal_y}" x2="#{width}" y2="#{goal_y}" stroke="#8696a0" stroke-width="1" stroke-dasharray="4 3"/>) +
      chart_text(width, goal_y - 4, label, color: '#667781', size: 8, weight: 600, anchor: 'end')
  end

  # Semáforo (verde/amarelo/vermelho) de um valor numa métrica → { color:, emoji:, word:, level: }.
  def pdf_status(value, metric:)
    Reports::PdfBenchmarks.status(value, metric)
  end

  # Delta vs período anterior, direção-aware. cmp => { current:, previous:, delta_pct:, better:, lower_better: }.
  def pdf_delta(cmp)
    return ''.html_safe if cmp.blank? || cmp[:delta_pct].nil? || cmp[:delta_pct].zero?

    arrow = cmp[:current].to_f >= cmp[:previous].to_f ? '▲' : '▼'
    %(<span class="delta delta--#{delta_css(cmp)}">#{arrow} #{cmp[:delta_pct]}% #{delta_word(cmp)}</span>).html_safe
  end

  def delta_css(cmp)
    return 'flat' if cmp[:better].nil?

    cmp[:better] ? 'good' : 'bad'
  end

  # Barra empilhada (composicao). segments => [{label:, value:, color:}].
  def pdf_composition_bar(segments, width: 540, height: 26)
    segments = Array(segments).reject { |seg| seg[:value].to_f.negative? }
    total = segments.sum { |seg| seg[:value].to_f }
    bar = composition_segments(segments, total, width, height)
    legend = composition_legend(segments, total)
    <<~HTML.html_safe
      <div class="composition">
        <svg width="100%" height="#{height}" viewBox="0 0 #{width} #{height}" preserveAspectRatio="none" style="display:block;max-width:100%;">
          <rect x="0" y="0" width="#{width}" height="#{height}" rx="6" fill="#eef1f3"/>
          #{bar}
        </svg>
        <div class="composition-legend">#{legend}</div>
      </div>
    HTML
  end

  # Heatmap 7 dias x 24 horas. grid => { day_labels:, hour_labels:, values: [[..24]*7] }.
  # legend: true (default) desenha a escala de tonalidade à DIREITA (menos↕mais) sem
  # encolher as células — só aumenta a largura total do SVG (princ. 9).
  def pdf_heatmap(grid, palette: :traffic, width: 540, legend: true)
    days = grid[:day_labels]
    values = grid[:values]
    return empty_chart('Sem tráfego no período') if values.blank? || values.flatten.compact.sum.zero?

    ctx = heatmap_ctx(values, palette, width)
    grid_h = ctx[:cell_h] * days.size
    svg_h = grid_h + 18
    legend_w = legend ? 86 : 0
    <<~SVG.html_safe
      <svg class="chart-heatmap" width="#{width + legend_w}" height="#{svg_h}" viewBox="0 0 #{width + legend_w} #{svg_h}">
        #{heatmap_rows(days, values, ctx)}
        #{heatmap_hour_axis(ctx, days.size)}
        #{legend ? heatmap_scale_legend(width + 14, grid_h, ctx[:colors]) : ''}
      </svg>
    SVG
  end

  private

  def distribution_row(row, max, bar_width)
    color = row[:color] || BAND_COLORS.fetch(row[:band], '#2dc46f')
    filled = max.zero? ? 0 : (bar_width * (row[:count] / max)).round
    filled = 2 if filled.zero? && row[:count].positive?
    <<~HTML
      <div class="dist-row">
        <span class="dist-score">#{row[:score]}</span>
        <span class="dist-track" style="width:#{bar_width}px;">
          <span class="dist-fill" style="width:#{filled}px;background:#{color};"></span>
        </span>
        <span class="dist-count">#{row[:count]}</span>
      </div>
    HTML
  end

  # ---------------- Gauge ----------------
  def gauge_gradient(zones)
    stops = zones.each_with_index.map do |zone, i|
      offset = zones.size == 1 ? 50 : (100.0 * i / (zones.size - 1)).round
      %(<stop offset="#{offset}%" stop-color="#{zone[:color]}"/>)
    end.join
    %(<linearGradient id="gaugeGrad" x1="0" y1="0" x2="1" y2="0">#{stops}</linearGradient>)
  end

  def gauge_zone_ticks(zones, min, max, width, height)
    zones.drop(1).map do |zone|
      x = (width * ((zone[:from] - min).to_f / (max - min))).round
      %(<line x1="#{x}" y1="26" x2="#{x}" y2="#{26 + height}" stroke="#ffffff" stroke-width="1" stroke-opacity="0.6"/>)
    end.join
  end

  def gauge_zone_labels(zones, min, max, width, height)
    y = 26 + height + 16
    zones.map do |zone|
      mid = (zone[:from] + zone[:to]) / 2.0
      x = (width * ((mid - min).to_f / (max - min))).round
      <<~SVG
        <text x="#{x}" y="#{y}" text-anchor="middle" font-size="9" font-weight="700" fill="#{zone[:color]}">#{zone[:label]}</text>
        <text x="#{x}" y="#{y + 12}" text-anchor="middle" font-size="8" fill="#8696a0">#{zone[:from]} a #{zone[:to]}</text>
      SVG
    end.join
  end

  def gauge_bubble(marker_x, label, width)
    x = marker_x.clamp(16, width - 16)
    { value_text: chart_text(x, 14, label, color: '#111b21', size: 13, weight: 700) }
  end

  # ---------------- Bar chart ----------------
  # ctx => { step:, bar_w:, plot_h:, max:, color:, value_format:, label_every:, last: }
  def bar_chart_column(point, index, ctx)
    value = point[:value].to_f
    center_x = ctx[:x0].to_f + (ctx[:step] * index) + (ctx[:step] / 2)
    bar_h = [((value / ctx[:max]) * (ctx[:plot_h] - 14)).round, value.positive? ? 2 : 0].max
    top_y = ctx[:plot_h] - bar_h
    bar_rect(center_x, top_y, bar_h, ctx) + bar_chart_labels(point, index, [center_x, top_y], ctx)
  end

  def bar_rect(center_x, top_y, bar_h, ctx)
    x = (center_x - (ctx[:bar_w] / 2)).round
    %(<rect x="#{x}" y="#{top_y}" width="#{ctx[:bar_w].round}" height="#{bar_h}" rx="3" fill="#{ctx[:color]}"/>)
  end

  def bar_chart_labels(point, index, center, ctx)
    center_x, top_y = center
    value = point[:value].to_f
    value_label = value.positive? ? chart_text(center_x, top_y - 4, format_chart_value(value, ctx[:value_format]), color: '#667781', weight: 700) : ''
    show_axis = (index % ctx[:label_every]).zero? || index == ctx[:last]
    axis_label = show_axis ? chart_text(center_x, ctx[:plot_h] + 14, point[:label]) : ''
    value_label + axis_label
  end

  # ---------------- Line chart ----------------
  def line_chart_scale(values)
    min = [values.min, 0].min
    { min: min, span: [(values.max - min).abs, 1.0].max }
  end

  def line_x(index, count, x_start, x_end)
    return ((x_start + x_end) / 2).round if count == 1

    (x_start + ((x_end - x_start).to_f * index / (count - 1))).round
  end

  def line_y(value, scale, plot_h)
    (plot_h - (((value - scale[:min]) / scale[:span]) * (plot_h - 16)) - 8).round
  end

  # highlight: índices a rotular além das pontas (pico/vale) — deixa a linha legível.
  def line_chart_dots(points, series, color:, value_format:, highlight: [])
    last = points.size - 1
    points.each_with_index.map do |(point_x, point_y), i|
      show = i.zero? || i == last || highlight.include?(i) || points.size <= 8
      text = format_chart_value(series[i][:value], value_format)
      label = show && text.present? ? chart_text(point_x, dot_label_y(point_y), text, color: '#667781', weight: 700, anchor: dot_anchor(i, last)) : ''
      %(<circle cx="#{point_x}" cy="#{point_y}" r="3" fill="#ffffff" stroke="#{color}" stroke-width="2"/>#{label})
    end.join
  end

  # Rótulo abaixo do ponto quando ele está no topo (pico) — acima estouraria a borda.
  def dot_label_y(point_y)
    point_y < 16 ? point_y + 13 : point_y - 7
  end

  # Ancora os rotulos das pontas para dentro (start/end) — labels longos (ex.: "18 horas 45 min")
  # centralizados na ponta transbordariam a borda do grafico.
  def dot_anchor(index, last)
    return 'start' if index.zero?
    return 'end' if index == last

    'middle'
  end

  # ---------------- Composition ----------------
  def composition_segments(segments, total, width, height)
    return %(<rect x="0" y="0" width="#{width}" height="#{height}" rx="6" fill="#e9edef"/>) if total.zero?

    x = 0.0
    segments.map do |seg|
      w = (width * (seg[:value].to_f / total))
      rect = %(<rect x="#{x.round}" y="0" width="#{w.ceil}" height="#{height}" fill="#{seg[:color]}"/>)
      x += w
      rect
    end.join
  end

  def composition_legend(segments, total)
    segments.map do |seg|
      pct = total.zero? ? 0 : ((seg[:value].to_f / total) * 100).round
      <<~HTML
        <span class="composition-item">
          <span class="swatch" style="background:#{seg[:color]};"></span>
          <span class="composition-label">#{seg[:label]}</span>
          <span class="composition-value">#{seg[:value].to_i} · #{pct}%</span>
        </span>
      HTML
    end.join
  end

  # ---------------- Heatmap ----------------
  def heatmap_ctx(values, palette, width)
    label_col = 34
    { label_col: label_col, cell: (width - label_col) / 24.0, cell_h: 17,
      colors: HEATMAP_PALETTES.fetch(palette, HEATMAP_PALETTES[:traffic]),
      max: values.flatten.compact.max.to_f }
  end

  # Escala vertical de tonalidade (mais escuro = mais) à direita do grid (princ. 9).
  def heatmap_scale_legend(legend_x, grid_h, colors)
    bar_w = 12
    bar_h = [grid_h - 2, 56].max
    seg_h = bar_h / colors.size.to_f
    rects = colors.reverse.each_with_index.map do |color, i|
      %(<rect x="#{legend_x}" y="#{(i * seg_h).round}" width="#{bar_w}" height="#{seg_h.ceil}" fill="#{color}"/>)
    end.join
    label_x = legend_x + bar_w + 5
    rects +
      chart_text(label_x, 8, 'mais', color: '#667781', size: 7.5, anchor: 'start') +
      chart_text(label_x, bar_h.round, 'menos', color: '#667781', size: 7.5, anchor: 'start')
  end

  # ctx => { label_col:, cell:, cell_h:, colors:, max: }
  def heatmap_rows(days, values, ctx)
    days.each_with_index.map do |day, row_i|
      cells = (0..23).map { |hour| heatmap_cell(values.dig(row_i, hour).to_i, row_i, hour, ctx) }.join
      label = chart_text(0, (row_i * ctx[:cell_h]) + ctx[:cell_h] - 6, day, color: '#667781', weight: 600, anchor: 'start')
      label + cells
    end.join
  end

  def heatmap_cell(value, row_i, hour, ctx)
    fill = heatmap_color(value, ctx[:max], ctx[:colors])
    x = (ctx[:label_col] + (ctx[:cell] * hour)).round
    %(<rect x="#{x}" y="#{row_i * ctx[:cell_h]}" width="#{ctx[:cell].ceil}" height="#{ctx[:cell_h] - 2}" rx="2" fill="#{fill}"/>)
  end

  def heatmap_hour_axis(ctx, day_count)
    y = (ctx[:cell_h] * day_count) + 10
    [0, 4, 8, 12, 16, 20, 23].map do |hour|
      x = (ctx[:label_col] + (ctx[:cell] * hour) + (ctx[:cell] / 2)).round
      chart_text(x, y, format('%02dh', hour), size: 7.5)
    end.join
  end

  def heatmap_color(value, max, colors)
    return colors.first if value.zero? || max.zero?

    idx = ((value.to_f / max) * (colors.size - 1)).ceil.clamp(1, colors.size - 1)
    colors[idx]
  end

  # ---------------- Shared ----------------
  # Texto SVG centralizado (anchor 'middle' por padrao). Centraliza estilo p/ encurtar as linhas.
  def chart_text(pos_x, pos_y, text, opts = {})
    anchor = opts[:anchor] || 'middle'
    size = opts[:size] || 8
    color = opts[:color] || '#8696a0'
    weight_attr = opts[:weight] ? %( font-weight="#{opts[:weight]}") : ''
    %(<text x="#{pos_x}" y="#{pos_y}" text-anchor="#{anchor}" font-size="#{size}"#{weight_attr} fill="#{color}">#{text}</text>)
  end

  # Texto do delta, direção-aware: tempos => "mais rápido/lento"; contagens => "a mais/menos".
  def delta_word(cmp)
    faster_slower = cmp[:lower_better]
    if cmp[:better]
      faster_slower ? 'mais rápido 🎉' : 'a mais 🎉'
    else
      faster_slower ? 'mais lento' : 'a menos'
    end
  end

  # Rótulo de duração compacto p/ eixo Y (ex.: 8m, 17h) — não estoura a margem esquerda.
  def compact_duration(seconds)
    secs = seconds.to_f
    return "#{secs.round}s" if secs < 60
    return "#{(secs / 60).round}min" if secs < 3600

    "#{(secs / 3600.0).round(1)}h"
  end

  def format_chart_value(value, value_format)
    case value_format
    when :seconds then Reports::TimeFormatPresenter.new(value).format
    when :pct then "#{value.round}%"
    else value.to_i.to_s
    end
  end

  def empty_chart(message)
    %(<div class="chart-empty">#{message}</div>).html_safe
  end
end
# rubocop:enable Rails/OutputSafety
