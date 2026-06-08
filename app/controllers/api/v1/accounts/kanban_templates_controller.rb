# frozen_string_literal: true

# KANBAN-P2-01: lista templates oficiais (e da conta) + aplica template
# criando 1 Kanban + N KanbanStages.
class Api::V1::Accounts::KanbanTemplatesController < Api::V1::Accounts::BaseController
  before_action :template, only: [:show, :apply]

  def index
    @templates = KanbanTemplate
                 .where('is_official = ? OR account_id = ?', true, Current.account.id)
                 .ordered
  end

  def show; end

  def apply
    kanban = Kanbans::ApplyTemplateService.new(
      account: Current.account,
      template: @template,
      options: template_options,
      user: Current.user
    ).perform

    @kanban = kanban
    render 'api/v1/accounts/kanbans/show', formats: [:json]
  end

  private

  def template
    @template = KanbanTemplate.where('is_official = ? OR account_id = ?', true, Current.account.id)
                              .find(params[:id])
  end

  def template_options
    params.permit(:name, :description, :color, :team_id, inbox_ids: []).to_h
  end
end
