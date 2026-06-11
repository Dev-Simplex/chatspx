# Tese — O triângulo de 3 camadas e o meta-agente (a peça que falta no SPX)

> **Data:** 2026-06-10 · Registro da discussão estratégica Paulo × Claude após o mapeamento completo (`MAPEAMENTO-SPX-ORQUESTRACAO-IA-2026-06-10.md`) e o roadmap (`ROADMAP-IA-COMPLETA.md`).
> **Pergunta de origem:** "sinto que falta uma IA verdadeiramente inteligente que entende como o harness SPX funciona, como se auto-aprimorar, como entender o comportamento dos usuários e dos agentes humanos para melhorar a experiência."

---

## 1. Diagnóstico — por que a sensação de limitação é tecnicamente real

### 1.1 A Clara é um *responder*, não um *worker*

O loop do Captain v2 é: mensagem chega → monta contexto → tool-calling → responde → **a run morre**. Consequências:

- Não **verifica o próprio trabalho** (não relê, não confere se o cliente entendeu, não corrige);
- Não **age fora do turno** — o follow-up (`directive`) é o único embrião de ação espontânea;
- Não **aprende** — toda conversa nasce do mesmo prompt; nada do que acontece flui de volta (o `feature_memory` gera notas que o agente nunca lê — memória write-only);
- Não **explora o ambiente** — as tools são fixas; o agente não descobre o SPX como o Claude Code descobre um repo.

O harness do Claude Code é o oposto: loop persistente que planeja → executa → **observa o resultado → se corrige** → continua. A diferença é de espécie, não de grau.

### 1.2 "No n8n era mais rápido" — verdade parcial que aponta o gap certo

O n8n dava velocidade de **edição** (mexe no node, vê o dado passar). O SPX hoje tem ciclo lento (editar prompt via console → testar no WhatsApp real → ler log). Mas a métrica que importa é velocidade de **validação** — saber se a mudança melhorou ou piorou — e essa **nenhuma das duas plataformas teve até hoje**. Reconstruir velocidade de iteração ≠ voltar ao visual; = construir o ciclo de validação.

---

## 2. O que o mercado de elite faz (Sierra, Decagon, Intercom Fin — 2025/26)

1. **Evals como infraestrutura, não auditoria.** Mudança de prompt é tratada como deploy de código: golden set de conversas reais + replay + LLM-judge ANTES de publicar (Sierra: "Agent Development Life Cycle"). É o "tsc + testes" do mundo de agentes.
2. **Memória como produto.** Perfil estruturado por cliente que o agente lê E escreve + lições destiladas que voltam ao prompt. (No fork, o `ContactAttributesService` está 80% pronto e órfão — é exatamente essa peça.)
3. **Agente como tarefa viva.** O lead é um objetivo de longa duração ("qualificar e agendar"); eventos e relógio acordam o agente pra avançar o objetivo. Os primitivos já existem no SPX (`directive`, follow-up, ScheduledMessages) — falta o modelo mental.

---

## 3. A tese — triângulo de 3 camadas

**A "IA que entende o harness do SPX" NÃO deve ser a Clara.** Engordar o runtime de atendimento explode custo e latência (cliente espera resposta em segundos). A inteligência profunda vai numa camada própria:

```
┌─────────────────────────────────────────────────────────────────┐
│  CAMADA 3 — META-AGENTE (o "engenheiro residente")              │
│  Harness Claude Code / Agent SDK · roda por ciclo (diário/hora) │
│  lê logs+conversas → avalia IA e humanos → propõe e APLICA      │
│  melhorias via API code-first → valida por replay → changelog   │
└──────────────────────────┬──────────────────────────────────────┘
                           │ configura (prompt, KB, behavior, rules)
┌──────────────────────────▼──────────────────────────────────────┐
│  CAMADA 2 — ORQUESTRAÇÃO (worker de lead)                       │
│  funil = estado · eventos+relógio acordam a IA · triagem,       │
│  atribuição, cadência, SLA  (= plano-mestre F1–F2)              │
└──────────────────────────┬──────────────────────────────────────┘
                           │ aciona por mensagem/evento
┌──────────────────────────▼──────────────────────────────────────┐
│  CAMADA 1 — RUNTIME (Clara)                                     │
│  responde mensagens · rápida, barata, com guardrails            │
│  (90% pronta: behaviors + tools + knowledge)                    │
└─────────────────────────────────────────────────────────────────┘
```

### O meta-agente em detalhe (o "Clara Improvement Loop")

Ciclo (diário no começo, depois por hora):

1. **Coletar** — conversas do período + `Captain::AssistantLog` (toda decisão da Clara já é logada) + reporting_events (humanos).
2. **Julgar** — rubrica fixa via LLM-judge: qualificou certo? alucinou? tool na hora certa? handoff no timing? tom? E dos humanos: lead esperando? resposta fora do playbook?
3. **Classificar** — padrões de falha (ex.: "leads de terreno caem no cenário errado", "corretor X não responde sábado").
4. **Propor e aplicar** — editar prompt do cenário (PUT /captain/assistants), adicionar Q&A na knowledge, ajustar behavior JSONB, criar automation rule, abrir tarefa pra tool nova.
5. **Validar** — replay do golden set contra a mudança antes de publicar; comparar score.
6. **Publicar com changelog** — cada mudança registrada, reversível.
7. **Medir** — métricas do dia seguinte fecham o loop.

**Governança:** começa human-in-the-loop (Paulo aprova cada mudança); autonomia gradual conforme o eval prova acerto. Toda mudança com diff + rollback.

**Por que é viável JÁ:** a decisão code-first de abril ("Claude Code configura via API, frontend é viewer") criou exatamente a interface que o meta-agente precisa. O que hoje são sessões manuais com o Claude vira loop permanente via Claude Agent SDK. A Onda 6 do roadmap (worker de evals, porta 8910 — a tool `get_conversation_analysis` já espera esse serviço) é a fundação; o meta-agente é a evolução natural dela.

---

## 4. Quick wins imediatos (antes de qualquer construção grande)

1. **Ligar o Langfuse/OTel** — o runner do Captain **já está instrumentado** (`agent_runner_service.rb`, spans com assistant/conversation/tools). Ligar o backend devolve a visibilidade visual "estilo n8n" das runs: cada decisão, cada tool call, cada token. Custo: configuração, não código.
2. **Playground de conversa** — testar a Clara sem WhatsApp real (o Captain tem endpoint de chat direto com o assistant; é exposição de UI, não construção).
3. **Golden set inicial** — selecionar 20–30 conversas reais (boas e ruins) como base de regressão para toda mudança de prompt daqui pra frente.

---

## 5. Posição competitiva (avaliação honesta)

Em **runtime**, o SPX está acima da média do mercado brasileiro de n8n+Chatwoot (multimodal nativo, behaviors humanizados, tools de negócio, follow-up em 2 camadas). O gap — **que é o mesmo gap dos concorrentes** — está na camada de aprendizado: evals, memória que volta ao prompt, loop de auto-aprimoramento. Quem fechar esse loop primeiro no nicho tem um produto que melhora sozinho toda semana. A vantagem injusta da Simplex: o operador desse loop (harness Claude) já está dentro da operação diária.

## 6. Encaixe no roadmap

| Peça da tese | Onde vive no roadmap |
|---|---|
| Camada 1 (runtime) | Ondas 0–1 (go-live + percepção) |
| Camada 2 (worker de lead) | Ondas 2–4 (mãos, memória, proatividade) |
| Camada 3 (meta-agente) | **Onda 6 expandida** — evals (6.1) é a fundação; meta-agente é 6.6 |
| Quick wins (Langfuse, playground, golden set) | Imediato, paralelo a qualquer onda |
