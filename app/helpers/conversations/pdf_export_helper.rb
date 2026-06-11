module Conversations::PdfExportHelper
  TZ = 'America/Manaus'.freeze

  def fmt_dt(time)
    return '' if time.blank?

    time.in_time_zone(TZ).strftime('%d/%m/%Y %H:%M')
  end

  def msg_css_class(msg)
    classes = ['message']
    classes << 'message--outgoing' if msg.outgoing?
    classes << 'message--incoming' if msg.incoming?
    classes << 'message--activity' if msg.activity?
    classes << 'message--private' if msg.private
    classes.join(' ')
  end

  def sender_label(msg)
    if msg.outgoing?
      name = msg.sender&.try(:available_name) || msg.sender&.name || msg.sender&.email || 'Agente'
      "Agente: #{name}"
    elsif msg.incoming?
      name = msg.sender&.try(:name) || msg.conversation.contact&.name || 'Contato'
      "Contato: #{name}"
    elsif msg.activity?
      'Sistema'
    else
      msg.sender&.try(:available_name) || msg.sender&.name || 'Sistema'
    end
  end

  def filters_summary(filters)
    parts = []
    parts << 'cliente' if filters['include_incoming'] != false
    parts << 'agente' if filters['include_outgoing'] != false
    parts << 'notas privadas' if filters['include_private']
    parts << 'sistema' if filters['include_activity']
    range = []
    range << "de #{Date.parse(filters['date_from']).strftime('%d/%m/%Y')}" if filters['date_from'].present?
    range << "até #{Date.parse(filters['date_to']).strftime('%d/%m/%Y')}" if filters['date_to'].present?
    summary = parts.empty? ? 'nenhum tipo selecionado' : "Tipos: #{parts.join(', ')}"
    summary += " · Período: #{range.join(' ')}" unless range.empty?
    summary
  rescue ArgumentError
    'filtros inválidos'
  end

  def render_attachment(attachment)
    name = attachment.file&.filename&.to_s || "anexo-#{attachment.id}"
    label = attachment_type_label(attachment.file_type)
    size_str = format_byte_size(attachment.file&.byte_size || 0)
    url = safe_attachment_url(attachment)
    inline = ''
    inline = %(<img src="#{image_data_uri(attachment)}" alt="#{ERB::Util.h(name)}"/>) if attachment.file_type == 'image' && attachment.file.attached?
    link = url ? %(<a href="#{ERB::Util.h(url)}" target="_blank" rel="noopener">#{ERB::Util.h(name)}</a>) : ERB::Util.h(name)
    <<~HTML
      <div class="attachment">
        <strong>[#{label}]</strong> #{link} <span style="color:#888;font-size:10px;">(#{size_str})</span>
        #{inline}
      </div>
    HTML
  end

  private

  def attachment_type_label(type)
    case type.to_s
    when 'image' then 'Imagem'
    when 'audio' then 'Áudio'
    when 'video' then 'Vídeo'
    when 'file'  then 'Arquivo'
    when 'location' then 'Localização'
    when 'contact' then 'Contato'
    else type.to_s.capitalize
    end
  end

  def format_byte_size(bytes)
    return '0 B' if bytes.zero?

    units = %w[B KB MB GB]
    exp = (Math.log(bytes) / Math.log(1024)).to_i.clamp(0, units.size - 1)
    format('%<value>.1f %<unit>s', value: bytes.to_f / (1024**exp), unit: units[exp])
  end

  def safe_attachment_url(att)
    att.file.attached? ? Rails.application.routes.url_helpers.rails_blob_url(att.file, host: ENV.fetch('FRONTEND_URL', 'http://localhost:3000')) : nil
  rescue StandardError
    nil
  end

  def image_data_uri(att)
    return safe_attachment_url(att) unless att.file.attached?

    blob = att.file.blob
    return safe_attachment_url(att) if (blob.byte_size || 0) > 2_500_000

    content = blob.download
    "data:#{blob.content_type};base64,#{Base64.strict_encode64(content)}"
  rescue StandardError
    safe_attachment_url(att)
  end
end
