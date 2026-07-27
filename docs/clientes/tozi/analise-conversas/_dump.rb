# encoding: utf-8
# Dump READ-ONLY de conversas do Captain pra analise offline.
# Uso:  bundle exec rails runner _dump.rb <account_id> <display_id> [display_id...]
# Ex.:  scripts/ops/tozi-prod.sh put docs/clientes/tozi/analise-conversas/_dump.rb /tmp/_dump.rb
#       scripts/ops/tozi-prod.sh run "bundle exec rails runner /tmp/_dump.rb 6 18973 18986"
# Cola a saida em raw/<display_id>.md (condensando anexos/URLs assinadas, que expiram).
account_id  = ARGV[0].to_i
display_ids = ARGV[1..].to_a.map(&:to_i).reject(&:zero?)
abort 'uso: rails runner _dump.rb <account_id> <display_id...>' if account_id.zero? || display_ids.empty?

account = Account.find(account_id)
KIND = { 0 => 'IN ', 1 => 'OUT', 2 => 'ACT', 3 => 'TPL' }.freeze

display_ids.each do |dis|
  conv = account.conversations.find_by(display_id: dis)
  puts "\n" + ('=' * 90)
  unless conv
    puts "CONVERSA display_id=#{dis}: NAO ENCONTRADA na conta #{account_id}"
    next
  end
  c = conv.contact
  ib = conv.inbox
  puts "CONVERSA display_id=#{conv.display_id} (id=#{conv.id}) | status=#{conv.status}"
  puts "inbox=#{ib&.name.inspect} (##{ib&.id} #{ib&.channel_type}) | team=#{conv.team&.name.inspect} (##{conv.team&.id}) | assignee=#{conv.assignee&.name.inspect}"
  puts "contato=#{c&.name.inspect} | criada=#{conv.created_at} | last_activity=#{conv.last_activity_at}"
  puts "labels=#{conv.cached_label_list.inspect}"
  puts "custom_attributes=#{conv.custom_attributes.inspect}"
  puts "total_mensagens=#{conv.messages.count}"
  puts '-' * 90

  conv.messages.order(:id).each do |m|
    kind = KIND[m.message_type] || m.message_type.to_s
    name = begin
      m.sender&.try(:name) || m.sender&.try(:available_name)
    rescue StandardError
      nil
    end
    who = m.sender_type ? "#{m.sender_type}:#{name.inspect}" : 'system'
    who = "PRIV/#{who}" if m.private
    ts = m.created_at.strftime('%d/%m %H:%M:%S')
    puts "[#{ts}] #{kind} #{who} (msg_id=#{m.id})"
    puts "  #{m.content}" if m.content.present?
    ca = m.content_attributes
    if ca.is_a?(Hash) && (ca['in_reply_to'] || ca['in_reply_to_external_id'])
      puts "  reply_to=#{ca['in_reply_to'] || ca['in_reply_to_external_id']}"
    end
    m.attachments.each { |a| puts "  <ATTACH #{a.file_type}>" }
  end
end
nil
