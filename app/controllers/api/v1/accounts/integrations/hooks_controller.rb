class Api::V1::Accounts::Integrations::HooksController < Api::V1::Accounts::Integrations::BaseController
  before_action :fetch_hook, except: [:create]
  before_action :check_authorization

  def create
    @hook = Current.account.hooks.create!(permitted_params)
  end

  def update
    @hook.update!(update_params)
  end

  def process_event
    response = @hook.process_event(params[:event])

    # for cases like an invalid event, or when conversation does not have enough messages
    # for a label suggestion, the response is nil
    if response.nil?
      render json: { message: nil }
    elsif response[:error]
      render json: { error: response[:error] }, status: :unprocessable_entity
    else
      render json: { message: response[:message] }
    end
  end

  def destroy
    @hook.destroy!
    head :ok
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.find(params[:id])
  end

  def permitted_params
    params.require(:hook).permit(:app_id, :inbox_id, :status, settings: {})
  end

  # ChatSPX (item 26): `settings` é MESCLADO, nunca substituído.
  #
  # O upstream passou a filtrar `settings` por `app.visible_properties` em
  # `app/views/api/v1/models/_hook.json.jbuilder` — do lado dele isso é seguro, porque o upstream
  # não tem tela de editar hook. A nossa tem (`EditHook.vue`, 100% do fork). Ela lê o hash já
  # filtrado, o campo da credencial chega `undefined`, o form grava `''` e o submit reenviava
  # `settings: { api_key: '' }`. Com `update!` substituindo o jsonb inteiro, a credencial era
  # DESTRUÍDA no banco — sem erro, sem log, sem GlitchTip, e com 200 OK na resposta. Nenhum dos
  # três lados está errado sozinho, e é por isso que passava por toda a suíte verde.
  # São 6 integrações e 14 chaves; `meta_lead_ads` perde 3 segredos de uma vez.
  #
  # Mesclar aqui fecha o buraco para QUALQUER cliente, não só para a nossa tela — inclusive script
  # que chame a API direto. `EditHook.vue` também foi corrigido para não reenviar chave que não
  # recebeu; os dois lados são necessários, cada um fecha um caminho.
  #
  # Consequência aceita: a API deixa de conseguir REMOVER uma chave de `settings` (só sobrescrever
  # o valor, inclusive com vazio). Nenhuma tela nossa faz isso, e perder credencial em silêncio é
  # muito pior do que precisar de uma migração para apagar uma chave órfã.
  def update_params
    attrs = permitted_params.slice(:status, :settings)
    return attrs unless attrs.key?(:settings)

    attrs.merge(settings: merged_settings(attrs[:settings].to_h))
  end

  def merged_settings(incoming)
    stored = @hook.settings.to_h
    stored.merge(incoming.reject { |key, value| blanking_a_key_the_client_never_saw?(stored, key, value) })
  end

  # Mesclar resolve o caso "o cliente não mandou a chave". Falta o caso "o cliente mandou a chave
  # VAZIA", que é exatamente o que a nossa tela fazia e o que qualquer script escrito contra ela
  # ainda faria. A regra aqui é a mesma do front, do outro lado do fio: se a chave NÃO está em
  # `visible_properties`, o cliente nunca a recebeu — logo não pode ter lido o valor, e um vazio
  # vindo dele é resíduo de formulário, não intenção de apagar. Chave visível continua podendo ser
  # esvaziada normalmente, e trocar a credencial por um valor novo funciona em qualquer caso.
  def blanking_a_key_the_client_never_saw?(stored, key, value)
    return false unless value.nil? || value == ''

    visible = Array(@hook.app&.visible_properties).map(&:to_s)
    visible.exclude?(key.to_s) && stored[key.to_s].present?
  end
end
