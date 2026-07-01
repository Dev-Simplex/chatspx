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
      validates :modo, inclusion: { in: MODOS }
      validates :team_id, uniqueness: { scope: :account_id }

      scope :ativas, -> { where(ativo: true) }

      # Política ativa do time, ou nil.
      def self.for_team(account_id, team_id)
        ativas.find_by(account_id: account_id, team_id: team_id)
      end

      # Entradas ativas do pool, na ORDEM configurada (o rodízio anda nessa ordem).
      # pool = jsonb [{ "user_id" => 128, "ativo" => true, "cap" => 20 }, ...]
      def pool_entries
        (pool || []).select { |e| e['ativo'] != false }
      end
    end
  end
end
