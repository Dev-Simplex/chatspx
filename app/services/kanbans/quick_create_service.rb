# frozen_string_literal: true

# Cria um KanbanItem a partir de uma string livre (P1-05).
# Tenta:
#   1. matchear contato existente por telefone normalizado (PT-BR)
#   2. caso não encontre, cria contato novo + conversa "manual" no inbox WAHA
#      default da conta
# Retorna o KanbanItem persistido.
class Kanbans::QuickCreateService
  attr_reader :account, :kanban_stage, :contact_query, :agent

  def initialize(account:, kanban_stage:, contact_query:, agent: nil)
    @account = account
    @kanban_stage = kanban_stage
    @contact_query = contact_query.to_s.strip
    @agent = agent
  end

  def call
    return nil if contact_query.blank?

    contact, conversation = resolve_contact_and_conversation
    return nil unless contact && conversation

    KanbanItems::MoveService.new(
      conversation: conversation,
      kanban: kanban_stage.kanban,
      kanban_stage: kanban_stage,
      moved_by: agent
    ).perform
  end

  private

  def resolve_contact_and_conversation
    contact = find_contact_by_phone || find_contact_by_name || create_contact
    return [nil, nil] unless contact

    conversation = ensure_conversation(contact)
    [contact, conversation]
  end

  def find_contact_by_phone
    normalized = BrazilianPhoneNormalizer.call(contact_query)
    return nil if normalized.blank?

    account.contacts.where('phone_number ILIKE ?', "%#{normalized.last(8)}%").first
  end

  def find_contact_by_name
    return nil if contact_query.length < 3

    account.contacts.where('name ILIKE ?', "%#{contact_query}%").order(updated_at: :desc).first
  end

  def create_contact
    name, phone = guess_name_and_phone
    return nil unless name.present? || phone.present?

    Contact.create!(
      account: account,
      name: name.presence || phone.presence || contact_query,
      phone_number: normalized_phone(phone)
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def guess_name_and_phone
    # padrão "Nome 65999991234" — separa último token numérico do resto
    tokens = contact_query.split(/\s+/)
    phone_token = tokens.reverse.find { |t| t.gsub(/\D/, '').size >= 8 }
    name_tokens = tokens.reject { |t| t == phone_token }
    [name_tokens.join(' '), phone_token]
  end

  def normalized_phone(raw)
    BrazilianPhoneNormalizer.call(raw)
  end

  def ensure_conversation(contact)
    existing = contact.conversations.where(account_id: account.id).order(last_activity_at: :desc).first
    return existing if existing

    inbox = default_inbox
    return nil unless inbox

    contact_inbox = ContactInbox.find_or_create_by!(
      contact: contact,
      inbox: inbox,
      source_id: contact.phone_number.presence || SecureRandom.uuid
    )

    Conversation.create!(
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox,
      assignee: agent,
      status: :open
    )
  end

  def default_inbox
    @default_inbox ||= account.inboxes.where(channel_type: 'Channel::Whatsapp').first || account.inboxes.first
  end
end
