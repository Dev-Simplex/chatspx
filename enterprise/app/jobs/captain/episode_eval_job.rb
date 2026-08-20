# Avalia UM episódio fechado e faz upsert do veredito (Eval 2.0 F1). Idempotente:
# episódios fechados são imutáveis, então cada um é julgado uma única vez (re-julga
# só se a faixa de mensagens mudou — re-segmentação).
#
# Custo em 2 camadas (padrão juiz-pequeno-pra-volume): o EVAL_OPEN_AI_MODEL julga
# tudo; se existir EVAL_ESCALATION_MODEL, o juiz forte re-julga só nota baixa,
# episódios com flag do gate e uma amostra fixa — auditoria contínua sem pagar o
# modelo caro no tráfego inteiro.
class Captain::EpisodeEvalJob < ApplicationJob
  queue_as :low

  ESCALATION_MAX_NOTA = 5
  ESCALATION_SAMPLE_RATE = 10 # 1 em cada N episódios sobe pro juiz forte

  # force: re-julga mesmo com veredito existente — usado pela anotação humana (#eval),
  # que muda o contexto do juiz sem mudar a faixa de mensagens do episódio.
  def perform(episode, force: false)
    return if episode.ended_at.blank?

    conversation = episode.conversation
    account = conversation.account
    return unless Captain::ConversationEval.enabled_for?(account)

    # Fatos do F3 (desfecho + traços de conduta) ANTES do juiz e antes da idempotência
    # do veredito: são determinísticos e de custo zero, então não podem se perder quando
    # o LLM falha nem ficar de fora do episódio que já tem veredito.
    record_f3_facts(episode)

    existing = Captain::ConversationEval.find_by(episode_id: episode.id)
    return if !force && existing && existing.mensagens_avaliadas == episode.mensagens

    annotated = episode.human_annotations.exists?
    result = judge(episode, conversation, account)
    # Episódio sem mensagem avaliável (ex.: só HSM de disparo sem resposta) recebe um
    # eval sintético 'sem_atendimento' — sai do funil pra sempre em vez de re-tentar
    # a cada ciclo e entupir os slots do cron.
    return persist_empty(episode, conversation, account, existing) if result[:error] == 'Sem mensagens para avaliar'
    return if result[:error].present? || result[:verdict].blank?

    gate = gate_findings(episode)
    result = escalate_if_needed(result, gate, episode, conversation, account, annotated)
    verdict = merge_findings(result[:verdict], gate)
    verdict = verdict.merge(veredito_raw: verdict[:veredito_raw].to_h.merge('human_annotated' => true)) if annotated
    persist(episode, conversation, account, verdict, existing)
  end

  private

  def judge(episode, conversation, account, model_override: nil)
    Captain::ConversationEvalService.new(
      account: account,
      conversation_display_id: conversation.display_id,
      episode: episode,
      model_override: model_override
    ).perform
  end

  # Re-julga com o juiz forte quando o veredito barato indica problema (nota baixa),
  # o gate flagrou algo objetivo, há anotação humana (#eval — sinal máximo de que o
  # episódio importa), ou o episódio caiu na amostra de auditoria.
  def escalate_if_needed(result, gate, episode, conversation, account, annotated)
    strong = InstallationConfig.find_by(name: 'EVAL_ESCALATION_MODEL')&.value
    return result if strong.blank?

    nota = result.dig(:verdict, :nota)
    needs = (nota.present? && nota <= ESCALATION_MAX_NOTA) || gate.any? || annotated ||
            (episode.id % ESCALATION_SAMPLE_RATE).zero?
    return result unless needs

    strong_result = judge(episode, conversation, account, model_override: strong)
    strong_result[:error].blank? && strong_result[:verdict].present? ? strong_result : result
  end

  def persist_empty(episode, conversation, account, existing)
    record = existing || Captain::ConversationEval.new(conversation_id: conversation.id, episode_id: episode.id)
    record.assign_attributes(
      account_id: account.id,
      captain_assistant_id: assistant_id_for(conversation, episode),
      mensagens_avaliadas: episode.mensagens,
      avaliado_em: Time.now.utc,
      representatividade: 'sem_atendimento',
      resumo: 'Sem mensagens avaliáveis (ex.: disparo sem resposta do contato).',
      veredito_raw: { 'skip' => 'sem_mensagens' }
    )
    record.save!
  end

  # Camada de fatos do F3: desfecho (o QUE aconteceu) + traços de conduta (COMO foi
  # conduzido). Best-effort: falha aqui nunca derruba o julgamento — inclusive quando a
  # migration ainda não subiu (PG::UndefinedTable/UndefinedColumn cai neste rescue) — e
  # o backfill (spx:eval:outcomes) recupera o que ficar para trás.
  def record_f3_facts(episode)
    Captain::EpisodeOutcomeService.new(episode: episode).perform
    Captain::EpisodeTraitsService.new(episode: episode).perform
  rescue StandardError => e
    Rails.logger.warn("[eval-f3] falhou no episódio #{episode.id}: #{e.class} #{e.message}")
  end

  # Flagras objetivos do gate determinístico (custo zero), marcados com origem
  # 'gate'. Falha do gate nunca derruba o eval.
  def gate_findings(episode)
    Captain::EpisodeGateService.new(episode: episode).perform
  rescue StandardError => e
    Rails.logger.warn("[eval-gate] falhou no episódio #{episode.id}: #{e.class} #{e.message}")
    []
  end

  def merge_findings(verdict, gate)
    return verdict if gate.empty?

    verdict.merge(response_findings: gate + Array(verdict[:response_findings]))
  end

  def persist(episode, conversation, account, verdict, existing)
    record = existing || Captain::ConversationEval.new(conversation_id: conversation.id, episode_id: episode.id)
    record.assign_attributes(
      account_id: account.id,
      captain_assistant_id: assistant_id_for(conversation, episode),
      mensagens_avaliadas: episode.mensagens,
      avaliado_em: Time.now.utc,
      **verdict
    )
    record.save!
  end

  # Assistente dominante DO EPISÓDIO (não da conversa): o último que respondeu
  # dentro da faixa de mensagens do episódio.
  def assistant_id_for(conversation, episode)
    conversation.messages
                .where(id: episode.first_message_id..episode.last_message_id)
                .where(sender_type: 'Captain::Assistant')
                .reorder(:created_at).last&.sender_id ||
      conversation.assignee_agent_bot&.captain_assistant&.id
  end
end
