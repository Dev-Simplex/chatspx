class BulkActionsJob < ApplicationJob
  include DateRangeHelper

  queue_as :medium
  retry_on StandardError, wait: :polynomially_longer, attempts: 3
  discard_on ActiveJob::DeserializationError
  attr_accessor :records

  MODEL_TYPE = ['Conversation'].freeze

  def perform(account_id:, params:, user_id:)
    @account = Account.find_by(id: account_id)
    return unless @account

    user = User.find_by(id: user_id)
    return unless user

    Current.user = user
    @params = params
    @records = records_to_updated(params[:ids])
    bulk_update
  ensure
    Current.reset
  end

  def bulk_update
    bulk_remove_labels
    bulk_conversation_update
  end

  def bulk_conversation_update
    params = available_params(@params)
    records.each do |conversation|
      bulk_add_labels(conversation)
      bulk_snoozed_until(conversation)

      next if resolution_blocked?(conversation, params)
      next if takeover_blocked?(conversation, params)

      conversation.update(params) if params
    end
  end

  # D1 (Fase 3) — guard (b): o bulk tem porta PRÓPRIA (seta Current.user e faz
  # update(params) com assignee_id), então não passa pelo assignments_controller.
  # Guard irmão do resolution_blocked? logo abaixo.
  #
  # NÃO cria pedidos em massa de propósito: 500 conversas selecionadas viraria
  # 500 pedidos = DoS social no dono. Aqui só pula e loga.
  def takeover_blocked?(conversation, params)
    return false unless params && params[:assignee_id].present?

    blocked = Conversations::TakeoverGate.new(
      conversation: conversation,
      actor: Current.user,
      new_assignee_id: params[:assignee_id]
    ).blocked?
    Rails.logger.warn("Skipping assignment of conversation #{conversation.id} - takeover request required") if blocked
    blocked
  end

  # Guards that prevent a resolve from being applied during a bulk update.
  def resolution_blocked?(conversation, params)
    return false unless params && params[:status] == 'resolved'

    # A team is required before a conversation can be resolved.
    if conversation.team_id.blank?
      Rails.logger.warn("Skipping resolution of conversation #{conversation.id} - team required")
      return true
    end

    # "Atribuição obrigatória" mode: only the assignee may resolve. The frontend
    # self-assigns before this runs; we enforce it here too so the API can't be bypassed.
    if resolve_assignment_blocked?(conversation, params)
      Rails.logger.warn("Skipping resolution of conversation #{conversation.id} - assignment required")
      return true
    end

    false
  end

  def resolve_assignment_blocked?(conversation, params)
    return false unless @account.resolve_assignment_gate_enabled?

    # Allow when the same payload reassigns the conversation to the acting user.
    return false if params[:assignee_id].present? && params[:assignee_id].to_i == Current.user&.id

    conversation.assignee_id != Current.user&.id
  end

  def bulk_remove_labels
    records.each do |conversation|
      remove_labels(conversation)
    end
  end

  def available_params(params)
    return unless params[:fields]

    params[:fields].delete_if { |key, value| value.nil? && key == 'status' }
  end

  def bulk_add_labels(conversation)
    conversation.add_labels(@params[:labels][:add]) if @params[:labels] && @params[:labels][:add]
  end

  def bulk_snoozed_until(conversation)
    conversation.snoozed_until = parse_date_time(@params[:snoozed_until].to_s) if @params[:snoozed_until]
  end

  def remove_labels(conversation)
    return unless @params[:labels] && @params[:labels][:remove]

    labels = conversation.label_list - @params[:labels][:remove]
    conversation.update(label_list: labels)
  end

  def records_to_updated(ids)
    current_model = @params[:type].camelcase
    return unless MODEL_TYPE.include?(current_model)

    current_model.constantize&.where(account_id: @account.id, display_id: ids)
                 &.includes(:inbox, :contact, :team, :assignee, :account)
  end
end
