# frozen_string_literal: true

# Segunda raspagem de PII e envio ao Sentry/GlitchTip — bloco 2.13.
#
# POR QUE UMA SEGUNDA RASPAGEM
#
# A primeira acontece em `widget/helpers/telemetry.js`, no navegador. Mas esse
# código roda na máquina de outra pessoa: um cliente com um build antigo em
# cache, um navegador que falhou no `replace`, ou alguém batendo no endpoint à
# mão mandam o que quiserem. Confiar só no cliente para remover dado pessoal é
# confiar em código que não controlamos — e o custo de errar aqui é vazar PII de
# visitante para dentro do nosso agregador de erros.
#
# POR QUE NÃO O DSN NO NAVEGADOR
#
# `SENTRY_DSN` já está configurado por VM. Mandar direto do navegador exigiria
# publicar um DSN no HTML de cada widget, e o POST seria cross-origin — morreria
# na `connect-src` de qualquer cliente com CSP apertada, justamente aqueles cujos
# problemas mais queremos enxergar. Aqui o POST é same-origin e o reenvio sai do
# servidor, pelo SDK Ruby que já existe.
class Widget::ErrorReport
  LIMITE_MENSAGEM = 1_000
  LIMITE_PILHA = 4_000

  # Mesmos padrões de `telemetry.js`, na MESMA ordem — credencial antes de
  # e-mail (um JWT pode conter algo que pareça e-mail) e documento antes de
  # telefone (CPF e telefone competem pelos mesmos dígitos). Duas listas para o
  # mesmo contrato é o risco conhecido; por isso há um teste que percorre os
  # mesmos casos dos dois lados.
  PADROES = [
    [/\b[Bb]earer\s+[\w\-.=]+/, '[credencial]'],
    [/\beyJ[\w-]*\.[\w-]+\.[\w-]+/, '[credencial]'],
    [/\b(token|secret|password|senha|api[_-]?key)=[^\s&;"']+/i, '\1=[credencial]'],
    [%r{\b\d{2}\.?\d{3}\.?\d{3}/?\d{4}-?\d{2}\b}, '[documento]'],
    [/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/, '[documento]'],
    [/\b\d{16}\b/, '[documento]'],
    [/\b\d{4}[\s-]\d{4}[\s-]\d{4}[\s-]\d{4}\b/, '[documento]'],
    [/[\w.+-]+@[\w-]+\.[\w.-]+/, '[email]'],
    [/\+\d[\d\s.-]{7,17}\d/, '[telefone]'],
    [/\(?\b\d{2}\)?[\s-]\d{4,5}-\d{4}\b/, '[telefone]']
  ].freeze

  def self.scrub(valor)
    case valor
    when String then PADROES.reduce(valor) { |texto, (padrao, troca)| texto.gsub(padrao, troca) }
    when Hash then valor.transform_values { |item| scrub(item) }
    when Array then valor.map { |item| scrub(item) }
    else valor
    end
  end

  def initialize(payload, web_widget)
    @payload = payload
    @web_widget = web_widget
  end

  def perform
    # `defined?` e não só `Sentry.initialized?`: a gem só é carregada quando
    # `SENTRY_DSN` está presente (`config/application.rb:24`), então em toda VM
    # sem DSN a CONSTANTE não existe e `Sentry.initialized?` levantaria
    # `NameError` — o endpoint de telemetria devolveria 500 justamente nas
    # instalações que não têm observabilidade nenhuma.
    return false unless defined?(Sentry) && Sentry.initialized?

    Sentry.with_scope do |scope|
      scope.set_tags(tags)
      scope.set_context('widget', contexto)
      Sentry.capture_message(mensagem, level: :error)
    end
    true
  end

  private

  def mensagem
    nome = Widget::ErrorReport.scrub(@payload[:name].to_s).presence || 'Error'
    texto = Widget::ErrorReport.scrub(@payload[:message].to_s).truncate(LIMITE_MENSAGEM)
    "[widget] #{nome}: #{texto}"
  end

  def tags
    {
      source: 'web_widget',
      account_id: @web_widget.inbox.account_id,
      inbox_id: @web_widget.inbox.id,
      origem: Widget::ErrorReport.scrub(@payload.dig(:context, :origem).to_s)
    }
  end

  def contexto
    {
      stack: Widget::ErrorReport.scrub(@payload[:stack].to_s).truncate(LIMITE_PILHA),
      # A URL chega sem query string do cliente; cortamos de novo porque quem
      # bate no endpoint à mão não passou por aquele corte.
      url: Widget::ErrorReport.scrub(@payload[:url].to_s.split('?').first.to_s),
      release: Widget::ErrorReport.scrub(@payload[:release].to_s)
    }
  end
end
