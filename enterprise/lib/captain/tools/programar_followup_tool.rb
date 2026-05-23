class Captain::Tools::ProgramarFollowupTool < Captain::Tools::BasePublicTool
  description 'Programa um follow-up (cutucada) pra esta conversa, pra retomar caso o cliente não responda. ' \
              'Use o seu julgamento: programe só quando vale a pena manter o lead aquecido ou esclarecer algo pendente. ' \
              'NÃO programe se o cliente disse que já responde, se a conversa se encerrou naturalmente, ou se não há nada pendente. ' \
              'Você escolhe o tempo: poucos minutos pra um lead quente que sumiu no meio, algumas horas ou 1-2 dias pra quem ficou de pensar. ' \
              'Programar de novo substitui o follow-up anterior.'

  param :minutos, type: 'number',
        desc: 'Em quantos minutos cutucar, se o cliente não responder até lá. Ex: 5 a 15 pra lead quente; 120-480 pra algumas horas; até 2880 (2 dias).', required: true
  param :motivo, type: 'string',
        desc: 'Em que ponto a conversa parou e o que retomar na cutucada. Ex: "estava escolhendo entre as duas casas que mandei".', required: true

  def perform(tool_context, minutos:, motivo:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra programar o follow-up.' unless conversation

    minutes = minutos.to_i.clamp(2, 2880)
    token = SecureRandom.hex(8)
    conversation.update!(custom_attributes: conversation.custom_attributes.merge(
      'followup_token' => token,
      'followup_motivo' => motivo.to_s,
      'followup_status' => "cutucada programada em ~#{minutes} min"
    ))
    Captain::Conversation::FollowupJob.set(wait: minutes.minutes).perform_later(conversation, token)
    'Follow-up programado.'
  rescue StandardError => e
    Rails.logger.warn("[ProgramarFollowupTool] #{e.message}")
    'Não consegui programar o follow-up agora.'
  end
end
