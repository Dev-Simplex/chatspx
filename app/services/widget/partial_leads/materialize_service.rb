# frozen_string_literal: true

# Bloco 4.18 — o abandono CONFIRMADO vira lead no painel.
#
# O que este servico NAO faz, e e a metade mais importante do aceite: **nao cria
# conversa**. Sem conversa nao ha `conversation_created`, entao o lead incompleto nao
# dispara automacao, nao entra em campanha e nao emite webhook de conversa. Nao e uma
# regra que precisamos escrever — e a consequencia de nao criar a conversa, e o spec
# prova pelos tres lados.
#
# O que ele faz: materializa (ou reencontra) o CONTATO e o marca como incompleto, com a
# ETAPA em que a pessoa parou. Sem canal de contato (e-mail ou WhatsApp) nao materializa
# nada — um cadastro sem forma de responder e lixo no painel do cliente.
class Widget::PartialLeads::MaterializeService
  # Marcadores em `custom_attributes` do contato. Sao os nomes que o painel le para
  # mostrar "lead incompleto" e a etapa; ficam em ingles porque sao CHAVE, nao texto.
  INCOMPLETE_KEY = 'widget_lead_incomplete'
  STEP_KEY = 'widget_lead_step'
  STEP_NAME_KEY = 'widget_lead_step_name'

  def initialize(lead)
    @lead = lead
  end

  # Devolve o Contact materializado, ou nil quando nao havia o que materializar.
  def perform
    return unless materializable?

    contact = identify_contact
    return if contact.blank?

    mark_incomplete(contact)
    apply_label(contact)
    @lead.update!(contact: contact, abandoned_at: @lead.abandoned_at || Time.current)
    contact
  rescue StandardError => e
    Rails.logger.error("Widget::PartialLeads::MaterializeService lead=#{@lead&.id}: #{e.message}")
    nil
  end

  private

  def materializable?
    return false if @lead.blank?
    return false if @lead.completed? || @lead.contact_id.present?

    @lead.contactable?
  end

  # Reusa o ContactInbox da propria sessao quando ele existe (o widget cria um no boot),
  # em vez de inventar um contato solto: assim o lead incompleto e o MESMO cadastro que a
  # pessoa usaria se voltasse e concluisse — que e o que impede o painel de ter duas
  # fichas da mesma pessoa.
  def identify_contact
    contact = session_contact
    return if contact.blank?

    ContactIdentifyAction.new(
      contact: contact,
      params: { email: @lead.email, phone_number: @lead.phone_number, name: @lead.name }.compact_blank,
      retain_original_contact_name: true
    ).perform
  end

  def session_contact
    ContactInbox.find_by(inbox_id: @lead.inbox_id, source_id: @lead.session_id)&.contact
  end

  def mark_incomplete(contact)
    attributes = contact.custom_attributes.to_h.merge(
      INCOMPLETE_KEY => true,
      STEP_KEY => @lead.step_reached,
      STEP_NAME_KEY => @lead.step_key
    ).compact
    contact.update!(custom_attributes: attributes)
  end

  # Etiqueta configuravel (mockup 22 §3: "Etiquetar como `lead-incompleto`"). Vazio
  # desliga a etiqueta sem desligar a captura. `add_labels` e aditivo — nao apaga as
  # etiquetas que o agente ja tenha posto.
  def apply_label(contact)
    label = Widget::PartialLeads::Settings.new(contact.account).label
    return if label.blank?

    contact.add_labels([label])
  end
end
