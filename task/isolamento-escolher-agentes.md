# Escolher quais agentes participam de cada isolamento

**Nível:** pleno · **Risco:** médio — mexe em regra de visibilidade, que erra para o lado de vazar
**Onde validar:** staging antes da frota

---

## Por que esta task existe

Hoje os dois isolamentos são **tudo ou nada por caixa de entrada**. Ligou o de agente, todo agente
não-admin passa a ver só as próprias mensagens. Ligou o de time, todo mundo fica preso ao próprio
time.

Na prática sempre aparece a exceção: o coordenador que precisa enxergar tudo, o backoffice que
confere pedidos, quem cobre o plantão. Hoje só existem duas saídas, e as duas são ruins: **tornar a
pessoa administradora** (que dá poder demais — ela passa a mexer em caixas, agentes e faturamento)
ou **desligar o isolamento inteiro** (e perder a proteção para todo mundo).

## O que fazer

Em cada um dos dois cards de isolamento, quando o toggle está ligado, mostrar a lista de agentes da
caixa com caixinhas de seleção — a mesma que já existe para escolher os agentes de um time.
Desmarcar um agente tira ele do isolamento: ele volta a ver tudo naquela caixa.

## A decisão de modelagem que evita o acidente

> **A tela mostra PARTICIPANTES; o banco guarda EXCEÇÕES.**

Todos nascem marcados, e a lista salva é a dos **desmarcados**. Parece detalhe, mas é o que separa
uma entrega segura de um vazamento:

- Lista vazia = exatamente o comportamento de hoje. A migração entra **inerte**, sem mudar nada em
  quem já usa isolamento.
- Se guardássemos participantes, uma caixa já existente entraria com a lista vazia e o isolamento
  simplesmente **deixaria de valer** no deploy — silenciosamente, sem ninguém perceber.
- Só que ninguém raciocina em "exceção" ao configurar. Por isso a tela fala a língua do time
  ("estes agentes participam"), e a conversão para exceção acontece no submit.

## Onde mexer

| Arquivo | O quê |
|---|---|
| `db/migrate/` (nova) | Tabela `inbox_isolation_exemptions`: `inbox_id`, `user_id`, `isolation_type` (`agent_message` \| `team_message`), índice único na tripla. Espelha `team_supervisors` (`db/schema.rb:2019`), que já é o padrão da casa para "quem escapa da regra" |
| `app/models/inbox_isolation_exemption.rb` (novo) | Model + `Inbox has_many ..., dependent: :destroy` e o mesmo em `User` — agente removido da conta some da lista sozinho |
| `app/services/agent_message_isolation.rb` | **O ponto que resolve o isolamento por agente inteiro.** Um `return nil if exempt?(user, inbox)` dentro de `restriction_id_for_inbox` cobre de uma vez MessageFinder, preview da lista, histórico do contato e busca. Repare que o arquivo já faz isso duas vezes: para admin e para supervisor de time |
| `app/models/conversation.rb:155` | **O ponto difícil.** O filtro de time mora na association `has_many :messages`, que não sabe quem está olhando. Ler `Current.user` ali, com guarda: `Current.user` nulo (job, API pública, widget) mantém o filtro de hoje |
| `app/controllers/api/v1/accounts/inboxes_controller.rb:216` | `inbox_attributes` ganha `{ agent_message_isolation_participant_ids: [] }` e `{ team_message_isolation_participant_ids: [] }`; o controller converte participantes → exceções |
| `app/views/api/v1/models/_inbox.json.jbuilder:23` | Expor as duas listas de participantes (derivadas: agentes da caixa menos as exceções) |
| `app/javascript/dashboard/routes/dashboard/settings/inbox/Settings.vue:807` | O bloco de UI dentro de cada card, visível só com o toggle ligado; entra no mesmo `updateInbox` que já salva as flags (linha 531) |
| `app/javascript/dashboard/routes/dashboard/settings/teams/AgentSelector.vue` | **Reusar, não recriar.** Já tem tabela, avatar, contador e "selecionar todos" |
| `i18n/locale/en/inboxMgmt.json` | Só o `en.json` — as outras línguas são da comunidade |

## Critério de aceite

1. Toggle desligado: nenhuma lista aparece, nada muda no comportamento atual.
2. Toggle ligado pela primeira vez numa caixa existente: **todos** os agentes aparecem marcados e o
   isolamento se comporta exatamente como hoje.
3. Desmarcar um agente e salvar: ele passa a ver as mensagens dos outros naquela caixa — na lista de
   conversas, na conversa aberta, no histórico do contato **e na busca**. Os demais seguem isolados.
4. Remarcar devolve o isolamento para ele.
5. Vale para os dois isolamentos, de forma independente: dá para isentar alguém só do de time.
6. O agente isento **não** ganha nada além de leitura — nenhum poder de admin.
7. Tirar o agente da conta remove a exceção junto (sem lixo apontando para usuário morto).
8. Recarregar a página traz as marcações salvas.
9. Specs cobrindo: exceção lê o que era escondido, não-exceção continua sem ver, lista vazia = regra
   antiga intacta, e um job (sem `Current.user`) mantém o filtro de time.
10. `rubocop` e `eslint` limpos nos arquivos tocados.

## Pegadinhas conhecidas

- **Administrador nunca entra na lista.** Ele já é isento nas duas regras; mostrá-lo com caixinha
  sugere que dá para isolar um admin, o que não é verdade. Deixe fora da tabela, com uma linha de
  texto explicando.
- **Supervisor de time também já é isento** (`TeamSupervision`). Não recrie essa regra aqui, e não
  a remova: são dois mecanismos diferentes que convivem.
- **O isolamento por agente é reaplicado em quatro pontos de leitura** — `conversation_finder`,
  `list_preloader`, `search_service` e o `MessageFinder`. Mexer direto neles em vez de no
  `AgentMessageIsolation` garante esquecer um (a busca é o que mais escapa).
- **O filtro de time não conhece o viewer.** É por isso que ele vive numa association e o de agente
  não. Se usar `Current.user` lá, teste explicitamente o caminho de job: `Current.user` nulo tem de
  manter o filtro, senão um job de relatório passa a enxergar mensagem de outro time.
- **Mensagens antigas podem ter `agent_id`/`team_id` nulos.** O backfill continua sendo pré-requisito
  para ligar o isolamento numa caixa com histórico — a exceção por agente não muda isso.
- O hook do `husky` quebra em worktree: `git commit --no-verify` se travar.

## Fora de escopo

- O terceiro toggle (**isolamento de conversa por agente**) — mesma ideia, mas outra regra e outra
  tela de bloqueio; vale uma task própria depois desta.
- Mudar o que administrador enxerga.
- Exceção por time inteiro ("time X não participa") — se aparecer a necessidade, é outra modelagem.
