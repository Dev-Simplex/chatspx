# frozen_string_literal: true

# Nó `distribuir` do motor Flow: entrega a conversa a UMA pessoa do time ATUAL usando o Motor de
# Distribuição (Spx::Distribuicao::DistribuirService — rodízio/fila). Misturado no
# Flows::ActionService (padrão de Flows::ParticipantAction/Flows::SequenceAction). Depende do
# host: @conversation e @flow.
#
# POR QUE VIRAR UM BLOCO DO CANVAS: até aqui o rodízio só disparava por um caminho INVISÍVEL no
# grafo — a flag global `gatilho_sem_ia` da política ("distribua sempre que um flow trocar o
# time", Spx::Distribuicao::DesignacaoListener#team_changed). Quem lia o fluxo não via nada:
# o `assign_team` aparecia, a distribuição não. Com o nó, o autor escreve
# `Atribuir time (Vendas)` → `Distribuir pelo rodízio` e o QUANDO fica desenhado onde se lê.
# A flag continua valendo e é ortogonal — quem já a usa não muda de vida.
#
# SEM PARÂMETRO, de propósito: distribui no time atual da conversa (`conversation.team`), que é
# quem carrega a política (Policy é por time). Um `team_id` no nó só permitiria mentir — o Motor
# lê o time da CONVERSA de qualquer jeito (DistribuirService#initialize). Para escolher o time,
# use um `assign_team` antes.
#
# GUARDAS TIPADAS — o ponto do nó. O DistribuirService devolve um `noop` MUDO nos casos em que não
# há o que distribuir (sem time, sem política ativa, modo != rodizio/fila). Reportar isso como
# `success` faria o painel Execuções MENTIR ("distribuiu" quando ninguém recebeu nada) — o achado
# mais grave da auditoria do módulo. Por isso as condições são reproduzidas AQUI e viram
# Flows::StepSkip com código próprio: o Runner grava o passo como `skipped` carregando o
# error_code (Flows::StepInstrumentation#error_code_for), sem ruído no Sentry.
#   sem_time    — a conversa não está em nenhum time
#   sem_politica— o time não tem política de distribuição ATIVA
#   modo_off    — a política existe mas está em `online`/`off` (Policy#distribui? == false)
#   sem_pool    — ninguém elegível (pool vazio/cap cheio); o Motor já registrou o motivo no razão
#   erro_motor  — Result sem decisão E sem motivo: o serviço engoliu uma exceção no próprio
#                 rescue (ele loga "[Distribuicao] conv=…"). Não é sucesso e não temos o erro.
module Flows::DistribuicaoAction
  private

  def distribuir(_action_params = nil)
    conversation = @conversation.reload
    team = conversation.team
    raise Flows::StepSkip.new('sem_time', 'a conversa não está em nenhum time') if team.blank?

    policy = Spx::Distribuicao::Policy.for_team(conversation.account_id, team.id)
    raise Flows::StepSkip.new('sem_politica', "o time #{team.name} não tem política de distribuição ativa") if policy.nil?
    raise Flows::StepSkip.new('modo_off', "a política do time #{team.name} está no modo '#{policy.modo}'") unless policy.distribui?

    resolver(Spx::Distribuicao::DistribuirService.new(conversation).call, team)
  end

  # Traduz o Result do Motor em sucesso ou skip tipado. Só é SUCESSO quando alguém foi escolhido
  # (`decidido`) ou quando a fila foi aberta (`motivo == 'fila'`: no modo pull ninguém é escolhido
  # de propósito — a linha aberta é o relógio do SLA, e é exatamente o que a ação deveria fazer).
  def resolver(result, team)
    return registrar_no_log(result, team) if result.decidido || result.motivo == 'fila'
    raise Flows::StepSkip.new('sem_pool', "ninguém do pool do time #{team.name} estava disponível") if result.motivo == 'sem_pool'

    raise Flows::StepSkip.new('erro_motor', 'o Motor de Distribuição não devolveu decisão (ver o log [Distribuicao])')
  end

  # Quem foi escolhido e por quê. O FlowStepLog do passo é montado pelo RUNNER
  # (Flows::StepInstrumentation#record_step) e não recebe metadata da ação, então o rastro do
  # sucesso sai aqui, no formato do próprio módulo. A decisão em si já vira linha no livro-razão
  # (`distribuicao_logs`, via DistribuirService#registrar), com candidatos e política do momento.
  def registrar_no_log(result, team)
    Rails.logger.info(
      "[Flows::DistribuicaoAction] flow=#{@flow.id} conv=#{@conversation.id} team=#{team.id} " \
      "escolhido=#{result.user_id || '-'} motivo=#{result.motivo}"
    )
  end
end
