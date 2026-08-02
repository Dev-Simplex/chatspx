# Tela de contabilização do rodízio (docs/clientes/tozi/SPEC-RODIZIO.md §9).
#
# VIEWER: lê o livro-razão (`distribuicao_logs`) e responde "quem recebeu quanto, sob qual
# regra, e o que está parado". Não decide e não altera nada.
#
# Por que a quebra POR MOTIVO não é enfeite: o número "recebidos" sozinho MENTE. Quem tem
# carteira grande recebe mais por continuidade e parece privilegiado sem ser; e quem aparece
# com muito `preferencia_cliente` pode estar furando o rodízio pelo pedido do cliente — que é
# a única porta de bypass que sobrou por desenho.
#
# Read-only e defensivo: seção que falhar volta vazia em vez de derrubar a tela.
class Api::V1::Accounts::DistribuicaoDashboardController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :ensure_admin

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

  def show
    render json: {
      periodo: { de: periodo.first, ate: periodo.last },
      times: times_com_politica,
      linhas: linhas,
      totais: totais,
      sem_movimento: sem_movimento
    }
  end

  # Drill-down: "por que ESTE lead foi pra ESTE corretor". Devolve motivo, candidatos e a
  # política que valia NA HORA — é para isso que o snapshot existe.
  def designacoes
    registros = escopo_periodo.where(conversation_id: params[:conversation_id]).order(id: :desc).limit(20)
    render json: { designacoes: registros.map { |log| serializar_designacao(log) } }
  end

  private

  def ensure_admin
    render json: { error: I18n.t('errors.access_denied') }, status: :unauthorized unless Current.account_user&.administrator?
  end

  # ------------------------------------------------------------------ escopo

  # Mês corrente por padrão: é a janela que a gestão já usa (uma aba por mês na planilha).
  def periodo
    return @periodo if defined?(@periodo)

    de = params[:de].present? ? Time.zone.parse(params[:de].to_s) : Time.zone.now.beginning_of_month
    ate = params[:ate].present? ? Time.zone.parse(params[:ate].to_s) : Time.zone.now.end_of_month
    @periodo = [de, ate]
  rescue StandardError
    @periodo = [Time.zone.now.beginning_of_month, Time.zone.now.end_of_month]
  end

  def escopo_periodo
    escopo = Spx::Distribuicao::Log.where(account_id: Current.account.id, created_at: periodo.first..periodo.last)
    escopo = escopo.where(conversation_id: conversas_do_time) if params[:team_id].present?
    escopo
  end

  def conversas_do_time
    Conversation.where(account_id: Current.account.id, team_id: params[:team_id]).select(:id)
  end

  # Só decisões com corretor entram na contagem: `sem_pool` é auditoria, não lead recebido.
  def decisoes
    @decisoes ||= escopo_periodo.where.not(chosen_user_id: nil)
                                .includes(:chosen_user, conversation: :inbox)
                                .to_a
  end

  def times_com_politica
    Spx::Distribuicao::Policy.ativas.where(account_id: Current.account.id)
                             .includes(:team)
                             .filter_map { |p| p.team && { id: p.team.id, name: p.team.name, modo_posse: p.modo_posse } }
  rescue StandardError
    []
  end

  # ------------------------------------------------------------------ linhas

  def linhas
    abertas = decisoes.group_by(&:chosen_user_id)
    abertas.map do |user_id, registros|
      {
        user_id: user_id,
        nome: registros.first.chosen_user&.name,
        recebidos: registros.size,
        motivos: contar(registros, &:motivo),
        canais: contar(registros) { |log| canal(log) },
        produtos: contar(registros) { |log| log.produto_slug.presence || '—' },
        abertos: registros.count { |log| log.status == 'designado' }
      }
    end.sort_by { |linha| -linha[:recebidos] }
  rescue StandardError
    []
  end

  def totais
    {
      recebidos: decisoes.size,
      por_motivo: contar(decisoes, &:motivo),
      por_canal: contar(decisoes) { |log| canal(log) }
    }
  rescue StandardError
    {}
  end

  def contar(registros)
    registros.each_with_object(Hash.new(0)) { |log, acc| acc[(yield log).to_s] += 1 }
  end

  def canal(log)
    tipo = log.conversation&.inbox&.channel_type.to_s
    CANAIS[tipo] || tipo.presence || '—'
  end

  # ------------------------------------------------------- SLA como medida

  # "N leads designados há mais de X sem ninguém pegar." Em vendas o SLA não repassa nada
  # (§7.2) — ele existe para o gestor VER. Ignora o período: o que importa é o que está
  # parado AGORA, inclusive coisa designada no mês passado.
  def sem_movimento
    limite = limiar_minutos
    corte = limite.minutes.ago
    abertas = Spx::Distribuicao::Log.where(account_id: Current.account.id, status: 'designado')
                                    .where(designado_em: ...corte)
    abertas = abertas.where(conversation_id: conversas_do_time) if params[:team_id].present?

    { limiar_minutos: limite,
      total: abertas.count,
      leads: abertas.includes(:chosen_user, :conversation).order(designado_em: :asc).limit(100).map { |log| serializar_parado(log) } }
  rescue StandardError
    { limiar_minutos: limiar_minutos, total: 0, leads: [] }
  end

  # Limiar do time consultado; sem time, o menor limiar configurado na conta (o mais
  # exigente), e 30 como último recurso.
  def limiar_minutos
    return @limiar_minutos if defined?(@limiar_minutos)

    escopo = Spx::Distribuicao::Policy.ativas.where(account_id: Current.account.id)
    escopo = escopo.where(team_id: params[:team_id]) if params[:team_id].present?
    @limiar_minutos = escopo.minimum(:sla_assumir_minutos) || 30
  end

  # ------------------------------------------------------------ serializers

  # `minutos_parado` é wall-clock. O relógio consciente de expediente depende de uma fonte
  # de horário POR TIME, que o Chatwoot não tem (working_hours é por inbox) — ver §9.1.
  def serializar_parado(log)
    {
      conversation_id: log.conversation_id,
      display_id: log.conversation&.display_id,
      corretor: log.chosen_user&.name,
      produto: log.produto_slug,
      designado_em: log.designado_em,
      minutos_parado: log.designado_em && ((Time.zone.now - log.designado_em) / 60).round,
      vista_negocio_codigo: log.vista_negocio_codigo
    }
  end

  def serializar_designacao(log)
    {
      id: log.id,
      corretor: log.chosen_user&.name,
      motivo: log.motivo,
      status: log.status,
      produto: log.produto_slug,
      designado_em: log.designado_em,
      encerrado_em: log.encerrado_em,
      candidatos: log.candidatos,
      regra_aplicada: log.policy_snapshot,
      vista_negocio_codigo: log.vista_negocio_codigo
    }
  end
end
