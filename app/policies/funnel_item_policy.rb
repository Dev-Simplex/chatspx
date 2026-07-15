# frozen_string_literal: true

class FunnelItemPolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    index? && record.funnel.account_id == account.id
  end

  def create?
    @account_user&.agent? || @account_user&.administrator?
  end

  def update?
    create? && record.funnel.account_id == account.id
  end

  # Kanban v2 (Fase 2): editing custom field values is a card update.
  def custom_attributes?
    update?
  end

  # Bulk operations on the board are agent/admin actions (Fase 3).
  def bulk_move?
    create?
  end

  def bulk_update?
    create?
  end

  # Reordenação manual de cartões dentro de uma coluna (Kanban DB restructure / P1).
  def reorder?
    create?
  end

  def destroy?
    create? && record.funnel.account_id == account.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      target_account = account || Current.account
      return scope.none if target_account.blank?

      scope.joins(:funnel).where(funnels: { account_id: target_account.id })
    end
  end
end
