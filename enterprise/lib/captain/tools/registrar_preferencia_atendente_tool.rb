# Escreve o pedido do cliente por um atendente específico, para o Motor de Distribuição honrar.
#
# O `DistribuirService` LÊ `custom_attributes['rodizio_preferencia']` desde 31/07 e escolhe essa
# pessoa antes de qualquer outra regra — mas NINGUÉM ESCREVIA o campo, então o desvio nasceu
# inerte. Esta tool é o escritor que faltava.
#
# ⚠️ REGRA #1 — a descrição não traz nome de exemplo, de propósito. Nome concreto em descrição de
# ferramenta vira valor copiado: já aconteceu neste projeto, com um código de imóvel de exemplo
# que a IA passou a mandar sempre.
class Captain::Tools::RegistrarPreferenciaAtendenteTool < Captain::Tools::BasePublicTool
  description 'Registra que o cliente PEDIU para falar com um atendente específico, pelo nome. ' \
              'Chame só quando ele pedir de fato — citar alguém de passagem não é pedir. ' \
              'NÃO confirme o nome ao cliente e NÃO prometa que aquela pessoa vai atender: ' \
              'ela pode estar de férias, fora da equipe ou o nome pode servir a mais de uma ' \
              'pessoa, e nesses casos o atendimento segue o caminho normal. Apenas registre e ' \
              'continue a conversa; quem responder se apresenta.'

  param :nome, type: 'string',
               desc: 'O nome do atendente exatamente como o cliente falou, sem corrigir e sem completar.',
               required: true

  CHAVE = 'rodizio_preferencia'.freeze

  def perform(tool_context, nome:)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa pra registrar a preferência.' unless conversation

    pedido = nome.to_s.strip
    return 'Nome vazio, nada a registrar.' if pedido.empty?

    conversation.update!(
      custom_attributes: conversation.custom_attributes.to_h.merge(CHAVE => pedido)
    )
    log_tool_usage('tool_preferencia_atendente', { conversation_id: conversation.id, pedido: pedido })

    # O retorno é instrução de conduta porque é o único lugar onde ela chega ao modelo no turno
    # em que ele acabou de agir. Repetir aqui o "não prometa" da descrição é de propósito: a
    # descrição é lida uma vez, na montagem do toolset; o retorno chega no momento da tentação.
    'Preferência registrada. NÃO diga ao cliente quem vai atendê-lo e não confirme o nome — ' \
      'a pessoa pode estar indisponível. Siga a conversa normalmente.'
  rescue StandardError => e
    Rails.logger.warn("[RegistrarPreferenciaAtendenteTool] #{e.message}")
    'Não consegui registrar a preferência agora.'
  end
end
