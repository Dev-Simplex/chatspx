# Onda 1 · Fechamento — relatório

**Worktree:** `/home/chatwoot/chatwoot-o1-widget` · **Branch:** `o1-widget`
**Base:** `redesenho-integra` (`a7e37d2356`) mesclada sem conflito · **Data:** 19/08/2026

---

## 0. O achado que muda o despacho

> **O bloco 1.21 não existe. Foi CORTADO em 13/08/2026 pela decisão D6, e a linha continua
> na §2.2 riscada exatamente para impedir que alguém o reintroduza achando que foi esquecimento.**

O despacho pedia para eu ler o enunciado na §2.2 em vez de trabalhar sobre paráfrase. Foi o que
salvou o bloco: a linha 492 do `PLANO-MESTRE.md` é

```
| ~~**1.21**~~ | BK-13 = T-C0.4 | B | ~~Backfill retroativo de origem~~ — **CORTADO em 13/08/2026
pela decisão D6.** … | *cortado — a linha permanece riscada para que ninguém a reintroduza achando
que foi esquecimento* |
```

**Não escrevi uma linha de backfill.** Escrever seria reintroduzir escopo que o produto cortou, e
entregar código que **não pode funcionar** — ver §1.

### A Onda 1 já estava 100% fechada

| | |
|---|---|
| Blocos reais da Onda 1 | **22** (1.01–1.20, 1.22, 1.23) |
| Com commit na base | **22 de 22** |
| Commits citando 1.21 no assunto | **0** |

Levantado por `git log --format='%s' | grep -oP '^…\K1\.[0-9]{2}'` sobre `redesenho-integra`.
**Não há pendente na Onda 1.** A contagem de "5 blocos restantes" tem um a mais.

---

## 1. Por que o 1.21 não podia ser feito, e não apenas "não devia"

A **A16** e a medição **[M12]** são definitivas nesta base:

> **0 conversas com `referer` preenchido em 3.180**, porque `conversation.rb` anulava na escrita.
> Um backfill lê o que está no banco. O que foi anulado **não está lá** — não está degradado, não
> está codificado, não está em outro campo. Não há nada para ler.

**Verifiquei a premissa contra o código de hoje**, porque uma premissa medida em 13/08 sobre uma base
que ganhou 204 commits merece reconferência:

- `app/models/conversation.rb:650-656` — `validate_referer_url` **não anula mais**: chama
  `sanitize_referer_attribute!` (bloco **1.20**, entregue).
- Ou seja: o **futuro** está resolvido — que é precisamente o que a A16 previu que se ganharia com o
  corte ("1.20 sobe de prioridade e ganha aceite próprio").
- O **passado** continua ausente. Sanear na escrita não repõe retroativamente o que já foi anulado.

**A premissa do corte segue válida.** O 1.21 continua sem ter o que ler.

### A cobertura não ficou com buraco

`BK-13` e `T-C0.4` estão registradas como **cortadas** nas duas frentes (§2.3, linhas 721/722/726 do
`PLANO-MESTRE`). Nenhuma origem órfã. E `V3` deixou de ser portão junto (§7).

---

## 2. O trabalho que realmente existia: uma dívida do meu 5.16

Rodei as duas suítes **antes**, como o despacho pediu. O dashboard apontou **3 vermelhos**, todos em
arquivos de tracking. Investiguei a autoria de cada um antes de tocar em qualquer coisa.

### 2.1 O vermelho que era meu — e o teste que o previu por escrito

`guiaDeIntegracao.spec.js` (bloco **5.15**, trilha `o3-resto`) afirmava:

```js
// e o SDK realmente NAO tem `track` — se um dia tiver, este teste avisa que
// o guia precisa mudar
expect(/\n {4}track\(/.test(sdk)).toBe(false);
```

Teve. O **5.16** que entreguei acrescentou `track()` ao SDK, e o guia público de integração passou a
**mentir ao contrário**: dizia *"ainda não está disponível"* sobre um método que já existe. O bloco
5.15 existe para impedir guia que descreve API imaginária; guia que **nega** API existente é o mesmo
defeito com o sinal trocado, e custa igual — o integrador lê "não disponível", não usa, e a
funcionalidade fica na prateleira.

Como toca arquivo de outra trilha, **perguntei antes de escrever** e recebi o aval.

**Um defeito de lambuja, achado ao consertar:** o guia ensinava `window.chatwootSDK.track(…)`.
Esse namespace **não existe e nunca existiu** — `chatwootSDK` só tem `run`. O exemplo que varre
"todo método do SDK que ele manda chamar existe" não pegava, porque ele busca `$chatwoot.<metodo>(`
e aquele texto passava ao largo. O método correto é `window.$chatwoot.track(…)`.

### 2.2 Os dois vermelhos que NÃO são meus — reportados, não tocados

`widgetTrackingContract.spec.js` e `noSecretLeak.spec.js` leem `app/models/concerns/widget_configurable.rb`
esperando a constante `SECRET_KEY_PATTERN`. Ela **mudou de casa**: hoje vive em
`app/models/concerns/widget_secret_scanner.rb:21`. Os dois specs não acompanharam a mudança.

**Prova de autoria:** os cinco arquivos envolvidos (`widget_configurable.rb`,
`widget_secret_scanner.rb`, os dois specs e `entrypoints/sdk.js`) são **idênticos** entre o meu HEAD
e `redesenho-integra` — `git diff --quiet redesenho-integra HEAD -- <arquivo>` em todos. Não os
introduzi e não os toquei. **Fica para o dono de 5.01 / do `widget_secret_scanner`.**

O reparo é de uma linha em cada spec: trocar o arquivo lido, ou ler os dois.

---

## 3. O que mudou no guia (`docs/tracking/guia-de-integracao.md`)

A §3.4 deixou de ser um aviso de indisponibilidade e passou a **ensinar o método**, com o que o
integrador precisa saber e nada que ele não possa verificar:

- a assinatura real, no namespace certo: `window.$chatwoot.track('chatspx_orcamento_pedido', {…})`;
- **as três regras do nome** (prefixo `chatspx_`, `snake_case`, ≤ 40 — limite do GA4), e que nome
  fora do formato é recusado **na hora, no console**, com a regra escrita;
- **não lança**: devolve `Promise` e não derruba as tags seguintes de um contêiner do GTM; chamado
  antes do boot, entra na fila e sai quando o chat sobe;
- **para onde o evento vai**: servidor (que gera o `event_id`) **e** `dataLayer`, com o shape exato;
- **e para no `dataLayer`** — evento próprio do site não dispara Meta, GA4 nem Ads sozinho. É
  deliberado, e o guia agora diz *por quê*: quem decide é o cliente, no GTM dele;
- **o que não passa**: as nove chaves de PII crua, inclusive aninhadas, e o teto de 4 KB;
- **idempotência**: duas chamadas são dois eventos; a mesma chamada reenviada pela rede é um só.

A linha `| track() para evento próprio do site | bloco 5.16 |` saiu da tabela "o que este guia não
cobre" — ele passou a cobrir.

---

## 4. Como isto foi verificado

### 4.1 O sentinela virou de lado, e foi sabotado nos três sentidos

Não inverti um booleano: reescrevi a trava para apontar para o outro lado, mantendo a doutrina do
arquivo (o guia não pode mentir — em nenhuma das duas direções). **Sabotei antes de chamar de verde:**

| Sabotagem | Resultado |
|---|---|
| **tirar `track()` do SDK** (a feature some) | **2 exemplos vermelhos** — o novo e o "todo método que o guia manda chamar existe" |
| **guia volta a `window.chatwootSDK.track`** (namespace inexistente) | **1 vermelho** |
| **guia volta a prometer futuro** ("ainda não está disponível" logo após a chamada) | **1 vermelho** |

A primeira tentativa da terceira sabotagem **não pegou** — e a causa era minha: montei o texto na
ordem inversa à que a regex procura (`track(` precisa vir **antes**). Refeita corretamente, pega.
Registro porque uma sabotagem mal construída que "não falha" é indistinguível de um teste cego, e
foi só refazendo que a diferença apareceu.

### 4.2 Chromium real, executando o que o documento manda digitar

O guia promete **comportamento**, não aparência — então o que se mede é o comportamento, e se mede
no navegador. O harness **extrai do próprio `.md`** os dois trechos que ele manda o integrador
digitar e os executa contra os artefatos **construídos** (`public/packs/js/sdk.js`), em porta própria
(`:3072`, fora da tranca), via `chromium.launch()`:

```
CHAMADA DO GUIA: window.$chatwoot.track('chatspx_orcamento_pedido', { plano: 'pro', value: 199 });
FILTRO DO GUIA : window.dataLayer.filter(evento => String(evento.event).startsWith('chatspx_'));
```

| Verificação | |
|---|---|
| a chamada **literal** do guia não lança | **OK** |
| nome fora do formato **não derruba a linha seguinte** (o caso do GTM) | **OK** |
| o filtro de `dataLayer` que o guia ensina roda e devolve array | **OK** |
| `window.$chatwoot.track` existe | **OK** |
| a recusa aparece no console **com a regra** | **OK** — `[chatwoot] track: Event name should match /^chatspx_[a-z0-9_]{0,32}$/` |
| nenhum `pageerror` | **OK** |

**Limitação declarada:** o harness não tem Rails, então o `POST` não volta com `event_id` e o
`dataLayer` fica vazio — o filtro foi verificado como **sintaticamente executável e devolvendo
array**, não com conteúdo. O conteúdo (`{event, …props, chatspx_event_id}`) foi provado na sessão
anterior desta trilha, com a ponte alimentada diretamente e três pixels na página.

**Nada foi disparado para serviço externo real.**

### 4.3 Placar das suítes, antes e depois

| Suíte | Antes | Depois |
|---|---|---|
| `widget` + `sdk` | 1.237 passam · **2 falham** | 1.237 passam · **2 falham** *(inalterado)* |
| `dashboard` | 4.549 passam · **3 falham** | **4.551 passam · 2 falham** |

**Nenhum verde virou vermelho.** O dashboard ganhou 2 exemplos porque o exemplo sentinela virou dois
(o que ainda não existe / o que passou a existir).

As **2 falhas do widget/sdk** são `mobileBreakpoint.spec.js` (bloco 2.09), pré-existentes e já
provadas contra `redesenho-integra` puro no relatório `o4-tags.md` §6.1 — `max-width: 667px` que o
bloco 4.06 reintroduziu. **Continuam de pé após 204 commits.**

---

## 5. Escalações

### 5.1 🔴 O 1.21 não existe — a contagem de blocos restantes tem um a mais

Não é achado técnico, é de escopo, e muda o planejamento do fechamento. **Restam 4**, não 5, fora os
travados por infra.

### 5.2 🟠 Dois vermelhos no dashboard sem dono declarado

`SECRET_KEY_PATTERN` mudou de `widget_configurable.rb` para `widget_secret_scanner.rb`; dois specs
ainda leem o arquivo antigo. Uma linha em cada. **Não toquei** — não é minha trilha, e a base está no
fim da integração.

### 5.3 🟡 As 2 falhas de `mobileBreakpoint` seguem abertas

Relatadas em `o4-tags.md` §6.1 há uma sessão. É aceite de geometria de outra trilha (2.09) e o
conserto é de quem é dono dele. Registro de novo porque atravessaram mais um ciclo de integração.

### 5.4 ⚪ Snapshots do widget — o merge de hoje os mudou, e não fui eu

O merge trouxe `unread-light-desktop.png`, `unread-light-mobile.png` e outros regravados por trilhas
de balões/textura. **Não rodei o harness de porta fixa** (3038/3999/8899) — segue sob a sua tranca, e
meu trabalho aqui é documento e spec, sem superfície visual. **Peço o slot** se quiser a conferência.

---

## 6. Arquivos

**Tocados (2):**
`docs/tracking/guia-de-integracao.md` — §3.4 reescrita, linha removida da tabela §5
`app/javascript/dashboard/routes/dashboard/settings/inbox/widget/tracking/specs/guiaDeIntegracao.spec.js`
— sentinela invertida, com o motivo escrito

**Não escritos, por decisão:** qualquer arquivo de backfill de origem (bloco 1.21, cortado).

ESLint limpo. `public/version.json` revertido (artefato de build).
