# Auditoria de cada decisão do Motor: "conv X → Bruno (rodizio)" / "→ Adrian
# (continuidade)" / "sem_pool". Sem updated_at (só created_at) — registro imutável.
module Spx
  module Distribuicao
    class Log < ApplicationRecord
      self.table_name = 'distribuicao_logs'

      MOTIVOS = %w[continuidade rodizio sem_pool].freeze
    end
  end
end
