# Resolve, server-side, o CONJUNTO de anexos elegíveis de um pedido de bulk
# download — usado tanto pelo controller (validação de caps ANTES de enfileirar)
# quanto pelo job (streaming). A resolução é reproduzível a partir do que fica
# persistido no record, por isso não passamos relations pela fila.
#
# Regra de ouro (RNF4): IDs vindos do front NUNCA são confiáveis. O escopo da
# galeria já aplica visibilidade (assigned_inboxes) + regra WhatsApp internamente,
# então IDs de inbox alheia são descartados silenciosamente. No modo conversa a
# autorização (ConversationPolicy) é responsabilidade do controller no create.
class Attachments::BulkDownloadScopeResolver
  # Na conversa o agente vê tudo nas bolhas (inclusive incoming WhatsApp), então
  # incluímos todos os tipos com arquivo — paridade com a tela (decisão §14.6).
  CONVERSATION_FILE_TYPES = %i[image video ig_reel audio file].freeze

  def initialize(account:, user:, conversation_id: nil, attachment_ids: nil, filters: nil)
    @account = account
    @user = user
    @conversation_id = conversation_id.presence
    @requested_ids = Array(attachment_ids).map(&:to_i).reject(&:zero?).presence
    @filters = filters || {}
  end

  # IDs (já filtrados por escopo/visibilidade) do conjunto a baixar. Materializa
  # no máximo MAX_FILES inteiros — barato e estável entre validação e streaming.
  def attachment_ids
    @attachment_ids ||= scope.pluck(:id)
  end

  def count
    attachment_ids.size
  end

  def total_bytes
    return 0 if attachment_ids.empty?

    ActiveStorage::Blob
      .joins('JOIN active_storage_attachments asa ON asa.blob_id = active_storage_blobs.id')
      .where(asa: { record_type: 'Attachment', record_id: attachment_ids, name: 'file' })
      .sum(:byte_size)
  end

  private

  def scope
    @conversation_id.present? ? conversation_scope : gallery_scope
  end

  def conversation_scope
    conversation = @account.conversations.find(@conversation_id)
    rel = conversation.attachments.where(file_type: CONVERSATION_FILE_TYPES)
    @requested_ids.present? ? rel.where(id: @requested_ids) : rel
  end

  def gallery_scope
    builder = Attachments::GalleryScopeBuilder.new(user: @user, account: @account, filters: @filters)
    if @requested_ids.present?
      # Modo "ids" (seleção manual): intersecta SÓ com a visibilidade por inbox
      # (base_scope), de propósito — SEM dedup nem filtro de tipo. Decisão de
      # produto (§T6, 2026-06-15): a seleção pode legitimamente cruzar abas
      # (mídia + documentos) e o front só expõe IDs já visíveis ao usuário, então
      # não há vazamento — apenas permite baixar exatamente os cards marcados,
      # inclusive duplicatas que a galeria colapsa na exibição. NÃO restringir a
      # deduped_scope: isso descartaria itens que o usuário marcou explicitamente.
      builder.base_scope.where(id: @requested_ids)
    else
      # Modo "selecionar tudo do filtro": mesmo escopo dedupado que a galeria
      # exibe — a contagem do banner bate com o conteúdo do zip.
      builder.deduped_scope
    end
  end
end
