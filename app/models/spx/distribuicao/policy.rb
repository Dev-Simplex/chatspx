# Política de distribuição POR TIME. Opt-in: sem policy (ou modo != rodizio) o
# Motor é no-op e a conversa segue no fluxo atual ("Aguardando atendimento").
# Tudo aqui é editável (UI "Política de Distribuição" = F3; F1 = rake/console).
module Spx
  module Distribuicao
    class Policy < ApplicationRecord
      self.table_name = 'distribuicao_policies'

      belongs_to :account
      belongs_to :team

      # rodizio — push: o Motor escolhe a pessoa e (conforme modo_posse) atribui ou designa.
      # fila    — pull: o Motor NÃO escolhe ninguém; a conversa fica sem dono na aba
      #           "Aguardando atendimento" e o primeiro que puxar leva. Existe como MODO (e não
      #           só como "não configurar política") para que a fila também tenha relógio: abre
      #           uma designação sem `chosen_user_id`, e é isso que dá ao pull o mesmo
      #           `sla_assumir_minutos` e a mesma escalação do push. Sem ninguém para quem
      #           repassar, o vencimento de uma fila escala direto ao destino de pool esgotado.
      # online  — reservado (F2 da MOTOR-DISTRIBUICAO): distribuir só a quem está online.
      # off     — no-op explícito.
      MODOS = %w[rodizio fila online off].freeze
      # Quem fica com a POSSE da conversa depois que o Motor escolhe alguém:
      #   assignee   — atribui o humano (o espelho captain cai pelo callback de
      #                exclusividade e a IA cala). É o comportamento de sempre.
      #   designacao — só registra a designação; `assignee` segue nulo, o espelho
      #                sobrevive e a IA continua atendendo até alguém assumir.
      MODOS_POSSE = %w[assignee designacao].freeze

      validates :modo, inclusion: { in: MODOS }
      validates :modo_posse, inclusion: { in: MODOS_POSSE }
      validates :team_id, uniqueness: { scope: :account_id }
      validates :sla_assumir_minutos, numericality: { greater_than: 0 }
      # 0 = repassa indefinidamente enquanto houver pool. O teto existe para o caso oposto:
      # rodar o pool inteiro num lead que ninguém quer é ruído para todo mundo.
      validates :max_repasses, numericality: { greater_than_or_equal_to: 0 }

      belongs_to :pool_esgotado_destino, class_name: 'User', optional: true

      scope :ativas, -> { where(ativo: true) }

      # Política ativa do time, ou nil.
      def self.for_team(account_id, team_id)
        ativas.find_by(account_id: account_id, team_id: team_id)
      end

      # Entradas ativas do pool, na ORDEM configurada (o rodízio anda nessa ordem).
      # pool = jsonb [{ "user_id" => 128, "ativo" => true, "cap" => 20,
      #                 "produtos" => [{ "produto" => <slug>, "valor_max" => <int> }] }, ...]
      def pool_entries
        (pool || []).select { |e| e['ativo'] != false }
      end

      def designacao?
        modo_posse == 'designacao'
      end

      def fila?
        modo == 'fila'
      end

      # O Motor só age nestes modos. `online` e `off` seguem no-op.
      MODOS_QUE_DISTRIBUEM = %w[rodizio fila].freeze

      def distribui?
        MODOS_QUE_DISTRIBUEM.include?(modo)
      end

      # O repasse por SLA vale para toda política ativa que distribui — não há interruptor.
      #
      # A ÚNICA exclusão é por motivo, não por toggle: política com `espelho_vista` não repassa
      # porque o card do lead já existe no Vista no nome do corretor escolhido. Passar o lead
      # adiante exigiria reescrever o `CorretorNegocio` de um card existente (capacidade não
      # testada) e o `DELETE` do Vista responde 401 — não há como desfazer. Errar aí custa um
      # lead que o corretor já estava trabalhando, o que é pior que o lead ficar parado.
      # Nesses times o `sla_assumir_minutos` segue valendo como MEDIDA na tela do gestor.
      def repassa?
        ativo? && distribui? && !espelho_vista? && sla_assumir_minutos.to_i.positive?
      end

      # Teto de repasses atingido? `max_repasses` zero = sem teto.
      def esgotou_repasses?(repasse_n)
        max_repasses.to_i.positive? && repasse_n.to_i >= max_repasses.to_i
      end
    end
  end
end
