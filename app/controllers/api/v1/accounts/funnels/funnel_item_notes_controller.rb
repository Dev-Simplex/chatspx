# frozen_string_literal: true

# Kanban v2 (Fase 4) — internal notes on a card. Nested under funnel_items:
# /api/v1/accounts/:account_id/funnels/:funnel_id/funnel_items/:funnel_item_id/notes
class Api::V1::Accounts::Funnels::FunnelItemNotesController < Api::V1::Accounts::BaseController
  before_action :funnel
  before_action :funnel_item
  before_action :note, only: [:destroy]
  before_action :check_authorization

  def index
    @notes = @funnel_item.funnel_item_notes.includes(:user).recent_first
  end

  def create
    @note = @funnel_item.funnel_item_notes.new(content: note_content)
    @note.user = Current.user
    @note.save!
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @note.destroy!
    head :ok
  end

  private

  def funnel
    @funnel ||= policy_scope(Funnel).find(params[:funnel_id])
  end

  def funnel_item
    @funnel_item ||= funnel.funnel_items.find(params[:funnel_item_id])
  end

  def note
    @note ||= @funnel_item.funnel_item_notes.find(params[:id])
  end

  def note_content
    params.dig(:funnel_item_note, :content) || params[:content]
  end

  def check_authorization
    authorize(@note || FunnelItemNote.new(funnel_item: @funnel_item))
  end
end
