json.meta do
  json.total_count @attachments_count
  json.current_page @attachments.current_page
  json.total_pages @attachments.total_pages
end

json.payload @attachments do |attachment|
  json.partial! 'api/v1/models/attachment', formats: [:json], attachment: attachment
  json.filename attachment.file.attached? ? attachment.file.filename.to_s : nil
end
