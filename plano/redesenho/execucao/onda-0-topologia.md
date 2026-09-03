# Onda 0 — topologia de branches e plano de integração

Escrito pelo coordenador porque a onda passou a ter cinco worktrees e a ordem de integração
deixou de ser óbvia. **Nenhum push, nenhum PR, nenhum deploy** — tudo local.

## Os SHAs que importam

```
899fce1c92  v4.12.1              base comum (merge-base dos dois lados)
70e284a044  v4.16.2              o upstream que entrou
f26db6ee81  baseline 0.1         harness Playwright + 16 PNG + fixture anti-erro
d21794862b  conserto do harness  aquece o Vite antes do /__ready + encerra os servidores
93571c69db  merge da v4.16.2     recuperado do disco; pais = f26db6ee81 + 70e284a044
6ad7a9ec6e  merge + conserto     cherry-pick de d21794862b sobre 93571c69db
```

## Os worktrees, e o que cada um é

| Worktree | Branch | Parte de | O que acontece nele | Escreve? |
|---|---|---|---|---|
| `chatwoot-redesenho-base` | `redesenho-base` | — | bloco 0.1: baseline validado 8/8; harness consertado | fechado |
| `chatwoot-redesenho-merge` | `redesenho-merge` | `6ad7a9ec6e` | medição dos 16 snapshots + auditoria A6 | **NÃO** — tem de ficar limpo |
| `chatwoot-redesenho-correcoes` | `redesenho-correcoes` | `93571c69db` | as 22+3+15 correções da auditoria (C1) | sim, só C1 |
| `chatwoot-redesenho-build` | `redesenho-build` | `6ad7a9ec6e` | bloco 0.3 — destrava o aceite do 0.2 | sim, só o 0.3 |
| `chatwoot-redesenho-config` | `redesenho-config` | `6ad7a9ec6e` | blocos 0.7 / 0.8 / 0.9 | sim |

**A regra do worktree do merge** existe por um motivo específico e não é burocracia: é o único
lugar onde a v4.16.2 existe isolada. Qualquer edição lá mistura "o que o upstream fez" com "o que
nós fizemos", e a separação não é recuperável depois. Dois executores começaram o 0.3 ali e foram
parados antes de qualquer alteração.

## Ordem de integração — **plano revisado em 17/08, e o motivo da revisão**

### O que eu ia fazer, e por que mudei

O plano original era produzir **um único commit de merge para o 0.2** com a árvore já corrigida
(`git commit-tree <árvore> -p d21794862b -p 70e284a044`), para que o 0.2 continuasse sendo *"o
merge, sozinho"* como a §2.2 exige. **Descartado**, por três razões que só ficaram visíveis depois
que as auditorias fecharam:

1. **Esconderia o que mais importa saber.** A resolução original do merge trazia **duas migrations
   que apagam dado de cliente** e sete perdas de comportamento de IA. Embutir as correções na
   árvore do merge apaga esse fato da história. Daqui a seis meses, o próximo merge do upstream vai
   reintroduzir os mesmos padrões — e quem estiver lá precisa poder ler o que aconteceu desta vez.
2. **Ninguém revisa um commit de 3.463 arquivos.** O que é revisável são as **correções**, com
   título e escopo. Como commits separados, elas viram uma lista que o dono do produto consegue
   percorrer; embutidas, viram um diff que ninguém abre.
3. **A regra da §2.2 quer dizer outra coisa.** *"Sem nenhuma outra mudança no PR"* proíbe embrulhar
   trabalho de feature junto com o merge. Correção da própria resolução do merge não é outra
   mudança — é o merge terminando.

### A ordem que vale

```
d21794862b  fix(e2e): conserto do harness            ← bloco 0.1
93571c69db  merge(0.2): upstream Chatwoot v4.16.2    ← o merge como foi resolvido, honesto
   fix(0.2): …                                        ← as correções da auditoria, por natureza
   fix(0.2): …                                          (DADO, perdas de IA, dashboard…)
8684f07304  build(0.3): reconcilia o vite            ← bloco 0.3
   chore(0.7) · fix(0.8) · fix(0.9)                  ← frente config
   chore(0.5)                                        ← gate de peso
```

1. **C1 fecha** as correções em `redesenho-correcoes` e commita **por natureza**, cada mensagem
   citando o id do achado.
2. **0.3 já fechou** (`301bbdfdf9` em `redesenho-build`, integrado como `8684f07304` em
   `redesenho-merge`). O aceite dele inclui o mecanismo que destravou o 0.2: `curl` em
   `/app/javascript/entrypoints/sdk.js` voltou a responder **200**.
3. O coordenador rebasa as correções sobre `redesenho-merge` (que já tem merge + harness + 0.3).
4. **Os 16 snapshots** são medidos em `redesenho-build`, que tem o bundle final do widget — e o
   número continua valendo depois das correções, porque foi conferido que C1 toca
   `app/javascript/dashboard/**` e Ruby, e **nada** em `widget/` ou `shared/`.
5. `redesenho-config` (0.7/0.8/0.9) e o `0.5` rebasam sobre o resultado.

### O que continua fora da árvore do 0.2

- O conserto do harness (`d21794862b`) — é do bloco **0.1**, e é o primeiro pai do merge.
- O bloco **0.3**, os blocos **0.7/0.8/0.9** e o **0.5** — commit próprio cada um.

## Verificação de disjunção entre as frentes (feita antes de integrar, não depois)

A regra *"um worktree por frente"* só vale se as frentes forem mesmo disjuntas em **arquivo** — e
isso se mede, não se supõe. Medido em 17/08, com as duas frentes que mais se aproximam (as duas
mexem em `app/javascript/dashboard/`):

```
correcoes (C1):  49 arquivos
config (0.7/0.8/0.9):  22 arquivos
interseção:      VAZIA
```

Por isso o rebase da integração não deve conflitar. As duas chegam perto sem se tocar: C1 mexe em
`components-next/`, `components/widgets/conversation/` e `helper/actionCable.js`; o config mexe em
`settings/inbox/`, `i18n/*/inboxWidget.json` e `helper/preChat.js`.

**Se a interseção não fosse vazia**, a resposta certa não seria "resolver o conflito depois" — seria
serializar as duas frentes, porque conflito entre frentes nossas é sintoma de partição errada, e
resolvê-lo no rebase é decidir no pior momento possível: com as duas metades já prontas e ninguém
lembrando por que cada linha está ali.

## `public/version.json` — ruído, não contaminação

Ele aparece modificado em praticamente todo worktree e em quase todo `git status` desta onda.
**Não é edição de ninguém:** é artefato gerado por hook depois de cada commit, que grava o SHA e o
`deployed_at`. Ficou **fora** de todos os commits das frentes, e nenhum relatório propõe mexer nele.

Registrado aqui porque, numa onda em que "worktree limpo" é critério operacional, um arquivo que
suja sozinho gera alarme falso — e alarme falso repetido é como um guarda de verdade passa a ser
ignorado. O guarda do worktree-régua filtra este arquivo explicitamente.
