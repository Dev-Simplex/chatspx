json.id message.id
json.content message.content
json.inbox_id message.inbox_id
json.echo_id message.echo_id if message.echo_id
json.conversation_id message.conversation.display_id
json.message_type message.message_type_before_type_cast
json.content_type message.content_type
json.status message.status
json.content_attributes message.content_attributes
json.created_at message.created_at.to_i
json.private message.private
json.source_id message.source_id
json.team_id message.team_id
json.agent_id message.agent_id
json.sender message.sender.push_event_data if message.sender
json.attachments message.attachments.map(&:push_event_data) if message.attachments.present?
json.additional_attributes message.additional_attributes
json.starred message.starred?

# PR 0.1 — hardening: expose forwarded fields via REST (already broadcast via push_event_data).
# Defensive `has_attribute?` mirrors Message#push_event_data so the partial keeps working in
# environments where the AddForwardedToMessages migration has not run yet.
json.forwarded message.forwarded if message.has_attribute?(:forwarded)
json.forwarded_from_message_id message.forwarded_from_message_id if message.has_attribute?(:forwarded_from_message_id)
# PR B1 — Reactions: aggregated `{emoji => count}` map exposed to the panel/mobile.
# `respond_to?(:reactions)` keeps the partial resilient if the association is
# ever removed (defensive — mirrors the pattern for forwarded fields above).
json.reactions message.reactions.group_by(&:emoji).transform_values(&:count) if message.respond_to?(:reactions)
