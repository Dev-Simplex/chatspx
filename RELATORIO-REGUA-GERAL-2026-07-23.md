# Régua Geral — estado de tudo pós-conciliação (23/07/2026, noite)

> **Para:** Paulo · Nicolas · Walisson — revisão conjunta do estado de cada frente.
> **Contexto:** semana intensa de 3 mãos — missões do Paulo (eval, áudio, encerramento, front,
> 9º dígito, knowledge), features do Nicolas (sino, kanban, gate de atendimento, chat interno)
> e a **conciliação final do Walisson** (back-merge homolog→prod `1c01b357b` + reset das VMs).
> A conciliação apagou do box da Tozi a cadeia do Eval que só existia lá (~9 commits);
> **recuperada do backup e consolidada no GitHub no mesmo dia** (`2bd596be8`) — detalhe na
> seção Incidentes. Retrato verificado na noite de 23/07; SHAs podem andar.

## Topologia (23/07 ~21h)

| Onde | SHA | Leitura |
|---|---|---|
| GitHub `producao` | `2bd596be8` | superset: conciliação + cadeia eval consolidada |
| GitHub `homologacao` | `55d42db54` | falta back-merge da prod (cadeia eval) · tem 1 commit a promover (harmonização botões) |
| VM TOZI | `2bd596be8` | ✅ alinhada com o GitHub — **primeira vez sem drift** |
| VM CATATAU / SENTINELA | `dc3b5d63f` | pegam a cadeia eval no próximo deploy normal (sem pressa — eval é só conta 6) |
| **VM PRODUCAO** | **`805f0fd6cc`** | 🔴 **SHA off-git — não existe no GitHub. Perguntar ao Walisson** |
| VM FABRICA | `c8f3dc803` | atrás; greenfield, decisão à parte |
| VM HOMOLOGACAO (.232) | `55d42db54` | em dia; migrations zeradas (até a dívida campaign-recipients foi aplicada) |

---

## 🟢 LIVE e verificado em produção

| Frente | Autor | Onde | Prova |
|---|---|---|---|
| Eval 2.0 completo (F1 episódios · F2 tool-trace+gate · F2.0 representatividade · F4 painel · F4.1 drill-down · spec-grounded · juiz 2 camadas · watchdog · gate foto-fantasma) | Paulo | conta 6 | recuperado + verificado peça a peça 23/07; consolidado no git |
| Fix clobber atômico `92da66936` (protege eval_unit/cache/handoff) | Paulo | conta 6 | jsonb_set ×2 no box; flags intactas |
| Guarda de procedência (template humano 1:1 → humano, não IA) | Paulo | contas 3 **e 6** | ligada 23/07 (`ai_triage_respects_human_template=true`); E2E 7/7 + rspec 49/0 na c3 |
| Anti-fonte 9º dígito (builder reusa ficha) + reconciliador incoming | Paulo | todas (código) | sempre-on; fecha a fábrica de fichas duplicadas (333 pares na c6) |
| Áudio da IA (ElevenLabs, voice note) | Paulo | c3 Clara #3 · **c6 piloto Clara #7 (Marianne)** | pipeline provado (OGG/opus 48kHz); ffmpeg nas 2 VMs; demais 6 agentes = 1 comando |
| Front UX 7 itens + harmonização Atribuir↔Devolver | Paulo | `.232` | precompile ✓ + deploy; aguarda olho do Paulo |
| Migração knowledge FASE 2 (31 Q&A + 2 reescritas · 6 prompts limpos · regra de processo dura) | Paulo | conta 6 | probes E2E PASS por agente; rollback `.bak` + `ai_rollback` |
| Anti-bot URA (skip_labels revivido `3f504ec42` + rule #67 + molde agnóstico) | Paulo | conta 6 + molde | provas router/probe/humano 22/07 |
| Handoff sensível (gatilho duro Bruna #14/Júlia #13) | Paulo | conta 6 | probe cenário 14363 PASS |
| Busca por código (`track_codigos`) + links (`track_urls`) | Paulo | conta 6 | no git desde 15-16/07; incidente encerrado |
| Meta Leads → Sofia (roteamento, erros Meta, RMKT catálogo com foto, holerite PDF/foto) | Paulo | conta 6 | live desde 14-17/07 |
| Sino/notificações (VisibilityService) · kanban (funil Geral, assumir-p/-ver) · gate de atendimento D1 · chat interno | Nicolas | via merges `c03245191`/`1c01b357b` | integrados na conciliação — **estado de teste = com o Nicolas** |
| Instagram DM + IA Lia (piloto Midwest) | Paulo | conta 3 | E2E 20/07 |
| Keys OpenAI por propósito + juiz gpt-5.4/mini | Paulo | conta 6 | live 16/07 + custo cortado ~97% em 22/07 |

## 🟡 Deployado mas dormente / aguardando E2E

| Item | O que falta | Dono |
|---|---|---|
| **Encerramento (auto_closure)** | Ligado só na c3. **C6 desligado DE PROPÓSITO**: religa o cron de auto-resolve (incidente de junho) + risco de inundar a fila (milhares de paradas). Sequência: E2E c3 → actions por classe → ligar c6 | Paulo decide |
| E2E conta 3 | áudio (voice note à Clara) · front visual · fila de encerramento · aba (fix `/meta` já subiu) | Paulo |
| Conduta de áudio nos prompts ("só quando pedir") | aguarda Fase 2 da knowledge assentar (exclusividade de prompt) | Paulo |
| Réplica do áudio nos outros 6 agentes da c6 | 1 comando pós-validação do piloto Clara | Paulo → orquestrador |
| 🐛 Feature `conversation_required_attributes` não liga | posição no features.yml estoura bigint `feature_flags` → modal de motivo inoperante em QUALQUER conta; trocar gate (settings) ou alargar coluna | plataforma (backlog) |

## 🔴 Pendências de reconciliação (o que sobrou do pente-fino)

1. **VM PRODUCAO em `805f0fd6cc` (off-git)** — único ponto da frota fora da régua. → **Walisson** identifica e regulariza.
2. **WIP meta-leads não-commitado** (~100 linhas `create_conversation_service` + `fetch_lead_service`) vive só em `bkp/tozi-wip-vista-uncommitted-2026-07-23`. Se era feature ativa, está FORA do ar desde a conciliação. → **autor confirma** (Nicolas/Walisson?) → commit ou descarte.
3. **Back-merge `producao→homologacao`** (cadeia eval) + promover `55d42db54` (harmonização) pra prod no próximo ciclo. → orquestrador, trivial.
4. **Trio geral** pega a cadeia eval no próximo deploy normal · **Fábrica** reconciliar depois (código off-git do box ainda não veio pro repo).
5. **Branches zumbis** pra apagar quando assentar: `bkp/*` (pós item 2), `audio-ia-tmp`, `tmp/f1-eval`, `tmp/f20-eval`, `tmp/f4-eval`, `spx/fix-fotos-handoff{,-hml}`, `worktree-tozi-eval`, `spx/busca-fallback-ampliar`.

## ⏳ Prateleira (especificado, não iniciado)

F4.2 comentários de admin→juiz (annotation queue) · F3 outcomes/autoria · F5 golden set/pass^k · v2 delegação-com-brief (BACKLOG §IA extensão do humano) · dedup L1 dos 333 pares (write, só com OK) · **inbox 62 mal configurada** (Júlia/vendas numa inbox de prestação; proprietária 4 semanas no vácuo — revisão dedicada) · caso 8917 RMKT no vácuo (decisão a/b/c do Paulo) · rodízio locação (aguarda `resolve_team`) · pendências knowledge não-bloqueantes (Rafa D-10, Letícia D-09, renda MCMV reformulada pro Guilherme).

## Incidentes da semana (fechados, com lição)

- **Conciliação apagou a cadeia do Eval (23/07):** o débito "commits só no box" cobrou exatamente como previsto no plano de reconciliação. Backup do Walisson salvou; recuperação no mesmo dia. **Lição institucionalizada: código que roda TEM que estar no GitHub — deploy só por branch, nunca acumular commits em box.**
- **Custo do eval US$260/5d (22/07):** clobber do eval_unit pôs o cron a re-julgar blobs no gpt-5.4. Fixes: clobber morto + funil destravado + juiz 2 camadas → ~$0,5-2/dia.
- **eval_unit clobberada (17→21/07):** raiz do read-modify-write em custom_attributes; fix atômico agora protege todas as flags.

## Próximos 3 passos sugeridos (ordem)

1. **Walisson:** identificar/regularizar o `805f0fd6cc` da PRODUCAO + confirmar o WIP do meta-leads.
2. **Paulo:** E2E na conta 3 (30 min: áudio → front → fila) → destrava auto_closure e réplica de áudio na c6.
3. **Orquestrador:** back-merge prod→homolog + promover harmonização + limpar branches zumbis (meia sessão).
