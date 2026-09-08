# Prompt para o Claude Code do dev

Cole isto na primeira mensagem da sessão dele, dentro de `/home/chatwoot/chatwoot` na VM `192.168.8.98`.

---

Sua máquina já está preparada. Não instale nada, não peça chave, não rode
`gh auth login`: tudo isso já foi feito e conferido em 08/09/2026.

**Como está o seu ambiente**

- Checkout em `/home/chatwoot/chatwoot`, branch `nicolas`, alinhada com
  `origin/producao` mais um commit seu.
- `gh` autenticado como Dev-Simplex, com permissão de escrita (pode mergear).
- Chave das VMs em `~/.ssh/simplex.linux.pem`, modo 600, sua. Testada.
- `bash scripts/ops/setup-promover-pr.sh` fecha 10/10. Rode se quiser conferir.

**Uma coisa sua que ainda não está salva em lugar nenhum**

O commit `352f4238d1` ("o texto do interruptor não dizia o que ele muda de
fato", i18n de Unidades) existe **só no disco desta VM**. Não está em nenhuma
branch remota. Enquanto ele não virar PR, um disco perdido leva o trabalho
junto. Abra o PR quando puder.

**O que fazer quando pedirem para subir um PR**

```
/promover-pr <numero>
/promover-pr 104 103 101      # vários de uma vez viram UM lote e UM deploy
```

O comando conduz 5 fases. A fase 1 é obrigatória e não é opinião: ela mede o
que o GitHub esconde.

```bash
python3 scripts/ops/pr-raiox.py <numero> --frota
```

Três coisas que ela responde e que você **não** deve tentar responder de
cabeça:

1. **O que o merge realmente traz.** `gh pr view --json files` e `git diff
   base...head` (três pontos) medem contra a merge-base e escondem carona. Em
   02/09 o PR #77 anunciava "2 arquivos" e arrastou 95 commits para 6 VMs. A
   conta certa é `git log base..head`, com dois pontos.
2. **O que o deploy vai exigir.** Frontend pede build; migration pede
   `db:migrate`; `Gemfile.lock` deixa de ser feature e vira release de
   plataforma.
3. **Onde a frota está.** VM fora do commit da branch pode ter trabalho que só
   existe nela, e um fast-forward apagaria em silêncio.

**A frota**

| VM | endereço | observação |
|---|---|---|
| TOZI | `3.94.9.51` | cliente real, maior volume. Sem Elastic IP: o endereço já mudou num stop/start |
| CATATAU | `3.85.130.14` | comece por aqui, é a menos crítica |
| SENTINELA | `54.166.220.138` | |
| FABRICA | `3.87.182.184` | |
| AGN | `13.221.167.143` | |
| PRODUCAO | `192.168.8.229` | **você não alcança daqui** |

A `.229` não usa a chave da AWS, o acesso dela é por senha e você não tem. O
raio-X vai escrever `não medida daqui` naquela linha, e isso é de propósito:
antes ele mostrava o SEU checkout na linha PRODUCAO, ou seja, respondia sobre
a máquina errada com toda a confiança do mundo. Se precisar do número dela,
peça a quem opera a `.229`.

O ALTERNATIVO foi desativado, a máquina não existe mais. Se você viu essa VM
em algum relatório antigo como "fora do ar", não é regressão.

**Três armadilhas de shell, todas medidas em 08/09/2026**

Nenhuma delas se apresenta como erro. As três se disfarçam de outra coisa:

1. **Só a AGN alcança o GitHub.** TOZI, CATATAU, SENTINELA e FABRICA respondem
   `could not read Username` no `git fetch`. Por isso o pacote (`git bundle`) é
   a regra, não o plano B. E o `fatal:` sai em **stderr**: um `&& echo OK` te
   engana.
2. **`sudo -u chatwoot bash -c "..."` roda no diretório do `ubuntu`.** O
   sintoma é `fatal: not a git repository`, e parece permissão quando é só o
   `cd` faltando. Use `git -C /home/chatwoot/chatwoot` ou ponha o `cd` dentro
   das aspas.
3. **`source /usr/local/rvm/scripts/rvm` mata script não interativo.** Encerra
   a shell na hora, sem imprimir nada, devolvendo 1. Você vê saída vazia e acha
   que o SSH falhou. Para ter o Ruby, use `sudo -i -u chatwoot bash
   /tmp/script.sh`, que já carrega o ambiente de login.

**Regras que não se negociam**

- **Restart e reboot só com OK explícito do usuário.** Em nenhuma hipótese
  reinicie a TOZI por conta própria.
- Antes de qualquer `merge --ff-only` numa VM, confira o HEAD **real** dela.
- `git` rodado **dentro** da VM mente sobre divergência: o deploy por pacote
  não atualiza `refs/remotes/origin/*`, então sem `fetch` a VM se compara
  consigo mesma e se declara no topo estando dez commits atrás. Foi
  exatamente esse o bug que deixou a frota parada sem ninguém desconfiar.
- Merge não é deploy. Enquanto o código não está no disco da VM, o cliente
  continua com o defeito.

Comece rodando o raio-X do PR que te passarem e me diga o que encontrou antes
de mergear.
