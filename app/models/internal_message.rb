# frozen_string_literal: true

# == Schema Information
#
# Table name: internal_messages
#
#  id                  :bigint           not null, primary key
#  content             :text             not null
#  content_attributes  :jsonb            not null
#  deleted_at          :datetime
#  edited_at           :datetime
#  mentioned_user_ids  :jsonb            not null
#  message_type        :integer          default("text"), not null
#  reactions           :jsonb            not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  internal_channel_id :bigint           not null
#  user_id             :bigint
#
class InternalMessage < ApplicationRecord
  belongs_to :internal_channel, inverse_of: :messages
  # Aviso do sistema (message_type system) não tem autor.
  belongs_to :user, optional: true
  belongs_to :reply_to, class_name: 'InternalMessage', optional: true
  belongs_to :shared_conversation, class_name: 'Conversation', optional: true
  has_many_attached :attachments

  # Hard cap for a single internal-chat attachment (defense in depth — the
  # composer also checks this client-side before uploading).
  MAX_ATTACHMENT_SIZE = 100.megabytes

  # text: mensagem comum · request: pedido de aprovação/ajuda (cartão com botões,
  # dados em content_attributes['request']) · system: aviso automático, sem autor.
  enum message_type: { text: 0, request: 1, system: 2 }, _prefix: true

  REQUEST_KINDS = %w[approval help].freeze

  # Transient client-generated id echoed back so the sender can reconcile its
  # optimistic bubble with the persisted message (never stored — mirrors Message).
  attr_accessor :echo_id

  # Rich card preview of a shared customer conversation, or nil.
  def shared_conversation_preview
    return if shared_conversation.blank?

    {
      display_id: shared_conversation.display_id,
      status: shared_conversation.status,
      contact_name: shared_conversation.contact&.name,
      inbox_name: shared_conversation.inbox&.name
    }
  end

  # Compact preview of the quoted message (for reply bubbles), or nil.
  def reply_preview
    return if reply_to.blank?

    {
      id: reply_to.id,
      user_name: reply_to.user&.name,
      content: reply_to.deleted? ? nil : reply_to.content.to_s.truncate(120),
      deleted: reply_to.deleted?
    }
  end

  validates :content, presence: true, unless: -> { attachments.attached? || deleted? }
  validates :user, presence: true, unless: :message_type_system?
  validate :request_well_formed, if: :message_type_request?
  validate :attachments_within_size_limit

  scope :recent_first, -> { order(created_at: :desc) }

  def deleted?
    deleted_at.present?
  end

  def edited?
    edited_at.present?
  end

  def request_data
    content_attributes['request'] || {}
  end

  def request_pending?
    message_type_request? && !deleted? && request_data['status'] == 'pending'
  end

  # Aprovação: só a pessoa a quem o pedido foi endereçado. Ajuda: qualquer
  # membro do canal menos quem pediu.
  def can_decide?(user)
    return false unless request_pending?
    return request_data['approver_id'].to_i == user.id if request_data['kind'] == 'approval'

    user_id != user.id && internal_channel.members.exists?(user_id: user.id)
  end

  def mentions?(user)
    Array(mentioned_user_ids).map(&:to_i).include?(user.id)
  end

  # Soft-delete: keep the row (so it stays in the thread as "message deleted")
  # but drop the content and attachments.
  def soft_delete!
    attachments.purge_later
    update!(deleted_at: Time.current, content: '', mentioned_user_ids: [], reactions: {})
  end

  # Toggle an emoji reaction for a user. reactions = { emoji => [user_id, ...] }.
  def toggle_reaction!(emoji, user_id)
    data = reactions.deep_dup
    list = Array(data[emoji])
    if list.include?(user_id)
      list.delete(user_id)
    else
      list << user_id
    end
    list.empty? ? data.delete(emoji) : data[emoji] = list
    update!(reactions: data)
  end

  private

  # Aprovação precisa de alguém do canal (que não seja quem pede) para decidir.
  def request_well_formed
    errors.add(:content_attributes, 'invalid request kind') unless REQUEST_KINDS.include?(request_data['kind'])
    return unless request_data['kind'] == 'approval'

    approver_id = request_data['approver_id'].to_i
    valid = approver_id != user_id && internal_channel.members.exists?(user_id: approver_id)
    errors.add(:content_attributes, 'approver must be another member of the channel') unless valid
  end

  # Reject oversized attachments before they are persisted (the controller maps
  # ActiveRecord::RecordInvalid to a 422). Inspects the pending upload directly,
  # since a new record's blob byte_size isn't available until after save.
  def attachments_within_size_limit
    changes = attachment_changes['attachments']
    return if changes.blank?

    oversized = Array(changes.attachables).any? do |attachable|
      size = attachable.try(:size) || attachable.try(:byte_size)
      size.to_i > MAX_ATTACHMENT_SIZE
    end
    return unless oversized

    errors.add(:attachments, "must be smaller than #{MAX_ATTACHMENT_SIZE / 1.megabyte} MB")
  end
end
