# frozen_string_literal: true

class Contacts::SearchForScheduleService
  DEFAULT_PER_PAGE = 10
  MAX_PER_PAGE = 20

  def initialize(account:, query:, page:, per_page:)
    @account = account
    @query = query
    @page = page
    @per_page = per_page
  end

  def perform
    contacts = filtered_contacts
    paginated_contacts = contacts.page(current_page).per(current_per_page)
    contact_ids = paginated_contacts.pluck(:id)

    conversations_by_contact = primary_conversations(contact_ids)
    inboxes_by_contact = recommended_inboxes(contact_ids, conversations_by_contact)

    payload = paginated_contacts.map do |contact|
      {
        contact: contact,
        primary_conversation: conversations_by_contact[contact.id],
        recommended_inbox: inboxes_by_contact[contact.id]
      }
    end

    {
      payload: payload,
      count: paginated_contacts.total_count,
      current_page: current_page,
      per_page: current_per_page
    }
  end

  private

  attr_reader :account, :query, :page, :per_page

  def filtered_contacts # rubocop:disable Metrics/MethodLength
    relation = account.contacts
                      .resolved_contacts(use_crm_v2: account.feature_enabled?('crm_v2'))
                      .includes(avatar_attachment: [:blob])

    if normalized_query.present?
      safe_query = ActiveRecord::Base.sanitize_sql_like(normalized_query)
      contains_match = "%#{safe_query}%"
      relation = relation.where(
        "contacts.name ILIKE :search OR contacts.email ILIKE :search OR contacts.phone_number ILIKE :search OR
           contacts.identifier LIKE :search OR contacts.additional_attributes->>'company_name' ILIKE :search",
        search: contains_match
      )
      rank_sql = ActiveRecord::Base.sanitize_sql_array(
        [
          <<~SQL.squish,
            CASE
              WHEN LOWER(contacts.phone_number) = LOWER(?) THEN 0
              WHEN LOWER(contacts.email) = LOWER(?) THEN 0
              WHEN contacts.identifier = ? THEN 0
              WHEN LOWER(contacts.name) LIKE LOWER(?) THEN 1
              ELSE 2
            END
          SQL
          normalized_query,
          normalized_query,
          normalized_query,
          "#{safe_query}%"
        ]
      )
      relation = relation.order(Arel.sql(rank_sql), last_activity_at: :desc, id: :desc)
      return relation
    end

    relation.order(last_activity_at: :desc, id: :desc)
  end

  def primary_conversations(contact_ids)
    return {} if contact_ids.blank?

    rows = account.conversations
                  .where(contact_id: contact_ids)
                  .select(
                    'DISTINCT ON (contact_id) conversations.id, conversations.contact_id, ' \
                    'conversations.display_id, conversations.inbox_id, conversations.last_activity_at'
                  )
                  .order('contact_id, last_activity_at DESC, id DESC')
    rows.index_by(&:contact_id)
  end

  def recommended_inboxes(contact_ids, conversations_by_contact)
    return {} if contact_ids.blank?

    contact_inboxes = ContactInbox.includes(:inbox)
                                  .where(contact_id: contact_ids)
                                  .order(created_at: :desc)
    inboxes_by_contact = contact_inboxes.each_with_object({}) do |contact_inbox, acc|
      acc[contact_inbox.contact_id] ||= contact_inbox.inbox
    end

    contact_ids.each_with_object({}) do |contact_id, acc|
      conversation = conversations_by_contact[contact_id]
      acc[contact_id] = if conversation&.inbox_id.present?
                          account.inboxes.find_by(id: conversation.inbox_id)
                        else
                          inboxes_by_contact[contact_id]
                        end
    end
  end

  def normalized_query
    query.to_s.strip
  end

  def current_page
    parsed_page = Integer(page)
    parsed_page.positive? ? parsed_page : 1
  rescue ArgumentError, TypeError
    1
  end

  def current_per_page
    parsed_per_page = Integer(per_page)
    parsed_per_page = DEFAULT_PER_PAGE if parsed_per_page <= 0
    parsed_per_page.clamp(1, MAX_PER_PAGE)
  rescue ArgumentError, TypeError
    DEFAULT_PER_PAGE
  end
end
