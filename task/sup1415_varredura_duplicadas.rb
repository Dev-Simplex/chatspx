# Varredura SÓ DE LEITURA: fichas do mesmo número (com/sem o 9º dígito) na mesma conta.
# Saída: resumo por conta + JSON dos grupos ativos em /tmp/dup-scan-sup1415.json (apagado por quem chamou).
require 'json'

def canonical(phone)
  d = phone.to_s.gsub(/\D/, '')
  return d unless d.start_with?('55') && d.length == 12 && d[4].to_i >= 6 # celular antigo de 8 dígitos

  "#{d[0, 4]}9#{d[4..]}"
end

Contact.uncached do
  t31 = Time.zone.parse('2026-09-17')
  since = 30.days.ago
  rows = Contact.where.not(phone_number: [nil, '']).pluck(:id, :account_id, :phone_number, :created_at,
                                                           Arel.sql("custom_attributes ? 'waha_whatsapp_chat_id'"))
  groups = rows.group_by { |r| [r[1], canonical(r[2])] }.select { |(_, c), rs| rs.size > 1 && c.length >= 12 }
  ids = groups.values.flatten(1).map(&:first)
  last_act = Conversation.where(contact_id: ids).group(:contact_id).maximum(:last_activity_at)
  convs = Conversation.where(contact_id: ids).group(:contact_id).count
  waha_inbox_accounts = Inbox.where(channel_type: 'Channel::Api').select { |i| i.channel.try(:webhook_url).to_s =~ %r{webhooks/chatwoot/} }.map(&:account_id).uniq

  out = Hash.new { |h, k| h[k] = Hash.new(0) }
  ativos = []
  groups.each do |(acc, num), rs|
    o = out[acc]
    o[:grupos] += 1
    o[:fichas_extras] += rs.size - 1
    with_conv = rs.count { |r| convs[r[0]].to_i.positive? }
    o[:com_conversa_nas_duas] += 1 if with_conv > 1
    active = rs.count { |r| last_act[r[0]] && last_act[r[0]] > since }
    waha_split = rs.any? { |r| r[4] } && rs.any? { |r| !r[4] }
    o[:waha_uma_sim_outra_nao] += 1 if waha_split
    o[:criado_apos_t31] += 1 if rs.map { |r| r[3] }.max > t31
    next unless active > 1

    o[:ativos_30d] += 1
    ativos << { conta: acc, numero: num, waha_split: waha_split,
                fichas: rs.sort_by { |r| r[3] }.map { |r| { id: r[0], tel: r[2], criada: r[3].to_date.to_s, waha: r[4], conversas: convs[r[0]].to_i, ultima: last_act[r[0]]&.to_date&.to_s } } }
  end

  names = Account.where(id: out.keys).pluck(:id, :name).to_h
  tot = Hash.new(0)
  out.sort_by { |_, o| -o[:grupos] }.each do |acc, o|
    o.each { |k, v| tot[k] += v }
    puts format('CONTA %-4s %-32s grupos=%-5d extras=%-5d conv_nas_duas=%-5d ativos30d=%-4d waha_split=%-5d pos_T31=%-3d%s',
                acc, names[acc].to_s[0, 32], o[:grupos], o[:fichas_extras], o[:com_conversa_nas_duas], o[:ativos_30d],
                o[:waha_uma_sim_outra_nao], o[:criado_apos_t31], waha_inbox_accounts.include?(acc) ? ' [WAHA]' : '')
  end
  puts "TOTAL #{tot.to_json} contatos_com_tel=#{rows.size}"
  File.write('/tmp/dup-scan-sup1415.json', JSON.pretty_generate(ativos))
end
