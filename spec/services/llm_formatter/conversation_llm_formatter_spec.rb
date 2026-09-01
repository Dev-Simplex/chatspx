require 'rails_helper'

RSpec.describe LlmFormatter::ConversationLlmFormatter do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:formatter) { described_class.new(conversation) }

  describe '#format' do
    def metadata_lines(conv)
      [
        "Assignee: #{conv.assignee&.name || 'unassigned'}",
        "Team: #{conv.team&.name || 'none'}",
        "Labels: #{conv.label_list.join(', ').presence || 'none'}",
        "Status: #{conv.status}",
        "Priority: #{conv.priority || 'none'}",
        "Created: #{conv.created_at.strftime('%Y-%m-%d %H:%M')}"
      ]
    end

    context 'when conversation has no messages' do
      it 'returns basic conversation info with no messages' do
        expected_output = [
          "Conversation ID: ##{conversation.display_id}",
          "Channel: #{conversation.inbox.channel.name}",
          'Message History:',
          'No messages in this conversation',
          *metadata_lines(conversation)
        ].join("\n")

        expect(formatter.format).to eq(expected_output)
      end
    end

    context 'when conversation has messages' do
      it 'formats messages in chronological order with sender labels' do
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: 'Hello, I need help'
        )

        create(
          :message,
          :bot_message,
          conversation: conversation,
          message_type: 'outgoing',
          content: 'Thanks for reaching out, an agent will reach out to you soon'
        )

        create(
          :message,
          conversation: conversation,
          message_type: 'outgoing',
          content: 'How can I assist you today?'
        )

        expected_output = [
          "Conversation ID: ##{conversation.display_id}",
          "Channel: #{conversation.inbox.channel.name}",
          'Message History:',
          'User: Hello, I need help',
          'Bot: Thanks for reaching out, an agent will reach out to you soon',
          'Support Agent: How can I assist you today?',
          '',
          *metadata_lines(conversation)
        ].join("\n")

        expect(formatter.format).to eq(expected_output)
      end
    end

    context 'when include_contact_details is true' do
      it 'includes contact details' do
        expected_output = [
          "Conversation ID: ##{conversation.display_id}",
          "Channel: #{conversation.inbox.channel.name}",
          'Message History:',
          'No messages in this conversation',
          "Contact Details: #{conversation.contact.to_llm_text}",
          *metadata_lines(conversation)
        ].join("\n")

        expect(formatter.format(include_contact_details: true)).to eq(expected_output)
      end
    end

    # Conversa de GRUPO de WhatsApp: o remetente do Chatwoot e sempre o contato-grupo, entao TODA
    # fala chegava ao LLM como "User:" — o classificador lia N pessoas como um cliente so. E o
    # texto ainda vinha com o prefixo que a app Chatwoot da WAHA injeta no corpo.
    context 'when the conversation is a WhatsApp group' do
      let(:group_contact) do
        create(:contact, account: account, name: 'TI TOZI - Inovação (GROUP)', identifier: '5566999991379-1634750731@g.us')
      end
      let(:conversation) { create(:conversation, account: account, contact: group_contact) }

      let(:group_header) do
        'Conversation type: WhatsApp group — "TI TOZI - Inovação". ' \
          'Messages come from DIFFERENT participants, not from a single customer.'
      end

      it 'announces the group in the header and strips the integration suffix from the title' do
        expect(formatter.format).to include(group_header)
      end

      it 'includes the participant count when the members snapshot exists' do
        conversation.update!(additional_attributes: { 'waha_group' => { 'count' => 12 } })

        expect(formatter.format).to include('WhatsApp group — "TI TOZI - Inovação" (12 participantes)')
      end

      it 'labels the line with the participant name from content_attributes (contrato C2)' do
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: 'Qual Wi-Fi está?',
          content_attributes: { 'group_sender' => { 'name' => 'Rogerio José Da Silva', 'lid' => '229480102662169', 'phone' => nil } }
        )

        expect(formatter.format).to include('Rogerio José Da Silva: Qual Wi-Fi está?')
      end

      it 'extracts the participant from the legacy prefix and cleans the text' do
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: "👥 *‎Rogerio José Da Silva (229480102662169@lid)*\n\nQual Wi-Fi está?"
        )

        output = formatter.format

        expect(output).to include('Rogerio José Da Silva: Qual Wi-Fi está?')
        expect(output).not_to include('👥')
        expect(output).not_to include('229480102662169')
      end

      # Formato fossil da Evolution API (ate ago/2025) — 4.800 mensagens de grupo nesta base,
      # quase 10x o formato novo. O telefone fica no rotulo, o nome vem depois do ultimo " - ".
      it 'extracts the participant from the Evolution API fossil prefix' do
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: "**+55 (66) 9683-6077 - Vilso Tozi:**\n\nBom dia pessoal"
        )

        output = formatter.format

        expect(output).to include('Vilso Tozi: Bom dia pessoal')
        expect(output).not_to include('9683-6077')
      end

      it 'handles the masked variant of the fossil prefix' do
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: "**+55 (66) 9***-**22 - Vilso Tozi:**\n\nBom dia"
        )

        expect(formatter.format).to include('Vilso Tozi: Bom dia')
      end

      it 'does not mistake a legitimate bold heading for the fossil prefix' do
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: "**Resumo:**\n\nSegue o combinado"
        )

        expect(formatter.format).to include("User: **Resumo:**\n\nSegue o combinado")
      end

      it 'never leaks the technical identifier, even outside the prefix' do
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: 'Chama o (229480102662169@lid) aqui'
        )

        expect(formatter.format).not_to include('229480102662169')
      end

      it 'falls back to the generic label when the participant cannot be identified' do
        create(:message, conversation: conversation, message_type: 'incoming', content: 'Bom dia')

        expect(formatter.format).to include('User: Bom dia')
      end

      it 'keeps agent and bot labels — they are not group participants' do
        create(
          :message,
          conversation: conversation,
          message_type: 'outgoing',
          content: 'Vou verificar',
          content_attributes: { 'group_sender' => { 'name' => 'Rogerio José Da Silva' } }
        )

        expect(formatter.format).to include('Support Agent: Vou verificar')
      end

      it 'separates two participants in the same transcript' do
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: 'Qual Wi-Fi está?',
          content_attributes: { 'group_sender' => { 'name' => 'Rogerio José Da Silva' } }
        )
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: 'O da sala',
          content_attributes: { 'group_sender' => { 'name' => 'Vilso Tozi' } }
        )

        output = formatter.format

        expect(output).to include('Rogerio José Da Silva: Qual Wi-Fi está?')
        expect(output).to include('Vilso Tozi: O da sala')
      end
    end

    # Nao-regressao: conversa 1:1 nao pode mudar em NADA — nem o rotulo, nem o texto.
    context 'when the conversation is 1:1 and the content looks like a group prefix' do
      it 'leaves the content untouched' do
        create(
          :message,
          conversation: conversation,
          message_type: 'incoming',
          content: "👥 *Fulano (229480102662169@lid)*\n\nOlá"
        )

        expect(formatter.format).to include("User: 👥 *Fulano (229480102662169@lid)*\n\nOlá")
      end
    end

    context 'when conversation has custom attributes' do
      it 'includes formatted custom attributes in the output' do
        create(
          :custom_attribute_definition,
          account: account,
          attribute_display_name: 'Order ID',
          attribute_key: 'order_id',
          attribute_model: :conversation_attribute
        )

        conversation.update(custom_attributes: { 'order_id' => '12345' })

        expected_output = [
          "Conversation ID: ##{conversation.display_id}",
          "Channel: #{conversation.inbox.channel.name}",
          'Message History:',
          'No messages in this conversation',
          *metadata_lines(conversation),
          'Conversation Attributes:',
          'Order ID: 12345'
        ].join("\n")

        expect(formatter.format).to eq(expected_output)
      end
    end
  end
end
