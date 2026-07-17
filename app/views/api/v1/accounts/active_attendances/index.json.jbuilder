json.meta do
  json.count @attendances_count
  json.current_page @current_page
end

json.payload do
  json.array! @attendances do |conversation|
    # `id` é o display_id — TODA rota de sub-recurso de conversa resolve por
    # display_id (conversations/base_controller.rb), e é o que o front chama de
    # conversationId. Expor a PK interna aqui só convidaria a mandá-la pra API e
    # tomar 404.
    json.id conversation.display_id
    json.status conversation.status
    # assignee_last_changed_at NÃO é "atendendo desde": é zerado na primeira
    # resposta do agente (message.rb:440), então mostraria "—" justamente nos
    # atendimentos que engrenaram. created_at/last_activity_at são verdade.
    json.created_at conversation.created_at.to_i
    json.last_activity_at conversation.last_activity_at.to_i if conversation.last_activity_at.present?

    # SEM `messages`/`unread_count`/labels de propósito (D2: só metadado, nunca
    # conteúdo de conversa). A spec trava com not_to have_key('messages').
    contact = conversation.contact
    if contact.present?
      json.contact do
        json.id contact.id
        json.name contact.name
        json.thumbnail contact.avatar_url
        json.phone_number contact.phone_number
        json.email contact.email
      end
    end

    inbox = conversation.inbox
    if inbox.present?
      json.inbox do
        json.id inbox.id
        json.name inbox.name
        json.channel_type inbox.channel_type
      end
    end

    # 3 variantes, espelhando _conversation.json.jbuilder:36-83 — humano,
    # espelho captain e assignee_id sem User ("Agente Removido"). Este último é
    # defensivo: a FK users(assignee_id) ON DELETE NULLIFY zera a coluna quando o
    # agente é removido, então só uma corrida (User apagado entre o load e o
    # preload) cai aqui. Fica pela paridade com o partial canônico.
    if conversation.assignee.present?
      assignee = conversation.assignee
      json.assignee do
        json.id assignee.id
        json.name assignee.name
        json.available_name assignee.available_name
        json.thumbnail assignee.avatar_url
        json.type 'user'
      end
    elsif conversation.assignee_agent_bot&.captain?
      bot = conversation.assignee_agent_bot
      json.assignee do
        json.id bot.id
        json.name bot.name
        json.available_name bot.name
        json.thumbnail bot.avatar_url
        json.type 'agent_bot'
        json.is_captain true
      end
    elsif conversation.assignee_id.present?
      json.assignee do
        json.id conversation.assignee_id
        json.name 'Agente Removido'
        json.available_name 'Agente Removido'
        json.thumbnail ''
        json.type 'user'
      end
    end

    if conversation.team.present?
      json.team do
        json.id conversation.team.id
        json.name conversation.team.name
      end
    end
  end
end
