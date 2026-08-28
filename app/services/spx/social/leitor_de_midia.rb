# frozen_string_literal: true

# Lê o que está ESCRITO numa mídia do Instagram, a partir da URL do CDN.
#
# Existe separado do `Captain::MediaDescriptionService` porque aquele recebe um `Attachment` do
# ActiveStorage, e aqui não há anexo nenhum: o filho de carrossel é uma URL pública e passageira.
# Baixar e guardar as 20 imagens de um encarte custaria storage para reproduzir um dado que a
# Meta já hospeda — o mesmo argumento que manteve o carrossel de saída como passthrough.
#
# IMAGEM vai direto pra visão pela URL. VÍDEO não: nenhum modelo de visão come mp4, então ele
# desce pro temporário e vira QUADROS pelo `Captain::VideoFrameExtractor`, que é o mesmo ffmpeg
# que já lê os stories da BigStore desde 15/08 — por isso ele ganhou entrada por caminho, em vez
# de existir um segundo extrator no produto.
#
# Chave e modelo saem de `Copilot::OpenaiSettings`, POR CONTA: mídia é o custo que mais varia de
# cliente pra cliente, e cada um tem que pagar e limitar o próprio consumo.
class Spx::Social::LeitorDeMidia
  MAX_TOKENS = 300
  MAX_BYTES_VIDEO = 25.megabytes
  MAX_BYTES_IMAGEM = 10.megabytes

  pattr_initialize [:url!, :tipo!, :account!]

  def perform
    return nil if url.blank?

    fontes = video? ? quadros : Array(imagem_em_base64)
    return nil if fontes.empty?

    pedir(fontes)
  end

  private

  # 🔴 A URL do CDN da Meta NÃO serve para o modelo, embora sirva para nós. Medido em 26/08: a
  # nossa box baixa a imagem com HTTP 200, e a OpenAI, tentando baixar a mesma URL, leva
  # **403** — o CDN recusa o fetcher dela (`invalid_image_url / Upstream status code: 403`).
  #
  # Então os bytes descem por aqui e sobem em base64. Pública para nós não quer dizer pública
  # para o modelo, e essa diferença não aparece em documentação nenhuma.
  def imagem_em_base64
    resposta = HTTParty.get(url, headers: { 'Accept' => 'image/*' })
    return nil unless resposta.success?

    bytes = resposta.body.to_s
    return aviso_tamanho(bytes.bytesize) if bytes.bytesize > MAX_BYTES_IMAGEM

    tipo_mime = resposta.headers['content-type'].presence || 'image/jpeg'
    "data:#{tipo_mime};base64,#{Base64.strict_encode64(bytes)}"
  rescue StandardError => e
    Rails.logger.error("[social] falha ao baixar imagem #{url.to_s[0, 80]}: #{e.class} #{e.message}")
    nil
  end

  def aviso_tamanho(bytes)
    Rails.logger.warn("[social] imagem grande demais (#{bytes} bytes) em #{url.to_s[0, 80]}")
    nil
  end

  def video?
    tipo.to_s.casecmp('video').zero?
  end

  def quadros
    arquivo = baixar
    return [] if arquivo.blank?

    Captain::VideoFrameExtractor.new(source_path: arquivo.path).data_urls
  ensure
    if arquivo
      arquivo.close
      arquivo.unlink
    end
  end

  # Temporário, nunca ActiveStorage: o vídeo é lido uma vez e o que fica é o texto.
  def baixar
    arquivo = Tempfile.new(['carrossel', '.mp4'], binmode: true)
    baixado = 0
    URI.parse(url).open('rb') do |remoto|
      while (pedaco = remoto.read(64 * 1024))
        baixado += pedaco.bytesize
        # Teto para um vídeo grande não comer a VM. Acima disso a leitura simplesmente não
        # acontece — e `lida_em` fica nulo, que quem lê sabe distinguir de "leu e não achou".
        return nil if baixado > MAX_BYTES_VIDEO

        arquivo.write(pedaco)
      end
    end
    arquivo.flush
    arquivo
  rescue StandardError => e
    Rails.logger.error("[social] falha ao baixar mídia #{url.to_s[0, 80]}: #{e.class} #{e.message}")
    arquivo&.close
    arquivo&.unlink
    nil
  end

  def pedir(fontes)
    resposta = OpenAI::Client.new(access_token: chave).chat(parameters: parametros(fontes))
    Copilot::OpenaiSettings.log_chat_usage(service: 'social_media_reading', account: account,
                                           model: modelo, response: resposta)
    resposta.dig('choices', 0, 'message', 'content').to_s.strip.presence
  rescue StandardError => e
    Rails.logger.error("[social] visão falhou em #{url.to_s[0, 80]}: #{e.class} #{e.message}")
    nil
  end

  def parametros(fontes)
    {
      model: modelo,
      max_tokens: MAX_TOKENS,
      temperature: 0.2,
      messages: [
        { role: 'system', content: instrucao },
        { role: 'user', content: fontes.map { |f| { type: 'image_url', image_url: { url: f } } } }
      ]
    }
  end

  # Extração, não descrição. O que serve pra responder comentário é o produto e o número escrito
  # no encarte; cenário e enfeite só gastam contexto.
  #
  # Sem exemplo de saída de propósito (REGRA #1): exemplo em prompt vira molde, e o modelo
  # devolve o exemplo quando não enxerga o dado. Aqui isso seria um preço inventado.
  def instrucao
    <<~PROMPT
      Estas imagens são de uma publicação comercial. #{'Elas são quadros de um mesmo vídeo, em ordem.' if video?}
      Liste o que está escrito nelas: produto, preço, condição de pagamento, prazo e restrição.
      Transcreva números e valores exatamente como aparecem, sem arredondar e sem converter.
      Não descreva cenário, enfeite, pessoas nem enquadramento.
      Não deduza preço a partir de outro item, não complete valor cortado e não interprete
      intenção. O que estiver ilegível, diga que está ilegível.
      Se não houver nada escrito, responda apenas: sem texto legível.
    PROMPT
  end

  def chave
    @chave ||= Copilot::OpenaiSettings.api_key(account)
  end

  def modelo
    @modelo ||= Copilot::OpenaiSettings.vision_model(account)
  end
end
