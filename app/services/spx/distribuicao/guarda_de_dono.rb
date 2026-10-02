# Quem já é dono deste lead, antes de o rodízio escolher alguém.
#
# Vive fora do DistribuirService porque ali é regra de BORDA: o serviço decide para quem vai um
# lead NOVO, e estas perguntas dizem quando não há lead novo nenhum para decidir.
#
# As duas primeiras nasceram da reclamação dos vendedores da Catatau em 15/09/2026, onde as duas
# faltas apareceram juntas: o cliente voltando ao menu chamava o Motor de novo e queimava a vez de
# cinco vendedores em cinco minutos, e o lead que alguém já atendia ia parar com outro porque em
# vendas se responde SEM assumir a conversa, e o Motor só enxergava `assignee`.
module Spx::Distribuicao::GuardaDeDono
  private

  # As duas perguntas que dizem "não há lead novo aqui, só um dono já decidido". Devolve o MOTIVO
  # (e não um booleano) porque é ele que o painel de Execuções mostra quando o passo é pulado.
  def sem_lead_novo(pool_ids)
    return 'ja_designada' if designacao_viva?(pool_ids)

    'ja_tem_dono' if dono_do_pool?(pool_ids)
  end

  # Uma designação VIVA já respondeu "de quem é este lead". Se o time MUDOU, o escolhido não está
  # mais no pool e o lead segue para o rodízio do time novo, que é o certo.
  def designacao_viva?(pool_ids)
    return false if @motivo_forcado

    log = Spx::Distribuicao::Log.designacao_aberta(@conversation.id)
    log.present? && pool_ids.include?(log.chosen_user_id.to_i)
  end

  # A conversa já tem dono do pool: não há lead novo para decidir. Sem isto, no modo assignee a
  # segunda chamada do Motor (o cliente voltando ao menu) trocava o dono sem nada ter acontecido.
  def dono_do_pool?(pool_ids)
    return false if @motivo_forcado

    @conversation.assignee_id.present? && pool_ids.include?(@conversation.assignee_id.to_i)
  end

  # Quem JÁ FALOU com o cliente nesta conversa fica com ela. Aqui a conversa ainda não tem dono:
  # em vendas se responde SEM assumir, e era assim que o Motor entregava a outro um lead que já
  # estava sendo atendido.
  #
  # `all_messages` (e não `messages`): em caixa com isolamento por time o `messages` vem filtrado,
  # e justamente na caixa onde isso importa o guard enxergaria conversa vazia.
  def quem_ja_atende(pool_ids)
    @conversation.all_messages.where(message_type: :outgoing, private: false, sender_type: 'User')
                 .where(sender_id: pool_ids).order(id: :desc).pick(:sender_id)
  end

  # Consultor que já atendeu ESTE contato NESTE time, dentro da janela, e que ainda está no pool
  # ativo. Query por contato (índice conversations.contact_id).
  #
  # ⚠️ Em modo_posse=designacao isto naturalmente não casa: `assignee` nunca é gravado, então não
  # há histórico por onde procurar. NÃO é bug — em vendas a fonte de "quem já atende este cliente"
  # é o VISTA (SPEC-RODIZIO §7.1), e entra junto com o espelho.
  def consultor_anterior(policy, pool_ids)
    desde = policy.continuidade_dias.to_i.days.ago
    @conversation.contact.conversations
                 .where(team_id: @team.id)
                 .where.not(id: @conversation.id)
                 .where(assignee_id: pool_ids)
                 .where('last_activity_at >= ?', desde)
                 .order(last_activity_at: :desc)
                 .limit(1)
                 .pick(:assignee_id)
  end

  # Ninguém escolhido tem dois sentidos bem diferentes, e o painel precisa saber qual: pool vazio é
  # problema de configuração, lead já designado é o Motor se recusando a refazer uma pergunta já
  # respondida.
  SEM_LEAD_NOVO = %w[ja_designada ja_tem_dono].freeze

  def sem_escolha(pool_ids, motivo)
    return Spx::Distribuicao::DistribuirService::Result.new(decidido: false, user_id: nil, motivo: motivo) if SEM_LEAD_NOVO.include?(motivo)

    sem_pool(pool_ids)
  end
end
