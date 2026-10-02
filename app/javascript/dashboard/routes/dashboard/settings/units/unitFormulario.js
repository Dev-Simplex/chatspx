// Ajudantes PUROS do formulário de unidade. Moram fora do .vue para poderem ser testados sem montar
// a tela — mesmo caminho do unitSchedule.js ao lado.

// 78550041, 78550-041 ou 78.550-041 dão no mesmo: fica só o dígito, no máximo 8, escrito como o CEP
// é escrito — ponto depois do segundo, traço depois do quinto. A busca no ViaCEP já removia tudo que
// não é dígito, então ela não muda.
export const formatarCep = valor => {
  const digitos = (valor || '').replace(/\D/g, '').slice(0, 8);
  const inicio =
    digitos.length > 2
      ? `${digitos.slice(0, 2)}.${digitos.slice(2, 5)}`
      : digitos;

  return digitos.length > 5 ? `${inicio}-${digitos.slice(5)}` : inicio;
};

// Telefone da filial: o parêntese e o traço aparecem enquanto se digita, como no CEP. Fixo fica
// (66) 3531-0000 e celular (66) 99999-9999 — quem manda é a quantidade de dígitos, não um seletor.
// Número colado com o 55 na frente perde o 55 em vez de perder os dois últimos dígitos no corte.
export const formatarTelefone = valor => {
  let digitos = (valor || '').replace(/\D/g, '');
  if (digitos.length > 11 && digitos.startsWith('55'))
    digitos = digitos.slice(2);
  digitos = digitos.slice(0, 11);

  if (digitos.length <= 2) return digitos ? `(${digitos}` : '';

  const ddd = `(${digitos.slice(0, 2)}) `;
  const resto = digitos.slice(2);
  if (resto.length <= 4) return ddd + resto;

  const corte = resto.length > 8 ? 5 : 4;
  return `${ddd}${resto.slice(0, corte)}-${resto.slice(corte)}`;
};

// Segunda a sexta costuma ser tudo igual: preenche um dia, copia, e ajusta só o que foge. Copia para
// os dias ABERTOS — fim de semana fechado continua fechado. Devolve a grade nova e QUAIS dias mudaram:
// o aviso nomeia os dias ("copiado para terça, quarta, quinta e sexta"), que é o que deixa claro, sem
// ler manual, que o fim de semana ficou de fora.
export const copiarHorarioParaDias = (slots, origem) => {
  const dias = [];
  const novos = slots.map(item => {
    if (item.day === origem.day || !item.from || !item.to) return item;

    dias.push(item.day);
    return {
      ...item,
      from: origem.from,
      to: origem.to,
      breakFrom: origem.breakFrom,
      breakTo: origem.breakTo,
      openAllDay: origem.openAllDay,
      valid: origem.valid,
    };
  });

  return { slots: novos, dias };
};

// Papel de cada caixa da unidade e se ela é canal de destino da IA (`canais` da API). O formulário
// guarda um objeto por caixa e manda só as caixas marcadas na unidade.
const CANAL_VAZIO = {
  papel: '',
  destino: false,
  principal: false,
  template_name: '',
  template_language: '',
  texto: '',
};

export const canaisDaUnidade = unidade =>
  Object.fromEntries(
    (unidade?.canais ?? []).map(({ inbox_id: id, ...canal }) => [
      id,
      { ...CANAL_VAZIO, ...canal },
    ])
  );

export const canalDaCaixa = (canais, id) => canais[id] ?? { ...CANAL_VAZIO };

// Caixa que alcança o cliente no WhatsApp: a API oficial ou uma sessão WAHA. Só ela pode ser
// destino ou o WhatsApp principal.
export const falaWhatsapp = caixa =>
  caixa?.channel_type === 'Channel::Whatsapp' ||
  (caixa?.channel_type === 'Channel::Api' && !!caixa?.waha_session_name);

// Templates que a Meta aprovou nesta caixa, um por nome e idioma.
export const templatesAprovados = caixa =>
  (caixa?.message_templates ?? [])
    .filter(modelo => String(modelo.status).toUpperCase() === 'APPROVED')
    .map(modelo => ({
      value: `${modelo.name}|${modelo.language}`,
      label: `${modelo.name} (${modelo.language})`,
    }));

// O WhatsApp principal é um só: marcar um desmarca os outros.
export const marcarPrincipal = (canais, id, ligado) =>
  Object.fromEntries(
    Object.entries(canais).map(([chave, canal]) => [
      chave,
      { ...canal, principal: ligado && String(chave) === String(id) },
    ])
  );

export const canaisParaEnvio = (canais, idsDaUnidade, caixas) =>
  idsDaUnidade.map(id => {
    const canal = canalDaCaixa(canais, id);
    const whatsapp = falaWhatsapp(caixas.find(caixa => caixa.id === id));
    return {
      inbox_id: id,
      papel: canal.papel.trim(),
      destino: whatsapp && canal.destino,
      principal: whatsapp && canal.principal,
      template_name: canal.template_name,
      template_language: canal.template_language,
      texto: canal.texto.trim(),
    };
  });
