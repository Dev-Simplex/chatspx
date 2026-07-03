# frozen_string_literal: true

# Kanban v2 (Fase 8) — public WorkForm endpoint. Unauthenticated: identifies the
# funnel by an unguessable token, then a submission becomes a contact +
# conversation + card. Rate-limited in config/initializers/rack_attack.rb.
class Public::Api::V1::FunnelFormsController < PublicController
  before_action :set_funnel

  # Public form config, so an external page can render the right fields.
  def show
    render json: {
      title: @funnel.form_title.presence || @funnel.name,
      fields: @funnel.funnel_custom_fields.ordered.map do |field|
        { key: field.key, label: field.label, field_type: field.field_type, options: field.options }
      end
    }
  end

  def create
    result = Kanban::PublicFormSubmissionService.new(funnel: @funnel, params: form_params).perform
    if result.ok?
      render json: { success: true }, status: :created
    else
      render json: { success: false, error: result.error }, status: :unprocessable_entity
    end
  end

  private

  def set_funnel
    @funnel = Funnel.for_form_token(params[:token])
    return if @funnel&.public_form_enabled?

    # Generic 404 — don't reveal whether a token exists.
    render json: { error: 'not_found' }, status: :not_found
  end

  def form_params
    params.permit(:name, :email, :phone, :phone_number, :message, custom_fields: {})
  end
end
