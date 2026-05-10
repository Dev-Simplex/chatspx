# Prompt para iniciar em novo chat

Cole o bloco abaixo como **primeira mensagem** num novo chat do Claude Code.

---

```
Você é o orquestrador do redesign 2026 do Copilot do Chat SPX. Trabalho TOTALMENTE AUTÔNOMO — não me pergunte nada, não pause entre fases, execute tudo até terminar. Se travar em algo bloqueante, registre no log e siga adiante com as próximas fases.

📍 CONTEXTO DA MÁQUINA:
- Repo: /home/chatwoot/chatwoot
- Branch atual: homologacao (esta VM 192.168.8.232 INTEIRA é homologação — RAILS_ENV=production é seguro aqui)
- URL teste: https://chatspx.app/app/login
- Restart: sudo systemctl restart chatwoot.target
- NÃO fazer push, NÃO mergear pra producao

📖 PLANO MESTRE (LEIA ANTES DE COMEÇAR):
/home/chatwoot/chatwoot/prompts/copilot-redesign/PLANO-COPILOT-2026.md

Esse arquivo tem:
- 8 fases com código pronto pra colar
- Lista exata de arquivos
- i18n keys novas (pt_BR + en)
- Checklist de validação por fase
- Checklist final de aceite

🚀 EXECUÇÃO

Distribua o trabalho em 4 sprints sequenciais. Para cada sprint, use Agents em paralelo dentro do sprint, mas sprints rodam em sequência.

SPRINT A — Fundação + Visual (Fases 0, 1, 2)
  → Agente A1: Fase 0 (tokens SCSS em _wa-skin.scss) + Fase 1 (CopilotLoader + CaptainLoader + i18n LOADER)
  → Agente A2: Fase 2 (CopilotEmptyState + i18n PANEL_TITLE/PROMPTS)
  Os 2 podem rodar em paralelo (arquivos disjuntos).

SPRINT B — UX Crítico (Fases 3, 4)
  → Agente B1: Fase 3 (Copilot.vue header + i18n STATUS_*)
  → Agente B2: Fase 4 (CopilotMenuBar.vue refactor + i18n SEARCH/QUICK/SUBGROUPS)
  Os 2 podem rodar em paralelo.

SPRINT C — Polish (Fases 5, 6, 7)
  → Agente C1: Fase 5 (CopilotAssistantMessage actions + i18n ACTIONS)
  → Agente C2: Fase 6 (CopilotInput hint+glow) + Fase 7 (CopilotLauncher pulse)
  Paralelo OK.

SPRINT D — Mobile (Fase 8)
  → Agente D1: Fase 8 (CopilotMenuBar bottom sheet)
  Sozinho.

Entre sprints, valide build com:
  cd /home/chatwoot/chatwoot
  RAILS_ENV=production bundle exec rake assets:precompile
  pnpm eslint app/javascript/dashboard/components-next/copilot --fix

Se exit code 0 → próximo sprint.
Se erro → corrija antes de seguir.

📝 INSTRUÇÕES PARA OS AGENTES (passe isso EXATAMENTE pra cada um):

  "Você é um Vue 3/Tailwind dev autônomo trabalhando no Copilot do Chat SPX.
  Repo: /home/chatwoot/chatwoot · Branch: homologacao.
  Sua missão: executar APENAS a fase {X} do plano em
  /home/chatwoot/chatwoot/prompts/copilot-redesign/PLANO-COPILOT-2026.md
  Leia o plano, execute literalmente o que está descrito na sua fase.
  Stack: Vue 3 Composition API <script setup>, Tailwind utility classes,
  Lucide via @egoist/tailwindcss-icons (i-lucide-*).
  Regras:
  - NÃO use scoped CSS, NÃO use inline styles, NÃO escreva CSS custom
    (exceto na FASE 0 que é justamente adicionar keyframes em _wa-skin.scss)
  - Edite apenas os arquivos listados na sua fase
  - Atualize EN E pt_BR i18n quando a fase mencionar i18n
  - Preserve atributos data-ai-tour=*, keyboard nav, prefers-reduced-motion
  - Após terminar: rode pnpm eslint nos arquivos editados, corrija lint warnings
  - Append no log /home/chatwoot/chatwoot/prompts/copilot-redesign/EXECUTION-LOG.md
    com Fase, arquivos, build status, timestamp ISO
  - NÃO commite, NÃO faça push. Apenas working tree.
  - Se algo falhar e for bloqueante, registre no log e retorne resumo do erro.
  Ao final reporte: arquivos alterados, build status, próxima fase pronta."

🏁 ENTREGA FINAL

Quando todas as 8 fases passarem:
1. Rebuild final: cd /home/chatwoot/chatwoot && RAILS_ENV=production bundle exec rake assets:precompile
2. Restart: sudo systemctl restart chatwoot.target
3. Crie /home/chatwoot/chatwoot/prompts/copilot-redesign/FINAL-REPORT.md com:
   - Lista de arquivos alterados (git status)
   - Tempo total de execução
   - Build final exit code
   - Validação manual sugerida (passos pra eu testar em https://chatspx.app)
   - Próximos passos opcionais (Fase 9 sources se backend permitir)

Não me pergunte nada. Execute tudo. Comece AGORA pelo Sprint A.
```

---

## 📦 Estrutura final esperada

Após execução completa, a árvore deve ter:

```
/home/chatwoot/chatwoot/prompts/copilot-redesign/
├── PLANO-COPILOT-2026.md          ← plano completo (já criado)
├── PROMPT-INICIAL.md              ← este arquivo (cola a primeira mensagem)
├── EXECUTION-LOG.md               ← criado pelos agentes durante execução
└── FINAL-REPORT.md                ← criado ao final
```

Arquivos da aplicação modificados (working tree, sem commit):

```
app/javascript/dashboard/assets/scss/_wa-skin.scss                              [Fase 0]
app/javascript/dashboard/components-next/copilot/CopilotLoader.vue              [Fase 1]
app/javascript/dashboard/components/widgets/conversation/copilot/CaptainLoader.vue [Fase 1]
app/javascript/dashboard/components-next/copilot/CopilotEmptyState.vue          [Fase 2]
app/javascript/dashboard/components-next/copilot/Copilot.vue                    [Fase 3]
app/javascript/dashboard/components/widgets/WootWriter/CopilotMenuBar.vue       [Fase 4 + 8]
app/javascript/dashboard/components-next/copilot/CopilotAssistantMessage.vue    [Fase 5]
app/javascript/dashboard/components-next/copilot/CopilotInput.vue               [Fase 6]
app/javascript/dashboard/components-next/copilot/CopilotLauncher.vue            [Fase 7]
app/javascript/dashboard/i18n/locale/pt_BR/conversation.json                    [Fases 1-7]
app/javascript/dashboard/i18n/locale/en/conversation.json                       [Fases 1-7]
```

## ⚠️ Lembretes de uso

1. **Compactação de contexto**: o plano é grande. Se o chat compactar, os agentes ainda têm o `.md` no disco — reler é instantâneo.
2. **Tmux multi-terminal**: você pode rodar cada Sprint em uma sessão `claude --dangerously-skip-permissions` separada se quiser.
3. **Worktree**: pra rodar 100% paralelo, criar worktree pra cada Sprint.
4. **Commits**: NENHUM agente commita. Você revisa o working tree e commita manualmente quando aprovar.
