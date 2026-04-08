class Captain::Behavior::DedupService
  def initialize(assistant:, conversation:)
    @assistant = assistant
    @conversation = conversation
    @config = assistant.behavior['dedup'] || {}
    @ttl = (@config['ttl_seconds'] || 120).to_i
  end

  def duplicate?(content)
    return false unless @config['enabled']

    hash = Digest::MD5.hexdigest("#{@conversation.id}:#{content}")
    key = format(Redis::RedisKeys::CAPTAIN_DEDUP_KEY, assistant_id: @assistant.id, hash: hash)

    !Redis::Alfred.set(key, '1', nx: true, ex: @ttl)
  end
end
