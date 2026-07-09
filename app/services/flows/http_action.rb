# frozen_string_literal: true

# Nó `http_request` do motor Flow: faz UMA chamada HTTP(S) externa (GET/POST/…), com URL,
# headers e body suportando Liquid ({{contact.name}}), e OPCIONALMENTE grava o corpo da resposta
# num atributo da conversa/contato (mesmo mecanismo do set_attribute). Misturado no
# Flows::ActionService (padrão de Flows::Compliance/AiActions/SnoozeAction). Depende do host:
# @conversation, @account e o helper render_liquid.
#
# A mecânica SSRF-safe (validação de URL/IP, fixação do IP, sem redirect, timeout+cap) fica no
# PORO Flows::SafeHttpClient — ver lá o MODELO DE AMEAÇA completo. Aqui só resolvemos Liquid,
# saneamos headers e gravamos a resposta. Erros de rede/URL/SSRF chegam como Flows::StepSkip
# (passo `skipped` triável, sem Sentry).
#
# Anti-loop: http_request não cria mensagem nem re-entra em flow/macro → não toca
# content_attributes.flow_id nem Current.flow_depth.
module Flows::HttpAction
  # Headers que o usuário NÃO pode definir (controlados pelo Net::HTTP/pela requisição).
  BLOCKED_REQUEST_HEADERS = %w[host content-length connection transfer-encoding].freeze

  private

  # action_params = [{ method, url, headers?, body?, target?, store?, key? }]
  #   • method: get|post|put|patch|delete (default get)
  #   • url:    http(s), suporta Liquid — validada por SSRF DEPOIS do render
  #   • headers: [{ key, value }] (value suporta Liquid) OU hash { key => value }
  #   • body:   string (suporta Liquid); ignorada em GET
  #   • key/target/store: onde gravar o corpo da resposta (opcional; sem key → não grava)
  def http_request(action_params)
    config = Array(action_params).first.to_h.with_indifferent_access
    url = render_liquid(config[:url].to_s).to_s.strip
    return if url.blank?

    method = config[:method].to_s.downcase
    result = Flows::SafeHttpClient.new(
      method: method, url: url,
      headers: render_http_headers(config[:headers]),
      body: http_body(method, config[:body])
    ).perform
    store_http_response(config, result.body)
  end

  # Aceita headers como array de { key, value } (formato do widget) OU hash { key => value }.
  # Cada value passa por Liquid. Descarta chaves vazias e headers hop-by-hop/sensíveis.
  def render_http_headers(headers)
    header_pairs(headers).each_with_object({}) do |(key, value), acc|
      name = key.to_s.strip
      next if name.blank? || BLOCKED_REQUEST_HEADERS.include?(name.downcase)

      acc[name] = render_liquid(value.to_s)
    end
  end

  def header_pairs(headers)
    case headers
    when Array then headers.filter_map { |h| pair_from_row(h) }
    when Hash then headers.to_a
    else []
    end
  end

  def pair_from_row(row)
    return unless row.respond_to?(:with_indifferent_access)

    row = row.with_indifferent_access
    [row[:key], row[:value]]
  end

  def http_body(method, body)
    return nil if method == 'get'

    render_liquid(body.to_s).presence
  end

  # Grava o corpo da resposta num atributo (opcional). Mesmo mecanismo do set_attribute:
  # custom_attributes (default) ou additional_attributes, na conversa (default) ou contato.
  # NOTA: o valor respeita a validação de tamanho do model (custom_attributes < 1500 chars) —
  # uma resposta grande demais vira passo `failed` observável em vez de gravação silenciosa.
  def store_http_response(config, response_body)
    key = config[:key].to_s
    return if key.blank?

    record = config[:target].to_s == 'contact' ? @conversation.contact : @conversation.reload
    return if record.blank?

    bag = config[:store].to_s == 'additional' ? :additional_attributes : :custom_attributes
    current = record.public_send(bag) || {}
    record.update!(bag => current.merge(key => response_body))
  end
end
