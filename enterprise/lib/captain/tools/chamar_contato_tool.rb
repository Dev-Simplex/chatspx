class Captain::Tools::ChamarContatoTool < Captain::Tools::BasePublicTool
  description 'Chama alguém no WhatsApp a partir desta conversa. Dois usos: (a) o próprio cliente pede pra continuar em OUTRO número dele; ' \
              '(b) o cliente INDICA outra pessoa interessada, em geral compartilhando o cartão de contato dela. ' \
              'Use apenas com número que apareceu nesta conversa — nunca com número que você não recebeu aqui. ' \
              'A mensagem de abertura sai sozinha; você não precisa (nem deve) informar número de telefone a ninguém. ' \
              'Numa indicação, confirme antes com quem indicou o nome da pessoa e o que ela procura, se não estiver claro. ' \
              'Depois de chamar, diga com suas palavras a quem está falando com você que a mensagem já foi enviada.'

  param :telefone,
        type: 'string',
        desc: 'O número de WhatsApp que apareceu nesta conversa (digitado pela pessoa ou no cartão de contato), com DDD.',
        required: true
  param :nome,
        type: 'string',
        desc: 'De quem é esse número, como você soube nesta conversa. ' \
              'Obrigatório quando for outra pessoa; no caso do próprio cliente pode ficar vazio.',
        required: false
  param :contexto,
        type: 'string',
        desc: 'A frase que a pessoa vai LER na abertura, dizendo por que está sendo chamada: no caso do próprio cliente, o assunto que ' \
              'vocês tratavam; numa indicação, quem indicou e o que essa pessoa procura. Escreva em segunda pessoa, curto e claro.',
        required: true
  param :mesma_pessoa,
        type: 'boolean',
        desc: 'Verdadeiro quando o número é do próprio cliente desta conversa (outro número dele). Falso quando é outra pessoa, indicada por ele.',
        required: true

  # Recusas viram orientação de conduta (o texto entra no contexto do agente).
  RECUSAS = {
    telefone_invalido: 'O número não parece válido. Confirme o número completo, com DDD, antes de tentar de novo.',
    mesmo_numero: 'Esse é o mesmo número desta conversa — não há outro número pra chamar. Siga o atendimento por aqui.',
    convite_recente: 'Já foi enviada uma mensagem pra outro número a partir desta conversa há pouco tempo. Oriente a pessoa a conferir o WhatsApp.',
    sem_nome: 'Falta saber de quem é o número. Pergunte o nome da pessoa indicada antes de chamar.',
    sem_contexto: 'Falta dizer por que a pessoa está sendo chamada. Descreva o motivo e tente de novo.',
    alvo_em_atendimento: 'Essa pessoa já está sendo atendida pela equipe. Diga a quem indicou que já temos contato com ela e siga o atendimento aqui.'
  }.freeze

  INDISPONIVEL = 'Não foi possível enviar mensagem pra esse número. Explique com suas palavras que o atendimento pode seguir por aqui, ' \
                 'ou que a pessoa pode iniciar a conversa a partir do número dela — sem informar nenhum número de telefone.'.freeze

  def perform(tool_context, telefone:, contexto:, mesma_pessoa:, nome: nil)
    conversation = find_conversation(tool_context&.state)
    return 'Não consegui identificar a conversa.' unless conversation

    result = Whatsapp::ContactInviteService.new(
      conversation: conversation, phone: telefone, contexto: contexto, nome: nome, mesma_pessoa: mesma_pessoa
    ).perform

    log_tool_usage('chamar_contato', { conversation_id: conversation.id, ok: result.ok, error: result.error })
    return sucesso(result) if result.ok

    RECUSAS.fetch(result.error, INDISPONIVEL)
  end

  private

  def sucesso(result)
    "Mensagem enviada no WhatsApp #{result.phone}#{" (#{result.contact_name})" if result.contact_name.present?}. " \
      "O atendimento dessa pessoa segue na conversa ##{result.conversation.display_id}."
  end
end
