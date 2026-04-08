class Api::V1::Accounts::Captain::AssistantLogsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization

  def index
    base_scope = Captain::AssistantLog.joins(:captain_assistant)
                                      .where(captain_assistants: { account_id: Current.account.id })

    base_scope = base_scope.where(captain_assistant_id: params[:assistant_id]) if params[:assistant_id].present?
    base_scope = base_scope.by_event_type(params[:event_type]) if params[:event_type].present?

    @logs = base_scope.ordered.page(params[:page]).per(25)
  end

  private

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.user&.administrator?
  end
end
