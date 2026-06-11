# Fase 0 — Evidências de aceite (2026-06-11)

## Resultado: 4/4 PASS (P1 e P2, light + dark)

Playwright 1.59.1 headless (chromium 1440x900), usuário dedicado `playwright-test@simplex.local` (admin, account 1 SimplexIA sandbox), app em produção local (`localhost:3000`) com build contendo o diff da Fase 0. Script: `/tmp/f0-validate.js`.

| Cenário | Tema | Resultado | Validações |
|---|---|---|---|
| P1 sidebar — trocar agente | light | PASS | URL estável (`/conversations/17`), toast "Novo agente atribuído", dropdown atualizado, thread visível |
| P1 sidebar — trocar time | light | PASS | URL estável, toast "Time da conversa alterado", dropdown atualizado |
| P1 sidebar — agente + time | dark | PASS | idem, `body.dark` confirmado visualmente |
| P2 context menu — atribuir time | light | PASS | URL estável (permanece na conversa aberta), toast "Time rh atribuído para o id de conversa 17" |
| P2 context menu — atribuir time | dark | PASS | idem, time "suporte" |

- **Console errors relevantes: zero** nas 4 execuções (sem `pageerror`; filtrados websocket/analytics).
- **Nenhum `router.push` para o dashboard** em nenhum fluxo (usuário admin — guard de perda de acesso corretamente inerte).
- Specs unitários: `conversationAccessHelper.spec.js` — **11/11 passed** (`f0-vitest-output.txt`).
- Observação confirmatória: atribuir time via context menu zerou `assignee_id` no banco quando o agente não era membro do time — comportamento do backend (`ensure_assignee_is_from_team`) que fundamenta a decisão AD-2 (`assigneeId: null` nos guards de troca de time).

## Screenshots
- `f0-p1-sidebar-light-before.png` / `f0-p1-sidebar-light-after-agent.png` / `f0-p1-sidebar-light-after-team.png`
- `f0-p1-sidebar-dark-after-agent.png` / `f0-p1-sidebar-dark-after-team.png`
- `f0-p2-contextmenu-light-menu.png` / `f0-p2-contextmenu-light-after.png` / `f0-p2-contextmenu-dark-after.png`
