require 'rails_helper'

# A peça que faltava do desvio de preferência: o `DistribuirService` LÊ
# `custom_attributes['rodizio_preferencia']` desde 31/07, mas ninguém escrevia o campo, então o
# desvio nasceu inerte. Chegou pelo PR #67 sem teste.
RSpec.describe Captain::Tools::RegistrarPreferenciaAtendenteTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  describe '#perform' do
    it 'grava o nome pedido na chave que o Motor le' do
      tool.perform(tool_context, nome: 'Ana')

      expect(conversation.reload.custom_attributes['rodizio_preferencia']).to eq('Ana')
    end

    # A tool manda gravar o nome "exatamente como o cliente falou": corrigir aqui inventaria uma
    # pessoa. Quem resolve nome em gente é o DistribuirService, contra o pool.
    it 'nao corrige nem completa o nome, so tira o espaco em volta' do
      tool.perform(tool_context, nome: '  ana paula  ')

      expect(conversation.reload.custom_attributes['rodizio_preferencia']).to eq('ana paula')
    end

    it 'nao grava nada com nome vazio' do
      resultado = tool.perform(tool_context, nome: '   ')

      expect(conversation.reload.custom_attributes).not_to have_key('rodizio_preferencia')
      expect(resultado).to include('Nome vazio')
    end

    it 'preserva os outros custom_attributes da conversa' do
      conversation.update!(custom_attributes: { 'produto' => 'locacao' })

      tool.perform(tool_context, nome: 'Ana')

      expect(conversation.reload.custom_attributes).to include('produto' => 'locacao',
                                                               'rodizio_preferencia' => 'Ana')
    end

    it 'sobrescreve a preferencia anterior quando o cliente muda de ideia' do
      tool.perform(tool_context, nome: 'Ana')
      tool.perform(tool_context, nome: 'Bruno')

      expect(conversation.reload.custom_attributes['rodizio_preferencia']).to eq('Bruno')
    end

    it 'nao estoura sem conversa no contexto' do
      resultado = tool.perform(Struct.new(:state).new({}), nome: 'Ana')

      expect(resultado).to include('Não consegui identificar a conversa')
    end

    # O retorno é instrução de conduta e chega ao modelo no turno em que ele acabou de agir —
    # é o único momento em que "não prometa" alcança a tentação de prometer.
    it 'devolve a conduta de NAO confirmar o nome ao cliente' do
      resultado = tool.perform(tool_context, nome: 'Ana')

      expect(resultado).to include('NÃO diga ao cliente quem vai atendê-lo')
    end
  end

  # Nome concreto em descrição de ferramenta vira valor copiado: já aconteceu neste projeto, com
  # um código de imóvel de exemplo que a IA passou a mandar sempre.
  describe '#description' do
    it 'nao traz nome de exemplo que a IA possa copiar' do
      expect(tool.description).not_to match(/["']\p{Lu}\p{Ll}+["']/)
    end

    it 'avisa para nao prometer que a pessoa vai atender' do
      expect(tool.description).to include('NÃO prometa')
    end
  end
end
