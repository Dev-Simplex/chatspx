json.meta do
  json.count @schedule_contacts_count
  json.current_page @schedule_current_page
  json.per_page @schedule_per_page
end

json.payload do
  json.array! @schedule_contacts do |entry|
    contact = entry[:contact]
    primary_conversation = entry[:primary_conversation]
    recommended_inbox = entry[:recommended_inbox]

    json.id contact.id
    json.name contact.name
    json.email contact.email
    json.identifier contact.identifier
    json.phone_number contact.phone_number
    json.thumbnail contact.avatar_url

    json.primary_conversation do
      if primary_conversation.present?
        json.id primary_conversation.id
        json.display_id primary_conversation.display_id
        json.inbox_id primary_conversation.inbox_id
        json.last_activity_at primary_conversation.last_activity_at&.iso8601
      else
        json.null!
      end
    end

    json.recommended_inbox do
      if recommended_inbox.present?
        json.id recommended_inbox.id
        json.name recommended_inbox.name
      else
        json.null!
      end
    end
  end
end
