# Limpeza dos marcadores RESIDUAIS da fila "Aguardando encerramento" (conta 6, Tozi).
#
# POR QUE EXISTE
# --------------
# O `auto_closure` da conta 6 está DESLIGADO (`captain_auto_resolve_mode = "disabled"` e
# `settings['auto_closure'] = {enabled: false, max_dias: 0}`), mas 355 conversas carregam
# `aguardando_encerramento_desde` — resíduo do minuto de 03/08/2026 em que as duas chaves foram
# ligadas na ordem errada. Elas aparecem na fila do time e não saem sozinhas: o marcador só cai
# quando um humano assume, o cliente volta a falar ou a conversa resolve — e nenhuma dessas três
# coisas acontece numa conversa parada.
#
# A correção das duas guardas (guarda B: o incoming do cliente solta a conversa) trata o FLUXO,
# não o passivo: sem uma mensagem nova, não há evento que dispare a limpeza. Daí esta varredura.
#
# O QUE FAZ (e o que NÃO faz)
# ---------------------------
# Remove APENAS as três chaves da fila de encerramento — `aguardando_encerramento_desde`,
# `encerramento_avisado_em` e `encerramento_classe`. NÃO muda status, NÃO atribui, NÃO manda
# mensagem, NÃO encosta em `aguardando_humano_desde` (é a outra fila).
#
# Usa `update_columns` de propósito, igual ao concern que faz a mesma limpeza: o objetivo é
# apagar um marcador, não movimentar a conversa. Um `update!` em 355 conversas dispararia a
# cadeia de after_commit (funil, ActionCable, webhooks) e a limpeza viraria evento.
#
# USO
# ---
#   scripts/ops/tozi-prod.sh run "bundle exec rails runner scripts/spx/tozi/limpa_marcadores_encerramento.rb"
#
#   DRY=1  (default)  -> só conta e mostra amostra. NÃO escreve nada.
#   DRY=0             -> aplica. Decisão do Paulo; não rode por conta própria.
#   CONTA=6           -> account_id alvo.
#   DIAS=3            -> só marcadores com mais de N dias (0 = todos, inclusive os de hoje).
#   LIMITE=N          -> teto de conversas tocadas (0 = sem teto).
#
# ⚠️ Antes de rodar com DRY=0, confira que o `auto_closure` continua desligado. Com a política
# ligada, marcador novo é fila legítima — e o corte por DIAS é o que separa um do outro.
CONTA  = (ENV['CONTA'] || 6).to_i
DIAS   = (ENV['DIAS'] || 3).to_i
LIMITE = (ENV['LIMITE'] || 0).to_i
DRY    = ENV['DRY'] != '0'

CHAVES = %w[aguardando_encerramento_desde encerramento_avisado_em encerramento_classe].freeze

def marcado(conta)
  Conversation.where(account_id: conta).where(
    "custom_attributes->>'aguardando_encerramento_desde' IS NOT NULL OR " \
    "custom_attributes->>'encerramento_avisado_em' IS NOT NULL"
  )
end

def antigo?(conv, dias)
  return true if dias.zero?

  desde = conv.custom_attributes['aguardando_encerramento_desde'] ||
          conv.custom_attributes['encerramento_avisado_em']
  return false if desde.blank?

  Time.zone.parse(desde) < dias.days.ago
rescue StandardError
  false # data ilegível: não é candidato — some do relatório em vez de virar escrita às cegas
end

escopo = marcado(CONTA)
alvos  = escopo.order(:id).select { |c| antigo?(c, DIAS) }
alvos  = alvos.first(LIMITE) if LIMITE.positive?

conta_conf = Account.find(CONTA).settings['auto_closure']
puts "conta #{CONTA} · auto_closure = #{conta_conf.inspect}"
puts "marcadores no total: #{escopo.count}"
puts "com mais de #{DIAS} dia(s): #{alvos.size}  <== conversas que este script tocaria"
puts "modo: #{DRY ? 'DRY-RUN (nada será escrito)' : 'EXECUÇÃO (vai escrever)'}"
puts "amostra display_id: #{alvos.first(15).map(&:display_id).inspect}"

if DRY
  puts 'FIM — dry-run, nada foi escrito.'
  exit
end

ok = 0
falhas = 0
alvos.each_slice(50) do |lote|
  lote.each do |conv|
    conv.update_columns(custom_attributes: (conv.custom_attributes || {}).except(*CHAVES)) # rubocop:disable Rails/SkipsModelValidations
    ok += 1
  rescue StandardError => e
    falhas += 1
    puts "FALHA conv=#{conv.id}: #{e.message}"
  end
  sleep 0.2
end

puts "limpas: #{ok} · falhas: #{falhas}"
puts "restantes com marcador: #{marcado(CONTA).count}"
