# Smoke-test carrossel — PASSO 1: inspeção read-only (conta 3, HML .232)
# Lista canais WhatsApp da conta, valida token contra Graph v23.0 (GET, sem enviar nada).
# NUNCA imprime credenciais (só comprimento da api_key).
require 'net/http'

acc = Account.find(3)
puts "CONTA #{acc.id} — #{acc.name}"

inboxes = acc.inboxes.where(channel_type: 'Channel::Whatsapp')
puts "Inboxes WhatsApp: #{inboxes.count}"

inboxes.each do |ib|
  ch = ib.channel
  cfg = ch.provider_config || {}
  puts "-" * 60
  puts "INBOX #{ib.id} | #{ib.name} | provider=#{ch.provider} | phone=#{ch.phone_number}"
  puts "  cfg_keys=#{cfg.keys.sort.inspect}"
  puts "  phone_number_id=#{cfg['phone_number_id']} | waba_id=#{cfg['business_account_id']} | api_key_len=#{cfg['api_key'].to_s.length}"

  next unless ch.provider == 'whatsapp_cloud' && cfg['phone_number_id'].present?

  uri = URI("https://graph.facebook.com/v23.0/#{cfg['phone_number_id']}?fields=display_phone_number,verified_name,quality_rating")
  req = Net::HTTP::Get.new(uri)
  req['Authorization'] = "Bearer #{cfg['api_key']}"
  res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
  puts "  GRAPH v23.0 GET phone: HTTP #{res.code} => #{res.body.to_s[0, 300]}"
end
puts "-" * 60
puts "FIM_INSPECT"
