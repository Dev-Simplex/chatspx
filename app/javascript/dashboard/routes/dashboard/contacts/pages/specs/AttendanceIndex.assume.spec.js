import conversationsModule from 'dashboard/store/modules/conversations';

// Trava a armadilha que causou um BUG DE FALSO SUCESSO na aba "Em atendimento":
// o handler de "Assumir" despachava `conversations/assignAgent`, mas o módulo
// conversations NÃO é namespaced. O Vuex, diante de uma action inexistente,
// apenas loga e devolve undefined — o `await` RESOLVE, então o código exibia
// "Você agora está atendendo este contato" sem ter atribuído nada (confirmado ao
// vivo: a conversa continuava com o dono antigo).
//
// Se um dia alguém puser `namespaced: true` no módulo, este teste quebra e
// aponta para o AttendanceIndex, que precisa passar a usar o caminho namespaced.
describe('contrato do "Assumir" da aba Em atendimento', () => {
  it('conversations module is NOT namespaced — the assume handler must dispatch the ROOT action', () => {
    expect(conversationsModule.namespaced).toBeFalsy();
  });

  it('exposes assignAgent as a root action', () => {
    expect(typeof conversationsModule.actions.assignAgent).toBe('function');
  });
});
