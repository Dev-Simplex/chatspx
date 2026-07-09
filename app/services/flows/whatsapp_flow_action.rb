# frozen_string_literal: true

# Nó `send_whatsapp_flow` do motor Flow — envio de um WhatsApp Flow interactive NATIVO (Meta)
# pela inbox WhatsApp Cloud. Misturado no Flows::ActionService. Depende do host: @conversation,
# @account e as guardas whatsapp_cloud_inbox?/enforce_compliance!.
#
# ── ESTADO: TODO DOCUMENTADO (integração pendente), NÃO exposto no produto ──────────────────
# O canal WhatsApp Cloud deste fork SÓ sabe enviar `interactive` do tipo botão/lista
# (Whatsapp::Providers::WhatsappCloudService#send_interactive_text_message, para content_type
# `input_select`). NÃO existe caminho de envio para `interactive.type = "flow"`. Seguindo a
# diretriz "não invente a API da Meta; segurança/corretude > completude", esta ação:
#   • FAZ a parte segura e correta: valida que a inbox é WhatsApp Cloud, aplica compliance
#     (Flow interactive é mensagem de sessão → exige a janela de 24h) e MONTA o payload Meta
#     no formato real (documentado abaixo);
#   • NÃO envia: como não há caminho de provider reutilizável e o provider está FORA da fatia
#     segura desta tarefa (é o canal ao vivo), levanta Flows::StepSkip('whatsapp_flow_provider_missing')
#     — passo `skipped` triável, nunca um envio silenciosamente errado.
# Por isso `send_whatsapp_flow` NÃO entra na whitelist (Flow::BASE_ACTION_NAMES) nem na paleta:
# um nó que sempre pula seria enganoso. Este arquivo é o ponto de integração pronto.
#
# PARA CONCLUIR (fatia separada, fora do escopo de analytics):
#   1. Adicionar Whatsapp::Providers::WhatsappCloudService#send_interactive_flow(phone, payload)
#      — um POST em `#{phone_id_path}/messages` com { type: 'interactive', interactive: payload },
#      espelhando #send_interactive_text_message.
#   2. Rotear até ele: um content_type/message novo (ex.: `input_flow`) OU um serviço dedicado
#      Whatsapp::SendFlowService, para o Flow interactive sair pelo pipeline de mensagens real
#      (herdando SendOnWhatsappService, retries, marcador flow_id anti-loop).
#   3. Trocar o StepSkip abaixo pela chamada real, e então somar 'send_whatsapp_flow' à
#      whitelist (community — o canal WhatsApp é community) + paleta (família `msg`) + widget
#      (flow_id, cta, body/header/footer, screen, flow_token) + i18n en/pt_BR.
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
    # Ponto de integração: sem caminho de envio de interactive:flow no provider, sinalizamos um
    # skip triável em vez de enviar errado. payload validado fica no rastro do StepSkip.
    raise Flows::StepSkip.new('whatsapp_flow_provider_missing',
                              "WhatsApp Flow send path not wired yet (payload ready: #{payload[:action][:parameters][:flow_id]})")
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
