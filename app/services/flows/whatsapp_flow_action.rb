# frozen_string_literal: true

# Nó `send_whatsapp_flow` do motor Flow — envio de um WhatsApp Flow interactive NATIVO (Meta)
# pela inbox WhatsApp Cloud. Misturado no Flows::ActionService. Depende do host: @conversation,
# @account e as guardas whatsapp_cloud_inbox?/enforce_compliance!, mais o wrapper
# create_interactive_message (Flows::RichInteractiveAction).
#
# ── ESTADO: INTEGRADO (F3) ───────────────────────────────────────────────────────────────────
# A ação monta o payload Meta `interactive:flow` (build_whatsapp_flow_payload) e o entrega pelo
# PASSTHROUGH genérico do F3: persiste o payload em content_attributes['interactive_payload'] e o
# provider (Whatsapp::Providers::WhatsappCloudService#send_raw_interactive) faz o POST cru
# { type:'interactive', interactive:<payload> } — o MESMO caminho de cta_url/location_request, sem
# rota hardcoded por tipo. Guardas preservadas: inbox WhatsApp Cloud, config mínima válida e
# compliance (Flow interactive é mensagem de sessão → exige a janela de 24h). Por já enviar de
# verdade, `send_whatsapp_flow` ENTRA na whitelist (Flow::BASE_ACTION_NAMES) e na paleta.
#
# ── PAYLOAD META (formato real, montado por #build_whatsapp_flow_payload) ────────────────────
# https://developers.facebook.com/docs/whatsapp/flows/reference/flowjson  (Send Flow message)
#   interactive: {
#     type: 'flow',
#     header?: { type: 'text', text: <header> },
#     body:    { text: <body> },
#     footer?: { text: <footer> },
#     action:  { name: 'flow', parameters: {
#       flow_message_version: '3', flow_token: <token>, flow_id: <meta_flow_id>,
#       flow_cta: <button_label>, flow_action: 'navigate'|'data_exchange',
#       flow_action_payload?: { screen: <screen>, data?: {...} }
#     } }
#   }
#
# action_params = [{ flow_id, cta, body, header?, footer?, screen?, flow_token?, flow_action? }]
module Flows::WhatsappFlowAction
  FLOW_MESSAGE_VERSION = '3'
  FLOW_ACTIONS = %w[navigate data_exchange].freeze

  private

  def send_whatsapp_flow(action_params)
    return if conversation_a_tweet?

    config = Array(action_params).first.to_h.with_indifferent_access
    # Guardas: canal certo + config mínima (id do Flow + rótulo do botão + corpo).
    raise Flows::StepSkip.new('inbox_not_whatsapp', 'inbox is not a WhatsApp Cloud channel') unless whatsapp_cloud_inbox?
    raise Flows::StepSkip.new('whatsapp_flow_incomplete', 'flow_id, cta and body are required') unless whatsapp_flow_config_valid?(config)

    # Flow interactive é mensagem de sessão (não-template) → precisa da janela de 24h; opt-out
    # de marketing não a barra (é utility). Mesma guarda do send_message livre.
    enforce_compliance!(category: 'utility', free_form: true)

    payload = build_whatsapp_flow_payload(config)
    # F3: passthrough genérico. O payload `interactive:flow` sai pelo provider via
    # content_attributes['interactive_payload'] (WhatsappCloudService#send_raw_interactive) — o MESMO
    # wrapper das ações cta_url/location_request (Flows::RichInteractiveAction#create_interactive_message).
    create_interactive_message(payload)
  end

  def whatsapp_flow_config_valid?(config)
    config[:flow_id].present? && config[:cta].present? && config[:body].present?
  end

  # Monta o payload `interactive` do WhatsApp Flow no formato REAL da Meta. Textos aceitam
  # Liquid ({{contact.name}}) via render_liquid do host. Read-only: só lê a config e a conversa.
  def build_whatsapp_flow_payload(config)
    payload = {
      type: 'flow',
      body: { text: render_liquid(config[:body].to_s) },
      action: { name: 'flow', parameters: whatsapp_flow_parameters(config) }
    }
    payload[:header] = { type: 'text', text: render_liquid(config[:header].to_s) } if config[:header].present?
    payload[:footer] = { text: render_liquid(config[:footer].to_s) } if config[:footer].present?
    payload
  end

  def whatsapp_flow_parameters(config)
    flow_action = FLOW_ACTIONS.include?(config[:flow_action].to_s) ? config[:flow_action].to_s : 'navigate'
    parameters = {
      flow_message_version: FLOW_MESSAGE_VERSION,
      flow_token: config[:flow_token].presence || SecureRandom.hex(16),
      flow_id: config[:flow_id].to_s,
      flow_cta: render_liquid(config[:cta].to_s),
      flow_action: flow_action
    }
    parameters[:flow_action_payload] = { screen: config[:screen].to_s } if config[:screen].present?
    parameters
  end
end
