# frozen_string_literal: true

# CORTE DE HISTÓRICO NA TRANSFERÊNCIA POR PEDIDO (EA-01).
#
# Quem recebe uma conversa por um pedido APROVADO passa a ver apenas o que aconteceu dali em
# diante: ele dá continuidade ao atendimento sem ler o que se passou antes. O corte é por PESSOA,
# não por conversa — o dono anterior, o supervisor e o resto do time continuam vendo tudo.
#
# **Nenhuma coluna nova.** O instante do corte já está gravado: é o `responded_at` do pedido
# aprovado daquele agente naquela conversa.
#
# **Usa o MENOR `responded_at`, nunca o último.** Se o mesmo agente já recebeu a conversa antes,
# ele leu aquele trecho de forma legítima — inclusive mensagens que ele mesmo escreveu. Um segundo
# pedido não pode apagar o que ele já tinha lido.
#
# Mesmo desenho do AgentMessageIsolation, e pelo mesmo motivo: a regra depende de QUEM olha, então
# precisa ser reaplicada em CADA ponto de leitura de mensagem (lista da conversa, prévia da lista,
# busca, PDF, Copilot, resumo da IA, faixa de mídias). Esconder numa porta e esquecer as outras é
# vazamento silencioso — foi assim que o Copilot leu conversa fora do alcance (T14) e o PDF saiu
# com nota privada (T15).
module Conversations::HandoverCut
  module_function

  # Cortes deste usuário na conta: { conversation_id => menor responded_at }.
  # Vazio (o caso comum) faz todo o resto virar no-op, sem custo.
  def cuts_for(user, account)
    account_id = account.is_a?(Account) ? account.id : account
    return {} unless corta?(user, account_id)

    # Memo na INSTÂNCIA do usuário: ela é nova a cada requisição, e a mesma requisição consulta o
    # corte em vários pontos (lista de mensagens, prévia, payload da conversa). Thread-local aqui
    # vazaria entre requisições — `Current.reset` não roda por request neste código.
    user.handover_cuts_cache ||= {}
    user.handover_cuts_cache[account_id] ||= ConversationTakeoverRequest.approved
                                                                        .where(account_id: account_id, requester_id: user.id)
                                                                        .where.not(responded_at: nil)
                                                                        .group(:conversation_id)
                                                                        .minimum(:responded_at)
  end

  # Quem NÃO tem corte: contexto sem pessoa (job, widget, API pública) e administrador — a regra
  # é sobre o agente que recebeu a conversa, não sobre quem audita.
  def corta?(user, account_id)
    return false unless user.is_a?(User)
    return false if account_id.blank?

    !user.account_users.find_by(account_id: account_id)&.administrator?
  end

  # Corte de UMA conversa (MessageFinder, PDF, resumo — os pontos que já sabem qual é a conversa).
  # nil = sem corte.
  def cut_at_for(conversation, user, account = nil)
    return nil if conversation.nil?

    cuts_for(user, account || conversation.account_id)[conversation.id]
  end

  # Aplica o corte a um scope de Message de UMA conversa.
  def filter_messages(scope, cut_at)
    return scope if cut_at.blank?

    scope.where(messages: { created_at: cut_at.. })
  end

  # Versão para listagens que MISTURAM conversas (busca, prévia da lista, faixa de mídias): o
  # corte é diferente por conversa, então vai como uma condição por par (conversa, instante).
  # São poucos pares por usuário — um pedido aprovado é evento raro —, e com zero pares o scope
  # volta intocado.
  def filter_messages_across(scope, user, account, coluna_conversa: 'messages.conversation_id', coluna_data: 'messages.created_at')
    cuts = cuts_for(user, account)
    return scope if cuts.empty?

    condicoes = cuts.map do |conversa_id, corte|
      ActiveRecord::Base.sanitize_sql_array(
        ["(#{coluna_conversa} = ? AND #{coluna_data} < ?)", conversa_id, corte]
      )
    end
    scope.where.not(Arel.sql(condicoes.join(' OR ')))
  end
end
