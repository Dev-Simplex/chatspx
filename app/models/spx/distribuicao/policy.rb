# Política de distribuição POR TIME. Opt-in: sem policy (ou modo != rodizio) o
# Motor é no-op e a conversa segue no fluxo atual ("Aguardando atendimento").
# Tudo aqui é editável (UI "Política de Distribuição" = F3; F1 = rake/console).
module Spx
  module Distribuicao
    class Policy < ApplicationRecord
      self.table_name = 'distribuicao_policies'

      belongs_to :account
      belongs_to :team

      MODOS = %w[rodizio online off].freeze
      # Quem fica com a POSSE da conversa depois que o Motor escolhe alguém:
      #   assignee   — atribui o humano (o espelho captain cai pelo callback de
      #                exclusividade e a IA cala). É o comportamento de sempre.
      #   designacao — só registra a designação; `assignee` segue nulo, o espelho
      #                sobrevive e a IA continua atendendo até alguém assumir.
      MODOS_POSSE = %w[assignee designacao].freeze

      validates :modo, inclusion: { in: MODOS }
      validates :modo_posse, inclusion: { in: MODOS_POSSE }
      validates :team_id, uniqueness: { scope: :account_id }

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
    end
  end
end
