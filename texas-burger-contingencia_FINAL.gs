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
  servidor: ['listarPendentes', 'marcarSincronizado', 'atualizarEspelho', 'getEspelho', 'getEspelhoPublico', 'getEspelhoInterno'],
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
