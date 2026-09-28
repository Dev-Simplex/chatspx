json.id suggestion.id
json.content suggestion.content
json.status suggestion.status
json.created_at suggestion.created_at.to_i

if suggestion.media.attached?
  json.media_url url_for(suggestion.media)
  json.media_filename suggestion.media.filename.to_s
end
