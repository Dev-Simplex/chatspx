# Fecha a DESIGNAÇÃO — o estado em que a conversa já tem dono mas a IA segue atendendo
# (docs/clientes/tozi/SPEC-RODIZIO.md §3).
#
# "Designado" é um estado com SAÍDA, e são duas:
#   1. ASSUMIR dentro do SPX — hoje no painel, pela recepção em nome do corretor; amanhã
#      pelo próprio corretor no app nativo, sem mudar nada daqui.
#   2. ENGAJAR no card do Vista — o corretor mexeu no card. O sinal (`vista_engajado_em`) é
#      escrito pela frente spx/eval; aqui a gente só CONSOME. Não construir outro leitor.
#
# IMPORTANTE: roda pra TODA conta da instância via AsyncDispatcher, e uma exceção aqui
# derrubaria os listeners seguintes do EventDispatcherJob. Por isso é rescue-wrapped.
# Conta sem designação aberta = no-op puro.
module Spx
  module Distribuicao
    class DesignacaoListener < BaseListener
      ENGAJADO_EM = 'vista_engajado_em'.freeze
      CORRETOR_VISTA = 'vista_corretor'.freeze

      def assignee_changed(event)
        conversation, _account = extract_conversation_and_account(event)
        return if conversation.nil?
        # Só humano encerra. Troca entre espelhos de IA não é "assumir".
        return if conversation.assignee_id.blank?

        designacao = Log.designacao_aberta(conversation.id)
        return if designacao.nil? || posse_do_motor?(designacao, conversation)

        designacao.encerrar!('assumido')
      rescue StandardError => e
        Rails.logger.error("[Spx::Distribuicao::DesignacaoListener] assignee conv=#{conversation&.id}: #{e.message}")
      end

      # Saída 3 (modo PUSH): a pessoa respondeu ao cliente. É o sinal de engajamento REAL do
      # push — "atribuído" não quer dizer atendido, e é justamente essa diferença que o
      # `sla_assumir_minutos` mede.
      #
      # Roda para TODA mensagem da instância: a guarda barata (outgoing + não-privada + humano)
      # vem antes de qualquer ida ao banco.
      def message_created(event)
        message = event.data[:message]
        return unless resposta_humana?(message)

        designacao = Log.designacao_aberta(message.conversation_id)
        return if designacao.nil? || !designacao.aguarda_primeira_resposta?

        designacao.encerrar!('assumido')
      rescue StandardError => e
        Rails.logger.error("[Spx::Distribuicao::DesignacaoListener] mensagem conv=#{message&.conversation_id}: #{e.message}")
      end

      # Gatilho SEM IA (opt-in por política, `gatilho_sem_ia`). O Motor nasceu pendurado no
      # handoff do Captain, então um time que recebe conversa por FLOW ou REGRA (`assign_team`)
      # nunca distribuía — a conversa caía no time e ficava parada até alguém pegar na mão.
      # Aqui o TEAM_CHANGED passa a acionar o Motor nesse caminho.
      def team_changed(event)
        conversation, _account = extract_conversation_and_account(event)
        return unless distribuivel_sem_ia?(conversation)

        DistribuirService.new(conversation).call
      rescue StandardError => e
        Rails.logger.error("[Spx::Distribuicao::DesignacaoListener] gatilho conv=#{conversation&.id}: #{e.message}")
      end

      # Saída 2: o corretor pegou o lead no Vista. Fecha a designação (para o cronômetro do
      # SLA) e cala a IA — o atendimento passou a ser dele, fora do SPX.
      #
      # Dispara pra QUALQUER update de conversa da instância, então o caminho comum tem que
      # ser barato: a checagem do campo é leitura de hash já carregado, sem ir ao banco.
      def conversation_updated(event)
        conversation, _account = extract_conversation_and_account(event)
        return if conversation.nil?

        engajado_em = (conversation.custom_attributes || {})[ENGAJADO_EM].presence
        return if engajado_em.blank?

        designacao = Log.designacao_aberta(conversation.id)
        return if designacao.nil?

        conferir_troca(conversation, designacao)
        # Fecha ANTES de silenciar: `silenciar_ia` salva a conversa e reentra neste handler.
        # Com a designação já fechada, a segunda passada sai no `return` acima.
        designacao.update!(status: 'engajado', encerrado_em: horario(engajado_em))
        silenciar_ia(conversation)
      rescue StandardError => e
        Rails.logger.error("[Spx::Distribuicao::DesignacaoListener] engajamento conv=#{conversation&.id}: #{e.message}")
      end

      private

      # Modo PUSH com repasse: quem gravou este assignee foi o próprio Motor, um instante atrás.
      # Fechar a designação aqui zeraria o cronômetro no nascimento — nesse modo ela só fecha
      # quando a pessoa RESPONDE (#message_created) ou quando OUTRA pessoa toma a conversa.
      def posse_do_motor?(designacao, conversation)
        designacao.aguarda_primeira_resposta? && designacao.chosen_user_id == conversation.assignee_id
      end

      def resposta_humana?(message)
        return false if message.nil?

        message.outgoing? && !message.private? && message.sender_type == 'User'
      end

      # Guardas antes de qualquer consulta cara, na ordem do mais barato para o mais caro:
      #   • já tem dono humano  → nada a distribuir
      #   • espelho da IA é o dono → o handoff é quem chama o Motor; distribuir aqui atropelaria
      #     a triagem em curso e calaria a IA no meio de uma conversa
      #   • conversa fechada → não se distribui histórico
      #   • já existe designação viva → não redesigna a cada save
      # Só então lê a política, e só age se o gestor tiver LIGADO o gatilho nela.
      def distribuivel_sem_ia?(conversation)
        return false unless conversa_sem_dono?(conversation)
        return false unless gatilho_ligado?(conversation)

        Log.designacao_aberta(conversation.id).nil?
      end

      def conversa_sem_dono?(conversation)
        return false if conversation.nil? || conversation.team_id.blank?
        return false if conversation.assignee_id.present? || conversation.assignee_agent_bot_id.present?

        conversation.open? || conversation.pending?
      end

      def gatilho_ligado?(conversation)
        policy = Policy.for_team(conversation.account_id, conversation.team_id)
        policy.present? && policy.gatilho_sem_ia? && policy.distribui?
      end

      # Soltar o espelho é o jeito NATIVO de calar a IA: todo o pipeline do Captain gateia em
      # `assignee_agent_bot`. A conversa fica sem dono no SPX — que é a verdade, porque quem
      # atende agora está no Vista. Se o cliente voltar com assunto novo, as regras de
      # reentrada devolvem a conversa pra uma IA.
      def silenciar_ia(conversation)
        return if conversation.assignee_agent_bot_id.blank?

        conversation.update!(assignee_agent_bot_id: nil)
      end

      # O card mudou de mão POR FORA: a contagem creditou o lead a quem o rodízio escolheu,
      # mas quem trabalhou foi outro. Só registra — o que fazer com a contagem nesse caso é
      # decisão de produto (SPEC-RODIZIO §13), não de listener.
      def conferir_troca(conversation, designacao)
        atual = (conversation.custom_attributes || {})[CORRETOR_VISTA].presence
        return if atual.blank?

        esperado = corretor_vista_designado(conversation, designacao)
        return if esperado.blank? || esperado.to_s == atual.to_s

        Rails.logger.warn(
          "[Spx::Distribuicao] card trocou de corretor fora do SPX conv=#{conversation.id} " \
          "designado=#{esperado} atual=#{atual}"
        )
      end

      def corretor_vista_designado(conversation, designacao)
        return nil if conversation.team_id.blank? || designacao.chosen_user_id.blank?

        policy = Policy.for_team(conversation.account_id, conversation.team_id)
        entrada = (policy&.pool || []).find { |e| e['user_id'].to_i == designacao.chosen_user_id }
        entrada && entrada['vista_corretor']
      end

      def horario(valor)
        Time.zone.parse(valor.to_s) || Time.current
      rescue StandardError
        Time.current
      end
    end
  end
end
