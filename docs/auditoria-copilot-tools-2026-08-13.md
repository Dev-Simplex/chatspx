# Auditoria dos tools do copilot — quem escreve, e quem escreve sem validar

**Data:** 13/08/2026 · **Base:** `origin/homologacao` (`aaf5f8354b`) · **Continuação do PR #43**

O #43 fechou dois pontos (`assign_conversation`, `get_team_info`) e derrubou a premissa que os
protegia: **não há humano aprovando a chamada**. O `Captain::ChatHelper` registra as tools com
`with_tool` e o `chat.ask` as executa dentro do laço agêntico — o operador está no laço da
**intenção**, não no do **destino**. A prova está nos registros: o `snooze_conversation`, que é
escrita, já rodou **sozinho** em produção. Este documento audita os ~30 tools restantes.

---

## 1. Inventário completo

São **32 tools nativos** registrados em `Captain::Copilot::ChatService::TOOL_CLASSES` — 31 em
`enterprise/app/services/captain/tools/copilot/` mais o `search_documentation`, que é
compartilhado com os agentes. **13 escrevem, 19 leem.**

Além deles, o `build_tools` injeta **todos** os custom tools habilitados da conta
(`account.captain_custom_tools.enabled`) — ver §5.

### 1.1 Tools que ESCREVEM (13)

| Tool | O que faz | Ids que aceita do modelo | Fronteira de conta | Fronteira de acesso |
|---|---|---|---|---|
| `assign_conversation` | atribui agente/time | `conversation_id`, **`agent_id`**, **`team_id`** | ❌ **vulnerável** → PR #43 | ❌ (fica pro #43) |
| `send_message` | envia mensagem ou nota privada | `conversation_id` | ✅ validado | ❌ **corrigido aqui** |
| `send_template` | envia HSM de WhatsApp | `conversation_id`, `template_name` (string) | ✅ validado | ❌ **corrigido aqui** |
| `resolve_conversation` | resolve (dispara CSAT) | `conversation_id` | ✅ validado | ❌ **corrigido aqui** |
| `snooze_conversation` | adia por N horas | `conversation_id` | ✅ validado | ❌ **corrigido aqui** |
| `change_status` | troca o status | `conversation_id` | ✅ validado | ❌ **corrigido aqui** |
| `change_priority` | troca a prioridade | `conversation_id` | ✅ validado | ❌ **corrigido aqui** |
| `add_label` | aplica label | `conversation_id`, `label` (string) | ✅ validado | ❌ **corrigido aqui** (label: ver §4.1) |
| `remove_label` | remove label | `conversation_id`, `label` (string) | ✅ validado | ❌ **corrigido aqui** |
| `set_custom_attributes` | grava atributos | `conversation_id`/`contact_id` | ✅ validado (ambos) | ❌ **corrigido aqui** (ramo conversa) |
| `transfer_to_inbox` | move de caixa | `conversation_id`, **`inbox_id`** | ✅ validado | ❌ conversa **corrigida**; caixa-destino: §4.2 |
| `update_contact` | edita nome/email/telefone | `contact_id` | ✅ validado | não se aplica |
| `add_note_to_contact` | cria nota no contato | `contact_id` | ✅ validado | não se aplica |

### 1.2 Tools que LEEM (19)

| Tool | Ids que aceita do modelo | Fronteira de conta | Fronteira de acesso |
|---|---|---|---|
| `get_conversation` | `conversation_id` | ✅ validado | ❌ **corrigido aqui** |
| `get_conversation_full` | `conversation_id` | ✅ validado | ❌ **corrigido aqui** |
| `get_labels` | — | ✅ validado | ❌ **corrigido aqui** (visibilidade) |
| `search_conversation` | `contact_id`, `status`, `priority`, `labels` | ✅ validado | ✅ já usava o `PermissionFilterService` |
| `get_contact` | `contact_id` | ✅ validado | não se aplica |
| `get_contact_conversations` | `contact_id`, `limit` | ✅ validado | ⚠️ §4.3 |
| `search_contacts` | filtros por texto | ✅ validado | não se aplica |
| `get_article` | `article_id` | ✅ validado | não se aplica |
| `search_articles` | `category_id`, `status`, `query` | ✅ escopado (filtro dentro da conta) | não se aplica |
| `search_messages` | `query`, `limit` | ✅ validado | ⚠️ §4.3 |
| `get_inbox_info` | `inbox_id` | ✅ validado | ⚠️ §4.2 |
| `get_team_info` | — | ✅ (PR #43) | ✅ (PR #43) |
| `get_agents` | — | ✅ validado | não se aplica |
| `get_agent_workload` | — | ✅ validado | não se aplica |
| `get_account_stats` | — | ✅ validado | não se aplica |
| `get_csat_data` | `days` | ✅ validado | não se aplica |
| `get_conversation_analysis` | — | ✅ validado | não se aplica |
| `search_linear_issues` | `term` | ✅ (hook da própria conta) | não se aplica |
| `search_documentation` | `query` | ✅ (`assistant.responses`) | não se aplica |

---

## 2. O achado: a fronteira que faltava não é a de conta

**Fronteira de CONTA: fechada em todos os 31 tools restantes.** Depois do #43, nenhum outro tool
leva um id do modelo direto para uma coluna sem checar a conta. `send_template` resolve o template
pelo canal da própria caixa; `search_articles` filtra `category_id` **dentro** de
`Article.where(account_id:)`; `set_custom_attributes` valida os dois ramos. Zero achados.

**Fronteira de ACESSO: aberta em 13 tools.** Dentro da mesma conta o app tem um segundo limite, e
ele é duro — `Conversations::PermissionFilterService` governa o ConversationFinder, o FilterService
e o `authorize_team_access`, que devolve **403** e some com a conversa da tela. Os tools escapavam
por `account.conversations`, então **o mesmo usuário que toma 403 na tela lia a conversa inteira —
com notas privadas — e escrevia nela pelo copilot.**

O `search_conversation` já chamava o `PermissionFilterService`. Os outros doze não. Uma regra, duas
verdades — exatamente o padrão que o #43 pediu para não repetir.

### Por que os tools de escrita alcançam agente simples

`Captain::Tools::BaseTool#user_has_permission` só consulta o **nome** da permissão quando o usuário
tem custom role. Sem custom role:

```ruby
return account_user.custom_role.permissions.include?(permission) if account_user.custom_role.present?
return account_user.administrator? || account_user.agent?   # <- ignora `permission`
```

Ou seja: para **agente simples, qualquer permissão devolve true** — inclusive
`user_has_permission('administrator')`, que gateia `transfer_to_inbox` e `get_inbox_info`. Todo
agente recebe todos os tools de escrita.

---

## 3. Medição nas três boxes (read-only, `rails runner` em `/tmp`)

### 3.1 Já aconteceu? — fronteira de conta: **zero**, como no #43

| Box | Contas | Conv. com inbox de outra conta | Conv. com contato de outra conta | Notas com contato de outra conta |
|---|---|---|---|---|
| Tozi PROD `3.82.215.109` | 1 (conta 6) | **0** | **0** | **0** |
| SaaS `.232` chatspx.app | 5 (1,3,4,5,7) | **0** | **0** | **0** |
| Fábrica `3.87.182.184` | 2 (1,2) | **0** | **0** | **0** |

### 3.2 Quem escreve sozinho — histograma de tool calls

Tozi PROD, 224 `copilot_messages` (eram 126 no #43):

```
get_contact=60  get_conversation=38  search_conversation=10  search_contacts=8
search_documentation=4  search_messages=4  snooze_conversation=2
```

`.232`: 54 mensagens, só `get_contact_conversations=2`. Fábrica: 0 (copilot nunca usado).
`snooze_conversation` segue sendo a **única escrita** já executada — e sem aprovação.

### 3.3 A fronteira de acesso: população real, medida

**Tozi PROD conta 6** — 7 usuários com a custom role **Corretor**
(`conversation_participating_manage` apenas). Um deles (**Francielli, user 138**) já tem thread de
copilot:

| Usuário | Papel | Alcance permitido | Alcance pelo copilot (antes) |
|---|---|---|---|
| Francielli (138) | agent + Corretor | **217** conversas | **24.206** — a conta inteira |

**111× o que ela pode ver na tela**, com notas privadas incluídas — e o `active?` do
`get_conversation` admite a permissão dela **de propósito**.

**`.232` conta 3** — 6 agentes simples, alcance 437–458 de 606 conversas.
**`.232` conta 5** — user 42 (Erika): alcance **0** de 1.908.
**Fábrica conta 1** — 15+ agentes simples, alcance 7–8 de 9.

Para todos eles, os 10 tools de escrita alcançavam a conta inteira.

### 3.4 Visibilidade de label: latente

| Box | Labels não-`everyone` |
|---|---|
| Tozi PROD | 0 de 23 |
| `.232` (5 contas) | 0 de 7 |
| Fábrica | 0 de 0 |

Nenhuma conta usa `personal`/`team` hoje. O vazamento do `get_labels` é **latente** — o commit
fecha a porta antes de alguém precisar dela.

---

## 4. O que foi medido e **decidido não corrigir**

### 4.1 `add_label` aceita label fora do catálogo — medição desaconselhou fechar

O `label` é string livre e não é validado contra `account.labels`. O reflexo instintivo seria
recusa fechada, como no #43. **A medição disse o contrário:**

Tozi PROD conta 6 — **3.932 taggings órfãs** (label aplicada sem `Label` correspondente na conta):

```
consulto-locação (3701)  nao-avalia (81)  followup-ativo (74)
entrega-segurada (65)    nao-qualificado (5)  prioridade-quente (5)  prioridade-morno (1)
```

Todas nascem de **código SPX** (listeners de follow-up, tratamento de erro da Meta, qualificação de
lead). O produto usa labels fora do catálogo **de propósito**. Recusar no copilot quebraria um fluxo
legítimo: o operador pede "marca como entrega-segurada" e o copilot negaria uma label que o próprio
sistema aplica sozinho. A API humana (`LabelConcern#create` → `update_labels`) também não valida —
fechar só aqui criaria divergência.

Fica registrado como **superfície de alucinação**, não como falha de fronteira. Se for tratado um
dia, o lugar é o catálogo (criar o `Label` junto), não a recusa.

### 4.2 `transfer_to_inbox` e `get_inbox_info`: a caixa-destino

A caixa é validada contra a conta, mas não contra o que **aquele usuário** pode usar. Um agente
simples pode transferir para caixa da qual não é membro (e o `active?` declarado `administrator`
não o barra, por §2). Não foi corrigido aqui porque a checagem exigiria uma **segunda** noção de
"admin da conta" ao lado da que o `PermissionFilterService` já tem — inventar a segunda verdade é
pior que registrar a dívida. O lado da **conversa** está fechado neste PR.

Nota separada, não é fronteira: `transfer_to_inbox` faz `update!(inbox_id:)` sem mexer no
`contact_inbox`, que continua apontando para a caixa antiga. Numa transferência entre canais
diferentes o `source_id` fica incoerente com o canal de envio.

### 4.3 `search_messages` e `get_contact_conversations` não filtram por acesso

Ambos exigem permissão que agente simples tem (§2) e varrem a conta inteira. Não entraram porque a
correção não é o mesmo `find_by` — é reescrever a consulta — e o raio deste PR já é grande. Próximo
alvo natural.

### 4.4 `user_has_permission` ignora o nome da permissão

Causa-raiz de §2. Consertar mudaria o gating de **todos** os tools de uma vez (tools de
`report_manage` sumiriam para agente simples) e o arquivo é upstream, compartilhado com os tools de
agente. Fica como o follow-up de maior valor — e o de maior risco.

---

## 5. Custom tools também vão para o copilot

`build_tools` injeta `account.captain_custom_tools.enabled` — **ignorando a coluna `copilot_only`**,
que existe desde `20260519210000`. Na Fábrica conta 1 são 9 tools habilitados, dos quais **4
escrevem no CRM externo** (`mtm_registrar_cliente`, `mtm_criar_proposta`, `mtm_agendar_visita`,
`mtm_cancelar_proposta`). São escopados por conta, então não é falha de fronteira — mas é escrita
externa disponível ao copilot sem que ninguém tenha decidido isso. Vale uma decisão explícita.

---

## 6. Correções deste PR

| Commit | Natureza | Tools | Raio |
|---|---|---|---|
| 1 | leitura respeita o alcance | `get_conversation`, `get_conversation_full` | menor |
| 2 | escrita respeita o alcance | os 10 de escrita por `conversation_id` | maior — revertível sozinho |
| 3 | visibilidade de label | `get_labels` | nenhum (latente) |

Recusa **fechada**, como no #43: não grava e devolve o motivo. A chamada é a ação inteira, então
recusar é no-op e a string volta pro modelo, que corrige o alvo ou avisa o operador. Distingue
"não existe" de "existe e você não alcança" — recusa sem motivo é indistinguível de alucinação.
Administrador não perde nada: o `PermissionFilterService` devolve o escopo cru para ele.

**Nada de regra nova.** O módulo `Captain::Tools::Copilot::ConversationScope` só chama quem já
decide.
