# Tarefa A — fundação (dados + API) · contrato para as tarefas B e C

Commit: `8aec9690c` · migration `20260819120000` aplicada no staging (nicolas), reversível
(migrate → rollback → migrate verificados).

## Tabela

`inbox_isolation_exemptions` — quem **escapa** da regra (espelha `team_supervisors`).

| coluna | tipo |
|---|---|
| `inbox_id` | bigint, null: false, FK inboxes ON DELETE CASCADE |
| `user_id` | bigint, null: false, FK users ON DELETE CASCADE |
| `isolation_type` | string, null: false — `'agent_message'` \| `'team_message'` |

Índices: único em `[inbox_id, user_id, isolation_type]`
(`index_inbox_isolation_exemptions_on_inbox_user_type`) e em `user_id`.

## Model — `InboxIsolationExemption`

- `ISOLATION_TYPES = %w[agent_message team_message]`
- `scope :for_type` · unicidade `user_id` no escopo `[inbox_id, isolation_type]`
- valida que o usuário pertence à conta da caixa
- `Inbox has_many :inbox_isolation_exemptions, dependent: :destroy` (idem em `User`)
- `InboxMember after_destroy` limpa as isenções: sair da caixa **ou da conta**
  (o `Agents::DestroyJob` destrói os `inbox_members`) leva a isenção junto — sem isso uma
  readmissão devolveria a isenção em silêncio.

## O que a TAREFA B (leitura) precisa saber

O ponto de checagem é uma consulta direta, sem serviço novo:

```ruby
InboxIsolationExemption.exists?(inbox_id: inbox.id, user_id: user.id, isolation_type: 'agent_message')
```

Sugestão (spec manda pôr no `AgentMessageIsolation#restriction_id_for_inbox`, junto dos
dois `return nil` que já existem para admin e supervisor). O filtro de time
(`conversation.rb:155`) usa `'team_message'`. **Lista vazia = regra antiga intacta.**

## O que a TAREFA C (UI) precisa saber

`GET/PATCH /api/v1/accounts/:id/inboxes/:id` (e o `index`) devolvem, no payload da caixa:

```json
"agent_message_isolation_participant_ids": [12, 34],
"team_message_isolation_participant_ids":  [12, 34]
```

São **participantes** (derivados: membros não-admin da caixa **menos** as exceções). Numa
caixa sem exceção vêm todos → todo mundo nasce marcado, que é o critério de aceite 2.

Para salvar, mande no mesmo `updateInbox` as mesmas chaves com os ids **marcados**:

```json
PATCH { "agent_message_isolation_participant_ids": [12] }
```

Regras do submit:

- **chave ausente = não mexe em nada.** Um update de nome/horário não isenta ninguém.
- lista vazia `[]` é válida: isenta todos os agentes daquela caixa.
- administrador nunca vira exceção (ele já é isento) e id de quem não é membro é ignorado.
- os dois isolamentos são independentes: mandar um não toca no outro.

## Specs

- `spec/models/inbox_isolation_exemption_spec.rb` — 16 exemplos (unicidade na tripla,
  `dependent: :destroy` por user/inbox/inbox_member, FK cascade, listas derivadas).
- `spec/controllers/api/v1/accounts/inboxes_controller_spec.rb` — 7 exemplos novos
  (conversão participantes→exceções, remarcar, chave ausente, admin, id de não-membro).

Rodam limpos. As 2 falhas do `inboxes_controller_spec` (linhas 317 e 381) são
**pré-existentes**: mensagem de exclusão traduzida para pt-BR e `website_url: 'test.com'`
reprovado no formato `uri` do swagger — nenhuma das duas toca isolamento.

`rubocop` limpo nos 11 arquivos tocados.
