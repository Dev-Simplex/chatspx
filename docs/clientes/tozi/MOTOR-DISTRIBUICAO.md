---
titulo: Motor de Distribuição de Atendimentos (SPX)
cliente: Tozi Imóveis (conta 6) — replicável multi-tenant
status: PLANO (kickoff)
data: 2026-07-01
ai-generated: true
tags: [spx, distribuicao, atribuicao, rodizio, captain, workflow]
---

# Motor de Distribuição de Atendimentos

## 1. Problema (o que a gestão pediu)

> Áudio do Guilherme (01/07), transcrito: depois da IA triar e rotear pro **time**, falta distribuir pra um **consultor específico**. Hoje quem faz é a **Maria (recepção), na mão**. Isso precisa ser **automático, compulsório e configurável**.

Dois motivos, dois setores:

- **Comercial (vendas/locação):** não pode deixar o consultor **escolher** o atendimento — cada um tem que receber o **mesmo número de leads** (rodízio justo). Senão o mais esperto pega os melhores.
- **Administrativo (financeiro/suporte/prestadores):** ninguém quer **puxar** a dor de cabeça — e pior: quando puxam, **começam a contar as métricas de SLA** (1ª resposta, espera). Então **não puxam** pra proteger o número. Tem que ser **empurrado, obrigatório**.

### 1.1. Por que o modelo atual ("Aguardando atendimento" / pull) não serve
A feature "Aguardando atendimento" (fila de onde o humano **puxa**) é **incompatível** com a gestão da Tozi: o consultor evita puxar (SLA passa a contar contra ele) e faz cherry-pick. **A distribuição tem que ser PUSH (compulsória), não pull.**

### 1.2. O "filtro" exigido
Antes de distribuir no rodízio, aplicar **continuidade**: se o cliente **já estava sendo atendido por um consultor**, a conversa volta pra **esse** consultor (o cliente segue com quem conhece o caso), não pro rodízio. A IA também deve ter **entendido o contexto** antes de distribuir (já qualifica hoje).

---

## 2. Conceito

Cada **time** (ou tipo comercial/administrativo) carrega uma **Política de Distribuição**: um conjunto de regras, tudo **liga/desliga e combinável**, que decide **quem recebe, quando e como**. Um **Motor** (`Spx::Distribuicao`) executa a política no gatilho (principalmente no **handoff da IA**).

```
conversa nova/reaberta → IA (triagem) → IA especialista qualifica
        → HANDOFF → [MOTOR DE DISTRIBUIÇÃO] → consultor específico (compulsório)
        → SLA conta a partir daqui → gestor tem accountability
```

---

## 3. Tudo que é configurável (o mapa amplo)

### 3.1. Estratégia (algoritmo de "quem é o próximo")
- **Rodízio** (round-robin, distribuição igual) — padrão comercial.
- **Menos recente** (quem faz mais tempo sem receber).
- **Por carga** (quem tem menos conversas abertas) — bom p/ administrativo.
- **Ponderado** (pesos por consultor: sênior 2×, trainee 0,5×).
- **Por skill/tag** (casa assunto ↔ habilidade).
- **Por performance** (mais rápido / mais converte) — ⚠️ tensiona a justiça.
- **Aleatório.**
- **Manual** (segue com a recepção = motor desligado, fallback).

### 3.2. Pool — quem participa da distribuição
- **Lista de participantes** — liga/desliga **por pessoa** no time.
- **Só quem está ONLINE** — toggle (presença via websocket).
- **Só em escala/plantão** — turnos (manhã/tarde), dias da semana.
- **Respeitar status do agente** — disponível / ausente / ocupado (o próprio marca).
- **Cap de capacidade** — máx. N conversas abertas por pessoa (não estoura).
- **Férias/folga** — exclui do pool.
- **Skill obrigatória** — só entra quem tem a tag do assunto.

### 3.3. Filtros de roteamento (ANTES do rodízio — têm prioridade)
- **Continuidade** — cliente já atendido por X → vai pra X. Config: janela (qualquer histórico / últimos N dias).
- **VIP / cliente-chave** → consultor ou pool específico.
- **Região/bairro** → consultor da área.
- **Faixa de valor / lead premium** → seniores.
- **Origem** (campanha, lead ads, número) → pool dedicado.
- Regras "SE condição ENTÃO pra quem", **ordenáveis**.

### 3.4. Gatilho — quando distribui
- **No handoff da IA** (principal).
- **Na entrada** (conversa nova, se pular a IA).
- **Na reabertura** (lead que volta).
- **Após X min sem 1ª resposta** (reatribui / escala).
- **Botão manual** "distribuir agora".

### 3.5. Reatribuição / rebalanceamento (mantém justo e vivo)
- **Não respondeu em X min** → próximo (conta como recusa).
- **Ficou offline/ausente** → reatribui os abertos dele.
- **Sobrecarga** → tira de quem tem muito, dá pra quem tem pouco.
- **Escalação** → após N tentativas sem resposta → **gestor**.
- **Rebalanceamento periódico.**

### 3.6. Justiça / contabilidade ("mesmo nº de leads")
- **Contador por consultor** (leads recebidos) — base do rodízio justo.
- **Janela de igualdade** — por dia / semana (reseta).
- **Compensação** — quem esteve fora volta recebendo por último até equalizar (ou primeiro, configurável).
- **Pausa individual** — "hoje o fulano não entra" (médico, treinamento).

### 3.7. Modo — push vs pull
- **Push (compulsório)** — atribui direto (o pedido do Guilherme).
- **Pull (fila)** — o atual (desligar p/ comercial/admin; opcional p/ algum time).
- **Híbrido** — push com opção de **recusar** (com motivo) → volta pro rodízio.

### 3.8. SLA / accountability
- 1ª resposta / espera / atendimento contados **da atribuição**.
- **Alertas** de estouro (consultor + gestor).
- **Dashboard de distribuição** — quantos cada um recebeu, tempo médio, conversão, recusas.

### 3.9. Controle do gestor & auditoria
- Reatribuir manual (sempre) · pausar o motor · modo manual temporário · forçar pra alguém.
- **Log de cada decisão:** "conv X → Bruno (rodízio, era a vez)" / "→ Adrian (continuidade)".

---

## 4. Comercial × Administrativo (perfis prontos)
Cada time carrega seu perfil:
- **Comercial:** rodízio justo + continuidade + cap → foco em **oportunidade igual**.
- **Administrativo:** por **carga/plantão** + escalação por SLA → foco em **ninguém escapa + resolve rápido**.

---

## 5. Modelo de dados (rascunho)

`DistribuicaoPolicy` (por team/account):
```
account_id, team_id, ativo, modo(push|pull|hibrido),
estrategia(rodizio|carga|ponderado|skill|...),
pool: [{user_id, ativo, peso, cap, skills:[]}],
so_online(bool), respeitar_escala(bool),
continuidade(bool, janela_dias),
filtros: [{condicao, alvo}],  # ordenáveis
reatribuir_sem_resposta_min, escala_apos_n, escala_para(user_id),
igualdade_janela(dia|semana)
```
`DistribuicaoLog` (auditoria): conversa, escolhido, motivo, candidatos, timestamp.
`DistribuicaoState` (rodízio): team_id → ponteiro/contadores por consultor.

---

## 6. Arquitetura no SPX (o que reusa)
- **Atribuição/times/membros** já existem (`AssignmentService`, `team_members`).
- **Auto-assign nativo do Chatwoot** (round-robin básico) = ponto de partida, mas **limitado** (só online, sem continuidade/carga/pesos/escala) → justifica o **motor próprio** `Spx::Distribuicao`.
- **Presença online** já rastreada (websocket) → alimenta o "só online".
- **O HANDOFF da IA** (que já mexemos: mantém a IA + marca aguardando) é o **gancho natural** — em vez de "soltar na fila", chama `Spx::Distribuicao.distribuir(conversation)`.
- **SLA/AppliedSla** nativo p/ os tempos + **as regras de reaberta** que montamos (reaberta→IA→handoff→motor).
- **Config-first (padrão SPX):** o front é viewer; o Claude Code / a UI configuram a política.

---

## 7. Faseamento
- **F1 (MVP):** modo push + estratégia **rodízio justo** + **continuidade** + **pool** (lista + cap) + **log**. Gancho no handoff. → resolve o pedido do Guilherme e substitui a Maria.
- **F2:** **só-online** + **escala/plantão** + **reatribuição por SLA** (sem resposta em X min → próximo).
- **F3:** **carga**, **pesos**, **skill/tag**, **dashboard de distribuição**, **escalação pro gestor**.
- **F4:** **híbrido** (recusa com motivo), **performance**, **compensação fina**, perfis comercial/admin salvos.

---

## 8. Decisões pendentes (definem o F1)
1. **Rodízio considera ONLINE** (só distribui p/ disponível) **ou ESTRITO** (todos recebem igual, mesmo offline)?
2. **Continuidade:** o que conta como "já estava sendo atendido" — qualquer histórico com o consultor, ou só últimos N dias?
3. **Comercial e administrativo** usam a MESMA regra de rodízio, ou o admin é por **carga/plantão**?
4. **Sem-resposta:** reatribui automático após X min? (qual X) — ou só o gestor reatribui?
5. **Cap de capacidade** por consultor: existe teto de conversas abertas?

---

## 9. Relação com o que já está no ar
- As **8 regras de reaberta → IA** (conta 6) já garantem que a conversa **sempre cai numa IA** (nunca órfã). O Motor entra **depois**, no handoff da IA → consultor.
- O **"Aguardando atendimento"** (pull) do outro dev vira **opcional/legado** — o Motor (push) é o novo padrão da Tozi. Alinhar com o dev.

---

## 10. F1 — Desenho técnico (MVP)

### 10.1. Decisões (fechadas 01/07 — TUDO configurável por time, via interface)
Cada time tem uma **Política** ligável/desligável numa **interface** (o Guilherme quer o toggle rápido, não só código). Por time se escolhe:
- **Modo:** `rodizio` (push, distribuição justa/compulsória — comercial) · `online` (pega quem está online — times sem rodízio) · `off` (segue no "aguardando"/pull atual).
- **Pool:** quem do time é **elegível** — liga/desliga **por pessoa**.
- **Só-online:** toggle (on = distribui só pra disponível; off = estrito, todos recebem igual).
- **Continuidade:** on/off + **janela** (dias) — dinâmico.
- **Cap** por consultor: opcional (teto de conversas abertas).
- **🔑 Coexistência (não substitui à força):** a fila **"Aguardando atendimento"** (pull) do outro dev **continua**; o Motor (rodízio) **só aparece pros times configurados com rodízio**. Times sem rodízio seguem no pega-online/pull. → **alinhar com o dev**: a fila dele vira **um dos modos** do leque, não é jogada fora.
- **Interface é parte do valor:** o gestor precisa ligar/desligar rápido → a **tela de Política por time** sobe cedo (não fica só pra F3).

### 10.2. Modelos (additivos)
- **`distribuicao_policies`** (por time): `account_id, team_id, ativo:bool, modo('rodizio'|'online'|'off'), estrategia('rodizio'), so_online:bool, continuidade_ativa:bool, continuidade_dias:int, pool:jsonb [{user_id, ativo, cap}]`. Tudo editável na UI.
- **`distribuicao_states`**: `team_id → last_user_id` (ponteiro do rodízio).
- **`distribuicao_logs`** (auditoria): `conversation_id, chosen_user_id, motivo('continuidade'|'rodizio'|'sem_pool'), candidatos:jsonb, created_at`.

### 10.3. Serviço `Spx::Distribuicao::DistribuirService.new(conversation).call`
1. `policy = policy_ativa(team_id)` — sem policy → **no-op** (mantém o comportamento atual; opt-in por time).
2. `pool = membros do time ∩ lista ativa` (respeita `cap` se setado; `so_online` só no F2).
3. **Continuidade:** procura o **consultor anterior** do contato (conversas anteriores do mesmo contato, no time, atendidas por alguém do pool, nos últimos `continuidade_dias`). Achou → escolhe ele. `motivo=continuidade`.
4. **Rodízio:** senão, `proximo = pool após last_user_id do state` (round-robin), pulando quem estourou o cap. `motivo=rodizio`.
5. **Atribui:** `AssignmentService` → `assignee_id = escolhido` (limpa o marcador aguardando; **SLA conta daqui**). Atualiza `state` + grava `log`.
6. Pool todo indisponível (cap cheio) → deixa aguardando + alerta gestor (`motivo=sem_pool`).

### 10.4. Gancho
No **handoff** (o `HandoffTool` que já mexemos): depois de setar o time + marcar aguardando, chama `DistribuirService`. Em vez de "soltar na fila", **atribui o consultor**.
- ⚠️ **Decisão de produto:** o Motor **substitui** o aguardando (push direto) — é o que o Guilherme quer. O "aguardando" vira transitório (só existe entre a atribuição e a 1ª resposta) ou some.

### 10.5. Config-first (padrão SPX)
- F1: policy criada via **rake/console** (`Spx::Distribuicao::Policy.create!(team_id:27, pool:[...])`).
- UI "Política de Distribuição" por time = **F3**.

### 10.6. Reuso / riscos
- **Reusa:** `AssignmentService` (atribuição real), `team.members` (pool), o handoff (gancho), `contact.conversations` (continuidade).
- **Risco:** rodízio estrito manda lead pra quem está de folga → mitigar no F1 pelo **pool** (tira da lista) + `cap`; online-gate no F2. Continuidade cross-conversa = query por contato (cuidar de índice/perf).

### 10.7. Como a fila "Aguardando atendimento" funciona hoje (e onde o Motor encaixa — sem quebrar)
**Hoje (pull):** no handoff, o `HandoffTool` **mantém a IA dona** (não solta) + seta o **time** + marca `custom_attributes['aguardando_humano_desde']`. A conversa cai no escopo **`awaiting`** (finder `assignee_type='awaiting'`) → aparece na aba "Aguardando atendimento". Um humano **assume** (atribui a si) → `clear_awaiting_human_marker` limpa o marcador → ele atende (SLA conta de quando **ele** assumiu = o problema). Vale no modo `reply_assignment_gate` (Atribuição obrigatória) ON.
**Com o Motor (push) — um branch no `HandoffTool`, não reescrita:** no handoff, olha a **política do time**:
- `modo=rodizio` → em vez de `awaiting`, chama `DistribuirService` → **atribui o consultor** → SLA conta da atribuição.
- `modo=online` → atribui um agente **online**.
- `modo=off`/sem política → **fluxo atual intacto** (fica em `awaiting`, humano puxa — a fila do dev, sem tocar).
→ A fila do dev **continua** pros times `off`/`online`; o Motor só **intercepta** os `rodizio`. **Zero conflito.**
