# Fase A — Evidências de aceite (2026-06-11)

## Mapeamento aceite §4 Fase A → specs (todos verdes)

Conjunto de aceite: **143 examples, 1 falha** (a única é `conversation_spec.rb:17` SLA/avatar, bug pré-existente do fork — jobs avatar idênticos ao HEAD).

| Bullet do aceite §4 | Spec que comprova |
|---|---|
| conversa sem atribuição → IA muda | `hook_execution_service_spec` "no owner (eligible inbox)" → nenhum ResponseBuilderJob |
| atribuir IA-1 (admin) → responde | `hook_execution_service_spec` "assistant whose mirror owns" → ResponseBuilderJob com IA-1 |
| atribuir IA-2 → IA-2 responde, IA-1 cala | `hook_execution_service_spec` "second assistant when its mirror owns" → ResponseBuilderJob com IA-2 |
| atribuir humano → IA cala (callback) | `hook_execution_service_spec` "assigned to a human" + "webhook agent bot" → silêncio |
| debounce em voo após troca de dono → descartado | `response_builder_job_spec` (re-check pré-LLM/pré-envio/por-chunk) + `debounced_response_job_spec` (early-return por dono) |
| agente comum atribuir IA via API → 403 | `assignments_controller_spec` (guard A7: admin 200, agente 403, AgentBot-token 403) |
| exclusividade bot×humano preservada | `conversation_spec` (invariante nos 4 fluxos de auto-assignment) |
| handoff IA→corretor (E2E #8): IA cala + corretor atribuído | `handoff_tool_spec` "mirror handoff" (fix do blocker do review) |
| sync do espelho (create/rename/destroy) | `assistant_mirror_service_spec` + `captain_inbox_spec` (uniqueness composta) |

## Boot e suíte integrada
- **Boot OK**: rails runner carrega tudo (12 espelhos captain, has_many, AssignmentKickJob, callbacks).
- App reiniciado em produção (homolog), HTTP 200.
- Suíte integrada completa (20 spec files): **331 examples, 3 falhas** — todas pré-existentes do fork (2× lifecycle `captain_activity_reason` no resolution_job + 1× SLA/avatar arity); ver `fase-a-suite-integrada.txt`.

## Review adversarial (5 lentes)
4 lentes ready ✓; 1 BLOCKER encontrado e corrigido (guard A2b quebrava handoff IA→humano — `HandoffTool` agora solta o espelho antes de atribuir, padrão do handoff de cota). Achados menores adiados documentados no relatório final.

## Validação E2E que falta (go-live, NÃO autônoma)
O roteiro §5.3 (16 testes na sandbox SimplexIA) exige respostas REAIS do LLM (API keys). É validação de go-live na sandbox, fora do escopo autônomo. Os specs acima provam mecanicamente as DECISÕES do gate; a geração de texto do LLM é o que falta exercitar ao vivo.
