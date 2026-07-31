export const getters = {
  getTeams($state) {
    return Object.values($state.records).sort((a, b) => a.id - b.id);
  },
  getMyTeams($state, $getters) {
    return $getters.getTeams.filter(team => {
      const { is_member: isMember } = team;
      return isMember;
    });
  },
  // Supervisão é ortogonal a ser membro (D1). Estes dois getters são novos de
  // propósito: `getMyTeams` continua governando visibilidade de etiquetas e
  // respostas prontas "de-time" e NÃO pode enxergar time supervisionado.
  getSupervisedTeams($state, $getters) {
    return $getters.getTeams.filter(team => {
      const { is_supervisor: isSupervisor } = team;
      return isSupervisor;
    });
  },
  // Membro ∪ supervisionado — use onde a pergunta for "de quais times este
  // usuário pode ver as conversas?" (filtro de time, guarda de acesso).
  getVisibleTeams($state, $getters) {
    return $getters.getTeams.filter(team => {
      const { is_member: isMember, is_supervisor: isSupervisor } = team;
      return isMember || isSupervisor;
    });
  },
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getTeam: $state => id => {
    return $state.records[Number(id)] || {};
  },
};
