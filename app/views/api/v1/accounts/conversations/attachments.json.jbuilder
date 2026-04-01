json.meta do
  json.total_count @attachments_count
  json.current_page @attachments.current_page
  json.total_pages @attachments.total_pages
end

json.payload @attachments do |attachment|
  attachment_data = attachment.push_event_data

  json.id attachment.id
  json.message_id attachment_data[:message_id]
  json.thumb_url attachment_data[:thumb_url]
  json.data_url attachment_data[:data_url]
  json.file_size attachment_data[:file_size]
  json.file_type attachment_data[:file_type]
  json.extension attachment_data[:extension]
  json.width attachment_data[:width]
  json.height attachment_data[:height]
  json.filename attachment.file.attached? ? attachment.file.filename.to_s : nil
  json.created_at attachment.message.created_at.to_i
  json.sender attachment.message.sender.push_event_data if attachment.message.sender
end
