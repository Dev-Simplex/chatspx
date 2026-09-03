# frozen_string_literal: true

# == Schema Information
#
# Table name: tracking_events
#
#  id              :bigint           not null, primary key
#  dedup_key       :string           not null
#  event_id        :string           not null
#  name            :string           not null
#  occurred_at     :datetime         not null
#  properties      :jsonb            not null
#  source          :integer          default("server"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  contact_id      :bigint
#  conversation_id :bigint
#  inbox_id        :bigint
#
# Indexes
#
#  index_tracking_events_on_account_name_time    (account_id,name,occurred_at)
#  index_tracking_events_on_contact_id           (contact_id)
#  index_tracking_events_on_conversation_id      (conversation_id)
#  index_tracking_events_on_dedup                (account_id,name,dedup_key) UNIQUE
#  index_tracking_events_on_event_id             (event_id) UNIQUE
#  index_tracking_events_on_inbox_id             (inbox_id)
#  index_tracking_events_on_occurred_at_brin     (occurred_at) USING brin
#
# O FATO: uma linha por acao do usuario que vale contar a um destino de anuncio ou analytics.
# Contrato completo — nome, tipo, default e o que acontece na ausencia — em
# docs/tracking/contrato-de-eventos.md. Bloco 5.03; consumido por 5.04, 5.05, 5.10, 5.11, 5.13 a 5.16.
#
# Tres coisas que este modelo garante, e cada uma existe porque e um jeito conhecido de o registro
# deixar de valer:
#  1. `event_id` sempre existe (UUID v4 do servidor) — e a chave de negocio do evento;
#  2. o NOME obedece as tres regras do contrato (prefixo, snake_case, 40 caracteres do GA4), porque
#     nome invalido so falharia no destino do cliente, longe de quem o escreveu;
#  3. `properties` nao carrega dado pessoal cru (RC5) — a PII sai hasheada pelo servidor em 5.11.
class TrackingEvent < ApplicationRecord
  NAME_PREFIX = 'chatspx_'
  # 40 e limite do GA4, nao preferencia nossa.
  NAME_MAX_LENGTH = 40
  SNAKE_CASE = /\A[a-z][a-z0-9_]*\z/

  # As chaves que o plano 25 nomeia como PII na §A.6 e em T-C5.3, mais os nomes por extenso que um
  # chamador distraido usaria. A varredura e em profundidade: PII aninhada vaza igual.
  PII_KEYS = %w[em ph fn ln email phone phone_number first_name last_name].freeze

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true

  has_many :tracking_deliveries, dependent: :destroy

  # `widget` = emitido pelo store do widget (5.04); `site` = via track() do cliente (5.16).
  enum source: { server: 0, widget: 1, site: 2 }

  before_validation :ensure_event_id
  before_validation :ensure_occurred_at
  before_validation :ensure_properties
  before_validation :ensure_dedup_key

  validates :name, presence: true
  validate :ensure_name_follows_the_contract
  validate :ensure_properties_carry_no_raw_pii

  scope :for_period, ->(range) { where(occurred_at: range) }

  # A chave natural do fato, deriva do fato e nao do instante da gravacao: o retry de um job traz o
  # mesmo `occurred_at`, entao produz a mesma chave e colide no indice unico.
  def self.derive_dedup_key(name:, occurred_at:, conversation_id: nil, contact_id: nil)
    subject = conversation_id || contact_id || 'account'

    "#{name}:#{subject}:#{occurred_at.to_i}"
  end

  # Reserva o direito de entregar este evento a um destino.
  #
  # Devolve a TrackingDelivery quando o chamador GANHOU a corrida — e so entao ele deve entregar.
  # Devolve `nil` quando ja havia entrega para o par: outro worker assumiu. A garantia e do indice
  # unico do banco, nao de uma checagem em Ruby, que dois workers concorrentes furariam.
  #
  # O savepoint (`requires_new: true`) existe porque no PostgreSQL uma violacao de constraint aborta
  # a transacao corrente: sem ele, o `nil` viria acompanhado de uma transacao inutilizavel, e a
  # proxima consulta do mesmo job falharia por um motivo que nao tem nada a ver com o que aconteceu.
  def claim_delivery(destination)
    self.class.transaction(requires_new: true) do
      tracking_deliveries.create!(destination: destination)
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  private

  def ensure_event_id
    self.event_id = SecureRandom.uuid if event_id.blank?
  end

  def ensure_occurred_at
    self.occurred_at = Time.current if occurred_at.blank?
  end

  def ensure_properties
    self.properties = {} if properties.blank?
  end

  def ensure_dedup_key
    return if dedup_key.present? || name.blank? || occurred_at.blank?

    self.dedup_key = self.class.derive_dedup_key(name: name, occurred_at: occurred_at,
                                                 conversation_id: conversation_id, contact_id: contact_id)
  end

  def ensure_name_follows_the_contract
    return if name.blank?

    return errors.add(:name, "deve começar com #{NAME_PREFIX}") unless name.start_with?(NAME_PREFIX)
    return errors.add(:name, 'deve ser snake_case: minúsculas, dígitos e _') unless name.match?(SNAKE_CASE)

    errors.add(:name, "passa do limite de #{NAME_MAX_LENGTH} caracteres do GA4") if name.length > NAME_MAX_LENGTH
  end

  def ensure_properties_carry_no_raw_pii
    return unless properties.is_a?(Hash)

    offender = find_pii_key(properties)
    return if offender.nil?

    errors.add(:properties,
               "não aceita dado pessoal cru: a chave \"#{offender}\" sai hasheada pelo servidor, nunca aqui")
  end

  def find_pii_key(node)
    return find_pii_key_in_hash(node) if node.is_a?(Hash)
    return node.filter_map { |item| find_pii_key(item) }.first if node.is_a?(Array)

    nil
  end

  def find_pii_key_in_hash(hash)
    hash.each do |key, value|
      return key.to_s if PII_KEYS.include?(key.to_s.downcase)

      nested = find_pii_key(value)
      return nested if nested
    end

    nil
  end
end
