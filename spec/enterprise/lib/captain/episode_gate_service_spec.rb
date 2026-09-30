require 'rails_helper'

# O gate lia `captain_tool_calls.status` como se fosse binário ('ok' ou 'error'). Com o
# Captain::Tools::Result o campo passa a ter cinco valores, e estes exemplos fixam o que cada
# um significa AQUI — é o ponto onde um status novo passaria despercebido e viraria flagra
# falso ou flagra que some.
RSpec.describe Captain::EpisodeGateService do
  subject(:findings) { described_class.new(episode: episodio).perform }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { create(:captain_assistant, account: account) }

  def fala_da_ia(texto, quando: Time.current)
    create(:message, account: account, inbox: inbox, conversation: conversation,
                     message_type: :outgoing, sender: assistant, content: texto, created_at: quando)
  end

  def tool(nome, preview, opcoes = {})
    Captain::ToolCall.create!(
      account_id: account.id, conversation_id: conversation.id, captain_assistant_id: assistant.id,
      tool_name: nome, args: opcoes.fetch(:args, {}), result_preview: preview,
      status: opcoes.fetch(:status, 'ok'), error: opcoes[:erro],
      created_at: opcoes.fetch(:quando, 2.minutes.ago)
    )
  end

  # O episódio é a janela: precisa existir e abraçar as mensagens e as tool calls.
  def episodio
    mensagens = conversation.messages.reorder(:created_at).to_a
    Captain::ConversationEpisode.create!(
      account_id: account.id, conversation_id: conversation.id, seq: 1,
      first_message_id: mensagens.first.id, last_message_id: mensagens.last.id,
      started_at: 10.minutes.ago, last_message_at: Time.current, mensagens: mensagens.size
    )
  end

  describe 'busca que rodou e não achou nada' do
    # `vazio_completo` é consulta BEM-SUCEDIDA. Comparar com `== 'ok'` a descartaria em
    # silêncio, e o gate pararia de reconhecer os códigos que ela devolveu.
    it 'continua contando como busca do episódio' do
      tool('buscar_imovel', 'cód 9908 Casa no Centro', status: 'vazio_completo')
      tool('enviar_fotos_imovel', 'enviei 3 fotos', args: { 'codigo' => '1234' }, quando: 1.minute.ago)
      fala_da_ia('te mandei as fotos')

      expect(findings.map { |f| f['categoria'] }).to include('usou_tool_errada')
    end
  end

  describe 'consulta que respondeu sem conteúdo' do
    # O retorno de um `desconhecido` não é vazio nem casa com EMPTY_RESULT. Lido como
    # "a tool trouxe resultados", a negação seguinte da IA viraria um flagra FALSO.
    it 'não vira contradição quando a IA diz que não encontrou' do
      tool('buscar_cep', 'A consulta foi respondida, mas veio sem conteúdo.', status: 'desconhecido')
      fala_da_ia('não encontrei nada por aqui', quando: 1.minute.ago)

      expect(findings.map { |f| f['categoria'] }).not_to include('contradisse_tool')
    end

    it 'também não é reportada como ferramenta que falhou — ela respondeu' do
      tool('buscar_cep', 'A consulta foi respondida, mas veio sem conteúdo.', status: 'desconhecido')
      fala_da_ia('um instante')

      expect(findings.map { |f| f['categoria'] }).not_to include('ignorou_erro_da_tool')
    end
  end

  describe 'consulta que falhou' do
    # Antes deste PR, ferramenta que capturava o próprio erro e devolvia "Não consegui..."
    # era gravada como 'ok' e NUNCA chegava aqui: a falha existia e era invisível ao eval.
    it 'vira finding de erro de ferramenta' do
      tool('buscar_imovel', nil, status: 'error', erro: 'timeout: Net::ReadTimeout')
      fala_da_ia('não temos nada nesse perfil')

      expect(findings.map { |f| f['categoria'] }).to include('ignorou_erro_da_tool')
    end

    it 'não é lida como resultado que a IA contradisse' do
      tool('buscar_imovel', nil, status: 'error', erro: 'timeout')
      fala_da_ia('não encontrei nada', quando: 1.minute.ago)

      expect(findings.map { |f| f['categoria'] }).not_to include('contradisse_tool')
    end
  end

  describe 'busca bem-sucedida que a IA nega' do
    it 'segue sendo flagrada' do
      tool('buscar_imovel', 'cód 9908 Casa no Centro, R$ 1.200')
      fala_da_ia('não encontrei nenhum imóvel nesse perfil', quando: 1.minute.ago)

      expect(findings.map { |f| f['categoria'] }).to include('contradisse_tool')
    end
  end
end
