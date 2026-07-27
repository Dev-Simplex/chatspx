# Análise de conversas — Tozi (conta 6, PROD)

Corpus vivo pra **observar falha real → corrigir → provar que melhorou**. Serve a dois públicos:

- **Sessões Claude** — o protocolo abaixo deixa qualquer sessão pegar e ajudar na análise sem redescobrir tudo.
- **A IA (Clara/Bruna)** — cada falha recorrente vira um de três destinos: *guardrail* (config no banco da conta), *scenario* (teste dourado) ou *commit* de código.

> ⚠️ **Isolamento.** Estas são conversas reais de **Tozi · conta 6 · `3.82.215.109`**. Leitura é read-only. Fix de conduta vai pro **banco da conta 6** (nunca no molde compartilhado `enterprise/lib/captain/prompts/assistant.liquid` — vaza pra outros clientes).

## Taxonomia — a MESMA do eval nativo (não inventar outra)

De `enterprise/lib/captain/conversation_eval_schema.rb`, pra análise manual e eval automático somarem em vez de virar silos:

- **categoria**: `alucinacao` · `info_incorreta` · `nao_respondeu_pergunta` · `narrou_ferramenta` · `tom_robotico` · `repeticao` · `exemplo_copiado` · `quebrou_regra` · `promessa_indevida` · `handoff_ausente` · `handoff_tardio` · `fora_horario_mal_tratado` · `outro`
- **handoff_timing**: `nao_precisou` · `no_prazo` · `tardio` · `precisava_nao_fez`
- **severidade**: `baixa` · `media` · `alta`

## Estrutura

| Item | O que é |
|---|---|
| `_dump.rb` | Puxa transcrição de conversa(s). **READ-ONLY.** |
| `raw/<id>.md` | Transcrição verbatim (imutável). A fonte. Regenerável via `_dump.rb`. |
| `casos/<id>.md` | Análise anotada: achados na taxonomia + comportamento ideal + status do fix. |
| `PADROES.md` | Rollup: causa-raiz recorrente × frequência × fix × verificação. **A memória de treino.** |

## Como puxar uma conversa (a URL vira id)

URL `https://tozi.chatspx.app/app/accounts/6/conversations/18973` → **conta 6, display_id 18973**.

```bash
LOCAL=docs/clientes/tozi/analise-conversas/_dump.rb
bash scripts/ops/tozi-prod.sh put "$LOCAL" /tmp/_dump.rb
bash scripts/ops/tozi-prod.sh run "bundle exec rails runner /tmp/_dump.rb 6 18973 18986"
```

Cola a saída em `raw/<id>.md` (condensa anexos pra `[📷 imagem]` / `[🎤 áudio]` e derruba as URLs assinadas — elas expiram e são ruído).

## O loop (o que uma sessão Claude faz aqui)

1. **Puxa** → `raw/<id>.md`.
2. **Analisa** → `casos/<id>.md` na taxonomia acima (um achado por resposta com falha).
3. **Consolida** → achado que repete sobe pra `PADROES.md`.
4. **Corrige** → guardrail (config banco c6, sem restart) · scenario · commit. `PADROES.md` linka o fix **E** a verificação.
5. **Prova** → eval nativo (quando estiver na c6) alimenta `PADROES.md` com nota antes/depois; ou re-teste isolado via `AgentRunnerService`.
