# frozen_string_literal: true

# Kanban v2 (Fase 8) — turns a public WorkForm submission into a real
# contact + conversation + card in the funnel's first stage, REUSING Chatwoot's
# proven builders (no hand-rolled contact/conversation creation). Defensive:
# any failure returns a generic error result, never raises to the public layer.
class Kanban::PublicFormSubmissionService
  Result = Struct.new(:ok, :conversation, :error, keyword_init: true) do
    def ok?
      ok
    end
  end

  def initialize(funnel:, params:)
    @funnel = funnel
    @params = params || {}
  end

  def perform
    return failure('form_disabled') unless @funnel.public_form_enabled?

    inbox = resolve_inbox
    return failure('no_inbox') if inbox.blank?

    conversation = create_conversation(inbox)
    add_initial_message(conversation)
    apply_custom_fields(conversation)
    place_in_first_stage(conversation)

    Result.new(ok: true, conversation: conversation)
  rescue StandardError => e
    Rails.logger.warn("PublicFormSubmissionService funnel #{@funnel.id} failed: #{e.message}")
    failure('submission_failed')
  end

  private

  def account
    @funnel.account
  end

  # Configured inbox, else the account's first API channel inbox.
  def resolve_inbox
    inbox = account.inboxes.find_by(id: @funnel.form_inbox_id) if @funnel.form_inbox_id.present?
    inbox || account.inboxes.where(channel_type: 'Channel::Api').order(:id).first
  end

  def create_conversation(inbox)
    contact_inbox = ContactInboxWithContactBuilder.new(
      inbox: inbox,
      contact_attributes: contact_attributes,
      hmac_verified: false
    ).perform

    # ConversationBuilder expects ActionController::Parameters (it calls permit!).
    conversation_params = ActionController::Parameters.new(
      additional_attributes: { source: 'kanban_funnel_form', funnel_id: @funnel.id }
    )
    ConversationBuilder.new(params: conversation_params, contact_inbox: contact_inbox).perform
  end

  def contact_attributes
    {
      name: clean(@params[:name]).presence || I18n.t('kanban.form.default_lead_name', default: 'Form lead'),
      email: clean(@params[:email]).downcase.presence,
      phone_number: e164_phone(@params[:phone_number] || @params[:phone])
    }.compact
  end

  def add_initial_message(conversation)
    content = clean(@params[:message]).presence
    return if content.blank?

    conversation.messages.create!(
      account_id: account.id,
      inbox_id: conversation.inbox_id,
      message_type: :incoming,
      content: content,
      sender: conversation.contact
    )
  end

  # Only this funnel's defined custom fields are accepted (namespaced).
  def apply_custom_fields(conversation)
    incoming = @params[:custom_fields]
    return unless incoming.respond_to?(:each)

    definitions = @funnel.funnel_custom_fields.index_by(&:key)
    attributes = conversation.custom_attributes || {}
    incoming.each do |key, value|
      field = definitions[key.to_s]
      attributes[field.attribute_key] = value.to_s if field
    end
    conversation.update!(custom_attributes: attributes)
  end

  def place_in_first_stage(conversation)
    stage = @funnel.funnel_stages.with_open_automation.first || @funnel.stages_ordered.first
    return if stage.blank?

    FunnelItems::MoveService.new(
      conversation: conversation, funnel: @funnel, funnel_stage: stage, moved_by: nil
    ).perform
  end

  # Coerce free-typed phone to E.164, assuming Brazil when no country code.
  # Returns nil (skip phone) rather than risk a contact validation failure.
  def e164_phone(raw)
    digits = raw.to_s.gsub(/[^\d+]/, '')
    return nil if digits.blank?
    return digits if digits.match?(/\A\+[1-9]\d{1,14}\z/)

    digits = digits.delete('+')
    return nil if digits.length < 8

    candidate = digits.length <= 11 ? "+55#{digits}" : "+#{digits}"
    candidate = Contacts::BrazilPhoneNormalizer.normalize(candidate)
    candidate.match?(/\A\+[1-9]\d{1,14}\z/) ? candidate : nil
  end

  def clean(value)
    value.to_s.strip
  end

  def failure(error)
    Result.new(ok: false, error: error)
  end
end
