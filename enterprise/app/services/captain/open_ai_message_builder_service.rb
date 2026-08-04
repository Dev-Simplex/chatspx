class Captain::OpenAiMessageBuilderService
  pattr_initialize [:message!]

  # Placeholder usado quando um áudio ainda não tem transcrição em cache — a transcrição
  # roda em background (ver #extract_audio_transcriptions), nunca síncrona neste caminho.
  AUDIO_PLACEHOLDER = '[áudio]'.freeze

  # Placeholder de texto pra mensagem só-imagem (sem legenda) — ver #ensure_text_part.
  IMAGE_PLACEHOLDER = '[imagem]'.freeze

  # Extracts text + attachment URLs (imagens e PDFs) do array multimodal (reverso do
  # generate_content). PDFs entram junto com as imagens: o RubyLLM detecta o tipo e manda
  # imagem como visão e PDF como bloco 'document' (o Claude lê nativo).
  def self.extract_text_and_attachments(content)
    return [content, []] unless content.is_a?(Array)

    text_parts = content.select { |part| part[:type] == 'text' }.pluck(:text)
    image_urls = content.select { |part| part[:type] == 'image_url' }.filter_map { |part| part.dig(:image_url, :url) }
    file_urls = content.select { |part| part[:type] == 'file_url' }.filter_map { |part| part.dig(:file_url, :url) }
    [text_parts.join(' ').presence, image_urls + file_urls]
  end

  def generate_content
    parts = []
    parts << text_part(referral_note) if referral_note.present?
    parts << text_part(@message.content) if @message.content.present?
    parts << text_part(property_ref_note) if property_ref_note.present?
    parts.concat(attachment_parts(@message.attachments)) if @message.attachments.any?

    return 'Message without content' if parts.blank?
    return parts.first[:text] if parts.one? && parts.first[:type] == 'text'

    ensure_text_part(parts)
  end

  private

  # A Anthropic recusa um turno multimodal cujo bloco de texto seja vazio
  # ("text content blocks must be non-empty"). Uma mensagem só-imagem (sem legenda,
  # sem referral, sem transcrição) geraria conteúdo só com bloco de imagem — no
  # histórico dos turnos seguintes isso vira bloco de texto vazio e derruba a resposta
  # inteira (IA responde 1× e cala). Garante um bloco de texto placeholder quando há
  # mídia sem nenhum texto. A imagem segue indo como image_url (o LLM continua vendo).
  def ensure_text_part(parts)
    return parts if parts.any? { |part| part[:type] == 'text' }

    [text_part(IMAGE_PLACEHOLDER)] + parts
  end

  def text_part(text)
    { type: 'text', text: text }
  end

  def image_part(image_url)
    { type: 'image_url', image_url: { url: image_url } }
  end

  # PDF vira bloco de documento (o extract junta com as imagens; o RubyLLM manda como
  # 'document' e o Claude lê nativo — ex.: holerite em PDF).
  def file_part(url)
    { type: 'file_url', file_url: { url: url } }
  end

  def attachment_parts(attachments)
    # Reply a story do Instagram chega com file_type :ig_story (enum próprio, NÃO :image) e o
    # arquivo já baixado pelo builder do canal (`create_story_reply_attachment`). Sem tratar
    # aqui, o story caía no balde genérico e o agente recebia só "User has shared an
    # attachment" — cego justamente ao que o cliente estava respondendo. Story em VÍDEO fica
    # de fora (o Captain ainda não lê vídeo) e segue como nota de texto.
    story_images, story_others = attachments.where(file_type: :ig_story).partition { |a| image_attachment?(a) }

    image_content = image_parts(attachments.where(file_type: :image) + story_images)

    transcription = extract_audio_transcriptions(attachments)
    transcription_part = text_part(transcription) if transcription.present?

    locations = extract_locations(attachments)
    location_part = text_part(locations) if locations.present?

    # PDF (ex.: holerite) vai como documento pro LLM ler; os demais anexos não-lidos
    # (docx, xlsx, zip...) seguem como nota de texto — o Claude só lê imagem e PDF.
    others = attachments.where.not(file_type: %i[image audio location ig_story]).to_a + story_others
    pdf_content = others.select { |a| pdf_attachment?(a) }.filter_map { |a| (u = get_attachment_url(a)) && file_part(u) }
    attachment_part = text_part('User has shared an attachment') if others.any? { |a| !pdf_attachment?(a) }

    [image_content, pdf_content, transcription_part, location_part, attachment_part].flatten.compact
  end

  # PDF? Confia no content_type do blob (Active Storage) e, no fallback (anexo externo/WAHA),
  # na extensão .pdf da URL. O RubyLLM ainda re-checa pelo conteúdo se a extensão faltar.
  # O `to_s` depois do split é obrigatório: anexo SEM arquivo e SEM url externa (vCard do
  # WhatsApp = file_type contact) devolve url vazia, e `''.split('?').first` é nil — o
  # `nil.downcase` derrubava o ResponseBuilderJob inteiro antes de chamar o LLM, deixando a
  # IA muda em toda conversa que tivesse um cartão de contato no histórico.
  def pdf_attachment?(attachment)
    return true if attachment.file.attached? && attachment.file.blob.content_type.to_s == 'application/pdf'

    get_attachment_url(attachment).to_s.split('?').first.to_s.downcase.end_with?('.pdf')
  end

  # Imagem? Mesma lógica do `pdf_attachment?`: confia no content_type do blob e, no fallback
  # (o download do story falhou e sobrou só a URL do CDN), na extensão da URL. Existe porque
  # :ig_story não entra no `where(file_type: :image)` — e um story em vídeo precisa cair fora.
  def image_attachment?(attachment)
    return true if attachment.file.attached? && attachment.file.blob.content_type.to_s.start_with?('image/')

    get_attachment_url(attachment).to_s.split('?').first.to_s.downcase.end_with?('.jpg', '.jpeg', '.png', '.gif', '.webp')
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

  # Mesma ideia do referral, para o lead que chega pelo botão do site: o texto pronto traz
  # o código do imóvel mas não diz se ele é de venda ou de locação, e sem isso a triagem
  # pergunta o que o acervo já sabe. Memoizado porque `generate_content` consulta duas
  # vezes e a resolução do código faz I/O (o serviço ainda cacheia por conta+código).
  def property_ref_note
    return @property_ref_note if defined?(@property_ref_note)

    @property_ref_note = Captain::PropertyRefContextService.new(message: @message).note
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

    audio_attachments.map { |attachment| transcription_or_placeholder(attachment) }.join
  end

  # NÃO transcreve áudio síncrono aqui. Este builder monta o histórico de TODAS as
  # mensagens da conversa a cada turno; transcrever inline via OpenAI fazia um cliente
  # que volta com dezenas de áudios antigos disparar dezenas de chamadas Whisper —
  # um 429/timeout no meio abortava a resposta inteira (IA muda) e ainda pressionava o
  # rate limit. Agora: usa o cache (`meta['transcribed_text']`) quando existe; senão,
  # enfileira a transcrição em background (preenche o cache pro próximo turno) e usa um
  # placeholder neste turno. O áudio da mensagem atual raramente cai aqui — o job async
  # disparado no upload (after_create_commit) já costuma ter preenchido o cache.
  def transcription_or_placeholder(attachment)
    cached = attachment.meta&.[]('transcribed_text').to_s
    # Marca a origem: sem o rótulo, a transcrição é indistinguível de texto DIGITADO e
    # uma palavra transcrita errado vira "evidência" de robô/spam pro agente (caso real:
    # saudação por áudio transcrita com nome estranho foi silenciada como spam por 16h).
    return "[áudio transcrito automaticamente — pode conter erros de transcrição]: #{cached}" if cached.present?

    Messages::AudioTranscriptionJob.perform_later(attachment.id)
    AUDIO_PLACEHOLDER
  end
end
