---
titulo: Plano executável das 8 frentes — Tozi Imobiliária (ago/2026)
cliente: Tozi Imóveis (conta 6 prod / conta 3 hml)
status: PLANO
data: 2026-07-24
ai-generated: true
tags: [spx, tozi, plano, follow-up, encerramento, eval, rodizio, vista, campanhas, funil, instagram]
---

# Plano executável das frentes da Tozi (ago/2026)

> **Escopo deste documento:** pesquisa e planejamento — nenhum código ou produção foi tocado para
> produzi-lo. Base: `.claude/STATE.md` (23/07), `.claude/BACKLOG.md`, `AGENTS.md`,
> `RELATORIO-REGUA-GERAL-2026-07-23.md`, `docs/mapeamento-2026-06-10/*` (10/06 — cruzado com o
> STATE onde havia risco de estar desatualizado), `docs/ROADMAP-IA-COMPLETA.md`,
> `plano/encerramento-inteligente-design.md`, `docs/clientes/tozi/MOTOR-DISTRIBUICAO.md` e o vault
> Obsidian (`kg_query`) para o que não vive no repo (Vista/Loft, Instagram, funil de leads).
> **Convenção de local seguida:** este arquivo replica o padrão já usado em
> `docs/clientes/tozi/PLANO-GOLIVE-IA-2026-06-11.md` — planos de cliente ficam em
> `docs/clientes/tozi/PLANO-*.md`. Não há convenção divergente a reportar.
> **Unidade de esforço:** sessões de agente IA (Claude Code), não dias-homem — uma sessão de build
> cirúrgico costuma fechar 1 arquivo/serviço + specs; uma sessão de verificação roda E2E na conta 3
> antes de promover.

---

## Decisões pendentes do Paulo (resumo para escaneamento rápido)

| # | Decisão | Frente | Urgência |
|---|---|---|---|
| D1 | Actions por classe do encerramento (trivial auto-fecha? substantiva sempre vai pra fila?) + `max_dias` | 2 | Alta — trava go-live conta 6 |
| D2 | Onde chegam os alertas do Eval (nota/inbox de gestão, webhook, Copilot) | 3 | Média |
| D3 | Rodízio: só-online ou estrito, janela de continuidade, comercial=admin ou perfis distintos, reatribuição automática por SLA, cap de capacidade | 4 | Alta — trava F1 do motor |
| D4 | O que exatamente é o "app nativo do Walisson" (escopo, prazo, contrato de integração) — hoje sem registro em repo/vault | 5 | Alta — maior bloqueio de todo o plano |
| D5 | Rodízio de corretor no Vista deve usar o mesmo Motor de Distribuição (frente 4) ou continuar escolha manual no handoff? | 5 | Média |
| D6 | O que significa "áudios" em campanha (TTS embutido em disparo? Meta não aceita áudio em template HSM de marketing tipicamente — checar viabilidade) | 6 | Média |
| D7 | "Remarket com catálogo" = header de imagem (já existe) ou WhatsApp Product Catalog API (não existe)? | 6 | Média |
| D8 | Escopo do "analítico de leads": estender o Kanban existente, construir dashboard dedicado (padrão do painel de Eval), ou os dois? | 7 | Média |
| D9 | App Meta / Business Manager específico da Tozi para Instagram (hoje só há piloto configurado para Midwest, conta 3) | 8 | Alta — trava setup técnico |
| D10 | Sender da cadência HSM: admin da conta (atual) ou corretor dono do lead? | 1 | Baixa |

---

## 1. Cadências de follow-up (IA + disparos)

**Objetivo verificável:** todo lead que esfria recebe cutucada automática dentro da janela de 24h e,
fora dela, cadência HSM de 1/3/7 dias — e para de receber qualquer coisa no exato momento em que
responde, em qualquer canal de origem (orgânico ou disparo em massa).

**Estado atual (fonte: `docs/mapeamento-2026-06-10/scheduled-cadencia.md`, cruzado com
`.claude/STATE.md` linhas 114-115 e 82-85):**
- **In-window** (`ProgramarFollowupTool` + `Captain::Conversation::FollowupJob`): funcionando —
  máx. 4 cutucadas, quiet hours 21h-8h hardcoded `America/Cuiaba`, reset automático quando o lead
  responde.
- **Fora da janela** (`Spx::Tozi::ReactivationCadenceService`): 3 passos HSM fixos (1d/3d/7d),
  só Cloud API, idempotente, mas **sender é o primeiro admin da conta, não o corretor dono do lead**
  (D10) e **sem quiet hours/horário comercial** (dispara na hora exata do offset, mesmo às 22h).
- **Stack de fixes já testado em homologação mas não 100% promovido a produção** (`STATE.md` §Tozi —
  análise de conversas 11-12/07): follow-up viciado em `[IGNORAR]`, contagem de mídia no turno
  (commit `dfa76d799`) — parte já verificada em prod (`fbbac1763`), resto pendente de promoção
  governada.
- **Gap real, não fechado:** `Spx::Tozi::DisparoLeadJob` (motor de disparo em massa) **não coloca o
  lead no funil** → o cancel-on-reply do `FunnelAutomationListener` é gateado pelo estágio do funil
  → **lead de disparo que responde não cancela a cadência HSM pendente** (pode continuar recebendo
  1d/3d/7d mesmo depois de já ter respondido). Fonte: `scheduled-cadencia.md` §2.2 e §6 item 5.
- **v2 "Delegação com brief"** (humano manda template 1:1 e a IA dá sequência se ele estiver
  offline) está **registrada no BACKLOG, não iniciada** — depende da guarda de procedência v1, que
  **já está LIVE nas contas 3 e 6** desde 23/07 (`ai_triage_respects_human_template=true`,
  `.claude/STATE.md` linha 31 do quadro "LIVE").

**O que falta (com critério de pronto):**
1. **Fechar o cancel-on-reply para leads de disparo** — colocar `DisparoLeadJob` no funil (estágio
   `aguardando_1a` ao disparar) OU generalizar o cancelamento para qualquer incoming com
   `ScheduledMessage.pending` marcada por origem (`source: 'cadence'`), não só quando há card no
   funil. *Pronto quando:* lead de disparo que responde não recebe mais nenhum HSM da cadência
   (teste isolado + E2E conta 3).
2. **Quiet hours na cadência HSM** — hoje só a via in-window respeita horário civilizado. *Pronto
   quando:* cadência agendada às 22h é reprogramada para o próximo horário comercial (config por
   conta, mesmo padrão do `FollowupJob`).
3. **Confirmar a migration `template_params` aplicada em prod real** — `db/schema.rb` local não
   reflete a coluna; toda a cadência HSM é *no-op silencioso* sem ela (`scheduled-cadencia.md` linha
   18 e §6 item 8). *Pronto quando:* `migrate:status` confere 0 down na VM Tozi e um agendamento de
   teste persiste com `template_params` preenchido.
4. **Promover o resto do stack de fixes de follow-up** (11-12/07) que ainda não chegou em produção —
   parte do back-merge geral já mapeado na reconciliação de frota.
5. **[D10] Sender da cadência** — decidir se passa a ser o corretor atribuído.
6. **v2 Delegação com brief** — só iniciar depois que os itens 1-3 acima estiverem estáveis (a v1
   precisa assentar sem incidente por pelo menos alguns dias de operação real).

**Esforço:** item 1 = 1 sessão de build + 1 de verificação E2E · item 2 = 1 sessão pequena · item 3 =
1 sessão de investigação/confirmação (pode virar 0, se já estiver aplicada) · item 4 = 1 sessão
(cirúrgico, reusa o diff já existente) · item 5 = 1 sessão pequena (depende de D10) · v2 completa =
2-3 sessões (já dimensionada como "médio-grande" no BACKLOG).

**Dependências/bloqueios:** nenhuma externa. Depende de D10 (sender) e da reconciliação geral de
frota não introduzir mais drift antes de promover os fixes pendentes.

**Risco:** HSM é pago (Meta cobra por template fora da janela) — cadência que não cancela no
cancel-on-reply gera custo e ruído desnecessário para leads que já responderam. Mexer em quiet
hours/horário sem cuidado pode acumular fila de envios atrasados.

---

## 2. Encerramentos

**Objetivo verificável:** toda conversa parada é classificada automaticamente (trivial / substantiva
/ campanha sem resposta / clique-e-silêncio) e tratada conforme a classe — sem nunca "sumir" uma
conversa que um humano ainda poderia reverter.

**Estado atual (fonte: `plano/encerramento-inteligente-design.md` + `.claude/STATE.md` §pouso 22/07 +
`RELATORIO-REGUA-GERAL-2026-07-23.md`):**
- **Desenho completo e já construído** (worktree `chatspx-homolog`, commits `33eececf1` +
  `15b0d69e1`, deployados na `.232` na noite de 22/07): classificador A/B/C/D, fila "Aguardando
  encerramento" (espelho 1:1 da fila "Aguardando atendimento" já em produção), cadência de fechamento
  (nota "vou encerrar" → fecho silencioso), motivo de fechamento estruturado (`motivo_encerramento`,
  IA e humano gravam no mesmo campo), combobox creatable.
- **Ligado só na conta 3 (HML)**. **Conta 6 (prod) desligada de propósito** — religar o cron de
  auto-resolve reabre risco de incidente (o de junho, fila inundada com milhares de paradas).
  Fonte: régua-geral, quadro "🟡 Deployado mas dormente".
- **E2E na conta 3 ainda não fechado** (Paulo): áudio, front visual, fila de encerramento, aba.
- **Bug de plataforma bloqueador cruzado:** a feature `conversation_required_attributes` **não liga
  em nenhuma conta** — a posição dela no `features.yml` estoura o bigint `feature_flags`
  (`RangeError 2^63+`). Sem essa flag, o modal de motivo obrigatório (§4b do design) não funciona em
  lugar nenhum. Fonte: régua-geral, mesmo quadro.

**O que falta:**
1. **Fix do bug `conversation_required_attributes`** (trocar posição no `features.yml` ou alargar a
   coluna `feature_flags`) — bloqueador transversal, não é específico de encerramento mas encerramento
   depende dele. *Pronto quando:* a flag liga em uma conta de teste sem `RangeError`.
2. **E2E conta 3** (Paulo, ~30 min por régua-geral): áudio, front, fila, aba — sem isso não há
   evidência de que o desenho funciona ponta-a-ponta com usuário real.
3. **[D1] Decidir actions por classe** para a conta 6: trivial auto-fecha ou vai pra fila? substantiva
   sempre fila? `max_dias` da válvula anti-pilha (default 3)?
4. **Ligar `auto_closure` na conta 6** com as actions decididas — *pronto quando:* conversa trivial de
   teste fecha sozinha com nota, conversa substantiva de teste cai na fila e é reversível.
5. **Ops residual:** custom attribute `motivo_encerramento` + `account.settings['auto_closure']` na
   conta 3 (parte já feita, confirmar) — nice-to-have: persistir categoria criada de volta na
   definição do atributo.
6. **Sweep NPS do backlog** — mencionado como tarefa separada NPS-safe (janela >24h já bloqueia
   captura, então é seguro rodar depois).

**Esforço:** item 1 = 1 sessão pequena (é fix de plataforma, não de encerramento em si, mas
desbloqueia) · item 2 = acompanhamento com o Paulo (não é sessão de agente sozinho) · item 4 = 1
sessão de config + monitoramento pós-live · item 5 = 1 sessão pequena · item 6 = 1 sessão.

**Dependências/bloqueios:** D1 (Paulo) + fix do bug de feature flags é pré-requisito técnico direto.

**Risco:** é o maior risco operacional da lista — religar auto-resolve errado reproduz o incidente de
junho (fila inundada, milhares de conversas fechadas em cascata). Ir devagar aqui é deliberado e
correto; não acelerar sem o E2E completo.

---

## 3. Evaluation (fechar o ciclo de auto-avaliação)

**Objetivo verificável:** toda conversa relevante da conta 6 é julgada por episódio, com veredito
acionável (outcome real vs assumido, autoria correta) e um golden set que testa mudanças de prompt
antes de ir pro ar — não só uma nota agregada.

**Estado atual (fonte: `.claude/STATE.md` linhas 140-164, `RELATORIO-REGUA-GERAL-2026-07-23.md`) —
esta é a frente mais adiantada das 8:**
- **F1 (episódios), F2 (tool-trace + gate determinístico), F2.0 (filtro de representatividade), F4
  (painel dentro do SPX), F4.1 (drill-down por indicador), spec-grounded judging e juiz em 2 camadas
  (custo cortado ~97%, de ~US$50/dia para ~US$0,5-2/dia) — **todos LIVE em produção (conta 6)**,
  recuperados e consolidados no GitHub em 23/07 depois de um incidente de conciliação que apagou a
  cadeia por algumas horas (já sanado, commit `2bd596be8`).
- Watchdog do funil de julgamento deployado (22/07) — dead-man's-switch se o cron parar de julgar em
  silêncio.

**O que falta (do blueprint Eval 2.0, `[[Obsidian/pesquisas/eval-2.0-arquitetura-robusta]]`):**
1. **F3 — outcomes e autoria**: `confirmed` vs `assumed` (a armadilha "Fin" que outras empresas do
   setor já mapearam) + autoria IA/mista/humana com índices nunca combinados. *Pronto quando:* o
   painel mostra outcome confirmado separado de outcome assumido, e a taxa de resolução por autoria
   não mistura os três buckets.
2. **F5 — golden set + simulador pass^k**: dataset curado de casos-referência (candidatos já
   apontados: caso 19861 URA/bot, caso 19863 fotos erradas) + simulação antes de publicar mudança de
   prompt. *Pronto quando:* uma mudança de prompt roda contra o golden set e mostra regressão/ganho
   antes de ir pra conta real.
3. **F4.2 — annotation queue** (comentários de admin por mensagem + observação por atendimento
   alimentando o juiz, substituindo prints no grupo de WhatsApp) — **planejada, ainda a desenhar**
   (mencionada 21/07, sem desenho técnico ainda).
4. **[D2] Onde chegam os alertas** (nota/inbox de gestão, webhook, Copilot) — decisão registrada como
   pendente na pesquisa do vault.
5. **Calibração CSAT inferido × NPS real** — mencionada como pendente na pesquisa
   `pesquisas/plano-fase2-eval-captain.md` (vault).
6. **Reconciliação trivial:** back-merge `producao→homologacao` da cadeia eval + promover a
   harmonização de botões (`55d42db54`) — meia sessão do orquestrador, sem decisão de produto
   envolvida.
7. **Rotacionar as 3 keys OpenAI que vazaram em texto no chat** durante os incidentes de 15-16/07 —
   pendência de segurança arrastada, mencionada 3× no STATE sem fechamento confirmado.

**Esforço:** F3 = 2-3 sessões (schema + pipeline + juiz + painel) · F5 = 2-3 sessões (curadoria do
dataset + simulador) · F4.2 = 1 sessão de design + 2 de build · item 6 = 0,5 sessão · item 7 =
operacional, não é sessão de agente (rotação de credencial, ação direta do Paulo ou via Almirante).

**Dependências/bloqueios:** nenhuma externa forte. F3/F5 competem por atenção com as outras 7 frentes
mas não bloqueiam nem são bloqueadas por elas.

**Risco:** manter o padrão de juiz em 2 camadas ao expandir F3 — a lição do incidente de custo
(US$260/5d) foi cara; qualquer novo eixo de julgamento (outcome/autoria) precisa nascer já dentro do
orçamento, não como chamada extra por episódio sem controle.

---

## 4. Rodízio de atribuições

**Objetivo verificável:** todo handoff da IA cai automaticamente no consultor certo — comercial por
rodízio justo, administrativo por carga/plantão — sem a Maria (recepção) distribuindo na mão.

**Estado atual (fonte: `docs/clientes/tozi/MOTOR-DISTRIBUICAO.md`, status "PLANO (kickoff)" desde
01/07, + `.claude/STATE.md` linhas 104-108):**
- **Desenho completo (F1-F4)**, decisões de F1 fechadas em 01/07: modo push (compulsório, não pull),
  estratégia rodízio justo + continuidade + pool + log.
- **Piloto locação APROVADO em 07/07** (pool Gelson+Adrian+Camila, online-only, continuidade 30d),
  mas **pendente de go-live** — nada foi codificado ainda (frontmatter do doc confirma "PLANO", não
  "implementado").
- **Linchpin identificado e não resolvido:** `HandoffTool#resolve_team` ainda roteia TODO handoff
  para `handoff_team_id=60` (recepção) antes de qualquer coisa — não existe roteamento por time
  conforme o assunto que a IA já identificou. Isso trava **duas frentes ao mesmo tempo**: o rodízio
  de locação (não adianta ter motor se o handoff nem chega no time certo) e o agente de RH (Helena,
  já LIVE, mas cujo handoff cai em recepção em vez do time RH — funciona hoje só porque a Maria
  acumula RH+recepção, uma muleta).
- Prateleira (régua-geral): "rodízio locação (aguarda `resolve_team`)" — confirma que nada avançou
  desde 07/07 além da aprovação de conceito.

**O que falta:**
1. **`resolve_team` no `HandoffTool`** — rotear pro time que a IA já indicou (RH→66, locação→27,
   jurídico→59), com o override de recepção como **fallback**, não absoluto. *Pronto quando:* handoff
   de assunto RH cai direto no time 66 e handoff sem assunto identificado ainda cai em recepção
   (regressão zero).
2. **F1 MVP do motor** (`distribuicao_policies`/`states`/`logs`, `DistribuirService` com
   continuidade+rodízio, gancho no handoff). *Pronto quando:* policy ativa no time 27 distribui
   round-robin com continuidade, policy inativa mantém o comportamento atual (pull) intacto.
3. **Config do piloto locação** (pool + cap + continuidade_dias) via rake/console, validação isolada
   (rails runner) antes do horário comercial.
4. **[D3] Decisões que definem o F1:** só-online ou estrito? janela de continuidade (qualquer
   histórico ou N dias)? comercial e admin usam a mesma regra ou perfis distintos (carga/plantão para
   admin)? reatribuição automática sem resposta em X min? cap de capacidade por consultor?
5. **Go-live piloto locação** com o time avisado, em horário comercial — acompanhamento, não é
   trabalho de agente sozinho.
6. **F2/F3** (depois do piloto validado): só-online real via presença, escala/plantão, reatribuição
   por SLA, carga, pesos, skill/tag, dashboard de distribuição.
7. **UI "Política de Distribuição" por time** — o Guilherme pediu toggle rápido, não só código; o
   desenho já marca isso como "não fica só pra F3" (§10.1 do doc) — pode precisar subir antes do
   esperado.
8. **Perfil administrativo** (por carga/plantão, escalação por SLA) — as "regras finas" que o Paulo
   mencionou (consultores de locação × corretores de vendas × administrativo) vivem majoritariamente
   aqui: comercial = rodízio justo; administrativo = carga+plantão+SLA. O desenho já separa os dois
   perfis (§4 do MOTOR-DISTRIBUICAO.md); falta codificar o perfil administrativo (hoje só o comercial
   tem piloto aprovado).

**Esforço:** item 1 (linchpin) = 1 sessão de build + 1 de verificação E2E (RH + locação) · item 2 =
1-2 sessões de build + 1 de verificação · item 3 = 1 sessão · item 6 = 2 sessões · item 7 = 2 sessões
(front+back) · item 8 = 1-2 sessões.

**Dependências/bloqueios:** D3 (Paulo) trava o desenho fino do F1. `resolve_team` é hard-blocker de
tudo o resto nesta frente — deve vir primeiro, sem exceção.

**Risco:** rodízio estrito manda lead pra quem está de folga (mitigado por pool+cap no F1, online-gate
só no F2); má configuração inicial pode gerar percepção de favoritismo entre corretores — comunicar
bem antes do go-live.

---

## 5. Cards Loft/Vista (corretor atender tudo pelo SPX)

**Objetivo verificável:** todo lead qualificado vira card no Vista automaticamente no handoff (sem a
Cibele cadastrar na mão) **e** o corretor consegue conduzir o atendimento inteiro dentro do SPX, sem
precisar do telefone pessoal.

**Estado atual — mais adiantado do que a formulação inicial sugere, mas com uma peça sem registro em
lugar nenhum (fonte: vault `kg_query` — `note:chat-2026-07-21-vista-criar-card-testado`,
`note:chat-2026-07-17-vista-fase2-criar-card-handoff`, `clientes/tozi-processo-leads-atual.md`):**
- **API Vista Fase 2 (escrita) liberada e testada em 21/07**: criação de cliente
  (`POST /clientes/detalhes`) + criação de card/negócio (`POST /negocios/detalhes`) funcionam,
  com dedup automática por telefone do lado do Vista. `CorretorNegocio` é obrigatório na criação —
  **hoje o SPX escolhe o corretor manualmente no handoff quente** (não é automático).
- **`DELETE` bloqueado (401) na API Vista** — qualquer erro de criação não tem desfazer via API;
  idempotência tem que ser garantida ANTES de escrever, não depois.
- **Decisão já batida com a Tozi:** o SPX cria o card **só para leads qualificados** no handoff
  quente (não para todo lead que entra).
- **Processo real que ainda roda em paralelo:** todo handoff quente vai pra Cibele, que cadastra no
  Vista e faz o rodízio manual entre corretores — **"os corretores da Tozi não usam o SPX para este
  processo"** hoje (citação literal da nota do vault, 17/07). Ou seja: mesmo com a API pronta e
  testada, não há confirmação de que ela substituiu o passo manual em produção real — precisa
  verificar/decidir se liga.
- **"App nativo do Walisson":** **zero registro em repo ou vault.** É informação que só existe com o
  Paulo — este plano não pode dimensionar o que não conhece.

**O que falta:**
1. **[VERIFICAR/DECIDIR]** confirmar se a criação automática de card no handoff quente já está ligada
   em produção real (substituindo o cadastro manual da Cibele) ou se segue só testada/latente.
2. **Idempotência antes de qualquer automação de volume:** checar cliente/negócio existente por
   telefone antes de criar (o Vista dedupe cliente, mas negócio/card duplicado é risco real dado o
   `DELETE` bloqueado). *Pronto quando:* reenvio do mesmo handoff não cria um segundo card.
3. **[D5] Decidir se o rodízio de `CorretorNegocio`** no create do Vista passa a usar o Motor de
   Distribuição (frente 4) em vez de escolha manual — depende do `resolve_team` e do F1 do motor
   estarem prontos primeiro.
4. **[D4] Levantamento do "app nativo do Walisson"** — não é tarefa de agente, é conversa do Paulo
   com o Walisson para mapear: o que o app faz, cronograma, e o contrato de integração (webhook?
   deep link? SSO? leitura/escrita no mesmo Vista?). **Este é o item que efetivamente decide se
   "corretor atender tudo pelo SPX" é uma meta de semanas ou de trimestre** — sem essa conversa, o
   resto da frente fica sem norte de arquitetura.
5. **Baseline de adoção:** hoje, aparentemente, zero corretores atendem pelo SPX nessa etapa (todos
   usam telefone pessoal pós-handoff) — estabelecer essa medição antes de tentar mover a agulha.
6. **Paridade de UX** — se a decisão for "SPX substitui o app", a UX de conversa (frente adjacente:
   kanban, front, respostas rápidas) precisa estar boa o bastante para o corretor preferir o SPX ao
   telefone; isso não é uma tarefa isolada, é resultado cumulativo de outras frentes (encerramento,
   analítico, kanban).

**Esforço:** item 1 = 1 sessão de investigação/confirmação (pode virar 0 build se já estiver ligado) ·
item 2 = 1 sessão pequena · item 3 = 1 sessão (depois de D5 e do linchpin da frente 4) · item 4 = não
dimensionável em sessões — é reunião/descoberta do Paulo · item 5 = 0,5 sessão de instrumentação.

**Dependências/bloqueios:** **D4 é o maior bloqueio de todo este plano** — sem saber o que é o app do
Walisson, não dá pra saber se o SPX está competindo, substituindo ou se integrando a ele. Depende
também de D5 e do linchpin `resolve_team` (frente 4) para a parte de rodízio automático.

**Risco:** qualquer automação de escrita no Vista sem idempotência sólida cria lixo permanente no CRM
real do cliente (sem `DELETE` disponível). Testar em volume baixo antes de automatizar tudo.

---

## 6. Meta-leads e campanhas

**Objetivo verificável:** todo lead de Meta Ads (formulário, DM, comentário) e todo disparo em massa
chegam ao lead certo, sem duplicar conversa, com controle operacional (pausar/retomar/redistribuir)
fora do console SSH.

**Estado atual — atenção a uma contradição real entre fontes, sinalizada abaixo (fonte:
`docs/mapeamento-2026-06-10/meta-lead-ads.md` e `campanhas.md`, 10/06, cruzados com
`.claude/STATE.md` e `RELATORIO-REGUA-GERAL-2026-07-23.md`, 23/07):**
- **Motor de disparo em massa (`DisparoLeadJob`)** funciona: pacing, round-robin de corretores,
  rotação de templates, dedup do 9º dígito já corrigido nesse job especificamente.
- **STATE.md (23/07) lista "Meta Leads → Sofia (roteamento, erros Meta, RMKT catálogo com foto,
  holerite PDF/foto) — live desde 14-17/07"**, mas o **BACKLOG ainda lista C4 (gap HSM da 1ª
  mensagem em Cloud API) como aberto e bloqueador de produção** — as duas fontes não batem
  perfeitamente; tratar como **[VERIFICAR]**, não como resolvido.
- **Achado crítico da régua-geral (23/07): "WIP meta-leads não-commitado (~100 linhas
  `create_conversation_service` + `fetch_lead_service`) vive só em
  `bkp/tozi-wip-vista-uncommitted-2026-07-23`. Se era feature ativa, está FORA DO AR desde a
  conciliação."** — ou seja, é possível que o código que fez "Meta Leads → Sofia" funcionar tenha
  saído do ar no reset da VM de 23/07 e nunca tenha sido commitado. **Isto precisa ser confirmado com
  urgência antes de qualquer outra coisa nesta frente.**
- **23 templates HSM aprovados** cobrindo lançamento/locação, venda, inquilinos (com header de
  imagem), follow-up e lead/cadência (`docs/clientes/tozi/TEMPLATES-DISPARO-TOZI.md`, snapshot
  08/06) — mas o asset de imagem do header (`inq-mapa.jpeg`) está **404 em produção**, dropado por
  deploy.
- **Gaps estruturais não resolvidos** (`campanhas.md` §9): sem modelo de disparo persistido (estado
  vive no Sidekiq ScheduledSet + scripts em `Downloads/`), sem controle Pausar/Retomar/Redistribuir
  na UI (é BACKLOG 🔴 alta), sem UI de criação de disparo (upload CSV + rake por SSH hoje), sem stats
  por template (precisa script de console).
- **Gaps do Meta Lead Ads** (diferente do disparo em massa): `CreateConversationService` **não tem o
  mesmo fix de 9º dígito** que o `DisparoLeadJob` já ganhou (mesma família de bug, não corrigida aqui
  ainda) + **sem idempotência por `leadgen_id`** (retry/redelivery do webhook cria conversa duplicada)
  + `HookFinder` sem escopo de conta + segredos (`app_secret`/`page_access_token`) em claro no JSONB.

**O que falta:**
1. **[URGENTE/VERIFICAR]** confirmar com o autor (Nicolas/Walisson) se o WIP do meta-leads é feature
   ativa; se sim, commitar/reaplicar imediatamente — hoje pode estar rodando código velho sem os
   fixes de roteamento pra Sofia.
2. **Fix source_id (9º dígito) no `CreateConversationService`** do Meta Lead Ads — mesmo patch já
   provado no `DisparoLeadJob`. *Pronto quando:* lead Meta que responde cai na conversa certa, sem
   duplicar ficha.
3. **Idempotência por `leadgen_id`** — evitar conversa duplicada em retry de webhook.
4. **1ª mensagem como HSM em Cloud API** (BACKLOG C4), se ainda pendente após o item 1.
5. **Controles operacionais na UI**: Pausar/Retomar/Redistribuir (botões na tela de detalhe da
   campanha) + drill-down de falhas por código Meta.
6. **UI "Novo disparo"** completa (upload CSV, corretores, templates com rotação, pacing, dry-run) —
   candidato a sessão de design antes de codificar (é um módulo, não um patch).
7. **Modelo de disparo persistido** (`CampaignDispatch`) + stats por template (group-by já mapeado,
   é query nova) + série temporal.
8. **Fix do asset 404** (`inq-mapa.jpeg`) — trivial, mas quebra o header de imagem dos templates de
   inquilinos até corrigir.
9. **Repescagem/2ª leva com imagem** — `FollowupHsmJob` hoje só manda texto (motivo do bloqueio
   documentado da 2ª leva de locação).
10. **Segurança:** criptografar `app_secret`/`page_access_token` no JSONB de settings do hook.
11. **[D6][D7]** esclarecer com o Paulo o que "áudios" e "catálogo" significam operacionalmente antes
    de estimar esforço de construção — hoje não há pesquisa de viabilidade de áudio em template HSM
    de marketing nem decisão sobre Product Catalog API vs header de imagem.

**Esforço:** item 1 = 0,5-1 sessão de investigação (é quase auditoria, não build) · item 2+3 = 1
sessão de build + 1 de verificação · item 4 = 1 sessão (se pendente) · item 5 = 1 sessão backend + 1
frontend · item 6 = 2-3 sessões (módulo) · item 7 = 2 sessões · item 8 = 0,5 sessão · item 10 = 0,5
sessão.

**Dependências/bloqueios:** item 1 depende de confirmação humana (autor do WIP) antes de qualquer
ação de código. D6/D7 (Paulo) definem se "áudios" e "catálogo" viram trabalho real ou saem do escopo.

**Risco:** disparo mal pacing degrada o tier do número WABA (YELLOW→RED) — já mitigado
parcialmente, mas sem alerta automático de degradação (item do BACKLOG C3, fora deste plano mas
correlato). Duplicação de conversa por retry de webhook gera ruído e possível lead perdido/confuso.

---

## 7. Analítico de leads (funil observável)

**Objetivo verificável:** dá para responder, sem rodar script de console, "quantos leads entraram
este mês, em qual estágio cada um está, quantos converteram e quantos morreram — e onde exatamente
travam".

**Estado atual (fonte: `docs/mapeamento-2026-06-10/kanban-funil.md` + `campanhas.md` §5, cruzados
com a análise pontual do vault `clientes/tozi-analise-leads-2026-04-20.md`):**
- **Os dados existem** (7 estágios do funil "Pré-Venda Tozi": novo_lead → aguardando_1a →
  em_conversa → em_silencio → agendado → qualificado → frio; `FunnelItem` com `moved_at`), mas **não
  existe painel/dashboard vivo** — é uma métrica completamente diferente do painel de Eval (que mede
  qualidade de atendimento, não fluxo de leads).
- Análise mais recente que existe foi **um script pontual em abril** (não dashboard):
  1.955 leads/30 dias, 77% Meta Ads, **63% viram card no pipeline (Vista)**, **84% sem etapa
  preenchida há 7+ dias** (candidatos a reativação/limpeza) — dado valioso mas manual e datado.
- `campaign_stats` (endpoint por campanha) existe mas é **admin-only**, sem quebra por template, sem
  série temporal.
- **Não existe endpoint** "estágio do lead X", "leads parados há N dias" ou "cards por
  automation_type" — o dado (`moved_at`) está no banco e é exposto no JSON, mas sem filtro
  server-side; consulta hoje é `rails runner` ad-hoc.
- **Dois bugs contaminam qualquer número que se tente extrair hoje:**
  (a) `DisparoLeadJob` não coloca lead no funil → leads de disparo em massa entram só via backfill
  automático, indistintos, em "Novo Lead";
  (b) o backfill automático **também empurra atendimento humano comum** pra "Novo Lead" toda vez que
  alguém abre o board (throttle 10 min) — porque o funil Tozi não tem estágio `resolved`, o
  `default_stage` vira o primeiro estágio.
- Cards duplicados por conversa duplicada (9º dígito) — dedup é só visual na renderização, o banco
  mantém os duplicados (mesma família de bug que a `MISSAO-9DIGITO-E-TRIAGEM.md` já ataca em outra
  frente).

**O que falta:**
1. **Endpoint "leads parados há X dias"** — `FunnelItem.by_funnel.by_stage.where(moved_at < X)`
   exposto via API. *Pronto quando:* dá pra listar, por estágio, quem está parado há mais de N dias
   sem rodar `rails runner`.
2. **Fix do backfill que polui "Novo Lead"** com atendimento humano comum — sem isso, qualquer
   contagem de "novos leads" está inflada por conversas que não são leads novos.
3. **Colocar `DisparoLeadJob` no funil** (estágio `aguardando_1a`) — sem isso, disparo em massa é
   invisível no funil de origem.
4. **`campaign_stats` por template + série temporal** — quebra por template já é query pronta
   (group-by sobre campo já gravado), falta implementar.
5. **[D8] Decidir o formato final:** estender o Kanban existente com filtros/API nova, ou construir
   um dashboard dedicado (reusando o padrão visual do painel de Eval que já existe e é aprovado) —
   ou os dois (Kanban pra operação do dia a dia, dashboard pra visão executiva mensal).
6. **Resolver duplicação de cards** — depende do fix geral do 9º dígito, já em andamento em
   `MISSAO-9DIGITO-E-TRIAGEM.md` (frente transversal de plataforma).

**Esforço:** item 1 = 1 sessão · item 2 = 1 sessão pequena · item 3 = 1 sessão pequena · item 4 = 1
sessão · dashboard dedicado (se D8 escolher essa opção) = 2-3 sessões (backend agregador + frontend).

**Dependências/bloqueios:** item 6 depende do fix transversal de 9º dígito (frente já em execução,
fora deste plano específico mas compartilhando causa raiz). D8 (Paulo) define o tamanho real do
trabalho de frontend.

**Risco:** construir dashboard antes de corrigir a poluição do backfill e a duplicação de cards
produz números bonitos e errados — mesmo erro de confiança que já aconteceu com o NPS de junho
(auditoria encontrou 421 notas perdidas por um bug silencioso). Corrigir a fonte antes de expor o
número.

---

## 8. Instagram total

**Objetivo verificável:** a Tozi atende DM, comentário e menção do Instagram pelo mesmo pipeline do
Captain V2 (não um n8n paralelo), com dado de orgânico e pago no mesmo funil de leads.

**Estado atual (fonte: `.claude/STATE.md` linhas 56-57 + vault `kg_query` —
`01-projects/spx-meta-connect.md`, `aprendizados/instagram-comment-to-lead-pipeline.md`,
`aprendizados/captain-v2-tozi-config-recipe.md`):**
- **Canal técnico já provado — mas para Midwest, não Tozi.** Piloto E2E em 20/07: inbox Instagram
  #56, IA Lia (assistant #17), DM real respondida em 3 turnos. Usa o Business Manager "MW" da
  Midwest — **não há app Meta / Business Manager configurado para a Tozi ainda.**
- **Comentários e curtidas: não implementado no SPX.** Existe um pipeline **antigo e paralelo**
  ("Instagram Comment → Lead", estilo ManyChat) já desenhado e documentado no vault, mas roda em
  **n8n + Supabase + WAHA** — fora do Captain V2/SPX nativo. Portar essa lógica pro pipeline
  unificado é trabalho não iniciado.
- **F6 do roadmap SPX Meta Connect** (vault) já prevê a expansão — subscrever `comments`, `mentions`,
  `messaging_postbacks` no webhook (hoje só `messages` está provado) e rotear pro mesmo pipeline dos
  agentes (Letícia/Bruna) — **planejado, não codificado**.
- **Conduta window-aware do IG** (24h Cloud / 7d IG, `HUMAN_AGENT` só humano) e **guarda
  anti-enxurrada de menção de story** — pendências já anotadas mesmo no piloto Midwest que está no ar.
- **App Review (Advanced Access) da Meta** — pré-requisito documentado para operar Instagram
  multi-tenant/produto de verdade; hoje limitado a "Instagram Tester" (1 conta só).
- **"Entender curtidas":** **sem pesquisa de viabilidade registrada.** A Graph API tem acesso muito
  limitado a curtidas de posts/comentários de terceiros — antes de prometer isso, precisa checar o
  que a API realmente expõe.

**O que falta:**
1. **[D9] Decidir o app Meta/Business Manager da Tozi** — sem isso, nada de setup técnico avança.
2. **Setup técnico do canal IG para a conta 6**, replicando a receita já provada na conta 3
   (Business Manager, OAuth redirect, webhook, Instagram Tester aceito). *Pronto quando:* DM real da
   conta oficial da Tozi chega no SPX e a IA responde.
3. **Expandir o webhook** para `comments`/`mentions`/`messaging_postbacks` (hoje só `messages`).
4. **Portar a auto-resposta de comentário→DM** do pipeline n8n antigo pro Captain V2 nativo (reusar
   agentes já existentes em vez de manter dois sistemas paralelos).
5. **Conduta window-aware + guarda anti-enxurrada de story** — pendências já conhecidas, ainda sem
   fix mesmo no piloto que está no ar.
6. **[PESQUISAR]** viabilidade real de "dados de curtidas" via Graph API antes de comprometer prazo —
   pode ser que o escopo real seja outro (ex.: métricas de engajamento de posts próprios, não
   curtidas de terceiros).
7. **Submeter App Review da Meta** — processo administrativo longo (semanas), fora do controle do
   time de dev; deve começar cedo, em paralelo com o código.

**Esforço:** item 2 = 1 sessão de build + 1 de verificação E2E · item 3 = 1-2 sessões de build + 1 de
verificação · item 4 = 2 sessões · item 5 = 1 sessão · item 6 = 1 sessão de pesquisa (sem build) ·
item 7 = não é sessão de agente (submissão + acompanhamento do processo da Meta).

**Dependências/bloqueios:** D9 (Paulo) trava o item 2. App Review é o maior bloqueio externo — prazo
não controlado pelo time, deve ser disparado o quanto antes independente da ordem das outras frentes.

**Risco:** operar sem App Review limita a testes (1 conta), não escala pra produção real da Tozi.
Rate limits e mudanças de API da Meta são recorrentes — qualquer coisa construída aqui precisa de
manutenção contínua, não é "constrói uma vez e esquece".

---

## Sequência recomendada (30 dias) e paralelização

**Regra de fundo do repo:** só existem 3 branches canônicas (`homologacao`, `producao`, `paulao`) —
nada de branches `feat/*` soltas (quebram o Almirante). Trabalho de **plataforma/código genérico**
(a maior parte das frentes 1, 2, 3, 4, 6, 7) roda no repo principal, commit direto em
`homologacao`, valida na conta 3 (`.232`), promove a `producao` via Almirante
(`dry_run` → `propose_deploy_*` → aprovação humana). Trabalho de **conduta/config de conta** roda nos
worktrees por cliente (`chatspx-clientes/tozi-prod` conta 6, `tozi-hml` conta 3) — nunca no molde
compartilhado. Várias frentes de código **podem rodar em paralelo em worktrees diferentes** desde que
toquem arquivos diferentes (ex.: `resolve_team` no `HandoffTool` vs. classificador de encerramento no
`InboxPendingConversationsResolutionJob` vs. fix de 9º dígito no
`Meta::LeadAds::CreateConversationService` — zero sobreposição de arquivo); o gargalo é sempre o
**push sequencial pra `homologacao`** e a validação humana antes de promover a `producao`, não o
trabalho em si.

### O que destrava o quê

- **`resolve_team`** (frente 4) é o linchpin de maior alavancagem do plano: destrava rodízio de
  locação, conserta o handoff de RH (Helena) e é pré-requisito para automatizar o rodízio de corretor
  no Vista (frente 5, item D5).
- **Fix `conversation_required_attributes`** (frente 2) é barato e destrava o motivo de encerramento
  em qualquer conta, não só Tozi.
- **Verificação do WIP meta-leads perdido** (frente 6) é a tarefa mais urgente de todo o plano — sem
  ela, não se sabe se o roteamento pra Sofia está de fato no ar.
- **Fix do 9º dígito / dedup de card** é transversal: destrava números confiáveis na frente 7 e reduz
  risco na frente 6.
- **Conversa com o Walisson (D4)** é a única tarefa do plano que não é código nem decisão interna — e
  é a que mais define o teto de ambição da frente 5. Marcar logo, não deixar pra depois.
- **Submissão do App Review da Meta (frente 8)** tem prazo fora do controle do time — disparar cedo
  aproveita o tempo de espera em paralelo com o resto.

### Marcos de 30 dias

**Semana 1 — estabilização e verificação (baixo risco, alto valor de reduzir incerteza)**
- Confirmar/reconciliar o WIP meta-leads perdido (frente 6, item 1) — commit ou descarte com o autor.
- Rotacionar as 3 keys OpenAI vazadas no chat (frente 3, item 7).
- Fix do bug `conversation_required_attributes`/`feature_flags` (frente 2, item 1).
- Fix source_id (9º dígito) no Meta Lead Ads + idempotência por `leadgen_id` (frente 6, itens 2-3).
- Back-merge trivial `producao→homologacao` da cadeia eval (frente 3, item 6).
- **Disparar em paralelo, fora do código:** agendar conversa com o Walisson (D4) e submeter o App
  Review da Meta (frente 8, item 7) — os dois têm relógio próprio, começar já.

**Semana 2 — linchpins**
- `resolve_team` no `HandoffTool` (frente 4, item 1) + verificação E2E (RH e locação).
- F1 MVP do Motor de Distribuição (frente 4, item 2) + config do piloto locação.
- E2E conta 3 de encerramento (Paulo) + decisão D1 + ligar `auto_closure` na conta 6 com cautela
  (frente 2, itens 2-4).
- Início do Eval F3 (outcomes/autoria) — corre em paralelo, sem dependência das outras frentes.

**Semana 3 — go-lives monitorados + módulos operacionais**
- Go-live do piloto de rodízio de locação (acompanhado, horário comercial, time avisado).
- Fechar o gap de cancel-on-reply da cadência para leads de disparo + funil (frente 1, item 1).
- Controles Pausar/Retomar/Redistribuir na UI de campanhas (frente 6, item 5).
- Endpoint "leads parados há X dias" + `campaign_stats` por template (frente 7, itens 1 e 4).
- Se D5 e o linchpin estiverem prontos: conectar o rodízio automático ao `CorretorNegocio` do Vista
  (frente 5, item 3).

**Semana 4 — fechamento do ciclo + replanejamento**
- Eval F5 (golden set) — início.
- Setup técnico do canal Instagram para a conta 6, se D9 já decidido (frente 8, item 2) + expansão do
  webhook para comentários/menções (item 3), independente do resultado do App Review (ambiente de
  teste não precisa esperar a aprovação).
- Dashboard de funil de leads dedicado, se D8 escolher essa opção (frente 7).
- Revisão geral do sprint com o Paulo: o que ficou fora (F4.2 annotation queue, v2 delegação com
  brief, F2/F3 do rodízio, UI completa de "Novo disparo", auto-resposta de comentário→DM) vira a base
  do próximo ciclo de 30 dias.

---

## Notas finais

- Este plano não cobre a **reconciliação de frota** em si (VM `producao` em SHA off-git
  `805f0fd6cc`, WIP não-commitado, branches zumbis) — ela é pré-requisito transversal já mapeada em
  `RELATORIO-REGUA-GERAL-2026-07-23.md` e no `PLANO-RECONCILIACAO-FROTA-2026-07-16.md`, e alguns dos
  itens da Semana 1 acima dependem dela estar limpa antes de promover código novo pra produção.
- Onde o repo e o vault divergiam (Meta Leads → Sofia "live" no STATE vs. C4 "aberto" no BACKLOG;
  encerramento "construído" no design doc vs. "dormente" na régua-geral), este plano preservou a
  divergência como **[VERIFICAR]** em vez de escolher uma fonte arbitrariamente — a primeira sessão
  de trabalho em cada uma dessas frentes deve começar confirmando o estado real antes de codificar.
