require 'rails_helper'

# DEFEITOS ABERTOS — todo exemplo aqui é VERMELHO de propósito.
#
# Cada um afirma o comportamento CERTO de algo que a produção hoje não cumpre. Ficam juntos e
# marcados com `:defeito_aberto` para que o portão de CI possa rodar `--tag ~defeito_aberto` e
# ainda assim continuar vendo esta lista crescer ou encolher — sem que "suíte vermelha" vire
# ruído de fundo que ninguém lê.
#
# Um exemplo só sai daqui de duas formas: o defeito é corrigido (e ele passa a viver no arquivo
# do cenário normal), ou alguém decide conscientemente que o comportamento fica como está e
# escreve a decisão no doc 06. Reescrever a asserção para caber no que a produção faz hoje não
# é nenhuma das duas.
# O sujeito de um cenário de harness é um COMPORTAMENTO atravessando várias classes, não uma
# classe. Nomeá-lo por classe esconderia justamente o que ele cobre.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'nível 1: defeitos abertos', :defeito_aberto do
  let(:account) { create(:account, custom_attributes: { 'captain_tool_context' => true }) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:roteiro) { Spx::Harness::Nivel1::Roteiro.new(assistant: assistant, conversation: conversation) }

  before { rede_falsa('crm.ficticio.invalid') }

  def acao(template)
    create(:captain_custom_tool, account: account, slug: "agendar_#{SecureRandom.hex(3)}",
                                 http_method: 'POST', endpoint_url: 'https://crm.ficticio.invalid/visitas',
                                 response_template: template)
  end

  def rodar(custom_tool)
    roteiro.executar([{ custom_tool: custom_tool, args: {} }]).last
  end

  # ==========================================================================================
  # 1. O 2xx que carrega a RECUSA dentro do corpo vira "realizada com sucesso".
  #
  # É o caso que motivou a regra: API de CRM que responde 200 com `{"sucesso": false}`. A regra
  # decidida é que 2xx ilegível em AÇÃO é INDETERMINADO. O caminho ACAO_ILEGIVEL existe, mas
  # quase nunca é alcançado, porque três camadas engolem o erro antes:
  #
  #   1. `parse_response_body` faz rescue de JSON::ParserError e devolve o corpo cru;
  #   2. o Liquid roda com `strict: false`, então campo ausente rende string VAZIA em vez de
  #      levantar (isso é deliberado e certo: API externa omite campo o tempo todo);
  #   3. corpo formatado vazio cai no ramo "2xx sem corpo", que para AÇÃO é ACAO_CONFIRMADA.
  #
  # Resultado medido: a ferramenta diz ao modelo que a visita foi agendada quando o CRM disse
  # que o horário está ocupado.
  # ==========================================================================================
  describe 'o 2xx com recusa no corpo' do
    it 'não pode virar confirmação quando o template não conseguiu ler a resposta' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas')
        .to_return(status: 200, body: '{"sucesso":false,"erro":"horário ocupado"}')

      passo = rodar(acao('{{ response.visita_id }}'))

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_ILEGIVEL)
      expect(passo.status).to eq('desconhecido')
    end

    it 'não pode virar confirmação quando o corpo nem é JSON' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas')
        .to_return(status: 200, body: 'ERRO INTERNO DO SISTEMA')

      passo = rodar(acao('{{ response.visita_id }}'))

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_ILEGIVEL)
      expect(passo.status).to eq('desconhecido')
    end

    # CONTROLE POSITIVO, e ele PASSA hoje: quando o template acha o campo, a confirmação é
    # legítima. Está aqui para provar que a correção não pode ser "nunca confirmar".
    it 'confirma normalmente quando o template consegue ler a resposta' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas')
        .to_return(status: 200, body: '{"visita_id":900}')

      expect(rodar(acao('visita {{ response.visita_id }}')).resultado).to eq('visita 900')
    end
  end

  # ==========================================================================================
  # 2. Resultado com bytes inválidos em UTF-8 some do trace, em silêncio.
  #
  # O `record_tool_trace` é best-effort por construção (nunca quebra a tool), e o insert falha
  # quando o `result_preview` tem byte inválido. A consequência não é cosmética: sem linha em
  # `captain_tool_calls` a chamada fica fora da nota do turno seguinte e fora do eval — o
  # modelo perde o retorno e volta a responder de memória, que é o defeito que a nota fecha.
  # ==========================================================================================
  describe 'o resultado em codificação inválida' do
    it 'continua sendo registrado no trace' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas')
        .to_return(status: 200, body: "\xFF\xFE\x00confirmado".dup.force_encoding('ASCII-8BIT'))

      passo = rodar(acao(nil))

      expect(passo.trace).to be_present
    end
  end
end
# rubocop:enable RSpec/DescribeClass
