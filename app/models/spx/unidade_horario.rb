# Horário PADRÃO de uma unidade num dia da semana — a camada que muda raramente.
# O que muda toda semana é exceção, e mora em Spx::UnidadeExcecao.
#
# Mais de uma linha no mesmo `dia_semana` é legítimo e é como se expressa grade partida
# (fecha pro almoço). Linha ausente = dia NÃO cadastrado; linha com `fechada` = dia cadastrado
# como fechado. As duas coisas são diferentes e quem lê precisa poder distinguir.
class Spx::UnidadeHorario < ApplicationRecord
  self.table_name = 'unidade_horarios'

  belongs_to :unidade, class_name: 'Spx::Unidade', inverse_of: :horarios

  # 0 = domingo ... 6 = sábado (convenção do Date#wday).
  validates :dia_semana, presence: true, inclusion: { in: 0..6 }

  scope :do_dia, ->(dia_semana) { where(dia_semana: dia_semana) }

  def faixa
    Spx::Unidade.faixa(fechada: fechada?, abre: abre, fecha: fecha)
  end
end
