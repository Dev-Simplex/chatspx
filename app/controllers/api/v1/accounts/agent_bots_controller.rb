class Api::V1::Accounts::AgentBotsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :agent_bot, except: [:index, :create]
  before_action :ensure_mutable_bot, only: [:update, :destroy, :avatar, :reset_access_token]
  before_action :reject_captain_bot_type, only: [:create, :update]

  def index
    @agent_bots = AgentBot.accessible_to(Current.account)
  end

  def show; end

  def create
    @agent_bot = Current.account.agent_bots.create!(permitted_params.except(:avatar_url))
    process_avatar_from_url
  end

  def update
    @agent_bot.update!(permitted_params.except(:avatar_url))
    process_avatar_from_url
  end

  def avatar
    @agent_bot.avatar.purge if @agent_bot.avatar.attached?
    @agent_bot
  end

  def destroy
    @agent_bot.destroy!
    head :ok
  end

  def reset_access_token
    @agent_bot.access_token.regenerate_token
    @agent_bot.reload
  end

  def reset_secret
    @agent_bot.reset_secret!
  end

  private

  def agent_bot
    @agent_bot = AgentBot.accessible_to(Current.account).find(params[:id]) if params[:action] == 'show'
    @agent_bot ||= Current.account.agent_bots.find(params[:id])
  end

  # Espelhos captain são gerenciados pelo sync do assistant — imutáveis via API.
  def ensure_mutable_bot
    return unless @agent_bot.captain?

    render json: { error: I18n.t('agent_bots.captain_mirror_immutable') }, status: :unprocessable_entity
  end

  # Espelho só nasce pelo Captain::AssistantMirrorService, nunca via params.
  def reject_captain_bot_type
    return unless params[:bot_type].to_s.in?(['captain', AgentBot.bot_types[:captain].to_s])

    render json: { error: I18n.t('agent_bots.captain_mirror_immutable') }, status: :unprocessable_entity
  end

  def permitted_params
    params.permit(:name, :description, :outgoing_url, :avatar, :avatar_url, :bot_type, bot_config: {})
  end

  def process_avatar_from_url
    ::Avatar::AvatarFromUrlJob.perform_later(@agent_bot.class.name, @agent_bot.id, params[:avatar_url]) if params[:avatar_url].present?
  end
end
