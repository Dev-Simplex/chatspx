# frozen_string_literal: true

# Bloco 5.20 — a mensagem proativa do backend do cliente, resolvida de ponta a ponta.
#
# O que ele substitui, e o que cada peça fazia (medido nesta base):
#
#   1. GET  /contacts/search        — achava o contato por LIKE parcial. Aqui a correspondencia e
#                                     EXATA de proposito: disparo nao e busca, e mandar mensagem
#                                     "para quem parece" e o pesadelo do recurso.
#   2. POST /conversations          — achava/criava a conversa. `ConversationBuilder` continua sendo
#                                     quem cria, com o mesmo lock por (inbox, contato), para nao
#                                     existirem dois caminhos de criacao de conversa.
#   3. POST /conversations/:id/messages — criava a mensagem. `Messages::MessageBuilder` continua
#                                     sendo quem cria, e e dele que vem o `message.created` — o
#                                     evento que leva a mensagem ao widget aberto em tempo real.
#
# O ganho nao e latencia: e SUPERFICIE. Quem dispara deixa de precisar saber o que e contact_inbox,
# `source_id` e `display_id`, e some o estado intermediario que ficava para tras quando a segunda
# chamada falhava — conversa vazia aberta na fila do atendimento, sem mensagem nenhuma.
#
# UM efeito colateral da rota antiga NAO sobrevive aqui, e e deliberado:
# `conversations_controller.rb:212-218` (`self_assign_creator_for_reply_gate`) atribui a conversa a
# quem a criou, quando a conta usa o gate de resposta. Ele existe para responsabilizar o humano que
# respondeu na tela; num disparo de backend nao ha humano respondendo, e atribuir a conversa ao dono
# do token de API poria na fila de uma pessoa algo que ela nao escreveu. Fica declarado morto NESTE
# caminho — na rota de conversas ele continua exatamente como estava.
class Messages::ProactiveDispatchService
  Result = Struct.new(:error, :status, :conversation, :message, keyword_init: true) do
    def success?
      error.nil?
    end
  end

  RECIPIENT_FIELDS = %i[identifier email phone_number].freeze

  def initialize(account:, inbox:, sender:, params:)
    @account = account
    @inbox = inbox
    @sender = sender
    @params = params
  end

  def perform
    content = @params[:content].to_s.strip
    return failure('content não pode ficar em branco', :unprocessable_entity) if content.blank?
    return failure("informe o destinatário por #{RECIPIENT_FIELDS.join(', ')}", :unprocessable_entity) if recipient_field.nil?

    contact = find_contact
    return failure('contato não encontrado nesta conta', :not_found) if contact.nil?

    dispatch(contact, content)
  end

  private

  def dispatch(contact, content)
    contact_inbox = pick_contact_inbox(contact)
    return failure('este contato nunca teve sessão nesta caixa de entrada', :unprocessable_entity) if contact_inbox.nil?

    unverified = verification_failure(contact_inbox)
    return unverified if unverified

    conversation = existing_conversation(contact_inbox) || build_conversation(contact_inbox)
    message = build_message(conversation, content)

    Result.new(conversation: conversation, message: message)
  end

  # Correspondencia EXATA. `contacts#search` usa LIKE parcial porque serve a uma tela de busca, onde
  # a pessoa confere o resultado antes de agir; aqui ninguem confere nada — a mensagem sai.
  def find_contact
    field = recipient_field
    @account.contacts.find_by(field => @params[field].to_s.strip)
  end

  def recipient_field
    RECIPIENT_FIELDS.find { |field| @params[field].present? }
  end

  # Uma sessao verificada vale mais que uma recente: e ela que prova que o destinatario e mesmo o
  # cliente do cliente, e nao alguem que digitou o e-mail dele num formulario.
  def pick_contact_inbox(contact)
    scope = contact.contact_inboxes.where(inbox_id: @inbox.id)

    scope.where(hmac_verified: true).order(updated_at: :desc).first || scope.order(updated_at: :desc).first
  end

  # T-I6.3: a diferenca entre "mandar mensagem para o meu cliente" e "mandar mensagem para quem
  # digitou o e-mail dele". Disparar para nao verificado continua possivel — mas o chamador tem de
  # dizer isso em voz alta, e fica no corpo da requisicao dele.
  def verification_failure(contact_inbox)
    return if contact_inbox.hmac_verified?
    return if ActiveModel::Type::Boolean.new.cast(@params[:allow_unverified_contact])

    failure('contato não verificado nesta caixa de entrada; use allow_unverified_contact para disparar assim mesmo',
            :unprocessable_entity)
  end

  # Disparo proativo nao abre uma segunda conversa quando ja ha uma em andamento: o agente veria
  # duas linhas para a mesma pessoa. Conversa resolvida nao e reaberta — encerrada e encerrada.
  def existing_conversation(contact_inbox)
    ::Conversation.where(inbox_id: @inbox.id, contact_id: contact_inbox.contact_id)
                  .where.not(status: :resolved)
                  .order(created_at: :desc)
                  .first
  end

  # T-I6.2: por padrao a conversa NASCE fora da fila (`snoozed` sem `snoozed_until`), e volta sozinha
  # quando o contato responde — `message.rb:462` ja faz isso, e por isso nao ha estado novo aqui. Sem
  # `snoozed_until`, o `TriggerScheduledItemsJob` nunca a varre: ela espera a pessoa, nao o relogio.
  def build_conversation(contact_inbox)
    status = open_without_reply? ? 'open' : 'snoozed'

    ConversationBuilder.new(params: { status: status }, contact_inbox: contact_inbox).perform
  end

  def open_without_reply?
    ActiveModel::Type::Boolean.new.cast(@params[:create_conversation_without_contact_reply])
  end

  def build_message(conversation, content)
    Messages::MessageBuilder.new(@sender, conversation, { content: content, message_type: 'outgoing' }).perform
  end

  def failure(error, status)
    Result.new(error: error, status: status)
  end
end
