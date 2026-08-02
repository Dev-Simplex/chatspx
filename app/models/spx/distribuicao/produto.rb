# Catálogo de produtos POR CONTA (SPEC-RODIZIO §5.2). Vivo: produto novo é uma linha,
# produto que a imobiliária deixou de vender é `ativo: false` — sem tocar em código.
#
# Taxonomia PLANA de propósito: a carteira real mistura construtora, empreendimento e
# categoria no mesmo nível. Hierarquia rígida quebra na primeira exceção.
module Spx
  module Distribuicao
    class Produto < ApplicationRecord
      self.table_name = 'distribuicao_produtos'

      belongs_to :account

      validates :slug, presence: true, uniqueness: { scope: :account_id }
      validates :nome, presence: true

      scope :ativos, -> { where(ativo: true) }

      # Lista de termos de reconhecimento de um sinal. Chave ausente = este produto não
      # casa por esse sinal (e não que ele case com tudo).
      def matcher(chave)
        Array((matchers || {})[chave.to_s]).map { |termo| termo.to_s.strip.downcase }.compact_blank
      end

      # --- Inventário de apresentação -------------------------------------------------
      # A config descreve MATERIAL e PÚBLICO, nunca SEQUÊNCIA: quem decide qual peça mandar e
      # quando é a IA, no contexto da conversa. O operador controla o que EXISTE no inventário
      # e escreve uma orientação em linguagem natural — uma frase, não um if.
      #
      # A COLUNA `apresentacao` (jsonb) é da frente spx/rodizio, dona desta tabela — esta frente
      # só CONSOME. Enquanto ela não existir, tudo aqui devolve vazio e o comportamento é o de
      # hoje (nenhuma peça, nenhuma tool ativa). Formato combinado:
      #   { "orientacao": "<uma frase sobre quem é este público e o que funciona com ele>",
      #     "audio_proativo": <bool>,
      #     "pecas": [ { "id": "<slug>", "tipo": "audio|imagem|video|documento",
      #                  "descricao": "<o que a peça explica e pra quem serve>", "url": "<...>" } ] }
      def apresentacao_config
        return {} unless has_attribute?(:apresentacao)

        (apresentacao.presence || {})
      end

      # Peças utilizáveis: precisam de id, tipo e url. Peça pela metade é ignorada em silêncio
      # em vez de virar erro na frente do cliente.
      def pecas
        Array(apresentacao_config['pecas']).select do |p|
          p.is_a?(Hash) && p['id'].present? && p['tipo'].present? && p['url'].present?
        end
      end

      def peca(id)
        pecas.find { |p| p['id'].to_s == id.to_s }
      end

      # Texto livre do operador sobre QUEM é este público e o que costuma funcionar com ele.
      def orientacao_publico
        apresentacao_config['orientacao'].to_s.strip.presence
      end

      # Áudio de empresa é mais invasivo que texto: o que converte num público pode irritar
      # outro. Default false — áudio proativo é opt-in por produto.
      def audio_proativo?
        apresentacao_config['audio_proativo'] == true
      end
    end
  end
end
