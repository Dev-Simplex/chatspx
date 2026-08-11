module Whatsapp
  # Envia um template (HSM) aprovado DENTRO de uma conversa que ja existe.
  #
  # E a interface unica de HSM fora do fluxo de campanha. Quem precisa mandar
  # template — repescagem, follow-up, reativacao, encerramento — chama isto em vez
  # de remontar o hash de `template_params` na mao. Essa remontagem estava
  # duplicada em cada motor de disparo, e cada copia carregava um hash de textos
  # hardcoded pra espelhar a mensagem na transcricao; foi dai que veio o susto do
  # "Oi Adriana!" (o espelho tinha um fallback, o template nao estava na lista).
  #
  # O ESPELHO da transcricao (o texto que o time le no painel) e renderizado a
  # partir do template SINCRONIZADO no canal, substituindo {{n}} pelos params. O
  # lead sempre recebe o HSM aprovado pela Meta; este texto e so o reflexo interno.
  # `mirror:` e a rede de seguranca pra quando o template ainda nao foi sincronizado.
  #
  # NAO decide politica: nao reabre conversa resolvida, nao checa a janela de 24h,
  # nao agenda nem espaca envios. Isso e do caller — a mesma chamada serve pra um
  # envio avulso e pra um passo de cadencia.
  #
  #   Whatsapp::SendTemplateService.new(
  #     conversation: conversation,
  #     name: 'tozi_lead_reativacao',
  #     body_params: { '1' => contato.first_name }
  #   ).perform
  #
  # Devolve a Message criada, ou nil quando a inbox nao e WhatsApp (HSM so existe
  # la) — nesse caso nao envia nada e loga.
  class SendTemplateService
    pattr_initialize [:conversation!, :name!, :body_params, :language, :header, :mirror, :content_attributes]

    DEFAULT_LANGUAGE = 'pt_BR'.freeze

    def perform
      return skip('inbox não é WhatsApp — HSM não existe neste canal') unless whatsapp_inbox?

      Messages::MessageBuilder.new(nil, conversation, message_params.with_indifferent_access).perform
    end

    private

    def message_params
      {
        content: transcript_mirror,
        content_type: :text,
        message_type: 'outgoing',
        private: false,
        content_attributes: content_attributes || {},
        template_params: {
          'name' => name, 'language' => locale, 'processed_params' => processed_params
        }
      }
    end

    def processed_params
      processed = {}
      processed['body'] = body if body.present?
      processed['header'] = media_header if media_header.present?
      processed
    end

    # Header de midia (ex.: foto do imovel, mapa). Aceita chaves symbol ou string
    # porque os callers vem tanto de codigo quanto de JSONB de config.
    def media_header
      return @media_header if defined?(@media_header)

      @media_header = begin
        url = header.is_a?(Hash) ? (header[:media_url] || header['media_url']) : nil
        if url.blank?
          nil
        else
          { 'media_url' => url, 'media_type' => header[:media_type] || header['media_type'] || 'image' }
        end
      end
    end

    def body
      @body ||= (body_params || {}).to_h { |key, value| [key.to_s, value.to_s] }
    end

    # Corpo do template sincronizado com {{n}} substituido. Sem template sincronizado
    # cai no mirror do caller; sem ele, nos proprios params — nunca em texto inventado.
    def transcript_mirror
      rendered = render_synced_body
      return rendered if rendered.present?

      mirror.presence || body.values.join(' ').presence || "(#{name})"
    end

    def render_synced_body
      text = synced_body_text
      return nil if text.blank?

      text.gsub(/\{\{(\d+)\}\}/) { body[Regexp.last_match(1)].to_s }
    end

    def synced_body_text
      template = Array(conversation.inbox.channel.message_templates).find do |candidate|
        candidate['name'] == name &&
          candidate['language'].to_s.casecmp?(locale) &&
          candidate['status'].to_s.casecmp?('approved')
      end
      Array(template && template['components'])
        .find { |component| component['type'].to_s.casecmp?('body') }&.dig('text')
    end

    def locale
      language.presence || DEFAULT_LANGUAGE
    end

    # Channel::Whatsapp cobre Cloud API e 360dialog — ambos entregam HSM.
    def whatsapp_inbox?
      conversation.inbox.channel_type == 'Channel::Whatsapp'
    end

    def skip(reason)
      Rails.logger.warn("[SendTemplate] conv=#{conversation.id} template=#{name}: #{reason}")
      nil
    end
  end
end
