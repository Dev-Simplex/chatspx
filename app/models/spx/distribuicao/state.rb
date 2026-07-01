# Ponteiro do rodízio por time: quem foi o ÚLTIMO consultor escolhido. O próximo
# do pool (após este) recebe a vez seguinte. 1 linha por time.
module Spx
  module Distribuicao
    class State < ApplicationRecord
      self.table_name = 'distribuicao_states'

      belongs_to :team
    end
  end
end
