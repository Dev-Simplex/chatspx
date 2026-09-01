# Baseline da suíte — frente `spx/followup`

> **Tarefa A.** Foto do estado atual da suíte **antes** de qualquer código das tarefas B e C.
> Data: **11/08/2026** · Commit medido: **`e973f8aab5`** · Máquina: **`.232`** (homologação, `192.168.8.232`).
>
> **Para que serve:** distinguir *regressão* (você quebrou) de *dívida preexistente* (já estava
> quebrado). Se depois de B ou C um destes 12 exemplos continuar falhando, **não é você**. Se
> aparecer um 13º, aí sim é.

---

## 0. O que foi consertado antes de medir (e por que importa)

`origin/spx/followup` apontava pra `ab2e510902` — **90 commits atrás** do HEAD local. A receita de
CI que circulou faz `git worktree add --detach <path> origin/spx/followup`; rodada como estava,
mediria **árvore velha** e o baseline nasceria mentindo.

Corrigido com `git push -u origin spx/followup` — **fast-forward puro**
(`ab2e510902..e973f8aab5`, sem `+` no refspec, sem `--force`). Depois do push:

```
origin/spx/followup = e973f8aab5   ← igual ao HEAD
origin/homologacao  = e973f8aab5   ← e igual à branch de integração
git rev-list --left-right --count origin/spx/followup...HEAD  →  0  0
```

**Consequência que sustenta todo este documento:** a árvore medida é **idêntica à
`origin/homologacao`**. Não existe uma linha de código desta frente nela. Logo, *toda* falha
listada abaixo é, por construção, **preexistente na branch de integração** — não é dívida que a
frente `spx/followup` introduziu, e não é regressão de nada.

---

## 1. Resultado por arquivo

| Arquivo | Examples | Falhas | Veredito |
|---|---:|---:|---|
| `spec/enterprise/jobs/captain/conversation/followup_job_spec.rb` | 12 | **0** | ✅ verde |
| `spec/enterprise/jobs/captain/conversation/response_builder_job_spec.rb` | 43 | **0** | ✅ verde |
| `spec/enterprise/jobs/captain/inbox_pending_conversations_resolution_job_spec.rb` | 27 | **3** | ⚠️ dívida preexistente |
| `spec/enterprise/models/message_spec.rb` | 15 | **0** | ✅ verde |
| `spec/models/conversation_spec.rb` | 105 | **9** | ⚠️ dívida preexistente |
| **TOTAL** | **202** | **12** | |

Os dois arquivos que B e C mais vão mexer — `followup_job_spec` e `response_builder_job_spec` —
estão **verdes**. Qualquer vermelho que aparecer neles depois é regressão, sem discussão.

---

## 2. As 12 falhas, classificadas

Todas as 12 são **preexistentes**. Nenhuma é regressão. Elas se reduzem a **duas causas-raiz**, e
as duas são o mesmo fenômeno: **spec parada no comportamento do upstream, enquanto o fork seguiu
em frente de propósito**.

### Causa-raiz A — guarda de status `pending` configurável por inbox (9 falhas)

Arquivo: `spec/models/conversation_spec.rb` (spec **OSS**, herdada do Chatwoot upstream).

Erro exato:

```
ActiveRecord::RecordInvalid:
  Validation failed: Status cannot be Pending — feature disabled for this inbox
```

O fork adicionou validação em `app/models/conversation.rb:389` que **recusa** status `pending`
quando a inbox não tem `pending_status_enabled`. A spec do upstream cria conversa com
`status: :pending` numa inbox de fábrica (pending desligado) → estoura na própria factory.

**Idade:** commit `da2ea07ed1`, **17/04/2026** — *"feat(inbox): permitir status Pendente
configuravel por caixa de entrada"*. Quase 4 meses. É a defesa contra o **limbo de pending** que
o `STATE.md` documenta desde o incidente de 02/06 (conversa presa em `pending`, invisível na aba
"Abertas"). Ou seja: **o código está certo e a spec é que está velha.**

| # | Exemplo | Sintoma |
|---|---|---|
| 1 | `auto_assignment_handler` · não auto-atribui se é conversa de bot | `create(:conversation, status: 'pending')` → `RecordInvalid` |
| 2 | `#toggle_status` · alterna pra open quando pending | idem |
| 3 | `#bot_handoff!` · muda status pra open | idem (`let` da factory) |
| 4 | `#bot_handoff!` · dispara `CONVERSATION_BOT_HANDOFF` | idem |
| 5 | `#bot_handoff!` · define `waiting_since` quando vazio | idem |
| 6 | `#bot_handoff!` · preserva `waiting_since` existente | idem |
| 7 | `#botinbox` · conversa em inbox com agent bot fica pending | esperado `"pending"`, veio `"open"` |
| 8 | `#botinbox` · campanha sem sender fica pending | esperado `"pending"`, veio `"open"` |
| 9 | `#botintegration` · inbox com dialogflow fica pending | esperado `"pending"`, veio `"open"` |

> ⚠️ **Atenção para as tarefas B e C:** os itens 3–6 são justamente os exemplos de **`bot_handoff!`**.
> A primeira tarefa desta frente troca a chamada `bot_handoff!` pelo `HumanHandoffService` no
> `ensure_handoff_if_promised`. **Estes 4 exemplos já estavam vermelhos antes de você encostar
> neles** — e continuam vermelhos pela factory, não pela lógica de handoff. Não perca tempo
> "consertando" o que não quebrou, e não use o vermelho deles como sinal de que a troca funcionou
> ou falhou. Escreva teste novo para cobrir a troca.

### Causa-raiz B — contrato do `Conversations::ActivityMessageJob` + locale (3 falhas)

Arquivo: `spec/enterprise/jobs/captain/inbox_pending_conversations_resolution_job_spec.rb`.

A spec ficou parada em **três** mudanças deliberadas do produto:

1. **O job recebe ID, não o registro.** Esperado `[#<Conversation id: 96 ...>, {...}]`;
   real `[96, {...}]`. É *exatamente* o mesmo desvio que o `STATE.md` registrou em 11/08 ao
   fechar a suíte de tools (*"`ActivityMessageJob` recebe ID e não o registro"*) — aquele passe
   arrumou os specs de **tools** e **deixou este arquivo para trás**.
2. **O payload ganhou atribuição de IA:** chave extra
   `content_attributes: {ai_actor: {id:, name:}}`, que a expectativa não prevê.
3. **Locale.** A conta de teste nasce `locale: "pt_BR"` e a mensagem sai traduzida, mas a spec
   compara com `I18n.t(...)` sem locale, que resolve em **`en`**:

   ```
   expected: "Resolving the conversation as it has been inactive for a while. ..."
        got: "Resolvendo a conversa dado que está inativa por um tempo. ..."
   ```

   Efeito colateral do fork entregar em PT-BR (`AGENTS.md`: *"feature nova edita `en` E `pt_BR`"*).

| # | Exemplo | Divergência |
|---|---|---|
| 1 | LLM `complete` · cria mensagem de resolução com default | locale (`en` esperado × `pt_BR` real) |
| 2 | LLM `complete` · activity message após resolução | ID×registro + `ai_actor` + locale |
| 3 | LLM `incomplete` · activity message após handoff | ID×registro + `ai_actor` + locale |

> ⚠️ **Atenção para B e C:** este é o arquivo de **encerramento/auto-closure**, coração desta
> frente. Ele **já entra vermelho**. Se você mexer em encerramento, o alvo é
> **manter em 3 falhas** — não em zero.

---

## 3. Baseline de lint (`rubocop`)

Commit `e973f8aab5`, config e árvore do projeto.

| Arquivo | Offenses |
|---|---:|
| `enterprise/app/jobs/captain/conversation/followup_job.rb` | **0** |
| `enterprise/app/jobs/captain/conversation/response_builder_job.rb` | **16** (1 autocorrigível) |
| `enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb` | **0** |
| `enterprise/app/models/enterprise/concerns/conversation.rb` | **0** |
| **TOTAL** | **16** |

Detalhe das 16 do `response_builder_job.rb` (o arquivo que B e C vão editar):

```
C:  1:  1: Metrics/ClassLength: Class has too many lines. [466/175]
C: 80:  5: Style/MultilineBlockChain: Avoid multi-line chains of blocks.
C:177:  3: Metrics/CyclomaticComplexity: auto_schedule_followup [8/7]
C:264:  3: Metrics/CyclomaticComplexity: with_reply_context [9/7]
C:333:151: Layout/LineLength [180/150]
C:422:  3: Metrics/CyclomaticComplexity: create_messages [9/7]
C:422:  3: Metrics/PerceivedComplexity: create_messages [9/8]
C:505:  3: Metrics/MethodLength [20/19]
C:515:151: Layout/LineLength [151/150]
C:545:151: Layout/LineLength [292/150]
C:549:151: Layout/LineLength [151/150]
C:556: 23: [Correctable] Style/StringConcatenation
C:587:151: Layout/LineLength [171/150]
C:672:  3: Metrics/CyclomaticComplexity: humanizer_typing_delay [10/7]
C:672:  3: Metrics/PerceivedComplexity: humanizer_typing_delay [10/8]
C:678:  5: Style/ComparableClamp: Use Comparable#clamp instead.
```

Por cop: `Layout/LineLength` 5 · `Metrics/CyclomaticComplexity` 4 · `Metrics/PerceivedComplexity` 2
· `Metrics/ClassLength` 1 · `Metrics/MethodLength` 1 · `Style/StringConcatenation` 1 ·
`Style/MultilineBlockChain` 1 · `Style/ComparableClamp` 1.

> ⚠️ **Duas armadilhas de lint para B e C, no arquivo que vocês vão mexer:**
> - **`Metrics/ClassLength` já está em 466/175** — 2,7× o teto. Qualquer linha nova mantém a
>   ofensa. Ela **não** é sua; não tente zerar, e não use `--auto-correct` achando que resolve.
> - **`Metrics/MethodLength` na linha 505 está em 20/19** — no fio. Um método vizinho que cresça
>   vira ofensa nova com facilidade.
> - `ensure_handoff_if_promised` (~linhas 238-257) hoje **não** aparece na lista. Se depois da
>   troca pelo `HumanHandoffService` ele aparecer como `CyclomaticComplexity`, é ofensa **nova** —
>   sua, e vale extrair método.

---

## 4. O banco de teste da `.232` ficou sujo?

**Não. Zero resíduo.** Explicitamente:

- **Não encostei no `chatwoot_test` compartilhado.** Rodei tudo num banco dedicado
  `chatwoot_ci_fup_a`, criado só para esta medição.
- O banco dedicado foi **dropado** ao final (`dropdb chatwoot_ci_fup_a`).
- A worktree `/tmp/ci-followup-a` foi **removida** (`git worktree remove --force`).
- Lista de bancos **antes** e **depois** conferida e **idêntica**: `chatwoot_ci_followup`,
  `chatwoot_dev`, `chatwoot_production`, `chatwoot_test`, `chatwoot_test_2..7`.
- `db:migrate` no banco dedicado terminou com **0 migrations pendentes**.

---

## 5. ⚠️ A `.232` é compartilhada entre TODAS as frentes

> **Esta seção não é sobre a tarefa A.** Vale para **qualquer sessão** que rode suíte na `.232` —
> desta frente ou de outra. Leia antes de rodar `rspec` ali.

A `192.168.8.232` é **máquina única para todas as frentes do SPX** rodarem teste. Não existe
isolamento automático: worktree e banco são recursos **globais** da caixa, e duas sessões que não
combinarem nomes vão se atropelar. Ao medir este baseline, as duas coisas aconteceram de verdade.

**Fato 1 — o path da worktree é global.** Frentes diferentes escolhem `/tmp/ci-*` por conta
própria e colidem. No momento desta medição havia worktrees de pelo menos quatro frentes
convivendo (`/tmp/ci-camp-e1`, `/tmp/ci-eval`, `/tmp/ci-fri` e `/tmp/ci-base`). As receitas de CI
que circulam começam com `git worktree remove --force <path>; rm -rf <path>` — ou seja, quem
chegar depois **apaga a árvore de quem já está rodando**, no meio da execução.

**Fato 2 — e este é o silencioso: o banco de teste default é o MESMO para todos.**
`config/database.yml` resolve o banco de teste como:

```ruby
test:
  database: "<%= ENV.fetch('POSTGRES_DATABASE', 'chatwoot_test') %>"
```

e o `.env` da VM — o mesmo que as receitas mandam symlinkar — **não define `POSTGRES_DATABASE`**.
Logo **toda** sessão cai em `chatwoot_test`. Duas suítes simultâneas ali compartilham fixtures,
sequences e limpeza de banco: uma trunca a tabela que a outra está usando e as duas colhem falha
**espúria**. Não dá erro de "banco ocupado" — dá teste vermelho que parece bug de código. É o
tipo de contaminação que faz alguém "consertar" um teste que nunca esteve quebrado.

**Regra para qualquer sessão que rode suíte na `.232`:** use **path próprio E banco próprio**.
Os dois, sempre — path sozinho não protege, porque o banco continua compartilhado.

```bash
# path exclusivo da sua sessão + banco exclusivo da sua sessão
POSTGRES_DATABASE=chatwoot_ci_<SEU_ID> RAILS_ENV=test bundle exec rspec <arquivos>
```

E **limpe no fim** (worktree removida + `dropdb`), senão a caixa acumula lixo até encher o disco.
A receita completa está em §6.2.

> 🔒 **E o alerta que vale mais que os outros:** o `.env` symlinkado é o de **produção** da `.232`,
> que atende **clientes reais** (contas 1 SimplexIA, 3 Simplex Tecnologia, 4 Colégio Alternativo,
> 5 Realizare) e traz `RAILS_ENV=production`. Hoje `RAILS_ENV=test` é seguro **só porque**
> `POSTGRES_DATABASE` está ausente e o bloco `test` cai no default `chatwoot_test`. **No dia em
> que alguém definir `POSTGRES_DATABASE` nesse `.env`, a mesma receita passa a apontar a suíte
> para o banco vivo — e `rspec` limpa o banco entre exemplos.** Seria perda de dados de cliente.
> **Confira essa variável antes de rodar suíte com o `.env` de produção symlinkado.**

---

## 6. Dois riscos de infraestrutura descobertos ao medir

### 6.1 🔴 Colisão de path — `/tmp/ci-base` já estava ocupado

A spec desta tarefa mandava usar `/tmp/ci-base` como path isolado. Na hora de usar, **havia um
processo ativo de outro worker exatamente nele** (pid 2107383/2108112), e o comando dele começava
com:

```
git worktree remove --force /tmp/ci-base; rm -rf /tmp/ci-base; git worktree add --detach /tmp/ci-base origin/homologacao
```

Pior: a suíte daquele worker incluía **`response_builder_job_spec.rb`**, que é **um dos 5 arquivos
deste baseline**. Obedecer à letra da spec teria feito os dois runs destruírem a árvore um do
outro no meio da execução — e o baseline sairia lixo.

**Feito:** medi em `/tmp/ci-followup-a` (path exclusivo). Coordenação avisada.

### 5.2 🔴 O banco de teste é compartilhado por padrão — e isso contamina baseline

`config/database.yml` resolve o banco de teste como
`ENV.fetch('POSTGRES_DATABASE', 'chatwoot_test')`, e o `.env` da VM **não define
`POSTGRES_DATABASE`**. Resultado: **todo worker cai no mesmo `chatwoot_test`**, e `rspec`
concorrente no mesmo banco gera falha espúria — justamente o veneno que um baseline não pode ter.

**Receita para B e C (use banco próprio):**

```bash
H=scripts/ops/tozi-hml.sh
bash $H chatwoot "cd /home/chatwoot/chatwoot; git fetch origin --quiet; git worktree add --detach /tmp/ci-fup-<SEU_ID> origin/spx/followup"
bash $H chatwoot "ln -sf /home/chatwoot/chatwoot/.env /tmp/ci-fup-<SEU_ID>/.env"
bash $H chatwoot "cd /tmp/ci-fup-<SEU_ID> && POSTGRES_DATABASE=chatwoot_ci_fup_<SEU_ID> RAILS_ENV=test bundle exec rails db:create db:schema:load db:migrate"
bash $H chatwoot "cd /tmp/ci-fup-<SEU_ID> && POSTGRES_DATABASE=chatwoot_ci_fup_<SEU_ID> RAILS_ENV=test bundle exec rspec <arquivos>"
# limpeza no fim:
bash $H chatwoot "cd /home/chatwoot/chatwoot && git worktree remove --force /tmp/ci-fup-<SEU_ID>; dropdb chatwoot_ci_fup_<SEU_ID>"
```

> `db:schema:load` em vez de só `db:migrate`: em banco novo, `db:migrate` roda o histórico inteiro
> de migrations e demora demais. `schema:load` + `db:migrate` chega no mesmo lugar em segundos.

### 5.3 🟢 Checagem de segurança feita antes de rodar qualquer coisa

Como o `.env` symlinkado é o de **produção** da `.232` (que atende contas de clientes reais —
1 SimplexIA, 3 Simplex Tecnologia, 4 Colégio Alternativo, 5 Realizare) e nele consta
`RAILS_ENV=production`, verifiquei **antes** de executar migration ou rspec para onde
`RAILS_ENV=test` apontava. Como `POSTGRES_DATABASE` **não** está definido, o bloco `test` cai no
default `chatwoot_test` — **separado** do `chatwoot_production`. Sem risco para os clientes.

> Fica o alerta permanente: se alguém **definir** `POSTGRES_DATABASE` nesse `.env`, esta mesma
> receita de CI passa a apontar `RAILS_ENV=test` para o banco vivo — e `rspec` **limpa** o banco
> entre exemplos. Seria destruição de dados de cliente. **Conferir esse fetch antes de rodar
> a suíte com o `.env` de produção symlinkado.**

---

## 6. Regra de uso deste baseline

- **Não conserte** os 12 exemplos vermelhos como parte de B ou C. Eles são a régua.
- Depois de B e C, o esperado é: **202 examples, 12 failures** — as mesmas 12, nos mesmos dois
  arquivos, mais os exemplos novos que você escrever (esses sim, verdes).
- Falha **nova** em `followup_job_spec` ou `response_builder_job_spec` = **regressão sua**.
- Lint: teto de **16 offenses** nos 4 arquivos. Passou disso, é seu.

> Em 31/07 esta frente entregou 3 commits de lógica de fila e **4 de 55 exemplos falharam na
> primeira execução real — incluindo o fix central**. Este documento existe para que isso não se
> repita.
