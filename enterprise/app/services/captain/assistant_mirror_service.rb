class Captain::AssistantMirrorService
  def initialize(assistant)
    @assistant = assistant
  end

  # Idempotente: cria ou atualiza o espelho 1:1 (unique parcial no banco garante).
  def sync!
    mirror = AgentBot.find_or_initialize_by(captain_assistant_id: @assistant.id)
    mirror.assign_attributes(
      account_id: @assistant.account_id,
      bot_type: :captain,
      name: @assistant.name,
      description: @assistant.description,
      outgoing_url: nil
    )
    mirror.save!
    sync_avatar(mirror)
    mirror
  end

  private

  def sync_avatar(mirror)
    if @assistant.avatar.attached?
      return if mirror.avatar.attached? && mirror.avatar.blob_id == @assistant.avatar.blob_id

      mirror.avatar.attach(@assistant.avatar.blob) # compartilha o blob, sem cópia de bytes
    elsif mirror.avatar.attached?
      mirror.avatar.purge
    end
  end
end
