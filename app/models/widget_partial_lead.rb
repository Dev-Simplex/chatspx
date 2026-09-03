# frozen_string_literal: true

# == Schema Information
#
# Table name: widget_partial_leads
#
#  id               :bigint           not null, primary key
#  abandoned_at     :datetime
#  answers          :jsonb            not null
#  completed_at     :datetime
#  last_answered_at :datetime         not null
#  session_id       :string           not null
#  step_key         :string
#  step_reached     :integer          default(0), not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  contact_id       :bigint
#  inbox_id         :bigint           not null
#
# Bloco 4.18 (BE-5) — a resposta PARCIAL do pre-chat, persistida ANTES de a conversa
# existir. Nao e uma conversa e nao vira uma: e por isso que o lead incompleto nao
# dispara automacao, campanha nem webhook de conversa — nao ha o que disparar.
#
# Ciclo de vida:
#   1. o visitante responde um campo    -> a linha nasce/atualiza (Widget::PartialLeads::RecordService)
#   2. ele conclui o pre-chat           -> `completed_at` (a conversa nasce pelo caminho de sempre)
#   3. ele some                         -> o varredor confirma `abandoned_at` e, havendo canal de
#                                          contato, MATERIALIZA o Contact marcado como incompleto
#   4. a retencao vence                 -> a linha e apagada (dado pessoal de quem nao consentiu)
class WidgetPartialLead < ApplicationRecord
  # Chaves de resposta que valem como CANAL DE CONTATO. Sao os mesmos nomes que o
  # pre-chat classico usa (`emailAddress`, `phoneNumber`) e os que um fluxo de captura
  # tende a usar (`email`, `phone`, `whatsapp`) — a lista e aberta de proposito porque o
  # nome do campo e escrito pelo administrador.
  EMAIL_KEYS = %w[emailAddress email e_mail].freeze
  PHONE_KEYS = %w[phoneNumber phone whatsapp telefone celular].freeze
  NAME_KEYS = %w[fullName name nome].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :contact, optional: true

  validates :session_id, presence: true
  validates :session_id, uniqueness: { scope: :inbox_id }

  scope :pending, -> { where(completed_at: nil) }
  scope :abandoned, -> { pending.where.not(abandoned_at: nil) }
  # Parou de responder ha mais tempo que a janela, e ainda nao concluiu.
  scope :stale, ->(cutoff) { pending.where(last_answered_at: ...cutoff) }

  # Marca como concluida a resposta parcial desta sessao. Idempotente e silencioso: nao
  # havendo registro (captura desligada, ou visitante que nunca respondeu campo nenhum)
  # simplesmente nao ha o que marcar.
  def self.complete_for(inbox_id:, session_id:)
    return if inbox_id.blank? || session_id.blank?

    pending.where(inbox_id: inbox_id, session_id: session_id).update_all(completed_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def completed?
    completed_at.present?
  end

  def email
    first_answer(EMAIL_KEYS)
  end

  def phone_number
    first_answer(PHONE_KEYS)
  end

  def name
    first_answer(NAME_KEYS)
  end

  # "Ao menos um contato (e-mail ou WhatsApp)" — a mesma regra que o widget aplica no
  # formulario de captura (bloco 4.03). Sem nenhum canal nao ha lead a materializar:
  # criar um Contact sem forma de responder seria cadastro-lixo no painel do cliente.
  def contactable?
    email.present? || phone_number.present?
  end

  private

  # Casamento tolerante ao nome: o administrador escreve o `name` do campo, entao
  # comparamos sem caixa e sem separador (`phone_number` casa `phoneNumber`).
  def first_answer(keys)
    normalized = keys.map { |key| key.downcase.delete('_') }
    answers.to_h.each do |key, value|
      next if value.to_s.strip.blank?
      return value.to_s.strip if normalized.include?(key.to_s.downcase.delete('_'))
    end
    nil
  end
end
