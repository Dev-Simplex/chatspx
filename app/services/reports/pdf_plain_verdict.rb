# Frase de veredito do topo do PDF, a mesma das telas de Relatorios (ReportVerdict / verdictFor):
# um rosto, um titulo curto e uma frase que responde "esta bom ou ruim?" em palavras do dia a dia.
# Recebe o que o PDF ja julgou contra a meta (Reports::PdfBenchmarks): [{ metric:, level:, goal_human: }].
module Reports::PdfPlainVerdict
  LABELS = {
    first_response: 'Espera pela primeira resposta', resolution: 'Tempo para resolver', reply: 'Espera entre mensagens',
    resolution_rate: 'Conversas resolvidas', csat: 'Clientes satisfeitos', nps: 'Indicariam a empresa',
    sla_hit_rate: 'Respondidos no prazo', bot_resolution_rate: 'Resolvidas pelo robô',
    bot_handoff_rate: 'Passadas do robô para uma pessoa'
  }.freeze

  BAD = {
    first_response: 'Os clientes estão esperando demais pela primeira resposta. A meta é até %<goal>s.',
    resolution: 'As conversas estão demorando para serem resolvidas. A meta é até %<goal>s.',
    reply: 'Entre uma mensagem e outra, o cliente está esperando demais. A meta é até %<goal>s.',
    resolution_rate: 'Poucas conversas estão sendo resolvidas. A meta é %<goal>s.',
    csat: 'Menos clientes que o esperado ficaram satisfeitos. A meta é %<goal>s.',
    nps: 'Poucos clientes indicariam a empresa. A meta é nota %<goal>s.',
    sla_hit_rate: 'Muitas conversas passaram do prazo combinado. A meta é %<goal>s no prazo.',
    bot_resolution_rate: 'O robô está resolvendo pouca coisa sozinho. A meta é %<goal>s.',
    bot_handoff_rate: 'O robô está passando conversas demais para uma pessoa. A meta é no máximo %<goal>s.'
  }.freeze

  module_function

  # Sem nada julgado (periodo vazio) nao ha frase: o PDF nao julga o que nao aconteceu.
  def from_entries(entries)
    entries = entries.compact
    return nil if entries.empty?

    bad = entries.select { |entry| entry[:level] == :bad }
    return bad_verdict(bad) if bad.any?

    warn = entries.find { |entry| entry[:level] == :warn }
    return warn_verdict(warn) if warn

    { level: :good, emoji: '😊', title: 'Está indo bem.', text: 'Todos os números estão dentro da meta. Continue assim.' }
  end

  # Um cartao de veredito do resolver (metric_verdict) vira uma entrada.
  def entry(metric, card)
    card && { metric: metric, level: card[:level], goal_human: card[:goal_human] }
  end

  # Visao geral e "agora": julga quem esta esperando resposta neste momento.
  def live(waiting)
    if waiting.zero?
      return { level: :good, emoji: '😊', title: 'Ninguém esperando agora.',
               text: 'Todos os clientes que escreveram já tiveram resposta.' }
    end

    noun = waiting == 1 ? '1 cliente está esperando' : "#{waiting} clientes estão esperando"
    { level: waiting > 10 ? :bad : :warn, emoji: waiting > 10 ? '😟' : '😐', title: 'Tem cliente esperando.',
      text: "#{noun} resposta agora." }
  end

  def bad_verdict(bad)
    first = bad.first
    text = format(BAD.fetch(first[:metric]), goal: first[:goal_human])
    more = bad.size - 1
    text += more == 1 ? ' E mais 1 ponto precisa de cuidado.' : " E mais #{more} pontos precisam de cuidado." if more.positive?
    { level: :bad, emoji: '😟', title: 'Atenção.', text: text }
  end

  def warn_verdict(warn)
    { level: :warn, emoji: '😐', title: 'Quase lá.',
      text: "Um ponto ficou um pouco fora da meta: #{LABELS.fetch(warn[:metric])} (a meta é #{warn[:goal_human]}). O resto está bem." }
  end
end
