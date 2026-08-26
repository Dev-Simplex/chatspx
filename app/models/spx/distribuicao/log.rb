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

      # repasse_sla     — a designação anterior venceu e o lead passou ao próximo do rodízio
      # escalado_gestor — venceu e o teto de repasses estourou (ou não havia próximo): foi ao
      #                   responsável fixo da política
      # fila            — modo pull: ninguém foi escolhido de propósito; a linha existe só para
      #                   dar relógio à espera
      MOTIVOS = %w[
        continuidade rodizio sem_pool preferencia_cliente manual_gestor
        repasse_sla escalado_gestor fila
      ].freeze
      # designado   — escolhido, ninguém assumiu ainda (só existe em modo_posse=designacao)
      # assumido    — um humano pegou a conversa dentro do SPX
      # engajado    — o corretor mexeu no card do Vista (sinal escrito pela frente spx/eval)
      # expirado    — estourou o SLA e a conversa foi repassada
      # substituido — uma designação nova tomou o lugar desta
      STATUS = %w[designado assumido engajado expirado substituido].freeze

      scope :abertas, -> { where(status: 'designado') }
      # Filtro GROSSO do varredor: usa o relógio de parede (o índice
      # status+designado_em) para trazer candidatas. O prazo real é conferido depois, no
      # relógio comercial de cada política — só que aí sobre dezenas de linhas, não sobre a
      # tabela inteira.
      scope :designadas_antes_de, ->(instante) { abertas.where(designacao_em_ate(instante)) }

      def self.designacao_em_ate(instante)
        arel_table[:designado_em].lteq(instante)
      end

      # A designação viva de uma conversa, se houver. Mais recente primeiro: um re-handoff
      # pode ter substituído a anterior.
      def self.designacao_aberta(conversation_id)
        abertas.where(conversation_id: conversation_id).order(id: :desc).first
      end

      def encerrar!(status)
        update!(status: status, encerrado_em: Time.current)
      end

      # Ninguém encostou: nem humano assumiu (o listener fecharia como `assumido`) nem o
      # corretor engajou no card. Reconferido na hora do repasse porque entre a varredura e o
      # processamento a conversa pode ter sido resolvida por gente.
      def parada?
        status == 'designado' && encerrado_em.nil?
      end

      # Designação de modo PUSH (`modo_posse: assignee`) aberta pelo repasse: aqui "designado"
      # significa *atribuído e ainda sem primeira resposta*. A distinção importa porque nesse
      # modo o próprio Motor grava o assignee — sem ela o evento de atribuição fecharia a linha
      # no mesmo instante em que ela nasce, e o SLA nunca teria o que medir.
      def aguarda_primeira_resposta?
        (policy_snapshot || {})['modo_posse'] == 'assignee'
      end
    end
  end
end
