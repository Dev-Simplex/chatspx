# ⚓ Almirante — Governança de Promoção & Deploy

**Princípio:** o dev chega no **máximo em homologação**. **Produção é exclusiva de admin.** Isso é travado em **3 camadas** — não depende de confiança.

---

## Branches (1 por ambiente)

| Tipo | Branch / VM |
|------|-------------|
| Dev | `paulao`, `nicolas` (cada dev na sua VM/branch) |
| Staging | `homologacao` |
| Produção | `producao` (+ branches por cliente da frota) |

---

## Dois caminhos de promoção (coexistem)

### 1. Pull Request — caminho NORMAL do dev (recomendado)
```
dev: git push origin <branch>  →  abre PR (base: homologacao)  →  ADMIN revisa + aprova + merge  →  Almirante deploya
```
- Review de verdade: diff, comentários linha a linha, CI.
- O control precisa só de **leitura** do GitHub.
- É como o dev promove. **Padrão pra tudo que vem de dev.**

### 2. Merge interno do Almirante — ATALHO do admin (gated)
```
"promove X pra Y" no Almirante  →  gate (admin aprova, anti-self-review)  →  control mergeia + push
```
- Rápido, **sem review** — usar consciente.
- **Só admin** dispara (dev é `operator`: propõe, não aprova).
- Precisa de credencial de **escrita** no control.
- Fluxos liberados: `paulao→homologacao`, `nicolas→homologacao`, `homologacao→producao`, `paulao→producao` *(atalho admin-only, sem review)*.

> ⚠️ Branch protection forte no `producao` **bloqueia** o push do merge interno. Pra produção, o **PR é o caminho recomendado**; o merge interno fica como atalho admin onde a proteção é leve.

---

## Quem aprova o quê

| Promoção | Quem aprova |
|----------|-------------|
| Código → `homologacao` | Admin (via PR ou merge gated) |
| Código → `producao` | **SÓ admin.** Dev nunca. |
| Deploy (pull pra VM) | Admin no Almirante (anti-self-review); staging pode ser automático |

---

## 3 camadas de enforcement (defesa em profundidade)

1. **GitHub — branch protection** em `producao` (e `homologacao`): exige PR + aprovação de admin/code-owner, restringe quem dá push/merge. Dev abre PR mas **não mergeia** em produção.
2. **Almirante — gate de deploy/merge**: ação = `role admin` + anti-self-review; `producao` é `critical`, sem auto-approve.
3. **Tokens**: dev = **`operator`** (propõe, não aprova) ou `viewer`. Admin = você. **Nunca** dev = `admin`.

---

## Fluxo padrão (ponta a ponta)

```
1. dev push branch  →  PR base homologacao        (VOCÊ aprova/mergeia)
2. Almirante: deploy homologacao (pull + migrate + restart)
3. valida na homolog
4. PR homologacao → producao                      (SÓ VOCÊ abre/aprova)
5. Almirante: deploy producao
```

O dev nunca abre nem aprova PR pra `producao` — esse passo é do admin, sempre.

---

## Fronteira dev × admin (resumo)

| Ação | Dev (operator) | Admin |
|------|:---:|:---:|
| Push da própria branch | ✓ | ✓ |
| Abrir PR → `homologacao` | ✓ | ✓ |
| Mergear PR em `homologacao` | ✗ | ✓ |
| Qualquer coisa em `producao` | ✗ | ✓ |
| Propor deploy no Almirante | ✓ | ✓ |
| **Aprovar** deploy/merge no Almirante | ✗ | ✓ |

---
*Almirante · Simplex Soluções — dev chega na homologação; produção é só admin.*
