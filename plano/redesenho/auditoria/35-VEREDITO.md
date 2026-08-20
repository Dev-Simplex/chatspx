# 35 — O VEREDITO

# Está à altura, com ressalvas.

O material é confiável no que apura — **53 das 54 referências `arquivo:linha` conferidas por duas
auditorias independentes se sustentam**, e as medições de peso batem até o byte. O que não está à
altura é a **consolidação**: o `PLANO-MESTRE` arbitrou dez divergências e não as escreveu onde o dev
vai ler, perdeu um pré-requisito de backend inteiro, e **9 dos 13 critérios de aceite conferidos
estão errados, são inatingíveis ou não têm mecanismo que os sustente** — o que faz ondas encerrarem
verdes com o defeito vivo. Nada disso é grande: o conserto do bloco todo é **escrita, não código**, e
é de esforço **P**.

> **Como esta síntese foi feita.** Li as quatro auditorias (31, 32, 33, 34) na íntegra e **refiz por
> conta própria 11 verificações** — incluindo as três em que as auditorias divergem entre si e a
> consulta ao banco que sustenta o achado mais caro da 34. Onde elas discordam, eu **arbitro com
> evidência** (§6) em vez de conciliar no texto. **Nenhum arquivo do repositório ou dos artefatos
> auditados foi alterado.**
>
> **Data:** 12/08/2026 · **Branch:** `homologacao` · **HEAD:** `ee87f5e799`

---

## 1. Os bloqueadores — o que impede começar a executar amanhã

**Há quatro. Nenhum é de código; três são de escrita e um é um `pnpm add`.**

| # | Bloqueador | O que trava | Quem achou | Correção |
|---|---|---|---|:---:|
| **B1** | **As dez arbitragens do mestre não foram propagadas aos quatro planos de frente** — que o próprio mestre declara serem "a fonte de verdade do detalhe". Confirmei pelos `mtime`: frentes 13:53–14:03, mestre 16:01, **nenhuma tocada depois** | O primeiro sprint. Três devs leem três documentos e constroem três arquiteturas: um cria a migration que A1 eliminou, outro grava `"suporte"` onde o resto lê `support`, o terceiro constrói o perfil como preset de escrita e não como flags | 31 (A-02) + eu | **P** |
| **B2** | **Não existe lar para a configuração de aparência.** `grep -o "BE-[0-9]"` no mestre devolve BE-1, BE-4, BE-6, BE-7, BE-8 — **faltam BE-2, BE-3 e BE-5**. `grep widget_appearance` nos cinco planos: **vazio** | A Onda 3. O aceite nº 5 dela ("mudar a posição para esquerda, reabrir em outro navegador e outro admin: continua esquerda") é **impossível de satisfazer** — não há coluna, chave, strong param nem montador | **31 (A-01) + 33 (L-01) + 34 (T34-02) + eu** — quatro achados independentes | **P** agora, **M** se descoberto no meio de 3.09 |
| **B3** | **A primeira tarefa do plano não roda.** O bloco 0.1 trata `playwright.config.js` como arquivo novo ("risco zero **por construção**"). Ele já existe, já serve `spec/e2e/copilot` (15 specs) e `spec/e2e/resolve-gate`, e **`@playwright/test` não está no `package.json`** | O dia 1. 0.1 é bloqueante do merge, que é bloqueante de tudo que toca código | 31 (A-10) | **P** |
| **B4** | **A premissa que sustenta 11 pontos da Onda 1 nunca foi medida** — "a origem já está no banco, e ninguém parseia". Reconferi em homologação: **0 conversas com `referer` em 3.179**; as 4 de widget trazem `"referer": null` | 1.18 → 1.22 (parser, backfill, relatório) — que o plano elegeu como "o argumento que compra orçamento" | 34 (T34-01), reconferido por mim | **P** (uma consulta) |

**Sobre o B4, e este é meu achado próprio:** a 34 disse "não sei por que é `null`, e o plano também
não". Fui ver. `base_controller.rb:38-44` grava o que o SDK manda, e
`conversation.rb:536-539` (`validate_referer_url`) **anula o valor na escrita** se a URL não passar
na validação. Os dois caminhos — "o SDK nunca mandou" e "a validação destruiu" — produzem exatamente
o mesmo `referer: null`, e **o banco não os distingue**. Isso tem duas consequências que nenhuma
auditoria juntou:

1. **O backfill (1.21) não pode recuperar o que a validação já anulou.** O dado não está degradado no
   banco; ele não está lá. Em 100% da amostra disponível, já se perdeu.
2. Portanto **1.20 ("sanear antes de anular") é a tarefa mais valiosa da trilha de origem** — e hoje
   ela não bloqueia nada: 1.19 (o parser) não depende dela (achado A-12 da 31). Subir o parser antes
   do saneamento continua destruindo dado enquanto o relatório promete respondê-lo.

---

## 2. Os graves, por tema

| Tema | O que é | Corrigir | **Não corrigir custa** |
|---|---|:---:|---|
| **G-A · Aceites que dão falso verde** | O grep do bloco 1.04 troca `shared/` por `sdk/`. **Medi: `sdk/` tem ZERO ocorrências de `n-brand` e de `getContrastingTextColor`; `shared/` tem 7 e 6.** O critério passa verde com o CSAT, os chips, os cards e o botão genérico ainda pintando `#2dc46f` fixo. Somam-se: `App.vue < 250` (inatingível: 386 − 88 + 5 = 303), zoom 200% (impossível: `show.html.erb:6` traz `user-scalable=0` e **nenhum bloco toca essa linha**), dois dos três contrastes errados, `@font-face` perdido no 1.08 | **P** | A Onda 1 é a bandeira do plano ("o produto para de mentir") e **encerra verde com o defeito vivo nas quatro superfícies mais visíveis depois do balão**. Pior efeito de segunda ordem: o primeiro aceite numérico liberado "porque é só um número" torna todos os outros 40 negociáveis |
| **G-B · Segurança e conformidade rebaixadas sem declarar** | `widget_tracking` é aceito no strong params na Onda 3 e só validado na Onda 5 — duas ondas de janela num campo servido inteiro a **qualquer agente e a qualquer agent bot** (`_inbox.json.jbuilder:27` + `inbox_policy.rb:22-27`, conferidos por mim). `allowed_domains` vazio (o default) **remove o `X-Frame-Options`** e a correção P0 do estudo virou "a tela avisa". O kill switch de consentimento (BK-33) não é escopo de bloco nenhum | **P–M** | Um cliente-piloto cola um Pixel com `access_token` na primeira tela improvisada e o segredo vaza antes de a validação existir. Em auditoria de cliente enterprise, "nós avisamos o administrador" não é resposta |
| **G-C · A vantagem nº 1 sem rede de segurança** | `sdk.js` = **28.834 B** (confirmei), 15,9× mais leve que a Leadster. **Oito blocos adicionam código eager** a ele. Confirmei que **`15 KB` tem 0 ocorrências no `PLANO-MESTRE`** e que o gate 0.5 mede o grafo do widget, não o SDK. E `5.07` (propagação) está na **Onda 5**, com `cache-control` de 1 ano **sem `ETag`** | **P** | É a única vantagem que este plano pode destruir **sem que um único aceite fique vermelho**. E o teaser da Onda 4 — a peça de conversão — pode não chegar a visitante recorrente por até 12 meses, com sintoma invisível (funciona no navegador de quem testa) |
| **G-D · Ausências silenciosas** | 16 das 68 capacidades, 8 dos 15 diferenciais, 4 das 24 decisões e 6 itens de MESA sumiram **sem entrar nas 25 linhas de "o que NÃO vamos fazer"**. Inclui a frente de IA inteira, o teste A/B, o facade, o lead incompleto (BE-5) e a decisão I5 — que era *"a única pergunta que realmente depende do redesenho de front"* e some atrás de um homônimo (o "I5" de webhooks) | **P** para escrever | Escopo volta em reunião como surpresa, e volta depois de as telas estarem construídas — que é quando fica caro. A §8 existe exatamente para impedir isso |
| **G-E · O mockup aprovado promete o que o plano não constrói** | O mockup 22 (contrato visual já mostrado) tem cinco seções; as seções 3 ("Salvar lead incompleto") e 4 ("Aviso de privacidade", "Barra de progresso") **não existem em bloco nenhum** | **M–G** (BE-5 é mudança do momento em que a conversa nasce) | Entrega-se 3 das 5 seções e a tela chega diferente do que foi aprovado. E sem lead incompleto, o "widget que trabalha" entrega leads e **não sabe quantos perdeu** |
| **G-F · Ordem de valor invertida** | O primeiro marco que muda a conversa comercial é a Onda 4, a **56,0%** do esforço; a atribuição — que o estudo chamou de "alavanca de maior valor por esforço" — chega a **76,8%** | **zero** (só ordem) | 107 pontos de trabalho entre a primeira entrega visível e a primeira que o cliente compra. É onde o patrocínio esfria — e o próprio plano teme isso na §3 |
| **G-G · Os mockups 20 e 21 não podem ir ao cliente hoje** | As **7 abas do topo são inertes** nas duas telas, e o preview corta 152 px em zoom 200% sem rolagem (reprova SC 1.4.4 e 1.4.10). O `index.html` — a porta de entrada — é a única página que **não usa o sistema que apresenta** (32 literais de cor, `<h1>` de 34 px, fonte diferente) | **P** (nove itens, todos P) | Clicar na aba seguinte é o primeiro gesto de qualquer pessoa diante daquela tela. A resposta é o silêncio, e quem recebe o link sozinho conclui que está quebrado |
| **G-H · Três itens do próprio checklist de a11y não fecham no widget** | `Esc` não fecha o painel (no mobile o foco cai no `<body>` e são **28 tabulações** até voltar), 6 alvos abaixo de 44 px, e em `forced-colors` o skeleton, o tooltip e o ponto de presença **desaparecem** | **P** | Comportamento que não está no mockup chega à implementação como "detalhe esquecido" — que é exatamente o que o mockup existe para impedir |

---

## 3. A taxa de veracidade — quanto confiar no resto do material

Três números, porque um só mentiria.

| O que o plano afirma | Conferências | Sustenta-se | Taxa |
|---|---:|---:|---:|
| **Sobre o código** (referências `arquivo:linha`, pesos, greps) | **54** (46 da task 31 + 8 minhas) | 53 | **98,1%** |
| **Números derivados** (contraste, contagens, agregados de esforço) | 8 | 3 | **37,5%** |
| **Sobre si mesmo** (critérios de aceite) | 13 | 4 | **30,8%** |

**Detalhe do que sustenta o primeiro número.** Reproduzi por conta própria: o CSS do widget em
**1.103.132 bytes exatos**, o `sdk.js` em **28.834**, os 25 pontos de `n-brand` (18 em `widget/` + 7
em `shared/` = 25, exato), `theme/colors.js:227` → `brand: '#2dc46f'`, `inbox_policy.rb:22-27`,
`_inbox.json.jbuilder:27`, `widgets_controller.rb:79-86`, `show.html.erb:6`. **Oito de oito.** A task
33 refez dez medições e bateu dez; a 34 refez nove e bateu oito. O único erro material em 54
referências é `theme/colors.js:123` (é `:227`) — e o dev acha por `grep` em dez segundos.

**Por que o segundo e o terceiro números são tão piores.** Os erros não estão na apuração, estão na
transcrição e na consolidação: contraste recalculado errado (`6,85` é `6,83`; o mesmo par de cores
aparece como `2,25` no resumo executivo e `2,27` no critério de pronto), "~74 custom properties" que
são 62, uma célula em branco escondendo **+253/−14** no arquivo mais perigoso do plano
(`conversation.rb`), um agregado "C0 = P" que contém três tarefas M, e um "o construtor virou" que
não virou nada — já era assim na v4.12.1.

**A leitura, em uma frase: confie no diagnóstico, não confie no gabarito.** Tudo que o plano diz que
o código *é*, o código é. Tudo que o plano diz sobre *si mesmo* — cobertura, rastreabilidade,
aceites — precisa ser reconferido antes de virar critério de aprovação.

E há uma asserção auto-referencial que é falsa e tem nome: a §2.3 do mestre chama-se **"Cobertura —
nada ficou de fora"**. Ela é **verdadeira** conferindo as 277 tarefas das quatro frentes contra os
106 blocos (amostrei e bate) e **falsa** contra o estudo, que é quem definiu o escopo. Ela confere os
planos contra si mesmos.

---

## 4. O que faltou, priorizado

| # | O que | Classe | Esforço |
|---:|---|---|:---:|
| 1 | **`widget_appearance`** — a quarta chave (BE-2). Destrava a Tela 1, o gap MESA M12 e o pedido do ícone | BLOQUEADOR | **P** agora |
| 2 | **Lead incompleto (BE-5)** — é pré-requisito de dropout (cap. 37), de analytics do widget (M13) e de qualquer teste A/B. Sem ele, entregamos leads sem saber quantos perdemos. **Está no mockup já aprovado** | BLOQUEADOR de escopo | **M–G** |
| 3 | **Teto do `sdk.js` no gate 0.5** e arbitragem entre os dois orçamentos que existem (15 KB gzip no apêndice do plano 22 × 40 KB crus no plano 25) | GRAVE | **P** |
| 4 | **As 22 linhas que faltam na §8** — IA (a frente inteira), A/B, facade, WordPress/Wix/GTM, roleta de números, feriados brasileiros, `open()`/`close()` idempotentes, stub queue no snippet. Onze delas são **P** e o estudo já avisava: *"não fazer os P é escolha, não restrição"* | GRAVE | **P** |
| 5 | **Rastreabilidade estudo ↔ plano** — uma coluna "origem no estudo" na tabela mestra. É o item de maior retorno da auditoria inteira: teria pego 16 capacidades, 8 diferenciais e 4 decisões antes de qualquer linha de código. Hoje os espaços de identificadores **colidem** (`M*`, `D*`, `V*`, `N*` e `I5` significam coisas diferentes nos dois corpos de documento) | MÉDIO | **P** |
| 6 | **Leitor de tela e navegador não-Chromium** — zero ocorrências de NVDA/VoiceOver e de WebKit nos cinco planos; toda a a11y se apoia em `axe` + asserções de DOM, que verificam presença de atributo, não experiência anunciada | MÉDIO | **P** |
| 7 | **Tela de instalação e onboarding** — a aba "Instalação" aparece no mockup 21 e **não tem bloco**. É a primeira tela que o cliente novo vê e a última que alguém planejou | MÉDIO | **P–M** |

### 4.1 O ícone do launcher — a pergunta direta do Walisson

**Resposta objetiva: não está coberto. Nem a troca de ícone, nem a foto de pessoa.**

Conferi no código, não no plano: `app/javascript/sdk/bubbleHelpers.js` monta o SVG a partir de um
`path` fixo (`bubbleSVG`, linha 10), com `fill` **cravado em `'#FFFFFF'`** (linha 46) e `title =
'Open chat window'` em inglês (linha 60). **Não existe caminho algum para uma imagem** — nem
`<image>`, nem `background-image`, nem parâmetro de configuração.

O planejamento toca esse arquivo **uma vez**: o item 34 do plano 22 troca o `#FFFFFF` por
`currentColor`. Isso é **correção de contraste** (o ícone branco some numa marca amarela), não troca
de ícone. A Tela 1 oferece para o lançador: posição, distância da borda, formato (só ícone / ícone +
texto), texto e "esconder a bolha". O campo **Avatar** existe na mesma tela, mas o próprio mockup
delimita: *"aparece no cabeçalho do widget e no teaser"* — explicitamente **não** no lançador.

**Para entregar isso faltam 11 especificações** (modelo do campo com três modos, onde grava, teto de
peso e formato, origem do byte, `preload`, fallback em erro, anel de contraste, recorte, nome
acessível, preview e modo escuro). **Esforço M**, caindo para **P–M** se entrar junto com 3.09 (a
tela do lançador já está sendo escrita) e 1.05 (o `fill` já vai ser mexido na mesma linha).

**Duas ressalvas honestas.** Primeira: **este pedido depende do bloqueador B2** — sem
`widget_appearance` não existe chave onde gravar. Segunda, sobre o mérito: o estudo mediu que **9 dos
13 launchers do corpus são um balão dentro de um círculo colorido e só a Leadster usa fotografia
humana**. Isso é evidência de que foto é **desvio**, não de que foto **converte mais** — nenhum
relatório traz teste comparando os dois. Recomendo entregar o campo (é barato, é pedido, e destrava
tanto a foto quanto o logo do cliente) e **não** prometer conversão em cima dele.

---

## 5. A leitura estratégica — o plano é a coisa certa?

**É.** A tese central sobrevive à auditoria mais hostil das quatro, e sobrevive nos pontos que
importam:

- **O iframe fica.** 28.834 B contra 456,1 KB da Leadster é bom demais para trocar, e o custo do
  caminho contrário está medido (239 `!important` no bundle deles).
- **O perfil duplo fica.** Custa **~3% do esforço** (10 de 323 pontos), medido por dois métodos que
  bateram entre si — e custa isso porque o plano tomou a decisão arquitetural certa: *o widget lê
  flags planas, nunca o nome do perfil*.
- **A Onda 0 fica inteira e primeiro.** A auditoria estratégica procurou o que criticar aqui e diz
  explicitamente que não achou.
- **A arbitragem A1** (jsonb em vez de coluna) elimina três migrations e o risco de colisão de
  timestamp. É a maior economia de risco do plano e está certa — falta-lhe apenas a quarta chave.

**Três correções de rota, e nenhuma delas é "repensar":**

1. **A ordem em que o valor chega está errada** (G-F). Não a ordem lógica — essa é sã.
2. **"Dois produtos" não é o que o plano entrega.** Medi junto com a auditoria: os dois mockups de
   widget são **99,0% idênticos**, e as 157 linhas de diferença são **o cenário do site host**, não o
   produto. O plano entrega *um widget que muda de postura por caixa de entrada* — que é uma boa
   história e é honesta. "Dois produtos" não sobrevive à primeira demo. **É decisão de posicionamento
   e está sendo tomada por omissão.**
3. **O plano não tem IA.** Zero ocorrências de "IA generativa", "guardrail" e "citação de fonte" em
   8.210 linhas, enquanto dois blocos **G** constroem exatamente o que o estudo declara commodity
   ("o chatbot de fluxo morreu comercialmente"). Isso pode ser uma escolha de escopo defensável — o
   plano é de chat de site, e escopo aberto mata projeto. **O problema não é a escolha; é ela não
   estar declarada.**

---

## 6. Onde as auditorias divergem — declarado e arbitrado

Quatro divergências reais. Não as concilio: arbitro.

### D1 · O peso do CSS do widget — três auditorias, três números

A 31 diz **1.103.132** ("bate byte a byte"); a 33 diz **1.103.138** ("Δ 6 B entre builds"); a 34 diz
**1.103.118** ("✅"). Fui medir:

```
1103138  public/vite/assets/widget-B98UQrMr.css   (27/07)
1103165  public/vite/assets/widget-BLFx8taJ.css   (28/07)
1103261  public/vite/assets/widget-CstjgxTk.css   (28/07)
1103132  public/vite/assets/widget-EcEcykJV.css   (29/07)  ← o do manifest
```

**A 31 está certa: 1.103.132 exatos, no artefato do manifest.** A 33 mediu **outro arquivo** (um
build de 27/07). A 34 mediu o arquivo certo, mas contou **caracteres** em Python (`len(str)`), não
bytes — daí os 14 a menos. **Arbitragem: o número do plano está correto.** E a divergência é a melhor
prova possível do achado que as três compartilham — há **quatro** `widget-*.css` no diretório e
qualquer glob casa o errado, que é exatamente o "falso verde do `size-limit`" que o plano denuncia.

### D2 · Os mockups estão à altura? A 32 diz que sim; a 33 diz que um deles é bloqueador

Não se contradizem — **medem coisas diferentes**, e o enquadramento importa. A 32 mediu o mockup
contra a especificação visual e contra a WCAG: **20 de 22 medidas conformes**, **472 de 478 nós de
texto aprovando em contraste**, zero cor literal nos três arquivos do widget, e diz explicitamente
"**BLOQUEADOR: nenhum**". A 33 mediu o mockup **contra o plano**: o mockup 22 promete duas seções que
não existem em bloco algum.

**Arbitragem:** as duas estão certas, e a leitura consolidada é — **os mockups estão bons como peça
de desenho; o casamento mockup × plano é que está quebrado.** O lado perigoso é o da 33, porque o
mockup já foi mostrado como o que a tela vai ser.

### D3 · O SDK (L-03) é bloqueador?

A 33 classifica como BLOQUEADOR; a 31 não menciona; a 34 trata como parte do facade sumido.
Confirmei o fato: `15 KB` tem **0 ocorrências** no `PLANO-MESTRE` e o gate 0.5 mede o grafo do widget.

**Arbitragem: é GRAVE, não bloqueador.** Bloqueador é o que impede executar; L-03 não impede executar
— impede **detectar**. Mas é o grave de maior prioridade do conjunto, porque o dano é assimétrico:
575 KB dentro do iframe custam ao visitante que **abriu** o chat; bytes no `sdk.js` custam a **100%
dos visitantes de todos os sites de todos os clientes**.

### D4 · A reordenação proposta pela 34 cabe no grafo validado pela 31?

A 31 auditou o grafo e o aprovou (zero ciclos, zero dependências para frente). A 34 propôs um marco
comercial antecipado — `5.03 + 5.04 + 5.05 + 5.10` logo depois da Onda 1 — estimado em **~11 pontos
(3,4% do plano)**. As duas auditorias nunca se falaram. **Fechei o grafo:**

```
fecho transitivo de {5.03, 5.04, 5.05, 5.10}
  → 0.1, 0.2, 1.09, 1.15, 1.23, 3.01, 5.01, 5.03, 5.04, 5.05, 5.07, 5.08, 5.09, 5.10
  blocos da Onda 5 arrastados: 5.01, 5.03, 5.04, 5.05, 5.07, 5.08, 5.09, 5.10  =  21 pontos
```

**Arbitragem: a recomendação sobrevive, o número não.** `5.10` depende de `5.08` e `5.09`, que a 34
não contou. O pacote real é **21 pontos (6,5%)**, quase o dobro do anunciado — e ainda assim entrega
o primeiro marco comercial a **~30% do esforço em vez de 76,8%**, sem cortar bloco nenhum.

E o fecho revela uma coisa que nenhuma das duas viu: **o caminho passa por `3.01`** — o mesmo bloco
onde falta a quarta chave (B2). O marco comercial antecipado e o bloqueador do BE-2 atravessam o
mesmo ponto do plano. Isso torna **corrigir 3.01 a ação de maior alavancagem do conjunto inteiro**.

### Sobre o que as quatro auditorias concordam

Registro porque convergência independente vale mais que qualquer argumento: **três auditorias que
não se leram acharam o mesmo bloqueador** (BE-2 / `widget_appearance`), por três caminhos diferentes
— rastreando as arbitragens, rastreando as dependências do plano 23 e rastreando os aceites da
Onda 3. Eu confirmei pela quarta via (`grep` no mestre). Quando quatro medições independentes
apontam para o mesmo lugar, o lugar existe.

---

## 7. O que fazer agora

Cinco ações, em ordem. **Nenhuma é código. As quatro primeiras somadas continuam sendo P.**

| # | Ação | Dono | Esf. |
|---:|---|---|:---:|
| **1** | **Congelar o `PLANO-MESTRE` como fonte única** e propagar as dez arbitragens: um bloco `> ARBITRADO — ver PLANO-MESTRE §5 A_x` no topo de cada seção contradita (`22:552`, `22:663`, `23:720`, `23:1305`, `23:1397`, `23:907`, `23:1398`, `24:1613`, `24:1580`, `25:231`), e fixar a lista canônica de flags de `profileConfig` num só lugar | **coordenador** | **P** |
| **2** | **`3.01` passa a declarar quatro chaves** — `widget_appearance` junto das outras três, na mesma edição única do arquivo 🔴, com a regra de precedência do BE-2 (banco é o padrão, `chatwootSettings` sobrescreve, a tela avisa) e com o campo do **ícone do launcher** dentro dela. É a ação de maior alavancagem: destrava o bloqueador, o gap M12, o pedido do Walisson e o marco comercial antecipado | **coordenador** | **P** |
| **3** | **Rodar os dois portões de medição antes de comprometer a Onda 1** — V3 (quantas conversas da frota têm `utm_`/`gclid`/`fbclid` no `referer`) e V6 (quantas inboxes Website ativas existem), por VM e por conta. **A consulta precisa separar "o SDK não mandou" de "a validação anulou"** — o banco sozinho não distingue. Se o volume for baixo, isso **não é fracasso**: cancela-se 1.21, reduz-se 1.19 ao prospectivo e antecipa-se 5.08 | **Walisson** libera o acesso · **dev** roda | **P** |
| **4** | **Corrigir os nove aceites defeituosos e destravar o dia 1**: o grep de 1.04 inclui `shared/`; `App.vue < 310`; os contrastes viram 9,24 / 6,83 / 2,27 com tolerância declarada; `@font-face` volta ao 1.08; o aceite de zoom da Onda 2 ganha o bloco que mexe em `show.html.erb:6`; `1.19 dep 1.20`; `pnpm add -D @playwright/test` com 0.1 reclassificado para 🟡. Junto, os nove **P** dos mockups (abas mortas, `overflow: auto` no preview, `index.html` na fundação, `Esc`, alvos de 44 px) | **dev** | **P** |
| **5** | **Decidir e escrever as ausências** — as 22 linhas que faltam na §8: a frente de IA, o teste A/B, o facade, WordPress/Wix/GTM, lead incompleto (BE-5: entra ou sai?), a decisão I5, e a coexistência com as campanhas legadas. **Isto é decisão de produto, não de engenharia** — e é o que impede o escopo de voltar em reunião depois de as telas estarem construídas | **Walisson** | **P** para decidir |

**Depois destas cinco, e só depois:** avaliar a reordenação do §6/D4 (marco comercial a ~30% em vez
de 76,8%) e partir a Onda 2 em 2A (o que sustenta a captura — mobile, offline, telemetria, peso:
fica onde está) e 2B (o acabamento visual: pode ir para depois da Onda 4). Não é urgente, e o próprio
plano já reconhece a Onda 2 como a única cortável sem quebrar as outras.

---

## 8. Uma última frase, sem rodeio

Este é um plano escrito por quem abriu os arquivos — e isso é raro o bastante para ser dito uma vez.
O que falta não é rigor: é **fechar o laço**. As arbitragens foram tomadas e não foram escritas onde
o dev lê; a cobertura foi conferida contra si mesma e não contra o estudo que a encomendou; os
aceites foram escritos com números que ninguém recalculou. Um dev competente não trava neste plano —
**ele executa a coisa errada com confiança**, que é pior, porque não gera pergunta.

O conserto é de um dia de escrita, e é hoje. Depois da Onda 3 começar, é retrabalho em arquivo 🔴.

---

### Anexo — as 11 verificações que refiz nesta síntese

```bash
cd /home/chatwoot/chatwoot

# D1 · o CSS do widget: 4 artefatos, 4 tamanhos (o do manifest e o EcEcykJV)
for f in public/vite/assets/widget-*.css; do echo "$(stat -c%s "$f") $f"; done   # 1103132 no manifest

# B2 · as dependencias de backend rastreadas no mestre e a chave que nao existe
grep -o "BE-[0-9]" plano/redesenho/PLANO-MESTRE.md | sort -u     # BE-1 BE-4 BE-6 BE-7 BE-8
grep -ril "widget_appearance" plano/redesenho/*.md               # vazio

# B1 · as arbitragens nao foram propagadas (mtime)
ls -l --time-style=+%d/%m\ %H:%M plano/redesenho/*.md            # frentes 13:53-14:03 < mestre 16:01

# B4 · a premissa da Onda 1, reconferida em homologacao (leitura, sem escrita)
psql -d chatwoot_production -c "select count(*) filter (where additional_attributes->>'referer' is not null),
  count(*) from conversations;"                                  # 0 de 3179
sed -n '536,540p' app/models/conversation.rb                     # validate_referer_url ANULA na escrita
sed -n '38,44p' app/controllers/api/v1/widget/base_controller.rb # de onde vem o valor

# G-A · o grep de aceite do 1.04 troca shared/ (13 pontos) por sdk/ (zero)
grep -rn "n-brand" app/javascript/widget app/javascript/sdk app/javascript/shared | wc -l   # 18 / 0 / 7
grep -rn "getContrastingTextColor" app/javascript/{widget,sdk,shared} | wc -l               # 12 / 0 / 6
sed -n '6p' app/views/widgets/show.html.erb                      # user-scalable=0 (aceite de zoom impossivel)

# G-C · o teto do SDK nao esta no gate
grep -c "15 KB" plano/redesenho/PLANO-MESTRE.md                  # 0
stat -c%s public/packs/js/sdk.js                                 # 28834

# 4.1 · o icone do launcher
sed -n '44,48p;58,62p' app/javascript/sdk/bubbleHelpers.js       # fill '#FFFFFF' cravado, title em ingles

# D4 · fecho transitivo do movimento comercial antecipado
#   -> 8 blocos da Onda 5, 21 pontos (nao 11), passando por 3.01
```

---

*Síntese produzida em 12/08/2026 sobre as auditorias `31-planos.md`, `32-mockups.md`,
`33-lacunas.md` e `34-tese.md` (3.489 linhas), com **11 verificações independentes** no HEAD
`ee87f5e799` — incluindo as três em que as auditorias divergiam entre si. **Nenhum arquivo do
repositório e nenhum artefato auditado foi alterado.** Onde não verifiquei, está escrito que não
verifiquei.*
