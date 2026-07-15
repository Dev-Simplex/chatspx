# frozen_string_literal: true

class FunnelPolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    return false unless index? && record.account_id == account.id
    return false if @account_user.blank?

    if record.team_id.present?
      return false if @account_user.user.blank?

      user_team_ids.include?(record.team_id)
    else
      # funil "Geral" (default, team_id nil) → só admin (agente não vê mais "tudo")
      @account_user.administrator?
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

  # Kanban v2 (Fase 6): reading the dashboard is a read on the funnel.
  def stats?
    show?
  end

  # Kanban v2 (Fase 8): configuring the public form is a funnel update.
  def form?
    update?
  end

  # Kanban v2 (Fase 8): templates catalog + instantiation.
  def templates?
    index?
  end

  def create_from_template?
    create?
  end

  private

  def user_team_ids
    @user_team_ids ||= @account_user.user.teams.where(account_id: account.id).pluck(:id)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      return scope.none if @account_user.blank?

      target_account = account || Current.account
      return scope.none if target_account.blank?

      team_ids = user_team_ids(target_account)

      base_scope = scope.where(account_id: target_account.id)
      # Admin enxerga todos os funis da conta (inclusive de times que não participa)
      return base_scope if @account_user.administrator?

      arel_table = base_scope.arel_table
      conditions = []

      conditions << arel_table[:team_id].in(team_ids) if team_ids.any?
      # funil "Geral" (default, team_id nil) só entra no escopo do admin; agente vê só os funis dos seus times
      conditions << arel_table[:team_id].eq(nil) if @account_user.administrator?

      if conditions.any?
        base_scope.where(conditions.reduce(:or))
      else
        scope.none
      end
    rescue ActiveRecord::StatementInvalid => e
      Rails.logger.error "FunnelPolicy::Scope#resolve: #{e.class}: #{e.message}"
      scope.none
    end

    private

    def user_team_ids(target_account)
      @user_team_ids ||= {}
      @user_team_ids[target_account.id] ||= if @account_user.user.present?
                                              @account_user.user.teams.where(account_id: target_account.id).pluck(:id)
                                            else
                                              []
                                            end
    end
  end
end
