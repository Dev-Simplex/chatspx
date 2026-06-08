# frozen_string_literal: true

# KANBAN-P3-04: agrega métricas e envia mensagem-resumo via WhatsApp.
# - Lê config em `kanban.settings.daily_summary` (enabled, recipient_phone,
#   inbox_id, time_local).
# - Métricas: total_cards, new_leads, moved, won_yesterday, lost_yesterday,
#   aging_critical (5+ dias).
# - Envio: cria mensagem outgoing na inbox configurada. Webhook do canal
#   processa o envio real (mesmo padrão das outras integrações).
#
# Retorna { ok: true, message_id: } ou { ok: false, error: }
class Kanbans::DailySummaryService
  AGING_CRITICAL_DAYS = 5

  attr_reader :kanban, :user

  def initialize(kanban:, user: nil)
    @kanban = kanban
    @user = user
  end

  def perform
    cfg = (kanban.settings || {})['daily_summary'] || {}
    return { ok: false, error: 'disabled' } unless ActiveModel::Type::Boolean.new.cast(cfg['enabled'])

    phone = cfg['recipient_phone'].to_s
    return { ok: false, error: 'no_recipient' } if phone.blank?

    inbox = find_inbox(cfg['inbox_id'])
    return { ok: false, error: 'no_inbox' } if inbox.blank?

    text = build_summary_text
    conversation = ensure_conversation(inbox, phone)
    message = create_message(conversation, text)
    { ok: true, message_id: message.id }
  rescue StandardError => e
    Rails.logger.tagged('kanban-summary').error("perform failed: #{e.class} #{e.message}")
    { ok: false, error: e.message }
  end

  def self.call(**)
    new(**).perform
  end

  def metrics
    @metrics ||= compute_metrics
  end

  def build_summary_text
    m = metrics
    template = ((kanban.settings || {})['daily_summary'] || {})['template'].presence || default_template
    template
      .gsub('{total_cards}', m[:total_cards].to_s)
      .gsub('{new_leads}', m[:new_leads].to_s)
      .gsub('{moved}', m[:moved].to_s)
      .gsub('{won_yesterday}', m[:won_yesterday].to_s)
      .gsub('{lost_yesterday}', m[:lost_yesterday].to_s)
      .gsub('{aging_critical}', m[:aging_critical].to_s)
  end

  private

  def default_template
    <<~MSG
      Bom dia! Resumo de hoje:
      • {total_cards} cards ativos
      • {new_leads} novos leads
      • {moved} movimentações
      • {won_yesterday} fechados ontem · {lost_yesterday} perdidos
      • {aging_critical} cards parados (5+ dias)
    MSG
  end

  def compute_metrics # rubocop:disable Metrics/AbcSize
    active = kanban.kanban_items.joins(:kanban_stage).where(kanban_stages: { won_loss_type: nil })
    yesterday = 1.day.ago.all_day
    won_y = kanban.kanban_items.joins(:kanban_stage)
                  .where(kanban_stages: { won_loss_type: 'won' })
                  .where(last_stage_change_at: yesterday).count
    lost_y = kanban.kanban_items.joins(:kanban_stage)
                   .where(kanban_stages: { won_loss_type: 'loss' })
                   .where(last_stage_change_at: yesterday).count

    {
      total_cards: active.count,
      new_leads: kanban.kanban_items.where(created_at: yesterday).count,
      moved: kanban.kanban_items.where(last_stage_change_at: yesterday).count,
      won_yesterday: won_y,
      lost_yesterday: lost_y,
      aging_critical: active.where('aging_days >= ?', AGING_CRITICAL_DAYS).count
    }
  end

  def find_inbox(inbox_id)
    return nil if inbox_id.blank?

    kanban.account.inboxes.find_by(id: inbox_id)
  end

  def ensure_conversation(inbox, phone) # rubocop:disable Metrics/AbcSize
    normalized = phone.to_s.gsub(/\D/, '')
    contact = kanban.account.contacts.find_or_create_by(phone_number: "+#{normalized}") do |c|
      c.name = 'Resumo pipeline'
    end
    inbox_contact = inbox.contact_inboxes.find_or_create_by(contact_id: contact.id) do |cic|
      cic.source_id = normalized
    end

    conv = kanban.account.conversations
                 .where(inbox_id: inbox.id, contact_id: contact.id)
                 .order(created_at: :desc)
                 .first
    return conv if conv

    Conversation.create!(
      account_id: kanban.account_id,
      inbox_id: inbox.id,
      contact_id: contact.id,
      contact_inbox_id: inbox_contact.id,
      status: :open
    )
  end

  def create_message(conversation, content)
    params = ActionController::Parameters.new(
      content: content,
      message_type: 'outgoing',
      private: false,
      content_attributes: { sent_from: 'kanban_daily_summary' }
    )
    Messages::MessageBuilder.new(user, conversation, params).perform
  end
end
