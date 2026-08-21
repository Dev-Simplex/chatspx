# frozen_string_literal: true

require 'rails_helper'

# Mecanismo de aceite do bloco 2.13 — a SEGUNDA raspagem de PII.
#
# ACEITE (§2.2): «Erro forçado aparece no GlitchTip **com PII removida**».
#
# A primeira raspagem é `widget/helpers/telemetry.js`, coberta por
# `app/javascript/widget/helpers/specs/telemetry.spec.js`. Esta é a do servidor,
# e ela existe porque a outra roda na máquina de outra pessoa: build antigo em
# cache, navegador que falhou no `replace`, ou alguém batendo no endpoint com
# `curl`. Os casos abaixo são os MESMOS dos dois lados, de propósito — duas
# listas de padrões para um contrato só é o risco conhecido desta escolha, e é
# assim que ele fica visível quando divergir.
RSpec.describe Widget::ErrorReport do
  let(:account) { create(:account) }
  let(:web_widget) { create(:channel_widget, account: account) }

  describe '.scrub' do
    it 'remove e-mail' do
      expect(described_class.scrub('falhou para joao.silva@empresa.com.br agora'))
        .to eq('falhou para [email] agora')
    end

    it 'remove telefone em formato brasileiro e internacional' do
      expect(described_class.scrub('ligou de +55 11 98765-4321')).to eq('ligou de [telefone]')
      expect(described_class.scrub('(11) 98765-4321')).to eq('[telefone]')
      expect(described_class.scrub('+1-415-555-0132')).to eq('[telefone]')
    end

    it 'remove CPF e CNPJ' do
      expect(described_class.scrub('doc 123.456.789-09 aqui')).to eq('doc [documento] aqui')
      expect(described_class.scrub('12.345.678/0001-95')).to eq('[documento]')
    end

    it 'remove o que parece credencial' do
      expect(described_class.scrub('Authorization: Bearer abc.def.ghi')).to eq('Authorization: [credencial]')
      expect(described_class.scrub('cw_conversation=eyJhbGciOiJIUzI1NiJ9.aaa.bbb')).to eq('cw_conversation=[credencial]')
    end

    it 'preserva o que é diagnóstico, não identidade' do
      # Raspar demais é tão ruim quanto raspar de menos: relatório sem a
      # mensagem do erro não serve para nada.
      texto = "Cannot read properties of undefined (reading 'matches')"
      expect(described_class.scrub(texto)).to eq(texto)
      expect(described_class.scrub('TypeError em conversation/actions.js:68'))
        .to eq('TypeError em conversation/actions.js:68')
    end

    it 'atravessa hash e array aninhados' do
      expect(described_class.scrub({ a: 'x maria@teste.com', b: ['tel (11) 98765-4321', 7] }))
        .to eq({ a: 'x [email]', b: ['tel [telefone]', 7] })
    end
  end

  describe '#perform' do
    # A gem `sentry-ruby` só é carregada quando `SENTRY_DSN` está presente
    # (`config/application.rb:24`), e o ambiente de teste não tem DSN — a
    # constante `Sentry` simplesmente NÃO EXISTE aqui. Por isso `stub_const`:
    # sem ele estes exemplos morrem com `NameError` antes de medir qualquer
    # coisa. Foi assim que se descobriu que o serviço precisava do `defined?`.
    # `double` e não `instance_double`: um duplo VERIFICÁVEL precisa da classe
    # real para conferir a assinatura, e aqui a constante `Sentry` não existe —
    # é justamente o que este bloco de testes contorna. Verificar contra o nada
    # não é possível, então a exceção é local e declarada.
    # rubocop:disable RSpec/VerifiedDoubles
    let(:scope) { double('Sentry::Scope', set_tags: nil, set_context: nil) }
    let(:sentry) { double('Sentry', initialized?: true, capture_message: nil) }
    # rubocop:enable RSpec/VerifiedDoubles

    before do
      allow(sentry).to receive(:with_scope).and_yield(scope)
      stub_const('Sentry', sentry)
    end

    it 'manda para o Sentry uma mensagem já raspada' do
      described_class.new(
        { name: 'TypeError', message: 'falha ao enviar para cliente@empresa.com', context: { origem: 'chat' } }.with_indifferent_access,
        web_widget
      ).perform

      expect(sentry).to have_received(:capture_message)
        .with('[widget] TypeError: falha ao enviar para [email]', level: :error)
    end

    it 'raspa também a pilha, que é onde a PII costuma se esconder' do
      described_class.new(
        { name: 'Error', message: 'x', stack: 'at envia (maria@teste.com:1:1)', context: { origem: 'chat' } }.with_indifferent_access,
        web_widget
      ).perform

      expect(scope).to have_received(:set_context).with('widget', hash_including(stack: 'at envia ([email]:1:1)'))
    end

    it 'corta query string da URL mesmo que o cliente não tenha cortado' do
      # Quem bate no endpoint à mão não passou pelo corte do navegador. Query
      # string de site de terceiro carrega `?email=` com frequência.
      described_class.new(
        { name: 'Error', message: 'x', url: 'https://loja.test/c?email=a@b.com', context: { origem: 'chat' } }.with_indifferent_access,
        web_widget
      ).perform

      expect(scope).to have_received(:set_context).with('widget', hash_including(url: 'https://loja.test/c'))
    end

    it 'etiqueta a conta e a caixa, para a triagem saber de quem é' do
      described_class.new(
        { name: 'Error', message: 'x', context: { origem: 'store/contacts' } }.with_indifferent_access,
        web_widget
      ).perform

      expect(scope).to have_received(:set_tags).with(
        hash_including(source: 'web_widget', account_id: web_widget.inbox.account_id, inbox_id: web_widget.inbox.id)
      )
    end

    it 'não explode quando o Sentry está carregado mas não inicializado' do
      allow(sentry).to receive(:initialized?).and_return(false)

      expect do
        expect(described_class.new({ name: 'Error', message: 'x' }.with_indifferent_access, web_widget).perform).to be(false)
      end.not_to raise_error
    end
  end

  describe '#perform numa instalação SEM Sentry' do
    # VM sem `SENTRY_DSN`: a gem nem e carregada e a constante nao existe. Sem o
    # `defined?` no servico, o endpoint de telemetria devolveria 500 exatamente nas
    # instalacoes sem observabilidade nenhuma.
    #
    # Antes este exemplo contava com o ambiente cru (`expect(defined?(Sentry)).to be_nil`).
    # Deixou de valer quando o GlitchTip entrou na frota: ele usa a gem sentry-ruby, entao
    # a constante existe aqui e o teste media o ambiente, nao o servico. `hide_const` torna
    # a ausencia explicita e deterministica, em qualquer maquina.
    it 'devolve false em silêncio, sem NameError' do
      hide_const('Sentry')
      expect(defined?(Sentry)).to be_nil

      expect do
        expect(described_class.new({ name: 'Error', message: 'x' }.with_indifferent_access, web_widget).perform).to be(false)
      end.not_to raise_error
    end
  end
end
