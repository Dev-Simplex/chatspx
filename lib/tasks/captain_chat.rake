require 'io/console'
require 'readline'

namespace :captain do
  desc 'Diagnose Copilot for an account - Usage: rake captain:diagnose[account_id]'
  task :diagnose, [:account_id] => :environment do |_, args|
    account_id = args[:account_id] || ARGV[1]

    unless account_id
      puts '❌ Please provide an account ID'
      puts 'Usage: rake captain:diagnose[account_id]'
      exit 1
    end

    account = Account.find_by(id: account_id)
    unless account
      puts "❌ Account with ID #{account_id} not found"
      exit 1
    end

    puts "\n🔍 Diagnóstico Copilot - Conta ##{account.id} (#{account.name})"
    puts '=' * 60

    # 1. Feature flags
    captain_v1 = account.feature_enabled?('captain_integration')
    captain_v2 = account.feature_enabled?('captain_integration_v2')
    if captain_v1 || captain_v2
      puts "✅ Feature flags: captain_integration=#{captain_v1}, captain_integration_v2=#{captain_v2}"
    else
      puts "❌ Feature flags: Captain desabilitado para esta conta"
      puts "   Para habilitar: Account.find(#{account.id}).enable_features!('captain_integration', 'captain_integration_v2')"
      puts "   Ou via: Configurações da conta > Features"
      exit 1
    end

    # 2. OpenAI API Key
    openai_service = Captain::OpenaiHookService.new(account: account)
    if openai_service.configured?
      puts '✅ Chave API OpenAI: configurada'
    else
      puts '❌ Chave API OpenAI: NÃO configurada'
      puts "   Configure em: Configurações > Integrações > OpenAI"
      exit 1
    end

    # 3. Assistants
    assistants = account.captain_assistants
    if assistants.any?
      puts "✅ Assistentes: #{assistants.count} encontrado(s) - IDs: #{assistants.pluck(:id).join(', ')}"
    else
      puts '❌ Assistentes: nenhum configurado'
      puts "   Crie um assistente em: Captain > Assistants"
      exit 1
    end

    # 4. Effective models + runtime support
    puts "\n🧠 Modelos Captain (efetivos):"
    unsupported_models = []
    account.captain_preferences[:models].each do |feature_key, model_name|
      supported = Llm::Models.runtime_supported_model?(model_name)
      marker = supported ? '✅' : '❌'
      puts "   #{marker} #{feature_key}: #{model_name} (runtime_supported=#{supported})"
      unsupported_models << [feature_key, model_name] unless supported
    end

    if unsupported_models.any?
      puts "\n❌ Modelos não suportados pelo runtime RubyLLM:"
      unsupported_models.each do |feature_key, model_name|
        puts "   - #{feature_key}: #{model_name}"
      end
      puts '   Ajuste os modelos em Captain > Configurações > Configuração de modelos'
      exit 1
    end

    # 5. Usage limits
    limits = account.usage_limits[:captain]
    if limits
      responses = limits[:responses] || {}
      current = responses[:current_available].to_i
      consumed = responses[:consumed].to_i
      total = responses[:total_count].to_i

      if current.positive?
        puts "✅ Limite de respostas: #{current} disponíveis (#{consumed}/#{total} consumidos)"
      else
        puts "❌ Limite de respostas: créditos esgotados (#{consumed}/#{total})"
        puts "   Compre mais créditos na seção de faturamento"
      end
    else
      puts '⚠️  Limites Captain: não definidos (pode usar limites globais)'
    end

    # 6. OpenAI Hook details (without exposing key)
    hook = account.hooks.find_by(app_id: 'openai')
    if hook
      puts "✅ Hook OpenAI: id=#{hook.id}, status=#{hook.status}"
    end

    puts '=' * 60
    puts "\n✅ Diagnóstico concluído. Copilot deve funcionar para esta conta."
    puts "   Teste via: POST /api/v1/accounts/#{account.id}/captain/copilot_threads"
    puts "   Payload: {\"assistant_id\": #{assistants.first&.id}, \"conversation_id\": ID_DA_CONVERSA, \"message\": \"Sua mensagem\"}"
    puts ''
  end

  desc 'Enable Captain features for an account - Usage: rake captain:enable_features[account_id]'
  task :enable_features, [:account_id] => :environment do |_, args|
    account_id = args[:account_id] || ARGV[1]
    unless account_id
      puts 'Usage: rake captain:enable_features[account_id]'
      exit 1
    end

    account = Account.find_by(id: account_id)
    unless account
      puts "❌ Account #{account_id} not found"
      exit 1
    end

    account.enable_features!('captain_integration', 'captain_integration_v2')
    puts "✅ Captain features habilitados para conta ##{account.id} (#{account.name})"
  end

  desc 'Start interactive chat with Captain assistant - Usage: rake captain:chat[assistant_id] or rake captain:chat -- assistant_id'
  task :chat, [:assistant_id] => :environment do |_, args|
    assistant_id = args[:assistant_id] || ARGV[1]

    unless assistant_id
      puts '❌ Please provide an assistant ID'
      puts 'Usage: rake captain:chat[assistant_id]'
      puts "\nAvailable assistants:"
      Captain::Assistant.includes(:account).each do |assistant|
        puts "  ID: #{assistant.id} - #{assistant.name} (Account: #{assistant.account.name})"
      end
      exit 1
    end

    assistant = Captain::Assistant.find_by(id: assistant_id)
    unless assistant
      puts "❌ Assistant with ID #{assistant_id} not found"
      exit 1
    end

    # Clear ARGV to prevent gets from reading files
    ARGV.clear

    chat_session = CaptainChatSession.new(assistant)
    chat_session.start
  end
end

class CaptainChatSession
  def initialize(assistant)
    @assistant = assistant
    @message_history = []
  end

  def start
    show_assistant_info
    show_instructions
    chat_loop
    show_exit_message
  end

  private

  def show_instructions
    puts "💡 Type 'exit', 'quit', or 'bye' to end the session"
    puts "💡 Type 'clear' to clear message history"
    puts('-' * 50)
  end

  def chat_loop
    loop do
      puts '' # Add spacing before prompt
      user_input = Readline.readline('👤 You: ', true)
      next unless user_input # Handle Ctrl+D

      break unless handle_user_input(user_input.strip)
    end
  end

  def handle_user_input(user_input)
    case user_input.downcase
    when 'exit', 'quit', 'bye'
      false
    when 'clear'
      clear_history
      true
    when ''
      true
    else
      process_user_message(user_input)
      true
    end
  end

  def show_exit_message
    puts "\nChat session ended"
    puts "Final conversation log has #{@message_history.length} messages"
  end

  def show_assistant_info
    show_basic_info
    show_scenarios
    show_available_tools
    puts ''
  end

  def show_basic_info
    puts "🤖 Starting chat with #{@assistant.name}"
    puts "🏢 Account: #{@assistant.account.name}"
    puts "🆔 Assistant ID: #{@assistant.id}"
  end

  def show_scenarios
    scenarios = @assistant.scenarios.enabled
    if scenarios.any?
      puts "⚡ Enabled Scenarios (#{scenarios.count}):"
      scenarios.each { |scenario| display_scenario(scenario) }
    else
      puts '⚡ No scenarios enabled'
    end
  end

  def display_scenario(scenario)
    tools_count = scenario.tools&.length || 0
    puts "   • #{scenario.title} (#{tools_count} tools)"
    return if scenario.description.blank?

    description = truncate_description(scenario.description)
    puts "     #{description}"
  end

  def truncate_description(description)
    description.length > 60 ? "#{description[0..60]}..." : description
  end

  def show_available_tools
    available_tools = @assistant.available_tool_ids
    if available_tools.any?
      puts "🔧 Available Tools (#{available_tools.count}): #{available_tools.join(', ')}"
    else
      puts '🔧 No tools available'
    end
  end

  def process_user_message(user_input)
    add_to_history('user', user_input)

    begin
      print "🤖 #{@assistant.name}: "
      @current_system_messages = []

      result = generate_assistant_response
      display_response(result)
    rescue StandardError => e
      handle_error(e)
    end
  end

  def generate_assistant_response
    runner = Captain::Assistant::AgentRunnerService.new(assistant: @assistant, callbacks: build_callbacks)
    runner.generate_response(message_history: @message_history)
  end

  def build_callbacks
    {
      on_agent_thinking: method(:handle_agent_thinking),
      on_tool_start: method(:handle_tool_start),
      on_tool_complete: method(:handle_tool_complete),
      on_agent_handoff: method(:handle_agent_handoff)
    }
  end

  def handle_agent_thinking(agent, _input)
    agent_name = extract_name(agent)
    @current_system_messages << "#{agent_name} is thinking..."
    add_to_history('system', "#{agent_name} is thinking...")
  end

  def handle_tool_start(tool, _args)
    tool_name = extract_tool_name(tool)
    @current_system_messages << "Using tool: #{tool_name}"
    add_to_history('system', "Using tool: #{tool_name}")
  end

  def handle_tool_complete(tool, _result)
    tool_name = extract_tool_name(tool)
    @current_system_messages << "Tool #{tool_name} completed"
    add_to_history('system', "Tool #{tool_name} completed")
  end

  def handle_agent_handoff(from, to, reason)
    @current_system_messages << "Handoff: #{extract_name(from)} → #{extract_name(to)} (#{reason})"
    add_to_history('system', "Agent handoff: #{extract_name(from)} → #{extract_name(to)} (#{reason})")
  end

  def display_response(result)
    response_text = result['response'] || 'No response generated'
    reasoning = result['reasoning']

    puts dim_text("\n#{@current_system_messages.join("\n")}") if @current_system_messages.any?
    puts response_text
    puts dim_italic_text("(Reasoning: #{reasoning})") if reasoning && reasoning != 'Processed by agent'

    add_to_history('assistant', response_text, reasoning: reasoning)
  end

  def handle_error(error)
    error_msg = "Error: #{error.message}"
    puts "❌ #{error_msg}"
    add_to_history('system', error_msg)
  end

  def add_to_history(role, content, agent_name: nil, reasoning: nil)
    message = {
      role: role,
      content: content,
      timestamp: Time.current,
      agent_name: agent_name || (role == 'assistant' ? @assistant.name : nil)
    }
    message[:reasoning] = reasoning if reasoning

    @message_history << message
  end

  def clear_history
    @message_history.clear
    puts 'Message history cleared'
  end

  def dim_text(text)
    # ANSI escape code for very dim gray text (bright black/dark gray)
    "\e[90m#{text}\e[0m"
  end

  def dim_italic_text(text)
    # ANSI escape codes for dim gray + italic text
    "\e[90m\e[3m#{text}\e[0m"
  end

  def extract_tool_name(tool)
    return tool if tool.is_a?(String)

    tool.class.name.split('::').last.gsub('Tool', '')
  rescue StandardError
    tool.to_s
  end

  def extract_name(obj)
    obj.respond_to?(:name) ? obj.name : obj.to_s
  end
end
