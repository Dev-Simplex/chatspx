# Auditoria upstream Chatwoot → ChatSPX — Relatório consolidado

**Data:** 03/08/2026 · **Escopo:** `v4.12.1` (25/03/2026) → `v4.16.2` (27/07/2026) + `upstream/develop` (03/08)
**Natureza:** auditoria **read-only**. Nenhuma linha de código foi alterada, nenhum merge/cherry-pick/rebase executado.

Relatórios de origem nesta pasta: [`01-features`](01-features.md) · [`02-migrations-schema`](02-migrations-schema.md) ·
[`03-conflitos`](03-conflitos.md) · [`04-infra-seguranca`](04-infra-seguranca.md) · [`05-captain-canais`](05-captain-canais.md)

---

## Veredito

**Não faça merge da tag. Não faça rebase.** O fork divergiu a ponto de o merge em bloco entregar 249 arquivos
quebrados e 427 pontos de decisão de uma vez — e 8 desses pontos não têm resposta técnica, são decisão de produto.

Mas há um **pacote pequeno, urgente e independente de merge** que deve sair desta semana: 8 falhas de segurança
confirmadas no nosso código hoje, 10 dependências vulneráveis, e 3 travas que impedem qualquer integração futura.
Isso cabe em ~3 dias e não depende de decidir nada sobre o merge grande.

---

## Os números

| | Commits | Arquivos |
|---|---:|---:|
| Nosso fork desde `v4.12.1` | 940 | 4.736 |
| Upstream desde `v4.12.1` | 555 | 3.605 |
| **Arquivos tocados pelos dois** | — | **558** |
| Destes, com conflito textual real | — | **249** (427 hunks, 15.667 linhas) |
| Arquivos que só o upstream tocou (caminho barato) | — | **3.047** (924 novos) |

Só **27% dos commits upstream** (147/537) não encostam em arquivo em colisão — cherry-pick commit-a-commit
não cobre o delta. Migrations: 45 deles × 105 nossas.

---

## 1. O que precisa sair agora (não depende de merge nenhum)

### 1.1 Segurança — verificado por inspeção direta no nosso código

Eu confirmei pessoalmente os quatro primeiros; os demais vêm do W4 com arquivo e linha.

| Falha | Estado no ChatSPX hoje | Patch |
|---|---|---|
| **SSRF no upload** (`external_url` → `uri.open` direto) | `upload_controller.rb:42`. **Não temos `lib/safe_fetch.rb`.** Qualquer agente autenticado lê IMDS da AWS (`169.254.169.254`) ou varre a rede interna | `871f2f4d56` |
| **Custom attributes sem autorização** | `custom_attribute_definitions_controller.rb` **não tem `check_authorization`** e a policy **não existe**. Upstream tem os dois | `5c6ea78ce6` — 1 linha + 1 arquivo |
| **`access_token` de agent bot exposto a agente** | `_agent_bot.json.jbuilder:9` serializa sem checar papel. Upstream adicionou `&& Current.account_user&.administrator?` | `13db36609d` — 1 linha |
| **SSRF no avatar por URL** | `avatar_from_url_job.rb:29` — `Down.download` sem filtro de IP | `661608c0b1` |
| **SSRF no webhook** de automação/macro/agent bot | `lib/webhooks/trigger.rb:35` — POST com corpo controlado para rede interna | `c8e551820b` **+ obrigatoriamente** `7c16071fc7` |
| Segredos de integração em texto puro na API | `_hook.json.jbuilder:8` devolve `settings` inteiro — inclui a `api_key` da OpenAI | `27404b4a27` |
| HMAC do widget sem comparação constant-time | 2 controllers usam `==` no digest | `1e7218d439` |
| XSS nos embeds markdown do Help Center | `custom_markdown_renderer.rb:76` sem escape — e nossa Central de Ajuda roda **em iframe no dashboard** | `2192af80f4` — 1 linha |
| Bypass de rate limit de login por barra final | `path_without_extentions` não casa `/auth/sign_in/` → escapa do throttle de brute-force | `2663a8495d` |

**10 dependências vulneráveis**: `puma 6.4.3→7.2.1`, `msgpack` (CVE-2026-54522), `loofah`, `rails-html-sanitizer`,
`crass`, `nokogiri`, `jwt`, `rack`, `dompurify`, `video.js`. É PR só de lockfile.

⚠️ **Armadilha:** não traga o SSRF de webhook (`c8e551820b`) sem a válvula `7c16071fc7`
(`SAFE_FETCH_ALLOW_PRIVATE_NETWORK`). Ele bloqueia IP privado por padrão — se algum agent bot, WAHA ou canal API
nosso apontar para rede interna, para de funcionar. O próprio upstream comeu dois issues por isso.

### 1.2 Performance — 3 patches minúsculos, ganho real

- **Deadlock de labels** (`de0bd8e71b`): counter cache de tags serializa writes paralelos na mesma linha.
  Fix é **um arquivo novo de 10 linhas**. Nossas automações aplicam label em massa — vale procurar
  `ActiveRecord::Deadlocked` no GlitchTip; se aparecer, isso é a causa raiz.
- **Sort "Pending Response"** (`fed32d5964`): `NULLS LAST` impede uso de índice → seq scan na `conversations`
  inteira. Fix de 1 linha, nosso arquivo está idêntico ao da base.
- **N+1 em `inboxes#index`** (`dd7f5c27e5`): 3 queries por inbox.

### 1.3 Duas correções nossas, sem relação com o upstream

- `NODE_OPTIONS=--max-old-space-size` continua **4096** nos nossos scripts de deploy — já sabemos que isso
  mascara OOM do Vite aqui. Subir para 8192.
- `runtime_context.liquid` tem **`(horário de Sinop/MT)` hardcoded** no prompt do Captain. Numa frota
  multi-cliente, toda conta em outro fuso recebe afirmação de fuso errada. O mecanismo do upstream
  (`config['timezone']` da conta) conserta isso — mecanismo deles, conteúdo nosso.

---

## 2. As três travas — nada entra antes disso

### 2.1 🔴 O bitmask de `feature_flags` está estourado, e o merge o corrompe

**Verificado por mim:** nosso `config/features.yml` tem **65 entradas** numa única coluna `bigint`, que comporta
**63**. As duas últimas — `conversation_required_attributes` (64) e `advanced_assignment` (65) — não têm bit onde
morar. São features referenciadas no front que nunca podem ser ligadas.

Pior: nós e o upstream reciclamos **os mesmos bits para features diferentes**. 12 posições divergem:

| bit | ChatSPX | Upstream v4.16.2 |
|---|---|---|
| 29 | `message_sequences` | `custom_tools` |
| 30 | `internal_chat` | `message_reply_to` |
| **39** | **`ai_assistant_v2`** (redesign do Copilot) | `captain_v1_action_classifier` |
| 61-63 | `kanban_cursor_loading`, `kanban_ux_v2`, `captain_tasks` | `captain_tasks`, `conversation_required_attributes`, `advanced_assignment` |

Um merge cru do `features.yml` produz arquivo **sintaticamente válido e semanticamente destrutivo**: as migrations
`repurpose_*` do upstream rodam `disable_features` sobre esses bits e **apagam `ai_assistant_v2` e
`message_sequences` de todas as contas da frota**, silenciosamente. E `captain_tasks` (do qual nosso auto-closure
depende, commit `d985beeafd`) muda de posição.

**A boa notícia:** o upstream resolveu exatamente esse problema em v4.16.0 (`873d16f54c`) — `Featurable`
multi-coluna + `feature_flags_ext_1` + validação que derruba o boot se passar de 63. Verifiquei: eles têm 68
features, 6 já em `feature_flags_ext_1`. **É a solução permanente que substitui nossa gambiarra de
`internal_attributes`.**

⚠️ Mas o concern novo **valida no boot**. Com nossas 65 entradas numa coluna, se trouxermos o `featurable.rb`
antes de reorganizar o YAML, **o app não sobe** — e o erro aponta para o concern, não para o YAML.

Isso é um projeto próprio, esforço M, e inclui uma **migration de dados** que releia o bitmask de cada conta
pelo mapa antigo e regrave pelo novo. Sem ela, reordenar corrompe a frota.

### 2.2 🔴 Duas colisões exatas de timestamp de migration

**Verificado por mim:**

| Timestamp | Nossa | Deles |
|---|---|---|
| `20260616120000` | `add_agent_id_to_messages.rb` | `add_icon_to_teams.rb` |
| `20260630000000` | `extend_ai_config_changes.rb` | `add_sender_created_index_to_messages.rb` |

`DuplicateMigrationVersionError` trava `db:migrate` e o boot **em toda a frota**, não só onde o merge foi feito.
Fix: re-carimbar **a deles** (as nossas já estão em `schema_migrations` das VMs). Custo < 1h.

⚠️ Jamais o contrário: se apagar a nossa e ficar com a deles no mesmo timestamp, o Rails considera a migration
"já rodada" e a coluna nunca é criada — falha silenciosa que só aparece em runtime.

### 2.3 🔴 Duas migrations do upstream destroem dados nossos

- **`purge_pending_captain_assistant_responses`** (v4.16.2): `DELETE FROM captain_assistant_responses WHERE
  status = 0`. No upstream `status 0` virou lixo órfão; **no nosso fork `0 = pending` e é estado vivo**
  (`bulk_actions_controller.rb:40` aprova pendentes). Isso **apaga todas as FAQs pendentes de aprovação de todos
  os clientes**, sem batch e sem `down`. **DESCARTAR.**
- **`drop_channel_voice`** (v4.14.0): o upstream matou `Channel::Voice`; nós ainda usamos em 10+ arquivos.
  Apaga a tabela e os dados. **DESCARTAR** (ou trazer o refactor de voz inteiro, que são 114 arquivos).

Há ainda `enqueue_validate_openai_hooks_job`, que enfileira um job que **destrói `Integrations::Hook` do OpenAI**
e e-mailala o admin do cliente quando o `/v1/models` responde 401 — perigoso se a VM usa endpoint via proxy.
Trazer o job, **não** a migration; rodar manual por conta.

---

## 3. O que vale trazer de produto

Ordenado por retorno sobre risco. Detalhamento e origem (commit/PR) nos relatórios W1 e W5.

**Retorno alto, risco baixo — fila da frente:**

1. **Companies completo** — em v4.12.1 era só listagem; virou CRM B2B (detalhe, notas, histórico, conversas da
   empresa, atributos, seletor no contato). Colide com **exatamente 1 arquivo nosso**. Melhor retorno por risco
   de toda a auditoria, e é pedido recorrente da frota. Esforço G (volume, não conciliação).
2. **SLA respeitando horário comercial** (`49b0ab0e1f`) — hoje calculamos breach em wall-clock mesmo com
   "only during business hours" ligado. **Não é falta de feature, é número errado num relatório que o cliente usa
   para cobrar o time dele.** Correção de dado.
3. **Merge opt-in de `custom_attributes` da conversa** (`acae0a2acf`) — hoje o PATCH substitui o hash inteiro.
   Nossos Flows e o Captain escrevem em paralelo e se sobrescrevem. Esforço P.
4. **`inbox_updated` quando a inbox desconecta** (`d0ecdc14d8`) — hoje descobrimos WhatsApp caído por reclamação
   de cliente. Webhook nativo alimenta alerta no Almirante sem polling. Esforço P.
5. **`max_turns` do agent runner: 100 → 10** (`ce2e10e89e`) — uma linha, e é dinheiro direto: hoje um assistente
   em loop de tool queima até 100 turnos por resposta.
6. **Assignment ignora conversa parada** (`df79c0bbde`) — muito relevante no WhatsApp, onde conversa fica aberta
   por dias porque o cliente sumiu e a auto-atribuição recicla lixo queimando capacidade do agente.
7. **BOM UTF-8 no export CSV de contatos** — acentuação quebrada no Excel é reclamação clássica.

**Canais WhatsApp — onde o upstream corrigiu na raiz o que nós remendamos:**

- **Override de webhook por número** (`7c7459b734`): o problema dos 2 números no mesmo WABA. Nosso patch
  (`acceptable_webhook_urls`, **ainda não commitado**) mascara o alerta na UI; o deles troca
  `override_waba_callback` por `override_phone_number_callback`, dando callback próprio a cada número.
  **Trocar o nosso pelo deles** — reduz divergência e resolve a causa.
- **HMAC nos webhooks WhatsApp/Instagram** (`a9ac1c633d`) — **não temos**. Obrigatório.
- **Contato bloqueado → descartar mensagem entrante** (1 linha), **`fallback_title` de localização truncado a 255**
  (mensagem sumia, 1 linha), **guarda da janela de 24h em envio por automação**.

**Captain — onde a versão deles ficou honestamente melhor que a nossa:**

Nós investimos em *capacidade de atendimento* (tools de negócio, eval por episódio, áudio, auto-closure); eles
investiram em *observabilidade e guardrails*. São eixos complementares, e três itens deles atacam problemas que
hoje tentamos resolver por prompt — com histórico de recaída documentado nos nossos próprios commits:

- **Classificador de handoff** (`70f799ab35`): segundo passe de LLM que decide *se* transfere, com taxonomia de
  12 razões. Nosso `handoff_tool` só decide *para qual time*. Nossos commits `b780eec93e` ("handoff quase nunca
  disparava") e `334f0409e9` ("garante handoff prometido") são exatamente o sintoma de tomar essa decisão por
  descrição de tool.
- **Guardrail de falsa promessa** (`1c7e60880d`): detecta "vou verificar e te aviso" — trabalho assíncrono que a
  IA não pode cumprir. Language-independent, pluga sem reescrever nosso prompt pt-BR.
- **Generation path na bolha + message reports** (`67cab7171d`, `6a262287d2`): o agente vê quais documentos/FAQs
  alimentaram a resposta, e marca resposta ruim com motivo. Nosso eval é LLM-as-judge automático; isso é o
  **feedback loop humano** que não temos.

---

## 4. Onde nós ganhamos (e devemos ignorar o upstream)

| Área | Veredito |
|---|---|
| **Flows × `time based automation`** deles | **Nós, com folga.** Eles entregam delay linear numa regra; nós temos grafo com `wait_for_reply`, ramificação por resposta, horário comercial e simulação. Descartar. |
| **Kanban, chat interno, relatórios de atribuição** | Upstream **não tem**. `git log --grep=kanban` no período: zero. Bônus: essas áreas não recebem conflito nenhum. |
| **WAHA/Evolution, grupos WhatsApp com autor, 9º dígito BR, Meta Lead Ads** | Só nós. |
| **Copilot streaming, MCP, eval por episódio** | Só nós. O Copilot upstream ficou **intocado no período** (1 linha) — nosso redesign é ganho líquido sem dívida. |
| **Campanha WhatsApp** | Nosso fluxo CSV (dedup, normalização BR, `template_params` por destinatário) é melhor. O Liquid deles (`{{contact.name}}`) preenche um buraco nosso — 4 arquivos, complementar. |
| **Contadores `/meta`** | **JÁ TEMOS e melhor**: nosso `compute_all_counts` faz 9 contadores com `COUNT(*) FILTER` numa query. *(Correção: o W1 recomendou trazer o patch deles; o W4 está certo — verifiquei o código.)* |
| **swagger, favicons, SCSS, i18n pt_BR/en** | Manter o nosso e ignorar. Nossa spec é produto em pt-BR (69k linhas); o pt_BR deles é saída de máquina. |
| **Chatlist v5 deles** | Manter o nosso layout. Portar só `sort by unread` e `filtro por contato`, que são funcionalidade, não layout. |

---

## 5. Estratégia recomendada

**Descartadas, com o número que as mata:**

- **Merge da tag** — 249 arquivos quebrados de uma vez, e as 2 colisões de migration impedem até o boot.
- **Rebase** — 940 commits nossos sobre 555 deles; `ChatList.vue`, `ReplyBox.vue` e `response_builder_job.rb`
  reconflitam em *cada* commit que os tocou. Custo multiplicativo.
- **Cherry-pick como estratégia única** — só 27% dos commits são limpos. Serve como tática, não como estratégia.

**Recomendado — 3 trilhos, sem nunca mergear a tag:**

| Trilho | Alvo | Mecânica | Custo |
|---|---|---|---|
| **0 — pré-requisito** | 2 timestamps de migration + pacote de segurança da §1 | patches isolados | P (dias) |
| **A — pull por caminho** | 3.047 arquivos só-deles | `git checkout v4.16.2 -- <caminho>` por subsistema, um PR cada, suite verde antes do próximo | M-G, paralelizável |
| **B — merge assistido** | 205 arquivos leves/médios (~4.500 linhas) | resolver fora do working tree, arquivo a arquivo; 28 favicons resolvem em bloco | G, mecânico |
| **C — decisão de produto** | 44 arquivos quentes + 8 temas arquiteturais | cada tema vira card com dono | G+, depende de negócio |

Alvo estável é **`v4.16.2`**, não `develop` — o `develop` carrega a saga dos unread counts, que o upstream
adicionou, reverteu, re-adicionou e reverteu de novo por problema de performance, e hoje vive atrás de flags
`chatwoot_internal` que nem eles ligam em produção.

⚠️ **Não incluir no ranking:** 14 arquivos fazem **auto-merge limpo mas com risco semântico** (os dois lados
mudaram ≥40 linhas em regiões diferentes). Não geram marcador de conflito e por isso passam despercebidos no
review. A lista está no W3 §6.10.

---

## 6. Alerta operacional imediato

O `git status` mostra **WIP não commitado** em `app/services/whatsapp/health_service.rb`, `AccountHealth.vue` e
`inboxes_controller_spec.rb` — exatamente os arquivos que o upstream reescreveu no PR #15100 (health de número
persistido + job agendado).

Duas consequências:

1. Se esse WIP for commitado, entram 3 arquivos novos na zona de colisão.
2. **Nosso patch `acceptable_webhook_urls` só existe no working tree.** Um `git checkout` distraído nesse arquivo
   durante qualquer integração o apaga sem rastro — a justificativa técnica dele só está preservada no
   relatório W5 desta auditoria.

Vale alinhar com quem está mexendo antes de qualquer trabalho de integração.

---

## 7. Decisões que precisam de você

1. **Reconciliação do `feature_flags`** é projeto próprio (esforço M, com migration de dados). Aprova como
   trabalho isolado antes de qualquer integração? Ela destrava tudo o mais e conserta um bug que já existe hoje.
2. **Captain V2 do upstream** — eles criaram 128 arquivos novos, nós 164. São dois produtos no mesmo namespace.
   A decisão não é técnica: adotamos a base deles e reaplicamos nosso redesign, ou seguimos divergindo e
   portamos só os guardrails (classificador de handoff, falsa promessa, message reports)? **Minha recomendação:
   portar só os guardrails.**
3. **`Channel::Voice`** — o upstream removeu. Mantemos o modelo órfão (dívida crescente) ou migramos para
   `Channel::TwilioSms`? Precisa saber antes se alguma conta tem linha em `channel_voice`.
4. **i18n de outros idiomas** — 1.432 arquivos, metade do volume do "caminho barato". Só vale se vendermos fora
   do Brasil. Decisão comercial.

---

## 8. O que a auditoria NÃO apurou

Tudo aqui é análise estática de git. **Nenhum banco foi consultado** e nada foi executado — então estas
perguntas continuam abertas e mudam algumas decisões:

- Quantas contas da frota têm `ai_assistant_v2` / `message_sequences` / `captain_tasks` ligados (dimensiona o
  estrago de §2.1). E se contas com Kanban "ligado sozinho" existem — seria sintoma do deslocamento de bits que
  nós mesmos já causamos ao inserir `kanban_*` nas posições 61-62.
- Se existe linha em `channel_voice` em alguma VM.
- Se há webhook/agent bot apontando para IP privado (decide se o SSRF fix quebra a frota).
- Se o `ActiveRecord::Deadlocked` de labels já aparece no GlitchTip (transformaria P1 de prevenção em correção
  de incidente ativo).
- Se o nosso motor Flow chama `Webhooks::Trigger` — se chamar, herda o bloqueio do SafeFetch.
- Comparação visual das telas novas do Captain contra o nosso redesign (estimativas de esforço G são por
  contagem de linhas, não inspeção de UI).

As queries SQL prontas para responder as quatro primeiras estão no W2 §6.1 e no W4 §B4.
