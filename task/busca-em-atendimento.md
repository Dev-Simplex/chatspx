# Barra de busca na aba "Em atendimento"

**Responsável:** Nicolas Silva
**Origem:** pedido de 22/09/2026, com captura da aba `Em atendimento`
**Fluxo:** implementar na `nicolas` → validar no staging (nicolas.chatspx.app) → PR para `homologacao`.
Conventional Commits. `pnpm eslint` / `bundle exec rubocop -a`.
**Onde:** `AttendanceIndex.vue` (a página), `store/modules/activeAttendances.js`, `api/activeAttendances.js`,
`app/controllers/api/v1/accounts/active_attendances_controller.rb`

---

## Por que esta task existe

A aba lista **99 atendimentos em 7 páginas**, 15 por vez. Para responder "este cliente já está sendo
atendido?" — que é a pergunta para a qual a tela existe — hoje é preciso **paginar de 15 em 15 até
achar**. Quem tem o nome ou o telefone na mão não tem onde digitar.

## O que fazer

Um campo de busca no cabeçalho, ao lado do título **Em atendimento**, com lupa e o texto de apoio:

```
Em atendimento                    🔍 Buscar por contato, telefone ou agente
```

Digitou, a lista responde. Nada de botão "Buscar": filtra sozinho enquanto digita, com uma pausa
curta (~300 ms) para não disparar uma requisição por tecla.

## A decisão que define a task

> **A busca acontece no SERVIDOR, nunca na página carregada.**

É o ponto que separa uma busca útil de uma que mente. A tela tem 15 das 99 linhas na mão; filtrar o
que já está carregado procuraria em 15 e diria "não achei" sobre as outras 84 — **exatamente a
resposta errada** numa tela cuja função é evitar atendimento duplicado. O termo vai para a API como
`?q=`, e o backend filtra antes de paginar.

## O que entra na busca

| Campo | Exemplo do que casa |
|---|---|
| Nome do contato | `Amanda`, `Layce` |
| Telefone do contato | `99927`, `+5566999274845` |
| E-mail e identificador do contato | o mesmo par que a busca de contatos já usa |
| Nome do agente | `João Vitor`, `Rogerio` |

**Time e caixa ficam de fora de propósito** (`desenvolvimento`, `simplex_996571379`): são conjuntos
pequenos e repetidos, e casariam com quase toda a lista a cada letra — viram **filtro**, não busca. Se
a necessidade aparecer, é uma segunda entrega, com seletor próprio.

## Como fazer

**Backend** (`active_attendances_controller.rb`, dentro de `fetch_attendances`):

- `params[:q]` com menos de **2 caracteres** = sem filtro (uma letra devolve a lista inteira e só
  custa query).
- Reaproveitar o molde que o projeto já usa em `contacts_controller#search`:
  `name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q OR contacts.identifier LIKE :q`, com
  `%termo%`, agora somado ao nome do agente (`users.name ILIKE :q`).
- **Telefone digitado com máscara.** Quem copia do painel cola `(66) 99927-4845`, e o banco guarda
  `+5566999274845`: o `ILIKE` cru não casa. Quando o termo é **só dígitos e pontuação**, use os
  dígitos contra o telefone sem pontuação (`regexp_replace(phone_number, '\D', '', 'g')`). Um campo,
  duas estratégias — quem digita nome cai na primeira, quem digita número cai na segunda.
- **`joins`, nunca `includes`.** O próprio arquivo já registra a armadilha: `includes` + `order` vira
  `LEFT JOIN` e **quebra o `total_count`**, ou seja, a paginação. A busca precisa de `joins(:contact)`
  e `left_joins(:assignee)` (o agente pode ser nulo).

**Store e API** (`activeAttendances.js`, `api/activeAttendances.js`): `q` viaja junto do `page`, do
mesmo jeito que o `contact_id` já viaja.

**Tela** (`AttendanceIndex.vue`): campo no `<header>` (hoje só tem o título, linha ~180), termo na
URL como `?q=`, ao lado do `?page=` que já está lá.

## Quatro detalhes que decidem se fica bom

- **Buscar volta para a página 1.** Sem isso, procurar estando na página 5 devolve "nada encontrado"
  para um termo que tem 3 resultados na página 1.
- **Vazio de busca ≠ vazio de verdade.** Hoje a tela tem um estado para "ninguém em atendimento". Com
  busca, é preciso um segundo: *"Nenhum atendimento para «amanda»"* + **Limpar busca**. Dizer "ninguém
  em atendimento" para quem acabou de digitar um nome é a mesma mentira que a tela existe para evitar.
- **Resposta atrasada não pode vencer a nova.** Digitando rápido, a requisição de `ama` pode chegar
  depois da de `amanda` e repintar a lista errada. O store guarda o termo pedido e **descarta** a
  resposta que não for a do termo atual.
- **O chip "2+ abertos" continua olhando a conta inteira.** Ele vem de `fetch_duplicated_contact_ids`,
  que hoje conta fora da página de propósito. **Não** aplicar a busca nele: se aplicar, buscar por
  "Amanda" esconderia justamente o aviso de que ela tem duas conversas abertas.

## Como validar

No staging, com os 99 atendimentos de hoje:

1. Digitar `amanda` → a lista mostra os atendimentos dela, o rodapé passa a dizer "Exibindo 1 - N de N"
   e o chip **2+ abertos** continua aparecendo.
2. Digitar `99927` e depois `(66) 99927-4845` → o mesmo contato nos dois.
3. Digitar o nome de um agente (`João Vitor`) → só os atendimentos dele.
4. Ir para a página 4, digitar um termo que só existe no começo da lista → volta para a página 1 com
   resultado (e não "nada encontrado").
5. Digitar `zzzz` → estado vazio próprio, com **Limpar busca**; limpar devolve a lista inteira.
6. Recarregar a página com `?q=amanda` na URL → volta buscando o mesmo termo.
7. Digitar rápido `a` → `am` → `amanda` e conferir que a lista final é a de `amanda`.

## Fora desta task

- Filtro por time, caixa ou status (é seletor, não busca).
- Busca dentro do conteúdo das mensagens: a aba não expõe mensagem nenhuma, só metadado, e puxar
  conteúdo para cá esbarraria nas travas de isolamento que o endpoint hoje não precisa aplicar.
