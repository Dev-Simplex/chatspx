class Messages::StatusUpdateService
  attr_reader :message, :status, :external_error

  def initialize(message, status, external_error = nil)
    @message = message
    @status = status
    @external_error = external_error
  end

  def perform
    return false unless valid_status_transition?

    update_message_status
  end

  private

  def update_message_status
    # Update status and set external_error only when failed
    message.update!(
      status: status,
      external_error: (status == 'failed' ? external_error : nil)
    )
  end

  def valid_status_transition?
    return false unless Message.statuses.key?(status)

    # Don't allow changing from 'read' to 'delivered'
    return false if message.read? && status == 'delivered'

    # A message already confirmed delivered/read must never be flipped to
    # 'failed'. The WAHA app (Option A of the silent-failure fix) reports real
    # send failures via this endpoint; a late/racing failure report must not
    # override a delivery that demonstrably happened. Keeps the failed state
    # truthful and prevents flapping.
    return false if (message.delivered? || message.read?) && status == 'failed'

    true
  end
end
