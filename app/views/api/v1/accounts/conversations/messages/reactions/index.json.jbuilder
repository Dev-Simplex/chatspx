# Aggregated reactions payload — grouped by emoji to keep the wire format flat
# and cheap to render in the panel/mobile (a single map keyed by emoji).
# `users` is an array of `{id, type, name}` ordered by `created_at`.
grouped = @reactions.group_by(&:emoji)

json.payload do
  json.array! grouped.map { |emoji, rows| [emoji, rows] } do |(emoji, rows)|
    json.emoji emoji
    json.count rows.size
    json.users rows do |row|
      json.id row.user_id
      json.type row.user_type
      json.name row.user_display_name
    end
  end
end

# Convenience: also expose the flat `{emoji => count}` map already used in the
# `_message.json.jbuilder` partial. Mobile clients can consume either shape.
json.counts grouped.transform_values(&:size)
