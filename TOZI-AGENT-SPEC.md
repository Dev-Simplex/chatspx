# Tozi Agent — Especificação para Implementação dentro do ChatWoot (SPX)

**Versão:** 1.0
**Data:** 2026-04-04
**Autor:** Paulo Seze / SimplexIA
**Para:** Desenvolvedor Ruby/Rails

---

## 1. Contexto

### O que é

Sistema de atendimento inteligente da Tozi Imobiliária (Sinop/MT) que funciona dentro do WhatsApp via ChatWoot. Composto por dois agentes de IA:

- **Clara** — pré-atendimento que conversa com clientes, qualifica leads e encaminha para o time
- **Copiloto** — assistente interno que ajuda atendentes nos bastidores

### O que existe hoje

Workflows no n8n (53 nós) que recebem webhooks do ChatWoot, processam com OpenAI e respondem via API. Funciona, mas é frágil, sem testes, difícil de debugar.

### O que queremos

Implementar a mesma lógica **dentro do ChatWoot (SPX)**, usando Ruby/Rails + Sidekiq. Elimina serviço externo, webhooks, e ganha a infraestrutura que o ChatWoot já oferece.

### Por que dentro do ChatWoot

| Aspecto | Serviço externo | Dentro do ChatWoot |
|---------|----------------|-------------------|
| Infraestrutura | Servidor separado, Docker, SSL | Já existe |
| Fila de jobs | Implementar do zero | Sidekiq (retry, dashboard, dead letter) |
| Redis | Instalar e configurar | Já roda |
| Banco de dados | Redis volátil | PostgreSQL persistente |
| Eventos | Webhook HTTP externo | Hook interno (after_create) |
| Enviar mensagem | HTTP POST com auth | `conversation.messages.create!()` |
| Histórico | GET API + parse | `conversation.messages` |
| Deploy | Separado | Junto com ChatWoot |
| Monitoramento | Configurar à parte | Sidekiq Web UI |

---

## 2. Arquitetura

### Fluxo principal

```
Mensagem chega no ChatWoot
        │
        ▼
Hook no model Message (after_create)
        │
        ▼
Tozi::Router.route(message)
        │
        ├─ :ignore              → nada
        │
        ├─ :marcar_atendimento  → conversation.update!(custom_attributes)
        │                         conversation.label_list.add("atendimento")
        │
        ├─ :limpar_atendimento  → conversation.update!(custom_attributes: {})
        │                         limpar labels
        │
        ├─ :copiloto            → Tozi::CopilotoJob.perform_later(message.id)
        │
        └─ :agente_clara        → Tozi::ClaraDebounceJob.set(wait: 15.seconds)
                                      .perform_later(conversation.id)
```

### Fluxo da Clara (detalhado)

```
ClaraDebounceJob dispara (após 15s de silêncio)
        │
        ▼
Verifica se é a última mensagem pendente
        │
        ├─ Não → descarta (outra mensagem chegou depois)
        │
        └─ Sim
              │
              ├─ Tem mídia? → Tozi::MediaPipeline.process(message)
              │                  áudio → Whisper → nota privada
              │                  imagem → Vision → nota privada
              │
              ▼
        Tozi::ClaraAgent.new(conversation).process
              │
              ▼
        Loop de agente (pode chamar tools)
              │
              ▼
        Tozi::Humanizer.split(resposta)
              │
              ▼
        Envia 1-2 mensagens (com 500ms de delay entre elas)
```

### Estrutura de arquivos

```
app/
├── services/
│   └── tozi/
│       ├── router.rb                # normalização + roteamento
│       ├── config.rb                # constantes, horário comercial
│       ├── clara_agent.rb           # loop de agente Clara
│       ├── copiloto_agent.rb        # loop de agente Copiloto
│       ├── atribuidor.rb            # subagente de enriquecimento
│       ├── humanizer.rb             # quebra resposta em 1-2 msgs
│       ├── media_pipeline.rb        # Whisper + Vision
│       ├── anthropic_client.rb      # client HTTP para Anthropic API
│       └── tools/
│           ├── base_tool.rb         # interface de tool
│           ├── buscar_imoveis.rb    # Vista API
│           ├── buscar_localizacao.rb # Google Maps geocoding
│           ├── faq_tozi.rb          # base de conhecimento
│           └── atribuir_atendimento.rb # atribui + envia resumo
│
├── jobs/
│   └── tozi/
│       ├── process_message_job.rb   # job principal (entry point)
│       ├── clara_debounce_job.rb    # debounce 15s + processa Clara
│       ├── copiloto_job.rb          # processa Copiloto
│       └── media_job.rb             # processa mídia (Whisper/Vision)
│
├── models/concerns/
│   └── tozi_hookable.rb             # hook no model Message
│
└── views/ (não se aplica — sem UI)
```

### Variáveis de ambiente necessárias

```env
# Anthropic (Claude)
TOZI_ANTHROPIC_API_KEY=sk-ant-...

# OpenAI (Whisper + Vision)
TOZI_OPENAI_API_KEY=sk-...

# Vista CRM (imóveis)
TOZI_VISTA_BASE_URL=https://toz19328-rest.vistahost.com.br
TOZI_VISTA_API_KEY=...

# Google Maps (geocoding)
TOZI_GOOGLE_MAPS_KEY=...

# Configuração
TOZI_ACCOUNT_ID=6
TOZI_INBOX_ID=91
TOZI_ENABLED=true
```

Prefixo `TOZI_` em tudo para não colidir com variáveis do ChatWoot.

---

## 3. Componentes detalhados

### 3.1 Hook de entrada

```ruby
# app/models/concerns/tozi_hookable.rb
module ToziHookable
  extend ActiveSupport::Concern

  included do
    after_create :tozi_dispatch, if: :tozi_eligible?
  end

  private

  def tozi_eligible?
    return false unless ENV['TOZI_ENABLED'] == 'true'
    inbox_id == ENV['TOZI_INBOX_ID'].to_i &&
      account_id == ENV['TOZI_ACCOUNT_ID'].to_i
  end

  def tozi_dispatch
    Tozi::ProcessMessageJob.perform_later(id)
  end
end
```

Incluir no model `Message`:

```ruby
# app/models/message.rb
class Message < ApplicationRecord
  include ToziHookable
  # ... resto do model
end
```

### 3.2 Router (normalização + roteamento)

```ruby
# app/services/tozi/router.rb
module Tozi
  class Router
    ROTAS = %i[ignore agente_clara copiloto marcar_atendimento limpar_atendimento].freeze

    def self.route(message)
      new(message).determine
    end

    def initialize(message)
      @message = message
      @conversation = message.conversation
      @sender = message.sender
    end

    def determine
      # Status changed (conversa resolvida)
      return :limpar_atendimento if resolved_event?

      # Activity messages (sistema)
      return :ignore if @message.activity?

      # Agent bot
      return :ignore if @sender.is_a?(AgentBot)

      # Grupos WhatsApp
      return :ignore if grupo_whatsapp?

      # Cliente (Contact)
      if @sender.is_a?(Contact)
        return :ignore if em_atendimento?
        return :ignore if @message.content.blank? && @message.attachments.empty?
        return :agente_clara
      end

      # Atendente (User)
      if @sender.is_a?(User)
        if @message.private?
          return :copiloto if @message.content&.downcase&.include?('#tozi')
          return :ignore
        end
        return :marcar_atendimento
      end

      :ignore
    end

    private

    # Detecta em_atendimento checando 3 fontes (corrige bug do n8n)
    def em_atendimento?
      # 1. Labels da conversa (mais confiável)
      return true if @conversation.label_list.include?('atendimento')
      # 2. Custom attributes da conversa
      return true if @conversation.custom_attributes&.dig('atendimento') == true
      # 3. Custom attributes do contato
      return true if @sender.respond_to?(:custom_attributes) &&
                      @sender.custom_attributes&.dig('atendimento') == true
      false
    end

    def grupo_whatsapp?
      source_id = @conversation.contact_inbox&.source_id.to_s
      source_id.include?('@g.us')
    end

    def resolved_event?
      # Isso é tratado pelo hook de status change, não pelo message hook
      # Incluído aqui para completude — ver seção 3.9
      false
    end
  end
end
```

### 3.3 Job principal

```ruby
# app/jobs/tozi/process_message_job.rb
module Tozi
  class ProcessMessageJob < ApplicationJob
    queue_as :tozi

    # Idempotência: não reprocessar mesma mensagem
    before_perform do |job|
      msg_id = job.arguments.first
      cache_key = "tozi:processed:#{msg_id}"
      if Rails.cache.exist?(cache_key)
        Rails.logger.info("[Tozi] Mensagem #{msg_id} já processada, ignorando")
        throw :abort
      end
      Rails.cache.write(cache_key, true, expires_in: 5.minutes)
    end

    def perform(message_id)
      message = Message.find(message_id)
      rota = Tozi::Router.route(message)

      Rails.logger.info("[Tozi] conversa=#{message.conversation_id} rota=#{rota} sender=#{message.sender_type}")

      case rota
      when :ignore
        # nada
      when :agente_clara
        Tozi::ClaraDebounceJob.set(wait: 15.seconds).perform_later(message.conversation_id)
      when :copiloto
        Tozi::CopilotoJob.perform_later(message_id)
      when :marcar_atendimento
        marcar(message.conversation)
      when :limpar_atendimento
        limpar(message.conversation)
      end
    end

    private

    def marcar(conversation)
      conversation.update!(custom_attributes: conversation.custom_attributes.merge('atendimento' => true))
      conversation.label_list.add('atendimento')
      conversation.save!
    end

    def limpar(conversation)
      conversation.update!(custom_attributes: conversation.custom_attributes.except('atendimento', 'resumo'))
      conversation.label_list.remove('atendimento')
      conversation.save!
    end
  end
end
```

### 3.4 Debounce da Clara

```ruby
# app/jobs/tozi/clara_debounce_job.rb
module Tozi
  class ClaraDebounceJob < ApplicationJob
    queue_as :tozi

    def perform(conversation_id)
      conversation = Conversation.find(conversation_id)

      # Verificar se esta é a última mensagem pendente
      # Se o cliente mandou outra mensagem depois, outro job foi agendado
      ultima_incoming = conversation.messages
        .where(message_type: :incoming)
        .order(created_at: :desc)
        .first

      return unless ultima_incoming

      # Se a última incoming tem menos de 14s, outro debounce job vai tratá-la
      if ultima_incoming.created_at > 14.seconds.ago
        Rails.logger.info("[Tozi] conversa=#{conversation_id} debounce: mensagem recente, aguardando")
        return
      end

      # Coletar todas as mensagens incoming não processadas desde a última resposta da Clara
      ultima_resposta_clara = conversation.messages
        .where(message_type: :outgoing, sender_type: nil) # mensagens do sistema/bot
        .order(created_at: :desc)
        .first

      mensagens = conversation.messages
        .where(message_type: :incoming)
        .where('created_at > ?', ultima_resposta_clara&.created_at || 100.years.ago)
        .order(:created_at)

      return if mensagens.empty?

      # Processar mídia se houver
      texto_final = mensagens.map do |msg|
        if msg.attachments.any?
          Tozi::MediaPipeline.process(msg)
        else
          msg.content
        end
      end.compact.join("\n")

      return if texto_final.blank?

      # Processar com Clara
      resposta = Tozi::ClaraAgent.new(conversation).process(texto_final)

      # Humanizar e enviar
      mensagens_formatadas = Tozi::Humanizer.split(resposta)
      mensagens_formatadas.each_with_index do |texto, i|
        sleep(0.5) if i > 0 # delay entre mensagens
        conversation.messages.create!(
          message_type: :outgoing,
          content: texto,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )
      end
    end
  end
end
```

### 3.5 Client Anthropic (HTTP puro)

```ruby
# app/services/tozi/anthropic_client.rb
module Tozi
  class AnthropicClient
    API_URL = "https://api.anthropic.com/v1/messages"
    MODEL = "claude-sonnet-4-6"

    def initialize
      @api_key = ENV.fetch('TOZI_ANTHROPIC_API_KEY')
    end

    # Executa o loop de agente: system + messages → resposta
    # Suporta tool_use com handler
    def agent_loop(system:, messages:, tools: nil, tool_handler: nil, max_tokens: 1024)
      loop do
        body = {
          model: MODEL,
          system: system,
          messages: messages,
          max_tokens: max_tokens
        }
        body[:tools] = tools if tools&.any?

        response = request(body)
        content = response['content']

        messages << { role: 'assistant', content: content }

        if response['stop_reason'] == 'end_turn'
          texto = content.find { |b| b['type'] == 'text' }&.dig('text') || ''
          return texto
        end

        if response['stop_reason'] == 'tool_use' && tool_handler
          results = content
            .select { |b| b['type'] == 'tool_use' }
            .map do |tool_call|
              result = tool_handler.call(tool_call['name'], tool_call['input'])
              {
                type: 'tool_result',
                tool_use_id: tool_call['id'],
                content: result.to_s
              }
            end

          messages << { role: 'user', content: results }
          next
        end

        # stop_reason inesperado
        return 'Não consegui processar no momento.'
      end
    end

    private

    def request(body)
      uri = URI(API_URL)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 60

      req = Net::HTTP::Post.new(uri.path)
      req['x-api-key'] = @api_key
      req['anthropic-version'] = '2023-06-01'
      req['content-type'] = 'application/json'
      req.body = body.to_json

      res = http.request(req)

      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.error("[Tozi] Anthropic API error: #{res.code} #{res.body}")
        raise "Anthropic API error: #{res.code}"
      end

      JSON.parse(res.body)
    end
  end
end
```

### 3.6 Clara Agent

```ruby
# app/services/tozi/clara_agent.rb
module Tozi
  class ClaraAgent
    SYSTEM_PROMPT = <<~PROMPT
      Você é a Clara, pré-atendimento da Tozi Imóveis (Sinop/MT) no WhatsApp.

      ## Seu papel

      Recepcionar o cliente, entender o que ele precisa e preparar o terreno para o time que vai atendê-lo. Você é a porta de entrada — acolhe, conversa, coleta contexto e direciona.

      ## Como se comportar

      Seja humana. Responda como uma pessoa real responderia: curto, direto, simpática. Não soe como menu de opções ou robô corporativo.

      - Respostas de 1-3 frases
      - Uma pergunta por vez
      - Sem formalidade forçada nem frases feitas
      - Emoji só se fizer sentido natural (máximo 1)
      - Adapte seu tom ao tom do cliente
      - Responda o que o cliente perguntar antes de fazer sua pergunta
      - Nunca mande duas perguntas na mesma mensagem

      ## Seja concisa

      Se o cliente já disse algo, siga em frente. Não repita de volta o que ele acabou de falar.
      Quando o cliente já deu todas as informações, sua resposta pode ser só uma confirmação curta e o aviso de que passou pro time.

      ## Só fale do que você faz

      Você passa pro time. O time é quem busca imóveis, mostra opções, agenda visitas. Não prometa nada além de passar pro time.

      ## Dois modos de operação

      ### Dentro do horário comercial
      O time está disponível. Seu objetivo é entender o motivo do contato com agilidade e atribuir.
      - Não prolongue a conversa além do necessário
      - Assim que entender o que o cliente precisa, confirme o nome e atribua

      ### Fora do horário comercial
      Ninguém vai atender agora. Você tem tempo. Use isso a favor do time.
      - Converse com mais calma, sem pressa de atribuir
      - Para comercial: aproveite para qualificar mais o lead (uma pergunta por vez)
      - Quando sentir que coletou o suficiente, confirme o nome e atribua

      ## Confirmação de nome
      O nome disponível no contexto vem do WhatsApp — pode ser apelido. Confirme o nome real antes de encaminhar.

      ## O que você faz
      1. Acolhe — responde saudações naturalmente
      2. Esclarece — responde dúvidas simples sobre a empresa consultando a FAQ
      3. Qualifica — coleta informações relevantes sobre a demanda
      4. Confirma — verifica o nome real do cliente
      5. Encaminha — atribui o atendimento para o time

      ## O que você NÃO faz
      - Não busca imóveis
      - Não agenda visitas
      - Não negocia valores
      - Não resolve suporte
      - Não promete prazos
      - Não pede documentos ou dados sensíveis

      ## Coleta por tipo de demanda

      ### Comercial (locação, venda, captação)
      - O que procura (casa, apartamento, kitnet, terreno)
      - Finalidade (alugar, comprar, anunciar)
      - Região ou bairro de preferência
      - Faixa de valor
      - Quantidade de quartos
      - Se tem pets
      - Prazo

      ### Suporte (boleto, contrato, manutenção)
      - Qual o problema
      - Endereço do imóvel (se mencionou)
      Colete rápido e atribua.

      ## Informações da empresa
      - Horário: Seg-Sex 7:30-11:30 e 13:30-17:30 | Sáb 9:00-11:30
      - Endereço: Av. das Figueiras, 3385 - Setor Comercial, Sinop/MT
      - Telefone: (66) 3531-5500
      - Site: www.tozisinop.com.br

      ## Contexto

      Nome do cliente: %{nome_cliente}
      Atribuído à: %{nome_atendente}
      Resumo prévio: %{resumo_previo}
      Horário: %{horario}
      Data/hora: %{data_hora}
    PROMPT

    TOOLS = [
      {
        name: 'faq_tozi',
        description: 'Consulta a base de conhecimento da Tozi. Use quando o cliente perguntar sobre a empresa.',
        input_schema: {
          type: 'object',
          properties: { pergunta: { type: 'string', description: 'A pergunta a buscar na FAQ' } },
          required: ['pergunta']
        }
      },
      {
        name: 'atribuir_atendimento',
        description: 'Atribui a conversa para o time. Diga em linguagem natural o que o cliente quer. Inclua o nome confirmado. Exemplos: "João Silva quer alugar casa em Sinop, até 2000 reais, 3 quartos", "Maria tem problema no boleto".',
        input_schema: {
          type: 'object',
          properties: { contexto: { type: 'string', description: 'Resumo completo do que o cliente precisa, incluindo nome confirmado' } },
          required: ['contexto']
        }
      }
    ].freeze

    def initialize(conversation)
      @conversation = conversation
      @client = Tozi::AnthropicClient.new
    end

    def process(texto_usuario)
      system = build_system
      historico = build_history
      historico << { role: 'user', content: texto_usuario }

      tool_handler = method(:handle_tool)

      @client.agent_loop(
        system: system,
        messages: historico,
        tools: TOOLS,
        tool_handler: tool_handler
      )
    end

    private

    def build_system
      contact = @conversation.contact
      assignee = @conversation.assignee
      now = Time.current.in_time_zone('America/Cuiaba')

      SYSTEM_PROMPT % {
        nome_cliente: contact&.name || 'Não identificado',
        nome_atendente: assignee&.name || 'Ninguém',
        resumo_previo: @conversation.custom_attributes&.dig('resumo') || 'Sem resumo',
        horario: Tozi::Config.dentro_do_horario?(now) ? 'dentro do expediente' : 'fora do expediente',
        data_hora: now.strftime('%d/%m/%Y %H:%M')
      }
    end

    def build_history
      @conversation.messages
        .where(private: false)
        .where.not(content: [nil, ''])
        .order(:created_at)
        .last(40)
        .map do |m|
          {
            role: m.incoming? ? 'user' : 'assistant',
            content: m.content
          }
        end
    end

    def handle_tool(name, input)
      case name
      when 'faq_tozi'
        Tozi::Tools::FaqTozi.call(input['pergunta'])
      when 'atribuir_atendimento'
        Tozi::Tools::AtribuirAtendimento.call(@conversation, input['contexto'])
      else
        "Tool '#{name}' não reconhecida"
      end
    end
  end
end
```

### 3.7 Copiloto Agent

```ruby
# app/services/tozi/copiloto_agent.rb
module Tozi
  class CopilotoAgent
    SYSTEM_PROMPT = <<~PROMPT
      Você é o Copiloto da Tozi Imóveis (Sinop/MT). Você ajuda o time nos bastidores.

      Alguém do time te chamou usando #tozi numa mensagem privada. Você responde também no privado. O cliente nunca te vê.

      ## Seu papel
      Ser o cérebro de apoio do time. Buscar informações, consultar bases, encontrar imóveis, responder dúvidas sobre processos.

      ## Comportamento
      Seja direto e útil. O atendente está no meio de um atendimento e precisa de informação rápida.
      Não faça perguntas ao atendente — ele não vai responder, está ocupado atendendo.
      Se não encontrar o que foi pedido, diga claramente.

      ## Contexto
      Nome do cliente: %{nome_cliente}
      Nome do atendente: %{nome_atendente}
    PROMPT

    TOOLS = [
      {
        name: 'buscar_imoveis',
        description: 'Busca imóveis no Vista. Input: JSON com filter, advFilter, order, paginacao.',
        input_schema: {
          type: 'object',
          properties: {
            filter: { type: 'object' },
            advFilter: { type: 'object' },
            order: { type: 'object' },
            paginacao: { type: 'object' }
          },
          required: %w[filter advFilter order paginacao]
        }
      },
      {
        name: 'buscar_localizacao',
        description: 'Converte referência geográfica em coordenadas. Sempre complete com "sinop mt".',
        input_schema: {
          type: 'object',
          properties: { local: { type: 'string' } },
          required: ['local']
        }
      },
      {
        name: 'faq_tozi',
        description: 'Consulta base de conhecimento da Tozi.',
        input_schema: {
          type: 'object',
          properties: { pergunta: { type: 'string' } },
          required: ['pergunta']
        }
      }
    ].freeze

    def initialize(conversation, pergunta)
      @conversation = conversation
      @pergunta = pergunta
      @client = Tozi::AnthropicClient.new
    end

    def process
      system = build_system
      historico_formatado = formatar_historico
      mensagem = "#{historico_formatado}\n\n---\nPergunta: #{@pergunta}"

      @client.agent_loop(
        system: system,
        messages: [{ role: 'user', content: mensagem }],
        tools: TOOLS,
        tool_handler: method(:handle_tool)
      )
    end

    private

    def build_system
      SYSTEM_PROMPT % {
        nome_cliente: @conversation.contact&.name || '?',
        nome_atendente: @conversation.assignee&.name || '?'
      }
    end

    def formatar_historico
      @conversation.messages
        .order(:created_at)
        .last(50)
        .map do |m|
          autor = if m.incoming?
                    "[Cliente]"
                  elsif m.private?
                    "[Interno] (privado)"
                  else
                    "[Atendente]"
                  end
          "#{autor}: #{m.content}"
        end
        .join("\n")
    end

    def handle_tool(name, input)
      case name
      when 'buscar_imoveis'
        Tozi::Tools::BuscarImoveis.call(input)
      when 'buscar_localizacao'
        Tozi::Tools::BuscarLocalizacao.call(input['local'])
      when 'faq_tozi'
        Tozi::Tools::FaqTozi.call(input['pergunta'])
      else
        "Tool '#{name}' não reconhecida"
      end
    end
  end
end
```

### 3.8 Copiloto Job

```ruby
# app/jobs/tozi/copiloto_job.rb
module Tozi
  class CopilotoJob < ApplicationJob
    queue_as :tozi

    def perform(message_id)
      message = Message.find(message_id)
      conversation = message.conversation

      # Extrair pergunta (remover #tozi do conteúdo)
      pergunta = message.content.gsub(/#tozi/i, '').strip

      resposta = Tozi::CopilotoAgent.new(conversation, pergunta).process

      # Enviar como mensagem privada
      conversation.messages.create!(
        message_type: :outgoing,
        content: resposta,
        private: true,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id
      )
    end
  end
end
```

### 3.9 Hook de status change (conversa resolvida)

```ruby
# Adicionar ao model Conversation ou criar concern separado
# app/models/concerns/tozi_conversation_hookable.rb
module ToziConversationHookable
  extend ActiveSupport::Concern

  included do
    after_update :tozi_on_resolved, if: :tozi_just_resolved?
  end

  private

  def tozi_just_resolved?
    ENV['TOZI_ENABLED'] == 'true' &&
      account_id == ENV['TOZI_ACCOUNT_ID'].to_i &&
      saved_change_to_status? &&
      resolved?
  end

  def tozi_on_resolved
    update!(custom_attributes: custom_attributes.except('atendimento', 'resumo'))
    label_list.remove('atendimento')
    save!
    Rails.logger.info("[Tozi] conversa=#{id} resolvida — atendimento limpo")
  end
end
```

### 3.10 Config

```ruby
# app/services/tozi/config.rb
module Tozi
  class Config
    CAMILA_AGENT_ID = 66

    HORARIO_COMERCIAL = {
      1 => [{ inicio: '07:30', fim: '11:30' }, { inicio: '13:30', fim: '17:30' }], # segunda
      2 => [{ inicio: '07:30', fim: '11:30' }, { inicio: '13:30', fim: '17:30' }], # terça
      3 => [{ inicio: '07:30', fim: '11:30' }, { inicio: '13:30', fim: '17:30' }], # quarta
      4 => [{ inicio: '07:30', fim: '11:30' }, { inicio: '13:30', fim: '17:30' }], # quinta
      5 => [{ inicio: '07:30', fim: '11:30' }, { inicio: '13:30', fim: '17:30' }], # sexta
      6 => [{ inicio: '09:00', fim: '11:30' }],                                     # sábado
      0 => []                                                                         # domingo
    }.freeze

    def self.dentro_do_horario?(now = nil)
      now ||= Time.current.in_time_zone('America/Cuiaba')
      faixas = HORARIO_COMERCIAL[now.wday] || []
      hora_atual = now.strftime('%H:%M')

      faixas.any? { |f| hora_atual >= f[:inicio] && hora_atual <= f[:fim] }
    end
  end
end
```

### 3.11 Humanizer

```ruby
# app/services/tozi/humanizer.rb
module Tozi
  class Humanizer
    SYSTEM = <<~PROMPT
      Você recebe a resposta de um agente e formata para envio no WhatsApp.
      Quebre textos longos em mensagens separadas (máximo 2 mensagens).
      Cada mensagem deve ter no máximo 3 frases.
      Remova formalidades excessivas.
      Mantenha o tom da resposta original.
      Não adicione informação que não estava na resposta.
      Emoji só se já tinha na resposta original (máximo 1).

      Responda em JSON: {"messages": ["mensagem 1", "mensagem 2"]}
      Use array com 1 ou 2 strings. Máximo 2 mensagens.
    PROMPT

    def self.split(texto)
      return [texto] if texto.length < 150

      client = Tozi::AnthropicClient.new
      resposta = client.agent_loop(
        system: SYSTEM,
        messages: [{ role: 'user', content: texto }],
        max_tokens: 512
      )

      parsed = JSON.parse(resposta) rescue nil
      if parsed && parsed['messages'].is_a?(Array)
        parsed['messages'].first(2)
      else
        [texto]
      end
    end
  end
end
```

### 3.12 Tools

```ruby
# app/services/tozi/tools/buscar_imoveis.rb
module Tozi
  module Tools
    class BuscarImoveis
      FIELDS = %w[Codigo Categoria Status Dormitorios Cidade Endereco Bairro
                  ValorLocacao ValorVenda Latitude Longitude TituloSite].freeze

      def self.call(query)
        pesquisa = {
          fields: FIELDS,
          filter: query['filter'] || {},
          advFilter: query['advFilter'] || {},
          order: query['order'] || { 'Codigo' => 'desc' },
          paginacao: query['paginacao'] || { 'pagina' => 1, 'quantidade' => 5 }
        }

        uri = URI("#{ENV['TOZI_VISTA_BASE_URL']}/imoveis/listar")
        uri.query = URI.encode_www_form(
          pesquisa: pesquisa.to_json,
          showtotal: 1,
          key: ENV['TOZI_VISTA_API_KEY']
        )

        response = Net::HTTP.get_response(uri)
        data = JSON.parse(response.body)

        # Formatar resultado para o agente
        imoveis = data.except('paginas', 'pagina', 'quantidade', 'total')
        imoveis.map do |_codigo, imovel|
          next unless imovel.is_a?(Hash)
          {
            codigo: imovel['Codigo'],
            tipo: imovel['Categoria'],
            bairro: imovel['Bairro'],
            endereco: imovel['Endereco'],
            quartos: imovel['Dormitorios'],
            valor_locacao: imovel['ValorLocacao'],
            valor_venda: imovel['ValorVenda'],
            url: "https://www.tozi.com.br/imovel/#{imovel['Codigo']}"
          }
        end.compact.to_json
      rescue => e
        Rails.logger.error("[Tozi] Erro buscar_imoveis: #{e.message}")
        "Erro ao buscar imóveis: #{e.message}"
      end
    end
  end
end
```

```ruby
# app/services/tozi/tools/buscar_localizacao.rb
module Tozi
  module Tools
    class BuscarLocalizacao
      RADIUS_KM = 3

      def self.call(local)
        local_completo = local.downcase.include?('sinop') ? local : "#{local} sinop mt"

        uri = URI('https://maps.googleapis.com/maps/api/geocode/json')
        uri.query = URI.encode_www_form(address: local_completo, key: ENV['TOZI_GOOGLE_MAPS_KEY'])

        response = Net::HTTP.get_response(uri)
        data = JSON.parse(response.body)

        result = data.dig('results', 0, 'geometry', 'location')
        return "Local não encontrado" unless result

        lat = result['lat']
        lng = result['lng']

        delta_lat = (RADIUS_KM * 1000.0) / 111_320.0
        delta_lng = delta_lat / Math.cos(lat * Math::PI / 180.0)

        {
          'Latitude' => [(lat - delta_lat).to_s, (lat + delta_lat).to_s],
          'Longitude' => [(lng - delta_lng).to_s, (lng + delta_lng).to_s]
        }.to_json
      rescue => e
        Rails.logger.error("[Tozi] Erro buscar_localizacao: #{e.message}")
        "Erro ao buscar localização: #{e.message}"
      end
    end
  end
end
```

```ruby
# app/services/tozi/tools/atribuir_atendimento.rb
module Tozi
  module Tools
    class AtribuirAtendimento
      def self.call(conversation, contexto)
        # Subagente atribuidor: analisa contexto e enriquece
        atribuidor = Tozi::Atribuidor.new(conversation, contexto)
        resultado = atribuidor.process

        # Enviar resumo como nota privada
        conversation.messages.create!(
          message_type: :outgoing,
          content: resultado[:resumo],
          private: true,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        )

        # Enviar sugestão como nota privada (se houver)
        if resultado[:sugestao].present?
          conversation.messages.create!(
            message_type: :outgoing,
            content: resultado[:sugestao],
            private: true,
            account_id: conversation.account_id,
            inbox_id: conversation.inbox_id
          )
        end

        # Atribuir para Camila
        conversation.update!(assignee_id: Tozi::Config::CAMILA_AGENT_ID)
        conversation.update!(
          custom_attributes: conversation.custom_attributes.merge(
            'atendimento' => true,
            'resumo' => resultado[:resumo]
          )
        )
        conversation.label_list.add('atendimento')
        conversation.save!

        "Atribuído com sucesso."
      end
    end
  end
end
```

```ruby
# app/services/tozi/tools/faq_tozi.rb
module Tozi
  module Tools
    class FaqTozi
      # Base de conhecimento da Tozi
      # Em produção, pode ser substituído por vector store ou busca no PostgreSQL
      FAQ = {
        'horario' => 'Segunda a sexta: 7:30-11:30 e 13:30-17:30. Sábado: 9:00-11:30. Domingo: fechado.',
        'endereco' => 'Av. das Figueiras, 3385 - Setor Comercial, Sinop/MT',
        'telefone' => '(66) 3531-5500',
        'site' => 'www.tozisinop.com.br',
        'documentos_locacao' => 'Para locação: RG, CPF, comprovante de renda (3x o valor do aluguel), comprovante de residência. Fiador: mesmos documentos + matrícula do imóvel.',
        'pets' => 'Depende do proprietário do imóvel. O time comercial pode verificar quais imóveis aceitam pets.',
        'garantias' => 'A Tozi trabalha com fiador, seguro fiança e caução (3 meses de aluguel).',
        'taxa_administracao' => 'A taxa de administração é de 10% sobre o valor do aluguel.',
        'vistoria' => 'A vistoria é realizada na entrada e na saída do imóvel, com relatório fotográfico.',
        'manutencao' => 'Problemas de manutenção devem ser reportados ao time. Reparos estruturais são responsabilidade do proprietário, reparos de uso são do inquilino.',
        'desocupacao' => 'Para desocupar, o inquilino deve comunicar com 30 dias de antecedência. A multa por quebra de contrato é proporcional ao período restante.'
      }.freeze

      def self.call(pergunta)
        # Busca simples por palavras-chave
        # TODO: substituir por vector store (pgvector) para busca semântica
        pergunta_lower = pergunta.downcase
        resultados = FAQ.select { |key, _| pergunta_lower.include?(key) || key_matches?(pergunta_lower, key) }

        if resultados.any?
          resultados.values.join("\n\n")
        else
          # Fallback: retorna tudo e deixa o LLM filtrar
          FAQ.map { |k, v| "#{k}: #{v}" }.join("\n\n")
        end
      end

      def self.key_matches?(pergunta, key)
        keywords = {
          'horario' => %w[horário hora abre fecha funciona expediente],
          'endereco' => %w[endereço onde fica localização],
          'telefone' => %w[telefone ligar número contato],
          'documentos_locacao' => %w[documento documentação precisar alugar locação],
          'pets' => %w[pet animal cachorro gato bicho],
          'garantias' => %w[garantia fiador caução seguro fiança],
          'taxa_administracao' => %w[taxa administração percentual],
          'vistoria' => %w[vistoria entrada saída],
          'manutencao' => %w[manutenção conserto reparo vazamento],
          'desocupacao' => %w[desocupar sair mudar multa contrato]
        }
        (keywords[key] || []).any? { |kw| pergunta.include?(kw) }
      end
    end
  end
end
```

### 3.13 Atribuidor (subagente)

```ruby
# app/services/tozi/atribuidor.rb
module Tozi
  class Atribuidor
    SYSTEM = <<~PROMPT
      Você é um subagente chamado pela Clara (pré-atendimento da Tozi Imóveis). Você trabalha nos bastidores.

      A Clara conversou com o cliente e te passou o contexto. Seu trabalho:
      1. Analisar o que foi coletado
      2. Enriquecer com buscas relevantes (se aplicável)
      3. Montar o resumo e a sugestão

      Se tem critérios para buscar imóveis (tipo + algum filtro) → busque.
      Se mencionou referência geográfica → busque coordenadas primeiro.
      Se não tem informação para buscar → só monte o resumo.

      Responda em JSON:
      {"resumo": "texto do resumo", "sugestao": "texto da sugestão ou vazio"}
    PROMPT

    TOOLS = [
      {
        name: 'buscar_imoveis',
        description: 'Busca imóveis no Vista.',
        input_schema: {
          type: 'object',
          properties: {
            filter: { type: 'object' },
            advFilter: { type: 'object' },
            order: { type: 'object' },
            paginacao: { type: 'object' }
          },
          required: %w[filter advFilter order paginacao]
        }
      },
      {
        name: 'buscar_localizacao',
        description: 'Converte referência geográfica em coordenadas.',
        input_schema: {
          type: 'object',
          properties: { local: { type: 'string' } },
          required: ['local']
        }
      }
    ].freeze

    def initialize(conversation, contexto)
      @conversation = conversation
      @contexto = contexto
      @client = Tozi::AnthropicClient.new
    end

    def process
      resposta = @client.agent_loop(
        system: SYSTEM,
        messages: [{ role: 'user', content: @contexto }],
        tools: TOOLS,
        tool_handler: method(:handle_tool)
      )

      parsed = JSON.parse(resposta) rescue { 'resumo' => resposta, 'sugestao' => '' }
      {
        resumo: parsed['resumo'] || resposta,
        sugestao: parsed['sugestao'] || ''
      }
    end

    private

    def handle_tool(name, input)
      case name
      when 'buscar_imoveis'
        Tozi::Tools::BuscarImoveis.call(input)
      when 'buscar_localizacao'
        Tozi::Tools::BuscarLocalizacao.call(input['local'])
      else
        "Tool não reconhecida"
      end
    end
  end
end
```

### 3.14 Media Pipeline

```ruby
# app/services/tozi/media_pipeline.rb
module Tozi
  class MediaPipeline
    def self.process(message)
      textos = message.attachments.map do |attachment|
        case attachment.file_type
        when 'audio'
          transcricao = transcrever_audio(attachment)
          enviar_nota_privada(message.conversation, "🎤 Áudio transcrito: #{transcricao}")
          transcricao
        when 'image'
          descricao = descrever_imagem(attachment)
          enviar_nota_privada(message.conversation, "🖼️ Imagem: #{descricao}")
          legenda = message.content.presence
          legenda ? "#{descricao}\nLegenda: #{legenda}" : descricao
        when 'video'
          "[Vídeo enviado pelo cliente]"
        when 'location'
          "[Localização enviada pelo cliente]"
        when 'contact'
          "[Contato enviado pelo cliente]"
        else
          "[Arquivo enviado pelo cliente]"
        end
      end

      texto_midia = textos.compact.join("\n")
      texto_msg = message.content.presence

      [texto_midia, texto_msg].compact.join("\n")
    end

    private

    def self.transcrever_audio(attachment)
      # Download do arquivo
      file_data = download_attachment(attachment)

      uri = URI('https://api.openai.com/v1/audio/transcriptions')
      boundary = SecureRandom.hex(16)

      body = []
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n"
      body << "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.ogg\"\r\nContent-Type: audio/ogg\r\n\r\n#{file_data}\r\n"
      body << "--#{boundary}--\r\n"

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      req = Net::HTTP::Post.new(uri.path)
      req['Authorization'] = "Bearer #{ENV['TOZI_OPENAI_API_KEY']}"
      req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      req.body = body.join

      res = http.request(req)
      JSON.parse(res.body)['text'] || 'Não foi possível transcrever'
    rescue => e
      Rails.logger.error("[Tozi] Erro transcrever áudio: #{e.message}")
      '[Erro na transcrição do áudio]'
    end

    def self.descrever_imagem(attachment)
      image_url = attachment.file_url

      uri = URI('https://api.openai.com/v1/chat/completions')
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      req = Net::HTTP::Post.new(uri.path)
      req['Authorization'] = "Bearer #{ENV['TOZI_OPENAI_API_KEY']}"
      req['Content-Type'] = 'application/json'
      req.body = {
        model: 'gpt-4o-mini',
        messages: [{
          role: 'user',
          content: [
            { type: 'text', text: 'Analise a imagem. Identifique: tipo de imagem, imóvel (se houver), placa de venda/aluguel (se visível), texto legível. Descrição em 1-2 frases para atendente imobiliário.' },
            { type: 'image_url', image_url: { url: image_url } }
          ]
        }],
        max_tokens: 300
      }.to_json

      res = http.request(req)
      JSON.parse(res.body).dig('choices', 0, 'message', 'content') || 'Não foi possível analisar'
    rescue => e
      Rails.logger.error("[Tozi] Erro descrever imagem: #{e.message}")
      '[Erro na análise da imagem]'
    end

    def self.download_attachment(attachment)
      uri = URI(attachment.file_url)
      Net::HTTP.get(uri)
    end

    def self.enviar_nota_privada(conversation, texto)
      conversation.messages.create!(
        message_type: :outgoing,
        content: texto,
        private: true,
        account_id: conversation.account_id,
        inbox_id: conversation.inbox_id
      )
    end
  end
end
```

---

## 4. Configuração do Sidekiq

Adicionar a fila `tozi` na configuração do Sidekiq:

```yaml
# config/sidekiq.yml
:queues:
  - [default, 5]
  - [mailers, 3]
  - [tozi, 3]        # ← adicionar
  - [low, 1]
```

### Retry e error handling

Os jobs já herdam de `ApplicationJob`. Configuração de retry específica:

```ruby
# app/jobs/tozi/process_message_job.rb
class Tozi::ProcessMessageJob < ApplicationJob
  queue_as :tozi
  retry_on StandardError, wait: 5.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound
end
```

---

## 5. Testes

### Estrutura

```
spec/
├── services/
│   └── tozi/
│       ├── router_spec.rb
│       ├── clara_agent_spec.rb
│       ├── config_spec.rb
│       ├── humanizer_spec.rb
│       └── tools/
│           ├── buscar_imoveis_spec.rb
│           └── buscar_localizacao_spec.rb
│
└── jobs/
    └── tozi/
        ├── process_message_job_spec.rb
        └── clara_debounce_job_spec.rb
```

### Testes obrigatórios do Router (equivalente à Fase 0)

```ruby
# spec/services/tozi/router_spec.rb
RSpec.describe Tozi::Router do
  describe '.route' do
    it 'roteia mensagem incoming de contato sem atendimento para :agente_clara'
    it 'ignora mensagem incoming de contato com label atendimento'
    it 'ignora mensagem incoming de contato com custom_attribute atendimento'
    it 'ignora mensagem incoming de contato com atendimento no sender'
    it 'roteia imagem incoming de contato para :agente_clara'
    it 'roteia mensagem outgoing pública de user para :marcar_atendimento'
    it 'roteia mensagem privada com #tozi de user para :copiloto'
    it 'ignora mensagem privada sem #tozi de user'
    it 'ignora mensagem de agent_bot'
    it 'ignora mensagem de grupo WhatsApp (@g.us)'
    it 'ignora mensagem activity'
    it 'ignora contato sem conteúdo e sem anexo'
  end
end
```

### Mock da API Anthropic

```ruby
# spec/support/tozi_helpers.rb
module ToziHelpers
  def stub_anthropic_response(text)
    stub_request(:post, 'https://api.anthropic.com/v1/messages')
      .to_return(
        status: 200,
        body: {
          content: [{ type: 'text', text: text }],
          stop_reason: 'end_turn'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end
end
```

---

## 6. Migração / Rollout

### Fase 1 — Router + testes (sem IA)
- Implementar `Tozi::Router`, `Tozi::Config`, hooks
- Todos os testes do Router passando
- Deploy com `TOZI_ENABLED=false`

### Fase 2 — Clara (sem tools)
- Implementar `AnthropicClient`, `ClaraAgent` (sem tools), `Humanizer`
- Implementar `ClaraDebounceJob`
- Testar com `TOZI_ENABLED=true` numa inbox de teste
- Validar: mensagem → Clara responde → sem duplicação

### Fase 3 — Tools da Clara
- Implementar `FaqTozi`, `AtribuirAtendimento`, `Atribuidor`
- Validar: Clara qualifica → atribui → Camila recebe lead com resumo

### Fase 4 — Copiloto
- Implementar `CopilotoAgent`, `CopilotoJob`
- Validar: `#tozi` → resposta privada

### Fase 5 — Mídia
- Implementar `MediaPipeline` (Whisper + Vision)
- Validar: áudio → transcrição → Clara responde

### Fase 6 — Virada
- Apontar `TOZI_INBOX_ID` para inbox de produção ([TOZI] FIXO, ID 91)
- Desligar workflow do n8n
- Monitorar via Sidekiq Web UI

---

## 7. IDs e constantes de produção

```ruby
# Produção (account 6)
TOZI_ACCOUNT_ID = 6
TOZI_INBOX_ID = 91          # [TOZI] FIXO

# Agentes
CAMILA_AGENT_ID = 66
TIME_LOCACAO_ID = 50
TIME_VENDAS_ID = 49
TIME_FINANCEIRO_ID = 56
TIME_MANUTENCAO_ID = 53

# Vista API
VISTA_BASE_URL = 'https://toz19328-rest.vistahost.com.br'

# Fuso horário
TIMEZONE = 'America/Cuiaba'
```

---

## 8. Observações para o desenvolvedor

1. **Não usar gems de IA** — A API da Anthropic é REST puro. `Net::HTTP` resolve. Sem dependência extra.

2. **Idempotência é crítica** — O hook `after_create` pode disparar mais de uma vez em cenários de race condition. O `Rails.cache` com chave por `message_id` evita reprocessamento.

3. **Debounce via Sidekiq** — O `set(wait: 15.seconds)` do Sidekiq é a forma correta de fazer debounce. Não usar `sleep`.

4. **Não bloquear o Sidekiq** — A chamada à Anthropic API pode levar 5-30s. Isso é OK num worker Sidekiq (é assíncrono). Não fazer isso no request cycle do Puma.

5. **Logs com conversa_id** — Todo log deve incluir `[Tozi] conversa=#{id}` para facilitar debug.

6. **Testes sem API real** — Usar WebMock/VCR para mockar Anthropic, Vista e Google Maps. Nunca chamar API real em teste.

7. **O prompt da Clara é sensível** — Mudanças no prompt afetam o comportamento. Tratar como código (versionado, revisado).

8. **FAQ é placeholder** — A implementação com hash é temporária. O ideal é migrar para pgvector (PostgreSQL) com busca semântica. Mas funciona para começar.
