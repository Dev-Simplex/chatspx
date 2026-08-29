/**
 * Os limites de `widget_exit`, do lado da tela (bloco 4.08).
 *
 * A autoridade é o servidor (`app/models/concerns/widget_exit_schema.rb`): é ele
 * que valida o jsonb e devolve 422. Estes valores existem para a tela poder
 * avisar ANTES — e `specs/widgetExitContract.spec.js` lê o arquivo Ruby e falha
 * se os dois lados se separarem.
 *
 * O defeito que essa checagem previne já aconteceu nesta base mais de uma vez:
 * a tela grava num formato que o schema recusa, cada trilha testa o SEU formato,
 * e ninguém roda o payload da tela contra a validação do servidor.
 */
export const EXIT_LIMITS = Object.freeze({
  whatsAppNumberMin: 8,
  whatsAppNumberMax: 15,
});

/**
 * O que vai para o banco: só dígitos.
 *
 * `wa.me` recusa qualquer outra coisa, então normalizar é o que permite ao
 * administrador colar `+55 (65) 99999-8888` — a forma como ele conhece o próprio
 * número — sem levar um 422 que não explica nada. A mesma conta que o componente
 * do widget faz ao montar a URL (`WhatsAppExit.vue`); aqui ela acontece ANTES de
 * gravar, para que o banco nunca guarde a máscara.
 */
export const whatsAppDigits = value => String(value ?? '').replace(/\D/g, '');

/**
 * `true` quando o valor gravável é aceito pelo schema do servidor.
 *
 * Vazio é VÁLIDO, e é o que permite desligar a saída apagando o campo: sem isso,
 * uma vez configurada, ela só poderia ser trocada.
 */
export const isWhatsAppNumberValid = value => {
  const digits = whatsAppDigits(value);
  if (!digits) return true;

  return (
    digits.length >= EXIT_LIMITS.whatsAppNumberMin &&
    digits.length <= EXIT_LIMITS.whatsAppNumberMax
  );
};
