# Configuração da distribuição DE UM TIME — o que alimenta o passo "Distribuição" da tela de
# edição do time (`/accounts/:id/settings/teams/:teamId/edit`).
#
# Por que mora dentro do time e não numa página global: a política é POR TIME
# (`distribuicao_policies.team_id` é único por conta), e quem sabe quem entrou de férias é
# quem convive com a equipe. Página global obrigaria escolher o time antes de configurar —
# uma pergunta que a URL já responde.
#
# QUEM PODE: admin da conta OU **gerente daquele time** (supervisor, via `team_supervisors`).
# É a mesma regra que já governa a gestão de membros do time (F5 da frente Supervisor) —
# gerenciar o pool é a extensão natural de gerenciar quem está no time.
class Api::V1::Accounts::Teams::DistribuicaoController < Api::V1::Accounts::BaseController
  before_action :fetch_team
  before_action :authorize_gestor

  # Chaves aceitas numa entrada do pool. O pool é jsonb livre: sem allowlist, qualquer coisa
  # que o cliente mandar fica gravada para sempre e vira lixo que ninguém sabe de onde veio.
  CHAVES_POOL = %w[user_id ativo suspenso_ate motivo cap produtos].freeze

  def show
    render json: payload
  end

  def update
    politica = policy_record || Spx::Distribuicao::Policy.new(account_id: Current.account.id, team_id: @team.id)
    politica.assign_attributes(policy_params)
    politica.pool = pool_sanitizado if params.key?(:pool)

    if politica.save
      @policy = politica
      render json: payload
    else
      render json: { errors: politica.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def fetch_team
    @team = Current.account.teams.find(params[:team_id])
  end

  def authorize_gestor
    return if Current.account_user&.administrator?
    return if TeamSupervision.supervises?(Current.user, @team.id, Current.account)

    render json: { error: I18n.t('errors.access_denied') }, status: :unauthorized
  end

  def policy_record
    @policy_record ||= Spx::Distribuicao::Policy.find_by(account_id: Current.account.id, team_id: @team.id)
  end

  # Time sem política NÃO é erro — é o estado inicial de todo time. Devolver 404 obrigaria a
  # tela a tratar "ainda não configurado" como falha; devolvendo o esqueleto com
  # `configurado: false`, ela renderiza os defaults e o primeiro save cria o registro.
  def payload
    p = @policy || policy_record
    {
      configurado: p.present?,
      time: { id: @team.id, nome: @team.name },
      politica: politica_json(p),
      pool: pool_json(p),
      candidatos: candidatos_json(p),
      # O repasse por SLA NÃO age em time sem expediente conhecido (o relógio não anda). Sem
      # este sinal a tela ligaria o repasse e nada aconteceria — falha silenciosa, que é
      # exatamente o que esta frente existe para acabar.
      horario_definido: horario_definido?(p)
    }
  end

  def horario_definido?(politica)
    return false if politica.blank?

    Spx::Distribuicao::JanelaService.new(policy: politica).horario_definido?
  rescue StandardError
    false
  end

  # Os mesmos defaults do banco, declarados uma vez. Time ainda não configurado devolve ISTO,
  # então a tela mostra o que ele VAI ser ao salvar — e não campos vazios que o operador
  # precisa adivinhar.
  PADROES = {
    ativo: false, modo: 'rodizio', modo_posse: 'assignee', so_online: false,
    continuidade_ativa: true, continuidade_dias: 30, sla_assumir_minutos: 30,
    repasse_automatico: false, max_repasses: 3, sla_respeita_horario: true,
    expirado_conta_como_recebido: true, pool_esgotado_destino_user_id: nil, espelho_vista: false,
    horario: {}
  }.freeze

  def politica_json(politica)
    return PADROES.dup if politica.nil?

    PADROES.keys.index_with { |campo| politica.public_send(campo) }
  end

  # Devolve o pool NA ORDEM configurada (é ela que o rodízio percorre), com o nome de cada um
  # e o motivo de quem está fora — a tela precisa DIZER por que a pessoa não recebe, em vez de
  # simplesmente não mostrá-la.
  #
  # `membro_do_time` existe por causa de uma armadilha real: o `build_pool` intersecta o pool
  # com os membros ATUAIS do time e descarta o resto EM SILÊNCIO. Um pool inteiro de gente que
  # não é membro produz `sem_pool` sem nenhum aviso — foi o que a medição encontrou no time de
  # vendas da Tozi. A tela mostra a divergência em vez de deixar o motor falhar calado.
  def pool_json(politica)
    entradas = (politica&.pool || []).select { |e| e.is_a?(Hash) && e['user_id'].present? }
    return [] if entradas.empty?

    membros = @team.members.pluck(:id).to_set
    nomes = User.where(id: entradas.map { |e| e['user_id'] }).pluck(:id, :name).to_h
    entradas.map { |entrada| entrada_json(entrada, politica, membros, nomes) }
  end

  def entrada_json(entrada, politica, membros, nomes)
    uid = entrada['user_id'].to_i
    {
      user_id: uid,
      nome: nomes[uid],
      ativo: entrada['ativo'] != false,
      suspenso_ate: entrada['suspenso_ate'],
      motivo: entrada['motivo'],
      cap: entrada['cap'],
      produtos: entrada['produtos'] || [],
      estado: politica.indisponibilidade(entrada) || :ativo,
      membro_do_time: membros.include?(uid)
    }
  end

  # Membros do time que ainda não estão no pool — é a lista do "+ adicionar".
  def candidatos_json(politica)
    no_pool = (politica&.pool || []).filter_map { |e| e['user_id'].to_i if e.is_a?(Hash) }.to_set
    @team.members.reject { |u| no_pool.include?(u.id) }.map { |u| { user_id: u.id, nome: u.name } }
  end

  def policy_params
    params.permit(
      :ativo, :modo, :modo_posse, :so_online, :continuidade_ativa, :continuidade_dias,
      :sla_assumir_minutos, :repasse_automatico, :max_repasses, :sla_respeita_horario,
      :expirado_conta_como_recebido, :pool_esgotado_destino_user_id, :espelho_vista,
      horario: {}
    )
  end

  # Só entra no jsonb quem é usuário DESTA conta e chave que a gente conhece. A ordem enviada
  # é preservada de propósito: ela É a ordem do rodízio.
  def pool_sanitizado
    validos = Current.account.users.pluck(:id).to_set

    Array(params[:pool]).filter_map do |entrada|
      hash = entrada.respond_to?(:to_unsafe_h) ? entrada.to_unsafe_h : entrada
      next unless hash.is_a?(Hash)

      uid = hash['user_id'].to_i
      next unless validos.include?(uid)

      hash.slice(*CHAVES_POOL).merge('user_id' => uid)
    end
  end
end
