# Contexto de REENTRADA: o cliente voltou a escrever depois de um atendimento humano que já
# tinha sido encerrado.
#
# Sem isso o agente que assume a reabertura não sabe que houve gente antes dele, e trata a
# continuação de um caso em andamento como assunto novo — reabre a triagem do zero, ou pior,
# responde tranquilizando e a conversa fica órfã (caso real: conv 18753, cliente pediu por
# áudio o contrato de aluguel que o consultor ia mandar e ficou 20h sem resposta).
#
# Devolve só FATO — quem atendeu, de que time, quando encerrou. O que fazer com isso (ignorar
# um agradecimento, triar assunto novo, devolver a continuidade pro dono) é conduta e mora no
# prompt do agente; nota de contexto que dá ordem vira exemplo pro modelo copiar.
class Captain::Conversation::HumanHistoryNote
  def initialize(conversation:)
    @conversation = conversation
  end

  # String pro histórico do turno, ou nil quando não é reentrada pós-atendimento humano.
  def text
    # Conversa encerrada não tem turno ativo — e é onde mora o ruído de pesquisa (o cliente
    # responde "10" ao NPS numa conversa resolvida, o que não é voltar a falar com o time).
    return unless @conversation.open?

    humano = last_human_message
    return if humano.nil?

    encerrado_em = resolved_at
    return if encerrado_em.nil? || encerrado_em < humano.created_at

    # Já voltou pras mãos de gente depois do encerramento? Então o caso tem dono e o agente
    # não precisa deste contexto.
    return if human_spoke_after?(encerrado_em)
    return unless contact_spoke_after?(encerrado_em)

    montar(humano, encerrado_em)
  rescue StandardError => e
    Rails.logger.warn("[HumanHistoryNote] conv=#{@conversation.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  # `reorder` obrigatório: Message tem default_scope ordenando por created_at ASC, que entra
  # ANTES no SQL e faz um `.order(desc)` devolver a PRIMEIRA mensagem em vez da última.
  def last_human_message
    @conversation.messages
                 .where(message_type: :outgoing, sender_type: 'User', private: false)
                 .reorder(created_at: :desc)
                 .first
  end

  def resolved_at
    ReportingEvent.where(conversation_id: @conversation.id, name: 'conversation_resolved')
                  .reorder(created_at: :desc)
                  .first&.created_at
  end

  def human_spoke_after?(momento)
    @conversation.messages
                 .where(message_type: :outgoing, sender_type: 'User', private: false)
                 .where('created_at > ?', momento)
                 .exists?
  end

  def contact_spoke_after?(momento)
    @conversation.messages
                 .where(message_type: :incoming)
                 .where('created_at > ?', momento)
                 .exists?
  end

  def montar(humano, encerrado_em)
    quem = humano.sender.try(:name).to_s.strip
    time = @conversation.team&.name.to_s.strip
    quando = encerrado_em.in_time_zone(fuso).strftime('%d/%m às %H:%M')

    partes = ['[Contexto do sistema: antes desta mensagem esta conversa já vinha sendo atendida']
    partes << (quem.present? ? "por #{quem}" : 'por um atendente do time')
    partes << "(time #{time})" if time.present?
    partes << "e foi encerrada em #{quando}."
    partes << 'O cliente voltou a escrever depois do encerramento.]'
    partes.join(' ')
  end

  # `Time.zone` (TZ do deployment — America/Manaus na Tozi), não `account.timezone`:
  # Account NÃO responde a `timezone`, então a chamada levantava NoMethodError, o rescue
  # engolia e a nota SEMPRE renderizava em UTC — informando ao modelo uma hora de
  # encerramento 4h adiantada. `reporting_timezone` é nil e `Inbox(91).timezone` está no
  # default 'UTC' (verificado em prod), então nenhum dos dois serve de fonte. Cada cliente
  # do SPX roda na própria VM, logo o fuso do app é o do cliente.
  def fuso
    Time.zone
  end
end
