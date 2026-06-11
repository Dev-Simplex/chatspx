# Decisões — IA SPX / Clara (consolidado em 2026-06-11)

> **Propósito:** uma lista única de TODAS as decisões pendentes extraídas da documentação
> (doc-mestre do mapeamento, roadmap das 7 ondas, tese do meta-agente, 21 relatórios por
> subsistema e plano de go-live), cada uma com contexto curto e recomendação, para a sessão
> de decisões Paulo × Claude. Bater uma a uma e marcar; o que for decidido vira fonte de
> verdade aqui (e migra pro STATE/vault no fechamento).
>
> **Como ler:** ✅ = já batida · 🔴 = a bater · ⚪ = pode esperar (não bloqueia go-live nem reconciliação).
> **REC** = minha recomendação.

---

## Já batidas (11/06)

- ✅ **D2 — Horário:** Clara responde 24/7 (behavior sem `outside_hours_action`; prompt qualifica fundo e promete retorno).
- ✅ **D3 — feature_memory/feature_faq:** desligar ambos no go-live (memória write-only + custo LLM + PII por resolve). *Aplicar no T7, junto da religada.*
- ✅ **D1 (parcial) — Replies de disparo:** Clara ATENDE os ~6.100 leads de disparo que responderem. Sub-definições no Grupo 2.
- ✅ **Branch de trabalho:** homologação (exige atualizá-la na reconciliação — está 114 commits atrás da linha consolidada).
- ✅ **Ambiente de teste:** número SimplexIA na Cloud API oficial como laboratório fiel de produção.

---

## Grupo 1 — Reconciliação & deploy (bloqueia todo o resto)

| # | Decisão | Contexto | REC |
|---|---|---|---|
| 1.1 🔴 | Autorizar `git push origin paulao` | 22 commits locais (incl. fix 403 de hoje) só no notebook | **Sim, hoje** — primeiro passo da reconciliação |
| 1.2 🔴 | Branch canônica: `producao` ou `rollout/release-*`? | `producao` == `rollout/release-20260605` desde 08/06 (frota alinhada) | **`producao` como canônica**; `rollout/release-*` vira tag de release |
| 1.3 🔴 | Processo oficial de deploy | AWS já é checkout git da rollout; hoje deploy via tar re-dropa patches | **Runbook git-pull**: `fetch → migrate:status (0 down) → checkout/pull → precompile → restart`. Nunca mais tar |
| 1.4 🔴 | Destino dos 10 PRs do redesign (workspace-v2) na homologação | Eles não existem na paulao nem na producao | **Rebase/merge da homologação sobre a canônica preservando os PRs** — homologação vira branch de integração |
| 1.5 🔴 | Sujeira não-commitada na AWS (frontend .vue/.js + patches de hoje) | Working tree sujo na rollout em prod | **Auditar diff → commitar o que é real → descartar ruído**, dentro da reconciliação |

## Grupo 2 — Go-live da Clara (D1 e companhia)

| # | Decisão | Contexto | REC |
|---|---|---|---|
| 2.1 🔴 | Reply de disparo: cenário certo? | Lead de disparo é PROPRIETÁRIO respondendo sobre o lançamento; Júlia foi desenhada pra quem procura imóvel (mas tem represamento de lançamento no prompt) | **Testar no piloto** uma conversa simulando reply de HSM ("tenho interesse") e validar que ela conduz como represamento; ajustar cenário se derrapar |
| 2.2 🔴 | Handoff em conversa que já tem dono (corretor do disparo) | HandoffTool hoje faz round-robin entre quem está online | **Manter o dono atual e só notificar** (não re-rotear); exige o ajuste do HandoffTool (4.4/F1.2) ou gate simples |
| 2.3 ✅* | Sem efeito retroativo | Clara só reage a mensagem nova; não varre as ~6.100 abertas nem o backlog do mutirão | Confirmado tecnicamente — *registrar como premissa* |
| 2.4 🔴 | Cadência da abertura | Whitelist → geral | **Piloto interno (Paulo+dev+Ederson) → 5–10 leads reais → geral**; cada etapa só avança com AssistantLog limpo |
| 2.5 🔴 | Auto-resolve do Captain | `captain_auto_resolve_mode='disabled'` desde o incidente | **Manter disabled no go-live**; revisitar depois com mensagem PT + gates |
| 2.6 ⚪ | Política do router_skip | Conversa pulada pela whitelist fica aberta esperando humano (pending está OFF na inbox 91 — limbo não recorre) | Aceitar durante o piloto curto; morre quando abrir geral. **Nunca ligar "status pendente" da inbox 91** |

## Grupo 3 — Orquestração & triagem

| # | Decisão | Contexto | REC |
|---|---|---|---|
| 3.1 🔴 | Ratificar: orquestração DENTRO do Captain | Doc-mestre recomenda (vs AgentBot externo); todo o investimento do fork está nas tools nativas | **Ratificar** |
| 3.2 🔴 | Destino da regra #53 ("iniciar zerado") | Zera assignee+team em TODO `conversation_opened` — desfaz atribuição do disparo, manual e da IA; mutuamente exclusiva com a triagem orquestrada | **Substituir e matar** na F1.4 (regra nova: devolver pra triagem SÓ órfãs reais); conviver até lá |
| 3.3 🔴 | Taxonomia `nicho:*`: label de conversa ou de contato? | Tool de label existente valida contra labels da conta; label de contato exigiria tool nova | **Conversa agora** (rápido); contato (perfil duradouro) na Onda 3 via custom_attributes |
| 3.4 ⚪ | Guardrails das agent tools | Tools rodam sem checagem de permissão | Validação na própria tool (inbox/time permitidos) — padrão pra toda tool nova |

## Grupo 4 — SLA & notificações (a falha das 432)

| # | Decisão | Contexto | REC |
|---|---|---|---|
| 4.1 🔴 | Ligar SLA nrt-only como vigia | Módulo Enterprise existe e roda no cron; "lead esperando > X" com notificação — era exatamente a falha das 432 | **Sim, logo após a reconciliação** (config, sem código) |
| 4.2 🔴 | Conversa única × AppliedSla terminal pós-resolve | Resolver mata o SLA pra sempre na conversa | **Snooze em vez de resolve** (recomendação do doc); re-arm como evolução |
| 4.3 ⚪ | Business hours no SLA | Avaliação ignora horário → alerta de madrugada | Aceitar 24/7 no começo; implementar respeito a horário se incomodar |
| 4.4 🔴 | Papel da secretária na triagem | Não existe "modo leitura"; quem vê, opera | Relatório recomenda **agent puro + membro da inbox 91 + FORA de qualquer time** (filtro de time esconde conversas sem team). Confirmar cadastro real antes |

## Grupo 5 — Cadência & disparos

| # | Decisão | Contexto | REC |
|---|---|---|---|
| 5.1 🔴 | Sender da cadência HSM | Hoje sai como 1º admin, não como o corretor dono | **Corretor atribuído** |
| 5.2 🔴 | Quiet hours pros HSM de cadência | Hoje manda a qualquer hora | **Sim** — janela 08h–20h Sinop |
| 5.3 ⚪ | Config da cadência: behavior JSONB vs model próprio | — | **JSONB agora**; model (`CadencePolicy`) na generalização (Onda 7) |
| 5.4 🔴 | Cancel-on-reply: gate por funil vs marcador na ScheduledMessage | Lead fora do funil não cancela cadência ao responder (buraco real) | **Marcador de origem na ScheduledMessage** + cancelar por incoming (F2.2) |
| 5.5 🔴 | Disparo/follow-up posicionam o lead no funil? | Hoje não entram (só backfill, indistintos) | **Sim** — `aguardando_1a` no disparo (F2.1) |
| 5.6 ⚪ | Agenda de disparo: Sidekiq ScheduledSet → entidade persistida | Estado do disparo vive em scripts + fila volátil | **Sim** — é o módulo de campanhas (F3) |
| 5.7 ⚪ | Gate de saúde do número no disparo | Nada impede continuar com número RED | **Sim** no F3 (pausa automática em YELLOW/RED + reação a 131026/130472) |
| 5.8 🔴 | 2ª leva inquilinos (segurada desde 08/06) | Exige recuperar `inq-mapa.jpeg` (candidato: attachment 411283) + header de imagem no FollowupHsmJob — OU texto zero-deploy | Decidir **quando** retomar; se for já, usar `tozi_followup_lanc` (texto, zero-deploy) |
| 5.9 ⚪ | Medir A/B qualificado (payoff nunca medido) | `tozi_venda_oportunidade` × `tozi_venda_lembrei` | **Medir já** — consulta read-only, eu rodo |

## Grupo 6 — Meta Lead Ads → prod

| # | Decisão | Contexto | REC |
|---|---|---|---|
| 6.1 🔴 | Os 3 bloqueadores antes do switch do callback | source_id com `+` (fábrica de duplicatas), 1ª msg texto-livre morre em Cloud API, sem idempotência por leadgen_id | **Corrigir os 3 primeiro** (1ª msg como HSM `tozi_lead_abertura`), só então apontar o callback pra prod |
| 6.2 ⚪ | Lead sem telefone | Hoje cria conversa sem 1ª msg | **Criar conversa + nota privada + atribuir à secretária** |
| 6.3 ⚪ | Atribuição do lead Meta | No create (listener) vs triagem da IA | **Triagem da IA** (F1.3) — mesma porta de todos os leads |
| 6.4 ⚪ | Assinar `message_template_status_update` no app Meta | Aprovação de template em tempo real vs sync de 3h | **Sim** (barato) |

## Grupo 7 — Plataforma & dados

| # | Decisão | Contexto | REC |
|---|---|---|---|
| 7.1 🔴 | Webhooks de conta at-most-once | Trigger engole StandardError; retry letra morta (fix de 1 linha) | **Fix na reconciliação** + idempotência no consumidor quando houver CRM espelhado |
| 7.2 ⚪ | `audit_logs` na Account 6 | Operação via console não deixa trilha | **Ligar** |
| 7.3 🔴 | PII nos traces (antes de ligar Langfuse/OTel) | `to_llm_text` expõe nome/telefone/notas sem máscara | **Definir retenção curta + acesso restrito** antes do quick win 1 |
| 7.4 🔴 | Kanban: backfill que polui o funil + filtro de label quebrado + custom role ignorada | Backfill despeja TUDO da inbox 91 em "Novo Lead" a cada GET | **Corrigir o backfill antes de usar o funil pra valer** (origem dos 868 "Novo Lead") |
| 7.5 ⚪ | `skip_agent_bot` NoMethodError latente | Coluna errada (`agent_bot_id` → `assignee_agent_bot_id`) | Fix pequeno na reconciliação |
| 7.6 ⚪ | Specs mínimos | Zero specs em 705 arquivos custom | 3 specs de alto valor (disparo, lead ads, cadência) na reconciliação/F5 |

## Grupo 8 — Estratégia (tese das 3 camadas + sandbox)

| # | Decisão | Contexto | REC |
|---|---|---|---|
| 8.1 🔴 | Ratificar a tese do triângulo de 3 camadas | Clara = responder (camada 1), worker de lead (camada 2), meta-agente (camada 3) | **Ratificar** — direciona Ondas 2–6 |
| 8.2 🔴 | Quick wins imediatos | Langfuse/OTel (config), playground (UI), golden set (curadoria) | **Executar junto com a montagem da sandbox SimplexIA** |
| 8.3 ⚪ | Governança do meta-agente | Autonomia gradual | **Human-in-the-loop total no início** (Paulo aprova cada mudança com diff + rollback) |
| 8.4 🔴 | Onde monta a sandbox SimplexIA (número Cloud API) | hmlchat (192.168.8.232) · VM PAULAO · SaaS chatspx.app | Decidir junto com a config do número — **REC: hmlchat** (espelho de homolog oficial, isola do dev) |
| 8.5 ⚪ | MA Financeiro (marco 🔴, ~1 mês atraso) | Destrava por `consultar_cadastro` Vista (Onda 5) | **Antecipar a investigação do endpoint Vista** (custo baixo: confirmar se a API expõe cadastro/boleto) em paralelo às Ondas 1–2 |

---

## Sequência pós-decisões (referência rápida)

1. **Reconciliação** (Grupo 1) → 2. **Sandbox SimplexIA + quick wins** (8.2/8.4) → 3. **Go-live Clara organizado** (Grupo 2, roteiro 13 testes na sandbox → piloto inbox 91 → geral) → 4. **Ondas 1+2+4.1 em paralelo** → 5. **Onda 5 (Vista fundo — pressão contratual MA/MB)** → Ondas 3, 6, 7.

> Executado hoje (11/06), fora deste doc: patches T1/T2/T3 em prod + restart (Bloco 1 do go-live), notificações dos corretores, times/higiene das 442, lista do mutirão (408), `audio_transcriptions=true`, fix 403 commitado na paulao (`e74b935b1`).
