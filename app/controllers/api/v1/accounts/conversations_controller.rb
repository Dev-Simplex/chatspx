class Api::V1::Accounts::ConversationsController < Api::V1::Accounts::BaseController
  include Events::Types
  include HmacConcern

  before_action :conversation, except: [:index, :meta, :search, :create, :filter]
  before_action :inbox, :contact, :contact_inbox, only: [:create]
  before_action :authorize_team_access,
                only: [:show, :update, :destroy, :attachments, :mute, :unmute, :transcript, :toggle_status, :toggle_priority, :toggle_typing_status,
                       :update_last_seen, :unread, :custom_attributes]

  ATTACHMENT_RESULTS_PER_PAGE = 20

  def index
    result = conversation_finder.perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
    @next_cursor = result[:next_cursor]
    @list_preloaded = Conversations::ListPreloader.call(@conversations)
  end

  def meta
    result = conversation_finder.perform_counts_only
    @conversations_count = result[:count]
  end

  def search
    result = conversation_finder.perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
    @list_preloaded = Conversations::ListPreloader.call(@conversations)
  end

  def attachments
    base_scope = @conversation.attachments
                              .includes(
                                { file_attachment: [:blob] },
                                { message: { sender: { avatar_attachment: [:blob] } } }
                              )
                              .order(created_at: :desc)
    @attachments = base_scope.page(attachment_params[:page]).per(ATTACHMENT_RESULTS_PER_PAGE)
    @attachments_count = @attachments.total_count
  end

  def show; end

  def create
    ActiveRecord::Base.transaction do
      @conversation = ConversationBuilder.new(params: params, contact_inbox: @contact_inbox).perform
      Messages::MessageBuilder.new(Current.user, @conversation, params[:message]).perform if params[:message].present?
    end
  end

  def update
    @conversation.update!(permitted_update_params)
  end

  def filter
    result = ::Conversations::FilterService.new(permitted_filter_params, current_user, current_account).perform
    @conversations = result[:conversations]
    @conversations_count = result[:count]
    @list_preloaded = Conversations::ListPreloader.call(@conversations)
  rescue CustomExceptions::CustomFilter::InvalidAttribute,
         CustomExceptions::CustomFilter::InvalidOperator,
         CustomExceptions::CustomFilter::InvalidQueryOperator,
         CustomExceptions::CustomFilter::InvalidValue => e
    render_could_not_create_error(e.message)
  end

  def mute
    @conversation.mute!
    head :ok
  end

  def unmute
    @conversation.unmute!
    head :ok
  end

  def transcript
    render json: { error: 'email param missing' }, status: :unprocessable_entity and return if params[:email].blank?

    ConversationReplyMailer.with(account: @conversation.account).conversation_transcript(@conversation, params[:email])&.deliver_later
    head :ok
  end

  def toggle_status
    Conversations::ToggleStatusService.new(conversation: @conversation, params: params, user: Current.user).perform
  rescue Conversations::ToggleStatusService::TeamRequiredError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def toggle_priority
    @conversation.toggle_priority(params[:priority])
    head :ok
  end

  def toggle_typing_status
    typing_status_manager = ::Conversations::TypingStatusManager.new(@conversation, current_user, params)
    typing_status_manager.toggle_typing_status
    head :ok
  end

  def update_last_seen
    update_last_seen_on_conversation(DateTime.now.utc, assignee?)
  end

  def unread
    last_incoming_message = @conversation.messages.incoming.last
    last_seen_at = last_incoming_message.created_at - 1.second if last_incoming_message.present?
    update_last_seen_on_conversation(last_seen_at, true)
  end

  def custom_attributes
    @conversation.custom_attributes = params.permit(custom_attributes: {})[:custom_attributes]
    @conversation.save!
  end

  def destroy
    authorize @conversation, :destroy?
    ::DeleteObjectJob.perform_later(@conversation.class.name, @conversation.id, Current.user&.id, request.ip)
    head :ok
  end

  private

  def permitted_filter_params
    params.permit(:page, payload: [:attribute_key, :filter_operator, :query_operator, :custom_attribute_type, { values: [] }])
  end

  def permitted_update_params
    # TODO: Move the other conversation attributes to this method and remove specific endpoints for each attribute
    params.permit(:priority)
  end

  def attachment_params
    params.permit(:page)
  end

  def update_last_seen_on_conversation(last_seen_at, update_assignee)
    # rubocop:disable Rails/SkipsModelValidations
    cols = { agent_last_seen_at: last_seen_at }
    cols[:assignee_last_seen_at] = last_seen_at if update_assignee.present?
    @conversation.update_columns(cols)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def conversation
    @conversation ||= Current.account.conversations.find_by!(display_id: params[:id])
    authorize @conversation, :show?
  end

  def inbox
    return if params[:inbox_id].blank?

    @inbox = Current.account.inboxes.find(params[:inbox_id])
    authorize @inbox, :show?
  end

  def contact
    return if params[:contact_id].blank?

    @contact = Current.account.contacts.find(params[:contact_id])
  end

  def contact_inbox
    @contact_inbox = build_contact_inbox

    # fallback for the old case where we do look up only using source id
    # In future we need to change this and make sure we do look up on combination of inbox_id and source_id
    # and deprecate the support of passing only source_id as the param
    @contact_inbox ||= ::ContactInbox.find_by!(source_id: params[:source_id])
    authorize @contact_inbox.inbox, :show?
  rescue ActiveRecord::RecordNotUnique
    render json: { error: 'source_id should be unique' }, status: :unprocessable_entity
  end

  def build_contact_inbox
    return if @inbox.blank? || @contact.blank?

    ContactInboxBuilder.new(
      contact: @contact,
      inbox: @inbox,
      source_id: params[:source_id],
      hmac_verified: hmac_verified?
    ).perform
  end

  def conversation_finder
    @conversation_finder ||= ConversationFinder.new(Current.user, params)
  end

  def assignee?
    @conversation.assignee_id? && Current.user == @conversation.assignee
  end

  def authorize_team_access
    return if Current.user.is_a?(AgentBot)
    return if Current.user.administrator?
    return if @conversation.team_id.nil?

    validate_team_param_access if params[:team_id].present?
    return if performed?

    # Block access if the user is not a member of the conversation's team
    return if Current.user.teams.exists?(id: @conversation.team_id)

    render json: { error: 'You do not have permission to access this conversation.' }, status: :forbidden
  end

  def validate_team_param_access
    team_id = params[:team_id].to_i

    unless Current.user.teams.exists?(id: team_id)
      render json: { error: 'You do not have permission to access this team.' }, status: :forbidden
      return
    end

    return if @conversation.team_id == team_id

    render json: { error: 'Conversation does not belong to this team.' }, status: :forbidden
  end
end

Api::V1::Accounts::ConversationsController.prepend_mod_with('Api::V1::Accounts::ConversationsController')
