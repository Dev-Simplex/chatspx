# 2026-07-14 — Modelo de handoff refeito + follow-up timing + pós-humano (7 agentes, prod c6)

> Sessão de análise (Paulo + Claude) sobre 4 conversas reais de prod. Virou reescrita de config nos 7 agentes da conta 6, via Almirante (`update_prompt`, test-gated por dry-run, reversível por change_set).

## Conversas analisadas

| Conv (display_id) | Achado | Categoria eval |
|---|---|---|
| 19222 | Lead qualificado (locação) esfriou; Bruna **ofereceu/perguntou** consultor 2× e **não acionou** o handoff → lead foi pra concorrência | `handoff_ausente` |
| 19221 | Lead disse "vou esperar meu noivo pra decidir"; Bruna **não programou follow-up** nem perguntou quando retomar | `handoff_ausente` / follow-up ausente |
| 19152 | Cliente voltou chamando a atendente humana (Cibely) pelo nome; **Letícia respondeu "a Cibely já finalizou o atendimento"** e se pôs como substituta | `tom_robotico` / novo padrão pós-humano |
| 19229 / 2159 | Busca por CÓDIGO quebrada: `track_imoveis` undefined → `NoMethodError` → falso "problema técnico" DEPOIS de o Vista achar. Fix `0d9d08238` na `producao`, **hotfix em andamento pelo Nicolas** | (código) |

## Modelo de handoff (o que passou a valer)

1. **Handoff é o destino padrão**, não exceção. Quase toda conversa com interesse/necessidade definida termina em handoff. Exceção (resolve sozinha): dúvida simples 100% sanada, info básica, saudação, spam.
2. **Rotear é decisão da IA e não depende de o cliente pedir/confirmar.** Proibido "quer que eu passe pro consultor?" como substituto da ação.
3. **Disclosure situacional:** silencioso, avisar que passou, ou oferecer — o que a conversa pedir. Oferta/aviso nunca substitui a ação (acionar ≠ narrar; se disse que vai passar, aciona na mesma resposta).
4. **Novo gatilho** (era o buraco do 19222): "mostrou opções e o lead não engatou/não gostou → passa pro humano recuperar".
5. **Follow-up com timing** (19221): quando a decisão depende de falar com alguém/pensar/ver depois, perguntar quando consegue retomar e marcar a cutucada pra essa janela.
6. **Pós-humano** (19152): cliente que volta chamando atendente por nome ou continuando thread humana → não anunciar que o humano encerrou; devolver pro time/pessoa, sem re-triar do zero.

## Change-sets aplicados (prod c6, via Almirante — rollback por esse id)

| Agente | id | change_set (rollback) | Deltas |
|---|---|---|---|
| Bruna | 14 | `cs_2026-07-14T23:25:19Z_b3d48bcc` | handoff reframe + follow-up timing |
| Júlia | 13 | `cs_2026-07-14T23:33:39Z_e60374d9` | handoff reframe + follow-up timing |
| Letícia | 15 | `cs_2026-07-14T23:36:45Z_a1b41a09` | handoff reframe + follow-up + **pós-humano** |
| Marina | 16 | `cs_2026-07-14T23:57:16Z_e09d1dcf` | handoff reframe + follow-up timing |
| Rafa | 17 | `cs_2026-07-15T00:10:28Z_14e3383d` | handoff (destino padrão) + follow-up timing |
| Helena | 18 | `cs_2026-07-15T00:10:41Z_7888a1b7` | handoff (destino padrão) |
| Clara | 7 | `cs_2026-07-15T00:12:09Z_2c8eaf77` | **pós-humano** (não re-triar quem continua atendimento humano) |

Rollback: `almirante_ai_rollback(vm:'tozi', change_set_id:'…')`.

## Pendente

- **CÓDIGO (Track B):** cadência de follow-up esgota sem resposta → **handoff automático**. ✅ Implementado + commitado + pushed na `homologacao` (`28b04cb9d`): novo `Captain::Conversation::HumanHandoffService` (extraído do `HandoffTool`), `FollowupJob#cool_down_lead` escala pra humano em vez de disparar reativação HSM. ⏳ **Pendente deploy+verify na 232** (Nicolas: pull + restart; rodar `zeitwerk:check` + rspec dos 2 specs + E2E de lead que esgota cutucadas). Não verificado localmente (sem Ruby na máquina). Só o gatilho do esgotamento mudou; `salvar_info_lead` segue usando reativação HSM.
- **Áudio (P6):** corrida da transcrição async — o turno responde no placeholder `[áudio]` antes de o cache encher (`open_ai_message_builder_service.rb:127`). Fix: segurar/re-debounce o turno até a transcrição chegar. Código, homolog.
- **Judge do Almirante:** desabilitado (chave OpenAI no host `painel.chatspx.app`, fora do alcance). NÃO é o eval nativo do SPX (esse funciona via `CAPTAIN_OPEN_AI_API_KEY`). Dispensável — validação real = observar conversas + eval nativo.
- **Observação:** validar o comportamento novo em conversas reais de locação/vendas/financeiro (o test-gate do Almirante não roda juiz, só dry-run).

## Adendo 15/07 — busca de imóvel (código + links) e pin do escritório

| Conversa | Achado | Fix |
|---|---|---|
| 19229 / 2159 | busca por CÓDIGO quebrada (`track_imoveis` NoMethodError → falso "problema técnico" depois do Vista já achar) | `0d9d08238` na `producao` |
| 19271 | **links da IA sumiam** — o sanitizador `fix_property_links` (response_builder_job.rb) apaga todo link cujo código não esteja em `urls_imoveis`; esse mapa ficava sempre vazio porque a **mesma regressão dropou o `track_urls`** | `80edd1114` na `producao` (restaura `track_urls` + chama nos 3 caminhos de busca; aditivo, +23 linhas) |
| 19137 | pin do **escritório** não ia — os especialistas não tinham o tool `enviar_localizacao` (só a Clara); a Bruna deu o endereço em texto (fallback correto, mas sem pin) | ✅ tool `enviar_localizacao` habilitado na Bruna #14 / Júlia #13 / Letícia #15 (config c6, direto no banco — Almirante não suporta arm_tool; sem restart) |

**Os dois fixes de código (19229 + 19271) estão empilhados em `origin/producao` — 1 deploy resolve os dois.** ⏳ Nicolas na 232: `git pull origin producao` + `zeitwerk:check` + restart web/worker + E2E (buscar por código volta; link chega).

**Chave do sanitizador de link:** `urls_imoveis` (mapa código→URL canônica de `build_url`) alimenta o `fix_property_links`. Vazio = TODO link da Tozi apagado. Populado por `track_urls` (buscar_imovel_tool). Regressão: a "renomeação" que quebrou `track_imoveis` dropou `track_urls` junto — e o hotfix `0d9d08238` (só troca linha 36 pra `track_codigos`) NÃO restaura, por isso o fix separado.

**Nota (19137):** apliquei só o tool, não a nota no prompt — as descrições dos dois tools (`enviar_localizacao`=escritório; `enviar_localizacao_imovel`=imóvel) são diretivas o bastante. Observar: se a regra "onde fica → texto" (contexto de imóvel) vazar pro caso do escritório, aí adiciona 1 linha no prompt.

## Adendo 15/07 (tarde) — afinação do handoff (mais agressivo) + busca consultiva

3 conversas mostraram que o modelo aplicado 14/07 ainda passava TARDE demais: a IA fazia um pré-atendimento bom mas nunca acionava o handoff.

| Conversa | Agente | O que faltou |
|---|---|---|
| 19272 | Bruna | ofereceu "esperar pra ver se aparece" em vez de handoff; e disse "não temos até R$X" em vez de buscar a melhor opção perto acima da faixa |
| 19271 | Bruna | mostrou 3 casas + fotos, lead engajada, mas nunca acionou |
| 19269 | Sofia (leads campanha) | lead pré-qualificado pelo anúncio, e a IA seguiu pedindo renda em vez de passar |

**Duas afinações aplicadas (config c6, Almirante, reversível):**

- **A — handoff cedo (P5):** aciona assim que o lead está qualificado+interessado, MESMO indeciso. Como é silencioso e a IA segue respondendo, passar cedo custa zero — o humano decide se assume. Mata "esperar pra ver se aparece", dump de fotos e qualificação esticada. Sofia (campanha): renda/enquadramento vira pendência do corretor, não trava o handoff. change-sets: Bruna `cs_2026-07-15T18:24:27Z_d4e0756f`, Júlia `cs_2026-07-15T18:30:19Z_32b8eab0` (A+B), Sofia `cs_2026-07-15T18:32:21Z_2f04aa68`.
- **B — busca consultiva (P12):** quando o exato não existe, a IA não responde só "não temos" — entende que o cliente valoriza a proximidade, busca a melhor opção real inclusive um pouco acima da faixa, e apresenta o tradeoff (mais barata+longe vs mais perto+um pouco mais cara) pra ele escolher. Só Bruna/Júlia (as que buscam imóvel). change-sets: Bruna `cs_2026-07-15T18:34:44Z_013cc323`, Júlia (junto no `…32b8eab0`).

**Observar (juiz Almirante off):** não super-corrigir — handoff cedo demais (antes de mostrar opção) ou oferecer muito acima do orçamento. Freios no prompt: só passa DEPOIS de mostrar opção; na busca oferece as DUAS (na faixa + um pouco acima). Rollback de qualquer afinação = `almirante_ai_rollback` com o change-set.

## Adendo 15/07 (noite) — "Me chama depois" invertido (Sofia, leads de campanha) — P14

Print de teste do Paulo (conv 2159): Sofia mandou o template de abertura de campanha com quick-replies **"Quero saber" / "Me chama depois"**; o lead clicou em **"Me chama depois"** e a Sofia respondeu *"Fico no aguardo então"* + *"Qualquer coisa, é só chamar"* — **inverteu a bola**. No banco a cutucada até estava programada (`followup_status="cutucada auto-programada em ~120 min"`, `tozi_status_lead="qualificado"`), mas o **texto** largou a iniciativa no cliente.

**Intenção de design (Paulo):** "Me chama depois" é o botão POSITIVO de adiamento (existe no lugar de um "não tenho interesse") — é pra **gerar compromisso de retorno em outro horário**, não despedida.

**Fix (config c6, Sofia #19, Almirante — reversível):** seção nova **"'Me chama depois' é compromisso, não fim de papo"**: quem clica está interessado, só quer falar depois → a IA **assume o compromisso de retorno** (é a Tozi que chama, não o lead que volta), pergunta o **melhor horário/dia**, e **programa a cutucada** (`programar_followup`) pra essa janela; proibido inverter ("fico no aguardo"/"qualquer coisa é só chamar"). change-set: Sofia `cs_2026-07-16T00:02:48Z_2a1c8c77`. Dry-run passou; smoke+juiz skipped (sem chave OpenAI no painel).

## Adendo 16/07 — handoff sumido na REABERTURA (Clara) — P15

Conv **19112** (proprietária Marina, vistoria de saída de locação). O handoff funcionou na 1ª rodada (10/07, evento `conversation_bot_handoff` → team #31 "vistoria" → Natalia humana atendeu). Natalia **resolveu 14/07 e removeu o time** ao resolver. **16/07** Marina voltou cobrando o retorno; a conversa reabriu **sem time** → automação #61 (sem-time→Clara) → **a Clara só tranquilizou** ("o time já vai te retornar / vou reforçar") e **não reacionou o handoff**. Resultado: `open`, team=nil, assignee=nil = **órfã**, ninguém vê.

**Causa exata:** duas regras da Clara brigando — a guarda **"handoff só UMA vez, nunca de novo"** (anti-spam) **não tinha fronteira** e disparava atravessando o resolve→reabertura (ela viu "já chamei o time" do 10/07); e a regra **pós-humano** dizia "devolva pro time" sem deixar claro que *devolver = ACIONAR a ferramenta*. A anti-spam ganhou → tranquilizou sem rotear.

**Fix (Clara #7, config, reversível):** (1) escopei o "uma vez" ao *atendimento em andamento*; reabertura-após-resolve com pendência = NOVO ciclo → DEVE reacionar o handoff. (2) "devolver pro time" agora é explicitamente ACIONAR o handoff, não narrar. change-set Clara `cs_2026-07-16T17:06:34Z_aa8d9a2a`. Dry-run passou; smoke+juiz skipped.

**Rescue operacional (16/07, feito):** 19112 devolvida ao **time #31 + Natalia Silva** (assignee que já tratava) via runner — `agent_bot` limpo pelo callback (IA fora), notificação de atribuição disparada, mensagens re-sincronizadas pro time. Marina saiu do limbo.

**Estrutural (decisão do Paulo — NÃO aplicado, por ora coberto pelo fix da Clara):** (a) times humanos funcionais sem IA (ex.: #31 vistoria) não têm regra de reabertura própria → catch-all manda pra Clara; (b) hábito do humano de **remover o time ao resolver** apaga o contexto de roteamento. Posição: o fix da Clara estanca o sangramento (ela reencaminha na reabertura → vistoria/desocupação vai pra Letícia por design), então NÃO adicionei regras de automação especulativas; só mexer nisso se o padrão recorrer.
