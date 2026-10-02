require 'rails_helper'

# O que estes exemplos protegem não é o formato da mensagem: é que a ferramenta NUNCA invente um
# ponto no mapa. Unidade que não existe, unidade sem coordenada e falha de envio têm que sair
# como três respostas diferentes e explícitas — pin errado manda a pessoa para o lugar errado, e
# ela só descobre quando chega lá.
RSpec.describe Captain::Tools::EnviarLocalizacaoUnidadeTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:conversation) { create(:conversation, account: account) }
  let(:contexto) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  def unidade(cidade:, nome: nil, **attrs)
    create(:unit, account: account, cidade: cidade, nome: nome || "Loja #{cidade}", **attrs)
  end

  describe '#active?' do
    it 'nega quando a conta não tem unidade nenhuma' do
      expect(tool).not_to be_active
    end

    # Sem coordenada não há pin: a ferramenta some do toolset em vez de existir e sempre recusar.
    it 'nega quando nenhuma unidade tem coordenada' do
      unidade(cidade: 'Sorriso')

      expect(tool).not_to be_active
    end

    it 'nega quando a única unidade com coordenada está desativada' do
      unidade(cidade: 'Sorriso', ativa: false, latitude: -12.545, longitude: -55.711)

      expect(tool).not_to be_active
    end

    it 'aceita quando há unidade ativa com coordenada' do
      unidade(cidade: 'Sorriso', latitude: -12.545, longitude: -55.711)

      expect(tool).to be_active
    end

    it 'não enxerga unidade de outra conta' do
      create(:unit, account: create(:account), cidade: 'Sorriso', latitude: -12.545, longitude: -55.711)

      expect(tool).not_to be_active
    end
  end

  describe 'envio' do
    before { unidade(cidade: 'Sorriso', latitude: -12.545, longitude: -55.711) }

    it 'cria a mensagem com o anexo de localização e as coordenadas do cadastro' do
      expect { tool.perform(contexto, cidade: 'Sorriso') }.to change { conversation.messages.count }.by(1)

      anexo = conversation.messages.last.attachments.last
      expect(anexo.file_type).to eq('location')
      expect(anexo.coordinates_lat).to be_within(0.001).of(-12.545)
      expect(anexo.coordinates_long).to be_within(0.001).of(-55.711)
    end

    it 'casa a cidade sem acento e sem caixa, como a busca faz' do
      expect { tool.perform(contexto, cidade: 'sorriso') }.to change { conversation.messages.count }.by(1)
    end

    it 'avisa quando não consegue identificar a conversa' do
      vazio = Struct.new(:state).new({})

      expect(tool.perform(vazio, cidade: 'Sorriso')).to include('identificar a conversa')
    end
  end

  describe 'o que NÃO pode virar pin inventado' do
    it 'recusa cidade sem unidade e lista as que existem, sem mandar o mapa de outra' do
      unidade(cidade: 'Sorriso', latitude: -12.545, longitude: -55.711)

      resposta = tool.perform(contexto, cidade: 'Rondonópolis')

      expect(resposta).to include('Não há unidade cadastrada')
      expect(resposta).to include('Sorriso')
      expect(conversation.messages.count).to eq(0)
    end

    # Existe a loja, não existe a coordenada. A resposta tem que mandar responder pelo endereço —
    # e não pode ser confundida com "não temos loja aí".
    it 'recusa unidade sem coordenada mandando responder pelo endereço' do
      unidade(cidade: 'Vera')
      unidade(cidade: 'Sorriso', latitude: -12.545, longitude: -55.711)

      resposta = tool.perform(contexto, cidade: 'Vera')

      expect(resposta).to include('não tem coordenada cadastrada')
      expect(resposta).to include('NÃO invente')
      expect(conversation.messages.count).to eq(0)
    end

    it 'não envia pin de unidade desativada' do
      unidade(cidade: 'Rondonópolis', ativa: false, latitude: -16.470, longitude: -54.635)
      unidade(cidade: 'Sorriso', latitude: -12.545, longitude: -55.711)

      resposta = tool.perform(contexto, cidade: 'Rondonópolis')

      expect(resposta).to include('Não há unidade cadastrada')
      expect(conversation.messages.count).to eq(0)
    end

    it 'anuncia falha de envio sem deixar concluir que a unidade não existe' do
      unidade(cidade: 'Sorriso', latitude: -12.545, longitude: -55.711)
      allow(tool).to receive(:find_conversation).and_raise(StandardError, 'boom')

      resposta = tool.perform(contexto, cidade: 'Sorriso')

      expect(resposta).to include('falha de envio, não ausência')
    end
  end

  describe 'registro no toolset' do
    it 'resolve a classe a partir do id declarado no tools.yml' do
      expect(Captain::Assistant.resolve_tool_class('enviar_localizacao_unidade')).to eq(described_class)
    end

    it 'está registrada e disponível para o agente' do
      expect(Captain::Assistant.built_in_tool_ids).to include('enviar_localizacao_unidade')
    end
  end
end
