# frozen_string_literal: true

# Bloco 5.11 — a fronteira com o bloco 5.02 (credenciais), que ainda NAO existe nesta arvore.
#
# O contrato assumido esta escrito aqui, num arquivo so, e e o unico lugar que precisa mudar quando
# `TrackingCredential` chegar: os destinos recebem um `Settings` e nunca falam com o modelo. Foi
# escolha deliberada — programar contra o modelo ausente espalharia `defined?(TrackingCredential)`
# por seis arquivos, e cada um os leria de um jeito.
#
# CONTRATO ASSUMIDO (escalado ao coordenador): um registro por (account_id, inbox_id), com
# `inbox_id` nulo valendo como padrao da conta, e leitores em claro so no servidor:
#   meta_pixel_id, meta_access_token, meta_test_event_code,
#   ga4_measurement_id, ga4_api_secret,
#   google_ads_customer_id, google_ads_conversion_action_id,
#   google_ads_developer_token, google_ads_access_token, google_ads_login_customer_id
#
# Enquanto o modelo nao existe, `call` devolve `nil` e a fila inteira fica inerte: nenhum destino se
# diz configurado, nenhuma entrega e reservada, nenhum job e enfileirado. E o comportamento correto
# — sem credencial nao ha o que entregar — e tambem o que garante que esta trilha nao muda o
# comportamento de nenhuma outra ate 5.02 aterrissar.
class Tracking::CredentialResolver
  FIELDS = %i[
    meta_pixel_id meta_access_token meta_test_event_code
    ga4_measurement_id ga4_api_secret
    google_ads_customer_id google_ads_conversion_action_id
    google_ads_developer_token google_ads_access_token google_ads_login_customer_id
  ].freeze

  Settings = Struct.new(*FIELDS, keyword_init: true) do
    def meta_capi_ready?
      meta_pixel_id.present? && meta_access_token.present?
    end

    def ga4_mp_ready?
      ga4_measurement_id.present? && ga4_api_secret.present?
    end

    def google_ads_ready?
      google_ads_customer_id.present? && google_ads_conversion_action_id.present? &&
        google_ads_developer_token.present? && google_ads_access_token.present?
    end
  end

  def self.call(account:, inbox: nil)
    new(account: account, inbox: inbox).call
  end

  def initialize(account:, inbox: nil)
    @account = account
    @inbox = inbox
  end

  def call
    record = credential_record
    return nil if record.nil?

    Settings.new(**FIELDS.index_with { |field| record.try(field) })
  end

  private

  attr_reader :account, :inbox

  def credential_record
    model = credential_model
    return nil if model.nil? || account.nil?

    (inbox && model.find_by(account_id: account.id, inbox_id: inbox.id)) ||
      model.find_by(account_id: account.id, inbox_id: nil)
  end

  # `const_defined?` em vez de `defined?`: o segundo tambem responde "sim" para constante so
  # registrada no autoload do Zeitwerk, e a diferenca importa numa arvore onde o modelo pode chegar
  # a qualquer merge.
  def credential_model
    return nil unless Object.const_defined?(:TrackingCredential)

    Object.const_get(:TrackingCredential)
  rescue NameError
    nil
  end
end
