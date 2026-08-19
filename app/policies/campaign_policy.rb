class CampaignPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def stats?
    @account_user.administrator?
  end

  def recipients?
    @account_user.administrator?
  end

  def start?
    @account_user.administrator?
  end

  def pause?
    @account_user.administrator?
  end

  # 4.22 — importar desativa a campanha e reescreve a configuracao da inbox: e escrita
  # em duas entidades, entao pede o mesmo nivel de quem pode editar campanha.
  def import_to_trigger?
    @account_user.administrator?
  end
end
