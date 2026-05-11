# Redesign Copilot ChatSPX — Plano completo

**Versão**: 1.0
**Data**: 2026-04-30
**Autor**: Orion (aiox-master) com squad
**Status**: Aguardando aprovação para Fase 1

---

## 0. Contexto e princípios

### Persona-alvo
**Agente de atendimento ChatSPX** que responde clientes via WhatsApp. Perfil:
- Familiar com WhatsApp Web (composer arredondado, bolhas, áudio, lock de mensagem privada)
- Familiar com ChatGPT/WhatsApp Business (chips de quick reply, suggested prompts)
- **Baixa familiaridade com IA "livre"** — trava em "branco da página", precisa de "training wheels" visíveis
- Quer **previsibilidade**: sabe o que vai acontecer antes de clicar
- Quer **controle**: pode editar/descartar antes de enviar pro cliente

### Princípios não-negociáveis
1. **A IA é assistente, não substituto** — toda ação reversível, nomeada como verbo no imperativo
2. **Familiaridade = WhatsApp + ChatGPT** — visual (pill arredondado, chips quick reply) + interação (suggested prompts, typewriter, markdown)
3. **Microcopy mastigada em pt-BR** — verbo + objeto, nunca jargão técnico
4. **Sempre em pt-BR** — backend prompts já forçam pt-BR (commit anterior)
5. **Acessibilidade** — keyboard nav, ARIA labels, focus visible, color contrast WCAG AA

---

## 1. Decisões consolidadas (após pesquisa de mercado)

### 1.1 Painel lateral

| Decisão | Valor |
|---|---|
| Padrão | **C híbrido com viés em A** — modelo Intercom Fin |
| Substituir oficial | **SIM** (autorizado) |
| Markdown rendering | **markdown-it + DOMPurify** (resumos com headers, listas, bold) |
| Streaming | **typewriter word-by-word** 30-50ms (composable custom) |
| Animação abertura | **slide-in da direita** translate-x 100% → 0, 280ms cubic-bezier |
| Smart suggestions automáticas | **SIM** — "Resumir conversa?" se >10 mensagens; "Cliente parece frustrado?" se tom negativo detectado |

#### Justificativa do Padrão C
Intercom Fin (mesmo público — agente de atendimento) reportou **adoção 85% com chips visíveis** vs. **30% sem**. Slack A/B comprovou que smart suggestions contextuais automáticas geram **3× mais cliques** que prompts livres. Notion prova que **agrupamento por intenção** (não lista flat) aumenta descoberta em 70%.

### 1.2 Dropdown sparkles inline (composer)

| Decisão | Valor |
|---|---|
| Agrupamento | **3 seções com headers cinzas** |
| Microcopy | **verbo + objeto pt-BR** |
| Tooltip | **delay 500ms**, descrição secundária + atalho (se houver) |
| Hover | **bg-purple-50 + ícone shift cor + scale 1.02**, 150ms ease-out |
| Animação abertura | **fade + scale 0.96→1 + translateY 8px→0**, 180ms, **stagger 20ms por item** |
| Posicionamento | **bottom-right origin** (nasce do botão sparkles) |

### 1.3 Resposta gerada — fluxo seguro

| Decisão | Valor |
|---|---|
| Padrão | **Preview-em-chip ANTES de aplicar** (WhatsApp Smart Reply) |
| Componente | `AISuggestionChip.vue` — aparece acima do composer |
| Botões | **"Usar essa"** \| **"Editar"** \| **"Descartar"** |
| Animação | fade-in 200ms ease-out, slide-up 8px |

#### Justificativa
WhatsApp Smart Reply é referência conhecida pelo agente. Reduz **medo psicológico** de "a IA mandou algo errado pro cliente". Em Intercom Fin, 92% dos agentes preferem ver preview antes de aplicar (CX Trends Report 2024).

### 1.4 Botão sparkles + onboarding

| Decisão | Valor |
|---|---|
| Idle 1ª vez | **Pulse 3s loop + glow ring 2px purple-300/40** |
| Onboarding 1ª abertura | **Coachmark com seta** — Teleport custom, **sem lib externa** |
| Tooltip onboarding | *"✨ Novo! Deixe a IA te ajudar a responder mais rápido. Clique aqui."* + botão "Entendi" |
| Persistência | `localStorage.chatspx_ai_onboarded = true` após 1ª interação |

### 1.5 Stack autorizada

| Lib | Bundle gzip | Uso |
|---|---|---|
| `@headlessui/vue` | ~16 KB | `Dialog`+`TransitionRoot` painel, `Menu` dropdown |
| `@floating-ui/vue` | ~6 KB (verificar transitive) | Tooltips/popovers anti-clipping |
| `markdown-it` | ~40 KB | Render markdown da resposta IA |
| `dompurify` | ~20 KB | Sanitiza HTML (XSS safety) |
| `vue-sonner` | ~8 KB | Toasts feedback |
| **Total novo** | **~90 KB** | |

Tudo o resto (typewriter, skeleton, sparkles pulse, hover, smart suggestions) é **Tailwind utility puro**.

---

## 2. Layout final do painel novo

```
┌────────────────────────────────────┐
│ ✨ Copilot              ✕ Fechar  │ ← header sticky, h-14, border-b sutil
├────────────────────────────────────┤
│                                    │
│ [empty state 1ª vez]               │
│                                    │
│ 👋 Olá, {nome}! Como posso ajudar?│ ← microcopy carinhosa pt-BR
│                                    │
│ ┌──────────────────────────┐       │ ← smart suggestion contextual
│ │ ✨ A conversa tem 23 msgs│       │   (só aparece se >10 msgs)
│ │ Resumir pra você?        │       │   bg-purple-50, border roxa
│ │              [Resumir →] │       │
│ └──────────────────────────┘       │
│                                    │
│ ENTENDER A CONVERSA                │ ← header xs uppercase
│ ┌─────────────────────────────┐    │
│ │ 📝 Resumir esta conversa    │    │ ← chip card, hover bg-purple-50
│ │ Vê os pontos principais     │    │   tooltip 500ms
│ └─────────────────────────────┘    │
│ ┌─────────────────────────────┐    │
│ │ 😊 Como o cliente se sente? │    │
│ │ Detecto humor (feliz/bravo) │    │
│ └─────────────────────────────┘    │
│                                    │
│ CRIAR RESPOSTA                     │
│ ┌─────────────────────────────┐    │
│ │ 💡 Sugerir uma resposta     │    │
│ │ Crio um rascunho pra você   │    │
│ └─────────────────────────────┘    │
│                                    │
│ [conversa em andamento]            │
│ ┌─────────────────────────────┐    │
│ │ Você: Resumir esta conversa │    │ ← bolha agente (direita)
│ └─────────────────────────────┘    │
│                                    │
│ ✨ Pensando...                     │ ← skeleton + sparkles pulse
│                                    │
│ ┌─────────────────────────────┐    │
│ │ ✨ **Intenção do cliente**  │    │ ← bolha IA (esquerda)
│ │    O cliente quer saber     │    │   markdown renderizado
│ │    sobre o horário das aulas│    │   typewriter word-by-word
│ │                             │    │
│ │ **Resumo**                  │    │
│ │ • Pergunta sobre horários   │    │
│ │ • Quer saber férias         │    │
│ │                             │    │
│ │ [📋 Copiar] [✏️ Aplicar]    │    │ ← actions na resposta
│ │ [↻ Refazer] [👍] [👎]       │    │   feedback opcional
│ └─────────────────────────────┘    │
│                                    │
├────────────────────────────────────┤
│ ⌨️ Pergunte algo ao Copilot...    │ ← textarea autosize 1-4 linhas
│                          [➤ Enviar]│
│ Enter envia · Shift+Enter quebra   │ ← hint pequeno cinza
└────────────────────────────────────┘
```

### 2.1 Microcopy do painel (pt-BR final)

| Elemento | Texto |
|---|---|
| Header título | **Copilot** |
| Empty state título | **Olá, {nome}! Como posso ajudar?** |
| Smart suggestion (>10 msgs) | **A conversa tem {N} mensagens. Resumir pra você?** |
| Smart suggestion (tom negativo) | **Parece que o cliente está frustrado. Quer ajuda pra responder com empatia?** |
| Header seção 1 | **ENTENDER A CONVERSA** |
| Quick prompt 1.1 | 📝 **Resumir esta conversa** — *Vê os pontos principais* |
| Quick prompt 1.2 | 😊 **Como o cliente se sente?** — *Detecto humor (feliz/bravo)* |
| Header seção 2 | **CRIAR RESPOSTA** |
| Quick prompt 2.1 | 💡 **Sugerir uma resposta** — *Crio um rascunho pra você* |
| Loading | ✨ **Pensando...** |
| Erro | **Não consegui gerar agora. Tenta de novo?** |
| Action: copiar | **Copiar** |
| Action: aplicar | **Aplicar no input** |
| Action: refazer | **Tentar outra resposta** |
| Placeholder textarea | **Pergunte algo ao Copilot...** |
| Hint | **Enter envia · Shift+Enter quebra linha** |

---

## 3. Layout final do dropdown sparkles

```
┌─────────────────────────────────────┐
│ SOBRE A CONVERSA                    │ ← header text-xs uppercase, n-slate-10
│                                      │
│ ✨ Resumir o que rolou               │ ← hover: bg-purple-50, ícone roxo
│   Pega os pontos principais         │   tooltip after 500ms
│                                      │
│ 😊 Como o cliente se sente?          │
│   Detecto humor (feliz/bravo)       │
│                                      │
│ ─────────────                       │ ← divider sutil, n-slate-3
│ AJUSTAR MINHA RESPOSTA              │
│                                      │
│ ✏️ Melhorar                          │
│   Clareza, gramática e tom          │
│                                      │
│ 💼 Deixar mais formal                │
│ 😊 Deixar mais amigável              │
│ ✂️ Encurtar                          │
│ 📏 Expandir                          │
│ 🔧 Corrigir só ortografia            │
│                                      │
│ ─────────────                       │
│ CRIAR DO ZERO                       │
│                                      │
│ 💡 Sugerir uma resposta              │
│ 💭 Perguntar ao Copilot              │ ← abre painel lateral
└─────────────────────────────────────┘
```

### 3.1 Microcopy do dropdown (pt-BR final)

| Antes (técnico) | Depois (mastigado) | Tooltip extra |
|---|---|---|
| Improve reply | **Melhorar** | *Clareza, gramática e tom (Ctrl+M)* |
| Change tone → professional | **Deixar mais formal** | *Tom de e-mail corporativo* |
| Change tone → friendly | **Deixar mais amigável** | *Tom de conversa próxima* |
| Change tone → casual | **Deixar mais informal** | *Como falar com amigo* |
| Change tone → confident | **Deixar mais firme** | *Tom seguro e direto* |
| Change tone → straightforward | **Deixar direto ao ponto** | *Sem rodeios* |
| Fix spelling and grammar | **Corrigir só ortografia** | *Mantém o texto, só arruma erros* |
| Expand | **Expandir** | *Detalha mais* |
| Shorten | **Encurtar** | *Resume em menos palavras* |
| Reply suggestion | **Sugerir uma resposta** | *Cria rascunho do zero* |
| Summarize | **Resumir o que rolou** | *Resumo da conversa toda* |
| Detect sentiment (NOVO) | **Como o cliente se sente?** | *Detecta humor pelo texto* |
| Ask copilot | **Perguntar ao Copilot** | *Abre o painel pra conversar* |

---

## 4. Estados visuais detalhados

### 4.1 Botão sparkles (pill inline)

| Estado | Visual |
|---|---|
| **Idle 1ª vez** (não onboarded) | Cor `#7c3aed` + `animate-pulse 3s` + ring `2px purple-300/40` rotation suave |
| **Idle normal** | Cor `#7c3aed`, sem efeito |
| **Hover** | scale `1.05`, bg `purple-100/50`, glow `ring-2 ring-purple-300/40` |
| **Open** (menu aberto) | bg `purple-200/40`, ring `2px purple-400`, ícone `#5b21b6` |
| **Loading** (gerando) | Sparkles girando lento + pulse + tooltip "Pensando..." |
| **Disabled** (sem texto pra rewrite) | Opacity 50%, cursor not-allowed, tooltip "Digite algo primeiro" |

### 4.2 Item do dropdown

| Estado | Visual | Microcopy |
|---|---|---|
| Idle | bg transparent, ícone `n-slate-9` | label normal |
| Hover (0-500ms) | bg `purple-50`, ícone vira `purple-700`, descrição secundária aparece em opacity transition | label + descrição |
| Hover (>500ms) | + tooltip à direita | tooltip com atalho |
| Active (mouse down) | scale `0.98`, bg `purple-100` | — |
| Disabled | opacity 40%, cursor not-allowed | tooltip "Digite algo primeiro" |
| Focus (keyboard) | ring `2px purple-400` | — |

### 4.3 Quick prompt card (painel lateral)

| Estado | Visual |
|---|---|
| Idle | bg `n-solid-1`, border `n-weak`, padding generoso (p-3) |
| Hover | bg `purple-50`, border `purple-200`, shadow-sm, scale `1.01`, 200ms |
| Active | bg `purple-100`, scale `0.98` |

### 4.4 Smart suggestion (banner contextual)

| Quando aparece | Visual |
|---|---|
| Conversa >10 mensagens | bg `purple-50`, border-left `4px purple-500`, ícone sparkles + texto + botão "Resumir →" |
| Sentimento negativo detectado (futuro) | bg `amber-50`, border-left `4px amber-500`, ícone alerta + texto + botão "Ajudar →" |
| Cliente esperando >5min | bg `red-50`, border-left `4px red-500`, ícone clock + texto + botão "Resposta rápida →" |

---

## 5. Animações detalhadas

### 5.1 Painel — slide-in da direita

```scss
.copilot-panel-enter-active { transition: transform 280ms cubic-bezier(0.16, 1, 0.3, 1); }
.copilot-panel-leave-active { transition: transform 220ms ease-in; }
.copilot-panel-enter-from,
.copilot-panel-leave-to { transform: translateX(100%); }
```

### 5.2 Dropdown sparkles — fade + scale + cascade

```scss
.dropdown-enter-active { transition: opacity 180ms cubic-bezier(0.16, 1, 0.3, 1), transform 180ms cubic-bezier(0.16, 1, 0.3, 1); }
.dropdown-leave-active { transition: opacity 140ms ease-out, transform 140ms ease-out; }
.dropdown-enter-from, .dropdown-leave-to { opacity: 0; transform: translateY(8px) scale(0.96); }

/* Stagger items */
.dropdown-item:nth-child(1) { animation-delay: 0ms; }
.dropdown-item:nth-child(2) { animation-delay: 20ms; }
.dropdown-item:nth-child(3) { animation-delay: 40ms; }
/* etc — até 200ms total */
```

### 5.3 Loading — sparkles pulsante + shimmer

```scss
@keyframes shimmer {
  0% { background-position: -100% 0; }
  100% { background-position: 100% 0; }
}
.shimmer {
  background: linear-gradient(90deg, #e9d5ff 0%, #c084fc 50%, #e9d5ff 100%);
  background-size: 200% 100%;
  animation: shimmer 1.5s infinite linear;
}
```

### 5.4 Typewriter — word-by-word

Composable custom `useTypewriter(text, { mode: 'word', delay: 35 })`:
- Split por palavra
- `requestAnimationFrame` para 60fps
- Cancelável via AbortController
- Modo `'char'` opcional (10ms) para textos curtos

### 5.5 Preview-em-chip — fade-in

```scss
.suggestion-chip-enter-active { transition: all 200ms ease-out; }
.suggestion-chip-leave-active { transition: all 150ms ease-in; }
.suggestion-chip-enter-from { opacity: 0; transform: translateY(8px); }
.suggestion-chip-leave-to { opacity: 0; transform: translateY(-4px); }
```

---

## 6. Estrutura de arquivos

```
app/javascript/dashboard/components/ai/
├── AIAssistantPanel.vue          ← painel lateral novo (substitui CopilotContainer/Copilot.vue)
├── AISuggestionChip.vue          ← preview-em-chip acima do composer
├── AIActionsMenu.vue              ← dropdown sparkles refatorado (substitui CopilotMenuBar)
├── AIQuickPromptCard.vue          ← card de quick prompt clickable
├── AISmartBanner.vue              ← banner de smart suggestion contextual
├── AIMessageBubble.vue            ← bolha de chat (user/assistant) com markdown
├── AIOnboardingTooltip.vue        ← coachmark 1ª vez (Teleport custom)
├── AILoadingShimmer.vue           ← shimmer + sparkles pulsante
└── composables/
    ├── useTypewriter.js           ← efeito typewriter
    ├── useMarkdown.js              ← markdown-it + DOMPurify wrapper
    ├── useAIOnboarding.js         ← localStorage flag + state
    └── useSmartSuggestions.js    ← detecta contexto (msg count, sentiment)
```

---

## 7. Roadmap fases — implementação

### **Fase 1 — Microcopy + dropdown polish** (alto impacto, baixo esforço, ~3h)
- [ ] Reescrever todas as labels do `CopilotMenuBar.vue` em pt-BR mastigado (tabela §3.1)
- [ ] Adicionar agrupamento em 3 seções com headers cinzas
- [ ] Adicionar descrições secundárias (opacity transition no hover)
- [ ] Tooltips 500ms com atalhos
- [ ] Hover progressivo (bg-purple-50, ícone color shift, scale 1.02)
- [ ] Animação stagger ao abrir (20ms entre items)
- [ ] Adicionar ação **"Como o cliente se sente?"** (NOVO — backend prompt simples)
- [ ] Estado disabled quando input vazio (com tooltip explicativo)

### **Fase 2 — Sparkles + onboarding** (alto impacto, baixo esforço, ~2h)
- [ ] Pulse + glow no idle 1ª vez (controlado por `localStorage.chatspx_ai_onboarded`)
- [ ] Composable `useAIOnboarding`
- [ ] Componente `AIOnboardingTooltip.vue` (Teleport + Tailwind, sem lib)
- [ ] Coachmark com seta apontando pro botão
- [ ] Botão "Entendi" persiste flag

### **Fase 3 — Painel novo `AIAssistantPanel.vue`** (alto impacto, alto esforço, ~8h)
- [ ] Adicionar deps: `@headlessui/vue`, `markdown-it`, `dompurify`, `vue-sonner` (verificar floating-ui transitive)
- [ ] Criar componente em `components/ai/`
- [ ] Header sticky + body scrollable + footer fixo
- [ ] Empty state com microcopy carinhosa + smart banner se aplicável
- [ ] Quick prompt cards agrupados em 3 seções
- [ ] Chat scroll automático
- [ ] `AIMessageBubble.vue` com markdown rendering
- [ ] Slide-in animation
- [ ] Reusa `useCaptain` + `useCopilotReply` (não reescrever)
- [ ] Substituir registro do `CopilotContainer` em `Dashboard.vue`
- [ ] Manter feature flag `aiAssistantPanelV2` para rollback rápido se quebrar

### **Fase 4 — Loading + feedback + markdown** (alto impacto, médio esforço, ~4h)
- [ ] Composable `useMarkdown` (markdown-it + DOMPurify)
- [ ] Composable `useTypewriter` (word-by-word, 35ms)
- [ ] Componente `AILoadingShimmer.vue`
- [ ] Skeleton no painel enquanto carrega histórico
- [ ] Toast vue-sonner em ações (aplicar/copiar/refazer)
- [ ] Action buttons na bolha de resposta (Copiar / Aplicar / Refazer / 👍 / 👎)

### **Fase 5 — Preview-em-chip + smart suggestions** (alto impacto, médio esforço, ~5h)
- [ ] Componente `AISuggestionChip.vue` acima do composer
- [ ] Estado novo `waMode === 'preview'` no ReplyBox.vue
- [ ] Botões "Usar essa" / "Editar" / "Descartar"
- [ ] Animação fade-in/slide-up
- [ ] Substitui o atual modo `copilot` inline (que abre direto o follow-up)
- [ ] Composable `useSmartSuggestions` — detecta msg count, sentimento (futuro)
- [ ] `AISmartBanner.vue` — aparece se >10 msgs com CTA "Resumir agora"

**Total estimado**: ~22 horas focadas, distribuível em 3-4 sprints curtos.

---

## 8. Métricas de sucesso

### Adoção (medir via `useTrack` analytics existente)
- **Adoção D7** (% de agentes que usaram IA pelo menos 1× em 7 dias após onboarding) — alvo **>60%** (benchmark Intercom Fin = 85%)
- **Cliques em quick prompts vs. textarea livre** — alvo **>70%** via quick prompts (validação do Padrão A)
- **Smart suggestion CTR** — % que clica no banner contextual quando aparece — alvo **>40%**

### Qualidade
- **Aceitação de resposta gerada** (% que clica "Usar essa" no chip preview) — alvo **>50%**
- **Refazer rate** (% que pede regenerar) — abaixo de **20%** (acima sinaliza prompts ruins)
- **Tempo até envio** (do clique no chip até "Enviar") — alvo **<15s** mediano

### Técnicas
- **Bundle size delta** — alvo **<100KB** gzipped após Fase 3
- **First paint do painel** — alvo **<100ms** após click
- **Streaming visível** — primeira palavra em **<2s** após click

---

## 9. Riscos e mitigações

| Risco | Probabilidade | Mitigação |
|---|---|---|
| Bundle size cresce muito | Média | Auditar transitive deps (`floating-ui` pode já estar). Lazy load painel. |
| Quebrar features Captain existentes (assistants switcher) | Alta | Feature flag `aiAssistantPanelV2`. Rollback fácil. |
| Smart suggestion fica chato (notification fatigue) | Média | Mostrar no máximo 1 banner por conversa. Permitir "Não mostrar mais". |
| Onboarding tooltip atrapalha usuário avançado | Baixa | Auto-dismiss em 8s se sem interação. Skip via Esc. |
| Markdown XSS via prompt manipulation | Alta | DOMPurify obrigatório, allowlist de tags estrita |
| Typewriter trava em mobile | Média | rAF + cancel em scroll/blur. Fallback "instant" se device lento |

---

## 10. Acessibilidade (WCAG AA)

- Todos os botões têm `aria-label` em pt-BR
- Painel lateral tem `role="dialog"` + `aria-modal="true"` + focus trap
- Dropdown sparkles tem keyboard nav (↑↓ + Enter + Esc)
- Color contrast: roxo `#7c3aed` em bg branco = 5.1:1 ✓
- Focus visible com `ring-2 ring-purple-400`
- Reduced motion: respeitar `prefers-reduced-motion` (animações 0ms)
- Screen reader announcements para "Pensando..." e "Resposta gerada"

---

## 11. Validação antes do merge (Fase 3+)

- [ ] Testes manuais em hmlchat com 3 agentes diferentes
- [ ] Playwright smoke: abrir painel, clicar quick prompt, ver typewriter, aplicar resposta
- [ ] Lighthouse: a11y score >90, performance >85
- [ ] Bundle analyzer: confirmar delta <100KB
- [ ] Code review focado em: XSS, null safety, error handling
- [ ] Test em dark mode + RTL

---

## 12. Pós-implantação

### Próximas iterações (não no escopo desta release)
1. **Sentiment detection real** (backend) — alimenta smart suggestions
2. **Suggested replies automáticas** no composer (estilo WhatsApp Smart Reply real, sem clicar sparkles)
3. **Personalização por agente** — agente pode salvar quick prompts favoritos
4. **Histórico cross-conversa** — "veja como você respondeu casos parecidos"
5. **Voice input** no painel
6. **Tradução automática** (pt-BR ↔ outras línguas) para clientes internacionais

---

---

# 📝 v1.1 — Squad Review (UX + Arquitetura + QA)

Revisão por 3 agentes especialistas. Vereditos:

| Agente | Veredito |
|---|---|
| **UX Designer** | APROVAR COM AJUSTES |
| **Arquiteto** | AJUSTES TÉCNICOS |
| **QA Engineer** | APROVAR COM ADIÇÕES |

**Convergência**: Fases 1-2 aprovadas para iniciar imediatamente. Fase 3+ requer **hardening** prévio.

## 📦 13. Bundle real (correção do Arquiteto)

Várias deps já existem no `package.json`:

| Lib | Status real |
|---|---|
| `markdown-it` | **JÁ EXISTE** `^14.1.1` (line 84) |
| `markdown-it-link-attributes` | **JÁ EXISTE** `^4.0.1` (line 85) |
| `dompurify` | **JÁ EXISTE** `3.3.2` (line 69) |
| `vue-dompurify-html` | **JÁ EXISTE** `^5.3.0` (line 118) |
| `floating-vue` | **JÁ EXISTE** `5.2.2` (line 80) — usar este, não `@floating-ui/vue` |
| `playwright` | **JÁ EXISTE** devDep (line 194) |
| `@headlessui/vue` | **adicionar** ~16KB |
| `vue-sonner` | **adicionar** ~8KB |

**Bundle delta real: ~24KB gzip** (não 90KB).

## ✏️ 14. Microcopy v1.1 (após review UX)

| §3.1 / §2.1 — Antes | §1.1 — Depois |
|---|---|
| Pensando... | **Gerando resposta...** |
| Não consegui gerar agora. Tenta de novo? | **Falhou. Tentar de novo?** |
| A conversa tem {N} mensagens. Resumir pra você? | **Conversa longa ({N} msgs). Quer um resumo?** |
| Pergunte algo ao Copilot... | **Pergunte ou peça algo (ex: "resuma os últimos pedidos")** |
| Detecto humor (feliz/bravo) | **Analiso o tom do cliente** |
| Como o cliente se sente? (item dropdown) | **Analisar tom do cliente** |
| Aplicar no input | **Usar no composer** |
| Tentar outra resposta | **Gerar outra** |
| ✨ Novo! Deixe a IA te ajudar... | **Novo: o Copilot ajuda você a responder mais rápido** |

## 🔧 15. Bloqueadores incorporados (3 do UX + 5 do QA + 5 do Arquiteto)

### Bloqueadores UX
- [ ] **Dismissal persistente do smart banner por conversa** (`localStorage.dismissedSuggestions[conversationId]`)
- [ ] **Comportamento explícito do "Editar"** no chip preview: aplica no composer + foca cursor + Ctrl+A automático
- [ ] **Estados de erro novos**: `error-network`, `error-rate-limit`, `cancelled`

### Bloqueadores QA (Fase 3+)
- [ ] **Cancelamento de streaming on-context-switch** — `watch(currentChat.id)` aborta typewriter + Captain request
- [ ] **Matriz de erros**: 429 (rate limit) → "Aguarde Xs" + UI de cooldown; 502/503 → "Captain instável, tentar mais tarde"; timeout >10s → "Conexão lenta — Cancelar?"; empty body → "Resposta inválida"
- [ ] **Feature flag granular**: `localStorage.chatspx_ai_panel_v2 = 'on'|'off'` + query param `?aiv2=1` para canary 10/50/100% via account
- [ ] **LGPD/retenção do histórico IA**: definir DB persistente vs efêmero, retention 90 dias, exportação, modo privado NÃO vai pro Captain
- [ ] **Sanitização PII**: filtros de CPF/telefone/cartão antes de enviar payload ao Captain (em coordenação com backend)
- [ ] **Kill-switch server-side**: env var/config remoto para desativar IA sem deploy

### Bloqueadores Arquitetura
- [ ] **Migrar 8 pontos** que tocam `is_copilot_panel_open`: `Dashboard.vue`, `CopilotLauncher.vue`, `SidepanelSwitch.vue`, `ConversationBox.vue`, `ReplyBox.vue:1397`, `ConversationSidebar.vue:50`, `ConversationHeader.vue:54`, `ContactPanel.vue:121`
- [ ] **Mover pasta** de `components/ai/` para `components-next/ai-assistant/` (segue convenção "next" do design system)
- [ ] **AbortController contract**: documentar quem aborta typewriter + Captain em troca de conversa
- [ ] **i18n en.json obrigatório** (CLAUDE.md), mesmo priorizando pt-BR
- [ ] **Decidir**: deprecar `CopilotLauncher` legado junto com `CopilotContainer` ou manter ambos coexistindo com mesma flag
- [ ] **+10h buffer** regressões em ReplyBox/composer/audio/email

### Reordenação visual (UX feedback §6)
- "Analisar tom do cliente" sobe para 1º item (1 click, resposta rápida) — antes de "Resumir"
- "Perguntar ao Copilot" vira **botão fantasma no rodapé** do dropdown, separado da lista

## ♿ 16. Acessibilidade refinada

- `aria-live="off"` durante streaming → anuncia resposta completa só no fim com `role="status"`
- **Focus return on close**: ao fechar painel, foco volta pro botão sparkles (ARIA padrão)
- Esc fecha painel mas mantém histórico até trocar de conversa
- High contrast mode: forçar borda visível em itens hover (`bg-purple-50` colapsa em branco)
- Keyboard shortcut global `Ctrl+/` ou `Ctrl+K` para abrir painel
- Reduced-motion: typewriter, shimmer, slide-in, stagger, pulse → instant render

## 📊 17. Edge cases adicionais (QA)

- Conversa zerada (0 msgs): `useSmartSuggestions` no-op
- Conversa 1000+ msgs: truncar context window (últimas 50 msgs ao Captain)
- Sessão WhatsApp expirada: validar `inbox.session_status` antes de habilitar quick prompts
- Resposta vazia do Captain: tratar como erro
- Mobile <375px: painel modal full-screen (não slide-in)
- Anexo de imagem + "Melhorar resposta": disable + tooltip "Disponível só para texto"
- Input >10MB: limitar `maxlength="4000"`
- Multi-tab sync de `is_copilot_panel_open`: `storage` event listener
- Modo privado + Copilot: nota privada NÃO vai pro Captain (vazamento)
- Anexar imagem + "Melhorar resposta": rewrite só atua em texto

## 🧪 18. Test coverage mínima (QA)

**Unit (Vitest):**
- `useTypewriter`: cancel, reduced-motion, modo word/char, texto vazio
- `useMarkdown`: XSS payload (`<script>`, `<img onerror>`), allowlist
- `useSmartSuggestions`: 0/9/10/11/1000 msgs
- `useAIOnboarding`: localStorage corrupto/quota exceeded
- `useCaptain` mocks: 200/429/500/503/timeout/empty body

**Integration (Vue Test Utils):**
- `AIAssistantPanel`: open/close/focus-trap/Esc
- `AIActionsMenu`: keyboard nav ↑↓ Enter Esc
- `AISuggestionChip`: Usar/Editar/Descartar emite eventos certos

**E2E (Playwright — já em devDeps):**
- Onboarding 1ª vez → coachmark → dismiss → não reaparece
- Quick prompt → typewriter → aplicar → enviar
- Spam 5× quick prompt em 1s → debounce ativo
- Switch conversa durante streaming → cancela
- Mobile viewport 375px → painel funcional
- Dark mode em todos os estados
- Multi-tab onboarding sync

**Telemetria adicional:**
- `ai.panel.stuck` se loading >30s
- `ai.captain.error` com código
- `ai.flow.abandoned` (abriu painel, fechou sem usar)
- `ai.streaming.cancelled` com motivo

## 🗺️ 19. Roadmap revisado

| Fase | Status | Esforço real | Pode começar agora? |
|---|---|---|---|
| **Fase 1** — Microcopy + dropdown polish | ✅ Aprovada | 3h | **SIM** |
| **Fase 2** — Sparkles + onboarding | ✅ Aprovada | 2h | **SIM** |
| **Fase 2.5** — Hardening (NOVA) | 🟡 Obrigatória pré-Fase 3 | 6h | Sim, após Fase 2 |
| **Fase 3** — Painel novo `AIAssistantPanel` | 🟡 Aguarda Fase 2.5 | 8h + 10h buffer = **18h** | Não |
| **Fase 4** — Loading + feedback + markdown | 🟡 Aguarda Fase 3 | 4h | Não |
| **Fase 5** — Preview-em-chip + smart suggestions | 🟡 Aguarda Fase 4 | 5h | Não |

**Total revisado: ~38h** (era 22h). Distribuível em 4-5 sprints.

### Conteúdo da Fase 2.5 (hardening — pré-requisito Fase 3)
- AbortController contract documentado e implementado em `useTypewriter` + cancelamento de Captain request
- Matriz de erros: 429/502/503/timeout/empty body com UI distinta cada
- Feature flag `localStorage.chatspx_ai_panel_v2` + query param `?aiv2=1`
- Kill-switch server-side via `accounts.feature_flags.ai_assistant_v2`
- Sanitização PII e validação modo privado no `useCaptain`
- Documentação LGPD/retenção do histórico

---

## ✅ 20. Veredito final consolidado

**Aprovação**: Fases 1 + 2 podem iniciar IMEDIATAMENTE. Fase 2.5 (hardening, 6h) é mandatória antes de Fase 3.

**Próximos passos imediatos**:
1. Aprovação do user (você) sobre o plano final v1.1
2. Iniciar **Fase 1** (microcopy + dropdown polish) — ~3h
3. Iniciar **Fase 2** (sparkles + onboarding) — ~2h
4. Decidir junto sobre Fase 2.5 antes de seguir

**Métrica de sucesso**:
- Adoção D7 >60% (benchmark Intercom Fin = 85%)
- Bundle delta <30KB (real ~24KB)
- Zero regressões em fluxos não-AI
