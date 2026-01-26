# 📚 Documentação - Banner de Manutenção

## Arquivos de Documentação Criados

### 1. `IMPLEMENTACAO_BANNER_MANUTENCAO.md` ⭐ **PRINCIPAL**
**Use este arquivo como referência principal!**

Contém:
- Todas as alterações detalhadas
- Código completo de cada arquivo modificado
- Instruções passo a passo
- Exemplos de código antes/depois

### 2. `CHECKLIST_IMPLEMENTACAO.md` ✅
**Use este arquivo para acompanhar o progresso!**

Contém:
- Checklist completo de todas as etapas
- Verificações de teste
- Comandos úteis para debug

### 3. `COMANDOS_RAPIDOS.md` 🚀
**Use este arquivo para comandos rápidos!**

Contém:
- Comandos de instalação resumidos
- Comandos do Rails console
- Verificações pós-instalação

### 4. `UpdateBanner.vue.COMPLETO` 📄
**Use este arquivo para copiar o componente completo!**

Este é o arquivo completo do componente `UpdateBanner.vue` que deve ser copiado para:
```
app/javascript/dashboard/components/app/UpdateBanner.vue
```

---

## 🎯 Como Usar

1. **Leia primeiro:** `IMPLEMENTACAO_BANNER_MANUTENCAO.md`
2. **Siga o checklist:** `CHECKLIST_IMPLEMENTACAO.md`
3. **Use comandos rápidos:** `COMANDOS_RAPIDOS.md` quando precisar
4. **Copie o componente:** Use `UpdateBanner.vue.COMPLETO` como referência

---

## 📦 Arquivo de Animação

**IMPORTANTE:** Você precisa copiar manualmente o arquivo:
- **Origem:** `/home/chatwoot/chatwoot/Under Maintenance.lottie`
- **Destino:** `/home/chatwoot/chatwoot/public/assets/Under Maintenance.lottie`

Comando:
```bash
cp /home/chatwoot/chatwoot/Under\ Maintenance.lottie /home/chatwoot/chatwoot/public/assets/Under\ Maintenance.lottie
```

---

## ⚡ Início Rápido

1. Instalar dependência:
   ```bash
   cd /home/chatwoot/chatwoot
   pnpm add @lottiefiles/dotlottie-vue
   ```

2. Seguir `IMPLEMENTACAO_BANNER_MANUTENCAO.md` para todas as alterações

3. Copiar arquivo de animação (ver acima)

4. Testar no Rails console:
   ```ruby
   MaintenanceBanner.enable("Teste")
   ```

---

## 📝 Notas

- Todos os arquivos estão na raiz do projeto `/home/chatwoot/chatwoot/`
- O banner de atualização do Chatwoot foi **desabilitado permanentemente**
- Apenas o banner de manutenção será exibido quando ativado
- A animação Lottie fica ao lado do texto, centralizada

---

## 🆘 Problemas?

Verifique:
1. Se todas as dependências foram instaladas
2. Se o arquivo de animação foi copiado corretamente
3. Se todos os arquivos foram modificados conforme documentação
4. Logs do Rails e console do navegador para erros

