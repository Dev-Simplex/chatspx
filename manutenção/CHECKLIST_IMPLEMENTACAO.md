# ✅ Checklist de Implementação - Banner de Manutenção

Use este checklist para garantir que todas as alterações foram aplicadas corretamente.

## Pré-requisitos
- [ ] Acesso SSH à máquina de produção
- [ ] Arquivo `Under Maintenance.lottie` disponível em `/home/chatwoot/chatwoot`

## Instalação de Dependências
- [ ] Executar: `cd /home/chatwoot/chatwoot && pnpm add @lottiefiles/dotlottie-vue`

## Arquivos Novos
- [ ] Criar `lib/maintenance_banner.rb` com o conteúdo do documento principal

## Arquivos Modificados - Backend
- [ ] Modificar `lib/redis/redis_keys.rb` - Adicionar `MAINTENANCE_BANNER = 'MAINTENANCE_BANNER'.freeze`
- [ ] Modificar `app/controllers/api/v1/accounts_controller.rb` - Adicionar `@maintenance_banner = MaintenanceBanner.info`
- [ ] Modificar `app/views/api/v1/accounts/show.json.jbuilder` - Adicionar `json.maintenance_banner @maintenance_banner || { enabled: false }`

## Arquivos Modificados - Frontend
- [ ] Modificar `app/javascript/dashboard/App.vue`:
  - [ ] Adicionar `maintenanceBanner: null` no `data()`
  - [ ] Adicionar `maintenance_banner: maintenanceBanner` na desestruturação
  - [ ] Adicionar `:maintenance-banner="maintenanceBanner"` na prop do UpdateBanner
- [ ] **SUBSTITUIR COMPLETO** `app/javascript/dashboard/components/app/UpdateBanner.vue` pelo conteúdo de `UpdateBanner.vue.COMPLETO`
- [ ] Modificar `app/javascript/dashboard/i18n/locale/pt_BR/generalSettings.json`:
  - [ ] Adicionar `"MAINTENANCE_BANNER": "Sistema em manutenção"`
  - [ ] Adicionar `"MAINTENANCE_SCHEDULED": "Manutenção programada para {scheduledAt}"`

## Arquivo de Animação
- [ ] Copiar `Under Maintenance.lottie` para `public/assets/Under Maintenance.lottie`
- [ ] Verificar permissões do arquivo: `ls -lh public/assets/Under\ Maintenance.lottie`

## Testes
- [ ] Reiniciar servidor Rails (se necessário)
- [ ] Recompilar assets frontend (se necessário)
- [ ] Testar no Rails console:
  ```ruby
  MaintenanceBanner.info
  # Deve retornar: {:enabled=>false}
  ```
- [ ] Ativar banner de teste:
  ```ruby
  MaintenanceBanner.enable("Teste de manutenção")
  MaintenanceBanner.active?
  # Deve retornar: true
  ```
- [ ] Verificar no navegador:
  - [ ] Banner aparece com animação
  - [ ] Animação está ao lado do texto
  - [ ] Texto está centralizado
  - [ ] Botão de fechar funciona
- [ ] Desativar banner de teste:
  ```ruby
  MaintenanceBanner.disable
  ```

## Verificações Finais
- [ ] Banner de atualização do Chatwoot não aparece mais
- [ ] Banner de manutenção funciona corretamente quando ativado
- [ ] Animação Lottie carrega e anima corretamente
- [ ] Layout está responsivo (testar em mobile)
- [ ] Não há erros no console do navegador
- [ ] Não há erros no log do Rails

## Comandos Úteis

### Verificar se a classe está carregando
```ruby
rails console
MaintenanceBanner
# Deve mostrar a classe sem erros
```

### Verificar se o arquivo de animação está acessível
```bash
curl -I http://localhost:3000/assets/Under%20Maintenance.lottie
# Deve retornar 200 OK
```

### Limpar cache (se necessário)
```bash
# Rails
rails tmp:clear

# Assets
rm -rf public/packs
rm -rf public/vite
```

---

## ⚠️ Importante

- **NÃO** esqueça de copiar o arquivo `Under Maintenance.lottie` para `public/assets/`
- **SUBSTITUIR COMPLETO** o arquivo `UpdateBanner.vue` (não apenas editar)
- Testar em ambiente de staging antes de aplicar em produção (se possível)

