class Captain::OpenAiMessageBuilderService
  # `assistant` e opcional: sem ele o builder monta o contexto exatamente como sempre montou.
  # Ele so existe pra consultar a politica de midia (Captain::Behavior::MediaPipelineService),
  # que vive no behavior do agente.
  pattr_initialize [:message!, :assistant]

  # Placeholder usado quando um áudio ainda não tem transcrição em cache — a transcrição
  # roda em background (ver #extract_audio_transcriptions), nunca síncrona neste caminho.
  AUDIO_PLACEHOLDER = '[áudio]'.freeze

  # Placeholder de texto pra mensagem só-imagem (sem legenda) — ver #ensure_text_part.
  IMAGE_PLACEHOLDER = '[imagem]'.freeze

  # Rótulo da descrição de imagem gerada por modelo. Mesmo motivo do rótulo da transcrição
  # de áudio: sem ele, texto escrito por um modelo fica indistinguível do que o cliente
  # escreveu, e um erro de descrição vira "fato" na boca do agente.
  IMAGE_DESCRIPTION_LABEL = '[imagem descrita automaticamente — pode conter erros de descrição]'.freeze

  # Mesmo motivo dos outros dois rótulos: o agente precisa saber que aquilo foi lido por uma
  # máquina. Vídeo tem dois porque são duas leituras diferentes do mesmo arquivo — o que está
  # ESCRITO na tela e o que é FALADO —, e uma conta pode ligar só uma delas.
  VIDEO_DESCRIPTION_LABEL = '[vídeo descrito automaticamente a partir de quadros — pode conter erros de descrição]'.freeze
  VIDEO_TRANSCRIPTION_LABEL = '[áudio do vídeo transcrito automaticamente — pode conter erros de transcrição]'.freeze

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

    images = attachments.where(file_type: :image) + story_images
    image_content = image_parts(images)
    description_part = optional_text_part(extract_image_descriptions(images))

    transcription_part = optional_text_part(extract_audio_transcriptions(attachments))
    location_part = optional_text_part(extract_locations(attachments))
    contacts_part = optional_text_part(extract_shared_contacts(attachments))

    # PDF (ex.: holerite) vai como documento pro LLM ler; os demais anexos não-lidos
    # (docx, xlsx, zip...) seguem como nota de texto — o Claude só lê imagem e PDF.
    # `contact` sai do balde genérico porque o vCard agora é lido em `extract_shared_contacts`:
    # deixá-lo aqui faria o cartão contar duas vezes — uma como texto com nome e telefone, outra
    # como "User has shared an attachment".
    others = attachments.where.not(file_type: %i[image audio location contact ig_story]).to_a + story_others

    # Vídeo com leitura gravada sai do balde genérico pelo mesmo motivo do vCard: senão a
    # mesma mídia entra duas vezes, uma como o que ela diz e outra como "User has shared an
    # attachment". Vídeo SEM leitura (conta com a chave desligada, ffmpeg mudo, job ainda na
    # fila) continua no balde — o agente segue sabendo que veio um anexo.
    video_part = optional_text_part(extract_video_context(others))
    others -= videos_ja_lidos(others)

    pdf_content = others.select { |a| pdf_attachment?(a) }.filter_map { |a| (u = get_attachment_url(a)) && file_part(u) }
    attachment_part = text_part('User has shared an attachment') if others.any? { |a| !pdf_attachment?(a) }

    [image_content, description_part, pdf_content, transcription_part, video_part,
     location_part, contacts_part, attachment_part].flatten.compact
  end

  # O que a camada de mídia leu do vídeo: o texto ESCRITO na tela (descrição por quadros) e o
  # que foi FALADO (transcrição). São duas chaves independentes por conta — medido: no story
  # da Tozi o dado está escrito e o áudio é trilha musical; na BigStore a informação do
  # produto é narrada. Só LÊ o cache; quem grava é o job disparado na chegada do anexo.
  # Desligar a chave para de gravar E para de injetar o que já foi gravado, no mesmo gesto.
  def extract_video_context(attachments)
    attachments.select { |att| video_attachment?(att) }.filter_map { |att| video_context_line(att) }.join(' ')
  end

  def videos_ja_lidos(attachments)
    attachments.select { |att| video_attachment?(att) && video_context_line(att).present? }
  end

  def video_context_line(attachment)
    meta = attachment.meta || {}
    partes = []
    if video_description_enabled?
      descricao = meta[Captain::MediaDescriptionService::META_KEY].to_s.strip
      partes << "#{VIDEO_DESCRIPTION_LABEL}: #{descricao}" if descricao.present?
    end
    if video_transcription_enabled?
      fala = meta[Captain::MediaDescriptionService::TRANSCRIPTION_META_KEY].to_s.strip
      partes << "#{VIDEO_TRANSCRIPTION_LABEL}: #{fala}" if fala.present?
    end
    partes.presence&.join(' ')
  end

  def video_description_enabled?
    media_policy&.video_description? || false
  end

  def video_transcription_enabled?
    media_policy&.video_transcription? || false
  end

  def media_policy
    return nil if @assistant.blank?

    @media_policy ||= Captain::Behavior::MediaPipelineService.new(assistant: @assistant, message: @message)
  end

  # Vídeo? Mesma lógica do `image_attachment?`: content_type do blob e, no fallback, a
  # extensão da URL — o story do Instagram chega como :ig_story nos dois formatos.
  def video_attachment?(attachment)
    return true if attachment.file.attached? && attachment.file.blob.content_type.to_s.start_with?('video/')

    get_attachment_url(attachment).to_s.split('?').first.to_s.downcase.end_with?('.mp4', '.mov', '.webm', '.3gp')
  end

  # Descrição de imagem produzida pela camada de mídia (Captain::MediaDescriptionService),
  # gravada em `attachment.meta` quando a conta liga `media_pipeline.image_description`.
  # A imagem CONTINUA indo como visão direta: a descrição é contexto adicional, não troca —
  # tirar a visão regrediria o que o modelo já lê hoje (documento fotografado, por exemplo).
  # Só LÊ o cache; quem descreve é o job disparado na chegada do anexo. Sem a chave ligada,
  # ou sem descrição gravada, este método não produz nada e o contexto sai idêntico ao de hoje.
  def extract_image_descriptions(image_attachments)
    return '' unless image_description_enabled?

    image_attachments.filter_map { |att| att.meta&.[](Captain::MediaDescriptionService::META_KEY).to_s.strip.presence }
                     .map { |texto| "#{IMAGE_DESCRIPTION_LABEL}: #{texto}" }
                     .join(' ')
  end

  def image_description_enabled?
    return false if @assistant.blank?

    Captain::Behavior::MediaPipelineService.new(assistant: @assistant, message: @message).image_description?
  end

  def optional_text_part(text)
    text.present? ? text_part(text) : nil
  end

  # Cartão de contato (vCard) vira TEXTO com nome e telefone. O número vem no
  # fallback_title e o nome no meta (firstName/lastName) — sem isso o agente só via
  # "User has shared an attachment" e ficava cego pra indicação ("olha o contato do
  # meu amigo que quer alugar"). Descritivo, igual ao pin de localização.
  def extract_shared_contacts(attachments)
    attachments.where(file_type: :contact).map { |att| shared_contact_line(att) }.join(' ')
  end

  def shared_contact_line(attachment)
    dados = shared_contact_data(attachment)
    return '[Cliente compartilhou um cartão de contato sem dados legíveis]' if dados.blank?

    "[Cliente compartilhou um cartão de contato: #{dados}]"
  end

  def shared_contact_data(attachment)
    meta = attachment.meta || {}
    campos = { 'nome' => [meta['firstName'], meta['lastName']].join(' ').squish,
               'telefone' => attachment.fallback_title.to_s.strip }
    campos.filter_map { |rotulo, valor| "#{rotulo} #{valor}" if valor.present? }.join(', ')
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
