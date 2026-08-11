# Espelha a designação nos custom_attributes da conversa (SPEC-RODIZIO §6).
#
# Dois consumidores, um carimbo:
#   - o TIME, no painel — o Chatwoot só renderiza custom_attributes DEFINIDOS, por isso as
#     definições são garantidas aqui (sem elas o dado existe e é invisível);
#   - o AGENTE, no contexto do turno — sem este gatilho visível não há como escrever a
#     conduta de "modo contido": a IA não teria como saber que a conversa já tem dono.
#
# A FONTE DA VERDADE continua sendo `distribuicao_logs`. Isto é espelho de LEITURA; se um
# dia divergir, o log manda.
#
# ⚠️ O nome do corretor é carimbado pro time, mas NÃO chega ao agente — ver o `except` em
# Captain::Assistant::AgentRunnerService#build_conversation_state. Nome no contexto faz o
# LLM anunciar o repasse, e o desenho proíbe anunciar.
module Spx
  module Distribuicao
    class CarimbarService
      CORRETOR = 'rodizio_corretor'.freeze
      DESIGNADO_EM = 'rodizio_designado_em'.freeze
      PRODUTO = 'rodizio_produto'.freeze

      DEFINICOES = {
        CORRETOR => 'Rodízio · Corretor designado',
        DESIGNADO_EM => 'Rodízio · Designado em',
        PRODUTO => 'Rodízio · Produto'
      }.freeze

      def initialize(conversation:, user_id:, produto: nil)
        @conversation = conversation
        @user_id = user_id
        @produto = produto
      end

      def perform
        attrs = {
          CORRETOR => nome_do_corretor,
          DESIGNADO_EM => Time.current.iso8601,
          PRODUTO => @produto
        }.compact
        return if attrs.empty?

        garantir_definicoes
        @conversation.update!(custom_attributes: (@conversation.custom_attributes || {}).merge(attrs))
      rescue StandardError => e
        # Carimbo é espelho: falhar aqui não pode derrubar a designação, que já está no log.
        Rails.logger.warn("[Distribuicao] carimbo conv=#{@conversation&.id}: #{e.message}")
      end

      private

      def nome_do_corretor
        User.find_by(id: @user_id)&.name
      end

      def garantir_definicoes
        DEFINICOES.each do |chave, nome|
          definicao = CustomAttributeDefinition.find_or_initialize_by(
            account_id: @conversation.account_id,
            attribute_key: chave,
            attribute_model: :conversation_attribute
          )
          next if definicao.persisted?

          definicao.update!(attribute_display_name: nome, attribute_display_type: :text)
        end
      end
    end
  end
end
