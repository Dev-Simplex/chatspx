# frozen_string_literal: true

class FunnelStagePolicy < ApplicationPolicy
  def index?
    @account_user&.agent? || @account_user&.administrator?
  end

  def show?
    index? && record.funnel.account_id == account.id
  end

  # Ver a etapa é trabalho de atendimento; MEXER na etapa é desenhar o processo, e
  # isso é de administrador. Um agente que renomeia, recoloriza, muda limite/SLA ou
  # apaga coluna altera o quadro de todo mundo.
  def create?
    @account_user&.administrator?
  end

  def update?
    create? && record.funnel.account_id == account.id
  end

  def destroy?
    create? && record.funnel.account_id == account.id
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      return scope.none if account.blank?

      target_account = account || Current.account
      return scope.none if target_account.blank?

      scope.joins(:funnel).where(funnels: { account_id: target_account.id })
    end
  end
end
