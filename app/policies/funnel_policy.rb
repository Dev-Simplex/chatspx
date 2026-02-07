# frozen_string_literal: true

class FunnelPolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    return false unless index? && record.account_id == account.id
    return false unless @account_user.present?

    if record.team_id.present?
      return false unless @account_user.user.present?

      user_teams = @account_user.user.teams.where(account_id: account.id)
      user_teams.exists?(id: record.team_id)
    else
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

  def reorder_stages?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none unless @account_user.present?

      target_account = account || Current.account
      return scope.none unless target_account.present?

      team_ids = []
      if @account_user.user.present?
        user_teams = @account_user.user.teams.where(account_id: target_account.id)
        team_ids = user_teams.pluck(:id)
      end

      base_scope = scope.where(account_id: target_account.id)
      arel_table = base_scope.arel_table
      conditions = []

      conditions << arel_table[:team_id].in(team_ids) if team_ids.any?
      conditions << arel_table[:team_id].eq(nil) if @account_user.agent? || @account_user.administrator?

      if conditions.any?
        base_scope.where(conditions.reduce(:or))
      else
        scope.none
      end
    rescue StandardError => e
      Rails.logger.error "FunnelPolicy::Scope#resolve: #{e.class}: #{e.message}"
      scope.none
    end
  end
end
