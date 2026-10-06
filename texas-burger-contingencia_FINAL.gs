/* =====================================================================
   TEXAS BURGER — API DE CONTINGÊNCIA (fila + espelho de leitura)
   =====================================================================
   Roda em uma CONTA GOOGLE DIFERENTE da planilha principal. É propositalmente
   "burra": guarda pedidos numa fila e uma cópia do cardápio. Nenhuma regra
   de negócio fica aqui — a principal valida tudo de novo ao reconciliar.

   TRÊS CHAVES (guardadas em Propriedades do script, NUNCA no código):
     CHAVE_SERVIDOR : só a planilha principal. Lê a fila, marca sincronizado, atualiza o espelho.
     CHAVE_INTERNA  : quem fez login (Admin/Operador). Enfileira venda e lê o espelho interno.
     CHAVE_PUBLICA  : vai no HTML (é pública por natureza). Só enfileira pedido do cardápio e
                      lê o espelho público (sem custos, taxas ou clientes).

   COMO IMPLANTAR / TROCAR AS CHAVES
   1. Cole este arquivo no projeto Apps Script da contingência (substitui o anterior).
   2. Rode `setup` (cria abas Fila e Espelho; não apaga se já existirem).
   3. Rode `gerarChaves` uma vez. Ele cria as 3 chaves novas e mostra no log de execução.
   4. Chave SERVIDOR e INTERNA -> na planilha principal: Configurações do projeto -> Propriedades do
      script -> adicionar CONTINGENCIA_CHAVE_SERVIDOR e CONTINGENCIA_CHAVE_INTERNA.
      Chave PÚBLICA -> constante CONTINGENCIA_CHAVE_PUBLICA no início do script do HTML.
   5. Implante como App da Web (Executar como "Eu", acesso "Qualquer pessoa") e, se a URL mudar,
      troque CONTINGENCIA_API_URL no HTML e na planilha principal.
   Rode `gerarChaves` de novo quando quiser trocar todas (as antigas param de valer na hora).
   ===================================================================== */

const FILA_MAX_PENDENTES = 300, FILA_MAX_CHARS = 30000;
/* SEGURANÇA (Módulo 3): a chave PÚBLICA fica no HTML, então qualquer um pode usá-la. Por isso ela tem cota própria: no máximo
   FILA_MAX_PUBLICA pedidos pendentes e FILA_MAX_PUBLICA_10MIN envios a cada 10 minutos — assim spam não enche a fila e não trava a venda interna. */
const FILA_MAX_PUBLICA = 100, FILA_MAX_PUBLICA_10MIN = 30;
const PERMISSOES = {
  servidor: ['listarPendentes', 'marcarSincronizado', 'atualizarEspelho', 'getEspelho', 'getEspelhoPublico', 'getEspelhoInterno',
             'guardarBackup', 'getArmazenamento', 'listarFotos', 'guardarFoto', 'removerFotosOrfas', 'syncLote'],
  interna:  ['enfileirar', 'getEspelhoPublico', 'getEspelhoInterno'],
  publica:  ['enfileirar', 'getEspelhoPublico']
};

function ss_() {
  const props = PropertiesService.getScriptProperties();
  let id = props.getProperty('SPREADSHEET_ID');
  if (!id) {
    const ativa = SpreadsheetApp.getActiveSpreadsheet();
    if (!ativa) throw new Error('Não foi possível identificar a planilha. Abra o editor do Apps Script pela própria planilha e rode setup() uma vez.');
    id = ativa.getId();
    props.setProperty('SPREADSHEET_ID', id);
  }
  return SpreadsheetApp.openById(id);
}

function setup() {
  const ss = ss_();
  let sh = ss.getSheetByName('Fila');
  if (!sh) {
    sh = ss.insertSheet('Fila');
    sh.getRange(1, 1, 1, 7).setValues([['id', 'tipo', 'dadosJson', 'recebidoEm', 'status', 'sincronizadoEm', 'origemChave']]);
    sh.setFrozenRows(1);
  }
  let esp = ss.getSheetByName('Espelho');
  if (!esp) {
    esp = ss.insertSheet('Espelho');
    esp.getRange(1, 1, 1, 3).setValues([['chave', 'dadosJson', 'atualizadoEm']]);
    esp.setFrozenRows(1);
  }
  abaFotos_();
  return 'Abas prontas. Agora rode gerarChaves() se ainda não configurou as chaves.';
}

function gerarChaves() {
  const nova = prefixo => prefixo + '-' + Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '').slice(0, 8);
  const c = { CHAVE_SERVIDOR: nova('txbsrv'), CHAVE_INTERNA: nova('txbint'), CHAVE_PUBLICA: nova('txbpub') };
  PropertiesService.getScriptProperties().setProperties(c);
  Logger.log('CONTINGENCIA_CHAVE_SERVIDOR = ' + c.CHAVE_SERVIDOR);
  Logger.log('CONTINGENCIA_CHAVE_INTERNA  = ' + c.CHAVE_INTERNA);
  Logger.log('CONTINGENCIA_CHAVE_PUBLICA  = ' + c.CHAVE_PUBLICA + '   (esta vai no HTML)');
  return 'Chaves geradas. Copie do log de execução.';
}

/* Troca SÓ as chaves de servidor e interna (as que não ficam no HTML) e MANTÉM a pública — assim o index.html não precisa mudar.
   Use quando uma dessas chaves tiver sido exposta. Depois de rodar:
   1) copie as duas chaves novas do Registro de execução;
   2) no projeto da PLANILHA: Configurações do projeto -> Propriedades do script -> edite CONTINGENCIA_CHAVE_SERVIDOR e
      CONTINGENCIA_CHAVE_INTERNA com os valores novos (sem colocar chave no código);
   3) no projeto da planilha rode conferirChavesContingencia() e veja os três testes OK;
   4) peça para os funcionários logados clicarem em Sair e entrarem de novo (a chave interna é buscada no login).
   Faça com a fila vazia: antes de rodar, confira que não há vendas pendentes na contingência. */
function rotacionarChavesSensiveis() {
  const p = PropertiesService.getScriptProperties();
  if (!p.getProperty('CHAVE_PUBLICA')) return 'Nada feito: não há chave pública cadastrada. Rode gerarChaves() primeiro.';
  const pendentes = readFilaPendente().length;
  if (pendentes > 0) return 'Nada feito: há ' + pendentes + ' venda(s) pendente(s) na contingência. Sincronize/reconcilie antes de trocar as chaves.';
  const nova = prefixo => prefixo + '-' + Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '').slice(0, 8);
  const c = { CHAVE_SERVIDOR: nova('txbsrv'), CHAVE_INTERNA: nova('txbint') };
  p.setProperties(c);
  Logger.log('CONTINGENCIA_CHAVE_SERVIDOR = ' + c.CHAVE_SERVIDOR);
  Logger.log('CONTINGENCIA_CHAVE_INTERNA  = ' + c.CHAVE_INTERNA);
  Logger.log('CHAVE_PUBLICA mantida (o index.html não muda).');
  return 'Chaves de servidor e interna trocadas. Copie do Registro de execução e siga os passos do comentário da função.';
}

function perfilDaChave_(chave) {
  if (!chave || typeof chave !== 'string') return '';
  const p = PropertiesService.getScriptProperties();
  if (chave === p.getProperty('CHAVE_SERVIDOR')) return 'servidor';
  if (chave === p.getProperty('CHAVE_INTERNA')) return 'interna';
  if (chave === p.getProperty('CHAVE_PUBLICA')) return 'publica';
  return '';
}

function responder(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

/* Health check (abrir a URL /exec no navegador). Só números — nada de dados de pedido. */
function doGet(e) {
  try {
    const pendentes = readFilaPendente().length;
    const esp = lerEspelho_();
    return responder({ ok: true, servico: 'Texas Burger - Contingência', pendentes: pendentes, espelhoAtualizadoEm: esp._atualizadoEm || null });
  } catch (err) {
    return responder({ ok: false, message: 'Erro: ' + err.message });
  }
}

function doPost(e) {
  let body;
  try { body = JSON.parse(e.postData.contents); } catch (err) { return responder({ ok: false, message: 'Requisição inválida.' }); }
  const perfil = perfilDaChave_(body && body.chave);
  if (!perfil) return responder({ ok: false, message: 'Chave inválida.' });
  if (PERMISSOES[perfil].indexOf(body.action) === -1) return responder({ ok: false, message: 'Esta chave não tem permissão para esta ação.' });

  const lock = LockService.getScriptLock();
  try { lock.waitLock(20000); } catch (err) { return responder({ ok: false, ocupado: true, message: 'Contingência ocupada, tente de novo.' }); }
  try {
    let r;
    switch (body.action) {
      case 'enfileirar': r = enfileirar(body.id, body.tipo, body.dados, perfil); break;
      case 'listarPendentes': r = { ok: true, pendentes: readFilaPendente() }; break;
      case 'marcarSincronizado': r = marcarSincronizado(body.id); break;
      case 'atualizarEspelho': r = atualizarEspelho(body.dados); break;
      case 'getEspelho': r = { ok: true, espelho: lerEspelho_() }; break;
      case 'getEspelhoPublico': { const esp = lerEspelho_(); r = { ok: true, espelho: Object.assign({}, esp.publico || {}, { _atualizadoEm: esp._atualizadoEm }) }; break; }
      case 'getEspelhoInterno': { const esp = lerEspelho_(); r = { ok: true, espelho: Object.assign({}, esp.publico || {}, esp.interno || {}, { _atualizadoEm: esp._atualizadoEm }) }; break; }
      case 'guardarBackup': r = guardarBackup(body.nome, body.base64); break;
      case 'getArmazenamento': r = getArmazenamentoCont_(); break;
      case 'listarFotos': r = listarFotos_(); break;
      case 'guardarFoto': r = guardarFoto(body.idOrigem, body.base64); break;
      case 'removerFotosOrfas': r = removerFotosOrfas(body.ids); break;
      case 'syncLote': r = ctSyncLote_(body.itens); break;   // ETAPA 4 — espelho das tabelas do Supabase (abas SB_<tabela>)
      default: r = { ok: false, message: 'Ação desconhecida.' };
    }
    return responder(r);
  } catch (err) {
    return responder({ ok: false, message: 'Erro: ' + err.message });
  } finally {
    lock.releaseLock();
  }
}

/* Texto vindo de fora nunca entra com HTML ou fórmula. */
function limpar_(v, prof) {
  if (prof > 6) return null;
  if (typeof v === 'string') {
    let s = v.replace(/[\u0000-\u001F\u007F]+/g, ' ').replace(/[<>`]/g, '').replace(/"/g, '\u201D').replace(/'/g, '\u2019').trim().slice(0, 300);
    return /^[=+\-@]/.test(s) ? "'" + s : s;
  }
  if (Array.isArray(v)) return v.slice(0, 80).map(x => limpar_(x, prof + 1));
  if (v && typeof v === 'object') { const o = {}; Object.keys(v).slice(0, 60).forEach(k => { o[String(k).slice(0, 60)] = limpar_(v[k], prof + 1); }); return o; }
  return (typeof v === 'number' || typeof v === 'boolean') ? v : null;
}

/* Guarda o item bruto na fila. Mesmo id = não duplica. */
function enfileirar(id, tipo, dados, perfil) {
  if (perfil === 'publica') {
    const cache = CacheService.getScriptCache();
    const usados = Number(cache.get('enf_publica')) || 0;
    if (usados >= FILA_MAX_PUBLICA_10MIN) return { ok: false, message: 'Muitos pedidos em sequência. Ligue para o restaurante.' };
    cache.put('enf_publica', String(usados + 1), 600);
  }
  if (!id || typeof id !== 'string' || id.length > 80 || !/^[A-Za-z0-9_\-]+$/.test(id)) return { ok: false, message: 'Id inválido.' };
  if ((tipo || 'venda') !== 'venda') return { ok: false, message: 'Tipo não aceito.' };
  if (!dados || typeof dados !== 'object' || !Array.isArray(dados.itens) || !dados.itens.length || dados.itens.length > 60) return { ok: false, message: 'Pedido sem itens válidos.' };
  /* BLOCO 1.1: "hora original da venda" só vale se vier de aparelho logado (nunca da chave pública) e for um instante recente e coerente. */
  if (dados.timestampOriginal !== undefined) {
    const tsO = Number(dados.timestampOriginal), agoraMs = Date.now();
    if (perfil === 'publica' || !Number.isFinite(tsO) || tsO > agoraMs + 60000 || tsO < agoraMs - 24 * 3600000) delete dados.timestampOriginal;
    else dados.timestampOriginal = Math.floor(tsO);
  }
  const json = JSON.stringify(limpar_(dados, 0));
  if (json.length > FILA_MAX_CHARS) return { ok: false, message: 'Pedido grande demais.' };
  const sh = ss_().getSheetByName('Fila');
  const last = sh.getLastRow();
  if (last >= 2) {
    const linhas = sh.getRange(2, 1, last - 1, 7).getValues();
    if (linhas.some(r => r[0] === id)) return { ok: true, message: 'Já estava na fila (não duplicado).', duplicado: true };
    const pendentes = linhas.filter(r => r[0] && r[4] === 'Pendente');
    if (pendentes.length >= FILA_MAX_PENDENTES) return { ok: false, message: 'Fila cheia. Ligue para o restaurante.' };
    if (perfil === 'publica' && pendentes.filter(r => r[6] === 'publica').length >= FILA_MAX_PUBLICA) return { ok: false, message: 'Fila de pedidos online cheia. Ligue para o restaurante.' };
  }
  sh.appendRow([id, 'venda', json, new Date(), 'Pendente', '', perfil || '']);
  return { ok: true, message: 'Guardado na fila de contingência.' };
}

function readFilaPendente() {
  const sh = ss_().getSheetByName('Fila');
  const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 6).getValues()
    .filter(r => r[0] && r[4] === 'Pendente')
    .map(r => { let d = {}, corrompido = false; try { d = JSON.parse(r[2] || '{}'); } catch (e) { corrompido = true; } return { id: r[0], tipo: r[1], dados: d, corrompido: corrompido, recebidoEm: r[3] }; });
}

/* Depois de reaplicar na principal, marca como sincronizado (não reaplica). */
function marcarSincronizado(id) {
  const sh = ss_().getSheetByName('Fila');
  const last = sh.getLastRow();
  if (last < 2) return { ok: false, message: 'Id não encontrado na fila.' };
  const ids = sh.getRange(2, 1, last - 1, 1).getValues();
  for (let i = 0; i < ids.length; i++) {
    if (ids[i][0] === id) {
      sh.getRange(i + 2, 5, 1, 2).setValues([['Sincronizado', new Date()]]);
      return { ok: true };
    }
  }
  return { ok: false, message: 'Id não encontrado na fila.' };
}

/* Espelho: uma linha por chave ('publico', 'interno'). Leitura e escrita em bloco. */
function atualizarEspelho(dados) {
  if (!dados || typeof dados !== 'object') return { ok: false, message: 'Sem dados pra espelhar.' };
  const sh = ss_().getSheetByName('Espelho');
  const last = sh.getLastRow();
  const existentes = {};
  if (last >= 2) sh.getRange(2, 1, last - 1, 1).getValues().forEach((r, i) => { existentes[r[0]] = i + 2; });
  const agora = new Date();
  const chaves = Object.keys(dados);
  chaves.forEach(chave => {
    const json = JSON.stringify(dados[chave]);
    if (existentes[chave]) sh.getRange(existentes[chave], 2, 1, 2).setValues([[json, agora]]);
    else sh.appendRow([chave, json, agora]);
  });
  return { ok: true, message: 'Espelho atualizado (' + chaves.length + ' tabelas).', atualizadoEm: agora };
}

function lerEspelho_() {
  const sh = ss_().getSheetByName('Espelho');
  const last = sh.getLastRow();
  const resultado = {};
  let maisRecente = null;
  if (last >= 2) {
    sh.getRange(2, 1, last - 1, 3).getValues().forEach(linha => {
      if (!linha[0]) return;
      try { resultado[linha[0]] = JSON.parse(linha[1]); } catch (e) { resultado[linha[0]] = null; }
      if (linha[2] && (!maisRecente || new Date(linha[2]) > maisRecente)) maisRecente = new Date(linha[2]);
    });
  }
  resultado._atualizadoEm = maisRecente;
  return resultado;
}

/* =====================================================================
   DRIVE DA CONTINGÊNCIA (itens 16–18): cópia dos backups, cópia das fotos e leitura do espaço usado
   ===================================================================== */
const CONT_BACKUP_MAX_BYTES = 15 * 1024 * 1024;   // acima disso a cópia é recusada (o backup local continua)
const CONT_FOTO_MAX_BYTES = 5 * 1024 * 1024;
const CONT_BACKUP_RETENCAO_DIAS = 7, CONT_BACKUP_MINIMO = 3; // apaga cópias com mais de 7 dias, mas SEMPRE guarda as 3 mais recentes
const CONT_ARMAZ_ATENCAO_PCT = 70, CONT_ARMAZ_CRITICO_PCT = 90, CONT_ARMAZ_BLOQUEIO_PCT = 97;

/* Rode UMA vez no editor (menu de funções -> autorizarDrive -> Executar) e aceite as permissões de Drive. */
function autorizarDrive() {
  DriveApp.getRootFolder();
  pastaBackups_(); pastaFotos_(); abaFotos_();
  return 'Drive autorizado. Pastas e aba Fotos prontas.';
}

function pastaDrive_(propChave, nome) {
  const props = PropertiesService.getScriptProperties();
  const id = props.getProperty(propChave);
  if (id) { try { const p = DriveApp.getFolderById(id); if (!p.isTrashed()) return p; } catch (e) { /* pasta apagada, recria abaixo */ } }
  const raiz = DriveApp.getRootFolder();
  const existentes = raiz.getFoldersByName(nome);
  const pasta = existentes.hasNext() ? existentes.next() : raiz.createFolder(nome);
  props.setProperty(propChave, pasta.getId());
  return pasta;
}
function pastaBackups_() { return pastaDrive_('PASTA_BACKUPS_ID', 'Texas Burger - Backups (cópia)'); }
function pastaFotos_() { return pastaDrive_('PASTA_FOTOS_ID', 'Texas Burger - Fotos (cópia)'); }

function armazenamento_() {
  const usado = DriveApp.getStorageUsed(), limite = DriveApp.getStorageLimit();
  const pct = limite > 0 ? Math.round(usado / limite * 1000) / 10 : null;
  const nivel = pct === null ? 'Indisponível' : pct > CONT_ARMAZ_CRITICO_PCT ? 'Crítico' : pct >= CONT_ARMAZ_ATENCAO_PCT ? 'Atenção' : 'Normal';
  return { usado: usado, limite: limite, livre: limite > 0 ? Math.max(0, limite - usado) : null, percentual: pct, nivel: nivel };
}
function semEspaco_() { const a = armazenamento_(); return (a.percentual !== null && a.percentual >= CONT_ARMAZ_BLOQUEIO_PCT) ? a : null; }

/* ---------- ITEM 16: cópia dos backups ---------- */
function guardarBackup(nome, base64) {
  if (typeof nome !== 'string' || !nome.trim()) return { ok: false, message: 'Nome do backup inválido.' };
  if (typeof base64 !== 'string' || !base64) return { ok: false, message: 'Nenhum arquivo recebido.' };
  const cheio = semEspaco_();
  if (cheio) return { ok: false, message: 'Drive da contingência quase cheio (' + cheio.percentual + '%). Cópia não guardada.' };
  const bytes = Utilities.base64Decode(base64);
  if (bytes.length > CONT_BACKUP_MAX_BYTES) return { ok: false, message: 'Backup grande demais para copiar (' + Math.round(bytes.length / 1048576) + ' MB; máximo ' + Math.round(CONT_BACKUP_MAX_BYTES / 1048576) + ' MB).' };
  if (bytes.length < 4 || (bytes[0] & 255) !== 0x50 || (bytes[1] & 255) !== 0x4B) return { ok: false, message: 'O arquivo recebido não é um .xlsx válido.' };
  const nomeArq = nome.replace(/[^\w\-\. ()]/g, '-').trim().slice(0, 120) + '.xlsx';
  const pasta = pastaBackups_();
  const ja = pasta.getFilesByName(nomeArq);
  if (ja.hasNext()) { const f = ja.next(); return { ok: true, duplicado: true, arquivoId: f.getId(), tamanho: f.getSize() }; }
  const blob = Utilities.newBlob(bytes, 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', nomeArq);
  const arq = pasta.createFile(blob); // privado: SEM link público (tem custos, clientes e financeiro)
  podarBackups_(pasta);
  return { ok: true, arquivoId: arq.getId(), tamanho: bytes.length };
}
function podarBackups_(pasta) {
  const limite = new Date(); limite.setDate(limite.getDate() - CONT_BACKUP_RETENCAO_DIAS);
  const lista = [];
  const it = pasta.getFiles();
  while (it.hasNext()) { const f = it.next(); lista.push({ f: f, d: f.getDateCreated() }); }
  lista.sort((a, b) => b.d - a.d);
  lista.slice(CONT_BACKUP_MINIMO).forEach(x => { if (x.d < limite) { try { x.f.setTrashed(true); } catch (e) {} } });
}

/* ---------- ITEM 17: cópia das fotos ---------- */
function abaFotos_() {
  const ss = ss_();
  let sh = ss.getSheetByName('Fotos');
  if (!sh) {
    sh = ss.insertSheet('Fotos');
    sh.getRange(1, 1, 1, 5).setValues([['fotoIdOrigem', 'fotoIdReserva', 'nome', 'tamanho', 'atualizadoEm']]);
    sh.setFrozenRows(1);
  }
  return sh;
}
function listarFotos_() {
  const sh = abaFotos_(); const last = sh.getLastRow(); const mapa = {};
  if (last >= 2) sh.getRange(2, 1, last - 1, 2).getValues().forEach(r => { if (r[0] && r[1]) mapa[r[0]] = r[1]; });
  return { ok: true, fotos: mapa };
}
function tipoImagem_(b) {
  const u8 = k => (b[k] + 256) % 256;
  if (u8(0) === 0xFF && u8(1) === 0xD8 && u8(2) === 0xFF) return { tipo: 'image/jpeg', ext: '.jpg' };
  if (u8(0) === 0x89 && u8(1) === 0x50 && u8(2) === 0x4E && u8(3) === 0x47) return { tipo: 'image/png', ext: '.png' };
  if (u8(0) === 0x52 && u8(1) === 0x49 && u8(2) === 0x46 && u8(3) === 0x46 && u8(8) === 0x57 && u8(9) === 0x45 && u8(10) === 0x42 && u8(11) === 0x50) return { tipo: 'image/webp', ext: '.webp' };
  return null;
}
function guardarFoto(idOrigem, base64) {
  if (typeof idOrigem !== 'string' || !/^[\w-]{10,80}$/.test(idOrigem)) return { ok: false, message: 'Id de foto inválido.' };
  if (typeof base64 !== 'string' || !base64) return { ok: false, message: 'Nenhuma imagem recebida.' };
  const sh = abaFotos_(); const last = sh.getLastRow();
  if (last >= 2) { const lin = sh.getRange(2, 1, last - 1, 2).getValues(); for (let i = 0; i < lin.length; i++) if (lin[i][0] === idOrigem) return { ok: true, duplicado: true, fotoIdReserva: lin[i][1] }; }
  const cheio = semEspaco_();
  if (cheio) return { ok: false, message: 'Drive da contingência quase cheio (' + cheio.percentual + '%).' };
  const bytes = Utilities.base64Decode(base64);
  if (bytes.length > CONT_FOTO_MAX_BYTES) return { ok: false, message: 'Imagem maior que 5 MB.' };
  const t = tipoImagem_(bytes);
  if (!t) return { ok: false, message: 'Arquivo não é uma imagem válida (JPG, PNG ou WEBP).' };
  const arq = pastaFotos_().createFile(Utilities.newBlob(bytes, t.tipo, idOrigem + t.ext));
  arq.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW); // foto de cardápio é pública, como na conta principal
  sh.appendRow([idOrigem, arq.getId(), arq.getName(), bytes.length, new Date()]);
  return { ok: true, fotoIdReserva: arq.getId() };
}
/* Apaga a cópia de fotos que não existem mais na principal. Trava de segurança: lista vazia ou "mais da metade órfã" não apaga nada. */
function removerFotosOrfas(idsAtuais) {
  if (!Array.isArray(idsAtuais) || !idsAtuais.length) return { ok: false, message: 'Lista vazia: nada removido (proteção).' };
  const set = {}; idsAtuais.forEach(i => { set[String(i)] = true; });
  const sh = abaFotos_(); const last = sh.getLastRow();
  if (last < 2) return { ok: true, removidas: 0 };
  const linhas = sh.getRange(2, 1, last - 1, 2).getValues();
  const orfas = linhas.map((r, i) => ({ id: r[0], reserva: r[1], lin: i + 2 })).filter(x => x.id && !set[x.id]);
  if (linhas.length > 10 && orfas.length > linhas.length / 2) return { ok: false, message: 'Proteção: mais da metade das fotos ficaria órfã (' + orfas.length + ' de ' + linhas.length + '). Nada removido.' };
  orfas.sort((a, b) => b.lin - a.lin).forEach(x => { try { DriveApp.getFileById(x.reserva).setTrashed(true); } catch (e) {} sh.deleteRow(x.lin); });
  return { ok: true, removidas: orfas.length };
}

/* ---------- ITEM 18: espaço usado da conta da contingência ---------- */
function getArmazenamentoCont_() {
  const cats = { 'Cópias de backup': { qtd: 0, bytes: 0 }, 'Fotos (cópia)': { qtd: 0, bytes: 0 } };
  const backups = [];
  const itB = pastaBackups_().getFiles();
  while (itB.hasNext()) { const f = itB.next(); const b = f.getSize(); cats['Cópias de backup'].qtd++; cats['Cópias de backup'].bytes += b; backups.push({ nome: f.getName(), tamanho: b, criadoEm: f.getDateCreated().toISOString() }); }
  backups.sort((a, b) => (a.criadoEm < b.criadoEm ? 1 : -1));
  const itF = pastaFotos_().getFiles();
  while (itF.hasNext()) { const f = itF.next(); cats['Fotos (cópia)'].qtd++; cats['Fotos (cópia)'].bytes += f.getSize(); }
  return { ok: true, drive: armazenamento_(), categorias: cats, backups: backups.slice(0, 10) };
}


/* =====================================================================
   ETAPA 4 — ESPELHO DO SUPABASE NA CONTINGÊNCIA (ação "syncLote")
   Só a CHAVE_SERVIDOR pode chamar. Recebe os itens da fila_sync ({id, tabela, registro_id, operacao, payload}) e mantém
   uma aba "SB_<tabela>" por tabela (uma linha por registro, coluna A = id). Só vale o ÚLTIMO estado de cada registro.
   Não toca em Fila nem Espelho. Reenvio do mesmo lote não duplica.
   ===================================================================== */
function ctCelula_(v) {
  if (v === null || v === undefined) return '';
  if (typeof v === 'number' || typeof v === 'boolean') return v;
  let t = (typeof v === 'object') ? JSON.stringify(v) : String(v);
  if (t.length > 40000) t = t.slice(0, 40000);
  if (/^[=+\-@]/.test(t) || /^\d{4}-\d{2}-\d{2}/.test(t) || /^[\d.,\s:]+(e\d+)?$/i.test(t)) t = "'" + t;
  return t;
}
function ctAba_(nome) {
  const ss = ss_();
  let sh = ss.getSheetByName(nome);
  if (!sh) { sh = ss.insertSheet(nome); sh.getRange(1, 1).setValue('_id'); sh.setFrozenRows(1); }
  return sh;
}
function ctUpsert_(nomeAba, linhas, remover) {
  const sh = ctAba_(nomeAba);
  let cab = sh.getLastColumn() ? sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(String) : ['_id'];
  if (!cab.length || cab[0] === '') cab = ['_id'];
  const novas = [];
  linhas.forEach(function (l) { Object.keys(l.dados).forEach(function (k) { if (cab.indexOf(k) === -1 && novas.indexOf(k) === -1) novas.push(k); }); });
  if (novas.length) { cab = cab.concat(novas); sh.getRange(1, 1, 1, cab.length).setValues([cab]); }
  const ultima = sh.getLastRow();
  const ids = ultima > 1 ? sh.getRange(2, 1, ultima - 1, 1).getValues().map(function (r) { return String(r[0]).replace(/^'/, ''); }) : [];
  const pos = {}; ids.forEach(function (id, i) { pos[id] = i + 2; });
  const novasLinhas = []; let gravadas = 0;
  linhas.forEach(function (l) {
    const linha = cab.map(function (c, i) { return i === 0 ? ctCelula_(l.id) : (c in l.dados ? ctCelula_(l.dados[c]) : ''); });
    const p = pos[String(l.id)];
    if (p) sh.getRange(p, 1, 1, cab.length).setValues([linha]);
    else { novasLinhas.push(linha); pos[String(l.id)] = -1; }
    gravadas++;
  });
  if (novasLinhas.length) sh.getRange(sh.getLastRow() + 1, 1, novasLinhas.length, cab.length).setValues(novasLinhas);
  let removidas = 0;
  if (remover && remover.length) {
    const alvo = {}; remover.forEach(function (id) { alvo[String(id)] = true; });
    const atuais = sh.getLastRow() > 1 ? sh.getRange(2, 1, sh.getLastRow() - 1, 1).getValues() : [];
    for (let i = atuais.length - 1; i >= 0; i--) {
      if (alvo[String(atuais[i][0]).replace(/^'/, '')]) { sh.deleteRow(i + 2); removidas++; }
    }
  }
  return { gravadas: gravadas, removidas: removidas };
}
function ctSyncLote_(itens) {
  if (!Array.isArray(itens) || itens.length > 500) return { ok: false, message: 'Lote inválido.' };
  const ultimo = {};
  itens.forEach(function (it) { if (it && it.tabela && it.registro_id != null) ultimo[it.tabela + '|' + it.registro_id] = it; });
  const porTabela = {};
  Object.keys(ultimo).forEach(function (k) {
    const it = ultimo[k]; const t = String(it.tabela).replace(/[^a-z0-9_]/gi, '');
    if (!t) return;
    porTabela[t] = porTabela[t] || { up: [], del: [] };
    if (it.operacao === 'DELETE') porTabela[t].del.push(String(it.registro_id));
    else porTabela[t].up.push({ id: String(it.registro_id), dados: it.payload || {} });
  });
  let total = 0;
  Object.keys(porTabela).forEach(function (t) {
    const r = ctUpsert_('SB_' + t, porTabela[t].up, porTabela[t].del);
    total += r.gravadas + r.removidas;
  });
  return { ok: true, processados: total };
}
