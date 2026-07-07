# frozen_string_literal: true

# Turns an incoming WAHA `poll.vote` event into a normal incoming message on the
# conversation that originally received the poll.
#
# Background: interactive menus are sent as native WhatsApp polls (see
# Waha::OutboundSpecialMessageService). When the customer taps an option, WhatsApp
# emits an (encrypted) poll vote; WAHA decrypts it and posts a `poll.vote` webhook
# carrying the original poll message id + the selected option(s). The external
# WAHA "chatwoot" app only mirrors plain messages, so votes would otherwise never
# reach the agent. This service closes that gap.
#
# WAHA `poll.vote` payload (defensive — shape varies by engine/version):
#   { vote: { id, from, fromMe, selectedOptions: [String|{name}] },
#     poll: { id } }                # poll.id == the WAMID we stored on Message#source_id
class Waha::PollVoteService
  def initialize(session_name:, payload:)
    @session_name = session_name
    @payload = (payload || {}).with_indifferent_access
  end

  def perform
    Rails.logger.info("[Waha::PollVoteService] session=#{@session_name} payload=#{@payload.to_h.inspect}")

    return if poll_message_id.blank?

    poll_message = find_poll_message
    return log_miss('poll message not found for source_id') if poll_message.nil?

    conversation = poll_message.conversation
    return log_miss('poll message has no conversation') if conversation.nil?

    label = selected_label(poll_message)
    return log_miss('vote carried no selected option') if label.blank?

    return if duplicate_vote?

    inject_vote(conversation, poll_message, label)
  end

  private

  def vote
    @payload[:vote] || {}
  end

  def poll
    @payload[:poll] || {}
  end

  # The original poll's WAMID. WAHA usually nests it under payload.poll.id; some
  # shapes expose it on the vote instead.
  def poll_message_id
    poll[:id].presence || vote.dig(:poll, :id).presence || vote[:pollId].presence
  end

  # Find the poll Message we sent. WhatsApp references the poll by a WAMID whose
  # CHAT part may differ from what we stored (it arrives in @lid form —
  # "true_<lid>@lid_<MSGID>" — while we store the @c.us form
  # "true_<phone>@c.us_<MSGID>"). The trailing <MSGID> is identical, so we match
  # exact first, then fall back to the stable message-id suffix.
  def find_poll_message
    exact = Message.find_by(source_id: poll_message_id)
    return exact if exact

    wamid = bare_message_id
    return nil if wamid.blank?

    Message.where('source_id LIKE ?', "%#{wamid}")
           .where(content_type: 'input_select')
           .order(id: :desc)
           .find { |m| m.source_id.to_s.end_with?(wamid) }
  end

  # The bare WhatsApp message id (no chat prefix). Prefer the explicit
  # pollCreationMessageKey.ID from the raw _data (unambiguous), then fall back to
  # the last "_"-delimited segment of the poll WAMID.
  def bare_message_id
    raw = @payload.dig(:_data, :Message, :pollUpdateMessage, :pollCreationMessageKey, :ID).presence
    return raw if raw

    tail = poll_message_id.to_s.split('_').last
    tail if tail.present? && tail != poll_message_id.to_s
  end

  # The vote's own WAMID — used to dedupe repeated webhook deliveries.
  def vote_id
    vote[:id].presence || @payload[:id].presence
  end

  def selected_options
    Array(vote[:selectedOptions] || vote[:selected_options]).map { |opt| option_text(opt) }.compact_blank
  end

  def option_text(opt)
    return opt.to_s.strip if opt.is_a?(String) || opt.is_a?(Numeric)
    return '' unless opt.is_a?(Hash)

    o = opt.with_indifferent_access
    (o[:name] || o[:title] || o[:optionName] || o[:localId]).to_s.strip
  end

  # Resolve the raw selected values against the poll's original option titles when
  # possible (handles engines that return an index/id instead of the text), then
  # join. Falls back to the raw values.
  def selected_label(poll_message)
    titles = poll_item_titles(poll_message)
    resolved = selected_options.map { |value| match_title(value, titles) }
    resolved.compact_blank.uniq.join(', ')
  end

  def match_title(value, titles)
    return value if titles.include?(value)

    # numeric/index fallback: "0" / "1" → nth option
    idx = Integer(value, exception: false)
    return titles[idx] if idx && titles[idx].present?

    value
  end

  def poll_item_titles(poll_message)
    items = poll_message.content_attributes&.dig('items') || poll_message.content_attributes&.dig(:items)
    Array(items).map { |i| (i['title'] || i[:title]).to_s.strip }.compact_blank
  end

  def voter
    (vote[:from] || vote[:participant]).to_s
  end

  def duplicate_vote?
    return false if vote_id.blank?

    Message.find_by(source_id: vote_id).present?
  end

  # WhatsApp lets a voter CHANGE their answer, firing a new poll.vote each time.
  # To avoid flooding the conversation with one message per tap, we keep a single
  # answer message per (poll, voter) and update it in place to the latest choice
  # (the in-place update still broadcasts via MESSAGE_UPDATED).
  def inject_vote(conversation, poll_message, label)
    attrs = { 'poll_message_id' => poll_message.id, 'selected_options' => selected_options, 'voter' => voter }
    existing = latest_vote_message(conversation, poll_message)

    if existing
      update_vote(existing, label, attrs, poll_message)
    else
      create_vote(conversation, label, attrs, poll_message)
    end
  end

  def update_vote(existing, label, attrs, poll_message)
    return if existing.content == label # same choice re-sent → no-op (no noisy re-broadcast)

    existing.update!(
      content: label,
      source_id: vote_id.presence,
      content_attributes: (existing.content_attributes || {}).merge('poll_vote' => attrs)
    )
    Rails.logger.info("[Waha::PollVoteService] updated vote -> '#{label}' on msg #{existing.id} (poll #{poll_message.id})")
  end

  def create_vote(conversation, label, attrs, poll_message)
    Messages::MessageBuilder.new(
      nil, conversation,
      {
        content: label,
        message_type: :incoming,
        source_id: vote_id.presence,
        content_attributes: { poll_vote: attrs }
      }
    ).perform
    Rails.logger.info("[Waha::PollVoteService] injected vote '#{label}' into conv #{conversation.id} (poll msg #{poll_message.id})")
  end

  # The current answer message for this poll + voter, if any. Ruby-side match
  # keeps it DB-agnostic across the jsonb content_attributes.
  def latest_vote_message(conversation, poll_message)
    conversation.messages.incoming
                .where('content_attributes::text LIKE ?', '%poll_vote%')
                .order(id: :desc)
                .find do |m|
      pv = m.content_attributes&.dig('poll_vote') || {}
      pv['poll_message_id'].to_s == poll_message.id.to_s && pv['voter'].to_s == voter
    end
  end

  def log_miss(reason)
    Rails.logger.info("[Waha::PollVoteService] skipped: #{reason} (poll_id=#{poll_message_id.inspect})")
    nil
  end
end
