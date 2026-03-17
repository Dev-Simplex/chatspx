module ConversationMuteHelpers
  extend ActiveSupport::Concern

  def mute!
    return unless contact

    resolved!
    contact.update(blocked: true)
    resolve_all_open_conversations_for_contact
    create_muted_message
  end

  def unmute!
    return unless contact

    contact.update(blocked: false)
    create_unmuted_message
  end

  def muted?
    contact&.blocked? || false
  end

  private

  def resolve_all_open_conversations_for_contact
    contact.conversations.open.where(account_id: account_id).find_each do |conv|
      next if conv.id == id

      conv.skip_team_required_for_resolution_validation = true
      conv.resolved!
    end
  end
end
