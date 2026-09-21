require 'rails_helper'

RSpec.describe Captain::Tools::HttpTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:custom_tool) { create(:captain_custom_tool, account: account) }
  let(:tool) { described_class.new(assistant, custom_tool) }
  let(:tool_context) { Struct.new(:state).new({}) }

  describe '#active?' do
    it 'returns true when custom tool is enabled' do
      custom_tool.update!(enabled: true)

      expect(tool.active?).to be true
    end

    it 'returns false when custom tool is disabled' do
      custom_tool.update!(enabled: false)

      expect(tool.active?).to be false
    end
  end

  describe '#perform' do
    context 'with GET request' do
      before do
        custom_tool.update!(
          http_method: 'GET',
          endpoint_url: 'https://example.com/orders/123',
          response_template: nil
        )
        stub_request(:get, 'https://example.com/orders/123')
          .to_return(status: 200, body: '{"status": "success"}')
      end

      it 'executes GET request and returns response body' do
        result = tool.perform(tool_context)

        expect(result).to eq('{"status": "success"}')
        expect(WebMock).to have_requested(:get, 'https://example.com/orders/123')
      end
    end

    context 'with POST request' do
      before do
        custom_tool.update!(
          http_method: 'POST',
          endpoint_url: 'https://example.com/orders',
          request_template: '{"order_id": "{{ order_id }}"}',
          response_template: nil
        )
        stub_request(:post, 'https://example.com/orders')
          .with(body: '{"order_id": "123"}', headers: { 'Content-Type' => 'application/json' })
          .to_return(status: 200, body: '{"created": true}')
      end

      it 'executes POST request with rendered body' do
        result = tool.perform(tool_context, order_id: '123')

        expect(result).to eq('{"created": true}')
        expect(WebMock).to have_requested(:post, 'https://example.com/orders')
          .with(body: '{"order_id": "123"}')
      end
    end

    context 'with template variables in URL' do
      before do
        custom_tool.update!(
          endpoint_url: 'https://example.com/orders/{{ order_id }}',
          response_template: nil
        )
        stub_request(:get, 'https://example.com/orders/456')
          .to_return(status: 200, body: '{"order_id": "456"}')
      end

      it 'renders URL template with params' do
        result = tool.perform(tool_context, order_id: '456')

        expect(result).to eq('{"order_id": "456"}')
        expect(WebMock).to have_requested(:get, 'https://example.com/orders/456')
      end
    end

    context 'with bearer token authentication' do
      before do
        custom_tool.update!(
          auth_type: 'bearer',
          auth_config: { 'token' => 'secret_bearer_token' },
          endpoint_url: 'https://example.com/data',
          response_template: nil
        )
        stub_request(:get, 'https://example.com/data')
          .with(headers: { 'Authorization' => 'Bearer secret_bearer_token' })
          .to_return(status: 200, body: '{"authenticated": true}')
      end

      it 'adds Authorization header with bearer token' do
        result = tool.perform(tool_context)

        expect(result).to eq('{"authenticated": true}')
        expect(WebMock).to have_requested(:get, 'https://example.com/data')
          .with(headers: { 'Authorization' => 'Bearer secret_bearer_token' })
      end
    end

    context 'with basic authentication' do
      before do
        custom_tool.update!(
          auth_type: 'basic',
          auth_config: { 'username' => 'user123', 'password' => 'pass456' },
          endpoint_url: 'https://example.com/data',
          response_template: nil
        )
        stub_request(:get, 'https://example.com/data')
          .with(basic_auth: %w[user123 pass456])
          .to_return(status: 200, body: '{"authenticated": true}')
      end

      it 'adds basic auth credentials' do
        result = tool.perform(tool_context)

        expect(result).to eq('{"authenticated": true}')
        expect(WebMock).to have_requested(:get, 'https://example.com/data')
          .with(basic_auth: %w[user123 pass456])
      end
    end

    context 'with API key authentication' do
      before do
        custom_tool.update!(
          auth_type: 'api_key',
          auth_config: { 'key' => 'api_key_123', 'location' => 'header', 'name' => 'X-API-Key' },
          endpoint_url: 'https://example.com/data',
          response_template: nil
        )
        stub_request(:get, 'https://example.com/data')
          .with(headers: { 'X-API-Key' => 'api_key_123' })
          .to_return(status: 200, body: '{"authenticated": true}')
      end

      it 'adds API key header' do
        result = tool.perform(tool_context)

        expect(result).to eq('{"authenticated": true}')
        expect(WebMock).to have_requested(:get, 'https://example.com/data')
          .with(headers: { 'X-API-Key' => 'api_key_123' })
      end
    end

    context 'with response template' do
      before do
        custom_tool.update!(
          endpoint_url: 'https://example.com/orders/123',
          response_template: 'Order status: {{ response.status }}, ID: {{ response.order_id }}'
        )
        stub_request(:get, 'https://example.com/orders/123')
          .to_return(status: 200, body: '{"status": "shipped", "order_id": "123"}')
      end

      it 'formats response using template' do
        result = tool.perform(tool_context)

        expect(result).to eq('Order status: shipped, ID: 123')
      end
    end

    # Falha de consulta, por classe. Antes as cinco classes colapsavam em
    # 'An error occurred while executing the request' — uma string em inglês que não distingue
    # "não há dado" de "o sistema caiu" e não fecha a porta pra resposta de memória. O modelo
    # lia isso como ausência e completava de cabeça (auditoria de 20/09, §5).
    #
    # `Resolv.getaddress` é stubado porque a guarda de SSRF resolve DNS de verdade, mesmo com
    # WebMock ligado: sem o stub estes exemplos dependem de rede.
    context 'when handling errors' do
      before do
        custom_tool.update!(endpoint_url: 'https://example.com/data', response_template: nil)
        allow(Resolv).to receive(:getaddress).with('example.com').and_return('93.184.216.34')
      end

      # Toda classe de falha carrega a mesma promessa: isto não é ausência, e não se responde
      # de memória. Se uma delas perder a frase, o modelo volta a preencher o silêncio.
      shared_examples 'falha de consulta' do |trecho|
        it "diz que é falha de consulta e proíbe responder de memória (#{trecho})" do
          resultado = tool.perform(tool_context)

          expect(resultado).to include(trecho)
          # Contra a própria constante, não contra uma cópia do texto: reescrever a frase sem
          # perceber que ela é a promessa do PR passaria despercebido num expect literal.
          expect(resultado).to include(described_class::NAO_INVENTE)
        end
      end

      context 'com timeout' do
        before { stub_request(:get, 'https://example.com/data').to_timeout }

        it_behaves_like 'falha de consulta', 'não respondeu a tempo'
      end

      context 'com o serviço fora do ar (HTTP 500)' do
        before { stub_request(:get, 'https://example.com/data').to_return(status: 500, body: 'Server error') }

        it_behaves_like 'falha de consulta', 'não respondeu ou está fora do ar'
      end

      context 'com falha de conexão' do
        before { stub_request(:get, 'https://example.com/data').to_raise(Errno::ECONNREFUSED) }

        it_behaves_like 'falha de consulta', 'não respondeu ou está fora do ar'
      end

      context 'com credencial recusada (HTTP 401)' do
        before { stub_request(:get, 'https://example.com/data').to_return(status: 401, body: 'nope') }

        it_behaves_like 'falha de consulta', 'recusada pelo sistema consultado'
      end

      context 'com credencial sem permissão (HTTP 403)' do
        before { stub_request(:get, 'https://example.com/data').to_return(status: 403, body: 'nope') }

        it_behaves_like 'falha de consulta', 'recusada pelo sistema consultado'
      end

      # 404 é contrato, não indisponibilidade: a chamada chegou e foi rejeitada. Continua sem
      # autorizar o modelo a concluir que o dado não existe.
      context 'com resposta que não pôde ser lida (HTTP 404)' do
        before { stub_request(:get, 'https://example.com/data').to_return(status: 404, body: 'Not found') }

        it_behaves_like 'falha de consulta', 'resposta não pôde ser lida'
      end

      # Filtro inexistente NÃO serve de gatilho: o `format_response` renderiza com
      # `strict: false` de propósito, porque a resposta vem de API externa que omite campo
      # conforme o caso. O que quebra de verdade é template malformado — tag não fechada.
      context 'com template malformado' do
        before do
          custom_tool.update!(response_template: '{{ response.x')
          stub_request(:get, 'https://example.com/data').to_return(status: 200, body: '{"x": 1}')
        end

        it_behaves_like 'falha de consulta', 'resposta não pôde ser lida'
      end

      context 'com corpo excessivo' do
        before do
          stub_request(:get, 'https://example.com/data')
            .to_return(status: 200, body: 'x' * (1.megabyte + 1))
        end

        it_behaves_like 'falha de consulta', 'grande demais'
      end

      # SSRF: o motivo real fica no log. Pro modelo é indisponibilidade — dizer "IP privado"
      # não o ajuda a atender e expõe topologia dentro da conversa.
      context 'com host que resolve para IP privado' do
        before do
          allow(Resolv).to receive(:getaddress).with('example.com').and_return('10.0.0.5')
        end

        it_behaves_like 'falha de consulta', 'não respondeu ou está fora do ar'

        it 'não revela o motivo do bloqueio ao modelo' do
          expect(tool.perform(tool_context)).not_to include('IP', 'privado', '10.0.0.5')
        end
      end

      # 2xx sem corpo NÃO é ausência confirmada: um 204 pode ser resposta válida de uma ação e
      # inútil para uma consulta, e o HttpTool não sabe qual é qual. Declarar ausência aqui
      # seria inventar ausência — o defeito que este PR fecha.
      context 'com 2xx sem conteúdo' do
        before { stub_request(:get, 'https://example.com/data').to_return(status: 204, body: '') }

        it 'não conclui ausência' do
          resultado = tool.perform(tool_context)

          expect(resultado).to include('sem conteúdo')
          expect(resultado).to include('NÃO confirma que o dado não existe')
        end
      end

      it 'logs error details' do
        stub_request(:get, 'https://example.com/data').to_raise(StandardError.new('Test error'))

        expect(Rails.logger).to receive(:error).with(/HttpTool execution error.*Test error/)

        tool.perform(tool_context)
      end

      it 'mantém o detalhe técnico fora do texto que o modelo lê' do
        stub_request(:get, 'https://example.com/data').to_return(status: 500, body: 'Server error')

        expect(tool.perform(tool_context)).not_to include('500', 'HTTP')
      end
    end

    # O HttpTool não herda de BasePublicTool, então ficava FORA do TraceRecorder: as custom tools
    # de todos os tenants não geravam trace nenhum, e o que não tem trace não chega na nota do
    # turno seguinte nem no eval. Aqui se testa o contrato de ponta a ponta — o status gravado é
    # semântico, não "nenhuma exceção propagou".

    # ── AÇÃO ──────────────────────────────────────────────────────────────────────────────
    # O HttpTool serve consulta E ação, e metade das custom tools armadas da frota é POST contra
    # CRM real (registrar cliente, agendar visita, criar/cancelar proposta). Para elas a pergunta
    # não é "consegui ler o dado?" e sim "a operação aconteceu?". As mensagens de consulta
    # respondiam a pergunta errada de dois jeitos que custam dinheiro do cliente: ReadTimeout
    # virava "não consegui" e o modelo repetia (proposta duplicada); 204 — resposta NORMAL de
    # cancelamento — virava `desconhecido` e o modelo cancelava de novo.
    describe 'ferramenta de AÇÃO (POST)' do
      let(:custom_tool) { create(:captain_custom_tool, :with_post, account: account) }
      let(:conversation) { create(:conversation, account: account) }
      let(:tool_context_com_conversa) do
        Struct.new(:state).new({ account_id: account.id, assistant_id: assistant.id,
                                 conversation: { id: conversation.id, display_id: conversation.display_id } })
      end

      before do
        account.update!(custom_attributes: account.custom_attributes.merge('captain_tool_context' => true))
        custom_tool.update!(endpoint_url: 'https://example.com/acao', response_template: nil)
        allow(Resolv).to receive(:getaddress).with('example.com').and_return('93.184.216.34')
      end

      def executar!
        texto = tool.perform(tool_context_com_conversa, value: 'x')
        [texto, Captain::ToolCall.for_conversation(conversation.id).last]
      end

      # A ÚNICA prova de que a ação não ocorreu é a requisição não ter saído.
      it 'com conexão recusada, afirma que a ação NÃO foi realizada' do
        stub_request(:post, 'https://example.com/acao').to_raise(Errno::ECONNREFUSED)

        texto, trace = executar!

        expect(texto).to eq(described_class::ACAO_NAO_REALIZADA)
        expect(trace.status).to eq('error')
      end

      # OpenTimeout é a conexão que nunca se estabeleceu — nada saiu.
      it 'com timeout de conexão, afirma que a ação NÃO foi realizada' do
        stub_request(:post, 'https://example.com/acao').to_raise(Net::OpenTimeout)

        expect(executar!.first).to eq(described_class::ACAO_NAO_REALIZADA)
      end

      it 'com host que resolve para IP privado, afirma que a ação NÃO foi realizada' do
        allow(Resolv).to receive(:getaddress).with('example.com').and_return('10.0.0.5')

        expect(executar!.first).to eq(described_class::ACAO_NAO_REALIZADA)
      end

      # Enviada e sem confirmação: pode ter acontecido do outro lado.
      shared_examples 'indeterminada' do
        it 'não afirma nem sucesso nem falha, e proíbe repetir' do
          texto, trace = executar!

          expect(texto).to eq(described_class::ACAO_INDETERMINADA)
          expect(texto).to include('NÃO repita')
          expect(texto).not_to include('não conseguiu consultar')
          expect(trace.status).to eq('desconhecido')
        end
      end

      context 'com ReadTimeout' do
        before { stub_request(:post, 'https://example.com/acao').to_raise(Net::ReadTimeout) }

        it_behaves_like 'indeterminada'
      end

      context 'com HTTP 408' do
        before { stub_request(:post, 'https://example.com/acao').to_return(status: 408) }

        it_behaves_like 'indeterminada'
      end

      context 'com HTTP 429' do
        before { stub_request(:post, 'https://example.com/acao').to_return(status: 429) }

        it_behaves_like 'indeterminada'
      end

      # 5xx é indeterminado porque o servidor pode ter gravado antes de falhar ao responder.
      context 'com HTTP 500' do
        before { stub_request(:post, 'https://example.com/acao').to_return(status: 500, body: 'boom') }

        it_behaves_like 'indeterminada'
      end

      # Conexão que morre no meio pode ter morrido DEPOIS de o servidor receber.
      context 'com conexão derrubada no meio' do
        before { stub_request(:post, 'https://example.com/acao').to_raise(Errno::ECONNRESET) }

        it_behaves_like 'indeterminada'
      end

      it 'com 4xx, diz que não foi concluída' do
        stub_request(:post, 'https://example.com/acao').to_return(status: 422, body: 'invalido')

        texto, trace = executar!

        expect(texto).to eq(described_class::ACAO_RECUSADA)
        expect(trace.status).to eq('error')
      end

      it 'com 401, diz que não foi concluída' do
        stub_request(:post, 'https://example.com/acao').to_return(status: 401)

        expect(executar!.first).to eq(described_class::ACAO_RECUSADA)
      end

      it 'com 2xx e corpo, devolve o corpo' do
        stub_request(:post, 'https://example.com/acao').to_return(status: 200, body: '{"id": 77}')

        texto, trace = executar!

        expect(texto).to eq('{"id": 77}')
        expect(trace.status).to eq('ok')
      end

      # O caso do mtm_cancelar_proposta: 204 é a resposta NORMAL, não ausência de confirmação.
      it 'com 204 sem corpo, é sucesso — não desconhecido' do
        stub_request(:post, 'https://example.com/acao').to_return(status: 204, body: '')

        texto, trace = executar!

        expect(texto).to eq(described_class::ACAO_CONFIRMADA)
        expect(trace.status).to eq('ok')
        expect(texto).not_to include('não conclua ausência')
      end

      # 2xx ilegível continua sendo uma ação que ACONTECEU. Dizer "não consegui" convidaria
      # o modelo a repetir uma operação já efetivada.
      it 'com 2xx e template malformado, é sucesso sem detalhe' do
        custom_tool.update!(response_template: '{{ response.x')
        stub_request(:post, 'https://example.com/acao').to_return(status: 200, body: '{"x": 1}')

        texto, trace = executar!

        expect(texto).to eq(described_class::ACAO_FEITA_SEM_LEITURA)
        expect(trace.status).to eq('ok')
      end

      # Nenhuma mensagem de ação pode carregar o NAO_INVENTE: ele manda "diga que não conseguiu
      # consultar", que é exatamente o que não se pode dizer sobre uma ação indeterminada.
      it 'nunca usa o texto de consulta numa ação' do
        stub_request(:post, 'https://example.com/acao').to_raise(Net::ReadTimeout)

        expect(executar!.first).not_to include(described_class::NAO_INVENTE)
      end
    end

    describe 'trace e status semântico' do
      let(:conversation) { create(:conversation, account: account) }
      let(:tool_context_com_conversa) do
        Struct.new(:state).new({ account_id: account.id, assistant_id: assistant.id,
                                 conversation: { id: conversation.id, display_id: conversation.display_id } })
      end

      before do
        account.update!(custom_attributes: account.custom_attributes.merge('captain_tool_context' => true))
        custom_tool.update!(endpoint_url: 'https://example.com/data', response_template: nil)
        allow(Resolv).to receive(:getaddress).with('example.com').and_return('93.184.216.34')
      end

      def executar!
        tool.perform(tool_context_com_conversa)
        Captain::ToolCall.for_conversation(conversation.id).last
      end

      it 'grava trace da custom tool, que antes não existia' do
        stub_request(:get, 'https://example.com/data').to_return(status: 200, body: '{"ok": true}')

        expect(executar!).to be_present
      end

      it 'grava falha como error, não como ok' do
        stub_request(:get, 'https://example.com/data').to_return(status: 500, body: 'x')

        trace = executar!

        expect(trace.status).to eq('error')
        expect(trace.error).to include('HTTP 500')
      end

      it 'grava 2xx sem corpo como desconhecido, nunca como ausência confirmada' do
        stub_request(:get, 'https://example.com/data').to_return(status: 204, body: '')

        trace = executar!

        expect(trace.status).to eq('desconhecido')
        expect(Captain::Tools::Result::NAO_CONFIRMADOS).to include(trace.status)
      end

      it 'grava resposta com corpo como ok e devolve String para a gem' do
        stub_request(:get, 'https://example.com/data').to_return(status: 200, body: '{"ok": true}')

        resultado = tool.perform(tool_context_com_conversa)

        expect(resultado).to be_a(String).and eq('{"ok": true}')
        expect(Captain::ToolCall.for_conversation(conversation.id).last.status).to eq('ok')
      end
    end

    context 'when integrating with Toolable methods' do
      it 'correctly integrates URL rendering, body rendering, auth, and response formatting' do
        custom_tool.update!(
          http_method: 'POST',
          endpoint_url: 'https://example.com/users/{{ user_id }}/orders',
          request_template: '{"product": "{{ product }}", "quantity": {{ quantity }}}',
          auth_type: 'bearer',
          auth_config: { 'token' => 'integration_token' },
          response_template: 'Created order #{{ response.order_number }} for {{ response.product }}'
        )

        stub_request(:post, 'https://example.com/users/42/orders')
          .with(
            body: '{"product": "Widget", "quantity": 5}',
            headers: {
              'Authorization' => 'Bearer integration_token',
              'Content-Type' => 'application/json'
            }
          )
          .to_return(status: 200, body: '{"order_number": "ORD-789", "product": "Widget"}')

        result = tool.perform(tool_context, user_id: '42', product: 'Widget', quantity: 5)

        expect(result).to eq('Created order #ORD-789 for Widget')
      end
    end

    context 'with metadata headers' do
      let(:conversation) { create(:conversation, account: account) }
      let(:contact) { conversation.contact }
      let(:tool_context_with_state) do
        Struct.new(:state).new({
                                 account_id: account.id,
                                 assistant_id: assistant.id,
                                 conversation: {
                                   id: conversation.id,
                                   display_id: conversation.display_id
                                 },
                                 contact_inbox: {
                                   id: conversation.contact_inbox.id,
                                   hmac_verified: conversation.contact_inbox.hmac_verified
                                 },
                                 contact: {
                                   id: contact.id,
                                   email: contact.email,
                                   phone_number: contact.phone_number
                                 }
                               })
      end

      before do
        custom_tool.update!(
          endpoint_url: 'https://example.com/api/data',
          response_template: nil
        )
      end

      it 'includes metadata headers in GET request' do
        stub_request(:get, 'https://example.com/api/data')
          .with(headers: {
                  'X-Chatwoot-Account-Id' => account.id.to_s,
                  'X-Chatwoot-Assistant-Id' => assistant.id.to_s,
                  'X-Chatwoot-Tool-Slug' => custom_tool.slug,
                  'X-Chatwoot-Conversation-Id' => conversation.id.to_s,
                  'X-Chatwoot-Conversation-Display-Id' => conversation.display_id.to_s,
                  'X-Chatwoot-Contact-Inbox-Id' => conversation.contact_inbox.id.to_s,
                  'X-Chatwoot-Contact-Inbox-Verified' => conversation.contact_inbox.hmac_verified.to_s,
                  'X-Chatwoot-Contact-Id' => contact.id.to_s,
                  'X-Chatwoot-Contact-Email' => contact.email
                })
          .to_return(status: 200, body: '{"success": true}')

        tool.perform(tool_context_with_state)

        expect(WebMock).to have_requested(:get, 'https://example.com/api/data')
          .with(headers: {
                  'X-Chatwoot-Account-Id' => account.id.to_s,
                  'X-Chatwoot-Contact-Inbox-Verified' => conversation.contact_inbox.hmac_verified.to_s,
                  'X-Chatwoot-Contact-Email' => contact.email
                })
      end

      it 'includes metadata headers in POST request' do
        custom_tool.update!(http_method: 'POST', request_template: '{"data": "test"}')

        stub_request(:post, 'https://example.com/api/data')
          .with(
            body: '{"data": "test"}',
            headers: {
              'Content-Type' => 'application/json',
              'X-Chatwoot-Account-Id' => account.id.to_s,
              'X-Chatwoot-Tool-Slug' => custom_tool.slug,
              'X-Chatwoot-Contact-Inbox-Verified' => conversation.contact_inbox.hmac_verified.to_s,
              'X-Chatwoot-Contact-Email' => contact.email
            }
          )
          .to_return(status: 200, body: '{"success": true}')

        tool.perform(tool_context_with_state)

        expect(WebMock).to have_requested(:post, 'https://example.com/api/data')
      end

      it 'includes metadata headers along with authentication headers' do
        custom_tool.update!(
          auth_type: 'bearer',
          auth_config: { 'token' => 'test_token' }
        )

        stub_request(:get, 'https://example.com/api/data')
          .with(headers: {
                  'Authorization' => 'Bearer test_token',
                  'X-Chatwoot-Account-Id' => account.id.to_s,
                  'X-Chatwoot-Contact-Inbox-Verified' => conversation.contact_inbox.hmac_verified.to_s,
                  'X-Chatwoot-Contact-Id' => contact.id.to_s
                })
          .to_return(status: 200, body: '{"success": true}')

        tool.perform(tool_context_with_state)

        expect(WebMock).to have_requested(:get, 'https://example.com/api/data')
          .with(headers: {
                  'Authorization' => 'Bearer test_token',
                  'X-Chatwoot-Contact-Id' => contact.id.to_s
                })
      end

      it 'handles missing contact in tool context' do
        tool_context_no_contact = Struct.new(:state).new({
                                                           account_id: account.id,
                                                           assistant_id: assistant.id,
                                                           conversation: {
                                                             id: conversation.id,
                                                             display_id: conversation.display_id
                                                           },
                                                           contact_inbox: {
                                                             id: conversation.contact_inbox.id,
                                                             hmac_verified: conversation.contact_inbox.hmac_verified
                                                           }
                                                         })

        stub_request(:get, 'https://example.com/api/data')
          .with(headers: {
                  'X-Chatwoot-Account-Id' => account.id.to_s,
                  'X-Chatwoot-Conversation-Id' => conversation.id.to_s,
                  'X-Chatwoot-Contact-Inbox-Verified' => conversation.contact_inbox.hmac_verified.to_s
                })
          .to_return(status: 200, body: '{"success": true}')

        tool.perform(tool_context_no_contact)

        expect(WebMock).to have_requested(:get, 'https://example.com/api/data')
      end

      it 'defaults contact inbox verified header to false when contact inbox is missing' do
        tool_context_without_contact_inbox = Struct.new(:state).new({
                                                                      account_id: account.id,
                                                                      assistant_id: assistant.id,
                                                                      conversation: {
                                                                        id: conversation.id,
                                                                        display_id: conversation.display_id
                                                                      },
                                                                      contact: {
                                                                        id: contact.id,
                                                                        email: contact.email
                                                                      }
                                                                    })

        stub_request(:get, 'https://example.com/api/data')
          .with(headers: {
                  'X-Chatwoot-Contact-Inbox-Verified' => 'false'
                })
          .to_return(status: 200, body: '{"success": true}')

        tool.perform(tool_context_without_contact_inbox)

        expect(WebMock).to have_requested(:get, 'https://example.com/api/data')
          .with(headers: { 'X-Chatwoot-Contact-Inbox-Verified' => 'false' })
      end

      it 'includes contact phone when present' do
        contact.update!(phone_number: '+1234567890')
        tool_context_with_state.state[:contact][:phone_number] = '+1234567890'

        stub_request(:get, 'https://example.com/api/data')
          .with(headers: {
                  'X-Chatwoot-Contact-Phone' => '+1234567890'
                })
          .to_return(status: 200, body: '{"success": true}')

        tool.perform(tool_context_with_state)

        expect(WebMock).to have_requested(:get, 'https://example.com/api/data')
          .with(headers: { 'X-Chatwoot-Contact-Phone' => '+1234567890' })
      end

      it 'includes unverified contact inbox status explicitly as false' do
        conversation.contact_inbox.update!(hmac_verified: false)
        tool_context_with_state.state[:contact_inbox][:hmac_verified] = false

        stub_request(:get, 'https://example.com/api/data')
          .with(headers: {
                  'X-Chatwoot-Contact-Inbox-Verified' => 'false'
                })
          .to_return(status: 200, body: '{"success": true}')

        tool.perform(tool_context_with_state)

        expect(WebMock).to have_requested(:get, 'https://example.com/api/data')
          .with(headers: { 'X-Chatwoot-Contact-Inbox-Verified' => 'false' })
      end
    end
  end
end
