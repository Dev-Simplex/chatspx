# frozen_string_literal: true

# send_interactive: envia uma mensagem interativa WhatsApp (lista/botões) a partir do Flow.
# Misturado no Flows::ActionService (mesmo padrão de Flows::SnoozeAction/HttpAction/… — mantém a
# classe host enxuta). Depende do host: @conversation, o helper conversation_a_tweet?, o
# enforce_compliance! (Flows::Compliance), author e message_content_attributes.
#
# Espelha send_message: é texto de SERVIÇO livre (utility, free_form), então exige a janela de 24h —
# fora dela o enforce_compliance! levanta um StepSkip (não manda um interactive que a Meta
# rejeitaria). O canal decide o formato pelo nº de opções (≤3 → botões, >3 → lista), em
# Whatsapp::Providers::BaseService#create_payload_based_on_items. F1 apenas ENVIA — esperar a
# resposta e ramificar é F2.
#
# Formato do param: action_params = [{ content:, items: [{ title:, value:, description? }] }].
# Ver o contrato (fonte de verdade) em plano/F1-contrato-send-interactive.md.
module Flows::InteractiveAction
  private

  # Bloco 4.02/BK-22 — os limites saíram daqui e passaram a depender do CANAL
  # (Flows::StructuredMessageLimits). No WhatsApp continuam os da Meta, enforçados na persistência
  # e, defensivamente, no canal (Whatsapp::Providers::BaseService); no chat de site valem os do
  # widget, que não tem o corte de 24 caracteres da Meta.
  def structured_limits
    @structured_limits ||= Flows::StructuredMessageLimits.for(@conversation)
  end

  def send_interactive(action_params)
    return if conversation_a_tweet?

    config = action_params[0].to_h.with_indifferent_access
    items = sanitize_interactive_items(config['items'])
    # Sem opção válida não há lista/botão a enviar — skip triável (guarda, não falha), sem Sentry.
    raise Flows::StepSkip.new('interactive_no_items', 'no valid interactive items to send') if items.blank?

    enforce_compliance!(category: 'utility', free_form: true)

    params = {
      content: config['content']&.to_s&.slice(0, structured_limits[:body]),
      private: false,
      content_type: 'input_select',
      # GOTCHA: `items` PRECISA morar dentro de content_attributes p/ o MessageBuilder populá-lo
      # via o método content_attributes (ver o fix aditivo em Messages::MessageBuilder#initialize).
      content_attributes: message_content_attributes.merge(items: items)
    }
    Messages::MessageBuilder.new(author, @conversation.reload, params).perform
  end

  # Sanea/limita as opções contra os limites da Meta ANTES de persistir: descarta item sem título,
  # trunca título/valor/descrição, cai no slug do título quando o valor vem vazio e aplica o cap de
  # 10. Devolve Hashes de CHAVES-STRING — o formato que Whatsapp::Providers::BaseService
  # (item['value']/['title']/['description']) e o ContentAttributeValidator esperam. description só
  # entra quando presente (aparece apenas em lista).
  def sanitize_interactive_items(raw_items)
    limits = structured_limits
    Array(raw_items).filter_map { |raw| sanitize_interactive_item(raw, limits) }.first(limits[:items])
  end

  def sanitize_interactive_item(raw, limits)
    item = raw.to_h.with_indifferent_access
    title = item['title'].to_s.strip
    return if title.blank?

    entry = {
      'title' => title[0, limits[:title]],
      'value' => (item['value'].to_s.strip.presence || title.parameterize.presence || title)[0, limits[:value]]
    }
    description = item['description'].to_s.strip
    entry['description'] = description[0, limits[:description]] if description.present?
    entry
  end
end
