require 'spec_helper'
require 'pathname'

# Guardrail: arquivo de DEFINIÇÃO de tool nunca carrega credencial.
#
# A definição de uma tool (o que ela faz, endpoint, método, schema de parâmetros) mora em código e
# viaja no deploy: o mesmo arquivo existe em TODAS as VMs e vale para TODAS as contas. A credencial
# não viaja: ela é por conta e mora no banco (`captain_custom_tools.auth_config`) ou, nas tools de
# código, em `integration_setting` / atributo da conta / ENV daquela VM.
#
# Esse token é o único portão entre uma conta e a API de outra. As 11 tools `mtm_*` da conta 1
# (Fábrica dos Óculos) só funcionam porque o bearer daquela conta está no banco daquela VM: se
# alguém habilitar `mtm_agendar_visita` num agente da Tozi, a chamada sai sem token e morre na
# autenticação do outro lado. No dia em que alguém "simplificar" e escrever esse bearer num arquivo
# de definição, o portão deixa de existir e TODA conta passa a falar com a API da Fábrica com a
# credencial da Fábrica. É esse commit que este spec tem que barrar.
#
# O scanner é textual de propósito: não carrega o Rails, não instancia tool nenhuma e não toca no
# banco, então roda em qualquer máquina e em qualquer branch, antes de qualquer boot.
module CaptainToolsCredentialGuardrail
  REPO_ROOT = Pathname.new(File.expand_path('../../../../..', __dir__))

  # O conjunto que viaja no deploy. É só isso que o guardrail precisa cobrir: o que está no banco
  # é por conta e não aparece aqui.
  SCANNED_GLOBS = [
    'enterprise/lib/captain/tools/**/*.rb',
    'config/agents/*.yml'
  ].freeze

  # Chaves que carregam credencial. `key` sozinho fica FORA de propósito: é nome de parâmetro
  # legítimo em toda tool da Vista (`query: { key: vista_api_key }`) e só daria falso positivo.
  CREDENTIAL_KEY = /
    (?: auth_?token | access_?token | refresh_?token | client_?secret | private_?key |
        api[_-]?key | apikey | authorization | bearer | token | secret | password | passwd | senha )
  /xi

  # Chave de credencial recebendo string literal: `TOKEN = 'abc'`, `api_key: "abc"`,
  # `'Authorization' => "abc"`, `auth_config['token'] = "abc"`.
  # Valor que vem de método, de ENV ou de interpolação não casa aqui: não há aspas depois do `=`.
  LITERAL_ASSIGNMENT = /(#{CREDENTIAL_KEY})["'\]]*\s*(?:=>|=|:)\s*(['"])([^'"]*)\2/

  # Mesma coisa em YAML, onde o valor costuma vir sem aspas: `token: abc123`.
  YAML_ASSIGNMENT = /(#{CREDENTIAL_KEY})\s*:\s*([^\s'"#]+)\s*$/

  # Valores que são rótulo, e não segredo: nome de auth_type, tipo de schema, placeholder de doc.
  PLACEHOLDER_VALUE = /
    \A(?: none | bearer | basic | header | query | string | object | integer | boolean | number | array | null |
          true | false | nil | x+ | fake | dummy | changeme | placeholder | redacted | example | seu_token |
          <[^>]*> | \{\{.*\}\} | \*+ )\z
  /xi

  # Formatos que já são segredo por si so, esteja onde estiver o valor.
  ANCHORED_SECRET_SHAPES = {
    'chave de API com prefixo conhecido (sk-, sk_live_, ghp_, xoxb-, AIza, AKIA)' =>
      /\A(?:sk-|sk_live_|pk_live_|rk_live_|ghp_|gho_|github_pat_|xox[abprs]-|AIza|AKIA)[A-Za-z0-9_\-]{12,}/,
    'JWT' => /\Aey[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\./,
    'blob hexadecimal longo (cara de chave gerada)' => /\A[A-Fa-f0-9]{32,}\z/,
    'blob base64 longo (cara de chave gerada)' =>
      %r{\A(?=[A-Za-z0-9+/]*[0-9])(?=[A-Za-z0-9+/]*[A-Za-z])[A-Za-z0-9+/]{40,}={0,2}\z}
  }.freeze

  # Formatos reconhecidos no meio da linha. `"Bearer #{...}"` não casa: interpolação não entra na
  # classe de caracteres, que é exatamente o código legítimo que lê a credencial do banco.
  INLINE_SECRET_SHAPES = {
    'header Authorization com o token escrito à mão' => /Bearer\s+[A-Za-z0-9._\-]{16,}/
  }.freeze

  module_function

  def files
    SCANNED_GLOBS.flat_map { |glob| Dir[REPO_ROOT.join(glob).to_s] }.sort
  end

  # @return [Array<Hash>] uma entrada por linha reprovada: :file, :line, :reason, :source
  def offenses
    files.flat_map do |path|
      relative = Pathname.new(path).relative_path_from(REPO_ROOT).to_s
      yaml = path.end_with?('.yml', '.yaml')

      File.readlines(path, chomp: true).each_with_index.filter_map do |line, index|
        reason = scan_line(line, yaml: yaml)
        reason && { file: relative, line: index + 1, reason: reason, source: line.strip }
      end
    end
  end

  # Devolve o motivo da reprovação, ou nil se a linha está limpa.
  # Linha 100% comentário passa: documentar como a credencial funciona e o comportamento desejado.
  def scan_line(line, yaml: false)
    return nil if line.strip.start_with?('#')

    literal_assignment_reason(line) ||
      (yaml ? yaml_assignment_reason(line) : nil) ||
      shape_reason(line)
  end

  def literal_assignment_reason(line)
    match = LITERAL_ASSIGNMENT.match(line)
    return nil unless match
    return nil unless secret_value?(match[3])

    "chave `#{match[1]}` recebendo credencial literal no código (#{mask(match[3])})"
  end

  def yaml_assignment_reason(line)
    match = YAML_ASSIGNMENT.match(line)
    return nil unless match
    return nil unless secret_value?(match[2])

    "chave `#{match[1]}` com credencial literal no YAML (#{mask(match[2])})"
  end

  def shape_reason(line)
    inline = INLINE_SECRET_SHAPES.find { |_reason, pattern| pattern.match?(line) }
    return "valor com cara de segredo: #{inline.first}" if inline

    candidates(line).filter_map { |candidate| anchored_shape_reason(candidate) }.first
  end

  # Valores isolados da linha: strings entre aspas e também tokens soltos, que é como o valor
  # aparece em YAML.
  def candidates(line)
    quoted = line.scan(/'([^']*)'|"([^"]*)"/).flatten.compact
    bare = line.split(/[\s,;:()\[\]{}=>]+/).map { |token| token.delete(%q('")) }
    (quoted + bare).reject(&:empty?)
  end

  def anchored_shape_reason(value)
    return nil if value.include?('#{')

    shape = ANCHORED_SECRET_SHAPES.find { |_reason, pattern| pattern.match?(value) }
    shape && "valor com cara de segredo: #{shape.first}"
  end

  def secret_value?(value)
    # interpolação: o valor real vem de fora do código, e não está escrito aqui
    return false if value.include?('#{') || value.strip.empty?
    return true if anchored_shape_reason(value)
    return false if PLACEHOLDER_VALUE.match?(value)
    return false if value.match?(/\s/) # frase de documentação, não credencial

    value.length >= 8
  end

  # Nunca imprime o segredo inteiro: o log do CI é público dentro da empresa.
  def mask(value)
    "#{value[0, 3]}… #{value.length} chars"
  end

  def failure_message(offenses)
    detail = offenses.map { |o| "  #{o[:file]}:#{o[:line]}\n    #{o[:reason]}\n    > #{o[:source]}" }.join("\n\n")

    <<~MESSAGE
      Credencial literal em arquivo de definição de tool (#{offenses.size}):

      #{detail}

      Por que isso é proibido: arquivo de definição de tool viaja no deploy e vale para TODAS as
      contas de TODAS as VMs. Credencial é por conta. Um bearer escrito aqui derruba o único portão
      que impede a conta A de chamar a API da conta B.

      Onde a credencial deve ficar:
        - tool criada pela tela  -> captain_custom_tools.auth_config (auth_type bearer/basic/api_key),
                                    lida em runtime por `@custom_tool.build_auth_headers`;
        - tool de código         -> `integration_setting(...)` / atributo customizado da conta /
                                    ENV daquela VM (ver enterprise/lib/captain/tools/concerns/integration_credentials.rb).

      Se o valor acima não é credencial de verdade, ele ainda tem cara de credencial: renomeie a
      chave ou tire o literal daqui. O guardrail não tem lista de exceção de propósito.
    MESSAGE
  end
end

RSpec.describe 'Guardrail: credencial nunca vai no código da tool', type: :model do
  it 'não encontra credencial literal em nenhum arquivo de definição de tool' do
    offenses = CaptainToolsCredentialGuardrail.offenses

    expect(offenses).to be_empty, -> { CaptainToolsCredentialGuardrail.failure_message(offenses) }
  end

  it 'esta varrendo arquivos de verdade (guardrail que não le nada não protege ninguem)' do
    files = CaptainToolsCredentialGuardrail.files

    expect(files.size).to be >= 20
    expect(files).to include(a_string_ending_with('enterprise/lib/captain/tools/http_tool.rb'))
    expect(files).to include(a_string_ending_with('config/agents/tools.yml'))
  end

  # Os dois blocos abaixo são o teste do teste: sem eles, uma regex quebrada viraria um guardrail
  # verde que não barra nada. Valores obviamente falsos, nenhum é credencial de verdade.
  describe 'reprova' do
    {
      'bearer hardcoded numa constante' => %(  FABRICA_TOKEN = 'zzzfakebearer0000111122223333'),
      'api_key hardcoded num hash de opcoes' => %(  api_key: 'zzzfake0000111122223333abcd',),
      'header Authorization montado com o token dentro' => %(  headers['Authorization'] = 'Bearer zzzfake0000111122223333'),
      'chave com prefixo de provedor' => %(  OPENAI = 'sk-zzzfake0000111122223333abcd'),
      'senha em string literal' => %(  password = 'trocaessasenha123'),
      'valor de credencial solto em YAML' => %(  token: zzzfake0000111122223333abcd)
    }.each do |case_name, line|
      it case_name do
        expect(CaptainToolsCredentialGuardrail.scan_line(line, yaml: true)).not_to be_nil
      end
    end
  end

  describe 'deixa passar' do
    {
      'código que le a credencial do banco' => %(    headers = @custom_tool.build_auth_headers),
      'header montado por interpolação' => %q(      { 'Authorization' => "Bearer #{auth_config['token']}" }), # rubocop:disable Lint/InterpolationCheck
      'credencial vinda de integration_setting' => %(        integration_setting('vista', 'vista_api_key') ||),
      'credencial vinda de ENV' => %(          ENV['TOZI_VISTA_API_KEY'].to_s),
      'nome de parametro num schema de tool' => %(      properties: { api_key: { type: 'string' } }),
      'nome de parametro passado adiante' => %(      query: { key: vista_api_key, showtotal: 1 }),
      'token gerado em runtime' => %(    token = SecureRandom.hex(8)),
      'rótulo de auth_type' => %(  auth_type: 'bearer'),
      'comentário explicando a regra' => %(  # o token de cada conta fica em auth_config['token'], nunca aqui),
      'texto em portugues numa descricao' => %(  description: 'Envia ao cliente o material de apoio pelo id')
    }.each do |case_name, line|
      it case_name do
        expect(CaptainToolsCredentialGuardrail.scan_line(line, yaml: true)).to be_nil
      end
    end
  end
end
