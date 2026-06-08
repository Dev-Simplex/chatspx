import { computed } from 'vue';

const NODE_SPACING_X = 220;
const START_X = 50;
const START_Y = 100;

const ALWAYS_VISIBLE = ['trigger', 'llm', 'response'];

const PIPELINE_NODES = [
  {
    id: 'trigger',
    type: 'trigger',
    label: 'Message Received',
    behaviorKey: null,
  },
  { id: 'router', type: 'router', label: 'Router', behaviorKey: 'router' },
  {
    id: 'business_hours',
    type: 'business_hours',
    label: 'Business Hours',
    behaviorKey: 'business_hours',
  },
  {
    id: 'debounce',
    type: 'debounce',
    label: 'Debounce',
    behaviorKey: 'debounce_seconds',
  },
  {
    id: 'media_pipeline',
    type: 'media_pipeline',
    label: 'Media Pipeline',
    behaviorKey: 'media_pipeline',
  },
  { id: 'llm', type: 'llm', label: 'AI Agent', behaviorKey: null },
  { id: 'dedup', type: 'dedup', label: 'Dedup', behaviorKey: 'dedup' },
  {
    id: 'humanizer',
    type: 'humanizer',
    label: 'Humanizer',
    behaviorKey: 'humanizer',
  },
  {
    id: 'response',
    type: 'response',
    label: 'Send Response',
    behaviorKey: null,
  },
];

const SECONDARY_NODES = [
  {
    id: 'handoff',
    type: 'handoff',
    label: 'Handoff Agent',
    behaviorKey: null,
  },
  {
    id: 'copilot_note',
    type: 'trigger',
    label: 'Private Note',
    behaviorKey: null,
  },
  {
    id: 'copilot_trigger',
    type: 'copilot_trigger',
    label: 'Copilot Trigger',
    behaviorKey: 'copilot_trigger',
  },
  {
    id: 'copilot_response',
    type: 'response',
    label: 'Copilot Response',
    behaviorKey: null,
  },
];

const NODE_STYLES = {
  trigger: {
    bg: 'bg-blue-50 dark:bg-blue-950/30',
    border: 'border-blue-300 dark:border-blue-700',
    icon: 'message-square',
    iconBg: 'bg-blue-100 dark:bg-blue-900/40',
    iconColor: 'text-blue-600 dark:text-blue-400',
  },
  router: {
    bg: 'bg-amber-50 dark:bg-amber-950/30',
    border: 'border-amber-300 dark:border-amber-700',
    icon: 'git-branch',
    iconBg: 'bg-amber-100 dark:bg-amber-900/40',
    iconColor: 'text-amber-600 dark:text-amber-400',
  },
  business_hours: {
    bg: 'bg-purple-50 dark:bg-purple-950/30',
    border: 'border-purple-300 dark:border-purple-700',
    icon: 'clock',
    iconBg: 'bg-purple-100 dark:bg-purple-900/40',
    iconColor: 'text-purple-600 dark:text-purple-400',
  },
  debounce: {
    bg: 'bg-cyan-50 dark:bg-cyan-950/30',
    border: 'border-cyan-300 dark:border-cyan-700',
    icon: 'timer',
    iconBg: 'bg-cyan-100 dark:bg-cyan-900/40',
    iconColor: 'text-cyan-600 dark:text-cyan-400',
  },
  media_pipeline: {
    bg: 'bg-indigo-50 dark:bg-indigo-950/30',
    border: 'border-indigo-300 dark:border-indigo-700',
    icon: 'image',
    iconBg: 'bg-indigo-100 dark:bg-indigo-900/40',
    iconColor: 'text-indigo-600 dark:text-indigo-400',
  },
  llm: {
    bg: 'bg-green-50 dark:bg-green-950/30',
    border: 'border-green-300 dark:border-green-700',
    icon: 'bot',
    iconBg: 'bg-green-100 dark:bg-green-900/40',
    iconColor: 'text-green-600 dark:text-green-400',
  },
  dedup: {
    bg: 'bg-orange-50 dark:bg-orange-950/30',
    border: 'border-orange-300 dark:border-orange-700',
    icon: 'copy-slash',
    iconBg: 'bg-orange-100 dark:bg-orange-900/40',
    iconColor: 'text-orange-600 dark:text-orange-400',
  },
  humanizer: {
    bg: 'bg-pink-50 dark:bg-pink-950/30',
    border: 'border-pink-300 dark:border-pink-700',
    icon: 'pen-tool',
    iconBg: 'bg-pink-100 dark:bg-pink-900/40',
    iconColor: 'text-pink-600 dark:text-pink-400',
  },
  response: {
    bg: 'bg-emerald-50 dark:bg-emerald-950/30',
    border: 'border-emerald-300 dark:border-emerald-700',
    icon: 'send',
    iconBg: 'bg-emerald-100 dark:bg-emerald-900/40',
    iconColor: 'text-emerald-600 dark:text-emerald-400',
  },
  handoff: {
    bg: 'bg-red-50 dark:bg-red-950/30',
    border: 'border-red-300 dark:border-red-700',
    icon: 'user-check',
    iconBg: 'bg-red-100 dark:bg-red-900/40',
    iconColor: 'text-red-600 dark:text-red-400',
  },
  copilot_trigger: {
    bg: 'bg-violet-50 dark:bg-violet-950/30',
    border: 'border-violet-300 dark:border-violet-700',
    icon: 'hash',
    iconBg: 'bg-violet-100 dark:bg-violet-900/40',
    iconColor: 'text-violet-600 dark:text-violet-400',
  },
};

function isNodeEnabled(behavior, behaviorKey) {
  if (!behaviorKey) return true;
  if (!behavior) return false;

  if (behaviorKey === 'debounce_seconds') {
    return Number(behavior.debounce_seconds) > 0;
  }

  const config = behavior[behaviorKey];
  if (!config) return false;
  if (typeof config === 'object') return config.enabled !== false;
  return Boolean(config);
}

function getNodeSummary(behavior, behaviorKey) {
  if (!behavior || !behaviorKey) return '';

  if (behaviorKey === 'debounce_seconds') {
    const seconds = Number(behavior.debounce_seconds);
    return seconds > 0 ? `${seconds}s` : '';
  }

  const config = behavior[behaviorKey];
  if (!config || typeof config !== 'object') return '';

  switch (behaviorKey) {
    case 'business_hours':
      return config.timezone || '';
    case 'humanizer':
      return config.max_chars ? `${config.max_chars} chars` : '';
    case 'dedup':
      return config.ttl_seconds ? `TTL ${config.ttl_seconds}s` : '';
    case 'copilot_trigger':
      return config.hashtag || '#copilot';
    case 'router': {
      const labels = config.skip_labels || [];
      return labels.length > 0 ? `skip: ${labels.join(', ')}` : '';
    }
    default:
      return '';
  }
}

export function useWorkflowBuilder(assistant) {
  const nodes = computed(() => {
    const behavior = assistant.value?.behavior || {};
    const hasBehavior = Object.keys(behavior).length > 0;
    const result = [];

    // Main pipeline (horizontal) — only show enabled nodes + always-visible
    let xPos = START_X;
    PIPELINE_NODES.forEach(nodeDef => {
      const enabled = isNodeEnabled(behavior, nodeDef.behaviorKey);
      if (!enabled && !ALWAYS_VISIBLE.includes(nodeDef.id)) return;

      result.push({
        id: nodeDef.id,
        type: 'workflow',
        position: { x: xPos, y: START_Y },
        data: {
          label: nodeDef.label,
          nodeType: nodeDef.type,
          style: NODE_STYLES[nodeDef.type] || NODE_STYLES.trigger,
          enabled,
          summary: getNodeSummary(behavior, nodeDef.behaviorKey),
          behaviorKey: nodeDef.behaviorKey,
        },
      });
      xPos += NODE_SPACING_X;
    });

    // Handoff node (below LLM) — only if behavior is configured
    if (hasBehavior) {
      const llmNode = result.find(n => n.id === 'llm');
      if (llmNode) {
        result.push({
          id: 'handoff',
          type: 'workflow',
          position: { x: llmNode.position.x, y: START_Y + 120 },
          data: {
            label: 'Handoff Agent',
            nodeType: 'handoff',
            style: NODE_STYLES.handoff,
            enabled: true,
            summary: '',
            behaviorKey: null,
          },
        });
      }
    }

    // Secondary pipeline (copilot) — only if copilot_trigger is enabled
    const copilotEnabled = isNodeEnabled(behavior, 'copilot_trigger');
    if (copilotEnabled) {
      const copilotY = START_Y + 240;
      let copilotX = START_X;
      SECONDARY_NODES.filter(n => n.id !== 'handoff').forEach(nodeDef => {
        const enabled = isNodeEnabled(behavior, nodeDef.behaviorKey);
        result.push({
          id: nodeDef.id,
          type: 'workflow',
          position: { x: copilotX, y: copilotY },
          data: {
            label: nodeDef.label,
            nodeType: nodeDef.type,
            style: NODE_STYLES[nodeDef.type] || NODE_STYLES.trigger,
            enabled,
            summary: getNodeSummary(behavior, nodeDef.behaviorKey),
            behaviorKey: nodeDef.behaviorKey,
          },
        });
        copilotX += NODE_SPACING_X;
      });
    }

    return result;
  });

  const edges = computed(() => {
    const result = [];
    const nodeIds = new Set(nodes.value.map(n => n.id));

    // Main pipeline edges — only between visible nodes
    const visiblePipeline = PIPELINE_NODES.filter(n => nodeIds.has(n.id));
    for (let i = 0; i < visiblePipeline.length - 1; i += 1) {
      result.push({
        id: `e-${visiblePipeline[i].id}-${visiblePipeline[i + 1].id}`,
        source: visiblePipeline[i].id,
        target: visiblePipeline[i + 1].id,
        animated: true,
      });
    }

    // LLM -> Handoff
    if (nodeIds.has('llm') && nodeIds.has('handoff')) {
      result.push({
        id: 'e-llm-handoff',
        source: 'llm',
        target: 'handoff',
        animated: true,
        label: 'handoff',
        style: { stroke: '#ef4444' },
      });
    }

    // Copilot pipeline edges
    if (nodeIds.has('copilot_note') && nodeIds.has('copilot_trigger')) {
      result.push({
        id: 'e-copilot-note-trigger',
        source: 'copilot_note',
        target: 'copilot_trigger',
        animated: true,
      });
    }
    if (nodeIds.has('copilot_trigger') && nodeIds.has('copilot_response')) {
      result.push({
        id: 'e-copilot-trigger-response',
        source: 'copilot_trigger',
        target: 'copilot_response',
        animated: true,
      });
    }

    return result;
  });

  return { nodes, edges };
}
