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

  CANAIS = Spx::Distribuicao::ContabilizacaoService::CANAIS

  # Teto da aba "Leads". Maior que o da faixa por consultor (20): esta lista é a conta inteira,
  # e o total sem teto vai junto na resposta para a tela dizer "mostrando 50 de 130".
  LIMITE_LEADS = 50

  # O cálculo mora no service porque o PDF desta tela usa o MESMO: tela e PDF não podem divergir.
  def show
    render json: contabilizacao.call
  end

  # Drill-down: "por que ESTE lead foi pra ESTE corretor". Devolve motivo, candidatos e a
  # política que valia NA HORA — é para isso que o snapshot existe.
  # SEM o recorte de período de propósito: a pergunta é sobre a CONVERSA, não sobre a janela que
  # está na tela. Com o filtro, o lead parado desde agosto — que aparece no cartão "sem
  # movimento", que não tem período — abria o painel vazio quando a tela olhava setembro. A conta
  # continua sendo o limite.
  def designacoes
    registros = Spx::Distribuicao::Log.where(account_id: Current.account.id, conversation_id: params[:conversation_id])
                                      .order(id: :desc).limit(20)
    render json: { designacoes: registros.map { |log| serializar_designacao(log) } }
  end

  # Drill-down por CONSULTOR: os leads que caíram nele pelo rodízio, cada um com a linha do tempo
  # do percurso (IA cobrindo → esperando ele pegar → atendimento). O cálculo mora no service.
  def linha_do_tempo
    render json: Spx::Distribuicao::LinhaDoTempoService.new(
      escopo: escopo_periodo, user_id: params[:user_id], canais: CANAIS
    ).call
  rescue StandardError
    render json: { leads: [], total: 0, media_espera_segundos: nil }
  end

  # A conta inteira, lead a lead: onde cada um está agora, com quem, e há quanto tempo. É a
  # pergunta que a tabela por consultor não responde — ali é preciso saber em quem o lead caiu
  # antes de poder olhar para ele. Teto maior que o da faixa, porque aqui não há um por pessoa.
  def leads
    render json: Spx::Distribuicao::LinhaDoTempoService.new(
      escopo: escopo_periodo, canais: CANAIS, limite: LIMITE_LEADS
    ).call
  rescue StandardError
    render json: { leads: [], total: 0, media_espera_segundos: nil }
  end

  private

  def ensure_admin
    render json: { error: I18n.t('errors.access_denied') }, status: :unauthorized unless Current.account_user&.administrator?
  end

  def contabilizacao
    @contabilizacao ||= Spx::Distribuicao::ContabilizacaoService.new(
      account: Current.account, inicio: params[:de], fim: params[:ate], team_id: params[:team_id]
    )
  end

  def escopo_periodo
    contabilizacao.escopo_periodo
  end

  def nomes_dos_usuarios
    @nomes_dos_usuarios ||= Current.account.users.pluck(:id, :name).to_h
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
      # Id não diz nada para quem lê a tela: "Candidatos: 3, 4, 5" é linha de log, não resposta.
      candidatos_nomes: (log.candidatos || []).map { |id| nomes_dos_usuarios[id] || id },
      regra_aplicada: log.policy_snapshot,
      vista_negocio_codigo: log.vista_negocio_codigo
    }
  end
end
