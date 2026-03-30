json.meta do
  json.count @contacts_count
  json.current_page @current_page
end

json.payload do
  json.array! @contacts do |contact|
    json.additional_attributes contact.additional_attributes
    json.availability_status contact.availability_status
    json.email contact.email
    json.id contact.id
    json.name contact.name
    json.phone_number contact.phone_number
    json.blocked contact.blocked
    json.identifier contact.identifier
    json.thumbnail contact.avatar_url
    json.custom_attributes contact.custom_attributes
    json.last_activity_at contact.last_activity_at.to_i if contact[:last_activity_at].present?
    json.created_at contact.created_at.to_i if contact[:created_at].present?
    if @include_contact_inboxes.present?
      json.contact_inboxes do
        json.array! contact.contact_inboxes do |contact_inbox|
          json.source_id contact_inbox.source_id
          json.inbox do
            inbox = contact_inbox.inbox
            json.id inbox.id
            json.avatar_url inbox.try(:avatar_url)
            json.channel_id inbox.channel_id
            json.name inbox.name
            json.channel_type inbox.channel_type
            json.provider inbox.channel.try(:provider)
          end
        end
      end
    end
  end
end
