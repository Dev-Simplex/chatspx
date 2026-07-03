json.array! @message_sequences do |message_sequence|
  json.partial! 'message_sequence', message_sequence: message_sequence
end
