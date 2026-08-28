# frozen_string_literal: true

# == Schema Information
#
# Table name: inbox_isolation_exemptions
#
#  id             :bigint           not null, primary key
#  isolation_type :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  inbox_id       :bigint           not null
#  user_id        :bigint           not null
#
# Indexes
#
#  index_inbox_isolation_exemptions_on_inbox_user_type  (inbox_id,user_id,isolation_type) UNIQUE
#  index_inbox_isolation_exemptions_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
# Quem ESCAPA de um isolamento de mensagens numa caixa de entrada.
#
# A tela fala PARTICIPANTES ("estes agentes participam do isolamento"); o banco guarda
# EXCEÇÕES. A inversão é deliberada: lista vazia = comportamento de hoje, então a feature
# entra inerte para quem já usa isolamento. Se guardássemos participantes, toda caixa já
# existente nasceria com lista vazia e o isolamento deixaria de valer no deploy, calado.
# A conversão participantes -> exceções acontece no submit (InboxesController).
#
# Isento aqui NÃO ganha nada além de leitura ampliada naquela caixa — nenhum poder de admin.
# Convive com os dois isentos que já existiam e não são recriados aqui: administrador
# (sempre isento das duas regras) e supervisor de time (TeamSupervision).
class InboxIsolationExemption < ApplicationRecord
  ISOLATION_TYPES = %w[agent_message team_message].freeze

  belongs_to :inbox
  belongs_to :user

  validates :isolation_type, inclusion: { in: ISOLATION_TYPES }
  validates :user_id, uniqueness: { scope: %i[inbox_id isolation_type] }
  validate :user_belongs_to_inbox_account

  scope :for_type, ->(isolation_type) { where(isolation_type: isolation_type) }

  private

  # Isenção é sempre dentro de uma conta: um usuário de OUTRA conta não pode ser isentado
  # do isolamento desta caixa. O controller já filtra os ids pelos membros da caixa; isto
  # é a rede de segurança para quem cria a linha direto pelo modelo/console.
  def user_belongs_to_inbox_account
    return if inbox.blank? || user.blank?
    return if user.account_users.exists?(account_id: inbox.account_id)

    errors.add(:user, 'must belong to the same account as the inbox')
  end
end
