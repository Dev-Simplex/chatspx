# Unidades — melhorias no formulário de cadastro/edição

> **Estado em 21/09/2026: os 4 itens estão implementados e no ar no staging `nicolas`.** Os itens 1
> a 4 saíram nos commits `d8f6510a3f`, `a4c15d2f81`, `2ebf941e01` e `cc43063492` (este último trouxe
> também máscara de telefone, que não estava pedida). O refino de texto do botão de copiar — a parte
> **"O texto do botão"**, no item 3b — é o commit `b3d58370ef`. Falta a validação no chat.

**Responsável:** Nicolas Silva
**Origem:** pedido de 18/09/2026, com capturas da tela `Configurações → Unidades`
**Fluxo:** implementar na `nicolas` → validar no staging (nicolas.chatspx.app) → PR para `homologacao`.
Conventional Commits. `pnpm eslint` / `bundle exec rubocop -a`.
**Tela:** `app/javascript/dashboard/routes/dashboard/settings/units/` (`Index.vue` abre o modal, `UnitForm.vue` é o formulário)

---

## Resumo

| # | Item | Tipo | Precisa de migration? |
|---|---|---|---|
| 1 | Máscara no CEP | melhoria | não |
| 2 | Campo **Número** no endereço | melhoria | **sim** (1 coluna) |
| 3 | Horário livre (ex.: 07:48) + copiar horário para os demais dias | BUG + melhoria | não |
| 4 | Perguntar "salvar ou descartar" ao sair com o formulário preenchido | BUG (perde o que foi digitado) | não |
| 5 | Mais de um telefone, com rótulo | melhoria | **sim** (1 coluna) |
| 6 | Links de redes sociais | melhoria | **sim** (1 coluna) |
| 7 | CEP escrito como CEP (78.550-041) | melhoria | não |

---

## 1. Máscara no CEP

| | |
|---|---|
| Hoje | O campo aceita texto livre e mostra `78550041` do jeito que foi digitado. A busca no ViaCEP já funciona com ou sem traço. |
| Quero | Formatar enquanto digita: **`78550-041`**. Colar `78550041`, `78550-041` ou `78.550-041` dá no mesmo resultado. No máximo 8 dígitos; letras não entram. |
| Onde | `UnitForm.vue:724-729` (o `woot-input` do CEP). O `watch` de `UnitForm.vue:205-212` já tira tudo que não é dígito antes de buscar, então a busca não muda. |
| Como fazer | Não há biblioteca de máscara no projeto, e não precisa: uma função que pega os dígitos, corta em 8 e põe o traço depois do 5º. Aplicar no `update:modelValue` e também ao carregar a unidade (as que já existem estão salvas sem traço e passam a aparecer formatadas). |
| Como validar | Digitar `78550041` → vira `78550-041` e preenche endereço/cidade/UF. Colar `78.550-041` → idem. Abrir uma unidade antiga salva sem traço → aparece com traço. |

---

## 2. Campo "Número" no endereço

| | |
|---|---|
| Hoje | Um campo só, **Endereço**, que o ViaCEP preenche com `logradouro - bairro` (ex.: `Rua dos Papiros - Setor Residencial Sul`). Não há onde pôr o número da casa. E pior: quem escreve o número dentro do endereço **perde o número** se mexer no CEP depois, porque a busca sobrescreve o campo inteiro (`UnitForm.vue:192-194`). |
| Quero | Campo **Número** ao lado do Endereço (Endereço largo, Número estreito). Texto, não numérico: precisa aceitar `S/N`, `123-A`, `Km 12`. O ViaCEP continua preenchendo só o Endereço e **nunca** toca no Número. |
| Onde | Migration: `units.address_number` (string, opcional). Permitir em `app/controllers/api/v1/accounts/units_controller.rb:55`, devolver em `app/views/api/v1/accounts/units/_unit.json.jbuilder`. Tela: `UnitForm.vue:742-747` + o `form` inicial (`:91-94` e `:125-128`). Lista: `Index.vue:268` passa a mostrar o número junto do endereço. |
| Atenção | Deploy precisa de `db:migrate` além do `assets:precompile`, e o `schema.rb` tem de levar a coluna escrita à mão (em produção o migrate não redespeja o schema). Ninguém além da tela e da API lê `units.address` hoje (a IA não usa), então não há outro consumidor a ajustar. |
| Como validar | Cadastrar com CEP + número `123` → salvar → reabrir: número continua. Trocar o CEP depois → endereço muda, **número fica**. Lista mostra o número. |

---

## 3. Escolha dos horários

Dois problemas diferentes na mesma grade semanal:

### 3a. Não dá para escolher um horário que não seja hora cheia ou meia hora — BUG

| | |
|---|---|
| Hoje | O seletor é uma lista de 30 em 30 minutos (00:00, 00:30, 01:00…). **Se a unidade abre às 07:48, não tem como cadastrar.** A lista também é longa: 48 opções para rolar. |
| Causa | Só a tela limita. `BusinessDay.vue:13` gera a lista com `generateTimeSlots(30)`, e os quatro seletores (abre, fecha, início e fim da pausa — `:231`, `:240`, `:259`, `:263`) usam essa lista. O banco aceita qualquer minuto de 0 a 59 (`app/models/working_hour.rb:36-37`). |
| Quero | Digitar a hora direto, qualquer minuto: `07:48`. |
| Como fazer | Trocar os quatro seletores por `<input type="time">` — **o mesmo campo que o próprio formulário já usa** no editor de regras do calendário (`UnitForm.vue:974-985`, com a classe `CAMPO`). Fica igual nas duas partes da tela e não precisa de componente novo. |
| Decisão | `BusinessDay.vue` é **compartilhado** com o horário de atendimento da caixa de entrada (`WeeklyAvailability.vue`). Trocar nele corrige as duas telas de uma vez — a caixa tem a mesma limitação e o mesmo backend. Se for para mexer só em Unidades, precisa de uma prop no componente. **Recomendo trocar nas duas.** |

### 3b. Preencher dia por dia é trabalhoso — melhoria

| | |
|---|---|
| Hoje | Os 7 dias são preenchidos um a um, cada um com abre, fecha e pausa. Para a maioria das filiais, segunda a sexta é tudo igual. |
| Quero | Continuar podendo ajustar cada dia, mas com um atalho em cada linha que repete aquele horário nos outros dias que estão **abertos**. Dia fechado (fim de semana) continua fechado. |
| Uso típico | Preenche segunda → copia → ajusta só o sábado. Dois passos em vez de sete. |
| Onde | `UnitForm.vue:240-244` (`onSlotUpdate`) já troca o slot de um dia; copiar é aplicar o mesmo slot aos outros dias abertos. |
| Como validar | Segunda 07:48–18:00 com pausa 12:00–13:00 → copiar → terça a sexta iguais, sábado e domingo continuam fechados. Salvar e reabrir. |

#### O texto do botão (o nome tem de explicar a função sozinho)

**"Copiar" sozinho não serve**: não diz o que copia nem para onde vai. O verbo continua sendo
_copiar_ — é o que todo mundo já conhece —, mas nunca aparece sem complemento, e em nenhum lugar
da tela ele vira sinônimo ("aplicar", "replicar", "repetir" estão proibidos: **um verbo só**).

| Onde | Texto |
|---|---|
| Botão, na linha do dia | ícone de cópia + **`Copiar para os demais dias`** |
| Tela estreita | só o ícone, com o mesmo texto no tooltip |
| Tooltip (mostra o horário de verdade, não um texto genérico) | **`Copiar 07:48 – 18:00 para os demais dias abertos`** |
| Ajuda, uma linha acima da grade | **`Preencha um dia e use "Copiar para os demais dias" — os dias fechados continuam fechados.`** |
| Aviso depois de clicar (diz o que aconteceu, nomeando os dias) | **`Horário de segunda-feira copiado para terça, quarta, quinta e sexta.`** |

Três detalhes que fazem mais pela compreensão do que a palavra escolhida:

- **O botão só fica ativo quando aquele dia tem horário preenchido e está aberto.** No dia fechado
  ele aparece apagado, com o tooltip `Este dia está fechado — não há horário para copiar`. Assim
  ninguém clica para descobrir o que faz.
- **"dias abertos", nunca "dias úteis".** Dia útil dá a entender que o sistema sabe de feriado; o
  que a grade tem é dia aberto e dia fechado. O mesmo par de palavras vale para a tela inteira.
- **O aviso nomeia os dias atingidos**, em vez de "copiado para 4 dias": é o que deixa claro,
  sem ler manual, que o fim de semana ficou de fora.

i18n em `UNITS_MGMT.FORM.HOURS.COPY.{BUTTON, TOOLTIP, DISABLED, HELP, DONE}` — só `en.json`,
as outras línguas são da comunidade.

---

## 4. Perguntar antes de descartar o que foi preenchido — BUG

| | |
|---|---|
| Hoje | Com o formulário preenchido, **clicar fora do modal fecha e perde tudo**, sem aviso. O mesmo acontece com `Esc`, com o **X** e com **Cancelar**. |
| Quero | Se houver alteração não salva, abrir um segundo modal: **"Você tem alterações não salvas. Deseja salvar antes de sair?"** com três botões: **Salvar**, **Descartar** e **Continuar editando**. Formulário sem alteração fecha direto, sem perguntar. |
| Comportamento | **Salvar** → roda a mesma validação do botão Salvar; se faltar algo (nome, faixa invertida), volta para o formulário mostrando o erro. **Descartar** → fecha e joga fora. **Continuar editando** (e também `Esc` ou clique fora do aviso) → volta ao formulário com tudo como estava. |
| "Tem alteração?" | Guardar uma foto do formulário ao abrir (depois de carregar a unidade ou montar a grade padrão) e comparar com o atual. Conta tudo: dados, grade semanal e regras do calendário. |
| Armadilha | O `woot-modal` (`app/javascript/dashboard/components/Modal.vue:34-37`) fecha **antes** de chamar o `on-close` — `show = false` já desmonta o formulário e o que foi digitado some. Então a pergunta não pode morar no `on-close` do `Index.vue:364`; precisa interceptar **antes** de fechar (uma prop opcional tipo `before-close` no `Modal.vue`, que as outras telas não usam, cobre clique fora, `Esc` e X de uma vez). O **Cancelar** (`UnitForm.vue:1326`) passa pela mesma pergunta. |
| Como validar | Abrir nova unidade, digitar o nome, clicar fora → aparece a pergunta. Continuar editando → nome continua lá. Descartar → fecha. Abrir uma unidade existente e clicar fora sem mexer em nada → fecha direto. Repetir com `Esc`, X e Cancelar. |

---

---

## 5. Mais de um telefone, com rótulo

| | |
|---|---|
| Hoje | Um campo **Telefone** só. A filial com número de vendas, de locação e o WhatsApp do plantão não tem onde pôr os outros. |
| Quero | Uma lista: cada linha com um **rótulo curto** (Vendas, Locação, plantão) e o número, botão de remover na linha e **"Adicionar telefone"** embaixo. O telefone continua se formatando enquanto digita. |
| Onde | Coluna `units.contacts` (jsonb, `[{label, phone}]`). O `phone` que já existia **continua valendo**: passa a ser o primeiro contato da lista, mantido pelo model. A lista de unidades, a API e quem lê o campo seguem funcionando sem saber da mudança, e a migration faz o backfill do que já estava lá. |
| Regra | Linha sem número não vira registro — a tela cria a linha antes de preencher, e quem desiste deixa para trás. |
| Como validar | Cadastrar dois números com rótulo, salvar, reabrir. A lista de unidades mostra o primeiro. Apagar o primeiro → o segundo vira o principal. |

## 6. Links de redes sociais

| | |
|---|---|
| Quero | Outra lista: escolhe a rede (Instagram, Facebook, WhatsApp, YouTube, LinkedIn, TikTok, site) e cola o link. Quantos quiser, com remover e **"Adicionar link"**. |
| Onde | Coluna `units.social_links` (jsonb, `[{network, url}]`). Rede nova é um item na lista do front, **sem mexer no banco**. |
| Regra | Link colado sem `https://` ganha o esquema ao salvar: sem ele, o navegador trata `instagram.com/x` como caminho dentro do painel e o link não abre. |
| Como validar | Colar `instagram.com/sua.filial` sem https → salvar → reabrir e conferir que virou `https://instagram.com/sua.filial`. |

## 7. CEP escrito como CEP

| | |
|---|---|
| Hoje | `78550-041`. |
| Quero | `78.550-041` — ponto depois do segundo dígito, do jeito que se escreve. |
| Onde | Só a apresentação (`formatarCep`). A busca no ViaCEP sempre usou apenas os dígitos, então nada muda ali; CEP já salvo aparece com o ponto ao abrir. |

---

## Fora desta task

- **Complemento** e **Bairro** separados: não pedidos. O bairro continua dentro do Endereço, como o ViaCEP devolve.

<!-- Próximos itens entram aqui, numerados a partir do 5. -->
