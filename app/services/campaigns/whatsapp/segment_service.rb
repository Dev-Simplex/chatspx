# Monta a lista a partir da BASE, em vez de uma planilha. Devolve exatamente o mesmo
# formato de `rows` que o upload produz — `[{ name:, phone: }]` — para que o
# AudienceBuilderService continue sendo o único lugar que decide quem entra e por quê.
# Sem isso haveria duas higienes, e a do segmento seria a que ninguém testou.
#
# Os critérios são os que a operação de fato usa para escolher público, e cada um existe
# por um caso real:
#
#   labels           — o balde mais usado ("pacaembu", "anuncio")
#   team_id          — a carteira de um corretor
#   inbox_id         — separar quem veio do WhatsApp de quem veio do Instagram
#   campaign_id      — repescar quem recebeu (ou NÃO recebeu) um disparo anterior; foi a
#                      falta disto que fez 294 pessoas levarem o mesmo assunto duas vezes
#   sem_campanha     — quem nunca recebeu disparo nenhum
#   ultima_atividade — recência, para não bater em quem sumiu há um ano
#   status           — conversa aberta é atendimento em andamento; o disparo não atropela
#                      (o AudienceBuilder já descarta, aqui é só não trazer)
#
# Critérios se somam (E), nunca se alternam: público que cresce por engano é o jeito mais
# rápido de mandar campanha para quem não devia.
class Campaigns::Whatsapp::SegmentService
  LIMITE = 20_000

  Result = Struct.new(:rows, :total, keyword_init: true)

  def initialize(account:, filtros: {})
    @account = account
    @filtros = (filtros || {}).with_indifferent_access
  end

  def perform
    escopo = contatos
    total = escopo.count
    Result.new(rows: linhas(escopo.limit(LIMITE)), total: total)
  end

  private

  attr_reader :account, :filtros

  def contatos
    escopo = account.contacts.where.not(phone_number: [nil, ''])
    escopo = por_label(escopo)
    escopo = por_conversa(escopo)
    escopo = por_campanha(escopo)
    por_atividade(escopo)
  end

  def por_label(escopo)
    labels = Array(filtros[:labels]).reject(&:blank?)
    return escopo if labels.empty?

    escopo.tagged_with(labels, any: true)
  end

  # Time e caixa são atributos da CONVERSA, não do contato: quem tem alguma conversa que
  # bate no critério entra.
  def por_conversa(escopo)
    conv = conversas_filtradas
    return escopo if conv.nil?

    escopo.where(id: conv.select(:contact_id))
  end

  def conversas_filtradas
    conv = account.conversations
    aplicou = false
    if filtros[:team_id].present?
      conv = conv.where(team_id: filtros[:team_id])
      aplicou = true
    end
    if filtros[:inbox_id].present?
      conv = conv.where(inbox_id: filtros[:inbox_id])
      aplicou = true
    end
    if filtros[:status].present?
      conv = conv.where(status: filtros[:status])
      aplicou = true
    end
    aplicou ? conv : nil
  end

  # Recebeu OU não recebeu um disparo. As duas fontes contam — o motor antigo carimbava
  # `campaign_id` na conversa e não criava `campaign_recipients`, e ler só a tabela nova
  # deixou passar 294 pessoas que já tinham recebido.
  def por_campanha(escopo)
    id = filtros[:campaign_id]
    return escopo if id.blank? && !filtros[:sem_campanha]

    alcancados = filtros[:sem_campanha] ? ja_receberam_qualquer : ja_receberam(id)
    return escopo.where.not(id: alcancados) if filtros[:sem_campanha] || filtros[:excluir_campanha]

    escopo.where(id: alcancados)
  end

  def ja_receberam(campaign_id)
    recipients = CampaignRecipient.where(campaign_id: campaign_id).select(:contact_id)
    conversas = account.conversations.where(campaign_id: campaign_id).select(:contact_id)
    Contact.where(id: recipients).or(Contact.where(id: conversas)).select(:id)
  end

  def ja_receberam_qualquer
    recipients = CampaignRecipient.joins(:campaign).where(campaigns: { account_id: account.id }).select(:contact_id)
    conversas = account.conversations.where.not(campaign_id: nil).select(:contact_id)
    Contact.where(id: recipients).or(Contact.where(id: conversas)).select(:id)
  end

  def por_atividade(escopo)
    dias = filtros[:ultima_atividade_dias].presence&.to_i
    return escopo if dias.blank? || dias.zero?

    recentes = account.conversations.where(last_activity_at: dias.days.ago..).select(:contact_id)
    escopo.where(id: recentes)
  end

  # `name` vai vazio quando o contato não tem nome de verdade: nome fabricado vira
  # saudação errada no template, e o padrão de falha conhecido é o token do próprio
  # template virando nome da pessoa.
  def linhas(escopo)
    escopo.pluck(:name, :phone_number).map do |nome, telefone|
      { name: nome.to_s.strip, phone: telefone }
    end
  end
end
