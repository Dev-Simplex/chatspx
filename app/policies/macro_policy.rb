class MacroPolicy < ApplicationPolicy
  # `index?` e `execute?` seguem abertos ao supervisor: agente executa macro dentro da
  # conversa e isso é uso legítimo. Só a GESTÃO (criar/editar/apagar) sai do alcance.
  def index?
    true
  end

  def create?
    !supervisor_settings_blocked?
  end

  def show?
    @record.global? || author?
  end

  def update?
    return false if supervisor_settings_blocked?

    author? || (@account_user.administrator? && @record.global?)
  end

  def destroy?
    return false if supervisor_settings_blocked?

    author? || orphan_record?
  end

  def execute?
    @record.global? || author?
  end

  private

  def author?
    @record.created_by == @account_user.user
  end

  def orphan_record?
    return @account_user.administrator? if @record.created_by.nil? && @record.global?

    false
  end
end
