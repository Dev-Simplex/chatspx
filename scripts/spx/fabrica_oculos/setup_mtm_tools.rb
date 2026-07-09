# Cria/atualiza as custom tools do MTM para a Elen (Account 1 - Fábrica dos Óculos).
# Idempotente. A chave do MTM vem de ENV['MTM_API_KEY'] (NÃO hardcodar no arquivo).
# Uso: MTM_API_KEY=xxx RAILS_ENV=production bundle exec rails runner Temp/setup_mtm_tools.rb

account = Account.find(1)
token = ENV['MTM_API_KEY'].to_s
abort('MTM_API_KEY ausente no ENV') if token.empty?

BASE = 'https://fabrica.simplexsolucoes.com.br/api/v1'.freeze

tools = [
  {
    slug: 'mtm_buscar_cliente',
    title: 'Buscar cliente por CPF (MTM)',
    description: 'Consulta o cadastro do cliente no MTM pelo CPF (somente números). ' \
                 'Use para verificar se o cliente já existe e puxar nome/cidade/status antes de cadastrar.',
    http_method: 'GET',
    endpoint_url: "#{BASE}/clients?cpf={{ cpf | url_encode }}",
    param_schema: [
      { 'name' => 'cpf', 'type' => 'string', 'description' => 'CPF do cliente, somente números (11 dígitos).', 'required' => true }
    ],
    response_template: '{% if r.data and r.data.size > 0 %}{% assign c = r.data[0] %}' \
                       'Cliente: {{ c.razao_social }} | CPF {{ c.cpf }} | {{ c.cidade }} | status {{ c.status }} | tel {{ c.fone1 }} | id {{ c.id }}' \
                       '{% else %}NAO_ENCONTRADO: nenhum cliente com esse CPF no MTM.{% endif %}'
  },
  {
    slug: 'mtm_registrar_cliente',
    title: 'Registrar cliente (MTM)',
    description: 'Cadastra um novo lead/cliente no MTM. Antes, SEMPRE tente o buscar_cliente por CPF. ' \
                 'Passe os campos que souber; se não souber algum, passe string vazia "".',
    http_method: 'POST',
    endpoint_url: "#{BASE}/clients",
    request_template: '{"razao_social":"{{nome}}","cpf":"{{cpf}}","fone1":"{{telefone}}",' \
                      '"cidade":"{{cidade}}","bairro":"{{bairro}}","status":"lead-ia"}',
    param_schema: [
      { 'name' => 'nome', 'type' => 'string', 'description' => 'Nome completo do cliente.', 'required' => true },
      { 'name' => 'cpf', 'type' => 'string', 'description' => 'CPF somente números, ou "" se não informado.', 'required' => true },
      { 'name' => 'telefone', 'type' => 'string', 'description' => 'Telefone com DDD, ou "".', 'required' => true },
      { 'name' => 'cidade', 'type' => 'string', 'description' => 'Cidade do cliente, ou "".', 'required' => true },
      { 'name' => 'bairro', 'type' => 'string', 'description' => 'Bairro do cliente, ou "".', 'required' => true }
    ],
    response_template: '{% if r.data %}OK: cliente cadastrado no MTM (id {{ r.data.id }}).{% else %}ERRO ao cadastrar: {{ r.message }}{% endif %}'
  },
  {
    slug: 'mtm_loja_por_cidade',
    title: 'Lojas por cidade (MTM)',
    description: 'Lista as lojas da rede por cidade e marca. departamento = "fabrica" (Fábrica dos Óculos) ou "atacadao" (Atacadão dos Óculos). ' \
                 'Use para indicar/definir a loja onde o cliente será atendido.',
    http_method: 'GET',
    endpoint_url: "#{BASE}/shops?cidade={{ cidade | url_encode }}&departamento={{ departamento | url_encode }}",
    param_schema: [
      { 'name' => 'cidade', 'type' => 'string', 'description' => 'Cidade do cliente (ex: Sinop, Cuiabá, Sorriso, Várzea Grande).', 'required' => true },
      { 'name' => 'departamento', 'type' => 'string', 'description' => 'Marca: "fabrica" ou "atacadao".', 'required' => true }
    ],
    response_template: '{% if r.data and r.data.size > 0 %}{% for s in r.data %}' \
                       '{{ s.nome_exibicao }} ({{ s.bairro }}, {{ s.cidade }}) [id {{ s.id }}, {{ s.departamento }}]' \
                       '{% unless forloop.last %} | {% endunless %}{% endfor %}' \
                       '{% else %}NENHUMA_LOJA encontrada para essa cidade/marca.{% endif %}'
  },
  {
    slug: 'mtm_listar_clinicas',
    title: 'Listar clínicas parceiras (MTM)',
    description: 'Lista as clínicas parceiras ativas com o valor da consulta. ' \
                 'Use no fluxo de óculos de grau SEM receita, para apresentar opções de consulta.',
    http_method: 'GET',
    endpoint_url: "#{BASE}/clinics?ativo=true&per_page=50",
    param_schema: [],
    response_template: '{% if r.data and r.data.size > 0 %}{% for c in r.data %}' \
                       '{{ c.nome }} (R$ {{ c.valor_consulta }}, id {{ c.id }})' \
                       '{% unless forloop.last %} | {% endunless %}{% endfor %}' \
                       '{% else %}NENHUMA_CLINICA ativa.{% endif %}'
  }
]

puts '=== CRIANDO/ATUALIZANDO CUSTOM TOOLS (Account 1) ==='
tools.each do |spec|
  t = Captain::CustomTool.find_or_initialize_by(account_id: account.id, slug: spec[:slug])
  t.title = spec[:title]
  t.description = spec[:description]
  t.http_method = spec[:http_method]
  t.endpoint_url = spec[:endpoint_url]
  t.request_template = spec[:request_template]
  t.response_template = spec[:response_template]
  t.param_schema = spec[:param_schema]
  t.auth_type = 'bearer'
  t.auth_config = { 'token' => token }
  t.enabled = true
  was_new = t.new_record?
  t.save!
  puts "  #{was_new ? 'CRIADA' : 'ATUALIZADA'}: #{t.slug} (id #{t.id})"
end

puts
puts '=== TESTE AO VIVO (somente GET; POST não testado p/ não poluir o MTM) ==='
assistant = Captain::Assistant.find(1)

def run_test(label, slug, assistant, params)
  tool = Captain::CustomTool.find_by(account_id: assistant.account_id, slug: slug).tool(assistant)
  out = tool.perform(nil, **params)
  puts "  [#{label}] => #{out.to_s[0, 600]}"
rescue StandardError => e
  puts "  [#{label}] ERRO: #{e.class} - #{e.message[0, 200]}"
end

run_test('buscar_cliente cpf=04614446159', 'mtm_buscar_cliente', assistant, { cpf: '04614446159' })
run_test('loja_por_cidade Sinop/fabrica', 'mtm_loja_por_cidade', assistant, { cidade: 'Sinop', departamento: 'fabrica' })
run_test('loja_por_cidade Cuiabá/atacadao', 'mtm_loja_por_cidade', assistant, { cidade: 'Cuiabá', departamento: 'atacadao' })
run_test('listar_clinicas', 'mtm_listar_clinicas', assistant, {})

puts
puts '=== TOOLS DA CONTA 1 ==='
Captain::CustomTool.where(account_id: 1).order(:id).each { |t| puts "  #{t.slug} | #{t.http_method} | enabled=#{t.enabled}" }
puts 'FIM.'
