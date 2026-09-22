require 'rails_helper'

# NÍVEL 1 — a diferença entre CONSULTAR e AGIR, com o CRM fora do ar.
#
# Cenário inteiramente FICTÍCIO. Não é a conta 1 nem nenhuma outra: é uma conta com duas custom
# tools, uma GET que consulta e uma POST que age, contra um host `.invalid`. Nenhuma credencial,
# nenhum endpoint e nenhum dado de cliente entram aqui — e é por isso que este arquivo pode
# rodar na CI e na máquina de qualquer um.
#
# O que está sob teste é a pergunta que a ferramenta responde. Numa CONSULTA a pergunta é
# "consegui ler o dado?" e a falha pode ser dita ao cliente. Numa AÇÃO a pergunta é "a operação
# aconteceu?", e aí "não consegui" é uma afirmação que a ferramenta não tem como sustentar:
#
#   - a requisição não saiu da máquina  -> a ação NÃO ocorreu (pode ser dito);
#   - a requisição saiu e não voltou     -> NÃO SE SABE (não repetir, não afirmar, escalar);
#   - 2xx ilegível                       -> NÃO SE SABE (CRM que responde 200 com recusa no corpo);
#   - 4xx (fora 408/429)                 -> recusada;
#   - 2xx, com ou sem corpo              -> realizada.
#
# Os dois erros que isso fecha custam dinheiro de verdade: o timeout que virava "não consegui" e
# nascia a proposta duplicada, e o 204 de um cancelamento que virava `desconhecido` e o modelo
# cancelava de novo.
# O sujeito de um cenário de harness é um COMPORTAMENTO atravessando várias classes, não uma
# classe. Nomeá-lo por classe esconderia justamente o que ele cobre.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'nível 1: consulta x ação quando o sistema externo falha' do
  let(:account) { create(:account, custom_attributes: { 'captain_tool_context' => true }) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:roteiro) { Spx::Harness::Nivel1::Roteiro.new(assistant: assistant, conversation: conversation) }

  let(:consulta) do
    create(:captain_custom_tool, account: account, slug: 'consultar_pedido', http_method: 'GET',
                                 endpoint_url: 'https://crm.ficticio.invalid/pedidos/77',
                                 response_template: nil)
  end
  let(:acao) do
    create(:captain_custom_tool, account: account, slug: 'agendar_visita', http_method: 'POST',
                                 endpoint_url: 'https://crm.ficticio.invalid/visitas',
                                 response_template: nil)
  end
  # A MESMA ação, com template. É a configuração real de quem cadastra custom tool: o template
  # é o que transforma a resposta do CRM em frase para o modelo — e era por dentro dele que a
  # recusa de 200 virava confirmação.
  let(:acao_com_template) do
    create(:captain_custom_tool, account: account, slug: 'agendar_visita_formatada', http_method: 'POST',
                                 endpoint_url: 'https://crm.ficticio.invalid/visitas',
                                 response_template: '{{ response.visita_id }}')
  end
  # A MESMA coisa, com texto literal em volta do campo. Parece detalhe e não é: ver o defeito
  # aberto no fim do arquivo.
  let(:acao_com_prefixo) do
    create(:captain_custom_tool, account: account, slug: 'agendar_visita_prefixada', http_method: 'POST',
                                 endpoint_url: 'https://crm.ficticio.invalid/visitas',
                                 response_template: 'visita {{ response.visita_id }}')
  end

  # O DNS é limite de rede igual ao HTTP: o guard de SSRF do HttpTool resolve o host ANTES de
  # montar a requisição. Sem fechar esse limite, toda falha do cenário vira "não chegou a ser
  # enviada" — a única classificação que afirma com segurança que a ação não aconteceu.
  before { rede_falsa('crm.ficticio.invalid') }

  def rodar(custom_tool)
    roteiro.executar([{ custom_tool: custom_tool, args: {} }]).last
  end

  describe 'a tool que CONSULTA' do
    # CONTROLE POSITIVO: sem ele, um classificador que devolvesse falha sempre passaria em
    # todos os exemplos negativos abaixo.
    it 'devolve o corpo quando o sistema responde' do
      stub_request(:get, 'https://crm.ficticio.invalid/pedidos/77')
        .to_return(status: 200, body: '{"pedido":77,"situacao":"em rota"}')

      passo = rodar(consulta)

      expect(passo.resultado).to include('em rota')
      expect(passo.status).to eq('ok')
    end

    # A falha de consulta PODE ser dita ao cliente — e precisa vir com a porta fechada para a
    # resposta de memória, que é o defeito que o tipo existe para impedir.
    it 'diz que a consulta falhou e proíbe concluir ausência' do
      stub_request(:get, 'https://crm.ficticio.invalid/pedidos/77').to_timeout

      passo = rodar(consulta)

      expect(passo.resultado).to include(Captain::Tools::HttpTool::FALHAS[:timeout])
      expect(passo.resultado).to include(Captain::Tools::HttpTool::NAO_INVENTE)
      expect(passo.status).to eq('error')
    end

    # 2xx sem corpo não é "não existe". Declarar ausência aqui seria inventar ausência.
    it 'não transforma resposta sem conteúdo em ausência confirmada' do
      stub_request(:get, 'https://crm.ficticio.invalid/pedidos/77').to_return(status: 204, body: '')

      passo = rodar(consulta)

      expect(passo.resultado).to include(Captain::Tools::HttpTool::SEM_CONTEUDO)
      expect(passo.status).not_to eq('vazio_completo')
    end
  end

  describe 'a tool que AGE' do
    # CONTROLE POSITIVO.
    it 'confirma quando o sistema responde com corpo' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas')
        .to_return(status: 200, body: '{"visita":900,"confirmada":true}')

      passo = rodar(acao)

      expect(passo.resultado).to include('900')
      expect(passo.status).to eq('ok')
    end

    # 204 é resposta NORMAL de operação que não devolve corpo. Tratá-la como `desconhecido`
    # fazia o modelo repetir a operação — foi assim que nasceu o cancelamento em dobro.
    it 'confirma o 2xx sem corpo em vez de chamá-lo de desconhecido' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas').to_return(status: 204, body: '')

      passo = rodar(acao)

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_CONFIRMADA)
      expect(passo.status).to eq('ok')
    end

    # O CASO AMBÍGUO, e o motivo deste arquivo existir. A requisição saiu; a resposta não
    # voltou. Não se sabe se a visita foi agendada. A ferramenta não pode dizer que falhou, não
    # pode dizer que deu certo e não pode convidar a repetir.
    # `Net::ReadTimeout`, não `to_timeout`. O WebMock traduz `to_timeout` em `Net::OpenTimeout`,
    # que é a conexão que NUNCA abriu — nada saiu, e aí "não foi realizada" é a classificação
    # certa. O caso ambíguo é o oposto: a requisição saiu e a resposta não voltou. A distinção
    # é do código e está certa; era a sonda que estava errada.
    it 'trata o timeout de LEITURA como INDETERMINADO: não repetir, não afirmar, escalar' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas').to_raise(Net::ReadTimeout)

      passo = rodar(acao)

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_INDETERMINADA)
      expect(passo.status).to eq('desconhecido')
      expect(passo.resultado).not_to include('não foi realizada')
      expect(passo.resultado).not_to include(Captain::Tools::HttpTool::NAO_INVENTE)
    end

    # 5xx também é indeterminado: o servidor pode ter gravado antes de falhar ao responder.
    it 'trata o 5xx como indeterminado' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas').to_return(status: 502, body: 'bad gateway')

      passo = rodar(acao)

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_INDETERMINADA)
      expect(passo.status).to eq('desconhecido')
    end

    # O 2xx com a RECUSA dentro do corpo. Este arquivo nasceu vermelho aqui: o nível 1 mostrou
    # que a regra do P0 não estava sendo cumprida e a ferramenta dizia "realizada com sucesso"
    # para uma operação que o CRM tinha recusado. Corrigido decidindo pelo corpo BRUTO antes do
    # template; fica como cenário normal, com o controle positivo ao lado.
    it 'não confirma quando o 200 carrega a recusa dentro do corpo' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas')
        .to_return(status: 200, body: '{"sucesso":false,"erro":"horário ocupado"}')

      passo = roteiro.executar([{ custom_tool: acao_com_template, args: {} }]).last

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_ILEGIVEL)
      expect(passo.status).to eq('desconhecido')
    end

    it 'confirma quando o template consegue ler a resposta' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas')
        .to_return(status: 200, body: '{"visita_id":900}')

      passo = roteiro.executar([{ custom_tool: acao_com_template, args: {} }]).last

      expect(passo.resultado).to eq('900')
      expect(passo.status).to eq('ok')
    end

    # DEFEITO ABERTO. O mesmo 200 com recusa no corpo, com um template que tem texto literal
    # em volta do campo: o Liquid rende `"visita "` — que NÃO é vazio —, o `formatado.present?`
    # dá true, e a recusa vira sucesso outra vez, agora com uma frase truncada sem sentido.
    #
    # A correção do corpo bruto fecha o template de campo nu; este caminho continua aberto, e é
    # a configuração MAIS comum de quem cadastra custom tool. Fechá-lo exige o render reportar
    # variável não resolvida — hoje ele roda com `strict: false` de propósito, porque API
    # externa omite campo o tempo todo. Não é uma linha: é uma decisão sobre o contrato do
    # template, e por isso está aqui em vez de remendada.
    it 'não confirma recusa quando o template tem texto literal em volta do campo', :defeito_aberto do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas')
        .to_return(status: 200, body: '{"sucesso":false,"erro":"horário ocupado"}')

      passo = roteiro.executar([{ custom_tool: acao_com_prefixo, args: {} }]).last

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_ILEGIVEL)
    end

    # 4xx que não é 408/429: o sistema recusou e a operação NÃO aconteceu. Isso pode ser dito.
    it 'trata o 4xx como recusa, e recusa é fato que pode ser dito' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas')
        .to_return(status: 422, body: '{"erro":"horário indisponível"}')

      passo = rodar(acao)

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_RECUSADA)
      expect(passo.status).to eq('error')
    end

    # 429 é a exceção dentro do 4xx: o servidor pode ter processado antes de desistir de
    # responder. Recusa não, indeterminado.
    it 'trata o 429 como indeterminado, não como recusa' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas').to_return(status: 429, body: '')

      passo = rodar(acao)

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_INDETERMINADA)
      expect(passo.status).to eq('desconhecido')
    end

    # A ÚNICA prova de que a ação não ocorreu: a requisição não saiu da máquina.
    it 'diz que a ação não foi realizada quando a requisição não chegou a sair' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas').to_raise(Errno::ECONNREFUSED)

      passo = rodar(acao)

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_NAO_REALIZADA)
      expect(passo.status).to eq('error')
    end

    # O par do exemplo acima, e o que separa os dois: o timeout de CONEXÃO também prova que
    # nada saiu. Sem este exemplo, inverter a classificação do OpenTimeout passaria despercebido.
    it 'diz que a ação não foi realizada quando a conexão nem chegou a abrir' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas').to_timeout

      passo = rodar(acao)

      expect(passo.resultado).to eq(Captain::Tools::HttpAcao::ACAO_NAO_REALIZADA)
      expect(passo.status).to eq('error')
    end
  end

  # Retorno de ferramenta não é mensagem: ele some no turno seguinte. A nota é o único caminho
  # de volta, e é nela que se vê se a falha chega ao modelo COMO falha — ou se some e vira uma
  # lacuna que ele preenche de memória.
  describe 'o que o turno seguinte recebe' do
    it 'carrega a ação indeterminada como não confirmada, com o aviso' do
      stub_request(:post, 'https://crm.ficticio.invalid/visitas').to_timeout
      rodar(acao)

      nota = roteiro.nota_do_proximo_turno

      expect(nota).to include('NÃO CONFIRMOU')
      expect(nota).to include(Captain::Conversation::ToolContextNote::AVISO_FALHA.strip)
    end

    # O trace sumia em silêncio quando o corpo não era UTF-8 válido — o Postgres recusa a linha
    # inteira — e com ele sumia a chamada da nota. Um CRM em latin-1 bastava. O que o nível 1
    # cobra é o efeito: a consulta continua chegando ao turno seguinte.
    it 'carrega a consulta mesmo quando o corpo veio em latin-1' do
      # 0xE3 é o `ã` em ISO-8859-1 e não é UTF-8 válido. Montado por byte, sem escape, para o
      # cenário não depender de como o arquivo de spec foi salvo.
      latin1 = 'pedido 77: entrega em S'.b + 0xE3.chr + 'o Paulo'.b
      stub_request(:get, 'https://crm.ficticio.invalid/pedidos/77').to_return(status: 200, body: latin1)
      rodar(consulta)

      # A nota rotula a chamada como `http` (o nome da classe), não pelo slug — e o byte inválido
      # virou `?` sem levar o resto junto, que é o ponto.
      expect(roteiro.nota_do_proximo_turno).to include('pedido 77: entrega em S?o Paulo')
    end

    # Sem falha, a nota sai byte a byte igual à de antes do P0 — é o que mantém a mudança
    # mensurável no nível 2 em vez de mover o chão junto.
    it 'não acrescenta aviso nenhum quando tudo deu certo' do
      stub_request(:get, 'https://crm.ficticio.invalid/pedidos/77').to_return(status: 200, body: '{"ok":true}')
      rodar(consulta)

      expect(roteiro.nota_do_proximo_turno).not_to include(Captain::Conversation::ToolContextNote::AVISO_FALHA.strip)
    end
  end
end
# rubocop:enable RSpec/DescribeClass
