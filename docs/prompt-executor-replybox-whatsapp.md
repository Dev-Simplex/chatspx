# Prompt do Executor — ReplyBox WhatsApp-fiel

> **Para:** próximo agente Claude Code (ou @dev) que vai executar o plano
> **Contexto deste prompt:** ChatSPX (fork Chatwoot) projeto da Simplex. Working dir `/home/chatwoot/chatwoot`. Branch `homologacao`. VM 192.168.8.232 = homologação (RAILS_ENV=production seguro). Restart com `sudo systemctl restart chatwoot.target` (NOPASSWD configurado).
> **Plano completo:** `docs/plan-replybox-whatsapp-2026-04-29.md`

---

## Sua missão

Você vai redesenhar o ReplyBox do ChatSPX (`app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue`) para ficar **visualmente o mais idêntico possível ao WhatsApp Web 2025/2026**, mantendo TODAS as features atuais do Chatwoot.

Walisson aprovou TUDO — execute todas as fases A-G + B2 (bubble menu real). Sem MVP, sem fases opcionais — escopo completo.

## Antes de começar

1. Leia `docs/plan-replybox-whatsapp-2026-04-29.md` completo. Ele tem 14 seções com tudo.
2. Leia `app/javascript/dashboard/components/widgets/conversation/ReplyBox.vue` (1908 linhas) e `ReplyTopPanel.vue`.
3. Capture estado atual via Playwright (script template no plano seção 7) pra ter `/tmp/replybox-before-*.png`.
4. Confirme dependências: `pnpm` e `bundle` instalados, `playwright` em `node_modules`.

## Decisões tomadas (todas D1-D8 do plano, padrão recomendado)

- **D1**: Toggle Privada = chip slim amarelo só visível em modo Privada
- **D2**: Copilot ✨ = ícone roxo size-7 no canto direito do input pill
- **D3**: Expand ⛶ = size-7 escondido até hover do composer (`group-hover:opacity-100`)
- **D4**: Send button = verde WhatsApp `#00A884`
- **D5**: SEM feature flag — flip direto, working tree, rollback via git
- **D6**: Anexos = popover com 5 opções (Foto/Vídeo/Áudio/Documento/Contato)
- **D7**: Bubble menu de formatação = implementar real (não só esconder menubar)
- **D8**: Placeholder = "Mensagem" / "Message"

## Ordem de execução (obrigatória nesta sequência)

### 1. Tokens primeiro (~30min)
- Adicionar `--wa-composer-*` em `app/javascript/dashboard/assets/scss/_chat-spx-tokens.scss` (criar se não existir; OU em arquivo de tokens existente — buscar com `rg -l "n-brand|n-solid-1" app/javascript/dashboard/assets/scss/`)
- Mapear tokens em `tailwind.config.js > theme.extend.colors`

### 2. i18n (~30min)
- Adicionar bloco `REPLYBOX` em:
  - `app/javascript/dashboard/i18n/locale/pt_BR/conversation.json`
  - `app/javascript/dashboard/i18n/locale/en/conversation.json`
- Strings exatas estão na seção 6/Fase F do plano

### 3. Fase A — TopPanel (~2h)
- Editar `ReplyTopPanel.vue`: condicionar render a `isOnPrivateNote || copilot.isActive`
- Em modo Privada: renderizar chip slim amarelo (snippet exato no plano)
- Manter botões Copilot/Expand mas mover proseguir conforme C abaixo

### 4. Fase C — Single composer pill (~3h)
- Editar `ReplyBox.vue` template — substituir o `<div class="flex justify-between p-3">` final pelo novo bloco do plano (seção 6/Fase C)
- Adicionar computed `hasMessageContent`
- `class="group"` no `.reply-box` raiz pra `group-hover` funcionar
- `WootMessageEditor` continua dentro, agora dentro do pill central
- Botões Emoji/Plus/Mic/Send seguem snippets exatos do plano

### 5. Fase B1 — esconder menubar (15min)
- CSS scoped em `ReplyBox.vue`:
  ```css
  .reply-box .ProseMirror-menubar-wrapper > .ProseMirror-menubar { display: none !important; }
  ```

### 6. Fase D — popover anexos (~2h)
- Criar `app/javascript/dashboard/components/widgets/conversation/AttachmentPopover.vue` (template no plano)
- Importar e usar em ReplyBox.vue conectando ao botão Plus
- Cada opção dispara `<input type="file" accept=...>` específico (manter componente FileUpload existente)

### 7. Fase E — animações (~1h)
- `<Transition name="composer-action" mode="out-in">` envolvendo mic/send
- `<Transition name="slide-down">` no chip Privada
- `active:scale-95` no send button
- `focus-within:ring-2 ring-wa-composer-send/20` no input pill

### 8. Fase G — responsividade + email (~1h)
- `v-if="!inboxIsEmail"` envolve TODO o novo composer; senão renderiza ReplyBox antigo (preservar via condicional, não deletar código antigo)
- Mobile (`<640px`): reduzir size-9 → size-8, gap-1
- Modo popout: testar mantém funcional

### 9. Fase B2 — bubble menu real (~5h)
- Criar `app/javascript/shared/helpers/editor/bubbleMenuPlugin.js` (esqueleto no plano seção 6/Fase B)
- Criar `app/javascript/dashboard/components/widgets/WootWriter/BubbleMenu.vue` com Teleport pro body
- Integrar plugin em `Editor.vue` (procurar onde EditorState é construído)
- Botões: Bold, Italic, Underline, Strike, Code, Link
- Comandos: `toggleMark(schema.marks.strong)`, etc

### 10. Build, restart, validar (~1.5h)
- `RAILS_ENV=production bundle exec rails assets:precompile` (1-3min)
- `sudo systemctl restart chatwoot.target` (NOPASSWD funciona — retorno vazio é sucesso)
- Validar serviços: `systemctl is-active chatwoot.target chatwoot-web.1.service chatwoot-worker.1.service` → 3x active
- Verificar bundle servido: `curl -sk https://hmlchat.simplexsolucoes.com.br/app | grep -oE 'src="[^"]*dashboard[^"]*"'` retorna hash novo
- Confirmar: `grep -c "wa-composer-send" public/vite/assets/dashboard-*.js` > 0

### 11. Playwright validação (~1h)
- Criar `tmp-replybox-test.js` (template no plano seção 7)
- Login: `sup@simplexsolucoes.com.br` / `Jzs72144#$GSpx`
- Capturar 6+ estados: idle, typing, typing-multiline, private, with-attachment, copilot-active
- Asserções: idle ≤ 80px (target 62)
- Salvar prints em `/tmp/replybox-after-*.png`
- Comparar com prints `/tmp/replybox-current-*.png` (já capturados)

### 12. Cleanup
- `rm tmp-replybox-test.js` e prints temporários
- NÃO commitar — Walisson decidirá quando commitar (junto com P5 read receipts + UI fixes)

## Restrições importantes

- **NÃO COMMITAR** — Walisson revisa antes
- **NÃO REMOVER FEATURES** — só reorganizar visualmente
- **NÃO QUEBRAR EMAIL INBOX** — `v-if="!inboxIsEmail"` preserva layout antigo pra email
- **PRESERVAR keyboard shortcuts** — `Ctrl+Shift+P` toggle privada, `Ctrl+B/I/U` formatação, `/` canned responses
- **Apenas i18n pt-BR + en** — outros idiomas comunidade mantém
- **`sudo systemctl restart chatwoot.target` é OK** — NOPASSWD configurado, mas valida com `systemctl is-active` depois

## Credenciais de teste (hmlchat)

```
URL: https://hmlchat.simplexsolucoes.com.br
Login: sup@simplexsolucoes.com.br
Senha: Jzs72144#$GSpx
```

## Estados a validar visualmente

Cada print deve ser comparado mentalmente com WhatsApp Web. Critérios:

| Estado | WhatsApp tem | ChatSPX deve ter |
|--------|--------------|------------------|
| idle | Composer slim ~62px, fundo `#F0F2F5`, sem chips em cima | igual |
| typing | Mic→Send transition, send circular verde com paper plane | igual + edge case multiline crescer |
| private | (não existe no WhatsApp) | chip amarelo slim acima do composer |
| with-attachment | Thumbs preview acima, X pra remover | igual + composer mantém slim |
| copilot-active | (não existe no WhatsApp) | painel Copilot expand acima do composer |

## Output esperado quando terminar

Mensagem final pra Walisson contendo:
1. Lista de arquivos modificados/criados (paths absolutos)
2. Métricas de altura: idle, typing, multiline, private (em px)
3. Caminhos dos screenshots `/tmp/replybox-after-*.png`
4. Checklist da seção 8 do plano marcado completo
5. Tempo gasto total
6. Issues encontrados que não estavam no plano + como resolveu
7. Pergunta: "Posso commitar P5 + P6 consolidado agora?"

## Em caso de bloqueio

- ProseMirror não aceita o plugin de bubble menu → **fallback B1**: só esconder menubar via CSS, atalhos continuam (deixar B2 pra outro ciclo)
- Token Tailwind não compila → checar `tailwind.config.js > theme.extend.colors` e rodar `pnpm build` localmente pra ver erro
- Email inbox quebra → garantir `v-if="!inboxIsEmail"` em TODOS os pontos novos do template
- Mobile responsivo quebra → ajustar `@media (max-width: 640px)` em scoped style

## Dúvidas para Walisson (esclarecer antes de começar se ele estiver disponível)

Se nada disso ficou claro com o plano, Walisson decide:
1. Se demorar > 18h, parar e reportar
2. Se Email inbox precisa do mesmo tema WhatsApp ou mantém antigo (recomendo manter antigo)
3. Se anexos popover deve fechar ao clicar fora ou só ao selecionar opção
4. Se quiser preview do dropdown anexos antes de implementar (pode mostrar mock estático)

---

**Boa sorte. Plano detalhado, decisões tomadas, screenshots before já capturados em `/tmp/replybox-current-*.png`.**

— Orion (Orchestrator), 2026-04-29
