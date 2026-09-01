# Handoff — sessão orquestradora geral · 13/08/2026

> Para quem assume a **geral** do chatspx depois desta sessão. Complementa
> `docs/ORQUESTRACAO-ORCA.md` (a prática) e `.claude/STATE.md` (o in-flight).

---

## 1. O contexto do Paulo, que redefine o papel

Ele toca **vários projetos distintos em paralelo** — chatspx é só um deles — e usa o Claude Code para
tudo, inclusive o que não é código. O Orca entrou para organizar branch, worktree, commit, push,
merge e PR, e traz três superfícies com usos diferentes:

| superfície | para quê | custo |
|---|---|---|
| **terminal flutuante** | conversa com ele, decisão, triagem, qualquer projeto; sem contexto de repo | nenhum |
| **sessão em worktree** | um repo, uma branch, um trabalho; herda o `CLAUDE.md` do projeto | isolamento de checkout |
| **orquestração** | uma sessão supervisionando várias, com `worker_done` e DAG | **fila de mensagens que notifica o Paulo** |

**A regra que faltou hoje:** orquestração **só** quando você realmente precisa de conclusão
estruturada de várias frentes ao mesmo tempo. Para o resto, terminal comum e leitura direta da saída.
Em 13/08 a fila de mensagens gerou dezenas de notificações para ele — batimentos, sobretudo — e ele
disse, com razão, que aquilo estava poluindo a conversa. Worker ignora o pedido de silêncio na spec e
só obedece quando recebe a mensagem no meio do trabalho, o que sempre chega tarde.

---

## 2. Estado em 13/08

**Sete PRs abertos**, todos contra `homologacao`:

| PR | conteúdo | urgência |
|---|---|---|
| **#46** | fecha acesso indevido em 13 tools do copilot | **alta** — corretora alcançava 24.206 conversas com nota privada contra 217 permitidas (111×), medido na Tozi conta 6 |
| **#41** | nil-safety do `track_urls` | **alta** — a `homologacao` está vermelha até entrar |
| **#40** | `dados_imoveis` vazando para o prompt | vazamento que entrou no lote de 12/08 |
| **#43** | fronteira de conta na atribuição do copilot | derrubou a premissa "copilot tem humano no meio": `snooze_conversation` rodou 2× sozinho |
| **#44** | marketing edita roteamento por campanha, com validação anti-`#132000` | |
| **#45** | camada mídia→contexto para imagem (eixo 3) | |
| **#42** | documentação | |

**Aplicado e provado em produção:** guarda de departamento na Fábrica (15 execuções sem vazar) ·
conduta do beco sem saída (9 rodadas) · tools do MTM (calendário, enum de período confirmado por
sonda) · override do Pacaembu na Tozi · agente da BigStore criado e gateado, com teste E2E passando ·
pool de conexões da `.232` restaurado.

**Disparo da Tozi:** terminou. **4.862 enviadas, 1 cancelada, zero falhas**, nas campanhas 4/5/6
(Francielli, Henrique, Weigler). As três ficaram em `paused` de propósito. Falta, se ele quiser, o
relatório de resultado por corretor.

---

## 3. O que falta, por frente e por dono

**Do Paulo:**
- **Crédito da Anthropic na `.232`** — segura duas provas comportamentais **já escritas**: a conduta
  que usa a base de conhecimento da BigStore, e a conduta do story. Scripts de aplicar, verificar e
  reverter salvos em `scratchpad/bigstore-conduta/` (cópia provada por hash, fora da box).
- **Vídeo no eixo 3** — exige `ffmpeg` na frota, mais decisão de quadros por minuto e teto de custo.
  ⚠️ Antes de priorizar: **97,1% dos story replies já trazem texto**; o caso 100% cego é **2,9%**, e
  nesses o próprio time humano não responde.
- **Escopo `instagram_business_manage_comments`** no painel da Meta — gate único das 4 capacidades de
  comentário. Brief pronto em `instagram-comentarios/Temp/BRIEF-META-escopo-comentarios.md`.

**Do Walisson:** os 7 PRs, e decidir como subir os **16 commits off-origin** da box de homologação.

**Da Tozi:** o mapa de CTA → slug de intenção, bloqueador da spec do site
(`intencao-site/Temp/SPEC-intencao-site.md`).

**Da BigStore:** tabela de lojas — mas hoje foi reconstruída do próprio atendimento: **Rondonópolis,
Primavera do Leste e Cláudia foram transferidas** (75 respostas do time, zero telefone entregue),
contra o que o vault registra.

**Sem dono:** allowlist de times da Fábrica (inerte até aquele box receber deploy) · deploy da
Fábrica, que é projeto e não ajuste (249 commits atrás, feature ativa fora do git, resgatada em
`backup/fabrica-box-offgit-20260812`) · os custom tools que vão todos ao copilot ignorando a coluna
que os marcaria como exclusivos, **4 deles escrevendo no CRM externo da Fábrica**.

---

## 4. ⚠️ O deploy da homologação está SUSPENSO, e não é por risco técnico

A box `.232` tem **144 arquivos off-git** (não 70 — `git status --porcelain` conta diretório
untracked como uma linha) e **16 commits em 7 branches** que não existem no GitHub. Tudo resgatado e
provado por hash em `scratchpad/homologacao-offgit/`.

O trabalho é **dirigido pelo Walisson**, executado por sessões de agente na própria box — e **havia
sessões rodando durante o levantamento** (dois `claude`, um há 27 horas, e um `codex`).

Um deploy hoje: trava num untracked que colide, **perderia 20 arquivos em silêncio absoluto** (o lote
`ai-assistant`/copilot, que o deploy nem toca — sem conflito e sem aviso), e traria **10 migrations**
que o "zero pendente" do Almirante não enxerga, porque ele mede **antes** do checkout.

---

## 5. As armadilhas de medição que custaram caro hoje

Todas produziram relatório errado antes de serem pegas:

1. **`order(id: :desc)` devolve registro velho.** Ordene por `created_at`, ou use `maximum(:id)`.
2. **Laço de monitor dentro de um `rails runner` congela** — o query cache repete a primeira
   resposta. Reportei "disparo parado há 12 minutos" com a fila andando a 19/min. Use
   `ActiveRecord::Base.uncached { }` em **cada** amostra. Sintoma: um número que não mexe **nenhum**
   enquanto outro do mesmo script varia.
3. **`contact_id` é nulo em `campaign_recipients` pendente** — o contato só nasce no envio. Cruze por
   telefone.
4. **`assignee_type` é `'AgentBot'`, não `'agent_bot'`.** Com a grafia errada o serviço trata como
   humano, procura um usuário inexistente e **limpa os dois campos**.
5. **`terminal list` mente por segundos** depois de `terminal close`, e o `preview` **não** serve para
   você se identificar. Use o pane do `run-create`.
6. **Baseline é o próprio ramo sem o próprio commit** — nunca `origin/homologacao`.

---

## 6. O que funcionou e vale repetir

**Exigir prova, não relatório.** Três propostas minhas foram **derrubadas pela medição** antes de ir
para produção: a conduta de locação da Júlia (0/8 no formato dominante), a regra de string sobre a
jornada (falso positivo irredutível — três jornadas byte a byte idênticas foram para times
diferentes) e o renome dos times do Atacadão (0% de eficácia, o modelo lê a marca e escolhe assim
mesmo).

**Deixar o worker discordar.** O melhor resultado do dia foi um "não" com 200 execuções atrás.

**Olhar antes de sobrescrever.** Duas VMs tinham trabalho vivo fora do git. Nas duas, o resgate veio
antes — e nas duas o deploy teria apagado em silêncio.
