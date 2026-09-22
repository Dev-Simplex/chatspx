require 'rails_helper'

# Golden test do CAMINHO DE SUCESSO da nota.
#
# O argumento que este PR precisa sustentar é um só: sem falha na conversa, a nota sai byte a
# byte igual à de antes. Ele não se prova rodando o harness de conduta contra a produção de um
# cliente — prova-se aqui, contra a saída GRAVADA do código anterior.
#
# `spec/fixtures/captain/tool_context_note_golden.yml` foi gerado com
# `enterprise/app/services/captain/conversation/tool_context_note.rb` restaurado de
# `origin/producao` (o código de antes deste PR). Por isso ele é prova, e não retrato do
# próprio comportamento novo. Para regravá-lo depois de uma mudança DELIBERADA no caminho de
# sucesso: restaure o arquivo da branch de referência, rode o gerador e confira o diff linha a
# linha — um golden regravado sem olhar o diff não vale nada.
#
# Só há chamadas com `status: 'ok'` aqui, de propósito: é exatamente o que uma conversa sem
# falha produz hoje em produção. Falha, `vazio_completo` e `parcial` mudam a nota de propósito
# e são cobertos em tool_context_note_spec.rb.
golden = YAML.load_file(
  File.expand_path('../../../../fixtures/captain/tool_context_note_golden.yml', __dir__)
).freeze

RSpec.describe Captain::Conversation::ToolContextNote, type: :model do
  let(:account) { create(:account, custom_attributes: { 'captain_tool_context' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:assistant) { create(:captain_assistant, account: account) }

  def montar(chamadas)
    chamadas.each do |c|
      Captain::ToolCall.create!(
        account_id: account.id, conversation_id: conversation.id, captain_assistant_id: assistant.id,
        tool_name: c['tool'], args: c['args'], result_preview: c['preview'],
        status: 'ok', created_at: c['min'].minutes.ago
      )
    end
    described_class.new(conversation: conversation.reload).text
  end

  # Sem isto, um fixture vazio ou truncado deixaria a suíte verde sem testar nada.
  it 'tem casos gravados, todos com texto' do
    expect(golden.size).to be >= 7
    expect(golden.map { |c| c['texto'] }).to all(be_present)
  end

  golden.each do |caso|
    it "reproduz byte a byte: #{caso['nome']}" do
      expect(montar(caso['chamadas'])).to eq(caso['texto'])
    end
  end
end
