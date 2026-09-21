# frozen_string_literal: true

# rake spx:resposta_celular:acertar_abertas             # SIMULA em todas as contas (nao grava)
# rake spx:resposta_celular:acertar_abertas[5]          # SIMULA so na conta 5
# APLICAR=1 rake spx:resposta_celular:acertar_abertas   # grava
#
# Acerto de UMA VEZ para as conversas ABERTAS que ficaram "esperando" por causa da resposta dada pelo
# celular numa caixa WAHA (nota privada com Message::WHATSAPP_PHONE_REPLY_MARKER). Antes da N-01 essa
# nota nao contava como resposta, entao `waiting_since` ficou parado no primeiro incoming e
# `first_reply_created_at` ficou vazio: a conversa aparece como nao atendida sem ser.
#
# O que faz, por conversa aberta ou pendente com `waiting_since`:
#   - se ha resposta pelo celular DEPOIS de `waiting_since`, o cliente foi respondido: `waiting_since`
#     passa a ser o primeiro incoming depois da ULTIMA resposta pelo celular (nil se ele nao voltou a
#     escrever);
#   - `first_reply_created_at` vazio recebe a primeira resposta pelo celular.
# O historico (resolvidas) fica como esta, por decisao de 18/09. Idempotente: rodar de novo nao muda nada.
namespace :spx do
  namespace :resposta_celular do
    desc 'Acerta waiting_since e first_reply_created_at das conversas abertas respondidas pelo celular (WAHA)'
    task :acertar_abertas, %i[account_id] => :environment do |_t, args|
      aplicar = ENV['APLICAR'] == '1'
      marcador = "#{Message::WHATSAPP_PHONE_REPLY_MARKER}%"

      conversas = Conversation.where(status: %i[open pending]).where.not(waiting_since: nil)
                              .joins(:inbox).where(inboxes: { channel_type: 'Channel::Api' })
                              .where.not(inboxes: { waha_session_name: [nil, ''] })
      conversas = conversas.where(account_id: args[:account_id].to_i) if args[:account_id].present?

      acertadas = Hash.new(0)
      conversas.find_each do |conversa|
        notas = conversa.all_messages.where(private: true, message_type: :outgoing).where('content LIKE ?', marcador)
        ultima = notas.where('messages.created_at > ?', conversa.waiting_since).maximum(:created_at)
        next if ultima.nil?

        novo_waiting = conversa.all_messages.incoming.where('messages.created_at > ?', ultima).minimum(:created_at)
        mudancas = { waiting_since: novo_waiting }
        mudancas[:first_reply_created_at] = notas.minimum(:created_at) if conversa.first_reply_created_at.nil?

        conversa.update_columns(mudancas) if aplicar # rubocop:disable Rails/SkipsModelValidations
        acertadas[conversa.account_id] += 1
      end

      modo = aplicar ? 'GRAVADO' : 'SIMULACAO (APLICAR=1 para gravar)'
      puts "[spx:resposta_celular] #{modo}"
      acertadas.sort.each { |conta, total| puts "  conta #{conta}: #{total} conversas acertadas" }
      puts "  total: #{acertadas.values.sum}"
    end
  end
end
