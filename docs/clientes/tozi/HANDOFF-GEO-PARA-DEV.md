# Handoff — camada geográfica da Tozi (pro dev conciliar)

> Trabalho pronto pra aplicar na Clara & time, MAS travado por uma **inconsistência de infra**
> que precisa ser conciliada antes. Leia o §Infra primeiro.

## 🔴 Infra a conciliar (bloqueador)
Ao verificar o alvo do apply (read-only), achei uma contradição séria:

- O `tozi-hml.sh` e os docs (STATE/AMBIENTES) apontam **"Tozi HML = `192.168.8.232`, conta 3"**.
- Mas o app da `.232` (`/home/chatwoot/chatwoot`) reporta:
  - `DB = chatwoot_dev` · `FRONTEND_URL = https://chatspx.app`
  - **contas:** 1 SimplexIA · **3 Simplex Tecnologia** · 4 Colégio Alternativo · 5 Realizare Imobiliária · 6/7 "Account 1"
  - **Total Captain agents = 1** (só um "Test Agent" na conta 1). **Nenhum** Clara/Bruna/Júlia/Marina/Rafa/Letícia.
  - conta 3 = **Simplex Tecnologia**, 0 agentes.
- Porém o painel real (`chatspx.app/accounts/3`) mostra a **Tozi com 6 agentes** (Clara, Rafa, Marina, Letícia, Bruna, Júlia).

**Conclusão:** a `.232` é uma instância **DEV velha** que ainda se diz `chatspx.app`, mas **NÃO** é o backend que serve o painel da Tozi. Aplicar config da Tozi na `.232` cairia em cima da **Simplex Tecnologia** (contaminação cross-cliente). O backend real do `chatspx.app` com a Tozi é **outro box** (provável: Proxmox VM `chatspx-paulo` #110, roteado pelo `proxy-edge-225`) — **a confirmar**.

**Ação do dev:** identificar o box/DB que serve o `chatspx.app` real (o do painel), e **corrigir o `tozi-hml.sh` + STATE/AMBIENTES** (hoje são uma armadilha de isolamento).

## ✅ O que está pronto (aplicar no box CERTO, depois de conciliar)
Método = **code-first via API** (`captain-v2-tozi-config-recipe`), ou `rails runner` no box certo.

1. **Rodar o build** no box certo: `scripts/spx/tozi/build_gazetteer_config.rb` (dry-run, lê acervo Vista + `gazetteer-sinop.json`, gera `config['gazetteer']`). Já robusto: **bbox de Sinop + mediana** no centroide.
2. **Injetar o mapa mental** (`mapa-mental-sinop.md`, 165 bairros c/ perfil, regiões do centroide) no prompt dos agentes que **buscam imóvel/orientam**: **Bruna (locação), Júlia (vendas)** + **Clara (recepção/triagem)** e **Marina (captação)**. É **dado por agente** (sem restart). Onde exatamente (config['instructions'] vs response_guidelines vs scenario.instruction) depende do modelo dos agentes nesse box — verificar read-only antes.
3. `config['gazetteer']` fica pronto pra quando existir o tool `consultar_bairro` (contrato em `consultar-bairro-contrato.md`).

## 🧹 QA pra equipe Tozi (corrigir no Vista)
5 imóveis com coord-placeholder de Goiás (`-13.9011,-50.7134`) que bagunçavam o mapa de bairro:
cód **7783** (Santa Catarina), **8364** (Jardim Curitiba), **8599** (Setor Residencial Norte),
**9598** (Residencial Paris), **9738** (Residencial Privillege). Lista: `Temp/imoveis_coord_suspeita.json`.

## Artefatos
`gazetteer-sinop.json` (225 bairros) · `mapa-mental-sinop.md` · `geocoding-reconciliacao.md` (QA) ·
`consultar-bairro-contrato.md` · `DESIGN-CAMADA-GEOGRAFICA.md` (mapa humano + índice geo da IA +
proximidade real-time + extensões de tool) · `mapa-sinop.html` / `mapa-imoveis-sinop.html` ·
`scripts/spx/tozi/build_gazetteer_config.rb` · `scripts/spx/tozi/viacep_bairros.py`.
