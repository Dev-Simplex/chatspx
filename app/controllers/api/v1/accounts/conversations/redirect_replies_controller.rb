# CHAT-155: responde o cliente de uma caixa somente leitura pela caixa de destino configurada.
# Pendurado em Conversations:: para herdar as travas de acesso a conversa de origem.
class Api::V1::Accounts::Conversations::RedirectRepliesController < Api::V1::Accounts::Conversations::BaseController
  def create
    return render_error(I18n.t('errors.read_only_inbox.not_redirectable')) if target_inbox.blank?

    authorize target_inbox, :show?
    return render_error(I18n.t('errors.read_only_inbox.contact_without_phone')) if contact.phone_number.blank?

    target = nil
    needs_template = false
    ActiveRecord::Base.transaction do
      target = target_conversation
      # Rollback desfaz tambem a conversa/vinculo recem-criados: o modal volta pedindo template.
      raise ActiveRecord::Rollback if (needs_template = requires_template?(target))

      # Encerra antes de enviar: se algo falhar, nada saiu pelo destino.
      close_original(target)
      Messages::MessageBuilder.new(Current.user, target, message_params).perform
    end
    return render json: { requires_template: true }, status: :unprocessable_entity if needs_template

    render json: { conversation_id: target.display_id }
  end

  private

  def target_inbox
    @target_inbox ||= @conversation.inbox.read_only? ? @conversation.inbox.read_only_redirect_inbox : nil
  end

  def contact
    @conversation.contact
  end

  # Busca explicita da conversa aberta: o ConversationBuilder pelo caminho da API nao olha a
  # conversa aberta e duplicaria. A nova ja nasce com quem respondeu, para ele conseguir abri-la.
  # O reload traz o display_id, que o banco preenche por trigger.
  def target_conversation
    contact_inbox = ContactInboxBuilder.new(contact: contact, inbox: target_inbox, source_id: nil).perform
    target_inbox.conversations.where(contact_id: contact.id).where.not(status: :resolved).order(:created_at).last ||
      target_inbox.conversations.create!(account_id: target_inbox.account_id, contact_id: contact.id, contact_inbox: contact_inbox,
                                         assignee_id: Current.user.id, team_id: @conversation.team_id).reload
  end

  # So o WhatsApp oficial tem a janela de 24h; WAHA aceita texto livre.
  def requires_template?(target)
    params[:template_params].blank? && target_inbox.whatsapp? && !target.can_reply?
  end

  def message_params
    ActionController::Parameters.new(
      content: params[:content], message_type: 'outgoing', template_params: params[:template_params]&.to_unsafe_h
    )
  end

  def close_original(target)
    @conversation.messages.create!(
      account_id: @conversation.account_id, inbox_id: @conversation.inbox_id, message_type: :outgoing, private: true,
      sender: Current.user,
      content: I18n.t('errors.read_only_inbox.replied_note', inbox: target_inbox.name, conversation: target.display_id)
    )
    # Encerramento do sistema, como o ResolutionJob: a regra "time antes de resolver" e para o
    # atendente -- uma conversa sem time numa caixa desativada nunca fecharia.
    @conversation.skip_team_required_for_resolution_validation = true
    @conversation.resolved!
  end

  def render_error(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
