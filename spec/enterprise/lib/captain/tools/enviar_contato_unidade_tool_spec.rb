require 'rails_helper'

# O que estes exemplos protegem é a regra de 29/09: a IA NÃO escreve telefone. Ela escolhe o
# rótulo; quem envia o número é o sistema, a partir do cadastro. Por isso, além do formato da
# mensagem, cada retorno à IA é conferido para não trazer número nenhum.
RSpec.describe Captain::Tools::EnviarContatoUnidadeTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:canal) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { canal.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:contexto) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  let(:contatos) do
    [{ 'label' => 'Comercial', 'phone' => '(66) 3531-7222' },
     { 'label' => 'Suporte', 'phone' => '66 99635-0491' }]
  end

  def unidade(nome:, **attrs)
    create(:unit, account: account, nome: nome, **attrs)
  end

  # Nenhuma sequência com cara de telefone pode voltar para a IA.
  def sem_numero!(texto)
    expect(texto).not_to match(/\d{4}/)
  end

  describe 'resolução da unidade da conversa' do
    it 'usa a unidade vinculada à caixa, mesmo com outras unidades na conta' do
      unidade(nome: 'Loja Norte', contacts: [{ 'label' => 'Comercial', 'phone' => '(65) 3333-1111' }])
      vinculada = unidade(nome: 'Loja Sul', contacts: contatos)
      inbox.update!(unit: vinculada)

      tool.perform(contexto, rotulo: 'Comercial')

      mensagem = conversation.messages.last
      expect(mensagem.additional_attributes['contact']).to include('name' => 'Loja Sul — Comercial', 'phone' => '+556635317222')
    end

    it 'cai na única unidade ativa da conta quando a caixa não tem vínculo' do
      unidade(nome: 'Loja Única', contacts: contatos)
      unidade(nome: 'Loja Fechada', ativa: false, contacts: contatos)

      expect { tool.perform(contexto, rotulo: 'Suporte') }.to change { conversation.messages.count }.by(1)
      expect(conversation.messages.last.additional_attributes['contact']['name']).to eq('Loja Única — Suporte')
    end

    it 'não escolhe unidade quando há várias e a caixa não tem vínculo' do
      unidade(nome: 'Loja Norte', contacts: contatos)
      unidade(nome: 'Loja Sul', contacts: contatos)

      resposta = tool.perform(contexto, rotulo: 'Comercial')

      expect(resposta).to include('não está vinculada a uma unidade')
      expect(resposta).to include('passar a conversa para uma pessoa')
      sem_numero!(resposta)
      expect(conversation.messages.count).to eq(0)
    end
  end

  describe 'cartão de contato no WhatsApp' do
    let!(:loja) { unidade(nome: 'Loja Centro', contacts: contatos) }

    it 'cria a mensagem com o anexo de contato e os dados do cadastro' do
      resposta = tool.perform(contexto, rotulo: 'suporte')

      mensagem = conversation.messages.last
      anexo = mensagem.attachments.last
      expect(mensagem).to be_outgoing
      expect(mensagem.sender).to eq(assistant)
      expect(anexo.file_type).to eq('contact')
      expect(anexo.fallback_title).to eq('+5566996350491')
      expect(mensagem.additional_attributes['contact']).to eq(
        'name' => 'Loja Centro — Suporte', 'phone' => '+5566996350491', 'source' => 'unit', 'ref' => loja.id
      )
      expect(resposta).to include('Loja Centro — Suporte')
      sem_numero!(resposta)
    end

    it 'devolve os rótulos, sem número, quando o rótulo não existe' do
      resposta = tool.perform(contexto, rotulo: 'Diretoria')

      expect(resposta).to include('"Diretoria" não é um dos contatos')
      expect(resposta).to include('"Comercial"', '"Suporte"', "\"#{described_class::ROTULO_CAIXA}\"")
      sem_numero!(resposta)
      expect(conversation.messages.count).to eq(0)
    end

    it 'devolve os rótulos, sem número, quando não recebe rótulo' do
      resposta = tool.perform(contexto)

      expect(resposta).to include('"Comercial"', '"Suporte"')
      sem_numero!(resposta)
      expect(conversation.messages.count).to eq(0)
    end

    it 'envia o número da própria caixa Cloud como cartão' do
      tool.perform(contexto, rotulo: described_class::ROTULO_CAIXA)

      contato = conversation.messages.last.additional_attributes['contact']
      expect(contato).to include('phone' => canal.phone_number, 'source' => 'inbox', 'ref' => inbox.id, 'name' => 'Loja Centro')
    end

    it 'marca a mensagem para o histórico da IA mostrar o rótulo, não o número' do
      tool.perform(contexto, rotulo: 'Comercial')

      expect(conversation.messages.last.additional_attributes['contato_enviado']).to eq('rotulo' => 'Comercial')
    end
  end

  describe 'caixa WAHA' do
    let(:inbox) { create(:channel_api, account: account).inbox.tap { |caixa| caixa.update!(waha_session_name: 'sessao-teste') } }

    before do
      unidade(nome: 'Loja Centro', contacts: contatos)
      # O after_create_commit da mensagem despacha o envio real; aqui só interessa o que foi gravado.
      allow(Waha::OutboundSpecialMessageService).to receive(:new).and_return(instance_double(Waha::OutboundSpecialMessageService, perform: true))
    end

    it 'envia o cartão pelo mesmo anexo de contato' do
      tool.perform(contexto, rotulo: 'Comercial')

      expect(conversation.messages.last.attachments.last.file_type).to eq('contact')
    end

    it 'envia o número da sessão quando pedem o número da própria caixa' do
      api = instance_double(Waha::ApiService, get_session_me: { 'id' => '5566999990000@c.us' })
      allow(Waha::ApiService).to receive(:new).and_return(api)

      resposta = tool.perform(contexto, rotulo: described_class::ROTULO_CAIXA)

      expect(conversation.messages.last.additional_attributes['contact']['phone']).to eq('+5566999990000')
      sem_numero!(resposta)
    end
  end

  describe 'canal que não é WhatsApp' do
    let(:inbox) { create(:channel_instagram, account: account).inbox }

    before { unidade(nome: 'Loja Centro', contacts: contatos) }

    it 'envia uma mensagem de texto só com o número do cadastro, sem anexo' do
      resposta = tool.perform(contexto, rotulo: 'Suporte')

      mensagem = conversation.messages.last
      expect(mensagem.content).to eq('+55 (66) 99635-0491')
      expect(mensagem.attachments).to be_empty
      expect(mensagem.additional_attributes['contato_enviado']).to eq('rotulo' => 'Suporte')
      sem_numero!(resposta)
    end

    it 'não oferece o número da própria caixa' do
      expect(tool.perform(contexto)).not_to include(described_class::ROTULO_CAIXA)
    end
  end

  describe 'registro no toolset' do
    it 'resolve a classe a partir do id declarado no tools.yml' do
      expect(Captain::Assistant.resolve_tool_class('enviar_contato_unidade')).to eq(described_class)
    end

    it 'sabe se está armada no assistente' do
      expect(described_class.armada?(assistant)).to be(false)

      assistant.update!(config: assistant.config.merge('tools' => ['enviar_contato_unidade']))

      expect(described_class.armada?(assistant)).to be(true)
    end
  end
end
