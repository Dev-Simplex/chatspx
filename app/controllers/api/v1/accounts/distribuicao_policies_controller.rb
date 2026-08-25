# Tela de configuração do rodízio (docs/clientes/tozi/SPEC-RODIZIO.md §9) — o lado de ESCRITA.
#
# O Motor (Spx::Distribuicao) já roda em produção, mas até aqui a política só nascia por
# rake/console: o DistribuicaoDashboardController é `only: [:show]`. O gestor via o rodízio andar
# e não conseguia dizer QUEM está na fila. É esse buraco que este controller fecha.
#
# UPSERT por TIME (PUT .../distribuicao_policies/:team_id): a política é 1-por-time
# (`validates :team_id, uniqueness: { scope: :account_id }`), então "criar" e "editar" são a mesma
# operação para quem usa a tela — e o front não precisa saber se a linha já existe.
#
# Tudo que o front manda é reconferido AQUI. A tela desenha o que quiser; quem decide se um
# corretor pode entrar no pool é o backend — um pool com gente que não é do time devolveria uma
# fila que MENTE sobre quem vai receber (o Motor intersecta com os membros na hora de distribuir
# e simplesmente pularia o intruso, sem dizer nada a ninguém).
class Api::V1::Accounts::DistribuicaoPoliciesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :ensure_admin
  before_action :fetch_team, only: [:show, :update, :destroy]

  # Colunas editáveis pela tela. Fora daqui de propósito: `espelho_vista`/`vista_padrao`
  # (integração Vista é outro assunto) e `so_online` (só faz sentido com o modo `online`, que
  # ainda é F2 no Motor).
  ATRIBUTOS = [
    :ativo, :modo, :modo_posse, :continuidade_ativa, :continuidade_dias, :sla_assumir_minutos,
    :repasse_automatico, :max_repasses, :pool_esgotado_destino_user_id, :gatilho_sem_ia
  ].freeze

  def index
    render json: {
      policies: politicas.map { |policy| serializar(policy) },
      teams: times.map { |team| serializar_time(team) }
    }
  end

  def show
    policy = politica_do_time
    render json: {
      policy: policy && serializar(policy),
      team: { id: @team.id, name: @team.name },
      members: membros(@team)
    }
  end

  def update
    policy = politica_do_time || Spx::Distribuicao::Policy.new(account_id: Current.account.id, team_id: @team.id)
    erros = validar
    return render json: { errors: erros }, status: :unprocessable_entity if erros.any?

    # `atributos` nunca inclui :pool, então o merge abaixo ainda enxerga o pool GRAVADO.
    policy.assign_attributes(atributos)
    policy.pool = pool_para_gravar(policy) if pool_enviado?
    return render json: { errors: policy.errors.full_messages }, status: :unprocessable_entity unless policy.save

    render json: { policy: serializar(policy.reload) }
  end

  # Remover a política = desligar o Motor naquele time (sem política o Distribuir é no-op).
  # Idempotente: time que já estava sem política também responde 204 — a tela só precisa saber
  # que o motor está desligado ali, não distinguir "desliguei agora" de "já estava".
  #
  # O ponteiro do rodízio (Spx::Distribuicao::State) fica: se a política voltar, a vez continua
  # de onde parou em vez de recomeçar do primeiro do pool.
  def destroy
    politica_do_time&.destroy
    head :no_content
  end

  private

  def ensure_admin
    render json: { error: I18n.t('errors.access_denied') }, status: :unauthorized unless Current.account_user&.administrator?
  end

  # Fronteira de conta fechada no lugar onde o recurso é resolvido, e não espalhada por cada
  # validação depois: time de outra conta simplesmente não existe aqui (404).
  def fetch_team
    @team = Current.account.teams.find(params[:team_id])
  end

  def politica_do_time
    Spx::Distribuicao::Policy.find_by(account_id: Current.account.id, team_id: @team.id)
  end

  # Todas as políticas da conta, inclusive as inativas — a tela precisa mostrar (e reativar) o
  # time que alguém desligou.
  def politicas
    Spx::Distribuicao::Policy.where(account_id: Current.account.id).includes(:team).sort_by { |p| p.team&.name.to_s }
  end

  def times
    Current.account.teams.includes(:members).order(:name)
  end

  # ------------------------------------------------------------------ escrita

  def policy_params
    @policy_params ||= params.require(:policy).permit(*ATRIBUTOS, pool: [:user_id, :ativo, :cap])
  end

  # PUT parcial é legítimo: chave ausente = "não mexi nisso", e não "apague".
  def atributos
    policy_params.slice(*ATRIBUTOS)
  end

  def pool_enviado?
    policy_params.key?(:pool)
  end

  def pool_recebido
    @pool_recebido ||= Array(policy_params[:pool]).map do |entry|
      { 'user_id' => entry[:user_id].to_i, 'ativo' => entrada_ativa?(entry[:ativo]), 'cap' => entry[:cap].to_i }
    end
  end

  # Boolean estrito: o jsonb grava o que mandarem e `Policy#pool_entries` filtra por
  # `!= false` — uma string "false" crua entraria no rodízio como se estivesse ativa.
  def entrada_ativa?(valor)
    return true if valor.nil?

    ActiveModel::Type::Boolean.new.cast(valor).present?
  end

  # `produtos` (filtro por produto, lido em DistribuirService#atende_produto?) mora no MESMO
  # objeto do pool e NÃO está no contrato desta tela. Gravar o array cru do front apagaria em
  # silêncio o filtro de quem foi configurado por rake — no primeiro save. Por isso o merge
  # preserva, por user_id, as chaves que a tela não conhece.
  def pool_para_gravar(policy)
    anteriores = (policy.pool || []).index_by { |entry| entry['user_id'].to_i }
    pool_recebido.map do |entry|
      extras = (anteriores[entry['user_id']] || {}).except('user_id', 'ativo', 'cap')
      extras.merge(entry)
    end
  end

  # ------------------------------------------------------------- validações

  # As do model (modo, modo_posse, sla_assumir_minutos, max_repasses, unicidade do time) saem
  # do `save`. Aqui ficam as que o model não tem como fazer: as que dependem do TIME e da CONTA
  # de quem está chamando.
  def validar
    validar_pool + validar_destino + validar_continuidade
  end

  def validar_pool
    return [] unless pool_enviado?

    validar_duplicados + validar_membros + validar_caps
  end

  def validar_duplicados
    duplicados = ids_do_pool.tally.select { |_id, vezes| vezes > 1 }.keys
    return [] if duplicados.empty?

    ["Pool com user_id repetido: #{duplicados.map { |id| descrever_usuario(id) }.join(', ')}"]
  end

  # Membro ATUAL do time: o pool é jsonb com user_id solto, sem FK — nada impede gravar
  # qualquer número ali.
  def validar_membros
    membros = @team.members.pluck(:id).to_set
    fora = ids_do_pool.uniq.reject { |id| membros.include?(id) }
    return [] if fora.empty?

    ["Não é membro do time #{@team.name}: #{fora.map { |id| descrever_usuario(id) }.join(', ')}"]
  end

  # cap negativo não é "sem teto", é teto impossível: `at_cap?` compara `abertas >= cap` e
  # tiraria a pessoa do rodízio para sempre, calada.
  def validar_caps
    pool_recebido.any? { |entry| entry['cap'].negative? } ? ['cap não pode ser negativo'] : []
  end

  def ids_do_pool
    pool_recebido.pluck('user_id')
  end

  # Destino de pool esgotado RECEBE conversa; tem que ser gente desta conta, senão a escalação
  # joga lead por cima da fronteira de conta.
  def validar_destino
    return [] unless policy_params.key?(:pool_esgotado_destino_user_id)

    destino = policy_params[:pool_esgotado_destino_user_id]
    return [] if destino.blank?
    return [] if usuarios_da_conta.exists?(id: destino)

    ["Destino de pool esgotado #{descrever_usuario(destino.to_i)} não é agente desta conta"]
  end

  # A única numérica sem validação no model (modo/modo_posse/sla/max_repasses já têm). Zero ou
  # negativo mataria a janela de continuidade em silêncio.
  def validar_continuidade
    return [] unless policy_params.key?(:continuidade_dias)

    policy_params[:continuidade_dias].to_i.positive? ? [] : ['continuidade_dias deve ser maior que zero']
  end

  # ------------------------------------------------------------ serializers

  def serializar(policy)
    {
      id: policy.id,
      team_id: policy.team_id,
      team_name: policy.team&.name,
      ativo: policy.ativo,
      modo: policy.modo,
      modo_posse: policy.modo_posse,
      continuidade_ativa: policy.continuidade_ativa,
      continuidade_dias: policy.continuidade_dias,
      sla_assumir_minutos: policy.sla_assumir_minutos,
      repasse_automatico: policy.repasse_automatico,
      max_repasses: policy.max_repasses,
      pool_esgotado_destino_user_id: policy.pool_esgotado_destino_user_id,
      gatilho_sem_ia: policy.gatilho_sem_ia,
      pool: serializar_pool(policy)
    }
  end

  # A ORDEM do array é o próprio rodízio (DistribuirService#proximo_rodizio anda por ela):
  # sai exatamente como está gravado — sem sort, sem uniq.
  def serializar_pool(policy)
    (policy.pool || []).map do |entry|
      user_id = entry['user_id'].to_i
      { user_id: user_id, ativo: entry['ativo'] != false, cap: entry['cap'].to_i, name: nome_do_usuario(user_id) }
    end
  end

  def serializar_time(team)
    { id: team.id, name: team.name, members: membros(team) }
  end

  # sort_by e não order(): em `index` os membros vêm pré-carregados e um `order` refaria a
  # consulta time a time.
  def membros(team)
    team.members.sort_by { |user| user.name.to_s }.map { |user| { id: user.id, name: user.name, email: user.email } }
  end

  def usuarios_da_conta
    Current.account.users
  end

  def nome_do_usuario(user_id)
    @nomes ||= usuarios_da_conta.pluck(:id, :name).to_h
    @nomes[user_id]
  end

  def descrever_usuario(user_id)
    nome = nome_do_usuario(user_id)
    nome.present? ? "#{nome} (#{user_id})" : "user_id #{user_id}"
  end
end
