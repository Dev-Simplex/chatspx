# frozen_string_literal: true

# == Schema Information
#
# Table name: tracking_credentials
#
#  id                         :bigint           not null, primary key
#  ga4_api_secret             :text
#  google_ads_developer_token :text
#  google_ads_refresh_token   :text
#  last_verified_at           :datetime
#  meta_access_token          :text
#  meta_test_event_code       :string
#  oauth_metadata             :jsonb            not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  inbox_id                   :bigint           not null
#
# Indexes
#
#  index_tracking_credentials_on_account_id  (account_id)
#  index_tracking_credentials_on_inbox_id    (inbox_id) UNIQUE
#
# O COFRE do rastreio, uma linha por inbox. Bloco 5.02 (T-C1.2). A configuracao PUBLICA — Pixel ID,
# Measurement ID, mapa de eventos — mora em `inbox.additional_attributes['widget_tracking']` e e
# servida ao navegador; aqui mora so o que NUNCA pode sair do backend (RC10).
#
# Tres garantias, e cada uma existe porque e um jeito conhecido de o segredo escapar:
#
#  1. **Cifrado em repouso.** Uma unica declaracao `encrypts` por atributo. Isto e regra, nao
#     estilo: duas declaracoes no mesmo atributo se MISTURAM e a opcao de cifra da segunda se perde
#     em silencio — foi medido nesta base em `User#otp_secret`, que se le como deterministico e nao
#     e (plano/redesenho/execucao/onda-0-infra-0.4-0.10-EXECUTADO.md).
#
#  2. **Nao deterministico, de proposito.** Nenhuma consulta busca inbox POR valor de segredo — o
#     acesso e sempre pela inbox — entao o determinismo nao compraria nada e custaria o IV
#     aleatorio, que e o que impede um observador do banco de descobrir que duas inboxes usam o
#     mesmo token comparando ciphertext.
#
#  3. **Nunca em claro na resposta nem na auditoria.** A serializacao passa por `secret_summary`, e
#     o `audited` do enterprise exclui os quatro campos por nome — senao a tabela `audits` guardaria
#     em texto puro justamente o valor que a coluna cifra.
class TrackingCredential < ApplicationRecord
  # A lista canonica dos campos que nunca saem em claro. Serializador, strong params e o `except:`
  # da auditoria leem TODOS daqui: campo novo acrescentado aqui ja nasce protegido nos tres, e nao
  # ha como acrescentar num lugar e esquecer nos outros.
  SECRET_ATTRIBUTES = %i[meta_access_token ga4_api_secret google_ads_refresh_token google_ads_developer_token].freeze

  # Abaixo disto, os "4 ultimos" seriam boa parte do segredo. Nenhuma credencial real dos tres
  # provedores chega perto deste piso — o access token da Meta passa de 100 caracteres.
  MIN_SECRET_LENGTH = 8

  belongs_to :account
  belongs_to :inbox

  validates :inbox_id, uniqueness: true
  validate :ensure_inbox_belongs_to_account
  validate :ensure_secrets_are_long_enough
  validate :ensure_encryption_is_configured

  # Sem guarda `if Chatwoot.encryption_configured?`, ao contrario de `Integrations::Hook`. A guarda
  # faz sentido para um campo legado que ja tem linha em claro no banco; aqui a tabela nasce vazia,
  # e num ambiente sem chaves a guarda gravaria o access token da Meta EM CLARO sem avisar
  # ninguem. A validacao acima recusa a gravacao nesse caso — falhar alto e a saida certa.
  encrypts :meta_access_token
  encrypts :ga4_api_secret
  encrypts :google_ads_refresh_token
  encrypts :google_ads_developer_token

  def configured?(attribute)
    self[attribute].present?
  end

  # Os 4 ULTIMOS caracteres, e so eles — o suficiente para o operador reconhecer qual credencial
  # colou, e insuficiente para reconstruir qualquer coisa. Devolve nil (nao um pedaco) quando o
  # valor e curto demais: sem isto, um segredo de 5 caracteres voltaria quase inteiro.
  def last_four(attribute)
    value = self[attribute]
    return if value.blank? || value.length < MIN_SECRET_LENGTH

    value.last(4)
  end

  # A UNICA forma pela qual um campo de segredo pode aparecer numa resposta de API.
  def secret_summary(attribute)
    { configured: configured?(attribute), last_four: last_four(attribute) }
  end

  private

  def ensure_inbox_belongs_to_account
    return if inbox.blank? || account_id.blank?
    return if inbox.account_id == account_id

    errors.add(:inbox, I18n.t('errors.tracking_credential.inbox_not_in_account'))
  end

  def ensure_secrets_are_long_enough
    SECRET_ATTRIBUTES.each do |attribute|
      value = self[attribute]
      next if value.blank? || value.length >= MIN_SECRET_LENGTH

      errors.add(attribute, I18n.t('errors.tracking_credential.secret_too_short', count: MIN_SECRET_LENGTH))
    end
  end

  def ensure_encryption_is_configured
    return if Chatwoot.encryption_configured?
    return if SECRET_ATTRIBUTES.none? { |attribute| self[attribute].present? }

    errors.add(:base, I18n.t('errors.tracking_credential.encryption_not_configured'))
  end
end

TrackingCredential.include_mod_with('Audit::TrackingCredential')
