// Reexportação, não cópia. A implementação mora em `shared/helpers/brMasks.js`
// porque a tela (dashboard) e o formulário do visitante (widget) precisam
// aplicar EXATAMENTE a mesma regra — duas cópias divergem no primeiro conserto
// feito de um lado só. Este arquivo existe para o caminho de import que o plano
// nomeia (`helper/brMasks.js`).
export * from 'shared/helpers/brMasks';
