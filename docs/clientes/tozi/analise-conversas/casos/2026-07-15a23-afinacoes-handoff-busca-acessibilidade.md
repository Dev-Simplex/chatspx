# 2026-07-15 a 23 — Rodada longa: handoff, busca, acessibilidade, código (prod c6)

> Loop de análise de conversas reais (Paulo + Claude) sobre a IA da Tozi (conta 6). Afinações de config via **Almirante** (`update_prompt`, reversível por change_set) e fixes de **código** na `producao` (deploy Nicolas). Tudo com dado de prod read-only + Vista.

## Change-sets de config (rollback: `almirante_ai_rollback(vm:'tozi', change_set_id:'…')`)

| Tema | Agente | change_set | Conversa |
|---|---|---|---|
| "Me chama depois" = compromisso de retorno | Sofia #19 | `cs_2026-07-16T00:02:48Z_2a1c8c77` | 2159 |
| P15 handoff-só-uma-vez atravessava reabertura → reacionar no reopen | Clara #7 | `cs_2026-07-16T17:06:34Z_aa8d9a2a` | 19112 |
| P16 link/código→transfere já; nunca citar valor/característica/garantia | Clara #7 | `cs_2026-07-16T17:59:19Z_70143eb5` → `…19:49:22Z_4bbd1da9` | 19330 |
| P17 seguro fiança NÃO existe (override do prior do modelo) | Clara `…4bbd1da9` · Sofia `…6b05c729` · Bruna `…dd10cc58` · Letícia `…de1fe102` · Marina `…e53982f5` · Júlia `…c16b079a` | (6 agentes) | 19330 |
| P18 busca por bairro (por bairro, singular, faixa de quartos) | Bruna `…c5d422be` · Júlia `…57b30956` | 19402 |
| P20 compromisso de visita/pegar-chave "amanhã" → handoff | Bruna `cs_2026-07-20T20:09:06Z_0ef021ef` | 19461, 19666 |
| P15 reopen re-handoff (mesma trava da Clara) | Sofia `cs_2026-07-20T20:51:09Z_121eb106` | 19701 |
| P22 não sabe ler/escrever → handoff pro HUMANO na hora | Clara `cs_2026-07-22T19:04:05Z_854003b9` | 19755 |
| P23 buscar_imovel = 3ª fonte (estoque real); buscar antes de "não temos" | Sofia `cs_2026-07-23T23:50:47Z_b3854d1c` | 19967 |

**Escopo do P15 confirmado:** só Clara e Sofia tinham a trava "handoff só uma vez"; Bruna/Júlia/Letícia/Marina/Rafa/Helena NÃO têm (não ficam bloqueadas). **Escopo do seguro fiança:** varredura exaustiva (config de todos os agentes, 266 chunks + 77 Q&A da knowledge, código + `assistant.liquid`) = ZERO menção; é **prior do modelo** (garantia-padrão do BR), por isso override em vez de "remover".

## Fixes de código (na `producao` = o que a Tozi prod roda; deploy Nicolas)

| Fix | Commit | Estado |
|---|---|---|
| Categoria comercial usa "Ponto Comercial" (Vista não tem "Sala Comercial") | `8e3fea7d2` (rebase) | ✅ deployado |
| Fotos teto 6→9 + IA oferece link da galeria | `339b53a7e` | ✅ deployado |
| Pin do imóvel sem "(Tozi Imóveis)" no título (mapa snapava pro escritório) | (reconciliação) | ✅ deployado |
| P18 busca ordena por **preço crescente** (não `Codigo desc` arbitrário) | `22fa7049e` | ⏳ pushado, aguarda deploy |

**Vista confirmado:** ordena `ValorLocacao`/`ValorVenda` numérico (não lexicográfico) → ordenação por preço é segura. `Categoria='Casa'` etc. exato; comercial → `LIKE %Comercial%`.

## Diagnósticos que NÃO viraram mudança (resolvidos/infra)

- **8062 (proprietária sem resposta ~4 semanas, inbox 62):** o setup de agente da 62 está OK — CaptainInbox é **tabela many-to-many de elegibilidade** (todos os agentes elegíveis, igual à 91); o "Júlia" que parecia errado era artefato do `find_by`. A causa (mensagens não reabriam) era o **guard de NPS antigo**, já corrigido na reconciliação (`ReopenGuard` preciso deployado — só bloqueia conteúdo que parece nota/skip). Sem ação pendente.
- **Enxurrada de mensagens / turnos sobrepostos (Sofia, 19701):** é P3 (debounce/código), não prompt.
- **Humano não lê o dossiê da IA (19701):** processo/treinamento do time, não IA — o resumo da Sofia estava impecável e o corretor repetiu perguntas.

## Meta-aprendizados (valem pra sempre)

- **Ferramentas > memória; nunca hardcodar fato de produto no prompt.** Paulo vetou (23/07) afinação que ia injetar fato de catálogo ("a Tozi tem revenda pronta"). O certo é regra COMPORTAMENTAL: o que a Tozi tem AGORA vem das ferramentas (buscar_imovel/buscar_empreendimento), a lista no prompt é só ponto de partida (envelhece). Foi a memória hardcoded ("casas = MCMV em construção") que fez a Sofia dizer falso no 19967. Reforça [[feedback-tudo-configuravel-dinamico]] e [[feedback-prompts-sem-scripts]].
- **"Não temos" sem buscar é o padrão recorrente** (P12, P16, P18, P19, P23): a IA que tem ferramenta de busca deve BUSCAR antes de afirmar ausência ou caracterizar estoque.
- **Handoff é o eixo:** o modelo "handoff é o destino padrão" recorreu em várias formas (P5, P10, P15, P20, P22) — cada afinação fechou uma fresta (reabertura, compromisso de visita, acessibilidade).

## Operacional
- Rescue feito: 19112 (Marina) devolvida ao time #31/Natalia (estava órfã pós-reopen).
- ⚠️ Divergência de branch: VM à frente do `origin/producao` com merge `bkp/tozi-wip-vista-2026-07-23` (WIP de vista de outra sessão) — reconciliar com Nicolas.
- ⚠️ Chave OpenAI que o Paulo colou no chat (juiz do Almirante) precisa ser rotacionada.
