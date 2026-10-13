# CHAT-177 — Metas e ranking do time

**Responsável:** Nicolas (servidor e tela) · **Repo:** chatspx · **Origem:** Walisson, 30/09/2026
**Fluxo:** implementar na `nicolas` → validar no staging → PR. Conventional Commits, sem citar ferramenta de IA.
`pnpm eslint` / `bundle exec rubocop -a`.

> **Um ponto a confirmar antes do PR:** a task diz *"Base: producao · PR para producao"*, mas a regra do
> projeto é **nicolas → homologacao → producao**, sem PR direto para produção. Este documento assume o
> fluxo do projeto; se for para mirar `producao`, é decisão do Nicolas no momento de abrir o PR.

---

## Em uma frase

O gestor passa a definir **metas mensais** para cada atendente e cada time em quatro indicadores, e o
sistema mostra um **ranking** de quanto cada um atingiu, usando os mesmos números dos relatórios que já
existem.

---

## Índice

1. [O que muda para quem usa](#1-o-que-muda-para-quem-usa)
2. [O que foi verificado no código](#2-o-que-foi-verificado-no-código-leia-antes-de-começar)
   · [2.6 Riscos medidos no banco](#26-riscos-medidos-no-banco-o-que-pode-dar-problema-em-produção)
3. [Decisões fechadas](#3-decisões-fechadas-não-reabrir)
4. [Regras de cálculo](#4-regras-de-cálculo)
5. [Permissão: quem vê e quem define](#5-permissão-quem-vê-e-quem-define)
6. [Banco e API](#6-banco-e-api)
7. [Telas](#7-telas)
8. [Plano de implementação em fases](#8-plano-de-implementação-em-fases)
9. [Testes automatizados](#9-testes-automatizados)
10. [Teste visual obrigatório](#10-teste-visual-obrigatório)
11. [Critérios de aceite](#11-critérios-de-aceite)
12. [Armadilhas](#12-armadilhas)
13. [Fora de escopo](#13-fora-de-escopo)

---

## 1. O que muda para quem usa

**Hoje:** existem 11 relatórios com números, mas nenhum diz *quanto era para fazer* nem *quem está na
frente*. Não há meta nem ranking em lugar nenhum do sistema.

**Depois desta task:**

| Quem | O que passa a poder fazer |
|---|---|
| Administrador / supervisor da conta | Define meta mensal de qualquer atendente e de qualquer time, nos 4 indicadores. Escolhe quem enxerga o ranking. |
| Supervisor de time | Define meta dos atendentes e dos times que supervisiona, e vê o ranking deles com números completos. |
| Atendente | Depende da configuração da conta: não vê nada (padrão), vê só o próprio desempenho, ou vê o ranking com os percentuais dos colegas (sem os números absolutos deles). |

A tela nova fica em **Relatórios → Metas**.

---

## 2. O que foi verificado no código (leia antes de começar)

Tudo abaixo foi conferido no repositório em 30/09/2026. **São os pontos onde a especificação encosta na
realidade do código** — e um deles muda o que a tela precisa dizer.

### 2.1 Os dois builders NÃO contam resolvidas do mesmo jeito ⚠️

Esta é a descoberta que mais importa:

| Builder | Como conta "resolvidas" | Arquivo |
|---|---|---|
| `V2::Reports::AgentSummaryBuilder` | conversas **criadas no período** que estão **resolvidas hoje**, agrupadas pelo **responsável atual** | `app/builders/v2/reports/agent_summary_builder.rb:17` |
| `V2::Reports::TeamSummaryBuilder` | **eventos** `conversation_resolved` **ocorridos no período**, agrupados pelo time da conversa | herda de `base_summary_builder.rb:23` |

São perguntas diferentes: a de agente é "da safra do mês, quantas já foram resolvidas"; a de time é
"quantas resoluções aconteceram no mês". **O total de pessoas não vai bater com o total de times, e isso
não é defeito** — é como os dois relatórios existentes já funcionam hoje.

**O que fazer:** manter cada um como está (a task manda reaproveitar, não recalcular), e escrever isso na
ajuda da tela: *"Pessoas e times usam o mesmo critério dos relatórios de agente e de time; os totais não
somam entre si."* Repetir no PR.

### 2.2 Como chamar os builders

```ruby
V2::Reports::AgentSummaryBuilder.new(account: account, params: { since: inicio.to_i, until: fim.to_i }).build
```

- `DateRangeHelper#range` monta `parse_date_time(since)...parse_date_time(until)` — **intervalo aberto no
  fim** (`...`). Então `until` deve ser **o primeiro instante do mês seguinte**, não `23:59:59` do último
  dia: com `end_of_month` você perde a última fração de segundo.
- `since`/`until` são **epoch em segundos** (`DateTime.strptime(v, '%s')`).
- **Não** passar `business_hours` (a task pede tempo de relógio).
- Retorno: lista de hashes com `id`, `resolved_conversations_count`, `avg_first_response_time` (**segundos**,
  pode vir `nil`), entre outros. Dividir por 60 para minutos.
- O builder de agente devolve **uma linha por `account_user`**, inclusive quem não teve conversa.

### 2.3 NPS

`Reports::NpsCalculator` já existe e tem o cálculo puro:

```ruby
Reports::NpsCalculator.score(promoters:, detractors:, total:)  # inteiro, −100..+100
```

Usar o mesmo recorte do relatório de NPS (`created_at` no mês, `status: :responded`, `score` preenchido,
escopo `.trusted`). **Sem resposta no mês = sem dado**, nunca zero. Vale notar: o `MIN_SAMPLE = 30` do
calculador serve para o selo de confiabilidade dos relatórios — no ranking ele **não** é usado para
esconder o número, só o "sem dado" vale.

### 2.4 Kanban

- `FunnelStage` hoje: `store_accessor :settings, :wip_limit, :sla_hours, :color_rules, :stage_permissions`
  (`app/models/funnel_stage.rb:25`) → acrescentar `:counts_as_won`.
- `funnel_stages_controller.rb:72` permite hoje `settings: [:wip_limit, :sla_hours]` → acrescentar
  `:counts_as_won` (não mexer no resto).
- `funnel_items` tem `conversation_id` (**nulo é permitido** — cartão de tarefa sem conversa), `assignee_id`,
  `moved_at` e `created_at` (`db/schema.rb:1382`). O `COALESCE(moved_at, created_at)` da regra está correto,
  e cartão sem conversa fica fora do ranking de **times** (não tem `team_id`), mas entra no de **pessoas**
  quando tem `assignee_id`.
- O model avisa que **jbuilder e `push_event_data` andam juntos**: quem acrescentar campo na etapa precisa
  atualizar os dois, senão a tela recebe o dado por uma via e não pela outra.

### 2.5 Permissão e rotas

- `ReportPolicy` é só `@account_user.administrator?` e termina com
  `ReportPolicy.prepend_mod_with('ReportPolicy')`; o overlay vive em
  `enterprise/app/policies/enterprise/report_policy.rb`. **Não alterar essa policy** — criar uma própria para
  metas, senão a mudança vaza para os 11 relatórios.
- `reports.routes.js` tem **um `const meta` compartilhado** por quase todas as rotas
  (`permissions: ['administrator', 'report_manage']`). A rota de Metas precisa de um **meta próprio**;
  alterar o compartilhado abriria todos os relatórios para o atendente.
- Última migration em `origin/producao`: `20260929111557`. A nova precisa de timestamp posterior, gerado com
  `date +%Y%m%d%H%M%S`.
- `TeamSupervision` (`app/services/team_supervision.rb`) já tem `team_ids(user, account)` e
  `manageable_agent_ids(user, account)`; `User#supervisor_of_account?(account_id)` também já existe.

---

## 2.6 Riscos medidos no banco (o que pode dar problema em produção)

Estes quatro pontos não estavam na especificação e foram conferidos no código e no staging em 30/09/2026.

### 🔴 Agentes fantasma no ranking — tratar **antes** de ligar a tela

`AgentSummaryBuilder#prepare_report` faz `account.account_users.map`, **sem juntar com `users`**
(`agent_summary_builder.rb:29`). Contas que já apagaram gente ficam com vínculos órfãos, e o builder
devolve uma linha por vínculo.

**Medido no staging agora: 19 dos 40 `account_users` estão sem usuário** — quase metade. O relatório de
agentes já mostra essas linhas hoje (sem nome, tudo zerado); o ranking herdaria o mesmo lixo, e pior:
qualquer `account_user.user.name` sem guarda **estoura 500**.

**O que fazer nesta task:** o serviço do ranking parte de `account.account_users.joins(:user)` (ou de
`account.users`), nunca da associação crua, e nenhum ponto do código dereferencia `.user` sem guarda.
Conferir com `AccountUser.left_joins(:user).where(users: { id: nil }).count` na conta antes de validar —
se o número for alto e o ranking mostrar linhas sem nome, o filtro não foi aplicado.

### 🟡 Metas órfãs quando alguém sai da empresa

`performance_goals` guarda `target_type` + `target_id` **sem chave estrangeira** (é o preço de apontar para
usuário ou time na mesma tabela). Apagar um usuário ou um time deixa a meta apontando para o nada.

**O que fazer:** o ranking e a tela de definir metas listam a partir de usuários/times que existem — meta
sem alvo simplesmente não aparece. Não inventar limpeza automática agora; só garantir que nada quebre.

### 🟡 Carga: é a mesma consulta do relatório de agentes, mas com muito mais gente abrindo

O cálculo roda a cada abertura da tela, sem cache (decisão da task). Hoje quem abre relatório é
administrador; com `goals_visibility: everyone`, **todo atendente passa a disparar o mesmo cálculo**.

Não há índice de `conversations(account_id, created_at)` — a varredura é a que o relatório de agentes já
faz hoje, então não é regressão, mas o volume de chamadas muda. O staging não serve de medida (4 conversas
no mês).

**O que fazer:** medir o tempo da tela na conta grande antes de ligar `everyone` para o time todo. Se
passar de uns 2 segundos, o próximo passo é cache por conta+mês — fora do escopo desta entrega, mas é o
caminho.

### 🟡 É dado sensível sobre pessoas

Ranking com nome e posição de colega é informação delicada. O padrão da task já é o caminho certo
(`managers`, fechado), e o corte acontece no servidor. Vale combinar com o time **antes** de alguém ligar
`everyone`: a mudança é por conta, imediata e reversível.

---

## 3. Decisões fechadas (não reabrir)

| Tema | Decisão |
|---|---|
| Período | Mensal, mês do calendário, no fuso de relatórios da conta |
| Alvo | Meta por atendente **e** por time, com dois rankings independentes |
| Indicadores | Conversas resolvidas, tempo de primeira resposta, NPS, negócios ganhos no Kanban |
| Quem enxerga | Configurável por conta; padrão: só quem gerencia |
| Validade | A meta vale do mês definido em diante, até ser alterada — ninguém redigita todo mês |
| Meses passados | Consultáveis, não editáveis |
| Negócio ganho | Cartão que está numa etapa marcada como ganho e entrou nela no mês |
| Menu | Item "Metas" dentro do grupo "Relatórios" |
| Teste visual | Obrigatório, com prints no PR |

---

## 4. Regras de cálculo

### 4.1 Os quatro indicadores

| Chave | Nome na tela | Unidade | Melhor é | Valor aceito |
|---|---|---|---|---|
| `resolved_conversations` | Conversas resolvidas | quantidade | maior | inteiro > 0 |
| `first_response_time` | Tempo de primeira resposta | minutos | **menor** | número > 0 |
| `nps` | NPS | pontos | maior | inteiro de 1 a 100 |
| `kanban_wins` | Negócios ganhos | quantidade | maior | inteiro > 0 |

### 4.2 De onde vem o realizado

| Indicador | Por atendente | Por time |
|---|---|---|
| Conversas resolvidas | `resolved_conversations_count` do `AgentSummaryBuilder` | mesmo campo do `TeamSummaryBuilder` (**critério diferente**, ver 2.1) |
| Primeira resposta | `avg_first_response_time` ÷ 60 | idem, no builder de time |
| NPS | respostas do mês por `assigned_agent_id` → `NpsCalculator` | as mesmas respostas pelo `team_id` da conversa |
| Negócios ganhos | ver 4.3 | ver 4.3 |

Mês no fuso de `account.reporting_timezone` (vazio → `Time.zone`).

### 4.3 Negócios ganhos

```
ganhos do mês = funnel_items
                que estão numa etapa com counts_as_won = true
                e cujo COALESCE(moved_at, created_at) cai no mês
```

- Atendente: `COALESCE(funnel_items.assignee_id, conversations.assignee_id)`
- Time: `conversations.team_id` (cartão sem conversa ou sem time fica fora do ranking de times)
- **Limitação aceita e declarada na tela:** cartão tirado da etapa deixa de contar. O Kanban não guarda
  histórico de movimentação — só o último `moved_at`.
- Nenhuma etapa marcada na conta → API devolve `kanban_configured: false` e a tela mostra a orientação no
  lugar do número.

### 4.4 Percentual, nota e ordem

**Percentual por indicador:**

- maior é melhor → `realizado ÷ meta` (realizado negativo, caso do NPS, conta como 0)
- menor é melhor → `meta ÷ realizado`
- sem meta **ou** sem dado → o indicador **fica de fora** daquela pessoa no mês. Nunca vira 0%.

**Nota geral da linha:** média simples dos percentuais que entraram, com cada um **limitado a 150% dentro
da média**. Na coluna, o percentual aparece sem limite. O teto existe para um indicador de meta baixa não
esconder os outros.

> Exemplo: meta de 80 resolvidas e 92 feitas → 115%. Meta de 5 min e 4,2 min reais → 5 ÷ 4,2 = 119%.
> Sem resposta de NPS no mês → NPS fora da conta. Nota geral = (115 + 119) ÷ 2 = **117%**.

**Ordem:** nota geral (maior primeiro). Empate: mais conversas resolvidas, depois nome. Quem não tem
nenhuma meta vai para o bloco **"Sem meta definida"**, no fim — visível só para quem gerencia.

### 4.5 Validade da meta

Cada meta gravada tem um **mês de início**. Para um mês qualquer vale a meta mais recente cujo início seja
menor ou igual a ele, para o mesmo alvo e indicador. Valor vazio grava "sem meta deste mês em diante".
Gravar em mês passado responde **422**, e a tela nem oferece.

---

## 5. Permissão: quem vê e quem define

Configuração por conta: `goals_visibility` em `account.settings`.

| Valor | O atendente comum vê |
|---|---|
| `managers` (padrão) | Nada. Continua sem "Relatórios" no menu. |
| `own` | Só o próprio desempenho: realizado, meta e percentual. |
| `everyone` | O próprio desempenho completo + ranking dos times de que participa. Dos colegas: posição, nome, foto e percentuais. **Nunca os números absolutos.** |

| Pessoa | Vê | Define meta | Muda a visibilidade |
|---|---|---|---|
| Administrador | tudo | de todos | sim |
| Supervisor da conta (`supervisor_of_account?`) | tudo | de todos | sim |
| Supervisor de time (`TeamSupervision`) | os times que supervisiona, com números completos | dos atendentes e times que supervisiona | não |
| Atendente | conforme `goals_visibility` | não | não |

`report_manage` dos papéis personalizados **não** dá acesso a metas.

> **O corte é no servidor.** A tela nunca recebe o número do colega que ela não deve mostrar. Conferir isso
> na resposta crua da API, não só na tela.

---

## 6. Banco e API

### 6.1 Tabela `performance_goals`

| Coluna | Tipo | Observação |
|---|---|---|
| `account_id` | referência | obrigatória |
| `month` | date | sempre o dia 1 do mês de início |
| `target_type` | string | `user` ou `team` |
| `target_id` | bigint | id do usuário ou do time |
| `metric` | string | uma das quatro chaves |
| `value` | decimal(10,2), aceita nulo | nulo = sem meta deste mês em diante |

Índice único: `[account_id, month, target_type, target_id, metric]`.

> **Nome:** em código é **`PerformanceGoal`**, nunca `Meta` — neste repositório "Meta" já é o Facebook
> (`meta_catalog_id`, `Meta::LeadAds`, `MetaSyncService`). "Metas" aparece só no texto da tela.

### 6.2 Endpoints (`/api/v1/accounts/:account_id/`)

| Método | Rota | Quem |
|---|---|---|
| GET | `performance_goals?month=AAAA-MM` | quem gerencia |
| PUT | `performance_goals` | quem gerencia |
| PATCH | `performance_goals/visibility` | administrador e supervisor da conta |
| GET | `performance_ranking?month=AAAA-MM&scope=users\|teams&team_id=` | conforme a seção 5 |

**GET performance_goals** devolve as metas **em vigor** no mês (com `since_month`), só dos alvos que quem
chama pode gerenciar.

**PUT performance_goals** grava o lote **numa transação**: um item inválido recusa tudo com 422 dizendo
qual. Alvo fora do alcance → 403.

**GET performance_ranking** devolve:

```json
{
  "month": "2026-10", "scope": "users", "visibility": "everyone",
  "can_manage": false, "kanban_configured": true, "generated_at": "2026-10-14T13:02:11Z",
  "me": { "…igual a uma linha, sempre com números completos" },
  "rows": [
    { "id": 12, "name": "Ana Souza", "avatar_url": "…", "position": 1, "overall": 1.12,
      "metrics": {
        "resolved_conversations": { "actual": 92,   "goal": 80, "attainment": 1.15 },
        "first_response_time":    { "actual": 4.2,  "goal": 5,  "attainment": 1.19 },
        "nps":                    { "actual": null, "goal": 70, "attainment": null },
        "kanban_wins":            { "actual": 3,    "goal": null, "attainment": null }
      } }
  ],
  "without_goal": []
}
```

- `attainment` e `overall` são frações (1.15 = 115%); `first_response_time` em minutos com uma casa.
- Atendente com `everyone`: nas linhas dos colegas, `actual` e `goal` vêm `null`; `without_goal` vem vazio.
- Atendente com `own`: `rows` vazio, só `me` preenchido.
- Atendente com `managers`: **403**.
- `me` vem `null` para quem não tem meta nem dado.

---

## 7. Telas

Vue 3 `<script setup>`, `components-next/`, **só Tailwind** (sem CSS, sem `<style scoped>`), tema claro e
escuro, textos em `en` e `pt_BR`.

### 7.1 Menu

"Metas" entra como item do grupo **Relatórios** (`Sidebar.vue`), e a rota fica em
`reports.routes.js` (`/accounts/:id/reports/goals`, nome `goals_reports`). Item de dentro do grupo não leva
ícone.

O cuidado está na permissão, porque hoje Relatórios é só de administrador:

- A rota de Metas leva **meta próprio** (aceitando também o atendente, mantendo o `featureFlag`).
  **Não alterar o `const meta` compartilhado** pelas outras rotas.
- `/reports` puro redireciona para a Visão geral, que é de administrador — o link do menu do atendente
  aponta **direto** para `goals_reports`.
- O grupo aparece quando **algum** item de dentro é permitido (`SidebarGroup.vue`). Então o atendente vai ver
  "Relatórios" com um item só, "Metas". **É o esperado, não é defeito.**
- `goals_visibility` muda por conta e permissão de rota é fixa: o item entra na lista **condicionalmente**,
  no molde que o `Sidebar.vue` já usa (`...(temRedeSocial.value ? [...] : [])`).
- Quem digitar o endereço sem poder ver recebe **403 do servidor**. O menu só esconde; a trava é do servidor.

> **Conflito de arquivo:** a CHAT-176 (catálogo, Thalysson) também mexe no `Sidebar.vue`. Fazer a menor
> mudança possível nesse arquivo e atualizar a branch antes de abrir o PR.

### 7.2 Tela Metas

- **Topo:** seletor de mês (abre no atual, volta para anteriores) e alternador **Pessoas | Times**; em
  Pessoas, filtro por time.
- **Cartão "Meu desempenho"** quando `me` vier preenchido: os quatro indicadores com realizado, meta, barra
  e nota geral.
- **Ranking:** posição, foto, nome, nota geral e uma coluna por indicador com barra e percentual. Quem
  gerencia vê também "realizado / meta". Os três primeiros com destaque; a linha de quem está logado marcada.
- Indicador sem meta ou sem dado → **"sem meta"** ou **"sem dado"**, nunca 0%.
- Primeira resposta aparece como **"4,2 min (meta 5 min)"**.
- `kanban_configured: false` → no lugar do número, *"Marque uma etapa do Kanban como ganho para este
  indicador funcionar"*, com link para o Kanban (só para quem gerencia).
- Bloco **"Sem meta definida"** no fim, só para quem gerencia.
- Estados: carregando, vazio (*"Nenhuma meta definida para este mês"*, com botão para quem gerencia) e erro.

### 7.3 Definir metas (só quem gerencia)

Botão **"Definir metas"** abre a configuração do mês selecionado (mês atual ou o próximo):

- **Aba Pessoas:** tabela de atendentes, quatro campos por linha, filtro por time e ação **"Aplicar a todos
  do time"** (preenche as linhas visíveis com os valores digitados no cabeçalho).
- **Aba Times:** a mesma tabela, por time.
- Campo vazio = sem meta. Ao lado, em texto pequeno, **"em vigor desde &lt;mês&gt;"** quando a meta vem de um
  mês anterior.
- Um botão **Salvar** para a tela inteira (PUT). Erro do servidor aponta a linha.
- **"Quem enxerga o ranking":** seletor com as três opções e a explicação de cada uma — só para administrador
  e supervisor da conta.
- Supervisor de time só enxerga os atendentes e times que supervisiona.

### 7.4 Kanban

Em `components-next/Kanban/StageForm.vue`: interruptor **"Esta etapa conta como negócio ganho"**, com a
ajuda *"Cards que entram nesta etapa contam nas metas de vendas. Se o card sair da etapa, deixa de contar."*

---

## 8. Plano de implementação em fases

Cada fase fecha com commit próprio (é a regra do projeto: commit ao fim de cada fase, não só no fim).

| Fase | O que entra | Pronto quando |
|---|---|---|
| **F1 — Banco e model** | Migration de `performance_goals`, model `PerformanceGoal` com as validações da 4.1, `month` no dia 1, alvo da mesma conta, e o método de classe que resolve "meta em vigor no mês" (4.5) em uma consulta | spec do model e da resolução por mês passando |
| **F2 — Cálculo puro** | Classe sem banco com percentual nos dois sentidos, teto de 150% na média, indicador fora da conta quando não tem meta/dado, desempate | spec da classe pura passando |
| **F3 — Realizado** | `PerformanceGoals::RankingService`: chama os builders (2.2), NPS (2.3) e a consulta do Kanban (4.3), junta com as metas e aplica a F2 | número bate com o relatório de agentes do mesmo mês, conferido à mão |
| **F4 — Permissão e API** | Ponto único de permissão (quais alvos gerencio, o que posso ver), controllers e rotas da 6.2, corte dos números do colega **no servidor**, `goals_visibility` no `account.rb` | spec de papel × visibilidade passando; resposta crua conferida como atendente |
| **F5 — Kanban** | `counts_as_won` no `store_accessor`, no permit do controller, no jbuilder e no `push_event_data`; interruptor no `StageForm.vue` | marcar etapa, mover cartão e ver o número subir |
| **F6 — Telas** | Rota + item no menu (7.1), tela Metas (7.2), tela Definir metas (7.3), textos `en`/`pt_BR` | checklist visual da seção 10 completo |

Textos de erro em `config/locales/en.yml` e `pt_BR.yml`.

**Desempenho:** o ranking é calculado na hora, com poucas consultas agrupadas por mês. **Sem cache e sem
tabela de resumo** nesta entrega.

---

## 9. Testes automatizados

Spec **só** para:

1. a classe pura de cálculo — percentual nos dois sentidos, teto de 150% na média, indicador sem meta ou sem
   dado fora da média, desempate;
2. a resolução da meta em vigor por mês (4.5);
3. o ranking por papel e por `goals_visibility` — o que cada um recebe e o que é cortado.

> **Não rodar dois `rspec` ao mesmo tempo:** o banco de teste é compartilhado entre sessões. Rodar com um
> banco próprio (`POSTGRES_DATABASE=chatwoot_test_metas`) evita atropelar outra sessão.

---

## 10. Teste visual obrigatório

Rodar teste automático não basta: **abrir a tela e conferir com os próprios olhos**. PR sem os prints não é
aceito. Na VM de desenvolvimento, com **build de produção** — se a mudança não aparecer, o build não foi
refeito.

Um print de cada item, **no tema claro e no escuro**:

- [ ] Menu com "Metas" dentro de "Relatórios" como administrador — item normal e item ativo
- [ ] Ranking de Pessoas com 5+ atendentes, incluindo **um acima de 100%**, **um sem dado de NPS** e **um sem meta**
- [ ] Ranking de Pessoas **sem nenhuma linha sem nome** (o teste dos agentes fantasma — ver 2.6)
- [ ] Ranking de Times
- [ ] Cartão "Meu desempenho"
- [ ] Tela "Definir metas", abas Pessoas e Times, com "Aplicar a todos do time"
- [ ] O seletor "Quem enxerga o ranking"
- [ ] O interruptor "conta como negócio ganho" na etapa do Kanban
- [ ] Como atendente, **uma vez para cada valor** de `goals_visibility`: sem "Relatórios" no menu; com
      "Relatórios" só com "Metas" e só o próprio desempenho; ranking com percentuais dos colegas. Nos três
      casos, **nenhum outro relatório abre**, nem pelo endereço direto
- [ ] Como supervisor de time: só os times dele
- [ ] Mês anterior aberto, **sem** o botão de definir metas
- [ ] Tela estreita (celular): ranking sem quebrar
- [ ] Lado a lado com o relatório de agentes do mesmo mês: conversas resolvidas e tempo de primeira resposta
      **iguais nas duas telas**

---

## 11. Critérios de aceite

1. Definir meta de um atendente em outubro; em novembro a mesma meta continua valendo sem redigitar.
2. Alterar a meta em novembro não muda o que outubro mostra.
3. Gravar meta em mês passado responde **422**, e a tela nem oferece.
4. Conversas resolvidas e tempo de primeira resposta **batem com o relatório de agentes** do mesmo mês.
5. NPS do atendente bate com o relatório de NPS filtrado por ele no mesmo mês.
6. Marcar uma etapa como ganho e mover um cartão para ela **soma 1**; tirar o cartão **subtrai**.
7. Atendente sem resposta de NPS no mês aparece **"sem dado"**, e o NPS não puxa a nota geral dele.
8. Com `managers`, o atendente não vê "Relatórios" no menu e a API responde **403**.
9. Com `own`, a resposta da API para o atendente **não contém dado de nenhum colega**.
10. Com `everyone`, a resposta traz os colegas **sem `actual` e sem `goal`**.
11. Supervisor de time não lê nem grava meta de atendente de outro time (**403**).
12. Só administrador e supervisor da conta mudam "quem enxerga".
13. Ranking de times e de pessoas funcionam de forma independente.
14. Liberar Metas para o atendente **não libera nenhum outro relatório** para ele.
15. O ranking **não mostra linha sem nome**, mesmo em conta com vínculo de usuário apagado (2.6).

---

## 12. Armadilhas

- **Vazamento de número de colega.** O corte é no servidor. Conferir a resposta crua da API como atendente,
  não só a tela.
- **Agentes fantasma** (2.6): partir de `account_users.joins(:user)`. São 19 de 40 no staging hoje.
- **Os dois builders contam diferente** (seção 2.1). Não tente fazer pessoas e times somarem.
- **`until` é exclusivo** no `DateRangeHelper` (`...`): passe o início do mês seguinte, não o fim do último dia.
- **Fuso.** Início e fim do mês no fuso de relatórios da conta — conversa das 23h do último dia tem que cair
  no mês certo.
- **Nome "Meta"** é o Facebook neste repositório. Em código, `PerformanceGoal`.
- **Não recalcular** o que os builders já calculam: número diferente do relatório vira chamado.
- **Não mexer na `ReportPolicy`** nem no `const meta` compartilhado das rotas de relatório — os dois abrem
  acesso aos 11 relatórios de uma vez. Procurar nas duas árvores antes:
  `rg -n "ReportPolicy|TeamSupervision" app enterprise`.
- **Jbuilder e `push_event_data` do Kanban andam juntos** ao acrescentar `counts_as_won`.
- **Migration com segundos reais** (`date +%Y%m%d%H%M%S`), conferindo antes
  `git ls-tree -r --name-only origin/producao db/migrate | sort | tail`.
- **`Sidebar.vue` está sendo mexido pela CHAT-176.** Menor mudança possível e rebase antes do PR.
- **Banco de teste compartilhado:** um `rspec` por vez, com banco próprio.

---

## 13. Fora de escopo

Meta semanal ou diária · meta por caixa de entrada ou por unidade · valor em reais dos negócios (só
quantidade) · histórico de movimentação do Kanban · prêmios, medalhas e pontos · notificação de meta batida ·
exportar o ranking em PDF ou planilha · comissão.
