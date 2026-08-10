# Atualiza os contratos das tools MTM e garante a habilitação por responsabilidade.
# Alvo: Fábrica dos Óculos, account 1. Idempotente e sem alterar prompts.
#
# Uso (no box, via rails runner):
#   SPX_ACTION=plan     .../harden_mtm_tools_20260807.rb
#   SPX_ACTION=apply    .../harden_mtm_tools_20260807.rb
#   SPX_ACTION=rollback SPX_BACKUP_PATH=/caminho/do/snapshot.json .../harden_mtm_tools_20260807.rb
#
# O apply cria antes um snapshot 0600 contendo somente os campos alterados (sem
# prompts, auth_config ou credenciais). O rollback restaura apenas esses campos.

require 'digest'
require 'fileutils'
require 'json'
require 'time'

ACCOUNT_ID = 1
BACKUP_VERSION = 1
MUTATED_TOOL_FIELDS = %w[description request_template response_template param_schema enabled].freeze
VALID_ACTIONS = %w[plan apply rollback].freeze

action = ENV.fetch('SPX_ACTION', 'plan')
abort("SPX_ACTION inválida: #{action.inspect}. Use plan, apply ou rollback.") unless VALID_ACTIONS.include?(action)

account = Account.find(ACCOUNT_ID)
assistants = Captain::Assistant.where(account_id: account.id).index_by(&:name)
instruction_hashes = assistants.transform_values do |assistant|
  Digest::SHA256.hexdigest(assistant.config['instructions'].to_s)
end

tool_updates = {
  'mtm_calendario' => {
    description: 'Retorna o AGORA exato (data, hora e timezone) e as datas dos próximos dias. ' \
                 'Use sempre que precisar validar se um horário ainda é possível; nunca calcule data ou hora por conta própria.',
    response_template: <<~LIQUID.strip
      AGORA data_hora={{ r.agora.data_hora }} data={{ r.agora.data }} hora={{ r.agora.hora }} timezone={{ r.agora.timezone }}.
      Hoje é {{ r.hoje }}. Datas exatas dos próximos dias (use estas, nunca calcule):
      {% for d in r.dias %}
      - {{ d.dia_semana }}, {{ d.data }}{% if d.rel %} ({{ d.rel }}){% endif %}
      {% if d.fim_de_semana %} — fim de semana{% endif %}
      {% endfor %}
    LIQUID
  },
  'mtm_criar_proposta' => {
    description: 'Cria um pedido de EXAME (consulta de grau) na loja. As clínicas respondem os horários depois, aqui na conversa. ' \
                 'Não invente horário. Informe hora exata OU período (manha, tarde, sem_preferencia). ' \
                 'Não use para visita à loja; use mtm_agendar_visita.',
    request_template: '{"shop_id":{{ shop_id | plus: 0 }},"type":"consulta_oftalmologica","origin_id":4,' \
                      '{% if cpf and cpf != "" %}"cpf":"{{ cpf }}",{% endif %}' \
                      '"razao_social":"{{ nome }}","fone1":"{{ fone }}","created_via":"ia_elen",' \
                      '"desired_window":{"preferred_dates":["{{ data }}"]' \
                      '{% if hora != "" %},"preferred_time":"{{ hora }}"' \
                      '{% elsif periodo != "" %},"preferred_period":"{{ periodo }}"{% endif %}}}',
    response_template: <<~LIQUID.strip,
      {% if r.data and r.data.status %}PEDIDO_CRIADO id={{ r.data.id }} status={{ r.data.status }}
      {% elsif r.code == "HORARIO_PASSADO" %}HORARIO_PASSADO agora={{ r.meta.agora }} timezone={{ r.meta.timezone }} mensagem="{{ r.message }}"
      {% elsif r.code == "ANTECEDENCIA_INSUFICIENTE" %}ANTECEDENCIA_INSUFICIENTE
      agora={{ r.meta.agora }} proximo={{ r.meta.proximo_horario_permitido }} mensagem="{{ r.message }}"
      {% elsif r.code == "PERIODO_JA_PASSOU" %}PERIODO_JA_PASSOU agora={{ r.meta.agora }} mensagem="{{ r.message }}"
      {% elsif r.code == "FORA_DO_HORARIO" %}FORA_DO_HORARIO abre={{ r.meta.abre_as }} fecha={{ r.meta.fecha_as }} mensagem="{{ r.message }}"
      {% else %}ERRO_TECNICO_CRIAR_PEDIDO{% endif %}
    LIQUID
    param_schema: [
      { 'name' => 'shop_id', 'type' => 'number', 'required' => true, 'description' => 'ID retornado por mtm_loja_mais_proxima.' },
      { 'name' => 'cpf', 'type' => 'string', 'required' => true, 'description' => 'CPF só números; passe string vazia se não informado.' },
      { 'name' => 'nome', 'type' => 'string', 'required' => true, 'description' => 'Nome completo do cliente.' },
      { 'name' => 'fone', 'type' => 'string', 'required' => true, 'description' => 'Telefone do cliente com DDD.' },
      { 'name' => 'data', 'type' => 'string', 'required' => true, 'description' => 'Data desejada, AAAA-MM-DD, confirmada por mtm_calendario.' },
      { 'name' => 'hora', 'type' => 'string', 'required' => true, 'description' => 'Hora exata HH:MM; passe string vazia quando usar período.' },
      {
        'name' => 'periodo',
        'type' => 'string',
        'required' => true,
        'description' => 'manha, tarde ou sem_preferencia; passe string vazia quando usar hora exata.'
      }
    ]
  },
  'mtm_status_proposta' => {
    description: 'Consulta o andamento do pedido de exame desta conversa e preserva o motivo real quando houver escalada.',
    response_template: <<~LIQUID.strip
      {% assign s = r.data.status %}{% if s == "awaiting_clinics" or s == "proposed" %}AGUARDANDO_CLINICAS
      {% elsif s == "awaiting_client" %}HORARIOS_DISPONIVEIS
      {% elsif s == "scheduled" %}AGENDADO
      {% elsif s == "escalated" %}{{ r.data.status_reason_code | default: "ESCALADO" }}
      {% elsif s == "expired" %}EXPIRADO
      {% elsif s == "cancelled" %}CANCELADO
      {% else %}STATUS_{{ s }}{% endif %}
    LIQUID
  },
  'mtm_loja_mais_proxima' => {
    response_template: <<~LIQUID.strip
      {% if r.data %}LOJA_DEFINIDA nome="{{ r.data.nome }}" cidade="{{ r.data.cidade }}"
      bairro="{{ r.data.bairro }}" endereco="{{ r.data.endereco }}" shop_id={{ r.data.shop_id }}
      distancia_km={{ r.data.distancia_km }}
      {% elsif r.empate %}EMPATE_REAL. Opções ordenadas da mais próxima para a segunda;
      opcao1 é a mais próxima. Se o cliente pedir apenas a mais perto, escolha opcao1 sem perguntar novamente.
      {% for loja in r.lojas %}opcao{{ forloop.index }}: nome="{{ loja.nome }}" shop_id={{ loja.shop_id }}
      distancia_km={{ loja.distancia_km }} bairro="{{ loja.bairro }}" endereco="{{ loja.endereco }}";
      {% endfor %}
      {% elsif r.precisa_referencia %}PRECISA_REFERENCIA
      {% else %}NAO_ACHOU_LOJA{% endif %}
    LIQUID
  }
}.freeze

required_tools = {
  'Bia' => %w[mtm_loja_mais_proxima mtm_calendario mtm_agendar_visita atualizar_resumo],
  'Carol' => %w[
    mtm_loja_mais_proxima mtm_calendario mtm_criar_proposta mtm_escolher_slot
    mtm_status_proposta mtm_cancelar_proposta atualizar_resumo
  ],
  'Sofia' => %w[
    mtm_loja_mais_proxima mtm_calendario mtm_criar_proposta mtm_escolher_slot
    mtm_status_proposta mtm_cancelar_proposta atualizar_resumo
  ]
}.freeze

def validate_templates!(tool_updates)
  tool_updates.each_value do |attributes|
    Liquid::Template.parse(attributes[:request_template], error_mode: :strict) if attributes[:request_template]
    Liquid::Template.parse(attributes[:response_template], error_mode: :strict) if attributes[:response_template]
  end
end

def capture_snapshot(account, assistants, tool_updates, required_tools)
  {
    'version' => BACKUP_VERSION,
    'account_id' => account.id,
    'created_at' => Time.now.utc.iso8601,
    'tools' => tool_updates.keys.index_with do |slug|
      tool = Captain::CustomTool.find_by!(account_id: account.id, slug: slug)
      tool.attributes.slice(*MUTATED_TOOL_FIELDS)
    end,
    'assistants' => required_tools.keys.index_with do |name|
      assistant = assistants.fetch(name)
      {
        'id' => assistant.id,
        'tools' => Array(assistant.config['tools']).deep_dup,
        'instructions_sha256' => Digest::SHA256.hexdigest(assistant.config['instructions'].to_s)
      }
    end
  }
end

def write_snapshot!(snapshot)
  backup_dir = ENV.fetch('SPX_BACKUP_DIR', Rails.root.join('tmp', 'spx_backups').to_s)
  FileUtils.mkdir_p(backup_dir, mode: 0o700)
  FileUtils.chmod(0o700, backup_dir)
  timestamp = Time.now.utc.strftime('%Y%m%dT%H%M%SZ')
  path = File.join(backup_dir, "fabrica_account_#{ACCOUNT_ID}_mtm_tools_#{timestamp}.json")
  File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
    file.write(JSON.pretty_generate(snapshot))
    file.write("\n")
  end
  path
end

def restore_snapshot!(account, snapshot)
  unless snapshot['version'] == BACKUP_VERSION && snapshot['account_id'] == account.id
    raise 'Snapshot incompatível com esta conta ou versão.'
  end

  ActiveRecord::Base.transaction do
    snapshot.fetch('tools').each do |slug, attributes|
      tool = Captain::CustomTool.find_by!(account_id: account.id, slug: slug)
      tool.update!(attributes.slice(*MUTATED_TOOL_FIELDS))
    end

    snapshot.fetch('assistants').each do |name, assistant_snapshot|
      assistant = Captain::Assistant.find_by!(id: assistant_snapshot.fetch('id'), account_id: account.id)
      raise "Assistant renomeado desde o snapshot: #{name}" unless assistant.name == name

      config = assistant.config.deep_dup
      config['tools'] = assistant_snapshot.fetch('tools')
      assistant.update!(config: config)
    end
  end
end

validate_templates!(tool_updates)

if action == 'rollback'
  backup_path = ENV['SPX_BACKUP_PATH'].to_s
  abort('SPX_BACKUP_PATH é obrigatório no rollback.') if backup_path.empty?

  snapshot = JSON.parse(File.read(backup_path))
  restore_snapshot!(account, snapshot)
  puts "ROLLBACK concluído para account #{account.id} a partir de #{backup_path}."
  exit
end

snapshot = capture_snapshot(account, assistants, tool_updates, required_tools)
changed_tools = tool_updates.filter_map do |slug, attributes|
  target = attributes.stringify_keys.merge('enabled' => true)
  before = snapshot.fetch('tools').fetch(slug)
  changed_fields = target.keys.select { |field| before[field] != target[field] }
  "#{slug}: #{changed_fields.join(', ')}" if changed_fields.any?
end
changed_assistants = required_tools.filter_map do |assistant_name, slugs|
  current = snapshot.fetch('assistants').fetch(assistant_name).fetch('tools')
  missing = slugs - current
  "#{assistant_name}: adicionar #{missing.join(', ')}" if missing.any?
end

puts "Plano account=#{account.id} action=#{action}:"
(changed_tools + changed_assistants).each { |change| puts "  - #{change}" }
puts '  - nenhuma mudança necessária' if changed_tools.empty? && changed_assistants.empty?
exit if action == 'plan'

backup_path = write_snapshot!(snapshot)

ActiveRecord::Base.transaction do
  tool_updates.each do |slug, attributes|
    tool = Captain::CustomTool.find_by!(account_id: account.id, slug: slug)
    tool.update!(attributes.merge(enabled: true))
  end

  required_tools.each do |assistant_name, slugs|
    assistant = assistants.fetch(assistant_name)
    config = assistant.config.deep_dup
    config['tools'] = (Array(config['tools']) + slugs).uniq
    assistant.update!(config: config) if config != assistant.config
  end

  elen_tools = Array(assistants.fetch('Elen').reload.config['tools'])
  forbidden_for_elen = %w[
    mtm_criar_proposta mtm_escolher_slot mtm_status_proposta mtm_cancelar_proposta mtm_agendar_visita
  ]
  raise 'Elen recebeu tool operacional indevida' if (elen_tools & forbidden_for_elen).any?

  assistants.each_value do |assistant|
    current_hash = Digest::SHA256.hexdigest(assistant.reload.config['instructions'].to_s)
    raise "Prompt alterado para #{assistant.name}" unless current_hash == instruction_hashes.fetch(assistant.name)
  end
end

puts "APPLY concluído na account #{account.id}; prompts inalterados."
puts "BACKUP_PATH=#{backup_path}"
puts 'Para desfazer a configuração: ' \
     "SPX_ACTION=rollback SPX_BACKUP_PATH=#{backup_path} bundle exec rails runner #{__FILE__}"
