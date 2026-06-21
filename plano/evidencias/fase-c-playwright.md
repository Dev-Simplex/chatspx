# Fase C — Validação Playwright (conta 3, light + dark) — 2026-06-12

Usuário de teste dedicado `playwright-test@simplex.local` (admin conta 3). Flag
`reply_assignment_gate` LIGADA na conta 3 → features novas ativas. Read-only (nenhuma
mensagem/atribuição alterada — verificado: zero vazamento na conversa real).

## Telas validadas (screenshots em plano/evidencias/)
| Cenário (§5.2) | Evidência | Resultado |
|---|---|---|
| P5 — tabs Minhas/IA/Todas | `c-pw-tabs-lista-{light,dark}.png` | **Minhas 0 / IA 1 / Todas 59**; "Não atribuídas" ausente (0 órfãs com gate ON, DC-4); ícone bot na tab IA; dark OK |
| P3/C1 — seção "Agentes IA" | `c-pw-secao-agentes-ia-{light,dark}.png` | Rafa/Marina/Letícia/Bruna com **badge "Agente IA"** + descrição + "Caixas de entrada elegíveis: SimplexIA"; read-only; light+dark paridade |
| P6/C3 — badge IA no card | `c-pw-tab-ia-cards-{light,dark}.png` | conversa de Paulo Seze com **badge "IA" + "Clara"** (a IA dona); listada na tab IA |
| **P10/D2 — dialog de assunção (variante d)** | `d-pw-dialog-gate-{light,dark}.png` | **gate ao vivo**: "Você não faz parte deste time. A conversa pertence ao time locação. Escolha um dos seus times" + card "Clara — Agente IA" + Cancelar/Atribuir e enviar. Draft intacto, **nada enviado** (interceptou antes; cancelado). Dark+light OK |
| P4/C2 — seletor "Agente IA" no sidebar | (visível no fundo de `d-pw-dialog-gate-*`) | sidebar admin mostra "Agente de IA: Clara" + "Time: locação" |

## Observações
- Tokens de cor corretos nos 2 temas; sem i18n leak (strings pt_BR renderizadas); o `:` de "Caixas de entrada elegíveis:" (fix do reSettings) visível.
- Timing: as tabs levam ~3-5s pós-load para assentar (fetch de assistants + flag) — a 1ª screenshot a 2.5s pegou o estado Clássico transitório (falso alarme, resolvido com espera maior).
- Único erro de console: `404 /enterprise/api/v1/accounts/3/limits` (endpoint de billing pré-existente, sem relação com a Fase C).

## Pendente (não-bloqueante, verificação manual ou Playwright com selector melhor)
- **Dialog de assunção ao vivo**: ✅ CAPTURADO (variante d — fora do time). Faltam só as variantes (a)/(b)/(c) isoladas, que exigem montar conversas em estados específicos — cobertas por 8 vitest.
- **Seletor "Agente IA" no sidebar (P4)**: admin-only; visível ao abrir conversa (não capturado isolado).
