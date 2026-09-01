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
  LIMITE_RELEASE = 200

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
      # ── O EVENTO DO WIDGET NÃO LEVA REQUISIÇÃO ────────────────────────────
      #
      # Sem estas duas linhas, TUDO o que a raspagem acima remove volta pela
      # porta dos fundos. O caminho é este, e foi medido com o SDK real:
      #
      #   1. `Sentry::Rails::CaptureExceptions` guarda o rack env inteiro no
      #      escopo corrente de cada requisição (`scope.set_rack_env(env)`);
      #   2. `Sentry.with_scope` DUPLICA o escopo corrente — o `dup` herda esse
      #      rack env;
      #   3. `Scope#apply_to_event` faz `event.rack_env = rack_env`, e com
      #      `send_default_pii = true` (`config/initializers/sentry.rb:14`) o
      #      `RequestInterface` publica `cookies`, `query_string`, o corpo do
      #      POST, os cabeçalhos e `user[:ip_address]`.
      #
      # O que isso significa aqui, concretamente: o documento do widget é
      # servido em `/widget?website_token=…&cw_conversation=<JWT>`, então o
      # `Referer` deste POST carrega o JWT DE CONVERSA do visitante, e o cookie
      # `cw_conversation` carrega o mesmo JWT de novo. Quem tem esse token lê a
      # conversa inteira daquele visitante. Mandar isso para um agregador de
      # erros externo é vazamento, não observabilidade.
      #
      # `set_rack_env({})` resolve os dois de uma vez: `Event#rack_env=` tem
      # `unless request || env.empty?`, então com um env VAZIO nenhum
      # `RequestInterface` é construído e o `user[:ip_address]` nunca é
      # calculado. `set_user({})` é a segunda tranca, para o caso de alguém
      # identificar o usuário no escopo de cima.
      #
      # Nada de diagnóstico se perde: a URL (sem query string) e a origem já
      # viajam no contexto `widget` logo abaixo, ambas raspadas.
      scope.set_rack_env({})
      scope.set_user({})
      scope.add_event_processor { |evento, _dica| aplica_release(evento) }
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

  # `release` de primeira classe, e não só uma chave dentro do contexto: é o
  # campo por onde o GlitchTip agrupa e filtra por versão. Antes deste bloco o
  # cliente LIA `window.chatwootWebChannel.release` e o servidor nunca o
  # publicava — o campo chegava `null` em toda instalação, e só o harness de
  # E2E o fabricava. Agora `widgets/show.html.erb` e o jbuilder de `configs`
  # publicam `Chatwoot.config[:version]`, e é ele que chega aqui.
  #
  # Vem do cliente, então é tratado como texto de fora: raspado e cortado. Sem
  # valor, o `release` do próprio SDK (o do servidor) continua valendo.
  def aplica_release(evento)
    valor = Widget::ErrorReport.scrub(@payload[:release].to_s).truncate(LIMITE_RELEASE)
    evento.release = valor if valor.present?
    evento
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
