import { computed } from 'vue';

/**
 * Detecta se uma stage Kanban é uma das automations default ('open' / 'resolved').
 * Usado para evitar exclusão/renomeação acidental de stages do sistema.
 *
 * Mantém compatibilidade com a detecção por nome legacy (Abertos / Resolvidos / Em Andamento)
 * que existia nos forms antigos antes do rename Funnel→Kanban.
 */
export function isDefaultStage(stage) {
  if (!stage) return false;

  const automationType = stage.automation_type ?? stage.automationType ?? null;
  if (automationType === 'open' || automationType === 'resolved') return true;

  const name = stage.name;
  return name === 'Abertos' || name === 'Resolvidos' || name === 'Em Andamento';
}

export function useKanbanStage(stageRef) {
  return {
    isDefault: computed(() =>
      isDefaultStage(stageRef?.value !== undefined ? stageRef.value : stageRef)
    ),
  };
}
