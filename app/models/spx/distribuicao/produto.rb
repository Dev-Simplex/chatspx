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

      # Inventário de peças de marketing — contrato em docs/contratos/apresentacao-produto.md.
      # Escrito pela config, consumido pela frente spx/followup. Leitores aqui pra as duas
      # frentes lerem do MESMO lugar em vez de cada uma parsear o hash por conta.
      #
      # A config descreve material e público; NUNCA sequência. Quem escolhe a peça e o momento
      # é a IA, no contexto — ver §1 do contrato antes de acrescentar campo aqui.
      #
      # Tolerante à coluna AUSENTE: a migration é aplicada com alvo, VM a VM, então o código
      # roda em box onde ela ainda não existe. Sem coluna, tudo devolve vazio e o comportamento
      # é o de hoje (produto sem material, nenhuma tool com o que oferecer).
      def apresentacao_config
        return {} unless has_attribute?(:apresentacao)

        apresentacao.presence || {}
      end

      def publico_alvo
        apresentacao_config['publico'].presence
      end

      def pecas
        Array(apresentacao_config['pecas']).select { |peca| peca.is_a?(Hash) && peca['id'].present? }
      end

      # Consumo da followup: resolver a peça pelo id que a IA escolheu na lista.
      def peca(id)
        pecas.find { |p| p['id'].to_s == id.to_s }
      end

      # Permissão de o agente TOMAR A INICIATIVA de responder em áudio neste produto. Não é peça
      # nem sequência: é política de público (áudio de empresa é mais invasivo que texto, e o que
      # converte num público irrita outro). Proposto como §4/4 do contrato; ausente = false, então
      # o áudio A PEDIDO do cliente segue funcionando como sempre.
      def audio_proativo?
        apresentacao_config['audio_proativo'] == true
      end
    end
  end
end
