# frozen_string_literal: true

# O recorte do relatório de rodízio (time, agente, canal, produto), num lugar só.
#
# Tela, resumo e PDF aplicam ESTE objeto ao livro-razão. Se cada um montasse o próprio `where`,
# bastava um esquecer um filtro para o PDF que vai para a diretoria dizer outra coisa que a tela.
#
# Agente = "só os leads que ESTE agente recebeu" (`chosen_user_id`). O período fica de fora: o
# cartão "parado agora" ignora o período de propósito, e cada chamador põe a janela que precisa.
class Spx::Distribuicao::Recorte
  # Mapa dos canais que a gestão já lê hoje na planilha manual. Fallback = o próprio
  # channel_type, pra canal novo aparecer em vez de sumir.
  CANAIS = {
    'Channel::Whatsapp' => 'WhatsApp',
    'Channel::Api' => 'WhatsApp',
    'Channel::WebWidget' => 'Site',
    'Channel::FacebookPage' => 'Facebook',
    'Channel::Instagram' => 'Instagram',
    'Channel::Email' => 'E-mail'
  }.freeze
  # A tela mostra "—" para lead sem produto; o filtro aceita o mesmo rótulo de volta.
  SEM_PRODUTO = '—'

  attr_reader :team_id, :user_id, :canal, :produto

  def initialize(account:, filtros: {})
    @account = account
    filtros = (filtros || {}).to_h.with_indifferent_access
    @team_id = filtros[:team_id].presence
    @user_id = filtros[:user_id].presence
    @canal = filtros[:canal].presence
    @produto = filtros[:produto].presence
  end

  def self.canal_de(channel_type)
    tipo = channel_type.to_s
    CANAIS[tipo] || tipo.presence || '—'
  end

  def aplicar(escopo)
    escopo = escopo.where(conversation_id: conversas.select(:id)) if team_id || canal
    escopo = escopo.where(chosen_user_id: user_id) if user_id
    escopo = escopo.where(produto_slug: produto == SEM_PRODUTO ? [nil, ''] : produto) if produto
    escopo
  end

  # "Time Vendas · Agente João · WhatsApp · Produto venda". Nil sem filtro nenhum.
  def descricao
    partes = []
    partes << "Time #{nome_do_time}" if team_id
    partes << "Agente #{nome_do_agente}" if user_id
    partes << "Canal #{canal}" if canal
    partes << "Produto #{produto}" if produto
    partes.join(' · ').presence
  end

  # Opções dos seletores. Vêm do histórico da conta (recortado só pelo time), não do período nem
  # dos outros filtros: o agente sem lead no mês continua escolhível, e escolher um canal não
  # some com os demais da lista.
  def opcoes
    base = Spx::Distribuicao::Log.where(account_id: @account.id).where.not(chosen_user_id: nil)
    base = base.where(conversation_id: Conversation.where(account_id: @account.id, team_id: team_id).select(:id)) if team_id
    {
      agentes: User.where(id: base.select(:chosen_user_id)).order(:name).map { |u| { id: u.id, name: u.name } },
      canais: @account.inboxes.distinct.pluck(:channel_type).map { |tipo| self.class.canal_de(tipo) }.uniq.sort,
      produtos: produtos(base)
    }
  end

  private

  def produtos(base)
    base.distinct.pluck(:produto_slug).map { |slug| slug.presence || SEM_PRODUTO }.uniq.sort
  end

  def conversas
    escopo = Conversation.where(account_id: @account.id)
    escopo = escopo.where(team_id: team_id) if team_id
    escopo = escopo.where(inbox_id: @account.inboxes.where(channel_type: tipos_do_canal).select(:id)) if canal
    escopo
  end

  def tipos_do_canal
    tipos = CANAIS.select { |_tipo, rotulo| rotulo == canal }.keys
    tipos.presence || [canal]
  end

  def nome_do_time
    @account.teams.find_by(id: team_id)&.name || "##{team_id}"
  end

  def nome_do_agente
    @account.users.find_by(id: user_id)&.name || "##{user_id}"
  end
end
