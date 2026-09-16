// O bundle do @chatwoot/ninja-keys embute o Lit de desenvolvimento, que no vite dev avisa a cada
// carga sobre "dev mode" e "multiple versions". Não há o que corrigir do nosso lado sem trocar a lib;
// o próprio Lit lê `litIssuedWarnings` para não repetir avisos já conhecidos. Precisa rodar antes do
// import do ninja-keys, e só em dev (o build de produção não emite esses avisos).
if (import.meta.env.DEV) {
  window.litIssuedWarnings = window.litIssuedWarnings || new Set();
  [
    'dev-mode',
    'multiple-versions',
    'Lit is in dev mode. Not recommended for production! See https://lit.dev/msg/dev-mode for more information.',
    'Multiple versions of Lit loaded. Loading multiple versions is not recommended. See https://lit.dev/msg/multiple-versions for more information.',
  ].forEach(warning => window.litIssuedWarnings.add(warning));
}
