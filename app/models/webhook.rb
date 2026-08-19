# == Schema Information
#
# Table name: webhooks
#
#  id            :bigint           not null, primary key
#  name          :string
#  secret        :string
#  subscriptions :jsonb
#  url           :text
#  webhook_type  :integer          default("account_type")
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :integer
#  inbox_id      :integer
#
# Indexes
#
#  index_webhooks_on_account_id_and_url  (account_id,url) UNIQUE
#

class Webhook < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true

  include WebhookSecretable

  validates :account_id, presence: true
  # Bloco 4.13: a unicidade acompanha o indice, que passou a incluir a inbox. A mesma URL
  # servindo duas inboxes diferentes e configuracao legitima agora que o filtro funciona.
  validates :url, uniqueness: { scope: [:account_id, :inbox_id] }, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  validate :validate_webhook_subscriptions
  # Bloco 4.13: enquanto o inbox_id era ignorado na entrega, apontar para inbox de outra
  # conta era inofensivo — e o modelo aceitava. Agora que o campo decide quem recebe, o
  # mesmo registro viraria uma armadilha silenciosa: nunca casaria com nenhum evento e o
  # dono do webhook ficaria sem entrega nenhuma, sem erro em lugar algum.
  #
  # `if: :will_save_change_to_inbox_id?` de proposito: linha antiga com inbox_id invalido
  # continua editavel. Validar em toda gravacao trancaria o cliente para fora de um
  # registro que ele precisa justamente consertar.
  validate :inbox_belongs_to_account, if: :will_save_change_to_inbox_id?
  enum webhook_type: { account_type: 0, inbox_type: 1 }

  # Bloco 4.12: `conversation_resolved` so chegava a agent bot
  # (agent_bot_listener.rb:2). Webhook de conta nao podia nem se inscrever nele — e
  # "a conversa foi resolvida" e justamente o gancho de CRM, NPS e billing.
  ALLOWED_WEBHOOK_EVENTS = %w[conversation_status_changed conversation_updated conversation_created conversation_resolved
                              contact_created contact_updated
                              message_created message_updated webwidget_triggered inbox_created inbox_updated
                              conversation_typing_on conversation_typing_off].freeze

  # Bloco 4.13 — a chave para assinar uma chamada de saida cuja URL foi digitada numa
  # automacao, macro, flow ou regra de kanban.
  #
  # Esses caminhos disparavam SEM assinatura nenhuma: o destino recebia um POST com dados
  # de conversa e nao tinha como provar que veio de nos. Aqui a regra e simples e honesta:
  # se a conta REGISTROU aquela URL como webhook, existe segredo combinado com o destino e
  # a chamada e assinada com ele. Se nao registrou, nao ha segredo compartilhado — e
  # inventar um nao assinaria coisa alguma, so daria a impressao de que assinou.
  def self.signing_secret_for(account:, url:)
    return if account.blank? || url.blank?

    account.webhooks.find_by(url: url)&.secret
  end

  private

  def inbox_belongs_to_account
    return if inbox_id.blank?
    return if account_id.present? && Inbox.exists?(id: inbox_id, account_id: account_id)

    errors.add(:inbox, I18n.t('errors.webhook.inbox_not_in_account', default: 'does not belong to this account'))
  end

  def validate_webhook_subscriptions
    invalid_subscriptions = !subscriptions.instance_of?(Array) ||
                            subscriptions.blank? ||
                            (subscriptions.uniq - ALLOWED_WEBHOOK_EVENTS).length.positive?
    errors.add(:subscriptions, I18n.t('errors.webhook.invalid')) if invalid_subscriptions
  end
end

Webhook.include_mod_with('Audit::Webhook')
