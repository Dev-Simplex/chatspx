# Plano de continuação — Encerramento por atribuição (Atribuição obrigatória)

> Feature `resolve_assignment_gate` na branch **nicolas**, working tree (nada commitado).
> Implementação concluída e testada (unit). Falta validação visual/E2E, build e deploy.
> Contexto completo: `task/MONDAY-encerramento-por-atribuicao.md` + memória `resolve-assignment-gate-feature.md`.

---

## Atualização (correção crítica de segurança do gate)
- **Buraco fechado:** `toggle_status` com **status vazio** numa conversa `open` fazia flip p/ `resolved` sem passar pelo guard (burla via API). Agora `ToggleStatusService#resolving?` detecta também o toggle param-less → o gate cobre 100% do endpoint do agente. Specs novos (serviço + controller HTTP) provando a não-burla. ✅
- **Fora de escopo confirmado:** `public/.../inboxes` e `widget` `toggle_status` são do CONTATO (não agente); `ActionService` (automação/macro/bot) faz bypass intencional (R-7). `funnel_items/move_service` resolve ao mover de estágio — **considerar** se deve ser barrado (não está hoje; não listado nas superfícies da task).
- **E2E adicionado:** `spec/e2e/resolve-gate/assign-and-resolve.spec.js` (Playwright, padrão do harness copilot). Cobre 422-fallback, confirma assign→resolve, tema escuro, cancelar, sem i18n vazada. NÃO roda neste host (`@playwright/test` é setup one-time; precisa `E2E_BASE_URL` + app servido).

## Estado atual (✅ pronto)

- **Backend (fonte da verdade):** flag `account.settings.resolve_assignment_gate` (sem migration), guard em `ToggleStatusService` → 422 `resolve_assignment_required` + meta, guard no `BulkActionsJob`, bypass automático p/ automação/macro/bot. i18n en+pt_BR.
- **Frontend:** composable `useResolveAssignmentGate`, modal `AssignAndResolveDialog` (4 variantes), interceptação no cabeçalho/atalho (+fallback 422), menu de contexto e bulk; toggle em Config›Conta. i18n en+pt_BR.
- **Testes unit verdes:** specs Rails (serviço/bulk/controller) + Vitest (composable). Lint/rubocop/prettier limpos.

---

## Fases para retomar

### Fase A — Ligar e fumaça manual (≈30 min)
- [ ] Ligar a flag na conta de homologação (toggle em Config›Conta, OU console: `Account.find(N).update!(settings: Account.find(N).settings.merge('resolve_assignment_gate' => true))`).
- [ ] Smoke local: dono encerra direto; não-dono vê modal; confirmar atribui+encerra.
- [ ] Conferir que com a flag **desligada** o comportamento é idêntico ao atual (modo clássico).

### Fase B — Playwright PR1–PR7 (obrigatório p/ aceite)
Conta 3, usuário de teste dedicado (nunca senha real), tema claro **e** escuro.
- [ ] PR1 — Dono resolve → encerra direto, sem modal
- [ ] PR2 — Não-dono do time → modal "Atribuir a você e encerrar?" → confirma → resolved + assignee = eu
- [ ] PR3 — Conversa de colega → modal "Assumir de {nome}…" → encerra; colega notificado
- [ ] PR4 — Conversa da IA → modal "Assumir da {IA}…" → espelho solto → resolved
- [ ] PR5 — Admin/fora do time → modal mostra os times do usuário → escolhe → atribui+encerra
- [ ] PR6 — Modo clássico (flag off) → encerra direto, sem modal
- [ ] PR7 — DOM walker: sem i18n vazada, ícones ok, contraste ok, 0 erros de console, 2 temas
- [ ] Cobrir as 3 superfícies: botão do cabeçalho, menu de contexto, ações em massa.

### Fase C — E2E / casos de borda (sandbox conta 3)
- [ ] Corrida: 2 agentes resolvem a mesma → o 2º recebe 422 + modal atualizado (testar fallback `rethrow`).
- [ ] Bulk com mix (minhas + de outros) → confirmação única → atribui+encerra todas (R-8).
- [ ] Resolve sem time ainda exige time (modal pede o time dentro do próprio dialog).
- [ ] Variante IA: confirmar que o self-assign solta o espelho (callback de exclusividade).

### Fase D — Notificação do dono anterior (verificar/implementar)
- [ ] Confirmar que reatribuir p/ si dispara `conversation_assignment` (NotificationService) ao dono anterior. Se não disparar pelo caminho do modal, completar. (PR3 valida isso.)

### Fase E — Build + Deploy
> NÃO fazer do host `nicolas` (pull-only). Disparar do orquestrador 192.168.8.229.
- [ ] `bundle exec rspec` (suíte relevante) no CI/orquestrador.
- [ ] Build vite: `assets:precompile` (zero-downtime) + `sudo /bin/systemctl restart chatwoot.target`.
- [ ] **Sem migration** (flag é JSONB) — não esquecer que NÃO precisa migrar DB.
- [ ] Commit só após validação (regra da task: nada vai pra cliente sem validar).

---

## Checklist de aceite (da task)
- [ ] Specs Rails + Vitest passando (✅ unit; falta rodar no CI)
- [ ] Playwright claro+escuro (Fase B)
- [ ] E2E sandbox (Fase C)
- [ ] Validado em homologação antes de cliente

---

## Riscos / pontos de atenção
- **Acoplamento futuro:** hoje é flag/modal separados do (inexistente) gate de resposta. Se a Fase D do plano IA for feita, unificar `resolve_assignment_gate` + reply gate numa só chave.
- **Variante IA (R-9):** depende do callback de exclusividade do espelho (enterprise/captain). Validar de verdade no PR4.
- **Bulk team-required:** se conversas sem time e usuário em vários times, o dialog pede o time; conferir que o `team_id` é aplicado só nas sem time antes do resolve.
- **Falhas pré-existentes (não nossas):** `markMessagesRead` em actions.spec e testes de status `pending` em inbox simples — ignorar, não regridem por nossa causa.

---

## Arquivos tocados (referência rápida)
**Backend:** `app/models/account.rb`, `app/controllers/api/v1/accounts_controller.rb`, `app/services/conversations/toggle_status_service.rb`, `app/controllers/api/v1/accounts/conversations_controller.rb`, `app/jobs/bulk_actions_job.rb`, `config/locales/{en,pt_BR}.yml`
**Frontend:** `composables/useResolveAssignmentGate.js`, `composables/useResolveValidation.js`, `composables/chatlist/useBulkActions.js`, `components-next/Conversation/AssignAndResolveDialog.vue`, `components/buttons/ResolveAction.vue`, `components/ChatList.vue`, `store/modules/conversations/actions.js`, `routes/.../account/components/AttendanceModeToggle.vue` (+ `Index.vue`), i18n `conversation.json`/`generalSettings.json` (en+pt_BR)
**Specs:** `spec/services/conversations/toggle_status_service_spec.rb`, `spec/jobs/bulk_actions_job_spec.rb`, `spec/controllers/.../conversations_controller_spec.rb`, `composables/spec/useResolveAssignmentGate.spec.js`, `composables/chatlist/spec/useBulkActions.spec.js`
