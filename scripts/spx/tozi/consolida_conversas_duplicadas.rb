# Consolidacao one-shot das conversas/fichas duplicadas dos disparos (inbox 91).
#
# CONTEXTO: o DisparoLeadJob antigo criava ficha (ContactInbox) com source_id no
# nosso formato (9o digito) e conversa nova via Conversation.create!. Quando o
# WhatsApp usa a outra variante (12d/13d) pro mesmo numero, o reply do lead caia
# numa ficha/conversa diferente da do disparo -> orfao + a AutomationRule #53
# desatribuia ao reabrir. Resultado: 275 contatos com >1 conversa.
#
# Este script funde, por contato, todas as conversas numa unica (a com mais
# incoming; empate -> mais recente), move as mensagens, atribui ao corretor do
# disparo, deixa aberta, e apaga as conversas vazias + fichas duplicadas.
# Usa delete/update_columns (sem callbacks/async) -> transacional e reversivel.
#
# Rodado em prod 2026-06-08: 275 ok, 0 falhas, 810 msgs movidas, 298 convs e
# 203 fichas apagadas. Verificado: 0 contatos com >1 conversa/ficha apos.
#
# USO:
#   MODE=validate rails runner scripts/spx/tozi/consolida_conversas_duplicadas.rb  # 1 contato, rollback
#   MODE=exec     rails runner scripts/spx/tozi/consolida_conversas_duplicadas.rb  # aplica nos alvos
#   LIMIT=N -> processa so os N primeiros (testes)
INBOX = 91
MODE = ENV['MODE'] || 'validate'
LIMIT = ENV['LIMIT'] ? ENV['LIMIT'].to_i : nil

def targets(inbox)
  dcids = Conversation.where(inbox_id: inbox).where("additional_attributes->>'source' = ?", 'disparo_lancamento').reorder(nil).distinct.pluck(:contact_id)
  Conversation.where(inbox_id: inbox, contact_id: dcids).reorder(nil).group(:contact_id).count.select { |_, n| n > 1 }.keys
end

def merge_contact(cid, inbox_id, verbose: false)
  convs = Conversation.where(inbox_id: inbox_id, contact_id: cid).to_a
  return { skip: true } if convs.size < 2

  cibs = ContactInbox.where(inbox_id: inbox_id, contact_id: cid).to_a
  ids = convs.map(&:id)
  inc = Message.where(conversation_id: ids, message_type: :incoming).reorder(nil).group(:conversation_id).count; inc.default = 0

  survivor = convs.sort_by { |c| [-inc[c.id], -c.created_at.to_i] }.first
  survivor_cib_id = survivor.contact_inbox_id
  disparo = convs.select { |c| (c.additional_attributes || {})['source'] == 'disparo_lancamento' }
  corretor = disparo.max_by(&:created_at)&.assignee_id
  others = convs - [survivor]

  if verbose
    puts "  contato #{cid}: survivor=#{survivor.id} (cib #{survivor_cib_id}) corretor=#{corretor}"
    convs.each { |c| puts "    conv#{c.display_id}/#{c.id} st=#{c.status} ass=#{c.assignee_id} in=#{inc[c.id]} msgs=#{Message.where(conversation_id: c.id).count}#{c.id == survivor.id ? ' SOBREVIVE' : ' -> apaga'}" }
  end

  moved = 0; camp = survivor.campaign_id
  attrs = (survivor.additional_attributes || {}).dup
  others.each do |o|
    moved += Message.where(conversation_id: o.id).update_all(conversation_id: survivor.id, team_id: survivor.team_id)
    camp ||= o.campaign_id
    oa = o.additional_attributes || {}
    attrs['source'] ||= oa['source']; attrs['template'] ||= oa['template']
  end

  upd = { additional_attributes: attrs, status: Conversation.statuses[:open],
          last_activity_at: (Message.where(conversation_id: survivor.id).maximum(:created_at) || survivor.last_activity_at) }
  upd[:assignee_id] = corretor if corretor
  upd[:campaign_id] = camp if camp && survivor.campaign_id.nil?
  survivor.update_columns(upd)

  others.each do |o|
    ActiveRecord::Base.connection.exec_delete("DELETE FROM captain_assistant_logs WHERE conversation_id=#{o.id.to_i}", 'logs')
    Notification.where(primary_actor_type: 'Conversation', primary_actor_id: o.id).delete_all
    Notification.where(secondary_actor_type: 'Conversation', secondary_actor_id: o.id).delete_all
    o.delete
  end
  cibs.reject { |c| c.id == survivor_cib_id }.each(&:delete)

  { survivor: survivor.id, corretor: corretor, moved: moved, del_convs: others.size, del_cibs: cibs.size - 1 }
end

list = targets(INBOX)
list = list.first(LIMIT) if LIMIT
puts "MODE=#{MODE} | alvos=#{list.size}"

if MODE == 'validate'
  cid = list.find { |c| ContactInbox.where(inbox_id: INBOX, contact_id: c).count > 1 } || list.first
  ActiveRecord::Base.transaction do
    r = merge_contact(cid, INBOX, verbose: true)
    sv = Conversation.find(r[:survivor])
    puts "  DEPOIS: convs=#{Conversation.where(inbox_id: INBOX, contact_id: cid).count} cibs=#{ContactInbox.where(inbox_id: INBOX, contact_id: cid).count} status=#{sv.status} assignee=#{sv.assignee_id}"
    puts "  result: #{r}"
    raise ActiveRecord::Rollback, 'validate-only'
  end
  puts "[VALIDATE] rollback OK."
else
  ok = 0; bad = 0; moved = 0; dc = 0; dk = 0; errs = []
  list.each do |cid|
    r = nil
    ActiveRecord::Base.transaction { r = merge_contact(cid, INBOX) }
    if r && !r[:skip] then ok += 1; moved += r[:moved]; dc += r[:del_convs]; dk += r[:del_cibs] end
  rescue StandardError => e
    bad += 1; errs << "#{cid}: #{e.class} #{e.message}"
  end
  puts "[EXEC] ok=#{ok} fail=#{bad} msgs_movidas=#{moved} convs_apagadas=#{dc} fichas_apagadas=#{dk}"
  errs.first(20).each { |e| puts "  ERRO #{e}" }
end
