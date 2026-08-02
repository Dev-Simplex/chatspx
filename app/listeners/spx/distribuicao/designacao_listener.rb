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

        Log.designacao_aberta(conversation.id)&.encerrar!('assumido')
      rescue StandardError => e
        Rails.logger.error("[Spx::Distribuicao::DesignacaoListener] assignee conv=#{conversation&.id}: #{e.message}")
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
