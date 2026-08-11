# frozen_string_literal: true

# Kanban: colapso de cards duplicados do MESMO contato dentro de uma etapa,
# extraído do FunnelItemsController (que já delega bulk e cartões de tarefa a
# concerns). Um contato que fala pelo mesmo número em conversas diferentes não
# pode virar dois cards lado a lado na mesma coluna.
#
# ⚠️ O front espelha esta regra em `assignItemToStage`
# (store/modules/kanban/mutations.js), inclusive o 9º dígito BR, porque o card
# também chega pelo websocket (Kanban tempo real) e não só por este `index`.
# Mudou aqui, mude lá.
module Kanban::FunnelItemsDeduplication
  extend ActiveSupport::Concern

  private

  def deduplicate_by_contact_phone(items) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    return items if items.blank?

    by_stage_and_phone = {}
    items.each do |item|
      contact = item.conversation&.contact
      phone = contact&.phone_number
      normalized = normalize_brazilian_phone(phone)
      key = if item.conversation.nil?
              "item:#{item.id}" # cartão de tarefa: nunca deduplica
            elsif normalized.present?
              "phone:#{normalized}"
            elsif item.conversation&.contact_id.present?
              "contact:#{item.conversation.contact_id}"
            else
              "conversation:#{item.conversation_id}"
            end
      stage_key = "#{item.funnel_stage_id}-#{key}"

      existing = by_stage_and_phone[stage_key]
      recency = item.conversation&.last_activity_at || item.created_at || Time.zone.at(0)
      if existing.nil? || recency > (existing.conversation&.last_activity_at || existing.created_at || Time.zone.at(0))
        by_stage_and_phone[stage_key] = item
      end
    end
    by_stage_and_phone.values.sort_by { |i| i.moved_at || i.created_at }.reverse
  end

  def normalize_brazilian_phone(phone)
    digits = phone.to_s.gsub(/\D/, '')
    return nil if digits.blank?

    digits = "#{digits[0, 4]}9#{digits[4, 8]}" if digits.start_with?('55') && digits.length == 12
    digits.presence
  end
end
