# Fase B — Relatório de VALIDAÇÃO do código existente (2026-06-11)

> Escopo alterado por instrução do usuário (AD-11): não implementar — validar o que já
> foi feito por outro dev (branch `paulao`, mesclada) contra os requisitos B1–B7.
> Verificação por 3 agentes exploradores + histórico git. Citações = código real.

## O que JÁ ESTÁ FEITO no código (trabalho do outro dev)

| Item | Evidência |
|---|---|
| **B1 (1ª metade)** — `config['instructions']` VALE no prompt v2 (a "armadilha" do plano está desatualizada) | commit `7e8353fa8`; `assistant.rb:149` injeta `instructions` no prompt_context; `assistant.liquid:9-14` renderiza bloco "Your Persona and Behavior" com prioridade sobre identidade genérica |
| **Tools de negócio existem e funcionam** (armadas via CENÁRIOS) | `enterprise/lib/captain/tools/`: `buscar_imovel`, `enviar_fotos_imovel`, `programar_followup`, `salvar_info_lead`, `add_label_to_conversation`, `resolve_conversation`, `update_priority`, `http_tool` etc.; cenário materializa refs `[X](tool://id)` em `scenario.tools` validadas contra `assistant.available_agent_tools` (`scenario.rb:108-115`) |
| **B5 (propósito coberto por outro caminho)** — sync de assistant entre ambientes | `rake captain:export/import` (`lib/tasks/captain_sync.rake`, commit `468674c55`): exporta/importa tabelas captain_* de UM assistant com embeddings, dry-run por padrão, backup automático |
| Infra de atendimento humanizado | RAG por chunks híbrido (`b6787cc3d`), humanizer/typing (`0b3307830`, `71629abe1`), transcrição de áudio (`1671b9017`), fixes de handoff v2 (`02bcbac0f`), fotos WhatsApp (`c7d425a4f`, `856c52aa4`) |
| Equipe de agentes criada na sandbox | commit `428e97b24` "equipe de 6 agentes criada na sandbox hmlchat (conta SimplexIA)" |

## O que do plano B1–B7 NÃO está no código (gaps — reportados, não implementados)

| Item | Estado real | Evidência |
|---|---|---|
| B1 (2ª metade) | Template ainda tem identidade de ORQUESTRADOR | `assistant.liquid:2` ("multi-agent AI system... handoff functions"), `:5` ("act as an orchestrator"), `:71-78` (Decision Framework manda handoff pra scenario agents), `:19` (regra FAQ-only conflita com tools de negócio) |
| B2 | Cenários AINDA são sub-agentes LLM separados com handoffs bidirecionais (não subprompts concatenados) | `agent_runner_service.rb:167-175` (`build_and_wire_agents`) — citação do plano exata, sem drift |
| B3 | ~~não implementado~~ → **FEITO pelo Paulo às 22:25** (commit `c69979876`): `configured_agent_tools` arma tools de negócio via `config['tools']` validado contra `available_agent_tools` (filter_map descarta inválidos; custom tools via slug) | `assistant.rb` pós-c69979876 — assistant standalone agora pode ter buscar_imovel/enviar_fotos sem cenário |
| B4 | `agent_name` legado (`scenario_X_*_agent`) cai SILENCIOSAMENTE no default da gem; nenhum filtro/log | gem `ai-agents-0.9.1 agent_runner.rb:216-235`; persistência em `response_builder_job.rb:254-266`, releitura em `:76`. Interage com C7 (IA→IA): histórico com agent_name da IA anterior cai no default da nova, sem sinal |
| B5 (literal do plano) | Rake de CRIAÇÃO de agentes por nicho + DUPLICAÇÃO de knowledge não existe (precedente `aws_create_faq.rb` citado no plano não existe no repo) | `lib/tasks/` só tem captain_chat/captain_mirrors/captain_sync. Armadilha p/ futuro: duplicar Q&A religada a Document dispara FAQ-builder que DESTRÓI e re-gera via LLM — duplicar com `documentable: nil` |
| B6 | Modelo LLM por assistant não existe (só conta → global) | `agentable.rb:45-48`; cuidado: `Agentable` incluído por `Scenario` que não tem `config` |
| B7 | ScenariosTab ainda rotulada como cenários/orquestrador; placeholders i18n falam "mostrado ao orquestrador" e "Prompt completo deste sub-agente" | `ScenariosTab.vue:151`, chaves `CAPTAIN.AGENT_TABS.SCENARIOS.*` (pt_BR e en) |

## Leitura de produto (IMPORTANTE para o Walisson)

O outro dev resolveu o problema funcional ("agente com prompt rico + tools de negócio")
por um caminho DIFERENTE do plano: manteve cenários como sub-agentes LLM e armou as
tools via cenários. Isso **diverge de D-7** ("cenários viram subprompts; deixam de ser
roteamento"). Ao instruir pular a fase, o usuário na prática aceitou o caminho existente.
Consequências práticas de manter como está:
1. 1º turno pode continuar com hop duplo (orquestrador→cenário) — o plano queria 1 chamada.
2. O aceite "subprompt muda comportamento sem segundo agente LLM" não vale no modelo atual.
3. B4 (agent_name legado) segue sem filtro — relevante para transferência IA→IA (Fase C/C7).
4. Assistant SEM cenário continua sem tools de negócio (armar exige cenário).

Nada disso quebra as Fases A/C/D (gate por atribuição é independente de como o prompt
é montado). Itens 3 e 4 serão considerados no desenho da Fase C (C7).

## Veredito
- **Funcional**: tools e atendimento da IA operam via cenários — confirmado no código e na sandbox (equipe de 6 agentes).
- **vs. plano B1–B7**: B1 parcial (instructions ✓, orquestrador ✗), B5 coberto em espírito por `captain:export/import`, B2/B3/B4/B6/B7 não implementados.
- **Ação**: nenhuma implementação (AD-11). Gaps documentados aqui e no relatório final. Seguindo para a Fase C.
