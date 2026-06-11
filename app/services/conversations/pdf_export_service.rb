module Conversations
  class PdfExportService
    Result = Struct.new(:bytes, :sha256, :bates_count, :timestamp_token, keyword_init: true)

    def initialize(export:)
      @export = export
      @conversation = export.conversation
      @account = export.account
      @filters = (export.filters || {}).with_indifferent_access
      @audit_meta = (export.audit_meta || {}).with_indifferent_access
    end

    def call
      messages = filter_messages
      html = render_html(messages)
      pdf_bytes = render_pdf(html)
      sha = Digest::SHA256.hexdigest(pdf_bytes)
      Result.new(
        bytes: pdf_bytes,
        sha256: sha,
        bates_count: messages.size,
        timestamp_token: maybe_timestamp(sha)
      )
    end

    private

    def filter_messages
      scope = @conversation.messages.includes(:sender, attachments: { file_attachment: :blob })

      type_filters = []
      type_filters << Message.message_types[:incoming] if @filters[:include_incoming] != false
      type_filters << Message.message_types[:outgoing] if @filters[:include_outgoing] != false
      type_filters << Message.message_types[:activity] if @filters[:include_activity]
      type_filters << Message.message_types[:template] if @filters[:include_outgoing] != false

      scope = scope.where(message_type: type_filters) if type_filters.any?
      scope = scope.where(private: false) unless @filters[:include_private]

      if @filters[:date_from].present?
        from = parse_date(@filters[:date_from])
        scope = scope.where('messages.created_at >= ?', from.beginning_of_day) if from
      end
      if @filters[:date_to].present?
        to = parse_date(@filters[:date_to])
        scope = scope.where('messages.created_at <= ?', to.end_of_day) if to
      end

      scope.order(:created_at).to_a
    end

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def render_html(messages)
      ApplicationController.renderer.render(
        template: 'conversations/pdf_export',
        layout: false,
        assigns: {
          conversation: @conversation,
          account: @account,
          contact: @conversation.contact,
          contact_name: @conversation.contact&.name || 'Sem nome',
          inbox: @conversation.inbox,
          messages: messages,
          total_messages: @conversation.messages.count,
          filters: @filters,
          audit_meta: @audit_meta,
          export_id: @export.id,
          generated_at: Time.current
        }
      )
    end

    # CDP printToPDF: margens em POLEGADAS (float). 1mm ~= 0.03937in
    def render_pdf(html)
      FerrumPdf.render_pdf(
        html: html,
        pdf_options: {
          format: :A4,
          print_background: true,
          prefer_css_page_size: true,
          display_header_footer: true,
          header_template: header_template,
          footer_template: footer_template,
          margin_top: 0.55,    # ~14mm
          margin_bottom: 0.71, # ~18mm
          margin_left: 0.47,   # ~12mm
          margin_right: 0.47   # ~12mm
        }
      )
    end

    def header_template
      <<~HTML
        <div style="font-size:9px;width:100%;padding:0 8mm;color:#888;display:flex;justify-content:space-between;border-bottom:1px solid #e0e0e0;padding-bottom:3px;">
          <span>Chat SPX · Conversa ##{@conversation.display_id} · #{ERB::Util.h(@conversation.contact&.name.to_s[0, 40])}</span>
          <span>Exportado em #{Time.current.in_time_zone('America/Manaus').strftime('%d/%m/%Y %H:%M')}</span>
        </div>
      HTML
    end

    def footer_template
      placeholder = '<span style="font-family:monospace;">SHA-256: HASH_AFTER_RENDER</span>'
      <<~HTML
        <div style="font-size:8.5px;width:100%;padding:0 8mm;color:#888;display:flex;justify-content:space-between;border-top:1px solid #e0e0e0;padding-top:3px;">
          <span>Export ID ##{@export.id} · Documento eletrônico</span>
          <span>#{placeholder}</span>
          <span>Página <span class="pageNumber"></span> de <span class="totalPages"></span></span>
        </div>
      HTML
    end

    def maybe_timestamp(sha)
      return nil unless ActiveModel::Type::Boolean.new.cast(ENV.fetch('CHATSPX_PDF_TIMESTAMP_ENABLED', 'false'))

      # Hook para RFC 3161 (ITI gov.br). Implementacao real exigira:
      #   - openssl ts -query -data <pdf> -no_nonce -sha256 -cert -out request.tsq
      #   - POST request.tsq para https://timestamp.iti.gov.br ou outro TSA
      #   - parse da resposta TimeStampToken (PKCS#7)
      # Por enquanto, deixamos o hook desligado (nao bloqueia entrega).
      Rails.logger.info("[pdf_export] timestamp RFC3161 desativado (sha=#{sha[0, 16]}...)")
      nil
    end
  end
end
