class Captain::OpenAiMessageBuilderService
  pattr_initialize [:message!]

  # Extracts text and image URLs from multimodal content array (reverse of generate_content)
  def self.extract_text_and_attachments(content)
    return [content, []] unless content.is_a?(Array)

    text_parts = content.select { |part| part[:type] == 'text' }.pluck(:text)
    image_urls = content.select { |part| part[:type] == 'image_url' }.filter_map { |part| part.dig(:image_url, :url) }
    [text_parts.join(' ').presence, image_urls]
  end

  def generate_content
    parts = []
    parts << text_part(referral_note) if referral_note.present?
    parts << text_part(@message.content) if @message.content.present?
    parts.concat(attachment_parts(@message.attachments)) if @message.attachments.any?

    return 'Message without content' if parts.blank?
    return parts.first[:text] if parts.one? && parts.first[:type] == 'text'

    parts
  end

  private

  def text_part(text)
    { type: 'text', text: text }
  end

  def image_part(image_url)
    { type: 'image_url', image_url: { url: image_url } }
  end

  def attachment_parts(attachments)
    image_attachments = attachments.where(file_type: :image)
    image_content = image_parts(image_attachments)

    transcription = extract_audio_transcriptions(attachments)
    transcription_part = text_part(transcription) if transcription.present?

    locations = extract_locations(attachments)
    location_part = text_part(locations) if locations.present?

    attachment_part = text_part('User has shared an attachment') if attachments.where.not(file_type: %i[image audio location]).exists?

    [image_content, transcription_part, location_part, attachment_part].flatten.compact
  end

  # Localização (pin do WhatsApp) vira texto com as coordenadas — é assim que o
  # agente recebe lat/lng pra busca por proximidade.
  def extract_locations(attachments)
    attachments.where(file_type: :location).map do |att|
      rotulo = att.fallback_title.to_s.strip.presence
      coords = "lat #{att.coordinates_lat}, lng #{att.coordinates_long}"
      rotulo ? "[Cliente enviou localização: #{rotulo} — #{coords}]" : "[Cliente enviou localização: #{coords}]"
    end.join(' ')
  end

  # Anúncio clique-para-WhatsApp: o Meta manda o criativo no `referral` do incoming de
  # entrada (content_attributes['referral'] = {source_type:'ad', body, headline, media_type,...}).
  # Injeta como texto pra IA saber DE QUE imóvel/assunto o cliente veio — senão ela fica
  # perguntando "qual imóvel?" com a resposta na mão. Descritivo (fatos), igual ao pin.
  def referral_note
    ref = (@message.content_attributes || {})['referral']
    return if ref.blank?

    titulo = ref['headline'].to_s.strip
    corpo = ref['body'].to_s.strip
    return if titulo.blank? && corpo.blank?

    partes = ['[Cliente chegou por um anúncio (clique-para-WhatsApp)']
    partes << "título: #{titulo}" if titulo.present?
    partes << "conteúdo do anúncio: #{corpo}" if corpo.present?
    partes << "mídia: #{ref['media_type']}" if ref['media_type'].present?
    "#{partes.join(' — ')}]"
  end

  def image_parts(image_attachments)
    image_attachments.each_with_object([]) do |attachment, parts|
      url = get_attachment_url(attachment)
      parts << image_part(url) if url.present?
    end
  end

  def get_attachment_url(attachment)
    return attachment.download_url if attachment.download_url.present?
    return attachment.external_url if attachment.external_url.present?

    attachment.file.attached? ? attachment.file_url : nil
  end

  def extract_audio_transcriptions(attachments)
    audio_attachments = attachments.where(file_type: :audio)
    return '' if audio_attachments.blank?

    audio_attachments.map do |attachment|
      result = Messages::AudioTranscriptionService.new(attachment).perform
      result[:success] ? result[:transcriptions] : ''
    end.join
  end
end
