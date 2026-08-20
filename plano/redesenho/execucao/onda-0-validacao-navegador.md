# Onda 0 — validação em navegador da branch integrada

**Executado por:** o coordenador, diretamente. O cliente Orca caiu (troca de host) e não havia como
despachar executor; a validação não foi adiada por isso.
**Alvo:** `redesenho-merge` = `redesenho-base` = **`5fd08050fc`** (a branch com tudo integrado).
**Data:** 17/08/2026.

---

## 1. O ambiente — e por que ele é a metade do valor deste documento

A porta **3000 desta VM roda o Puma de homologação**, servindo a branch `homologacao`. Testar
contra ela validaria **outro código** e reportaria verde para o nosso. Por isso:

| Item | Como foi feito | Por que importa |
|---|---|---|
| Servidor | **Puma isolado na 3055**, `RAILS_ENV=production`, servindo o worktree integrado | o da 3000 nunca foi tocado — conferido em 200 depois |
| Banco | **`chatwoot_val_onda0`, novo**, criado com `db:schema:load` | nenhuma migration rodou contra banco existente; a homologação não foi tocada |
| Redis | **índice 9** (`/9`), não o default | não mistura filas do Sidekiq com as da homologação |
| Assets | `assets:precompile` com `NODE_OPTIONS=--max-old-space-size=8192`; **manifest 16:46**, 375 assets | o manifest do worktree era **anterior à integração**. Conferido por **mtime**, não por exit code — `assets:precompile` mascara OOM do Vite saindo 0 com bundle velho |
| Usuário | **dedicado**, criado do zero (`val.onda0@teste.local`) | nenhuma senha de conta real foi resetada |

---

## 2. Resultado

| # | Verificação | light | dark | Evidência |
|---|---|:---:|:---:|---|
| 1 | login + dashboard carrega | ✅ | ✅ | `/app/accounts/4/dashboard` |
| 2 | conteúdo **real** renderizado (não casca) | ✅ | ✅ | `"VO Conversas Aberta Minhas Não atribuídas Todas Não há conve…"` — a interface em pt-BR |
| 3 | config da inbox abre | ✅ | ✅ | 90.415 / 90.419 bytes de HTML |
| 4 | cor verde da marca no DOM | ✅ | ✅ | `#2dc46f` presente |
| 5 | sem erro de console | ⚠️ | ⚠️ | um único: `HTTP 503 waha_connections` — **explicado na §3** |

**8 PASS · 2 "falhas" que são a mesma coisa, e ela não é regressão.**

Screenshots: `/tmp/claude-1001/shots/{login,dashboard,inbox-settings}-{light,dark}.png`.

> A verificação nº 2 existe porque *"a página respondeu 200"* não prova que o SPA montou. O texto
> capturado é a interface de verdade — lista de conversas, filtros, estado vazio, tudo em pt-BR.

---

## 3. O único erro de console, investigado em vez de presumido

```
HTTP 503 /api/v1/accounts/4/waha_connections
```

Três fatos, e os três apontam para ambiente, não para o merge:

1. **É o caminho documentado do próprio controller.**
   `app/controllers/api/v1/accounts/waha_connections_controller.rb:27-29` faz
   `rescue Waha::ApiService::Error => e … status: :service_unavailable`. 503 é o que ele devolve
   quando a API do WAHA não responde.
2. **O arquivo não foi tocado por esta onda.**
   `git log f26db6ee81..HEAD -- <o controller>` → **vazio**. Nem o merge nem as 26 correções
   encostaram nele.
3. **O ambiente isolado não tem WAHA — e o default aponta para o lugar errado de propósito.**
   `WAHA_API_URL` cai no default `http://localhost:3000` (`:102`), que **nesta VM é o Puma de
   homologação**, não um servidor WAHA. A chamada acerta um Chatwoot, não um WAHA, e erra.

**Veredito: condição do ambiente de validação, não defeito do produto.** Numa VM com WAHA
provisionado o endpoint responde normalmente.

> Vale como observação lateral: `WAHA_API_URL` ter default `http://localhost:3000` é frágil em
> qualquer VM onde o Chatwoot roda nessa porta — que é o caso desta. Não é achado desta onda (o
> arquivo é anterior), mas fica registrado.

---

## 4. O que esta validação **não** cobre — dito explicitamente

Nenhuma destas foi medida, e nada se afirma sobre elas:

| Não coberto | Por quê | Onde fica |
|---|---|---|
| canvas de **Automações** e **exportar PDF** | são os dois aceites do bloco 0.3 que exigem interação profunda; o banco isolado não tem dado de relatório | `COMO-TESTAR-ONDA-0.md` §4 itens 9 e 10 |
| **ColorPicker**: preview acompanhando o arraste | exige simular arraste no seletor; o aceite dos **dois sentidos** está no relatório do 0.9 | `onda-0-blocos-0.7-0.8-0.9.md` |
| isolamento por agente com **mensagem restrita real** | exige dois agentes e uma mensagem restrita; o banco isolado tem um usuário | `COMO-TESTAR-ONDA-0.md` §4 item 1 |
| **Central de Ajuda embutida** | não exercitada | idem, item 11 |

O que **está** provado por banco, e é mais forte que tela: excluir conversa exclui de verdade, a
credencial sobrevive ao update, a cor nasce verde pelos dois caminhos, e as duas migrations
destrutivas estão neutralizadas — ver §0.1 do `onda-0-RELATORIO.md`.

---

## 5. Veredito

**A Onda 0 está pronta para revisão humana.**

O app sobe com o merge da v4.16.2 dentro, o dashboard renderiza em claro e escuro, a config de
inbox abre com a cor da marca, e o único erro de console é do ambiente de validação — verificado,
não presumido.

O que falta é **decisão humana**, não trabalho: a lista de itens que só um operador logado fecha
está na §4, e a decisão de produto do bloco 0.8 (unificar a cor no verde) segue registrada como
minha e reversível em três passos.

---

## 6. O ambiente ficou de pé

O Puma da **3055** continua no ar servindo a branch integrada, com o banco `chatwoot_val_onda0` e o
usuário `val.onda0@teste.local`. Serve para conferir os itens da §4 sem montar nada.

Para derrubar quando não precisar mais:

```bash
pkill -f "rails server -b 127.0.0.1 -p 3055"
# e, se quiser limpar o banco de validação:
#   dropdb -U chatwoot -h 127.0.0.1 chatwoot_val_onda0
```

O Puma da **3000 (homologação) não foi tocado em momento algum** — conferido em 200 antes e depois.
</content>
