# Reconciliação `homologacao` × `producao` — 02/09/2026

> Levantamento medido no GitHub e **na própria VM da Tozi**, não deduzido.
> Autor: Paulo (via Claude Code). Destinatário: Walisson.

**O ponto de partida:** as duas branches divergiram. Cada uma tem trabalho que a outra não
tem, e **cinco commits são o mesmo trabalho aplicado duas vezes** (cherry-pick), com SHAs
diferentes. Uma promoção `homologacao → producao` feita hoje conflita nos arquivos de busca e
pode desfazer três correções que já estão rodando em produção.

**Estado dos ponteiros:**

| | SHA |
|---|---|
| `origin/homologacao` | `023457252a` |
| `origin/producao` | `b6358606cf` |
| VM Tozi produção (`3.82.215.109`) | `b6358606cf` — **igual ao `origin/producao`** |

---

## 1. 🔴 O que está quebrado em produção agora

**A busca de imóvel da Tozi devolve vazio para tudo.** Não é lentidão nem borda: kitnet,
apartamento e casa retornam *"Nenhum imóvel encontrado com esses critérios"* enquanto o acervo
tem 17, 17 e 31 imóveis respectivamente. Medido contra o Vista real, na VM, em 02/09.

A causa é uma linha. O Vista recusa paginação acima de 50:

```
HTTP 400 — {"status":400,"message":"O limite de resultados por página deve ser 50"}
```

e o fetch volta **vazio, sem erro visível**. O PR #90 fez o `quantidade_para` devolver
`TETO_INSPECAO = 60` em todos os ramos. Medido: quantidade **49 e 50 trazem os 17 kitnets;
51 e 60 trazem zero**.

O conserto existe e está pronto:

- **[PR #93](https://github.com/Dev-Simplex/chatspx/pull/93)** → contra `producao`
- **[PR #94](https://github.com/Dev-Simplex/chatspx/pull/94)** → contra `homologacao`

**São dois porque o commit de conserto ficou órfão:** ele foi feito depois que o #90 já tinha
sido mergeado, então nunca entrou em branch nenhuma. Sem o #94, a `homologacao` segue com 60 e
a próxima promoção desfaz o conserto em produção.

⚠️ **Merge não basta — precisa de deploy na VM.** Enquanto o código não estiver no disco da
`3.82.215.109`, o cliente continua sem busca.

---

## 2. Fila de PRs — 12 abertos

Medido com `git cherry` (comparação por **patch-id**, que enxerga através dos cherry-picks).
Comparar por SHA dá falso-negativo neste repositório hoje.

### Já rodam em produção — falta só a homologação

| PR | O que é | `homologacao` | `producao` |
|---|---|---|---|
| **#91** | `perf(busca)`: registrar o link só do que vai ao cliente | ❌ | ✅ já está |
| **#83** | `fix(eval)`: digest às 7h (gêmeo do #82, que já subiu) | ❌ | ✅ via #82 |

Os dois podem ser mergeados sem risco: o código **já está validado em produção**. Sem eles a
próxima promoção regride — no caso do #83, o digest volta para as 11h no primeiro boot.

### Não estão em lugar nenhum

| PR | O que é | Cliente |
|---|---|---|
| **#81** | `fix(followup)`: separa a cutucada do horário que o cliente pediu | Tozi |
| **#84** | `fix(fotos)`: o freio anti-rajada mede o turno, não o relógio | Tozi |
| **#85** | `fix(conduta)`: o harness de regressão estava morto por um keyword | Tozi |
| **#92** | `feat(eval)`: o juiz passa a ver o estado, não só o texto | Tozi |
| **#89** | `feat(campanhas)`: opt-out que grava + configuração do motor na tela | Tozi |
| **#88** | `feat(unidades)`: parser recusa em vez de errar a data | BigStore |
| **#79** | `feat(unidades)`: a agenda passa a valer na caixa (Nicolas) | BigStore |
| **#71** | `merge(reconciliacao)`: o redesenho do widget da `.232` volta pro git | plataforma |

### Podem ser fechados — já subiram

**#86** (Instagram JSON), **#87** (filtro de suíte) e **#90** (lista total + título do anúncio)
foram mergeados na `homologacao` **e** já estão em produção por cherry-pick. Confirmado por
patch-id: não há nada pendente neles.

---

## 3. Mergeado que nunca subiu para produção

**[PR #80](https://github.com/Dev-Simplex/chatspx/pull/80) — relatórios com recorte por caixa.**
2 commits, 19 arquivos. Está na `homologacao`; a produção não tem.

```
7578bc68e  feat(relatorios): recorte por caixa nas tres telas do "agora"
38ad75a16  chore(task): seed de demonstracao da tela de Bot com duas caixas
```

**São os únicos dois commits da `homologacao` que ainda não existem em produção.** Todo o resto
da diferença entre as branches é duplicata.

---

## 4. ⚠️ Um buraco que não tem PR nenhum

O commit `918d537b1` — **`fix(auth)`: "Invalid token" não dizia que o link era VELHO, e o
convite saía em inglês** — está **em produção e não está na homologação**. 8 arquivos:

```
app/controllers/devise_overrides/passwords_controller.rb
app/javascript/dashboard/i18n/locale/en/setNewPassword.json
app/javascript/dashboard/i18n/locale/pt_BR/setNewPassword.json
app/javascript/v3/views/auth/password/Edit.vue
config/locales/en.yml
config/locales/pt_BR.yml
enterprise/app/views/devise/mailer/confirmation_instructions.html.erb
spec/controllers/devise_overrides/passwords_controller_spec.rb
```

Ninguém abriu PR para levá-lo de volta. **Se a reconciliação for feita por reset da `producao`
sobre a `homologacao`, esse fix morre e o bug volta para todos os clientes.**

---

## 5. Os cinco duplicados e onde vão colidir

Estes já existem **dos dois lados**, com SHAs diferentes:

| Trabalho | na `homologacao` | na `producao` |
|---|---|---|
| `fix(instagram)`: corpo em JSON | `34752e813` | `b6cdd4f90` |
| `feat(busca)`: filtrar por suíte | `3d36c2668` | `a6907a072` |
| `fix(busca)`: lista para de afirmar que é tudo | `0665ee0a6` | `b88270d5a` |
| `style(busca)`: all matcher no spec | `79a2dff0e` | `ff89b5b6b` |
| `feat(busca)`: imóvel pelo título do anúncio | `f39c6fa8c` | `ea4f314d2` |

**Arquivos onde o conflito vai aparecer:**

```
enterprise/lib/captain/tools/buscar_imovel_tool.rb          ← o mais disputado
spec/enterprise/lib/captain/tools/buscar_imovel_tool_spec.rb
app/services/instagram/send_on_instagram_service.rb
app/services/instagram/messenger/send_on_instagram_service.rb
app/services/instagram/base_send_service.rb
spec/services/instagram/send_on_instagram_service_spec.rb
```

**Critério de resolução:** nestes cinco, é o **mesmo trabalho** — ficar com a versão de
produção resolve, porque ela já rodou. A exceção é o `buscar_imovel_tool.rb`, que também
carrega o `TETO_INSPECAO`: **ele tem que terminar em 50**, não em 60, venha de onde vier.

---

## 6. Ordem recomendada

1. **`#93` → merge → deploy na VM da Tozi.** É o único item que o cliente sente agora. Sem
   migration, sem asset de front, sem mudança de dependência — só Ruby.
2. **`#94` e `#83`** na `homologacao`, para ela parar de carregar defeito conhecido.
3. **`#91`** na `homologacao` (código já validado em produção).
4. **Levar o `fix(auth)` para a `homologacao`** — cherry-pick de `918d537b1`, ou PR dedicado.
5. **Só então conciliar as branches**, com os cinco duplicados resolvidos pelo critério acima.
6. Fila restante por impacto: `#84`, `#85`, `#92`, `#81` (Tozi), `#89` (campanhas), `#88`/`#79`
   (BigStore), `#71` (plataforma).
7. Fechar **#86**, **#87**, **#90**.

---

## 7. 🔴 A armadilha: git rodado dentro da VM mente

Auditando a VM da Tozi, o próprio git dela reporta:

```
local:  b6358606cf     origin/producao: 12c6dccd4b
commits SÓ na VM: 18
```

**Os 18 não existem.** Conferido contra o GitHub recém-fetchado, `origin/producao` **é**
`b6358606cf` — o mesmo commit da VM. As refs remotas da box estão paradas porque o deploy busca
por refspec e não atualiza `refs/remotes/origin/*`.

Quem auditar drift por `git log origin/producao..producao` **dentro** da VM conclui que há
trabalho off-git onde não há — e pode "resgatar" commit que já está no GitHub. **Comparar
sempre a partir de uma cópia com fetch recente**, nunca pela ref remota da box.

---

## 8. O que está de fato fora do git

Auditoria completa da VM: **zero código fora do git**. Nenhum arquivo rastreado modificado além
do `public/version.json` (gerado pelo deploy); nada em `app/`, `enterprise/`, `lib/`, `config/`
ou `db/`. Os untracked restantes são 26 assets `.gz` do precompile.

**Duas exceções, as duas relevantes:**

**a) Imagens de campanha que só existem naquele disco**

```
public/urban-ago26.jpg      136 KB   header de 9 campanhas do Urban DeVille
public/urban-henrique.jpg   112 KB   header do convite do Henrique
```

Servem HTTP 200 hoje. Mas a Meta busca a URL **no instante do envio** — imagem que some não dá
erro de deploy, dá disparo quebrado. O precedente está consumado: o `inq-mapa.jpeg`, do mesmo
jeito, hoje é **404**. O `pacaembu-ago26.jpg` foi resgatado para o git em 11/08 por esse motivo;
estas duas ficaram para trás.

As duas já foram baixadas e conferidas byte a byte contra a VM (md5 idêntico). Precisam entrar
**nas duas branches** — senão a próxima promoção descarta de novo.

**b) Um backup de `.env` que o `.gitignore` não cobre**

O `.gitignore` protege `.env.bak` e `.env.bak.*` — com **ponto**. O arquivo que existe na VM é
`.env.bak-spx-20260824-172728`, com **hífen**, e aparece como untracked comum. **Um `git add .`
naquela box commitaria as credenciais de produção.**

Correção: trocar as duas linhas por `.env.bak*`. Verificado que cobre os três formatos
existentes mais variações futuras.

---

## Resumo em uma tela

| | quantidade |
|---|---|
| PRs abertos | **12** |
| — quebrando produção agora | 1 (**#93**) |
| — já em produção, falta a hml | 2 (#91, #83) |
| — em lugar nenhum | 8 |
| — gêmeo do urgente | 1 (#94) |
| Mergeado que não subiu | **1** (#80) |
| Correção em produção sem PR de volta | **1** (`fix(auth)`) |
| PRs que podem ser fechados | 3 (#86, #87, #90) |
| Commits duplicados entre as branches | 5 |
| Arquivos de produto fora do git | 2 imagens |
