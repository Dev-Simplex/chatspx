// Mapa de ícones Lordicon usados no sidebar do ChatSPX.
// Formato: { idle, active, family? }
// - family 'system': idle=outline, active=solid (fidelidade WhatsApp)
// - family 'wired': idle e active iguais (só muda cor + stroke bold no active)

export const LORDICON = {
  // ============================================================
  // SYSTEM FAMILY (30) — outline → filled no estado ativo
  // ============================================================
  // Inbox do rail top (painel de notificações do agente)
  notifications: {
    idle: 'https://cdn.lordicon.com/ahxaipjb.json',
    active: 'https://cdn.lordicon.com/qtpaiyhf.json',
    family: 'system',
  },
  // Conversas rail + Canais sub-itens — chat clássico (balão cheio)
  chatMessage: {
    idle: 'https://cdn.lordicon.com/bpptgtfr.json',
    active: 'https://cdn.lordicon.com/wwsllqpi.json',
    family: 'system',
  },
  // Chat Interno entre agentes — pessoas (distinto do balão de Conversas)
  internalChat: {
    idle: 'https://cdn.lordicon.com/kphwxuxr.json',
    active: 'https://cdn.lordicon.com/ziflyeyv.json',
    family: 'system',
  },
  // Canais / Caixa de entrada (sub-conv + Settings Inboxes) — bandeja real
  channels: {
    idle: 'https://cdn.lordicon.com/bimokqfw.json',
    active: 'https://cdn.lordicon.com/awjeikyj.json',
    family: 'system',
  },
  kanban: {
    idle: 'https://cdn.lordicon.com/atitnoiw.json',
    active: 'https://cdn.lordicon.com/omkluzhr.json',
    family: 'system',
  },
  contacts: {
    idle: 'https://cdn.lordicon.com/vzhmhcrq.json',
    active: 'https://cdn.lordicon.com/oqanpepd.json',
    family: 'system',
  },
  companies: {
    idle: 'https://cdn.lordicon.com/qlpudrww.json',
    active: 'https://cdn.lordicon.com/mqqsmsvs.json',
    family: 'system',
  },
  reports: {
    idle: 'https://cdn.lordicon.com/lrzdmsmx.json',
    active: 'https://cdn.lordicon.com/kwnsnjyg.json',
    family: 'system',
  },
  live: {
    idle: 'https://cdn.lordicon.com/nbueqlaq.json',
    active: 'https://cdn.lordicon.com/tkdzkdji.json',
    family: 'system',
  },
  helpCenter: {
    idle: 'https://cdn.lordicon.com/biqqsrac.json',
    active: 'https://cdn.lordicon.com/etrhcwgm.json',
    family: 'system',
  },
  settings: {
    idle: 'https://cdn.lordicon.com/asyunleq.json',
    active: 'https://cdn.lordicon.com/umuwriak.json',
    family: 'system',
  },
  unattended: {
    idle: 'https://cdn.lordicon.com/okqjaags.json',
    active: 'https://cdn.lordicon.com/kiqyrejq.json',
    family: 'system',
  },
  filter: {
    idle: 'https://cdn.lordicon.com/huuuzars.json',
    active: 'https://cdn.lordicon.com/hvfxzpfu.json',
    family: 'system',
  },
  folder: {
    idle: 'https://cdn.lordicon.com/piurhpdv.json',
    active: 'https://cdn.lordicon.com/iuqrftwp.json',
    family: 'system',
  },
  team: {
    idle: 'https://cdn.lordicon.com/kphwxuxr.json',
    active: 'https://cdn.lordicon.com/ziflyeyv.json',
    family: 'system',
  },
  label: {
    idle: 'https://cdn.lordicon.com/abgykmtd.json',
    active: 'https://cdn.lordicon.com/ynhknmbh.json',
    family: 'system',
  },
  search: {
    idle: 'https://cdn.lordicon.com/xaekjsls.json',
    active: 'https://cdn.lordicon.com/vayiyuqd.json',
    family: 'system',
  },
  // Galeria global (Mídia + Documentos + Links)
  // system-outline-72-photo (idle) / system-solid-72-photo (active)
  gallery: {
    idle: 'https://cdn.lordicon.com/ltjljakp.json',
    active: 'https://cdn.lordicon.com/htbzeuqv.json',
    family: 'system',
  },
  // Tab "Mídia" da galeria — mesmo par do entry sidebar.
  galleryMedia: {
    idle: 'https://cdn.lordicon.com/ltjljakp.json',
    active: 'https://cdn.lordicon.com/htbzeuqv.json',
    family: 'system',
  },
  // Settings Account (Conta/Workspace) — prédio tipo corporate
  account: {
    idle: 'https://cdn.lordicon.com/wurouayb.json',
    active: 'https://cdn.lordicon.com/bgfqzjey.json',
    family: 'system',
  },
  // Agentes + Edit Profile — Avatar silhueta
  agent: {
    idle: 'https://cdn.lordicon.com/bushiqea.json',
    active: 'https://cdn.lordicon.com/spzqjmbt.json',
    family: 'system',
  },
  customAttrs: {
    idle: 'https://cdn.lordicon.com/lrubprlz.json',
    active: 'https://cdn.lordicon.com/zfemvkpr.json',
    family: 'system',
  },
  automation: {
    idle: 'https://cdn.lordicon.com/oxzvhhtl.json',
    active: 'https://cdn.lordicon.com/ojzziwbx.json',
    family: 'system',
  },
  macros: {
    idle: 'https://cdn.lordicon.com/ajcbrren.json',
    active: 'https://cdn.lordicon.com/yrzetxws.json',
    family: 'system',
  },
  integration: {
    idle: 'https://cdn.lordicon.com/yhrnusmx.json',
    active: 'https://cdn.lordicon.com/gcbgdlxt.json',
    family: 'system',
  },
  audit: {
    idle: 'https://cdn.lordicon.com/ibjcmcbv.json',
    active: 'https://cdn.lordicon.com/zzodbdoh.json',
    family: 'system',
  },
  customRoles: {
    idle: 'https://cdn.lordicon.com/fjsenoqa.json',
    active: 'https://cdn.lordicon.com/zhmafyut.json',
    family: 'system',
  },
  sla: {
    idle: 'https://cdn.lordicon.com/qpmdtzim.json',
    active: 'https://cdn.lordicon.com/nayeills.json',
    family: 'system',
  },
  billing: {
    idle: 'https://cdn.lordicon.com/vmztfafm.json',
    active: 'https://cdn.lordicon.com/hnzvpwtz.json',
    family: 'system',
  },
  support: {
    idle: 'https://cdn.lordicon.com/hvenareh.json',
    active: 'https://cdn.lordicon.com/gvbscsix.json',
    family: 'system',
  },
  changelog: {
    idle: 'https://cdn.lordicon.com/yraqammt.json',
    active: 'https://cdn.lordicon.com/ejurburo.json',
    family: 'system',
  },
  logout: {
    idle: 'https://cdn.lordicon.com/uzwahnzv.json',
    active: 'https://cdn.lordicon.com/tmoefgdy.json',
    family: 'system',
  },
  chevronDown: {
    idle: 'https://cdn.lordicon.com/gqfozvrp.json',
    active: 'https://cdn.lordicon.com/qwybfpea.json',
    family: 'system',
  },
  cannedResp: {
    idle: 'https://cdn.lordicon.com/znatchux.json',
    active: 'https://cdn.lordicon.com/iwnxhvce.json',
    family: 'system',
  },

  // ============================================================
  // WIRED FAMILY (7) — sem solid variante, active muda cor+stroke
  // System não tem esses conceitos
  // ============================================================
  megaphone: {
    idle: 'https://cdn.lordicon.com/jdnoclpe.json',
    active: 'https://cdn.lordicon.com/jdnoclpe.json',
    family: 'wired',
  },
  captain: {
    idle: 'https://cdn.lordicon.com/ohcvbvqh.json',
    active: 'https://cdn.lordicon.com/ohcvbvqh.json',
    family: 'wired',
  },
  bots: {
    idle: 'https://cdn.lordicon.com/jhntkrwu.json',
    active: 'https://cdn.lordicon.com/jhntkrwu.json',
    family: 'wired',
  },
  workflow: {
    idle: 'https://cdn.lordicon.com/ygqtedpk.json',
    active: 'https://cdn.lordicon.com/ygqtedpk.json',
    family: 'wired',
  },
  keyboard: {
    idle: 'https://cdn.lordicon.com/nyrkwwyh.json',
    active: 'https://cdn.lordicon.com/nyrkwwyh.json',
    family: 'wired',
  },
  theme: {
    idle: 'https://cdn.lordicon.com/cyzlkgid.json',
    active: 'https://cdn.lordicon.com/cyzlkgid.json',
    family: 'wired',
  },
  superAdmin: {
    idle: 'https://cdn.lordicon.com/qpuplinu.json',
    active: 'https://cdn.lordicon.com/qpuplinu.json',
    family: 'wired',
  },

  // WAHA mantém SVG custom (não é Lordicon)
  waha: {
    idle: 'https://cdn.lordicon.com/dnphlhar.json',
    active: 'https://cdn.lordicon.com/dnphlhar.json',
    family: 'wired',
  },
};
