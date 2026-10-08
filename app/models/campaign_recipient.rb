# == Schema Information
#
# Table name: campaign_recipients
#
#  id              :bigint           not null, primary key
#  canonical_phone :string
#  delivered_at    :datetime
#  external_error  :string
#  failed_at       :datetime
#  name            :string
#  phone_number    :string           not null
#  pricing         :jsonb            not null
#  read_at         :datetime
#  replied_at      :datetime
#  sent_at         :datetime
#  status          :integer          default("pending"), not null
#  template_params :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  campaign_id     :bigint           not null
#  contact_id      :bigint
#  conversation_id :bigint
#  message_id      :bigint
#
# Indexes
#
#  index_campaign_recipients_on_account_id_and_canonical_phone  (account_id,canonical_phone)
#  index_campaign_recipients_on_account_id_and_phone_number     (account_id,phone_number)
#  index_campaign_recipients_on_campaign_id_and_status          (campaign_id,status)
#  index_campaign_recipients_on_contact_id_and_sent_at          (contact_id,sent_at)
#  index_campaign_recipients_on_conversation_id                 (conversation_id)
#  index_campaign_recipients_on_message_id                      (message_id)
#
class CampaignRecipient < ApplicationRecord
  belongs_to :campaign
  belongs_to :account
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true

  enum status: {
    pending: 0, processing: 1, sent: 2, delivered: 3,
    read: 4, failed: 5, replied: 6, cancelled: 7, skipped: 8
  }

  # Quem NAO recebeu: falhou no envio (Meta ou erro interno) ou foi barrado antes de sair.
  UNDELIVERED_STATUSES = { 'failed' => %w[failed], 'blocked' => %w[skipped cancelled] }.freeze

  # Motivo de bloqueio gravado em `external_error` quando o motor pula o destinatario. Codigo
  # estavel (vira rotulo traduzido na tela e coluna no CSV); antes era frase solta, que segue
  # reconhecida em LEGACY_SKIP_REASONS para os disparos ja feitos.
  SKIP_REASONS = %w[caixa_somente_leitura atendimento_ativo].freeze
  LEGACY_SKIP_REASONS = {
    'caixa somente leitura' => 'caixa_somente_leitura', 'contato em atendimento ativo' => 'atendimento_ativo'
  }.freeze

  validates :phone_number, presence: true

  # Codigo do motivo de nao-envio. Falha da Meta grava "131026: Message undeliverable" -> '131026';
  # falha sem codigo (excecao interna, erro sincrono da API) -> 'erro_envio'.
  def reason_code
    return Whatsapp::UndeliveredReason.code(external_error) if failed?

    error = external_error.to_s
    return error if SKIP_REASONS.include?(error)

    LEGACY_SKIP_REASONS[error] || (cancelled? ? 'cancelado' : 'desconhecido')
  end

  # Motivo em linguagem de operador (mapa compartilhado em Whatsapp::UndeliveredReason).
  def reason_label
    Whatsapp::UndeliveredReason.label(reason_code, external_error)
  end

  # Reivindica o destinatario de forma atomica (pending -> processing) para que a
  # engine nao despache o mesmo numero duas vezes em ticks concorrentes do
  # scheduler. Reflete o estado em memoria quando ganha a corrida.
  def claim!
    won = self.class.where(id: id, status: :pending)
                    .update_all(status: self.class.statuses[:processing], updated_at: Time.current) == 1
    self.status = :processing if won
    won
  end
end
