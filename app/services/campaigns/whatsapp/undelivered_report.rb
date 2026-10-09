# Quem NAO recebeu a campanha e por que: falhou no envio (Meta ou erro interno) ou foi barrado
# antes de sair. As contagens do stats dizem quantos; isto diz QUEM, para o operador corrigir o
# cadastro e reenviar. `type` filtra (failed | blocked); sem ele, os dois.
class Campaigns::Whatsapp::UndeliveredReport
  include Rails.application.routes.url_helpers

  PER_PAGE = 25
  CSV_HEADERS = %w[name phone status reason detail date conversation].freeze

  pattr_initialize [:campaign!, :type]

  def page(number)
    records = scope.page(number).per(PER_PAGE)
    { meta: { total: records.total_count, page: records.current_page, per_page: PER_PAGE },
      payload: records.map { |recipient| json_row(recipient) } }
  end

  # `;`, BOM e data dd/mm/aaaa: e o que o Excel em pt-BR abre direto, com acento e coluna no
  # lugar. CSVSafe neutraliza celula que comece com = + - @ (nome vindo de planilha nao vira
  # formula). Cabecalho e motivo seguem o idioma da requisicao.
  def to_csv
    csv = CSVSafe.generate(col_sep: ';') do |rows|
      rows << CSV_HEADERS.map { |col| I18n.t("campaigns.undelivered.csv.#{col}") }
      scope.reorder(:id).find_each { |recipient| rows << csv_row(recipient) }
    end
    "\uFEFF#{csv}"
  end

  private

  def scope
    statuses = CampaignRecipient::UNDELIVERED_STATUSES[type] || CampaignRecipient::UNDELIVERED_STATUSES.values.flatten
    campaign.campaign_recipients.where(status: statuses).includes(:conversation).order(updated_at: :desc, id: :desc)
  end

  def json_row(recipient)
    { id: recipient.id, name: recipient.name, phone_number: recipient.phone_number, status: recipient.status,
      reason_code: recipient.reason_code, reason: recipient.reason_label, error: recipient.external_error,
      at: occurred_at(recipient).to_i, contact_id: recipient.contact_id, conversation_id: recipient.conversation&.display_id }
  end

  def csv_row(recipient)
    conversation = recipient.conversation
    [recipient.name, recipient.phone_number, I18n.t("campaigns.undelivered.statuses.#{recipient.status}"),
     recipient.reason_label, recipient.external_error, occurred_at(recipient).strftime('%d/%m/%Y %H:%M'),
     conversation && app_account_conversation_url(account_id: campaign.account_id, id: conversation.display_id)]
  end

  # `failed_at` so vem do webhook da Meta; pulado e falha interna ficam com o ultimo update.
  def occurred_at(recipient)
    recipient.failed_at || recipient.updated_at
  end
end
