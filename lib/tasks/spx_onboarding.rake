# Receita de onboarding de uma IA de atendimento — só leitura, nenhum UPDATE.
#
#   bundle exec rails "spx:onboarding:checar[1,1]"        # conta 1, assistente 1
#   SEM_CHAMADA=1 bundle exec rails "spx:onboarding:checar[1,1]"   # não chama o modelo
#   bundle exec rails "spx:onboarding:prompt_base[1,1]"   # imprime um esqueleto de instructions
#
# Por que existe: na montagem da IA da Rocket (01/10/2026) cada item abaixo custou uma volta — a
# chave global da Anthropic sem saldo deixou a IA muda, a trava de teste por telefone precisava
# estar ligada, a caixa estava desconectada, o humanizer não estava ajustado e as instructions
# traziam texto que o modelo copiava. Isto é a lista, em um comando.
#
# A checagem do modelo faz UMA chamada mínima ao provedor, pelo mesmo caminho do runtime (chave da
# conta, senão a global). Listar modelos não serve: a chave sem saldo lista normalmente e só falha
# ao gerar texto. Custa uma fração de centavo; SEM_CHAMADA=1 pula a chamada e só confere a chave.
module SpxOnboarding
  OK = '✅'.freeze
  FALHA = '❌'.freeze
  AVISO = '⚠️ '.freeze
  INFO = 'ℹ️ '.freeze

  CHAVES_GLOBAIS = { 'anthropic' => 'CAPTAIN_ANTHROPIC_API_KEY', 'openai' => 'CAPTAIN_OPEN_AI_API_KEY' }.freeze
  STATUS_BROADCAST = 'status@broadcast'.freeze

  # Padrões que costumam virar texto copiado pelo modelo (REGRA #1: descrever a origem, nunca o valor).
  PADROES_COPIAVEIS = {
    'fala entre aspas' => /["“][^"”\n]{12,}["”]/,
    '"ex:"' => /\bex\s*[:.]/i,
    '"por exemplo"' => /\bpor exemplo\b/i,
    'número longo' => /\d{4,}/
  }.freeze

  module_function

  def checagens(conta, assistente, chamar: true)
    [modelo(conta, chamar), trava(assistente), *caixas(assistente), humanizer(assistente), *instructions(assistente)]
  end

  def modelo(conta, chamar)
    id = conta.captain_assistant_model
    origem = conta.captain_models.to_h['assistant'].present? ? 'da conta' : 'padrão do llm.yml'
    provedor = Llm::AccountCredentialsResolver.new(account: conta).provider_for_model(id)
    chave = origem_da_chave(conta, provedor)
    titulo = "modelo #{id} (#{origem}, #{provedor})"
    return [FALHA, titulo, "sem chave #{provedor} na conta nem na instalação"] if chave.nil?
    return [OK, titulo, "chave #{chave} presente; chamada não feita (SEM_CHAMADA)"] unless chamar

    chamar_modelo(conta, id)
    [OK, titulo, "chave #{chave} respondeu a uma chamada mínima"]
  rescue StandardError => e
    [FALHA, titulo, "chave #{chave} falhou ao gerar: #{e.class}: #{e.message.to_s.tr("\n", ' ')[0, 160]}"]
  end

  def origem_da_chave(conta, provedor)
    conta_tem = case provedor
                when 'anthropic' then Captain::AnthropicHookService.new(account: conta).anthropic_api_key
                else Captain::OpenaiHookService.new(account: conta).openai_api_key
                end
    return 'da conta' if conta_tem.present?

    InstallationConfig.find_by(name: CHAVES_GLOBAIS.fetch(provedor, CHAVES_GLOBAIS['openai']))&.value.present? ? 'global da instalação' : nil
  end

  def chamar_modelo(conta, id)
    Llm::AccountScopedContext.with_account(conta) do |contexto|
      contexto.chat(model: Llm::Models.runtime_id_for(id)).ask('Responda apenas: ok')
    end
  end

  def trava(assistente)
    fones = Array(assistente.behavior.to_h.dig('router', 'only_contact_phones')).compact_blank
    return [INFO, 'trava de teste por telefone desligada', 'a IA responde a qualquer contato; em fase de teste, ligue'] if fones.empty?

    [INFO, 'trava de teste por telefone LIGADA', "só responde a: #{fones.join(', ')} — desligue ao liberar para os clientes"]
  end

  def caixas(assistente)
    ids = CaptainInbox.where(captain_assistant_id: assistente.id).pluck(:inbox_id)
    return [[FALHA, 'caixas', 'o assistente não está ligado a caixa nenhuma']] if ids.empty?

    Inbox.where(id: ids).order(:id).flat_map { |caixa| checar_caixa(caixa) }
  end

  def checar_caixa(caixa)
    titulo = "caixa ##{caixa.id} #{caixa.name} (#{caixa.channel_type.demodulize})"
    sessao = caixa.try(:waha_session_name).presence
    return [conexao_waha(titulo, sessao), status_broadcast(caixa)] if sessao
    return [[AVISO, titulo, 'canal de API sem sessão WAHA: se for WhatsApp, não envia']] if caixa.channel_type == 'Channel::Api'

    canal = caixa.channel
    return [[INFO, titulo, 'canal sem sinal de saúde no código']] unless canal.respond_to?(:reauthorization_required?)
    return [[FALHA, titulo, 'canal pede reautorização (token ou conexão perdidos)']] if canal.reauthorization_required?

    [[OK, titulo, 'sem pedido de reautorização (token revogado pode não aparecer aqui até a primeira falha de envio)']]
  end

  def conexao_waha(titulo, sessao)
    status = Waha::ApiService.new.get_session(sessao).to_h['status'].to_s
    return [OK, titulo, "sessão WAHA #{sessao} conectada (WORKING)"] if status == 'WORKING'

    [FALHA, titulo, "sessão WAHA #{sessao} em #{status.presence || 'status desconhecido'}: ler o QR code de novo"]
  rescue StandardError => e
    [FALHA, titulo, "não consegui consultar a sessão WAHA #{sessao}: #{e.class}: #{e.message.to_s[0, 120]}"]
  end

  # O filtro está no app desde o #277, mas a CHAT-170 segue aberta: a prova é não haver stories entrando.
  def status_broadcast(caixa)
    entradas = Message.joins(conversation: :contact).where(inbox_id: caixa.id, contacts: { identifier: STATUS_BROADCAST })
    recentes = entradas.where(created_at: 24.hours.ago..).count
    titulo = "status@broadcast na caixa ##{caixa.id} (CHAT-170, pendência aberta)"
    if recentes.positive?
      return [FALHA, titulo, "#{recentes} mensagem(ns) de stories nas últimas 24h, a última em #{entradas.maximum(:created_at)}: " \
                             'o filtro não está segurando e cada uma pode acionar a IA']
    end

    [AVISO, titulo, 'nenhuma entrada em 24h; o filtro do app existe, mas a CHAT-170 ainda não foi encerrada']
  end

  def humanizer(assistente)
    config = assistente.behavior.to_h['humanizer'].to_h
    return [FALHA, 'humanizer', 'desligado: a resposta sai num bloco só, sem quebra em mensagens curtas'] unless config['enabled'] == true
    return [FALHA, 'humanizer', 'ligado sem max_chars (o código assume 300)'] if config['max_chars'].blank?

    [OK, 'humanizer', "ligado, max_chars #{config['max_chars']}"]
  end

  def instructions(assistente)
    texto = assistente.config.to_h['instructions'].to_s
    return [[AVISO, 'instructions', 'vazias: a IA fala só com o molde e a descrição']] if texto.blank?

    achados = PADROES_COPIAVEIS.flat_map do |nome, padrao|
      texto.to_enum(:scan, padrao).map { [nome, texto[[Regexp.last_match.begin(0) - 30, 0].max, 90].tr("\n", ' ')] }
    end
    return [[OK, 'instructions', "#{texto.size} caracteres, sem padrão de exemplo copiável"]] if achados.empty?

    lista = achados.first(10).map { |nome, trecho| [AVISO, "instructions: #{nome}", "…#{trecho}… (descreva a origem do dado, não o texto)"] }
    achados.size > 10 ? lista << [AVISO, 'instructions', "e mais #{achados.size - 10} trecho(s) não listados"] : lista
  end

  def prompt_base(conta, assistente)
    empresa = assistente.config.to_h['product_name'].presence || conta.name
    "Você é #{assistente.name}, da #{empresa}.\nO que a #{empresa} faz, os serviços, valores, endereço e horários vêm das ferramentas " \
      "e do cadastro da empresa; o que não vier delas, você não afirma.\n"
  end
end

namespace :spx do
  namespace :onboarding do
    desc 'Checa se uma IA está pronta para atender (só leitura). args: account_id, assistant_id'
    task :checar, %i[account_id assistant_id] => :environment do |_t, args|
      conta = Account.find(args.fetch(:account_id))
      assistente = Captain::Assistant.find_by!(id: args.fetch(:assistant_id), account_id: conta.id)
      puts "\n=== conta #{conta.id} #{conta.name} · assistente #{assistente.id} #{assistente.name} ==="
      itens = SpxOnboarding.checagens(conta, assistente, chamar: ENV['SEM_CHAMADA'].blank?)
      itens.each { |icone, titulo, motivo| puts "  #{icone} #{titulo}: #{motivo}" }
      falhas = itens.count { |icone, _, _| icone == SpxOnboarding::FALHA }
      puts "\n#{falhas.zero? ? 'nenhuma falha' : "#{falhas} falha(s)"}; avisos não bloqueiam."
    end

    desc 'Imprime um esqueleto mínimo de instructions (não grava). args: account_id, assistant_id'
    task :prompt_base, %i[account_id assistant_id] => :environment do |_t, args|
      conta = Account.find(args.fetch(:account_id))
      assistente = Captain::Assistant.find_by!(id: args.fetch(:assistant_id), account_id: conta.id)
      puts SpxOnboarding.prompt_base(conta, assistente)
    end
  end
end
