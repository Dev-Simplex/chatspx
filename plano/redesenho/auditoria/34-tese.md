# TASK 34 — Auditoria adversarial: a tese sobrevive?

> **O que é este documento.** Uma auditoria de **estratégia**, não de execução. As outras auditorias
> perguntam "isto está bem feito?". Esta pergunta: **estamos construindo a coisa certa, ou é uma boa
> execução da coisa errada?**
>
> **Postura.** Parti da hipótese de que há problemas sérios e fui procurá-los. Onde não encontrei,
> digo em uma linha e sigo. Nenhuma afirmação marcada `[MEDIDO]` nos artefatos auditados foi aceita
> por estar marcada: refiz por amostragem, com os comandos reproduzidos na §0.3.
>
> **Regra dura cumprida.** Nenhum arquivo do repositório foi alterado. Nenhum artefato auditado foi
> tocado. O único arquivo escrito por esta task é este.
>
> **Data:** 12/08/2026 · **Branch:** `homologacao`, HEAD `ee87f5e799` · **Esforço** sempre em P/M/G,
> nunca em horas.

---

## 0. Como ler

### 0.1 Classificação dos achados

| Classe | Significa |
|---|---|
| **BLOQUEADOR** | Se ficar assim, uma premissa do plano cai e trabalho já orçado vira retrabalho. Decidir antes de começar |
| **GRAVE** | Custa dinheiro, credibilidade ou prazo de forma previsível. Corrigir dentro da onda em que aparece |
| **MÉDIO** | Erra o alvo ou perde valor, mas não derruba o plano |
| **MENOR** | Vale corrigir quando o arquivo estiver aberto |
| **COSMÉTICO** | Registro, não pedido |

Toda crítica tem **evidência** (arquivo:linha, comando ou medição) e **consequência** ("se ficar
assim, acontece Y"). Onde eu não achei problema, está escrito que não achei.

### 0.2 O que eu li

Os 5 documentos de planejamento (8.210 linhas: `PLANO-MESTRE.md` 1.005 · `22` 1.803 · `23` 1.616 ·
`24` 1.928 · `25` 1.858), o `DECISOES.md`, o `10-gap-analysis.md` integralmente, e as seções citadas
pelas hipóteses nos relatórios `01`, `02`, `05`, `06`, `07` e `08`. Os 8 mockups foram lidos como
artefato (diff estrutural), não como design — isso é de outra auditoria.

### 0.3 Medições que refiz nesta task

Não confiei nas medições dos planos. Refiz nove por amostragem. **Oito bateram exatamente.**

| # | Afirmação auditada | Comando | Resultado |
|---|---|---|---|
| V-1 | `show.html.erb` usa `@web_widget.inbox` em **11** chaves (M5, base da arbitragem A1) | `sed -n '7,32p' app/views/widgets/show.html.erb \| grep -c "@web_widget.inbox"` | ✅ **12 ocorrências / 11 atributos distintos** (`timezone` aparece duas vezes, em `utcOffset` e em `timezone`) — confere |
| V-2 | `--widget-color` é escrita e **não tem um único consumidor** (defeito B1) | `grep -rn -- "--widget-color" app/javascript/` | ✅ **1 ocorrência**, `widget/App.vue:121`, escrita |
| V-3 | **Zero** `fbq`/`gtag`/`dataLayer` em `app/` | `grep -rn "fbq\|gtag\|dataLayer" app/ \| wc -l` | ✅ **0** |
| V-4 | `WidgetBuilder.vue` órfão, 13.198 bytes (M11) | `ls -la` + `grep -rn WidgetBuilder app/javascript` | ✅ **13.198 B**, zero referências |
| V-5 | CSS do widget = **1.103.132 B**, dos quais **63,5%** são regras de ícone | medição sobre `public/vite/assets/widget-EcEcykJV.css` | ✅ **1.103.118 B**, regras `.i-*` = **700.724 B = 63,5%** |
| V-6 | `sdk.js` = **28,8 KB** | `curl -skI https://hmlchat.simplexsolucoes.com.br/packs/js/sdk.js` | ✅ **28.834 B** |
| V-7 | Migrations sem colisão (M9) | `ls db/migrate \| cut -d_ -f1 \| sort \| uniq -d` | ✅ vazio |
| V-8 | Strong params de inbox é lista fechada e o merge é raso | `inboxes_controller.rb:217` e `:52-56` | ✅ lista fechada; `merge` de 1º nível |
| V-9 | **Varredura de campo do 06 §13.2** (base da hipótese H1) | Playwright/Chromium 145, 8 sites, 17 s por site com scroll, 12/08/2026 | ✅ **conclusão sobrevive**, com ressalva de universo — §2.2 |

E duas medições **novas**, que os planos não fizeram e que mudam prioridade (§6 e §7):

| # | Medição nova | Comando | Resultado |
|---|---|---|---|
| N-1 | Compressão e cache do SDK no HTTPS público | `curl -skI -H "Accept-Encoding: gzip, br" …/packs/js/sdk.js` | **sem `content-encoding`**; `cache-control: public, max-age=31556952` (1 ano); **sem `ETag`**, sem `Last-Modified` |
| N-2 | Volume real do canal Website e do `referer` na única base acessível | `psql` em `chatwoot_production` (homologação) | **4** conversas de widget em **3.179** (0,13%); **`referer` = `null` nas 4**; **0** conversas com `utm_`/`gclid`/`fbclid` |

**Ressalva honesta sobre N-2:** homologação **não é a frota**. É a única base que eu podia consultar
sem tocar produção (e não toquei). O número não prova nada sobre clientes reais — mas é o **único
dado que existe hoje**, e ele aponta contra a premissa. É exatamente por isso que ele vira o achado
BLOQUEADOR da §3.

---

## 1. Veredito em uma tela

### 1.1 As quatro hipóteses

| # | Hipótese do coordenador | Veredito | Em uma frase |
|---|---|---|---|
| **H1** | "Estamos polindo a rampa, não o destino" | **PARCIAL** | O fato é real, a conclusão é invertida: o dado do WhatsApp foi medido **em sites que têm widget**, e diz que widget **+** WhatsApp converte mais que widget sozinho — não que o widget seja dispensável. Mas a rampa está mal servida no plano: a saída para WhatsApp é **um bloco M na Onda 4** |
| **H2** | "Dois perfis num produto só é aposta hedged (cara)" | **NÃO SE SUSTENTA** como custo — **SUSTENTA** como promessa | O hedge custa **~3% do esforço** (3 blocos, ~8 de 323 pontos) porque o plano escolheu flags planas. O problema não é preço: é que os dois mockups são **99,0% idênticos** — vendemos "dois produtos" e entregamos um com interruptor |
| **H3** | "O iframe é seguro e limita o teto" | **PARCIAL — o culpado é outro** | O teto não é o iframe: é (a) a recusa do **híbrido com Shadow DOM** que o próprio estudo recomendou (05 §15.3) e (b) o **facade sumiu do plano** sem entrar em "não faremos". O plano coloca o teaser fora do iframe **sem** o mecanismo de isolamento, e paga com o risco R13 |
| **H4** | "Chat de 2023 bem encanado para 2026" | **SUSTENTA (com um número corrigido)** | Em 8.210 linhas de plano: **0** ocorrências de "IA generativa", "ChatGPT", "guardrail", "citação de fonte". Mas o argumento do coordenador usa o número errado: IA generativa converte 7,80% sobre **0,10% do tráfego** — o Google Ads gera ~100× mais leads. A tese de H4 é verdadeira; a evidência que a sustenta é outra |

### 1.2 Os achados que mudam decisão

| Id | Classe | Achado | §|
|---|---|---|---|
| **T34-01** | **BLOQUEADOR** | "A origem já está no banco" nunca foi verificada, e a única amostra existente a contradiz (0 conversas com `referer`). A pergunta que testa isso (V3) está classificada como "só dimensiona o backfill" | §3.1 |
| **T34-02** | **BLOQUEADOR** | Não existe lar declarado para a configuração de **aparência** (posição, offsets, tema, texto do lançador). A arbitragem A1 declara três chaves e nenhuma é aparência — mas o aceite da Onda 3 exige persistir "posição" | §8.1 |
| **T34-03** | **GRAVE** | `5.07` (propagação do SDK) está na **última** onda, mas é pré-requisito de tudo que muda o SDK nas Ondas 1, 2 e 4. Medido: cache de **1 ano sem `ETag`** | §8.2 |
| **T34-04** | **GRAVE** | A primeira onda que **muda a conversa comercial** é a 4, depois de **56,0%** do esforço. O tracking — que o estudo chamou de "alavanca de maior valor por esforço" — está a **76,8%** | §6 |
| **T34-05** | **GRAVE** | Seis itens do estudo evaporaram entre `10-gap-analysis` e o plano **sem entrar na lista "o que NÃO vamos fazer"**: facade, teste A/B, lead incompleto, analytics do widget, instalação WordPress/Wix/GTM, cookie `secure` | §9 |
| **T34-06** | **GRAVE** | O aceite "painel funciona em **200% de zoom**" (Onda 2, item 7) é inatingível: `show.html.erb:6` traz `maximum-scale=1, user-scalable=0` e **nenhum bloco toca essa linha** | §8.3 |
| **T34-07** | **GRAVE** | `allowed_domains` vazio (o default) **remove o `X-Frame-Options`** — qualquer site do mundo embute o widget de qualquer conta. O estudo pedia correção (P0); o plano entrega **um aviso na tela**, e não declara a troca | §8.4 |
| **T34-08** | **MÉDIO** | Cinco riscos declarados pelo estudo não foram carregados para o plano (`MutationObserver` na página do cliente, `user-scalable`, cookie sem `Partitioned`, contato criado no page-load, decisão automatizada — art. 20 LGPD) | §9.2 |
| **T34-09** | **MÉDIO** | O `DECISOES.md` N2 registra "manter iframe — conclusão convergente de 3 relatórios". O 05 §15.3 recomendou **híbrido**, não iframe puro. A convergência é construída | §4 |
| **T34-10** | **MÉDIO** | Degradação na cadeia de citação: 01 §2.2 diz "**usam** WhatsApp"; 00-INDICE, 10-gap e 22 §B.4 dizem "**redirecionam para** o WhatsApp" — coisas diferentes, com consequências diferentes | §2.3 |
| **T34-11** | **MENOR** | `widget_triggers` é hash aberto no strong params, sem teto de tamanho declarado (o teto de 1.14 cobre só o contato). O jsonb é servido no ERB de toda página do cliente | §8.5 |

### 1.3 Recomendação final, em uma linha

**Reordenar** — não manter como está, não repensar. O plano é bom engenharia e a tese central
sobrevive; o que está errado é a **ordem em que o valor chega** e **duas premissas não medidas** que
sustentam a primeira onda. Os três movimentos concretos estão na §11.

---

## 2. H1 — "Estamos polindo a rampa, não o destino"

### 2.1 A evidência a favor

Ela é forte e está bem levantada:

1. **[FATO, 01 §3.10]** Panorama 2026: empresas com WhatsApp convertem **3,20%**; sem WhatsApp,
   **2,66%**. Delta **+0,54 p.p. (+20,3% relativo)**. Adoção **75,96%**.
2. **[FATO, 06 §13.2]** Varredura de campo em 18 sites BR: Magalu, Americanas, Nubank, Contaazul e
   Sympla não expõem widget no HTML inicial; Locaweb expõe **link de WhatsApp**.
3. **[INFERÊNCIA, 10-gap §1.3]** "No Brasil, o concorrente do nosso widget é o botão de WhatsApp,
   não o Intercom."

**Refiz a medição 2 em navegador real** (Chromium 145, viewport 1366×900, UA de Chrome desktop,
12 s de espera + scroll + 5 s, `pt-BR`), porque `curl` não vê SPA nem GTM — e o próprio 06 §13.1
avisa que "**ausência aqui não é prova de ausência**":

| Site | Widget de chat detectado (rede + DOM + elemento fixo) | Links WhatsApp na home |
|---|---|---|
| magazineluiza.com.br | **nenhum** (0 iframes, 0 elementos fixos) | 0 |
| americanas.com.br | **nenhum** (o único fixo é o menu de acessibilidade) | 0 |
| nubank.com.br | **nenhum** | 0 |
| locaweb.com.br | **nenhum** (o único fixo é o VLibras) | **2** |
| contaazul.com | **nenhum** (fixos: banner de cookies) | **5** |
| sympla.com.br | HubSpot no DOM; nenhum widget de chat visível | 0 |
| zenvia.com | **Zenvia** (o próprio produto) | **9** |
| **leadster.com.br** *(controle positivo)* | **Leadster** — elemento fixo `nld-shown-slide nld-avatar` (o teaser deles **apareceu**) | 3 |

**Veredito da medição:** a conclusão do 06 §13.2 **sobrevive a um método melhor**. O controle
positivo prova que meu detector funciona (achou o teaser da Leadster e o widget da Zenvia). Isso é
justo dizer e eu digo: a varredura estava certa, apesar do método fraco.

### 2.2 A evidência contra — e ela é decisiva

**(a) O dado do WhatsApp foi medido dentro de sites que têm widget.** O Panorama é produzido pela
Leadster sobre **2.425 sites** [FATO, 08 §5.3] — sites que rodam o widget da Leadster. Portanto
"conversão com WhatsApp 3,20% × sem WhatsApp 2,66%" compara **widget+WhatsApp** contra
**widget sozinho**. Não existe no corpus a coluna "sem widget nenhum".

**Consequência:** o número **não** autoriza a leitura "o widget é corredor de passagem, invista no
destino". Ele autoriza exatamente a leitura oposta — *o widget é o que qualifica antes de entregar
ao WhatsApp, e quem faz as duas coisas converte 20% mais*. Usar esse número para desinvestir do
widget é lê-lo ao contrário.

**(b) O universo da varredura é o errado.** Magalu, Americanas e Nubank não são — e nunca serão —
ICP do ChatSPX. São empresas com central de atendimento própria e app. A conclusão correta da minha
medição é mais estreita do que a que o gap analysis tirou: *o grande varejo brasileiro não usa
widget de chat*. Isso não diz nada sobre a PME de energia solar, imobiliária ou clínica — que é
quem compra.

**A lacuna que ninguém fechou:** o estudo mediu 18 grandes marcas e **zero** empresas do porte do
ICP. A medição barata que responderia isso está no próprio plano (**V6**: "quantas inboxes Website
existem na frota e quantas já têm campanha de chat ativa") e está classificada como
**"Bloqueia: Nada; refina 3.03"**. Ver §3.2.

**(c) O plano trata a rampa como acessório.** Se a tese é "o widget é a antessala do WhatsApp",
então a saída para WhatsApp deveria ser peça central. No plano ela é:

| Bloco | O que é | Onda | Esforço |
|---|---|---|---|
| **4.08** | Saída para WhatsApp no perfil marketing, carregando o contexto | 4 | **M** |

Um bloco M, na quinta onda, dependente de `4.03` (que é **G**). E o item que o `10-gap-analysis §3.2`
classifica como **D5 — "ninguém documenta ter feito"**, o handoff que costura **identidade,
transcript e origem** com código opaco no `?text=` (05 §9.7), **não aparece com esse escopo em lugar
nenhum do plano**: `grep -rn "transcript" plano/redesenho/*.md` não retorna o mecanismo. O plano diz
"o link leva o contexto" e não especifica o quê.

### 2.3 Um defeito de cadeia de citação (T34-10, MÉDIO)

O mesmo número aparece com dois significados:

| Onde | Texto |
|---|---|
| `01-leadster-produto.md:230` | "75,96% das empresas analisadas **usam WhatsApp**" |
| `01-leadster-produto.md:486` | tabela: "Empresas que **usam** WhatsApp — 75,96%" |
| `00-INDICE.md:74` | "75,96% das empresas **redirecionam para** o WhatsApp" |
| `10-gap-analysis.md:82` | "75,96% das empresas **redirecionam para** o WhatsApp" |
| `22-plano-widget.md` §B.4 | "75,96% das empresas brasileiras **redirecionam para** o WhatsApp" |

"Usar WhatsApp como canal" e "redirecionar o visitante do site para o WhatsApp" são fatos
diferentes. O primeiro é quase trivial no Brasil; o segundo é a tese do produto.

**Consequência:** o número entrou no **plano de execução** (22 §B.4) já com o significado forte,
justificando o CTA de saída. Se um cliente ou um investidor conferir a fonte, encontra a formulação
fraca. É o tipo de erro que custa credibilidade uma vez só, e caro.

### 2.4 Veredito de H1

**PARCIAL.** O fato ("no Brasil o WhatsApp é o destino") é real e está bem medido. A conclusão
("então o investimento no widget está no lugar errado") **não se sustenta na evidência do próprio
estudo** — o dado mede sites que têm widget. O que **se sustenta** é uma crítica de ênfase: se a
rampa é a tese, ela merece mais que um bloco M na quarta onda, e o mecanismo que ninguém tem (D5)
precisa estar escrito.

---

## 3. O achado que ataca a premissa da Onda 1

### 3.1 T34-01 — "a origem já está no banco" (BLOQUEADOR)

O plano mestre abre o resumo executivo com cinco números medidos. O quarto é:

> "**Zero** ocorrências de `fbq`, `gtag` ou `dataLayer` em `app/`. A origem do lead **já está no
> banco**, crua, em `conversations.additional_attributes.referer`, e **ninguém parseia**."
> — `PLANO-MESTRE.md:179-180`

E a §3 item 4 declara o que se compra com isso:

> "É a **única entrega deste plano que responde 'de onde veio esse lead' para conversas que já
> aconteceram**, e é o argumento que **compra orçamento** para as ondas seguintes."

Sobre essa premissa estão pendurados **cinco blocos** da Onda 1 — `1.18` (seed), `1.19` (parser),
`1.20` (sanear `referer`), `1.21` (backfill), `1.22` (relatório) — **11 pontos de esforço**.

**Medi na única base a que tenho acesso** (homologação, `chatwoot_production`, 12/08/2026):

```sql
select i.channel_type, count(c.id) from conversations c
  join inboxes i on i.id=c.inbox_id group by 1 order by 2 desc;
--  Channel::Api        | 2504
--  Channel::Instagram  |  658
--  Channel::Whatsapp   |   13
--  Channel::WebWidget  |    4

select count(*) filter (where additional_attributes->>'referer' is not null) as com_referer,
       count(*) filter (where additional_attributes->>'referer' ~ 'utm_|gclid|fbclid') as com_campanha,
       count(*) as total from conversations;
--  com_referer | com_campanha | total
--            0 |            0 |  3179
```

E as quatro conversas de widget que existem trazem, literalmente, `"referer": null`.

**Três leituras, em ordem de importância:**

1. **A chave `referer` só existe em conversas do canal Website** — é gravada em
   `app/controllers/api/v1/widget/base_controller.rb:42`, a partir de `message[referer_url]` que só o
   SDK do widget envia. Portanto o parser retroativo (C0) **não alcança** conversas de API, WhatsApp
   ou Instagram, que aqui são **99,87%** do volume. A frase "responde de onde veio esse lead para a
   base inteira" (§3 item 4 e §1 item 4) é, no melhor caso, "para a fatia de widget da base".
2. **Nas conversas de widget que existem, o valor é `null`.** Pode ser efeito de
   `validate_referer_url` (que o bloco `1.20` corrige) ou de tráfego sintético. Não sei — e **o plano
   também não**.
3. **A pergunta que testaria isso existe e está subclassificada.** `PLANO-MESTRE.md §7, V3`:
   *"Quantas conversas da frota têm `utm_`/`gclid`/`fbclid` no `referer`? — **Bloqueia: só dimensiona
   1.21 (backfill)**"*. Não é verdade: ela dimensiona **1.18, 1.19, 1.21 e 1.22**, e testa a premissa
   que sustenta o argumento de orçamento do plano inteiro.

**Consequência se ficar assim:** a equipe executa a Onda 1 inteira, chega ao cliente com "agora você
sabe de onde veio cada lead", roda o backfill — e o relatório vem vazio, porque o `referer` das
conversas antigas é `null` ou o canal não é o widget. O plano perde exatamente a entrega que ele
elegeu como "o argumento que compra orçamento para as ondas seguintes", **depois** de ter gasto os 11
pontos.

**Correção (esforço P, uma tarde):** promover V3 de "verificação pendente" a **portão de decisão**,
com a consulta já escrita acima rodada **por VM, por conta e por mês**, antes de qualquer linha de
1.18–1.22. Se o volume for alto, o plano continua como está e ganha um argumento de venda. Se for
baixo, **isso não é fracasso** — o próprio plano já diz o que fazer (V3: "reforça 5.08, o coletor"),
e a consequência correta é **antecipar 5.08 e cancelar 1.21**, não descobrir isso depois.

### 3.2 O primo dessa pergunta: V6 (GRAVE, dentro de T34-01)

`PLANO-MESTRE.md §7, V6`: *"Quantas inboxes Website existem na frota, e quantas já têm campanha de
chat ativa? — **Bloqueia: Nada; refina 3.03**"*.

Em homologação: **1 inbox** WebWidget contra 13 de API e 1 de WhatsApp; **4 conversas** de widget em
3.179. De novo: homologação não é a frota. Mas V6 não é um refinamento do texto de um diálogo — é a
pergunta **"este plano de 106 blocos tem cliente?"**. Se a frota tiver 3 inboxes Website ativas, a
resposta muda a ordem de tudo (e talvez a decisão de fazer).

**Consequência:** a mesma. Uma consulta de 10 minutos decide entre executar como está e reordenar.
Nenhuma das duas verificações bloqueia a Onda 0, que pode começar hoje.

---

## 4. H3 — "O iframe é seguro e limita o teto"

### 4.1 O que a hipótese acerta

O ganho é real e eu confirmei o número: `sdk.js` = **28.834 B** contra os 456,1 KB do
`neurolead.min.js` (02 §8.1) — **15,9×**. E o custo do caminho contrário está medido: **239
`!important`** no bundle da Leadster (02 §5.1). Nesse ponto não tenho crítica: manter o **painel** em
iframe é a decisão certa e está bem fundamentada.

### 4.2 O que a hipótese erra — o teto é outro (T34-09, MÉDIO)

**(a) A "convergência de 3 relatórios" é construída.** `DECISOES.md` N2 diz:

> "**Manter iframe.** Conclusão convergente de 3 relatórios."

O relatório 05 §15.3, que é o que estudou a questão, **não** conclui isso. Conclui:

> "**Manter o iframe para o painel de conversa. Mover o chrome (bolha, badge, convite proativo,
> anúncio de acessibilidade) para Shadow DOM no host.**"

E explica por quê: *"o chrome no host resolve **de graça** três P0/P1 de uma vez: `aria-live` no
documento do cliente, badge instantâneo sem carregar o app, e o facade que corta 570 KB"*.

O plano mestre transforma isso no item 1 da lista "o que NÃO vamos fazer" (`§8`): *"Migrar para
Shadow DOM ou DOM direto"* — e adia o híbrido ("decisão posterior"). Ninguém propôs migrar; o que foi
proposto é usar Shadow DOM **para o chrome**, que é meia dúzia de elementos.

**(b) E o plano faz a parte difícil do híbrido sem o mecanismo dele.** O bloco `4.06` (**G**) coloca
o **teaser no host**, fora do iframe — exatamente a peça que o 05 recomendou pôr em Shadow DOM. A
mitigação escolhida (`22-plano-widget.md` §C.2) é:

> "prefixo `woot-`, todas as propriedades declaradas explicitamente (nada herdado), e `all: revert` no
> contêiner"

Isto é, **a mesma técnica da Leadster** que o estudo usa como prova de que a abordagem é ruim, só que
com `all: revert` em vez de `!important`. E o plano registra o preço no próprio risco **R13**: *"o
teaser fora do iframe quebra em site com CSS agressivo… testar em 3 sites de clientes antes da
frota"*.

**Consequência:** pagamos o custo do DOM compartilhado (R13, teste manual em sites de terceiros,
classe inteira de bug intermitente que só aparece no site de um cliente) **sem** o benefício do
isolamento que estava disponível por poucas linhas. Se um cliente tiver um `* { box-sizing }`
agressivo ou um `z-index` de banner acima do nosso, o teaser — que é a peça de conversão da Onda 4 —
quebra em produção e não quebra em teste.

**(c) O que de fato limita o teto sumiu do plano.** O gap analysis classifica **M6 — "Peso: app
carregado sob demanda"** como gap de **MESA** (🔴 "todo mundo tem, nós não temos, constrange na
venda"), com Intercom, Zendesk, Crisp e Chaport tendo loader < 5 KB contra os nossos **587 KB gzip
para 100% dos visitantes**.

```
$ grep -ril "facade" plano/redesenho/*.md
(vazio)
```

**Zero ocorrências** em 8.210 linhas. O facade não foi feito, não foi adiado com justificativa, e
não entrou na lista de 25 itens "o que NÃO vamos fazer". O plano ataca o peso por **emagrecimento**
(`1.08`: CSS ≤ 80 KB; `2.18`: JS eager ≤ 150 KB gzip) — que é a ordem certa, o próprio gap dizia
"resolver o CSS antes do facade" — mas **para antes do último passo**, e sem dizer que parou.

### 4.3 Veredito de H3

**PARCIAL, com o alvo trocado.** O iframe não limita o teto — protege, e o número prova. O que limita
é: (a) a decisão de não usar Shadow DOM para o chrome, tomada com base numa "convergência" que não
existe nos relatórios; (b) o desaparecimento silencioso do facade, que é gap de mesa. Nenhum dos dois
exige repensar o plano: exige **uma linha na lista de decisões** e um bloco a mais.

---

## 5. H4 — "Um chat de 2023 bem encanado para 2026"

### 5.1 Primeiro, corrigir o número da hipótese

O coordenador escreve: *"tráfego de IA generativa converte a 7,80%, mais que o dobro do Google Ads"*.
Está certo, e o próprio estudo dá o denominador que falta — na mesma tabela:

| Canal | Conversão | % do tráfego | Leads por 100 acessos |
|---|---:|---:|---:|
| **IA Generativa** | **7,80%** | **0,10%** | **0,0078** |
| Google Ads | 3,41% | 23,40% | **0,798** |
| Busca Orgânica | 2,39% | 27,91% | 0,667 |
| Meta Ads | 3,91% | 9,48% | 0,371 |

[FATO — `01 §3.7` e `08 §5.3`: "Tráfego vindo de assistentes de IA: 170,5 mil acessos (**0,10%** do
total)"]

**O Google Ads gera hoje ~102× mais leads que a IA generativa.** Priorizar o roadmap por "converte
2,3× mais" e ignorar "0,10% do tráfego" é o erro clássico de ler taxa sem base. O item **D14**
(detectar referrer de IA e marcar a conversa) continua valendo — é **P**, custa quase nada e o
crescimento é a aposta — mas não é manchete de roadmap, e o estudo nunca disse que era.

### 5.2 Agora, o que sustenta H4 de verdade

**(a) O plano não tem IA.** Busca literal nos 5 documentos:

| Termo | Ocorrências em `plano/redesenho/*.md` |
|---|---:|
| `IA generativa` | **0** |
| `ChatGPT` / `Perplexity` / `GPTBot` / `llms.txt` | **0** |
| `citação de fonte` | **0** |
| `guardrail` | **0** |
| `Captain` | 2 (incidentais) |

O único bloco de IA é `4.09` — **rótulo** de identidade de IA no header e na bolha, `aria-busy` no
streaming. É conformidade (EU AI Act art. 50), não produto.

**(b) E o estudo diz, com todas as letras, que o que o plano constrói é a categoria em declínio.**
`08-ia-em-chats.md:86`:

> "**O 'chatbot de fluxo' morreu comercialmente.** O Drift — que *inventou* a categoria
> 'conversational marketing' — está em sunset. […] árvore de decisão sem LLM virou commodity de baixo
> valor: **quem só tem fluxo não sustenta preço**."

Os blocos `4.02` (**G**) e `4.03` (**G**) constroem exatamente isso: fluxo de captura conversacional
com Flows como fonte de verdade — campos que chegam como mensagens, teto de 8, máscaras BR. É bom
produto, é o que a Leadster vende, e é o que o estudo classifica como commodity.

**(c) Enquanto o que o estudo elege como o item de maior valor por esforço do inventário inteiro fica
de fora.** `10-gap-analysis §3.2`:

| Id | Diferencial | O que o estudo diz | No plano? |
|---|---|---|---|
| **D8** | QA/eval de IA exposto como produto de gestão | "**O motor já existe** — episódios, LLM-as-judge com 16 categorias de falha, gates determinísticos no padrão τ-bench. É **a coisa de maior valor/esforço do inventário inteiro**" — **M** | **não** |
| **D9** | Guardrail executável (gates movidos do eval para o pré-envio) | "Fecha o **gap nº 1** da nossa IA reusando código já testado" — **M** | **não** |
| **D10** | Citação de fonte por padrão no canal web + "sou uma IA" no 1º turno | "A flag `feature_citation` **já existe**; é decisão de default por canal" — **P** | parcial (`4.09` faz o rótulo, não a citação) |
| **D14** | Detectar referrer de IA generativa | **P** | **não** |

**(d) E o risco correspondente também sumiu.** `10-gap §6.5`: *"widget web é o canal mais exposto a
prompt injection: anônimo, sem custo de criar conta, atacante itera centenas de vezes"*. O plano
cobre uma fatia (`4.17` — delimitar atributos do site no prompt) e não cobre o resto: rate limit por
sessão de widget, validação de ação sensível em código.

### 5.3 Veredito de H4

**SUSTENTA.** Não pelo motivo que o coordenador deu (o número da IA generativa está inflado pela
ausência do denominador), mas por um motivo mais forte: **o plano investe dois blocos G na categoria
que o próprio estudo declara commodity de baixo valor, e zero no que o estudo elege como o maior
valor por esforço da casa.** Três dos quatro itens (D9, D10, D14) são **P ou M** e usam código que já
existe.

Ressalva de justiça: isso é uma **escolha de escopo defensável** — o plano é de *chat de site*, não
de IA, e escopo aberto mata projeto. O problema não é a escolha; é ela não estar **declarada**. A
lista "o que NÃO vamos fazer" tem 25 linhas e nenhuma delas diz "IA fica fora deste plano".

---

## 6. O custo do perfil duplo (H2), medido

### 6.1 Método

Contei o que **desapareceria** se o produto escolhesse **um** perfil. Não conta como custo do hedge
aquilo que existiria de qualquer forma num produto só-marketing (teaser, fluxo de captura, gatilhos,
saída para WhatsApp) — isso é o custo de **ter captura**, não de **ter dois perfis**.

Conversão de esforço declarada (hipótese minha, para tornar comparável): **P = 1, M = 3, G = 8**.
Total do plano: **323 pontos** em 106 blocos.

### 6.2 O que existe só por causa do perfil duplo

| Bloco | Título | Esf. | Fração atribuível | Pontos |
|---|---|:---:|---:|---:|
| **3.03** | `WidgetProfile.resolve` → flags planas; seed na criação; troca que **propõe** | M | 100% | 3,0 |
| **3.07** | Seletor de perfil (2 `RadioCard`) + `useProfileVisibility` + pergunta no wizard | M | 100% | 3,0 |
| **3.17** | Tela inicial **por perfil** + base de conhecimento por flag | M | ~70% (o fix do `ArticleViewer` fica) | 2,1 |
| — | Gates de visibilidade espalhados por `3.05`, `3.09`, `3.14`, `4.04`, `4.06`, `4.08` | — | estimado | ~2,0 |
| **Total** | | | | **≈ 10,1 de 323 = 3,1%** |

Conferência por outro caminho — **tarefas nomeadas nas frentes**: das **277**, sete citam perfil e
sobrevivem (`W3.2`, `W3.3`, `W3.4`, `W3.7`, `T1.3`, `T1.5`, `BK-08` em parte); duas foram
**eliminadas** por arbitragem (`W3.1`, migration; `T1.4`/`BE-3`, backfill). **7 de 277 = 2,5%.** Os
dois métodos batem.

**Custo de governança** (não é esforço, mas é atrito): **3 das 12 arbitragens** do plano mestre
existem só por causa do perfil (**A2** idioma do valor, **A3** o que a troca faz, **A4** backfill), e
uma quarta o inclui (**A1**). Mais 1 dos 25 riscos (**R3**) e 1 dos 25 "não faremos" (#19).

### 6.3 Por que é tão barato — e o que isso revela

Porque o plano tomou **a decisão arquitetural certa** e a repetiu em quatro lugares: *o widget lê
flags planas, nunca o nome do perfil* (22 §B.1, A3, R3, `3.05`). Isso evita o `if` espalhado, mantém
a matriz de teste em 16 snapshots em vez de 32 e torna o híbrido possível. **Aqui o plano está certo
e não tenho crítica.**

Mas o mesmo dado tem uma segunda leitura, que é desconfortável. Medi o diff estrutural dos dois
mockups de widget:

```
marketing: 276.422 B · suporte: 276.516 B
similaridade estrutural: 0,990   (157 linhas de diff em 5.846)
```

E as 157 linhas de diferença são **o cenário**, não o produto: o site host muda de "Helios Energia
Solar / Reduza até 95% da sua conta de luz" para "Helios · Área do cliente / Olá, Juliana"; o menu
muda de "Planos, Simulador" para "Faturas, Chamados". **A anatomia do widget é a mesma.**

### 6.4 Veredito de H2

**NÃO SE SUSTENTA como custo** — o hedge custa ~3% do esforço, e o desenho que o torna barato é
mérito do plano, não sorte.

**SUSTENTA como promessa.** O risco real do perfil duplo não é preço de engenharia: é **vender dois
produtos e entregar um com interruptor de visibilidade**. A matriz de `23 §B.1.3` deixa isso explícito
— *"perfil **esconde**, não **remove**"*, com um link "mostrar configurações de {outro perfil}" no
rodapé. Um comprador de marketing que ouviu "temos um modo marketing" vai encontrar o mesmo widget
com o teaser ligado e uma aba a mais.

**Consequência:** se o discurso comercial for "dois produtos", a expectativa não é atendida na
primeira demo. Se for "um widget que muda de postura por caixa de entrada" — que é o que o plano
realmente entrega, e é uma boa história —, é honesto e defensável. É decisão de posicionamento, e
está sendo tomada por omissão.

---

## 7. A curva de valor: quando o cliente percebe alguma coisa

### 7.1 Esforço por onda (medido sobre a tabela mestra)

| Onda | Blocos | P | M | G | Pontos | % do plano | Acumulado |
|---|---:|---:|---:|---:|---:|---:|---:|
| 0 — Terreno | 10 | 6 | 3 | 1 | 23 | 7,1% | 7,1% |
| 1 — Nada mentindo | 23 | 9 | 14 | 0 | 51 | 15,8% | 22,9% |
| 2 — A conversa | 18 | 6 | 10 | 2 | 52 | 16,1% | 39,0% |
| 3 — Configuração | 17 | 3 | 12 | 2 | 55 | 17,0% | **56,0%** |
| 4 — Captura | 17 | 2 | 11 | 4 | 67 | 20,7% | **76,8%** |
| 5 — Prova de valor | 21 | 4 | 13 | 4 | 75 | 23,2% | 100% |
| **Total** | **106** | **30** | **63** | **13** | **323** | | |

*(o bloco `5.07` tem esforço "P/M" na tabela mestra; contei como P)*

### 7.2 O que o cliente percebe se o time parar em cada onda

| Se parar depois da… | O cliente percebe? | Muda a conversa comercial? |
|---|---|---|
| **Onda 0** | **Sim, uma coisa só**: o widget passa a viajar comprimido (`0.4`). Medi: hoje o `sdk.js` sai **28.834 B sem `content-encoding`** no HTTPS público. Todo o resto (merge, snapshots, gate de peso, paridade de config) é invisível | **Não** |
| **Onda 1** | **Sim, e é o mais visível do plano inteiro**: o widget de cada cliente passa a ter **a cor dele** no header, no botão de enviar, nos links e no launcher — hoje é o nosso `#2dc46f`. Contraste sobe de 2,25:1 para AA. CSS cai de 1.103.132 B para ≤ 80 KB. O atributo que o site manda para de sumir do painel (B6) | **Parcialmente** — sai do constrangimento e entrega "de onde veio o lead" **no nosso painel** (se houver `referer` — ver §3.1). Não entrega nada no GA4 nem no Gerenciador de Anúncios do cliente |
| **Onda 2** | Sim: mobile utilizável (hoje **0 de 5** alvos passam em 375 px, com **74,4%** do tráfego BR em mobile), estados de rede honestos, fila offline, `Esc`, dark automático, telemetria de erro | **Não.** Ninguém troca de fornecedor por causa de raio de balão — mas ninguém *fica* com um chat que não funciona no celular |
| **Onda 3** | Sim: o cliente configura sozinho o que hoje exige `rails console` ou colar parâmetro no snippet | **Não** — habilita, não vende |
| **Onda 4** | Sim: o widget **aborda**, qualifica e entrega ao WhatsApp | **SIM — é aqui.** É o gap de produto com a Leadster |
| **Onda 5** | Sim: o lead do chat aparece no Gerenciador de Anúncios e no GA4 do cliente, deduplicado | **SIM, e é o diferencial** — dedup por `event_id` "nem a Leadster faz" |

### 7.3 T34-04 — a conclusão (GRAVE)

**A primeira onda que muda a conversa comercial é a 4, com 56,0% do esforço já gasto.** E aquilo que
o estudo elegeu como *"a alavanca de maior valor por esforço"* (`10-gap §1.3`: **a atribuição, não a
interface**) só chega na 5, a **76,8%**.

Isso inverte a ordem do documento de decisão que originou o plano. O `10-gap-analysis §5` propunha
quatro ondas: 1 higiene → **2 origem ("sei de onde vem o lead", com C0+C2+C3+C1+C4)** → 3 captura →
4 prova. O plano mestre pegou a Onda 2 do estudo, **partiu ao meio**, deixou C0 na Onda 1 (correto e
elogiável) e **empurrou C1, C2 e C4 da segunda posição para a última**, inserindo duas ondas novas
(conversa e configuração, 107 pontos = 33% do plano) no meio.

**Consequência concreta:** entre a primeira entrega visível ao cliente (Onda 1) e a primeira entrega
que ele **compra** (Onda 4), o time atravessa 107 pontos de trabalho sem nenhum marco comercial. Em
qualquer projeto real, é aí que o patrocínio esfria — e é exatamente o que o próprio plano teme na
§3 item 4 ("o argumento que compra orçamento para as ondas seguintes").

**Existe um caminho barato que o plano já contém e não usa** — ver §11, movimento 3.

---

## 8. Contradições e furos internos

### 8.1 T34-02 — não existe lar para a configuração de aparência (BLOQUEADOR)

A arbitragem **A1** é chamada pelo próprio plano de *"a maior economia de risco de todo o plano"*
(§9 item 2). Ela decide:

> "`inbox.additional_attributes`, com **três chaves de topo** — `widget_profile`, `widget_triggers`,
> `widget_tracking` — declaradas **numa única edição** do strong params."

E a razão nº 4 é explícita: chaves de topo separadas, porque o update faz `merge` de **primeiro
nível** — confirmei em `inboxes_controller.rb:52-56` — então um sub-hash único faria um `PATCH`
parcial apagar as outras chaves.

**O furo:** o plano 23 declara **oito** dependências de backend (`BE-1`…`BE-8`). O plano mestre
rastreia cinco:

```
$ grep -o "BE-[0-9]" PLANO-MESTRE.md | sort -u
BE-1  BE-4  BE-6  BE-7  BE-8        →  faltam BE-2, BE-3, BE-5
```

**`BE-2`** é, textualmente (`23-plano-config-dashboard.md`): *"Configuração de **apresentação** hoje
presa ao snippet: **tema, posição, offsets, tipo e texto do lançador, esconder bolha, estilo do
painel**"*. É a dependência do defeito **D1** do plano 23 — *"Posição, tipo de bolha e título do
lançador vivem no `localStorage` do admin"*.

E o critério de pronto da Onda 3, item 5, exige:

> "Mudar a posição para 'esquerda', salvar e reabrir **em outro navegador e como outro
> administrador**: continua 'esquerda'."

**Não há onde gravar isso.** As três chaves declaradas são perfil, gatilhos e tracking. O plano 24
não menciona "posição" nem "offsets" uma única vez (`grep` retorna vazio). Portanto, na hora de
executar `3.09` (Tela 1 completa: "tema, lançador, offsets, textos"), acontece uma de três coisas:

1. **Uma segunda edição no `inboxes_controller.rb`** (🔴, +53/−9 upstream e +87/−6 fork) para
   declarar uma quarta chave — que é **exatamente** o custo que A1 diz estar evitando, e o argumento
   nº 4 dela deixa de valer;
2. **A aparência entra dentro de `widget_profile`** — semanticamente errado (aparência não é perfil)
   e, pelo merge raso, um `PATCH` de perfil passa a arrastar aparência junto;
3. **A Tela 1 não persiste** e o item 5 do critério de pronto da Onda 3 falha.

**Consequência:** a arbitragem que o plano apresenta como sua maior economia de risco está incompleta,
e a incompletude só aparece no meio da Onda 3, quando a tela já está sendo escrita.

**Correção (esforço P):** declarar **quatro** chaves em `3.01` — `widget_appearance` junto das outras
três — na mesma edição única. Custo zero agora; custo real depois.

### 8.2 T34-03 — `5.07` está cinco ondas atrasada (GRAVE)

Medi o que o plano lista como pendência V4:

```
$ curl -skI -H "Accept-Encoding: gzip, br" https://hmlchat.simplexsolucoes.com.br/packs/js/sdk.js
HTTP/2 200
content-length: 28834
cache-control: public, max-age=31556952
   (sem content-encoding · sem ETag · sem Last-Modified)
```

Um ano de cache, **sem validador**. Um navegador que já baixou o `sdk.js` não volta a pedi-lo — não
tem como revalidar, porque não há `ETag` nem `Last-Modified`.

Agora, o que muda o `sdk.js` ao longo do plano: `1.05` (literais → variáveis), `1.03` (tokens no
launcher), `1.23` (contrato do SDK com `Promise` e fila pré-boot), `2.08` (movimento), `2.09`
(mobile), `2.14` (degradação do launcher), **`4.06` (o teaser)**, `5.08` (coletor), `5.10` (tags).

E o bloco que conserta a propagação, `5.07`, está na **Onda 5**, com a observação do próprio plano:
*"afeta todo rollout de SDK"*.

**Consequência:** o teaser da Onda 4 — a peça de conversão do plano — pode não chegar a visitantes
recorrentes por até 12 meses depois do deploy. Pior: o sintoma é invisível (funciona no navegador de
quem testa, que limpou cache) e o diagnóstico é caro ("o teaser não aparece no site do cliente X").
O mesmo vale, com menos gravidade, para as correções de cor da Onda 1 que vivem no launcher
(`1.03`, `1.05`) — o launcher **é** SDK.

**Correção (esforço P/M):** `5.07` sobe para a Onda 0 ou início da Onda 1. É código nosso
(`config/environments/production.rb:23-26`), entra pelo deploy normal, não depende do nginx de VM
nenhuma — o próprio plano diz isso.

### 8.3 T34-06 — o aceite de zoom é inatingível (GRAVE)

Critério de pronto da Onda 2, item 7: *"Painel funciona em **320 px** e em **200% de zoom** sem perda
de conteúdo."*

`app/views/widgets/show.html.erb:6`, HEAD `ee87f5e799`:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=0" />
```

`maximum-scale=1` + `user-scalable=0` desabilita o zoom do usuário — é a violação **WCAG 1.4.4 (AA)**
que o estudo registrou (`05 §15.2 P1 #12`, com a correção pronta: *"substituível por
`font-size: 16px` nos inputs"*). Busquei nos 5 documentos:

```
$ grep -ril "user-scalable" plano/redesenho/*.md
(vazio)
```

**Nenhum bloco toca essa linha.** O bloco `1.06` (a11y mínima) mexe em `show.html.erb:2` (o `lang`),
não na `:6`.

**Consequência:** ou o aceite falha na revisão da Onda 2 e alguém descobre tarde que precisa mexer em
`show.html.erb` + nos inputs do composer (que é a Onda 2 inteira reaberta), ou — pior — o aceite é
declarado verde porque "o painel renderiza em 200%" sem ninguém notar que o usuário **não consegue**
dar zoom. E o widget continua reprovando um critério AA que estamos vendendo como diferencial
(`§9 item 5`: "onde o mercado inteiro é fraco, é barato ganhar").

### 8.4 T34-07 — segurança rebaixada a aviso, sem declarar (GRAVE)

`app/controllers/widgets_controller.rb:79-86`:

```ruby
def allow_iframe_requests
  if @web_widget.allowed_domains.blank? || embedded_from_non_web_origin?
    response.headers.delete('X-Frame-Options')
```

`allowed_domains` nasce `""` (`24-plano-backend-dados.md:86`). Portanto, **por padrão, o widget de
qualquer conta pode ser embutido por qualquer site do mundo** — que é como o estudo descreve
(`05 §15.2 P0 #3`), com a correção proposta: *"`allowed_domains` preenchido no onboarding com o
`website_url` que já é obrigatório"*, esforço **P**, na Onda 1 do gap analysis.

No plano isso virou o defeito **D8** e a tarefa **T0.7**, absorvida pelo bloco `0.8`:

> "aviso de `allowed_domains` vazio (**D8**)" · aceite: "a tela **diz** o que acontece com domínio
> vazio"

**A correção virou um texto explicativo.** Isso pode até ser a decisão certa — preencher
automaticamente quebraria clientes com subdomínios, staging ou múltiplos sites. Mas a decisão **não
está declarada em lugar nenhum**: não está em "o que NÃO vamos fazer", não está nas arbitragens, e o
plano nunca diz que trocou uma correção P0 por uma mensagem de UI.

**Consequência:** quem ler o plano acredita que D8 está resolvido. Ele está **descrito**. Numa
auditoria de segurança de cliente enterprise, "nós avisamos o administrador" não é resposta.

### 8.5 T34-11 — jsonb aberto sem teto (MENOR)

A arbitragem A1 estabelece que a evolução acontece *"**dentro** dos jsonb, que são hash aberto
(`{}`), sem tocar mais no controller"*. Correto em Rails — e significa que o strong params **não
filtra nada** dentro de `widget_triggers` e `widget_tracking`.

O plano cria teto de tamanho e quantidade para `custom_attributes` **do contato** (`1.14`) e nenhum
para o `additional_attributes` da inbox — que é servido **inteiro** a qualquer agente com a inbox
atribuída (M6, confirmado em `_inbox.json.jbuilder:27` + `inbox_policy.rb:22-27`) e vai para o ERB de
**toda página** do site do cliente.

O bloco `3.02` (schema por `json_schemer`) mitiga se o schema tiver `maxItems`/`maxLength`, mas isso
não está escrito. **Consequência:** um admin pode gravar um jsonb grande e engordar o HTML do widget
para todos os visitantes daquele cliente — o oposto do orçamento de bytes que o plano defende em
outros seis lugares.

---

## 9. O que se perdeu entre o estudo e o plano

### 9.1 T34-05 — seis itens sumiram sem entrar em "o que NÃO vamos fazer" (GRAVE)

O plano mestre tem uma §2.3 chamada **"Cobertura — nada ficou de fora"**, que confere as **277
tarefas das quatro frentes** contra os 106 blocos. A conferência está correta — eu amostrei e bate.
**Mas ela não cobre o que interessa aqui:** as frentes foram escritas *depois* do estudo, e o que
caiu **entre o estudo e as frentes** não aparece em conferência nenhuma.

Rodei a checagem que faltava — os 15 gaps de MESA (`10-gap §3.1`, critério: "4 ou mais players têm,
nós não") e os 15 diferenciais (`§3.2`) contra os 5 documentos do plano:

| Item do estudo | Classe no estudo | Esf. | No plano? | Em "não faremos"? |
|---|---|:---:|---|---|
| **M6** — facade (app sob demanda) | MESA 🔴 | G | **não** (`grep facade` = 0) | **não** |
| **M13** — analytics do widget (chats abertos, conversas iniciadas, leads, **dropout**) | MESA 🔴 | M | **não** (`grep dropout` = 0); só `1.22`, que é conversas por `utm_source` | **não** |
| **M14** — instalação documentada em WordPress / Wix / GTM | MESA 🔴 | P | **não** (`grep WordPress` = 0, `grep Wix` = 0) | **não** |
| **BE-5 / M36** — lead incompleto (persistir resposta parcial antes da conversa existir) | base do dropout | M | **não** — aparece **uma vez**, como dependência (`23:1155`), e não existe bloco | **não** |
| **D15** — A/B por mensagem, versionado | DIFERENCIAL | M | **não** (`grep "A/B"` = 0 em todo o plano) | **não** |
| Cookie com `secure` quando HTTPS | Onda 1 do gap, P0 | P | **não** (`grep secure` = 0) | **não** |

Alguns são defensáveis (o facade depende do emagrecimento, que o plano faz primeiro; A/B é produto
novo). **O problema não é a ausência: é a ausência silenciosa.** O plano tem uma lista de 25 itens
"o que NÃO vamos fazer", cada um com o número que sustenta a recusa — o que cria a expectativa
legítima de que *o que não está lá, está no plano*. Seis itens de MESA e DIFERENCIAL não estão em
nenhum dos dois lugares.

**Consequência:** numa reunião de escopo, alguém pergunta "e o teste A/B?" e a resposta é o silêncio
— não a recusa fundamentada que o plano dá para os outros 25. É assim que escopo cresce em reunião,
que é exatamente o que a §8 existe para impedir.

### 9.2 T34-08 — cinco riscos declarados não foram carregados (MÉDIO)

O `10-gap §6` lista riscos por categoria. O plano mestre §6 tem 25 riscos, muito bem construídos.
Cinco do estudo não chegaram lá:

| Risco no estudo | Evidência | Consequência de ignorar | No plano |
|---|---|---|---|
| `MutationObserver` na `<body>` do cliente com `subtree: true` | 09 §13.2 item 10 | Ruído contínuo no main thread do **site alheio** — é o tipo de coisa que faz o time de marketing do cliente vetar a instalação, que o próprio 05 §15.4 aponta como o diferencial (c) da Leadster | **0 ocorrências** |
| `user-scalable=0` viola WCAG 1.4.4 | 05 §15.2 P1 #12 | Ver T34-06 | **0** |
| Cookie sem `Partitioned` | 05 §15.2 P0 #4 | Storage particionado quebra continuidade em navegador que já bloqueia contexto de terceiro | **0** |
| **Contato criado no page-load**, antes de qualquer interação | 09 §13.2 item 12 | Base inflada de anônimos; polui relatório e, com a Onda 5, **infla evento de conversão** — o cliente decide mídia com número errado | **0** |
| Decisão automatizada sobre o lead (art. 20 LGPD; ANPD com IA entre os 4 eixos de fiscalização 2026-2027) | 08 §9.4.3 | Desqualificar lead por IA é decisão automatizada com direito a revisão | **0** |

O quarto merece destaque: se o contato nasce no page-load e a Onda 5 dispara `chatspx_lead` a partir
de "contato passou a ter e-mail ou telefone", a base de anônimos não afeta o evento — mas afeta todo
relatório de taxa (leads ÷ contatos) que o cliente vai olhar ao lado. É o risco **R11** do plano
("conversão contada em dobro") com outra causa, e sem mitigação.

---

## 10. Riscos estratégicos não declarados

Os 25 riscos do plano são de **execução**. Estes cinco são de **estratégia**, e nenhum aparece:

| Id | Risco | Evidência | Consequência | Mitigação barata |
|---|---|---|---|---|
| **E1** | **A Onda 5 inteira depende de decisão de terceiro.** 75 pontos (23,2% do plano, 4 blocos G) apoiados em CAPI, Measurement Protocol, Enhanced Conversions e OAuth de Meta e Google | O estudo já registra um precedente: *"a integração GA4 direta foi **descontinuada**; a documentação aponta para o GTM"* (`07-tracking-pixel-ga4.md:1202`). Janelas (7 d / 48 h / 72 h / 90 d) são política, não contrato | Meta ou Google mudam janela, exigência de consentimento ou modelo de credencial, e uma onda G vira retrabalho | Construir **5.03 + 5.04 + 5.05** (contrato de eventos, eventos, `event_id`) que são **nossos** antes de qualquer integração; e **5.10 no modo "somente `dataLayer`"**, que já é o padrão de fábrica e **não depende de ninguém** |
| **E2** | **CTWA é território da Meta.** `5.21` (**G**) depende de V1, que está **[NÃO VERIFICADO]** | O plano registra: "homologação tem **zero** mensagens com `referral`, então não serve de amostra" | Um bloco G no fim do caminho crítico pendurado numa pergunta sem resposta | V1 é uma consulta SQL em produção. Responder antes de planejar a onda, não durante |
| **E3** | **O upstream pode construir isso.** O plano mestre não carrega esse risco | O `10-gap §6.1` carregava, com a avaliação certa ("Baixo — três issues abertas há 3 anos"). E o v4.16.2 **já nos deu `companies` de graça** (M8) — o upstream avança em superfícies adjacentes | Se o Chatwoot lançar tracking nativo, nossa versão vira divergência de merge em vez de diferencial | Manter o tracking isolado em módulo próprio — o plano **já faz isso** (`app/services/tracking/` ⚪). Só falta o risco estar escrito |
| **E4** | **A estratégia inteira pressupõe fork mergeável.** A Onda 0 é um merge de 113 arquivos (+4.332 −7.635) e o upstream **já quebrou** `vite.config.ts` em quatro arquivos | `PLANO-MESTRE §0.3 M1`, e o bloco `0.3` | Se o upstream reescrever o widget (Vue 3 → outra coisa, ou reestruturação do SDK), o custo do fork sobe de degrau, e nada no plano diz o que fazer | Uma cláusula de saída: qual é o gatilho que faria a gente **parar de mergear** o widget e assumir divergência |
| **E5** | **Concorrentes rodam a mesma base MIT.** Existem no mínimo **6 operações brasileiras** vendendo Chatwoot whitelabel (04 §1406), uma delas com preço público e 14 páginas de comparativo | 04 §931: *"este é o playbook completo que o ChatSPX poderia executar — e alguém já está executando"* | Tudo que construirmos em `app/` é copiável em uma tarde por quem roda a mesma base. A arbitragem **A11** coloca a tela de tracking em `app/`, por uma boa razão de produto (o bitmask de `features.yml` está cheio) — mas a consequência competitiva não é discutida | Nada a fazer no código. Mas a decisão A11 merece a frase: "aceitamos que isto é copiável; o que protege é a fila server-side e o dado da frota, não a tela" |

E o risco que o estudo chamou de **"o risco que não é técnico"** (`10-gap §6.7`) o plano **carregou
bem** — é o R25 ("o plano andar e a história não ser contada", com as 16 vantagens verificáveis que
nunca apareceram em material comercial). Registro como acerto.

---

## 11. Recomendação

**Reordenar.** Não manter como está — duas premissas não medidas sustentam a primeira onda e a
primeira entrega comercial está a 56,0% do caminho. Não repensar — a tese central sobrevive à
auditoria, a arquitetura está certa, as medições que amostrei bateram todas, e o desenho do perfil
duplo é bom.

### Movimento 1 — Dois portões de medição antes de comprometer a Onda 1 (esforço P, não bloqueia a Onda 0)

| Portão | Consulta | Se a resposta for alta | Se for baixa |
|---|---|---|---|
| **V3** (hoje "só dimensiona o backfill") | `select count(*) filter (where additional_attributes->>'referer' ~ 'utm_\|gclid\|fbclid') …` por VM, conta e mês | Plano segue como está; C0 vira argumento de venda | **Cancelar `1.21`** (backfill), reduzir `1.19` ao prospectivo e **antecipar `5.08`** (coletor), que é onde a origem passa a existir de verdade |
| **V6** (hoje "Bloqueia: Nada") | inboxes por `channel_type` + campanhas ativas, por VM | Plano segue | Se a frota tiver poucas inboxes Website ativas, **a ordem inteira muda**, e possivelmente a decisão de fazer |

Custo: uma tarde. O que está em jogo: 11 pontos da Onda 1 e a credibilidade do "argumento que compra
orçamento".

### Movimento 2 — Três blocos mudam de lugar (esforço zero, só ordem)

1. **`5.07` (propagação do SDK) → Onda 0.** É pré-requisito de todo bloco que toca o `sdk.js` nas
   Ondas 1, 2 e 4. Medido: 1 ano de cache sem `ETag` (§8.2).
2. **`0.4` (compressão nas 4 VMs) ganha dono nominal e data.** É P, é fora do repositório, e é o
   único ganho perceptível da Onda 0 — medi que hoje **não existe** no HTTPS público.
3. **`3.01` declara quatro chaves, não três** — `widget_appearance` junto (§8.1). Custo P agora,
   custo de uma edição no arquivo 🔴 depois.

### Movimento 3 — Um marco comercial no meio, usando o que o plano já tem

O plano já contém um caminho de prova de valor que **não depende de segredo, de OAuth, de DPA nem
de chave de criptografia** — e portanto não depende de `0.10`, `5.02`, V2 nem V5:

| Bloco | O que é | Depende de |
|---|---|---|
| `5.03` | Contrato de eventos + registro server-side com `event_id` | `1.09` (bridge, Onda 1) |
| `5.04` | Os eventos que faltam, emitidos uma vez, do store | `5.03` |
| `5.05` | `event_id` nasce no backend e volta ao widget | `1.15`, `5.03` |
| `5.10` **em modo "somente `dataLayer`"** | O `dataLayer.push` — que o próprio plano define como **"padrão de fábrica"** | os três acima |

São ~11 pontos (3,4% do plano) que entregam **"o lead do chat aparece no GTM do cliente, com
`event_id`, sem tocar em pixel nenhum"** — o critério de pronto da Onda 2 do gap analysis, em uma
fração do custo. Colocá-los **logo depois da Onda 1**, antes da Onda 2, dá ao projeto um marco
comercial aos ~26% do esforço em vez de aos 76,8%.

### Movimento 4 — Partir a Onda 2, mas não pelo motivo que parece (e o contrafactual honesto)

A task me pediu para avaliar o contrafactual "e se a gente **não** fizesse o redesenho visual (Onda 2)
e fosse direto para captura + atribuição". **Fui medir e a premissa da pergunta não se confirma: a
Onda 2 não é redesenho visual.** Decompondo os 52 pontos:

| Natureza | Blocos | Pontos | % da onda |
|---|---|---:|---:|
| **Reconstrução de UI** (primitivos, `MessageRow`, balões) | 2.01 (G), 2.02, 2.03 | 14 | 27% |
| **Mobile e conversão** | 2.09 (mobile, hoje **0 de 5** alvos passam, com 74,4% do tráfego BR em mobile), 2.05 (composer) | 6 | 12% |
| **Confiabilidade** | 2.07 (estados), 2.15 (idempotência), 2.16 (fila offline), 2.13 (telemetria — hoje **zero** observabilidade e ~20 `catch { // Ignore }`) | 12 | 23% |
| **Peso** | 2.18 (**G** — JS eager ≤ 150 KB gzip) | 8 | 15% |
| **Acessibilidade** | 2.08 (`prefers-reduced-motion`, `forced-colors`), 2.11 (`Esc`), 2.10 (dark), 2.06 (`h1`, `main`) | 8 | 15% |
| Outros (render, i18n, degradação) | 2.12, 2.14, 2.17, 2.04 | 4 | 8% |

**Cortar a Onda 2 para "ir direto à captura" jogaria fora mobile, offline, telemetria e peso — e
manteria o custo estético.** O que se perde, quantificado: um widget de captura que não passa em
alvos de toque de 44 px, no país onde **74,4%** dos acessos são mobile (01 §3.6) e onde o mobile
converte pior (3,37% × 3,50%). Captura sem mobile é captura sem 3 de cada 4 visitantes.

**A recomendação certa não é cortar, é partir:**

- **Onda 2A — o que sustenta a captura** (2.05, 2.07, 2.09, 2.10, 2.11, 2.13, 2.16, 2.18 ≈ 38 pontos):
  fica onde está. Sem isso, a Onda 4 entrega captura que não funciona no celular e que ninguém
  consegue diagnosticar quando quebrar.
- **Onda 2B — o acabamento** (2.01, 2.02, 2.03, 2.04, 2.06 na parte visual ≈ 14 pontos): pode ir para
  **depois da Onda 4**, sem prejuízo. O próprio plano já reconhece que essa é a parte cortável (§3
  item 7: *"Onda 2 é a maior em volume e a que mais depende de gosto — e é a única que pode ser
  cortada sem quebrar as outras"*).

Com os movimentos 3 e 4, o marco comercial sai de **76,8%** para **~26%** do esforço, sem cortar
nenhum bloco e sem mexer em nenhuma decisão do Walisson.

### O que **não** recomendo mudar

- **O perfil duplo fica.** Custa 3% e o desenho (flags planas) é o motivo de custar isso. A revisão
  necessária é de **discurso comercial**, não de engenharia (§6.4).
- **O iframe fica** para o painel. O número (28.834 B × 456,1 KB) é bom demais para trocar.
- **A Onda 0 fica inteira, e primeiro.** O argumento do §9 item 6 é correto: sem harness, é aposta.
  Não achei nada para criticar aqui — e procurei.
- **As arbitragens A1 (com a quarta chave), A3, A5, A6 e A9** estão bem construídas e sustentadas por
  medição própria que eu refiz e confirmei.

---

## 12. Onde o trabalho está bom (uma linha cada, sem gastar espaço)

- **As medições são confiáveis.** Refiz nove por amostragem; **oito bateram exatamente** e a nona
  (a varredura de campo) sobreviveu a um método melhor que o original.
- **A arbitragem por medição, e não por opinião,** é o melhor traço do plano mestre: A6 reclassifica
  um risco Médio para Baixo mostrando que o método é byte-idêntico entre as tags.
- **A honestidade das lacunas** é real: `[NÃO VERIFICADO]` aparece onde deve, inclusive contra o
  interesse do próprio documento.
- **A regra "o widget lê flags planas, nunca o nome do perfil"** é o que torna o perfil duplo barato,
  e está repetida nos quatro lugares onde poderia ser esquecida.
- **A lista "o que NÃO vamos fazer"** com o número que sustenta cada recusa é um artefato melhor que
  o plano em si — quando está completa (§9.1).
- **R25** (o plano andar e a história não ser contada) mostra que o risco não técnico foi levado a
  sério.

## 13. Dimensões em que procurei e não achei problema

Registro explícito, para não parecer omissão:

1. **Cobertura das 277 tarefas das frentes → 106 blocos.** Amostrei as quatro conferências da §2.3 e
   bate. As três mudanças de estado (W3.1 absorvida, T1.4 eliminada, T-C1.1 corrigida) estão todas
   justificadas por arbitragem escrita.
2. **Caminho crítico e paralelismo.** Não achei dependência circular nem duas trilhas paralelas
   competindo pelo mesmo arquivo. A lista "o que NUNCA deve correr em paralelo" está certa,
   principalmente o item 2 (`Settings.vue`).
3. **Risco de merge.** As classificações ⚪/🟢/🟡/🔴 que amostrei conferem com o `git diff --numstat`.
4. **A decisão de não fazer auto-open** está sustentada por três evidências independentes e é o tipo
   de recusa que protege o produto do próprio cliente.
5. **Segurança do tracking** (segredo fora de `additional_attributes`, hash só no servidor, sem GA4
   nosso no site do cliente, `trackSingle`/`send_to`): não achei furo. É a parte mais bem pensada dos
   cinco documentos.

---

## Anexo — Como reproduzir as medições desta task

```bash
cd /home/chatwoot/chatwoot

# V-1 · as 11 chaves da inbox no ERB (base da arbitragem A1)
sed -n '7,32p' app/views/widgets/show.html.erb | grep -c "@web_widget.inbox"

# V-2 · --widget-color e o defeito B1
grep -rn -- "--widget-color" app/javascript/

# V-3 · zero tags de marketing no backend
grep -rn "fbq\|gtag\|dataLayer" app/ | wc -l

# V-4 · WidgetBuilder orfao
ls -la app/javascript/dashboard/routes/dashboard/settings/inbox/WidgetBuilder.vue
grep -rn "WidgetBuilder" app/javascript --include=*.vue --include=*.js

# V-5 · CSS do widget e a fracao de icones
python3 - <<'PY'
import re
s=open('public/vite/assets/widget-EcEcykJV.css').read()
r=re.findall(r'\.i-[^{}]*\{[^{}]*\}', s); b=sum(map(len,r))
print(f"total={len(s)} | regras .i-*={len(r)} | bytes={b} ({100*b/len(s):.1f}%)")
PY

# V-6 / N-1 · peso, compressao e cache do SDK no HTTPS publico
curl -skI -H "Accept-Encoding: gzip, br" https://hmlchat.simplexsolucoes.com.br/packs/js/sdk.js

# V-7 · colisao de migration
ls db/migrate | cut -d_ -f1 | sort | uniq -d

# V-8 · strong params fechado e merge raso
sed -n '212,222p' app/controllers/api/v1/accounts/inboxes_controller.rb
sed -n '48,58p'   app/controllers/api/v1/accounts/inboxes_controller.rb

# N-2 · volume do canal Website e do referer (homologacao; NAO rodar em producao sem autorizacao)
export PGPASSWORD=$(grep '^POSTGRES_PASSWORD=' .env | cut -d= -f2-) PGUSER=chatwoot PGHOST=localhost
psql -d chatwoot_production -c "select i.channel_type, count(c.id) from conversations c
  join inboxes i on i.id=c.inbox_id group by 1 order by 2 desc;"
psql -d chatwoot_production -c "select
  count(*) filter (where additional_attributes->>'referer' is not null) as com_referer,
  count(*) filter (where additional_attributes->>'referer' ~ 'utm_|gclid|fbclid') as com_campanha,
  count(*) as total from conversations;"

# T34-06 · a meta viewport que torna o aceite de 200% de zoom inatingivel
sed -n '6p' app/views/widgets/show.html.erb

# T34-07 · allowed_domains vazio remove o X-Frame-Options
sed -n '79,87p' app/controllers/widgets_controller.rb

# §9.1 · o que sumiu entre o estudo e o plano
cd plano/redesenho
for t in facade dropout "lead incompleto" "A/B" WordPress Wix secure user-scalable \
         MutationObserver Partitioned "IA generativa" guardrail "citação de fonte"; do
  printf "%-22s: %s\n" "$t" "$(grep -ril "$t" *.md | tr '\n' ' ')"
done

# §8.1 · dependencias de backend do plano 23 rastreadas no mestre
grep -o "BE-[0-9]" PLANO-MESTRE.md | sort -u        # BE-1 BE-4 BE-6 BE-7 BE-8 (faltam 2, 3, 5)

# §6.3 · similaridade dos dois mockups de perfil
cd mockups && python3 - <<'PY'
import re, difflib
c=lambda t: re.sub(r'data:[^"\')]{200,}','[DATA]',t).split('\n')
a=c(open('10-widget-marketing.html').read()); b=c(open('10-widget-suporte.html').read())
print("similaridade: %.3f" % difflib.SequenceMatcher(None,a,b).ratio())
PY

# V-9 · varredura de campo em navegador real (refazendo 06 §13.2)
#   script completo em: <scratchpad>/varredura.py  (Playwright, Chromium 145, --no-sandbox)
```

---

*Auditoria produzida em 12/08/2026 sobre `plano/redesenho/` (5 documentos, 8.210 linhas, 8 mockups) e
`plano/estudo-chat-web/` (22 relatórios). **Nenhum arquivo do repositório foi alterado; nenhum
artefato auditado foi tocado.** Onde nada foi verificado, está escrito que não foi.*
