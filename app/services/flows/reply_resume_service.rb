# frozen_string_literal: true

# Retomada de um wait_for_reply por MENSAGEM (não por tempo). Espelha o Flows::ResumeService, mas
# o gatilho é a RESPOSTA do contato: acha o FlowRun `waiting` da conversa cujo current_node_id é um
# nó wait_for_reply, reentra o Flows::RunnerService NESSE nó injetando o reply { id, title } e deixa
# o runner ramificar pela opção escolhida (o id da reply == o value da opção == edge.branch).
#
# Reentrante — `with_lock` + uma re-checagem de status DENTRO do lock impedem que duas respostas
# quase simultâneas retomem o mesmo run em duplicidade (mesmo padrão do ResumeService). Best-effort:
# um erro é logado e o run marcado `failed` (runs-veneno param de tentar), pra uma resposta ruim não
# derrubar o listener. Devolve true SÓ quando de fato retomou um run — o AutomationRuleListener usa
# isso pra dar early-return (a resposta pertence ao flow ativo, não dispara flow novo).
class Flows::ReplyResumeService
  def initialize(conversation:, reply:)
    @conversation = conversation
    @reply = reply
  end

  # true se retomou um wait_for_reply pendente; false se não havia nenhum (ou se falhou).
  def perform
    run = pending_reply_run
    return false unless run

    resume(run)
  rescue StandardError => e
    Rails.logger.error("Flows::ReplyResumeService conversation=#{@conversation&.id}: #{e.message}")
    mark_failed(run)
    false
  end

  private

  def resume(run)
    run.with_lock do
      # Re-checa DENTRO do lock: outra resposta pode ter retomado (e completado/re-suspendido) o
      # run entre o SELECT e o lock. Só o primeiro a pegar o lock com o run ainda :waiting retoma.
      next false unless run.waiting?

      Flows::RunnerService.new(
        flow: run.flow, conversation: run.conversation,
        trigger_payload: run.context, flow_run: run, resume_reply: @reply
      ).resume_from(run.current_node_id)
      true
    end
  end

  # O run `waiting` mais recente desta conversa cujo ponteiro de reentrada (current_node_id) aponta
  # um nó wait_for_reply. `detect` (não um WHERE) porque o tipo do nó mora na definition do flow (em
  # memória), não numa coluna — carregamos os poucos runs waiting da conversa e filtramos. Um `wait`
  # (tempo) puro NÃO casa: seu current_node_id é o sucessor, não um wait_for_reply.
  def pending_reply_run
    FlowRun.waiting.where(conversation: @conversation)
           .order(updated_at: :desc)
           .detect { |run| wait_for_reply_node?(run) }
  end

  def wait_for_reply_node?(run)
    node = run.flow.nodes.find { |n| n.is_a?(Hash) && n['id'] == run.current_node_id }
    node.present? && node['type'] == 'wait_for_reply'
  end

  # Não deixa um run-veneno preso em :waiting. O fail! tem seu próprio rescue: se a falha original
  # foi de banco, marcar failed também pode falhar (espelha o Flows::ResumeService).
  def mark_failed(run)
    run&.fail!
  rescue StandardError
    nil
  end
end
