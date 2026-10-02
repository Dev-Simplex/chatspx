# frozen_string_literal: true

class Conversations::UpdateMessagesTeamIdJob < ApplicationJob
  # B5: era 1.000 e estourava o `statement_timeout` de 1min nas conversas grandes (11 falhas em
  # producao em 22/09, issue #233). Nao falta indice — o EXPLAIN mostra Index Only Scan; o que
  # custa e a manutencao dos SEIS indices de `messages` que envolvem conversation_id/team_id em
  # cada update_all, somada a disputa de lock (a frota tambem registra LockWaitTimeout).
  #
  # 250 mexe num quarto das linhas por statement e segura o lock por um quarto do tempo. Na maior
  # conversa da frota (72.789 mensagens) sao ~292 lotes em vez de ~73: o job inteiro demora mais,
  # cada pedaco fica bem longe do minuto. E a troca que se quer aqui.
  BATCH_SIZE = 250

  queue_as :low

  # Reads conversation.team_id at execution time (not from job args). When the conversation
  # is reassigned multiple times in quick succession, several jobs are enqueued; previously
  # each carried a frozen team_id and could overwrite a newer value out of order. By reading
  # the current state here, the last write always wins.
  #
  # Second arg is kept for backward compatibility with jobs already in the Sidekiq queue.
  def perform(conversation_id, _legacy_team_id = nil)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    destino = conversation.team_id
    # O cursor por id avanca sem reler a conversa inteira a cada lote.
    conversation.all_messages.where('messages.team_id IS DISTINCT FROM ?', destino).in_batches(of: BATCH_SIZE) do |batch|
      # B5: com lotes de 250 o job passou a durar ~4x mais, e a janela para a conversa trocar de
      # time NO MEIO da execucao cresceu junto. Sem esta checagem, o job do time antigo continuaria
      # gravando o valor velho nos lotes restantes DEPOIS de o job do time novo ter terminado —
      # exatamente a inconsistencia que este job existe para evitar. Abortar e seguro: o job da
      # troca nova ja esta na fila e refaz o trabalho com o valor certo.
      break if conversation.class.where(id: conversation.id).pick(:team_id) != destino

      batch.update_all(team_id: destino) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
