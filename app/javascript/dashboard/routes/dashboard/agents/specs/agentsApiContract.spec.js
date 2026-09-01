import fs from 'fs';
import path from 'path';

/**
 * Invariante das telas de Agentes IA: o front só pode ler campo que a API devolve.
 *
 * A tela lia três campos que o payload do assistant NUNCA teve
 * (`account_inbox_ids`, `active`, `config.model`). O JavaScript não reclama de
 * propriedade inexistente: entrega `undefined`, o `|| 0` vira zero, o
 * `undefined !== false` vira `true`, e a tela mostra um número falso com cara de
 * número real. Nada quebra, ninguém percebe.
 *
 * Este spec fecha essa porta comparando, por leitura de arquivo, o que os
 * componentes leem contra o que os jbuilder/strong params realmente entregam.
 * Ele quebra se alguém voltar a ler um campo inexistente.
 */

const repoRoot = process.cwd();
const read = relativePath =>
  fs.readFileSync(path.resolve(repoRoot, relativePath), 'utf-8');

const ASSISTANT_JBUILDER =
  'enterprise/app/views/api/v1/models/captain/_assistant.json.jbuilder';
const TOOLS_JBUILDER =
  'enterprise/app/views/api/v1/accounts/captain/assistants/tools.json.jbuilder';
const DOCUMENT_JBUILDER =
  'enterprise/app/views/api/v1/models/captain/_document.json.jbuilder';
const ASSISTANTS_CONTROLLER =
  'enterprise/app/controllers/api/v1/accounts/captain/assistants_controller.rb';

// Componentes que recebem um assistant/agent e leem campos dele.
const AGENT_COMPONENTS = [
  'app/javascript/dashboard/routes/dashboard/agents/pages/AgentsDashboard.vue',
  'app/javascript/dashboard/routes/dashboard/agents/pages/AgentsPageView.vue',
  'app/javascript/dashboard/routes/dashboard/agents/pages/AgentDetailView.vue',
  'app/javascript/dashboard/components-next/agents-ui/AiAgentCard.vue',
  'app/javascript/dashboard/components-next/agents/tabs/OverviewTab.vue',
  'app/javascript/dashboard/components-next/agents/tabs/SettingsTab.vue',
  'app/javascript/dashboard/components-next/agents/tabs/FlowTab.vue',
  'app/javascript/dashboard/components-next/agents/tabs/InboxesTab.vue',
  'app/javascript/dashboard/components-next/agents/tabs/KnowledgeTab.vue',
  'app/javascript/dashboard/components-next/agents/tabs/LogsTab.vue',
  'app/javascript/dashboard/components-next/agents/tabs/ScenariosTab.vue',
  'app/javascript/dashboard/components-next/agents/behavior/BehaviorTab.vue',
  'app/javascript/dashboard/components-next/agents/workflow/AgentFlowSimple.vue',
  'app/javascript/dashboard/components-next/agents/workflow/AgentFlowGraph.vue',
];

/**
 * Remove comentários (JS de linha e bloco, e HTML) para não confundir a
 * documentação de um bug corrigido com uma leitura real do campo.
 */
const stripComments = source =>
  source
    .replace(/<!--[\s\S]*?-->/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:'"`\\])\/\/[^\n]*/g, '$1');

/** Chaves que o jbuilder devolve: linhas `json.<chave>`. */
const jbuilderKeys = relativePath => {
  const source = read(relativePath);
  const keys = new Set();
  const re = /^\s*json\.([a-z_][a-zA-Z0-9_]*)/gm;
  let match = re.exec(source);
  while (match) {
    keys.add(match[1]);
    match = re.exec(source);
  }
  return keys;
};

/**
 * Campos lidos de `agent`/`assistant` em um componente, com a linha de origem.
 * Cobre `agent.x`, `agent?.x`, `props.agent.x` e `agent.value.x`.
 */
const agentFieldReads = relativePath => {
  const lines = stripComments(read(relativePath)).split('\n');
  const re =
    /(?:props\.)?\b(?:agent|assistant)\??\.(?:value\??\.)?([a-z_][a-zA-Z0-9_]*)/g;
  const reads = [];
  lines.forEach((line, index) => {
    let match = re.exec(line);
    while (match) {
      // `agent.value` é o unwrap de um ref do Vue, não um campo da API.
      if (match[1] !== 'value') {
        reads.push({ field: match[1], line: index + 1 });
      }
      match = re.exec(line);
    }
  });
  return reads;
};

describe('Agentes IA — contrato de campos com a API', () => {
  it('lê do jbuilder as chaves que a API do assistant realmente devolve', () => {
    // Guarda do próprio guarda: se o jbuilder mudar de forma e a extração vier
    // vazia, o teste abaixo passaria vazio e não protegeria nada.
    const keys = jbuilderKeys(ASSISTANT_JBUILDER);
    expect(keys.size).toBeGreaterThan(5);
    expect(keys).toContain('inbox_ids');
    expect(keys).toContain('config');
  });

  it('não lê nenhum campo de agent/assistant que a API não devolva', () => {
    const apiKeys = jbuilderKeys(ASSISTANT_JBUILDER);
    const offenders = [];

    AGENT_COMPONENTS.forEach(file => {
      agentFieldReads(file).forEach(({ field, line }) => {
        if (!apiKeys.has(field)) {
          offenders.push(`${file}:${line} lê \`${field}\``);
        }
      });
    });

    expect(offenders).toEqual([]);
  });

  it('não ressuscita os três campos fantasma já corrigidos', () => {
    // Regressões concretas, nomeadas: caixas sempre 0, modelo sempre vazio,
    // status sempre "Ativo".
    const banned = ['account_inbox_ids', 'llm_model'];
    const offenders = [];

    AGENT_COMPONENTS.forEach(file => {
      const source = stripComments(read(file));
      banned.forEach(field => {
        if (source.includes(field)) offenders.push(`${file}: \`${field}\``);
      });
      // `active` só é proibido como campo do agente: não existe coluna
      // active/enabled/status em captain_assistants nem método no modelo.
      // `isActiveTab`, `connectionActive` e afins seguem livres.
      if (
        /(?:props\.)?\b(?:agent|assistant)\??\.(?:value\??\.)?active\b/.test(
          source
        )
      ) {
        offenders.push(`${file}: \`agent.active\``);
      }
    });

    expect(offenders).toEqual([]);
  });

  it('não lê config.model: o modelo é da conta, não do agente', () => {
    // O permit do config é a lista fechada do que a tela pode gravar/ler em
    // `config`. `model` e `llm_model` nunca estiveram lá, e o modelo de verdade
    // sai de Agentable#agent_model -> account.captain_assistant_model.
    const permit = read(ASSISTANTS_CONTROLLER);
    expect(permit).not.toMatch(/config:\s*\[[^\]]*[^_a-z]model\b/s);

    const offenders = [];
    AGENT_COMPONENTS.forEach(file => {
      const source = stripComments(read(file));
      if (/config\??\.(?:value\??\.)?(?:model|llm_model)\b/.test(source)) {
        offenders.push(file);
      }
      if (/\bcfg\??\.(?:model|llm_model)\b/.test(source)) offenders.push(file);
    });

    expect(offenders).toEqual([]);
  });

  it('lê o tipo do documento dos campos que o jbuilder entrega', () => {
    const documentKeys = jbuilderKeys(DOCUMENT_JBUILDER);
    expect(documentKeys).toContain('content_type');
    expect(documentKeys).not.toContain('document_type');

    const knowledge = stripComments(
      read(
        'app/javascript/dashboard/components-next/agents/tabs/KnowledgeTab.vue'
      )
    );
    expect(knowledge).not.toMatch(/\bdoc\??\.document_type\b/);
    expect(knowledge).toMatch(/\bdoc\??\.content_type\b/);
  });

  it('serializa `custom` em /tools, senão a tela duplica cada tool personalizada', () => {
    // A tela filtra o catálogo de sistema com `!tool.custom`. A flag existe em
    // Captain::CustomTool#to_tool_metadata; se o jbuilder não a devolver, o filtro
    // não exclui nada e toda tool personalizada aparece duas vezes.
    expect(read(TOOLS_JBUILDER)).toMatch(/json\.custom\b/);

    const toolsView = stripComments(
      read(
        'app/javascript/dashboard/routes/dashboard/agents/pages/ToolsView.vue'
      )
    );
    expect(toolsView).toMatch(/\.custom\b/);
  });

  it('trata created_at dos logs como epoch em segundos', () => {
    // O jbuilder serializa com `.to_i` (segundos). `new Date(segundos)` interpreta
    // milissegundos e data todo log em janeiro de 1970.
    expect(
      read(
        'enterprise/app/views/api/v1/accounts/captain/assistant_logs/index.json.jbuilder'
      )
    ).toMatch(/json\.created_at\s+log\.created_at\.to_i/);

    const logsTab = stripComments(
      read('app/javascript/dashboard/components-next/agents/tabs/LogsTab.vue')
    );
    // O bug era formatar o epoch cru; a conversão para milissegundos é o que precisa existir.
    expect(logsTab).not.toMatch(/return new Date\(ts\)\.toLocaleString/);
    expect(logsTab).toMatch(/ts \* 1000/);
  });
});
