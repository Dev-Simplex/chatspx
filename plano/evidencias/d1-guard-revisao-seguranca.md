# D1 — Guard de resposta (422 assignment_required) — Revisão de segurança (2026-06-12)

## Implementação (working tree, NÃO commitada)
- `messages_controller.rb`: `before_action :enforce_reply_assignment_gate, only: [:create, :share_location, :share_contact]`.
- `conversations_controller.rb`: `self_assign_creator_for_reply_gate` na criação de conversa com mensagem (OQ-D1).

## Auditoria — OK
- **Ordem de carregamento**: `@conversation` é carregado pelo `before_action :conversation` do `base_controller` (pai), que roda ANTES do guard (filho). Sem risco de 500 por nil.
- **Gating pela flag**: `Current.account.reply_assignment_gate_enabled?` → OFF = no-op total (modo Clássico intacto, D-13).
- **Bypasses corretos**: nota privada (`params[:private]=='true'`), bot-token/nil (`!user.is_a?(User)`), echo WAHA (`source_id` presente), incoming via API, e o próprio assignee.
- **422 estruturado**: `error_code: assignment_required` + `meta.current_assignee {id,name,type}` (type via `conversation.assignee_type` = 'AgentBot' quando dono é IA) + `meta.team`. Mantém a chave `error` legada para o alert antigo.
- **i18n** pt_BR + en presentes.
- **Cobertura**: 7 specs novos em `messages_controller_spec.rb` (não-assignee 422 + meta, assignee passa, nota privada bypass, source_id bypass, incoming bypass, dono-IA no meta, modo Clássico inerte). Verdes.

## ⚠️ PONTOS PARA REVISÃO MANUAL (decisão de produto/segurança)
1. **Bypass via `source_id`**: um agente autenticado pode incluir `source_id` na requisição para furar o gate (o dashboard nunca envia, mas a API aceita). É o discriminador acordado do echo WAHA (OQ-D3 sancionada — echoes inevitavelmente não passam pelo gate). O gate é uma disciplina de workflow atrás de flag por conta, não uma fronteira de segurança rígida. Avaliar se vale endurecer (ex.: só bypassar `source_id` quando o sender for o bot da ponte WAHA / user id específico).
2. **`share_location`/`share_contact`** entram no guard pela mesma before_action, mas não têm spec dedicado (mesma lógica do create — baixo risco). Adicionar 1 spec se quiser cobertura explícita.
3. **incoming de agente já 500 no fork** (pré-existente, sem relação com o gate) — o bypass do gate está correto; o 500 downstream é dívida antiga.
