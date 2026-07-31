# Fecha a DESIGNAÇÃO quando um humano assume a conversa dentro do SPX
# (docs/clientes/tozi/SPEC-RODIZIO.md §3).
#
# "Designado" é um estado com saída: enquanto está aberto, a IA segue atendendo e o relógio
# do SLA corre. Quem fecha aqui é o ato de ASSUMIR — hoje feito no painel pela recepção em
# nome do corretor; amanhã pelo próprio corretor no app nativo, sem mudar nada disto.
# A outra saída (corretor mexeu no card do Vista) chega pelo campo `vista_engajado_em`,
# escrito pela frente spx/eval.
#
# IMPORTANTE: roda pra TODA conta da instância via AsyncDispatcher, e uma exceção aqui
# derrubaria os listeners seguintes do EventDispatcherJob. Por isso é rescue-wrapped.
# Conta sem designação aberta = no-op puro.
module Spx
  module Distribuicao
    class DesignacaoListener < BaseListener
      def assignee_changed(event)
        conversation, _account = extract_conversation_and_account(event)
        return if conversation.nil?
        # Só humano encerra. Troca entre espelhos de IA não é "assumir".
        return if conversation.assignee_id.blank?

        Log.designacao_aberta(conversation.id)&.encerrar!('assumido')
      rescue StandardError => e
        Rails.logger.error("[Spx::Distribuicao::DesignacaoListener] conv=#{conversation&.id}: #{e.message}")
      end
    end
  end
end
