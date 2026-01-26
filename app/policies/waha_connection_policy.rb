# frozen_string_literal: true

class WahaConnectionPolicy < ApplicationPolicy
  def index?
    @account_user.administrator?
  end

  def create?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator?
  end

  def qr_code?
    @account_user.administrator?
  end

  def connect?
    @account_user.administrator?
  end

  def disconnect?
    @account_user.administrator?
  end

  def restart?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end
end


