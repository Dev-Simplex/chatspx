---
description: Revisa um ou mais PRs, e se nada quebrar, mergeia e leva para as VMs de produção. No fim, oferece alinhar a homologação e as VMs dos devs
argument-hint: <numero(s) do(s) PR(s), ex: 99 ou 99 100 101>
allowed-tools: Bash, Read, Grep, Glob, Edit, Write
---

Você vai conduzir a promoção de **$ARGUMENTS** (um ou mais PRs) do repositório
`Dev-Simplex/chatspx`.

**Com mais de um PR, trate como LOTE**: revise todos, mergeie todos, e faça **um
único deploy no fim** — um bundle, um restart por VM. Deployar PR a PR multiplica
a janela de instabilidade e é como se deixa uma VM para trás.

**Primeira vez nesta máquina?** Rode antes:
`bash scripts/ops/setup-promover-pr.sh` — ele confere os 4 requisitos (repo, `gh`
autenticado com permissão de merge, chave SSH das VMs, e as peças do comando) e
diz exatamente o que falta. Sem o SSH dá para revisar e mergear, mas não para
deployar.

Este comando existe porque o processo tem armadilhas que já derrubaram produção
nesta semana. Siga as fases na ordem. **Não pule a fase 1**, e não trate o
resultado do script como opinião: ele mede o que o GitHub esconde.

## Fase 1 — Raio-X (obrigatória, sempre primeiro)

```bash
python3 scripts/ops/pr-raiox.py $ARGUMENTS --frota
```

Aceita vários números de uma vez (`99 100 101`); ele analisa um a um e fecha com
o resumo do lote. A frota é consultada só uma vez, no fim.

O script responde três coisas que você **não** deve tentar responder de cabeça:

- **O que o merge realmente traz.** A lista de arquivos do GitHub mede contra a
  merge-base e esconde carona. O PR #77 anunciava 2 arquivos e arrastou 95
  commits para 6 VMs.
- **O que o deploy vai exigir.** Frontend pede build de assets, migration pede
  `db:migrate`, `Gemfile.lock` vira release de plataforma com `bundle install`.
- **Onde a frota está.** Uma VM fora do commit da branch pode ter trabalho que
  só existe nela; um fast-forward ingênuo apagaria.

Se o veredito for **PARE E LEIA**, não siga sozinho: explique ao usuário o que
foi encontrado e pergunte como proceder.

## Fase 2 — Revisão de verdade

O script não lê código. Você lê:

1. `gh pr view <n> --json body --jq .body` e o diff, **para cada PR do lote**.
   Se o diff mostrar arquivo como REMOVIDO e você não esperava, não conclua nada:
   mergeie num worktree e confira. Arquivo que a base ganhou depois aparece como
   deletado no diff, e o merge não o apaga.
2. Procure o que costuma quebrar: chamada em laço que vira N requisições HTTP,
   limite de API (o Vista recusa paginação acima de 50 e devolve **vazio sem
   erro**), campo que sai do strong params, `update!` em jsonb que substitui em
   vez de mesclar, mudança de conduta que afeta outro fluxo.
3. **Rode os testes dos arquivos tocados** e compare com o baseline. O CI deste
   repositório é **vermelho por defeito**: falha de teste só conta se não falhar
   também na branch base. Nunca rode dois `rspec` ao mesmo tempo (mesmo banco).

## Fase 3 — Merge

```bash
# repita para cada PR aprovado, na ordem
sha=$(gh pr view <n> --json headRefOid --jq .headRefOid)
gh pr merge <n> --merge --match-head-commit "$sha"
```

O `--match-head-commit` existe porque o `gh` já pegou head velho por 30 segundos
e mergeou a versão errada. Se o PR precisa ir para produção sem levar o que já
está na homologação, use cherry-pick dos commits do autor em vez do merge direto.

## Fase 4 — Deploy (merge não muda nada no cliente)

**Um deploy para o lote inteiro**, depois do último merge. O pacote vai do commit
que as VMs têm hoje até o topo da branch, então cobre todos os PRs de uma vez.

As VMs de produção:

| VM | endereço |
|---|---|
| PRODUCAO | local (a própria máquina) |
| TOZI | `3.94.9.51` — cliente real |
| CATATAU | `3.85.130.14` |
| SENTINELA | `54.166.220.138` |
| FABRICA | `3.87.182.184` |
| AGN | `13.221.167.143` |
| CDSOLAR | `13.218.193.75` — cliente real (novo) |

A **TOZI não tem Elastic IP**: o endereço dela já mudou num stop/start da AWS. Se
não responder, confira o console EC2 antes de concluir que caiu.

Comece pela CATATAU, que não é cliente crítico. A TOZI vai primeiro só quando o
usuário pedir.

**TOZI e CDSOLAR são clientes**: só entram no deploy com OK explícito do usuário, pedido
**a cada deploy**, e vão por último. Nem leitura por SSH sem esse OK.

```bash
# 1. pacote (só o que entrou, conferido pelo tamanho: 2 arquivos ≈ poucos KB)
git bundle create /tmp/rel.bundle <branch> --not <commit_anterior>

# 2. em cada VM
git fetch /tmp/rel.bundle <branch> && git merge --ff-only FETCH_HEAD
# se tiver migration:
RAILS_ENV=production bundle exec rake db:migrate
# conferir SEMPRE (o timer também confere, e aborta se achar down):
RAILS_ENV=production bundle exec rake db:migrate:status | grep -c '^   down'

# 3. instalar ou atualizar o timer, a cada deploy, para o script novo chegar
cd /home/chatwoot/chatwoot/deployment
sudo install -m 750 -o root -g root chatwoot-restart-noturno.sh /usr/local/sbin/
sudo install -m 644 -o root -g root chatwoot-restart-noturno.service chatwoot-restart-noturno.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now chatwoot-restart-noturno.timer
```

**Por padrão não reinicie.** O processo no ar continua servindo o código e o front
antigos até o restart (o Puma sobe com `preload_app!` e o manifest do Vite fica em
memória), então código e assets podem ir de dia. O timer reinicia web e workers às
20:00 de Cuiabá, só se o disco andou depois que o web subiu, e aborta sozinho se
houver migration pendente. O `install` usa o acesso de root que a VM tiver. O
script vai para `/usr/local/sbin` como root porque o do checkout é do `chatwoot`, e
root executando arquivo que o `chatwoot` pode editar é escalada de privilégio.

Restart na hora só quando o usuário disser que é urgente (hotfix), com OK
explícito, e aí do jeito de antes: `db:migrate:status` zerado e
`sudo systemctl restart chatwoot-web.1 chatwoot-worker.1` (na PRODUCAO também
`chatwoot-worker.bulk` e `chatwoot-worker.realtime`, que o `chatwoot.target` não
cobre).

**Migration com restart adiado.** Entre o migrate (de dia) e o restart (20:00), o
código VELHO roda contra o schema NOVO. Migration aditiva (criar tabela, coluna,
índice, trocar FK) é segura. Migration que remove ou renomeia tabela ou coluna, ou
muda o tipo ou o `null: false` de coluna que o código velho usa, **não pode
esperar**: faça o deploy inteiro junto do restart, às 20:00 ou na hora como
urgente com OK. Leia as migrations que o raio-X lista antes de decidir.

Com frontend, antes do passo 2: build **no checkout principal**
(`/home/chatwoot/chatwoot`), nunca dentro de worktree, onde o `pnpm exec vite
build` entra em loop infinito. Use heap 12288 (`NODE_OPTIONS
'--max-old-space-size=12288'`): com 4096 essa base estoura OOM, e o OOM **não
derruba o deploy**, o exit code vem mascarado e o precompile termina "com
sucesso" sem ter gerado nada. Depois do build, gerar os `.gz` (o nginx usa
`gzip_static` e o vite não gera).

Para levar os assets sem copiar 1,1 GB: empacote só o que a build acabou de
gerar, sem os `.map`, e extraia por cima na VM (sem `--delete`, para o entry
antigo continuar servindo quem ainda não recarregou).

```bash
find public/vite -newermt '<AAAA-MM-DDTHH:MM:SS>' -type f ! -name '*.map' -print0 > /tmp/novos.list0
tar -czf /tmp/assets.tgz --null -T /tmp/novos.list0   # ~19 MB, com o manifest dentro
```

**Não restaure nem escreva o `public/version.json` à mão.** É ele que faz a aba
aberta há dias recarregar sozinha (`autoUpdateHelper.js` compara a cada polling), e
quem o escreve é o boot do web (`config/initializers/app_version.rb`), com o commit
com que o web subiu. Escrito de dia, a aba recarrega à toa no front velho, guarda a
versão nova e não recarrega mais quando o web novo sobe às 20:00. Só faça
`git checkout -- public/version.json` se o `merge --ff-only` recusar por causa dele.

### Três armadilhas de shell que custam 15 minutos cada

1. **Só a AGN alcança o GitHub.** TOZI, CATATAU, SENTINELA e FABRICA respondem
   `could not read Username` no `git fetch`. Por isso o pacote é a regra, não o
   plano B. E o `fatal:` sai em **stderr**: um `&& echo OK` te engana.
2. **`sudo -u chatwoot bash -c "..."` roda no diretório do `ubuntu`**, não no do
   chatwoot. O sintoma é `fatal: not a git repository`, e parece problema de
   permissão quando é só o `cd` faltando. Use `git -C /home/chatwoot/chatwoot`
   ou ponha o `cd` **dentro** das aspas.
3. **`source /usr/local/rvm/scripts/rvm` mata script não interativo.** Ele
   encerra a shell na hora, sem imprimir nada, e devolve 1. Você vê saída vazia
   e acha que o SSH falhou. Para ter o Ruby, chame `sudo -i -u chatwoot bash
   /tmp/script.sh`, que já carrega o ambiente de login.

## Fase 5 — Provar que funcionou

Não diga "deployado". Com o restart às 20:00, a prova vem em dois tempos.

**Agora**, em cada VM:

- o commit no disco (`git rev-parse --short=10 HEAD`)
- `db:migrate:status` sem nenhum `down`
- o timer ativo: `systemctl is-enabled chatwoot-restart-noturno.timer` e
  `systemctl list-timers chatwoot-restart-noturno.timer`
- o web ainda saudável no código antigo: `systemctl is-active` e o healthcheck
  (`curl .../api`)

E diga "no disco, carrega às 20:00".

**Depois das 20:00**, rode o raio-X com `--frota`: a seção 4 mostra, por VM, se o
web já serve o disco e o que o timer fez na última noite. Só então prove o
comportamento: se o PR conserta a busca, faça uma busca; se muda a tela, baixe o
entry pela URL pública e confira o 200. Com restart urgente, a prova é toda na
hora, como antes.

Ao final, alinhe a `homologacao` com a `producao` se elas divergirem, e siga para
a Fase 6. O que ficou pendente você diz ao usuário no fechamento dela.

## Fase 6: homologação e VMs dos devs

Branch alinhada não é VM alinhada. Não existe auto-pull: merge em `homologacao`
não desce para a `.232`, e nada chega sozinho nas VMs dos devs. Em 18/09 os 6 PRs
do dia entraram pela `homologacao` e mesmo assim a `.232` ficou 52 commits atrás,
parada em `feat/badge-conversas-nao-lidas`; o Thalysson ficou sem 3 PRs e o
Nicolas, 179 commits atrás. Por isso a pergunta depende de onde cada VM está, não
de onde o PR veio: **meça sempre e só pergunte pelas atrasadas.**

| VM | endereço | branch | atualizar é |
|---|---|---|---|
| HOMOLOGACAO | `192.168.8.232` | `homologacao` | mesmo commit da produção (fast-forward) |
| THALYSSON | `192.168.8.167` | `thalysson` | merge da `producao` na branch dele |
| NICOLAS | `192.168.8.98` | `nicolas` | idem |

A VM do Walisson (`.46`) fica fora, a pedido dele.

**VM de dev é onde o dev trabalha.** Ela tem commit que não está no GitHub e
arquivo em edição. Ali nunca se faz fast-forward, reset, stash nem clean:
atualizar é mergear a `producao` na branch dele. Na homologação o critério é
"mesmo commit"; na VM de dev é "contém o commit".

### 1. Medir

Depois do deploy, rode de novo o raio-X e leia a seção 5:

```bash
python3 scripts/ops/pr-raiox.py $ARGUMENTS --frota
```

Se as três contêm o commit, diga isso em uma linha e encerre.

### 2. Perguntar uma vez

Use a ferramenta de pergunta de múltipla escolha, com **só as VMs atrasadas e
desbloqueadas** como opção. Cada opção diz o que vai acontecer: ff ou merge, se
tem migration, se tem build, e quando reinicia (homologação às 20:00, pelo timer;
VM de dev na hora). Marcar a VM é o OK para reiniciar aquela VM. As bloqueadas
aparecem no texto da pergunta, com o motivo, e não como opção.

A VM está **bloqueada** quando:

- tem arquivo em edição além do `public/version.json`. É o trabalho do dev, e não
  se faz stash no lugar dele;
- o merge dá conflito: `git merge-tree --write-tree HEAD <sha>` sai com erro
  (teste depois do fetch, antes dele o commit nem está lá);
- aparece como `nao medida daqui`;
- é a homologação e o checkout está parado numa branch com commit que a
  `homologacao` não tem. Pode ser teste em andamento: pergunte antes.

### 3. Backup do que só existe no disco

Se a VM tem commit que nenhum remote tem (o raio-X avisa no veredito), faça backup
no GitHub antes de mexer, sem tocar no checkout:

```bash
# na VM
git bundle create /tmp/<vm>.bundle HEAD --not --remotes
# aqui, depois de trazer o arquivo
git fetch /tmp/<vm>.bundle HEAD
git push origin FETCH_HEAD:refs/heads/backup/<vm>-vm<ultimo-octeto>-<AAAAMMDD>
```

O merge não apaga esses commits. O backup é para o dia em que a VM morrer.

### 4. Uma VM por vez

As VMs de LAN dividem o host Proxmox com serviço de produção. Em 18/09 o swap do
host estava cheio, e build em paralelo aperta todo mundo.

### 5. Receita da homologação

```bash
cd /home/chatwoot/chatwoot
git fetch origin                     # a .232 alcança o GitHub
git checkout homologacao && git merge --ff-only origin/homologacao
RAILS_ENV=production bundle exec rake db:migrate
```

A fase 5 já alinhou a `homologacao` com a `producao`, então é o mesmo commit e os
assets são **o mesmo tgz da fase 4**: extraia por cima e gere os `.gz`. Depois,
`db:migrate:status` sem nenhum `down`, o timer instalado como na fase 4 e a prova
em dois tempos da fase 5. A homologação tem cliente (contas 3/4/5): o restart
também fica para as 20:00.

O `public/version.json` segue a regra da fase 4. Se o `merge --ff-only` recusar
porque a branch `homologacao` local tem commit só dela (aconteceu em 18/09:
`fca99fcb0a`, de 02/09), faça o backup do passo 3 e renomeie a branch com
`git branch -m`, nunca force.

### 6. Receita da VM de dev

```bash
cd /home/chatwoot/chatwoot
git checkout -- public/version.json
git fetch origin producao
git merge-tree --write-tree HEAD FETCH_HEAD >/dev/null   # erro aqui é conflito: pare e avise
git merge --no-edit FETCH_HEAD
RAILS_ENV=production bundle exec rake db:migrate
git diff --name-only ORIG_HEAD HEAD -- app/javascript    # vazio: sem build
```

Build **na VM**, só se o merge trouxe frontend, no checkout principal dela e com
heap 12288, e depois os `.gz`. O tgz da produção não serve aqui, porque o código
da VM do dev é outro. Depois, `db:migrate:status` sem nenhum `down`, restart na
hora e prova. VM de dev não é cliente e não recebe o timer.

Nunca dê push na branch do dev (publicar é decisão dele), e nunca stash, reset
nem clean.

### 7. Provar e fechar

A prova é a da fase 5, com uma diferença: na VM de dev o critério é
`git merge-base --is-ancestor <sha> HEAD` (contém), não HEAD igual.

Feche dizendo o que ficou para trás e o que o dev precisa fazer. Por exemplo:
"Nicolas: 5 arquivos em edição; quando ele commitar, rode a fase 6 de novo."

## Regras que não se negociam

- **Restart e reboot exigem OK explícito do usuário.**
- **Reiniciar é reiniciar os serviços do SPX (web e workers), nunca a VM.** Nada
  de `reboot`, `shutdown` ou stop/start: na AWS as VMs não têm Elastic IP e o IP
  público muda num stop/start (a TOZI já trocou de IP assim). O restart das 20:00
  é do timer, por decisão do dono em 18/09; fora dele, restart na hora continua
  exigindo OK.
- Antes de qualquer `merge --ff-only` numa VM, confira o HEAD **real** dela: a
  branch pode estar atrás do que roda no cliente.
- `git` rodado **dentro** da VM mente sobre divergência, porque o deploy por
  refspec não atualiza `refs/remotes/origin/*`. Compare sempre de uma cópia com
  fetch recente.
