# SPX — Mapeamento completo e plano da IA orquestradora

> **Data:** 2026-06-10 · **Branch:** `paulao` · **Método:** 21 agentes de mapeamento sobre o código local (app/ + enterprise/) + auditoria **read-only** da produção Tozi (AWS, Account 6) + fluxos n8n legados (`Workspaces/tozi`).
> **Relatórios detalhados por subsistema** (com referências `arquivo:linha`): [`docs/mapeamento-2026-06-10/`](mapeamento-2026-06-10/) — 20 relatórios.
> Nada em produção foi modificado.

---

## 1. Sumário executivo

O SPX já tem **quase todas as peças** de que a IA orquestradora precisa — runtime de agente (Captain v2), 12 agent tools + 32 copilot tools, funil com state machine, follow-up em duas camadas (texto livre na janela 24h + HSM fora dela), motor de disparos, SLA nativo, webhooks, labels, automation rules. O que falta não é construir do zero: é **costurar** as peças (atribuição direcionada, triagem por nicho, notificação que chega no celular do corretor) e **desarmar 5 armadilhas estruturais** que causaram os incidentes recentes.

**Os problemas relatados, com causa-raiz confirmada em código e dados de prod:**

| Sintoma | Causa-raiz | Estado |
|---|---|---|
| Lead respondeu dias depois do disparo e ficou sem resposta | Conversa de disparo fica `open` atribuída ao corretor; reply não dispara `conversation_opened` (regra #53 não zera) → não entra na fila "Não atribuídas" da triagem; corretor tem ~1.700 abertas e não vê; **push/e-mail de "nova mensagem na sua conversa" vem DESLIGADO de fábrica** (só o sininho in-app) | 🔴 **432 conversas nesse estado hoje** (medido em prod) |
| Conversas duplicadas / reply órfão sem histórico | `DisparoLeadJob` criava ficha com source_id na variante 13d (+9º dígito) e `Conversation.create!` incondicional; Meta entrega wa_id na variante 12d → reply caía em outra ficha | 🟡 Consolidação aplicada (275 contatos); **fix `11b913531` NÃO deployado** (prod regrediu no rollout de 08/06). +143 duplicatas históricas (jan–mai) fora do escopo da consolidação |
| Conversas que "não aparecem em Todas" | Mistura de: (a) limbo `pending` (invisível na aba default + sem notificação, por construção); (b) custom role do corretor (vê só as suas); (c) fila "Abertas" com **6.508 conversas** (≈6.100 são de disparo) — o sinal afoga no ruído | 🟡 Limbo mitigado em código (commits `f96ae7740` + override Enterprise); ruído de fila não tratado |

**A decisão estratégica recomendada** (uma só, sem dicotomia): a orquestração vive **dentro do SPX, no ecossistema Captain** — listener próprio no barramento de eventos + tools de atribuição/funil para o agente + automation rules dirigidas por labels de nicho — e **não** como serviço externo via AgentBot/webhook. Motivo: 80% da infraestrutura já existe nesse plano, o fork já provou o padrão (`FunnelAutomationListener`), e o caminho externo exigiria consertar webhooks at-most-once + bug do `skip_agent_bot` antes de começar.

---

## 2. Os cinco fluxos de entrada e o que acontece hoje

### 2.1 Inbound orgânico (cliente chama o número fixo)

`POST /webhooks/whatsapp/:phone` → `WhatsappEventsJob` → `IncomingMessageWhatsappCloudService`. A ficha é resolvida por `Whatsapp::PhoneNumberNormalizationService` (testa variantes 12d/13d do 9º dígito — `app/services/whatsapp/phone_number_normalization_service.rb:14-31`). Com `lock_to_single_conversation` (inbox 91), reusa a última conversa **da ficha** (mesmo resolvida); conversa nova nasce `open` e **sem assignee** — entra na fila de triagem da secretária.

- Se a conversa estava `resolved`: **sem bot** na inbox → reabre `open` → dispara `conversation_opened` → **regra #53 zera assignee+team** (por design: "iniciar zerado" = volta pra triagem). **Com bot** (Clara conectada) → vira `pending` (o famoso limbo — ver §4).
- ⚠️ O lock é **por ficha, não por contato** (`incoming_message_base_service.rb:131-142`) — com 2 fichas, o "1 conversa por contato" fura. É o guarda-corpo que falta (reconciliador do 9º dígito, `docs/backlog/reconciliador-incoming-9-digito.md`).

### 2.2 Outbound manual (atendente chama o contato)

"Nova conversa" pela UI usa `ConversationBuilder` (escopo correto **por contato**), mas o source_id da ficha nova vem de `contact.phone_number` sem reconciliar variantes (`contact_inbox_builder.rb:56-61`) — **fonte viva de duplicata** se o phone armazenado estiver na variante errada. Fora da janela 24h o composer vira o `WhatsappWindowExpired.vue` (só templates aprovados).

### 2.3 Disparos de lista (motor próprio)

Scripts de ingestão (Python, dedup 4 camadas) → motores `rails runner` enfileiram `Spx::Tozi::DisparoLeadJob` com pacing 5s no `Sidekiq::ScheduledSet` → job cria/reusa ficha+conversa, atribui corretor round-robin, manda HSM via `template_params`, grava `campaign_id`. Campanha nativa = âncora `completed` só pra agregar stats (`GET /campaigns/:id/stats`). Pausar = deletar jobs do ScheduledSet via console.

- Números reais (02–08/06): **7.249 HSM, 84,4% alcance, 24,2% resposta, ~R$1.950**. Follow-up no fio existente teve só 3,3% de falha (vs 13,5% geral) — **reusar a conversa é mais barato e mais saudável**.
- Fragilidades: estado do disparo é volátil (ScheduledSet + scripts em Downloads/), `INBOX_ID=91` hardcoded, PREVIEWS triplicados (Meta ↔ job ↔ docs), filtro "conversa em atendimento" só cobriu inquilinos e só status `open`, **sem monitoramento da saúde do número** (health endpoint existe mas é on-demand).

### 2.4 Meta Lead Ads (formulário → conversa)

Webhook validado por HMAC → `FetchLeadService` (traz ad/campanha/form — ouro pra triagem) → `CreateConversationService` cria contato+conversa+1ª mensagem e coloca no funil "Novo Lead". **Dois bloqueadores antes de apontar pra inbox 91:**
1. 1ª mensagem é texto livre → fora da janela 24h **falha localmente** ("Template not found") — lead entra no funil mas nunca recebe nada. Fix: 1ª-mensagem-como-HSM (`tozi_lead_abertura` já APPROVED), copiando o padrão `template_params` do DisparoLeadJob.
2. `source_id_for` devolve phone **com `+`** para Cloud API (`create_conversation_service.rb:108`) — **mesma classe de bug das duplicatas** (reply do lead criaria ficha nova). Precisa do mesmo `resolved_source_id`.
3. Bônus: sem idempotência por `leadgen_id` — retry do Sidekiq duplica conversa.

### 2.5 IA (Captain v2 / Clara)

Hoje **desconectada** da inbox 91 (zero `captain_inboxes` em prod — confirmado). Cérebro pronto: prompt Júlia (cenário Vendas), knowledge hybrid (Playbook 19 chunks + 40 Q&A), tools Vista/geocoding/fotos/follow-up, behavior com debounce 15s, humanizer, business hours, dedup, whitelist no número do Paulo. Modelo `claude-sonnet-4.5` per-conta; chaves LLM globais da instalação (trocar chave = restart do worker).

---

## 3. Visibilidade e atribuição — por que "ninguém viu"

### 3.1 O modelo (4 camadas)

- **Administrator** vê tudo da conta. Em prod, **26 dos 30 usuários são admins** (incluindo a equipe de triagem — Maria Vitoria etc.); só os 4 corretores de disparo (Kettlen, Lucas, Marcus, Bruno) têm a custom role "Corretor" (`conversation_participating_manage` = lista/abre **só o atribuído a ele**).
- **Não existe "ver sem operar"**: a mesma permissão que dá visibilidade dá operação (`show?` é o único gate de todos os endpoints de conversa).
- **Filtro de time do fork** (`conversation_finder.rb:212-216`): agente em qualquer time **deixa de ver conversas sem time** na lista — bomba latente (conversas de disparo não têm team). Não afeta admins.
- **Participantes** = mecanismo nativo de "cc": dão acesso unitário + view "Participando" sem mudar assignee — ideal pra supervisão pontual e escalação (a IA pode adicionar/remover via API).

### 3.2 O diagnóstico real do incidente

A secretária (admin) **podia** ver — mas a conversa do lead que respondeu: (a) não estava em "Não atribuídas" (fila de triagem dela), porque continuava atribuída ao corretor; (b) estava afogada entre 6.508 abertas; (c) o corretor não percebeu porque `assigned_conversation_new_message` (lead respondeu na SUA conversa) **não gera push nem e-mail por default** — só o sininho. O único tipo com entrega ativa de fábrica é `conversation_assignment`. **O elo quebrado é notificação + higiene de fila, não permissão.**

### 3.3 Os números de prod (10/06)

- Inbox 91: 6.508 open / 7.009 resolved. Por assignee: Lucas 1.781, Kettlen 1.718, Bruno 1.649, Marcus 961 (≈disparos), Gelson 282, Adrian 70…
- **432 conversas abertas cuja última mensagem é incoming há >12h** (Bruno 151, Kettlen 149, Marcus 61, Lucas 59, Natália 9…) — a fila real de "lead esperando".
- 1.618 resolved com assignee (reply futuro reabre e a #53 zera — design atual de triagem).
- 143 contatos ainda com >1 ficha e 115 com >1 conversa — **resíduo histórico** (jan–mai, última em 03/06), fora do escopo da consolidação dos 275. Sem re-duplicação ativa desde então.
- Automation rules ativas: só a **#53 "iniciar zerado"** (`conversation_opened`, inboxes 61/62/91 → assignee nil + team nil). As #45/#54 (tentativas de abrir por mensagem) estão inativas.
- 13 times funcionais (espelham os funis; Maria Vitoria em quase todos) + 5 times "X - disparo". 19 funis (operacionais por assunto + "Pré-Venda Tozi" #41 + funis por corretor de disparo).
- Labels relevantes: `atendimento` (router skip da Clara), `bot-ia`, `lead-spl-2026`, `interagiu-spl-2026`. Custom attributes já definidos: `resumo`, `atendimento`, `intencao` (conversa).

### 3.4 A regra #53 — entender antes de mexer

Ela é a triagem-por-reabertura de hoje: conversa resolvida + lead volta → reabre → zera dono → cai em "Não atribuídas" → secretária tria. Funciona **só** pra conversas resolvidas; falha nas abertas (caso das 432). E é **determinística contra qualquer atribuição** feita antes do seu turno async (last-write-wins) — inclusive contra: a atribuição do disparo no reopen, o auto-open da Clara (`ensure_conversation_open` emite `conversation_opened` com `performed_by=Captain::Assistant`, que NÃO é ignorado pelo anti-loop), e qualquer atribuição futura da IA. **Conclusão: a regra #53 e a IA orquestradora são mutuamente exclusivas no médio prazo** — a IA assume a função dela (triagem com dono certo, em vez de triagem por zerar).

---

## 4. Ciclo de vida da conversa e o limbo pending

- Estados: `open / resolved / pending / snoozed`. Fork adiciona 2 gates: `pending` só se a inbox habilitar (`pending_status_enabled`); **resolver exige team** (`team_required_for_resolution` — afeta auto-resolve, mute!, widget; conversa de disparo sem team não resolve sem skip).
- Incoming em conversa resolved: **com bot ativo → `pending!`** (invisível na aba default + `NotificationListener` ignora pending = invisibilidade dupla); sem bot → `open!`.
- **O limbo está 80% resolvido no código local** (o STATE estava desatualizado): (1) commit `f96ae7740` — quando o router aprova a IA atender, a conversa é promovida pending→open; (2) o override Enterprise `mark_pending_conversation_as_open_for_human_response` (`enterprise/app/models/enterprise/message.rb`) **existe e está ativo** via prepend — resposta humana pública abre a pending (o stub OSS `captain_pending_conversation? → false` é sobrescrito). **Residual:** quem cai em `router_skip` (whitelist/labels/grupos) continua pending invisível — em piloto com whitelist, TODO lead real é "ruído". O go-live precisa de política explícita (recomendação: piloto por % ou por inbox de teste, nunca por whitelist longa em produção viva).
- Snooze: indefinido (via automação) só sai com incoming. Cadência HSM **não reabre** a conversa (outgoing não passa por reopen) — HSM de reativação pode sair em conversa resolved que permanece resolved.

**Bugs latentes confirmados** (nenhum bloqueia hoje, todos com file:line nos relatórios): `reopen_resolved_conversation` não checa `pending_status_enabled` (RecordInvalid dentro de after_commit aborta callbacks da mensagem); `router.skip_agent_bot` referencia atributo inexistente (`NoMethodError` se ligar a flag); copilot `send_template` passa `template_params` no lugar errado (a tool nunca envia template de verdade); humanizer `sleep` de até 7s/chunk segura thread do Sidekiq; handoff por cota esgotada manda string em inglês.

---

## 5. O que a IA JÁ pode fazer (e o que falta)

### 5.1 Capacidades atuais por plano

| Capacidade | Agente autônomo (Clara) | Copilot (humano invoca) |
|---|---|---|
| Atribuir a agente/time | ⚠️ Só `handoff` → round-robin entre membros **online** da inbox, sem direcionamento (TODO de `team_id` anotado no código) | ✅ `assign_conversation(agent_id, team_id)` |
| Status (abrir/resolver/snooze) | ⚠️ resolve gateado pelo kill-switch do auto-resolve; abre só via handoff | ✅ `change_status` qualquer |
| Etiquetar | ✅ (valida contra catálogo) | ✅ |
| Mover funil | ⚠️ Só efeito colateral (`programar_followup`→em_silencio; `salvar_info_lead`→qualificado/frio) — sem tool `mover_card` | ❌ |
| Mensagem em OUTRA conversa | ❌ (tools presas à conversa corrente via state) | ✅ `send_message(conversation_id)` |
| HSM fora da janela | ❌ direto (só a cadência determinística) | ⚠️ `send_template` existe mas tem o bug do template_params |
| CRM Vista / geocoding / fotos | ✅ | ⚠️ via custom tools |
| Consultar carga de agentes/times/stats | ❌ | ✅ `get_agent_workload`, `get_team_info`, `get_account_stats` |
| Follow-up agendado | ✅ `programar_followup` (2min–2d, MAX 4, quiet hours) → cadência HSM 1d/3d/7d ao esfriar | — |
| Memória do lead | `conversation.custom_attributes` (salvar_info_lead) + `contact.custom/additional_attributes` (se `feature_contact_attributes`) + histórico integral da conversa única. **Notas geradas pelo `feature_memory` NUNCA voltam ao prompt** (write-only) | lê tudo via `get_contact`/`get_conversation` |

### 5.2 A ponte copilot→agente está pronta

`HttpTool` roda nos dois planos; portar uma copilot tool pro agente = ~20 linhas no padrão `BasePublicTool` (provado 4× pelas tools Tozi) + registro em `config/agents/tools.yml`. **A decisão é de produto/segurança, não técnica**: agent tools não têm checagem de permissão — os guardrails (agente pertence à inbox? time permitido?) têm que ser construídos na própria tool.

### 5.3 Mecanismos de orquestração descobertos no mapeamento (subutilizados)

- **SLA Enterprise funciona e está no cron** (5 min): policy nrt-only aplicada por automação = "lead esperando resposta humana há X" com notificação nativa a admins+assignee+participantes. Caveats: AppliedSla morre na primeira resolução da conversa (ruim com conversa única — usar snooze em vez de resolve, ou re-arm), business hours ignorado, entrega push/email default OFF.
- **Labels → automação**: Clara etiqueta `nicho:locacao` → `CONVERSATION_UPDATED` (performed_by=assistant, não suprimido) → automation rule `assign_team` + `add_sla`. **Triagem por nicho sem código novo.** Provisionar o catálogo de labels antes (a tool valida contra `Label` existente).
- **`directive:` no ResponseBuilderJob**: qualquer orquestrador pode "acordar" a Clara numa conversa com instrução interna (é como o follow-up funciona) — primitivo genérico de IA proativa.
- **`ContactAttributesService` órfão**: extração LLM de atributos do lead pro contato está 80% pronta (prompt incluso) e desligada — é a memória estruturada ideal, porque `contact.custom_attributes` JÁ entram no prompt (diferente das notas).
- **Webhooks de conta** (por evento, com HMAC) = espelho externo pro CRM/Vista — mas hoje são **at-most-once** (Trigger engole exceções; o retry declarado nunca roda). Fix de 1 linha (re-raise) destrava entrega confiável.
- **`Current.executed_by`** = moeda de autoria em todos os eventos/atividades — a orquestradora deve se identificar nela (auditoria de quem-fez-o-quê IA×humano×automação).

---

## 6. Conversa única por contato — posição

A decisão (1 conversa, fecha/reabre) **deve ser mantida**, e o incômodo organizacional resolvido por outra dimensão. Razões:

1. **O canal é assim.** Pro cliente o WhatsApp é um fio único; múltiplas conversas abertas pro mesmo wa_id criam exatamente os replies órfãos que acabamos de consolidar. O `lock_to_single` é a defesa estrutural contra a classe inteira de bugs do 9º dígito.
2. **A organização que você sente faltar não precisa vir do objeto Conversation.** O modelo já oferece três eixos ortogonais ao fio:
   - **Funis**: `FunnelItem` é único por (conversa, funil) — **a mesma conversa pode ter cards em N funis** (locação, manutenção, pré-venda…). O "assunto" vive no card, não na conversa. Os 19 funis de prod já operam assim.
   - **Labels + custom attributes** (`intencao` já existe em prod) = classificação do momento.
   - **Episódios = ciclos open→resolved**: `reporting_events` (first_response, resolved, bot_handoff) medem cada ciclo separadamente — métricas por episódio existem mesmo com fio único.
3. **O que aceitar como custo**: o histórico misto (disparo + suporte + venda no mesmo fio) — que aliás virou benefício no incidente (corretor passou a ver tudo); e SLA/applied_sla terminal por conversa (contornável com snooze/re-arm).

**Recomendação prática:** manter `lock_to_single`, levar o fix de conversa-única pra TODOS os produtores (disparo ✅ feito; Lead Ads pendente; "Nova conversa" da UI pendente) e investir a energia organizacional em funil+labels — onde a IA consegue operar.

---

## 7. Evals — o que existe e o desenho recomendado

**Sua expectativa** (uma IA paralela monitorando a IA atendente e o uso das ferramentas) **tem fundação no fork**:

1. **Conector pronto**: a copilot tool `get_conversation_analysis` consome um serviço externo de **LLM-as-a-Judge** (`TOZI_EVAL_API_URL`, default `127.0.0.1:8910/report`, token via env/InstallationConfig, gateado por conta) que reporta: interesse, intenção, estágio de funil percebido, objeções, falhas por agente, timing de handoff. **O serviço em si não existe ainda** (porta 8910 vazia na VM) — o fork preparou a tomada.
2. **Trilha de decisões já gravada**: `Captain::AssistantLog` registra cada decisão do runtime (response, router_skip, debounce_fire, business_hours_skip, handoff, dedup_skip, humanizer_split, copilot_trigger, error) ligada a conversa+mensagem — o "flight recorder" da Clara.
3. **Precedente de judge inline**: o modo `evaluated` do auto-resolve (`ConversationCompletionService`) já usa LLM pra julgar "conversa completa?".

**Desenho recomendado (assíncrono, não inline):** um worker de eval batch (pode ser processo separado na própria VM, na porta 8910 que a tool já espera) que a cada N horas: (a) varre conversas com atividade recente; (b) julga com rubrica fixa — qualificação correta? tom? alucinação? tools usadas quando deviam? handoff no momento certo? humano deixou lead esperando? — tanto pra IA quanto pra atendimento humano; (c) grava veredito estruturado (tabela própria ou custom_attributes) e alimenta o relatório da tool `get_conversation_analysis`; (d) alerta (nota privada/menção/label `eval:atencao`) quando encontra problema acionável. **Não** recomendo IA-observadora em tempo real por mensagem: dobra o custo de LLM por turno com valor marginal — o batch de hora em hora captura os mesmos problemas a tempo de agir, e o `AssistantLog` + SLA cobrem o tempo-real determinístico.

## 8. Copilot — o que existe e o que falta pra sua visão

A sua expectativa ("IA chamada pelo humano dentro da conversa, com insights e sugestão de resposta") **já está ~80% construída**:

- **Painel Copilot** no front (`components-next/copilot/`) + `Captain::Copilot::ChatService` com **32 tools** (busca conversas/contatos/mensagens, carga de agentes, CSAT, atribuir, resolver, etiquetar, mandar mensagem/template, transferir inbox…), com loop agêntico e permissões espelhando o usuário humano que invocou.
- **Gatilho `#copilot` em nota privada** (`CopilotTriggerService`) — o equivalente do `#tozi` do n8n — **existe mas está semifuncional**: não passa `user_id` (logo as tools de ação ficam inativas) e a resposta é descartada (não vira nota privada). Dois fixes pequenos o transformam no canal humano→IA dentro da conversa.
- **Gap funcional vs n8n**: o copiloto antigo buscava imóveis/localização pro atendente. Conferir/levar as tools Tozi (`buscar_imovel` etc.) pro plano copilot (a infra `HttpTool`/custom tools já pluga nos dois).
- **Bug a corrigir**: `send_template` do copilot monta `template_params` dentro de `additional_attributes`, mas o `MessageBuilder` só lê top-level — a tool hoje não envia template de fato.

---

## 9. Arquitetura-alvo: a IA orquestradora

```
                         ┌────────────────────────────────────────────┐
   ENTRADAS              │           ORQUESTRAÇÃO (SPX)               │         HUMANOS
                         │                                            │
 inbound orgânico ──┐    │  HookExecutionService (inline, síncrono)   │   secretária (triagem)
 disparos de lista ─┤    │   └─ router → Clara atende? → open         │     vê “Não atribuídas”
 meta lead ads ─────┼──▶ │  Spx::OrchestratorListener (async, pos. 2) │     + SLA + menções
 outbound manual ───┘    │   └─ triagem: classifica → label nicho:*   │
                         │  AutomationRules: label → assign_team      │   corretores (role restrita)
                         │  HandoffTool v2: team_id + roleta nicho    │     push/e-mail LIGADOS
                         │  Funil = state store (FunnelPlacement)     │     recebem só o seu nicho
                         │  Follow-up: agente (24h) → HSM (1d/3d/7d)  │
                         │  SLA nrt = despertador “lead esperando”    │   gerente/admin
                         │  Eval worker (8910) = observador batch     │     get_conversation_analysis
                         └────────────────────────────────────────────┘     campanha stats
```

**Princípios (derivados das decisões já tomadas):**
1. Conversa única por contato; o fio é do cliente, o **estado é do funil**.
2. Toda atribuição implica visibilidade + notificação entregue (push/e-mail ligados) — atribuir sem notificar é o bug original.
3. A IA se identifica (`Current.executed_by = assistant`) e loga (`AssistantLog`) toda decisão.
4. Janela 24h arbitra o canal: dentro = texto do agente; fora = HSM via `ScheduledMessages.template_params`.
5. Config code-first: tudo dirigido pelo `behavior` JSONB + automation rules + labels — sem deploy pra ajustar política.
6. A regra #53 morre quando a triagem orquestrada assumir (ela é a versão burra da mesma função).

---

## 10. Plano de execução (fases)

### Fase 0 — Higiene e fundação (destrava tudo; ~1 semana)
1. **Reconciliar `paulao` ↔ `rollout`** (P0 absoluto — plano pronto em `docs/RECONCILIACAO-BRANCHES-2026-06-08.md`): 6 commits/59 arquivos só no notebook; cada redeploy de prod re-dropa followup_hsm_job/lógica inq/asset. Trazer também a versão SAFE da migration landmine pra `paulao` (hoje a branch local carrega a bomba e prod o desarme).
2. **Patch cirúrgico do fix `11b913531` em prod** (conversa única no disparo) + restart worker — pendente só de aval.
3. **Ligar notificações dos corretores** (script one-time em `notification_settings`): `push/email_assigned_conversation_new_message` + `conversation_mention` + garantir webpush/subscription. **Resolve o "corretor não fica sabendo" hoje, sem nenhuma feature nova.**
4. **Mutirão das 432**: relatório por corretor (query pronta da auditoria) → triagem manual → zerar a fila.
5. **Higiene da fila "Abertas"**: política pra conversas de disparo sem resposta (resolver após X dias com team setado — a cadência HSM cuida do re-engajamento; "Abertas" volta a significar trabalho humano real). Hoje 6.508 abertas ≈ ruído.
6. Recuperar `inq-mapa.jpeg` (candidato: attachment 411283 da resposta rápida `/interesse`) e versionar assets.
7. Consolidar as 143 duplicatas históricas (mesmo script, escopo ampliado) + implementar o reconciliador do incoming (preferir ficha da conversa mais recente — ~1 método + 1 spec).

### Fase 1 — Triagem orquestrada + go-live da Clara
1. Pré-go-live: o limbo pending está mitigado no código (f96ae7740 + override Enterprise — **validar que ambos estão em prod pós-reconciliação**); definir política pro `router_skip` (piloto por inbox/percentual, não whitelist longa); manter auto-resolve `disabled`.
2. **HandoffTool v2**: aceitar `team_id`/nicho (TODO já anotado no código), com fallback quando ninguém online (fila da secretária + menção) — hoje termina silenciosamente sem dono.
3. **Triagem por labels**: catálogo `nicho:*` + tool de etiquetar no cenário da Clara + automation rules `label → assign_team` (+ `add_sla` nrt). Times já existem e espelham os assuntos.
4. **Substituir a #53**: nova regra/listener que devolve pra triagem **só** conversas órfãs reais (reopen sem dono ativo), preservando atribuição de disparo/IA.
5. Reconectar `CaptainInbox(91, Clara)` em piloto → medir com `AssistantLog` + eval → ampliar.
6. Meta Lead Ads: aplicar `resolved_source_id` + 1ª-mensagem-HSM + idempotência por leadgen_id → apontar callback pra prod.

### Fase 2 — Follow-up e cadência completos
1. Disparo coloca lead no funil (`aguardando_1a`) — fecha o buraco do cancel-on-reply (hoje lead de disparo fora do funil não cancela cadência ao responder).
2. Cancel-on-reply genérico: marcador de origem na `ScheduledMessage` (cancelar por incoming, não por estágio).
3. Expor `template_params` na API de scheduled_messages (1 permit) + sweeper de pendentes órfãos.
4. SLA: policy nrt-only via automação no primeiro incoming; secretária como participante nas escaladas; decidir snooze-vs-resolve pra conversa única (recomendo **snooze** pra leads em cadência — preserva o AppliedSla).
5. `FollowupHsmJob` com suporte a header de imagem (destrava a 2ª leva de inquilinos).

### Fase 3 — Campanhas como módulo
Entidade persistida `CampaignDispatch` (audiência snapshot, pacing, rotação, round-robin, status pausável) + form de criação na UI (o `WhatsAppCampaignForm.vue` órfão é a base) + stats por template (group-by que falta no `campaign_stats` — é o payoff do A/B nunca medido) + **gate de saúde do número** (health check antes de cada lote; pausa automática em YELLOW/RED) + detalhe vivo com pausar/retomar.

### Fase 4 — Evals + Copilot
1. Worker de eval (porta 8910, contrato que `get_conversation_analysis` já espera) com rubrica IA+humanos; alertas via nota privada/menção/label.
2. Consertar `#copilot` (user + postback como nota privada) e o `send_template` do copilot; levar tools Tozi pro plano copilot.
3. Tools de orquestração pro agente: `atribuir(team/nicho)`, `mover_card(stage)`, `agendar_hsm` — todas com guardrails na tool (validar inbox/time).
4. Completar `ContactAttributesService` (memória estruturada do lead que volta ao prompt).

### Fase 5 — Generalização multi-cliente
De-hardcode (`INBOX_ID`, brokers, templates, funil por nome → config por inbox/assistant no `behavior` JSONB ou model próprio), gates por conta nos listeners globais, specs nos fluxos críticos (hoje **zero** specs em 705 arquivos custom — risco R1 da auditoria de 04/06).

---

## 11. Inventário de riscos/bugs achados no mapeamento (além dos já conhecidos)

| # | Item | Gravidade | Onde |
|---|---|---|---|
| 1 | Regra #53 zera atribuição de QUALQUER `conversation_opened`, inclusive futuro auto-open da Clara | 🔴 design | prod + `automation_rule_listener.rb` |
| 2 | Notificações `assigned_conversation_new_message` default OFF (push/email) | 🔴 operação | `account_user.rb:46-51` |
| 3 | Lead Ads: source_id com `+` + sem idempotência (futura fábrica de duplicatas) | 🔴 antes do switch | `create_conversation_service.rb:98-123` |
| 4 | Webhooks de conta at-most-once (retry inerte) | 🟠 integração | `lib/webhooks/trigger.rb:16-29` |
| 5 | Copilot `send_template` não envia template (params no lugar errado) | 🟠 | `send_template_service.rb` |
| 6 | `router.skip_agent_bot` → NoMethodError se ligado | 🟠 latente | `router_service.rb:98` |
| 7 | Backfill do Kanban despeja conversas open/resolved no 1º estágio do funil Tozi a cada GET do board (868 cards "Novo Lead" em prod têm essa origem) | 🟠 | `funnel_items_backfill_service.rb` |
| 8 | Kanban não respeita custom role (corretor vê todos os cards) + filtro por label do kanban quebrado | 🟠 | `funnel_item_policy.rb` / `KanbanBoard.vue:185-191` |
| 9 | `reopen_resolved_conversation` sem checar `pending_status_enabled` → RecordInvalid aborta callbacks da mensagem | 🟠 latente | `message.rb:466-476` |
| 10 | Arrastar card pra coluna automation_type=resolved RESOLVE a conversa (alimenta limbo com bot) | 🟡 | `funnel_items/move_service.rb:34-44` |
| 11 | Humanizer/debounce com sleep dentro do worker (esgota concorrência sob volume) | 🟡 | `response_builder_job.rb:205-241` |
| 12 | Cadência HSM: sem quiet hours, sender = 1º admin (não o corretor), 3 passos agendados de uma vez | 🟡 | `reactivation_cadence_service.rb` |
| 13 | `to_llm_text` espelha PII integral (incl. notas) também no backend de traces OTel/Langfuse | 🟡 privacidade | `contact_llm_formatter.rb` |
| 14 | EventDispatcherJob: retry re-executa listeners não-idempotentes; 15 threads = last-writer-wins sem lock | 🟡 estrutural | `event_dispatcher_job.rb` |
| 15 | `waiting_since` nasce sujo em conversa de disparo (distorce SLA frt e reporting do 1º ciclo) | 🟡 métricas | `disparo_lead_job.rb` + `conversation.rb:302` |

---

## 12. Referência rápida — superfícies de orquestração

- **Eventos**: listener custom no `AsyncDispatcher` (posição 2 = vê estado pós-automação no mesmo evento; rescue + idempotência obrigatórios).
- **REST**: `assignments`, `toggle_status`, `labels`, `custom_attributes`, `participants`, `bulk_actions`, `macros/:id/execute`, CRUD `automation_rules`, `funnel_items` (+`bulk_move`), `scheduled_messages`, `campaigns/:id/stats`, `inboxes/:id/health`, `message_templates`, `sla_policies`.
- **Tools**: `config/agents/tools.yml` (agente) / `TOOL_CLASSES` do `Copilot::ChatService` / `Captain::CustomTool` (HTTP dinâmico com headers X-Chatwoot-* de contexto).
- **Config**: `behavior` JSONB do assistant (PUT `/captain/assistants/:id`).
- **Estado do lead**: `FunnelPlacementService.move/current_type` + `custom_attributes` (`atendimento_humano` trava a IA; `tozi_status_lead`; `intencao`).
- **Telemetria**: `Captain::AssistantLog`, `reporting_events`, `campaign_stats`, `sla_events`, status de mensagem (`external_error` com códigos Meta).
