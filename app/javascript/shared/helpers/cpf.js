// CPF: onze dígitos, os dois últimos calculados a partir dos nove primeiros.
//
// Fica em `shared` porque três telas precisam da mesma verdade: o modal de encerrar
// conversa, o painel de atributos e o cadastro do atributo.

export const apenasDigitos = valor => String(valor ?? '').replace(/\D/g, '');

// Máscara progressiva: formata enquanto se digita, sem esperar os onze dígitos.
export const formatarCpf = valor => {
  const digitos = apenasDigitos(valor).slice(0, 11);
  if (digitos.length <= 3) return digitos;
  if (digitos.length <= 6) return `${digitos.slice(0, 3)}.${digitos.slice(3)}`;
  if (digitos.length <= 9)
    return `${digitos.slice(0, 3)}.${digitos.slice(3, 6)}.${digitos.slice(6)}`;
  return `${digitos.slice(0, 3)}.${digitos.slice(3, 6)}.${digitos.slice(6, 9)}-${digitos.slice(9)}`;
};

const digitoVerificador = (digitos, pesoInicial) => {
  const soma = digitos
    .split('')
    .slice(0, pesoInicial - 1)
    .reduce(
      (total, digito, indice) =>
        total + Number(digito) * (pesoInicial - indice),
      0
    );
  const resto = (soma * 10) % 11;
  return resto === 10 ? 0 : resto;
};

// Recusa os onze dígitos repetidos (111.111.111-11 passa na conta, mas não é CPF).
export const cpfValido = valor => {
  const digitos = apenasDigitos(valor);
  if (digitos.length !== 11) return false;
  if (/^(\d)\1{10}$/.test(digitos)) return false;

  return (
    digitoVerificador(digitos, 10) === Number(digitos[9]) &&
    digitoVerificador(digitos, 11) === Number(digitos[10])
  );
};

export const CPF_PLACEHOLDER = '000.000.000-00';
