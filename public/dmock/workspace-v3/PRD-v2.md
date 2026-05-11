# PRD v2 — ChatSPX Redesign WhatsApp-Fiel

**Produto:** ChatSPX (Simplex Soluções)
**Versão:** 2.0
**Data:** 2026-04-18
**Autor:** @pm (Morgan) — por solicitação de Walisson
**Status:** Em aprovação
**Substitui:** PRD v1 (`public/dmock/workspace-v3/PRD.html`)

---

## 1. Visão

Ser o **WhatsApp Web para empresas brasileiras**. Um atendente abre o ChatSPX e em 5 segundos reconhece a linguagem visual que já usa todo dia no celular — mesma paleta verde, mesmos bubbles, mesmos gestos — mas com superpoderes de CRM, IA, macros e colaboração em tempo real. Fidelidade visual é nossa arma competitiva: zero curva de aprendizado para o atendente júnior brasileiro, que já é nativo de WhatsApp.

---

## 2. Problema

O atendente brasileiro médio (operador de SAC, vendas, suporte) passa 6-8h/dia em uma ferramenta que **parece um ERP corporativo americano** — densidade alta, paleta azul/roxa genérica, terminologia em inglês traduzida ao pé da letra, decisões de UX pensadas para mercado EUA/Europa. Isso gera:

- **Curva de onboarding de 2-3 semanas** para o atendente novo ficar produtivo (benchmark Simplex em Clara Tozi, Alpha, etc.).
- **Erros de roteamento e resposta** porque o layout não destaca o que importa (contato, última mensagem, status).
- **Resistência cultural**: atendente sente que "o WhatsApp pessoal é melhor" e burla a ferramenta respondendo pelo celular pessoal.
- **Alto custo de suporte N1** interno ("como eu faço X?") que o Chatwoot OSS resolve com menus, mas não com reconhecimento visual imediato.

Concorrentes BR (Digisac, Omni, Huggy) tentaram resolver isso mas mantêm estética híbrida Chatwoot/Zendesk. Nenhum foi **radical** em fidelidade WhatsApp. Essa é nossa brecha.

---

## 3. Público-Alvo

| Persona | Cenário | Dor principal |
|---------|---------|---------------|
| **Atendente Operador** (70% do uso) | 8h/dia em 30-80 conversas simultâneas, idade 22-35, ensino médio/técnico, nativo de WhatsApp pessoal | Precisa responder rápido, reconhecer o contato, não errar destinatário |
| **Supervisor** (20% do uso) | Monitora 5-15 atendentes, revisa SLA, reatribui conversas, tira dúvida da equipe | Precisa visão macro + capacidade de entrar em conversa específica em 2 cliques |
| **Admin/Dono** (10% do uso) | Configura inboxes, macros, agentes IA, integrações; olha dashboard semanal | Precisa configurar rápido, não quebrar nada, delegar ao atendente |

**Empresa-tipo:** PME brasileira, 5-50 atendentes, setor de serviços (saúde, educação, e-commerce, imobiliário, advocacia). Já usa WhatsApp Business hoje e quer profissionalizar sem treinar equipe do zero.

---

## 4. Princípios de Produto

1. **Fidelidade visual WhatsApp é lei** — paleta `#005c4b` / `#d9fdd3` / `#efeae2`, bubbles idênticos, tipografia Segoe UI/Helvetica. Zero gradientes, zero glassmorphism, zero "design da moda".
2. **Atendente primeiro, admin depois** — qualquer decisão de UX passa pelo teste "o operador na trincheira ganhou tempo?". Admin aceita 1 clique a mais se o operador economiza 3.
3. **Teclado > mouse sempre** — atalho para tudo o que o atendente faz >10x/dia. Mouse é fallback, não fluxo principal.
4. **Densidade calibrada** — mais conversas visíveis por viewport que Chatwoot padrão, sem sacrificar clique preciso. Toque de WhatsApp Desktop, não de Slack.
5. **Desktop-first honesto** — não fingimos mobile-first. O atendente trabalha em monitor de 1366x768+ o dia inteiro. Mobile é observador, não operador.

---

## 5. Escopo v2

### Must-Have — Onda 1 (esta semana)
- Tokens globais WA aplicados em todas as telas principais (Conversa, Settings, Reports, Kanban).
- Rail lateral fixo 72px com todos os 8 itens principais (Conversations, Contacts, Reports, Campaigns, Automation, Helpdesk, AI Agents, Settings).
- Tabs responsivos na ConversationHeader sem scroll horizontal <1280px.
- Polimento de hardcodes de cor (`#1f93ff`, `#44ce4b`, etc.) → tokens WA.
- Dark mode funcional em 100% dos componentes tocados.

### Should-Have — Onda 2 (próximas 2 semanas)
- **Quick Reply Chips** no ReplyBox (atalhos visuais por inbox, top 5 macros).
- **Pin de conversas** WA-style (pin/unpin com ícone, conversa sobe para topo da lista).
- **Cheatsheet de atalhos** (Cmd+/ abre modal com todos shortcuts agrupados).
- **Typing indicator** animado (três pontos estilo WA quando contato digita).
- **Notes internas em bubble amarelo** proeminente (ao invés de linha separadora cinza).
- **Transcrição de áudio inline** (botão expand no bubble de áudio, chama Whisper via WAHA).

### Could-Have — Onda 3 (mês seguinte)
- **Copilot IA em drawer lateral** (contextual à conversa aberta, sugestões de resposta).
- **CRM lateral com tabs** (Contato / Histórico / Pedidos / Notas / Atividade).
- **Multi-view** da lista de conversas (lista padrão / kanban por status / densa só-texto).
- **Macros compostas** (macro que dispara N ações: responder + atribuir + aplicar label + fechar).

### Won't-Have (agora)
- Mobile-first / PWA dedicado ao atendente mobile.
- Alterações no backend Chatwoot (tudo front + composables).
- Novos canais além de WhatsApp/Instagram/Email/Webchat já existentes.
- Multi-tenancy SaaS novo (separado deste PRD).

---

## 6. Métricas de Sucesso

| KPI | Baseline | Meta 60d | Como medir |
|-----|----------|----------|-----------|
| Tempo médio 1ª resposta | ~4min [assumption] | -20% (≤3min) | Reports nativo Chatwoot |
| Conversas resolvidas / agente / dia | ~35 [assumption] | +15% (≥40) | Reports nativo |
| Taxa de adoção Quick Replies | 0% (não existe) | ≥40% após 30d | Evento frontend `quick_reply_used` |
| CSAT interno do atendente (NPS) | não medido | ≥50 | Pesquisa pós-rollout |
| Tickets de suporte N1 "como faço X" | ~15/semana [assumption] | -30% | Contagem manual Walisson |

---

## 7. Critérios de Aceitação

- [ ] Paleta WA aplicada em 100% das 4 telas principais (Conversa, Settings, Kanban, Reports).
- [ ] Zero scroll horizontal em viewport ≥1024px em todas as rotas principais.
- [ ] Atendente experiente resolve uma conversa do começo ao fim apenas com teclado.
- [ ] Dark mode visualmente paritário ao light em todas telas tocadas.
- [ ] Lighthouse Desktop ≥85 nas rotas críticas (/conversations, /dashboard).
- [ ] Nenhuma regressão funcional em comparação com branch `producao` (validado por @qa).
- [ ] i18n pt-BR cobre 100% das strings novas; en fallback presente.

---

## 8. Plano de Rollout

| Fase | Prazo | Ambiente | Público |
|------|-------|----------|---------|
| **Fase 1** | Semana 1 (18-25/abr) | Homologação (hmlchat) | Equipe interna Simplex |
| **Fase 2** | Semana 2 (26/abr-02/mai) | Produção com feature flag | Clara Tozi (piloto), 1-2 clientes consentidos |
| **Fase 3** | Semana 3-4 (03-16/mai) | Produção geral + SaaS | Todos os clientes (flag default ON, toggle de opt-out) |

Rollback: toggle "interface clássica" no perfil do usuário mantido por 60 dias pós-Fase 3.

---

## 9. Riscos (Top 5)

| Risco | Sev | Mitigação |
|-------|-----|-----------|
| Atendente veterano resistir à mudança visual | 🔴 Alto | Toggle "interface clássica" 60d + vídeo de 90s mostrando o que mudou |
| Admin perder acesso rápido a Settings (rail mais minimalista) | 🟡 Médio | Atalho `Cmd+,` sempre visível + item "Settings" fixo no rail |
| Fidelidade WA gerar risco jurídico (Meta) | 🟡 Médio | Não copiar logo/nome/ícone Meta; inspiração de paleta e layout é lícita |
| Piloto Clara Tozi detectar bug crítico e bloquear Fase 3 | 🟡 Médio | QA + @qa gate antes de cada fase; feature flag reversível em 1 clique |
| Performance cair com novos componentes (drawer IA, CRM lateral) | 🟢 Baixo | Lazy-load drawers; Lighthouse no CI |

---

## 10. Dependências

- **@analyst** entrega research (BR + global — Digisac, Omni, Huggy, Intercom, Front, Missive, Crisp) **antes** de congelar escopo das Ondas 2 e 3.
- **@ux-design-expert** entrega design system (tokens finalizados, 10 componentes-chave em Figma/HTML mock) **antes** do @dev implementar Onda 2.
- **@architect** valida plano técnico (estrutura components-next, estratégia de migração, impacto Enterprise overlay) **antes** de qualquer refactor >200 LOC.
- **@qa** valida em homologação **antes** de cada transição de fase (1→2, 2→3).
- **@devops** responsável por feature flag, rollout e rollback.

---

## 11. Timeline

| Semana | @analyst | @ux-design-expert | @architect | @dev | @qa | @devops |
|--------|----------|-------------------|-----------|------|-----|---------|
| **S1** (18-25/abr) | Research BR+global | Design tokens Onda 1 | Plano técnico Onda 1 | Implementa Onda 1 (Must-Have) | Gate Fase 1 | Deploy hml |
| **S2** (26/abr-02/mai) | Research profundo Onda 2 | Design system Onda 2 | Review arquitetura drawer/CRM | Implementa Onda 2 (Should-Have) | Gate Fase 2 | Flag + deploy piloto |
| **S3** (03-09/mai) | Synthesis + playbook | Design Onda 3 | Plano Copilot drawer | Implementa Onda 3 (Could-Have) início | Gate Onda 3 parcial | Monitoramento piloto |
| **S4** (10-16/mai) | Post-launch analysis | Polimento + ajustes | — | Finaliza Onda 3 + polimento | Regressão geral | Rollout geral + SaaS |

---

**Aprovação:** Walisson (founder) — assinar abaixo
**Próximo passo:** @analyst e @ux-design-expert em paralelo a partir da aprovação deste PRD.
