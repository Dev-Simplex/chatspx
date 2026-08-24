# Credenciais de rastreio de uma inbox (bloco 5.02).
#
# Nenhuma acao deste controller devolve segredo. `show` e `update` respondem pelo mesmo jbuilder,
# que so sabe montar `{ configured, last_four }` — o valor em claro nao tem por onde sair.
class Api::V1::Accounts::Inboxes::TrackingCredentialsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action -> { check_authorization(TrackingCredential) }
  before_action :fetch_credential

  def show; end

  def update
    @tracking_credential.update!(update_params)
  end

  def verify
    result = TrackingCredentials::Verifier.new(@tracking_credential, provider: params[:provider]).perform

    render json: result, status: result[:success] ? :ok : :unprocessable_entity
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  # Upsert: a tela abre antes de existir credencial, e obrigar um POST separado so para poder
  # editar seria estado a mais sem nada em troca.
  #
  # Busca pela tabela em vez de por `@inbox.tracking_credential` de proposito: a associacao
  # `has_one` em `app/models/inbox.rb` seria uma linha, mas esse arquivo pertence a outra trilha
  # agora. O comportamento e o mesmo — o UNIQUE em `inbox_id` garante a cardinalidade e a FK
  # `on_delete: :cascade` garante a limpeza, ambos no banco, que e onde importa.
  def fetch_credential
    @tracking_credential = TrackingCredential.find_or_initialize_by(inbox: @inbox) do |credential|
      credential.account = Current.account
    end
  end

  def permitted_params
    params.require(:tracking_credential)
          .permit(:meta_access_token, :ga4_api_secret, :google_ads_refresh_token, :google_ads_developer_token,
                  :meta_test_event_code)
  end

  # Segredo que chega VAZIO nao apaga o valor gravado.
  #
  # Esta base ja perdeu credencial exatamente assim, em `Integrations::Hook`: a resposta filtra o
  # segredo, o formulario recebe `undefined`, grava `''` e reenvia o objeto inteiro — o `update!`
  # entao substituia a credencial por vazio, com 200 OK e sem nenhum erro em lugar nenhum. Aqui a
  # tela NUNCA recebe o valor (so `last_four`), entao um vazio vindo dela e sempre residuo de
  # formulario, jamais intencao de apagar.
  #
  # Consequencia aceita: para REMOVER um segredo, o cliente manda `null` explicito, nao `''`.
  # Perder credencial em silencio e muito pior do que precisar de um valor diferente para apagar.
  def update_params
    attributes = permitted_params
    TrackingCredential::SECRET_ATTRIBUTES.each do |attribute|
      attributes.delete(attribute) if attributes[attribute] == ''
    end
    attributes
  end
end
