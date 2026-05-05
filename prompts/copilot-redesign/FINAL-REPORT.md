# Copilot Redesign 2026 — Final Report

**Branch:** `homologacao` · **VM:** 192.168.8.232 (homologação)
**Início:** 2026-05-04T18:17:22Z
**Fim:**    2026-05-04T19:08:00Z (≈ 51 minutos)
**Build final:** `RAILS_ENV=production bundle exec rake assets:precompile` → exit 0
**Restart:** `sudo systemctl restart chatwoot.target` → OK (chatwoot-web.1 e chatwoot-worker.1 active)

---

## Sumário

8 fases concluídas em 4 sprints (A–D), executadas por agentes em paralelo dentro de cada sprint. Build de produção verde após cada sprint. Working tree only — sem commits, sem push, sem merge para `producao`.

| Sprint | Fases | Tempo aprox. | Status |
|--------|------:|:-----------:|:------:|
| A — Fundação + Visual | 0, 1, 2 | ~13 min | ✅ |
| B — UX Crítico | 3, 4 | ~5 min  | ✅ |
| C — Polish | 5, 6, 7 | ~5 min  | ✅ |
| D — Mobile | 8 | ~2 min  | ✅ |

Build/restart e validação final inclusos.

---

## Arquivos alterados (escopo Copilot)

| Arquivo | Stat |
|---------|------|
| `app/javascript/dashboard/assets/scss/_wa-skin.scss` | +tokens AI (Fase 0) |
| `app/javascript/dashboard/components-next/copilot/Copilot.vue` | header customizado (Fase 3) |
| `app/javascript/dashboard/components-next/copilot/CopilotAssistantMessage.vue` | barra de ações copy/👍/👎 (Fase 5) |
| `app/javascript/dashboard/components-next/copilot/CopilotEmptyState.vue` | empty state acolhedor (Fase 2) |
| `app/javascript/dashboard/components-next/copilot/CopilotInput.vue` | input com glow + hint (Fase 6) |
| `app/javascript/dashboard/components-next/copilot/CopilotLauncher.vue` | pulse no launcher (Fase 7) |
| `app/javascript/dashboard/components-next/copilot/CopilotLoader.vue` | sparkles + shimmer (Fase 1.1) |
| `app/javascript/dashboard/components/widgets/WootWriter/CopilotMenuBar.vue` | search + promptbook + chips + bottom sheet (Fases 4 e 8) |
| `app/javascript/dashboard/components/widgets/conversation/copilot/CaptainLoader.vue` | glow no logo Captain (Fase 1.2) |
| `app/javascript/dashboard/i18n/locale/en/integrations.json` | i18n (todas fases) |
| `app/javascript/dashboard/i18n/locale/pt_BR/integrations.json` | i18n (todas fases) |

**Totais:** 11 arquivos · +1965 / -292 linhas (não considerando outros arquivos pré-existentes da branch).

---

## Validação técnica

- ✅ Build `RAILS_ENV=production bundle exec rake assets:precompile` passou (1ª tentativa OOM no Vite, 2ª com `NODE_OPTIONS=--max-old-space-size=8192` OK).
- ✅ ESLint sem novos erros nos arquivos modificados; warnings restantes são `@intlify/vue-i18n/no-dynamic-keys` pré-existentes (estrutura `tooltipKey/labelKey` mantida intencionalmente).
- ✅ JSONs i18n validados com `python3 -m json.tool` (pt_BR + en).
- ✅ Restart aplicado; serviços ativos.

### Pitfall importante (i18n path)

O plano original referenciava `conversation.json`, mas o namespace `CAPTAIN.COPILOT.*` neste fork **vive em `integrations.json`**. Todos os agentes detectaram e ajustaram para o arquivo correto. Mesma observação para `INTEGRATION_SETTINGS.OPEN_AI.REPLY_OPTIONS.*` (Fase 4).

---

## Validação manual sugerida — passos para testar

URL: https://chatspx.app/app/login

### 1. Empty state do painel Copilot
- Abrir uma conversa qualquer e abrir o painel Copilot (botão "Show Copilot" no header).
- **Verificar:** avatar do Captain com glow circular (ai-glow), título "Como posso ajudar você hoje?", 3 cards de prompts verticais com ícone Lucide + label + hint.
- **Hover:** cada card "levanta" 2px e ganha borda verde-marca + sombra leve.
- **Click:** envia o prompt automaticamente.

### 2. Header com identidade
- Avatar 36px com glow + bolinha de status (verde "Pronto pra ajudar" / âmbar pulsante "Pensando…" durante request / cinza "Offline" se timeout).
- Botões à direita (incluindo X) abrem/fecham o painel.

### 3. Loader sparkles + shimmer
- Enviar uma mensagem ao Copilot.
- **Verificar:** ao invés dos 3 dots antigos, aparecem 3 sparkles flutuando (delays escalonados) + 2 barras shimmer (skeleton) + label "Pensando uma boa resposta…".

### 4. Resposta do assistant
- Após resposta chegar, hover na bolha.
- **Verificar:** barra de ações abaixo (copy/👍/👎) ficando mais visível no hover.
- **Click em copy:** toast "Copiado!" via useAlert.
- **Click em 👍 ou 👎:** botão fica colorido. Click novamente desmarca.

### 5. Input convidativo
- Botão de envio acinzentado quando textarea vazio.
- Botão verde com sombra brand quando há texto.
- Hint "Enter para enviar · Shift+Enter para quebrar linha" abaixo do input.

### 6. Dropdown da IA no editor (botão sparkles)
- No editor de respostas, clicar no botão da IA.
- **Verificar:**
  - Search bar no topo filtra ações em tempo real.
  - Promptbook (grid 2x2) com as 4 ações mais usadas (Resumir, Sugerir resposta, Melhorar, Encurtar).
  - Categoria "Reescrever" agora usa **chips inline** agrupados em 3 sub-grupos: Polir / Mudar o tom / Mudar o tamanho.
  - Outras categorias mantêm formato lista.
  - Keyboard nav (↑↓ Enter Esc) funciona.
  - Tour `data-ai-tour="dropdown-first-item"` preservado no primeiro item.

### 7. Editor "Melhorar"
- Selecionar texto no editor → escolher "Melhorar".
- **Verificar:** logo Captain com glow pulsante (sem mais "jumping logo").

### 8. Launcher flutuante (mobile/SaaS)
- Botão flutuante (`CopilotLauncher`) com pulse sutil a cada ~2.4s.
- `prefers-reduced-motion` desabilita as animações (testar via DevTools → Rendering → Emulate CSS media feature).

### 9. Mobile (DevTools 375px)
- Abrir editor → clicar no botão IA.
- **Verificar:** menu sobe de baixo como bottom sheet, com handle visual no topo, cobrindo 80% da altura. Em desktop (≥768px) o comportamento original de dropdown ancorado.

### 10. Dark mode
- Trocar tema → verificar que avatar, cards, header, dropdown, chips, input, launcher continuam legíveis.

---

## Próximos passos opcionais

- **Fase 9 (sources/citations):** se o backend expuser metadados de fonte por mensagem do assistant (URL/título do KB), renderizar uma seção "Fontes" abaixo da bolha. Requer extensão da API antes.
- **Fase 8.2:** swipe-to-close gesture no painel `Copilot.vue` em mobile (atualmente fecha só pelo botão X).
- **Backend de feedback (Fase 5):** persistir o estado 👍/👎 — emitir evento `feedback` ou POST em endpoint dedicado (TODO já comentado em `CopilotAssistantMessage.vue`).
- **Substituir `purple-*` legacy:** algumas classes residuais em outros componentes do Copilot ainda usam tokens roxos. A migração para `n-brand` foi feita nos arquivos das fases 2/3/4; varredura geral é trabalho follow-up.
- **Specs visuais:** os arquivos `*.story.vue` (CopilotLoader.story.vue, Copilot.story.vue, CopilotThinkingGroup.story.vue) podem precisar atualização cosmética para refletir o novo visual no Histoire.

---

## Restrições respeitadas

- ✅ Branch `homologacao` (sem switch).
- ✅ Sem `git push`, sem merge para `producao`.
- ✅ Sem `git reset --hard` ou `git push --force`.
- ✅ Build com `RAILS_ENV=production` (esta VM é homologação).
- ✅ Restart com `sudo systemctl restart chatwoot.target`.
- ✅ Apenas `en.yml`/`en.json` + `pt_BR.json` editados (conforme prioridade i18n do projeto).
- ✅ Working tree only — usuário pode revisar com `git diff` antes de commitar.

---

**FIM. Pronto para testes manuais e commit quando aprovado.**
