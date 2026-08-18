# I2 — Backend / Guards: parar de tratar grupo como se fosse uma pessoa

> Worker I2 · 27/07/2026 · VM 192.168.8.232 (homologação) · branch `homologacao`
> Nada commitado — tudo no working tree, como manda o briefing.

---

## 1. Resumo

Instalei os freios que faltavam para conversa de grupo de WhatsApp. Todos perguntam ao contrato
**C1 (`Conversation#group?`)** — a heurística de `@g.us` não foi reimplementada em lugar nenhum, e
a que existia duplicada no router do Captain foi **removida** em favor da delegação.

| # | Guard | Situação antes | Depois |
|---|---|---|---|
| 1 | CSAT | disparava em grupo (**15 pesquisas** já enviadas) | não dispara |
| 2 | NPS automático | disparava em grupo (**2 NpsResponse**) | não dispara (manual segue permitido) |
| 3 | Greeting / fora-de-horário / coleta de e-mail | disparavam em grupo (**9 mensagens**) | não disparam |
| 4 | Captain (IA) | `skip_groups` config-gated e **desligado por padrão** | padrão seguro; config explícita preservada |
| 5 | Formatter de LLM | 5.313 mensagens entregues ao modelo com ruído e todas como "User:" | autor nomeado + texto limpo |
| 6 | Automações / webhooks | — | **deliberadamente NÃO bloqueado** (§5) |

---

## 2. O que mudou (arquivo:linha)

### 2.1 CSAT — `app/services/csat_survey_service.rb:26-33`

`#conversation_allows_csat?` ganhou `&& !conversation.group?`.

Confirmei que este é o ponto de entrada REAL antes de mexer: `CsatSurveyService` é o chokepoint dos
**dois** caminhos que existem hoje — `CsatSurveyListener#conversation_status_changed` (resolução) e
`Flows::ActionService#send_csat` (`action_service.rb:270`, ação de automação). Guardar aqui cobre os
dois; guardar no listener cobriria só um. (A linha 26 apontada no relatório continua correta.)

### 2.2 NPS — `app/listeners/nps_survey_listener.rb:2-8, 44-60`

Extraí a elegibilidade do disparo automático para `#auto_nps_eligible?` (o método do evento estourou
a complexidade ciclomática do rubocop ao ganhar mais um `return`) e somei `return false if
conversation.group?`. A ordem das outras checagens é idêntica à de antes.

**Decisão consciente:** o disparo **manual** (`nps_responses_controller.rb:64`, agente clicando
"enviar NPS") **continua permitido**. É ação deliberada de humano; barrá-la em silêncio, sem
mensagem na tela, seria pior que o bug — e a tela é território do I4/I5. Fica como proposta.

### 2.3 Greeting / OOO / coleta de e-mail — `app/services/message_templates/hook_execution_service.rb`

- `#group_conversation?` novo (linha 69), delegando a `conversation.group?`.
- `#should_send_greeting?` (linha 53), `#should_send_email_collect?` (linha 81) e
  `#out_of_office_context_allows?` (linha 39, extraído de `#should_send_out_of_office_message?` pelo
  mesmo motivo de complexidade) barram grupo.

**Argumento da decisão (o briefing pediu para argumentar, não só aplicar):** essas três mensagens são
dirigidas a *uma* pessoa que acabou de chamar. Num grupo de trabalho de N integrantes elas viram
ruído para todo mundo, e o gatilho é a mensagem de **qualquer** participante — o bot fala sozinho no
meio da conversa alheia. Não é hipótese: a conv 12 (grupo "Sentinela Monitoramento") recebeu o texto
de fora-de-horário **duas vezes no mesmo dia**.

A coleta de e-mail é redundante (só roda em web widget, que nunca é grupo), mas mantive o guard por
uniformidade: se outro canal ganhar semântica de grupo, não abre buraco novo. Custo zero, risco zero.

### 2.4 Vazamento do fora-de-horário pelo Captain — `app/services/message_templates/template/out_of_office.rb:4-15`

**Achado não previsto na task.** `MessageTemplates::Template::OutOfOffice.perform_if_applicable` é um
segundo portão, usado por **4 chamadores** do Captain que não passam pelo `HookExecutionService`:

```
enterprise/app/services/captain/conversation/human_handoff_service.rb:69
enterprise/app/services/enterprise/message_templates/hook_execution_service.rb:229
enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb:271
enterprise/app/jobs/captain/conversation/response_builder_job.rb:270
```

Sem freio ali, o guard 2.3 seria furado pelo handoff da IA. Adicionei `return if
conversation.group?` no gate. **Este arquivo não estava na minha lista de propriedade** — não é de
nenhum outro worker (I1 = ingestão/`app/services/whatsapp/`, I4/I5 = front), mas registro aqui para
o coordenador conferir.

### 2.5 Captain — `enterprise/app/services/captain/behavior/router_service.rb`

- `SKIP_GROUPS_DEFAULT = true` (linha 2).
- `#skip_groups_enabled?` (linha 39) resolve a config **tri-estado**: ausente/vazia → default seguro;
  presente → valor do usuário (aceita boolean *e* string, porque `behavior` é JSON editado por tela e
  por API — `'false'` desliga, `'true'` liga).
- `#conversation_is_group?` (linha 51) agora é **só** `@conversation.group?`. As 12 linhas de
  heurística duplicada saíram, e o comentário obsoleto sobre `@g.us` foi substituído.

**Preservação de quem já configurou:** só a *ausência* da chave cai no default. Quem gravou `false`
de propósito (a conta que quer a IA dentro do grupo) continua com a IA respondendo. Há spec para
`false`, `'false'`, `true`, `'true'` e ausente.

Impacto medido nesta base: dos 8 assistants, **6 já tinham `skip_groups: true` explícito** e 2 não
tinham a chave — **Helena (#16) e Lia (#17)**, exatamente as que hoje podiam responder dentro de
grupo. São essas duas que a mudança protege; as outras 6 não mudam de comportamento.

### 2.6 Formatter de LLM — `app/services/llm_formatter/conversation_llm_formatter.rb`

Em conversa de grupo (e **só** nela):

1. **Cabeçalho novo** (`#group_header`, linha 105):
   `Conversation type: WhatsApp group — "Sentinela Monitoramento" (12 participantes). Messages come
   from DIFFERENT participants, not from a single customer.`
   O título sai limpo (sufixos `(GROUP)`/`(Group)`/`(Grupo)` removidos) e a contagem só aparece se o
   snapshot **C3** existir (defensivo — o W3 ainda não gravou nada).
   *Extrapolação assumida:* a task pedia só o transcript. Achei que dizer ao modelo, em uma linha,
   que não há um cliente do outro lado é o coração do "parar de tratar grupo como pessoa", e o custo
   é uma linha de prompt. Se o coordenador discordar, é um `return` a menos.
2. **Transcript por participante** (`#format_message`, linha 84): `"<Nome>: <texto>"`.
   Fonte, em ordem: `content_attributes['group_sender']['name']` (**contrato C2**) → prefixo no
   próprio texto → **rótulo genérico de sempre** (`User`). Nunca inventa nome.
   Só mensagem de **Contact** ganha nome: outgoing continua `Support Agent`/`Bot`, que não são
   integrantes do grupo.
3. **Limpeza do texto**: o token `(<lid>@lid)` é removido de onde quer que apareça, não só do prefixo.

**Leitura DEFENSIVA, como pedido:** funciona com e sem `group_sender`. No momento da medição o
campo existia em **0 mensagens** (o I1 ainda não tinha landado), então todo o ganho medido vem do
parser de legado. O caminho C2 está implementado e coberto por spec, mas **não foi exercitado
contra dado real** — vale revalidar depois que a ingestão do I1 gravar as primeiras mensagens.

---

## 3. O parser de legado (e o que ficou pendente)

Descobri no banco que existem **duas** gerações de prefixo em conversa de grupo, e a que o helper de
front **C4** trata é a *minoritária*:

| Formato | Origem | Mensagens de grupo |
|---|---|---|
| `👥 *Nome (229480102662169@lid)*` | app Chatwoot da WAHA (dez/2025+) | **513** |
| `**+55 (66) 9683-6077 - Sentinela:**` | Evolution API (até ago/2025) | **4.800** |
| sem prefixo | — | 4.467 |

O lado Ruby cobre os **dois**:

- **Formato `👥`** — o I1 landou `app/services/whatsapp/group_sender_extractor.rb` no meio da minha
  execução, então **passei a delegar para ele** (`Whatsapp::GroupSenderExtractor.call`) em vez de
  manter o regex duplicado que eu tinha escrito. É o mesmo serviço que a ingestão usa para gravar o
  C2 — um segundo parser para o mesmo prefixo divergiria com o tempo. Revalidei contra dado real
  depois da troca: saída idêntica.
  *Divergência deliberada mantida:* o extrator do I1 nunca altera o corpo além do prefixo (é dado do
  cliente, tem que ficar íntegro); o formatter aplica por cima um `gsub` que tira `(<lid>@lid)` solto
  do meio da frase, porque ali o destino é um prompt e o identificador só gasta token.
- **Formato fóssil** — `FOSSIL_GROUP_PREFIX`, local no formatter. O extrator do I1 **não** cobre esse
  formato. Exige `\d\d` no rótulo como discriminador, para não casar um negrito legítimo
  (`**Resumo:**`) — há spec para esse falso-positivo.

### ⚠️ Ação para o coordenador (não executei — arquivo do C4)

`app/javascript/dashboard/helper/whatsappGroupHelper.js#parseLegacyGroupContent` trata **só** o
formato `👥`. As **4.800** mensagens do formato fóssil vão continuar aparecendo cruas na bolha para
o I4/I5. Não editei o arquivo (o briefing manda avisar em vez de editar). A regra equivalente em JS
seria algo como `/^\*\*((?=[^\n]*\d\d)[^\n]{1,100}?):\*\*\n{1,2}/`, com o nome depois do último
` - `. **Decida você** se o C4 é estendido — deixei o Ruby completo de propósito, porque é o lado
que alimenta o classificador.

### Pendência declarada

Unificação do formato `👥`: **feita** (delegação acima). Não criei nada em
`app/services/whatsapp/` — esse diretório continua sendo do I1.

**Fica pendente:** o formato fóssil não está no serviço do I1 nem no helper C4. Se o coordenador
quiser um ponto único de verdade para os dois formatos, o lugar natural é
`Whatsapp::GroupSenderExtractor` — mas isso é edição em arquivo do I1, então não fiz.
Consequência de manter como está: o **acoplamento** do formatter ao serviço do I1 (se ele mudar o
shape do `Result`, meu spec quebra e avisa).

---

## 4. Consumidores de LLM que ficaram de FORA (proposta)

O guard 2.6 cobre o `ConversationLlmFormatter`. Outros três caminhos leem `message.content_for_llm`
cru e continuam recebendo o prefixo com o LID — **não são meus arquivos**, não toquei:

- `lib/captain/base_task_service.rb:136`
- `lib/captain/sentiment_analysis_service.rb:28`
- `enterprise/lib/captain/conversation_eval_service.rb:140`

Proposta: quando o extrator do I1 existir, o lugar certo do saneamento passa a ser
`Message#content_for_llm` (`app/models/message.rb:285`) — resolve os quatro de uma vez.

---

## 5. Automações e webhooks — decisão de NÃO bloquear

A task pediu para ser conservador aqui, e o dado confirma que é o certo:

- **17 mensagens** dentro de conversas de grupo carregam `automation_rule_id` ou `flow_id`, ou seja,
  **automação já está sendo usada de propósito em grupo** nesta base. As contas 3 e 5 têm 7
  `automation_rules` ativas.
- **0 webhooks** configurados nas contas que têm grupo — bloquear seria mexer em algo com impacto
  medido zero e risco não-zero.

**Não alterei `app/listeners/automation_rule_listener.rb`** (arquivo meu, deixado intacto).

Risco que registro para o coordenador, sem aplicar: uma regra do tipo *"ao criar conversa → atribuir
ao time X"* ou *"ao receber mensagem → responder Y"* dispara em grupo a cada fala de qualquer
integrante. Se algum cliente reclamar de automação barulhenta em grupo, a solução correta **não** é
um bloqueio global — é expor `is_group` como **condição de filtro** na tela de automação (o
`ConditionsFilterService` já suporta atributos de conversa), deixando a escolha com a conta.
Bloquear automação que alguém usa é pior que o bug.

---

## 6. Como testei

### 6.1 Estático

```
bundle exec rubocop <6 arquivos de código + 6 de spec>   →  12 files inspected, no offenses detected
```

### 6.2 Specs

```
bundle exec rspec spec/services/csat_survey_service_spec.rb \
  spec/listeners/csat_survey_listener_spec.rb spec/listeners/nps_survey_listener_spec.rb \
  spec/builders/csat_surveys spec/builders/nps_surveys spec/services/message_templates \
  spec/enterprise/services/enterprise/message_templates/hook_execution_service_spec.rb \
  spec/enterprise/services/captain/behavior/router_service_spec.rb spec/services/llm_formatter

→ 170 examples, 3 failures
```

**As 3 falhas são PRÉ-EXISTENTES.** Provei trocando os meus arquivos pela versão do `HEAD` e
rodando os mesmos exemplos — falham igual:

| Exemplo | Causa | Falha no HEAD? |
|---|---|---|
| `csat_survey_service_spec.rb:38` | spec espera `ActivityMessageJob.perform_later(conversation, …)`, código passa `conversation.id` | **sim** |
| `csat_survey_service_spec.rb:350` | idem | **sim** |
| `enterprise/.../hook_execution_service_spec.rb:388` | reentrada órfã D-12 não reatribui | **sim** |

Specs novos/alterados (todos verdes):

- `spec/services/csat_survey_service_spec.rb` — 3 casos de grupo (identifier `@g.us`,
  `additional_attributes.type`, `waha_whatsapp_chat_id`); o "dispara em 1:1" já existia.
- `spec/listeners/nps_survey_listener_spec.rb` — **novo**, 6 exemplos (1:1 dispara; 3 formas de
  grupo não disparam; não-resolvida e NPS desabilitado seguem barrando).
- `spec/services/message_templates/hook_execution_service_spec.rb` — 4 exemplos de grupo, incluindo
  **não-regressão**: 1:1 na *mesma inbox* continua recebendo greeting.
- `spec/services/message_templates/template/out_of_office_spec.rb` — 2 exemplos no
  `.perform_if_applicable` (1:1 envia, grupo não).
- `spec/enterprise/services/captain/behavior/router_service_spec.rb` — o exemplo
  "responds to group conversations when skip_groups is not configured" **inverteu de propósito**
  (agora `be false`); somei 6 exemplos cobrindo default ausente, `behavior` vazio, `false`,
  `'false'`, `'true'` e 1:1 com a config ausente.
- `spec/services/llm_formatter/conversation_llm_formatter_spec.rb` — 12 exemplos de grupo
  (C2, prefixo WAHA, prefixo fóssil, variante mascarada, falso-positivo `**Resumo:**`, LID solto no
  meio do texto, fallback genérico, agente, dois participantes, cabeçalho, contagem) + **1 de
  não-regressão**: em 1:1 um texto que *parece* prefixo de grupo fica intacto.

### 6.3 Dado REAL (somente leitura, `RAILS_ENV=production bundle exec rails runner`)

Formatter rodado contra conversas de verdade:

```
GRUPO conv=2417 "Astra online #1 (Grupo)"   (formato 👥)
  | Conversation type: WhatsApp group — "Astra online #1". Messages come from DIFFERENT participants…
  | José: Denúncia ele pessoal que ai cai
  | Douglas Dall'Agnol: Eu gostaria de menos informações, por favor
  | Will. Winchester: qual o intuito desse grupo? …
  VAZAMENTO(lid/emoji): []          ← nenhum

GRUPO conv=12 "Sentinela Monitoramento (GROUP)"   (formato fóssil)
  | Sentinela: …        (era: "User: **+55 (66) 9683-6077 - Sentinela:**\n\n…")
  75 linhas → 45 linhas
  VAZAMENTO(lid/emoji): []

1:1 conv=17 "Ederson Ricieri Davi"
  | Conversation ID / Channel / Message History / User: Ola / Bot: …
  byte-a-byte igual ao de antes (nenhuma linha de grupo, nenhum reprocessamento)
```

---

## 7. Consulta de leitura — quanto os guards teriam poupado

```
Conversas totais: 2521 | de GRUPO: 90 (3,6%) | contas envolvidas: [3, 5]

GUARD CSAT       ->  15 pesquisas CSAT que NÃO teriam sido enviadas
                 ->   2 respostas CSAT contaminando o relatório de satisfação
GUARD NPS        ->   2 NpsResponse que NÃO teriam sido criados
GUARD GREET/OOO  ->   9 mensagens automáticas de texto que NÃO teriam caído no grupo
GUARD CAPTAIN    ->   assistants sem skip_groups explícito (a IA podia falar no grupo):
                        #16 Helena
                        #17 Lia
FORMATTER LLM    ->  513 msgs com prefixo '👥 *Nome (LID@lid)*'
                 -> 4800 msgs com prefixo '**+fone - Nome:**'
                 -> 5313 de 9780 mensagens de grupo ganham autor nomeado
```

Total: **26 disparos automáticos** que não voltam a acontecer + **5.313 mensagens** que deixam de
chegar ao modelo como ruído anônimo.

---

## 8. Riscos que o coordenador precisa saber

1. **Spec invertido de propósito** — `router_service_spec.rb`, "responds to group conversations when
   skip_groups is not configured" agora espera `false`. Se alguém revisar o diff sem contexto vai
   achar que é regressão. **É a mudança pedida.**
2. **`out_of_office.rb` fora da minha lista de propriedade** (§2.4). Toquei porque sem isso o guard
   de greeting/OOO seria furado pelos 4 caminhos do Captain. Uma linha, gate de classe.
3. **Formato fóssil não tratado no front** (§3). 4.800 mensagens. Precisa da sua decisão sobre o C4.
4. **Cabeçalho novo no prompt de grupo** (§2.6, item 1) — vai além do que a task pediu. Muda o
   prompt que o classificador recebe em conversa de grupo. Reversível em uma linha.
5. **NPS manual e automações continuam livres em grupo** — decisões conscientes, argumentadas em
   §2.2 e §5. Se você quiser bloquear, é um `return` em cada, mas eu recomendo não.
6. **3 falhas pré-existentes** na suíte (§6.2). Não são minhas, mas quem rodar a suíte vai vê-las.
7. **Contrato C2 ainda sem dado** — 0 mensagens com `group_sender` no momento da medição. O caminho
   C2 do formatter está implementado e testado por spec, mas **não foi exercitado contra dado real**.
   Vale revalidar depois que a ingestão do I1 gravar as primeiras.
8. **Acoplamento novo ao I1** — o formatter agora chama `Whatsapp::GroupSenderExtractor.call` e usa
   `Result#matched?`, `#content` e `#sender['name']`. Se o I1 mudar esse shape, o spec do formatter
   quebra (é o comportamento desejado, mas vale saber antes de mergear os dois lados).
