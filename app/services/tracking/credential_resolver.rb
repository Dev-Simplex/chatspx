# frozen_string_literal: true

# A JUNTA entre a fila server-side (5.11/5.12/5.13) e o cofre de credenciais (5.02).
#
# Este e o unico arquivo da fila que fala com `TrackingCredential`. Os destinos e os jobs recebem um
# `Settings` e nunca tocam o modelo — foi escolha da trilha da fila, e continua valendo: quando a
# fonte de um campo mudar (o OAuth do Google, por exemplo), muda aqui e em lugar nenhum mais.
#
# O CONTRATO ASSUMIDO PELA FILA NAO CASOU COM O MODELO ENTREGUE, e o ajuste foi deste lado porque o
# modelo ja tem spec e aceite passado. Duas diferencas, e as duas mudam comportamento:
#
#  1. **Nao existe credencial "da conta".** A fila assumia um registro com `inbox_id` nulo valendo
#     como padrao; a tabela tem `inbox_id` NOT NULL com UNIQUE. Entao a resolucao e ESTRITAMENTE por
#     inbox: evento sem inbox nao tem credencial, e nao herda a de ninguem. E o comportamento certo
#     para uma tabela cuja cardinalidade e uma linha por inbox — inventar uma heranca aqui faria o
#     evento de uma inbox sair pelo pixel de outra.
#
#  2. **O cofre guarda so os SEGREDOS.** Pixel ID e Measurement ID sao publicos (aparecem no HTML de
#     qualquer site que use as tags) e moram em `inbox.additional_attributes['widget_tracking']`, do
#     bloco 5.01. Segredo que morasse junto seria publicado no HTML — e por isso as duas metades sao
#     lidas de lugares diferentes e so se encontram aqui, no servidor.
#
# A CREDENCIAL E A ANCORA: sem linha no cofre o retorno e `nil` e a fila fica inerte, mesmo que a
# inbox tenha Pixel ID configurado. Id publico sozinho nao escreve nada em destino nenhum — o que
# escreve e o token, e ele so existe no cofre.
class Tracking::CredentialResolver
  FIELDS = %i[
    meta_pixel_id meta_access_token meta_test_event_code
    ga4_measurement_id ga4_api_secret
    google_ads_customer_id google_ads_conversion_action_id
    google_ads_developer_token google_ads_access_token google_ads_login_customer_id
  ].freeze

  # Os identificadores PUBLICOS, lidos do jsonb da inbox. As chaves sao as mesmas de
  # `WidgetTrackingProjection::PUBLIC_KEYS` — se divergirem, o valor volta nil e o destino se declara
  # nao configurado, que e falha silenciosa; por isso ha spec que compara as duas listas.
  PUBLIC_SOURCE = {
    meta_pixel_id: 'meta_pixel_id',
    ga4_measurement_id: 'ga4_measurement_id'
  }.freeze

  # Os campos que vem do cofre, cada um com o nome que a coluna tem. `meta_test_event_code` entra
  # aqui por morar na mesma tabela, ainda que nao seja segredo.
  SECRET_SOURCE = {
    meta_access_token: :meta_access_token,
    meta_test_event_code: :meta_test_event_code,
    ga4_api_secret: :ga4_api_secret,
    google_ads_developer_token: :google_ads_developer_token
  }.freeze

  # Os quatro campos do Google Ads que HOJE NAO TEM FONTE, e que por isso ficam `nil` — o que mantem
  # `google_ads_ready?` falso e o destino fora do leque, sem nunca montar um payload que a API
  # recusaria:
  #
  #  - `google_ads_access_token`: o cofre guarda o REFRESH token (`google_ads_refresh_token`); trocar
  #    um pelo outro e o OAuth de um clique, a metade (b) do 5.02, que depende de app registrado no
  #    Google — cadastro do dono, nao codigo.
  #  - `google_ads_customer_id` e `google_ads_conversion_action_id`: nao existem nem no cofre nem no
  #    `widget_tracking`. NAO sao derivaveis do `google_ads_send_to`: o `AW-000/Rotulo` do gtag e o id
  #    da TAG de conversao com um rotulo opaco, e a API quer dois numeros diferentes desses dois
  #    (`customers/<CID>/conversionActions/<ID>`). Derivar produziria um payload que a API rejeita e
  #    uma entrega morta na DLQ que ninguem consegue explicar.
  #  - `google_ads_login_customer_id`: so faz sentido com conta MCC, e chega junto do OAuth.
  #
  # Quando essas fontes existirem, e so acrescenta-las aos mapas acima: os destinos, os jobs e o
  # leque ja estao prontos e nao mudam uma linha.
  UNSOURCED_FIELDS = %i[
    google_ads_customer_id google_ads_conversion_action_id
    google_ads_access_token google_ads_login_customer_id
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
    credential = credential_record
    return nil if credential.nil?

    Settings.new(**public_settings, **secret_settings(credential))
  end

  private

  attr_reader :account, :inbox

  # O filtro por `account_id` e redundante com a validacao do modelo — e fica assim de proposito.
  # O UNIQUE do banco e so em `inbox_id`, entao esta e a unica barreira que sobreviveria a uma linha
  # gravada por console ou import com a conta errada, e o preco de errar aqui e o evento de um
  # cliente sair pelo pixel de outro.
  def credential_record
    return nil if account.nil? || inbox.nil?

    TrackingCredential.find_by(account_id: account.id, inbox_id: inbox.id)
  end

  def public_settings
    config = widget_tracking

    PUBLIC_SOURCE.transform_values { |key| config[key].presence }
  end

  # `to_h` duas vezes, e nao `dig`: a coluna pode vir nula e a chave pode faltar. Assim a ausencia do
  # 5.01 vira campo `nil` — que o destino le como "nao configurado" — e nunca um NoMethodError dentro
  # de um job, que morreria na DLQ como se fosse erro do destino.
  def widget_tracking
    inbox.additional_attributes.to_h['widget_tracking'].to_h
  end

  def secret_settings(credential)
    SECRET_SOURCE.transform_values { |column| credential.public_send(column).presence }
  end
end
