# Mapeamento — Estado operacional e dívidas documentadas (área: docs-operacao)

> Data: 2026-06-10 · Branch local: `paulao` · Análise documental + verificação pontual em código (read-only).
> Fontes lidas integralmente: `.claude/STATE.md`, `docs/RECONCILIACAO-BRANCHES-2026-06-08.md`, `docs/clientes/tozi/RELATORIO-DISPAROS-TOZI-2026-06-08.md`, `docs/clientes/tozi/TEMPLATES-DISPARO-TOZI.md`, `docs/AUDITORIA-SPX-2026-06-04.md`, `docs/clientes/tozi/HANDOFF-2026-05-29.md`, `docs/backlog/reconciliador-incoming-9-digito.md`, `ONBOARDING.md`.
> Código verificado para ancorar referências: `app/jobs/spx/tozi/disparo_lead_job.rb` (178 linhas), `app/jobs/spx/tozi/followup_hsm_job.rb` (40 linhas), `db/migrate/20260330120000_add_foreign_key_constraints.rb` (99 linhas), `app/services/whatsapp/phone_number_normalization_service.rb` (70 linhas), `scripts/spx/tozi/` (18+ scripts), `app/services/spx/tozi/`, `app/listeners/spx/tozi/`, `enterprise/lib/captain/tools/`.

---

## 1. Dívidas e bloqueios abertos — lista consolidada e priorizada

### 🔴 P0 — Integridade do trabalho e do banco (risco de perda)

#### P0.1 — Divergência `paulao` (local) ↔ `rollout/release-20260605` (prod) — trabalho crítico vive em UM lugar só
**Fonte:** `docs/RECONCILIACAO-BRANCHES-2026-06-08.md` (TL;DR e §Topologia). **Plano levantado em 08/06, explicitamente "NÃO executado".**

- Prod **não roda** `paulao` nem `producao` — roda uma branch **local-de-prod** `rollout/release-20260605` (deploy 08/06 01:48) que **não existe no origin** (só no servidor AWS).
- A `paulao` local tem **6 commits / 59 arquivos / 2.460 inserções que existem APENAS no notebook** (nem em `origin/paulao`, que parou em `71629abe1` de 01/06, nem na rollout): `11b913531` (frente-1 disparo), `ed1b90a54`, `cd409845a` (filtro não-lidas), `6ee421881` (tela stats campanha), `1133a6fd6` (anexo canned), `d88e51c55` (orquestrador disparo HSM + inquilinos/imagem + scripts).
- A rollout tem o que a paulao **não** tem: migration landmine **versão SAFE** (`fc0f9afdf` — "nullify + abort-and-list"), fix WAHA F5 realtime (`a4a098bd9`), manual de marca, `.gitattributes` eol=lf.
- 3 features (canned anexo / campaign stats / blaster off) existem **nos dois lados via commits diferentes** → merge direto **conflita** em `campaigns_controller.rb`, `ReplyBox.vue`, `config/routes.rb`, `app/models/campaign.rb`, canned-response/*, `.claude/STATE.md` (§Conflitos esperados).
- **Decisões abertas pro Paulo** (§final do doc, nenhuma marcada): autorizar `git push origin paulao`; autorizar push da rollout pro origin; confirmar rollout como canônica; definir processo oficial de deploy.
- **Implicação pra orquestração IA:** qualquer feature nova de orquestração construída sobre a `paulao` local cai no mesmo buraco até a reconciliação acontecer. A reconciliação é pré-requisito de QUALQUER deploy novo.

#### P0.2 — Código e assets off-git somem a cada redeploy da rollout
**Fonte:** `.claude/STATE.md` entradas [2026-06-08] ("CONVERSA ÚNICA" e "Follow-up 2ª leva").

- O deploy das 01:48 de 08/06 **dropou**: `public/inq-mapa.jpeg` (→ **404**; é o header de imagem dos templates `tozi_inq_lancamento`/`tozi_inq_invest` — envio de imagem falharia porque a Meta busca a URL no momento do envio); e o `app/jobs/spx/tozi/followup_hsm_job.rb` (**`uninitialized constant Spx::Tozi::FollowupHsmJob`** em prod durante o disparo de 09/06 — restaurado via scp do repo local + restart do worker, "mas é remendo").
- O `disparo_lead_job.rb` em prod tem **124 linhas** (pré-inquilinos) vs **178 no repo local** (verificado: a versão local tem `NO_BODY_VAR`/`INQ_IMAGE_URL` em `disparo_lead_job.rb:56-62` + `resolved_source_id`/`find_or_create_conversation` em `:112-143`). Confirmado na tabela comparativa de `docs/RECONCILIACAO-BRANCHES-2026-06-08.md` (§"O que cada lado tem").
- STATE: "⚠️ Cada vez que prod for redeployado da rollout, esse job (e a imagem, e a lógica inq) **somem de novo**. Reconciliar a rollout com a paulao é o conserto definitivo."
- Imagem possivelmente recuperável: anexo `mapa-localizacao.jpeg` da resposta rápida `/interesse` (attachment id 411283 em prod), "*se for o mesmo mapa*" (STATE 06-08).

#### P0.3 — Migration landmine `20260330120000_add_foreign_key_constraints`
**Fontes:** `docs/AUDITORIA-SPX-2026-06-04.md` §3.2 (R2, 🔴 Crítico); `.claude/STATE.md` [2026-05-29] "Deploy AWS — GOTCHAS"; `docs/RECONCILIACAO-BRANCHES-2026-06-08.md` (commit `fc0f9afdf`).

- A versão **local** (`db/migrate/20260330120000_add_foreign_key_constraints.rb:63-75`) ainda é a **DESTRUTIVA**: `DELETE FROM <from> WHERE NOT EXISTS (...)` antes de cada FK, ordenada de propósito para que os cascades em filhos de `conversations` existam antes da limpeza — apagar conversation órfã cascateia para `messages`, `mentions`, `scheduled_messages`, `funnel_items`, csat/nps, `reporting_events` (linhas 10-27 da migration). `disable_ddl_transaction!` (linha 2) significa **sem rollback** se falhar no meio. `safety_execute` (linhas 94-98) só **loga**, não protege. Auditoria: "Só disciplina humana evita o desastre".
- A rollout (prod) tem a versão **SAFE** (`fc0f9afdf` "nullify + abort-and-list") — que **não está na paulao local**. Ou seja: hoje a branch de trabalho local carrega a bomba e prod carrega o desarme.
- **Agravante (Auditoria §3.2):** `db/schema.rb` versionado já contém as FKs da landmine e `template_params` (dump de dev onde a landmine rodou) → o `version:` do schema **não é confiável**; `db:schema:load` acidental reconstrói o banco com cascades ativos.
- **Contradição registrada a investigar (STATE 06-08, Frente 1):** `migrate:status` em prod retornou **0 down**, "⚠️ contradiz o STATE que dizia a landmine `20260330120000` down — investigar se foi aplicada" (provavelmente a versão SAFE da rollout rodou no deploy de 08/06; não confirmado em doc).
- Outras 3 migrations destrutivas com `down` no-op (Auditoria §3.2): `20260203180000` (FunnelItem.delete_all), `20260317204605` (DELETE notifications/participants/mentions), `20260317214100` (UPDATE massa dedup conversations).

#### P0.4 — Frente-1 do disparo (fix anti-duplicata) commitada local, NÃO deployada
**Fonte:** `.claude/STATE.md` [2026-06-08] "CONVERSA ÚNICA POR CONTATO", Frente 1.

- O fix da causa-raiz das duplicatas (`resolved_source_id` usando `Whatsapp::PhoneNumberNormalizationService` + `find_or_create_conversation`) está no commit local `11b913531` (`disparo_lead_job.rb:84` e `:121-143`) mas **prod ainda roda a versão sem ele**.
- Deploy planejado = **patch cirúrgico in-place** (3 pontos), NÃO transporte do arquivo inteiro (clobberaria a versão prod que está atrás). **PENDENTE: aval do Paulo** + restart `chatwoot-worker.1`. "Não urgente (bleeding já parado pela consolidação; frente 1 só previne disparo futuro)."
- A consolidação (Frente 2) **já foi aplicada e verificada em prod**: 275 contatos fundidos, 810 msgs movidas, 298 conversas + 203 fichas apagadas, 0 contatos com >1 conversa/ficha após. Script versionado: `scripts/spx/tozi/consolida_conversas_duplicadas.rb`.

### 🔴 P1 — Go-live da Clara (IA) — plano com pré-requisitos 1-4
**Fonte:** `.claude/STATE.md` [2026-06-02] "PLANO DE GO-LIVE DA IA (prioridade — resolver o quanto antes)". Clara (#7) está **DESCONECTADA da inbox 91** desde o incidente de 02/06.

1. **Pré-req reabertura (pending limbo):** religar a Clara faz `active_bot?` voltar `true` → resposta de cliente em conversa resolvida vira **pending invisível** de novo (`Message#reopen_resolved_conversation`: inbox com bot → `pending!` em vez de `open!`). Resolver com (a) Clara atendendo de verdade (sem whitelist) e abrindo a conversa, **ou** (b) corrigir o código — `mark_pending_conversation_as_open_for_human_response` está **stubbado `false`** em `app/models/message.rb` (`captain_pending_conversation?` retorna false), "então nem resposta humana abre a pending".
2. **Whitelist:** sair de `behavior.router.only_contact_phones=["+5566996350491"]` de forma controlada (piloto com N leads → geral).
3. **Auto-resolve:** manter `captain_auto_resolve_mode='disabled'` OU reconfigurar com cuidado (mensagem PT decente, gateado, sem loop pending→resolve). Contexto: incidente 02/06 — auto-resolve fechou ~17 convs presas em pending com mensagem "Resolvendo a conversa dado que está inativa..." (57 PT + 55 EN, inboxes 61/62/91). Trava dupla aplicada no código (scheduler linha 15 + job linha 8: `return if captain_auto_resolve_disabled?`).
4. **Reconectar:** recriar `CaptainInbox(inbox_id=91, captain_assistant_id=7)` **só depois** dos 3 acima; testar E2E que cliente que volta é atendido (não fica pending).
- Cérebro já validado/staged: prompt Júlia (Scenario Vendas #5, 6.274 chars) + knowledge (1 doc Playbook 19 chunks + 40 Q&A nativas, modo hybrid) + tools (`buscar_imovel` via `TOZI_VISTA_API_KEY`, geocoding com chave embutida na endpoint_url).
- **Bug residual conhecido (não corrigido, STATE 06-02):** `reopen_resolved_conversation` manda pra `pending!` em inbox com bot — "ok SE o bot atende; vira limbo se o bot está calado (whitelist). Tratar no go-live (item 1)."

### 🟠 P1 — Gap Meta Lead Ads → Cloud API (lead de formulário "morre")
**Fontes:** `.claude/STATE.md` [2026-05-29] §"Falta"; `docs/AUDITORIA-SPX-2026-06-04.md` §3.4 item 7.

- `create_initial_message` (`app/services/meta/lead_ads/create_conversation_service.rb:129`) manda **texto livre**. Na inbox 91 (Cloud API), a 1ª mensagem a um lead de formulário (sem sessão aberta) é **bloqueada pela Meta** — fora da janela de 24h só HSM passa. **Construir: 1ª-mensagem-como-HSM** (`tozi_lead_abertura`, id 2078242513112579, já APPROVED — `docs/clientes/tozi/TEMPLATES-DISPARO-TOZI.md` §Lead) via `template_params` quando `inbox.whatsapp?`. Sem isso, ativar o hook = leads entram no funil mas não recebem abertura.
- Meta-side (Paulo): trocar o callback do app Meta pra `https://tozi.chatspx.app/webhooks/meta_lead_ads` (hoje aponta pra PAULAO).

### 🟠 P2 — Cadência Bloco 3+4 — implementada, falta TUNING
**Fontes:** `.claude/STATE.md` [2026-05-29] "Bloco 3+4 DEPLOYADO"; `docs/clientes/tozi/HANDOFF-2026-05-29.md` §5.4 (escrito ANTES da implementação — superado pela entrada do STATE do mesmo dia).

- **Já em prod (29/05):** Bloco 3 = `Spx::Tozi::FunnelAutomationListener` (Wisper/AsyncDispatcher, rescue-wrapped) + `FunnelPlacementService.move` — transições incoming→em_conversa (+cancela cadência), handoff→qualificado, programar_followup→em_silencio, followup MAX→frio, salvar_info_lead→qualificado/frio. Hooks em `enterprise/lib/captain/tools/{programar_followup,salvar_info_lead}_tool.rb` + `followup_job.rb`. Bloco 4 = `ScheduledMessages` com `template_params` (jsonb) + `Spx::Tozi::ReactivationCadenceService` (HSM 1d/3d/7d, só Cloud API, idempotente, cancel-on-reply). Regra: **dentro da janela 24h = follow-up do agente; fora = HSM determinístico; o estágio do funil arbitra.**
- **Pendências (STATE 29/05 §Falta):** tuning de produto — "cadência até 4 cutucadas in-window + 3 HSM; `agendado`/`aguardando_1a` sem trigger automático"; reconciliar corpos exatos dos templates v2 com o WABA; teste E2E em prod (dependia do hook Meta ou teste manual). Funil "Pré-Venda Tozi" id=41 (stages 127-133) criado em prod; backfill = 0 leads (hook Meta nunca rodou em prod).

### 🟡 P2 — Reconciliador do 9º dígito no incoming (defensivo)
**Fonte:** `docs/backlog/reconciliador-incoming-9-digito.md` (status: proposto, prioridade **baixa** — "cinto-e-suspensório").

- `Whatsapp::PhoneNumberNormalizationService#normalize_and_find_contact_by_provider` retorna a **primeira** ficha que casar nas variantes 12d/13d (`app/services/whatsapp/phone_number_normalization_service.rb`); se um contato tiver 2 fichas, o reply pode cair na "errada". Proposta: com 2+ matches, escolher a ficha da **conversa mais recente** (thread viva); early-return em `matches.one?` preserva o hot-path.
- Não urgente porque a fonte de duplicatas foi fechada: (1) consolidação 08/06; (2) frente-1 do `DisparoLeadJob`. Só importa se duplicata surgir por **outro** caminho (outra integração, import). Esforço: ~1 método + 1 spec; camada OSS, sem override Enterprise; tem specs existentes em `spec/services/whatsapp/phone_number_normalization_service_spec.rb`.

### 🟡 P2 — Riscos estruturais da auditoria (`docs/AUDITORIA-SPX-2026-06-04.md`)
- **R1 (🔴): zero specs no código custom** (§3.1) — `DisparoLeadJob`, funil, cadência, Meta Lead Ads, 7 behavior services, tools, `campaign_stats`, `template_params`, canned-anexo: **nenhum** spec em 705 arquivos. Mitigação sugerida: 3 specs de alto valor (disparo, SignatureVerifier/FetchLead, cadência).
- **R3 (🟠): operação 100% via console SSH** (§3.3) — disparo/pausa/dedup/ativação IA/kill-switch tudo `rails runner` na AWS; sem trilha de auditoria; sem guard-rails; **hardcode Tozi**: `DisparoLeadJob::INBOX_ID = 91` (`disparo_lead_job.rb:12`; idem `followup_hsm_job.rb:9`), brokers por ID, ENV `TOZI_*`, funil por nome. Mitigação: model `BulkDispatch` de primeira classe + UI mínima.
- **Riscos pontuais (§3.4):** exceção em gating sobe pelo callback `message_created` sem rescue (#1); `BusinessHoursChecker.parse_time` sem validação (#2); `rescue StandardError` engole falhas do disparo (#3 — confirmado em `disparo_lead_job.rb:90-91`); template de 1 var pode dar `#132000` (#4 — parcialmente mitigado: comentário em `disparo_lead_job.rb:153` diz que `format` ignora chaves não-usadas no content, mas `processed_params` ainda manda sempre `{'1','2'}` no caminho de 2 vars, `:159`); humanizer `sleep` até 7s/chunk prende worker Sidekiq (#5/§4.2); chave LLM **global** compartilhada entre contas (#6); `store_accessor :behavior` dead code (#8); `MediaPipelineService` órfão (#9); handoff de cota em EN hardcoded (#10); `campaign_stats` com N+1 e full-scan sem cache (§4.1); `FunnelAutomationListener` roda pra TODA conta no dispatcher global (§4.3).
- **Multi-tenancy (§5):** "MVP de produto operando como serviço gerenciado para 1 cliente" — caminho do 2º cliente = de-hardcode (§5.1), self-service (§5.2), confiabilidade (§5.3), onboarding (§5.4), billing (§5.5).

### 🟡 P2/P3 — Pendências operacionais menores
- **Follow-up 2ª leva inquilinos:** pool restante pós-09/06 ≈ Venda 2.206 + Inquilinos 1.015 (follow-up) e Inquilinos 2.470 (disparo novo); o de locação (670) já saiu em 09/06. Disparo com template de imagem **travado** pela imagem 404 + `FollowupHsmJob` só suporta texto hoje (`followup_hsm_job.rb:23-33` — sem branch de header). Paulo mandou "segurar". Alternativa zero-deploy: texto `tozi_followup_lanc` (STATE 06-08).
- **A/B qualificado sem medição:** taxa de resposta QUALIFICADA (cliques "Quero saber" + interesse real) dos templates `tozi_venda_oportunidade` vs `tozi_venda_lembrei` nunca foi cruzada — "esse é o payoff do teste" (STATE 06-04; `docs/clientes/tozi/RELATORIO-DISPAROS-TOZI-2026-06-08.md` §A/B: "Não medida aqui — pendente cruzar os cliques de botão").
- **Conflito de templates v1 (rake) vs v2 (WABA):** `rake spx:tozi:create_templates` ainda tem conteúdo v1 rejeitado; se alguém rodar, cria 2 nomes novos + 2 colidindo (`docs/clientes/tozi/HANDOFF-2026-05-29.md` §5.1). A rake foi feita idempotente (list-then-skip) com nomes v2 em 29/05 (STATE), mas o STATE de 29/05 ainda lista "reconciliar corpos exatos dos templates v2 com o WABA" como pendente.
- **`tozi_followup_horario_combinado` reclassificado UTILITY→MARKETING** pela Meta — decisão de produto pendente (HANDOFF §5.2).
- **Deploy PAULAO (dev):** git sem credencial no user `chatwoot` + precompile manual não-automatizado (HANDOFF §5.3).
- **Limpeza PAULAO:** apagar 1 Playbook duplicado + doc FAQ na UI (STATE 06-01 Knowledge).
- **Gotchas Meta permanentes** (STATE 06-01): token da WABA Tozi **cria HSM mas não deleta** (`#100 Need permission`; deletar = WhatsApp Manager pelo Paulo); nome+idioma de template deletado **trava ~4 semanas** (`2388023`); corpo **não pode começar/terminar com variável** (`2388299`); template novo exige `sync_templates` + **restart do worker** (cache de templates) antes de enviar.
- **Backlog técnico longo-prazo** (STATE §Backlog; ONBOARDING.md §Backlog): UI `RouterConfig.vue` editar `only_contact_phones`/`skip_groups`; UI `captain_auto_resolve_mode`; divergência chave OpenAI (Account.hooks vs InstallationConfig); `feature_ai_assistant_v2` bigint overflow (bit 2^250); reativar auto-resolve com mensagem PT.

---

## 2. Histórico dos disparos — números pra dimensionar a orquestração

**Fonte primária:** `docs/clientes/tozi/RELATORIO-DISPAROS-TOZI-2026-06-08.md` (extraído da base de prod em 08/06, por mensagem HSM). Período: **02–08/jun/2026**, inbox 91.

| Métrica | Valor |
|---|---|
| HSM disparadas | **7.249** |
| Alcançadas (delivered+read) | 6.119 — **84,4%** |
| Lidas | 4.409 — 60,8% |
| Falhas | 982 — **13,5%** |
| Contatos únicos atingidos | 6.200 |
| **Contatos que responderam** | **1.501 — 24,2%** (teto; pós-consolidação pode incluir histórico antigo) |
| Custo estimado | ~US$ 382 ≈ R$ 1.950 (US$ 0,0625/entregue; base autoritativa: 2.162 entregues = US$ 135,12 via `pricing_analytics`) |

**Por segmento:** Lançamento/Locação (camp. 1) 1.612 · Venda (camp. 2) 3.426 · Inquilinos (header imagem) 1.178 (17% falha — lista com nº morto) · Follow-up (re-bate) 1.027 (**3,3% falha — a menor, porque mandou na conversa que já existia**) · Lead orgânico/cadência 6.

**23 templates, todos APPROVED/MARKETING/pt_BR** (inventário completo com IDs, corpos e botões em `docs/clientes/tozi/TEMPLATES-DISPARO-TOZI.md`): 6 lançamento/locação, 9 venda, 3 inquilinos (2 com header IMAGE em `https://tozi.chatspx.app/inq-mapa.jpeg` — **hoje 404**), 2 follow-up, 3 lead/cadência (`tozi_lead_abertura/followup/reativacao`).

**Aprendizados operacionais documentados:**
- **Falhas dominantes:** `131026` (sem WhatsApp) e `130472`/`131049` (pacing Meta em número degradado). Venda concentrou 57% das falhas (base mais fria) (RELATORIO §Análise de falhas).
- **Saúde do número:** degradou pra YELLOW no auge do disparo frio e **recuperou GREEN** após pausa + engajamento — "template curto que gera resposta protege a reputação; pitch longo em base fria derruba" (RELATORIO §Notas; STATE 06-04 "SAÚDE recuperou").
- **A/B (leitura, não resposta):** oportunidade 51% lidas vs lembrei 61%; métrica-alvo (resposta qualificada) pendente.
- **Pacing padrão:** 5s entre envios, round-robin de corretores (Kettlen #126, Lucas #127, Marcus #128, Bruno #131; variando por lote), decorrelação template×corretor (`template = j % TEMPLATES.size`). Regra do Paulo: **contínuo sem cap, ele manda parar** (memória `feedback-disparo-continuo-sem-cap`; STATE 06-03), com exceções explícitas de cap (1.200 e 1.000 em 04/06).
- **Disparo de 09/06 (pós-relatório, STATE 06-08):** +670 follow-ups locação, 4 corretores, `tozi_followup_lanc`; ~40% falhas iniciais = número morto (esperado em não-respondentes), "envio saudável".
- **Disparo 1 (02/06, campaign_stats #1):** total 1.529, alcançados 1.337, lidas 824, falhas 178, **respostas 180**; respostas classificadas: 63 positivas / 21 negativas / 5 neutras de 89 (STATE 06-02).
- **Consolidação 08/06:** 275 contatos com duplicata (203 com 2 fichas + 72 com 2 convs na mesma ficha), 810 msgs movidas, 298 convs + 203 fichas apagadas; corretor passou a ver o histórico inteiro (STATE 06-08).

---

## 3. Decisões já tomadas que CONSTRANGEM o design da IA orquestradora

1. **Conversa ÚNICA por contato** — "o SPX da Tozi exige 1 conversa por contato (`lock_to_single`)"; decisão explícita de **consolidar duplicatas em vez de remendar roteamento** (STATE 06-08 §Decisão). Materializada em `DisparoLeadJob#find_or_create_conversation` (`disparo_lead_job.rb:119-143`: reusa/reabre, cria só se nunca existiu) e na inbox 91 (`lock_to_single_conversation=true`, STATE 06-01). A IA orquestradora **não pode** criar conversa paralela por assunto/campanha — todo o histórico vive num fio só.
2. **Identidade de contato = variantes 12d/13d reconciliadas** — todo outbound deve resolver o source_id via `Whatsapp::PhoneNumberNormalizationService` antes de criar ficha (`disparo_lead_job.rb:109-116`); o backlog defensivo do 9º dígito (`docs/backlog/reconciliador-incoming-9-digito.md`) define a regra "ficha da conversa mais recente" se 2+ casarem.
3. **Blaster nativo de campanha DESATIVADO** — `Campaign#execute_campaign` só loga; botão "Nova campanha WhatsApp" removido; a Campaign nativa é **âncora de stats** (`campaign_id` FK + `campaigns_controller#stats`), nunca dispara (STATE 06-02; commit `c7405f010` na rollout). Orquestração de outbound = motor próprio (`DisparoLeadJob`/`FollowupHsmJob`/`ScheduledMessages`), não o nativo.
4. **Corretor não vê conversa de outro** — custom role "Corretor" (`conversation_participating_manage`) via `Enterprise::Conversations::PermissionFilterService` (participating → `assigned_to(user)`; admin bypassa). Verificado ao vivo: corretor vê 0 fora do seu; Guilherme (admin) vê tudo (STATE 06-01 Fase B). A orquestradora precisa garantir que atribuição implique visibilidade — o "reply órfão" nasceu exatamente de conversa atribuída que a secretária não via.
5. **AutomationRule #53 'iniciar zerado' NÃO desativar** — zera assignee+team em `conversation_opened` (inboxes 61/62/91); diagnóstico cravou que é "consequência, não causa" (STATE 06-08). Qualquer reabertura orquestrada pela IA vai colidir com essa rule — o disparo contorna reatribuindo após `open!`.
6. **Auto-resolve do Captain DISABLED com trava dupla** — `captain_auto_resolve_mode='disabled'` na Account 6 + guard no scheduler e no job (STATE 06-02 incidente). Religar exige mensagem PT, gating e ausência de loop pending→resolve (pré-req 3 do go-live).
7. **Clara desconectada até cumprir pré-reqs 1-4** — o interruptor de ativação é `CaptainInbox(91,7)`; religar sem resolver o pending-limbo reabre o incidente (STATE 06-02).
8. **Code-first** — Claude Code configura agentes via API; o frontend é viewer (AGENTS.md §Filosofia Code-First). A orquestradora deve ser configurável por API/JSONB (`behavior`), não por formulário.
9. **Janela de 24h arbitra o canal do follow-up** — dentro da janela = follow-up do agente (tool `programar_followup`); fora = HSM determinístico via `ScheduledMessages.template_params`; **o estágio do funil arbitra** (STATE 29/05 Bloco 4).
10. **Regras Meta imutáveis no curto prazo:** só HSM aprovado fora da janela; corpo não começa/termina com variável; nome de template deletado trava 4 semanas; token cria mas não deleta template; template novo exige sync + restart de worker; reputação do número (GREEN/YELLOW) limita o throughput de MARKETING (STATE 06-01/06-02/06-03).
11. **Disparo contínuo sem cap por default** — pacing 5s, fila completa, Paulo decide parar (memória `feedback-disparo-continuo-sem-cap`); pausar = deletar jobs do `Sidekiq::ScheduledSet`.
12. **1ª mensagem a lead Meta deve virar HSM** quando inbox Cloud API (gap aberto, decisão já cravada como "construir" — STATE 29/05 §Falta).
13. **Atribuição no momento do disparo, preservada na consolidação** — a conversa fundida ficou com o **corretor do disparo** e aberta (STATE 06-08 Frente 2); o follow-up mantém o assignee (`followup_hsm_job.rb` header: "mantendo o corretor ja atribuido").

---

## 4. Pontos de plugagem para a IA orquestradora (mapeados pelos docs + código verificado)

- **Eventos Wisper via dispatcher:** `message_created`, `conversation_opened`, `assignee_changed` — onde `Spx::Tozi::FunnelAutomationListener` (`app/listeners/spx/tozi/funnel_automation_listener.rb`) já pluga hoje no `AsyncDispatcher`. Caveat da auditoria (§4.3): roda pra toda conta — gate por account/feature-flag antes de escalar.
- **Pipeline de resposta do Captain:** `Enterprise::MessageTemplates::HookExecutionService` (`enterprise/app/services/enterprise/message_templates/hook_execution_service.rb`) → behavior services (router/debounce/business_hours/copilot_trigger) → `ResponseBuilderJob` → `AgentRunnerService` (`enterprise/app/services/captain/assistant/agent_runner_service.rb`) → dedup/humanizer (Auditoria §1.3).
- **Config da orquestração:** JSONB `behavior` do `Captain::Assistant` (router/debounce/humanizer/dedup/business_hours/copilot_trigger/media_pipeline) — extensível sem migration (AGENTS.md §Behavior JSONB).
- **Tools com efeito colateral no funil:** `enterprise/lib/captain/tools/programar_followup_tool.rb` e `salvar_info_lead_tool.rb` (hooks pro funil), `handoff_tool.rb`, `buscar_imovel_tool.rb`, `resolve_conversation_tool.rb`, `add_label_to_conversation_tool.rb` etc. (verificado o diretório).
- **Primitivas de outbound:** `Spx::Tozi::DisparoLeadJob` (HSM novo lead, com imagem), `Spx::Tozi::FollowupHsmJob` (HSM no fio existente — capacidade nova de 05/06), `ScheduledMessages` + `template_params`, `Spx::Tozi::ReactivationCadenceService` (1d/3d/7d, cancel-on-reply).
- **Estado do lead:** `Funnel` id=41 "Pré-Venda Tozi" (7 stages, automation_type `novo_lead`→`qualificado`/`frio`) + `Spx::Tozi::FunnelPlacementService` (`app/services/spx/tozi/funnel_placement_service.rb`).
- **Aquisição:** webhook `app/controllers/webhooks/meta_lead_ads_controller.rb` + `app/services/meta/lead_ads/*` (genérico por page_id, multi-conta — HANDOFF §7).
- **Telemetria:** `campaign_stats` (`campaigns_controller#stats`, agrega por `campaign_id`) — hoje sem cache (Auditoria §4.1); `Channel::Whatsapp#sync_templates` pro status de aprovação.
- **Interruptores:** `CaptainInbox` (liga/desliga IA por inbox), `behavior.router.only_contact_phones` (whitelist), `captain_auto_resolve_mode` (kill-switch).

---

## 5. Questões em aberto (citadas nos docs, sem resposta registrada)

1. Reconciliação: rollout vira canônica ou tudo migra pra `producao`? Processo oficial de deploy? (RECONCILIACAO §Decisões abertas — 4 checkboxes não marcados.)
2. A landmine foi de fato aplicada em prod (versão SAFE)? O `migrate:status` 0 down de 08/06 contradiz o registro anterior — "investigar" (STATE 06-08 Frente 1).
3. O `mapa-localizacao.jpeg` da resposta rápida `/interesse` (att 411283) é a mesma imagem do `inq-mapa.jpeg` perdido? (STATE 06-08.)
4. Qual a taxa de resposta QUALIFICADA do A/B oportunidade×lembrei? (RELATORIO §A/B — pendente cruzar cliques.)
5. Go-live da Clara: caminho (a) atender de verdade vs (b) corrigir o stub do `mark_pending_conversation_as_open_for_human_response` — não decidido (STATE 06-02 plano item 1).
6. `tozi_followup_horario_combinado`: reescrever pra voltar a UTILITY? (HANDOFF §5.2.)
7. Quando retomar o follow-up de inquilinos (Paulo: "segura") e com qual template (imagem exige recuperar asset + estender `FollowupHsmJob`)? (STATE 06-08.)
8. Generalização multi-cliente: separar mecanismo (SPX) de dados (Tozi) — roteiro existe (HANDOFF §7; Auditoria §5), execução não começou.

---

*Relatório de mapeamento documental. Nenhum arquivo de código foi modificado. Referências de código verificadas localmente na branch `paulao` em 2026-06-10.*
