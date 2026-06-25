# frozen_string_literal: true

class Api::V1::Accounts::FunnelsController < Api::V1::Accounts::BaseController
  before_action :funnel, except: [:index, :create, :templates, :create_from_template]
  before_action :check_authorization, except: [:index]

  def index
    authorize(Funnel.new(account: Current.account), :index?)
    Kanban::EnsureDefaultFunnelsService.new(account: Current.account).perform
    @funnels = policy_scope(Funnel).includes(:funnel_custom_fields).order(:position, :created_at)
  end

  def show; end

  def create
    @funnel = Current.account.funnels.create!(funnel_params)
  end

  def update
    @funnel.update!(funnel_params)
  end

  def destroy
    @funnel.destroy!
    head :ok
  end

  def reorder_stages
    stage_ids = Array(params[:stage_ids]).map { |id| id.to_s.to_i }.reject(&:zero?)
    Funnels::ReorderStagesService.new(funnel: @funnel, stage_ids: stage_ids).perform
    head :ok
  rescue StandardError => e
    Rails.logger.error "FunnelsController#reorder_stages: #{e.class} - #{e.message}"
    render json: { error: 'Error reordering stages', details: (Rails.env.development? ? e.message : nil) }, status: :internal_server_error
  end

  # Kanban v2 (Fase 8): the catalog of ready-made funnel templates.
  def templates
    render json: Kanban::EnsureFunnelTemplatesService.new.perform.map { |template| template_json(template) }
  end

  # Create a funnel for the account from a chosen template.
  def create_from_template
    template = FunnelTemplate.find_by(id: params[:template_id])
    return render json: { error: 'Template not found' }, status: :not_found if template.blank?

    @funnel = Kanban::CreateFunnelFromTemplateService.new(
      account: Current.account, template: template, name: params[:name]
    ).perform
    render :show, status: :created
  end

  # Kanban v2 (Fase 6): live operational stats for the in-board dashboard.
  def stats
    render json: Kanban::FunnelReportService.new(funnel: @funnel).perform.merge(baseline: baseline)
  end

  # Kanban v2 (Fase 8): enable/configure the public WorkForm; mints the token.
  def form
    @funnel.form_enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled])
    @funnel.form_inbox_id = params[:inbox_id].presence
    @funnel.form_title = params[:title].to_s.strip.presence
    @funnel.form_token = SecureRandom.hex(24) if @funnel.form_enabled && @funnel.form_token.blank?
    @funnel.save!
    render json: form_payload
  end

  private

  def template_json(template)
    {
      id: template.id,
      slug: template.slug,
      name: template.name,
      description: template.description,
      stages: template.stages.pluck('name')
    }
  end

  def form_payload
    {
      form_enabled: @funnel.public_form_enabled?,
      form_token: @funnel.form_token,
      form_inbox_id: @funnel.form_inbox_id,
      form_title: @funnel.form_title,
      form_url: (@funnel.form_token.presence && "#{ENV.fetch('FRONTEND_URL', '')}/public/api/v1/funnel_forms/#{@funnel.form_token}")
    }
  end

  # Most recent snapshot before today (yesterday's totals) for "vs" deltas.
  def baseline
    snapshot = @funnel.funnel_metric_snapshots.where(captured_on: ...Date.current).recent_first.first
    snapshot&.metrics&.dig('totals')
  end

  def funnel
    @funnel ||= policy_scope(Funnel).find(params[:id])
  end

  def funnel_params
    params.require(:funnel).permit(:name, :position, :color, :team_id, inbox_ids: [], settings: [:deadline_mode, :default_view])
  end

  def check_authorization
    authorize(@funnel || Funnel.new(account: Current.account))
  end
end
