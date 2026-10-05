class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :campaign, except: [:index, :create]
  before_action :check_authorization

  # Quantas linhas da audiencia voltam como amostra (o total vai sempre nas stats).
  SAMPLE_SIZE = 50

  def index
    @campaigns = Current.account.campaigns.includes(:inbox, sender: [:teams, { avatar_attachment: :blob }]).order(created_at: :desc)
    @campaigns = @campaigns.page(params[:page]).per(25) if params[:page].present?
  end

  def show; end

  def stats
    render json: campaign_stats
  end

  # Higiene da audiencia em DRY-RUN: mostra quem entra, quem sai e por que, sem
  # gravar destinatario nenhum. E o que impede planejar um disparo em cima de
  # numero errado — o nome do arquivo mente (listas "200" e "380" tinham 100 e 81).
  def audience_preview
    result = Campaigns::Whatsapp::AudienceBuilderService.new(
      campaign: @campaign, rows: recipient_rows, blocklist_phones: blocklist_phones
    ).perform
    render json: audience_payload(result)
  end

  # Carrega a lista (upload) de destinatarios na campanha de disparo, aplicando as
  # MESMAS regras do preview.
  def recipients
    result = Campaigns::Whatsapp::ListLoaderService.new(
      campaign: @campaign, rows: recipient_rows, blocklist_phones: blocklist_phones
    ).perform
    render json: audience_payload(result).merge(
      total: @campaign.campaign_recipients.count,
      pending: @campaign.campaign_recipients.pending.count
    )
  end

  # Inicia/retoma o disparo (dispatch_status: running). O scheduler despacha no pacing.
  # O motivo de um agendamento que não pôde iniciar (`start_error`) sai daqui: iniciar à mão
  # é justamente a resposta a ele.
  def start
    blocker = @campaign.dispatch_start_blocker
    return render json: { error: blocker }, status: :unprocessable_entity if blocker

    @campaign.update!(dispatch_status: :running, dispatch_config: @campaign.dispatch_config.except('start_error'))
    render json: dispatch_state
  end

  # Pausa o disparo mantendo os pendentes (retomar = start).
  def pause
    @campaign.dispatch_paused!
    render json: dispatch_state
  end

  def create
    @campaign = Current.account.campaigns.new(campaign_params)
    # Disparo WhatsApp com horário nasce agendado: o DispatchSchedulerJob o inicia quando a
    # hora chega. Sem horário fica em rascunho e começa pelo botão Iniciar do detalhe.
    @campaign.dispatch_status = :scheduled if @campaign.inbox&.inbox_type == 'Whatsapp' && campaign_params[:scheduled_at].present?
    @campaign.save!
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
                                     :dispatch_assignee_id,
                                     audience: [:type, :id], trigger_rules: {}, template_params: {}, dispatch_config: {})
  end

  # Linhas da lista: ou vieram de uma planilha (`rows`), ou a base as produz a partir de um
  # segmento (`segmento`). Os dois caminhos desembocam AQUI de propósito — assim o preview e
  # o carregamento continuam sendo os mesmos, e a higiene não ganha uma segunda
  # implementação, que seria justamente a que ninguém testou.
  def recipient_rows
    return segmento_rows if params[:segmento].present?

    params.permit(rows: %i[name phone nome telefone])[:rows]&.map(&:to_h) || []
  end

  def segmento_rows
    Campaigns::Whatsapp::SegmentService.new(account: Current.account, filtros: segmento_params).perform.rows
  end

  def segmento_params
    params.require(:segmento).permit(:team_id, :inbox_id, :status, :campaign_id, :sem_campanha,
                                     :excluir_campanha, :ultima_atividade_dias, labels: [])
  end

  # Telefones a excluir vindos de fora da base (ex.: CSV de corretores). A exclusao
  # por etiqueta de contato mora em `dispatch_config['blocklist_labels']`.
  def blocklist_phones
    params.permit(blocklist: [])[:blocklist] || []
  end

  # Amostra + contagem completa. O truncamento e explicito: audiencia que parece
  # limpa porque a lista foi cortada em silencio e pior do que audiencia suja.
  def audience_payload(result)
    {
      stats: result.stats,
      accepted_sample: result.accepted.first(SAMPLE_SIZE).map { |entry| entry.slice(:name, :phone) },
      rejected_sample: result.rejected.first(SAMPLE_SIZE),
      rejected_omitted: [result.rejected.size - SAMPLE_SIZE, 0].max
    }
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
      # A config do disparo vem junto porque a tela do detalhe é onde ela se edita: sem isto
      # o painel abriria vazio e o operador não teria como saber o que está valendo. Sem o
      # `target_team_id`, por exemplo, a conversa nasce sem time e o reply do lead cai sem
      # dono — foi o buraco que a automação de disparo teve que fechar à mão em agosto.
      campaign: { display_id: @campaign.display_id, title: @campaign.title, status: @campaign.campaign_status,
                  target_team_id: @campaign.target_team_id, dispatch_assignee_id: @campaign.dispatch_assignee_id,
                  pacing_seconds: @campaign.pacing_seconds, template_name: @campaign.template_name,
                  dispatch_config: @campaign.dispatch_config },
      dispatch_status: @campaign.dispatch_status,
      dispatch_preview: dispatch_preview,
      recipients: @campaign.campaign_recipients.group(:status).count,
      total: total, reached: reached, sent: sent, delivered: delivered, read: read, failed: failed, replied: replied,
      delivery_rate: total.zero? ? 0 : (reached.to_f / total * 100).round(1),
      read_rate: reached.zero? ? 0 : (read.to_f / reached * 100).round(1),
      distribution: distribution, failures: failures, recent: recent
    }
  end

  # O que o PRÓXIMO destinatário pendente vai receber, já renderizado.
  #
  # A tela que dispara nunca mostrou a mensagem. Foi assim que 124 pessoas receberam
  # "Oi , sou a Kettlen": o parâmetro vazio só ficou visível DEPOIS do envio, lendo o
  # texto enviado — o status não acusa, porque a Meta aceitou.
  #
  # O corpo vem do template APROVADO sincronizado no canal, pelo mesmo catálogo que a
  # engine de captação usa (`TemplateCatalog`, "a mesma lente do envio"), e os parâmetros
  # são montados como em `Campaigns::Whatsapp::RecipientDispatchService#send_hsm`:
  # `default_params` da campanha sobrescritos pelos do destinatário.
  #
  # `nil` quando não há template configurado; `body: nil` quando o template não está
  # sincronizado/aprovado no canal — a tela diz isso em vez de inventar um corpo.
  def dispatch_preview
    return nil if @campaign.template_name.blank?

    descritor = LeadCampaigns::TemplateCatalog.new(@campaign.inbox)
                                              .encontrar(@campaign.template_name, @campaign.template_language)
    proximo = @campaign.campaign_recipients.pending.order(:id).first
    parametros = preview_params(proximo)

    {
      template_name: @campaign.template_name, template_language: @campaign.template_language,
      contact_name: proximo&.name.presence, contact_phone: proximo&.phone_number,
      body: descritor && render_template_body(descritor[:corpo], parametros),
      # Variável que o template exige e o parâmetro não preenche: é a checagem que teria
      # pego o "Oi ," ANTES de sair.
      missing: descritor ? descritor[:variaveis].reject { |nome| parametros[nome.to_s].present? } : []
    }
  end

  def preview_params(recipient)
    bruto = (@campaign.dispatch_config['default_params'] || {}).merge(recipient&.template_params || {})
    bruto.to_h { |chave, valor| [chave.to_s, valor.to_s] }
  end

  # Mesma substituição de `Whatsapp::SendTemplateService#render_synced_body`. Se as duas
  # divergirem, o preview passa a mentir sobre o envio — e um preview que mente é pior que
  # preview nenhum, porque é justamente nele que o operador vai confiar.
  def render_template_body(texto, parametros)
    texto.to_s.gsub(LeadCampaigns::TemplateCatalog::VARIAVEL) { parametros[Regexp.last_match(1).strip].to_s }
  end
end
