# Comandos Rápidos - Banner de Manutenção

## Instalação Rápida

### 1. Instalar dependência
```bash
cd /home/chatwoot/chatwoot
pnpm add @lottiefiles/dotlottie-vue
```

### 2. Copiar arquivo de animação
```bash
# Se o arquivo estiver em /home/chatwoot/chatwoot
cp /home/chatwoot/chatwoot/Under\ Maintenance.lottie /home/chatwoot/chatwoot/public/assets/Under\ Maintenance.lottie

# Verificar
ls -lh /home/chatwoot/chatwoot/public/assets/Under\ Maintenance.lottie
```

### 3. Reiniciar serviços (se necessário)
```bash
# Reiniciar Rails
# Reiniciar Vite/Webpack (se estiver rodando)
```

---

## Uso no Rails Console

### Ativar Banner
```ruby
# Com mensagem e data/hora
MaintenanceBanner.enable("Sistema em manutenção programada", "2024-01-20 22:00:00")

# Apenas com mensagem
MaintenanceBanner.enable("Sistema em manutenção")
```

### Verificar Status
```ruby
MaintenanceBanner.active?
MaintenanceBanner.info
```

### Desativar Banner
```ruby
MaintenanceBanner.disable
```

---

## Verificação Pós-Instalação

1. Verificar se a classe está carregando:
```ruby
rails console
MaintenanceBanner.info
# Deve retornar: {:enabled=>false}
```

2. Testar ativação:
```ruby
MaintenanceBanner.enable("Teste")
MaintenanceBanner.active?
# Deve retornar: true
```

3. Verificar no navegador:
- Acessar o dashboard
- O banner deve aparecer com a animação e mensagem
- Verificar console do navegador para erros




