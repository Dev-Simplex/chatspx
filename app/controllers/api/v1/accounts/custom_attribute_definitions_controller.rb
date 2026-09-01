class Api::V1::Accounts::CustomAttributeDefinitionsController < Api::V1::Accounts::BaseController
  # Só a GESTÃO sai do alcance do supervisor de time. `index`/`show` continuam abertos
  # de propósito: as definições alimentam os campos personalizados do painel do contato
  # e da conversa — fechá-las some com os campos na tela de atendimento dele.
  before_action :check_platform_settings_authorization?, only: [:create, :update, :destroy]
  before_action :fetch_custom_attributes_definitions, except: [:create]
  before_action :fetch_custom_attribute_definition, only: [:show, :update, :destroy]
  DEFAULT_ATTRIBUTE_MODEL = 'conversation_attribute'.freeze

  def index; end

  def show; end

  def create
    @custom_attribute_definition = Current.account.custom_attribute_definitions.create!(
      # Bloco 4.17: a origem e carimbada pelo SERVIDOR, a partir de quem esta autenticado,
      # e nunca lida do corpo. Quem chega aqui passou por `Api::V1::Accounts::BaseController`
      # — e um agente da conta. Aceitar `origin` do payload deixaria o proprio agente
      # reivindicar `website` e pegar de graca o selo de auto-provisionado do bloco 1.17.
      permitted_payload.merge(origin: CustomAttributeDefinition::ORIGIN_AGENT)
    )
  end

  def update
    @custom_attribute_definition.update!(permitted_payload)
  end

  def destroy
    @custom_attribute_definition.destroy!
    head :no_content
  end

  private

  def fetch_custom_attributes_definitions
    @custom_attribute_definitions = Current.account.custom_attribute_definitions.with_attribute_model(permitted_params[:attribute_model])
  end

  def fetch_custom_attribute_definition
    @custom_attribute_definition = Current.account.custom_attribute_definitions.find(permitted_params[:id])
  end

  def permitted_payload
    params.require(:custom_attribute_definition).permit(
      :attribute_display_name,
      :attribute_description,
      :attribute_display_type,
      :attribute_key,
      :attribute_model,
      :regex_pattern,
      :regex_cue,
      # Bloco 4.17: sem esta linha a coluna existe, o portao existe, e nao ha como ligar a
      # flag fora do console — que e como o bloco chegou "PARCIAL". `origin` fica DE FORA
      # de proposito (ver `create`): ela e carimbo do servidor, nao campo de formulario.
      :requires_verified_origin,
      :required,
      :hidden,
      attribute_values: []
    )
  end

  def permitted_params
    params.permit(:id, :filter_type, :attribute_model)
  end
end
