# frozen_string_literal: true

# Kanban v2 (Fase 2) — CRUD of per-funnel custom field DEFINITIONS.
# Nested under funnels: /api/v1/accounts/:account_id/funnels/:funnel_id/custom_fields
class Api::V1::Accounts::Funnels::CustomFieldsController < Api::V1::Accounts::BaseController
  before_action :funnel
  before_action :custom_field, except: [:index, :create]
  before_action :check_authorization

  def index
    @custom_fields = funnel.funnel_custom_fields.ordered
  end

  def show; end

  def create
    @custom_field = funnel.funnel_custom_fields.build(custom_field_params)
    @custom_field.save!
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def update
    @custom_field.update!(custom_field_params)
    render :show
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @custom_field.destroy!
    head :ok
  end

  private

  def funnel
    return @funnel if defined?(@funnel)

    @funnel = policy_scope(Funnel).find_by(id: params[:funnel_id])
    render json: { error: 'Funnel not found' }, status: :not_found unless @funnel
    @funnel
  end

  def custom_field
    @custom_field ||= funnel&.funnel_custom_fields&.find(params[:id])
  end

  def custom_field_params
    params.require(:custom_field).permit(:key, :label, :field_type, :position, :show_on_card, options: {})
  end

  def check_authorization
    return if performed? || funnel.blank?

    authorize(@custom_field || FunnelCustomField.new(funnel: funnel))
  end
end
