# Plano Técnico — Refactor WhatsApp-fiel ChatSPX

**Autor:** @architect (Aria) · **Branch:** `homologacao` · **Data:** 2026-04-18
**Escopo:** alinhar UI do ChatSPX ao visual WhatsApp Web sem regressões em produção.

---

## 1. Estado atual — diagnóstico técnico

**Camadas já WA-nativas:**
- **Tokens globais** (`_next-colors.scss`, 322 linhas): paleta WA (`#00a884`, `#111b21`, `#202c33`) propagada via CSS custom properties. Cobre `--color-woot`, `--n-slate-*`, `--n-solid-*`, `--n-background-*`. Impacto automático em **~80% dos componentes** que consomem `bg-n-*` / `text-n-*` via Tailwind.
- **Skin overrides** (`_wa-skin.scss`, 1745 linhas): ajustes pontuais em Sidebar, Tabs, Select, ConversationCard, Header, ReplyBox, menus pop-up, scrollbars, estados hover/active. Dark mode coberto.
- **Rail lateral** (`Sidebar.vue`): reduzido a 72px fixo, ícones centralizados, badge contadora, profile menu inferior.
- **Enterprise overlay (`enterprise/`):** **não contém `app/javascript/`** — é 100% Ruby (builders, controllers, services, models). **Risco visual com Enterprise = zero.**

**Camadas com risco/hardcode residual:**
- `components-next/copilot/*` e `components-next/captain/*`: usam cores antigas (`bg-n-solid-blue`, `text-n-brand`) — 8 arquivos detectados.
- `components/widgets/conversation/MessagesView.vue` e `ReplyBox.vue` ainda têm classes legacy fora do skin.
- Editor ProseMirror (`WootWriter`) herda tokens mas tem scoped CSS residual (toolbar, menção, emoji).
- `i18n/locale/pt_BR/settings.json` dirty — validar antes de merge.
- Avatar/Thumbnail components e charts (dashboard reports) ainda com paleta antiga.

**Pontos de atrito com Enterprise overlay:** apenas backend (`SlaPolicy`, `Captain::*Service`, helpers). Nenhum CSS/Vue. Overlay não afeta visual.

---

## 2. Riscos — top 8

| # | Risco | Sev | Mitigação |
|---|---|---|---|
| 1 | Paleta verde WA ferindo contraste em telas Captain/Copilot (ainda usam azul hardcoded) | 🔴 | `rg "bg-n-solid-blue\|text-n-brand" app/javascript` — override dos 8 arquivos no `_wa-skin.scss` ou refactor inline |
| 2 | `_wa-skin.scss` com 1745 linhas vira monolito difícil de revisar | 🟡 | Particionar em `_wa-skin/_sidebar.scss`, `_wa-skin/_conversation.scss`, `_wa-skin/_reply.scss` via `@use` |
| 3 | Tokens alterados propagam em telas admin/reports não revisadas (settings, integrations) | 🟡 | Walk-through visual em todas rotas `/app/accounts/:id/settings/*` antes de merge |
| 4 | Dark mode WA (`#0b141a`) pode quebrar em temas custom já ativos em contas reais | 🟡 | Testar com conta produção clonada; manter fallback se `--color-background-light` setado |
| 5 | Editor ProseMirror (Tiptap) usa CSS interno que ignora tokens | 🟢 | Override `.ProseMirror` em `_wa-skin.scss` — já parcialmente feito |
| 6 | Charts (Chartkick/Chart.js) em dashboard/reports com cores fixas no JS | 🟡 | Expor tokens via `getComputedStyle(document.documentElement)` no chart config |
| 7 | CSS cache no browser dos clientes (Cloudflare/asset digest) após deploy | 🟢 | Rails já faz fingerprint em `assets:precompile`; comunicar usuários para Ctrl+F5 |
| 8 | Merge `homologacao → producao` pode trazer arquivos dirty não relacionados (`_woot.scss`, `i18n/*`) | 🔴 | `git diff --stat producao..homologacao` e cherry-pick apenas arquivos do refactor |

---

## 3. Roadmap técnico

| Prio | Frente | Escopo | Tempo | Arquivos-chave |
|---|---|---|---|---|
| P0 | Tokens WA globais | feito | 0h | `_next-colors.scss` |
| P0 | Rail lateral 72px | feito | 0h | `Sidebar.vue`, `SidebarProfileMenu.vue` |
| P0 | Skin WA (tabs, select, cards, header) | feito | 0h | `_wa-skin.scss` |
| P0 | ConversationCard pin/status | feito | 0h | `ConversationCard.vue` |
| P0 | Particionar `_wa-skin.scss` em módulos | refactor organizacional | 1h | 5 partials novos |
| P0 | Auditar Captain/Copilot (remover azul) | substituir `bg-n-solid-blue` | 1h | 8 arquivos components-next |
| P1 | Quick Reply Chips | componente novo sobre ReplyBox | 1h | `ReplyBox.vue` + `QuickReplyChips.vue` |
| P1 | Pin de conversas | store + UI + badge | 2h | `conversation` store, `ConversationCard.vue` |
| P1 | Atalho Cmd+K (paleta de comandos) | overlay global | 1h | novo `CommandPalette.vue` |
| P1 | Scrollbar WA-fiel (4px verde) | override global | 15min | `_wa-skin.scss` |
| P1 | Avatar ring ativo | border verde em online | 30min | `Avatar.vue` / `Thumbnail.vue` |
| P1 | Editor — toolbar WA | bubble flutuante em seleção | 2h | `WootWriter/Editor.vue` |
| P1 | Charts usando tokens | leitura dinâmica via `getComputedStyle` | 1h | `widgets/Chart/*` |
| P2 | Copilot drawer lateral (Cmd+J) | migrar do inline pra drawer | 4h | `components-next/copilot/*` |
| P2 | Multi-view (conversas + contatos em split) | layout novo opcional | 6h | rota `dashboard/conversation` |
| P2 | Status bubble (WhatsApp stories) | novo feature | 4h | rota nova `/status` |
| P2 | Modo foco (hide rail + agent panel) | toggle UI | 1h | layout shell |
| P2 | Animações de transição (Vue `<Transition>`) | open/close drawers | 1h | Sidebar, drawers |
| P2 | Onboarding WA-fiel | tour guiado | 3h | novo `OnboardingTour.vue` |
| P2 | Modo mobile (< 768px) | responsivo total | 5h | layout shell + Sidebar |

**Total P0 restante:** ~2h · **P1:** ~8h · **P2:** ~24h

---

## 4. Pontos de extensão (Enterprise)

- **Enterprise overlay = só Ruby.** Não há `enterprise/app/javascript/`. Logo, qualquer mudança em Vue/SCSS é livre de conflito.
- **Features Simplex-only no frontend:** viver em `app/javascript/dashboard/` (sem fork `enterprise/`), gated por `isFeatureEnabledonAccount(accountId, 'flag_name')` ou `useInstallationName`. Padrão já usado em Sidebar e ReplyBox.
- **Quando backend precisa lógica Enterprise-only:** usar `prepend_mod_with('::Concerns::ChatSpx')` em controllers OSS e colocar o módulo em `enterprise/app/controllers/concerns/chat_spx/`. **Não editar OSS direto.**
- **Features exclusivas** (ex: Quick Reply Chips com analytics Simplex): componente Vue em `app/javascript/dashboard/components-next/chatspx/`, concern Ruby em `enterprise/app/models/concerns/chat_spx/`.
- **Specs Enterprise:** espelhar em `spec/enterprise/` (ex: `spec/enterprise/models/chat_spx/quick_reply_spec.rb`).

---

## 5. Feature flags recomendadas

| Flag | Default homologação | Default produção | Uso |
|---|---|---|---|
| `quick_reply_chips` | `true` | `false` (fase 1 rollout 20%) | Mostra chips de atalho no ReplyBox |
| `conversation_pinning` | `true` | `false` global, habilitar por conta piloto | Pin de conversas fixas no topo |
| `command_palette` | `true` | `true` todas as contas | Cmd+K em produção — já é discoverable |
| `copilot_drawer` | `true` | `false` (aguardando P2) | Migra Copilot pra drawer lateral |
| `wa_multi_view` | `false` | `false` | Split contatos+conversas — só piloto Clara Tozi |

Registrar em `config/features.yml` + toggle em `/super_admin/features`.

---

## 6. Rollout gradual

**Onda 1 — agora (homologação → produção esta semana):** tokens + rail + tabs + skin + auditoria Captain/Copilot + particionamento SCSS. **Risco: baixo** — só visual, rollback trivial. Validar 48h em homologação com Clara Tozi.

**Onda 2 — próximos 5 dias:** Quick Reply Chips, pin de conversas, Cmd+K, scrollbar WA, avatar ring. Atrás de flag. Ativar primeiro em `clara-tozi` e `simplexia-interno`, depois 20%, depois global.

**Onda 3 — próxima semana:** Copilot drawer, multi-view, editor toolbar, charts refactor. Features grandes — entram atrás de flag `false` default, ativação manual por conta após QA e feedback do piloto.

---

## 7. Checklist de validação (pré-merge homologação → produção)

- [ ] `bundle exec rspec spec/` verde (baseline: mesmo número de testes e zero novos skips)
- [ ] `bundle exec rspec spec/enterprise/` verde
- [ ] `pnpm eslint` sem erros novos
- [ ] `bundle exec rubocop` sem offenses novos
- [ ] `pnpm test` (Vitest) verde
- [ ] `RAILS_ENV=production bundle exec rails assets:precompile` sem warnings
- [ ] Hard reload em Chrome + Firefox + Safari em homologação — sem flicker, sem FOUC
- [ ] Contraste AA (WCAG): textos `#e9edef` sobre `#202c33` = 11.2:1 ✓; verificar todos os botões primários
- [ ] 3 rotas críticas testadas: `/conversations`, `/settings/inboxes`, `/reports/overview`
- [ ] Clara Tozi logada em homologação, valida "sente como WhatsApp" em 2 conversas reais

---

## 8. Rollback

**Estratégia preferida:** working tree nunca commitado → `git stash` local (ou `git checkout -- <arquivos>`) reverte em segundos. Nada de revert remoto enquanto não houver commit.

**Após commit em `homologacao`:**
- Arquivos **safe to revert** (risco zero, visual only): `_next-colors.scss`, `_wa-skin.scss`, `_woot.scss`. `git checkout producao -- <arquivo>` e recompilar.
- Arquivos **risk to revert** (mexem em estrutura): `Sidebar.vue`, `ConversationCard.vue`, `ReplyBox.vue` — revert pode trazer bug se branch divergiu; preferir patch manual removendo classes WA-específicas.

**Se produção já deploiou e quebrou:**
1. `ssh prod` → `cd /home/chatwoot/chatwoot`
2. `git log --oneline -5` identifica commit de merge WA
3. `git revert <sha>` (novo commit, não reset)
4. `RAILS_ENV=production bundle exec rails assets:precompile`
5. `sudo systemctl restart chatwoot-web.1 chatwoot-worker.1`
6. Cloudflare cache purge dos assets (se aplicável)

**O que preservar:**
- `vault/` (notas, lições) — nunca tocar
- `public/dmock/` (mocks de design) — preservar para referência futura
- `i18n/locale/pt_BR/*` — validar separadamente, não junto com refactor visual

**Tempo de rollback estimado:** 5 minutos (revert + precompile + restart).

---

## Decisões arquiteturais

1. **Tokens via CSS custom properties** (não SCSS vars) — permite trocar paleta em runtime (dark/light/custom) sem rebuild.
2. **`_wa-skin.scss` como camada de override**, não substituição — preserva contrato Chatwoot original, facilita merge com upstream OSS.
3. **Enterprise 100% backend** — mudanças visuais ficam em OSS sem risco.
4. **Feature flags por conta** — rollout controlado, evita big-bang em produção build-to-earn.
5. **Sem novas libs** — tudo com Vue 3 + Tailwind existentes. Zero dependência nova.
