# Resolve o PRODUTO de uma conversa (SPEC-RODIZIO §4), pela PRIMEIRA fonte que responder:
#   1. intenção declarada  — o que a IA gravou sobre o cliente (`sobre_cliente`)
#   2. imóvel do anúncio   — carimbo `meta_imovel_codigo` / `meta_imovel`
#   3. campanha de entrada — campaign_id + carimbo `meta_campanha`
#   4. nada                — nil, e o pool inteiro do time segue elegível
#
# A INTENÇÃO GANHA DA CAMPANHA de propósito: o lead clica no anúncio de um lançamento e na
# conversa diz que quer outra coisa. Quem atende tem que ser o da coisa que ele quer, não o
# do anúncio que ele clicou. Por isso a resolução roda no handoff — quando a IA já qualificou.
module Spx
  module Distribuicao
    class ResolverProdutoService
      def initialize(conversation)
        @conversation = conversation
      end

      # Devolve o slug do produto, ou nil quando nenhum sinal casa.
      def call
        produtos = Produto.ativos.where(account_id: @conversation.account_id).to_a
        return nil if produtos.empty?

        casar(produtos, :palavras, intencao) ||
          casar(produtos, :empreendimentos, imovel) ||
          casar(produtos, :campanhas, campanha)
      end

      private

      # Casa por CONTÉM, não por igualdade: os sinais chegam como texto livre (nome de
      # campanha, descrição de imóvel, frase sobre o cliente), nunca como chave exata.
      def casar(produtos, chave, texto)
        return nil if texto.blank?

        produtos.find { |produto| produto.matcher(chave).any? { |termo| texto.include?(termo) } }&.slug
      end

      def intencao
        normalizar(custom('sobre_cliente'))
      end

      def imovel
        normalizar("#{custom('meta_imovel_codigo')} #{custom('meta_imovel')}")
      end

      # O carimbo guarda o NOME da campanha; o id fica no additional_attributes do lead.
      # Junta os dois pra o matcher poder ser escrito de qualquer uma das formas.
      def campanha
        lead = (@conversation.additional_attributes || {})['lead'] || {}
        normalizar("#{lead['campaign_id']} #{custom('meta_campanha')}")
      end

      def custom(chave)
        (@conversation.custom_attributes || {})[chave].to_s
      end

      def normalizar(texto)
        texto.to_s.strip.downcase.presence
      end
    end
  end
end
