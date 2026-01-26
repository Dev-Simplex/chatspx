# Conexões WhatsApp - Gerenciamento de Conexões - Nova Funcionalidade

O CHAT - SPX agora oferece a funcionalidade de gerenciamento de Conexões WhatsApp, permitindo que você conecte e gerencie múltiplas contas WhatsApp para atendimento. Esta ferramenta é essencial para empresas que precisam atender clientes através do WhatsApp de forma profissional e organizada, com a capacidade de gerenciar várias conexões simultaneamente.

## Como Funciona

### Acesso às Conexões

A funcionalidade de Conexões WhatsApp está disponível nas configurações do sistema:

1. **Navegue até Configurações**: Acesse o menu lateral e clique em **Configurações**
2. **Selecione "Conexões WhatsApp"**: Clique na opção "Conexões WhatsApp" no menu de configurações
3. **Visualize o Dashboard**: A página carrega automaticamente mostrando todas as suas conexões

### Interface do Gerenciador

O gerenciador apresenta uma interface moderna e intuitiva com os seguintes elementos:

• **Cabeçalho Centralizado**: Título "Conexões WhatsApp" com descrição e logo do WhatsApp

• **Botão Principal**: Botão grande e destacado para "Adicionar Nova Conexão"

• **Indicadores de Status**: Mostra atualização automática e última atualização

• **Grid de Cards**: Cada conexão é exibida em um card individual com todas as informações

## Exemplo Visual

Abaixo você pode ver como o gerenciador aparece na interface:

![Gerenciador de Conexões WhatsApp - Visão Geral](conexoes-visao-geral.png)

*Visão geral do gerenciador mostrando todas as conexões WhatsApp*

![Modal de Adicionar Conexão](modal-adicionar-conexao.png)

*Modal para adicionar uma nova conexão WhatsApp*

![Modal de QR Code](modal-qr-code.png)

*Modal exibindo o QR Code para escanear com WhatsApp*

## Funcionalidades Principais

### Criar Nova Conexão

Para criar uma nova conexão WhatsApp:

**Passo 1: Adicionar Conexão** ➕
- Clique no botão "Adicionar Nova Conexão"
- Um modal será aberto solicitando o nome da conexão

**Passo 2: Definir Nome** 📝
- Digite um nome descritivo para a conexão (ex: "Atendimento Principal", "Vendas", "Suporte")
- O nome será usado para identificar a conexão no sistema
- Uma caixa de entrada será criada automaticamente e vinculada à conexão

**Passo 3: Escanear QR Code** 📱
- Após criar, um QR Code será exibido automaticamente
- Escaneie o QR Code com seu WhatsApp para conectar
- A conexão será estabelecida automaticamente após o escaneamento

### Status das Conexões

Cada conexão pode estar em diferentes estados:

**🟢 Conectado (WORKING)**
- Conexão ativa e funcionando
- WhatsApp vinculado e pronto para receber/enviar mensagens
- Indicador verde visível no card

**🟡 Escanear QR Code (SCAN_QR_CODE)**
- Conexão criada, aguardando escaneamento do QR Code
- QR Code disponível para escanear
- Botão "QR Code" disponível para visualizar

**🔴 Falhou (FAILED)**
- Conexão falhou ao estabelecer
- QR Code pode ter expirado
- Botão "Reiniciar" disponível para tentar novamente

**⚪ Desconectado (STOPPED)**
- Conexão foi desconectada manualmente
- Não está ativa no momento
- Botões "Conectar" e "QR Code" disponíveis

**🔄 Iniciando (STARTING)**
- Conexão está sendo iniciada
- Processo de conexão em andamento
- Indicador de carregamento visível

### Informações do Card

Cada card de conexão exibe:

**Informações Básicas** 📋
- **Nome da Conexão**: Nome definido ao criar
- **Status**: Badge colorido indicando o estado atual
- **Logo WhatsApp**: Ícone do WhatsApp com indicador de status

**Detalhes da Conexão** 📞
- **Número de Telefone**: Número do WhatsApp conectado (quando conectado)
- **Caixa de Entrada**: Nome da caixa de entrada vinculada
- **Data de Criação**: Quando a conexão foi criada

**Ações Disponíveis** ⚙️
- Botões de ação variam conforme o status:
  - **QR Code**: Ver/gerar QR Code para escanear
  - **Conectar**: Iniciar conexão desconectada
  - **Desconectar**: Desconectar conexão ativa
  - **Reiniciar**: Reiniciar conexão que falhou
  - **Excluir**: Remover conexão permanentemente

### Gerenciamento de QR Code

O sistema oferece um modal completo para gerenciar o QR Code:

**Visualização do QR Code** 📱
- QR Code grande e claro para fácil escaneamento
- Atualização automática do QR Code quando necessário
- Timer mostrando tempo decorrido desde a geração

**Instruções Passo a Passo** 📖
- Instruções claras de como escanear:
  1. Abrir WhatsApp no celular
  2. Acessar Menu ou Configurações
  3. Ir em "Aparelhos conectados" → "Conectar um aparelho"
  4. Escanear o QR Code na tela

**Monitoramento Automático** 🔄
- Sistema verifica automaticamente se o QR Code foi escaneado
- Atualização a cada 3 segundos
- Notificação automática quando conectado

**Estados do QR Code** ⚡
- **Aguardando**: QR Code ativo, aguardando escaneamento
- **Conectado**: Conexão estabelecida com sucesso
- **Expirado**: QR Code expirou, precisa reiniciar
- **Erro**: Erro ao carregar QR Code, opção de tentar novamente

### Ações Disponíveis

**Conectar** 🔌
- Inicia uma conexão que está desconectada
- Gera novo QR Code automaticamente
- Abre modal de QR Code para escanear

**Desconectar** 🔌
- Desconecta uma conexão ativa
- Útil para manutenção ou pausa temporária
- Conexão pode ser reconectada depois

**Reiniciar** 🔄
- Reinicia uma conexão que falhou
- Gera novo QR Code
- Útil quando QR Code expirou ou conexão falhou

**Excluir** 🗑️
- Remove permanentemente uma conexão
- **Atenção**: A caixa de entrada associada também será excluída
- Confirmação obrigatória antes de excluir

**Ver QR Code** 📱
- Visualiza o QR Code de uma conexão existente
- Útil para reconectar ou escanear novamente
- Atualiza automaticamente se necessário

### Atualização Automática

O sistema mantém os dados atualizados automaticamente:

**Polling Automático** ⚡
- Atualiza status das conexões a cada 5 segundos
- Não requer ação manual do usuário
- Mantém informações sempre atualizadas

**Indicador Visual** 🟢
- Ponto verde pulsante indicando atualização ativa
- Mostra horário da última atualização
- Botão manual de atualização disponível

**Sincronização em Tempo Real** 🔄
- Mudanças de status são refletidas imediatamente
- Cards atualizam automaticamente
- Status badges mudam de cor conforme estado

## Como Usar

### Passo a Passo: Criar e Conectar uma Nova Conexão

1. **Acesse o Gerenciador**
   - Navegue até **Configurações** → **Conexões WhatsApp**
   - Aguarde o carregamento das conexões existentes

2. **Crie uma Nova Conexão**
   - Clique no botão "Adicionar Nova Conexão"
   - Digite um nome descritivo (ex: "Atendimento Principal")
   - Clique em "Criar Conexão"

3. **Escanee o QR Code**
   - O modal de QR Code abrirá automaticamente
   - Abra o WhatsApp no seu celular
   - Vá em Menu → Configurações → Aparelhos conectados → Conectar um aparelho
   - Escaneie o QR Code exibido na tela

4. **Aguarde a Conexão**
   - O sistema verificará automaticamente se você escaneou
   - Quando conectado, uma mensagem de sucesso aparecerá
   - A conexão estará pronta para uso

5. **Verifique o Status**
   - Volte à lista de conexões
   - Verifique se o status mudou para "Conectado"
   - O número de telefone deve aparecer no card

### Gerenciar Conexões Existentes

**Reconectar uma Conexão Desconectada**
1. Localize a conexão com status "Desconectado"
2. Clique em "Conectar"
3. Escaneie o QR Code exibido
4. Aguarde a conexão ser estabelecida

**Reiniciar uma Conexão que Falhou**
1. Localize a conexão com status "Falhou"
2. Clique em "Reiniciar"
3. Um novo QR Code será gerado
4. Escaneie o novo QR Code

**Desconectar uma Conexão Ativa**
1. Localize a conexão com status "Conectado"
2. Clique em "Desconectar"
3. Confirme a ação
4. A conexão será desconectada

**Excluir uma Conexão**
1. Localize a conexão que deseja excluir
2. Clique no botão de excluir (ícone de lixeira)
3. Confirme a exclusão
4. **Atenção**: A caixa de entrada associada também será excluída

### Dicas de Uso

🎯 **Nomes Descritivos**: Use nomes claros para identificar facilmente cada conexão (ex: "Vendas", "Suporte Técnico", "Atendimento Geral")

📱 **Múltiplas Conexões**: Você pode criar várias conexões para diferentes departamentos ou finalidades

🔄 **Manutenção Preventiva**: Desconecte e reconecte conexões periodicamente para manter estabilidade

⚡ **Monitoramento**: Use a atualização automática para monitorar o status de todas as conexões

🔒 **Segurança**: Mantenha o QR Code privado e não compartilhe com pessoas não autorizadas

## Casos de Uso

### Para Empresas com Múltiplos Departamentos

**Organização por Departamento** 🏢
- Crie uma conexão para cada departamento
- Exemplos: "Vendas", "Suporte", "Financeiro", "RH"
- Facilita organização e roteamento de mensagens

**Atendimento Especializado** 👥
- Diferentes equipes podem usar diferentes conexões
- Cada equipe gerencia sua própria conexão
- Melhor organização e responsabilização

### Para Empresas com Múltiplos Números

**Múltiplos Números WhatsApp** 📞
- Conecte vários números WhatsApp à mesma conta
- Útil para empresas com múltiplas linhas
- Centralize o atendimento em uma plataforma

**Backup e Redundância** 🔄
- Mantenha conexões de backup
- Se uma falhar, outra pode assumir
- Maior disponibilidade do serviço

### Para Gestão e Monitoramento

**Visão Centralizada** 👁️
- Veja todas as conexões em um só lugar
- Status de cada conexão claramente visível
- Fácil identificação de problemas

**Manutenção Rápida** 🔧
- Reconecte conexões com um clique
- Reinicie conexões que falharam facilmente
- Gerenciamento simplificado

## Características Técnicas

### Performance

• **Atualização Automática**: Status atualizado a cada 5 segundos

• **Carregamento Rápido**: Interface otimizada para carregamento rápido

• **Polling Eficiente**: Sistema de polling otimizado para não sobrecarregar o servidor

• **Cache Inteligente**: Dados cacheados para melhor performance

### Segurança

• **QR Code Temporário**: QR Codes expiram após um tempo para segurança

• **Confirmação de Exclusão**: Exclusão de conexões requer confirmação

• **Validação de Dados**: Validação de nomes e dados antes de criar conexões

• **Isolamento de Sessões**: Cada conexão é isolada e segura

### Integração

• **Integração WAHA**: Utiliza WhatsApp HTTP API (WAHA) para conexões

• **Criação Automática de Inbox**: Caixa de entrada criada automaticamente

• **Vinculação Automática**: Conexão vinculada automaticamente à inbox

• **Sincronização**: Status sincronizado com o servidor WAHA

## Benefícios

### Eficiência Operacional

• ⚡ **Gerenciamento Centralizado**: Todas as conexões em um só lugar

• 🔄 **Atualização Automática**: Status sempre atualizado sem intervenção manual

• 📱 **Conexão Rápida**: Processo simples de criar e conectar

• 🎯 **Múltiplas Conexões**: Suporte para várias conexões simultâneas

### Facilidade de Uso

• 🎨 **Interface Intuitiva**: Design limpo e fácil de usar

• 📖 **Instruções Claras**: Passo a passo claro para escanear QR Code

• 🔔 **Feedback Visual**: Status claramente indicado com cores e ícones

• ⚡ **Ações Rápidas**: Botões de ação diretos e acessíveis

### Organização

• 🏷️ **Nomes Personalizados**: Identifique facilmente cada conexão

• 📊 **Visão Geral**: Veja todas as conexões e seus status de uma vez

• 🔍 **Informações Completas**: Todos os detalhes importantes em cada card

• 📅 **Histórico**: Data de criação visível para referência

## Compatibilidade

Esta funcionalidade está disponível em:

✅ Navegadores desktop (Chrome, Firefox, Safari, Edge)

✅ Navegadores móveis modernos (iOS Safari, Chrome Mobile)

✅ Tablets (iPad, Android tablets)

✅ Diferentes resoluções de tela

⚠️ **Nota**: Para escanear o QR Code, você precisará de um dispositivo móvel com WhatsApp instalado. O QR Code deve ser escaneado do celular, não da mesma tela onde está sendo exibido.

## Limitações Conhecidas

• **QR Code Expira**: QR Codes têm tempo de expiração e precisam ser renovados

• **Uma Conexão por Vez**: Cada número WhatsApp pode ter apenas uma conexão ativa por vez

• **Dependência WAHA**: Requer servidor WAHA configurado e funcionando

• **Exclusão de Inbox**: Excluir conexão também exclui a caixa de entrada associada

## Solução de Problemas

### QR Code não aparece

**Possíveis causas:**
- Erro ao criar conexão
- Servidor WAHA não está respondendo
- Problema de conexão com a internet

**Soluções:**
- Verifique se o servidor WAHA está funcionando
- Tente criar a conexão novamente
- Verifique sua conexão com a internet
- Entre em contato com o suporte técnico

### QR Code expira muito rápido

**Possíveis causas:**
- Tempo padrão de expiração do WhatsApp
- Demora para escanear

**Soluções:**
- Escaneie o QR Code o mais rápido possível após gerar
- Use o botão "Reiniciar" para gerar um novo QR Code
- Certifique-se de que o celular está próximo e com boa iluminação

### Conexão não conecta após escanear

**Possíveis causas:**
- QR Code já foi usado
- Problema com o servidor WAHA
- WhatsApp não está atualizado

**Soluções:**
- Aguarde alguns segundos, o sistema verifica automaticamente
- Tente reiniciar a conexão
- Verifique se o WhatsApp está atualizado
- Entre em contato com o suporte se o problema persistir

### Status não atualiza

**Possíveis causas:**
- Polling automático parou
- Problema de conexão
- Servidor WAHA não responde

**Soluções:**
- Clique no botão "Atualizar" manualmente
- Recarregue a página
- Verifique sua conexão com a internet
- Verifique se o servidor WAHA está funcionando

### Não consigo excluir conexão

**Possíveis causas:**
- Conexão está em uso
- Permissões insuficientes
- Erro no servidor

**Soluções:**
- Desconecte a conexão antes de excluir
- Verifique suas permissões de administrador
- Tente novamente após alguns segundos
- Entre em contato com o suporte se necessário

## Suporte

Se você tiver dúvidas sobre esta funcionalidade ou encontrar algum problema:

• Entre em contato com nossa equipe de suporte através da Central de Ajuda

• Abra um ticket de suporte descrevendo o problema encontrado

• Consulte outros artigos da Central de Ajuda para mais informações sobre configurações e funcionalidades relacionadas

---

**Última atualização**: [Data da publicação]

**Versão**: 1.0

