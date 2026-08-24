# Triagem da suíte — 21/08

Recorte do redesenho do chat de site, branch `homologacao`. Tudo local: **nada foi pushado**.

## Números (medidos, não estimados)

| momento | exemplos | falhas |
|---|---|---|
| `origin/homologacao` (base) | 8.928 | 399 |
| início da triagem | 10.067 | 382 |
| meio (checkpoint) | 10.068 | 285 |
| checkpoint | 10.070 | 102 |
| checkpoint | 10.070 | 62 |
| checkpoint | 10.070 | 19 |
| **fim** | **10.070** | **17** |

O recorte acrescenta **+1.142 exemplos** à suíte. Medição por 6 grupos em paralelo, cada um
com banco dedicado.

As **17 falhas finais são todas escaladas** — nenhuma é minha para decidir (última seção).

Duas outras eu havia classificado como "instáveis por natureza". **Estavam erradas essa
classificação e eu.** Cada uma tinha causa determinável, e uma delas escondia um buraco bem
maior que o teste que a revelou — ver a seção seguinte.

## "Teste instável" era diagnóstico preguiçoso — três vezes

Nenhuma das duas falhas restantes era instável. Chamar de flaky é a saída fácil, e ela custou
caro: uma delas escondia um defeito de infraestrutura que apagava a cobertura de **toda**
invariante de exclusão mútua via Redis.

**1. O dublê de Redis não era compartilhado entre as conexões do pool.**
`ConnectionPool.new(size: 15) { MockRedis.new }` roda o bloco **uma vez por conexão**. Em
produção as 15 conexões falam com o mesmo servidor; em teste havia até 15 armazenamentos
independentes. Medido antes do conserto:

| sonda | antes | depois |
|---|---|---|
| sequencial (mesma conexão reusada) | 1 instância | 1 instância |
| concorrente (5 threads) | **5 instâncias distintas** | 1 armazenamento |
| `SET NX` em duas conexões | **`true` e `true`** | `true` e `false` |

`SET NX` devolvendo `true` para as duas: **a trava não travava**. É o mesmo "verde por ausência
de sujeito", agora na infraestrutura — o dublê nunca reproduzia a contenção que a trava existe
para resolver. Spec sequencial não muda em nada (o pool já devolvia a mesma conexão).

**2. `Current` vazava de um exemplo para o outro.** O executor do Rails reseta
`CurrentAttributes` a cada requisição e a cada job; entre exemplos não reseta ninguém, e a
thread é a mesma. Código de produção que legitimamente seta `Current` vazava para o exemplo
seguinte, e `AssignmentHistoryService#classify` dá prioridade a `Current.executed_by` — então
uma atribuição manual era gravada como `automation`, sem autor. Hook `after` de um arquivo
protege os outros dele, não ele dos outros; e não roda se o exemplo anterior estourou no meio.

**3. `Faker::Config.locale = :en` valia só para a thread principal.** O getter do gem é
`Thread.current[:faker_config_locale] || I18n.locale`. Eu já tinha consertado isso uma vez — e
corrigi o **valor**, não o **fallback**. Em thread nova o Faker voltava a pt-BR, e como a
fábrica monta `email { display_name + "@uuid.com" }`, um nome com acento derrubava o
`create(:user)` dentro da thread. Intermitente porque só quebra quando o sorteio dá nome
acentuado: **passou 3 vezes seguidas e falhou 4 seguidas na mesma árvore** — eu li isso como
carga da máquina, e era o sorteio.

As três foram provadas por contraprova (removida a correção, o teste acusa; recolocada, passa).

## Ressalvas de método

Elas mudam a leitura dos números:

- rodar specs *enquanto* a medição corre a contamina. Um checkpoint chegou a marcar 16 falhas
  num grupo que, medido limpo, tem 6 — as 10 extras eram artefato da minha própria carga
  concorrente (specs de Flow, sensíveis a tempo). Passam 64/64 isolados;
- o número que decide deploy é o da medição **limpa**, com nada mais rodando;
- log de suíte tem validade: comparar o `mtime` do log com o da árvore antes de triar. Uma
  leva de 11 falhas era fantasma — o log era anterior a 449 arquivos alterados;
- **"passa isolado, falha no lote" não é sinônimo de instável.** Foi o que eu escrevi de duas
  falhas, e as duas tinham causa determinável. Vale gastar a hora antes de aceitar o rótulo.

## O que motivou

A suíte tinha 382 falhas. Falha em massa não distingue "defeito nosso" de "spec herdado
desatualizado", e enquanto não distingue, ninguém confia no vermelho — que é justamente
quando ele para de servir para alguma coisa.

## Defeitos de produção encontrados

Nenhum destes foi procurado. Todos apareceram porque um spec vermelho foi lido até o fim em
vez de ser adaptado até ficar verde. "Origem" diz se o defeito **entrou com o recorte** ou se
**já estava na base** (`origin/homologacao`) — os da base estão em produção hoje.

| # | Defeito | Efeito | Origem |
|---|---------|--------|--------|
| 1 | `resource :star` roteava para `stars#` (plural), classe é `StarController` | endpoint de favoritar mensagem **404 para todo mundo**, desde sempre | recorte |
| 2 | `push_diagnostics` e `platform_banners` nas rotas sem controller | **painel super_admin inteiro em 500** — a barra do Administrate vive no layout | recorte |
| 3 | `jsonb_set` sem criar o nó pai | configuração por usuário da conversa **nunca persistia** (pin/arquivar/silenciar/tema) | base |
| 4 | `ActionController::Parameters` contra `is_a?(Hash)` | mesmo endpoint respondia **422 para toda requisição válida** | base |
| 5 | `valid_token?(nil)` == `nil` | **verificação do webhook do Instagram passava sem token** | base |
| 6 | `redirect_to` sem `allow_other_host` | `GET /auth/sign_in` respondia **500** quando o domínio de acesso ≠ FRONTEND_URL | base |
| 7 | `Integrations::App#visible_properties` declarado em 3 pontas e **inexistente** na quarta | **credencial de integração vazava na API** — nada filtrava a serialização | recorte |
| 8 | `featurable.rb` de uma coluna contra `features.yml` de duas | **12 recursos entregues eram ingraváveis** — `RangeError`, não "desligado" | recorte |
| 9 | `Conversations::UnreadCounts::FilteredCountInvalidator` inexistente, chamado em `after_update_commit` incondicional | **gravar rótulo ou prioridade quebrava** em produção | recorte |
| 10 | `conversation_faq_generator` perdido no merge | geração de FAQ a partir de conversas **quebrada** | recorte |
| 11 | `captain_false_promise_harness_enabled` sem `store_accessor` | recurso **inligável** + uma exceção por resposta da IA indo pro GlitchTip | recorte |
| 12 | `AssistantActionClassifierService` passava `feature:` a um construtor que não aceita | classificador **não instanciava**; a resposta não chegava ao cliente | recorte |
| 13 | `Captain::Document#to_llm_metadata` nunca existiu | `NoMethodError` em toda geração de FAQ paginada (PDF) | recorte |
| 14 | serviço de captura ausente no caminho da IA | **toda** resposta da IA caía em handoff | recorte |
| 15 | caminho v2 do Captain levantava `ArgumentError` | **toda** resposta virava handoff | recorte |
| 16 | handoff devolvia `"Failed"` ao LLM; 7 de 13 features não salvavam o modelo | IA entregava erro como se fosse conteúdo | recorte |
| 17 | URL crua do visitante entrava no *system prompt* | dado de navegação do visitante ia para o provedor de LLM | recorte |
| 18 | `MESSAGE_UPDATED` disparado em duplicata | assinantes (ActionCable, webhooks) recebiam tudo duas vezes | recorte |
| 19 | apagar conversa levantava `NameError` | ação **impossível** pela API | recorte |
| 20 | rota de não-lidas sem controller + `with_lock` ausente | contador de não-lidas **404** e corrida na escrita | recorte |
| 21 | constante de evento ausente | invalidação do contador de não-lidas **nunca disparava** | recorte |
| 22 | `rescue` do Instagram apontava para constante inexistente | o `rescue` **nunca capturava** — erro subia cru | base |
| 23 | 5 parceiros de contrato ausentes no widget | `first_utm_source`/`gclid` **descartados em silêncio** na primeira mensagem | recorte |
| 24 | `*.png` no `.gitignore` engolindo asset de produto | ícone do `site_leads` **404** | base |
| 25 | grafia do locale não batia com o gem (`pt_BR` × `pt-BR`) | mensagens do Rails **não existiam em pt-BR** | base |
| 26 | 125 chaves i18n ausentes; arquivo `en` preenchido em português | texto faltando e idioma trocado na interface | recorte |
| 27 | setting aceito pela API e inexistente no modelo | gravação silenciosamente descartada | base |
| 28 | três assinaturas diferentes para o mesmo job | **"apagar notificações" estourava na fila** | base |
| 29 | `team_id: 0` em ação em massa | violava a *foreign key* e **derrubava a requisição** | base |
| 30 | `/conversations/filter` devolvia 3 contadores **nulos** | quebra aritmética em quem consome; o schema declara `integer` | base |
| 31 | `previous = existing.dup` no evento de reação | **500** ao trocar emoji; e remover reação não chegava ao tempo real | recorte |
| 32 | `captain_integration` em `premium_features.yml` | job **diário** desligava o Captain em **todas as contas** | base |
| 33 | 3 FKs para `teams` sem cascade nem associação | apagar time impossível — pelo modelo e pela API | base |
| 34 | `Llm::AccountScopedContext` é código morto | Captain **v2** usa a chave global, não a da conta (marcado `pending`) | base |

Os itens 3 e 4 estavam na **mesma feature**, em camadas diferentes — por isso cada spec
falhava por um motivo distinto e consertar um não acendia o outro. Os itens 14, 15 e 16
também se empilhavam: cada um sozinho já derrubava a resposta da IA inteira.

Fora da tabela, um defeito da **própria suíte**: ela travava num laço infinito do Rails
(`ActionView#find_offset`), exposto por `consider_all_requests_local = true` no `test.rb`.
Parecia deadlock e não era; capturado com watchdog sob carga.

## O padrão que mais apareceu

**Verde por ausência de sujeito.** Um teste que afirma ausência ("404", "não chamou", "não
gravou") passa tanto quando o código acertou quanto quando o sujeito nunca existiu.

- Dois specs do Instagram batiam numa rota inexistente, esperavam 404, recebiam o 404 da rota
  ausente e **nunca chegaram ao controller** — cobrindo exatamente o caminho com o furo de
  segurança.
- `it 'does not run the false promise harness when disabled'` passava porque o método
  **explodia** antes de instanciar o detector.
- Uma guarda de contrato Vuex passava **no vácuo em 7 dos 8 módulos**: media zero.

O segundo padrão mais comum tem nome próprio: **parceiro de contrato ausente**. Um arquivo
entra do upstream e a peça que fecha o contrato dele — constante, `store_accessor`, mutation,
controller, chave i18n — fica para trás. Sete dos defeitos acima são exatamente isso.

Ambos registrados no vault como lição permanente.

## Categorias das falhas herdadas

Não são defeitos — são divergências deliberadas nossas que ninguém propagou para os specs:

- **tradução** (a maior): conta nasce em pt-BR por decisão nossa; specs cravam o inglês.
  Conserto: ler a mesma chave i18n com `locale:` explícito;
- **spec que mede o ambiente**: cravava o valor de *fallback* de `FRONTEND_URL`, presumia que
  `MAILER_INBOUND_EMAIL_DOMAIN` não existe, ou dependia do fuso da instalação. Passavam só em
  máquina desconfigurada;
- **contrato desatualizado**: código passa `id`, spec espera o objeto; webhook ganhou
  assinatura, spec ficou com 2 argumentos;
- **feature não adotada**: spec do upstream trazido sem a implementação que o acompanha;
- **premissa torcida em vez de estabelecida**: o exemplo *esperava* que o ambiente estivesse
  num certo estado em vez de colocá-lo lá.

## Travas criadas

- `spec/routing/super_admin_routes_spec.rb` — toda rota do namespace tem controller.
  Provado que acusa: rota falsa inserida → falhou nomeando-a → removida → verde.
- `spec/support/mock_redis_eval.rb` — MockRedis não tem Lua; o dublê executa **só** scripts
  conhecidos e levanta em qualquer outro, para nunca aprovar Lua não implementado.
- `spec/support/faker_locale.rb` — fixa o Faker em `:en`. Sem isso o conserto de i18n fazia o
  Faker gerar nomes brasileiros e derrubar specs de relatório.
- `mutationContract.spec.js` — `commit` de mutation inexistente não levanta no Vuex, só
  `console.error`. Já custou o `utm`/`gclid`.
- `spec/support/current_attributes_reset.rb` — reseta `Current` **antes** de cada exemplo, o
  que fecha a classe inteira de dependência de ordem descrita acima.
- `config/initializers/01_redis.rb` — em teste, todas as conexões do pool passam a ver o
  **mesmo** armazenamento, para que `SET NX` volte a ser uma trava de verdade.

## Varreduras sistemáticas (e o que cada uma achou)

| varredura | universo | suspeitos | reais |
|---|---|---|---|
| constantes Ruby qualificadas que não resolvem | 1.639 | 25 | 7 |
| métodos/constantes perdidos vs. base | 126 arquivos | 5 | 1 |
| chamadas de método de classe sem definição | 314 pares | 0 | 0 |
| rotas sem controller | 17 | 17 | 2 fatais |

O detector de método sem definição foi **provado escondendo um método conhecido** — sem essa
prova, "0 reais" é indistinguível de detector quebrado.

Uma limitação medida: varredura por **presença** de método é cega para **estreitamento de
assinatura**. `activity_message_params` continuou existindo e mudou de aridade — nenhuma
varredura de presença pegaria.

## O que fica pendente (não é meu para decidir)

- **`change_set_applier` (14 falhas)** — feature de change-sets do Paulo. Código e spec
  idênticos à base; o spec exercita operações que `SUPPORTED_OPERATIONS` nunca teve.
- **`Integrations::Cloudflare::RealtimeKitCredentialsValidator`** — a classe não existe, as
  chaves i18n existem. Precisa de chamada a API externa e de decisão de produto.
- **16 grupos de rota sem controller** — inertes (nenhuma é chamada pelo front), mas podem
  ser lugar reservado para trabalho de outra pessoa. Apagar rota alheia não é minha decisão.
- **`toggle_status` não solta o dono-robô** — nosso próprio spec diz que deveria; a regra de
  quem pode ser solto é desenho documentado (espelho captain, gate D1). Decisão do dono.
- **`update_last_seen` não marca notificação como lida** — `update_columns` pula callbacks
  na base e na nossa árvore; o comportamento não existe em lado nenhum.

## Observações registradas (não corrigidas)

- O payload de digitação reporta um agente-robô como `type: 'user'`.
- E-mail de notificação do Chatwoot entregue numa caixa de e-mail vira conversa — não há
  proteção de laço por cabeçalho.
- O widget **não consulta o locale da conta**: `switch_locale` vai por query string, usuário,
  domínio custom, `ENV['DEFAULT_LOCALE']` e cai em `I18n.default_locale`. A forma é do
  upstream; o que mudou para nós foi o valor do fallback (pt_BR). Uma conta `en` responde em
  pt-BR se o SDK não mandar `locale`.
