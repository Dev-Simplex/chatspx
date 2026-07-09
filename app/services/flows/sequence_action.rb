# frozen_string_literal: true

# Nó `enroll_in_sequence` do motor Flow: inscreve a conversa numa Message Sequence (drip de
# follow-up). Misturado no Flows::ActionService (padrão de Flows::Compliance/AiActions/
# SnoozeAction). Depende do host: @conversation, @account e @actor.
#
# Reusa o serviço REAL MessageSequences::EnrollService — o MESMO caminho do widget de sequência
# da conversa. Ele já é IDEMPOTENTE (no-op se a conversa já está inscrita e ativa — guard
# already_enrolled? + índice único parcial), exige a sequência ativa e agenda o primeiro passo.
# Portanto NÃO duplicamos guard aqui: só resolvemos a sequência da conta e delegamos.
# enrolled_by = @actor (o autor no modo manual; nil no modo automação).
#
# Anti-loop: o EnrollService não envia mensagem síncrona nem re-entra em flow/macro (o drip
# manda mensagens DEPOIS, por jobs próprios, com exit conditions próprias) → não toca
# content_attributes.flow_id nem Current.flow_depth.
#
# action_params = [sequence_id]  (ou [{ sequence_id }])
module Flows::SequenceAction
  private

  def enroll_in_sequence(action_params)
    sequence_id = sequence_param_id(action_params)
    return if sequence_id.blank?

    sequence = @account.message_sequences.find_by(id: sequence_id)
    return if sequence.blank?

    MessageSequences::EnrollService.new(
      sequence: sequence, conversation: @conversation.reload, enrolled_by: @actor
    ).perform
  end

  def sequence_param_id(action_params)
    first = Array(action_params).first
    first.is_a?(Hash) ? first.with_indifferent_access[:sequence_id] : first
  end
end
