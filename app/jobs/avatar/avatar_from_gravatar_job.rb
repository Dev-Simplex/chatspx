class Avatar::AvatarFromGravatarJob < ApplicationJob
  queue_as :purgable

  ALLOWED_AVATARABLE_TYPES = %w[Contact User Inbox AgentBot].freeze

  def perform(avatarable_type, avatarable_id, email)
    return unless ALLOWED_AVATARABLE_TYPES.include?(avatarable_type)

    avatarable = avatarable_type.constantize.find_by(id: avatarable_id)
    return unless avatarable
    return if GlobalConfigService.load('DISABLE_GRAVATAR', '').present?
    return if email.blank?
    return if avatarable.avatar_url.present?

    hash = Digest::MD5.hexdigest(email)
    gravatar_url = "https://www.gravatar.com/avatar/#{hash}?d=404"
    Avatar::AvatarFromUrlJob.perform_later(avatarable_type, avatarable_id, gravatar_url)
  end
end
