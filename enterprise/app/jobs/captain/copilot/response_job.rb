require 'timeout'

class Captain::Copilot::ResponseJob < ApplicationJob
  queue_as :high
  COPILOT_RESPONSE_TIMEOUT_SECONDS = 30

  def perform(assistant:, conversation_id:, user_id:, copilot_thread_id:, message:, copilot_message_id: nil)
    started_at = monotonic_time
    generate_chat_response_with_timeout(
      assistant: assistant,
      conversation_id: conversation_id,
      user_id: user_id,
      copilot_thread_id: copilot_thread_id,
      message: message
    )
    log_job_outcome(
      outcome: 'success',
      assistant_id: assistant.id,
      account_id: assistant.account_id,
      user_id: user_id,
      copilot_thread_id: copilot_thread_id,
      copilot_message_id: copilot_message_id,
      started_at: started_at
    )
  rescue Llm::Config::MissingAccountApiKeyError => e
    log_job_outcome(
      outcome: 'missing_api_key',
      assistant_id: assistant.id,
      account_id: assistant.account_id,
      user_id: user_id,
      copilot_thread_id: copilot_thread_id,
      copilot_message_id: copilot_message_id,
      started_at: started_at,
      error: e
    )
    create_fallback_message(
      copilot_thread_id: copilot_thread_id,
      copilot_message_id: copilot_message_id,
      content: I18n.t('captain.errors.missing_api_key')
    )
  rescue Timeout::Error => e
    log_job_outcome(
      outcome: 'timeout',
      assistant_id: assistant.id,
      account_id: assistant.account_id,
      user_id: user_id,
      copilot_thread_id: copilot_thread_id,
      copilot_message_id: copilot_message_id,
      started_at: started_at,
      error: e
    )
    create_fallback_message(
      copilot_thread_id: copilot_thread_id,
      copilot_message_id: copilot_message_id,
      content: I18n.t('captain.copilot.timeout')
    )
  rescue StandardError => e
    log_job_outcome(
      outcome: 'failure',
      assistant_id: assistant.id,
      account_id: assistant.account_id,
      user_id: user_id,
      copilot_thread_id: copilot_thread_id,
      copilot_message_id: copilot_message_id,
      started_at: started_at,
      error: e
    )
    create_fallback_message(
      copilot_thread_id: copilot_thread_id,
      copilot_message_id: copilot_message_id,
      content: I18n.t('captain.copilot.failure')
    )
  end

  private

  def generate_chat_response_with_timeout(**kwargs)
    Timeout.timeout(COPILOT_RESPONSE_TIMEOUT_SECONDS) do
      generate_chat_response(**kwargs)
    end
  end

  def generate_chat_response(assistant:, conversation_id:, user_id:, copilot_thread_id:, message:)
    service = Captain::Copilot::ChatService.new(
      assistant,
      user_id: user_id,
      copilot_thread_id: copilot_thread_id,
      conversation_id: conversation_id
    )
    # When using copilot_thread, message is already in previous_history
    # Pass nil to avoid duplicate
    service.generate_response(copilot_thread_id.present? ? nil : message)
  end

  def create_fallback_message(copilot_thread_id:, copilot_message_id:, content:)
    thread = CopilotThread.find_by(id: copilot_thread_id)
    return if thread.blank?
    return if assistant_message_already_present?(thread: thread, copilot_message_id: copilot_message_id)

    thread.copilot_messages.create!(
      message_type: :assistant,
      message: {
        content: content
      }
    )
  end

  def assistant_message_already_present?(thread:, copilot_message_id:)
    return false if copilot_message_id.blank?

    thread.copilot_messages
          .assistant
          .where('id > ?', copilot_message_id)
          .exists?
  end

  def log_job_outcome(
    outcome:,
    assistant_id:,
    account_id:,
    user_id:,
    copilot_thread_id:,
    copilot_message_id:,
    started_at:,
    error: nil
  )
    duration_ms = ((monotonic_time - started_at) * 1000).round
    log_message = "#{self.class.name} outcome=#{outcome} " \
                  "assistant_id=#{assistant_id} account_id=#{account_id} user_id=#{user_id} " \
                  "copilot_thread_id=#{copilot_thread_id} copilot_message_id=#{copilot_message_id} " \
                  "duration_ms=#{duration_ms}"
    log_message += " error_class=#{error.class.name} error_message=#{error.message}" if error

    if error
      Rails.logger.warn(log_message)
    else
      Rails.logger.info(log_message)
    end
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
