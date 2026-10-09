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
             'guardarBackup', 'getArmazenamento', 'listarFotos', 'guardarFoto', 'removerFotosOrfas', 'syncLote', 'gerarChaveLeitura'],
  interna:  ['enfileirar', 'getEspelhoPublico', 'getEspelhoInterno', 'getEspelhoReserva', 'listarFilaInterna'],
  publica:  ['enfileirar', 'getEspelhoPublico'],
  leitura:  ['getEspelhoReserva', 'listarFilaInterna']   // RESERVA DE LEITURA: só consulta (Cozinha/Garçom/Entregador também usam); sem dados de contato nem de pagamento
};

let _ssMemo_ = null; // abre a planilha UMA vez por execução
function ss_() {
  const props = PropertiesService.getScriptProperties();
  let id = props.getProperty('SPREADSHEET_ID');
  if (!id) {
    const ativa = SpreadsheetApp.getActiveSpreadsheet();
    if (!ativa) throw new Error('Não foi possível identificar a planilha. Abra o editor do Apps Script pela própria planilha e rode setup() uma vez.');
    id = ativa.getId();
    props.setProperty('SPREADSHEET_ID', id);
  }
  if (!_ssMemo_) _ssMemo_ = SpreadsheetApp.openById(id);
  return _ssMemo_;
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
  if (chave === p.getProperty('CHAVE_LEITURA')) return 'leitura';
  return '';
}

function responder(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

/* Health check (abrir a URL /exec no navegador). Só números — nada de dados de pedido. */
function doGet(e) {
  try {
    return responder({ ok: true, servico: 'Texas Burger - Contingência', pendentes: contarPendentes_(), espelhoAtualizadoEm: espelhoAtualizadoEm_() });
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

  /* OTIMIZAÇÃO (Etapa A): ações só de leitura NÃO esperam a trava. Antes, o cardápio público e a Cozinha ficavam na fila atrás de uma gravação. */
  const SEM_TRAVA = ['listarPendentes', 'getEspelho', 'getEspelhoPublico', 'getEspelhoInterno', 'getEspelhoReserva', 'listarFilaInterna', 'listarFotos', 'getArmazenamento'];
  const lock = LockService.getScriptLock();
  const usaTrava = SEM_TRAVA.indexOf(body.action) === -1;
  if (usaTrava) { try { lock.waitLock(20000); } catch (err) { return responder({ ok: false, ocupado: true, message: 'Contingência ocupada, tente de novo.' }); } }
  try {
    let r;
    switch (body.action) {
      case 'enfileirar': r = enfileirar(body.id, body.tipo, body.dados, perfil); break;
      case 'listarPendentes': r = { ok: true, pendentes: readFilaPendente() }; break;
      case 'marcarSincronizado': r = marcarSincronizado(body.id); break;
      case 'atualizarEspelho': r = atualizarEspelho(body.dados); break;
      case 'getEspelho': r = { ok: true, espelho: lerEspelho_() }; break;
      case 'getEspelhoPublico': { const esp = lerEspelho_(['publico']); r = { ok: true, espelho: Object.assign({}, esp.publico || {}, { _atualizadoEm: esp._atualizadoEm }) }; break; }
      case 'getEspelhoInterno': { const esp = lerEspelho_(['publico', 'interno']); r = { ok: true, espelho: Object.assign({}, esp.publico || {}, esp.interno || {}, { _atualizadoEm: esp._atualizadoEm }) }; break; }
      case 'guardarBackup': r = guardarBackup(body.nome, body.base64); break;
      case 'getArmazenamento': r = getArmazenamentoCont_(); break;
      case 'listarFotos': r = listarFotos_(); break;
      case 'guardarFoto': r = guardarFoto(body.idOrigem, body.base64); break;
      case 'removerFotosOrfas': r = removerFotosOrfas(body.ids); break;
      case 'syncLote': r = ctSyncLote_(body.itens); break;
      case 'gerarChaveLeitura': r = gerarChaveLeitura_(); break;
      case 'listarFilaInterna': r = { ok: true, fila: filaInternaResumo_() }; break;
      case 'getEspelhoReserva': { const esp = lerEspelho_(['reserva']); r = { ok: true, reserva: esp.reserva || null, atualizadoEm: esp._atualizadoEm }; break; }   // ETAPA 4 — espelho das tabelas do Supabase (abas SB_<tabela>)
      default: r = { ok: false, message: 'Ação desconhecida.' };
    }
    return responder(r);
  } catch (err) {
    return responder({ ok: false, message: 'Erro: ' + err.message });
  } finally {
    if (usaTrava) lock.releaseLock();
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
    /* OTIMIZAÇÃO (Etapa A): lê só as colunas id, status e origem (a coluna C guarda o pedido inteiro, até 30 mil caracteres por linha). */
    const n = last - 1;
    const ids = sh.getRange(2, 1, n, 1).getValues(), sts = sh.getRange(2, 5, n, 1).getValues(), ori = sh.getRange(2, 7, n, 1).getValues();
    let pend = 0, pendPub = 0;
    for (let i = 0; i < n; i++) {
      if (ids[i][0] === id) return { ok: true, message: 'Já estava na fila (não duplicado).', duplicado: true };
      if (ids[i][0] && sts[i][0] === 'Pendente') { pend++; if (ori[i][0] === 'publica') pendPub++; }
    }
    if (pend >= FILA_MAX_PENDENTES) return { ok: false, message: 'Fila cheia. Ligue para o restaurante.' };
    if (perfil === 'publica' && pendPub >= FILA_MAX_PUBLICA) return { ok: false, message: 'Fila de pedidos online cheia. Ligue para o restaurante.' };
  }
  sh.appendRow([id, 'venda', json, new Date(), 'Pendente', '', perfil || '']);
  return { ok: true, message: 'Guardado na fila de contingência.' };
}

function contarPendentes_() {
  const sh = ss_().getSheetByName('Fila');
  const last = sh.getLastRow();
  if (last < 2) return 0;
  return sh.getRange(2, 5, last - 1, 1).getValues().filter(r => r[0] === 'Pendente').length;
}
function readFilaPendente() {
  /* OTIMIZAÇÃO (Etapa A): descobre pela coluna de status onde estão os pendentes e lê o pedido (coluna C) só dessa faixa. */
  const sh = ss_().getSheetByName('Fila');
  const last = sh.getLastRow();
  if (last < 2) return [];
  const sts = sh.getRange(2, 5, last - 1, 1).getValues();
  let primeira = -1;
  for (let i = 0; i < sts.length; i++) if (sts[i][0] === 'Pendente') { primeira = i; break; }
  if (primeira < 0) return [];
  const ini = primeira + 2;
  return sh.getRange(ini, 1, last - ini + 1, 6).getValues()
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
  const existentes = {}, hashes = {};
  if (last >= 2) sh.getRange(2, 1, last - 1, 4).getValues().forEach((r, i) => { existentes[r[0]] = i + 2; hashes[r[0]] = String(r[3] || ''); });
  const agora = new Date();
  const chaves = Object.keys(dados);
  let gravadas = 0, iguais = 0;
  chaves.forEach(chave => {
    const json = JSON.stringify(dados[chave]);
    const h = Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, json).map(b => ('0' + (b & 0xff).toString(16)).slice(-2)).join('');
    if (existentes[chave]) {
      if (hashes[chave] === h) { iguais++; return; }   // conteúdo idêntico ao que já está aí: não regrava (coluna D guarda o hash)
      sh.getRange(existentes[chave], 2, 1, 3).setValues([[json, agora, h]]);
    } else sh.appendRow([chave, json, agora, h]);
    gravadas++;
  });
  if (gravadas) limparCacheEspelho_();
  return { ok: true, message: 'Espelho atualizado (' + gravadas + ' de ' + chaves.length + ' tabelas gravadas' + (iguais ? ', ' + iguais + ' já estavam iguais' : '') + ').', atualizadoEm: agora };
}

function espelhoAtualizadoEm_() {
  const sh = ss_().getSheetByName('Espelho');
  const last = sh.getLastRow();
  if (last < 2) return null;
  let m = null;
  sh.getRange(2, 3, last - 1, 1).getValues().forEach(r => { if (r[0] && (!m || new Date(r[0]) > m)) m = new Date(r[0]); });
  return m;
}
/* OTIMIZAÇÃO (Etapa A): "chaves" limita o que é lido e convertido (o cardápio público não precisa baixar a lista de clientes).
   Resultado guardado 60 s em cache (cada chave até ~90 mil caracteres); atualizarEspelho() limpa o cache na hora. */
const ESP_CACHE_SEG = 60;
function lerEspelho_(chaves) {
  const cache = CacheService.getScriptCache();
  const ck = 'esp:' + (chaves ? chaves.slice().sort().join(',') : '*');
  try { const c = cache.get(ck); if (c) { const o = JSON.parse(c); if (o._atualizadoEm) o._atualizadoEm = new Date(o._atualizadoEm); return o; } } catch (e) {}
  const sh = ss_().getSheetByName('Espelho');
  const last = sh.getLastRow();
  const resultado = {};
  let maisRecente = null;
  if (last >= 2) {
    // OTIMIZAÇÃO: lê só chave e data de todas as linhas; o JSON (coluna B, pode ter dezenas de milhares de caracteres) só das linhas pedidas
    const chavesCol = sh.getRange(2, 1, last - 1, 1).getValues(), datasCol = sh.getRange(2, 3, last - 1, 1).getValues();
    chavesCol.forEach((l, i) => {
      const chave = l[0]; if (!chave) return;
      const d = datasCol[i][0];
      if (d && (!maisRecente || new Date(d) > maisRecente)) maisRecente = new Date(d);
      if (chaves && chaves.indexOf(chave) === -1) return;
      try { resultado[chave] = JSON.parse(sh.getRange(i + 2, 2).getValue()); } catch (e) { resultado[chave] = null; }
    });
  }
  resultado._atualizadoEm = maisRecente;
  try { const j = JSON.stringify(resultado); if (j.length < 90000) cache.put(ck, j, ESP_CACHE_SEG); } catch (e) {}
  return resultado;
}
function limparCacheEspelho_() {
  try { CacheService.getScriptCache().removeAll(['esp:*', 'esp:publico', 'esp:publico,interno', 'esp:reserva']); } catch (e) {}
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
  /* OTIMIZADO: lê a coluna de ids uma vez, grava linhas vizinhas em um só bloco e apaga em faixas (antes: uma chamada por linha). */
  const sh = ctAba_(nomeAba);
  let cab = sh.getLastColumn() ? sh.getRange(1, 1, 1, sh.getLastColumn()).getValues()[0].map(String) : ['_id'];
  if (!cab.length || cab[0] === '') cab = ['_id'];
  const novas = [];
  linhas.forEach(function (l) { Object.keys(l.dados).forEach(function (k) { if (cab.indexOf(k) === -1 && novas.indexOf(k) === -1) novas.push(k); }); });
  if (novas.length) { cab = cab.concat(novas); sh.getRange(1, 1, 1, cab.length).setValues([cab]); }
  const ultima = sh.getLastRow();
  const ids = ultima > 1 ? sh.getRange(2, 1, ultima - 1, 1).getValues().map(function (r) { return String(r[0]).replace(/^'/, ''); }) : [];
  const pos = {}; ids.forEach(function (id, i) { pos[id] = i + 2; });
  const atualizar = [], novasLinhas = [], idxNova = {}; let gravadas = 0;
  linhas.forEach(function (l) {
    const linha = cab.map(function (c, i) { return i === 0 ? ctCelula_(l.id) : (c in l.dados ? ctCelula_(l.dados[c]) : ''); });
    const chave = String(l.id), p = pos[chave];
    if (p > 0) atualizar.push({ p: p, linha: linha });
    else if (idxNova[chave] !== undefined) novasLinhas[idxNova[chave]] = linha;
    else { idxNova[chave] = novasLinhas.length; novasLinhas.push(linha); }
    gravadas++;
  });
  if (atualizar.length) {
    atualizar.sort(function (a, b) { return a.p - b.p; });
    let k = 0;
    while (k < atualizar.length) {
      let f = k; while (f + 1 < atualizar.length && atualizar[f + 1].p === atualizar[f].p + 1) f++;
      sh.getRange(atualizar[k].p, 1, f - k + 1, cab.length).setValues(atualizar.slice(k, f + 1).map(function (x) { return x.linha; }));
      k = f + 1;
    }
  }
  if (novasLinhas.length) sh.getRange(sh.getLastRow() + 1, 1, novasLinhas.length, cab.length).setValues(novasLinhas);
  let removidas = 0;
  if (remover && remover.length) {
    const alvo = {}; remover.forEach(function (id) { alvo[String(id)] = true; });
    const apagar = []; ids.forEach(function (id, i) { if (alvo[id]) apagar.push(i + 2); });
    const o = apagar.sort(function (a, b) { return a - b; }), faixas = [];
    o.forEach(function (n) { const u = faixas[faixas.length - 1]; if (u && n === u[0] + u[1]) u[1]++; else faixas.push([n, 1]); });
    for (let f = faixas.length - 1; f >= 0; f--) { sh.deleteRows(faixas[f][0], faixas[f][1]); removidas += faixas[f][1]; }
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


/* =====================================================================
   RESERVA DE LEITURA (Etapa 6 das correções pós-migração)
   Quando o Supabase cai, o app mostra os pedidos em andamento (espelho a cada ~10 min) e os pedidos que entraram aqui na fila.
   Perfil "leitura": só lê. Nunca devolve telefone, endereço nem forma de pagamento.
   ===================================================================== */
function gerarChaveLeitura_() {   // só a planilha principal chama (chave do servidor); devolve sempre a mesma chave
  const p = PropertiesService.getScriptProperties();
  let k = p.getProperty('CHAVE_LEITURA');
  if (!k) { k = 'txblei' + Utilities.getUuid().replace(/-/g, ''); p.setProperty('CHAVE_LEITURA', k); }
  return { ok: true, chave: k };
}
function filaInternaResumo_() {
  return readFilaPendente().filter(function (x) { return x.tipo === 'venda' && !x.corrompido; }).slice(-80).map(function (x) {
    const d = x.dados || {};
    const itens = (d.itens || []).map(function (i) { return { descricao: String(i.descricao || ''), quantidade: Number(i.quantidade) || 0 }; });
    const total = (d.itens || []).reduce(function (t, i) { return t + (Number(i.valorUnitario) || 0) * (Number(i.quantidade) || 0); }, 0);
    return { id: x.id, recebidoEm: x.recebidoEm, origem: d.origem || '', cliente: d.clienteNome || '', tipoEntrega: d.tipoEntrega || '', itens: itens,
             total: Math.round(total * 100) / 100, obs: (d.dadosEntrega && d.dadosEntrega.observacoes) ? String(d.dadosEntrega.observacoes) : '' };
  });
}


/* =====================================================================
   ETAPA A (OTIMIZAÇÃO) — LIMPEZA DA FILA
   A aba Fila só crescia: cada pedido sincronizado continuava ali e todo envio relia tudo. Agora as linhas SINCRONIZADAS com mais
   de FILA_RETENCAO_DIAS dias são apagadas (em faixas, de baixo para cima). Pendentes e corrompidos NUNCA são apagados.
   Rode `garantirLimpezaFila` UMA vez no editor para criar o gatilho diário (4h).
   ===================================================================== */
const FILA_RETENCAO_DIAS = 7;
function limparFilaSincronizada() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(20000)) return 'Ocupado; tente depois.';
  try {
    const sh = ss_().getSheetByName('Fila');
    const last = sh ? sh.getLastRow() : 0;
    if (last < 2) return 'Fila vazia.';
    const dados = sh.getRange(2, 5, last - 1, 2).getValues();   // status, sincronizadoEm
    const corte = Date.now() - FILA_RETENCAO_DIAS * 86400000;
    const apagar = [];
    dados.forEach((r, i) => { if (r[0] === 'Sincronizado' && r[1] && new Date(r[1]).getTime() < corte) apagar.push(i + 2); });
    const faixas = [];
    apagar.forEach(n => { const u = faixas[faixas.length - 1]; if (u && n === u[0] + u[1]) u[1]++; else faixas.push([n, 1]); });
    for (let f = faixas.length - 1; f >= 0; f--) sh.deleteRows(faixas[f][0], faixas[f][1]);
    return 'Fila: ' + apagar.length + ' linha(s) sincronizada(s) antiga(s) apagada(s).';
  } finally { lock.releaseLock(); }
}
function garantirLimpezaFila() {
  const tem = ScriptApp.getProjectTriggers().some(t => t.getHandlerFunction() === 'limparFilaSincronizada');
  if (!tem) ScriptApp.newTrigger('limparFilaSincronizada').timeBased().everyDays(1).atHour(4).create();
  return 'Limpeza diária da Fila ativada (4h).';
}
