# frozen_string_literal: true

# Soft-deletes a message the way edit works: the original content is preserved in
# `content_attributes['previous_content']` and `deleted`/`deleted_at`/`deleted_by`
# metadata is recorded, so the UI can show a "Mensagem apagada" placeholder plus a
# clickable badge revealing the original.
#
# The local soft-delete is permissive (any agent with access can delete, on any
# channel) — this preserves Chatwoot's historical behaviour. Only the WhatsApp
# delete-for-everyone propagation is gated: it fires solely for outgoing messages
# sent by the acting agent on a WAHA inbox. For non-WAHA channels — or WAHA messages
# that never reached WhatsApp (no resolvable id) — we still soft-delete locally.
# A hard WAHA API error aborts (mirrors edit) so the agent can retry.
class Messages::DeleteContentService
  include Messages::WahaMessageResolvable

  def initialize(message)
    @message = message
  end

  def perform
    validate!
    waha_message_id = propagate_to_waha? ? resolve_waha_message_id_safely : nil
    delete_on_waha(waha_message_id) if waha_message_id.present?
    persist_delete(waha_message_id)
    @message
  end

  private

  def validate!
    raise ArgumentError, 'Message has already been deleted' if @message.content_attributes['deleted']
  end

  def propagate_to_waha?
    waha_inbox? && @message.outgoing? && sent_by_current_user?
  end

  # Best-effort id resolution: a non-resolvable id (message never reached WhatsApp,
  # WAHA history lookup miss) must NOT block the local soft-delete.
  def resolve_waha_message_id_safely
    resolve_waha_message_id
  rescue ArgumentError => e
    Rails.logger.warn("[#{self.class.name}] Could not resolve WAHA message id (#{e.message}); soft-deleting locally only")
    nil
  end

  def delete_on_waha(waha_message_id)
    Waha::ApiService.new.delete_message(inbox.waha_session_name, chat_id, waha_message_id)
  rescue Waha::ApiService::Error => e
    raise ArgumentError, "WAHA API error: #{e.message}"
  end

  def persist_delete(waha_message_id)
    previous = @message.content
    actor = Current.user
    attrs = {
      content: I18n.t('conversations.messages.deleted'),
      content_type: :text,
      content_attributes: @message.content_attributes.merge(
        'previous_content' => previous,
        'deleted' => true,
        'deleted_at' => Time.zone.now.iso8601,
        'deleted_by' => actor ? { 'id' => actor.id, 'name' => actor.name } : nil
      )
    }
    # Persist the WAHA message ID we discovered so it is available downstream.
    attrs[:source_id] = waha_message_id if @message.source_id.blank? && waha_message_id.present?

    ActiveRecord::Base.transaction do
      @message.update!(attrs)
      @message.attachments.destroy_all
    end
  end
end
