# Initialize and validate the complete immutable scope identity together.
# rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
class Captain::Evidence::Scope
  attr_reader :account_id, :conversation_id, :assistant_id, :episode_key, :turn_id, :run_id, :assistant, :conversation
  attr_accessor :unavailable, :entity_id, :query_id, :publication_id, :unit_id

  def initialize(conversation:, assistant:)
    @conversation = conversation
    @assistant = assistant
    @account_id = conversation.account_id
    @conversation_id = conversation.id
    @assistant_id = assistant.id
    @run_id = SecureRandom.uuid
    raise ArgumentError, 'tenant mismatch' unless assistant.account_id == account_id

    boundary = Captain::Conversation::EpisodeBoundary.new(conversation: conversation).atual
    @episode_key = boundary&.first_message_id&.to_s
    @unavailable = @episode_key.blank?
    @episode_key ||= 'unavailable'
    incoming = conversation.messages.where(message_type: :incoming, private: false).order(:id).last
    @turn_id = incoming&.id&.to_s || 'none'
    ids = Captain::Evidence::ClaimExtractor.entity_ids(incoming&.content.to_s)
    @entity_id = ids.first if ids.size == 1
  end

  def identity
    { account_id: account_id, conversation_id: conversation_id, episode_key: episode_key }
  end

  def metadata
    identity.merge(captain_assistant_id: assistant_id, turn_id: turn_id, run_id: run_id)
  end

  def expiry(origin, now)
    seconds = assistant.config.dig('fact_guard', 'validity_seconds', origin).to_i
    seconds.positive? ? now + seconds.seconds : nil
  end
end
# rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
