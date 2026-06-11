# -*- coding: utf-8 -*-
# Agenda follow-up nos NAO-RESPONDENTES (alcancados, sem incoming) da campanha 1
# atribuidos a Lucas/Bruno. Interleave p/ ambos terem cobertura. Cap 600, 5s.
# Envia DENTRO da conversa existente (FollowupHsmJob), mantendo o corretor.
require 'set'

BROKERS = [127, 131].freeze   # Lucas, Bruno
TOTAL = 600                   # cap total da campanha de follow-up
STEP = 5
DRY = ENV['DRY'] == '1'
NAMES = { 127 => 'Lucas', 131 => 'Bruno' }.freeze

convs = Conversation.where(inbox_id: 91, campaign_id: 1, assignee_id: BROKERS)
conv_ids = convs.pluck(:id)
replied = Message.where(conversation_id: conv_ids, message_type: :incoming)
                 .reorder(nil).distinct.pluck(:conversation_id).to_set
reached = Message.where(conversation_id: conv_ids, message_type: :outgoing, status: %i[delivered read])
                 .reorder(nil).distinct.pluck(:conversation_id).to_set
target_ids = (reached - replied).to_a

# exclui quem JA recebeu o follow-up (os 44 ja enviados antes da pausa) — sem mandar 2x
already_fu = Message.where(inbox_id: 91, message_type: :outgoing)
                    .where("additional_attributes->'template_params'->>'name' = 'tozi_followup_lanc'")
                    .reorder(nil).distinct.pluck(:conversation_id).to_set
target_ids = target_ids.reject { |id| already_fu.include?(id) }
LIMIT = (ENV['LIMIT'] || [TOTAL - already_fu.size, 0].max.to_s).to_i

rows = Conversation.where(id: target_ids).includes(:contact).map do |c|
  first = c.contact&.name.to_s.strip.split.first.presence || 'tudo bem'
  { id: c.id, first: first, assignee: c.assignee_id }
end

lucas = rows.select { |r| r[:assignee] == 127 }
bruno = rows.select { |r| r[:assignee] == 131 }
interleaved = []
[lucas.size, bruno.size].max.times do |i|
  interleaved << lucas[i] if lucas[i]
  interleaved << bruno[i] if bruno[i]
end
picked = LIMIT.positive? ? interleaved.first(LIMIT) : interleaved

per = Hash.new(0)
picked.each_with_index do |r, j|
  per[r[:assignee]] += 1
  next if DRY

  Spx::Tozi::FollowupHsmJob.set(wait: (STEP * j).seconds).perform_later(conversation_id: r[:id], first: r[:first])
end

mins = (STEP * [picked.size - 1, 0].max / 60.0).round
puts "disponiveis (Lucas+Bruno nao-resp): #{rows.size} | vao receber: #{picked.size}"
puts "por corretor: #{per.map { |k, v| "#{NAMES[k]}=#{v}" }.join(' ')}"
puts((DRY ? 'DRY-RUN' : 'ENFILEIRADO') + " #{picked.size} · 1/#{STEP}s · ~#{mins}min")
