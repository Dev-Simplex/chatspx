require 'rails_helper'

# O contrato de construcao do Llm::LegacyBaseOpenAiService.
#
# POR QUE ESTE ARQUIVO EXISTE
#
# `Captain::Llm::PdfProcessingService` e `Captain::Llm::PaginatedFaqGeneratorService`
# passaram de 31/03/2026 a 18/08/2026 estourando ArgumentError na INSTANCIACAO, em toda VM
# da frota: o merge do upgrade v4.12.1 (cb0d3d999f) trouxe a versao upstream do base, que
# nao aceita argumento, e deixou as duas subclasses chamando `super(account: ...)`.
#
# Os specs das duas classes existiam e estavam vermelhos o tempo todo. O que faltava era
# alguem OLHAR: a suite enterprise/llm carrega dezenas de falhas de WebMock por specs que
# tentam alcancar api.openai.com, e um vermelho novo se perde no meio de vermelho velho.
#
# Este arquivo e o oposto disso: nao toca rede, nao depende de fixture pesada, e varre as
# subclasses SOZINHO — subclasse nova nasce coberta sem ninguem lembrar de adiciona-la
# aqui. Se um dia o base mudar de assinatura de novo, quem quebrar e cobrado por um teste
# que fala do assunto, e nao por um erro de mock a trinta arquivos de distancia.
RSpec.describe Llm::LegacyBaseOpenAiService do
  # Toda subclasse construida com um `Captain::Document`. Se aparecer uma que precise de
  # outro argumento, ela entra aqui de proposito — a lista e a declaracao de como cada uma
  # se constroi, e obriga quem cria subclasse a dizer isso em algum lugar.
  # Cada subclasse declara COMO se constroi e QUAL chave usa. A declaracao e o ponto: o
  # defeito nasceu de uma subclasse chamando um contrato de construcao que nao existia mais,
  # e ninguem tinha onde perceber.
  subclasses = {
    'Captain::Llm::PdfProcessingService' => {
      build: ->(ctx) { Captain::Llm::PdfProcessingService.new(ctx[:document]) },
      key: 'CAPTAIN_OPEN_AI_API_KEY'
    },
    'Captain::Llm::PaginatedFaqGeneratorService' => {
      build: ->(ctx) { Captain::Llm::PaginatedFaqGeneratorService.new(ctx[:document]) },
      key: 'CAPTAIN_OPEN_AI_API_KEY'
    },
    # A que o b1c3c7812b corrigiu na epoca, e a unica das tres com chave propria.
    'Messages::AudioTranscriptionService' => {
      build: ->(ctx) { Messages::AudioTranscriptionService.new(ctx[:attachment]) },
      key: 'AUDIO_OPEN_AI_API_KEY'
    }
  }.freeze

  let(:document) { create(:captain_document) }
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }
  let(:contexto) { { document: document, attachment: attachment } }

  before do
    installation_config = instance_double(InstallationConfig, value: 'test-api-key')
    allow(InstallationConfig).to receive(:find_by!)
      .with(name: 'CAPTAIN_OPEN_AI_API_KEY').and_return(installation_config)
    allow(InstallationConfig).to receive(:find_by).and_call_original
    allow(InstallationConfig).to receive(:find_by)
      .with(name: 'CAPTAIN_OPEN_AI_API_KEY').and_return(installation_config)
  end

  describe 'toda subclasse se constroi' do
    subclasses.each do |nome, decl|
      it "#{nome} instancia sem erro" do
        expect { decl[:build].call(contexto) }.not_to raise_error
      end

      it "#{nome} termina a construcao com um client utilizavel" do
        service = decl[:build].call(contexto)

        expect(service.client).to be_a(OpenAI::Client)
      end
    end

    # A lista acima so vale enquanto cobrir todo mundo. Este exemplo e o que a mantem
    # honesta: subclasse nova sem entrada na lista reprova aqui, com o nome dela no erro.
    it 'a lista cobre todas as subclasses carregadas' do
      Rails.application.eager_load! unless Rails.application.config.eager_load

      carregadas = described_class.subclasses.map(&:name).sort
      declaradas = subclasses.keys.sort

      expect(carregadas - declaradas).to eq([]),
                                         "subclasse sem cobertura de construcao: #{(carregadas - declaradas).join(', ')}"
    end
  end

  describe 'a chave resolvida' do
    # O commit b1c3c7812b separou chaves por proposito (eval e transcricao de audio).
    # Ingestao de PDF e geracao de FAQ NAO entraram na separacao: elas seguem na chave
    # padrao do Captain. Este exemplo trava isso — se alguem der uma chave propria a elas,
    # que seja de propósito e nao por acidente de heranca.
    subclasses.each do |nome, decl|
      it "#{nome} resolve #{decl[:key]}" do
        service = decl[:build].call(contexto)

        expect(service.send(:api_key_config_name)).to eq(decl[:key])
      end
    end
  end
end
