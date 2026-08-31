# frozen_string_literal: true

# Chat interno (Módulo B, B1) — the people the current user can start a DM with:
# every other confirmed member of the account.
class Api::V1::Accounts::InternalChatAgentsController < Api::V1::Accounts::BaseController
  include InternalChatFeatureGuard

  before_action :check_authorization

  def index
    @agents = Current.account.users.where.not(id: Current.user.id).order(:name)
  end

  private

  def check_authorization
    authorize(InternalChannel)
  end
end
