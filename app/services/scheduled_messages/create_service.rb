# frozen_string_literal: true

class ScheduledMessages::CreateService
  attr_reader :conversation, :inbox, :message_content, :scheduled_at, :user, :attachments, :template_params

  def initialize(conversation:, inbox:, message:, scheduled_at:, user: nil, attachments: [], template_params: nil) # rubocop:disable Metrics/ParameterLists
    @conversation = conversation
    @inbox = inbox
    @message_content = message
    @scheduled_at = scheduled_at
    @user = user || Current.user
    @attachments = attachments
    @template_params = template_params

    validate_inputs!
  end

  def perform # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
    scheduled_at_time = parse_scheduled_at
    validate_scheduled_at!(scheduled_at_time)

    inbox_to_use = conversation.inbox

    scheduled_message_params = {
      conversation: conversation,
      inbox: inbox_to_use,
      scheduled_at: scheduled_at_time,
      status: :pending
    }
    scheduled_message_params[:account_id] = conversation.account_id if ScheduledMessage.column_names.include?('account_id')
    scheduled_message_params[:message] = (message_content.presence || '').to_s if ScheduledMessage.column_names.include?('message')
    scheduled_message_params[:scheduled_by] = user if ScheduledMessage.column_names.include?('scheduled_by_id')
    scheduled_message_params[:template_params] = template_params if template_params.present? && ScheduledMessage.column_names.include?('template_params')

    scheduled_message = ScheduledMessage.new(scheduled_message_params)

    attachable = normalize_attachments(attachments)
    if attachable.present?
      begin
        scheduled_message.attachments.attach(attachable)
      rescue StandardError => e
        Rails.logger.error "ScheduledMessages::CreateService: attach failed: #{e.class}: #{e.message}"
        Rails.logger.error e.backtrace.first(5).join("\n")
        raise ArgumentError, "Error attaching files: #{e.message}"
      end
    end

    scheduled_message.save!

    begin
      ScheduledMessages::SendJob.set(wait_until: scheduled_at_time).perform_later(scheduled_message.id)
    rescue StandardError => e
      Rails.logger.error "ScheduledMessages::CreateService: job enqueue falhou: #{e.class}: #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    scheduled_message
  rescue ActiveRecord::RecordInvalid => e
    raise ArgumentError, "Validation error: #{e.record.errors.full_messages.join(', ')}"
  end

  private

  def validate_inputs! # rubocop:disable Metrics/CyclomaticComplexity
    raise ArgumentError, 'User is required' if user.nil?
    raise ArgumentError, 'Conversation is required' if conversation.nil?
    raise ArgumentError, 'Inbox is required' if inbox.nil?
    raise ArgumentError, 'Inbox does not belong to the conversation account' unless inbox.account_id == conversation.account_id
    raise ArgumentError, 'Text or at least one attachment is required' if message_content.blank? && !attachments_present?
    raise ArgumentError, 'Scheduled_at is required' if scheduled_at.blank?
  end

  def parse_scheduled_at
    result = if scheduled_at.is_a?(String)
               Time.zone.parse(scheduled_at)
             else
               scheduled_at
             end
    raise ArgumentError, "Invalid date/time: #{scheduled_at}" unless result.is_a?(Time) || result.is_a?(ActiveSupport::TimeWithZone)

    result
  rescue ArgumentError => e
    raise ArgumentError, "Invalid date/time: #{scheduled_at}. Error: #{e.message}"
  end

  def validate_scheduled_at!(scheduled_at_time)
    # Allow 2-minute tolerance in the past to account for clock drift or timezone differences.
    raise ArgumentError, 'Scheduled date/time must be in the future' if scheduled_at_time <= 2.minutes.ago
  end

  def attachments_present?
    Array(attachments).any?(&:present?)
  end

  # Keep only what Active Storage accepts: String (signed_id) or UploadedFile (multipart).
  # Discards empty hashes, nils, and any other types.
  def normalize_attachments(attachments_param)
    return [] if attachments_param.blank?

    Array(attachments_param).compact.select do |a|
      a.is_a?(String) || a.respond_to?(:tempfile)
    end
  end
end
