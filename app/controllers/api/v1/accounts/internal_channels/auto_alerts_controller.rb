# frozen_string_literal: true

# Chat interno — liga/desliga os avisos automáticos de uma sala de time. Qualquer um que vê a sala lê;
# só admin da conta ou supervisor do time muda (InternalChannels::AutoAlertsService.can_manage?).
class Api::V1::Accounts::InternalChannels::AutoAlertsController < Api::V1::Accounts::BaseController
  include InternalChatFeatureGuard

  before_action :fetch_channel

  def show
    render json: payload
  end

  def update
    return render json: { error: 'Not allowed' }, status: :forbidden unless can_manage?

    alerts = @channel.settings.fetch('auto_alerts', {}).merge(
      params.permit(*InternalChannels::AutoAlertsService::EVENTS).to_h.transform_values { |v| ActiveModel::Type::Boolean.new.cast(v) }
    )
    @channel.update!(settings: @channel.settings.merge('auto_alerts' => alerts))
    render json: payload
  end

  private

  def fetch_channel
    base = Current.account_user&.administrator? ? Current.account.internal_channels : policy_scope(InternalChannel)
    @channel = base.team.find(params[:internal_channel_id])
    authorize(@channel, :show?)
  end

  def can_manage?
    InternalChannels::AutoAlertsService.can_manage?(@channel, Current.account_user)
  end

  def payload
    {
      events: InternalChannels::AutoAlertsService::EVENTS.index_with { |e| InternalChannels::AutoAlertsService.enabled?(@channel, e) },
      can_manage: can_manage?,
      limiar_minutos: Spx::Distribuicao::ContabilizacaoService.new(account: Current.account, team_id: @channel.team_id).limiar_minutos
    }
  end
end
