# 🚀 Prompt para novo chat — Execução COMPLETA do redesign Copilot

> **Como usar:** copie TUDO abaixo da linha `---` e cole no novo chat.
> O prompt já ativa `aiox-master`, força delegação ao squad e bloqueia atalhos de MVP.

---

# Contexto

Estou no projeto **ChatSPX** (fork Chatwoot da Simplex) em `/home/chatwoot/chatwoot`, branch `homologacao`. Esta VM (192.168.8.232) inteira é homologação — pode rodar `RAILS_ENV=production` à vontade.

Existe um plano de redesign do **painel Copilot + dropdown de ações de IA** já validado por squad (UX, Architect, QA) em:

**`docs/copilot-redesign-plan.md`** ← LEIA ESTE ARQUIVO PRIMEIRO, INTEGRALMENTE, ANTES DE QUALQUER OUTRA AÇÃO.

Ele contém:
- 6 decisões consolidadas (substituição total, fluxo híbrido, onboarding, libs autorizadas, pt-BR, etc)
- Layout do painel novo (WhatsApp-fiel, 3 categorias)
- Layout do dropdown (chips visíveis, sem hover-only)
- Microcopy pt-BR refinada pelo UX
- Stack autorizada (~24KB de bibs novas: `vue-shepherd`, `@vueuse/core`, `@floating-ui/vue`)
- Roadmap de 5 fases + Fase 2.5 hardening + QA = **38h total**
- 3 vereditos do squad (UX: APROVAR COM AJUSTES / Architect: AJUSTES / QA: APROVAR COM ADIÇÕES)
- Edge cases, error matrix, acessibilidade WCAG AA, LGPD/PII

# O que eu quero

**Implementação COMPLETA. NÃO É MVP.** Todas as 5 fases + Fase 2.5 hardening + QA do plano. Ponto.

Não quero:
- ❌ "Vou fazer o básico primeiro e depois evoluímos"
- ❌ Fases puladas
- ❌ "Versão simplificada por hora"
- ❌ Recortar feature flag granular ou error matrix porque "não é crítico"
- ❌ Pular onboarding (Fase 4) porque "dá para fazer depois"
- ❌ Pular sugestões contextuais (Fase 5) porque "é mais complexa"

Quero:
- ✅ Fase 1 — Painel novo completo, substituindo o legado
- ✅ Fase 2 — Dropdown 3 categorias com chips visíveis
- ✅ Fase 2.5 — Hardening (streaming cancellation, error matrix 429/502/503/timeout, feature flag granular, AbortController, LGPD/PII sanitization)
- ✅ Fase 3 — Preview inline (Aceitar/Editar/Descartar)
- ✅ Fase 4 — Onboarding (tour 4 passos com `vue-shepherd` + tooltip "Novo!" 7 dias)
- ✅ Fase 5 — Sugestões contextuais inteligentes (IA detecta intenção e sugere ação)
- ✅ QA + polish (testes E2E, acessibilidade, microcopy refinada)

# Como você deve trabalhar

**Você é o `aiox-master` — você ORQUESTRA, você não codifica sozinho.**

Não faça você mesmo a implementação. Ative o squad e delegue cada fase ao agente apropriado, conforme abaixo:

| Fase | Agente principal | Apoio |
|---|---|---|
| Leitura/análise do plano | `@aiox-master` (você) | — |
| Fase 1 — Painel novo | `@dev` | `@ux-design-expert` (revisão visual) |
| Fase 2 — Dropdown | `@dev` | `@ux-design-expert` (revisão visual) |
| Fase 2.5 — Hardening | `@architect` (design) → `@dev` (implementação) | `@qa` (validação) |
| Fase 3 — Preview inline | `@dev` | `@ux-design-expert` (microcopy + animações) |
| Fase 4 — Onboarding | `@ux-design-expert` (copy do tour) → `@dev` (integração `vue-shepherd`) | — |
| Fase 5 — Sugestões contextuais | `@architect` (design da heurística) → `@dev` (implementação) | `@analyst` (pesquisa de gatilhos) |
| QA + polish | `@qa` | `@ux-design-expert` (acessibilidade) |
| Commit final | `@dev` (working tree only — só commitar quando TUDO estiver pronto, conforme regra do usuário) | — |

**Regras de delegação rígidas:**
1. Use `Task` tool para spawnar subagentes em paralelo quando puder
2. Antes de cada fase, faça um `*plan` rápido das tarefas
3. Depois de cada fase, faça `@qa` validar antes de seguir
4. Se um agente errar 2 vezes seguidas, reporte e pergunte ao Walisson antes de continuar
5. NUNCA commit sem testar visualmente (acesse `https://hmlchat.simplexsolucoes.com.br` ou rode `pnpm dev`)

# Restrições obrigatórias do projeto

Lidas no `CLAUDE.md` do projeto e nas memórias:

1. **pt-BR sempre** — todo texto user-facing em pt-BR mastigado, com acentos e diacríticos perfeitos. Ex: "não", "função", "está" — nunca "nao", "funcao", "esta".
2. **Tailwind only** — sem CSS custom, sem scoped CSS, sem inline styles
3. **Vue 3 Composition API** com `<script setup>`
4. **Enterprise overlay** — antes de editar qualquer coisa core, busque também em `enterprise/` com `rg -n "FooService" app enterprise`
5. **i18n pt-BR primeiro** — editar `pt_BR/conversation.json` E `en/conversation.json` (essa regra do Walisson sobrescreve o CLAUDE.md original que diz "só en")
6. **Branding** — usar `replaceInstallationName` de `shared/composables/useBranding`, nunca hardcodar "Chatwoot"
7. **Components-next** — preferir `components-next/` para mensagens
8. **Working tree only** — não commitar enquanto o trabalho não estiver 100% completo. Walisson revisa visualmente antes do commit final.
9. **No deploy automático** — só pushar/restartar quando o Walisson autorizar explicitamente
10. **Restart em homologação:** `sudo systemctl restart chatwoot.target` (um comando só)
11. **rbenv:** `eval "$(rbenv init -)"` antes de qualquer comando Ruby

# Quality gates que VOCÊ deve enforçar

Antes de declarar uma fase pronta:

- [ ] `pnpm eslint` sem erros nos arquivos tocados
- [ ] `bundle exec rubocop -a` sem offenses (se Ruby)
- [ ] Testou no browser (`https://hmlchat.simplexsolucoes.com.br` ou `pnpm dev`)
- [ ] Verificou que não tem regressão em features adjacentes (audio, mentions `@`/`/`/`:`, attachments, popout, signature)
- [ ] i18n pt-BR e en preenchidos
- [ ] Acessibilidade: navegação por teclado funciona, ARIA labels, contraste WCAG AA
- [ ] Verificou `enterprise/` para arquivos relacionados
- [ ] Microcopy bate exatamente com o que está no `docs/copilot-redesign-plan.md` v1.1

Se algo falhar, **NÃO siga em frente. Reporte ao Walisson.**

# Como começar

1. **Leia o `docs/copilot-redesign-plan.md` integralmente** (627 linhas, 31KB)
2. **Atualize sua memória persistente** se descobrir algo novo (vault em `/home/chatwoot/chatwoot/vault/`, regra global em `~/.claude/CLAUDE.md`)
3. **Ative seu squad com `Task` tool em paralelo:**
   - `@architect` revisa Fases 2.5 e 5 (as mais complexas) e me dá um plano detalhado
   - `@ux-design-expert` valida microcopy e animações de todas as 5 fases
   - `@qa` define os testes E2E que serão exigidos no fim
4. **Apresente um plano consolidado** com:
   - Lista de arquivos que serão tocados (estimativa)
   - Ordem de execução das fases
   - Riscos identificados
   - Checkpoints de validação visual
5. **Espere meu OK explícito antes de começar a Fase 1**
6. Daí em diante, vai executando fase por fase, validando ao fim de cada uma.

# Sobre meu perfil

Sou Walisson, dev na Simplex/ChatSPX, perfil técnico, prefiro:
- Respostas diretas e curtas em pt-BR
- Sem rodeios nem MVPs implícitos
- Delegação real ao squad, não você fingindo ser todo mundo
- Testes visuais antes de commitar
- Quando eu digo "faz o que achar melhor" significa "execute end-to-end sem me perguntar a cada passo"

# Comece agora

Responda com:
1. Confirmação de que leu o `docs/copilot-redesign-plan.md` (cite 3 pontos específicos para provar)
2. Plano consolidado pós-revisão do squad
3. Estimativa total realista (em horas)
4. Pergunta única: "Aprovo começar a Fase 1?"

**Não comece a editar código antes de eu responder a essa pergunta.**
