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
    end
  end
end
