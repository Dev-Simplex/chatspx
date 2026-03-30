class ApplicationCable::Connection < ActionCable::Connection::Base
  identified_by :pubsub_token

  def connect
    self.pubsub_token = verify_pubsub_token
  end

  private

  def verify_pubsub_token
    token = request.params[:pubsub_token]
    reject_unauthorized_connection if token.blank?
    token
  end
end
