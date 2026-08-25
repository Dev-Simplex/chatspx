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

      # Entradas DISPONÍVEIS do pool, na ORDEM configurada (o rodízio anda nessa ordem).
      # pool = jsonb [{ "user_id" => 128, "ativo" => true, "suspenso_ate" => "2026-08-30",
      #                 "motivo" => "férias", "cap" => 20,
      #                 "produtos" => [{ "produto" => <slug>, "valor_max" => <int> }] }, ...]
      def pool_entries
        (pool || []).select { |e| disponivel?(e) }
      end

      # Duas formas de ficar de fora, DIFERENTES de propósito:
      #
      #   ativo: false   → indefinido. Saiu da equipe, está sendo pausado sem data.
      #                    Só volta quando alguém religar.
      #   suspenso_ate   → temporário e previsto (férias, folga, treinamento).
      #                    VOLTA SOZINHO no dia seguinte à data.
      #
      # A segunda existe porque exceção que não morre sozinha vira regra: com só o booleano,
      # alguém tem que lembrar de reativar depois das férias — e ninguém lembra. Era a única
      # forma de pausar até aqui, e é por isso que "pausa" e "punição" viraram a mesma coisa.
      def disponivel?(entry)
        return false unless entry.is_a?(Hash)
        return false if entry['ativo'] == false

        !suspenso?(entry)
      end

      # A data é INCLUSIVA: "suspenso até 30/08" recebe de novo em 31/08.
      #
      # Data ilegível NÃO suspende. Excluir alguém do rodízio por causa de um campo mal
      # digitado é pior que incluir: o efeito de incluir é um lead a mais; o de excluir é
      # alguém sumir da fila sem ninguém entender por quê.
      def suspenso?(entry)
        bruto = entry['suspenso_ate']
        return false if bruto.blank?

        ate = bruto.respond_to?(:to_date) ? bruto.to_date : Date.parse(bruto.to_s)
        Time.zone.today <= ate
      rescue ArgumentError, TypeError
        false
      end

      # Por que a pessoa está fora — para a tela dizer, em vez de só omitir.
      # nil = está dentro.
      def indisponibilidade(entry)
        return :invalido unless entry.is_a?(Hash)
        return nil if disponivel?(entry)
        return :desativado if entry['ativo'] == false

        :suspenso
      end

      def designacao?
        modo_posse == 'designacao'
      end

      def fila?
        modo == 'fila'
      end

      # O Motor só age nestes modos. `online` e `off` seguem no-op.
      def distribui?
        %w[rodizio fila].include?(modo)
      end

      # A AÇÃO de repasse. Desligado (default), `sla_assumir_minutos` continua sendo apenas a
      # medida que a tela do gestor lê — o comportamento de quem já está no ar.
      def repassa?
        ativo? && repasse_automatico?
      end

      # Teto de repasses atingido? `max_repasses` zero = sem teto.
      def esgotou_repasses?(repasse_n)
        max_repasses.to_i.positive? && repasse_n.to_i >= max_repasses.to_i
      end
    end
  end
end
