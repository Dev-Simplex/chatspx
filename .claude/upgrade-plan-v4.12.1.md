# PLANO DE UPGRADE: ChatSPX v4.10.1 → v4.12.1

## STATUS: EM EXECUÇÃO

---

## FASE 1: PREPARAÇÃO ✅
- [ ] Commitar todos os fixes da auditoria na branch homologacao
- [ ] Fetch upstream tags/branches
- [ ] Criar branch upgrade/v4.12.1 a partir de homologacao

## FASE 2: MERGE
- [ ] git merge v4.12.1 --no-commit
- [ ] Listar todos os conflitos
- [ ] Resolver conflitos por zona (ver abaixo)

## FASE 3: PÓS-MERGE
- [ ] bundle install (novas gems: cld3, skooma, ai-agents bump)
- [ ] pnpm install (novas deps: virtua, @iconify-json/fluent; removidas: vue-multiselect, vue-virtual-scroller)
- [ ] rails db:migrate (7 novas migrations upstream)
- [ ] RuboCop em todos os arquivos com conflito
- [ ] ESLint em todos os JS/Vue com conflito
- [ ] Ruby specs
- [ ] JS specs
- [ ] Build de produção

## FASE 4: PROMOÇÃO
- [ ] Merge upgrade/v4.12.1 → homologacao
- [ ] Testar em staging
- [ ] Merge homologacao → producao (SOMENTE após aprovação)

---

## ZONAS DE CONFLITO E ESTRATÉGIA

### ZONA 1: AI/Copilot (ALTO RISCO)
**Upstream**: Deletou useAI.js, AIAssistanceButton.vue, AIAssistanceModal.vue, openai/processor_service.rb
**Upstream**: Adicionou Captain Tasks, CopilotEditor, CopilotMenuBar, CopilotReplyBottomPanel
**Custom**: Modificou AIAssistanceButton.vue
**Estratégia**: Aceitar TODAS as deleções e adições do upstream. Nosso AIAssistanceButton.vue foi apenas branding — o novo CopilotEditor substitui completamente. Se houver customizações de branding, aplicar no novo componente.

### ZONA 2: ReplyBox.vue (ALTO RISCO)
**Upstream**: Adicionou CopilotEditor integration, CopilotReplyBottomPanel
**Custom**: Performance fixes, whatsappNoticeTimeoutId cleanup, WAHA validation
**Estratégia**: Aceitar layout/structure do upstream, re-aplicar nossos fixes (timeout cleanup, WAHA) no novo código.

### ZONA 3: Conversation Components (MÉDIO RISCO)
**Arquivos**: ConversationCard.vue, ChatList.vue, MessagesView.vue, ConversationSearchBar.vue
**Upstream**: Melhorias gerais, virtual scrolling (virtua), label right-click remove
**Custom**: Performance fixes, ::v-deep→:deep(), Tailwind migration, sizeDependencies
**Estratégia**: Aceitar mudanças estruturais upstream, re-aplicar nossos fixes pontuais.

### ZONA 4: Vuex Stores (MÉDIO RISCO)
**Arquivos**: conversations/index.js, conversations/getters.js, reports.js, auth.js, contacts/, notifications/
**Upstream**: Pode ter mudanças em mutations/actions
**Custom**: conversationMap, null-safety, reactivity fixes, async/await, camelcase write-time
**Estratégia**: Manter TODOS os nossos fixes de performance. Se upstream mudou algum mutation, integrar com nosso pattern.

### ZONA 5: Dependências (MÉDIO RISCO)
**Gemfile**: ai-agents bump, cld3 (NOVA), skooma (NOVA dev)
**package.json**: virtua (NOVA), @iconify-json/fluent (NOVA), markdown-it 13→14, vue-multiselect REMOVIDA, vue-virtual-scroller REMOVIDA
**Estratégia**: Aceitar TODAS as mudanças upstream de dependências. Verificar que nossas gems custom (oj) estão mantidas.

### ZONA 6: Database Migrations (BAIXO RISCO)
**Upstream**: 7 novas migrations (webhook secret, reporting_events_rollups, captain features, indexes)
**Custom**: 18 migrations + 3 novas da auditoria
**Estratégia**: Sem conflito — timestamps diferentes. Apenas rodar todas.

### ZONA 7: Backend Services/Controllers (MÉDIO RISCO)
**Upstream**: Novos endpoints (captain/tasks, health, shopify, csat_template)
**Custom**: WAHA, NPS, scheduled messages, kanban, toggle_status_service, translate_service
**Estratégia**: Aceitar novos endpoints upstream, manter todos os custom. Resolver routes.rb conflitos mantendo ambos.

### ZONA 8: Locales/I18n (BAIXO RISCO)
**Upstream**: Novas keys em en/*.json
**Custom**: Novas keys em en/ e pt_BR/ (WAHA, NPS, private chat, kanban)
**Estratégia**: Merge simples — adicionar keys de ambos os lados.

### ZONA 9: Config/Infra (BAIXO RISCO)
**Upstream**: schedule.yml changes (novos jobs), feature flags
**Custom**: Oj initializer, custom feature flags
**Estratégia**: Aceitar upstream schedule/flags, manter nossos adicionais.

### ZONA 10: Schema.rb (AUTO-GERADO)
**Estratégia**: Após rodar todas migrations, regenerar com rails db:schema:dump. NÃO resolver conflito manual.

---

## REGRA DE OURO PARA CONFLITOS

```
SE upstream ADICIONOU algo novo → ACEITAR
SE upstream MODIFICOU algo que NÃO tocamos → ACEITAR upstream
SE upstream MODIFICOU algo que TAMBÉM modificamos → MANTER AMBOS integrados
SE upstream DELETOU algo que USAMOS → MANTER nosso + ADAPTAR ao novo padrão
SE upstream DELETOU algo que NÃO usamos → ACEITAR deleção
```

---

## PROMPT DE CONTINUAÇÃO (colar em nova conversa se necessário)

```
Leia o arquivo .claude/upgrade-plan-v4.12.1.md — ele contém o plano completo
de upgrade do ChatSPX de v4.10.1 para v4.12.1.

O plano já foi iniciado. Verifique o STATUS de cada fase e continue de onde parou.

Contexto:
- Branch de trabalho: upgrade/v4.12.1
- Upstream remote: upstream (github.com/chatwoot/chatwoot.git)
- Origin remote: origin (github.com/Dev-Simplex/chatspx.git)
- Branch principal: homologacao
- Produção: producao

Regra de ouro: NADA se perde. Trazer tudo novo do upstream E manter tudo custom.

Para cada zona de conflito:
1. Leia AMBOS os lados (upstream e custom)
2. Integre mantendo os dois
3. Teste (RuboCop, ESLint, specs)

Use agentes em paralelo para resolver conflitos por zona.
Teste tudo antes de mergear de volta na homologacao.
```
