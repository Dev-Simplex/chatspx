# Estado ChatSPX — atualizado 2026-06-11 (reconciliação de branches EXECUTADA + Bloco 1+2 do go-live em prod)

> Single source of truth do que está **in-flight** no projeto.
> Coisas estáveis vão pro [`MEMORY.md`](../../../.claude/projects/C--Users-paulo-Workspaces-chatspx/memory/MEMORY.md) (per-projeto) ou pro vault Obsidian.
> Decisões com mais de 30 dias devem ser movidas pra `clientes/tozi-conversation-log.md` no vault.

> ✅ O handoff de 29/05 foi SUPERADO em 11/06: reconciliação executada, deploy AWS virou git, código paulao→prod Tozi completo. Sessão de decisões pendente: **[`docs/DECISOES-CLARA.md`](../docs/DECISOES-CLARA.md)**.

---

## 🚧 Em andamento

### [2026-07-14] 🟢 META LEADS (Caminho B, formulário) — GO-LIVE EXECUTADO na prod Tozi (Sofia pré-qualifica); validando com lead de teste

> **Contexto:** campanha Meta `120243133255210544` (forms Pacaembu/Tívoli MCMV). Estado ao vivo verificado read-only na prod Tozi (conta 6): **0 hooks meta_lead_ads, 0 conversas `source=meta_lead_ads`, 0 CTWA em 180d** — nenhum lead de anúncio chega ao SPX hoje. Decisão do Paulo: fazer funcionar por **formulário com webhook** (não CTWA). Modelo de IA vigente = "IA como agente atribuível" (7 agentes: Clara #7 triagem, Júlia #13, Bruna #14, Letícia #15, Marina #16, Rafa #17, Helena #18 RH).

- **✅ Gap do webhook corrigido** (`app/services/meta/lead_ads/create_conversation_service.rb`, commit `0e6f37820` em **homologacao**): (1) `source_id` em Cloud API via `PhoneNumberNormalizationService` (fim do reply órfão/duplicata); (2) `find_or_create_conversation` honra `lock_to_single` + idempotência contra redelivery/retry; (3) guard anti-1ª-msg-duplicada. Espelha o `DisparoLeadJob`. Syntax OK. **Falta chegar na `producao`** (governado) antes de ligar o webhook.
- **✅ IA Sofia #19 criada** na prod conta 6 (runner clonando comportamento da Júlia + prompt novo script-free, 9461 ch): pré-qualificação de leads Meta com **gates sensíveis** (trava não é parede — nome sujo → previsão de quitação/Tuiuiú; sem holerite → renda alternativa/terreno; sempre busca caminho e passa pro corretor), herda o *feeling* de venda da Júlia (encantar sem "namorar"). Mirror AgentBot #23. **DESCONECTADA** (0 CaptainInbox = não responde nada). `image_description` ON (foto do holerite → sinaliza, não reprova). Tools: salvar_info_lead, programar_followup, transferir_para_agente, atualizar_resumo, registrar_observacao, registrar_assunto.
- **✅ Time "Leads Meta" #67** criado (conta 6), único membro **Cibely (user #67)** — ela distribui manual entre corretores. `Sofia.config.team_id=67`.
- **Credenciais do webhook** (vault `credenciais/tozi.md`): app `1658426868710322`, page `539594042748152`, verify/secret/system-user-token OK. **Callback ainda em PAULAO** (`paulo.chatspx.app`) — migrar pra `tozi.chatspx.app/webhooks/meta_lead_ads`.
- **🟢 GO-LIVE EXECUTADO (14/07):** fluxo Meta Leads → Sofia LIVE na prod Tozi. (a) template `tozi_lead_pacaembu_abertura` (id 4534320560147675) APPROVED + sincronizado na inbox 91; (b) 3 commits meta na `producao` (`603ba9bbb`) — **deploy governado via Almirante travou** (mirror git dele defasado + VM Tozi sem credencial git), feito **hotfix cirúrgico** no box (só o `create_conversation_service.rb`, sem migration, migrate:status limpo, restart web+worker, HTTP 200); (c) **Hook #8** criado na conta 6 (page 539594042748152, inbox 91, template, `assign_agent_bot_id=23`=Sofia); (d) **callback do app Meta migrado** de PAULAO → `tozi.chatspx.app/webhooks/meta_lead_ads` (subscription active, leadgen; page confirmada subscrita ao app); (e) roteamento por hook (não por automação) — cada campanha/hook → seu agente; (f) Sofia elegível na inbox 91 (CaptainInbox), **piloto = acompanhar os 1os leads + kill-switch** (desabilitar Hook #8 ou desplugar Sofia). Futuras campanhas: novo hook por `form_id`/campanha → agente/knowledge próprio.
- **⚠️ Dívidas de infra descobertas (não bloqueiam o go-live, mas organizar):** (1) mirror git do Almirante desatualiza — não fez fetch de `0d9d08238`/`603ba9bbb`; (2) VM Tozi **sem credencial git** (`could not read Username for github.com`) → deploy governado não consegue `pull`; (3) commit `0d9d08238` (fix captain track_imoveis de outro dev) está na `producao` mas **não deployado** na frota (que roda `c97ce3b8e`). O hotfix da Tozi levou só o arquivo meta, não o `0d9d08238`.
- **PENDENTE (validação):** lead de teste (Paulo dispara pela Meta Lead Ads Testing Tool com telefone real → cadeia completa: conversa + HSM + Sofia atribuída + resposta). Watcher rodando no box.

### [2026-06-11] ✅ DECISÃO 2.7 EXECUTADA em prod Tozi — higiene das abertas só-HSM (4.013 resolvidas, 0 falhas)

- **Critério estrito do Paulo:** conversa com APENAS template(s) outgoing, zero resposta do lead, zero texto humano, atribuída. Universo: 4.606 (nenhum corretor tinha escrito nada). Resolvidas as paradas 3d+: **4.013 em 369s, 0 falhas** (lotes de 50 + pacing; teams setados nas sem-team via MAP corretor→time de disparo; Gelson/Adrian via skip flag). Dry-run prévio: CSAT/NPS OFF (zero pesquisa pro lead), 0 webhooks de conta, resolve+rollback de teste OK.
- **Resultado: inbox 91 caiu de 6.508 → 2.487 abertas** (resolved 11.077). Residual: 593 (<3 dias — ficam com os corretores). Cards dos funis moveram pra "Resolvidos" via callback. Reply futuro reabre zerada (#53) → triagem por intenção (decisão 3.5, batida hoje: labels `intencao:*` + automation `assign_team`). Detalhes: `docs/DECISOES-CLARA.md` §2.7 e §3.5 · script `Temp/executa_27.rb` · log `/tmp/resolve27.log` na AWS.

### [2026-06-11] 🚨 DESCOBERTA DE INFRA: 192.168.8.232 = chatspx.app (SaaS COM CLIENTES), não só "hmlchat"

- `FRONTEND_URL` da VM 232 é `https://chatspx.app`; contas: 1 SimplexIA · 3 Simplex Tecnologia · 4 Colégio Alternativo · 5 Realizare Imobiliária. **Tratar como produção** (o restart/migrations de hoje passaram sem incidente, mas o risco era maior que o assumido). Auto-pull da homologacao SEM migrate vira risco crítico — corrigir urgente. Vault atualizado (`credenciais/infraestrutura.md`).

### [2026-06-11] 🟢 CLARA LIVE NO NÚMERO SIMPLEXIA OFICIAL (chatspx.app, conta 3, inbox 44)

- **Número Cloud API oficial funcionando: +55 66 2018-0686** (inbox 44 "SimplexIA", conta 3 Simplex Tecnologia). Equipe clonada da conta 1 → conta 3: **Clara #3 (CONECTADA à inbox 44)** · Júlia #10 · Bruna #11 · Letícia #12 · Marina #13 · Rafa #14. Modelo da conta 3: `claude-sonnet-4.5` (era gpt-4.1, sem uso). Custom tools clonadas (geocoding ON). Cota 99.965/100k. `audio_transcriptions=true` na conta 3. `pending_status_enabled=false` na inbox 44 (sem limbo). Sem whitelist — a Clara responde QUALQUER mensagem no número (é o teste).
- **Para testar:** mandar WhatsApp pro +55 66 2018-0686 (texto/áudio). Trocar o agente conectado = `CaptainInbox.find_by(inbox_id: 44).destroy` + `create!(inbox_id: 44, captain_assistant_id: <id>)`.
- Limitações conhecidas do teste: transferência IA→IA = handoff com destino no motivo (tool real = Fase C6) · busca de imóvel usa o Vista da TOZI (chave no .env — ok pra teste).
- **Knowledge da AWS importada (11/06):** Playbook de Vendas (doc, 19 chunks com embedding, available) → Júlia #10 · 40 Q&A divididas conforme a spec: 4 institucionais → Clara #3, 36 vendas/objeções → Júlia #10, todas com embedding. Bruna/Letícia/Marina/Rafa seguem sem knowledge (curadoria §12 do EQUIPE doc — a base de prod não tem conteúdo de locação/suporte/captação/prestadores). `knowledge_mode=hybrid` (retrieval ON; `feature_faq=false` só desliga a GERAÇÃO automática de FAQ no resolve, não a consulta).
- **🔄 AJUSTE pós-teste do Paulo (11/06 tarde): Clara #3 virou ORQUESTRADORA** (padrão validado da Tozi prod, já que o runtime atual só permite 1 assistant por inbox). Os 5 especialistas viraram CENÁRIOS dela (Vendas #13 c/ buscar_imovel+geocoding+fotos · Locação #14 idem · Suporte #15 · Captação #16 · Prestadores #17), com frases de transferência ajustadas pro mecanismo de cenários (devolver à assistente principal). Cenário recepcionista standalone desabilitado (volta no modelo IA-como-agente). Knowledge CONSOLIDADA na #3: 40/40 Q&A + Playbook (19/19 chunks) com embeddings. Motivo do teste falho: a Clara recepcionista não tinha buscar_imovel por design e não tinha pra quem transferir. Os assistants #10–14 ficam como fonte pro modelo novo (não conectados).

### [2026-06-11] 🟢 EQUIPE DE AGENTES CRIADA NA SANDBOX (chatspx.app, conta 1 SimplexIA)

> Spec completa: [`docs/EQUIPE-AGENTES-IA.md`](../docs/EQUIPE-AGENTES-IA.md). Setup idempotente: `Temp/hml_setup_sandbox.rb` (local, não versionado).

- **6 agentes criados** (assistant ids 4–9): Clara (recepção/triagem por intenção) · Júlia (vendas, prompt = prod) · Bruna (locação, = prod) · Letícia (suporte, = prod) · Marina (captação, NOVO) · Rafa (prestadores de serviço, NOVO). Cada um: 1 cenário "Comportamento" com o prompt, config baseline (guardrails+guidelines da Clara prod + anti-senha; memory/faq OFF), behavior baseline (debounce 15s, humanizer 280, business_hours Sinop, sem whitelist), modelo `claude-sonnet-4.5`.
- **Infra da sandbox**: chaves LLM (InstallationConfig) copiadas da AWS · custom tools geocoding (enabled) + vista (disabled, como prod) na conta 1 · `TOZI_VISTA_API_KEY` no .env · web+worker reiniciados (migrate 0 down) · HTTP 200. **Nenhum agente conectado a inbox** — não respondem nada até plugar (seguro).
- **Critério de agente por setor** (DECISÕES §13 do EQUIPE doc): jurídico SEM agente (handoff humano); prestação de contas do proprietário → Letícia até Onda 5. Transferência IA→IA por enquanto = handoff com destino no motivo (tool real é Fase C6 da arquitetura).
- **Próximo:** Paulo valida os agentes na UI (hmlchat → conta SimplexIA → Agentes IA) · plugar inbox de teste OU aguardar número SimplexIA Cloud API pro teste E2E · curadoria de knowledge (institucional/locação/suporte/captação/prestadores).

### [2026-06-11 noite] 🟢 ORQUESTRAÇÃO IA FUNCIONANDO E2E no chatspx.app (conta 3, inbox 44)

> **Fluxo provado em teste sintético:** conversa órfã → triagem automática atribui Clara (automation `assign_ai_agent`, rule #31) → Clara identifica intenção e **transfere via tool `transferir_para_agente`** → Bruna assume com contexto e atende. Transferência invisível, sem eco.

- **Implementado por mim (commits na homologacao até `5fb885a2e`):** tool `transferir_para_agente` (C6, lookup direto do espelho) · action `assign_ai_agent` (C4) · entry tools.yml · B3 `configured_agent_tools` · B1 instructions no v2 · fix image-blocks no histórico (foto da IA quebrava turnos seguintes) · fixes de fotos (transação/reenvio/sem oferta) · gates aceitam `captain_integration_v2` (gotcha "não habilitado" morto na raiz, useCaptain+CSAT+áudio).
- **Equipe conta 3:** Clara #3 recepcionista (transfere) · Júlia #10 · Bruna #11 · Letícia #12 · Marina #13 · Rafa #14 — agentes únicos standalone (cenários OFF, B1+B3), todos ELEGÍVEIS na inbox 44 (CaptainInbox; a Fase C endureceu: espelho não-elegível é recusado).
- **Frente paralela (.41):** 2 sessões Claude Code NO SERVIDOR (loop autônomo `plano/ia-consolidado.md`; F0+A aceitas — commitei tudo em `2bee0f724`; Fase C/UI em andamento). ⚠️ Precompile SEGURADO até a Fase C fechar (SCSS em progresso quebra build + não servir UI parcial pros clientes do SaaS). Bugs da noite (todos mortos): multi-agente da gem (eco), worker dessincronizado, image-blocks, elegibilidade sem dados.
- **Próximo:** teste do Paulo via WhatsApp (conversa 515 com a Clara) · Fase C fechar → precompile (UI de agentes + fix da tela) · curadoria de knowledge dos especialistas · espelhar a receita pro go-live Tozi.

### [2026-06-11] 📐 ARQUITETURA "IA COMO AGENTE ATRIBUÍVEL" — planejada de manhã; Fases A (loop .41) + B1/B3/C4/C6 (eu) JÁ IMPLEMENTADAS — ver entrada acima

> **Plano completo: [`docs/ARQUITETURA-IA-COMO-AGENTE.md`](../docs/ARQUITETURA-IA-COMO-AGENTE.md)** (fases A–D, ~2 semanas, aceites e roteiro E2E novo de 14 testes).

- **Decisão do Paulo:** fim da "Clara com cenários". Cada IA = um agente independente, atribuível como atendente; **a IA só responde conversa atribuída a ela** (sem router/whitelist/labels). Cenário sobrevive só como SUBPROMPT de comportamento. Conversa da IA fica com composer BLOQUEADO pro humano — botão "Assumir conversa" rouba a atribuição explicitamente.
- **Viabilidade verificada no código (6 agentes, 11/06): ~70% do trilho já existe** — `conversations.assignee_agent_bot_id` + AssignmentService com assignee_type + endpoint + callback `reset_agent_bot_when_assignee_present` (atribuir humano limpa o bot = "transferiu → cala" de graça). Trilho escolhido: **AgentBot-espelho por Captain::Assistant** (`bot_type :captain`). O gate atual é 100% por inbox (`inbox.captain_assistant`) — vira por conversa.
- **Implicações:** whitelist/label atendimento/skip-pós-humano/pending-limbo MORREM; regra #53 TEM que morrer na virada; go-live da Clara deve acontecer JÁ neste modelo (não religar no modelo velho); substitui parte da Onda 2 do roadmap.

### [2026-06-11] ✅ RECONCILIAÇÃO DE BRANCHES EXECUTADA — `producao` é a canônica única

> **O problema "cada redeploy re-dropa patches off-git" está MORTO.** Estado final dos ambientes:

- **`producao` (29a32046f)** = canônica, superset de TODAS as linhas: paulao (22 commits, PR #21) + producao consolidada de 08/06 + único commit exclusivo da rollout (FK cascade, PR #22). Merge teve 1 conflito (disparo_lead_job add/add → versão paulao) + 18 .rb validados com ruby -c. Migration landmine agora é a versão SAFE em todas as branches.
- **`paulao`** = sincronizada com producao. **`homologacao`** = producao + 10 PRs do redesign workspace-v2 (merge sem conflito) — **branch de trabalho do Paulo daqui pra frente**.
- **AWS Tozi** = checkout LIMPO da `producao` (era rollout/release-20260605 + sujeira off-git). Bundle incremental via scp (VM sem credencial git), backup da sujeira em branch local `backup/pre-switch-20260611`, migration 20260609120000 aplicada via `db:migrate:up` específico, 0 down, precompile + restart → HTTP 200, tráfego real ok.
- **hmlchat (192.168.8.232)** = homologacao completa: 6 migrations aplicadas, zeitwerk OK, HTTP 200. Credencial descoberta e salva no vault (`credenciais/infraestrutura.md` § HMLCHAT). ⚠️ Tem **auto-pull da homologacao que NÃO migra/precompila/restarta** — bomba-latente a cada push; corrigir o mecanismo.
- **TODOs operacionais:** deploy key git na AWS (fetch falha; bundle foi o workaround) · git ident do user chatwoot na AWS · runbook oficial de deploy (decisão 1.3) · consertar auto-pull da hmlchat.

### [2026-06-11] 🟡 GO-LIVE REORGANIZADO — Bloco 1+2 executados em prod; switch da Clara aguarda sandbox + decisões

- **Executado em prod Tozi (11/06):** T1 áudio (gate código + `audio_transcriptions=true`) · T2 fix 403 (+ commit `e74b935b1`) · T3 anti-duplicata do disparo · T4 restart validado · T5 notificações dos 4 corretores (3 flags push + 3 email; falta cada corretor ACEITAR a permissão no navegador — Ederson) · T6 memberships Marcus/Bruno + 442 conversas re-sincronizadas (0 dessincronizadas no final) · T8 lista do mutirão (408 conversas em `Downloads/mutirao-tozi-12h.csv`; inclui Paloma 11, Gelson 4, Ivanete 1 além dos 4 corretores).
- **Decisões batidas (11/06):** D1 SIM com sub-definições (ver doc) · D2 24/7 · D3 desligar memory/faq · homologacao = branch de trabalho · sandbox = número SimplexIA na Cloud API oficial.
- **PENDENTE:** T7 (config Clara) · T9 (switch CaptainInbox) · T10 (roteiro 13 testes) · T12 (piloto leads reais) — aguardam Etapa 2 (sandbox SimplexIA) + sessão de decisões dos Grupos 2–8 de **[`docs/DECISOES-CLARA.md`](../docs/DECISOES-CLARA.md)** (~35 decisões consolidadas com recomendação cada).
- **Ordem macro decidida:** Etapa 1 reconciliação ✅ → Etapa 2 sandbox SimplexIA Cloud API + quick wins (Langfuse/playground/golden set) → Etapa 3 go-live Clara organizado → Etapa 4 Ondas 1+2+4.1 em paralelo → Etapa 5 Onda 5 antecipada (Vista fundo; MA Financeiro 🔴 ~1 mês de atraso contratual).

### [2026-06-10] 🚀 PLANO DE GO-LIVE DA IA — 11/06 (Paulo + dev sênior + Ederson), abertura 12/06

> **Plano executável: [`docs/PLANO-GOLIVE-IA-2026-06-11.md`](../docs/PLANO-GOLIVE-IA-2026-06-11.md)** — tarefas T1–T12 com comandos prontos, papéis, roteiro E2E de 13 testes, critérios go/no-go e rollback.

- **Verificação final de prod (10/06):** kit Clara quase completo — 13 tools ✅, fallback handoff (02bcbac0f) ✅, typing ✅, followup_job ✅. **Pending limbo NÃO recorre em prod**: a rollout tem guarda dupla no `reopen_resolved_conversation` (`active_bot? && pending_status_enabled?`) + `pending_status_enabled=false` na inbox 91 → conversa resolvida reabre OPEN. ⚠️ A `paulao` local NÃO tem essa guarda (tem o f96ae7740 no lugar) — na reconciliação levar AMBOS (complementares). ⚠️ NUNCA ligar "status pendente" da inbox 91.
- **Gaps reais achados (entram no plano de amanhã):** (T1) transcrição de áudio MORTA em prod — commit `1671b9017` ausente + `account.audio_transcriptions=false` (2 gates); (T2) fix 403 = 1 linha no `authorize_team_access` (assignee sempre abre a própria conversa); (T3) patch cirúrgico do `11b913531`; (T5) notificações dos corretores OFF de fábrica; (T7) `feature_memory=true` e `feature_faq=true` na Clara — religar dispara LLM por resolve (recomendado desligar no go-live); (T6) Marcus/Bruno sem membership de time + re-sync team das conversas de disparo.
- **Decisões D1–D3 pro Paulo bater amanhã cedo:** Clara atende replies de disparo ao abrir geral? (recomendo sim; script de label bulk pronto como alternativa) · responder fora do horário? (recomendo manter) · desligar memory/faq? (recomendo sim).

### [2026-06-10] 🔴 BUG ATIVO: corretor vê conversa atribuída a ele mas recebe 403 ao abrir ("Você não tem permissão")

> Reportado pelo Paulo com prints (lista do Lucas + modal de permissão). **Diagnóstico cravado com dados de prod (read-only).**

- **Causa:** gate de time do fork — `authorize_team_access` (`app/controllers/api/v1/accounts/conversations_controller.rb:231-243`): não-admin recebe 403 ao abrir conversa cujo `team_id` é de um time do qual ele NÃO é membro. As conversas problemáticas estão **atribuídas ao corretor X mas com team do corretor Y** — dessincronização causada pelas **reatribuições em massa via `update_columns`** (04/06 jobs→Kettlen; 09/06 Kettlen→4 corretores) que não rodam o `sync_team_from_assignee`. Confirmado nos contatos dos prints: "Harla Proprietaria" (conv 11986) e "Lourival spadacio" (conv 12324) = assignee Lucas + team 62 "kettlen - disparo" → 403.
- **Números (prod 10/06):** ~700 conversas abertas com assignee ∉ team — Lucas 114 + Bruno 113 + Marcus 113 no team da Kettlen; Bruno 49/Marcus 42/Kettlen 42 no team do Lucas; + dezenas em times funcionais (locação/financeiro/recepção). **Agravante:** Marcus (#128) e Bruno (#131) **não são membros de NENHUM team** (nem dos próprios "marcus/bruno - disparo", que só têm Guilherme+Maria Vitoria). O corretor VÊ a conversa na lista porque o push do ActionCable filtra client-side só por assignee (`applyRoleFilter` não checa team), mas o GET unitário toma 403.
- **Fix proposto (aguardando aval — mexe em prod):** (1) DADOS: re-sincronizar `team_id` das abertas dos 4 corretores — times de disparo (61-65) → team do próprio assignee; criar membership de Marcus→64 e Bruno→65; times funcionais decidir caso a caso (adicionar membro ou reatribuir). (2) CÓDIGO: 1 linha no `authorize_team_access` — `return if @conversation.assignee_id == Current.user.id` (assignee sempre pode abrir a própria conversa; atribuição implica acesso).

### [2026-06-10] 🗺️ MAPEAMENTO COMPLETO — IA orquestradora de conversas (doc-mestre + plano em fases)

> **Doc-mestre: [`docs/MAPEAMENTO-SPX-ORQUESTRACAO-IA-2026-06-10.md`](../docs/MAPEAMENTO-SPX-ORQUESTRACAO-IA-2026-06-10.md)** + 20 relatórios por subsistema em `docs/mapeamento-2026-06-10/` (21 agentes sobre o código + auditoria read-only de prod). Pedido do Paulo: estado atual do SPX + o que a IA pode orquestrar (triagem, atribuição, follow-up, campanhas, kanban) coexistindo com humanos.

- **Achados de prod (10/06, read-only):** inbox 91 com **6.508 open** (≈6.100 de disparo) / 7.009 resolved; **432 abertas com lead esperando resposta >12h** (Bruno 151, Kettlen 149, Marcus 61, Lucas 59); 1.618 resolved com assignee; **143 contatos ainda com >1 ficha + 115 com >1 conversa** (resíduo HISTÓRICO jan–mai, fora do escopo da consolidação dos 275; sem re-duplicação ativa). Rule #53 ativa (única); teams espelham funis; 26/30 usuários são admin (só os 4 corretores têm role restrita). Fix `11b913531` confirmado FORA de prod (diff real: prod sem fix e sem lógica inq — rollout 08/06 regrediu o job). `inq-mapa.jpeg` 404 confirmado. 0 migrations pendentes. Sidekiq sem jobs spx agendados.
- **Diagnóstico-chave do "ninguém viu":** não é permissão (secretárias são admin) — é **notificação default OFF** (`assigned_conversation_new_message` sem push/email de fábrica; só `conversation_assignment` vem ligado — `account_user.rb:46-51`) + fila "Abertas" afogada em conversas de disparo + reply em conversa open não dispara `conversation_opened` (#53 não devolve pra triagem).
- **Correções ao STATE antigo:** (1) o limbo pending está 80% resolvido NO CÓDIGO — `mark_pending_conversation_as_open_for_human_response` NÃO está mais stubbado (override `enterprise/app/models/enterprise/message.rb` ativo via prepend) + `f96ae7740` abre quando a IA assume; residual = `router_skip` (whitelist) segue pending invisível. (2) SLA Enterprise EXISTE e roda no cron (gatilho temporal nativo "lead esperando há X" com notificação) — caveats: AppliedSla terminal pós-resolve (ruim c/ conversa única; usar snooze), business hours ignorado. (3) Já existe embrião de **Evals**: copilot tool `get_conversation_analysis` espera serviço LLM-judge externo em `TOZI_EVAL_API_URL` (127.0.0.1:8910) — serviço NÃO existe ainda (porta vazia na VM). (4) Copilot do painel já tem 32 tools (assign/status/send_template/workload) — gatilho `#copilot` semifuncional (sem user → tools inativas; resposta descartada) e `send_template` com bug (template_params em additional_attributes, MessageBuilder lê top-level).
- **Decisão recomendada no doc:** orquestração DENTRO do Captain (listener `Spx::Orchestrator` + tools de atribuição com team_id + triagem por labels `nicho:*` → automation `assign_team` + SLA nrt como despertador) — NÃO via AgentBot externo. Rule #53 é substituída pela triagem orquestrada no médio prazo (são mutuamente exclusivas: ela zera QUALQUER atribuição em `conversation_opened`, inclusive auto-open da Clara). Conversa única (lock_to_single) MANTIDA — organização por funis (FunnelItem é por conversa×funil, multi-card) + labels + custom_attributes, não por múltiplas conversas.
- **Plano em fases (doc §10):** F0 higiene (reconciliar branches; patch fix disparo; **ligar notificações dos corretores — quick win nº1**; mutirão das 432; política de status p/ conversas de disparo; consolidar 143 históricas + reconciliador incoming) → F1 triagem+go-live Clara (HandoffTool c/ team_id, labels nicho, matar #53, Lead Ads HSM+source_id) → F2 cadência completa (disparo entra no funil, cancel-on-reply genérico, SLA nrt) → F3 campanhas como módulo (entidade persistida + UI + stats por template + gate de saúde) → F4 Evals (worker 8910) + Copilot consertado → F5 multi-cliente.
- **15 bugs/riscos novos catalogados** (doc §11): webhooks at-most-once (retry inerte — fix 1 linha), backfill do Kanban poluindo o funil Tozi (origem dos 868 "Novo Lead"), Kanban ignora custom role + filtro de label quebrado, Lead Ads source_id com `+` (futura fábrica de duplicatas), `skip_agent_bot` NoMethodError latente, PII integral nos traces OTel, etc.

### [2026-06-08] 🟢 CONVERSA ÚNICA POR CONTATO — duplicatas de disparo CONSOLIDADAS (reply órfão resolvido)

> **Reclamação:** leads que receberam disparo dias atrás e respondiam hoje apareciam **"Não atribuída", sem corretor e sem histórico**.

- **Causa-raiz (diagnóstico com dados):** o `DisparoLeadJob` criava ficha (`ContactInbox`) com `source_id` no NOSSO formato (`BrazilPhoneNormalizer`, +9º dígito) e conversa nova via `Conversation.create!`. Pros números antigos, o **wa_id que o Meta entrega é a outra variante** (12d sem o 9). Aí o reply caía numa **ficha/conversa diferente** da do disparo → órfão; e a `AutomationRule #53 'iniciar zerado'` (event `conversation_opened`, inboxes 61/62/91, zera assignee+team) **desatribuía ao reabrir**. O `Whatsapp::PhoneNumberNormalizationService` (variantes 12d/13d) existe e é certo — o disparo é que **não o usava**. **275 contatos** ficaram com >1 conversa (203 com 2 fichas + 72 com 2 convs na mesma ficha).
- **Decisão (com Paulo):** o SPX da Tozi exige **1 conversa por contato** (`lock_to_single`). Logo, **não** remendar roteamento (deixaria 2 convs) — **consolidar** (eliminar a duplicata) + **consertar a origem**. NÃO desativar a #53 (é consequência, não causa).
- **🟢 FRENTE 2 — consolidação APLICADA + verificada (prod):** script `scripts/spx/tozi/consolida_conversas_duplicadas.rb`. Por contato: funde tudo na conversa com mais incoming (empate→mais recente), move msgs (`update_all`), atribui ao **corretor do disparo**, deixa **aberta**, migra `campaign_id`/`source`/`template`, apaga convs vazias + fichas duplicadas (`delete`/`update_columns`, sem callbacks/async, transação por contato). Validado com rollback em 1, depois rodado: **275 ok, 0 falhas, 810 msgs movidas, 298 convs + 203 fichas apagadas.** Pós-verificação: **0 contatos com >1 conversa/ficha**. SILMAR (exemplo): 1 ficha (`556699776106`) + 1 conversa aberta atribuída ao Bruno, 22 msgs (atendimento+HSM+follow-up+reply juntos). **Bônus:** o corretor agora **vê o histórico inteiro** (resolve o "sem histórico" da reclamação). **Bleeding parado** — replies agora roteiam certo sozinhos.
- **🟡 FRENTE 1 — job consertado, COMMITADO LOCAL (`11b913531`), NÃO deployado.** `disparo_lead_job.rb`: `resolved_source_id` (usa `PhoneNumberNormalizationService` → reusa a ficha que o WhatsApp já usa) + `find_or_create_conversation` (reusa a conversa única, reabre+atribui; cria só se nunca existiu). **Impede o próximo disparo de re-duplicar.**
  - ⚠️ **BLOQUEIO de deploy — DIVERGÊNCIA prod↔repo:** o job em prod (AWS, **124 linhas**) está **ATRÁS do repo** — **não tem** a lógica de inquilinos (`NO_BODY_VAR`/`INQ_IMAGE_URL`/`no_var_params` + chaves `tozi_inq_*`). Resíduo das múltiplas sessões. **NÃO transportar o arquivo inteiro** (clobberaria). Deploy de frente 1 = **patch cirúrgico in-place** (3 pontos: source_id + find_or_create + 2 helpers, baseline confere) + restart `chatwoot-worker.1`. Backup do job feito na AWS (`.bak.*`). `migrate:status` = **0 down** (restart seguro; ⚠️ contradiz o STATE que dizia a landmine `20260330120000` down — investigar se foi aplicada).
  - **PENDENTE:** aval do Paulo pro patch cirúrgico + restart do worker. Não urgente (bleeding já parado; frente 1 só previne disparo futuro).
  - 🔴 **O deploy das 01:48 (rollout) também dropou ASSETS off-git:** `public/inq-mapa.jpeg` → **404** (imagem do header dos templates `tozi_inq_*`). Templates existem APPROVED no canal, mas **envio de imagem falharia** (Meta busca a URL no envio). Some também do repo/local. Recuperável: anexo `mapa-localizacao.jpeg` da resposta rápida `/interesse` (att 411283, em prod) — *se for o mesmo mapa*. Reforça que a reconciliação tem que trazer **código + assets** da paulao/off-git pra rollout.

### [2026-06-08] ⏸️ Follow-up 2ª leva (600 locação) — EM ESPERA (Paulo: "segura")

> Pool de follow-up por segmento (não-respondentes sem re-bate): **Locação 669 · Venda 2.206 · Inquilinos 1.015 = 3.890**. Disparos novos faltando: **Inquilinos 2.470** (locação/venda esgotadas, ~35 resíduo).

- Paulo pediu armar **600 da locação** (17:30 Sinop = 21:30 UTC, round-robin Lucas#127/Bruno#131/Kettlen#126, 200 cada, 5s) com **template de imagem**. **Travado** porque a imagem morreu (ver acima) → exigiria recuperar imagem + dar suporte a header de imagem no `FollowupHsmJob` (hoje só texto) + deploy/restart em prod. Paulo mandou **segurar**.
- ✅ Confirmado: follow-up é **seguro pós-consolidação** — `FollowupHsmJob` manda na conversa única existente (não duplica; o bug era só do `DisparoLeadJob`). Alternativa zero-deploy quando retomar: texto `tozi_followup_lanc` (copy encaixa nos não-respondentes), sem mexer em prod.
- **🟢 DISPAROU (09/06 ~22:20 UTC):** 670 não-respondentes locação, 4 corretores **Marcus#128/Kettlen#126/Bruno#131/Lucas#127** (~167 cada, round-robin, reatribuídos via `update_columns`), 5s, `tozi_followup_lanc` (1 var). Script `Downloads`/tmp `fu_schedule.rb`. Termina ~23:16 UTC.
  - 🔴 **GOTCHA grave:** o `followup_hsm_job.rb` tinha **SUMIDO de prod** (`uninitialized constant Spx::Tozi::FollowupHsmJob`) — dropado no deploy 01:48 junto com TODO o código off-git da paulao. **Restaurei** via scp do repo local → prod + **restart `chatwoot-worker.1`** (migrate:status 0 down). Agora prod tem o job de novo (mas é remendo; a reconciliação real continua pendente).
  - Falhas iniciais ~40% = **131026 número morto** (esperado nos não-respondentes; não cobrado) + 1× 130472 pacing. **Não é bug** — envio saudável (entregues OK).
  - ⚠️ Cada vez que prod for redeployado da `rollout`, esse job (e a imagem, e a lógica inq) **somem de novo**. Reconciliar a `rollout` com a paulao é o conserto definitivo.

### [2026-06-05] 🔁 FOLLOW-UP re-engajamento (capacidade nova: HSM na conversa EXISTENTE)

> Re-bater nos NÃO-RESPONDENTES da campanha 1 (lançamento/locação). Paulo: 600 total, corretores Lucas+Bruno.

- **Audiência:** campanha 1, alcançados (delivered/read) SEM incoming, atribuídos a Lucas(127)/Bruno(131) = 691 → cap **600** (interleave: Lucas 330 + Bruno 270, ambos cobertos). Script `Downloads/followup_schedule.rb`.
- **🆕 `Spx::Tozi::FollowupHsmJob`** (`app/jobs/spx/tozi/followup_hsm_job.rb`, no repo + prod): envia o HSM **DENTRO da conversa que já existe** (não cria nova — diferente do DisparoLeadJob), `conv.open!` se resolvida, mantém o assignee. 1 variável ({{1}}=nome). Pausar: deletar `FollowupHsmJob` do ScheduledSet.
- **Template `tozi_followup_lanc`** (id 2265413040930153, MARKETING/pt_BR, PENDING): "Oi {{1}}, mandei uma mensagem essa semana e ainda não tive retorno seu..." + botões `Tenho interesse`/`Me chama depois`. ⚠️ "Oi" adicionado antes de {{1}} (Meta não deixa corpo começar com variável).
- **Monitor** espera DisparoLeadJob (inquilinos) zerar + template aprovar → sync → amostra do follow-up na conversa do Paulo → se OK, dispara 600, 5s ~50min.
- **🟢 DISPAROU (05/06):** monitor disparou auto quando inquilinos zerou. Paulo mandou "não disparar inquilinos hoje" mas inquilinos **já tinha terminado** (1.178 enviados, 975 ok). Follow-up foi pausado no 44º, Paulo confirmou **"follow-up sim, inquilinos não"** → retomado com exclusão dos 44 já-enviados (`already_fu` no `followup_schedule.rb`), +556 → **600 total** (Lucas 330 / Bruno 270). 5s.
- **🟢 FOLLOW-UP VENDA +400 (05/06):** Paulo pediu "mais 400" → base de VENDA. Mesmo template/job, alvo = não-respondentes da **campanha 2** no fio existente. Primeiro rodou K/L/B (134/133/133), mas Paulo corrigiu **"só Bruno e Lucas"** → pausei (375 deletados, incl. Kettlen) e re-disparei **400 = Lucas 200 + Bruno 200** (exclui já-enviados via `already_fu`). Script `Downloads/followup_venda_schedule.rb` (BROKERS=[127,131]). ⚠️ Número **YELLOW** (Paulo ciente; follow-up warm). Monitorar.

### [2026-06-05] 🖼️ INQUILINOS — disparo com TEMPLATE DE IMAGEM (capacidade nova) + auto-armado

> Lista nova `INQUILINOS.xlsx` (3.919). Guilherme vetou gatilho "sair do aluguel" (lista tem inativos, alguns já compraram). Copy refeita: ângulo oportunidade/investir/relacionamento, **sem nome** (nomes estranhos), **sem presumir status**.

- **Ingestão `Downloads/ingestao_inquilinos.py`** — dedup 4 camadas: corretores + já-enviados + **CONVERSA ABERTA na inbox 91** (não-resolvida, p/ não misturar assunto) + dup. Recuperação: 9-díg→DDD 66, 8-díg→66+9, trunk-0→tira 0 mantém DDD. **3.654 net-new** (`tozi_inquilinos_limpa.csv`).
- **🆕 TEMPLATE COM IMAGEM (1ª vez):** 3 criados `tozi_inq_lancamento`/`tozi_inq_invest` (header IMAGE = mapa localização, represamento) + `tozi_inq_cliente` (texto). Imagem subida via **resumable upload** (`POST /APP_ID/uploads` → handle; APP_ID=1147301410628990) em `Downloads/create_inq_templates.rb`. Hospedada pública p/ envio: `https://tozi.chatspx.app/inq-mapa.jpeg` (em `public/inq-mapa.jpeg`).
- **🆕 JOB ESTENDIDO** (`disparo_lead_job.rb`): branch `NO_BODY_VAR` (templates inq = corpo SEM variável) + `no_var_params` monta `processed_params: {header: {media_url: URL, media_type: 'image'}}`. Formato descoberto em `Whatsapp::TemplateProcessorService#build_header_params` (espera `media_url`+`media_type`). Caminho de 2 variáveis intacto (A/B não quebra).
- **Disparo:** `Downloads/disparo_inq.rb` — 1.200, 3 corretores **Bruno #131/Kettlen #126/Lucas #127** (400 cada), 3 templates decorrelacionados, 5s, ~1h40. CSV em `/home/chatwoot/tozi_inquilinos_limpa.csv`.
- **Monitor background** espera A/B 227 zerar + 3 aprovarem → sync → **amostra com imagem pro Paulo** → se entregar (= Meta buscou a imagem) → solta os 1.200. Gotcha: "delivered" num template de imagem prova que a imagem foi buscada/entregue OK.

### [2026-06-04] 🧪 A/B QUALIFICADO DISPAROU 20:41 (auto via monitor) — base de venda ESGOTADA

> A/B `tozi_venda_oportunidade` (137) vs `tozi_venda_lembrei` (136) disparou automático às 20:41 (monitor esperou o 1.000 zerar → sync → amostra delivered pro Paulo → soltou). **273 leads, só Kettlen** (Bruno/Marcus/Lucas removidos a pedido), split 50/50 perfeito (fórmula `j % TEMPLATES.size`), 5s, ~23min. **Base de venda zerada após** (3.398 elegíveis todos disparados ao longo dos lotes). **PENDENTE:** medir a **taxa de resposta QUALIFICADA** de cada template (cliques `Quero saber` + interesse real / enviados) quando o lote terminar (~21:04) — esse é o payoff do teste. Motor `Downloads/disparo_ab.rb`.

### [2026-06-03] 🟢 DISPARO VENDA Tozi (proprietários de venda, copy nova, 5s, SEM cap)

> Segundo disparo. Público = **PROPRIETÁRIOS DE VENDA** (vendedores), segmento NOVO (lista de locação já tinha sido toda disparada — ver entrada de 02/06). Paulo quer **contínuo a 5s, sem cap, ele manda parar** (ver [[feedback-disparo-continuo-sem-cap]]).

- **Audiência:** `PROPRIETARIOS VENDA - removidos ativos...xlsx` (3.505) → ingestão `Downloads/ingestao_tozi_v4.py` (canonical DDD+8, dedup tríplice: blacklist corretores 1.177 + já-enviados DB + dup interno + filtro fake `(\d)\1{6,}`) → **3.394 elegíveis** (`Downloads/tozi_venda_limpa.csv`). Só 5 overlap com locação (segmento limpo).
- **Templates (APPROVED + sincronizados):** `tozi_venda_prioridade` (1507152557728445), `tozi_venda_investidor` (1473243537915273), `tozi_venda_condicoes` (1911525192852443). MARKETING/pt_BR, {{1}}=lead {{2}}=corretor, 2 botões quick-reply: **"Tenho interesse" / "Quero, mas outro horário"**. Criados via `Downloads/create_venda_templates.rb` (Net::HTTP→Graph API, rodado na AWS p/ não corromper acento).
- **Motor:** `Downloads/disparo_venda.rb` (rodado na AWS via `rails runner`, `DRY=1` simula / `DRY=0` enfileira). Decorrelacionado (cada corretor manda os 3 templates), round-robin **Kettlen #126 / Bruno #131 / Lucas #127 / Marcus #128** (~849 cada), 5s, `campaign_id=2`.
- **Campaign âncora #2** "Disparo Venda Tozi" (one_off/completed — nunca auto-dispara). Stats via tela de campanha por `campaign_id=2`.
- **PAUSAR:** deletar `DisparoLeadJob` do `Sidekiq::ScheduledSet` (script igual aos de `Temp/`). Início: 3.379 na fila após enfileirar.
- **🔴→✅ SUSTO "mensagens estranhas" (resolvido):** Paulo viu no painel a bolha cortada **"Oi Adriana!"** e mandou pausar. Diagnóstico: o `DisparoLeadJob` tem hash `PREVIEWS` (o `content` que o time vê na transcrição) e os `tozi_venda_*` **não estavam lá** → caía no fallback `'Oi %<n>s!'`. **Era só o rótulo interno** — o LEAD sempre recebeu o template completo (confirmado: corpo aprovado na Meta idêntico, params {{1}}/{{2}} certos, 0 duplicatas, 3 testes pro WhatsApp do Paulo chegaram perfeitos). **Fix:** adicionados os 3 `tozi_venda_*` ao `PREVIEWS` com corpo completo (`app/jobs/spx/tozi/disparo_lead_job.rb`, deploy + **restart worker** com disparo pausado) → painel agora mostra a mensagem inteira. Repo sincronizado com prod.
- **Retomado 03/06:** re-enfileirado com dedup (`skip ja_enviado:51, fake:4`) → **3.343** a 5s. ⚠️ `prioridade` diz "aqui é **o** {{2}}" — fica "o Kettlen" (mulher), gramática torta só nesse template c/ corretora mulher.
- **🔄 TROCA p/ template CURTO (03/06):** Paulo dispensou os 3 longos e pediu um **curto com botões**. Criado `tozi_venda_abertura` (id 1737345930628257, MARKETING/pt_BR, **APPROVED**): *"Oi {{1}}, tudo bem? Aqui é {{2}}, da Tozi Imóveis. Tá podendo falar agora?"* + botões **`Sim, pode falar` / `Agendar horário`**. Gênero-neutro ("Aqui é {{2}}"). Adicionado ao `PREVIEWS` do job (deploy + worker restart). **Kettlen #126 removida** da rotação → só **Bruno #131 / Lucas #127 / Marcus #128**. Motor: `Downloads/disparo_venda_curto.rb` (template único + 3 corretores). **314 já tinham recebido os 3 longos** (51 1ª leva + 263 na retomada); os **3.082 restantes** recebem o curto. Re-enfileirado 03/06 (`skip ja_enviado:312, fake:4`), 5s, ~4,3h.
- **⚠️ Falhas esperadas:** lista de vendedores tem muito 131026 (sem WhatsApp) + 130472/131049 (pacing). Não-cobradas.
- **🟢 FASE 2 (04/06):** 3 templates NOVOS APPROVED (`tozi_venda_condicao` 1391763976151966 / `tozi_venda_invest` 874042698421860 / `tozi_venda_suites` 996870739390338, copy refinada, **gênero-neutro "aqui é {{2}}"** + botões `Tenho interesse`/`Quero, mas outro horário`). Disparo **1.200** (Paulo deu cap explícito desta vez — exceção ao [[feedback-disparo-continuo-sem-cap]]) — 4 corretores Kettlen #126/Marcus #128/Lucas #127/Bruno #131 (300 cada), 3 templates (400 cada), 5s, ~1h40. Número GREEN, primeiros sends 0 falha. Motor `Downloads/disparo_venda2.rb` (cap `LIMIT=1200`) + `create_venda2_templates.rb`. Sobram ~1.273 na base após.
- **🟢 LOTE 3 (04/06):** mais **1.000** com o template CURTO `tozi_venda_abertura` (4 corretores Kettlen/Marcus/Lucas/Bruno, 250 cada, cap 1.000, 5s, ~1h23). Motor `Downloads/disparo_curto_lote2.rb` (`LIMIT=1000`, 4 brokers). Dedup excluiu 2.121 já enviados → 1.000 de 1.273 disponíveis; **sobram ~273** após. Número GREEN.
- **🧪 A/B QUALIFICADO (04/06) — auto-disparo armado:** insight do Paulo: curto "Tá podendo falar?" enche de volume DESQUALIFICADO (clientes acham que é sobre o imóvel deles); longo qualifica mas pouco volume. Solução = **curiosidade ancorada no benefício**. 2 templates novos APPROVED-pending p/ A/B: `tozi_venda_oportunidade` (3096853437186543, "Separei uma oportunidade boa pra você... valoriza rápido e dá pra alugar. Quer que eu te conte?") + `tozi_venda_lembrei` (1298701482390341, "Apareceu uma oportunidade que combina com cliente da casa e lembrei de você... valoriza e gera renda. Vale 2 min?"). Botões iguais (isola copy): `Quero saber`/`Me chama depois`. **Esgota os ~273 restantes**, split 50/50 por lead (`template = j % TEMPLATES.size` — fórmula trocada porque a antiga `(j + j/N)%2` quebrava com N=1 e mandava só 1 template). **SÓ Kettlen #126 — Bruno #131, Marcus #128 e Lucas #127 removidos a pedido 04/06** (jobs pendentes deles no lote de 1.000 reatribuídos pra Kettlen via `reassign_{bruno,marcus,lucas}.rb`, horários preservados: 66+59+75). ⚠️ Tudo concentrado na Kettlen (~423 convs: 150 do 1.000 + 273 A/B). Motor `Downloads/disparo_ab.rb` (LIMIT=0). **Monitor background** espera 1.000 zerar + aprovação → sync → amostra pro Paulo → se OK dispara. Previews dos 2 já no job. ⚠️ Gotcha de relógio: server loga UTC (≠ Sinop UTC-4) — "00:40 UTC" = 20:40 Sinop. Métrica do teste = **taxa de resposta QUALIFICADA** (não volume bruto).
- **🟢 SAÚDE recuperou pra GREEN (04/06):** número estava YELLOW, voltou pra **GREEN** após pausa + engajamento alto (433 respostas, 24,5% no curto). WABA APPROVED/verified, `health_status.can_send_message=AVAILABLE` (WABA+Business+App), throughput STANDARD, inbound vivo (250/12h). **Seguro retomar.** Lição: blast de pitch longo em base fria derruba reputação; template curto que gera resposta a PROTEGE (Meta premia engajamento). Custo real acumulado (2 disparos, via pricing_analytics): **US$135,12 ≈ R$701** (2.162 marketing entregues; 2.954 service grátis). Relatório PDF: `Downloads/Relatorio-Disparos-Tozi.pdf` (1 pág, gerador `report_gen.py` + `report_data.rb`).
- ⚠️ **Qualidade do número = YELLOW** (degradou no 1º disparo). Falhas iniciais: **131026 sem-WhatsApp** (lista de vendedores tem mais nº morto) + **131049/130472 pacing** (Meta já throttla marketing cedo no YELLOW). Risco real de RED se mandar tudo (3.394 = 4,7h, ~R$1.065). Paulo controla o stop.
- **Job hardcoda** `source='disparo_lancamento'` → venda entra no mesmo dedup futuro (ok). `tozi_venda_limpa.csv` na AWS em `/home/chatwoot/`.

### [2026-06-02 noite] 🟢 DEPLOY CONCLUÍDO (tela campanha + anexo resposta-rápida) — disparo FINALIZOU

> Disparo copy-nova **terminou** (Paulo confirmou "os envios terminaram"). Com a fila zerada, as 2 features foram deployadas num **precompile único + restart só do `chatwoot-web.1`** (worker intocado — nenhuma das 2 usa job). Guard `migrate:status` = `down==1` (só a landmine). HTTP local+público 200. **Números finais do disparo (campaign_stats #1): total 1529, alcançados 1337, entregues 457, lidas 824, falhas 178 (131026=119 sem-WhatsApp, pacing 58, outro 1), respostas 180.** Distribuição Lucas 583 / Kettlen 583 / Bruno 363.

**Disparo "Lançamento Tozi" — copy NOVA (Guilherme refinou), rodando:**
- Templates novos **APROVADOS + sincronizados** no WABA: `tozi_lanc_prioridade` (id 874854259000986), `tozi_lanc_portfolio` (2773640852999289), `tozi_lanc_investidor` (869549619532683). MARKETING/pt_BR, **{{1}}=lead + {{2}}=corretor**, 2 botões ("Tenho interesse"/"Quero saber mais"). (Os `tozi_aquarela_*` com Guilherme fixo foram **apagados** no WhatsApp Manager — nome trava ~4 semanas.)
- `app/jobs/spx/tozi/disparo_lead_job.rb` **DEPLOYADO**: `agent_first_name(assignee_id)` preenche `{{2}}`, PREVIEWS novos, grava `campaign_id=1`. Worker reiniciado.
- **GOTCHA resolvido:** template novo dava `#132000 number of parameters` até `Inbox.find(91).channel.sync_templates` (o SendOnWhatsappService usa os templates SINCRONIZADOS, não só processed_params). Depois precisou **restart do worker** pra limpar cache de templates.
- **Resume:** corretores **Kettlen #126 / Lucas #127 / Bruno #131**, **5s**, dedup. ~412 já enviados + **420 restantes DECORRELACIONADOS** (`template=(j + j/3)%3` — cada corretor manda os 3; o `i%3` original casava corretor↔template = cada um mandava só 1). Os ~412 da 1ª parte ficaram correlacionados (irreversível). 1ª leva (695) usou copy ANTIGA `tozi_lancamento_*`.
- Scripts em `Temp/`: `resume_lanc.rb`, `fix_decorrelate.rb`, `monitor_lanc.rb`, `create_lanc_templates.rb`.

**Respostas rápidas criadas** (Account 6, com `{{contact.name}}`): `/interesse` (loc+lista prioridade) + `/preco` (deflete preço + qualifica investir/uso).

**🟢 DEPLOYADO (02/06 noite)** — precompile único (`✓ built in 2m20s`, manifest 23:35) + restart `chatwoot-web.1`:
1. **Fix tela campanha** — `app/javascript/dashboard/api/campaigns.js`: **axios GLOBAL** (`/* global axios */`) em vez de `import axios` (era 401 → "Não foi possível carregar estatísticas"). ✅ no ar.
2. **Anexo em respostas rápidas** (9 arquivos): Back — `canned_response.rb` (`has_many_attached :attachments`) + `canned_responses_controller.rb` (permit `attachments: []` + serialize `file_url: url_for(att)` + purge no update). Front — `api/cannedResponse.js` (FormData c/ anexo), `AddCanned.vue`+`EditCanned.vue` (input file), `CannedResponseModal.vue` (emite `attachments` no select), `ReplyBox.vue` (`onCannedResponseSelect`→`attachCannedResponseFiles`: fetch `file_url`→File→`onFileUpload`), `cannedMgmt.json` en+pt_BR (`FORM.ATTACHMENT.LABEL`). ✅ no ar.

**Verificação pós-deploy (backend, server-side ✅):** `campaign_stats(#1)` retorna hash completo (números acima); `CannedResponse#attachments` carrega (`has_many_attached`); **mapa anexado na resposta #77 `/interesse`** (att id=411283, `mapa-localizacao.jpeg`, 290KB) e `rails_blob_url` serve com `302 → disco` (fetch do ReplyBox segue o redirect). Endpoint `GET /canned_responses` (HTTP 200) já traz `attachments:[{id,filename,file_type,file_url}]` por item.

**🔴→✅ BUG do anexo inline (achado quando Paulo testou "não vi mapa no /interesse") — corrigido + deployado (02/06 ~00:12):** havia **2 caminhos** de resposta rápida e só o **modal** estava ligado ao anexo. O **`/` inline** (o que o time usa) é renderizado pelo editor ProseMirror (`Editor.vue` → `CannedResponse.vue` via `MentionBox`), que inseria **só o texto** (`@replace`) e descartava `attachments`. Fix aditivo em 3 arquivos: `CannedResponse.vue` emite `@attach` com `selected.attachments` (match por `short_code===item.key`); `Editor.vue` encaminha via emit `attachCannedFiles`; `ReplyBox.vue` liga **os 2 editores** (compositor padrão 2291 + wa-composer-bar 2530) ao `attachCannedResponseFiles` já existente. **Zero regressão** (canned sem anexo nunca dispara `@attach`). Revisão adversarial OK: MentionBox repassa item completo (`item.key` sobrevive); `onFileUpload({name,type,size,file})` = mesmo shape do drag-drop (ReplyBox:1103). **Falta só Paulo testar** (hard-refresh Ctrl+Shift+R p/ pegar o bundle novo): (a) 📊 no card da campanha carrega; (b) digitar `/interesse` inline → texto + mapa juntos.

**Deploy B (tela de campanha) JÁ no ar:** endpoint `GET /api/v1/accounts/:id/campaigns/:id/stats` (`campaigns_controller#stats` + `campaign_stats`, agrega por `campaign_id`) + policy `stats?` + rota detalhe `campaigns_whatsapp_detail` (`whatsapp/:campaignId`) + `WhatsAppCampaignDetail.vue` + card 📊. Faltava só o fix do axios (item 1).

### [2026-06-02] 🟢 PLANO DE GO-LIVE DA IA (prioridade — resolver o quanto antes)

> **🟢 RE-VERIFICADO AO VIVO 2026-06-10 (read-only, prod AWS Account 6).** Cérebro + infra **100% prontos e intactos** (o deploy 08/06 que dropou código off-git NÃO mexeu na config da Clara — ela vive no DB). Estado seguro: Clara **desconectada** (`CaptainInbox(91)=nil`, `active_bot?=false`, `agent_bot=nil`). Confirmado: `captain_integration_v2=true`; `captain_auto_resolve_mode='disabled'`; modelo `claude-sonnet-4.5`; cota captain 99.841/100k; knowledge `hybrid` (1 doc Playbook *available* + **40 Q&A com embedding**); Scenarios Vendas#5=6274 / Locação#6=3719 / Suporte#7=2796; chaves LLM SET no InstallationConfig (que é de onde o `ai_agents.rb` lê — `after_initialize`); `TOZI_VISTA_API_KEY` SET no env do worker; canal `whatsapp_cloud` com `api_key`; código SPX/Tozi presente (`disparo_lead_job`, `followup_hsm_job` restaurado 09/06, `funnel_placement_service`, `reactivation_cadence_service`).
>
> **⚠️ CORREÇÃO do bloqueio #1 (pending limbo):** o item 1 abaixo está **superdimensionado**. `Inbox(91).pending_status_enabled?` = **`false`** (coluna real no DB, default false, **independente do bot** — NÃO deriva de `active_bot?`). Em `reopen_resolved_conversation` a guarda é `active_bot? && pending_status_enabled?` → com pending desligado, conversa resolvida que recebe msg do cliente cai no `else → conversation.open!` (**reabre, não vira pending**). Logo o stub `captain_pending_conversation?=false` é **inofensivo hoje** (o caminho `pending!` nunca roda). **O incidente NÃO recorre por essa via.** ⚠️ **Único cuidado:** NÃO ligar "status pendente" da inbox 91 na UI (`pending_status_enabled`) — se ligar, o limbo volta (o stub continua lá).
>
> **Resta só DECISÃO, não trabalho:** (a) recriar `CaptainInbox(91,7)` e (b) abrir a whitelist `only_contact_phones` (hoje só `+5566996350491`). Recomendado: **piloto controlado** (reconectar + N números reais + monitorar 1 dia → remover whitelist).

A Clara está **DESCONECTADA da inbox 91** (test-mode encerrado por causa do incidente abaixo). Pra religar pra valer, resolver ANTES (senão o incidente volta):

1. **Pré-req reabertura:** com a Clara religada `active_bot?` volta a `true` → resposta de cliente em conversa resolvida vira **pending limbo** de novo (`Message#reopen_resolved_conversation`: inbox com bot → `pending!` em vez de `open!`). **🟢 NEUTRALIZADO 10/06:** só dispara se `pending_status_enabled?=true`, e na inbox 91 está **false** → reabre como `open!`. Resolver com UMA das opções: (a) Clara atende de verdade (tira whitelist) e abre a conversa, **ou** (b) corrigir o código — `mark_pending_conversation_as_open_for_human_response` está **stubbado `false`** em `app/models/message.rb` (`captain_pending_conversation?` retorna false), então nem resposta humana abre a pending.
2. **Whitelist:** sair de `behavior.router.only_contact_phones=["+5566996350491"]` de forma controlada (piloto com N leads → geral).
3. **Auto-resolve:** manter `captain_auto_resolve_mode='disabled'` OU reconfigurar com cuidado (mensagem PT decente, gateado, sem loop pending→resolve).
4. **Reconectar:** recriar `CaptainInbox(inbox_id=91, captain_assistant_id=7)` só depois dos 3 acima. Testar E2E: cliente que volta é atendido (não fica pending).
5. **Cérebro (já validado/staged):** prompt Júlia (Scenario Vendas #5, 6274 chars) + knowledge (1 doc Playbook 19 chunks + 40 Q&A nativas, modo hybrid) + tools (`buscar_imovel` via `TOZI_VISTA_API_KEY`, geocoding com chave embutida).

### [2026-06-02] 🔴→✅ INCIDENTE: IA fechando conversas / "mensagens sumindo" — RESOLVIDO

**Sintoma:** equipe achou que o número parou de receber mensagens + conversas fechando com *"Resolvendo a conversa dado que está inativa..."*. Suspeita: IA.

**Diagnóstico (com dados):** número 100% saudável na Meta (`CONNECTED/GREEN/STANDARD`); inbound nunca parou (241 msgs/dia, última há 1 min). A causa era a combinação:
- Inbox 91 com Clara conectada → `active_bot?=true`. Em `Message#reopen_resolved_conversation`, inbox com bot → conversa resolvida que recebe msg do cliente vira **`pending!`** (não `open!`), esperando o bot atender.
- Clara com **whitelist** (`only_contact_phones`, só o nº do Paulo) → **não atende o lead** → conversa **presa em pending** (invisível na aba "Abertas").
- **Auto-resolve do Captain** (`Enterprise::Account::ConversationsResolutionSchedulerJob` → `Captain::InboxPendingConversationsResolutionJob`) fechava as pending inativas >1h com a mensagem PT (pública) + nota EN "Auto-resolved:" (privada). **57 PT + 55 EN, ~17 convs, inboxes 61/62/91**, ondas 23/05 (47) + 01/06 (10), **última 01/06 15:34**.

**Fixes aplicados (prod):**
- **Auto-resolve:** `Account.find(6).captain_auto_resolve_mode='disabled'` (já estava, desde 01/06). Trava DUPLA no código (scheduler linha 15 + job linha 8: `return if captain_auto_resolve_disabled?`). **Zero auto-resolve desde 01/06 15:34** (confirmado: 0 hoje).
- **Reabertura:** **Clara DESCONECTADA da inbox 91** — `CaptainInbox(91,7)` destruído → `active_bot?=false` → cliente que volta cai no `else → conversation.open!` (reabre como **Aberta**). Clara (assistant #7, config/knowledge/cenários) **intacta**, reconecta no go-live.
- **Recuperação:** **76 conversas presas reabertas** (74 inbox 91 + 1+1 em 61/62) + 5 pending limbo zeradas.

**Bug residual conhecido (não corrigido):** `reopen_resolved_conversation` manda pra `pending!` em inbox com bot — ok SE o bot atende; vira limbo se o bot está calado (whitelist). Tratar no go-live (item 1 do plano acima).

### [2026-06-02] 🟡 Disparo "Lançamento Tozi" EXECUTADO (parcial, PAUSADO) + Campaign âncora + view "Não lidas"

**Disparo (motor próprio, NÃO o nativo):**
- **695 enviados de 1.526** (601 entregues, 335 lidas, **87 falhas**: 56 sem-WhatsApp `131026` + 31 pacing Meta `130472`/`131049`). **832 segurados** (pausados; jobs cancelados do Sidekiq).
- Motor: `app/jobs/spx/tozi/disparo_lead_job.rb` (cria contato+conversa+atribui+HSM, grava `campaign_id`) + rake `spx:tozi:disparo[csv,limit,dry_run,spread_min,template]` + `spx:tozi:disparo_teste`. Pacing ~4,8s, round-robin, rotação 3 templates `tozi_lancamento_{interagir,qualifica,curiosidade}` (aprovados, 2 botões positivos + Agendar). CSV audiência: `Downloads/tozi_audiencia_limpa.csv` (1.526) na AWS em `/home/chatwoot/`.
- **Distribuição final:** Kettlen #126 **305**, Lucas #127 **304**, Bruno #131 **86** (Marcus #128 e Guilherme #125 tirados e redistribuídos). Corretores isolados por custom role "Corretor".
- ⚠️ **Adrian #63 e Gelson #72 mandaram ~11 HSM na mão** (fora do orquestrador, sem `campaign_id`) — equipe continuou disparo manual.
- Pausar/retomar/redistribuir/dedup = scripts console (canonical = DDD+8). Pra retomar: re-enqueue com dedup pelos já-enviados.
- **Relatório PDF:** `Downloads/Relatorio-Disparo-Tozi.pdf` (89 respostas → **63 positivas / 21 negativas / 5 neutras**; gerado via Python→HTML→Edge headless).

**Campaign nativa como âncora (Campanhas › WhatsApp) — Deploy A no ar:**
- **Campaign #1** "Disparo Lançamento Tozi" criada `completed` (NUNCA dispara o blaster nativo: scheduler ignora não-active + `trigger!` retorna `if completed?`). 695 conversas linkadas via FK `campaign_id`.
- **Blaster WhatsApp nativo DESATIVADO** (`Campaign#execute_campaign` só loga — `Whatsapp::OneoffCampaignService` não tem pacing/atribuição/rotação, atropelaria o WABA) + **botão "Nova campanha WhatsApp" REMOVIDO** (`WhatsAppCampaignsPage.vue` vira viewer; `CampaignLayout.vue` botão `v-if="buttonLabel"`). Quebra 1 spec nativo (esperado).
- ⚠️ **FALTA Deploy B:** tela de **detalhe** da campanha (dashboard agregado por `campaign_id`: progresso/entrega/distribuição/conversas + Pausar/Retomar). Conceito = "Painel de Disparos" (workflow). Card hoje só lista/exclui.

**View "Não lidas" deployada (12 arquivos, no ar):** scope `Conversation.unread` (incoming após `agent_last_seen_at`) + finder `conversation_type=unread` + rotas `conversation_unread` + item sidebar (abaixo de "Mencionadas") + i18n en/pt_BR. Espelha o "Não respondidas". Validado E2E.

### [2026-06-01] 🟡 Clara ATIVADA em MODO TESTE em prod (só +5566996350491)

> ⚠️ **SUPERADO em 02/06:** a Clara foi DESCONECTADA da inbox 91 (ver incidente acima). O conteúdo abaixo é histórico do estado em 01/06.

**Mudança de estado crítica:** a Clara (#7) saiu de DESLIGADA para **LIGADA em modo teste** na inbox 91 (Account 6).
- `CaptainInbox(inbox_id=91, captain_assistant_id=7)` criado → `inbox91.captain_assistant=Clara`.
- `behavior.router.only_contact_phones` trocado de 4 números antigos para **`["+5566996350491"]`** (número do Paulo). Só ele recebe resposta; todos os outros (386 conversas abertas + leads reais) → router skip → Clara calada.
- `captain_active?=true` (cota captain.responses: 99.856 disponíveis de 100k) → **sem risco de `perform_handoff`** (que mandaria "Transferring to another agent" em inglês nas pending se a cota estivesse zerada). `skip_after_human_response=true` e `skip_groups=true` preservados.
- Chaves LLM (InstallationConfig global OpenAI+Anthropic) setadas.
- **[2026-06-01] Modelo trocado pra Claude:** `account.captain_models['assistant']` = **`claude-sonnet-4.5`** (era `gpt-4.1`). O modelo do runner v2 vem de `account.captain_assistant_model` (= dropdown "Assistente" da tela LLM Settings), lido a cada request. Chave: o `ai_agents.rb` configura o gem `agents` no boot com a Anthropic **GLOBAL** (`CAPTAIN_ANTHROPIC_API_KEY`) — a chave per-conta da UI NÃO alimenta o v2. **Chave global testada ao vivo: chamada a `claude-sonnet-4-5` respondeu "OK".**
- **⚠️ Worker precisa reiniciar** pra carregar a chave Anthropic global no runtime (`Agents.configure` roda no boot). Modelo muda sem restart; chave não. Reiniciar `chatwoot-worker.1` antes do teste E2E.

**Sessão de teste 01/06 — achados e fixes (todos em prod):**
- ✅ **Modelo trocado pra Claude Sonnet 4.5** (`captain_models['assistant']`). Chave Anthropic global validada ao vivo. Teste direto do agente: Júlia respondeu natural em PT-BR, roteou pra cenário Locação. **Cérebro OK.**
- 🔴→✅ **Auto-resolve estava ligando junto com a Clara e mandando "inicie uma nova conversa" + resolvendo conversas de CLIENTES REAIS** (10 msgs/6h, NÃO gateado pela whitelist). Kill-switch: `account.captain_auto_resolve_mode` (`store_accessor :settings`, default 'evaluated'). **Setado `'disabled'`** via `Account.find(6).update!(captain_auto_resolve_mode: 'disabled')`. Scheduler `Enterprise::Account::ConversationsResolutionSchedulerJob` roda p/ TODA `CaptainInbox` exceto `captain_auto_resolve_disabled?`.
- 🐛→✅ **Bug do handoff v2:** quando o agente faz handoff, `result.output` volta vazio → `ResponseBuilderJob` tratava como `[IGNORAR]` → **fala de transferência sumia no WhatsApp**. Fix em `AgentRunnerService#process_agent_result` (fallback `last_assistant_message_text`). Commit `02bcbac0f`, transportado + worker restart.
- ✅ **n8n desligado da inbox 91:** o `AgentBot "Clara" #7` (webhook n8n, 19.614 msgs) ainda estava plugado mesmo após Paulo remover workflow/webhook. **`AgentBotInbox(inbox_id=91)` destruído** → `inbox91.agent_bot=nil`. Captain Clara intacta. Migração n8n→SPX concluída na inbox 91.
- ⚠️ **Whitelist FUNCIONA** (dezenas de `router_skip` p/ clientes reais; só o nº do Paulo engaja). Mas a inbox 91 é **produção viva** (atendentes reais + clientes o tempo todo) — cuidado com efeitos colaterais ao mexer.
- ⚠️ **Conv 2159 = thread de teste podre** (centenas de msgs, multi-dia) → histórico polui o agente. Limpa: 2132 deletada, 2159 esvaziada (557 msgs+38 anexos). **inbox 91 tem `lock_to_single_conversation=true`** → não cria conversa nova por contato; reusa/reabre a última.
- 🟢 **E2E APROVADO (01/06 16:07):** Clara (Captain v2, **Claude Sonnet 4.5**) respondeu "Oi, Paulo! Tudo bem? 😊" / "Como posso te ajudar hoje?" — outgoing público, humanizer quebrou em 2, enviado no WhatsApp. 2.9s. Sender=Captain::Assistant (não AgentBot). Pipeline completo OK.
- 🟢 **Indicador "digitando" + espaçamento (commits `0b3307830`, `71629abe1`):** typing via Cloud API (`status:read`+`typing_indicator`, **v21.0** — v13.0 do endpoint padrão NÃO suporta). `Whatsapp::Providers::WhatsappCloudService#send_typing_indicator(source_id, show_typing=true)` (show_typing=false = só read/tique azul) + no-op no base + delegate no `Channel::Whatsapp`. **Comportamento final (após feedback do Paulo):** tique azul (read) imediato no hook **sem** typing contínuo; "digitando" só em **rajada curta antes de CADA pedaço** do humanizer, proporcional ao tamanho (`delay_per_char_ms` 45, piso 1,5s / teto 7s). Corrige "typing contínuo da chegada até a resposta" (robótico) + mensagens fora de ordem. Best-effort (rescue), só WhatsApp Cloud.
- 🔴→✅ **Busca de imóvel NÃO achava nada — `TOZI_VISTA_API_KEY` faltava no `.env` de prod** (o n8n tinha; migração esqueceu). `Captain::Tools::BuscarImovelTool` lê `ENV['TOZI_VISTA_API_KEY']` (+ `TOZI_VISTA_BASE_URL` default `toz19328-rest.vistahost.com.br`, correto). Chave no vault `credenciais/tozi.md` como `VISTA_API_KEY` (nome diferente!). **Adicionada `TOZI_VISTA_API_KEY` no `.env`** + restart. Testado: acha apto cód 9532 (Aquarela). ⚠️ gotcha: o tool usa `TOZI_VISTA_*`, o vault/n8n usavam `VISTA_*`.
- ✅ **Geocoding (busca por localização) OK** — custom tool #4 "Buscar localização (geocoding)" tem a **chave do Google Maps EMBUTIDA na endpoint_url** (não env var). Testado ao vivo: `google_status=OK`, coordenadas certas. Proximidade ~3km alimenta o `buscar_imovel` (lat/lng bbox).
- ✅ **`buscar_imovel` confirmado E2E:** ferramenta built-in (`enterprise/lib/captain/tools/buscar_imovel_tool.rb`) consulta Vista, filtra Cidade/Status/Categoria/Bairro(like)/Dormitorios/Valor/lat-lng, retorna até 5 com URL `toziimoveis.com.br`. Clara também tem `enviar_fotos_imovel`, `salvar_info_lead`, `programar_followup`. Custom tool #3 "Buscar imóveis no Vista" está `enabled=false` (a built-in substitui).
- ⚠️ **Reopen-on-incoming:** ao esvaziar+force-resolve a 2159 via `update_columns`, a conversa NÃO reabriu sozinha no incoming (hook não dispara em `resolved`). Disparei `ResponseBuilderJob.perform_now` manual + abri a conversa. Provável artefato do force-resolve; conferir se em prod normal (resolve via flow) o incoming reabre + Captain responde a cliente que retorna.

**Go-live (quando validar):** remover a whitelist `only_contact_phones`. Antes disso, decidir as **57 conversas open+pending SEM resposta humana** (as 329 com resposta humana já são protegidas por `skip_after_human_response`): travar as 57 com `atendimento_humano=true` (script) OU deixar a Clara resgatá-las. 0 conversas com trava manual hoje.

### [2026-06-01] 🟢 Knowledge da Clara reorganizada em prod (FAQ→Q&A nativa, modo hybrid)

**Contexto:** Paulo apontou que o FAQ devia ser Q&A nativa (não doc) e o Playbook "parecia duplicado". Auditoria + verificação adversarial (workflow 3 frentes) confirmou: prod (Account 6, Clara #7) estava `knowledge_mode=chunks` com **0 Q&A nativas**; FAQ vivia como documento chunkado (13 chunks) duplicando ~factualmente o Playbook (19 chunks). O "playbook duplicado" é na **PAULAO** (2 docs "Playbook de Vendas Tozi" na aba Documents) — em prod só há 1 cópia. PAULAO tem as Q&A nativas corretas (aba FAQs, Approved) = `FAQ-TOZI.md` verbatim; nunca foram migradas pra prod.

**Feito em prod (Account 6):**
- ✅ **40 Q&A nativas criadas** (`Captain::AssistantResponse`, standalone `documentable=nil`, status approved, **40/40 com embedding**) — extraídas do `FAQ-TOZI.md` (16 institucional + 17 observada + 7 objeções; dropado 1 dup de FGTS). Script: `aws_create_faq.rb`.
- ✅ **knowledge_mode `chunks`→`hybrid`** (liga faq_lookup + mantém search_knowledge). Retrieval testado com 6 perguntas reais → todas casaram na Q&A certa (dist 0.24–0.47).
- ✅ **Documento FAQ (doc#2) DELETADO** (13 chunks foram em cascata; 0 responses atreladas — as 40 Q&A são standalone, intactas). Backup: `clara_knowledge_report.txt` (local) + `/tmp/faq_doc_backup_2.md` (AWS).
- **Estado final:** 1 doc (Playbook, 19 chunks) + 40 Q&A. Zero duplicação de fatos.
- **Playbook prod = fonte canônica** `PLAYBOOK-VENDAS-TOZI.md` (28/05/2026) verbatim — atualizado.

**UI deployada em prod (commit `444e6afa4`, restart web):** aba Knowledge→FAQs agora tem **editar** (inline) + **excluir** (confirmação inline) nas Q&A — backend já tinha o CRUD (`resources :assistant_responses`); faltava só o front (botões + override do `update` no `api/captain/response.js` p/ envolver no wrapper `assistant_response`). Mesmo restart serviu o fix do scroll do Settings.vue. (PAULAO só vê quando recompilar na rede da empresa.)

**Pendente:** limpeza PAULAO (Paulo, via UI: apagar 1 Playbook dup + doc FAQ). Opcional não-bloqueante: enxugar seções factuais 1/3/4 do Playbook prod.

### [2026-06-01] Disparo em massa Tozi — audiência + templates de lançamento

- **Fase A (ingestão) FEITA:** `PROPRIETARIOS DE LOCAÇÃO TOZI.xlsx` (1.614 donos, Nome+Tel sem DDI) cruzado com lista negra `TODOS CORRETORES DE SINOP.csv` (1.177, com DDI). Normalização canônica = **DDD + últimos 8 dígitos** (colapsa DDI + 9º dígito). Resultado v2 (recuperação aplicada): **1.526 leads limpos** (`Downloads/tozi_audiencia_limpa.csv`), 22 corretores cortados, **+12 recuperados** (trunk-0 e mobile 9-díg sem DDD → +66), 24 pra revisão manual (`tozi_revisao_manual.csv` — quase todos "9 duplicado/dígito a mais"), 43 dups. Script `Temp/ingestao_tozi_v2.py`. Verificado: 0 corretor vazou, 0 dup, encoding ok, recuperados presentes.
- **Fase B FEITA:** Custom role **"Corretor" #1** (`conversation_participating_manage`) criada. Configurados na Account 6 + membros da inbox 91: Marcus #128, Kettlen #126 (rebaixado admin→agent), Lucas #127 (rebaixado admin→agent), Bruno #131 — todos **agent + role Corretor** (veem só o atribuído). Guilherme #125 = **administrator** (vê tudo + recebe lead na fila). **Isolamento verificado ao vivo:** corretor vê 0 (só o seu), Guilherme vê 11.216 (tudo). Mecanismo: `Enterprise::Conversations::PermissionFilterService` (participating → `accessible_conversations.assigned_to(user)`; admin bypassa). Senhas recebidas no chat NÃO salvas (contas já existiam).
- **Fase C (orquestrador) A FAZER** — bloqueada por: templates `tozi_lancamento_*` aprovados (PENDING Meta) + tier WABA (~1.600/dia). Build `Spx::Tozi::DisparoEmMassa`: round-robin pros 5 + ScheduledMessages c/ HSM personalizado espalhado em 2h. Testar lote 5-10 antes do real.
- **Templates de disparo recriados com nomes NOVOS `tozi_lancamento_{interagir,qualifica,curiosidade}`** (MARKETING, pt_BR, **2 botões positivos** + "Agendar horário", texto do Guilherme = lançamento apto 3 suítes). **PENDING** na Meta. Audiência = os proprietários (donos/investidores).
- ⚠️ **2 gotchas Meta HSM:** (1) ao DELETAR um template, o **nome+idioma fica travado ~4 semanas** (`error_subcode 2388023`) → recriar exige nome diferente (por isso `tozi_disparo_*` virou `tozi_lancamento_*`). (2) **corpo NÃO pode começar/terminar com variável** (`2388299`) → precisa texto antes do `{{1}}` (usar "Oi {{1}}, ...").
- **Plano disparo (Fase B/C):** Custom Role "Corretor" (`conversation_participating` = só vê o que é atribuído a ele) — **NÃO precisa de 5 times**, basta 5 contas + role + atribuição round-robin. Orquestrador `Spx::Tozi::DisparoEmMassa` sobre `ScheduledMessages` (cria conversa + atribui round-robin + HSM personalizado espalhado em 2h). Pré-req: 5 contas de corretor (Paulo cria), tier WABA p/ ~1.600/dia, recuperação dos 10 tels.

### [2026-06-01] ⚠️ Gotcha: token da WABA Tozi cria templates mas NÃO deleta

`Whatsapp::TemplateManagementService#delete` (e o botão excluir da nova UI de templates) falham com `#100 Need permission on either WhatsApp Business Account or owner/shared business`. O `api_key` do provider_config da inbox 91 cria/envia mas não tem management/delete. **Pra deletar HSM:** WhatsApp Manager (Paulo, admin). Impacto: os 3 `tozi_disparo_*` já estão **APPROVED com 2 botões**; pra trocar p/ botão único (regra: só positivo), Paulo apaga no Manager → eu recrio com 1 botão.

### [2026-05-29] 🟢 Bloco 3+4 + branch paulao DEPLOYADO em produção AWS (Account 6)

**Status:** Branch paulao (19 commits) MERGEADO em `producao` (PR #19, merge `cc4536209`) e DEPLOYADO na VM Tozi AWS (`3.82.215.109`, Account 6). App **live e saudável** (HTTP 200 local+público, web/worker/target active, bundle novo `BaY3jm5l` servido). `zeitwerk:check` "All is good!" na AWS e na PAULAO.

**Implementado nesta sessão (Bloco 3+4):**
- **Bloco 3 — state machine do funil:** `Spx::Tozi::FunnelAutomationListener` (Wisper/AsyncDispatcher, rescue-wrapped, no-op p/ contas sem o funil) + `FunnelPlacementService.move/current_type/prevenda_funnel`. Transições: incoming→em_conversa (+cancel cadência); handoff humano→qualificado; programar_followup→em_silencio; followup MAX→frio; salvar_info_lead status→qualificado/frio. Hooks em `enterprise/lib/captain/tools/{programar_followup,salvar_info_lead}_tool.rb` + `followup_job.rb`.
- **Bloco 4 — cadência HSM fora-da-janela 24h:** `ScheduledMessages` aceita `template_params` (coluna jsonb + create/send service; o `MessageBuilder` já fazia a ponte→`SendOnWhatsappService`). `Spx::Tozi::ReactivationCadenceService` agenda HSM (1d/3d/7d), só Cloud API, idempotente, cancel-on-reply. **Dentro da janela = follow-up do agente (já existia); fora = HSM determinístico.** Estágio do funil arbitra.
- **Fixes:** CGI.escape no template service; migration de chunks `disable_ddl_transaction!`+`if_not_exists`; rake `create_templates` idempotente (list-then-skip) + nomes v2.
- Review adversarial (4 reviewers) + 6 fixes (HIGH: handoff não cancelava cadência; MEDIUM: listener sem rescue derrubava event chain global).

**Deploy AWS — GOTCHAS (críticos pra próxima vez):**
- **🔴 LANDMINE migration:** `20260330120000_add_foreign_key_constraints` é **DESTRUTIVA** (`DELETE` de órfãos em conversations/messages/scheduled_messages/etc.) e está `down` há 6+ dias **DE PROPÓSITO**. **NUNCA rodar `db:migrate` puro na AWS** — dispararia ela = perda de dados. Aplicar SEMPRE alvo: `db:migrate:up VERSION=<ts>`.
- **Transporte (não-git):** tar-pipe de `git archive origin/producao` → AWS. **`tar` extrai como ROOT** (`--owner` é opção de criação, ignorada na extração; sem `--no-same-owner` usa uid do archive=0) → `EACCES` no boot (`public/version.json`). **Fix: `sudo chown -R chatwoot:chatwoot` exceto storage/node_modules.** Alternativa melhor: extrair via `sudo -u chatwoot tar`. Também `git archive` do Windows traz CRLF (Ruby tolera; limpei `bin/*`).
- pgvector **0.8.2** → HNSW direto (fix H1 é só rede de segurança). Precompile com `NODE_OPTIONS=--max-old-space-size=4096`.
- `rake spx:tozi:setup_funnel[6,91]` → **funil "Pré-Venda Tozi" id=41** (stages 127-133). Backfill: 0 leads (hook Meta nunca rodou em prod).

**Re-apply em prod (FEITO 29/05):**
- ✅ **Prompt da Júlia** aplicado no Scenario Vendas **#5** (Clara #7): 4458→6274 chars (da proposta `julia-vendas-PROPOSTA.md`). Backup do antigo em `/tmp/julia_vendas_5_backup.txt` na AWS.
- ✅ **Knowledge** anexada à Clara #7 (knowledge_mode `faq`→`chunks`): doc#1 Playbook (19 chunks) + doc#2 FAQ (13 chunks) = **32 chunks, todos com embedding**. RAG funcionando.

**Estado de ativação (VERIFICADO em prod 31/05 — read-only):**
- 🟢 **Clara DESLIGADA (seguro): não conectada a nenhuma inbox.** `inbox91.captain_assistant=nil`, `clara.inboxes=[]`, `inbox91.captain_active?=false`. Não responde nada. Inbox 91 é tocada por **humanos** (469 msgs/3d, sender=User). Prompt+knowledge estão staged numa assistant não-plugada. **O interruptor real de ativação = conectar a Clara à inbox 91** (na UI: Agents → Inboxes, ou via API). ⚠️ Inbox 91 é a linha humana ao vivo — configurar router (whitelist/skip)/trava-humana/horário ANTES de conectar, senão a Clara atropela os atendentes.
- ✅ **Backend já pronto:** `captain_integration_v2=true`; chaves LLM setadas (InstallationConfig global `CAPTAIN_OPEN_AI_API_KEY`+`CAPTAIN_ANTHROPIC_API_KEY` + hook per-conta `openai` #4); Clara config (prompt Vendas #5=6274 + 32 chunks); **4 templates HSM APROVADOS** no WABA (abertura/followup/reativacao/horario_combinado); inbox 91 Cloud API com `api_key` SET.
- ⚠️ A UI "Agentes IA não habilitado" é enganosa (gotcha "chave em 2 lugares": UI checa hook per-conta, runner v2 usa InstallationConfig global). `CAPTAIN_OPEN_AI_MODEL` vazio→usa default. Diag sugeriu Agents SDK não-configurado no runtime → **restart garante** ao ativar (initializer `ai_agents.rb` lê chaves no boot).

**Falta (próxima sessão) — depois de ativar o agente:**
- 🔴 **Hook Meta Lead Ads em prod BLOQUEADO por gap de código.** `create_initial_message` (`app/services/meta/lead_ads/create_conversation_service.rb:129`) manda **texto livre**. Na inbox 91 (Cloud API), a 1ª msg a um lead de formulário (sem sessão WhatsApp aberta) é **bloqueada pela Meta** — fora da janela 24h só HSM passa. **Construir: 1ª-mensagem-como-HSM (`tozi_lead_abertura` via `template_params`) quando inbox.whatsapp?**. Sem isso, ativar o hook = leads entram no funil mas não recebem abertura (morrem). Em WAHA (PAULAO) funciona porque texto livre passa.
  - Meta-side (Paulo): switch do callback do app Meta pra `https://tozi.chatspx.app/webhooks/meta_lead_ads` (hoje aponta pra PAULAO) + confirmar aprovação do template `tozi_lead_abertura` no WABA.
- **Teste E2E** em prod (depende do hook OU teste manual da state machine/Júlia numa conversa controlada).
- Reconciliar corpos exatos dos templates v2 com o WABA (rake tem corpos-fonte; conferir via `svc.list`).
- Tuning de produto: cadência até 4 cutucadas in-window + 3 HSM; `agendado`/`aguardando_1a` sem trigger automático.

**Acesso AWS:** `ssh -i Downloads/handoff-tozi/simplex.linux.pem ubuntu@3.82.215.109` · RVM · `sudo -u chatwoot bash -lc "cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec ..."`.

### [2026-05-29] Vendas Tozi — Júlia repaginada + templates HSM + knowledge

**Base:** análise de 400+ áudios de atendimentos reais (corretor Henrique, alta conversão) em `C:/Users/paulo/Workspaces/tozi/analise-atendimentos/` (ANALISE-COMPORTAMENTAL.md, PLAYBOOK-VENDAS-TOZI.md, FAQ-TOZI.md, julia-vendas-PROPOSTA.md). Método: consultivo, tom "de Sinop", descobre a pessoa antes dos números (direção do gerente Guilherme: "não quero SDR que pergunta 'qual sua renda bruta'").

**Feito (PAULAO + WABA prod):**
1. ✅ **Prompt da Júlia (Scenario Vendas #1, account 1)** atualizado da proposta: 4458→6273 chars, agora com consciência de nicho (5 nichos), qualificação humanizada, represamento de lançamentos, handoff por nicho, consulta à knowledge. Backup: `/tmp/julia_backup_1780092115.txt` na VM PAULAO. **A proposta NÃO estava aplicada antes — só era documento.**
2. ✅ **Knowledge anexada à Clara** (assistant 1, knowledge_mode=chunks): doc#3 Playbook (19 chunks) + doc#4 FAQ (13 chunks), embeddings OK. Júlia consulta via search_documentation (RAG).
3. ✅ **4 templates HSM submetidos** no WABA Tozi (905788818829319) — PENDING aprovação Meta. IDs em `Obsidian/credenciais/tozi.md`.

**Acesso produção descoberto:** VM AWS `3.82.215.109` (tozi.chatspx.app), chave `Downloads/handoff-tozi/simplex.linux.pem`, Account 6. **Não é git** (deploy via script). Detalhes em `credenciais/tozi.md`.

**Falta:**
- Aplicar o mesmo (prompt Júlia + knowledge) em **produção AWS Account 6** quando subir — lá o Scenario Vendas é #5, assistant Clara #7, ainda com prompt antigo (4458).
- Aprovar/ajustar templates com o time (Paulo confirmando).
- Subir o código da branch paulao pra AWS (processo não-git a definir).
- Bloco 3+4 da cadência (state machine + ScheduledMessages) — ainda pendente.


### [2026-05-27] Meta Lead Ads → Clara (Tozi) — 🟢 EM PRODUÇÃO, aguardando lead orgânico

**Status:** Pipeline completo funcionando E2E. App em modo Live no Meta. Subscription ativa. Hook configurado. Testado via Lead Ads Testing Tool — webhook real chegou no SPX, conversa criada (id=146). Aguarda primeiro lead orgânico real (de campanha rodando) pra fechar ciclo com WAHA+Clara.

**Configuração final (27/05):**
- App Meta: **SPX Lead Ads Tozi** id=`1658426868710322`, criado dentro do BM Tozi, modo **Ao Vivo**
- Page Tozi: `539594042748152`, subscribed em field `leadgen` ✅
- Lead Access Manager: SPX Lead Ads Tozi listado como CRM ✅
- SU Token: nunca expira, salvo em `Obsidian/credenciais/tozi.md` seção "Meta Lead Ads"
- App Secret: `4c27cd1eb604a196f6ed1d74c05abacf` (vault)
- Verify Token: `228d3c9f0065ab7fa859255dce9b24795a60ff0bbd9988f2` (vault)
- Hook no SPX (Account 1): id=3, `skip_initial_message=true` (modo teste — não dispara 1ª msg ao lead até validar com lead real)
- Inbox alvo: 1 (WAHA Tozi, paulo.chatspx.app)
- Último commit: `005661347` (fix substring match + dummy filter na extração de campos)

**Validação E2E (27/05):**
- ✅ GET challenge respondido (Meta verificou webhook)
- ✅ POST de Meta IP real (`2a03:2880:2ff:4d::`) chegou em 13:23
- ✅ Job processou em 611ms, criou Conversation 146 (sem phone — form de teste tinha dummy data)
- ✅ Conversations criadas: 144, 145, 146 (todas testes, podem ser deletadas)

**Bugs identificados e corrigidos hoje:**
1. `Lead has no phone_number` raise → agora aceita lead sem phone (cria conv mesmo assim, não envia 1ª msg) — commit `09958905a`
2. Form com nomes custom PT-BR (`qual_seu_telefone?`) não casavam com lista exata de chaves → substring match + normalização de acentos/caracteres especiais — commit `005661347`
3. Test Tool injeta `<test lead: dummy data>` como valor → agora filtra via TEST_DUMMY_REGEX

**Bloqueios resolvidos hoje:**
- "App is not installed by any of the admins" → resolvido adicionando app ao Lead Access Manager
- "App em desenvolvimento, leads reais não disparam webhook" → resolvido ativando modo Live (URL política privacidade + categoria já configurados)
- Webhook ficava Pending no Tool → resolvido com DELETE+POST subscribed_apps (reset)

**Pesquisa-base:** [`Obsidian/pesquisas/meta-lead-ads-webhook-api.md`](C:/Users/paulo/Workspaces/Obsidian/pesquisas/meta-lead-ads-webhook-api.md)

**Antes do primeiro lead orgânico responder:**
- ⚠ Remover/ampliar whitelist `only_contact_phones` da Clara (hoje só responde +5566996247866)
- ⚠ Quando confiante, desligar flag `skip_initial_message` no hook (Settings → Integrations → Meta Lead Ads → Editar)

### [2026-05-27] Templates HSM WhatsApp via API do SPX — 🟢 mecanismo pronto, falta criar os templates Tozi

**Objetivo:** criar/submeter message templates (HSM) pra aprovação Meta sem abrir WhatsApp Manager — tudo via API do SPX. Base pra cadência em produção (Cloud API).

**Implementado (commits `de4014dd2` + `2991b61e7`):**
- `Whatsapp::TemplateManagementService` — generaliza `CsatTemplateService`. create/list/status/delete via Graph API v22.0. Aceita MARKETING/UTILITY/AUTHENTICATION + components livres. Usa `provider_config` business_account_id + api_key. Normaliza nome (lowercase+underscore).
- `Api::V1::Accounts::InboxMessageTemplatesController` — index/create/destroy scoped por inbox. Valida Cloud API (WAHA rejeitado). Rota: `resources :message_templates` dentro de inboxes.
- `rake spx:tozi:create_templates[account_id,inbox_id]` — cria os 4 templates da cadência: tozi_lead_inicial (MKT), tozi_lead_followup_dia (MKT), tozi_lead_reativacao (MKT), tozi_followup_horario_combinado (UTILITY).

**Status sync de aprovação:** já existe `Channel::Whatsapp#sync_templates` + `templates_sync_job`.

**Falta:** rodar `create_templates` numa inbox Cloud API. PAULAO é WAHA (sem WABA). Prod inbox 91 (número fixo Tozi Cloud API) serve. Precisa WABA id + api_key do provider_config da inbox 91, OU rodar a rake em prod.

### [2026-05-27] Kanban de Pré-Venda Tozi + Cadência de Follow-up — 🟡 EM CONSTRUÇÃO

**Descoberta chave:** o fork chatspx JÁ TEM sistema Kanban completo e robusto — não precisa construir. Componentes existentes a reusar:
- `Funnel` / `FunnelStage` / `FunnelItem` (models) — Kanban com colunas/cards/drag-and-drop
- `KanbanBoard.vue` + `ListView` + `CalendarView` (3 visualizações prontas em `routes/dashboard/kanban/`)
- `FunnelStage.automation_type` — move card automático (hoje só open/resolved)
- **`ScheduledMessage` + `ScheduledMessages::SendJob`/`CreateService`** — base PRONTA da cadência de follow-up (envio agendado, status pending/sent/failed/cancelled)
- `Kanban::FunnelItemsBackfillService`, `MoveConversationToAutomatedStageService`

**Diagramas de design (v3):** `docs/tozi-followup-{kanban,flow}.excalidraw` + `.png`. Renderer offline: `docs/render_excalidraw_offline.py` (PIL, sem CDN — porque esm.sh está bloqueado no ambiente). Cadência definida: A (frio, 2h/24h/3d, Marketing), B (silêncio, trigger=pergunta pendente, 15min/1h/6h/24h, Service→Marketing), AGENDADO só com horário definido, 24/7 (sem horário comercial), QUALIFICADO = saída.

**Implementado hoje (PAULAO, Account 1, Inbox 1):**
- Bloco 1 ✅ — `rake spx:tozi:setup_funnel[1,1]` cria funil "Pré-Venda Tozi" (id=6) com 7 stages (automation_type: novo_lead, aguardando_1a, em_conversa, em_silencio, agendado, qualificado, frio). Idempotente, parametrizável pra prod (6,91).
- Bloco 2 ✅ — `Spx::Tozi::FunnelPlacementService` + hook no `CreateConversationService` → lead Meta entra em "Novo Lead". `rake spx:tozi:backfill_funnel[1]` colocou 45 leads existentes.

**Falta (próxima sessão):**
- Bloco 3 — `Spx::Tozi::FunnelAutomationService` (state machine): move cards por evento (incoming→em_conversa, pergunta+15min→em_silencio, cap→frio, handoff→qualificado). Hook em message_created.
- Bloco 4 — cadência via ScheduledMessages: cria mensagens agendadas (A/B) quando lead em espera, cancela pending quando responde. Reusa SendJob existente.

**Produção:** trabalho feito no PAULAO (WAHA). Em prod (Account 6, Inbox 91 = número fixo Tozi com Cloud API oficial), cadência usa templates HSM (janela 24h + categorias Marketing/Utility/Service valem). ScheduledMessage envia pelo canal da inbox → mesmo código, transparente.

### [2026-05-25] Meta Lead Ads — histórico de implementação
- **Objetivo:** webhook Meta Lead Ads → cria conversa na Inbox 1 (WAHA Tozi) → Clara assume e inicia atendimento automaticamente
- **Acesso confirmado:** Paulo tem app **Business MW (Midwest)** no Meta for Developers; página Tozi compartilhada via Lead Access; MCP Meta Marketing API já configurado (separado, não conflita)
- **Caminho escolhido:** UI manual no SPX (admin cola tokens) + webhook público. Caminho longo (Tech Provider OAuth tipo ManyChat) corre em paralelo em outra sessão.
- **Pesquisa-base:** [`Obsidian/pesquisas/meta-lead-ads-webhook-api.md`](C:/Users/paulo/Workspaces/Obsidian/pesquisas/meta-lead-ads-webhook-api.md)

**Decisões técnicas (cravadas):**
- Reusa `Integrations::Hook` (não nova tabela) — `app_id='meta_lead_ads'`, settings JSONB
- System User Token (não expira) é preferível ao Page Access Token
- Lookup por `page_id` do payload (`entry[0].id`), não slug na URL
- Verify token por hook (não global) — flexível multi-conta
- 1ª msg texto livre via WAHA por enquanto; campo `initial_message_template` no schema já prevê HSM quando migrar pra Cloud API
- OSS layer (não Enterprise overlay) — move depois se virar paga

**Estrutura a implementar:**
```
app/controllers/webhooks/meta_lead_ads_controller.rb   # GET verify + POST lead
app/services/meta/lead_ads/
  signature_verifier.rb        # X-Hub-Signature-256
  fetch_lead_service.rb        # Graph API GET leadgen_id
  create_conversation_service.rb # Contact + Conv + 1ª Message
app/javascript/dashboard/routes/dashboard/settings/integrations/MetaLeadAds.vue
config/routes.rb               # match /webhooks/meta_lead_ads via [:get, :post]
```

**Fluxo end-to-end:**
1. Lead preenche form Lead Ads (FB/IG)
2. Meta POST → `/webhooks/meta_lead_ads` → SignatureVerifier valida HMAC
3. Lookup `Integrations::Hook` por `entry[0].id` (page_id)
4. FetchLeadService busca leadgen → phone, nome, campos custom
5. CreateConversationService: normaliza phone (BR), Contact find_or_create, Conversation na Inbox alvo, 1ª Message com template renderizado
6. `message_created` callback → Captain → Clara assume

**Backend implementado (25/05/2026):**
- `config/integration/apps.yml` — entrada `meta_lead_ads` com `settings_form_schema` + `settings_json_schema` (hook_type=account, allow_multiple_hooks=true)
- `config/locales/en.yml` + `pt_BR.yml` — i18n da integração
- `config/routes.rb` — `get/post /webhooks/meta_lead_ads`
- `app/controllers/webhooks/meta_lead_ads_controller.rb` — GET (verify challenge) + POST (HMAC + enqueue job)
- `app/services/meta/lead_ads/`:
  - `signature_verifier.rb` — HMAC-SHA256 contra `app_secret` de cada hook ativo
  - `token_verifier.rb` — challenge verify_token
  - `hook_finder.rb` — lookup por page_id
  - `fetch_lead_service.rb` — Graph API v22.0 com System User Token, parse de field_data (cobre full_name/nome/phone/telefone/email/cidade)
  - `create_conversation_service.rb` — Contact via `ContactInboxWithContactBuilder` + Conversation em pending/open + 1ª Message outgoing renderizada via Liquid
- `app/jobs/webhooks/meta_lead_ads_job.rb` — processa entries.changes do payload

**Callback URL exposta** (cole no Meta Developers):
- Prod Tozi: `https://chat.simplexsolucoes.com.br/webhooks/meta_lead_ads`
- VM PAULAO: `https://paulo.chatspx.app/webhooks/meta_lead_ads`

**O que falta:**
- Frontend UI customizada (Task #10) — opcional, UI genérica já funciona via `NewHook.vue` + apps.yml. Push pra próxima sessão se quiser refinar UX (mostrar Callback URL com copy-button, botão Testar Conexão).
- Teste E2E com lead real (Task #11) — exige Paulo configurar Meta Developers + form de teste

**Setup no Meta Developers (passo-a-passo):**
1. App Business MW → Webhooks → Add Subscription (object: `page`, field: `leadgen`)
2. Callback URL: a URL acima. Verify Token: gerar string aleatória (qualquer texto), colar mesmo valor no SPX e no Meta
3. App Settings → Basic → App Secret (copiar)
4. Business Settings → System Users → criar/usar System User → Generate New Token → app=Business MW, permissões: `leads_retrieval`, `pages_show_list`, `pages_manage_metadata`, `pages_read_engagement`. **Marcar "Never expires"**
5. Subscribe page ao app: `curl -X POST "https://graph.facebook.com/v22.0/{PAGE_ID}/subscribed_apps?subscribed_fields=leadgen&access_token={SYSTEM_USER_TOKEN}"`
6. No SPX: Settings → Integrations → Meta Lead Ads → Add → preencher 7 campos
7. Testar via Meta Lead Ads Testing Tool: `https://developers.facebook.com/tools/lead-ads-testing/`

**⚠️ Atenção (gotcha conhecido):** Clara hoje tem `behavior.router.only_contact_phones = ["+5566996247866"]` (whitelist do Paulo). Pra leads reais responderem, REMOVER essa whitelist via API/console antes do teste E2E, ou Clara ignora todos os leads novos. Ver `MEMORY.md → reference-captain-v2-gotchas`.

### [2026-05-19] Captain V2 — Clara/Tozi rodando em produção (paulao)
- **Status:** E2E validado, tools nativas implementadas, follow-up + handoff + IGNORAR funcionando
- **Inbox:** 1 (Channel::Api WAHA, Account 1, `paulo.chatspx.app`)
- **VM:** `192.168.8.100` (PAULAO, hostname interno `paulo` — NÃO confundir com SENTINELA do AWS)
- **Último commit branch `paulao`:** `5db646c98` (follow-up decidido por agente + trava humana)
- **Backlog técnico (resumo):** UI editar `only_contact_phones`/`skip_groups`, UI `captain_auto_resolve_mode`, camada `app/services/spx/tozi/`, bug divergência chave OpenAI (Account.hooks vs InstallationConfig), `feature_ai_assistant_v2` bigint overflow → detalhes em `MEMORY.md → project-clara-tozi-spx`

### [2026-05-25] Sistema de memória multi-sessão Claude Code
- **Objetivo:** resolver perda de contexto entre sessões (este arquivo é a Camada 1)
- **Camadas:**
  1. ✅ `.claude/STATE.md` versionado (este arquivo)
  2. ⏳ Hook `SessionEnd` que força atualização — pendente, próxima sessão
  3. ⏳ MCP Supermemory ou Mem0 (opcional, só se Camadas 1+2 não derem conta)
- **Pesquisa-base:** `Obsidian/pesquisas/claude-code-memoria-persistente-2026.md`

---

## ✅ Decisões recentes (rolling 30 dias)

- **[2026-05-27]** Criado app **SPX Lead Ads Tozi** (id `1658426868710322`) dentro do BM Tozi (não cross-BM via Business MW). Caminho cross-BM exigia Partnership e era overhead — app no BM dono da página é mais limpo.
- **[2026-05-27]** Implementada UI de editar hook (`EditHook.vue`) — não é mais limitação do Chatwoot core, fork nosso. Vale pra todas integrações declarativas.
- **[2026-05-27]** Adicionada flag `skip_initial_message` no hook pra modo teste sem enviar msg ao lead.
- **[2026-05-25]** Adotado modelo STATE.md + hook SessionEnd como solução pra perda de contexto multi-sessão. MCP de memória semântica (Supermemory/Mem0) fica como opcional.
- **[2026-05-19]** SPX institucional (SimplexIA) usa **Meta WhatsApp Cloud API direta** (Account 3, Inbox 89, `provider=whatsapp_cloud`) — NÃO WAHA. Corrige assumption anterior.
- **[2026-05-17]** Stack escolhida pra agente IA Tozi: **Captain V2 nativo + camada fina futura** em `app/services/spx/tozi/`. Descartado tozi-agent/ Python e AIOX (meta-framework dev, não runtime).

---

## ⏳ Aguardando externos

- **Lead orgânico real** de campanha Tozi rodando → vai disparar webhook automático e criar conversa (Clara não responderá enquanto flag `skip_initial_message=true` e whitelist `only_contact_phones` estiverem ativos).
- **Paulo:** quando quiser, ampliar `only_contact_phones` da Clara + desligar `skip_initial_message` no hook.
- **(Opcional, limpeza):** deletar conversas de teste 144, 145, 146 (mesmo lead replay, source=meta_lead_ads).

---

## 📋 Backlog técnico longo-prazo

Detalhes em [`MEMORY.md`](../../../.claude/projects/C--Users-paulo-Workspaces-chatspx/memory/project-clara-tozi-spx.md):
- UI `RouterConfig.vue` editar `only_contact_phones` e `skip_groups`
- UI `captain_auto_resolve_mode` (hoje só via console)
- Camada `app/services/spx/tozi/` (debounce/humanizer/media)
- Bug divergência chave OpenAI (Account.hooks vs InstallationConfig)
- `feature_ai_assistant_v2` bigint overflow (posição 250)
- Reativar Captain auto-resolve com mensagem PT

---

## Protocolo de uso

- **Início de sessão:** Claude lê este arquivo automaticamente (via `@` no CLAUDE.md)
- **Durante sessão:** ao tomar decisão importante ou abrir frente nova, Claude adiciona aqui
- **Fim de sessão:** Claude atualiza "Em andamento" + "Aguardando externos" antes de encerrar
- **Mensal:** mover decisões >30 dias pro vault (`clientes/tozi-conversation-log.md`)
