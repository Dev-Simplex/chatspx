require 'rails_helper'

# O carrossel de fotos é passthrough do WhatsApp Cloud: a mensagem carrega o objeto
# `interactive` da Meta em content_attributes['interactive_payload'], e só o
# WhatsappCloudService#send_message lê essa chave. Num canal que não lê, a mensagem sai como
# o TEXTO do content ("📷 Carrossel: N fotos do imóvel X"), o cliente não recebe foto nenhuma
# e ninguém registra falha — a tool ainda devolve "enviei", e a IA garante ao cliente que
# mandou. Medido na Tozi (conta 6, inbox 101 Instagram): 9 chamadas, 0 imagem entregue.
RSpec.describe Captain::Tools::EnviarFotosImovelTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account, config: { 'fotos_carrossel' => true }) }
  let(:tool) { described_class.new(assistant) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  let(:detalhes) do
    { 'Codigo' => '9434', 'ImoCodigo' => '9391', 'Status' => 'VENDA', 'Categoria' => 'Casa',
      'Foto' => { '1' => { 'Foto' => 'https://cdn.example.com/1.jpg', 'Destaque' => 'Sim' },
                  '2' => { 'Foto' => 'https://cdn.example.com/2.jpg', 'Destaque' => 'Nao' },
                  '3' => { 'Foto' => 'https://cdn.example.com/3.jpg', 'Destaque' => 'Nao' } } }
  end

  let(:outgoing) { conversation.reload.messages.where(message_type: :outgoing).order(:id) }

  before do
    # Sem rede: o Vista e o download da foto não são o que está sob teste aqui.
    allow(tool).to receive(:fetch_detalhes).and_return(detalhes)
    allow(Down).to receive(:download) { StringIO.new('bytes-de-imagem') }
    allow(tool).to receive(:sleep)
  end

  context 'when the channel delivers interactive payloads (WhatsApp Cloud)' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                validate_provider_config: false, sync_templates: false)
    end
    let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }

    it 'sends a single carousel message carrying the interactive payload' do
      expect(tool.perform(tool_context, codigo: '9434')).to include('carrossel')

      expect(outgoing.count).to eq(1)
      expect(outgoing.first.content_attributes['interactive_payload']['type']).to eq('carousel')
      expect(outgoing.first.attachments).to be_empty
    end
  end

  # O Instagram é o caso medido, mas a regra vale para todo canal que não leia a chave
  # (WAHA, Messenger): sem carrossel, o fluxo cai no envio foto a foto — que o Instagram
  # entrega normalmente, porque a Meta busca a imagem pela URL do anexo.
  context 'when the channel does not deliver interactive payloads (Instagram)' do
    let(:channel) { create(:channel_instagram, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }

    it 'falls back to one message per photo, each carrying the image' do
      tool.perform(tool_context, codigo: '9434')

      expect(outgoing.count).to eq(3)
      expect(outgoing.map { |m| m.attachments.size }).to eq([1, 1, 1])
      expect(outgoing.flat_map { |m| (m.content_attributes || {}).keys }).not_to include('interactive_payload')
    end

    it 'records what it sent, so the next call advances instead of repeating' do
      tool.perform(tool_context, codigo: '9434')

      expect(conversation.reload.custom_attributes['fotos_offset_9434']).to eq(3)
    end
  end

  # A trava anti-alucinação compara o código pedido com o que a busca DESTA conversa
  # registrou. Ela lia só `codigos_buscados`, que guarda apenas o Codigo e corta em 40; o
  # `urls_imoveis` guarda Codigo E ImoCodigo e corta em 60. Como a IA cita ora um ora outro,
  # a trava recusava foto de imóvel legítimo — aconteceu na conversa 48182 da Tozi, com a
  # cliente pedindo fotos de três casas e levando "não" silencioso em todas.
  describe 'the anti-hallucination guard' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                validate_provider_config: false, sync_templates: false)
    end
    let(:conversation) do
      create(:conversation, account: account, inbox: channel.inbox,
                            custom_attributes: { 'codigos_buscados' => ['9434'],
                                                 'urls_imoveis' => { '9434' => 'https://site/9434',
                                                                     '9391' => 'https://site/9434' } })
    end

    it 'accepts the ImoCodigo that the search recorded only in urls_imoveis' do
      expect(tool.perform(tool_context, codigo: '9391')).not_to include('não apareceu na busca')
      expect(outgoing.count).to eq(1)
    end

    it 'still refuses a code that no search of this conversation returned' do
      expect(tool.perform(tool_context, codigo: '1234')).to include('não apareceu na busca')
      expect(outgoing).to be_empty
    end
  end
end
