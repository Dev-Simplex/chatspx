# Nomear contato direto pelo cabeçalho da conversa

**Nível:** júnior · **Risco:** baixo — sem migration, sem endpoint novo
**Onde validar:** staging antes da frota

---

## Por que esta task existe

Em 05/08 entrou em produção uma mudança de regra (PR #27): contato sem nome na origem
**fica sem nome**, nunca com nome fabricado.

A razão está comentada no código, em `app/services/campaigns/whatsapp/recipient_dispatch_service.rb`:

> `contact.name` é área de trabalho do time humano (eles anotam "Fulano / Casa do Beltrano"),
> então fabricar um nome escreve lixo num campo de trabalho. Foi assim que 110 contatos
> viraram "tudo bem".

A decisão está certa. Mas ela cria uma consequência: esses contatos passam a aparecer só
pelo telefone, e **o fluxo esperado é que o nome apareça durante a conversa** — a IA ou o
atendente pergunta e confirma.

## O problema

Hoje, quando o atendente descobre o nome, o caminho é:

1. clicar no nome no cabeçalho → abre o painel lateral do contato
2. encontrar o campo de nome
3. editar
4. salvar
5. fechar o painel

Cinco passos para digitar uma palavra, várias vezes por dia.

## O que fazer

Permitir nomear o contato ali mesmo no cabeçalho da conversa, sem abrir painel.

## Onde mexer

| Arquivo | O que tem lá |
|---|---|
| `app/javascript/dashboard/components/widgets/conversation/ConversationHeader.vue` (~linha 296) | O nome do contato, **já clicável** hoje via `@click="toggleContactPanel"` |
| `app/javascript/dashboard/api/contacts.js` (linha 38) | `PATCH` de contato — **já existe**, não precisa criar nada no backend |

## Critério de aceite

1. Contato **sem nome**: o cabeçalho oferece uma forma óbvia de nomear
2. Contato **com nome**: comportamento atual preservado, sem regressão
3. Salvar atualiza o cabeçalho **e** a lista de conversas, sem recarregar a página
4. `Esc` cancela sem salvar
5. Campo vazio **não apaga** um nome que já existia
6. `eslint` limpo nos arquivos tocados

## Uma decisão que é sua

O clique no nome deve virar edição (e o painel abre por outro gesto), ou a edição entra
como ação separada?

Não há resposta certa — escolha uma e **justifique no PR**. É uma decisão pequena de UX e
faz parte da task exercitar isso.

## Pegadinhas conhecidas

- O hook do `husky` quebra quando o repo está em worktree. Se travar no commit:
  `git commit --no-verify`
- Nas VMs, `bundle` só existe com `bash -lc` (RVM). Sem o `-l` dá
  "Could not locate Gemfile"

## Fora de escopo

- Editar telefone, e-mail ou qualquer outro campo do contato — só o nome
- Mexer no painel lateral de contato
- Qualquer coisa relacionada aos 6.456 contatos com identificador divergente
  (ver `task/reconciliador-incoming-9-digito.md`)
