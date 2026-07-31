# Livro-razão do Motor: cada decisão vira uma linha ("conv X → Bruno, por continuidade").
#
# Em modo_posse=designacao esta linha É o estado "designado": nasce aberta e fecha quando
# alguém assume, quando o corretor engaja no card do Vista, ou quando uma designação nova
# a substitui. É daqui que saem a tela de contabilização e o SLA-como-medida.
module Spx
  module Distribuicao
    class Log < ApplicationRecord
      self.table_name = 'distribuicao_logs'

      # optional: uma linha `sem_pool` não tem corretor, e conversa deletada não pode
      # derrubar a leitura do histórico.
      belongs_to :conversation, optional: true
      belongs_to :chosen_user, class_name: 'User', optional: true

      MOTIVOS = %w[continuidade rodizio sem_pool preferencia_cliente manual_gestor].freeze
      # designado   — escolhido, ninguém assumiu ainda (só existe em modo_posse=designacao)
      # assumido    — um humano pegou a conversa dentro do SPX
      # engajado    — o corretor mexeu no card do Vista (sinal escrito pela frente spx/eval)
      # expirado    — estourou o SLA e a conversa foi repassada
      # substituido — uma designação nova tomou o lugar desta
      STATUS = %w[designado assumido engajado expirado substituido].freeze

      scope :abertas, -> { where(status: 'designado') }

      # A designação viva de uma conversa, se houver. Mais recente primeiro: um re-handoff
      # pode ter substituído a anterior.
      def self.designacao_aberta(conversation_id)
        abertas.where(conversation_id: conversation_id).order(id: :desc).first
      end

      def encerrar!(status)
        update!(status: status, encerrado_em: Time.current)
      end
    end
  end
end
