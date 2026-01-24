# frozen_string_literal: true

class FunnelPolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    return false unless index? && record.account_id == account.id
    return false unless @account_user.present?
    
    # Verificar se usuário pertence ao time do funil ou se é funil padrão
    if record.team_id.present?
      return false unless @account_user.user.present?
      user_teams = @account_user.user.teams.where(account_id: account.id)
      user_teams.exists?(id: record.team_id)
    else
      # Funil padrão (team_id = NULL) - acessível para agentes e administradores
      @account_user.agent? || @account_user.administrator?
    end
  end

  def create?
    @account_user&.agent? || @account_user&.administrator?
  end

  def update?
    create? && record.account_id == account.id
  end

  def destroy?
    create? && record.account_id == account.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      begin
        return scope.none unless @account_user.present?
        
        # Usar Current.account se account não estiver disponível no contexto
        target_account = account || Current.account
        return scope.none unless target_account.present?
        
        # Filtrar funis dos times do usuário
        team_ids = []
        if @account_user.user.present?
          user_teams = @account_user.user.teams.where(account_id: target_account.id)
          team_ids = user_teams.pluck(:id)
        end
        
        # Construir query base com account_id
        base_scope = scope.where(account_id: target_account.id)
        
        # Construir condições separadas para team_id e nil usando arel_table
        arel_table = base_scope.arel_table
        conditions = []
        
        # Adicionar funis dos times do usuário
        if team_ids.any?
          conditions << arel_table[:team_id].in(team_ids)
        end
        
        # Adicionar funil padrão se usuário for agent ou administrator
        if @account_user.agent? || @account_user.administrator?
          conditions << arel_table[:team_id].eq(nil)
        end
        
        # Combinar condições
        if conditions.any?
          # Usar where com OR usando arel
          base_scope.where(conditions.reduce(:or))
        else
          scope.none
        end
      rescue StandardError => e
        Rails.logger.error "FunnelPolicy::Scope#resolve: Erro - #{e.class}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        scope.none
      end
    end
  end
end


