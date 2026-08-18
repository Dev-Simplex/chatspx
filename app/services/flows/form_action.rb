# frozen_string_literal: true

# Bloco 4.02 (BK-22) — `send_form`: o no de pergunta que emite uma mensagem `form` no CANAL WEB.
#
# Fecha o par que o bloco 4.01 deixou aberto: o widget ja sabia RESPONDER um `form` (a submissao
# vira mensagem `incoming`), mas nenhum no do motor sabia ENVIAR um. Sem este arquivo o motor
# consegue ler uma resposta que ele mesmo nunca consegue pedir.
#
# Misturado no Flows::ActionService, como os demais concerns de acao. Depende do host:
# @conversation, conversation_a_tweet?, enforce_compliance! (Flows::Compliance), author,
# message_content_attributes e `structured_limits` (Flows::InteractiveAction).
#
# CANAL: `form` so tem renderizacao no chat de site (`ChatForm.vue`). Em qualquer outro canal a
# acao levanta um Flows::StepSkip TRIAVEL (`form_unsupported_channel`) — o passo aparece no
# FlowStepLog com o motivo, em vez de mandar um texto improvisado que o cliente nao pediu. E a
# degradacao declarada do "mesmo Flow nos dois canais": no WhatsApp, quem faz esse papel e o
# `send_whatsapp_flow`.
#
# Formato do param: action_params = [{ content:, button_label?, items: [{ name:, label?, type?,
# placeholder?, required?, options? }] }].
module Flows::FormAction
  # Os tipos que `ChatForm.vue` realmente desenha. Tipo desconhecido vira `text` em vez de
  # quebrar a tela: um campo que aparece como texto e recuperavel; um campo que nao renderiza
  # trava o fluxo do visitante.
  FIELD_TYPES = %w[text email text_area select].freeze
  FIELD_NAME_LIMIT = 100

  private

  def send_form(action_params)
    return if conversation_a_tweet?

    raise Flows::StepSkip.new('form_unsupported_channel', 'form renders only on the website channel') unless web_widget_conversation?

    config = action_params[0].to_h.with_indifferent_access
    items = sanitize_form_items(config['items'])
    raise Flows::StepSkip.new('form_no_fields', 'no valid form fields to send') if items.blank?

    enforce_compliance!(category: 'utility', free_form: true)

    Messages::MessageBuilder.new(author, @conversation.reload, form_message_params(config, items)).perform
  end

  def form_message_params(config, items)
    attributes = message_content_attributes.merge(items: items)
    button_label = config['button_label'].to_s.strip
    attributes[:button_label] = button_label[0, structured_limits[:title]] if button_label.present?

    {
      content: config['content']&.to_s&.slice(0, structured_limits[:body]),
      private: false,
      content_type: 'form',
      content_attributes: attributes
    }
  end

  # Teto de campos IGUAL ao do fluxo de captura (Flow::WidgetPrechatSchema::MAX_COLLECTED_FIELDS):
  # um `form` de 9 campos e exatamente o que o BK-23 recusa salvar, entao tambem nao se envia.
  def sanitize_form_items(raw_items)
    limits = structured_limits
    Array(raw_items)
      .filter_map { |raw| sanitize_form_item(raw, limits) }
      .first(Flow::WidgetPrechatSchema::MAX_COLLECTED_FIELDS)
  end

  def web_widget_conversation?
    @conversation.inbox&.web_widget?
  end

  # Devolve Hashes de CHAVES-STRING restritas a ContentAttributeValidator::ALLOWED_FORM_ITEM_KEYS —
  # qualquer chave fora dessa lista faz a Message inteira ser invalidada na persistencia.
  def sanitize_form_item(raw, limits)
    item = raw.to_h.with_indifferent_access
    name = item['name'].to_s.strip.slice(0, FIELD_NAME_LIMIT)
    return if name.blank?

    entry = base_form_field(item, name, limits)
    placeholder = item['placeholder'].to_s.strip
    entry['placeholder'] = placeholder[0, limits[:title]] if placeholder.present?
    entry['options'] = sanitize_form_options(item['options'], limits) if entry['type'] == 'select'
    entry
  end

  def base_form_field(item, name, limits)
    {
      'name' => name,
      'label' => (item['label'].to_s.strip.presence || name)[0, limits[:title]],
      'type' => FIELD_TYPES.include?(item['type'].to_s) ? item['type'].to_s : 'text',
      'required' => ActiveModel::Type::Boolean.new.cast(item['required']) || false
    }
  end

  # `ChatForm.vue` le `option.value` e `option.label` (e `option.key` so como :key do v-for).
  def sanitize_form_options(raw_options, limits)
    Array(raw_options).filter_map do |raw|
      option = raw.to_h.with_indifferent_access
      value = option['value'].to_s.strip.slice(0, limits[:value])
      next if value.blank?

      { 'key' => value, 'value' => value,
        'label' => (option['label'].to_s.strip.presence || value)[0, limits[:title]] }
    end.first(limits[:items])
  end
end
