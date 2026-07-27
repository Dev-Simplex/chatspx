# frozen_string_literal: true

# Limpeza do seed de QA da secao "Midia, links e docs".
# Remove SOMENTE as mensagens marcadas com content_attributes['seed']='nps345_media'
# na conversa da contato "NPS Sim invalid2" — as mensagens originais do teste de NPS
# ficam intactas. Os anexos caem junto via dependent: :destroy da Message.

TAG = 'nps345_media'

conv = Conversation.joins(:contact).find_by(contacts: { name: 'NPS Sim invalid2' })
abort 'Conversa de "NPS Sim invalid2" nao encontrada.' if conv.nil?

msgs = conv.messages.where("content_attributes->>'seed' = ?", TAG)
n = msgs.count
if n.zero?
  puts "Nada a limpar (nenhuma mensagem #{TAG} na conversa ##{conv.display_id})."
  exit 0
end

ids = msgs.pluck(:id)
msgs.each(&:destroy!)
puts "== Removidas #{n} mensagens #{TAG} da conversa ##{conv.display_id}: #{ids.inspect} =="
