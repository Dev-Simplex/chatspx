class NpsResponsePolicy < ApplicationPolicy
  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def metrics?
    @account_user.administrator? || @account_user.agent?
  end

  def download?
    @account_user.administrator?
  end

  def send_survey?
    @account_user.administrator? || @account_user.agent?
  end

  def view_comments?
    # By default, all agents can view comments
    # Can be restricted to admins/supervisors if needed
    @account_user.administrator? || @account_user.agent?
  end
end

NpsResponsePolicy.prepend_mod_with('NpsResponsePolicy')
