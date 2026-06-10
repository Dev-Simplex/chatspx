# 🐙 GitHub — Fluxo de Branches, PR & Deploy (ChatSPX)

Repositório: **`Dev-Simplex/chatspx`** (privado).

## Topologia
| Branch | Papel | Máquina |
|--------|-------|---------|
| `nicolas` | dev | VM nicolas |
| `paulao` | dev | VM paulao |
| `homologacao` | staging | VM homologacao |
| `producao` | produção | VM producao |

Cada branch tem **uma máquina rodando aquele código**.

## Regra de ouro
**dev → `homologacao` (via PR, admin aprova) → `producao` (via PR, só admin).**
O dev nunca vai direto pra produção.

---

# PARTE 1 — O que o ADMIN configura no GitHub (uma vez)

### 1.1 — Dar acesso ao time
`Settings → Collaborators and teams → Add people`
- Adicione cada dev com papel **Write**.
- (Write deixa o dev **dar push na branch dele e abrir PR**; a proteção abaixo impede que ele mergeie em homologacao/producao.)

### 1.2 — Proteger a branch `producao`
`Settings → Branches → Add branch protection rule`
- **Branch name pattern:** `producao`
- ☑ **Require a pull request before merging**
  - ☑ Require approvals → **1**
  - ☑ Dismiss stale pull request approvals when new commits are pushed
- ☑ **Restrict who can push to matching branches** → adicione **só você / admins**
- ☑ **Block force pushes**
- ☑ Do not allow bypassing the above settings *(opcional, mais rígido)*
- **Save changes**

→ Resultado: ninguém faz push direto em `producao`; só entra por PR aprovado por admin.

### 1.3 — Proteger a branch `homologacao`
Repita o 1.2 com **pattern `homologacao`**:
- ☑ Require a pull request before merging → ☑ Require approvals **1**
- ☑ Block force pushes
- (Não precisa restringir push só a admins aqui — basta exigir PR + a SUA aprovação.)

→ Resultado: o dev abre PR pra `homologacao`, mas **você aprova/mergeia**.

### 1.4 — (Opcional) CODEOWNERS — forçar a sua review
Crie o arquivo **`.github/CODEOWNERS`** com:
```
* @SEU_USUARIO_GITHUB
```
E nas regras (1.2/1.3) marque ☑ **Require review from Code Owners**.
→ Todo PR passa obrigatoriamente pela sua revisão.

### 1.5 — Token de leitura pra infra (me passa ESTE)
`Settings (sua conta) → Developer settings → Personal access tokens → Fine-grained tokens → Generate new token`
- **Resource owner:** Dev-Simplex
- **Repository access:** Only select repositories → **chatspx**
- **Permissions → Repository permissions → Contents:** **Read-only**
- Generate → **copie o token** (`github_pat_…`) e me mande.

→ É o que o painel/Almirante usa pra **puxar** o código nas VMs (deploy). Read-only = seguro.
*(Se um dia quiser ligar o "promover" interno do Almirante sem PR, aí seria Contents = Read **and Write** — mas o caminho recomendado é PR.)*

---

# PARTE 2 — Passo a passo do DEV (manda pro time)

> Você trabalha na **sua branch** (`nicolas` ou `paulao`). Quando quiser levar pra homologação, abre um **Pull Request**.

### Dia a dia
```bash
git checkout SUA_BRANCH          # ex: git checkout nicolas
git pull                         # pega o que tiver de novo

# ... edita / programa ...

git add -A
git commit -m "feat: descrição da mudança"
git push origin SUA_BRANCH       # sobe sua branch pro GitHub
```

### Abrir o Pull Request (levar pra homologação)
1. No GitHub, abre o repo → vai aparecer **"Compare & pull request"** (ou `Pull requests → New`).
2. **base:** `homologacao`  ·  **compare:** `SUA_BRANCH`.
3. Escreva o título + descrição do que mudou → **Create pull request**.
4. **Aguarde a aprovação do admin.** Não tente mergear — a proteção bloqueia.
5. Aprovou e mergeou? Sua mudança está em `homologacao`. O deploy é feito pelo admin/Almirante.

> ⚠️ Dev **não** abre PR pra `producao`. No máximo `homologacao`.

---

# PARTE 3 — Promoção & deploy (ADMIN)

1. **Revisa o PR** do dev no GitHub (diff, comentários) → **Approve** → **Merge** → entra em `homologacao`.
2. **Deploy da homologação:** no painel/Claude — *"atualiza a homologação"* (pull + migrate + restart na VM homologacao).
3. **Valida** na homologação.
4. **Promover pra produção:** abra um PR **base `producao` ← compare `homologacao`** → você aprova → merge.
5. **Deploy da produção:** *"atualiza a produção"* no painel.

---

## ✅ Checklist do admin (uma vez)
- [ ] Devs adicionados como **Write** (1.1)
- [ ] Branch protection em **`producao`** (1.2)
- [ ] Branch protection em **`homologacao`** (1.3)
- [ ] *(opcional)* CODEOWNERS (1.4)
- [ ] **Token read-only gerado e enviado** pra configurar o Almirante (1.5)

## Fronteira dev × admin
| Ação | Dev | Admin |
|------|:---:|:---:|
| Push na própria branch | ✓ | ✓ |
| Abrir PR → `homologacao` | ✓ | ✓ |
| Aprovar/mergear PR | ✗ | ✓ |
| Qualquer coisa em `producao` | ✗ | ✓ |

---
*ChatSPX · Simplex Soluções — dev chega na homologação; produção é só admin.*
