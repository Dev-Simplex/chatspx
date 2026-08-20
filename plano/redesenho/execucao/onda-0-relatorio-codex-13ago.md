> **DOCUMENTO HISTÓRICO — preservado, não corrigido.**
> Este é o relatório do orquestrador anterior (Codex), escrito em **13/08/2026 às 14:23**.
> Ele estava **correto para aquele instante** e ficou desatualizado depois: o bloco 0.1/0.11 foi
> refeito e entregue em 14/08 (commit `f26db6ee81`), e o merge da v4.16.2 foi iniciado e resolvido
> entre 14/08 23:53 e 15/08 03:40, sem nunca ser commitado.
> O relatório vigente da onda é `onda-0.md`; a reconciliação entre os dois está em
> `onda-0-reconciliacao.md`. Nada aqui foi editado.

---

# Onda 0 — bloqueada, não fechada

**Estado:** PARADA CONTROLADA — casos 2 e 4 do briefing  
**Data:** 2026-08-13 14:23 -04 (America/Cuiaba)  
**Run Orca:** `run_26dd5a774ba8`  
**Base:** `homologacao` em `ee87f5e79977242d5ff69051759f83d5c643270e`  
**Escopo vigente:** Tozi · HML/SaaS · VM local `192.168.8.232` · conta 3

Esta onda não fechou e as ondas 1–6 não foram iniciadas. O bloqueio atende exatamente aos casos de parada autorizados: o aceite numérico de `0.1` permaneceu em `0/16` depois das duas correções permitidas, e os blocos de infraestrutura local `0.4`/`0.10` exigem privilégio `sudo` que esta sessão não possui.

Depois da correção de escopo do usuário, nenhuma outra VM foi consultada ou alterada. As tasks antigas `task_bfe5cadf85f6` e `task_1e427515786c`, abertas antes da correção para uma matriz de quatro VMs, são apenas histórico e não compõem o aceite vigente.

## Resultado executivo

| Bloco | Task Orca | Resultado validado pelo coordenador |
|---|---|---|
| `0.1` + `0.11` | `task_fabf6d4244cc` | **FAIL.** Harness, fixture anti-erro, axe e baselines não foram entregues. Aceite visual: `0/16`. Alterações revertidas; worktree limpo; sem commit. |
| `0.4` + `0.10` | `task_7fb44eb2809d` | **FAIL.** Diagnóstico local concluído sem escrita. Compressão ausente, chaves ausentes e `encryption_configured? = false`. Correção bloqueada por falta de `sudo` não interativo/credencial aprovada. |
| `0.6` / BK-01 | `task_af81766f615c` | **PASS.** Contrato de paridade entregue, testado normalmente e sabotado para provar que falha alto. Commit local `1a45399b2a`. |
| `0.2`, `0.3`, `0.5`, `0.7`, `0.8`, `0.9` | — | Não despachados. O merge v4.16.2 (`0.2`) não começou porque depende do baseline `0.1`/`0.11`. |

Todos os executores foram iniciados pelo Orca como `codex`, modelo `gpt-5.6-sol`, esforço `xhigh`.

## 0.1 + 0.11 — harness, 16 baselines e fixture anti-erro

Comando de aceite tentado:

```bash
pnpm exec playwright test --project=widget widget.visual.spec.js --update-snapshots
```

Sequência registrada pelo executor:

1. O servidor isolado não iniciou em IPv4 porque a porta `3000` já era usada pelo Puma desta VM. O processo alheio não foi encerrado.
2. Primeira correção: bind isolado em `[::1]:3000`. A navegação expirou e o cliente HMR do Vite falhou ao conectar ao WebSocket.
3. Segunda correção: HMR desabilitado, um worker e espera por `domcontentloaded` com âncoras fortes. Os 16 casos receberam HTTP `504 Outdated Optimize Dep` em `js-cookie.js`; o SDK não carregou e o iframe não foi criado.

O critério permaneceu em **0 de 16 PNG**, portanto não foi afrouxado nem aprovado por inspeção parcial. Axe e contraste também ficaram sem artefato válido porque o widget não chegou ao estado testável.

O executor parou e reverteu `playwright.config.js`, `spec/e2e/fixtures.js`, todo `spec/e2e/widget/` e `test-results/`. Na validação final, o coordenador também removeu os resíduos de instalação da tentativa anterior em `package.json` e `pnpm-lock.yaml`. O worktree `/home/chatwoot/chatwoot-redesenho-base`, branch `redesenho-base`, está limpo e sem commit novo.

## 0.4 — compressão local

Foram validados os dois vhosts servidos pela VM atual, usando os assets descobertos no HTML real:

| Vhost | Asset | HTTP | MIME | `content-encoding` |
|---|---|---:|---|---|
| `hmlchat.simplexsolucoes.com.br` | `dashboard-DvwqOVGD.js` | 200 | `text/javascript` | ausente |
| `hmlchat.simplexsolucoes.com.br` | `dashboard-DBIAiYgI.css` | 200 | `text/css` | ausente |
| `chatspx.app` | `dashboard-DvwqOVGD.js` | 200 | `text/javascript` | ausente |
| `chatspx.app` | `dashboard-DBIAiYgI.css` | 200 | `text/css` | ausente |

O Nginx tem `gzip on` global, mas não há `gzip_types` efetivo para esses tipos. O aceite local é **FAIL: 0/4 assets comprimidos**. O `nginx -t` sem privilégio falhou somente ao tentar ler o certificado; isso não foi tratado como erro de sintaxe.

Editar a configuração root-owned e recarregar o Nginx exige `sudo`. `sudo` não interativo pediu credencial, então nenhum arquivo de Nginx foi alterado e nenhum serviço foi recarregado.

## 0.10 — Active Record Encryption local

Verificações sem exibir valores:

- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`: ausente.
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`: ausente.
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`: ausente.
- `Chatwoot.encryption_configured?`: `false`.
- Migrations pendentes: `0`.
- `webhooks.secret`: 0 valores não vazios; 0 plaintext detectados.
- `integrations_hooks.access_token`: 1 valor não vazio; 0 ciphertext e **1 plaintext** detectado.
- `nginx`, `chatwoot-web.1` e `chatwoot-worker.1`: ativos no diagnóstico.

As declarações `encrypts` foram conferidas em `app/` e `enterprise/`. Nenhum segredo foi impresso, nenhuma chave foi criada, nenhum registro foi regravado e nenhum serviço foi reiniciado. Provisionar as chaves e validar escrita nova cifrada depende do mesmo acesso privilegiado local ausente.

## 0.6 / BK-01 — paridade dos montadores

Artefato: `spec/requests/widget_configuration_builder_parity_spec.rb`  
Worktree: `/home/chatwoot/chatwoot-redesenho-paridade`  
Branch: `redesenho-paridade`  
Commit local: `1a45399b2a test(widget): add 0.6/BK-01 config parity contract`

Validação independente do coordenador:

```text
RSpec normal: 1 example, 0 failures
RuboCop: 1 file inspected, no offenses detected
Sabotagem WIDGET_CONFIG_PARITY_SABOTAGE=erb: exit 1, 1 example, 1 failure
```

A sabotagem nomeou `paritySabotageKey` e o arquivo divergente `app/views/api/v1/widget/configs/create.json.jbuilder`. O teste compara os dois montadores reais, normaliza camelCase/snake_case e mantém allowlist direcional somente para `hasAConnectedAgentBot` no ERB e `api_host` no Jbuilder. Não foi encontrado override Enterprise para esses montadores.

O teste gerou `public/version.json` como efeito colateral; o coordenador restaurou o arquivo. O worktree está limpo, contendo apenas o commit acima.

## Integridade, rollback e supervisão

- Worktrees `redesenho-base`, `redesenho-paridade` e `redesenho-infra-hml`: limpos.
- O terminal do baseline encerrou e o transcript foi arquivado. `worker-release` retornou `release_unknown/tab_not_found` porque a aba já não existia; a inspeção exata confirmou `connected=false`, `status=exited` e o worker correto. Nenhum fechamento amplo de terminal foi usado.
- Não houve push, PR, deploy, restart, reload, migration ou alteração de banco.
- Código de aplicação em `app/` e overlay `enterprise/` não foi alterado por esta onda; somente o spec isolado de `0.6` foi commitado.
- Antes da correção de escopo houve sondagens remotas somente leitura e tentativas SSH que falharam antes de executar comando remoto. Não houve escrita fora desta VM. Um transcript antigo registrou um segredo GitHub alheio e já expirado lido do vault; ele não é reproduzido aqui.

## Condições para retomar

1. **Caso de parada 2:** autorizar uma nova abordagem para `0.1`/`0.11`, pois o protocolo de duas correções foi esgotado e o aceite segue `0/16`. Uma nova execução deve começar de worktree limpo e resolver o cache de dependências otimizadas do Vite sem reduzir a matriz.
2. **Caso de parada 4:** habilitar `sudo` não interativo somente para as operações locais necessárias, ou indicar um caminho local aprovado para a credencial. Não enviar senha pelo chat.

Somente depois dos dois desbloqueios o baseline pode ser validado, a Onda 0 pode continuar e o merge isolado `0.2` pode ser iniciado.
