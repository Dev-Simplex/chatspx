# Tools do Captain (Agentes IA)

Este diretório é a **definição** das tools que os Agentes IA podem chamar: o que a tool faz, para
onde ela vai, que parâmetros aceita. Tudo aqui é código, viaja no deploy e existe igual em todas as
VMs e para todas as contas.

O que **não** mora aqui: a credencial de cada conta, quais agentes usam a tool e o liga/desliga.
Isso é configuração, fica no banco de cada conta e não viaja no deploy. Ler a seção
[Credencial nunca vai no código](#credencial-nunca-vai-no-código) antes de qualquer coisa.

## Como criar uma tool

São dois passos, e o segundo é o que as pessoas esquecem.

1. **A classe**, em `enterprise/lib/captain/tools/<id>_tool.rb`, herdando de
   `Captain::Tools::BasePublicTool`:

   ```ruby
   class Captain::Tools::RegistrarAssuntoTool < Captain::Tools::BasePublicTool
     description 'Registra um assunto identificado na conversa...'   # isto o LLM lê
     param :assunto, type: 'string', desc: '...', required: true

     def perform(tool_context, assunto:)
       conversation = find_conversation(tool_context&.state)
       ...
     end
   end
   ```

   `BasePublicTool` já te dá `find_conversation` / `find_contact` (escopados na conta do
   assistente), `log_tool_usage`, o trace de chamadas e os helpers de credencial por conta de
   `concerns/integration_credentials.rb`. O retorno do `perform` é texto que volta pro LLM: erro
   também é texto, não exceção, senão o agente trava no meio do atendimento.

2. **O registro**, em `config/agents/tools.yml`, com `id`, `title`, `description` e `icon`:

   ```yaml
   - id: registrar_assunto
     title: 'Registrar Assunto'
     description: 'Registra um assunto/tarefa identificado na conversa...'
     icon: 'task'
   ```

**Sem esse registro a tool NÃO EXISTE.** Não aparece na tela de Agentes IA, não entra em
`available_agent_tools` e nenhum agente consegue armá-la, por mais correta que a classe esteja. O
YAML é a única lista de tools de código do sistema.

## A armadilha do plural

O id vira nome de classe por `camelize` (`Captain::Assistant.tool_class_name`, do concern
`Concerns::CaptainToolsHelpers`):
`buscar_unidades` procura `Captain::Tools::BuscarUnidadesTool` em `buscar_unidades_tool.rb`. Regra
única: **id, nome do arquivo e nome da classe iguais palavra por palavra, plural incluído.**

Até agosto de 2026 esse método usava `classify`, que singulariza a última palavra. O estrago foi
real e ficou meses de pé:

* `apresentar_imoveis` procurava `ApresentarImoveiTool`, que não existe.
* `listar_pecas` procurava `ListarPecaTool`, que não existe.
* `load_agent_tools` descartava as duas com um `Rails.logger.warn` e seguia em frente. O YAML
  listava 29 tools, a tela mostrava 27, e ninguém percebeu a diferença.
* `buscar_unidades` só funcionava porque alguém batizou a classe no singular para contornar o bug,
  com um comentário explicando o contorno em vez de corrigir a causa.

E o detalhe que mais importa aqui: `spec/enterprise/lib/captain/tools/apresentar_imoveis_tool_spec.rb`
**passava verde** o tempo todo. Ele instancia a classe pela constante e nunca passa pelo registro,
então testava uma tool morta com sucesso. Testar a classe não é testar que a tool existe para o
agente. Quem testa isso é `spec/enterprise/models/concerns/captain_tools_registry_spec.rb`.

Hoje um id que não resolve levanta `Concerns::CaptainToolsHelpers::UnresolvableToolError` em test e
development. Em produção continua sendo log de erro, porque derrubar o boot por causa de uma tool
seria pior que a tool faltar.

## Tool nova só aparece depois do restart

`built_in_agent_tools` e `built_in_tool_ids` são memoizados em variável de classe
(`@built_in_agent_tools ||= load_agent_tools`). O YAML é lido **uma vez por processo**.

Ou seja: criou a tool, registrou no YAML, e a tela continua sem ela? Reinicie o processo (`rails s`,
`overmind restart`, ou o serviço na VM). Isso já confundiu gente que ficou caçando erro de
digitação num arquivo que estava certo. Vale para renomear e para remover também.

## Credencial nunca vai no código

**Nenhum arquivo deste diretório, e nenhum arquivo de `config/agents/`, pode conter token, bearer,
api_key, secret ou senha literal.** Não é preferência de estilo, é o modelo de isolamento entre
contas.

As tools `mtm_*` da conta 1 (Fábrica dos Óculos) chamam a API daquele cliente com `auth_type=bearer`
e um token guardado em `captain_custom_tools.auth_config`, por conta, no banco daquela VM. Esse
token é o **único portão** entre uma conta e a API de outra: se alguém habilitar
`mtm_agendar_visita` num agente da Tozi, a chamada sai sem token e morre na autenticação do outro
lado. É assim que tem que ser.

No dia em que alguém "simplificar" e escrever o bearer da Fábrica num arquivo de definição, esse
arquivo desce no deploy para todas as VMs e **toda conta passa a falar com a API da Fábrica com a
credencial da Fábrica**. Não existe correção rápida depois: o segredo já está no histórico do git e
já está em disco em todas as máquinas.

Onde a credencial deve ficar:

| Tipo de tool | Onde mora a credencial | Quem lê |
|---|---|---|
| Criada pela tela (`captain_custom_tools`, por conta) | `auth_config` (jsonb) com `auth_type` `bearer` / `basic` / `api_key` | `@custom_tool.build_auth_headers` / `build_basic_auth_credentials`, em runtime, dentro do `HttpTool` |
| De código (este diretório) | `integration_setting('vista', 'vista_api_key')`, atributo customizado da conta, ou ENV da VM | os helpers de `concerns/integration_credentials.rb` |

Código que **lê** credencial é legítimo e passa no guardrail: `@custom_tool.build_auth_headers`,
`{ 'Authorization' => "Bearer #{auth_config['token']}" }`, `ENV['TOZI_VISTA_API_KEY']`,
`query: { key: vista_api_key }`. O que não passa é o valor escrito à mão.

## `available_agent_tools` não filtra por conta

`Captain::Assistant#available_agent_tools` devolve **todas** as tools de código do YAML, mais as
custom tools daquela conta. As de código não têm dono: qualquer conta enxerga qualquer uma delas na
tela.

Quem limita de verdade é:

1. **A credencial**, do jeito descrito acima: sem o token daquela conta, a chamada não passa da
   autenticação do outro lado.
2. **A escolha por agente**, em `assistant.config['tools']`, a lista de ids que aquele agente arma
   (`configured_agent_tools`). Tool que não está nessa lista nunca entra no toolset.

Então não escreva uma tool assumindo "só o cliente X vai ver isso". Todo mundo vê. Escreva assumindo
que ela vai ser chamada pela conta errada um dia, e faça a credencial ausente ser a resposta.

## O que quebra se você violar as regras acima

Dois specs, e é de propósito que eles sejam chatos:

* `spec/enterprise/models/concerns/captain_tools_registry_spec.rb`: todo id do YAML resolve para uma
  classe que existe, o registro entrega ao front exatamente o que foi declarado, sem descarte
  silencioso, e os ids no plural continuam resolvendo.
* `spec/enterprise/lib/captain/tools/no_hardcoded_credentials_spec.rb`: varre este diretório e
  `config/agents/*.yml` atrás de credencial literal. Não carrega Rails, roda em menos de um segundo,
  e a mensagem de falha diz o arquivo, a linha e por quê. Ele **não tem lista de exceção**: se o seu
  valor legítimo tem cara de segredo, renomeie a chave ou tire o literal do código.
