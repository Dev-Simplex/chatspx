require 'administrate/field/base'

# Multi-seleção dos times que a pessoa supervisiona NESTA conta. Existe porque
# "supervisor" é sempre supervisor DE ALGUM TIME — oferecer o papel sem dizer
# quais times seria um controle que não faz nada.
class SupervisedTeamsField < Administrate::Field::Base
  # Chega como array no params, então precisa ser permitido como array.
  def self.permitted_attribute(attr, _options = nil)
    { attr => [] }
  end

  # Times da conta do vínculo. Vazio enquanto a conta não foi escolhida (formulário
  # de criação), e aí o campo aparece sem opções em vez de listar a instalação toda.
  def available_teams
    account = resource.account
    return Team.none if account.blank?

    account.teams.order(:name)
  end

  def selected_ids
    Array(data).map(&:to_i)
  end

  def team_names
    available_teams.where(id: selected_ids).pluck(:name)
  end
end
