class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, except: [:index, :create]
  before_action :check_authorization

  def index
    @campaigns = Current.account.campaigns.includes(:inbox, sender: [:teams, { avatar_attachment: :blob }]).order(created_at: :desc)
    @campaigns = @campaigns.page(params[:page]).per(25) if params[:page].present?
  end

  def show; end

  def stats
    render json: campaign_stats
  end

  # Carrega a lista (upload) de destinatarios na campanha de disparo.
  def recipients
    inserted = Campaigns::Whatsapp::ListLoaderService.new(campaign: @campaign, rows: recipient_rows).perform
    render json: { inserted: inserted, total: @campaign.campaign_recipients.count,
                   pending: @campaign.campaign_recipients.pending.count }
  end

  # Inicia/retoma o disparo (dispatch_status: running). O scheduler despacha no pacing.
  def start
    return render json: { error: 'Campanha sem destinatários' }, status: :unprocessable_entity if @campaign.campaign_recipients.empty?
    return render json: { error: 'Defina o template do disparo' }, status: :unprocessable_entity if @campaign.template_name.blank?

    @campaign.dispatch_running!
    render json: dispatch_state
  end

  # Pausa o disparo mantendo os pendentes (retomar = start).
  def pause
    @campaign.dispatch_paused!
    render json: dispatch_state
  end

  def create
    @campaign = Current.account.campaigns.create!(campaign_params)
  end

  def update
    @campaign.update!(campaign_params)
  end

  def destroy
    @campaign.destroy!
    head :ok
  end

  private

  def campaign
    @campaign ||= Current.account.campaigns.find_by!(display_id: params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(:title, :description, :message, :enabled, :trigger_only_during_business_hours, :inbox_id, :sender_id,
                                     :scheduled_at, :template_name, :template_language, :target_team_id, :pacing_seconds,
                                     audience: [:type, :id], trigger_rules: {}, template_params: {}, dispatch_config: {})
  end

  # Linhas da lista enviada (upload): [{name, phone}]. ListLoaderService normaliza e deduplica.
  def recipient_rows
    params.permit(rows: %i[name phone nome telefone])[:rows]&.map(&:to_h) || []
  end

  def dispatch_state
    { dispatch_status: @campaign.dispatch_status, pending: @campaign.campaign_recipients.pending.count,
      total: @campaign.campaign_recipients.count }
  end

  # Agregado read-only de um disparo ancorado nesta campanha (conversas linkadas por
  # campaign_id + status das mensagens-template). Generico: vale pra qualquer campanha
  # WhatsApp cujo orquestrador grave campaign_id nas conversas.
  def campaign_stats # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
    conv_ids = @campaign.conversations.pluck(:id)
    total = conv_ids.size

    outgoing = Message.where(conversation_id: conv_ids, message_type: :outgoing)
                      .where("messages.additional_attributes -> 'template_params' ->> 'name' IS NOT NULL")
    by_status = outgoing.reorder(nil).group(:status).count
    sent = by_status['sent'].to_i
    delivered = by_status['delivered'].to_i
    read = by_status['read'].to_i
    failed = by_status['failed'].to_i
    reached = sent + delivered + read

    replied = Message.where(conversation_id: conv_ids, message_type: :incoming, private: false)
                     .where.not(content: [nil, '']).reorder(nil).distinct.count(:conversation_id)

    dist = Conversation.where(id: conv_ids).where.not(assignee_id: nil).reorder(nil).group(:assignee_id).count
    agent_names = User.where(id: dist.keys).pluck(:id, :name).to_h
    distribution = dist.map { |aid, n| { id: aid, name: agent_names[aid] || "##{aid}", count: n } }
                       .sort_by { |h| -h[:count] }

    codes = Hash.new(0)
    outgoing.where(status: :failed).find_each { |m| codes[m.external_error.to_s[/\A\d+/] || 'outro'] += 1 }
    failures = codes.map { |code, n| { code: code, count: n } }.sort_by { |h| -h[:count] }

    recent = Conversation.where(id: conv_ids).includes(:contact, :assignee)
                         .reorder(last_activity_at: :desc).limit(15).map do |conversation|
      last_in = Message.where(conversation_id: conversation.id, message_type: :incoming, private: false)
                       .where.not(content: [nil, '']).reorder(created_at: :desc).first
      {
        id: conversation.display_id, name: conversation.contact&.name, status: conversation.status,
        agent: conversation.assignee&.name, last_reply: last_in&.content.to_s[0, 80],
        last_activity_at: conversation.last_activity_at
      }
    end

    {
      campaign: { display_id: @campaign.display_id, title: @campaign.title, status: @campaign.campaign_status },
      dispatch_status: @campaign.dispatch_status,
      recipients: @campaign.campaign_recipients.group(:status).count,
      total: total, reached: reached, sent: sent, delivered: delivered, read: read, failed: failed, replied: replied,
      delivery_rate: total.zero? ? 0 : (reached.to_f / total * 100).round(1),
      read_rate: reached.zero? ? 0 : (read.to_f / reached * 100).round(1),
      distribution: distribution, failures: failures, recent: recent
    }
  end
end
