/**
 * TEXAS BURGER — Sistema Completo (Login, Clientes, Produtos, Estoque, Caixa, Financeiro)
 *
 * COMO USAR:
 * 1. Crie uma planilha nova e em branco no Google Sheets.
 * 2. Extensões > Apps Script. Apague tudo e cole este arquivo inteiro.
 * 3. Rode "criarPlanilhaTexasBurger" uma vez (autorize o acesso).
 * 4. "Implantar" > "Nova implantação" > "App da Web" > Executar como "Eu" > Acesso "Qualquer pessoa".
 * 5. Copie a URL /exec e cole na constante API_URL do HTML.
 *
 * LOGIN INICIAL: usuário "Jonatan" (nível Admin). A senha temporária é gerada ao rodar
 * "criarPlanilhaTexasBurger" e aparece UMA vez em Ver > Registros de execução. Troque-a no primeiro acesso
 * em Administrador > Usuários e Permissões.
 * ESQUECEU A SENHA DE ADMIN? Rode "redefinirSenhaAdminEmergencia" pelo editor do Apps Script (gera nova senha temporária).
 * ANTES DE USAR DE VERDADE: rode "marcarProducao" (bloqueia dados de teste).
 */

const COR_VERMELHO = '#B3241C';
const COR_DOURADO  = '#E8B23D';
const COR_ESCURO   = '#241A10';
const COR_CREME    = '#F2E6D2';
const COR_LINHA    = '#EFE6D6';
const FUSO         = 'America/Sao_Paulo';

let USUARIO_ATUAL = '';
let NIVEL_ATUAL = '';
let APARELHO_ATUAL = ''; // BLOCO 4.2/4.5: "aparelho xxxxxxxx · Chrome · Android" da sessão (o Apps Script não expõe IP)
let AUTORIZADOR_ATUAL = ''; // FASE 9: quem autorizou a operação sensível (Admin logado ou dono da senha digitada)

/* Perfis do sistema (ITEM 6). Adicionar um nível novo aqui já libera ele em toda
   validação de cadastro de usuário — não precisa mexer em mais nenhum lugar. */
const NIVEIS_VALIDOS = ['Admin', 'Operador', 'Garçom', 'Cozinha', 'Entregador'];

/* ---------- CONTINGÊNCIA (Item 81) ----------
   API separada, numa conta Google diferente, que serve de plano B: espelho de
   leitura (cardápio/produtos/clientes) + fila de vendas feitas enquanto esta
   planilha estiver fora do ar. */
const CONTINGENCIA_API_URL = 'https://script.google.com/macros/s/AKfycby3WljBnr7gpJrHdkbTvBCh5uIXqS4KCS6wkBYB5idxf5gI04efoDumQj264kR_smoW/exec';
/* SEGURANÇA: as chaves da contingência NÃO ficam no código. Cadastre em Configurações do projeto ->
   Propriedades do script: CONTINGENCIA_CHAVE_SERVIDOR (só esta planilha usa) e CONTINGENCIA_CHAVE_INTERNA
   (entregue só a Admin/Operador logados). Os valores saem da função gerarChaves() do script da contingência. */
function chaveContingencia_(nome) {
  const v = PropertiesService.getScriptProperties().getProperty(nome);
  if (!v) throw new Error('Chave da contingência não configurada (' + nome + '). Veja Propriedades do script.');
  return v;
}

/* CONFIGURAÇÃO RÁPIDA DA CONTINGÊNCIA — rode UMA vez no editor (menu de funções -> configurarContingencia -> Executar).
   Grava as duas chaves nas Propriedades do script (onde o sistema as lê) e já roda a conferência.
   Depois de rodar com sucesso, APAGUE os valores abaixo (deixe '') para as chaves não ficarem escritas no código. */
function configurarContingencia() {
  const SERVIDOR = 'txbsrv-bc2849c9bee9461fb6b606c22c386152d98e51f2';
  const INTERNA = 'txbint-1396dc14a0f64602a4738828a456e21a9697b414';
  PropertiesService.getScriptProperties().setProperties({ CONTINGENCIA_CHAVE_SERVIDOR: SERVIDOR, CONTINGENCIA_CHAVE_INTERNA: INTERNA });
  return conferirChavesContingencia();
}

/* ITEM 16 — conferência das chaves da contingência.
   Rode no editor do Apps Script (menu de funções -> conferirChavesContingencia -> Executar) e veja o "Registro de execução".
   Nunca mostra a chave inteira. */
function conferirChavesContingencia() {
  const p = PropertiesService.getScriptProperties();
  const srv = p.getProperty('CONTINGENCIA_CHAVE_SERVIDOR') || '';
  const int = p.getProperty('CONTINGENCIA_CHAVE_INTERNA') || '';
  const mascara = v => v ? v.slice(0, 7) + '…' + v.slice(-4) + ' (' + v.length + ' caracteres)' : 'AUSENTE';
  const chamar = (chave, action) => {
    try {
      const r = UrlFetchApp.fetch(CONTINGENCIA_API_URL, { method: 'post', contentType: 'application/json', payload: JSON.stringify({ chave: chave, action: action }), muteHttpExceptions: true });
      return JSON.parse(r.getContentText());
    } catch (e) { return { ok: false, message: 'Falha de rede: ' + e.message }; }
  };
  const L = [];
  L.push('CONTINGENCIA_CHAVE_SERVIDOR: ' + mascara(srv) + (srv && srv.indexOf('txbsrv-') !== 0 ? '   ⚠ prefixo inesperado (deveria começar com txbsrv-)' : ''));
  L.push('CONTINGENCIA_CHAVE_INTERNA : ' + mascara(int) + (int && int.indexOf('txbint-') !== 0 ? '   ⚠ prefixo inesperado (deveria começar com txbint-)' : ''));
  if (srv && srv === int) L.push('⚠ SERVIDOR e INTERNA são iguais — devem ser chaves diferentes.');
  if (srv) { const r = chamar(srv, 'listarPendentes'); L.push('Teste SERVIDOR (listarPendentes): ' + (r.ok ? 'OK — a contingência aceitou a chave' : 'FALHOU — ' + (r.message || 'sem resposta'))); }
  if (int) {
    const r1 = chamar(int, 'getEspelhoInterno'); L.push('Teste INTERNA (getEspelhoInterno): ' + (r1.ok ? 'OK — a contingência aceitou a chave' : 'FALHOU — ' + (r1.message || 'sem resposta')));
    const r2 = chamar(int, 'listarPendentes'); L.push('Teste INTERNA não pode listar pendentes: ' + (r2.ok ? '⚠ ela aceitou uma ação só de servidor — confira se não é a mesma chave' : 'OK (negado, como deve ser)'));
  }
  L.push('Chave PÚBLICA: fica no index.html (constante CONTINGENCIA_CHAVE_PUBLICA) e deve ser igual à CHAVE_PUBLICA do projeto da contingência.');
  Logger.log(L.join('\n'));
  return L.join('\n');
}

/* ITEM 16 — medição: mostra quanto tempo cada leitura leva (rode antes e depois das mudanças e compare). */
function medirTemposLeitura() {
  USUARIO_ATUAL = 'sistema'; NIVEL_ATUAL = 'Admin';
  const t = (nome, fn) => {
    const i = Date.now(); let n = '';
    try { const r = fn(); n = Array.isArray(r) ? r.length + ' linhas' : ''; } catch (e) { n = 'ERRO ' + e.message; }
    Logger.log(nome + ': ' + (Date.now() - i) + ' ms ' + n);
  };
  t('readProdutos', () => readProdutos());
  t('readProdutoPrecos', () => readProdutoPrecos());
  t('readClientes', () => readClientes());
  t('readVendas', () => readVendas());
  t('readItensVenda', () => readItensVenda());
  t('readPagamentosVenda', () => readPagamentosVenda());
  t('calcularMaisPedidos_', () => calcularMaisPedidos_());
  t('getAllData (tudo)', () => getAllData());
  invalidarCacheCardapio_(false);
  t('getCardapioPublico (sem cache)', () => getCardapioPublico());
  t('getCardapioPublico (com cache)', () => getCardapioPublico());
  NIVEL_ATUAL = '';
}

/* Duração da sessão (ITEM 7). Cache do Apps Script tem teto de 6h por chave;
   por isso a sessão é renovada a cada chamada válida (sliding expiration) em
   vez de expirar no meio de um turno de trabalho. */
const SESSAO_TTL_SEGUNDOS = 21600;

/* =========================================================
   PARTE 1 — CRIAÇÃO E FORMATAÇÃO DA PLANILHA
   ========================================================= */
function criarPlanilhaTexasBurger() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  PropertiesService.getScriptProperties().setProperty('SPREADSHEET_ID', ss.getId());
  ss.rename('Texas Burger - Sistema Completo');

  criarUsuarios(ss);
  criarClientes(ss);
  criarPromocoes(ss);
  criarEstruturasNovosRecursos(ss);
  criarIndicacoes(ss);
  criarFidelidade(ss);
  criarFormasPagamento(ss);
  criarCategorias(ss);
  criarAdicionais(ss);
  criarProdutoAdicionais(ss);
  criarFeedbacks(ss);
  criarOcorrencias(ss);
  criarProdutos(ss);
  criarProdutoIngredientes(ss);
  criarProdutoPrecos(ss);
  criarEstoque(ss);
  criarMovimentacoesEstoque(ss);
  criarContingenciaReconciliada(ss);
  criarCombos(ss);
  criarComboPrecos(ss);
  criarComboItens(ss);
  criarVendas(ss);
  criarMesas(ss);
  criarFechamentosEntrega(ss);
  criarEntregasFechadas(ss);
  criarItensVenda(ss);
  criarPagamentosVenda(ss);
  criarDespesas(ss);
  criarDespesasRecorrentes(ss);
  criarSangrias(ss);
  criarConfiguracoes(ss);
  criarCaixaSessoes(ss);
  criarLog(ss);
  abaBackups_();
  abaRequisicoes_();

  const padrao = ss.getSheetByName('Sheet1') || ss.getSheetByName('Página1');
  if (padrao && ss.getSheets().length > 1) ss.deleteSheet(padrao);

  ss.setActiveSheet(ss.getSheetByName('Clientes'));
  SpreadsheetApp.flush();
}

/* ---------- DADOS FICTÍCIOS DE TESTE (uso único) ----------
   Cria um funcionário de cada perfil e alguns clientes fictícios pra testar o
   sistema. Tudo com prefixo "TESTE" no nome pra ficar fácil de achar e apagar
   depois. Idempotente: não duplica se já existir. */


function criarUsuarios(ss) {
  let sh = ss.getSheetByName('Usuários') || ss.insertSheet('Usuários', 0);
  sh.clear();
  sh.setTabColor('#000000');
  formatarCabecalho(sh, ['Login', 'Senha', 'Nível de Acesso', 'Ativo', 'Criado em', 'Nome', 'Telefone', 'ID']);
  [140, 140, 130, 70, 150, 180, 140, 280].forEach((w, i) => sh.setColumnWidth(i + 1, w));
  sh.getRange('B2:B500').setNumberFormat('@'); // Senha como Texto — evita "123456" virar número e quebrar o login
  sh.getRange('G2:G500').setNumberFormat('@'); // Telefone como Texto
  const regraNivel = SpreadsheetApp.newDataValidation().requireValueInList(NIVEIS_VALIDOS, true).setAllowInvalid(false).build();
  sh.getRange('C2:C500').setDataValidation(regraNivel);
  const regraAtivo = SpreadsheetApp.newDataValidation().requireValueInList(['Sim', 'Não'], true).setAllowInvalid(false).build();
  sh.getRange('D2:D500').setDataValidation(regraAtivo);
  const senhaTemp = novaSenhaTemporaria_();
  sh.getRange(2, 1, 1, 8).setValues([['Jonatan', hashSenha_(senhaTemp), 'Admin', 'Sim', agora(), '', '', Utilities.getUuid()]]);
  Logger.log('SENHA TEMPORÁRIA do usuário Jonatan: ' + senhaTemp + ' (troque no primeiro acesso)');
  aplicarZebraELinhas(sh, 7, 500);
}

function criarClientes(ss) {
  let sh = ss.getSheetByName('Clientes') || ss.insertSheet('Clientes');
  sh.clear();
  sh.setTabColor(COR_CREME);
  formatarCabecalho(sh, ['ID', 'Nome', 'Telefone', 'Data Nascimento', 'Endereço', 'Como Conheceu', 'Primeiro Contato', 'Observações']);
  [40,200,140,120,240,150,150,220].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('C2:C3000').setNumberFormat('@');
  sh.getRange('D2:D3000').setNumberFormat('@');
  aplicarZebraELinhas(sh, 8, 3000);
  sh.hideColumns(1, 1);
}

/* ---------- FASE 8A — FORMAS DE PAGAMENTO (ITENS 41, 42) ----------
   Colunas: ID, Nome, Ativa, VisívelCardápio, Taxa %, Taxa Fixa, Prazo (dias), Permite Troco, Ordem.
   A taxa é uma FOTO: cada pagamento de venda guarda a taxa calculada na hora (PagamentosVenda col. E),
   então mudar a taxa depois não altera vendas antigas. */
const CABECALHO_FORMAS_PAGAMENTO = ['ID', 'Nome', 'Ativa', 'VisívelCardápio', 'Taxa %', 'Taxa Fixa', 'Prazo (dias)', 'Permite Troco', 'Ordem'];
function criarFormasPagamento(ss) {
  let sh = ss.getSheetByName('Formas de Pagamento') || ss.insertSheet('Formas de Pagamento');
  sh.clear();
  sh.setTabColor(COR_DOURADO);
  if (sh.getMaxColumns() < 9) sh.insertColumnsAfter(sh.getMaxColumns(), 9 - sh.getMaxColumns());
  formatarCabecalho(sh, CABECALHO_FORMAS_PAGAMENTO);
  [40,200,80,110,80,90,100,110,70].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  const regraSimNao = SpreadsheetApp.newDataValidation().requireValueInList(['Sim', 'Não'], true).setAllowInvalid(false).build();
  ['C2:C200','D2:D200','H2:H200'].forEach(a => sh.getRange(a).setDataValidation(regraSimNao));
  sh.getRange('E2:E200').setNumberFormat('0.00"%"');
  sh.getRange('F2:F200').setNumberFormat('R$ #,##0.00');
  aplicarZebraELinhas(sh, 9, 200);
  sh.hideColumns(1, 1);
  const iniciais = ['Dinheiro', 'Pix', 'Cartão de Débito', 'Cartão de Crédito', 'Alelo', 'iFood'];
  iniciais.forEach((nome, i) => sh.appendRow([Utilities.getUuid(), nome, 'Sim', 'Sim', 0, 0, 0, nome === 'Dinheiro' ? 'Sim' : 'Não', i + 1]));
}

/* Rode UMA vez na planilha atual (não apaga nada): acrescenta as colunas novas de Formas de Pagamento
   e a coluna "Taxa Aplicada" em PagamentosVenda. Pode rodar de novo sem duplicar. */
function prepararFase8Formas() {
  const ss = ss_();
  const sh = ss.getSheetByName('Formas de Pagamento');
  if (sh.getMaxColumns() < 9) sh.insertColumnsAfter(sh.getMaxColumns(), 9 - sh.getMaxColumns());
  if (!String(sh.getRange(1, 5).getValue())) {
    sh.getRange(1, 5, 1, 5).setValues([CABECALHO_FORMAS_PAGAMENTO.slice(4)]);
    sh.getRange(1, 5, 1, 5).setBackground(COR_ESCURO).setFontColor(COR_DOURADO).setFontWeight('bold');
    const last = sh.getLastRow();
    for (let i = 2; i <= last; i++) {
      const nome = String(sh.getRange(i, 2).getValue());
      sh.getRange(i, 5, 1, 5).setValues([[0, 0, 0, nome === 'Dinheiro' ? 'Sim' : 'Não', i - 1]]);
    }
    const regraSimNao = SpreadsheetApp.newDataValidation().requireValueInList(['Sim', 'Não'], true).setAllowInvalid(false).build();
    sh.getRange('H2:H200').setDataValidation(regraSimNao);
    sh.getRange('E2:E200').setNumberFormat('0.00"%"');
    sh.getRange('F2:F200').setNumberFormat('R$ #,##0.00');
    [80,90,100,110,70].forEach((w,i)=>sh.setColumnWidth(i+5,w));
  }
  const sp = ss.getSheetByName('PagamentosVenda');
  if (sp.getMaxColumns() < 5) sp.insertColumnsAfter(sp.getMaxColumns(), 5 - sp.getMaxColumns());
  if (!String(sp.getRange(1, 5).getValue())) {
    sp.getRange(1, 5).setValue('Taxa Aplicada').setBackground(COR_ESCURO).setFontColor(COR_DOURADO).setFontWeight('bold');
    sp.getRange('E2:E20000').setNumberFormat('R$ #,##0.00');
    sp.setColumnWidth(5, 110);
  }
  return { ok: true, message: 'Estrutura da Fase 8A pronta.' };
}

function criarProdutoPrecos(ss) {
  let sh = ss.getSheetByName('ProdutoPrecos') || ss.insertSheet('ProdutoPrecos');
  sh.clear();
  sh.setTabColor('#6b4a24');
  formatarCabecalho(sh, ['ID', 'ID Produto', 'ID Forma de Pagamento', 'Preço', 'Custo']);
  [40,40,40,100,100].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('D2:E20000').setNumberFormat('R$ #,##0.00');
  aplicarZebraELinhas(sh, 5, 20000);
  sh.hideColumns(1, 3);
}

function criarComboPrecos(ss) {
  let sh = ss.getSheetByName('ComboPrecos') || ss.insertSheet('ComboPrecos');
  sh.clear();
  sh.setTabColor('#8a5a1f');
  formatarCabecalho(sh, ['ID', 'ID Combo', 'ID Forma de Pagamento', 'Preço', 'Custo']);
  [40,40,40,100,100].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('D2:E20000').setNumberFormat('R$ #,##0.00');
  aplicarZebraELinhas(sh, 5, 20000);
  sh.hideColumns(1, 3);
}

function criarPromocoes(ss) {
  let sh = ss.getSheetByName('Promoções') || ss.insertSheet('Promoções');
  sh.clear();
  sh.setTabColor(COR_DOURADO);
  formatarCabecalho(sh, ['Nome', 'Tipo', 'Regra de Duplicidade', 'Benefício', 'Ativa']);
  [170,150,260,240,80].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  const linhas = [
    ['Indicação de amigos', 'Indicação', 'O indicado só pode aparecer uma vez', '1 batata pequena para quem indicou', 'Sim'],
    ['Cartão Fidelidade', 'Fidelidade (carimbos)', 'Soma marca a cada venda com cliente associado', '1 porção de batata frita a cada 10 marcas', 'Sim']
  ];
  sh.getRange(2, 1, linhas.length, 5).setValues(linhas);
  const regraAtiva = SpreadsheetApp.newDataValidation().requireValueInList(['Sim', 'Não'], true).setAllowInvalid(false).build();
  sh.getRange('E2:E200').setDataValidation(regraAtiva);
  aplicarZebraELinhas(sh, 5, 200);
  sh.getRange(2, 1, linhas.length, 5).setBackground('#FFFFFF').setFontColor('#2A1E12');
}


function criarEstruturasNovosRecursos(ss) {
  // Cupons: estrutura independente da antiga tabela Promoções, preservando legado.
  let sh = ss.getSheetByName('Cupons') || ss.insertSheet('Cupons');
  if (sh.getLastRow() === 0) {
    formatarCabecalho(sh, ['ID','Código','Nome','Tipo','Valor','Frete Grátis','Data Início','Data Fim','Hora Início','Hora Fim','Limite Total','Limite/Cliente','Valor Mínimo','Ativa','Acumula','Criado Em','Criado Por']);
    sh.setFrozenRows(1); sh.setTabColor(COR_DOURADO);
  }
  let u = ss.getSheetByName('CuponsUsos') || ss.insertSheet('CuponsUsos');
  if (u.getLastRow() === 0) {
    formatarCabecalho(u, ['ID','Cupom ID','Código','Venda ID','Cliente ID','Telefone','Desconto','Frete Grátis','Data/Hora','Requisição']);
    u.setFrozenRows(1); u.setTabColor(COR_DOURADO);
  }
  let e = ss.getSheetByName('Eventos') || ss.insertSheet('Eventos');
  if (e.getLastRow() === 0) {
    formatarCabecalho(e, ['ID','Nome','Tipo','Data','Hora Início','Hora Fim','Local','Contratante','Telefone','Status','Valor Contratado','Valor Recebido','Valor a Receber','Custo Total','Resultado','Observações','Criado Em','Criado Por','Atualizado Em']);
    e.setFrozenRows(1); e.setTabColor('#8a5a1f');
  }
  let ec = ss.getSheetByName('EventosCustos') || ss.insertSheet('EventosCustos');
  if (ec.getLastRow() === 0) {
    formatarCabecalho(ec, ['ID','Evento ID','Descrição','Categoria','Valor','Data','Observação','Criado Em','Criado Por']);
    ec.setFrozenRows(1);
  }
  let er = ss.getSheetByName('EventosRecebimentos') || ss.insertSheet('EventosRecebimentos');
  if (er.getLastRow() === 0) {
    formatarCabecalho(er, ['ID','Evento ID','Valor','Forma Pagamento','Data','Observação','Criado Em','Criado Por','Requisição']);
    er.setFrozenRows(1);
  }
}

function criarIndicacoes(ss) {
  let sh = ss.getSheetByName('Indicações') || ss.insertSheet('Indicações');
  sh.clear();
  sh.setTabColor(COR_VERMELHO);
  formatarCabecalho(sh, ['Nome Indicador', 'Telefone Indicador', 'Nome Indicado', 'Telefone Indicado', 'Data', 'Status', 'Observações', 'ID Indicador', 'ID Indicado']);
  [160,140,160,140,100,110,200].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('B2:B1000').setNumberFormat('@');
  sh.getRange('D2:D1000').setNumberFormat('@');
  const regra = SpreadsheetApp.newDataValidation().requireValueInList(['Pendente', 'Resgatado'], true).setAllowInvalid(false).build();
  sh.getRange('F2:F1000').setDataValidation(regra);
  aplicarZebraELinhas(sh, 7, 1000);
  const regras = sh.getConditionalFormatRules();
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('Pendente').setBackground('#F6E6BF').setFontColor('#7A5A12').setRanges([sh.getRange('F2:F1000')]).build());
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('Resgatado').setBackground('#DCEBD3').setFontColor('#3D5F2F').setRanges([sh.getRange('F2:F1000')]).build());
  sh.setConditionalFormatRules(regras);
}

function criarFidelidade(ss) {
  let sh = ss.getSheetByName('Fidelidade') || ss.insertSheet('Fidelidade');
  sh.clear();
  sh.setTabColor(COR_ESCURO);
  formatarCabecalho(sh, ['Nome', 'Telefone', 'Carimbos (0-10)', 'Prêmios Resgatados', 'Última Atualização', 'Observações', 'ID Cliente']);
  [180,140,120,140,150,200].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('B2:B1000').setNumberFormat('@');
  const regraCarimbos = SpreadsheetApp.newDataValidation().requireNumberBetween(0, 10).setAllowInvalid(false).build();
  sh.getRange('C2:C1000').setDataValidation(regraCarimbos);
  aplicarZebraELinhas(sh, 6, 1000);
  const regras = sh.getConditionalFormatRules();
  regras.push(SpreadsheetApp.newConditionalFormatRule()
    .setGradientMaxpointWithValue(COR_DOURADO, SpreadsheetApp.InterpolationType.NUMBER, '10')
    .setGradientMinpointWithValue('#FBF3DF', SpreadsheetApp.InterpolationType.NUMBER, '0')
    .setRanges([sh.getRange('C2:C1000')]).build());
  sh.setConditionalFormatRules(regras);
}

function criarProdutos(ss) {
  let sh = ss.getSheetByName('Produtos') || ss.insertSheet('Produtos');
  sh.clear();
  sh.setTabColor('#6b4a24');
  formatarCabecalho(sh, ['ID', 'Nome', 'Descrição', 'Categoria', 'Ativo', 'FotoID', 'Destaque', 'EstoqueProprioIngredienteId', 'OrdemCardapio']);
  [40,200,220,140,70,220,80,220,100].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  const regraAtivo = SpreadsheetApp.newDataValidation().requireValueInList(['Sim','Não'], true).setAllowInvalid(false).build();
  sh.getRange('E2:E2000').setDataValidation(regraAtivo);
  sh.getRange('G2:G2000').setDataValidation(regraAtivo);
  aplicarZebraELinhas(sh, 9, 2000);
  sh.hideColumns(1, 1);
  sh.hideColumns(6, 1);
  sh.hideColumns(8, 1);
}

function criarProdutoIngredientes(ss) {
  let sh = ss.getSheetByName('ProdutoIngredientes') || ss.insertSheet('ProdutoIngredientes');
  sh.clear();
  sh.setTabColor('#4a3a20');
  formatarCabecalho(sh, ['ID', 'ID Produto', 'ID Ingrediente', 'Nome Ingrediente', 'Quantidade por Unidade']);
  [40,40,40,200,160].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  aplicarZebraELinhas(sh, 5, 6000);
  sh.hideColumns(1, 3);
}

function criarEstoque(ss) {
  let sh = ss.getSheetByName('Estoque') || ss.insertSheet('Estoque');
  sh.clear();
  sh.setTabColor('#3d5f2f');
  formatarCabecalho(sh, ['ID', 'Ingrediente', 'Quantidade', 'Quantidade Mínima', 'Unidade', 'Custo Unitário', 'Status']);
  [40,220,140,160,90,120,80].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  aplicarZebraELinhas(sh, 7, 2000);
  sh.hideColumns(1, 1);
  const regraUnidade = SpreadsheetApp.newDataValidation().requireValueInList(['un','g','kg','ml','l'], true).setAllowInvalid(false).build();
  sh.getRange('E2:E2000').setDataValidation(regraUnidade);
  sh.getRange('F2:F2000').setNumberFormat('R$ #,##0.00');
  const regraStatus = SpreadsheetApp.newDataValidation().requireValueInList(['Ativo','Inativo'], true).setAllowInvalid(false).build();
  sh.getRange('G2:G2000').setDataValidation(regraStatus);
  const regras = sh.getConditionalFormatRules();
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenFormulaSatisfied('=$C2<=$D2').setBackground('#F6C4BC').setFontColor('#7A1F16').setRanges([sh.getRange('A2:G2000')]).build());
  sh.setConditionalFormatRules(regras);
}
function criarMovimentacoesEstoque(ss) {
  let sh = ss.getSheetByName('MovimentaçõesEstoque') || ss.insertSheet('MovimentaçõesEstoque');
  sh.clear();
  sh.setTabColor('#3d5f2f');
  formatarCabecalho(sh, ['ID', 'Ingrediente', 'Tipo', 'Quantidade', 'Qtd. Antes', 'Qtd. Depois', 'Motivo/Referência', 'Usuário', 'Data']);
  [40,200,90,90,90,90,220,110,140].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('I2:I20000').setNumberFormat('dd/MM/yyyy HH:mm');
  const regraTipo = SpreadsheetApp.newDataValidation().requireValueInList(['Entrada','Venda','Saída','Perda','Ajuste','Inventário'], true).setAllowInvalid(false).build();
  sh.getRange('C2:C20000').setDataValidation(regraTipo);
  aplicarZebraELinhas(sh, 9, 20000);
  sh.hideColumns(1, 1);
}
function criarContingenciaReconciliada(ss) {
  let sh = ss.getSheetByName('ContingenciaReconciliada') || ss.insertSheet('ContingenciaReconciliada');
  sh.clear();
  sh.setTabColor('#7a1f16');
  formatarCabecalho(sh, ['ID da Fila (contingência)', 'ID da Venda (aqui)', 'Reconciliado em']);
  [220,220,150].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('C2:C20000').setNumberFormat('dd/MM/yyyy HH:mm');
  aplicarZebraELinhas(sh, 3, 20000);
}

function criarCategorias(ss) {
  let sh = ss.getSheetByName('Categorias') || ss.insertSheet('Categorias');
  sh.clear();
  sh.setTabColor(COR_DOURADO);
  formatarCabecalho(sh, ['ID', 'Nome', 'Ativa', 'Ordem']);
  [40,200,80,70].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  const regraAtiva = SpreadsheetApp.newDataValidation().requireValueInList(['Sim', 'Não'], true).setAllowInvalid(false).build();
  sh.getRange('C2:C300').setDataValidation(regraAtiva);
  aplicarZebraELinhas(sh, 4, 300);
  sh.hideColumns(1, 1);
}
function criarAdicionais(ss) {
  let sh = ss.getSheetByName('Adicionais') || ss.insertSheet('Adicionais');
  sh.clear();
  sh.setTabColor('#c98a2f');
  formatarCabecalho(sh, ['ID', 'Nome', 'Preço', 'Ativo', 'ID Ingrediente (baixa de estoque)', 'Quantidade a descontar']);
  [40,200,100,70,220,150].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('C2:C2000').setNumberFormat('R$ #,##0.00');
  const regraAtivo = SpreadsheetApp.newDataValidation().requireValueInList(['Sim','Não'], true).setAllowInvalid(false).build();
  sh.getRange('D2:D2000').setDataValidation(regraAtivo);
  aplicarZebraELinhas(sh, 6, 2000);
  sh.hideColumns(1, 1);
}
function criarProdutoAdicionais(ss) {
  let sh = ss.getSheetByName('ProdutoAdicionais') || ss.insertSheet('ProdutoAdicionais');
  sh.clear();
  sh.setTabColor('#c98a2f');
  formatarCabecalho(sh, ['ID', 'ID Produto', 'ID Adicional']);
  [40,40,40].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  aplicarZebraELinhas(sh, 3, 20000);
  sh.hideColumns(1, 3);
}
function criarFeedbacks(ss) {
  let sh = ss.getSheetByName('Feedbacks') || ss.insertSheet('Feedbacks');
  sh.clear();
  sh.setTabColor('#5f8f4e');
  formatarCabecalho(sh, ['ID', 'ID Venda', 'Telefone Cliente', 'Nota', 'Comentário', 'Data', 'Status', 'ID Cliente']);
  [40,40,140,60,300,140,100].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  aplicarZebraELinhas(sh, 7, 5000);
  sh.hideColumns(1, 1);
}
function criarComboItens(ss) {
  let sh = ss.getSheetByName('ComboItens') || ss.insertSheet('ComboItens');
  sh.clear();
  sh.setTabColor('#8a5a1f');
  formatarCabecalho(sh, ['ID', 'ID Combo', 'ID Produto', 'Quantidade']);
  [40,40,40,100].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  aplicarZebraELinhas(sh, 4, 5000);
  sh.hideColumns(1, 3);
}
function criarCombos(ss) {
  let sh = ss.getSheetByName('Combos') || ss.insertSheet('Combos');
  sh.clear();
  sh.setTabColor('#8a5a1f');
  formatarCabecalho(sh, ['ID', 'Nome do Combo', 'Categoria', 'Ativo', 'FotoID', 'Destaque', 'OrdemCardapio']);
  [40,200,140,70,220,80,100].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  const regraAtivo = SpreadsheetApp.newDataValidation().requireValueInList(['Sim','Não'], true).setAllowInvalid(false).build();
  sh.getRange('D2:D2000').setDataValidation(regraAtivo);
  sh.getRange('F2:F2000').setDataValidation(regraAtivo);
  aplicarZebraELinhas(sh, 7, 2000);
  sh.hideColumns(1, 1);
  sh.hideColumns(5, 1);
}

function criarVendas(ss) {
  let sh = ss.getSheetByName('Vendas') || ss.insertSheet('Vendas');
  sh.clear();
  sh.setTabColor('#3d5f2f');
  formatarCabecalho(sh, ['ID', 'Data/Hora', 'Cliente', 'Telefone Cliente', 'Forma de Pagamento', 'Valor Total', 'Custo Total', 'Status', 'Motivo Cancelamento', 'Tipo', 'Status Pedido', 'Endereço', 'Complemento', 'Referência', 'Observações Entrega', 'Data/Hora Pronta', 'Data/Hora Concluída', 'Status Pagamento', 'Data/Hora Recebimento', 'Valor Original', 'Valor Desconto', 'Desconto Detalhe', 'Entregador', 'Data/Hora Saiu', 'Origem', 'ID da Mesa', 'Taxa Entrega', 'Fechamento Entrega', 'Registrado Por', 'Nº Pedido', 'Início Preparo']);
  [40,140,180,140,170,120,120,110,220,90,140,220,140,180,220,150,150,120,150,120,120,180,160,150,120,120,110,150,130,90,150].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('B2:B8000').setNumberFormat('dd/MM/yyyy HH:mm');
  sh.getRange('D2:D8000').setNumberFormat('@'); // Telefone Cliente como Texto
  sh.getRange('P2:Q8000').setNumberFormat('dd/MM/yyyy HH:mm');
  sh.getRange('S2:S8000').setNumberFormat('dd/MM/yyyy HH:mm');
  sh.getRange('F2:G8000').setNumberFormat('R$ #,##0.00');
  sh.getRange('T2:U8000').setNumberFormat('R$ #,##0.00');
  const regraStatus = SpreadsheetApp.newDataValidation().requireValueInList(['Confirmada','Cancelada'], true).setAllowInvalid(false).build();
  sh.getRange('H2:H8000').setDataValidation(regraStatus);
  const regraTipo = SpreadsheetApp.newDataValidation().requireValueInList(['Retirada','Entrega','Mesa'], true).setAllowInvalid(false).build();
  sh.getRange('J2:J8000').setDataValidation(regraTipo);
  const regraStatusPedido = SpreadsheetApp.newDataValidation().requireValueInList(['Recebido','Em preparo','Pronta','Saiu para entrega','Entregue','Retirada','Servida'], true).setAllowInvalid(false).build();
  sh.getRange('K2:K8000').setDataValidation(regraStatusPedido);
  const regraStatusPagamento = SpreadsheetApp.newDataValidation().requireValueInList(['Pago','A Receber'], true).setAllowInvalid(false).build();
  sh.getRange('R2:R8000').setDataValidation(regraStatusPagamento);
  sh.getRange('X2:X8000').setNumberFormat('dd/MM/yyyy HH:mm');
  const regraOrigem = SpreadsheetApp.newDataValidation().requireValueInList(['Balcão','Cardápio','Garçom'], true).setAllowInvalid(false).build();
  sh.getRange('Y2:Y8000').setDataValidation(regraOrigem);
  sh.getRange('AA2:AA8000').setNumberFormat('R$ #,##0.00');
  aplicarZebraELinhas(sh, 29, 8000);
  sh.hideColumns(1, 1);
  sh.hideColumns(26, 1);
  sh.hideColumns(28, 1);
  const regras = sh.getConditionalFormatRules();
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('Cancelada').setBackground('#F6C4BC').setFontColor('#7A1F16').setRanges([sh.getRange('H2:H8000')]).build());
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('Confirmada').setBackground('#DCEBD3').setFontColor('#3D5F2F').setRanges([sh.getRange('H2:H8000')]).build());
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('A Receber').setBackground('#F6E3BC').setFontColor('#7A5A16').setRanges([sh.getRange('R2:R8000')]).build());
  sh.setConditionalFormatRules(regras);
}
function criarMesas(ss) {
  let sh = ss.getSheetByName('Mesas') || ss.insertSheet('Mesas');
  sh.clear();
  sh.setTabColor('#6b4a24');
  formatarCabecalho(sh, ['ID', 'Número', 'Status', 'Capacidade', 'Observação', 'Garçom Responsável']);
  [40,90,170,100,220,160].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  const regraStatus = SpreadsheetApp.newDataValidation().requireValueInList(['Livre','Ocupada','Aguardando fechamento','Fechada','Bloqueada/Manutenção'], true).setAllowInvalid(false).build();
  sh.getRange('C2:C300').setDataValidation(regraStatus);
  aplicarZebraELinhas(sh, 5, 300);
  sh.hideColumns(1, 1);
  const regras = sh.getConditionalFormatRules();
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('Livre').setBackground('#DCEBD3').setFontColor('#3D5F2F').setRanges([sh.getRange('C2:C300')]).build());
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('Ocupada').setBackground('#F6E3BC').setFontColor('#7A5A16').setRanges([sh.getRange('C2:C300')]).build());
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('Bloqueada/Manutenção').setBackground('#F6C4BC').setFontColor('#7A1F16').setRanges([sh.getRange('C2:C300')]).build());
  sh.setConditionalFormatRules(regras);
}

function criarItensVenda(ss) {
  let sh = ss.getSheetByName('ItensVenda') || ss.insertSheet('ItensVenda');
  sh.clear();
  sh.setTabColor('#2d4a22');
  formatarCabecalho(sh, ['ID', 'ID da Venda', 'ID Produto', 'ID Combo', 'Descrição', 'Quantidade', 'Valor Unitário', 'Custo Unitário', 'Valor Total do Item', 'Adicionais (IDs)']);
  [40,40,40,40,220,90,120,120,140,160].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('G2:I20000').setNumberFormat('R$ #,##0.00');
  aplicarZebraELinhas(sh, 10, 20000);
  sh.hideColumns(1, 4);
  sh.hideColumns(10, 1);
}

function criarPagamentosVenda(ss) {
  let sh = ss.getSheetByName('PagamentosVenda') || ss.insertSheet('PagamentosVenda');
  sh.clear();
  sh.setTabColor('#2d4a22');
  if (sh.getMaxColumns() < 5) sh.insertColumnsAfter(sh.getMaxColumns(), 5 - sh.getMaxColumns());
  formatarCabecalho(sh, ['ID', 'ID da Venda', 'Forma de Pagamento', 'Valor', 'Taxa Aplicada']);
  [40,40,160,120,110].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('D2:E20000').setNumberFormat('R$ #,##0.00');
  aplicarZebraELinhas(sh, 5, 20000);
  sh.hideColumns(1, 2);
}

function criarDespesas(ss) {
  let sh = ss.getSheetByName('Despesas') || ss.insertSheet('Despesas');
  sh.clear();
  sh.setTabColor('#7c1a15');
  if (sh.getMaxColumns() < 14) sh.insertColumnsAfter(sh.getMaxColumns(), 14 - sh.getMaxColumns());
  formatarCabecalho(sh, ['ID', 'Data/Hora', 'Descrição', 'Valor', 'Observação', 'Status', 'Motivo Cancelamento'].concat(CABECALHO_DESPESAS_EXTRA));
  [40,140,220,120,200,110,220,130,100,90,90,100,100,140].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('B2:B8000').setNumberFormat('dd/MM/yyyy HH:mm');
  sh.getRange('D2:D8000').setNumberFormat('R$ #,##0.00');
  sh.getRange('I2:I8000').setNumberFormat('@');
  sh.getRange('L2:L8000').setNumberFormat('@');
  sh.getRange('N2:N8000').setNumberFormat('dd/MM/yyyy HH:mm');
  const regraStatus = SpreadsheetApp.newDataValidation().requireValueInList(['Confirmada','Cancelada'], true).setAllowInvalid(false).build();
  sh.getRange('F2:F8000').setDataValidation(regraStatus);
  sh.getRange('J2:J8000').setDataValidation(SpreadsheetApp.newDataValidation().requireValueInList(['Paga', 'A pagar'], true).setAllowInvalid(false).build());
  sh.getRange('M2:M8000').setDataValidation(SpreadsheetApp.newDataValidation().requireValueInList(['Sim', 'Não'], true).setAllowInvalid(false).build());
  aplicarZebraELinhas(sh, 14, 8000);
  sh.hideColumns(1, 1);
  sh.hideColumns(11, 1);
  const regras = sh.getConditionalFormatRules();
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('Cancelada').setBackground('#F6C4BC').setFontColor('#7A1F16').setRanges([sh.getRange('F2:F8000')]).build());
  regras.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo('A pagar').setBackground('#F6E3BC').setFontColor('#7A5A16').setRanges([sh.getRange('J2:J8000')]).build());
  sh.setConditionalFormatRules(regras);
}

function criarSangrias(ss) {
  let sh = ss.getSheetByName('Sangrias') || ss.insertSheet('Sangrias');
  sh.clear();
  sh.setTabColor('#7c1a15');
  formatarCabecalho(sh, ['ID', 'Data/Hora', 'Valor', 'Motivo', 'Usuário']);
  [40,140,120,260,140].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('B2:B8000').setNumberFormat('dd/MM/yyyy HH:mm');
  sh.getRange('C2:C8000').setNumberFormat('R$ #,##0.00');
  aplicarZebraELinhas(sh, 5, 8000);
  sh.hideColumns(1, 1);
}

/* ---------- FASE 7 — ENTREGAS: estruturas (ITENS 53, 54) ----------
   FechamentosEntrega = 1 linha por entregador/dia fechado (resumo congelado).
   EntregasFechadas   = 1 linha por entrega incluída num fechamento (foto da taxa
   no momento do fechamento — mudar a taxa depois não altera período fechado). */
const CABECALHO_FECHAMENTOS_ENTREGA = ['ID', 'Data Ref', 'Entregador', 'Qtd Entregas', 'Total Taxas', 'Ajuda Diária', 'Total Devido', 'Valor Pago', 'Diferença', 'Fechado em', 'Fechado por', 'Observação', 'ID Requisição'];
const CABECALHO_ENTREGAS_FECHADAS = ['ID', 'Fechamento ID', 'Venda ID', 'Data Ref', 'Entregador', 'Taxa'];
function criarFechamentosEntrega(ss) {
  let sh = ss.getSheetByName('FechamentosEntrega') || ss.insertSheet('FechamentosEntrega');
  sh.clear();
  sh.setTabColor('#2f5f5f');
  formatarCabecalho(sh, CABECALHO_FECHAMENTOS_ENTREGA);
  [40,100,140,90,110,110,110,110,110,150,140,220,140].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('B2:B5000').setNumberFormat('@');
  sh.getRange('E2:I5000').setNumberFormat('R$ #,##0.00');
  sh.getRange('J2:J5000').setNumberFormat('dd/MM/yyyy HH:mm');
  aplicarZebraELinhas(sh, 13, 5000);
  sh.hideColumns(1, 1);
  sh.hideColumns(13, 1);
}
function criarEntregasFechadas(ss) {
  let sh = ss.getSheetByName('EntregasFechadas') || ss.insertSheet('EntregasFechadas');
  sh.clear();
  sh.setTabColor('#2f5f5f');
  formatarCabecalho(sh, CABECALHO_ENTREGAS_FECHADAS);
  [40,100,100,100,140,110].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('D2:D20000').setNumberFormat('@');
  sh.getRange('F2:F20000').setNumberFormat('R$ #,##0.00');
  aplicarZebraELinhas(sh, 6, 20000);
  sh.hideColumns(1, 1);
}
/* Roda uma vez numa planilha JÁ existente (sem apagar nada): cria as abas novas e as
   colunas novas de Vendas. Em planilha nova, criarPlanilhaTexasBurger() já faz isso. */
/* FASE 12 — RELATÓRIOS: a aba Vendas ganha a coluna 29 "Registrado Por" (login de quem lançou a venda: operador ou garçom;
   vazio para pedidos do Cardápio Digital). É o que permite os relatórios por operador e por garçom (ITENS 83 e 87).
   Rode UMA vez se a planilha já existir (criarPlanilhaTexasBurger já cria a coluna sozinha). Vendas antigas ficam "sem registro". */
function criarConfiguracoes(ss) {
  let sh = ss.getSheetByName('Configurações') || ss.insertSheet('Configurações');
  sh.clear();
  sh.setTabColor('#5a5a5a');
  formatarCabecalho(sh, ['Chave', 'Valor']);
  sh.setColumnWidth(1, 180);
  sh.setColumnWidth(2, 160);
  sh.getRange(2, 1, 2, 2).setValues([['MetaMensal', 0], ['MetaDiaria', 0]]);
  aplicarZebraELinhas(sh, 2, 50);
}

function criarCaixaSessoes(ss) {
  let sh = ss.getSheetByName('Caixa') || ss.insertSheet('Caixa');
  sh.clear();
  sh.setTabColor('#e8b23d');
  if (sh.getMaxColumns() < 12) sh.insertColumnsAfter(sh.getMaxColumns(), 12 - sh.getMaxColumns());
  formatarCabecalho(sh, ['ID', 'Abertura', 'Fundo de Caixa', 'Fechamento', 'Total Vendas', 'Total Despesas', 'Saldo Final', 'Status', 'Usuário Abertura', 'Usuário Fechamento', 'Valor Contado', 'Diferença']);
  [40,140,120,140,120,120,120,100,130,130,120,110].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('K2:L2000').setNumberFormat('R$ #,##0.00');
  sh.getRange('B2:B2000').setNumberFormat('dd/MM/yyyy HH:mm');
  sh.getRange('D2:D2000').setNumberFormat('dd/MM/yyyy HH:mm');
  sh.getRange('C2:C2000').setNumberFormat('R$ #,##0.00');
  sh.getRange('E2:G2000').setNumberFormat('R$ #,##0.00');
  const regraStatus = SpreadsheetApp.newDataValidation().requireValueInList(['Aberto','Fechado'], true).setAllowInvalid(false).build();
  sh.getRange('H2:H2000').setDataValidation(regraStatus);
  aplicarZebraELinhas(sh, 12, 2000);
  sh.hideColumns(1, 1);
}

function criarLog(ss) {
  let sh = ss.getSheetByName('Log') || ss.insertSheet('Log');
  sh.clear();
  sh.setTabColor('#5a5a5a');
  formatarCabecalho(sh, ['Data/Hora', 'Ação', 'Telefone', 'Detalhes', 'Usuário']);
  [140,200,140,320,120].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  aplicarZebraELinhas(sh, 5, 10000);
}

function formatarCabecalho(sh, colunas) {
  const range = sh.getRange(1, 1, 1, colunas.length);
  range.setValues([colunas]);
  range.setBackground(COR_VERMELHO).setFontColor(COR_CREME).setFontWeight('bold').setFontSize(11).setHorizontalAlignment('center').setVerticalAlignment('middle');
  sh.setRowHeight(1, 34);
  sh.setFrozenRows(1);
}

function aplicarZebraELinhas(sh, numColunas, numLinhas) {
  const range = sh.getRange(2, 1, (numLinhas || 999) - 1, numColunas);
  range.setBackground('#FFFFFF').setFontColor('#2A1E12').setFontSize(11);
  range.setBorder(true, true, true, true, true, true, COR_LINHA, SpreadsheetApp.BorderStyle.SOLID);
}

/* =========================================================
   PARTE 2 — API (WEB APP)
   ========================================================= */
/* doGet fica público (qualquer pessoa pode acessar a URL /exec pelo navegador), então
   NUNCA deve devolver getAllData() — isso exporia senhas de usuários, clientes, vendas
   e financeiro para qualquer visitante. Só retorna os dados seguros do Cardápio público. */
/* CORREÇÃO (Módulo 2): acha a linha de um ID lendo a coluna A UMA vez (antes: uma leitura por linha, com a trava global
   segurada — o sistema ficava lento e podia dar "ocupado" quando o histórico crescia). Devolve 0 se não achar. */
function linhaDoId_(sh, id) {
  const last = sh.getLastRow();
  if (last < 2 || id === undefined || id === null || id === '') return 0;
  const col = sh.getRange(2, 1, last - 1, 1).getValues();
  for (let k = 0; k < col.length; k++) if (col[k][0] === id) return k + 2;
  return 0;
}
/* SEGURANÇA (Módulo 3): texto que começa com "=" ou "@" vira FÓRMULA ao gravar na planilha (ex.: =IMPORTDATA(...) poderia
   enviar dados para fora). Aqui todo texto recebido é neutralizado ANTES de qualquer ação, inclusive nos cadastros feitos por
   funcionários. Senhas, login, token e imagem ficam de fora (não podem ser alterados). */
const CHAVES_SEM_SANITIZAR_ = { senha: 1, senhaAtual: 1, novaSenha: 1, senhaAdmin: 1, senhaAdminConfirmacao: 1, token: 1, base64Data: 1, login: 1, novoLogin: 1, loginAlvo: 1, chave: 1 };
/* Módulo 4: texto que começa com + ou - também pode virar fórmula (no Sheets, ou ao abrir um CSV/Excel exportado).
   Para não estragar o que é comum no dia a dia, só é neutralizado quando PARECE fórmula: tem chamada de função (NOME(...)),
   "|" ou "!". Ficam como estão: números ("-5,50"), telefones ("+55 (11) 99999-9999") e texto comum ("- sem cebola", "+ bacon").
   "=", "@", tabulação e retorno de carro no início continuam sempre neutralizados. */
function pareceFormulaPorSinal_(v) {
  if (/^[+-][\d\s().,-]*$/.test(v)) return false;
  return /[A-Za-z_][\w.]*\s*\(|[|!\\]/.test(v);
}
function sanitizarEntrada_(v, chave, prof) {
  if (prof > 8) return v;
  if (typeof v === 'string') {
    if (chave && CHAVES_SEM_SANITIZAR_[chave]) return v;
    const c = v.charAt(0);
    return (c === '=' || c === '@' || c === '\t' || c === '\r' || ((c === '+' || c === '-') && pareceFormulaPorSinal_(v))) ? "'" + v : v;
  }
  if (Array.isArray(v)) return v.map(x => sanitizarEntrada_(x, chave, prof + 1));
  if (v && typeof v === 'object') { const o = {}; Object.keys(v).forEach(k => { o[k] = sanitizarEntrada_(v[k], k, prof + 1); }); return o; }
  return v;
}
/* ITEM 18 — cardápio por GET. Se o celular já tem a mesma versão (?v=...), responde só "igual" (poucos bytes). */
function doGet(e) {
  if (e && e.parameter && e.parameter.ping) return responder({ ok: true, servico: 'Texas Burger - Planilha principal', manutencao: manutencaoAtiva_() }); // ping leve do popup de conexão (não lê o cardápio)
  if (manutencaoAtiva_()) return responder({ ok: false, manutencao: true }); // ITEM 2.8: não lê o cardápio com a planilha sendo reescrita (o app cai no cache local)
  const dados = getCardapioPublico();
  const v = versaoCardapio_(dados);
  if (e && e.parameter && e.parameter.v === v) return responder({ ok: true, igual: true, versao: v });
  return responder(Object.assign({}, dados, { versao: v }));
}

/* ITEM 17 — leituras leves que NÃO entram na fila única (lock) do doPost: não escrevem nada e não esperam as gravações. */
const ACOES_LEITURA_SEM_FILA_ = ['getVersoes', 'getStatusPedidoPublico', 'getMesaPublica', 'detectarNovosPedidos'];

/* ITEM 19 — versões dos dados. O painel (Admin/Operador) pergunta "mudou algo?" (barato, sem ler planilha) e só baixa o que mudou.
   cad = cadastro (produtos, preços, combos, adicionais, formas de pagamento, configurações); din = todo o resto.
   REGRA DE SEGURANÇA: toda ação que não esteja na lista de "só leitura" troca a versão din; e toda ação que não esteja na lista
   "só dinâmicas" troca também a versão cad. Ação nova/esquecida => troca as duas (na dúvida, baixa tudo). */
const ACOES_SEM_ALTERACAO_ = ['getAll', 'getVersoes', 'getDadosGrupo', 'detectarNovosPedidos', 'conferirIntegridade', 'getCardapio', 'obterStatusBackup',
  'obterArmazenamento', 'obterArmazenamentoContingencia', 'getStatusPedidoPublico', 'getMesaPublica', 'validarCupomCardapio', 'obterChaveContingencia', 'verificarSenhaAdmin', 'simularPrecificacao', 'listarSessoes'];
const ACOES_SO_DINAMICAS_ = ['autenticar', 'encerrarSessao', 'encerrarSessaoRemota', 'iniciarVenda', 'criarPedidoCardapio', 'criarPedidoMesa', 'cancelarPedidoMesa', 'cancelarPedidoCardapioPublico', 'pedirContaMesa',
  'chamarGarcomMesa', 'avancarStatusPedido', 'iniciarPreparoPedido', 'atribuirEntregador', 'confirmarRecebimentoPedido', 'editarVenda', 'cancelarVenda',
  'aceitarPedido', 'rejeitarPedido', 'suspenderPedido', 'retomarPedido', 'abrirCaixa', 'fecharCaixa', 'editarStatusMesa', 'fecharContaMesa', 'addSangria',
  'addDespesa', 'pagarDespesa', 'salvarCliente', 'addOrStampFidelidade', 'resgatarPremioFidelidade', 'toggleResgateIndicacao', 'indicarNovoCliente',
  'addFeedback', 'editarStatusFeedback', 'registrarOcorrencia', 'atualizarOcorrencia', 'registrarEntradaEstoque', 'registrarPerdaEstoque', 'registrarInventarioEstoque'];
function novaVersao_() { return Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36); }
function versoesAtuais_() {
  const c = CacheService.getScriptCache();
  let cad = c.get('ver_cad'), din = c.get('ver_din');
  if (!cad) { cad = novaVersao_(); c.put('ver_cad', cad, 21600); }  // cache esvaziado = versão nova = todo mundo baixa de novo (lado seguro)
  if (!din) { din = novaVersao_(); c.put('ver_din', din, 21600); }
  return { cad: cad, din: din };
}
function bumpVersoes_(action) {
  try {
    const p = { ver_din: novaVersao_() };
    if (ACOES_SO_DINAMICAS_.indexOf(action) === -1) p.ver_cad = novaVersao_();
    CacheService.getScriptCache().putAll(p, 21600);
  } catch (e) { /* se falhar, o painel ainda baixa tudo a cada 15 min (rede de segurança no app) */ }
}

/* ITEM 2.8 — MODO MANUTENÇÃO durante a restauração de backup.
   A flag fica em PropertiesService (e NÃO na aba Configurações): a restauração sobrescreve a própria aba Configurações, o que
   apagaria a flag no meio do processo. TTL de 30 min: se o Apps Script morrer no meio (timeout), a flag expira sozinha e vira log.
   A checagem roda ANTES de pegar o lock da fila — é isso que evita os operadores ficarem tentando e recebendo "ocupado". */
const MANUTENCAO_PROP_ = 'MODO_MANUTENCAO';
const MANUTENCAO_TTL_MS_ = 30 * 60 * 1000;
function manutencaoAtiva_() {
  try {
    const props = PropertiesService.getScriptProperties(), raw = props.getProperty(MANUTENCAO_PROP_);
    if (!raw) return null;
    const m = JSON.parse(raw);
    if (!m || !m.ts || Date.now() - m.ts > MANUTENCAO_TTL_MS_) {
      props.deleteProperty(MANUTENCAO_PROP_);
      try { registrarLog('Modo manutenção expirou sozinho (limite de 30 min)', '', 'Motivo original: ' + ((m && m.motivo) || '?') + ' | iniciado por ' + ((m && m.por) || '?')); } catch (e2) {}
      return null;
    }
    return m;
  } catch (e) { return null; }
}
function ligarManutencao_(motivo) {
  PropertiesService.getScriptProperties().setProperty(MANUTENCAO_PROP_, JSON.stringify({ ts: Date.now(), motivo: String(motivo || ''), por: USUARIO_ATUAL || '' }));
}
function desligarManutencao_() { try { PropertiesService.getScriptProperties().deleteProperty(MANUTENCAO_PROP_); } catch (e) {} }
/* Só olha o cache (sem ler planilha, que pode estar sendo reescrita): a sessão é de Admin? A validação completa continua acontecendo depois. */
function ehAdminPeloCache_(token) {
  try { const raw = token ? CacheService.getScriptCache().get('sess_' + token) : ''; return !!raw && JSON.parse(raw).nivel === 'Admin'; } catch (e) { return false; }
}

function doPost(e) {
  let body;
  try { body = JSON.parse(e.postData.contents); } catch (err) { return responder({ ok: false, message: 'Requisição inválida.' }); }
  if (!body || typeof body !== 'object' || Array.isArray(body) || typeof body.action !== 'string') return responder({ ok: false, message: 'Requisição inválida.' });
  const action = body.action;
  body = sanitizarEntrada_(body, '', 0);
  USUARIO_ATUAL = ''; NIVEL_ATUAL = ''; AUTORIZADOR_ATUAL = ''; APARELHO_ATUAL = '';
  { // ITEM 2.8: em manutenção, todo mundo (inclusive o cardápio público) recebe aviso na hora; só Admin passa.
    const manut = manutencaoAtiva_();
    if (manut && !ehAdminPeloCache_(body.token)) return responder({ ok: false, manutencao: true, desde: manut.ts, message: 'Sistema em manutenção — aguarde alguns minutos. Nada foi perdido.' });
  }
  let resultado;
  const lock = LockService.getScriptLock();
  /* FASE 11 (ITEM 80): todas as operações passam por este lock, então duas ações simultâneas são
     processadas uma de cada vez. Se a fila estiver cheia, avisa "ocupado" SEM ter feito nada —
     o app pode repetir com segurança. */
  const semFila = ACOES_LEITURA_SEM_FILA_.indexOf(action) !== -1; // ITEM 17
  let temLock = false;
  if (!semFila) {
    try { lock.waitLock(20000); temLock = true; } catch (err) { return responder({ ok: false, ocupado: true, message: 'O sistema está ocupado. Tente novamente em alguns segundos.' }); }
  }
  let chaveIdem = '';
  try {
    if (ACOES_PUBLICAS.indexOf(action) === -1) {
      const sessao = validarSessao_(body.token);
      if (!sessao) return responder({ ok: false, message: 'Sessão expirada. Faça login novamente.', sessaoExpirada: true });
      USUARIO_ATUAL = sessao.login; NIVEL_ATUAL = sessao.nivel;
      APARELHO_ATUAL = sessao.deviceId ? ('aparelho ' + String(sessao.deviceId).slice(0, 8) + (sessao.ua ? ' · ' + String(sessao.ua).slice(0, 60) : '')) : '';
      if (!checarPermissao_(action, NIVEL_ATUAL)) {
        registrarLog('Tentativa de acesso negado', USUARIO_ATUAL, 'Ação: ' + action + ' | Nível: ' + NIVEL_ATUAL + (APARELHO_ATUAL ? ' | ' + APARELHO_ATUAL : ''));
        return responder({ ok: false, message: 'Seu perfil não tem permissão para esta ação.' });
      }
    }
    /* FASE 11 (ITEM 79): idempotência DURÁVEL (aba Requisicoes, sobrevive ao cache). A mesma requisição
       repetida (duplo toque, retry, internet voltando) nunca executa a operação duas vezes. */
    if (body.requisicaoId && ACOES_IDEMPOTENTES.indexOf(action) !== -1) {
      chaveIdem = action + ':' + String(body.requisicaoId).slice(0, 80);
      const previa = requisicaoBuscar_(chaveIdem);
      if (previa) {
        const dup = { ok: true, duplicado: true, id: previa.resultado, message: 'Operação já registrada anteriormente — repetição ignorada.' };
        try { // devolve também o Nº do pedido (antes vinha 0 quando o cliente reenviava depois de uma queda de internet)
          const shV = ss_().getSheetByName('Vendas'), lin = shV ? linhaDoId_(shV, previa.resultado) : 0;
          if (lin && shV.getMaxColumns() >= 30) { const n = numPlanilha_(shV.getRange(lin, 30).getValue()) || 0; if (n) dup.numero = n; }
        } catch (eNum) {}
        return responder(dup);
      }
    }
    const msgConflito = conflitoDeVersao_(action, body);
    if (msgConflito) {
      registrarLog('Edição recusada por conflito de versão', '', action + ' | ' + String(body.id || body.loginAlvo).slice(0, 40));
      return responder({ ok: false, conflito: true, message: msgConflito });
    }
    switch (action) {
      case 'getAll': resultado = getAllData(); break;
      case 'getVersoes': resultado = Object.assign({ ok: true }, versoesAtuais_()); break;
      case 'getDadosGrupo': resultado = getAllData(body.grupo === 'cad' ? 'cad' : 'din'); break;
      case 'conferirIntegridade': resultado = conferirIntegridade(); break;
      case 'getCardapio': resultado = getCardapioPublico(); break;
      case 'obterStatusBackup': resultado = obterStatusBackup(); break;
      case 'configurarBackupAutomatico': resultado = configurarBackupAutomaticoApp(body.ativo, body.frequencia, body.hora); break;
      case 'obterArmazenamento': resultado = obterArmazenamento(); break;
      case 'obterArmazenamentoContingencia': resultado = obterArmazenamentoContingencia(); break;
      case 'restaurarBackup': resultado = restaurarBackup(body.backupId, body.senhaAdmin, body.confirmacao); break;
      case 'fazerBackupAgora':
        if (!exigeConfirmacaoAdmin(body.senhaAdminConfirmacao)) { resultado = { ok: false, message: 'Senha de administrador incorreta.' }; }
        else { resultado = fazerBackupManual_(); }
        break;

      case 'autenticar': resultado = autenticar(body.login, body.senha, body.deviceId, body.ua); break;
      case 'listarSessoes': resultado = listarSessoes(body.token); break;
      case 'encerrarSessaoRemota': resultado = encerrarSessaoRemota(body.sessaoId, body.token); break;
      case 'encerrarSessao': resultado = encerrarSessao(body.token); break;
      case 'trocarMinhaSenha': resultado = trocarMinhaSenha(body.senhaAtual, body.novaSenha, body.token); break;
      case 'criarUsuario': resultado = criarUsuario(body.novoLogin, body.novaSenha, body.nivel, body.senhaAdminConfirmacao, body.nome, body.telefone); break;
      case 'editarUsuario': resultado = editarUsuario(body.loginAlvo, body.novaSenha, body.novoNivel, body.novoAtivo, body.senhaAdminConfirmacao, body.nome, body.telefone); break;
      case 'excluirUsuario': resultado = excluirUsuario(body.loginAlvo, body.senhaAdminConfirmacao); break;

      case 'salvarCliente': resultado = salvarCliente(body.id, body.nome, body.telefone, body.dataNascimento, body.endereco, body.comoConheceu, body.observacao); break;
      case 'excluirCliente': resultado = excluirCliente(body.id, body.senhaAdminConfirmacao); break;
      case 'indicarNovoCliente': resultado = indicarNovoCliente(body.telIndicador, body.nomeIndicador, body.nome, body.telefone, body.dataNascimento, body.endereco, body.comoConheceu, body.observacao); break;

      case 'toggleResgateIndicacao': resultado = toggleResgateIndicacao(body.telIndicado); break;
      case 'addOrStampFidelidade': resultado = addOrStampFidelidade(body.telefone, body.nome, body.observacao); break;
      case 'resgatarPremioFidelidade': resultado = resgatarPremioFidelidade(body.telefone); break;

      case 'addFormaPagamento': resultado = addFormaPagamento(body.nome, body.taxaPct, body.taxaFixa, body.prazoDias, body.permiteTroco); break;
      case 'editarFormaPagamento': resultado = editarFormaPagamento(body.id, body.novoNome, body.novoAtivo, body.novoVisivelCardapio, body.novaTaxaPct, body.novaTaxaFixa, body.novoPrazoDias, body.novoPermiteTroco, body.novaOrdem); break;

      case 'addCategoria': resultado = addCategoria(body.nome); break;
      case 'editarCategoria': resultado = editarCategoria(body.id, body.novoNome, body.novoAtivo, body.novaOrdem); break;
      case 'excluirCategoria': resultado = excluirCategoria(body.id); break;

      case 'addProduto': resultado = addProduto(body.nome, body.descricao, body.categoria, body.precoBase, body.custoBase, body.precos, body.ingredientes, body.destaque, body.adicionaisIds, body.estoqueProprio); break;
      case 'editarProduto': resultado = editarProduto(body.id, body.nome, body.descricao, body.categoria, body.ativo, body.precos, body.ingredientes, body.destaque, body.adicionaisIds, body.estoqueProprio); break;
      case 'excluirProduto': resultado = excluirProduto(body.id); break;
      case 'uploadFotoProduto': resultado = uploadFotoProduto(body.produtoId, body.nomeBase, body.base64Data, body.mimeType); break;
      case 'excluirFotoProduto': resultado = excluirFotoProduto(body.produtoId); break;

      case 'addAdicional': resultado = addAdicional(body.nome, body.preco, body.ingredienteId, body.quantidadeDesconto); break;
      case 'editarVisibilidadeCardapioProduto': resultado = editarVisibilidadeCardapioProduto(body.id, body.ativo, body.destaque); break;
      case 'editarOrdemCardapioProduto': resultado = editarOrdemCardapioProduto(body.id, body.ordem); break;
      case 'editarVisibilidadeCardapioCombo': resultado = editarVisibilidadeCardapioCombo(body.id, body.ativo, body.destaque); break;
      case 'editarOrdemCardapioCombo': resultado = editarOrdemCardapioCombo(body.id, body.ordem); break;
      case 'seedCardapioTexasBurger': resultado = seedCardapioTexasBurger(); break;
      case 'addMesa': resultado = addMesa(body.numero, body.capacidade); break;
      case 'editarStatusMesa': resultado = (NIVEL_ATUAL === 'Garçom') ? editarStatusMesaGarcom_(body.id, body.novoStatus) : editarStatusMesa(body.id, body.novoStatus, body.observacao); break;
      case 'excluirMesa': resultado = excluirMesa(body.id); break;
      case 'fecharContaMesa': resultado = fecharContaMesa(body.mesaId, body.pagamentos); break;
      case 'sincronizarContingenciaAgora': resultado = sincronizarContingencia(); break;
      case 'reconciliarContingenciaAgora': resultado = reconciliarContingencia(); break;
      case 'ativarSincronizacaoContingencia': resultado = garantirTriggerContingenciaDiario(); break;
      case 'editarAdicional': resultado = editarAdicional(body.id, body.nome, body.preco, body.ativo, body.ingredienteId, body.quantidadeDesconto); break;
      case 'excluirAdicional': resultado = excluirAdicional(body.id); break;
      case 'vincularAdicionaisEmLote': resultado = vincularAdicionaisEmLote(body.categorias, body.adicionaisIds); break;

      case 'addFeedback': resultado = addFeedback(body.vendaId, body.telefone, body.nota, body.comentario, body.nome); break;
      case 'editarStatusFeedback': resultado = editarStatusFeedback(body.id, body.novoStatus); break;
      case 'registrarOcorrencia': resultado = registrarOcorrencia(body.tipo, body.vendaId, body.descricao); break;
      case 'atualizarOcorrencia': resultado = atualizarOcorrencia(body.id, body.status, body.responsavel, body.solucao, body.statusEsperado); break;
      case 'obterChaveContingencia':
        try { resultado = { ok: true, chave: chaveContingencia_('CONTINGENCIA_CHAVE_INTERNA') }; } catch (errK) { resultado = { ok: false, message: 'Contingência sem chave configurada.' }; }
        break;
      case 'salvarConfigNotificacoes': resultado = salvarConfigNotificacoes(body.eventos); break;
      case 'salvarConfigEstoque': resultado = salvarConfigEstoque(body.bloquear); break;
      case 'salvarConfigCardapio': resultado = salvarConfigCardapio(body.kicker, body.frase, body.tempoEntrega, body.tempoRetirada, body.tempoMesa); break;

      case 'addIngrediente': resultado = addIngrediente(body.nome, body.quantidade, body.minimo, body.unidade, body.custo); break;
      case 'editarIngrediente': resultado = editarIngrediente(body.id, body.nome, body.quantidade, body.minimo, body.unidade, body.custo, body.ativo); break;
      case 'registrarEntradaEstoque': resultado = registrarEntradaEstoque(body.ingredienteId, body.quantidade, body.motivo); break;
      case 'registrarPerdaEstoque': resultado = registrarPerdaEstoque(body.ingredienteId, body.quantidade, body.motivo); break;
      case 'registrarInventarioEstoque': resultado = registrarInventarioEstoque(body.ingredienteId, body.novaQuantidade, body.motivo); break;
      case 'excluirIngrediente': resultado = excluirIngrediente(body.id); break;

      case 'addCombo': resultado = addCombo(body.nome, body.categoria, body.precoBase, body.custoBase, body.precos, body.itens, body.destaque); break;
      case 'editarCombo': resultado = editarCombo(body.id, body.nome, body.categoria, body.ativo, body.precos, body.itens, body.destaque); break;
      case 'excluirCombo': resultado = excluirCombo(body.id); break;
      case 'uploadFotoCombo': resultado = uploadFotoCombo(body.comboId, body.nomeBase, body.base64Data, body.mimeType); break;
      case 'excluirFotoCombo': resultado = excluirFotoCombo(body.comboId); break;

      case 'abrirCaixa': resultado = abrirCaixa(body.fundoCaixa, USUARIO_ATUAL || body.usuarioAtual); break;
      case 'fecharCaixa':
        if (!verificarSenhaDoUsuarioAtual_(body.senhaConfirmacao)) {
          const chaveFecha = 'falhas_senha_propria_' + String(USUARIO_ATUAL).toLowerCase();
          const segFecha = excedeuTentativas_(chaveFecha, 5) ? segundosRestantesBloqueio_(chaveFecha) : 0;
          resultado = { ok: false, bloqueioSegundos: segFecha || undefined, message: segFecha ? 'Muitas tentativas erradas. Aguarde ' + (segFecha >= 60 ? Math.floor(segFecha / 60) + ' min ' + (segFecha % 60) + ' s' : segFecha + ' s') + ' e tente de novo.' : 'Senha incorreta. O caixa não foi fechado.' };
          break;
        }
        resultado = fecharCaixa(body.id, USUARIO_ATUAL || body.usuarioAtual, body.valorContado); break;

      case 'iniciarVenda': resultado = iniciarVenda(body.itens, body.clienteNome, body.clienteTelefone, body.pagamentos, body.tipoEntrega, body.dadosEntrega, body.statusPagamento, body.desconto, body.senhaAdminConfirmacao, body.origem, body.mesaId, body.requisicaoId); break;
      case 'criarPedidoCardapio': { const de = body.dadosEntrega && typeof body.dadosEntrega === 'object' ? Object.assign({}, body.dadosEntrega) : {}; de.observacoes = body.observacoes || de.observacoes || ''; resultado = criarPedidoCardapio(body.itens, body.clienteNome, body.clienteTelefone, body.tipoEntrega, de, body.formaPagamentoId, body.observacaoTroco, body.requisicaoId, body.codigoCupom); break; }
      case 'avancarStatusPedido': resultado = avancarStatusPedido(body.vendaId, body.novoStatus, body.statusEsperado); break;
      case 'salvarConfigEntrega': resultado = salvarConfigEntrega(body.taxaPadrao, body.ajudaDiaria); break;
      case 'previewFechamentoEntrega': resultado = previewFechamentoEntrega(body.entregador, body.dataRef); break;
      case 'fecharPeriodoEntregador': resultado = fecharPeriodoEntregador(body.entregador, body.dataRef, body.valorPago, body.observacao, body.requisicaoId); break;
      case 'atribuirEntregador': resultado = atribuirEntregador(body.vendaId, body.entregador); break;
      case 'confirmarRecebimentoPedido': resultado = confirmarRecebimentoPedido(body.vendaId); break;
      case 'editarVenda': resultado = editarVenda(body.id, body.itens, body.motivo, body.senhaAdminConfirmacao); break;
      case 'cancelarVenda': resultado = cancelarVenda(body.id, body.motivo, body.senhaAdminConfirmacao, body.mercadoriaPerdida); break;
      case 'suspenderPedido': resultado = suspenderPedido(body.vendaId, body.motivo); break;
      case 'retomarPedido': resultado = retomarPedido(body.vendaId); break;
      case 'aceitarPedido': resultado = aceitarPedido(body.vendaId); break;
      case 'iniciarPreparoPedido': resultado = iniciarPreparoPedido(body.vendaId); break;
      case 'detectarNovosPedidos': resultado = detectarNovosPedidos(); break;
      case 'rejeitarPedido': resultado = rejeitarPedido(body.vendaId, body.motivo, body.senhaAdminConfirmacao); break;
      case 'getStatusPedidoPublico': resultado = getStatusPedidoPublico(body.codigo); break;
      case 'getMesaPublica': resultado = getMesaPublica(body.mesa, body.codigo); break;
      case 'criarPedidoMesa': resultado = criarPedidoMesa(body.mesa, body.codigo, body.itens, body.clienteNome, body.requisicaoId); break;
      case 'cancelarPedidoMesa': resultado = cancelarPedidoMesa(body.mesa, body.codigo, body.vendaId); break;
      case 'cancelarPedidoCardapioPublico': resultado = cancelarPedidoCardapioPublico(body.codigo); break;
      case 'pedirContaMesa': resultado = pedirContaMesa(body.mesa, body.codigo); break;
      case 'chamarGarcomMesa': resultado = chamarGarcomMesa(body.mesa, body.codigo); break;
      case 'getQrMesas': resultado = obterQrMesas(); break;
      case 'gerarNovoCodigoMesa': resultado = gerarNovoCodigoMesa(body.mesaId); break;
      case 'atenderChamadoMesa': resultado = atenderChamadoMesa(body.mesaId); break;
      case 'validarCupomCardapio': resultado = validarCupomCardapio(body.codigo, body.telefone, body.subtotal, body.tipoEntrega, body.itens); break;
      case 'salvarCupom': resultado = salvarCupom(body.codigo,body.nome,body.tipo,body.valor,body.freteGratis,body.dataInicio,body.dataFim,body.horaInicio,body.horaFim,body.limiteTotal,body.limitePorCliente,body.valorMinimo,body.ativa,body.acumula); break;
      case 'editarCupom': resultado = editarCupom(body.id,body.codigo,body.nome,body.tipo,body.valor,body.freteGratis,body.dataInicio,body.dataFim,body.horaInicio,body.horaFim,body.limiteTotal,body.limitePorCliente,body.valorMinimo,body.ativa,body.acumula); break;
      case 'alternarCupom': resultado = alternarCupom(body.id,body.ativo); break;
      case 'salvarEvento': resultado = salvarEvento(body.id,body.nome,body.tipo,body.data,body.horaInicio,body.horaFim,body.local,body.contratante,body.telefone,body.status,body.valorContratado,body.observacoes); break;
      case 'adicionarCustoEvento': resultado = adicionarCustoEvento(body.eventoId,body.descricao,body.categoria,body.valor,body.data,body.observacao,body.requisicaoId); break;
      case 'adicionarRecebimentoEvento': resultado = adicionarRecebimentoEvento(body.eventoId,body.valor,body.forma,body.data,body.observacao,body.requisicaoId); break;
      case 'cancelarEvento': resultado = cancelarEvento(body.id,body.motivo); break;
      case 'simularPrecificacao': resultado = simularPrecificacao(body.produtoId,body.formaPagamentoId,body.precoSimulado,body.embalagem,body.outrosCustos,body.taxaMarketplace); break;
      case 'aplicarPrecoCalculadora': resultado = aplicarPrecoCalculadora(body.produtoId,body.formaPagamentoId,body.novoPreco); break;

      case 'addDespesa': resultado = addDespesa(body.descricao, body.valor, body.observacao, body.categoria, body.vencimento, body.situacao, body.saiuDoCaixa); break;
      case 'pagarDespesa': resultado = pagarDespesa(body.id, body.saiuDoCaixa, body.valorPago); break;
      case 'addDespesaRecorrente': resultado = addDespesaRecorrente(body.descricao, body.categoria, body.valor, body.diaVencimento, body.periodicidade, body.observacao, body.inicio, body.termino); break;
      case 'editarDespesaRecorrente': resultado = editarDespesaRecorrente(body.id, body.descricao, body.categoria, body.valor, body.diaVencimento, body.periodicidade, body.observacao, body.inicio, body.termino, body.ativa); break;
      case 'gerarDespesasMes': resultado = gerarDespesasMes(); break;
      case 'addSangria': resultado = addSangria(body.valor, body.motivo); break;
      case 'editarDespesa': resultado = editarDespesa(body.id, body.descricao, body.valor, body.observacao, body.categoria, body.vencimento); break;
      case 'cancelarDespesa': resultado = cancelarDespesa(body.id, body.motivo, body.senhaAdminConfirmacao); break;
      case 'registrarAjustePosVenda': resultado = registrarAjustePosVenda(body.vendaId, body.tipo, body.valor, body.motivo, body.detalhe, body.saida, body.senhaAdminConfirmacao); break;
      case 'cancelarAjustePosVenda': resultado = cancelarAjustePosVenda(body.id, body.motivo, body.senhaAdminConfirmacao); break;

      case 'salvarMeta': resultado = salvarMeta(body.tipo, body.valor); break;
      case 'verificarSenhaAdmin': resultado = { ok: verificarAdmin(body.senha) }; break;

      default: resultado = { ok: false, message: 'Ação desconhecida.' };
    }
    if (ACOES_SEM_ALTERACAO_.indexOf(action) === -1) bumpVersoes_(action); // ITEM 19: avisa o painel de que algo mudou
    if (ACOES_INVALIDAM_CARDAPIO_.indexOf(action) !== -1) invalidarCacheCardapio_(false);
    else if (ACOES_INVALIDAM_DINAMICO_.indexOf(action) !== -1) invalidarCacheCardapio_(true);
    if (ACOES_PUBLICAS.indexOf(action) === -1) resultado = anexarVersoes_(resultado); // FASE 11C: cada registro editável sai com sua versão (_v)
    if (chaveIdem && resultado && resultado.ok === true && !resultado.duplicado) requisicaoRegistrar_(chaveIdem, action, resultado.id || resultado.message);
  } catch (erro) {
    /* Erro inesperado: sempre responde JSON (nunca a página de erro do Google). O lock é solto no finally.
       Como a falha pode ter ocorrido no meio da operação, o aviso pede para conferir antes de repetir. */
    try { registrarLog('Erro inesperado no servidor', USUARIO_ATUAL || '', String(action).slice(0, 60) + ' | ' + String(erro && erro.message || erro).slice(0, 200)); } catch (e2) {}
    return responder({ ok: false, message: 'Erro inesperado no servidor. Confira se a operação foi feita antes de repetir.' });
  } finally {
    if (temLock) lock.releaseLock();
  }
  return responder(resultado);
}

function responder(obj) { return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON); }
/* Converte o que vier de uma célula em número: aceita número, "51", "51,5", "R$ 51,50", "1.234,56", "1,234.56", "(51,5)" e "-51,5".
   Vazio, texto que não é número, data e booleano viram o padrão (0). Regra do ponto sozinho: "1.234" / "1.234.567" = milhar;
   "0.250", "51.5" = decimal. A vírgula sozinha é decimal ("51,5"), a não ser que se repita ("1,234,567" = milhar). */
function numPlanilha_(v, padrao) {
  const pad = (padrao === undefined) ? 0 : padrao;
  if (typeof v === 'number') return isFinite(v) ? v : pad;
  if (typeof v !== 'string') return pad;
  let s = v.replace(/[\s\u00a0]/g, '').replace(/%$/, '');
  let neg = false;
  if (/^\(.*\)$/.test(s)) { neg = true; s = s.slice(1, -1); }
  if (s.charAt(0) === '-') { neg = true; s = s.slice(1); }
  s = s.replace(/^R\$/i, '');
  if (!/^[\d.,]+$/.test(s) || !/\d/.test(s)) return pad;
  const temV = s.indexOf(',') !== -1, temP = s.indexOf('.') !== -1;
  if (temV && temP) {
    if (s.lastIndexOf(',') > s.lastIndexOf('.')) s = s.replace(/\./g, '').replace(',', '.');
    else s = s.replace(/,/g, '');
  } else if (temV) {
    s = ((s.match(/,/g) || []).length > 1) ? s.replace(/,/g, '') : s.replace(',', '.');
  } else if (temP) {
    if (/^[1-9]\d{0,2}(\.\d{3})+$/.test(s)) s = s.replace(/\./g, '');
  }
  const n = Number(s);
  if (!isFinite(n)) return pad;
  return neg ? -n : n;
}
function normTel(t) { return (t || '').toString().replace(/\D/g, ''); }
function agora() { return Utilities.formatDate(new Date(), FUSO, 'dd/MM/yyyy HH:mm'); }
function ss_() {
  const props = PropertiesService.getScriptProperties();
  let id = props.getProperty('SPREADSHEET_ID');
  if (!id) {
    // Primeira vez rodando: captura o ID enquanto ainda há um contexto vinculado
    // disponível, e guarda pra sempre — depois disso, nunca mais depende de
    // getActiveSpreadsheet() (que falha silenciosamente em Web App e em gatilhos
    // por tempo, já que ali não existe planilha "ativa").
    const ativa = SpreadsheetApp.getActiveSpreadsheet();
    if (!ativa) throw new Error('Não foi possível identificar a planilha na primeira execução. Abra o editor do Apps Script pela própria planilha (Extensões → Apps Script) e rode a função configurarIdPlanilha() uma vez.');
    id = ativa.getId();
    props.setProperty('SPREADSHEET_ID', id);
  }
  return SpreadsheetApp.openById(id);
}
/* Rode esta função uma vez pelo editor do Apps Script (aberto a partir da
   própria planilha) se por algum motivo o ID precisar ser (re)configurado. */
function configurarIdPlanilha() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  PropertiesService.getScriptProperties().setProperty('SPREADSHEET_ID', ss.getId());
  return 'ID da planilha configurado: ' + ss.getId();
}



/* ---------- ETAPA 1: SENHA TEMPORÁRIA, PRODUÇÃO E EMERGÊNCIA ---------- */
function novaSenhaTemporaria_() { return Utilities.getUuid().replace(/-/g, '').slice(0, 10); }
/* Proteção de produção: dados fictícios não fazem parte da versão operacional. */
function marcarProducao() {
  PropertiesService.getScriptProperties().setProperty('PRODUCAO', 'Sim');
  Logger.log('Sistema marcado como PRODUÇÃO: dados de teste bloqueados.');
}
function desmarcarProducao() {
  PropertiesService.getScriptProperties().deleteProperty('PRODUCAO');
  Logger.log('Marca de PRODUÇÃO removida.');
}
/* Só roda pelo editor do Apps Script (quem tem acesso ao script já é dono do sistema). */
function redefinirSenhaAdminEmergencia() {
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 3).getValue() === 'Admin' && sh.getRange(i, 4).getValue() === 'Sim') {
      const senhaTemp = novaSenhaTemporaria_();
      sh.getRange(i, 2).setValue(hashSenha_(senhaTemp));
      registrarAuditoria_('Senha de administrador redefinida (emergência)', String(sh.getRange(i, 1).getValue()));
      Logger.log('Nova senha temporária de ' + sh.getRange(i, 1).getValue() + ': ' + senhaTemp);
      return;
    }
  }
  Logger.log('Nenhum administrador ativo encontrado.');
}



/* ---------- ETAPA 3 — OCORRÊNCIAS (ITENS 62, 63, 70) ----------
   Aba "Ocorrências": ID, Nº, Data/Hora, Tipo, Setor, ID Venda, Cliente, Telefone, Registrado Por, Responsável,
   Descrição, Solução, Status, Atualizada em, Histórico.
   • Qualquer perfil registra (a produção avisa "não consigo produzir"). Só Admin e Operador tratam e resolvem.
   • Quem não é Admin/Operador vê apenas as ocorrências que ele mesmo registrou.
   • Toda criação e toda mudança de status entram na Auditoria e no Histórico da própria ocorrência.
   • Não muda o status do pedido: o pedido ganha um aviso visível enquanto houver ocorrência aberta. */
const OCORRENCIA_TIPOS = ['Produção', 'Entrega', 'Atendimento', 'Pagamento', 'Estoque', 'Outro'];
const OCORRENCIA_STATUS = ['Aberta', 'Em andamento', 'Resolvida'];
const OCORRENCIA_COLUNAS = ['ID', 'Nº', 'Data/Hora', 'Tipo', 'Setor', 'ID Venda', 'Cliente', 'Telefone', 'Registrado Por', 'Responsável', 'Descrição', 'Solução', 'Status', 'Atualizada em', 'Histórico'];
function criarOcorrencias(ss) {
  let sh = ss.getSheetByName('Ocorrências') || ss.insertSheet('Ocorrências');
  sh.clear();
  sh.setTabColor('#b5651d');
  formatarCabecalho(sh, OCORRENCIA_COLUNAS);
  [40, 60, 140, 110, 120, 60, 160, 130, 130, 130, 320, 260, 110, 140, 360].forEach((w, i) => sh.setColumnWidth(i + 1, w));
  sh.getRange('H2:H2000').setNumberFormat('@');
  sh.setFrozenRows(1);
}
/* Planilha que já existe: rode UMA vez no editor do Apps Script. Não apaga nada. */
function prepararEtapa3Ocorrencias() {
  const ss = ss_();
  if (ss.getSheetByName('Ocorrências')) return { ok: true, message: 'A aba Ocorrências já existe.' };
  criarOcorrencias(ss);
  registrarLog('Etapa 3: aba Ocorrências criada', '', '');
  return { ok: true, message: 'Aba Ocorrências criada.' };
}
/* SEGURANÇA (reauditoria): todo texto vindo de endpoint PÚBLICO passa por aqui — remove < > e aspas que
   poderiam virar HTML no painel, tira caracteres de controle, limita o tamanho e evita que vire fórmula. */
function textoPublicoSeguro_(t, max) {
  let s = String(t == null ? '' : t).replace(/[\u0000-\u001F\u007F]+/g, ' ').replace(/[<>`]/g, '').replace(/"/g, '\u201D').replace(/'/g, '\u2019').trim();
  s = s.slice(0, max || 200);
  return /^[=+\-@]/.test(s) ? "'" + s : s;
}
function textoPlanilhaSeguro_(t) { // evita que texto digitado vire fórmula na planilha
  const s = String(t == null ? '' : t).trim();
  return /^[=+\-@]/.test(s) ? "'" + s : s;
}
function setorPorPerfil_(nivel) {
  return ({ 'Cozinha': 'Cozinha', 'Garçom': 'Salão', 'Entregador': 'Entrega', 'Operador': 'Caixa', 'Admin': 'Administração' })[nivel] || 'Outro';
}
function readOcorrencias() {
  const sh = ss_().getSheetByName('Ocorrências');
  if (!sh) return [];
  const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, Math.min(15, sh.getMaxColumns())).getValues().filter(r => r[0]).map(r => ({
    id: r[0], numero: numPlanilha_(r[1]) || 0, data: dataTexto_(r[2]), tipo: r[3], setor: r[4], vendaId: r[5] || '', clienteNome: r[6] || '', clienteTelefone: r[7] || '',
    registradoPor: r[8] || '', responsavel: r[9] || '', descricao: r[10] || '', solucao: r[11] || '', status: r[12] || 'Aberta', atualizada: dataTexto_(r[13]), historico: r[14] || ''
  }));
}
function ocorrenciasVisiveis_(lista) {
  if (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador') return lista;
  const eu = String(USUARIO_ATUAL).toLowerCase();
  return lista.filter(o => String(o.registradoPor).toLowerCase() === eu);
}
function vendaNoEscopoDoUsuario_(venda) {
  if (!venda) return false;
  if (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador') return true;
  if (NIVEL_ATUAL === 'Entregador') {
    return venda.tipoEntrega === 'Entrega' &&
      String(venda.entregador || '').toLowerCase() === String(USUARIO_ATUAL || '').toLowerCase();
  }
  if (NIVEL_ATUAL === 'Garçom') {
    const mesasAtivas = readMesas()
      .filter(m => ['Ocupada', 'Aguardando fechamento'].indexOf(m.status) !== -1)
      .map(m => String(m.id));
    return !!venda.mesaId &&
      mesasAtivas.indexOf(String(venda.mesaId)) !== -1 &&
      String(venda.registradoPor || '').toLowerCase() === String(USUARIO_ATUAL || '').toLowerCase();
  }
  // A Cozinha pode registrar ocorrência sobre qualquer pedido que esteja no fluxo de produção.
  if (NIVEL_ATUAL === 'Cozinha') {
    return venda.status === 'Confirmada' &&
      ['Recebido', 'Em preparo', 'Pronta', 'Servida', 'Retirada', 'Saiu para entrega', 'Entregue']
        .indexOf(String(venda.statusPedido || '')) !== -1;
  }
  return false;
}

function registrarOcorrencia(tipo, vendaId, descricao) {
  if (OCORRENCIA_TIPOS.indexOf(tipo) === -1) return { ok: false, message: 'Escolha o tipo da ocorrência.' };
  const desc = String(descricao || '').trim();
  if (desc.length < 3) return { ok: false, message: 'Descreva o que aconteceu.' };
  if (desc.length > 600) return { ok: false, message: 'Descrição muito longa (máximo 600 caracteres).' };
  let venda = null;
  if (vendaId) {
    venda = readVendas().find(v => v.id === vendaId);
    if (!venda) return { ok: false, message: 'Pedido não encontrado.' };
    if (!vendaNoEscopoDoUsuario_(venda)) return { ok: false, message: 'Este pedido não está no seu escopo operacional.' };
  }
  const sh = ss_().getSheetByName('Ocorrências');
  if (!sh) return { ok: false, message: 'A aba Ocorrências ainda não existe. Peça ao administrador para rodar prepararEtapa3Ocorrencias.' };
  const last = sh.getLastRow();
  let numero = 0;
  if (last >= 2) sh.getRange(2, 2, last - 1, 1).getValues().forEach(r => { const n = numPlanilha_(r[0]) || 0; if (n > numero) numero = n; });
  numero += 1;
  const id = Utilities.getUuid();
  const agoraTxt = agora();
  const setor = setorPorPerfil_(NIVEL_ATUAL);
  const hist = agoraTxt + ' — ' + USUARIO_ATUAL + ' (' + NIVEL_ATUAL + '): ocorrência registrada';
  sh.appendRow([id, numero, agoraTxt, tipo, setor, vendaId || '', venda ? venda.clienteNome : '', venda ? venda.clienteTelefone : '', USUARIO_ATUAL || '', '',
    textoPlanilhaSeguro_(desc), '', 'Aberta', agoraTxt, hist]);
  registrarAuditoria_('Ocorrência registrada', '#' + numero + ' ' + tipo + (venda ? ' — pedido #' + (venda.numero || String(venda.id).slice(-5).toUpperCase()) : '') + ': ' + desc.slice(0, 120));
  return { ok: true, message: 'Ocorrência #' + numero + ' registrada.', id: id, ocorrencias: ocorrenciasVisiveis_(readOcorrencias()) };
}
function atualizarOcorrencia(id, status, responsavel, solucao, statusEsperado) {
  if (OCORRENCIA_STATUS.indexOf(status) === -1) return { ok: false, message: 'Status inválido.' };
  const sol = String(solucao || '').trim();
  if (status === 'Resolvida' && sol.length < 3) return { ok: false, message: 'Descreva a solução para resolver a ocorrência.' };
  const sh = ss_().getSheetByName('Ocorrências');
  if (!sh) return { ok: false, message: 'A aba Ocorrências ainda não existe.' };
  const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() !== id) continue;
    const statusAtual = sh.getRange(i, 13).getValue() || 'Aberta';
    if (statusEsperado && statusEsperado !== statusAtual) { // concorrência: outra pessoa já mexeu (ITEM 80)
      return { ok: false, conflito: true, message: 'Essa ocorrência já foi atualizada por outra pessoa (agora está "' + statusAtual + '"). Confira a lista.', ocorrencias: ocorrenciasVisiveis_(readOcorrencias()) };
    }
    const numero = sh.getRange(i, 2).getValue();
    const resp = String(responsavel || '').trim().slice(0, 60);
    const agoraTxt = agora();
    if (resp) sh.getRange(i, 10).setValue(textoPlanilhaSeguro_(resp));
    if (sol) sh.getRange(i, 12).setValue(textoPlanilhaSeguro_(sol.slice(0, 600)));
    sh.getRange(i, 13).setValue(status);
    sh.getRange(i, 14).setValue(agoraTxt);
    const linha = agoraTxt + ' — ' + USUARIO_ATUAL + ' (' + NIVEL_ATUAL + '): ' + statusAtual + ' → ' + status + (resp ? ' · resp.: ' + resp : '') + (sol ? ' · solução: ' + sol.slice(0, 80) : '');
    const histAtual = String(sh.getRange(i, 15).getValue() || '');
    sh.getRange(i, 15).setValue((histAtual ? histAtual + '\n' : '') + linha);
    registrarAuditoria_('Ocorrência atualizada', '#' + numero + ': ' + statusAtual + ' → ' + status + (sol ? ' — ' + sol.slice(0, 120) : ''));
    return { ok: true, message: 'Ocorrência #' + numero + ' atualizada.', ocorrencias: ocorrenciasVisiveis_(readOcorrencias()) };
  }
  return { ok: false, message: 'Ocorrência não encontrada.' };
}

/* ---------- ETAPA 2 — IDENTIFICADORES (ITEM 9) ----------
   • Usuários ganham "ID" permanente (coluna 8). O login continua sendo o que a pessoa digita.
   • Vendas ganham "Nº Pedido" (coluna 30): número amigável sequencial (1, 2, 3...). O código público de acompanhamento
     do cliente continua sendo o sufixo do ID longo (difícil de adivinhar); o número serve para a equipe e para o cliente citar o pedido.
   • Fidelidade, Indicações e Feedbacks passam a guardar também o ID do cliente. O telefone continua sendo a busca rápida. */
function proximoNumeroPedido_(shVendas) {
  const last = shVendas.getLastRow();
  if (last < 2 || shVendas.getMaxColumns() < 30) return 1;
  let max = 0;
  shVendas.getRange(2, 30, last - 1, 1).getValues().forEach(r => { const n = numPlanilha_(r[0]) || 0; if (n > max) max = n; });
  return max + 1;
}
function garantirColuna_(sh, coluna, titulo, largura) {
  if (sh.getMaxColumns() < coluna) sh.insertColumnsAfter(sh.getMaxColumns(), coluna - sh.getMaxColumns());
  if (!String(sh.getRange(1, coluna).getValue())) {
    sh.getRange(1, coluna).setValue(titulo).setBackground(COR_ESCURO).setFontColor(COR_DOURADO).setFontWeight('bold');
    if (largura) sh.setColumnWidth(coluna, largura);
  }
}
/* Rode UMA vez no editor do Apps Script em planilha que já existe (planilha nova já nasce com as colunas). Pode rodar de novo sem duplicar. */
/* ---------- FASE 9 — SENHAS, TENTATIVAS E AUDITORIA ---------- */
function buscarUsuarioPorLogin_(login) {
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  if (last < 2) return null;
  const alvo = String(login || '').toLowerCase();
  const linhas = sh.getRange(2, 1, last - 1, 4).getValues();
  for (let i = 0; i < linhas.length; i++) {
    if (String(linhas[i][0]).toLowerCase() === alvo) return { login: linhas[i][0], nivel: linhas[i][2], ativo: linhas[i][3], marca: marcaSenha_(linhas[i][1]) };
  }
  return null;
}
function sha256hex_(texto) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, texto, Utilities.Charset.UTF_8)
    .map(b => ('0' + (b & 0xff).toString(16)).slice(-2)).join('');
}
function hashSenha_(senha) {
  const salt = Utilities.getUuid().replace(/-/g, '').slice(0, 16);
  return 'sha256$' + salt + '$' + sha256hex_(salt + String(senha));
}
/* Aceita senha já com hash OU texto puro antigo (migrada para hash no primeiro login). */
function senhaConfere_(armazenada, informada) {
  const a = String(armazenada || '');
  if (a.indexOf('sha256$') === 0) { const p = a.split('$'); return p.length === 3 && sha256hex_(p[1] + String(informada)) === p[2]; }
  return a !== '' && a === String(informada);
}
function excedeuTentativas_(chave, max) { const p = String(CacheService.getScriptCache().get(chave) || '').split('|'); return (Number(p[0]) || 0) >= max; }
/* O prazo de bloqueio conta a partir do PRIMEIRO erro e não é renovado a cada novo erro (antes, quem insistisse mantinha o login trancado sem fim). */
function registrarFalha_(chave, duracaoMs) {
  const c = CacheService.getScriptCache(), agoraMs = Date.now(), p = String(c.get(chave) || '').split('|');
  let n = Number(p[0]) || 0, ate = Number(p[1]) || 0;
  if (!ate || ate <= agoraMs) { n = 0; ate = agoraMs + (duracaoMs || 600000); } // BLOCO 1.4: quem precisa de espera menor (fechar caixa) informa a duração; o padrão continua 10 min
  c.put(chave, (n + 1) + '|' + ate, Math.max(1, Math.ceil((ate - agoraMs) / 1000)));
  return n + 1;
}
/* BLOCO 1.4: quanto falta (em segundos) para o bloqueio daquela chave acabar; 0 se não está bloqueada. */
function segundosRestantesBloqueio_(chave) {
  const p = String(CacheService.getScriptCache().get(chave) || '').split('|'), ate = Number(p[1]) || 0;
  return Math.max(0, Math.ceil((ate - Date.now()) / 1000));
}
function limparFalhas_(chave) { CacheService.getScriptCache().remove(chave); }

const ACOES_AUDITADAS_RE = /ajuste p[óo]s-venda|suspens|retomad|desconto|cancelad|editada|estorno|estoque|perda|inventário|usuário|senha|sangria|despesa|forma de pagamento|restaur|backup|acesso negado|preço|fechamento|entregador atribu|login falhou|conta de mesa|qr da mesa/i;
function registrarAuditoria_(acao, detalhes) {
  const ss = ss_();
  let sh = ss.getSheetByName('Auditoria');
  if (!sh) {
    sh = ss.insertSheet('Auditoria');
    sh.appendRow(['Data/Hora', 'Usuário', 'Perfil', 'Ação', 'Detalhes', 'Autorizado por', 'Aparelho']);
    sh.setFrozenRows(1); sh.setTabColor('#5a5a5a');
  }
  if (sh.getLastColumn() < 7) sh.getRange(1, 7).setValue('Aparelho'); // BLOCO 4.2: abas antigas ganham a coluna sozinhas
  sh.appendRow([agora(), USUARIO_ATUAL || '', NIVEL_ATUAL || '', acao, detalhes || '', AUTORIZADOR_ATUAL || '', APARELHO_ATUAL || '']);
}

/* ---------- USUÁRIOS / LOGIN / PERMISSÕES ---------- */
function readUsuarios() {
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, Math.min(8, sh.getMaxColumns())).getValues().filter(r => r[0])
    .map(r => ({ login: r[0], nivel: r[2], ativo: r[3] === 'Sim', criadoEm: r[4], nome: r[5] || '', telefone: r[6] || '', id: r[7] || '' }));
}
function autenticar(login, senha, deviceId, ua) {
  const chaveBloq = 'falhas_login_' + String(login || '').toLowerCase();
  if (excedeuTentativas_(chaveBloq, 5)) return { ok: false, message: 'Muitas tentativas erradas. Aguarde 10 minutos e tente de novo.' };
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    const linha = sh.getRange(i, 1, 1, 4).getValues()[0];
    if (String(linha[0]).toLowerCase() === String(login || '').toLowerCase() && senhaConfere_(linha[1], senha)) {
      if (linha[3] !== 'Sim') return { ok: false, message: 'Este acesso está desativado.' };
      if (String(linha[1]).indexOf('sha256$') !== 0) sh.getRange(i, 2).setValue(hashSenha_(senha)); // migra texto puro -> hash
      limparFalhas_(chaveBloq);
      const token = criarSessao_(linha[0], linha[2], marcaSenha_(sh.getRange(i, 2).getValue()), { deviceId: deviceId, ua: ua });
      registrarLog('Login realizado', '', login + (deviceId ? ' | aparelho ' + String(deviceId).replace(/[^A-Za-z0-9-]/g, '').slice(0, 8) : '') + (ua ? ' | ' + String(ua).slice(0, 60) : ''));
      return { ok: true, login: linha[0], nivel: linha[2], token: token };
    }
  }
  registrarFalha_(chaveBloq);
  registrarLog('Login falhou', '', String(login || '').slice(0, 40) + (deviceId ? ' | aparelho ' + String(deviceId).replace(/[^A-Za-z0-9-]/g, '').slice(0, 8) + (ua ? ' · ' + String(ua).slice(0, 60) : '') : ''));
  return { ok: false, message: 'Login ou senha incorretos.' };
}

/* ---------- SESSÃO (ITEM 7, 8) ----------
   O login é o único lugar onde confiamos no que o cliente manda. Depois disso,
   toda ação usa o token: o backend resolve login/nível a partir dele, nunca do
   que o app diz que é. Esconder um botão no HTML não impede alguém de chamar
   a API direto — só a validação aqui embaixo impede. */
/* SEGURANÇA (Módulo 3): a sessão guarda uma "marca" da senha atual. Trocou a senha do usuário -> todas as sessões antigas dele
   caem na hora (antes, quem tinha o token continuava logado mesmo depois da troca). Também tem vida máxima de 16 h. */
const SESSAO_VIDA_MAXIMA_MS = 16 * 3600 * 1000;
function marcaSenha_(armazenada) { return sha256hex_('marca|' + String(armazenada || '')).slice(0, 16); }
function criarSessao_(login, nivel, marca, meta) {
  const token = Utilities.getUuid();
  meta = meta || {};
  const agoraMs = Date.now();
  const sess = { login: login, nivel: nivel, marca: marca || '', criada: agoraMs, visto: agoraMs, idx: agoraMs,
    deviceId: String(meta.deviceId || '').replace(/[^A-Za-z0-9-]/g, '').slice(0, 40), ua: String(meta.ua || '').slice(0, 80) };
  CacheService.getScriptCache().put('sess_' + token, JSON.stringify(sess), SESSAO_TTL_SEGUNDOS);
  try { indexarSessao_(token, sess); } catch (e) { /* rastreio é só visibilidade: nunca pode impedir o login */ }
  return token;
}
/* ITEM 2.1 — Rastreio de sessões. O CacheService não lista chaves, então cada usuário tem um ÍNDICE ('sessidx_<login>')
   com os tokens dele + metadados. O índice só aumenta visibilidade; quem manda na validade continua sendo 'sess_<token>'.
   Obs.: o Apps Script (web app) NÃO expõe o IP de quem chama, então não há IP — usamos deviceId + resumo do navegador. */
function sessaoIdPublico_(token) { return sha256hex_('sid|' + token).slice(0, 12); }  // nunca expomos o token ao painel
function lerIndiceSessoes_(login) {
  try { const a = JSON.parse(CacheService.getScriptCache().get('sessidx_' + String(login).toLowerCase()) || '[]'); return Array.isArray(a) ? a : []; } catch (e) { return []; }
}
function gravarIndiceSessoes_(login, lista) {
  const c = CacheService.getScriptCache(), k = 'sessidx_' + String(login).toLowerCase();
  if (!lista.length) c.remove(k); else c.put(k, JSON.stringify(lista), SESSAO_TTL_SEGUNDOS);
}
function indexarSessao_(token, sess) {
  const c = CacheService.getScriptCache();
  // poda: só fica no índice quem ainda tem sessão viva no cache
  let lista = lerIndiceSessoes_(sess.login).filter(x => x.token !== token);
  const vivos = lista.length ? c.getAll(lista.map(x => 'sess_' + x.token)) : {};
  lista = lista.filter(x => vivos['sess_' + x.token]);
  lista.push({ token: token, deviceId: sess.deviceId || '', ua: sess.ua || '', criada: sess.criada, visto: sess.visto || sess.criada });
  if (lista.length > 20) lista = lista.slice(-20);
  gravarIndiceSessoes_(sess.login, lista);
}
/* Lista (Admin) as sessões vivas de todos os usuários — sem token. */
function listarSessoes(tokenAtual) {
  const c = CacheService.getScriptCache(), out = [], idAtual = tokenAtual ? sessaoIdPublico_(tokenAtual) : '';
  readUsuarios().forEach(u => {
    const lista = lerIndiceSessoes_(u.login);
    if (!lista.length) return;
    const vivos = c.getAll(lista.map(x => 'sess_' + x.token));
    const restantes = [];
    lista.forEach(x => {
      const raw = vivos['sess_' + x.token];
      if (!raw) return;
      restantes.push(x);
      let visto = x.visto; try { visto = JSON.parse(raw).visto || visto; } catch (e) {}
      const sid = sessaoIdPublico_(x.token);
      out.push({ sessaoId: sid, login: u.login, nivel: u.nivel, deviceId: x.deviceId ? x.deviceId.slice(0, 8) : '', ua: x.ua || '',
        criadaEm: Utilities.formatDate(new Date(x.criada), 'America/Sao_Paulo', 'dd/MM/yyyy HH:mm'),
        vistoEm: Utilities.formatDate(new Date(visto), 'America/Sao_Paulo', 'dd/MM/yyyy HH:mm'), vistoMs: visto, atual: sid === idAtual });
    });
    if (restantes.length !== lista.length) gravarIndiceSessoes_(u.login, restantes);
  });
  out.sort((a, b) => b.vistoMs - a.vistoMs);
  return { ok: true, sessoes: out };
}
/* Admin derruba uma sessão de outro aparelho. Não permite derrubar a própria sessão por aqui (para isso existe "Sair"). */
function encerrarSessaoRemota(sessaoId, tokenAtual) {
  const alvoId = String(sessaoId || '');
  if (!/^[0-9a-f]{12}$/.test(alvoId)) return { ok: false, message: 'Sessão inválida.' };
  if (tokenAtual && sessaoIdPublico_(tokenAtual) === alvoId) return { ok: false, message: 'Esta é a sua sessão atual. Use "Sair" para encerrá-la.' };
  const c = CacheService.getScriptCache();
  const us = readUsuarios();
  for (let i = 0; i < us.length; i++) {
    const lista = lerIndiceSessoes_(us[i].login), alvo = lista.find(x => sessaoIdPublico_(x.token) === alvoId);
    if (!alvo) continue;
    c.remove('sess_' + alvo.token);
    gravarIndiceSessoes_(us[i].login, lista.filter(x => x.token !== alvo.token));
    registrarLog('Acesso encerrado remotamente (usuário)', '', 'Sessão de ' + us[i].login + ' | aparelho ' + (alvo.deviceId ? alvo.deviceId.slice(0, 8) : '?') + ' | ' + (alvo.ua || ''));
    return { ok: true, message: 'Sessão de ' + us[i].login + ' encerrada.' };
  }
  return { ok: false, message: 'Sessão não encontrada (talvez já tenha expirado).' };
}
function validarSessao_(token) {
  if (!token) return null;
  const raw = CacheService.getScriptCache().get('sess_' + token);
  if (!raw) return null;
  const sessao = JSON.parse(raw);
  // FASE 9: o usuário pode ter sido desativado/rebaixado depois do login — o token não pode sobreviver a isso.
  const u = buscarUsuarioPorLogin_(sessao.login);
  if (!u || u.ativo !== 'Sim') { CacheService.getScriptCache().remove('sess_' + token); return null; }
  if ((sessao.marca && sessao.marca !== u.marca) || (sessao.criada && Date.now() - sessao.criada > SESSAO_VIDA_MAXIMA_MS)) { CacheService.getScriptCache().remove('sess_' + token); return null; }
  sessao.nivel = u.nivel;
  if (!sessao.idx || Date.now() - sessao.idx > 1800000) { // a cada 30 min: atualiza "visto" e renova o índice de rastreio (ITEM 2.1)
    sessao.idx = sessao.visto = Date.now();
    try { indexarSessao_(token, sessao); } catch (e) {}
  }
  CacheService.getScriptCache().put('sess_' + token, JSON.stringify(sessao), SESSAO_TTL_SEGUNDOS); // renova (sliding expiration)
  return sessao;
}
function encerrarSessao(token) {
  if (token) {
    const c = CacheService.getScriptCache();
    try { // tira do índice de rastreio (ITEM 2.1)
      const raw = c.get('sess_' + token);
      if (raw) { const lg = JSON.parse(raw).login; gravarIndiceSessoes_(lg, lerIndiceSessoes_(lg).filter(x => x.token !== token)); }
    } catch (e) {}
    c.remove('sess_' + token);
  }
  return { ok: true };
}
function verificarAdmin(senha) {
  if (!senha) return false;
  const chaveBloq = 'falhas_admin_' + String(USUARIO_ATUAL || 'anon').toLowerCase();
  if (excedeuTentativas_(chaveBloq, 5)) return false; // bloqueado por 10 min após 5 erros
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    const linha = sh.getRange(i, 1, 1, 4).getValues()[0];
    if (linha[2] === 'Admin' && linha[3] === 'Sim' && senhaConfere_(linha[1], senha)) { limparFalhas_(chaveBloq); AUTORIZADOR_ATUAL = String(linha[0]); return true; }
  }
  registrarFalha_(chaveBloq);
  registrarLog('Falha na senha de administrador', '', 'Tentativa por ' + (USUARIO_ATUAL || 'anônimo'));
  return false;
}
/* Confere a senha de QUEM está logado (Operador confere a dele; Admin operando o caixa confere a dele). Usada no fechamento do caixa.
   BLOCO 1.4: 5 erros = 2 minutos de espera (nas outras senhas continuam 10). Aqui a pessoa já tem sessão válida, e no fim do turno
   10 minutos travava o fechamento. A 5ª falha vira alerta na Auditoria. */
const BLOQUEIO_FECHAR_CAIXA_MS_ = 120000;
function verificarSenhaDoUsuarioAtual_(senha) {
  if (!senha || !USUARIO_ATUAL) return false;
  const chaveBloq = 'falhas_senha_propria_' + String(USUARIO_ATUAL).toLowerCase();
  if (excedeuTentativas_(chaveBloq, 5)) return false;
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    const linha = sh.getRange(i, 1, 1, 4).getValues()[0];
    if (String(linha[0]).toLowerCase() === String(USUARIO_ATUAL).toLowerCase() && linha[3] === 'Sim' && senhaConfere_(linha[1], senha)) { limparFalhas_(chaveBloq); return true; }
  }
  const nFalhas = registrarFalha_(chaveBloq, BLOQUEIO_FECHAR_CAIXA_MS_);
  registrarLog('Falha na senha ao fechar o caixa', '', 'Tentativa por ' + USUARIO_ATUAL + ' (' + nFalhas + ' de 5)');
  if (nFalhas >= 5) registrarAuditoria_('ALERTA: fechamento de caixa bloqueado por senha errada', USUARIO_ATUAL + ' errou a senha 5 vezes ao fechar o caixa; bloqueado por 2 minutos');
  return false;
}
/* Dupla trava para operação sensível: OU a sessão validada já é de um Admin,
   OU foi digitada a senha de um Admin agora (fluxo do Operador pedindo autorização). */
function exigeConfirmacaoAdmin(senhaAdminConfirmacao) {
  if (NIVEL_ATUAL === 'Admin') { AUTORIZADOR_ATUAL = USUARIO_ATUAL; return true; }
  return verificarAdmin(senhaAdminConfirmacao);
}

/* ---------- MAPA DE PERMISSÕES POR AÇÃO (ITEM 8) ----------
   '*' = qualquer usuário com sessão válida. Ações fora deste mapa e fora de
   ACOES_PUBLICAS são bloqueadas por padrão (nega por omissão, não permite). */
const ACOES_PUBLICAS = ['autenticar', 'getCardapio', 'criarPedidoCardapio', 'validarCupomCardapio', 'addFeedback', 'getStatusPedidoPublico', 'getMesaPublica', 'criarPedidoMesa', 'cancelarPedidoMesa', 'cancelarPedidoCardapioPublico', 'pedirContaMesa', 'chamarGarcomMesa'];
const PERMISSOES_ACAO = {
  encerrarSessao: '*', listarSessoes: ['Admin'], encerrarSessaoRemota: ['Admin'], trocarMinhaSenha: '*', verificarSenhaAdmin: '*', getAll: '*',
  getVersoes: ['Admin', 'Operador'], getDadosGrupo: ['Admin', 'Operador'],
  abrirCaixa: ['Admin', 'Operador'], fecharCaixa: ['Admin', 'Operador'],
  iniciarVenda: ['Admin', 'Operador', 'Garçom'],
  avancarStatusPedido: ['Admin', 'Operador', 'Garçom', 'Cozinha', 'Entregador'],
  atribuirEntregador: ['Admin', 'Operador'],
  salvarConfigEntrega: ['Admin'], previewFechamentoEntrega: ['Admin'], fecharPeriodoEntregador: ['Admin'],
  confirmarRecebimentoPedido: ['Admin', 'Operador'],
  editarVenda: ['Admin', 'Operador'], cancelarVenda: ['Admin', 'Operador'],
  aceitarPedido: ['Admin', 'Operador'], rejeitarPedido: ['Admin', 'Operador'], suspenderPedido: ['Admin', 'Operador'], retomarPedido: ['Admin', 'Operador'],
  iniciarPreparoPedido: ['Admin', 'Operador', 'Cozinha'], detectarNovosPedidos: ['Admin', 'Operador', 'Cozinha', 'Garçom', 'Entregador'],
  salvarCliente: ['Admin', 'Operador', 'Garçom'], excluirCliente: ['Admin'],
  indicarNovoCliente: ['Admin', 'Operador', 'Garçom'],
  toggleResgateIndicacao: ['Admin', 'Operador'], addOrStampFidelidade: ['Admin', 'Operador'],
  resgatarPremioFidelidade: ['Admin', 'Operador'],
  addDespesa: ['Admin', 'Operador'], editarDespesa: ['Admin'], cancelarDespesa: ['Admin'], registrarAjustePosVenda: ['Admin'], cancelarAjustePosVenda: ['Admin'],
  pagarDespesa: ['Admin'], addDespesaRecorrente: ['Admin'], editarDespesaRecorrente: ['Admin'], gerarDespesasMes: ['Admin'],
  addSangria: ['Admin', 'Operador'], salvarMeta: ['Admin'],
  criarUsuario: ['Admin'], editarUsuario: ['Admin'], excluirUsuario: ['Admin'],
  addFormaPagamento: ['Admin'], editarFormaPagamento: ['Admin'],
  addCategoria: ['Admin'], editarCategoria: ['Admin'], excluirCategoria: ['Admin'],
  addIngrediente: ['Admin'], editarIngrediente: ['Admin'], excluirIngrediente: ['Admin'],
  registrarEntradaEstoque: ['Admin'], registrarPerdaEstoque: ['Admin'], registrarInventarioEstoque: ['Admin'],
  addProduto: ['Admin'], editarProduto: ['Admin'], excluirProduto: ['Admin'],
  uploadFotoProduto: ['Admin'], excluirFotoProduto: ['Admin'],
  addCombo: ['Admin'], editarCombo: ['Admin'], excluirCombo: ['Admin'],
  uploadFotoCombo: ['Admin'], excluirFotoCombo: ['Admin'],
  addAdicional: ['Admin'], editarAdicional: ['Admin'], excluirAdicional: ['Admin'], vincularAdicionaisEmLote: ['Admin'],
  editarVisibilidadeCardapioProduto: ['Admin'], editarOrdemCardapioProduto: ['Admin'],
  editarVisibilidadeCardapioCombo: ['Admin'], editarOrdemCardapioCombo: ['Admin'],
  seedCardapioTexasBurger: ['Admin'],
  addMesa: ['Admin'], excluirMesa: ['Admin'],
  editarStatusMesa: ['Admin', 'Operador', 'Garçom'], getQrMesas: ['Admin'], gerarNovoCodigoMesa: ['Admin'], atenderChamadoMesa: ['Admin', 'Operador', 'Garçom'],
  fecharContaMesa: ['Admin', 'Operador', 'Garçom'], // ETAPA 3: garçom recebe só nas SUAS mesas (checado dentro de fecharContaMesa)
  sincronizarContingenciaAgora: ['Admin'], reconciliarContingenciaAgora: ['Admin'], ativarSincronizacaoContingencia: ['Admin'],
  editarStatusFeedback: ['Admin', 'Operador'],
  registrarOcorrencia: ['Admin', 'Operador', 'Garçom', 'Cozinha', 'Entregador'], atualizarOcorrencia: ['Admin', 'Operador'],
  salvarConfigCardapio: ['Admin'], salvarConfigNotificacoes: ['Admin'], salvarConfigEstoque: ['Admin'],
  obterChaveContingencia: ['Admin', 'Operador'], // Garçom/Cozinha/Entregador não usam a fila
  fazerBackupAgora: ['Admin'], obterStatusBackup: ['Admin'],
  configurarBackupAutomatico: ['Admin'], obterArmazenamento: ['Admin'], obterArmazenamentoContingencia: ['Admin'], restaurarBackup: ['Admin'],
  conferirIntegridade: ['Admin'],
  salvarCupom: ['Admin'], editarCupom: ['Admin'], alternarCupom: ['Admin'],
  salvarEvento: ['Admin'], adicionarCustoEvento: ['Admin'], adicionarRecebimentoEvento: ['Admin'], cancelarEvento: ['Admin'],
  aplicarPrecoCalculadora: ['Admin'], simularPrecificacao: ['Admin']
};
function checarPermissao_(action, nivel) {
  if (!Object.prototype.hasOwnProperty.call(PERMISSOES_ACAO, action)) return false; // 'constructor', 'toString'... não herdam regra
  const regra = PERMISSOES_ACAO[action];
  if (!regra) return false; // ação sem regra explícita: negada por padrão
  if (regra === '*') return !!nivel;
  return regra.indexOf(nivel) !== -1;
}
/* Política para NOVAS senhas de funcionário (as atuais continuam valendo até serem trocadas). */
function erroSenhaFraca_(senha, login) {
  const s = String(senha || '');
  if (s.length < 8) return 'A senha precisa ter ao menos 8 caracteres.';
  if (login && s.toLowerCase() === String(login).toLowerCase()) return 'A senha não pode ser igual ao login.';
  if (/^(.)\1+$/.test(s) || ['12345678', '123456789', '1234567890', '87654321', 'senha123', 'password', 'qwertyui', '11111111'].indexOf(s.toLowerCase()) !== -1) return 'Essa senha é fácil demais de adivinhar. Escolha outra.';
  return '';
}
function criarUsuario(novoLogin, novaSenha, nivel, senhaAdminConfirmacao, nome, telefone) {
  if (!novoLogin || !novaSenha || !nivel) return { ok: false, message: 'Preencha login, senha e nível de acesso.' };
  /* MELHORIA 5.2: o login é isento da sanitização (precisa ficar idêntico), então o formato é validado: começa com letra/número, 3 a 30 caracteres, só letras, números, ponto, hífen e sublinhado. Impede login que pareça fórmula (=, +, -, @). */
  if (!/^[A-Za-z0-9\u00C0-\u00FF][A-Za-z0-9\u00C0-\u00FF._-]{2,29}$/.test(String(novoLogin).trim())) return { ok: false, message: 'Login inválido: use de 3 a 30 caracteres (letras, números, ponto, hífen ou sublinhado), começando por letra ou número e sem espaços.' };
  { const fraca = erroSenhaFraca_(novaSenha, novoLogin); if (fraca) return { ok: false, message: fraca }; }
  if (NIVEIS_VALIDOS.indexOf(nivel) === -1) return { ok: false, message: 'Nível de acesso inválido.' };
  if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta.' };
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (String(sh.getRange(i, 1).getValue()).toLowerCase() === novoLogin.toLowerCase()) return { ok: false, message: 'Já existe um usuário com esse login.' };
  }
  sh.appendRow([novoLogin, hashSenha_(novaSenha), nivel, 'Sim', agora(), nome || '', telefone || '', Utilities.getUuid()]);
  registrarLog('Usuário criado', '', novoLogin + ' (' + nivel + ')');
  return { ok: true, message: 'Usuário criado.', usuarios: readUsuarios() };
}
/* ETAPA C: o próprio usuário troca a senha (qualquer perfil). Só mexe no usuário da SESSÃO — o login nunca vem do app.
   Exige a senha atual (com limite de 5 erros / 10 min), aplica a mesma regra de senha forte e derruba as outras sessões
   do usuário (a "marca" da senha muda). Devolve um token novo para este aparelho continuar logado. */
function trocarMinhaSenha(senhaAtual, novaSenha, tokenAtual) {
  if (!USUARIO_ATUAL) return { ok: false, message: 'Sessão inválida. Faça login novamente.' };
  senhaAtual = String(senhaAtual || ''); novaSenha = String(novaSenha || '');
  if (!senhaAtual || !novaSenha) return { ok: false, message: 'Preencha a senha atual e a nova senha.' };
  const chaveBloq = 'falhas_troca_' + String(USUARIO_ATUAL).toLowerCase();
  if (excedeuTentativas_(chaveBloq, 5)) return { ok: false, message: 'Muitas tentativas erradas. Aguarde 10 minutos e tente de novo.' };
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    const linha = sh.getRange(i, 1, 1, 4).getValues()[0];
    if (String(linha[0]).toLowerCase() !== String(USUARIO_ATUAL).toLowerCase()) continue;
    if (linha[3] !== 'Sim') return { ok: false, message: 'Este acesso está desativado.' };
    if (!senhaConfere_(linha[1], senhaAtual)) {
      registrarFalha_(chaveBloq);
      registrarLog('Falha ao trocar a própria senha', '', 'Senha atual incorreta: ' + linha[0]);
      return { ok: false, message: 'A senha atual está incorreta.' };
    }
    if (novaSenha === senhaAtual) return { ok: false, message: 'A nova senha precisa ser diferente da atual.' };
    const fraca = erroSenhaFraca_(novaSenha, linha[0]);
    if (fraca) return { ok: false, message: fraca };
    const novoHash = hashSenha_(novaSenha);
    sh.getRange(i, 2).setValue(novoHash);
    limparFalhas_(chaveBloq);
    const token = criarSessao_(linha[0], linha[2], marcaSenha_(novoHash));
    if (tokenAtual) CacheService.getScriptCache().remove('sess_' + tokenAtual);
    registrarLog('Senha alterada pelo próprio usuário', '', String(linha[0]));
    return { ok: true, message: 'Senha alterada. Em outros aparelhos você precisará entrar de novo.', token: token };
  }
  return { ok: false, message: 'Usuário não encontrado.' };
}
function editarUsuario(loginAlvo, novaSenha, novoNivel, novoAtivo, senhaAdminConfirmacao, nome, telefone) {
  if (nome !== undefined && String(nome).length > 60) return { ok: false, message: 'O nome pode ter no máximo 60 caracteres.' };
  if (telefone !== undefined && String(telefone).length > 25) return { ok: false, message: 'O telefone pode ter no máximo 25 caracteres.' };
  if (novoNivel !== undefined && NIVEIS_VALIDOS.indexOf(novoNivel) === -1) return { ok: false, message: 'Nível de acesso inválido.' };
  if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta.' };
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (String(sh.getRange(i, 1).getValue()).toLowerCase() === String(loginAlvo).toLowerCase()) {
      const nivelAtual = sh.getRange(i, 3).getValue();
      const ativoAtual = sh.getRange(i, 4).getValue();
      const seraAdmin = novoNivel !== undefined ? novoNivel === 'Admin' : nivelAtual === 'Admin';
      const seraAtivo = novoAtivo !== undefined ? (novoAtivo ? 'Sim' : 'Não') : ativoAtual;
      if (nivelAtual === 'Admin' && (!seraAdmin || seraAtivo === 'Não')) {
        const admins = readUsuarios().filter(u => u.nivel === 'Admin' && u.ativo && u.login.toLowerCase() !== loginAlvo.toLowerCase());
        if (admins.length === 0) return { ok: false, message: 'Não é possível remover o último administrador ativo.' };
      }
      if (novaSenha) { const fraca = erroSenhaFraca_(novaSenha, loginAlvo); if (fraca) return { ok: false, message: fraca }; sh.getRange(i, 2).setValue(hashSenha_(novaSenha)); }
      if (novoNivel !== undefined) sh.getRange(i, 3).setValue(novoNivel);
      if (novoAtivo !== undefined) sh.getRange(i, 4).setValue(novoAtivo ? 'Sim' : 'Não');
      let contatoMudou = false;
      if (nome !== undefined && String(nome).trim() !== String(sh.getRange(i, 6).getValue() || '')) { sh.getRange(i, 6).setValue(String(nome).trim()); contatoMudou = true; }
      if (telefone !== undefined && String(telefone).trim() !== String(sh.getRange(i, 7).getValue() || '')) { sh.getRange(i, 7).setValue(String(telefone).trim()); contatoMudou = true; }
      registrarLog('Usuário editado', '', loginAlvo + (novaSenha ? ' (senha alterada)' : '') + (contatoMudou ? ' (nome/telefone alterado)' : '') + (novoNivel !== undefined ? ' nível=' + novoNivel : '') + (novoAtivo !== undefined ? ' ativo=' + (novoAtivo ? 'Sim' : 'Não') : ''));
      return { ok: true, message: 'Usuário atualizado.', usuarios: readUsuarios() };
    }
  }
  return { ok: false, message: 'Usuário não encontrado.' };
}
function excluirUsuario(loginAlvo, senhaAdminConfirmacao) {
  if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta.' };
  const sh = ss_().getSheetByName('Usuários'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (String(sh.getRange(i, 1).getValue()).toLowerCase() === String(loginAlvo).toLowerCase()) {
      if (sh.getRange(i, 3).getValue() === 'Admin') {
        const admins = readUsuarios().filter(u => u.nivel === 'Admin' && u.ativo && u.login.toLowerCase() !== loginAlvo.toLowerCase());
        if (admins.length === 0) return { ok: false, message: 'Não é possível excluir o último administrador.' };
      }
      sh.deleteRow(i);
      registrarLog('Usuário excluído', '', loginAlvo);
      return { ok: true, usuarios: readUsuarios() };
    }
  }
  return { ok: false, message: 'Usuário não encontrado.' };
}
function dataTexto_(v) {
  if (v instanceof Date) return Utilities.formatDate(v, FUSO, 'dd/MM/yyyy HH:mm');
  return String(v || '');
}
/* ETAPA 1: a tela Auditoria lê a aba Auditoria (perfil e quem autorizou), não o Log simples. */
function readLogRecentes(limite) {
  const sh = ss_().getSheetByName('Auditoria');
  if (!sh) return [];
  const last = sh.getLastRow();
  if (last < 2) return [];
  const n = Math.min(limite || 50, last - 1);
  const colsAud = Math.min(7, Math.max(6, sh.getLastColumn()));
  return sh.getRange(last - n + 1, 1, n, colsAud).getValues().reverse()
    .map(r => ({ data: dataTexto_(r[0]), usuario: r[1], perfil: r[2], acao: r[3], detalhes: r[4], autorizador: r[5], aparelho: r[6] || '' }));
}

/* ---------- LEITURA GERAL ---------- */
function getAllDataEntregador_() {
  const login = String(USUARIO_ATUAL).toLowerCase();
  const minhas = readVendas().filter(v => v.tipoEntrega === 'Entrega' && String(v.entregador).toLowerCase() === login)
    .map(v => { const y = Object.assign({}, v); delete y.custoTotal; return y; });
  const ids = {}; minhas.forEach(v => { ids[v.id] = true; });
  const eu = readUsuarios().filter(u => String(u.login).toLowerCase() === login);
  return {
    usuarios: eu,
    vendas: minhas.map(v => Object.assign({}, v)),
    itensVenda: readItensVendaResposta_().filter(it => ids[it.vendaId]),
    configEntrega: readConfigEntrega(),
    configNotificacoes: readConfigNotificacoes(),
    fechamentosEntrega: readFechamentosEntrega().filter(f => String(f.entregador).toLowerCase() === login),
    entregasFechadas: readEntregasFechadas().filter(f => String(f.entregador).toLowerCase() === login),
    ocorrencias: ocorrenciasVisiveis_(readOcorrencias())
  };
}
function readVendasResposta_() {
  const vendas = readVendas();
  if (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador') return vendas;
  if (NIVEL_ATUAL === 'Entregador') {
    // Entregador precisa dos dados operacionais da entrega, mas nunca do custo interno da venda.
    return vendas.filter(v => v.tipoEntrega === 'Entrega' && String(v.entregador).toLowerCase() === String(USUARIO_ATUAL).toLowerCase())
      .map(v => { const y = Object.assign({}, v); delete y.custoTotal; return y; });
  }
  if (NIVEL_ATUAL === 'Garçom') {
    // O garçom recebe somente pedidos das mesas que estão sob sua operação atual.
    const mesasAtivas = readMesas().filter(m => ['Ocupada', 'Aguardando fechamento'].indexOf(m.status) !== -1).map(m => String(m.id));
    const ids = {};
    vendas.forEach(v => {
      const meu = String(v.registradoPor).toLowerCase() === String(USUARIO_ATUAL).toLowerCase();
      if (v.mesaId && mesasAtivas.indexOf(String(v.mesaId)) !== -1 && meu) ids[v.id] = true;
      // pedidos por telefone (entrega/retirada) lançados por ele, até a entrega e o recebimento
      if (!v.mesaId && meu && ['Entrega', 'Retirada'].indexOf(v.tipoEntrega) !== -1 && v.status === 'Confirmada' &&
          ((v.statusPedido !== 'Entregue' && v.statusPedido !== 'Retirada') || v.statusPagamento === 'A Receber')) ids[v.id] = true;
    });
    return vendas.filter(v => !!ids[v.id]);
  }
  if (NIVEL_ATUAL === 'Cozinha') {
    // Cozinha precisa do pedido para produção, mas não de PII operacional nem custos.
    return vendas.map(v => {
      const y = Object.assign({}, v);
      delete y.clienteTelefone;
      delete y.endereco;
      delete y.complemento;
      delete y.referencia;
      delete y.custoTotal;
      return y;
    });
  }
  return [];
}
function readItensVendaResposta_() {
  const itens = readItensVenda();
  if (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador') return itens;
  if (NIVEL_ATUAL === 'Entregador') return itens.map(it => { const y = Object.assign({}, it); delete y.custoUnitario; return y; });
  const ids = {};
  readVendasResposta_().forEach(v => { ids[v.id] = true; });
  return itens.filter(it => ids[it.vendaId]).map(it => {
    if (NIVEL_ATUAL !== 'Cozinha' && NIVEL_ATUAL !== 'Garçom') return it;
    const y = Object.assign({}, it);
    delete y.custoUnitario;
    return y;
  });
}
function readClientesResposta_() {
  const clientes = readClientes();
  if (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador') return clientes;
  if (NIVEL_ATUAL === 'Garçom') {
    // precisa achar qualquer cliente pelo telefone para lançar pedidos por telefone; sem as observações internas
    return clientes.map(c => { const y = Object.assign({}, c); delete y.observacao; return y; });
  }
  // Cozinha e Entregador não precisam da agenda geral de clientes.
  return [];
}
function readIndicacoesResposta_() {
  const indicacoes = readIndicacoes();
  if (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador') return indicacoes;
  if (NIVEL_ATUAL === 'Garçom') {
    const eu = readUsuarios().find(u => String(u.login).toLowerCase() === String(USUARIO_ATUAL).toLowerCase());
    const tel = eu ? normTel(eu.telefone) : '';
    return tel ? indicacoes.filter(i => normTel(i.telIndicador) === tel) : [];
  }
  return [];
}
function readFidelidadeResposta_() {
  const fidelidade = readFidelidade();
  if (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador') return fidelidade;
  if (NIVEL_ATUAL === 'Garçom') {
    const telefones = {};
    readVendasResposta_().forEach(v => { if (v.clienteTelefone) telefones[normTel(v.clienteTelefone)] = true; });
    return fidelidade.filter(f => telefones[normTel(f.telefone)]);
  }
  return [];
}
function readPagamentosVendaResposta_() {
  if (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador') return readPagamentosVenda();
  if (NIVEL_ATUAL === 'Entregador') {
    const ids = {};
    readVendasResposta_().forEach(v => { ids[v.id] = true; });
    return readPagamentosVenda().filter(p => ids[p.vendaId]);
  }
  return [];
}
function readEstoqueResposta_() {
  const estoque = readEstoque();
  if (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador') return estoque;
  return estoque.map(x => { const y = Object.assign({}, x); delete y.custo; return y; });
}

/* ITEM 19 — o getAll agora pode sair em duas partes: 'cad' (cadastro: muda pouco, fica em cache no servidor) e 'din' (o resto). */
function dadosCadastro_() {
  return {
    formasPagamento: readFormasPagamento(),
    categorias: readCategorias(),
    produtos: readProdutos(),
    produtoPrecos: readProdutoPrecos(),
    produtoIngredientes: readProdutoIngredientes(),
    combos: readCombos(),
    comboPrecos: readComboPrecos(),
    comboItens: readComboItens(),
    adicionais: readAdicionais(),
    produtoAdicionais: readProdutoAdicionais(),
    configCardapio: readConfigCardapio(),
    categoriasDespesa: CATEGORIAS_DESPESA,
    configEntrega: readConfigEntrega(),
    configEstoque: { bloquear: String(lerConfigChave_('BLOQUEAR_ESTOQUE_NEGATIVO', 'Não')) === 'Sim' },
    configNotificacoes: readConfigNotificacoes()
  };
}
function cadastroEmCache_(verCad) {
  const chave = 'gd_cad_' + verCad; // a versão faz parte da chave: mudou o cadastro, a chave muda sozinha
  let d = cacheLerJson_(chave);
  if (!d) { d = dadosCadastro_(); cacheGravarJson_(chave, d, 21600); }
  return d;
}
function dadosDinamicos_() {
  return {
    usuarios: readUsuarios(),
    logRecentes: readLogRecentes(50),
    clientes: readClientesResposta_(),
    promocoes: readPromocoes(),
    cupons: NIVEL_ATUAL === 'Admin' ? readCupons() : [],
    eventos: NIVEL_ATUAL === 'Admin' ? readEventos() : [],
    indicacoes: readIndicacoes(),
    fidelidade: readFidelidade(),
    estoque: readEstoqueResposta_(),
    movimentacoesEstoque: readMovimentacoesEstoque(),
    mesas: readMesas(),
    feedbacks: readFeedbacks(),
    ocorrencias: ocorrenciasVisiveis_(readOcorrencias()),
    maisPedidos: maisPedidosEmCache_(),
    vendas: readVendasResposta_(),
    itensVenda: readItensVendaResposta_(),
    pagamentosVenda: readPagamentosVendaResposta_(),
    despesas: readDespesas(),
    despesasRecorrentes: NIVEL_ATUAL === 'Admin' ? readDespesasRecorrentes() : [],
    ajustesPosVenda: NIVEL_ATUAL === 'Admin' ? readAjustesPosVenda() : [],
    sangrias: readSangrias(),
    metas: readMetas(),
    sessaoCaixa: readSessaoAberta(),
    historicoCaixa: readSessoesCaixa(),
    fechamentosEntrega: readFechamentosEntrega(),
    entregasFechadas: readEntregasFechadas()
  };
}
function maisPedidosEmCache_() {
  let m = cacheLerJson_('cd_mais'); // o mesmo cache de 1 hora do cardápio público
  if (!m) { m = { lista: calcularMaisPedidos_() }; cacheGravarJson_('cd_mais', m, CARDAPIO_TTL_MAIS_); }
  return m.lista;
}
function getAllData(grupo) {
  const vers = versoesAtuais_(); // lida ANTES dos dados: se algo mudar durante a leitura, a próxima conferência baixa de novo
  { const cacheEstr = CacheService.getScriptCache();
    if (!cacheEstr.get('estr_ok')) { criarEstruturasNovosRecursos(ss_()); cacheEstr.put('estr_ok', '1', 21600); } } // antes rodava a cada chamada
  if (NIVEL_ATUAL === 'Entregador') return getAllDataEntregador_();
  if (NIVEL_ATUAL === 'Admin' && garantirDespesasDoMes_(false)) bumpVersoes_('trigger');
  const gestor = (NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador');
  if (!gestor) grupo = ''; // só Admin/Operador recebem em partes; os outros perfis continuam recebendo tudo, como hoje
  const quer = g => !grupo || grupo === g;
  const cad = quer('cad') ? cadastroEmCache_(vers.cad) : {}; // MELHORIA 4.2: Garçom e Cozinha também usam o cache (o cadastro não depende do perfil; os filtros de custo/usuário rodam depois, sobre cópias)
  const din = quer('din') ? dadosDinamicos_() : {};
  const dados = Object.assign({}, cad, din);
  // SEGURANÇA: getAll nunca deve entregar dados financeiros/custos a perfis operacionais.
  if (NIVEL_ATUAL !== 'Admin') dados.logRecentes = [];
  if (NIVEL_ATUAL === 'Garçom' || NIVEL_ATUAL === 'Cozinha') {
    ['despesas', 'sangrias', 'historicoCaixa', 'fechamentosEntrega', 'entregasFechadas', 'movimentacoesEstoque'].forEach(k => { dados[k] = []; });
    dados.metas = { mensal: 0, diaria: 0 };
    const eu = String(USUARIO_ATUAL).toLowerCase();
    dados.usuarios = dados.usuarios.filter(u => String(u.login).toLowerCase() === eu);

    // Custos nunca são necessários para a operação de Garçom/Cozinha.
    dados.produtoPrecos = dados.produtoPrecos.map(x => { const y = Object.assign({}, x); delete y.custo; return y; });
    dados.comboPrecos = dados.comboPrecos.map(x => { const y = Object.assign({}, x); delete y.custo; return y; });
    dados.estoque = dados.estoque.map(x => { const y = Object.assign({}, x); delete y.custo; return y; });
    dados.vendas = dados.vendas.map(x => { const y = Object.assign({}, x); delete y.custoTotal; return y; });
    dados.itensVenda = dados.itensVenda.map(x => { const y = Object.assign({}, x); delete y.custoUnitario; return y; });
    // ETAPA 3: o Garçom agora recebe pagamento, então vê as formas ativas — mas nunca taxa %, taxa fixa nem prazo.
    dados.formasPagamento = dados.formasPagamento.map(f => ({ id: f.id, nome: f.nome, ativa: f.ativa, permiteTroco: f.permiteTroco, ordem: f.ordem }));
  }

  if (NIVEL_ATUAL === 'Garçom') {
    // Não existe hoje um campo proprietário em Mesas. Enquanto essa relação não
    // for modelada separadamente, o vínculo operacional é a combinação mesaId +
    // registradoPor nos pedidos de mesa do próprio Garçom. Somente mesas em uso
    // continuam elegíveis para a lista operacional de clientes.
    const mesasEmUso = new Set(dados.mesas.filter(m => ['Ocupada', 'Aguardando fechamento'].indexOf(m.status) !== -1).map(m => String(m.id)));
    const meusPedidosDeMesa = dados.vendas.filter(v => String(v.registradoPor || '').toLowerCase() === String(USUARIO_ATUAL).toLowerCase() && v.mesaId && mesasEmUso.has(String(v.mesaId)));
    const telefonesPermitidos = new Set(meusPedidosDeMesa.map(v => String(v.clienteTelefone || '').trim()).filter(Boolean));
    dados.clientes = dados.clientes.map(c => { const y = Object.assign({}, c); delete y.observacao; return y; });
    dados.fidelidade = dados.fidelidade.filter(f => telefonesPermitidos.has(String(f.telefone || '').trim()));
    dados.indicacoes = [];
    dados.promocoes = [];
    dados.pagamentosVenda = [];
  }

  if (NIVEL_ATUAL === 'Garçom') dados.feedbacks = []; // telefone e comentário dos clientes: só Admin/Operador
  if (NIVEL_ATUAL === 'Cozinha') ['clientes', 'fidelidade', 'indicacoes', 'promocoes', 'pagamentosVenda', 'feedbacks'].forEach(k => { dados[k] = []; });
  dados.versoes = vers; if (grupo) dados.grupo = grupo; // ITEM 19
  return dados;
}

/* ---------- CARDÁPIO PÚBLICO ----------
   Endpoint público (sem login): só devolve o que o cliente pode ver — nunca
   usuários/senhas, clientes, vendas ou financeiro. */
/* ---------- CACHE DO CARDÁPIO PÚBLICO (Etapa 2: velocidade) ----------
   Três camadas, para o cliente não esperar a planilha ser lida a cada abertura:
   - cd_est: itens, preços, adicionais e configurações (muda pouco) -> guardado até 10 min e LIMPO
     automaticamente quando o admin edita produto/preço/adicional/categoria/configuração.
   - cd_din: caixa aberto/fechado e itens esgotados -> 30 segundos.
   - cd_mais: "Mais pedidos" (varre todas as vendas, é o trecho mais pesado) -> 5 minutos (MELHORIA 4.1: antes 1 hora, o ranking não refletia vendas novas). */
const CARDAPIO_TTL_EST_ = 1800, CARDAPIO_TTL_DIN_ = 30, CARDAPIO_TTL_MAIS_ = 300; // estático: 30 min (é limpo na hora quando você edita)
const CARDAPIO_CHUNK_ = 30000; // o cache aceita ~100 KB por chave; fatiamos para nunca estourar
function cacheLerJson_(chave) {
  try {
    const c = CacheService.getScriptCache();
    const n = Number(c.get(chave + '_n'));
    if (!n) return null;
    const keys = []; for (let i = 0; i < n; i++) keys.push(chave + '_' + i);
    const got = c.getAll(keys);
    let txt = ''; for (let i = 0; i < n; i++) { if (got[keys[i]] == null) return null; txt += got[keys[i]]; }
    return JSON.parse(txt);
  } catch (e) { return null; }
}
function cacheGravarJson_(chave, obj, ttl) {
  try {
    const c = CacheService.getScriptCache();
    const txt = JSON.stringify(obj); const partes = {}; let n = 0;
    for (let i = 0; i < txt.length; i += CARDAPIO_CHUNK_) { partes[chave + '_' + n] = txt.slice(i, i + CARDAPIO_CHUNK_); n++; }
    partes[chave + '_n'] = String(n);
    c.putAll(partes, ttl);
  } catch (e) { /* cache é só acelerador: se falhar, o cardápio continua funcionando lendo a planilha */ }
}
function cacheLimpar_(chave) { try { CacheService.getScriptCache().remove(chave + '_n'); } catch (e) {} }
/* Chamado pelo doPost depois de qualquer ação que muda o que o cliente enxerga. */
function invalidarCacheCardapio_(soDinamico) {
  cacheLimpar_('cd_din');
  if (!soDinamico) { cacheLimpar_('cd_est'); cardapioNovaGen_(); }
}
const ACOES_INVALIDAM_CARDAPIO_ = ['addFormaPagamento','editarFormaPagamento','addCategoria','editarCategoria','excluirCategoria','addProduto','editarProduto','excluirProduto','uploadFotoProduto','excluirFotoProduto','addAdicional','editarAdicional','excluirAdicional','vincularAdicionaisEmLote','editarVisibilidadeCardapioProduto','editarOrdemCardapioProduto','editarVisibilidadeCardapioCombo','editarOrdemCardapioCombo','seedCardapioTexasBurger','addCombo','editarCombo','excluirCombo','uploadFotoCombo','excluirFotoCombo','salvarConfigCardapio','salvarConfigEntrega','aplicarPrecoCalculadora','restaurarBackup'];
const ACOES_INVALIDAM_DINAMICO_ = ['abrirCaixa','fecharCaixa','salvarConfigEstoque','addIngrediente','editarIngrediente','excluirIngrediente','registrarEntradaEstoque','registrarPerdaEstoque','registrarInventarioEstoque'];

function montarCardapioEstatico_() {
  const categorias = readCategorias().filter(c => c.ativa);
  const produtos = readProdutos().filter(p => p.ativo)
    .sort((a, b) => a.ordemCardapio - b.ordemCardapio)
    .map(p => ({
      id: p.id, nome: p.nome, descricao: p.descricao, categoria: p.categoria, fotoUrl: p.fotoUrl, destaque: p.destaque
    }));
  const combos = readCombos().filter(c => c.ativo)
    .sort((a, b) => a.ordemCardapio - b.ordemCardapio)
    .map(c => ({
      id: c.id, nome: c.nome, categoria: c.categoria, fotoUrl: c.fotoUrl, destaque: c.destaque
    }));
  const formasPagamento = readFormasPagamento().filter(f => f.ativa && f.visivelCardapio).map(f => ({ id: f.id, nome: f.nome, ativa: true, visivelCardapio: true }));
  const idsFormasAtivas = formasPagamento.map(f => f.id);
  const produtoPrecos = readProdutoPrecos().filter(p => idsFormasAtivas.indexOf(p.formaPagamentoId) !== -1)
    .map(p => ({ produtoId: p.produtoId, formaPagamentoId: p.formaPagamentoId, preco: p.preco }));
  const comboPrecos = readComboPrecos().filter(p => idsFormasAtivas.indexOf(p.formaPagamentoId) !== -1)
    .map(p => ({ comboId: p.comboId, formaPagamentoId: p.formaPagamentoId, preco: p.preco }));
  const adicionais = readAdicionais().filter(a => a.ativo).map(a => ({ id: a.id, nome: a.nome, preco: a.preco }));
  const produtoAdicionais = readProdutoAdicionais();
  const comboItens = readComboItens().map(ci => ({ comboId: ci.comboId, produtoId: ci.produtoId }));
  return {
    categorias: categorias, produtos: produtos, combos: combos,
    formasPagamento: formasPagamento, produtoPrecos: produtoPrecos, comboPrecos: comboPrecos,
    adicionais: adicionais, produtoAdicionais: produtoAdicionais, comboItens: comboItens,
    config: Object.assign({}, readConfigCardapio(), { taxaEntrega: readConfigEntrega().taxaPadrao })
  };
}
/* Itens que o estoque não cobre nem para 1 unidade. Só vale quando o admin ligou "bloquear venda sem estoque". */
function calcularEsgotados_() {
  if (String(lerConfigChave_('BLOQUEAR_ESTOQUE_NEGATIVO', 'Não')) !== 'Sim') return { produtos: [], combos: [] };
  const estoque = {}; readEstoque().forEach(e => { estoque[e.id] = Number(e.quantidade) || 0; });
  const pi = readProdutoIngredientes(); const ci = readComboItens();
  const faltaProduto = (produtoId, vezes) => pi.some(v => v.produtoId === produtoId && v.ingredienteId in estoque && (Number(v.quantidadePorUnidade) || 0) * vezes > 0 && estoque[v.ingredienteId] + 1e-9 < (Number(v.quantidadePorUnidade) || 0) * vezes);
  const produtos = readProdutos().filter(p => p.ativo && faltaProduto(p.id, 1)).map(p => p.id);
  const combos = readCombos().filter(c => c.ativo && ci.some(x => x.comboId === c.id && faltaProduto(x.produtoId, Number(x.quantidade) || 1))).map(c => c.id);
  return { produtos: produtos, combos: combos };
}
function getCardapioPublico() {
  const gen = cardapioGen_();
  let base = cacheLerJson_('cd_est');
  if (!base) { base = montarCardapioEstatico_(); if (cardapioGen_() === gen) cacheGravarJson_('cd_est', base, CARDAPIO_TTL_EST_); } // não guarda se alguém editou durante a leitura
  let din = cacheLerJson_('cd_din');
  if (!din) { din = { caixaAberto: !!readSessaoAberta(), esgotados: calcularEsgotados_() }; cacheGravarJson_('cd_din', din, CARDAPIO_TTL_DIN_); }
  return Object.assign({}, base, { maisPedidos: maisPedidosEmCache_(), caixaAberto: din.caixaAberto, esgotados: din.esgotados });
}
/* "Geração" do cache estático: cada edição de cardápio troca a geração; uma leitura que começou antes da edição não grava dado velho. */
function cardapioGen_() { try { return CacheService.getScriptCache().get('cd_gen') || '0'; } catch (e) { return '0'; } }
function cardapioNovaGen_() { try { CacheService.getScriptCache().put('cd_gen', Date.now() + '-' + Math.floor(Math.random() * 1e6), 21600); } catch (e) {} }
function versaoCardapio_(obj) {
  const bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, JSON.stringify(obj), Utilities.Charset.UTF_8);
  return Utilities.base64EncodeWebSafe(bytes).slice(0, 12);
}
/* Recebe um pedido feito pelo Cardápio público. Nunca confia em preço vindo do navegador —
   recalcula tudo a partir da planilha. */
function criarPedidoCardapio(itens, clienteNome, clienteTelefone, tipoEntrega, dadosEntrega, formaPagamentoId, observacaoTroco, requisicaoId, codigoCupom, mesaCtx) {
  USUARIO_ATUAL = 'Cardápio (cliente)';
  // SEGURANÇA: texto livre do cliente é higienizado antes de tocar a planilha ou o painel.
  clienteNome = textoPublicoSeguro_(clienteNome, 80);
  observacaoTroco = textoPublicoSeguro_(observacaoTroco, 200);
  if (dadosEntrega && typeof dadosEntrega === 'object') {
    dadosEntrega = { endereco: textoPublicoSeguro_(dadosEntrega.endereco, 200), complemento: textoPublicoSeguro_(dadosEntrega.complemento, 100),
      referencia: textoPublicoSeguro_(dadosEntrega.referencia, 150), observacoes: textoPublicoSeguro_(dadosEntrega.observacoes, 300) };
  }
  if (!itens || !itens.length) return { ok: false, message: 'Carrinho vazio.' };
  if (!clienteNome || (!mesaCtx && !clienteTelefone)) return { ok: false, message: mesaCtx ? 'Informe o seu nome.' : 'Informe nome e telefone.' };
  if (!mesaCtx) { const telPub = normTel(clienteTelefone); if (!telPub || telPub.length < 10 || telPub.length > 13) return { ok: false, message: 'Informe um telefone válido com DDD.' }; }
  // SEGURANÇA (Módulo 3): teto geral do cardápio público — sem ele, alguém trocando o número de telefone a cada envio lotaria a cozinha e a trava do sistema.
  if (excedeuTentativas_('pedcard_global', 60)) return { ok: false, message: 'Estamos com muitos pedidos no momento. Tente novamente em alguns minutos ou ligue para o restaurante.' };
  if (itens.length > 40) return { ok: false, message: 'Carrinho grande demais.' };
  // FASE 9 — endpoint público: no máximo 5 pedidos por telefone a cada 10 minutos.
  const chaveTel = mesaCtx ? 'pedmesa_' + mesaCtx.id : 'pedcard_' + normTel(clienteTelefone);
  if (excedeuTentativas_(chaveTel, mesaCtx ? 8 : 5)) return { ok: false, message: mesaCtx ? 'Muitos pedidos em sequência nesta mesa. Chame o garçom.' : 'Muitos pedidos em sequência. Aguarde alguns minutos.' };
  const sessao = readSessaoAberta();
  if (!sessao) return { ok: false, message: 'Estamos fechados no momento. Tente novamente mais tarde.' };
  const tipo = mesaCtx ? 'Mesa' : (tipoEntrega === 'Entrega' ? 'Entrega' : 'Retirada');
  if (tipo === 'Entrega') {
    const de = dadosEntrega || {};
    if (!de.endereco) return { ok: false, message: 'Informe o endereço de entrega.' };
  }
  // Mesa (QR): o cliente não escolhe a forma — vale a primeira forma ativa do cardápio só para o preço; o recebimento real é feito no fechamento da conta.
  const forma = mesaCtx ? readFormasPagamento().filter(f => f.ativa && f.visivelCardapio)[0] : readFormasPagamento().find(f => f.id === formaPagamentoId && f.ativa);
  if (!forma) return { ok: false, message: 'Forma de pagamento inválida.' };
  if (mesaCtx) formaPagamentoId = forma.id;

  const produtos = readProdutos(); const combos = readCombos();
  const produtoPrecos = readProdutoPrecos(); const comboPrecos = readComboPrecos();
  const adicionaisDisponiveis = readAdicionais().filter(a => a.ativo);
  const itensRecalculados = [];
  for (let i = 0; i < itens.length; i++) {
    const it = itens[i];
    const qtd = Number(it.quantidade) || 0;
    if (qtd <= 0) continue;
    if (qtd > 50 || Math.floor(qtd) !== qtd) return { ok: false, message: 'Quantidade inválida no carrinho.' };
    let extraUnit = 0, extraCusto = 0, descAdicionais = '';
    (it.adicionaisIds || []).forEach(adId => {
      const ad = adicionaisDisponiveis.find(a => a.id === adId);
      if (ad) { extraUnit += ad.preco; descAdicionais += ' + ' + ad.nome; }
    });
    { const obsItem = textoPublicoSeguro_(it.observacao, 100); if (obsItem) descAdicionais += ' — Obs: ' + obsItem; } // ex.: "X Salada + Bacon — Obs: sem cebola"
    if (it.produtoId) {
      const p = produtos.find(x => x.id === it.produtoId && x.ativo);
      if (!p) return { ok: false, message: 'Um dos produtos não está mais disponível.' };
      const preco = produtoPrecos.find(pp => pp.produtoId === it.produtoId && pp.formaPagamentoId === formaPagamentoId);
      if (!preco) return { ok: false, message: '"' + p.nome + '" não tem preço configurado para essa forma de pagamento.' };
      itensRecalculados.push({ produtoId: p.id, descricao: p.nome + descAdicionais, quantidade: qtd, valorUnitario: Number(preco.preco) + extraUnit, custoUnitario: Number(preco.custo) + extraCusto, adicionaisIds: (it.adicionaisIds || []) });
    } else if (it.comboId) {
      const c = combos.find(x => x.id === it.comboId && x.ativo);
      if (!c) return { ok: false, message: 'Um dos combos não está mais disponível.' };
      const preco = comboPrecos.find(pp => pp.comboId === it.comboId && pp.formaPagamentoId === formaPagamentoId);
      if (!preco) return { ok: false, message: '"' + c.nome + '" não tem preço configurado para essa forma de pagamento.' };
      itensRecalculados.push({ comboId: c.id, descricao: c.nome + descAdicionais, quantidade: qtd, valorUnitario: Number(preco.preco) + extraUnit, custoUnitario: Number(preco.custo) + extraCusto, adicionaisIds: (it.adicionaisIds || []) });
    }
  }
  if (!itensRecalculados.length) return { ok: false, message: 'Carrinho vazio.' };

  const valorOriginalPedido = Math.round(itensRecalculados.reduce((s, it) => s + it.quantidade * it.valorUnitario, 0) * 100) / 100;
  let promocaoValidada = null;
  if (codigoCupom && !mesaCtx) {
    promocaoValidada = validarCupom_(codigoCupom, clienteTelefone, valorOriginalPedido, tipo, itens, true);
    if (!promocaoValidada.ok) return promocaoValidada;
  }
  const dadosComTaxa = dadosEntrega ? Object.assign({}, dadosEntrega) : {};
  const taxaPedido = tipo === 'Entrega' && !(promocaoValidada && promocaoValidada.freteGratis) ? calcularTaxaEntrega_(dadosComTaxa) : 0;
  const valorTotal = Math.max(0.01, Math.round((valorOriginalPedido - Number(promocaoValidada ? promocaoValidada.desconto : 0) + taxaPedido) * 100) / 100);
  const pagamentos = [{ forma: forma.nome, valor: valorTotal }];
  const dadosComTroco = dadosEntrega ? Object.assign({}, dadosEntrega) : {};
  if (promocaoValidada && promocaoValidada.freteGratis) dadosComTroco.freteGratis = true;
  if (observacaoTroco) dadosComTroco.observacoes = (dadosComTroco.observacoes ? dadosComTroco.observacoes + ' — ' : '') + observacaoTroco;
  const resultado = iniciarVenda(itensRecalculados, clienteNome, clienteTelefone, pagamentos, tipo, dadosComTroco, 'A Receber', null, null, 'Cardápio', mesaCtx ? mesaCtx.id : '', requisicaoId, promocaoValidada);
  if (resultado.ok) {
    if (!resultado.duplicado) { registrarFalha_(chaveTel); registrarFalha_('pedcard_global'); }
    if (promocaoValidada && !resultado.duplicado) { const usoCupom=registrarUsoCupom_(promocaoValidada, resultado.id, clienteTelefone, requisicaoId); if(!usoCupom.ok) registrarLog('Falha ao registrar uso de cupom', resultado.id, usoCupom.message||''); }
    registrarLog(mesaCtx ? 'Pedido recebido pelo cliente na mesa ' + mesaCtx.numero : 'Pedido recebido pelo Cardápio', clienteTelefone || clienteNome, 'Total R$ ' + valorTotal.toFixed(2) + (promocaoValidada ? ' | Cupom ' + promocaoValidada.codigo : ''));
    return { ok: true, message: 'Pedido enviado!' + (resultado.numero ? ' Nº ' + resultado.numero + '.' : '') + ' Total: R$ ' + valorTotal.toFixed(2) + '.', id: resultado.id, numero: resultado.numero || 0, valorTotal: valorTotal, valorOriginal: valorOriginalPedido, valorDesconto: promocaoValidada ? promocaoValidada.desconto : 0, cupom: promocaoValidada ? promocaoValidada.codigo : '', freteGratis: !!(promocaoValidada && promocaoValidada.freteGratis) };
  }
  return resultado;
}

/* ---------- CLIENTES ---------- */
function upsertCliente(telefone, nome) {
  if (!telefone) return '';
  const sh = ss_().getSheetByName('Clientes');
  const tel = normTel(telefone);
  const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (normTel(sh.getRange(i, 3).getValue()) === tel) {
      if (nome && !sh.getRange(i, 2).getValue()) sh.getRange(i, 2).setValue(nome);
      return sh.getRange(i, 1).getValue(); // ETAPA 2: devolve o ID permanente do cliente
    }
  }
  const novoId = Utilities.getUuid();
  sh.appendRow([novoId, nome || '', telefone, '', '', '', agora(), '']);
  return novoId;
}
/* ETAPA 2: ID permanente do cliente a partir do telefone ('' se não existir). O telefone continua sendo a busca rápida. */
function idClientePorTelefone_(telefone) {
  if (!telefone) return '';
  const sh = ss_().getSheetByName('Clientes'); const last = sh.getLastRow();
  if (last < 2) return '';
  const tel = normTel(telefone);
  const v = sh.getRange(2, 1, last - 1, 3).getValues(); // MELHORIA 4.3: uma leitura só (antes: dois acessos à planilha por linha)
  for (let i = 0; i < v.length; i++) { if (normTel(v[i][2]) === tel) return v[i][0]; }
  return '';
}
function salvarCliente(idOuTelefoneOriginal, nome, telefone, dataNascimento, endereco, comoConheceu, observacao) {
  if (!nome || !telefone) return { ok: false, message: 'Nome e telefone são obrigatórios.' };
  const sh = ss_().getSheetByName('Clientes');
  const tel = normTel(telefone);
  const last = sh.getLastRow();
  // aceita tanto um ID de cliente já existente quanto (por compatibilidade) o telefone original
  const idAlvo = idOuTelefoneOriginal || null;
  for (let i = 2; i <= last; i++) {
    const telLinha = normTel(sh.getRange(i, 3).getValue());
    const idLinha = sh.getRange(i, 1).getValue();
    const ehMesmoRegistro = idAlvo && (idLinha === idAlvo || telLinha === normTel(idAlvo));
    if (telLinha === tel && !ehMesmoRegistro) return { ok: false, message: 'Já existe outro cliente cadastrado com esse telefone.' };
  }
  if (idAlvo) {
    for (let i = 2; i <= last; i++) {
      const idLinha = sh.getRange(i, 1).getValue();
      const telLinha = normTel(sh.getRange(i, 3).getValue());
      if (idLinha === idAlvo || telLinha === normTel(idAlvo)) {
        if (NIVEL_ATUAL === 'Garçom') {
          const permitido = readClientesResposta_().some(c => String(c.id) === String(idLinha));
          if (!permitido) return { ok: false, message: 'Este cliente não está no seu escopo operacional.' };
        }
        sh.getRange(i, 2, 1, 5).setValues([[nome, telefone, String(dataNascimento || ''), endereco || '', comoConheceu || '']]);
        if (observacao !== undefined) sh.getRange(i, 8).setValue(observacao || '');
        registrarLog('Cliente atualizado', telefone, nome);
        return { ok: true, message: 'Cadastro atualizado.', clientes: readClientesResposta_() };
      }
    }
    return { ok: false, message: 'Cliente não encontrado para edição.' };
  }
  sh.appendRow([Utilities.getUuid(), nome, telefone, String(dataNascimento || ''), endereco || '', comoConheceu || '', agora(), observacao || '']);
  registrarLog('Cliente cadastrado', telefone, nome);
  return { ok: true, message: 'Cliente cadastrado.', clientes: readClientesResposta_() };
}
function excluirCliente(id, senhaAdminConfirmacao) {
  if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta.' };
  const sh = ss_().getSheetByName('Clientes');
  const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 1).getValue() === id) { sh.deleteRow(i); break; } }
  registrarLog('Cliente excluído', '', id);
  return { ok: true, clientes: readClientesResposta_() };
}
function indicarNovoCliente(telIndicador, nomeIndicador, nome, telefone, dataNascimento, endereco, comoConheceu, observacao) {
  const resCliente = salvarCliente(null, nome, telefone, dataNascimento, endereco, comoConheceu, observacao);
  if (!resCliente.ok) return resCliente;
  const resIndicacao = addIndicacao(nomeIndicador, telIndicador, nome, telefone, '');
  return {
    ok: true,
    message: resIndicacao.ok ? ('Cliente cadastrado e indicação registrada! ' + nomeIndicador + ' ganhará 1 batata pequena na próxima compra.') : ('Cliente cadastrado, mas: ' + resIndicacao.message),
    clientes: readClientesResposta_(), indicacoes: readIndicacoesResposta_()
  };
}

/* ---------- LOG ---------- */
function registrarLog(acao, telefone, detalhes) {
  ss_().getSheetByName('Log').appendRow([agora(), acao, telefone || '', detalhes || '', USUARIO_ATUAL || '']);
  if (ACOES_AUDITADAS_RE.test(String(acao))) registrarAuditoria_(acao, (telefone ? '[' + telefone + '] ' : '') + (detalhes || ''));
}

/* ---------- LEITURA ---------- */
function readClientes() {
  const sh = ss_().getSheetByName('Clientes'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 8).getValues().filter(r => r[1]).map(r => ({ id: r[0], nome: r[1], telefone: r[2], dataNascimento: String(r[3]||''), endereco: r[4], comoConheceu: r[5], primeiroContato: r[6], observacao: r[7] }));
}
function readFormasPagamento() {
  const sh = ss_().getSheetByName('Formas de Pagamento'); const last = sh.getLastRow();
  if (last < 2) return [];
  const colunas = Math.min(9, sh.getMaxColumns());
  const linhas = sh.getRange(2, 1, last - 1, colunas).getValues().filter(r => r[1]);
  return linhas.map((r, idx) => ({
    id: r[0], nome: r[1], ativa: r[2] !== 'Não', visivelCardapio: r[3] !== 'Não',
    taxaPct: numPlanilha_(r[4]) || 0, taxaFixa: numPlanilha_(r[5]) || 0, prazoDias: numPlanilha_(r[6]) || 0,
    permiteTroco: r[7] === 'Sim' || (r[7] === '' && r[1] === 'Dinheiro'),
    ordem: numPlanilha_(r[8]) || (idx + 1)
  })).sort((a, b) => a.ordem - b.ordem);
}
/* Taxa de UM pagamento = valor x taxa% + taxa fixa (fixa cobrada por pagamento). Sem taxa = 0. */
function calcularTaxaPagamento_(nomeForma, valor) {
  const f = readFormasPagamento().find(x => x.nome === nomeForma);
  const v = Number(valor) || 0;
  if (!f || v <= 0) return 0;
  return Math.round((v * f.taxaPct / 100 + f.taxaFixa) * 100) / 100;
}
function readProdutoPrecos() {
  const sh = ss_().getSheetByName('ProdutoPrecos'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 5).getValues().filter(r => r[1]).map(r => ({ id: r[0], produtoId: r[1], formaPagamentoId: r[2], preco: numPlanilha_(r[3]), custo: numPlanilha_(r[4]) }));
}
function readComboPrecos() {
  const sh = ss_().getSheetByName('ComboPrecos'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 5).getValues().filter(r => r[1]).map(r => ({ id: r[0], comboId: r[1], formaPagamentoId: r[2], preco: numPlanilha_(r[3]), custo: numPlanilha_(r[4]) }));
}
function readPromocoes() {
  const sh = ss_().getSheetByName('Promoções'); if (!sh) return [];
  const last = sh.getLastRow(); if (last < 2) return [];
  return sh.getRange(2,1,last-1,Math.min(5,sh.getMaxColumns())).getValues().filter(r=>r[0]).map(r=>({nome:r[0],tipo:r[1],regra:r[2],beneficio:r[3],ativa:r[4]==='Sim'}));
}
function readCupons() {
  const sh = ss_().getSheetByName('Cupons'); if (!sh) return [];
  const last=sh.getLastRow(); if(last<2) return [];
  return sh.getRange(2,1,last-1,17).getValues().filter(r=>r[0]||r[1]).map(r=>({
    id:r[0]||'', codigo:String(r[1]||'').trim().toUpperCase(), nome:r[2]||'', tipo:r[3]||'percentual', valor:numPlanilha_(r[4])||0,
    freteGratis:r[5]===true||String(r[5]).toLowerCase()==='sim', dataInicio:r[6]||'', dataFim:r[7]||'', horaInicio:r[8]||'', horaFim:r[9]||'',
    limiteTotal:numPlanilha_(r[10])||0, limitePorCliente:numPlanilha_(r[11])||0, valorMinimo:numPlanilha_(r[12])||0, ativa:r[13]!==false&&String(r[13]).toLowerCase()!=='não', acumula:r[14]===true||String(r[14]).toLowerCase()==='sim', criadoEm:r[15]||'', criadoPor:r[16]||''
  }));
}
function readCuponsUsos_() {
  const sh=ss_().getSheetByName('CuponsUsos'); if(!sh) return [];
  const last=sh.getLastRow(); if(last<2) return [];
  return sh.getRange(2,1,last-1,10).getValues().filter(r=>r[0]).map(r=>({id:r[0],cupomId:r[1],codigo:r[2],vendaId:r[3],clienteId:r[4],telefone:r[5],desconto:numPlanilha_(r[6])||0,freteGratis:r[7]===true||String(r[7]).toLowerCase()==='sim',data:r[8],requisicao:r[9]}));
}
function dataCupomValidoHoje_(c) {
  const agora=new Date();
  const d=dt=>dt?new Date(dt):null;
  if(c.dataInicio){const x=d(c.dataInicio); if(x && agora < new Date(x.getFullYear(),x.getMonth(),x.getDate(),0,0,0)) return false;}
  if(c.dataFim){const x=d(c.dataFim); if(x && agora > new Date(x.getFullYear(),x.getMonth(),x.getDate(),23,59,59)) return false;}
  const hh=agora.getHours()*60+agora.getMinutes();
  const toMin=v=>{ if(!v)return null; const m=String(v).match(/(\d{1,2}):(\d{2})/); return m?Number(m[1])*60+Number(m[2]):null; };
  const hi=toMin(c.horaInicio), hf=toMin(c.horaFim); if(hi!==null&&hf!==null){ if(hi<=hf ? (hh<hi||hh>hf) : (hh>hf&&hh<hf)) return false; }
  return true;
}
function validarCupom_(codigo, telefone, subtotal, tipoEntrega, itens, confirmarUso) {
  criarEstruturasNovosRecursos(ss_());
  const cod=String(codigo||'').trim().toUpperCase(); if(!cod) return {ok:false,message:'Informe um cupom.'};
  const c=readCupons().find(x=>x.codigo===cod);
  if(!c || !c.ativa) return {ok:false,message:'Cupom inválido ou inativo.'};
  if(!dataCupomValidoHoje_(c)) return {ok:false,message:'Este cupom está fora do período de validade.'};
  const usos=readCuponsUsos_().filter(u=>u.cupomId===c.id);
  if(c.limiteTotal>0 && usos.length>=c.limiteTotal) return {ok:false,message:'O limite de utilizações deste cupom foi atingido.'};
  const tel=normTel(telefone);
  const usosCliente=tel?usos.filter(u=>normTel(u.telefone)===tel):[];
  if(c.limitePorCliente>0 && usosCliente.length>=c.limitePorCliente) return {ok:false,message:'Você já atingiu o limite de uso deste cupom.'};
  const bruto=Math.round(Number(subtotal||0)*100)/100;
  if(bruto < c.valorMinimo) return {ok:false,message:'Este cupom exige pedido mínimo de R$ '+c.valorMinimo.toFixed(2).replace('.',',')+'.'};
  let desconto=0;
  if(c.tipo==='percentual') { if(c.valor<=0||c.valor>100) return {ok:false,message:'Cupom configurado com percentual inválido.'}; desconto=Math.round(bruto*c.valor)/100; }
  else if(c.tipo==='fixo') { if(c.valor<=0) return {ok:false,message:'Cupom configurado com valor inválido.'}; desconto=Math.min(bruto,Math.round(c.valor*100)/100); }
  else if(c.tipo==='frete') desconto=0;
  else return {ok:false,message:'Tipo de cupom não suportado.'};
  desconto=Math.min(desconto,Math.max(0,bruto-0.01));
  return {ok:true,cupomId:c.id,codigo:c.codigo,nome:c.nome,tipo:c.tipo,desconto:Number(desconto.toFixed(2)),freteGratis:!!c.freteGratis||c.tipo==='frete',acumula:!!c.acumula,limiteRestante:c.limiteTotal>0?Math.max(0,c.limiteTotal-usos.length-1):null};
}
function validarCupomCardapio(codigo, telefone, subtotal, tipoEntrega, itens) {
  // SEGURANÇA (Módulo 3): endpoint público — limita tentativas erradas para ninguém descobrir cupons por tentativa e erro.
  const chaveTel = 'cupfalha_' + (normTel(telefone) || 'anon');
  if (excedeuTentativas_(chaveTel, 8) || excedeuTentativas_('cupfalha_global', 150)) return { ok: false, message: 'Muitas tentativas de cupom. Aguarde alguns minutos.' };
  const subNum = Number(subtotal);
  if (!isFinite(subNum) || subNum < 0 || subNum > 5000) return { ok: false, message: 'Valor do pedido inválido para aplicar cupom.' }; // a prévia confiava no subtotal enviado; o valor cobrado é sempre recalculado
  const r = validarCupom_(codigo, telefone, subtotal, tipoEntrega, itens, false);
  if (!r.ok && /inválido ou inativo/.test(String(r.message || ''))) { registrarFalha_(chaveTel); registrarFalha_('cupfalha_global'); }
  return r;
}
function registrarUsoCupom_(validacao, vendaId, telefone, requisicaoId) {
  if(!validacao || !validacao.ok) return {ok:true};
  const lock=LockService.getScriptLock(); if(!lock.tryLock(20000)) return {ok:false,message:'Cupom temporariamente ocupado. Tente novamente.'};
  try {
    const sh=ss_().getSheetByName('CuponsUsos'); const usos=readCuponsUsos_();
    if(requisicaoId && usos.some(u=>u.requisicao===requisicaoId)) return {ok:true};
    const c=readCupons().find(x=>x.id===validacao.cupomId); if(!c||!c.ativa) return {ok:false,message:'Cupom deixou de estar disponível.'};
    const usosCupom=usos.filter(u=>u.cupomId===c.id); const tel=normTel(telefone);
    if(c.limiteTotal>0 && usosCupom.length>=c.limiteTotal) return {ok:false,message:'O limite deste cupom foi atingido.'};
    if(c.limitePorCliente>0 && usosCupom.filter(u=>normTel(u.telefone)===tel).length>=c.limitePorCliente) return {ok:false,message:'Limite do cupom para este cliente atingido.'};
    const clienteId=idClientePorTelefone_(telefone)||'';
    sh.appendRow([Utilities.getUuid(),validacao.cupomId,validacao.codigo,vendaId,clienteId,telefone||'',validacao.desconto||0,validacao.freteGratis?'Sim':'Não',agora(),requisicaoId||'']);
    return {ok:true};
  } finally { lock.releaseLock(); }
}
function salvarCupom(codigo,nome,tipo,valor,freteGratis,dataInicio,dataFim,horaInicio,horaFim,limiteTotal,limitePorCliente,valorMinimo,ativa,acumula) {
  if(NIVEL_ATUAL!=='Admin') return {ok:false,message:'Apenas Administrador pode criar cupons.'};
  codigo=String(codigo||'').trim().toUpperCase().replace(/\s+/g,''); nome=String(nome||'').trim(); tipo=String(tipo||'percentual');
  if(!/^[A-Z0-9_-]{3,40}$/.test(codigo)) return {ok:false,message:'Código inválido. Use letras, números, _ ou -.'};
  if(!nome) return {ok:false,message:'Informe o nome da promoção.'};
  if(['percentual','fixo','frete'].indexOf(tipo)<0) return {ok:false,message:'Tipo de cupom inválido.'};
  valor=Number(valor)||0; if(tipo!=='frete'&&(!Number.isFinite(valor)||valor<=0)) return {ok:false,message:'Valor do benefício inválido.'};
  if(tipo==='percentual'&&valor>100) return {ok:false,message:'Percentual não pode ultrapassar 100%.'};
  limiteTotal=Math.max(0,Math.floor(Number(limiteTotal)||0)); limitePorCliente=Math.max(0,Math.floor(Number(limitePorCliente)||0)); valorMinimo=Math.max(0,Number(valorMinimo)||0);
  const sh=ss_().getSheetByName('Cupons'); const usos=readCupons(); if(usos.some(c=>c.codigo===codigo)) return {ok:false,message:'Já existe um cupom com esse código.'};
  const id=Utilities.getUuid(); sh.appendRow([id,codigo,nome,tipo,valor,freteGratis?'Sim':'Não',dataInicio||'',dataFim||'',horaInicio||'',horaFim||'',limiteTotal,limitePorCliente,valorMinimo,ativa===false?'Não':'Sim',acumula?'Sim':'Não',agora(),USUARIO_ATUAL||'']);
  registrarLog('Cupom criado',codigo,nome+' | benefício '+tipo+' '+valor);
  return {ok:true,message:'Cupom criado.',cupons:readCupons()};
}
function editarCupom(id,codigo,nome,tipo,valor,freteGratis,dataInicio,dataFim,horaInicio,horaFim,limiteTotal,limitePorCliente,valorMinimo,ativa,acumula){
  if(NIVEL_ATUAL!=='Admin') return {ok:false,message:'Apenas Administrador pode editar cupons.'};
  const sh=ss_().getSheetByName('Cupons'); const last=sh.getLastRow(); for(let i=2;i<=last;i++){ if(sh.getRange(i,1).getValue()===id){
    codigo=String(codigo||'').trim().toUpperCase().replace(/\s+/g,''); valor=Number(valor)||0;
    if(!codigo||!nome||['percentual','fixo','frete'].indexOf(tipo)<0) return {ok:false,message:'Dados do cupom inválidos.'};
    if(tipo==='percentual'&&(valor<=0||valor>100)) return {ok:false,message:'Percentual inválido.'};
    if(tipo!=='frete'&&valor<=0) return {ok:false,message:'Valor inválido.'};
    sh.getRange(i,2,1,14).setValues([[codigo,nome,tipo,valor,freteGratis?'Sim':'Não',dataInicio||'',dataFim||'',horaInicio||'',horaFim||'',Math.max(0,Math.floor(Number(limiteTotal)||0)),Math.max(0,Math.floor(Number(limitePorCliente)||0)),Math.max(0,Number(valorMinimo)||0),ativa===false?'Não':'Sim',acumula?'Sim':'Não']]);
    registrarLog('Cupom alterado',codigo,nome); return {ok:true,message:'Cupom atualizado.',cupons:readCupons()};
  }} return {ok:false,message:'Cupom não encontrado.'};
}
function alternarCupom(id,ativo){ if(NIVEL_ATUAL!=='Admin') return {ok:false,message:'Acesso negado.'}; const sh=ss_().getSheetByName('Cupons'); const last=sh.getLastRow(); for(let i=2;i<=last;i++) if(sh.getRange(i,1).getValue()===id){sh.getRange(i,14).setValue(ativo?'Sim':'Não'); registrarLog(ativo?'Cupom ativado':'Cupom desativado',id,''); return {ok:true,cupons:readCupons()};} return {ok:false,message:'Cupom não encontrado.'}; }

function readEventos() {
  const sh=ss_().getSheetByName('Eventos'); if(!sh)return [];
  const last=sh.getLastRow(); if(last<2)return [];
  return sh.getRange(2,1,last-1,19).getValues().filter(r=>r[0]).map(r=>({id:r[0],nome:r[1],tipo:r[2],data:r[3],horaInicio:r[4],horaFim:r[5],local:r[6],contratante:r[7],telefone:r[8],status:r[9],valorContratado:numPlanilha_(r[10])||0,valorRecebido:numPlanilha_(r[11])||0,valorAReceber:numPlanilha_(r[12])||0,custoTotal:numPlanilha_(r[13])||0,resultado:numPlanilha_(r[14])||0,observacoes:r[15]||'',criadoEm:r[16],criadoPor:r[17],atualizadoEm:r[18]}));
}
function recalcularEvento_(eventoId){
  const sh=ss_().getSheetByName('Eventos'); const last=sh.getLastRow(); let row=0,ev=null; for(let i=2;i<=last;i++){if(sh.getRange(i,1).getValue()===eventoId){row=i;ev=readEventos().find(x=>x.id===eventoId);break;}} if(!row)return null;
  const custos=readEventoCustos_(eventoId).reduce((s,x)=>s+x.valor,0); const rec=readEventoRecebimentos_(eventoId).reduce((s,x)=>s+x.valor,0); const contratado=ev.valorContratado;
  sh.getRange(row,12,1,4).setValues([[rec,Math.max(0,contratado-rec),custos,Math.round((contratado-custos)*100)/100]]); sh.getRange(row,19).setValue(agora());
  return readEventos().find(x=>x.id===eventoId);
}
function readEventoCustos_(eventoId){const sh=ss_().getSheetByName('EventosCustos');if(!sh)return[];const l=sh.getLastRow();if(l<2)return[];return sh.getRange(2,1,l-1,9).getValues().filter(r=>r[0]&&r[1]===eventoId).map(r=>({id:r[0],eventoId:r[1],descricao:r[2],categoria:r[3],valor:numPlanilha_(r[4])||0,data:r[5],observacao:r[6]||'',criadoEm:r[7],criadoPor:r[8]}));}
function readEventoRecebimentos_(eventoId){const sh=ss_().getSheetByName('EventosRecebimentos');if(!sh)return[];const l=sh.getLastRow();if(l<2)return[];return sh.getRange(2,1,l-1,9).getValues().filter(r=>r[0]&&r[1]===eventoId).map(r=>({id:r[0],eventoId:r[1],valor:numPlanilha_(r[2])||0,forma:r[3]||'',data:r[4],observacao:r[5]||'',criadoEm:r[6],criadoPor:r[7],requisicaoId:r[8]||''}));}
function salvarEvento(id,nome,tipo,data,horaInicio,horaFim,local,contratante,telefone,status,valorContratado,observacoes){
  if(NIVEL_ATUAL!=='Admin')return{ok:false,message:'Apenas Administrador pode gerenciar eventos.'};
  nome=String(nome||'').trim(); if(!nome||!data)return{ok:false,message:'Informe nome e data do evento.'};
  const statusValidos=['Orçamento','Confirmado','Em andamento','Concluído','Cancelado']; status=statusValidos.indexOf(status||'')>=0?(status||'Orçamento'):'Orçamento';
  valorContratado=Number(valorContratado); if(!Number.isFinite(valorContratado)||valorContratado<0)return{ok:false,message:'Valor contratado inválido.'};
  const sh=ss_().getSheetByName('Eventos'); if(id){const l=sh.getLastRow();for(let i=2;i<=l;i++)if(sh.getRange(i,1).getValue()===id){sh.getRange(i,2,1,10).setValues([[nome,tipo||'',data,horaInicio||'',horaFim||'',local||'',contratante||'',telefone||'',status||'Orçamento',valorContratado]]);sh.getRange(i,16).setValue(observacoes||'');sh.getRange(i,19).setValue(agora());const ev=recalcularEvento_(id);registrarLog('Evento alterado',id,nome);return{ok:true,message:'Evento atualizado.',evento:ev,eventos:readEventos()};}}
  const novo=Utilities.getUuid();sh.appendRow([novo,nome,tipo||'',data,horaInicio||'',horaFim||'',local||'',contratante||'',telefone||'',status||'Orçamento',valorContratado,0,valorContratado,0,valorContratado,observacoes||'',agora(),USUARIO_ATUAL||'',agora()]);registrarLog('Evento criado',novo,nome);return{ok:true,message:'Evento criado.',evento:readEventos().find(x=>x.id===novo),eventos:readEventos()};
}
function adicionarCustoEvento(eventoId,descricao,categoria,valor,data,observacao,requisicaoId){
  if(NIVEL_ATUAL!=='Admin')return{ok:false,message:'Apenas Administrador pode lançar custos de eventos.'}; if(!readEventos().some(e=>e.id===eventoId))return{ok:false,message:'Evento não encontrado.'}; valor=Number(valor)||0;if(valor<=0)return{ok:false,message:'Valor inválido.'};
  const sh=ss_().getSheetByName('EventosCustos'); const req=String(requisicaoId||''); const l=sh.getLastRow();if(req&&l>=2&&sh.getRange(2,9,l-1,1).getValues().some(r=>r[0]===req))return{ok:true,message:'Lançamento já registrado.',evento:recalcularEvento_(eventoId)};
  sh.appendRow([Utilities.getUuid(),eventoId,descricao||'',categoria||'Outros',valor,data||new Date(),observacao||'',agora(),USUARIO_ATUAL||'']);const ev=recalcularEvento_(eventoId);registrarLog('Custo de evento lançado',eventoId,descricao+' R$ '+valor.toFixed(2));return{ok:true,message:'Custo lançado.',evento:ev,custos:readEventoCustos_(eventoId)};
}
function adicionarRecebimentoEvento(eventoId,valor,forma,data,observacao,requisicaoId){
  if(NIVEL_ATUAL!=='Admin')return{ok:false,message:'Apenas Administrador pode lançar recebimentos de eventos.'}; const evAtual=readEventos().find(e=>e.id===eventoId); if(!evAtual)return{ok:false,message:'Evento não encontrado.'}; valor=Number(valor)||0;if(!Number.isFinite(valor)||valor<=0)return{ok:false,message:'Valor inválido.'};
  if(forma && !readFormasPagamento().some(f=>f.ativa && f.nome===forma))return{ok:false,message:'Forma de pagamento inválida.'};
  if(valor>Math.max(0,Number(evAtual.valorAReceber)||0)+0.01)return{ok:false,message:'O recebimento não pode ultrapassar o valor a receber do evento.'};
  const sh=ss_().getSheetByName('EventosRecebimentos'); const req=String(requisicaoId||''); const l=sh.getLastRow();if(req&&l>=2&&sh.getRange(2,9,l-1,1).getValues().some(r=>r[0]===req))return{ok:true,message:'Recebimento já registrado.',evento:recalcularEvento_(eventoId)};
  sh.appendRow([Utilities.getUuid(),eventoId,valor,forma||'',data||new Date(),observacao||'',agora(),USUARIO_ATUAL||'',req]);const ev=recalcularEvento_(eventoId);registrarLog('Recebimento de evento lançado',eventoId,'R$ '+valor.toFixed(2)+' '+(forma||''));return{ok:true,message:'Recebimento registrado.',evento:ev,recebimentos:readEventoRecebimentos_(eventoId)};
}
function cancelarEvento(id,motivo){if(NIVEL_ATUAL!=='Admin')return{ok:false,message:'Acesso negado.'};const sh=ss_().getSheetByName('Eventos');const l=sh.getLastRow();for(let i=2;i<=l;i++)if(sh.getRange(i,1).getValue()===id){sh.getRange(i,10).setValue('Cancelado');sh.getRange(i,16).setValue((sh.getRange(i,16).getValue()||'')+(motivo?' | Cancelamento: '+motivo:''));sh.getRange(i,19).setValue(agora());registrarLog('Evento cancelado',id,motivo||'');return{ok:true,message:'Evento cancelado.',eventos:readEventos()};}return{ok:false,message:'Evento não encontrado.'};}
function simularPrecificacao(produtoId,formaPagamentoId,precoSimulado,embalagem,outrosCustos,taxaMarketplace){
  if(NIVEL_ATUAL!=='Admin')return{ok:false,message:'Acesso negado.'};
  const p=readProdutos().find(x=>x.id===produtoId); if(!p)return{ok:false,message:'Produto não encontrado.'};
  const f=readFormasPagamento().find(x=>x.id===formaPagamentoId&&x.ativa); if(!f)return{ok:false,message:'Forma de pagamento não encontrada.'};
  const prec=readProdutoPrecos().find(x=>x.produtoId===produtoId&&x.formaPagamentoId===formaPagamentoId); if(!prec)return{ok:false,message:'Preço do produto para esta forma de pagamento não encontrado.'};
  const ficha=readProdutoIngredientes().filter(x=>x.produtoId===produtoId); const ing=readEstoque();
  let custoTecnico=0; ficha.forEach(x=>{const i=ing.find(y=>y.id===x.ingredienteId); custoTecnico+=(i?Number(i.custo)||0:0)*(Number(x.quantidadePorUnidade)||0);});
  if(custoTecnico<=0)custoTecnico=Number(prec.custo)||0;
  const preco=Number(precoSimulado); if(!Number.isFinite(preco)||preco<=0)return{ok:false,message:'Preço simulado inválido.'};
  const emb=Math.max(0,Number(embalagem)||0), outros=Math.max(0,Number(outrosCustos)||0), mp=Math.max(0,Number(taxaMarketplace)||0);
  const taxaPagamento=Math.round((preco*f.taxaPct/100+f.taxaFixa)*100)/100;
  const taxaMp=Math.round(preco*mp/100*100)/100;
  const custoTotal=Math.round((custoTecnico+emb+outros+taxaPagamento+taxaMp)*100)/100;
  const resultado=Math.round((preco-custoTotal)*100)/100;
  const margem=preco>0?resultado/preco*100:0; const markup=custoTotal>0?preco/custoTotal:0;
  return{ok:true,produto:p.nome,formaPagamento:f.nome,precoAtual:Number(prec.preco)||0,precoSimulado:preco,custoTecnico:Number(custoTecnico.toFixed(2)),embalagem:emb,outrosCustos:outros,taxaPagamento:Number(taxaPagamento.toFixed(2)),taxaPagamentoPct:f.taxaPct,taxaPagamentoFixa:f.taxaFixa,taxaMarketplace:Number(taxaMp.toFixed(2)),taxaMarketplacePct:mp,custoTotal,resultado,margem:Number(margem.toFixed(2)),markup:Number(markup.toFixed(2))};
}
function aplicarPrecoCalculadora(produtoId,formaPagamentoId,novoPreco){
  if(NIVEL_ATUAL!=='Admin')return{ok:false,message:'Acesso negado.'}; novoPreco=Number(novoPreco);if(!Number.isFinite(novoPreco)||novoPreco<=0)return{ok:false,message:'Preço inválido.'};
  const sh=ss_().getSheetByName('ProdutoPrecos');const l=sh.getLastRow();for(let i=2;i<=l;i++){if(sh.getRange(i,2).getValue()===produtoId&&sh.getRange(i,3).getValue()===formaPagamentoId){const antigo=numPlanilha_(sh.getRange(i,4).getValue())||0;sh.getRange(i,4).setValue(novoPreco);registrarLog('Preço aplicado pela calculadora',produtoId,'Forma '+formaPagamentoId+' | R$ '+antigo.toFixed(2)+' → R$ '+novoPreco.toFixed(2));return{ok:true,message:'Preço aplicado.',produtoPrecos:readProdutoPrecos()};}}return{ok:false,message:'Preço do produto para esta forma de pagamento não encontrado.'};}
function readIndicacoes() {
  const sh = ss_().getSheetByName('Indicações'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, Math.min(9, sh.getMaxColumns())).getValues().filter(r => r[1]).map(r => ({ nomeIndicador: r[0], telIndicador: r[1], nomeIndicado: r[2], telIndicado: r[3], data: r[4], resgatado: r[5] === 'Resgatado', observacao: r[6], idIndicador: r[7] || '', idIndicado: r[8] || '' }));
}
function readFidelidade() {
  const sh = ss_().getSheetByName('Fidelidade'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, Math.min(7, sh.getMaxColumns())).getValues().filter(r => r[1]).map(r => ({ nome: r[0], telefone: r[1], carimbos: numPlanilha_(r[2]), premios: numPlanilha_(r[3]), atualizado: r[4], observacao: r[5], clienteId: r[6] || '' }));
}
function urlFoto_(fotoId) { return fotoId ? ('https://drive.google.com/uc?export=view&id=' + fotoId) : ''; }
function readProdutos() {
  const sh = ss_().getSheetByName('Produtos'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 9).getValues().filter(r => r[1]).map(r => ({ id: r[0], nome: r[1], descricao: r[2], categoria: r[3], ativo: r[4] !== 'Não', fotoId: r[5] || '', fotoUrl: urlFoto_(r[5]), destaque: r[6] === 'Sim', estoqueProprioIngredienteId: r[7] || '', ordemCardapio: numPlanilha_(r[8]) || 0 }));
}
function readProdutoIngredientes() {
  const sh = ss_().getSheetByName('ProdutoIngredientes'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 5).getValues().filter(r => r[1]).map(r => ({ id: r[0], produtoId: r[1], ingredienteId: r[2], ingredienteNome: r[3], quantidadePorUnidade: r[4] }));
}
function readEstoque() {
  const sh = ss_().getSheetByName('Estoque'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 7).getValues().filter(r => r[1])
    .map(r => ({ id: r[0], nome: r[1], quantidade: numPlanilha_(r[2]), minimo: numPlanilha_(r[3]), unidade: r[4] || 'un', custo: numPlanilha_(r[5]) || 0, ativo: r[6] !== 'Inativo' }));
}
function readMovimentacoesEstoque() {
  const sh = ss_().getSheetByName('MovimentaçõesEstoque'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 9).getValues().filter(r => r[0])
    .map(r => ({ id: r[0], ingredienteNome: r[1], tipo: r[2], quantidade: numPlanilha_(r[3]), qtdAntes: numPlanilha_(r[4]), qtdDepois: numPlanilha_(r[5]), motivo: r[6] || '', usuario: r[7] || '', data: r[8] }))
    .sort((a, b) => new Date(b.data) - new Date(a.data));
}
function registrarMovimentoEstoque_(ingredienteId, ingredienteNome, tipo, quantidade, qtdAntes, qtdDepois, motivo) {
  const sh = ss_().getSheetByName('MovimentaçõesEstoque');
  sh.appendRow([Utilities.getUuid(), ingredienteNome, tipo, quantidade, qtdAntes, qtdDepois, motivo || '', USUARIO_ATUAL || '', new Date()]);
}
function readCombos() {
  const sh = ss_().getSheetByName('Combos'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 7).getValues().filter(r => r[1]).map(r => ({ id: r[0], nome: r[1], categoria: r[2], ativo: r[3] !== 'Não', fotoId: r[4] || '', fotoUrl: urlFoto_(r[4]), destaque: r[5] === 'Sim', ordemCardapio: numPlanilha_(r[6]) || 0 }));
}
function readCategorias() {
  const sh = ss_().getSheetByName('Categorias'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 4).getValues().filter(r => r[1])
    .map(r => ({ id: r[0], nome: r[1], ativa: r[2] !== 'Não', ordem: numPlanilha_(r[3]) || 0 }))
    .sort((a, b) => a.ordem - b.ordem);
}
function readComboItens() {
  const sh = ss_().getSheetByName('ComboItens'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 4).getValues().filter(r => r[1]).map(r => ({ id: r[0], comboId: r[1], produtoId: r[2], quantidade: numPlanilha_(r[3]) }));
}
/* ITEM 17 — mesma leitura de sempre, agora também disponível só para o FIM da aba (pedidos recentes). */
function readVendas() { return readVendasDesde_(2); }
function readVendasCauda_(n) { const sh = ss_().getSheetByName('Vendas'); return readVendasDesde_(Math.max(2, sh.getLastRow() - n + 1)); }
function readVendasDesde_(linhaIni) {
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  if (last < 2 || last < linhaIni) return [];
  const colunas = Math.min(31, sh.getMaxColumns());
  return sh.getRange(linhaIni, 1, last - linhaIni + 1, colunas).getValues().filter(r => r[0]).map(r => ({
    id: r[0], data: Utilities.formatDate(new Date(r[1]), FUSO, 'dd/MM/yyyy HH:mm'), timestamp: new Date(r[1]).getTime(),
    clienteNome: r[2], clienteTelefone: r[3], formaPagamento: r[4], valorTotal: numPlanilha_(r[5]), custoTotal: numPlanilha_(r[6]), status: r[7], motivoCancelamento: r[8],
    tipoEntrega: r[9] || 'Retirada', statusPedido: r[10] || '', endereco: r[11] || '', complemento: r[12] || '', referencia: r[13] || '', observacoesEntrega: r[14] || '',
    timestampPronta: r[15] ? new Date(r[15]).getTime() : null, timestampConcluida: r[16] ? new Date(r[16]).getTime() : null,
    statusPagamento: r[17] || 'Pago', timestampRecebimento: r[18] ? new Date(r[18]).getTime() : null,
    valorOriginal: numPlanilha_(r[19]) || numPlanilha_(r[5]), valorDesconto: numPlanilha_(r[20]), descontoDetalhe: r[21] || '', entregador: r[22] || '',
    timestampSaiu: r[23] ? new Date(r[23]).getTime() : null, origem: r[24] || 'Balcão', mesaId: r[25] || '',
    taxaEntrega: numPlanilha_(r[26]) || 0, fechamentoEntregaId: r[27] || '', registradoPor: r[28] || '', numero: numPlanilha_(r[29]) || 0,
    timestampInicioPreparo: r[30] ? new Date(r[30]).getTime() : null
  }));
}
function readItensVenda() { return readItensVendaDesde_(2); }
function readItensVendaCauda_(n) { const sh = ss_().getSheetByName('ItensVenda'); return readItensVendaDesde_(Math.max(2, sh.getLastRow() - n + 1)); }
function readItensVendaDesde_(linhaIni) {
  const sh = ss_().getSheetByName('ItensVenda'); const last = sh.getLastRow();
  if (last < 2 || last < linhaIni) return [];
  return sh.getRange(linhaIni, 1, last - linhaIni + 1, 10).getValues().filter(r => r[0]).map(r => {
    let adicionaisIds = [];
    try { adicionaisIds = r[9] ? JSON.parse(r[9]) : []; } catch (e) { adicionaisIds = []; }
    return { id: r[0], vendaId: r[1], produtoId: r[2], comboId: r[3], descricao: r[4], quantidade: numPlanilha_(r[5]), valorUnitario: numPlanilha_(r[6]), custoUnitario: numPlanilha_(r[7]), valorTotalItem: numPlanilha_(r[8]), adicionaisIds: adicionaisIds };
  });
}
function readPagamentosVenda() {
  const sh = ss_().getSheetByName('PagamentosVenda'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, Math.min(5, sh.getMaxColumns())).getValues().filter(r => r[0]).map(r => ({ id: r[0], vendaId: r[1], forma: r[2], valor: numPlanilha_(r[3]), taxa: numPlanilha_(r[4]) || 0 }));
}
function readSangrias() {
  const sh = ss_().getSheetByName('Sangrias'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 5).getValues().filter(r => r[0]).map(r => ({
    id: r[0], data: Utilities.formatDate(new Date(r[1]), FUSO, 'dd/MM/yyyy HH:mm'), timestamp: new Date(r[1]).getTime(),
    valor: numPlanilha_(r[2]), motivo: r[3], usuario: r[4]
  }));
}
function addSangria(valor, motivo) {
  const v = Number(valor) || 0;
  if (v <= 0) return { ok: false, message: 'Informe um valor de sangria maior que zero.' };
  if (!motivo) return { ok: false, message: 'Informe o motivo da sangria.' };
  const sh = ss_().getSheetByName('Sangrias');
  const id = Utilities.getUuid();
  sh.appendRow([id, new Date(), v, motivo, USUARIO_ATUAL || '']);
  registrarLog('Sangria registrada', '', motivo + ' = R$ ' + v.toFixed(2));
  return { ok: true, message: 'Sangria registrada: R$ ' + v.toFixed(2), sangrias: readSangrias() };
}
function readMetas() {
  const sh = ss_().getSheetByName('Configurações'); const last = sh.getLastRow();
  let mensal = 0, diaria = 0;
  for (let i = 2; i <= last; i++) {
    const chave = sh.getRange(i, 1).getValue();
    if (chave === 'MetaMensal') mensal = numPlanilha_(sh.getRange(i, 2).getValue()) || 0;
    if (chave === 'MetaDiaria') diaria = numPlanilha_(sh.getRange(i, 2).getValue()) || 0;
  }
  return { mensal: mensal, diaria: diaria };
}
function salvarMeta(tipo, valor) {
  if (tipo !== 'MetaMensal' && tipo !== 'MetaDiaria') return { ok: false, message: 'Tipo de meta inválido.' };
  const sh = ss_().getSheetByName('Configurações'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() === tipo) {
      sh.getRange(i, 2).setValue(Number(valor) || 0);
      registrarLog('Meta atualizada', '', tipo + ': R$ ' + (Number(valor) || 0).toFixed(2));
      return { ok: true, metas: readMetas() };
    }
  }
  sh.appendRow([tipo, Number(valor) || 0]);
  return { ok: true, metas: readMetas() };
}

/* ---------- CONFIGURAÇÃO DO CARDÁPIO DIGITAL (ITEM 93) ----------
   Textos do banner editáveis pelo Administrador, sem precisar mexer no HTML. */
function lerConfigChave_(chave, padrao) {
  const sh = ss_().getSheetByName('Configurações'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) { if (sh.getRange(i, 1).getValue() === chave) return sh.getRange(i, 2).getValue() || padrao; }
  return padrao;
}
function salvarConfigChave_(chave, valor) {
  const sh = ss_().getSheetByName('Configurações'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) { if (sh.getRange(i, 1).getValue() === chave) { sh.getRange(i, 2).setValue(valor); return; } }
  sh.appendRow([chave, valor]);
}
function readConfigCardapio() {
  return {
    kicker: lerConfigChave_('CardapioKicker', 'DELIVERY · SABOR QUE CONQUISTA'),
    frase: lerConfigChave_('CardapioFrase', 'Peça pelo cardápio — rápido, sem complicação.'),
    tempoEntrega: lerConfigChave_('CardapioTempoEntrega', '40-60 min'),
    tempoRetirada: lerConfigChave_('CardapioTempoRetirada', '20-30 min'),
    tempoMesa: lerConfigChave_('CardapioTempoMesa', '20-30 min')
  };
}
function salvarConfigCardapio(kicker, frase, tempoEntrega, tempoRetirada, tempoMesa) {
  salvarConfigChave_('CardapioKicker', kicker || '');
  salvarConfigChave_('CardapioFrase', frase || '');
  if (tempoEntrega !== undefined) salvarConfigChave_('CardapioTempoEntrega', tempoEntrega || '');
  if (tempoRetirada !== undefined) salvarConfigChave_('CardapioTempoRetirada', tempoRetirada || '');
  if (tempoMesa !== undefined) salvarConfigChave_('CardapioTempoMesa', tempoMesa || '');
  registrarLog('Configuração do Cardápio Digital atualizada', '', '');
  return { ok: true, message: 'Cardápio atualizado.', config: readConfigCardapio() };
}

/* ---------- NOTIFICAÇÕES ADMINISTRATIVAS (ITENS 64 e 65) ----------
   Catálogo FIXO de eventos do mural de Notificações. O Administrador liga/desliga cada
   evento e escolhe quais perfis o recebem; a escolha fica na aba Configurações (chave
   NotificacoesConfig, JSON) — sem aba nova. Só perfis que abrem o mural (Admin, Operador,
   Cozinha) podem ser destinatários. O filtro é aplicado no mural; a configuração só é
   alterável pelo Admin (validado aqui, não só na tela). */
const NOTIF_PERFIS_DESTINO = ['Admin', 'Operador', 'Cozinha'];
const NOTIF_EVENTOS = {
  pedido:      { grupo: 'Pedidos',      rotulo: 'Pedidos novos aguardando aceite',      perfis: ['Admin', 'Operador'] },
  entrega:     { grupo: 'Entregas',     rotulo: 'Entregas sem entregador, paradas ou fechamento pendente', perfis: ['Admin', 'Operador'] },
  estoque:     { grupo: 'Estoque',      rotulo: 'Estoque baixo',                        perfis: ['Admin', 'Operador', 'Cozinha'] },
  financeiro:  { grupo: 'Financeiro',   rotulo: 'Despesas vencidas a pagar',            perfis: ['Admin'] },
  ocorrencia:  { grupo: 'Ocorrências',  rotulo: 'Ocorrências abertas',                  perfis: ['Admin', 'Operador'] },
  sistema:     { grupo: 'Sistema',      rotulo: 'Falha de backup, Drive crítico e fila de envio com erro', perfis: ['Admin'] },
  fidelidade:  { grupo: 'Clientes',     rotulo: 'Cliente prestes a completar o cartão fidelidade', perfis: ['Admin', 'Operador'] },
  indicacao:   { grupo: 'Clientes',     rotulo: 'Indicações pendentes de resgate',      perfis: ['Admin', 'Operador'] },
  aniversario: { grupo: 'Clientes',     rotulo: 'Aniversariantes do mês',               perfis: ['Admin', 'Operador'] },
  inativos:    { grupo: 'Clientes',     rotulo: 'Clientes inativos (30+ dias)',         perfis: ['Admin', 'Operador'] }
};
function readConfigNotificacoes() {
  let salvo = {};
  try { salvo = JSON.parse(lerConfigChave_('NotificacoesConfig', '{}') || '{}') || {}; } catch (e) { salvo = {}; }
  const eventos = {};
  Object.keys(NOTIF_EVENTOS).forEach(id => {
    const padrao = NOTIF_EVENTOS[id], s = salvo[id];
    const perfis = (s && Array.isArray(s.perfis)) ? s.perfis.filter(p => NOTIF_PERFIS_DESTINO.indexOf(p) !== -1) : padrao.perfis.slice();
    eventos[id] = { ativo: s ? s.ativo !== false : true, perfis: perfis };
  });
  return eventos;
}
function salvarConfigNotificacoes(eventosRecebidos) {
  if (!eventosRecebidos || typeof eventosRecebidos !== 'object') return { ok: false, message: 'Configuração inválida.' };
  const antes = readConfigNotificacoes();
  const novo = {};
  Object.keys(NOTIF_EVENTOS).forEach(id => {
    const e = eventosRecebidos[id];
    if (!e) { novo[id] = antes[id]; return; } // evento não enviado: mantém como estava
    const perfis = Array.isArray(e.perfis) ? e.perfis.filter((p, i, a) => NOTIF_PERFIS_DESTINO.indexOf(p) !== -1 && a.indexOf(p) === i) : [];
    novo[id] = { ativo: e.ativo !== false, perfis: perfis };
  });
  const json = JSON.stringify(novo);
  if (json.length > 4000) return { ok: false, message: 'Configuração grande demais.' };
  const mudou = Object.keys(novo).filter(id => JSON.stringify(novo[id]) !== JSON.stringify(antes[id]));
  salvarConfigChave_('NotificacoesConfig', json);
  if (mudou.length) registrarAuditoria_('Configuração de notificações alterada', 'Eventos: ' + mudou.map(id => id + ' → ' + (novo[id].ativo ? novo[id].perfis.join('/') || 'ninguém' : 'desligado')).join('; '));
  return { ok: true, message: mudou.length ? 'Notificações atualizadas.' : 'Nada mudou.', config: readConfigNotificacoes() };
}

/* ---------- INDICAÇÕES ---------- */
function addIndicacao(nomeIndicador, telIndicador, nomeIndicado, telIndicado, observacao) {
  if (!nomeIndicador || !telIndicador || !nomeIndicado || !telIndicado) return { ok: false, message: 'Preencha todos os campos.' };
  const tIndicador = normTel(telIndicador); const tIndicado = normTel(telIndicado);
  if (tIndicador === tIndicado) return { ok: false, message: 'Quem indicou e quem foi indicado não podem ser a mesma pessoa.' };
  const dados = readIndicacoes();
  const jaIndicado = dados.find(i => normTel(i.telIndicado) === tIndicado);
  if (jaIndicado) return { ok: false, message: nomeIndicado + ' já foi indicado antes (por ' + jaIndicado.nomeIndicador + ').', indicacoes: dados };
  const sh = ss_().getSheetByName('Indicações');
  const idIndicador = upsertCliente(telIndicador, nomeIndicador);
  const idIndicado = upsertCliente(telIndicado, nomeIndicado);
  sh.appendRow([nomeIndicador, telIndicador, nomeIndicado, telIndicado, agora(), 'Pendente', observacao || '', idIndicador || '', idIndicado || '']);
  registrarLog('Indicação registrada', telIndicado, nomeIndicador + ' indicou ' + nomeIndicado);
  return { ok: true, message: 'Indicação registrada.', indicacoes: readIndicacoes() };
}
function toggleResgateIndicacao(telIndicado) {
  const sh = ss_().getSheetByName('Indicações'); const tel = normTel(telIndicado); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (normTel(sh.getRange(i, 4).getValue()) === tel) {
      const novo = sh.getRange(i, 6).getValue() === 'Resgatado' ? 'Pendente' : 'Resgatado';
      sh.getRange(i, 6).setValue(novo);
      registrarLog('Status de indicação alterado', telIndicado, novo);
      break;
    }
  }
  return { ok: true, indicacoes: readIndicacoes() };
}

/* ---------- FIDELIDADE ---------- */
function addOrStampFidelidade(telefone, nome, observacao) {
  if (!telefone) return { ok: false, message: 'Informe o telefone do cliente.' };
  const sh = ss_().getSheetByName('Fidelidade'); const tel = normTel(telefone); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (normTel(sh.getRange(i, 2).getValue()) === tel) {
      if (!sh.getRange(i, 7).getValue()) sh.getRange(i, 7).setValue(upsertCliente(telefone, nome) || ''); // ETAPA 2: vincula ao ID do cliente
      const carimbosAtuais = sh.getRange(i, 3).getValue();
      if (observacao) sh.getRange(i, 6).setValue(observacao);
      if (carimbosAtuais >= 10) return { ok: true, novo: false, message: 'Cartão já está completo (10/10). Resgate o prêmio antes de somar nova marca.', fidelidade: readFidelidade() };
      sh.getRange(i, 3).setValue(carimbosAtuais + 1);
      sh.getRange(i, 5).setValue(agora());
      registrarLog('Marca adicionada (fidelidade)', telefone, (carimbosAtuais + 1) + '/10');
      return { ok: true, novo: false, message: 'Marca adicionada (' + (carimbosAtuais + 1) + '/10).', fidelidade: readFidelidade() };
    }
  }
  if (!nome) return { ok: false, message: 'Cliente não encontrado no fidelidade e nome não informado.' };
  const idCliFid = upsertCliente(telefone, nome);
  sh.appendRow([nome, telefone, 1, 0, agora(), observacao || '', idCliFid || '']);
  registrarLog('Cliente novo no fidelidade', telefone, nome);
  return { ok: true, novo: true, message: '1ª marca registrada.', fidelidade: readFidelidade() };
}
function resgatarPremioFidelidade(telefone) {
  const sh = ss_().getSheetByName('Fidelidade'); const tel = normTel(telefone); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (normTel(sh.getRange(i, 2).getValue()) === tel) {
      const carimbos = sh.getRange(i, 3).getValue();
      if (carimbos < 10) return { ok: false, message: 'Este cartão ainda não completou 10 marcas.' };
      const premios = sh.getRange(i, 4).getValue() || 0;
      sh.getRange(i, 3).setValue(0); sh.getRange(i, 4).setValue(premios + 1); sh.getRange(i, 5).setValue(agora());
      registrarLog('Prêmio resgatado (fidelidade)', telefone, 'Total de prêmios: ' + (premios + 1));
      return { ok: true, message: 'Prêmio resgatado — cartão reiniciado.', fidelidade: readFidelidade() };
    }
  }
  return { ok: false, message: 'Cliente não encontrado.' };
}

/* ---------- PRODUTOS + INGREDIENTES VINCULADOS ---------- */
/* ---------- ESTOQUE PRÓPRIO SIMPLES (ITEM 27 sem burocracia) ----------
   Em vez de obrigar o usuário a entender "ficha técnica" pra algo simples como
   uma lata de refrigerante, isso cria e vincula o ingrediente por trás das
   cenas. A quantidade inicial só é usada na criação; depois disso, o estoque
   se ajusta só pelas movimentações (venda, entrada, perda, inventário) — editar
   o produto nunca mais mexe na quantidade, só em mínimo/unidade/custo/nome. */
function aplicarEstoqueProprio_(produtoAtual, nomeProduto, estoqueProprio) {
  if (!estoqueProprio || !estoqueProprio.ativo) {
    return produtoAtual ? (produtoAtual.estoqueProprioIngredienteId || '') : '';
  }
  const shEstoque = ss_().getSheetByName('Estoque');
  const idExistente = produtoAtual ? produtoAtual.estoqueProprioIngredienteId : '';
  if (idExistente) {
    const last = shEstoque.getLastRow();
    for (let i = 2; i <= last; i++) {
      if (shEstoque.getRange(i, 1).getValue() === idExistente) {
        shEstoque.getRange(i, 2, 1, 2).setValues([[nomeProduto, shEstoque.getRange(i, 3).getValue()]]); // mantém quantidade atual
        shEstoque.getRange(i, 4).setValue(Number(estoqueProprio.minimo) || 0);
        shEstoque.getRange(i, 5).setValue(estoqueProprio.unidade || 'un');
        shEstoque.getRange(i, 6).setValue(Number(estoqueProprio.custo) || 0);
        return idExistente;
      }
    }
  }
  const r = addIngrediente(nomeProduto, estoqueProprio.quantidade, estoqueProprio.minimo, estoqueProprio.unidade, estoqueProprio.custo);
  const novo = readEstoque().find(e => e.nome === nomeProduto);
  return novo ? novo.id : '';
}
function salvarIngredientesDoProduto(produtoId, ingredientes) {
  const sh = ss_().getSheetByName('ProdutoIngredientes');
  const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 2).getValue() === produtoId) sh.deleteRow(i); }
  (ingredientes || []).forEach(ing => {
    if (!ing.ingredienteId) return;
    sh.appendRow([Utilities.getUuid(), produtoId, ing.ingredienteId, ing.ingredienteNome || '', Number(ing.quantidadePorUnidade) || 0]);
  });
}

/* ---------- ADICIONAIS (ITEM 20, 28) ----------
   Catálogo próprio (nome + preço) associável a produtos. A baixa de estoque via
   ingrediente vinculado é ligada na Fase 3, junto com o resto da lógica de estoque. */
function readAdicionais() {
  const sh = ss_().getSheetByName('Adicionais'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 6).getValues().filter(r => r[1])
    .map(r => ({ id: r[0], nome: r[1], preco: numPlanilha_(r[2]) || 0, ativo: r[3] !== 'Não', ingredienteId: r[4] || '', quantidadeDesconto: numPlanilha_(r[5]) || 1 }));
}
function readProdutoAdicionais() {
  const sh = ss_().getSheetByName('ProdutoAdicionais'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 3).getValues().filter(r => r[1])
    .map(r => ({ id: r[0], produtoId: r[1], adicionalId: r[2] }));
}
function addAdicional(nome, preco, ingredienteId, quantidadeDesconto) {
  if (!nome) return { ok: false, message: 'Informe o nome do adicional.' };
  if (nomeJaExiste_(readAdicionais(), nome)) return { ok: false, message: 'Já existe um adicional com esse nome.' };
  const sh = ss_().getSheetByName('Adicionais');
  sh.appendRow([Utilities.getUuid(), nome, Number(preco) || 0, 'Sim', ingredienteId || '', Number(quantidadeDesconto) || 1]);
  registrarLog('Adicional cadastrado', '', nome);
  return { ok: true, message: 'Adicional cadastrado.', adicionais: readAdicionais() };
}
function editarAdicional(id, nome, preco, ativo, ingredienteId, quantidadeDesconto) {
  const sh = ss_().getSheetByName('Adicionais'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      sh.getRange(i, 2, 1, 2).setValues([[nome, Number(preco) || 0]]);
      if (ativo !== undefined) sh.getRange(i, 4).setValue(ativo === false ? 'Não' : 'Sim');
      if (ingredienteId !== undefined) sh.getRange(i, 5).setValue(ingredienteId || '');
      if (quantidadeDesconto !== undefined) sh.getRange(i, 6).setValue(Number(quantidadeDesconto) || 1);
      registrarLog('Adicional editado', '', nome);
      return { ok: true, message: 'Adicional atualizado.', adicionais: readAdicionais() };
    }
  }
  return { ok: false, message: 'Adicional não encontrado.' };
}
/* Vincula adicionais aos produtos das categorias escolhidas, de uma vez só (sem apagar vínculos existentes).
   Os adicionais cadastrados pela importação nascem sem vínculo com produto e por isso não apareciam no cardápio. */
function vincularAdicionaisEmLote(categorias, adicionaisIds) {
  if (!Array.isArray(categorias) || !categorias.length) return { ok: false, message: 'Escolha ao menos uma categoria.' };
  if (!Array.isArray(adicionaisIds) || !adicionaisIds.length) return { ok: false, message: 'Escolha ao menos um adicional.' };
  const idsValidos = readAdicionais().map(a => a.id);
  const adIds = adicionaisIds.filter(id => idsValidos.indexOf(id) !== -1);
  if (!adIds.length) return { ok: false, message: 'Nenhum adicional válido selecionado.' };
  const idsCat = categorias.map(c => String(c));
  const produtos = readProdutos().filter(p => idsCat.indexOf(String(p.categoria)) !== -1); // o produto guarda o ID da categoria
  if (!produtos.length) return { ok: false, message: 'Não há produtos nessas categorias.' };
  const existentes = {};
  readProdutoAdicionais().forEach(pa => { existentes[pa.produtoId + '|' + pa.adicionalId] = true; });
  const novas = [];
  produtos.forEach(p => adIds.forEach(adId => {
    if (!existentes[p.id + '|' + adId]) novas.push([Utilities.getUuid(), p.id, adId]);
  }));
  if (novas.length) {
    const sh = ss_().getSheetByName('ProdutoAdicionais');
    sh.getRange(sh.getLastRow() + 1, 1, novas.length, 3).setValues(novas);
  }
  registrarLog('Adicionais vinculados em lote', '', produtos.length + ' produtos x ' + adIds.length + ' adicionais');
  return { ok: true, message: novas.length ? (novas.length + ' vínculos criados em ' + produtos.length + ' produtos.') : 'Esses vínculos já existiam.', produtoAdicionais: readProdutoAdicionais() };
}
function excluirAdicional(id) {
  const sh = ss_().getSheetByName('Adicionais'); const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 1).getValue() === id) { sh.deleteRow(i); break; } }
  const shLigacao = ss_().getSheetByName('ProdutoAdicionais'); const last2 = shLigacao.getLastRow();
  for (let i = last2; i >= 2; i--) { if (shLigacao.getRange(i, 3).getValue() === id) shLigacao.deleteRow(i); }
  registrarLog('Adicional excluído', '', id);
  return { ok: true, adicionais: readAdicionais(), produtoAdicionais: readProdutoAdicionais() };
}
function salvarAdicionaisDoProduto(produtoId, adicionaisIds) {
  const sh = ss_().getSheetByName('ProdutoAdicionais');
  const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 2).getValue() === produtoId) sh.deleteRow(i); }
  (adicionaisIds || []).forEach(adId => { if (adId) sh.appendRow([Utilities.getUuid(), produtoId, adId]); });
}

/* ---------- MAIS PEDIDOS (ITEM 15) ----------
   Calcula os 5-8 itens (produto ou combo) mais vendidos nos últimos 30 dias,
   ignorando inativos/indisponíveis — sem seleção manual, é automático. */
function calcularMaisPedidos_() {
  const limite = new Date(); limite.setDate(limite.getDate() - 30);
  const vendas = readVendas().filter(v => v.status === 'Confirmada' && (v.timestamp || 0) >= limite.getTime()).map(v => v.id);
  const setVendas = new Set(vendas);
  const itens = readItensVenda().filter(it => setVendas.has(it.vendaId));
  const contagem = {};
  itens.forEach(it => {
    const chave = it.produtoId ? ('p_' + it.produtoId) : (it.comboId ? ('c_' + it.comboId) : null);
    if (!chave) return;
    contagem[chave] = (contagem[chave] || 0) + (Number(it.quantidade) || 1);
  });
  const produtosAtivos = readProdutos().filter(p => p.ativo);
  const combosAtivos = readCombos().filter(c => c.ativo);
  const ranking = Object.keys(contagem).map(chave => {
    const [tipo, id] = [chave.slice(0, 1), chave.slice(2)];
    const item = tipo === 'p' ? produtosAtivos.find(p => p.id === id) : combosAtivos.find(c => c.id === id);
    if (!item) return null;
    return { tipo: tipo === 'p' ? 'produto' : 'combo', id: item.id, nome: item.nome, fotoUrl: item.fotoUrl, categoria: item.categoria, vendas: contagem[chave] };
  }).filter(Boolean).sort((a, b) => b.vendas - a.vendas).slice(0, 8);
  return ranking;
}

/* ---------- FEEDBACKS (ITEM 34) ---------- */
function readFeedbacks() {
  const sh = ss_().getSheetByName('Feedbacks'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, Math.min(8, sh.getMaxColumns())).getValues().filter(r => r[0])
    .map(r => ({ id: r[0], vendaId: r[1], telefone: r[2], nota: numPlanilha_(r[3]) || 0, comentario: r[4] || '', data: r[5], status: r[6] || 'Novo', clienteId: r[7] || '' }));
}
function addFeedback(vendaId, telefone, nota, comentario, nome) {
  const n = Number(nota) || 0;
  if (n < 1 || n > 5 || Math.floor(n) !== n) return { ok: false, message: 'A nota deve ser de 1 a 5.' };
  /* SEGURANÇA: endpoint público — limite por telefone e geral, textos higienizados e NUNCA cria cliente novo
     (feedback não é cadastro; só liga ao cliente que já existe). */
  const tel = normTel(telefone);
  if (tel && (tel.length < 10 || tel.length > 13)) return { ok: false, message: 'Telefone inválido.' };
  const chaveTel = 'feedback_' + (tel || 'anon');
  if (excedeuTentativas_(chaveTel, 5) || excedeuTentativas_('feedback_global', 120)) return { ok: false, message: 'Muitos feedbacks em sequência. Aguarde alguns minutos.' };
  let vId = String(vendaId || '').trim().slice(0, 80);
  if (vId && !readVendas().some(v => v.id === vId)) vId = ''; // ID que não existe não é gravado
  const sh = ss_().getSheetByName('Feedbacks');
  const idCliFeed = idClientePorTelefone_(tel);
  sh.appendRow([Utilities.getUuid(), vId, tel, n, textoPublicoSeguro_(comentario, 500), agora(), 'Novo', idCliFeed || '']);
  registrarFalha_(chaveTel); registrarFalha_('feedback_global');
  registrarLog('Feedback recebido', tel, 'Nota ' + n);
  return { ok: true, message: 'Obrigado pelo feedback!' };
}
function editarStatusFeedback(id, novoStatus) {
  const sh = ss_().getSheetByName('Feedbacks'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      sh.getRange(i, 7).setValue(novoStatus || 'Novo');
      registrarLog('Feedback atualizado', '', 'Status: ' + novoStatus);
      return { ok: true, feedbacks: readFeedbacks() };
    }
  }
  return { ok: false, message: 'Feedback não encontrado.' };
}
/* ---------- FOTOS (Google Drive) ---------- */
function obterPastaFotos_() {
  const props = PropertiesService.getScriptProperties();
  const folderId = props.getProperty('PASTA_FOTOS_ID');
  if (folderId) {
    try { return DriveApp.getFolderById(folderId); } catch (e) { /* pasta foi apagada, recria abaixo */ }
  }
  const raiz = DriveApp.getRootFolder();
  const existentes = raiz.getFoldersByName('Texas Burger - Fotos');
  const pasta = existentes.hasNext() ? existentes.next() : raiz.createFolder('Texas Burger - Fotos');
  props.setProperty('PASTA_FOTOS_ID', pasta.getId());
  return pasta;
}
function nomeArquivoSeguro_(nome) {
  const base = (nome || 'item').toString().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-zA-Z0-9\-_ ]/g, '').trim().replace(/\s+/g, '-').toLowerCase();
  return (base || 'item');
}
/* Sobe a foto NOVA primeiro; só depois de confirmado que ela foi salva com sucesso
   é que a foto ANTIGA (fotoIdAntigo) é excluída do Drive. Se o upload falhar, a antiga permanece intacta. */
function _uploadFotoSegura(nomeBase, base64Data, mimeType, fotoIdAntigo) {
  if (!base64Data) return { ok: false, message: 'Nenhuma imagem recebida.' };
  try {
    const pasta = obterPastaFotos_();
    const dadosLimpos = base64Data.indexOf(',') >= 0 ? base64Data.split(',').pop() : base64Data;
    const bytes = Utilities.base64Decode(dadosLimpos);
    /* SEGURANÇA (Módulo 3): confere o conteúdo real do arquivo (não confia no tipo informado). Só JPEG/PNG/WEBP até 5 MB —
       impede hospedar HTML, SVG ou executável no Drive do restaurante com link público. */
    if (bytes.length > 5 * 1024 * 1024) return { ok: false, message: 'Imagem grande demais (máximo 5 MB).' };
    const b = bytes;
    const u8 = function (k) { return (b[k] + 256) % 256; };
    let tipoReal = '', ext = '';
    if (u8(0) === 0xFF && u8(1) === 0xD8 && u8(2) === 0xFF) { tipoReal = 'image/jpeg'; ext = '.jpg'; }
    else if (u8(0) === 0x89 && u8(1) === 0x50 && u8(2) === 0x4E && u8(3) === 0x47) { tipoReal = 'image/png'; ext = '.png'; }
    else if (u8(0) === 0x52 && u8(1) === 0x49 && u8(2) === 0x46 && u8(3) === 0x46 && u8(8) === 0x57 && u8(9) === 0x45 && u8(10) === 0x42 && u8(11) === 0x50) { tipoReal = 'image/webp'; ext = '.webp'; }
    if (!tipoReal) return { ok: false, message: 'Arquivo não é uma imagem válida (use JPG, PNG ou WEBP).' };
    const nomeArquivo = nomeArquivoSeguro_(nomeBase) + '-' + Utilities.getUuid().slice(0, 8) + ext;
    const blob = Utilities.newBlob(bytes, tipoReal, nomeArquivo);
    const arquivo = pasta.createFile(blob);
    arquivo.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
    const novoId = arquivo.getId();
    // Só chega aqui se o upload da nova foto deu certo — agora sim pode excluir a antiga.
    if (fotoIdAntigo) { try { DriveApp.getFileById(fotoIdAntigo).setTrashed(true); } catch (e) { /* antiga já não existe, ok */ } }
    return { ok: true, fotoId: novoId, fotoUrl: urlFoto_(novoId) };
  } catch (e) {
    return { ok: false, message: 'Não foi possível salvar a foto: ' + e.message };
  }
}
function uploadFotoProduto(produtoId, nomeBase, base64Data, mimeType) {
  const sh = ss_().getSheetByName('Produtos'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() === produtoId) {
      const fotoIdAntigo = sh.getRange(i, 6).getValue();
      const r = _uploadFotoSegura(nomeBase, base64Data, mimeType, fotoIdAntigo);
      if (r.ok) { sh.getRange(i, 6).setValue(r.fotoId); registrarLog('Foto do produto atualizada', '', nomeBase); }
      r.produtos = readProdutos();
      return r;
    }
  }
  return { ok: false, message: 'Produto não encontrado.' };
}
function excluirFotoProduto(produtoId) {
  const sh = ss_().getSheetByName('Produtos'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() === produtoId) {
      const fotoId = sh.getRange(i, 6).getValue();
      if (fotoId) { try { DriveApp.getFileById(fotoId).setTrashed(true); } catch (e) {} }
      sh.getRange(i, 6).setValue('');
      registrarLog('Foto do produto removida', '', produtoId);
      return { ok: true, produtos: readProdutos() };
    }
  }
  return { ok: false, message: 'Produto não encontrado.' };
}
function uploadFotoCombo(comboId, nomeBase, base64Data, mimeType) {
  const sh = ss_().getSheetByName('Combos'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() === comboId) {
      const fotoIdAntigo = sh.getRange(i, 5).getValue();
      const r = _uploadFotoSegura(nomeBase, base64Data, mimeType, fotoIdAntigo);
      if (r.ok) { sh.getRange(i, 5).setValue(r.fotoId); registrarLog('Foto do combo atualizada', '', nomeBase); }
      r.combos = readCombos();
      return r;
    }
  }
  return { ok: false, message: 'Combo não encontrado.' };
}
function excluirFotoCombo(comboId) {
  const sh = ss_().getSheetByName('Combos'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() === comboId) {
      const fotoId = sh.getRange(i, 5).getValue();
      if (fotoId) { try { DriveApp.getFileById(fotoId).setTrashed(true); } catch (e) {} }
      sh.getRange(i, 5).setValue('');
      registrarLog('Foto do combo removida', '', comboId);
      return { ok: true, combos: readCombos() };
    }
  }
  return { ok: false, message: 'Combo não encontrado.' };
}

/* ---------- CATEGORIAS ---------- */
function addCategoria(nome) {
  if (!nome) return { ok: false, message: 'Informe o nome da categoria.' };
  const existentes = readCategorias();
  if (existentes.some(c => c.nome.toLowerCase() === nome.toLowerCase())) return { ok: false, message: 'Já existe uma categoria com esse nome.' };
  const sh = ss_().getSheetByName('Categorias');
  const proximaOrdem = existentes.length ? Math.max.apply(null, existentes.map(c => c.ordem)) + 1 : 1;
  sh.appendRow([Utilities.getUuid(), nome, 'Sim', proximaOrdem]);
  registrarLog('Categoria cadastrada', '', nome);
  return { ok: true, message: 'Categoria cadastrada.', categorias: readCategorias() };
}
function editarCategoria(id, novoNome, novoAtivo, novaOrdem) {
  const sh = ss_().getSheetByName('Categorias'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      if (novoNome) sh.getRange(i, 2).setValue(novoNome);
      if (novoAtivo !== undefined) sh.getRange(i, 3).setValue(novoAtivo === false ? 'Não' : 'Sim');
      if (novaOrdem !== undefined && novaOrdem !== null) sh.getRange(i, 4).setValue(Number(novaOrdem) || 0);
      registrarLog('Categoria atualizada', '', novoNome || id);
      return { ok: true, message: 'Categoria atualizada.', categorias: readCategorias() };
    }
  }
  return { ok: false, message: 'Categoria não encontrada.' };
}
function excluirCategoria(id) {
  const emUsoProdutos = readProdutos().filter(p => p.categoria === id).length;
  const emUsoCombos = readCombos().filter(c => c.categoria === id).length;
  const total = emUsoProdutos + emUsoCombos;
  if (total > 0) return { ok: false, message: `${total} item(ns) usam essa categoria (${emUsoProdutos} produto(s), ${emUsoCombos} combo(s)). Mova-os para outra categoria antes de excluir.` };
  const sh = ss_().getSheetByName('Categorias'); const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 1).getValue() === id) { sh.deleteRow(i); break; } }
  registrarLog('Categoria excluída', '', id);
  return { ok: true, categorias: readCategorias() };
}

/* ---------- MESAS (ITEM 55) ---------- */
function readMesas() {
  const sh = ss_().getSheetByName('Mesas');
  garantirColuna_(sh, 6, 'Garçom Responsável', 160);
  const last = sh.getLastRow();
  if (last < 2) return [];
  const colunas = Math.min(6, sh.getMaxColumns());
  const chamados = jsonConfig_(MESA_CHAMADOS_CHAVE_);
  return sh.getRange(2, 1, last - 1, colunas).getValues().filter(r => r[1] !== '' && r[1] !== null)
    .map(r => ({ id: r[0], numero: r[1], status: r[2] || 'Livre', capacidade: r[3] || '', observacao: r[4] || '', garcomResponsavel: r[5] || '', chamadoEm: Number(chamados[r[0]]) || 0 }))
    .sort((a, b) => Number(a.numero) - Number(b.numero));
}
/* ---------- QR CODE DAS MESAS + PEDIDO DO CLIENTE NA MESA (Etapa 6) ----------
   Sem colunas nem abas novas: os códigos secretos e os chamados ficam em JSON na aba Configurações.
   O pedido do cliente entra como "Cardápio" + Mesa → chega "Recebido" e SÓ vai ao preparo quando o caixa/garçom ACEITA. */
const MESA_QR_CHAVE_ = 'QR_MESAS', MESA_CHAMADOS_CHAVE_ = 'CHAMADOS_MESAS';
function configRapida_(chave, padrao) {
  const sh = ss_().getSheetByName('Configurações'); const last = sh.getLastRow();
  if (last < 2) return padrao;
  const v = sh.getRange(2, 1, last - 1, 2).getValues();
  for (let i = 0; i < v.length; i++) { if (v[i][0] === chave) return v[i][1] || padrao; }
  return padrao;
}
function jsonConfig_(chave) { try { const o = JSON.parse(configRapida_(chave, '{}') || '{}'); return (o && typeof o === 'object') ? o : {}; } catch (e) { return {}; } }
function codigoAleatorioMesa_() { return Utilities.getUuid().replace(/-/g, '').slice(0, 10); }
function obterQrMesas() {
  const codigos = jsonConfig_(MESA_QR_CHAVE_); let mudou = false;
  const lista = readMesas().map(m => { if (!codigos[m.id]) { codigos[m.id] = codigoAleatorioMesa_(); mudou = true; } return { id: m.id, numero: m.numero, codigo: codigos[m.id] }; });
  if (mudou) salvarConfigChave_(MESA_QR_CHAVE_, JSON.stringify(codigos));
  return { ok: true, mesas: lista };
}
function gerarNovoCodigoMesa(mesaId) {
  const m = readMesas().find(x => x.id === mesaId);
  if (!m) return { ok: false, message: 'Mesa não encontrada.' };
  const codigos = jsonConfig_(MESA_QR_CHAVE_); codigos[mesaId] = codigoAleatorioMesa_();
  salvarConfigChave_(MESA_QR_CHAVE_, JSON.stringify(codigos));
  cacheLimpar_('mp_' + mesaId);
  registrarLog('Código QR da mesa renovado', '', 'Mesa ' + m.numero + ' — o QR antigo deixou de funcionar');
  return { ok: true, message: 'Novo código gerado. Imprima o QR da mesa ' + m.numero + ' de novo.', mesas: obterQrMesas().mesas };
}
/* Confere mesa + código secreto. Tentativas erradas são limitadas (anti-chute). */
function validarMesaQr_(numero, codigo) {
  const msgInvalido = { ok: false, invalido: true, message: 'QR Code inválido ou desativado. Chame o garçom.' };
  if (excedeuTentativas_('mesaqr_fail', 40)) return { ok: false, message: 'Muitas tentativas. Aguarde alguns minutos ou chame o garçom.' };
  const mesa = readMesas().find(m => String(m.numero) === String(numero || '').trim());
  const codigos = jsonConfig_(MESA_QR_CHAVE_);
  if (!mesa || !codigo || codigos[mesa.id] !== String(codigo)) { registrarFalha_('mesaqr_fail'); return msgInvalido; }
  return { ok: true, mesa: mesa };
}
function definirStatusMesaServidor_(mesaId, status) {
  const sh = ss_().getSheetByName('Mesas'); const i = linhaDoId_(sh, mesaId); if (i < 1) return false;
  const anterior = String(sh.getRange(i, 3).getValue() || 'Livre');
  sh.getRange(i, 3).setValue(status);
  registrarLog('Status de mesa alterado', '', 'Mesa ' + sh.getRange(i, 2).getValue() + ': ' + anterior + ' → ' + status);
  return true;
}
function limparChamadoMesa_(mesaId) {
  const c = jsonConfig_(MESA_CHAMADOS_CHAVE_);
  if (c[mesaId]) { delete c[mesaId]; salvarConfigChave_(MESA_CHAMADOS_CHAVE_, JSON.stringify(c)); }
}
const ROTULO_STATUS_MESA_PUBLICO_ = { 'Recebido': 'Aguardando confirmação', 'Em preparo': 'Em preparo', 'Pronta': 'Pronto', 'Servida': 'Servido', 'Suspenso': 'Em preparo' };
function montarEstadoMesaPublica_(mesa) {
  const chave = 'mp_' + mesa.id;
  const emCache = cacheLerJson_(chave);
  if (emCache) return emCache;
  const limiteCancel = Date.now() - 3 * 3600 * 1000;
  const todas = readVendas().filter(v => v.mesaId === mesa.id && v.origem === 'Cardápio');
  const ativas = readVendas().filter(v => v.mesaId === mesa.id && v.status === 'Confirmada' && v.statusPagamento === 'A Receber');
  const idsVisiveis = {}; ativas.forEach(v => { idsVisiveis[v.id] = true; });
  todas.filter(v => v.status === 'Cancelada' && v.timestamp >= limiteCancel).forEach(v => { idsVisiveis[v.id] = true; });
  const itens = readItensVenda();
  const pedidos = readVendas().filter(v => v.mesaId === mesa.id && idsVisiveis[v.id]).sort((a, b) => a.timestamp - b.timestamp).slice(-12).map(v => ({
    id: v.id, numero: v.numero || 0, hora: Utilities.formatDate(new Date(v.timestamp), Session.getScriptTimeZone(), 'HH:mm'),
    valor: Number(v.valorTotal) || 0, cancelado: v.status === 'Cancelada',
    status: v.status === 'Cancelada' ? 'Cancelado' : (ROTULO_STATUS_MESA_PUBLICO_[v.statusPedido] || v.statusPedido || ''),
    podeCancelar: v.status === 'Confirmada' && v.origem === 'Cardápio' && v.statusPedido === 'Recebido',
    itens: itens.filter(it => it.vendaId === v.id).map(it => ({ quantidade: it.quantidade, descricao: it.descricao }))
  }));
  const total = Math.round(ativas.reduce((s, v) => s + (Number(v.valorTotal) || 0), 0) * 100) / 100;
  const estado = { pedidos: pedidos, total: total };
  cacheGravarJson_(chave, estado, 15);
  return estado;
}
function getMesaPublica(numero, codigo) {
  const v = validarMesaQr_(numero, codigo); if (!v.ok) return v;
  const mesa = readMesas().find(m => m.id === v.mesa.id) || v.mesa;
  const estado = montarEstadoMesaPublica_(mesa);
  return { ok: true, mesa: { numero: mesa.numero, status: mesa.status, chamando: !!mesa.chamadoEm }, pedidos: estado.pedidos, total: estado.total, caixaAberto: !!readSessaoAberta() };
}
function criarPedidoMesa(numero, codigo, itens, clienteNome, requisicaoId) {
  const v = validarMesaQr_(numero, codigo); if (!v.ok) return v;
  const mesa = v.mesa;
  if (['Livre', 'Ocupada'].indexOf(mesa.status) === -1) {
    return { ok: false, message: mesa.status === 'Aguardando fechamento' ? 'A conta desta mesa já foi pedida. Chame o garçom para novos pedidos.' : 'Esta mesa não está disponível para pedidos pelo celular. Chame o garçom.' };
  }
  const r = criarPedidoCardapio(itens, clienteNome, '', 'Mesa', {}, '', '', requisicaoId, '', { id: mesa.id, numero: mesa.numero });
  if (r.ok && !r.duplicado) { registrarFalha_('pedmesa_' + mesa.id); registrarFalha_('pedcard_global'); cacheLimpar_('mp_' + mesa.id); }
  return r;
}
function cancelarPedidoMesa(numero, codigo, vendaId) {
  const v = validarMesaQr_(numero, codigo); if (!v.ok) return v;
  const mesa = v.mesa;
  const sh = ss_().getSheetByName('Vendas'); const i = linhaDoId_(sh, vendaId);
  if (i < 1) return { ok: false, message: 'Pedido não encontrado.' };
  const venda = readVendas().find(x => x.id === vendaId);
  if (!venda || venda.mesaId !== mesa.id || venda.origem !== 'Cardápio') return { ok: false, message: 'Pedido não encontrado nesta mesa.' };
  if (venda.status !== 'Confirmada') return { ok: false, message: 'Esse pedido já foi cancelado.' };
  if (venda.statusPedido !== 'Recebido') return { ok: false, message: 'O restaurante já aceitou este pedido. Chame o garçom para alterar.' };
  sh.getRange(i, 8).setValue('Cancelada');
  sh.getRange(i, 9).setValue('Cancelado pelo cliente (mesa ' + mesa.numero + ')');
  ajustarEstoquePorVenda(readItensVenda().filter(it => it.vendaId === vendaId), -1, vendaId);
  registrarLog('Pedido de mesa cancelado pelo cliente', venda.clienteNome || '', 'Mesa ' + mesa.numero + ' | R$ ' + Number(venda.valorTotal || 0).toFixed(2));
  // Mesa aberta só por esse pedido (sem garçom e sem outro pedido pendente): volta a Livre, para não ficar "Ocupada" fantasma.
  const restantes = readVendas().filter(x => x.mesaId === mesa.id && x.status === 'Confirmada' && x.statusPagamento === 'A Receber');
  const atual = readMesas().find(m => m.id === mesa.id);
  if (atual && atual.status === 'Ocupada' && !atual.garcomResponsavel && !restantes.length) liberarMesaServidor_(mesa.id);
  cacheLimpar_('mp_' + mesa.id);
  return { ok: true, message: 'Pedido cancelado.' };
}
function pedirContaMesa(numero, codigo) {
  const v = validarMesaQr_(numero, codigo); if (!v.ok) return v;
  const mesa = readMesas().find(m => m.id === v.mesa.id);
  if (mesa.status === 'Aguardando fechamento') return { ok: true, message: 'A conta já foi pedida. Já estamos a caminho!' };
  if (mesa.status !== 'Ocupada') return { ok: false, message: 'Faça um pedido antes de pedir a conta.' };
  if (excedeuTentativas_('pedirconta_' + mesa.id, 3)) return { ok: false, message: 'Já recebemos seu pedido de conta. Aguarde um instante.' };
  definirStatusMesaServidor_(mesa.id, 'Aguardando fechamento');
  registrarFalha_('pedirconta_' + mesa.id);
  registrarLog('Conta pedida pelo cliente na mesa', '', 'Mesa ' + mesa.numero);
  cacheLimpar_('mp_' + mesa.id);
  return { ok: true, message: 'Conta solicitada! Em instantes alguém vem até a sua mesa.' };
}
function chamarGarcomMesa(numero, codigo) {
  const v = validarMesaQr_(numero, codigo); if (!v.ok) return v;
  const mesa = v.mesa;
  if (excedeuTentativas_('chamargarcom_' + mesa.id, 3)) return { ok: true, message: 'Já avisamos o garçom. Já estamos a caminho!' };
  const c = jsonConfig_(MESA_CHAMADOS_CHAVE_); c[mesa.id] = Date.now();
  salvarConfigChave_(MESA_CHAMADOS_CHAVE_, JSON.stringify(c));
  registrarFalha_('chamargarcom_' + mesa.id);
  registrarLog('Garçom chamado pelo cliente na mesa', '', 'Mesa ' + mesa.numero);
  return { ok: true, message: 'Garçom chamado! Já estamos a caminho.' };
}
function atenderChamadoMesa(mesaId) {
  const mesa = readMesas().find(m => m.id === mesaId);
  if (!mesa) return { ok: false, message: 'Mesa não encontrada.' };
  if (NIVEL_ATUAL === 'Garçom' && mesa.garcomResponsavel && String(mesa.garcomResponsavel).toLowerCase() !== String(USUARIO_ATUAL || '').toLowerCase()) return { ok: false, message: 'Esta mesa está sob responsabilidade de outro garçom.' };
  limparChamadoMesa_(mesaId);
  return { ok: true, mesas: readMesas() };
}
function addMesa(numero, capacidade) {
  if (numero === '' || numero === null || numero === undefined) return { ok: false, message: 'Informe o número da mesa.' };
  const existentes = readMesas();
  if (existentes.some(m => String(m.numero) === String(numero))) return { ok: false, message: 'Já existe uma mesa com esse número.' };
  const sh = ss_().getSheetByName('Mesas');
  sh.appendRow([Utilities.getUuid(), numero, 'Livre', capacidade || '', '', '']);
  registrarLog('Mesa cadastrada', '', 'Mesa ' + numero);
  return { ok: true, message: 'Mesa cadastrada.', mesas: readMesas() };
}
function editarStatusMesa(id, novoStatus, observacao) {
  const validos = ['Livre', 'Ocupada', 'Aguardando fechamento', 'Fechada', 'Bloqueada/Manutenção'];
  if (validos.indexOf(novoStatus) === -1) return { ok: false, message: 'Status de mesa inválido.' };
  const sh = ss_().getSheetByName('Mesas'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      const statusAtual = String(sh.getRange(i, 3).getValue() || 'Livre');
      const responsavelAtual = String(sh.getRange(i, 6).getValue() || '');
      // Regra de escopo no próprio endpoint: Garçom só abre sua mesa e só a devolve a Livre.
      if (NIVEL_ATUAL === 'Garçom') {
        const eu = String(USUARIO_ATUAL || '').toLowerCase();
        if (novoStatus === 'Ocupada') {
          if (statusAtual !== 'Livre') return { ok: false, message: 'Somente mesas livres podem ser abertas pelo garçom.' };
          sh.getRange(i, 6).setValue(USUARIO_ATUAL || '');
        } else if (novoStatus === 'Aguardando fechamento') {
          if (responsavelAtual && responsavelAtual.toLowerCase() !== eu) return { ok: false, message: 'Esta mesa está sob responsabilidade de outro garçom.' };
          if (statusAtual !== 'Ocupada') return { ok: false, message: 'Somente uma mesa ocupada pode ser enviada para fechamento.' };
        } else if (novoStatus === 'Livre') {
          if (responsavelAtual && responsavelAtual.toLowerCase() !== eu) return { ok: false, message: 'Esta mesa está sob responsabilidade de outro garçom.' };
          return { ok: false, message: 'O garçom não libera a mesa diretamente; o caixa deve fechar a conta.' };
        } else {
          return { ok: false, message: 'O garçom não pode alterar a mesa para este estado.' };
        }
        if (observacao !== undefined) sh.getRange(i, 5).setValue(observacao);
      } else {
        sh.getRange(i, 3).setValue(novoStatus);
        if (observacao !== undefined) sh.getRange(i, 5).setValue(observacao);
        if (novoStatus === 'Livre') sh.getRange(i, 6).setValue('');
      }
      sh.getRange(i, 3).setValue(novoStatus);
      if (novoStatus === 'Livre') sh.getRange(i, 6).setValue('');
      registrarLog('Status de mesa alterado', '', 'Mesa ' + sh.getRange(i, 2).getValue() + ': ' + statusAtual + ' → ' + novoStatus);
      return { ok: true, mesas: readMesas() };
    }
  }
  return { ok: false, message: 'Mesa não encontrada.' };
}
function excluirMesa(id) {
  const mesa = readMesas().find(m => m.id === id);
  if (mesa && mesa.status === 'Ocupada') return { ok: false, message: 'Não é possível excluir uma mesa ocupada.' };
  const sh = ss_().getSheetByName('Mesas'); const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 1).getValue() === id) { sh.deleteRow(i); break; } }
  return { ok: true, mesas: readMesas() };
}
/* ETAPA 3: libera a mesa direto na planilha. Existe porque editarStatusMesa recusa o Garçom ao devolver uma mesa a "Livre",
   e o fechamento de conta é uma ação do servidor, já validada (dono da mesa, caixa aberto, soma dos pagamentos). */
function liberarMesaServidor_(mesaId) {
  const sh = ss_().getSheetByName('Mesas');
  const i = linhaDoId_(sh, mesaId);
  if (i < 1) return false;
  const anterior = String(sh.getRange(i, 3).getValue() || 'Livre');
  sh.getRange(i, 3).setValue('Livre');
  sh.getRange(i, 6).setValue('');
  registrarLog('Status de mesa alterado', '', 'Mesa ' + sh.getRange(i, 2).getValue() + ': ' + anterior + ' → Livre');
  return true;
}

/* Fecha a conta de uma mesa: pega todas as vendas "A Receber" daquela mesa,
   confere que a soma bate com o pagamento informado (aceita dividir — Item 40),
   marca todas como pagas e libera a mesa (Item 58).
   ETAPA 3: Garçom pode receber, mas só em mesa sob a sua responsabilidade. */
function fecharContaMesa(mesaId, pagamentos) {
  const mesa = readMesas().find(m => m.id === mesaId);
  if (!mesa) return { ok: false, message: 'Mesa não encontrada.' };
  if (NIVEL_ATUAL === 'Garçom') {
    if (!mesa.garcomResponsavel || String(mesa.garcomResponsavel).toLowerCase() !== String(USUARIO_ATUAL || '').toLowerCase()) {
      return { ok: false, message: 'Esta mesa não está sob a sua responsabilidade.' };
    }
  }
  // "A Receber (Mesa)" nunca é forma de recebimento (ETAPA 2).
  if ((pagamentos || []).some(p => p && String(p.forma || '').trim() === 'A Receber (Mesa)')) return { ok: false, message: 'Forma de pagamento inválida para esta operação.' };
  const vendasDaMesa = readVendas().filter(v => v.mesaId === mesaId && v.status === 'Confirmada' && v.statusPagamento === 'A Receber');
  if (!vendasDaMesa.length) { liberarMesaServidor_(mesaId); return { ok: true, message: 'Essa mesa não tinha conta pendente. Liberada.', vendas: readVendasResposta_(), mesas: readMesas() }; }
  // ETAPA A: o dinheiro recebido precisa cair numa sessão de caixa, senão fica fora do fechamento e a gaveta nunca bate.
  if (!readSessaoAberta()) return { ok: false, message: 'Abra o caixa antes de fechar a conta da mesa — o valor recebido precisa entrar no fechamento do caixa.' };
  const totalConta = Math.round(vendasDaMesa.reduce((s, v) => s + v.valorTotal, 0) * 100) / 100;
  const erroPagamentos = validarPagamentosVenda_(pagamentos, 'Mesa', NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador' ? NIVEL_ATUAL : 'Caixa');
  if (erroPagamentos) return { ok: false, message: erroPagamentos };
  const somaPagamentos = Math.round((pagamentos || []).reduce((s, p) => s + Number(p.valor), 0) * 100) / 100;
  if (Math.abs(somaPagamentos - totalConta) > 0.02) return { ok: false, message: 'A soma dos pagamentos (R$ ' + somaPagamentos.toFixed(2) + ') não bate com a conta da mesa (R$ ' + totalConta.toFixed(2) + ').' };

  const shVendas = ss_().getSheetByName('Vendas');
  const last = shVendas.getLastRow();
  const formaResumo = pagamentos.map(p => p.forma).join(' + ');
  const shPagamentos = ss_().getSheetByName('PagamentosVenda');
  for (let i = 2; i <= last; i++) {
    const idLinha = shVendas.getRange(i, 1).getValue();
    const venda = vendasDaMesa.find(v => v.id === idLinha);
    if (!venda) continue;
    shVendas.getRange(i, 5).setValue(formaResumo);
    shVendas.getRange(i, 18).setValue('Pago');
    shVendas.getRange(i, 19).setValue(new Date());
    // Divide o pagamento informado proporcionalmente ao valor de cada venda da mesa, e registra na aba de pagamentos.
    const proporcao = totalConta > 0 ? (venda.valorTotal / totalConta) : (1 / vendasDaMesa.length);
    pagamentos.forEach(p => { const parte = Math.round(Number(p.valor) * proporcao * 100) / 100; shPagamentos.appendRow([Utilities.getUuid(), idLinha, p.forma, parte, calcularTaxaPagamento_(p.forma, parte)]); });
  }
  const telsMesa = {};
  vendasDaMesa.forEach(v => { if (v.clienteTelefone && !telsMesa[normTel(v.clienteTelefone)]) { telsMesa[normTel(v.clienteTelefone)] = 1; addOrStampFidelidade(v.clienteTelefone, v.clienteNome, ''); } });
  liberarMesaServidor_(mesaId);
  registrarLog('Conta de mesa fechada', '', 'Mesa ' + mesa.numero + ': R$ ' + totalConta.toFixed(2) + ' | ' + formaResumo + ' | recebido por ' + (USUARIO_ATUAL || '?') + ' (' + NIVEL_ATUAL + ')');
  return { ok: true, message: 'Conta da mesa ' + mesa.numero + ' fechada — R$ ' + totalConta.toFixed(2) + '.', vendas: readVendasResposta_(), mesas: readMesas() };
}

/* ---------- PREÇOS POR FORMA DE PAGAMENTO ---------- */
function salvarPrecosDoProduto(produtoId, precos) {
  const sh = ss_().getSheetByName('ProdutoPrecos');
  const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 2).getValue() === produtoId) sh.deleteRow(i); }
  (precos || []).forEach(p => {
    if (!p.formaPagamentoId) return;
    sh.appendRow([Utilities.getUuid(), produtoId, p.formaPagamentoId, Number(p.preco) || 0, Number(p.custo) || 0]);
  });
}
function salvarPrecosDoCombo(comboId, precos) {
  const sh = ss_().getSheetByName('ComboPrecos');
  const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 2).getValue() === comboId) sh.deleteRow(i); }
  (precos || []).forEach(p => {
    if (!p.formaPagamentoId) return;
    sh.appendRow([Utilities.getUuid(), comboId, p.formaPagamentoId, Number(p.preco) || 0, Number(p.custo) || 0]);
  });
}
/* Preenche automaticamente o preço/custo de todas as formas de pagamento ativas
   a partir de um "preço base" único, usado ao cadastrar produto/combo novo. */
function expandirPrecoBase(precoBase, custoBase, overridesPorForma) {
  const formas = readFormasPagamento();
  const overrides = overridesPorForma || {};
  return formas.map(f => ({
    formaPagamentoId: f.id,
    preco: overrides[f.id] && overrides[f.id].preco !== undefined ? overrides[f.id].preco : (Number(precoBase) || 0),
    custo: overrides[f.id] && overrides[f.id].custo !== undefined ? overrides[f.id].custo : (Number(custoBase) || 0)
  }));
}

function addProduto(nome, descricao, categoria, precoBase, custoBase, precos, ingredientes, destaque, adicionaisIds, estoqueProprio) {
  if (!nome) return { ok: false, message: 'Informe o nome do produto.' };
  if (nomeJaExiste_(readProdutos(), nome)) return { ok: false, message: 'Já existe um produto com esse nome.' };
  const sh = ss_().getSheetByName('Produtos');
  const id = Utilities.getUuid();
  const estoqueProprioId = aplicarEstoqueProprio_(null, nome, estoqueProprio);
  const doCategoria = readProdutos().filter(p => p.categoria === categoria);
  const proximaOrdem = doCategoria.length ? Math.max.apply(null, doCategoria.map(p => p.ordemCardapio)) + 1 : 1;
  sh.appendRow([id, nome, descricao || '', categoria || '', 'Sim', '', destaque ? 'Sim' : 'Não', estoqueProprioId, proximaOrdem]);
  const listaPrecos = (precos && precos.length) ? precos : expandirPrecoBase(precoBase, custoBase);
  salvarPrecosDoProduto(id, listaPrecos);
  const listaIngredientes = (ingredientes || []).slice();
  if (estoqueProprioId) listaIngredientes.push({ ingredienteId: estoqueProprioId, ingredienteNome: nome, quantidadePorUnidade: 1 });
  salvarIngredientesDoProduto(id, listaIngredientes);
  salvarAdicionaisDoProduto(id, adicionaisIds);
  registrarLog('Produto cadastrado', '', nome);
  return { ok: true, message: 'Produto cadastrado.', id: id, produtos: readProdutos(), produtoPrecos: readProdutoPrecos(), produtoIngredientes: readProdutoIngredientes(), produtoAdicionais: readProdutoAdicionais(), estoque: readEstoqueResposta_() };
}
/* ---------- CURADORIA DO CARDÁPIO DIGITAL (ITEM 93) ----------
   Ações leves e específicas pra tela de curadoria — não pedem nome/categoria/
   preço de novo, só o que realmente muda ali: aparece ou não, destaque, ordem. */
function editarVisibilidadeCardapioProduto(id, ativo, destaque) {
  const sh = ss_().getSheetByName('Produtos'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      if (ativo !== undefined) sh.getRange(i, 5).setValue(ativo === false ? 'Não' : 'Sim');
      if (destaque !== undefined) sh.getRange(i, 7).setValue(destaque ? 'Sim' : 'Não');
      return { ok: true, produtos: readProdutos() };
    }
  }
  return { ok: false, message: 'Produto não encontrado.' };
}
function editarOrdemCardapioProduto(id, ordem) {
  const sh = ss_().getSheetByName('Produtos'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) { sh.getRange(i, 9).setValue(Number(ordem) || 0); return { ok: true, produtos: readProdutos() }; }
  }
  return { ok: false, message: 'Produto não encontrado.' };
}
function editarProduto(id, nome, descricao, categoria, ativo, precos, ingredientes, destaque, adicionaisIds, estoqueProprio) {
  const sh = ss_().getSheetByName('Produtos'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      const produtoAtual = readProdutos().find(p => p.id === id);
      const precosAntes = readProdutoPrecos().filter(p => p.produtoId === id);
      sh.getRange(i, 2, 1, 4).setValues([[nome, descricao || '', categoria || '', ativo === false ? 'Não' : 'Sim']]);
      if (destaque !== undefined) sh.getRange(i, 7).setValue(destaque ? 'Sim' : 'Não');
      const estoqueProprioId = aplicarEstoqueProprio_(produtoAtual, nome, estoqueProprio);
      sh.getRange(i, 8).setValue(estoqueProprioId);
      if (precos) salvarPrecosDoProduto(id, precos);
      const listaIngredientes = (ingredientes || []).slice();
      if (estoqueProprioId) listaIngredientes.push({ ingredienteId: estoqueProprioId, ingredienteNome: nome, quantidadePorUnidade: 1 });
      salvarIngredientesDoProduto(id, listaIngredientes);
      if (adicionaisIds !== undefined) salvarAdicionaisDoProduto(id, adicionaisIds);
      let detalhesPreco = '';
      if (precos) {
        const formas = readFormasPagamento();
        precos.forEach(p => {
          const antigo = precosAntes.find(a => a.formaPagamentoId === p.formaPagamentoId);
          if (antigo && Number(antigo.preco) !== Number(p.preco)) {
            const nomeForma = (formas.find(f => f.id === p.formaPagamentoId) || {}).nome || '?';
            detalhesPreco += nomeForma + ': R$ ' + Number(antigo.preco).toFixed(2) + ' → R$ ' + Number(p.preco).toFixed(2) + '; ';
          }
        });
      }
      registrarLog('Produto editado', '', nome + (detalhesPreco ? ' — Preços alterados: ' + detalhesPreco : ''));
      return { ok: true, message: 'Produto atualizado.', produtos: readProdutos(), produtoPrecos: readProdutoPrecos(), produtoIngredientes: readProdutoIngredientes(), produtoAdicionais: readProdutoAdicionais(), estoque: readEstoqueResposta_() };
    }
  }
  return { ok: false, message: 'Produto não encontrado.' };
}
function excluirProduto(id) {
  const sh = ss_().getSheetByName('Produtos'); const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) {
    if (sh.getRange(i, 1).getValue() === id) {
      const fotoId = sh.getRange(i, 6).getValue();
      if (fotoId) { try { DriveApp.getFileById(fotoId).setTrashed(true); } catch (e) {} }
      sh.deleteRow(i); break;
    }
  }
  const shPI = ss_().getSheetByName('ProdutoIngredientes'); const lastPI = shPI.getLastRow();
  for (let i = lastPI; i >= 2; i--) { if (shPI.getRange(i, 2).getValue() === id) shPI.deleteRow(i); }
  const shPP = ss_().getSheetByName('ProdutoPrecos'); const lastPP = shPP.getLastRow();
  for (let i = lastPP; i >= 2; i--) { if (shPP.getRange(i, 2).getValue() === id) shPP.deleteRow(i); }
  registrarLog('Produto excluído', '', id);
  return { ok: true, produtos: readProdutos(), produtoPrecos: readProdutoPrecos(), produtoIngredientes: readProdutoIngredientes() };
}

/* ---------- FORMAS DE PAGAMENTO ---------- */
function validarConfigForma_(taxaPct, taxaFixa, prazoDias) {
  const pct = Number(taxaPct) || 0, fixa = Number(taxaFixa) || 0, prazo = Number(prazoDias) || 0;
  if (pct < 0 || pct > 100) return 'A taxa % deve ficar entre 0 e 100.';
  if (fixa < 0) return 'A taxa fixa não pode ser negativa.';
  if (prazo < 0 || prazo > 365 || Math.floor(prazo) !== prazo) return 'O prazo deve ser um número inteiro de dias (0 a 365).';
  return '';
}
function addFormaPagamento(nome, taxaPct, taxaFixa, prazoDias, permiteTroco) {
  nome = String(nome || '').trim();
  if (!nome) return { ok: false, message: 'Informe o nome da forma de pagamento.' };
  if (readFormasPagamento().some(f => f.nome.toLowerCase() === nome.toLowerCase())) return { ok: false, message: 'Já existe uma forma de pagamento com esse nome.' };
  const erro = validarConfigForma_(taxaPct, taxaFixa, prazoDias);
  if (erro) return { ok: false, message: erro };
  const sh = ss_().getSheetByName('Formas de Pagamento');
  const id = Utilities.getUuid();
  const ordem = readFormasPagamento().reduce((m, f) => Math.max(m, f.ordem), 0) + 1;
  sh.appendRow([id, nome, 'Sim', 'Sim', Number(taxaPct) || 0, Number(taxaFixa) || 0, Number(prazoDias) || 0, permiteTroco ? 'Sim' : 'Não', ordem]);

  // Ao nascer, a nova forma já recebe o preço/custo "base" (usa a primeira forma ativa como referência)
  const formas = readFormasPagamento();
  const referencia = formas.find(f => f.id !== id) || null;

  const shPP = ss_().getSheetByName('ProdutoPrecos');
  readProdutos().forEach(p => {
    const precoRef = referencia ? (readProdutoPrecos().find(pp => pp.produtoId === p.id && pp.formaPagamentoId === referencia.id)) : null;
    shPP.appendRow([Utilities.getUuid(), p.id, id, precoRef ? precoRef.preco : 0, precoRef ? precoRef.custo : 0]);
  });
  const shCP = ss_().getSheetByName('ComboPrecos');
  readCombos().forEach(c => {
    const precoRef = referencia ? (readComboPrecos().find(cp => cp.comboId === c.id && cp.formaPagamentoId === referencia.id)) : null;
    shCP.appendRow([Utilities.getUuid(), c.id, id, precoRef ? precoRef.preco : 0, precoRef ? precoRef.custo : 0]);
  });

  registrarLog('Forma de pagamento cadastrada', '', nome + ' | taxa ' + (Number(taxaPct) || 0) + '% + R$ ' + (Number(taxaFixa) || 0).toFixed(2) + ' | prazo ' + (Number(prazoDias) || 0) + 'd | troco ' + (permiteTroco ? 'sim' : 'não'));
  return { ok: true, message: 'Forma de pagamento cadastrada.', formasPagamento: readFormasPagamento(), produtoPrecos: readProdutoPrecos(), comboPrecos: readComboPrecos() };
}
/* Campos não enviados (undefined) ficam como estão. Mudança de taxa vale só para vendas FUTURAS
   (as antigas guardam a taxa aplicada na época) e fica no Log com antes → depois. */
function editarFormaPagamento(id, novoNome, novoAtivo, novoVisivelCardapio, novaTaxaPct, novaTaxaFixa, novoPrazoDias, novoPermiteTroco, novaOrdem) {
  const sh = ss_().getSheetByName('Formas de Pagamento'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() !== id) continue;
    const atual = readFormasPagamento().find(f => f.id === id);
    const pct = novaTaxaPct !== undefined ? novaTaxaPct : atual.taxaPct;
    const fixa = novaTaxaFixa !== undefined ? novaTaxaFixa : atual.taxaFixa;
    const prazo = novoPrazoDias !== undefined ? novoPrazoDias : atual.prazoDias;
    const erro = validarConfigForma_(pct, fixa, prazo);
    if (erro) return { ok: false, message: erro };
    if (novoNome) {
      const nomeLimpo = String(novoNome).trim();
      if (nomeLimpo !== atual.nome) {
        if (readFormasPagamento().some(f => f.id !== id && f.nome.toLowerCase() === nomeLimpo.toLowerCase())) return { ok: false, message: 'Já existe uma forma de pagamento com esse nome.' };
        // Vendas antigas guardam o NOME da forma; renomear quebraria o vínculo.
        if (readPagamentosVenda().some(p => p.forma === atual.nome)) return { ok: false, message: 'Essa forma já foi usada em vendas e não pode ser renomeada. Desative e cadastre uma nova.' };
        sh.getRange(i, 2).setValue(nomeLimpo);
      }
    }
    if (novoAtivo !== undefined) sh.getRange(i, 3).setValue(novoAtivo === false ? 'Não' : 'Sim');
    if (novoVisivelCardapio !== undefined) sh.getRange(i, 4).setValue(novoVisivelCardapio === false ? 'Não' : 'Sim');
    sh.getRange(i, 5, 1, 3).setValues([[Number(pct) || 0, Number(fixa) || 0, Number(prazo) || 0]]);
    if (novoPermiteTroco !== undefined) sh.getRange(i, 8).setValue(novoPermiteTroco ? 'Sim' : 'Não');
    if (novaOrdem !== undefined) sh.getRange(i, 9).setValue(Number(novaOrdem) || 0);
    const depois = readFormasPagamento().find(f => f.id === id);
    const mudou = [];
    if (depois.taxaPct !== atual.taxaPct) mudou.push('taxa % ' + atual.taxaPct + ' → ' + depois.taxaPct);
    if (depois.taxaFixa !== atual.taxaFixa) mudou.push('taxa fixa R$ ' + atual.taxaFixa.toFixed(2) + ' → R$ ' + depois.taxaFixa.toFixed(2));
    if (depois.prazoDias !== atual.prazoDias) mudou.push('prazo ' + atual.prazoDias + 'd → ' + depois.prazoDias + 'd');
    if (depois.permiteTroco !== atual.permiteTroco) mudou.push('troco ' + (atual.permiteTroco ? 'sim' : 'não') + ' → ' + (depois.permiteTroco ? 'sim' : 'não'));
    if (depois.ativa !== atual.ativa) mudou.push(depois.ativa ? 'reativada' : 'desativada');
    registrarLog('Forma de pagamento atualizada', '', depois.nome + (mudou.length ? ' | ' + mudou.join(' | ') : ''));
    return { ok: true, message: 'Forma de pagamento atualizada.', formasPagamento: readFormasPagamento() };
  }
  return { ok: false, message: 'Forma de pagamento não encontrada.' };
}

/* ---------- ESTOQUE (INGREDIENTES) ---------- */
function addIngrediente(nome, quantidade, minimo, unidade, custo) {
  if (!nome) return { ok: false, message: 'Informe o nome do ingrediente.' };
  if (nomeJaExiste_(readEstoque(), nome)) return { ok: false, message: 'Já existe um ingrediente com esse nome.' };
  const sh = ss_().getSheetByName('Estoque');
  const id = Utilities.getUuid();
  const qtdInicial = Number(quantidade) || 0;
  sh.appendRow([id, nome, qtdInicial, Number(minimo) || 0, unidade || 'un', Number(custo) || 0, 'Ativo']);
  if (qtdInicial > 0) registrarMovimentoEstoque_(id, nome, 'Entrada', qtdInicial, 0, qtdInicial, 'Estoque inicial do cadastro');
  registrarLog('Ingrediente cadastrado', '', nome);
  return { ok: true, message: 'Ingrediente cadastrado.', estoque: readEstoqueResposta_(), movimentacoesEstoque: readMovimentacoesEstoque() };
}
function editarIngrediente(id, nome, quantidade, minimo, unidade, custo, ativo) {
  const sh = ss_().getSheetByName('Estoque'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      const qtdAntes = numPlanilha_(sh.getRange(i, 3).getValue()) || 0;
      const qtdDepois = Number(quantidade) || 0;
      sh.getRange(i, 2, 1, 4).setValues([[nome, qtdDepois, Number(minimo) || 0, unidade || 'un']]);
      sh.getRange(i, 6).setValue(Number(custo) || 0);
      if (ativo !== undefined) sh.getRange(i, 7).setValue(ativo === false ? 'Inativo' : 'Ativo');
      if (qtdDepois !== qtdAntes) registrarMovimentoEstoque_(id, nome, 'Ajuste', qtdDepois - qtdAntes, qtdAntes, qtdDepois, 'Edição manual do cadastro');
      registrarLog('Estoque atualizado', '', nome + ': ' + qtdAntes + ' → ' + qtdDepois + ' ' + (unidade || 'un'));
      return { ok: true, message: 'Estoque atualizado.', estoque: readEstoqueResposta_(), movimentacoesEstoque: readMovimentacoesEstoque() };
    }
  }
  return { ok: false, message: 'Ingrediente não encontrado.' };
}
/* ---------- MOVIMENTAÇÕES MANUAIS DE ESTOQUE (ITEM 29) ---------- */
function registrarEntradaEstoque(ingredienteId, quantidade, motivo) {
  const qtd = Number(quantidade) || 0;
  if (qtd <= 0) return { ok: false, message: 'Informe uma quantidade de entrada maior que zero.' };
  const sh = ss_().getSheetByName('Estoque'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() === ingredienteId) {
      const nome = sh.getRange(i, 2).getValue();
      const qtdAntes = numPlanilha_(sh.getRange(i, 3).getValue()) || 0;
      const qtdDepois = qtdAntes + qtd;
      sh.getRange(i, 3).setValue(qtdDepois);
      registrarMovimentoEstoque_(ingredienteId, nome, 'Entrada', qtd, qtdAntes, qtdDepois, motivo || 'Reposição de estoque');
      registrarLog('Entrada de estoque', '', nome + ': +' + qtd);
      return { ok: true, message: 'Entrada registrada.', estoque: readEstoqueResposta_(), movimentacoesEstoque: readMovimentacoesEstoque() };
    }
  }
  return { ok: false, message: 'Ingrediente não encontrado.' };
}
function registrarPerdaEstoque(ingredienteId, quantidade, motivo) {
  const qtd = Number(quantidade) || 0;
  if (qtd <= 0) return { ok: false, message: 'Informe uma quantidade de perda maior que zero.' };
  if (!motivo) return { ok: false, message: 'Informe o motivo da perda.' };
  const sh = ss_().getSheetByName('Estoque'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() === ingredienteId) {
      const nome = sh.getRange(i, 2).getValue();
      const qtdAntes = numPlanilha_(sh.getRange(i, 3).getValue()) || 0;
      const qtdDepois = Math.max(0, qtdAntes - qtd);
      sh.getRange(i, 3).setValue(qtdDepois);
      registrarMovimentoEstoque_(ingredienteId, nome, 'Perda', -qtd, qtdAntes, qtdDepois, motivo);
      registrarLog('Perda de estoque', '', nome + ': -' + qtd + ' (' + motivo + ')');
      return { ok: true, message: 'Perda registrada.', estoque: readEstoqueResposta_(), movimentacoesEstoque: readMovimentacoesEstoque() };
    }
  }
  return { ok: false, message: 'Ingrediente não encontrado.' };
}
function registrarInventarioEstoque(ingredienteId, novaQuantidade, motivo) {
  const nova = Number(novaQuantidade);
  if (isNaN(nova) || nova < 0) return { ok: false, message: 'Informe uma quantidade de inventário válida.' };
  const sh = ss_().getSheetByName('Estoque'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() === ingredienteId) {
      const nome = sh.getRange(i, 2).getValue();
      const qtdAntes = numPlanilha_(sh.getRange(i, 3).getValue()) || 0;
      sh.getRange(i, 3).setValue(nova);
      registrarMovimentoEstoque_(ingredienteId, nome, 'Inventário', nova - qtdAntes, qtdAntes, nova, motivo || 'Contagem de inventário');
      registrarLog('Inventário de estoque', '', nome + ': ' + qtdAntes + ' → ' + nova + ' (contagem física)');
      return { ok: true, message: 'Inventário registrado.', estoque: readEstoqueResposta_(), movimentacoesEstoque: readMovimentacoesEstoque() };
    }
  }
  return { ok: false, message: 'Ingrediente não encontrado.' };
}
function excluirIngrediente(id) {
  const sh = ss_().getSheetByName('Estoque'); const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 1).getValue() === id) { sh.deleteRow(i); break; } }
  registrarLog('Ingrediente excluído', '', id);
  return { ok: true, estoque: readEstoqueResposta_() };
}

/* Quanto de cada ingrediente uma lista de itens consome (produto, combo e adicionais — ITENS 25–28). */
function consumoDosItens_(itens) {
  const mapaProduto = readProdutoIngredientes();
  const mapaComboItens = readComboItens();
  const mapaAdicionais = readAdicionais();
  const consumo = {};
  const soma = (ingId, qtd) => { if (ingId && qtd) consumo[ingId] = (consumo[ingId] || 0) + qtd; };
  const porProduto = (produtoId, vezes) => mapaProduto.filter(v => v.produtoId === produtoId).forEach(v => soma(v.ingredienteId, (Number(v.quantidadePorUnidade) || 0) * vezes));
  (itens || []).forEach(item => {
    const qtd = Number(item.quantidade) || 0;
    if (item.produtoId) porProduto(item.produtoId, qtd);
    if (item.comboId) mapaComboItens.filter(ci => ci.comboId === item.comboId).forEach(ci => porProduto(ci.produtoId, (Number(ci.quantidade) || 0) * qtd));
    (item.adicionaisIds || []).forEach(adId => {
      const ad = mapaAdicionais.find(a => a.id === adId);
      if (ad && ad.ingredienteId) soma(ad.ingredienteId, (Number(ad.quantidadeDesconto) || 1) * qtd);
    });
  });
  return consumo;
}
/* ITEM 99 (estoque insuficiente): se o Admin ligou "bloquear venda sem estoque", recusa ANTES de gravar qualquer coisa. */
function verificarEstoqueVenda_(itens, origem) {
  if (String(lerConfigChave_('BLOQUEAR_ESTOQUE_NEGATIVO', 'Não')) !== 'Sim') return '';
  if (String(origem || '').indexOf('Contingência') === 0) return ''; // venda que já aconteceu: reconciliar, não recusar
  const consumo = consumoDosItens_(itens);
  const ids = Object.keys(consumo); if (!ids.length) return '';
  const sh = ss_().getSheetByName('Estoque'); const last = sh.getLastRow(); if (last < 2) return '';
  const linhas = sh.getRange(2, 1, last - 1, 3).getValues();
  for (let k = 0; k < ids.length; k++) {
    const l = linhas.find(r => r[0] === ids[k]); if (!l) continue;
    const atual = numPlanilha_(l[2]);
    if (atual + 1e-9 < consumo[ids[k]]) {
      return origem === 'Cardápio' ? 'Um dos itens do pedido acabou. Escolha outro item ou fale com o restaurante.'
        : 'Estoque insuficiente de "' + l[1] + '" (tem ' + atual + ', a venda precisa de ' + Math.round(consumo[ids[k]] * 1000) / 1000 + ').';
    }
  }
  return '';
}
function ajustarEstoquePorVenda(itens, direcao, vendaId) {
  const consumo = consumoDosItens_(itens);
  const ids = Object.keys(consumo); if (!ids.length) return;
  const shEstoque = ss_().getSheetByName('Estoque');
  const last = shEstoque.getLastRow(); if (last < 2) return;
  const linhas = shEstoque.getRange(2, 1, last - 1, 3).getValues(); // UMA leitura (antes: uma por célula)
  const tipoMovimento = direcao > 0 ? 'Venda' : 'Saída';
  const referencia = vendaId ? ('Venda #' + String(vendaId).slice(0, 8)) : (direcao > 0 ? 'Venda' : 'Estorno de venda');
  const mov = [];
  ids.forEach(ingId => {
    const idx = linhas.findIndex(r => r[0] === ingId); if (idx === -1) return;
    const nome = linhas[idx][1];
    const atual = Number(linhas[idx][2]) || 0;
    const delta = direcao * consumo[ingId];
    const novo = Math.round((atual - delta) * 1e6) / 1e6;
    linhas[idx][2] = novo;
    if (direcao > 0 && novo < 0) registrarLog('Estoque negativo', '', nome + ': ' + novo + ' (' + referencia + ')');
    if (delta !== 0) mov.push([Utilities.getUuid(), nome, tipoMovimento, -delta, atual, novo, referencia, USUARIO_ATUAL || '', new Date()]);
  });
  shEstoque.getRange(2, 3, linhas.length, 1).setValues(linhas.map(r => [r[2]])); // UMA gravação em bloco
  if (mov.length) { const shM = ss_().getSheetByName('MovimentaçõesEstoque'); shM.getRange(shM.getLastRow() + 1, 1, mov.length, 9).setValues(mov); }
}

/* ---------- COMBOS ---------- */
/* A baixa de estoque do combo é calculada automaticamente a partir dos ingredientes
   de cada produto que o compõe (ver ComboItens). */
function salvarItensDoCombo(comboId, itens) {
  const sh = ss_().getSheetByName('ComboItens');
  const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) { if (sh.getRange(i, 2).getValue() === comboId) sh.deleteRow(i); }
  (itens || []).forEach(it => {
    if (!it.produtoId || !(Number(it.quantidade) > 0)) return;
    sh.appendRow([Utilities.getUuid(), comboId, it.produtoId, Number(it.quantidade)]);
  });
}
function addCombo(nome, categoria, precoBase, custoBase, precos, itens, destaque) {
  if (!nome) return { ok: false, message: 'Informe o nome do combo.' };
  if (nomeJaExiste_(readCombos(), nome)) return { ok: false, message: 'Já existe um combo com esse nome.' };
  const sh = ss_().getSheetByName('Combos');
  const id = Utilities.getUuid();
  const doCategoria = readCombos().filter(c => c.categoria === categoria);
  const proximaOrdem = doCategoria.length ? Math.max.apply(null, doCategoria.map(c => c.ordemCardapio)) + 1 : 1;
  sh.appendRow([id, nome, categoria || '', 'Sim', '', destaque ? 'Sim' : 'Não', proximaOrdem]);
  const listaPrecos = (precos && precos.length) ? precos : expandirPrecoBase(precoBase, custoBase);
  salvarPrecosDoCombo(id, listaPrecos);
  salvarItensDoCombo(id, itens);
  registrarLog('Combo cadastrado', '', nome);
  return { ok: true, message: 'Combo cadastrado.', id: id, combos: readCombos(), comboPrecos: readComboPrecos(), comboItens: readComboItens() };
}
function editarVisibilidadeCardapioCombo(id, ativo, destaque) {
  const sh = ss_().getSheetByName('Combos'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      if (ativo !== undefined) sh.getRange(i, 4).setValue(ativo === false ? 'Não' : 'Sim');
      if (destaque !== undefined) sh.getRange(i, 6).setValue(destaque ? 'Sim' : 'Não');
      return { ok: true, combos: readCombos() };
    }
  }
  return { ok: false, message: 'Combo não encontrado.' };
}
function editarOrdemCardapioCombo(id, ordem) {
  const sh = ss_().getSheetByName('Combos'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) { sh.getRange(i, 7).setValue(Number(ordem) || 0); return { ok: true, combos: readCombos() }; }
  }
  return { ok: false, message: 'Combo não encontrado.' };
}
function editarCombo(id, nome, categoria, ativo, precos, itens, destaque) {
  const sh = ss_().getSheetByName('Combos'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      const precosAntes = readComboPrecos().filter(p => p.comboId === id);
      sh.getRange(i, 2, 1, 3).setValues([[nome, categoria || '', ativo === false ? 'Não' : 'Sim']]);
      if (destaque !== undefined) sh.getRange(i, 6).setValue(destaque ? 'Sim' : 'Não');
      if (precos) salvarPrecosDoCombo(id, precos);
      if (itens) salvarItensDoCombo(id, itens);
      let detalhesPreco = '';
      if (precos) {
        const formas = readFormasPagamento();
        precos.forEach(p => {
          const antigo = precosAntes.find(a => a.formaPagamentoId === p.formaPagamentoId);
          if (antigo && Number(antigo.preco) !== Number(p.preco)) {
            const nomeForma = (formas.find(f => f.id === p.formaPagamentoId) || {}).nome || '?';
            detalhesPreco += nomeForma + ': R$ ' + Number(antigo.preco).toFixed(2) + ' → R$ ' + Number(p.preco).toFixed(2) + '; ';
          }
        });
      }
      registrarLog('Combo editado', '', nome + (detalhesPreco ? ' — Preços alterados: ' + detalhesPreco : ''));
      return { ok: true, message: 'Combo atualizado.', combos: readCombos(), comboPrecos: readComboPrecos(), comboItens: readComboItens() };
    }
  }
  return { ok: false, message: 'Combo não encontrado.' };
}
/* ---------- IMPORTAÇÃO INICIAL DO CARDÁPIO (uso único) ----------
   Cadastra categorias, produtos, combos e bebidas com os dois preços (loja e
   iFood) de uma vez. Idempotente: se um nome já existir, não duplica — só
   avisa. Pode rodar de novo sem medo. */
function seedCardapioTexasBurger() {
  const resultado = { categorias: 0, produtos: 0, combos: 0, avisos: [] };
  const ss = ss_();

  /* ---- Leituras únicas, uma vez só (é isso que faltava — antes cada função
     "garantir..." relia a planilha inteira de novo a cada um dos ~70 itens) ---- */
  const formas = readFormasPagamento();
  const formaIfood = formas.find(f => f.nome.toLowerCase().indexOf('ifood') !== -1);
  const categoriasExistentes = readCategorias();
  const produtosExistentes = readProdutos();
  const combosExistentes = readCombos();
  const ingredientesExistentes = readEstoque();
  const adicionaisExistentes = readAdicionais();

  const nomesProdutosExistentes = new Set(produtosExistentes.map(p => p.nome.toLowerCase()));
  const nomesCombosExistentes = new Set(combosExistentes.map(c => c.nome.toLowerCase()));
  const nomesIngredientesExistentes = new Set(ingredientesExistentes.map(e => e.nome.toLowerCase()));
  const nomesAdicionaisExistentes = new Set(adicionaisExistentes.map(a => a.nome.toLowerCase()));
  let proximaOrdemCategoria = categoriasExistentes.length ? Math.max.apply(null, categoriasExistentes.map(c => c.ordem)) + 1 : 1;
  const ordemPorCategoria = {};
  produtosExistentes.concat(combosExistentes).forEach(p => { ordemPorCategoria[p.categoria] = Math.max(ordemPorCategoria[p.categoria] || 0, p.ordemCardapio || 0); });

  // ---- Linhas novas acumuladas em memória (nada é escrito na planilha ainda) ----
  const linhasCategorias = [], linhasProdutos = [], linhasProdutoPrecos = [], linhasProdutoIngredientes = [];
  const linhasCombos = [], linhasComboPrecos = [], linhasComboItens = [], linhasEstoque = [], linhasAdicionais = [];

  function garantirIngredienteBasico(nome) {
    if (nomesIngredientesExistentes.has(nome.toLowerCase())) { resultado.avisos.push('Ingrediente já existia, não duplicado: ' + nome); return; }
    nomesIngredientesExistentes.add(nome.toLowerCase());
    linhasEstoque.push([Utilities.getUuid(), nome, 0, 0, 'un', 0, 'Ativo']);
    resultado.ingredientes = (resultado.ingredientes || 0) + 1;
  }
  function garantirAdicionalBasico(nome) {
    if (nomesAdicionaisExistentes.has(nome.toLowerCase())) { resultado.avisos.push('Adicional já existia, não duplicado: ' + nome); return; }
    nomesAdicionaisExistentes.add(nome.toLowerCase());
    linhasAdicionais.push([Utilities.getUuid(), nome, 0, 'Sim', '', 1]);
    resultado.adicionaisBasicos = (resultado.adicionaisBasicos || 0) + 1;
  }

  const idsCategoriasExistentes = {}; // nome em minúsculo -> id
  categoriasExistentes.forEach(c => { idsCategoriasExistentes[c.nome.toLowerCase()] = c.id; });
  const idsCategoriasNovas = {};

  function garantirCategoria(nome) {
    if (!nome) return '';
    const chave = nome.toLowerCase();
    if (idsCategoriasExistentes[chave]) return idsCategoriasExistentes[chave];
    if (idsCategoriasNovas[chave]) return idsCategoriasNovas[chave];
    const id = Utilities.getUuid();
    idsCategoriasNovas[chave] = id;
    linhasCategorias.push([id, nome, 'Sim', proximaOrdemCategoria++]);
    resultado.categorias++;
    return id;
  }
  function precos(precoLoja, precoIfood) {
    return formas.map(f => ({ formaPagamentoId: f.id, preco: (formaIfood && f.id === formaIfood.id) ? (precoIfood != null ? precoIfood : precoLoja) : precoLoja }));
  }
  function proximaOrdemDoItem(categoriaId) {
    const atual = (ordemPorCategoria[categoriaId] || 0) + 1;
    ordemPorCategoria[categoriaId] = atual;
    return atual;
  }
  function garantirProduto(nome, descricao, nomeCategoria, precoLoja, precoIfood) {
    if (nomesProdutosExistentes.has(nome.toLowerCase())) { resultado.avisos.push('Produto já existia, não duplicado: ' + nome); return null; }
    const categoriaId = garantirCategoria(nomeCategoria);
    const id = Utilities.getUuid();
    linhasProdutos.push([id, nome, descricao || '', categoriaId, 'Sim', '', 'Não', '', proximaOrdemDoItem(categoriaId)]);
    precos(precoLoja, precoIfood).forEach(p => linhasProdutoPrecos.push([Utilities.getUuid(), id, p.formaPagamentoId, p.preco, 0]));
    resultado.produtos++;
    return id;
  }
  function garantirBebida(nome, precoLoja, precoIfood) {
    if (nomesProdutosExistentes.has(nome.toLowerCase())) { resultado.avisos.push('Bebida já existia, não duplicada: ' + nome); return null; }
    const categoriaId = garantirCategoria('Bebidas');
    const idProduto = Utilities.getUuid();
    const idIngrediente = Utilities.getUuid();
    linhasEstoque.push([idIngrediente, nome, 0, 5, 'un', 0, 'Ativo']);
    linhasProdutos.push([idProduto, nome, '', categoriaId, 'Sim', '', 'Não', idIngrediente, proximaOrdemDoItem(categoriaId)]);
    linhasProdutoIngredientes.push([Utilities.getUuid(), idProduto, idIngrediente, nome, 1]);
    precos(precoLoja, precoIfood).forEach(p => linhasProdutoPrecos.push([Utilities.getUuid(), idProduto, p.formaPagamentoId, p.preco, 0]));
    resultado.produtos++;
    return idProduto;
  }
  function garantirCombo(nome, nomeCategoria, precoLoja, precoIfood, itens) {
    if (nomesCombosExistentes.has(nome.toLowerCase())) { resultado.avisos.push('Combo já existia, não duplicado: ' + nome); return; }
    const categoriaId = garantirCategoria(nomeCategoria);
    const id = Utilities.getUuid();
    linhasCombos.push([id, nome, categoriaId, 'Sim', '', 'Não', proximaOrdemDoItem(categoriaId)]);
    precos(precoLoja, precoIfood).forEach(p => linhasComboPrecos.push([Utilities.getUuid(), id, p.formaPagamentoId, p.preco, 0]));
    (itens || []).forEach(it => { if (it.produtoId) linhasComboItens.push([Utilities.getUuid(), id, it.produtoId, it.quantidade || 1]); });
    resultado.combos++;
  }

  // ===== SMASH (iFood) — fotos: aplicadas pelo front pelo NOME (Item 13) =====
  garantirProduto('Smash Catupiry', 'Pão de Brioche, Smash de 80 gr, Catupiry, queijo mussarela, alface', 'Smash', 23.50, 24.90);
  garantirProduto('Smash Cheddar', 'Pão de Brioche, Smash de 80 gr, queijo cheddar e cebola caramelizada', 'Smash', 23.50, 24.90);
  garantirProduto('Smash Tasty', 'Pão de Brioche, Smash de 80 gr, queijo mussarela, alface e tomate', 'Smash', 23.50, 24.90);

  // ===== TEXAS GOURMET =====
  const idBurguerRustic = garantirProduto('Burguer Rustic', '1 Hambúrguer 150gr, Queijo, Bacon, Rúcula, Geleia de Pimenta, Pão com gergelim', 'Texas Gourmet', 38.30, 40.90);
  const idBarbecueMister = garantirProduto('Barbecue Mister', '1 Hambúrguer 150gr, Queijo, Picles, Bacon, Barbecue, Cebola Crispy, Pão com gergelim', 'Texas Gourmet', 39.50, 41.90);
  const idOnionTexas = garantirProduto('Onion Texas', '1 Hambúrguer 150gr, Queijo, Bacon, Anéis de Cebola, Barbecue, Picles', 'Texas Gourmet', 41.70, 44.90);
  const idXTexas = garantirProduto('X Texas', '1 Hambúrguer 200gr linguiça, Queijo, Rúcula, Tomate, Geleia de pimenta', 'Texas Gourmet', 36.00, 38.90);
  const idDuploCheddar = garantirProduto('Duplo Cheddar', 'Dois hambúrgueres 150g, duplo cheddar, bacon, cebola caramelizada, molho da casa', 'Texas Gourmet', 48.40, 51.90);
  const idPiclesCheddar = garantirProduto('Picles Cheddar', '1 Hambúrguer 150gr, Cheddar, Alface, Tomate, Cebola Roxa, Picles', 'Texas Gourmet', 36.00, 38.90);
  const idTexasHoney = garantirProduto('Texas Honey', '1 Hambúrguer 150gr, Cheddar, Bacon, mostarda com mel, Pão Brioche', 'Texas Gourmet', 38.30, 40.90);
  const idCatupiryBacon = garantirProduto('Catupiry Bacon', 'Pão Brioche, 1 Hambúrguer 150gr, Disco Catupiry 100gr, Bacon, Mussarela, Alface, Tomate', 'Texas Gourmet', 45.00, 48.90);
  const idCheddar = garantirProduto('Cheddar', 'Pão Brioche, 1 Hambúrguer 150gr, Cheddar cremoso, Bacon, Cebola Caramelizada', 'Texas Gourmet', 34.00, 35.90);
  garantirProduto('X Picanha', 'Pão Brioche, Hambúrguer 150gr de Picanha, Queijo, Rúcula, Tomate', 'Texas Gourmet', 39.40, 42.00);
  garantirProduto('X Costela', 'Pão com Gergelim, Hambúrguer 150gr de Costela, Queijo, Rúcula, Tomate', 'Texas Gourmet', 38.30, 41.00);

  // ===== LANCHES DE HAMBÚRGUER =====
  garantirProduto('X Salada', 'Pão, hambúrguer 150g, presunto, queijo, tomate, alface', 'Lanches de Hambúrguer', 28.25, 29.90);
  garantirProduto('X Burguer', 'Pão, hambúrguer 150g, presunto, queijo, tomate', 'Lanches de Hambúrguer', 28.25, 29.90);
  garantirProduto('X Bacon', 'Pão, hambúrguer 150g, bacon crocante, presunto, queijo, tomate, alface', 'Lanches de Hambúrguer', 36.00, 38.90);
  garantirProduto('X Egg', 'Pão, hambúrguer 150g, dois ovos fritos, presunto, queijo, tomate, alface', 'Lanches de Hambúrguer', 31.65, 33.90);
  garantirProduto('X Egg Bacon', 'Pão, hambúrguer 150g, dois ovos, bacon crocante, presunto, queijo, tomate, alface', 'Lanches de Hambúrguer', 39.55, 39.90);
  garantirProduto('X Tudo', 'Pão, hambúrguer 150g, bacon, salsicha, ovo, presunto, queijo, tomate, alface', 'Lanches de Hambúrguer', 39.55, 41.90);
  garantirProduto('X Tudo Especial', 'Pão, hambúrguer 150g, bacon, milho, salsicha, ovo, batata palha, catupiry, queijo, presunto, tomate', 'Lanches de Hambúrguer', 45.00, 47.90);

  // ===== LANCHES DE FRANGO =====
  garantirProduto('Frango Egg', 'Pão, 250g frango, ovo, queijo, alface, tomate', 'Lanches de Frango', 32.00, 33.90);
  garantirProduto('Frango Bacon', 'Pão, 250g frango crocante, bacon, queijo derretido, tomate, alface', 'Lanches de Frango', 38.00, 40.90);
  garantirProduto('Frango Catupiry', 'Pão, 250g frango, catupiry cremoso, queijo, alface, tomate', 'Lanches de Frango', 34.00, 35.90);
  garantirProduto('Frango Bacon Catupiry', 'Pão, 250g frango, bacon crocante, catupiry cremoso, queijo, alface, tomate', 'Lanches de Frango', 39.00, 41.90);
  garantirProduto('Frango Cubano', 'Pão, 250g frango, milho, batata palha, catupiry cremoso, queijo, alface, tomate', 'Lanches de Frango', 41.70, 44.90);
  garantirProduto('Frango Salada', 'Pão macio, 250g frango, queijo derretido, tomate fresco, alface crocante', 'Lanches de Frango', 31.00, 32.90);

  // ===== CHURRASCO / CARNE =====
  garantirProduto('Churrasco Tudo', 'Carne suculenta, ingredientes completos', 'Churrasco', 50.85, 53.90);

  // ===== FRITAS TEXAS =====
  const idFritasSimples = garantirProduto('Fritas Simples', 'Batatas em palito, crocantes', 'Fritas Texas', 34.00, 35.90);
  garantirProduto('Fritas 3 Queijos', 'Batata com mussarela, catupiry e cheddar', 'Fritas Texas', 67.80, 71.90);
  garantirProduto('Fritas C C B', 'Batata com cheddar cremoso, catupiry e bacon crocante', 'Fritas Texas', 67.80, 71.90);
  garantirProduto('Fritas Cheddar Bacon', 'Batata com cheddar cremoso e bacon crocante', 'Fritas Texas', 67.80, 71.90);
  garantirProduto('Fritas Especial Texas', 'Batata com carne, frango, catupiry, cheddar, bacon e mussarela', 'Fritas Texas', 90.00, 95.90);
  garantirProduto('Frango a Passarinho', '', 'Fritas Texas', 50.00, 50.00);

  // ===== BATATA RECHEADA (500g) =====
  garantirProduto('Batata Recheada Frango Bacon', 'Frango, bacon crocante, queijo, creme de leite, batata palha — 500g', 'Batata Recheada', 38.30, 41.00);
  garantirProduto('Batata Recheada Frango Cubano', 'Frango, bacon, milho, catupiry, queijo, batata palha — 500g', 'Batata Recheada', 41.70, 45.00);
  garantirProduto('Batata Recheada Churrasco Cubano Contra Filé', 'Carne, bacon, milho, catupiry, queijo, batata palha — 500g', 'Batata Recheada', 50.85, 54.90);
  garantirProduto('Batata Recheada Carne e Queijo Contra Filé', 'Carne suculenta, queijo derretido, batata palha — 500g', 'Batata Recheada', 50.85, 54.90);
  garantirProduto('Batata Recheada Presunto e Queijo', 'Presunto, Catupiry, creme de leite, batata palha — 500g', 'Batata Recheada', 33.00, 35.00);
  garantirProduto('Batata Recheada Brócolis e Bacon', 'Brócolis frescos, bacon defumado, queijo, batata palha — 500g', 'Batata Recheada', 36.00, 38.00);
  garantirProduto('Batata Recheada Frango Bacon e Catupiry', 'Frango, bacon, queijo, catupiry aveludado, creme de leite, palha — 500g', 'Batata Recheada', 41.00, 43.00);

  // ===== KIDS =====
  garantirProduto('Franguinho', 'Mini lanche frango empanado com queijo', 'Kids', 22.60, 23.99);
  garantirProduto('Hamburguinho', 'Mini hambúrguer com queijo derretido', 'Kids', 22.60, 23.99);
  garantirProduto('Doguinho', 'Pão fofinho, salsicha, batata palha, ketchup, maionese', 'Kids', 17.00, 17.99);

  // ===== BEBIDAS (já com estoque próprio vinculado — Item 27 sem burocracia) =====
  const idCocaLata = garantirBebida('Coca Cola Lata 350ml', 6.00, 7.50);
  garantirBebida('Coca Cola Zero Lata 350ml', 6.00, 7.50);
  garantirBebida('Coca Cola 1L', 10.00, 12.00);
  garantirBebida('Coca Cola Zero 1L', 10.00, 12.00);
  garantirBebida('Coca Cola 2L', 16.00, 19.00);
  garantirBebida('Coca Cola Zero 2L', 16.00, 19.00);

  // ===== TEXAS GOURMET COMBO (vem com batata + coca lata) =====
  garantirCombo('Burguer Rustic Combo', 'Texas Gourmet', 49.60, 52.90, [{ produtoId: idBurguerRustic, quantidade: 1 }, { produtoId: idFritasSimples, quantidade: 1 }, { produtoId: idCocaLata, quantidade: 1 }]);
  garantirCombo('Texas Honey Combo', 'Texas Gourmet', 49.60, 52.90, [{ produtoId: idTexasHoney, quantidade: 1 }, { produtoId: idFritasSimples, quantidade: 1 }, { produtoId: idCocaLata, quantidade: 1 }]);
  garantirCombo('Duplo Cheddar Combo', 'Texas Gourmet', 59.80, 63.90, [{ produtoId: idDuploCheddar, quantidade: 1 }, { produtoId: idFritasSimples, quantidade: 1 }, { produtoId: idCocaLata, quantidade: 1 }]);
  garantirCombo('Barbecue Mister Combo', 'Texas Gourmet', 50.00, 53.90, [{ produtoId: idBarbecueMister, quantidade: 1 }, { produtoId: idFritasSimples, quantidade: 1 }, { produtoId: idCocaLata, quantidade: 1 }]);
  garantirCombo('Catupiry Bacon Combo', 'Texas Gourmet', 56.40, 59.90, [{ produtoId: idCatupiryBacon, quantidade: 1 }, { produtoId: idFritasSimples, quantidade: 1 }, { produtoId: idCocaLata, quantidade: 1 }]);
  garantirCombo('Onion Texas Combo', 'Texas Gourmet', 52.00, 56.90, [{ produtoId: idOnionTexas, quantidade: 1 }, { produtoId: idFritasSimples, quantidade: 1 }, { produtoId: idCocaLata, quantidade: 1 }]);
  garantirCombo('Cheddar Combo', 'Texas Gourmet', 45.00, 47.90, [{ produtoId: idCheddar, quantidade: 1 }, { produtoId: idFritasSimples, quantidade: 1 }, { produtoId: idCocaLata, quantidade: 1 }]);
  garantirCombo('X Texas Combo', 'Texas Gourmet', 47.00, 49.90, [{ produtoId: idXTexas, quantidade: 1 }, { produtoId: idFritasSimples, quantidade: 1 }, { produtoId: idCocaLata, quantidade: 1 }]);
  garantirCombo('Picles Cheddar Combo', 'Texas Gourmet', 47.00, 49.90, [{ produtoId: idPiclesCheddar, quantidade: 1 }, { produtoId: idFritasSimples, quantidade: 1 }, { produtoId: idCocaLata, quantidade: 1 }]);

  // ===== COMBOS (a descrição não deixa claro QUAL burguer/fritas específica compõe —
  // cadastrados sem composição pra não vincular o produto errado. Ajuste manual depois. =====
  garantirCombo('Combo Texas', 'Combos', 79.00, 84.99, []);
  garantirCombo('Combo X Bacon', 'Combos', 99.90, 107.99, []);
  garantirCombo('Combo Salada Burguer', 'Combos', 90.00, 95.99, []);
  garantirCombo('Duplo Tudo', 'Combos', 60.00, 71.99, []);
  garantirCombo('Cheddar em Dobro', 'Combos', 90.00, 107.99, []);
  garantirCombo('Dobro Burguer + Churros', 'Combos', 80.00, 95.99, []);

  // ===== HOT DOG GOURMET (iFood) — fotos: aplicadas pelo front pelo NOME (Item 13) =====
  garantirProduto('Nacho Dog Texas', 'Pão de cachorro-quente, salsicha, bacon, muito cheddar e cebola caramelizada', 'Hot Dog Gourmet', 21.50, 22.90);
  garantirProduto('The Master Dog', 'Pão de cachorro-quente, salsicha, bacon, molho especial, picles e cebola', 'Hot Dog Gourmet', 21.50, 22.90);

  // ===== INGREDIENTES BÁSICOS (ITEM 1.3 — só nome, sem preço/estoque real ainda) =====
  ['Pão', 'Pão com gergelim', 'Pão Brioche', 'Hambúrguer 150g', 'Hambúrguer 200g de linguiça', 'Hambúrguer 150g de Picanha', 'Hambúrguer 150g de Costela',
   'Frango', 'Frango crocante', 'Carne Contra Filé', 'Bacon', 'Presunto', 'Salsicha', 'Ovo', 'Queijo Mussarela', 'Cheddar cremoso', 'Catupiry', 'Creme de leite',
   'Rúcula', 'Alface', 'Tomate', 'Anel de Cebola', 'Cebola Caramelizada', 'Cebola Roxa', 'Picles', 'Milho', 'Brócolis', 'Batata palha', 'Batata frita',
   'Geleia de Pimenta', 'Molho Barbecue', 'Mostarda com mel', 'Molho da casa', 'Ketchup', 'Maionese',
   'Hambúrguer Smash 80g', 'Pão de cachorro-quente'].forEach(garantirIngredienteBasico);

  // ===== ADICIONAIS GENÉRICOS (ITEM 1.3 — só nome/preço 0, sem vínculo de estoque ainda) =====
  ['Hambúrguer extra (150g)', 'Bacon extra', 'Ovo extra', 'Frango extra', 'Costela extra',
   'Queijo extra (mussarela)', 'Cheddar extra', 'Catupiry extra', 'Cream cheese',
   'Maionese temperada', 'Maionese verde', 'Molho rosê', 'Molho picante/pimenta', 'Molho ranch',
   'Tomate seco', 'Pepino', 'Jalapeño', 'Cebola frita crocante',
   'Porção extra de batata frita', 'Batata rústica', 'Onion rings extra'].forEach(garantirAdicionalBasico);

  /* ---- Gravação em lote — uma chamada de escrita por aba, não uma por item ----
     Isso é o que evita estourar a cota do Apps Script numa importação grande. */
  function gravarLote(nomeAba, linhas, numColunas) {
    if (!linhas.length) return;
    const sh = ss.getSheetByName(nomeAba);
    const proximaLinha = sh.getLastRow() + 1;
    sh.getRange(proximaLinha, 1, linhas.length, numColunas).setValues(linhas);
  }
  gravarLote('Categorias', linhasCategorias, 4);
  gravarLote('Estoque', linhasEstoque, 7);
  gravarLote('Produtos', linhasProdutos, 9);
  gravarLote('ProdutoPrecos', linhasProdutoPrecos, 5);
  gravarLote('ProdutoIngredientes', linhasProdutoIngredientes, 5);
  gravarLote('Combos', linhasCombos, 7);
  gravarLote('ComboPrecos', linhasComboPrecos, 5);
  gravarLote('ComboItens', linhasComboItens, 4);
  gravarLote('Adicionais', linhasAdicionais, 6);

  registrarLog('Importação inicial de cardápio executada', '', resultado.categorias + ' categorias, ' + resultado.produtos + ' produtos, ' + resultado.combos + ' combos, ' + (resultado.ingredientes||0) + ' ingredientes, ' + (resultado.adicionaisBasicos||0) + ' adicionais.');
  return { ok: true, message: resultado.categorias + ' categorias, ' + resultado.produtos + ' produtos, ' + resultado.combos + ' combos, ' + (resultado.ingredientes||0) + ' ingredientes e ' + (resultado.adicionaisBasicos||0) + ' adicionais cadastrados.', detalhes: resultado };
}
function excluirCombo(id) {
  const sh = ss_().getSheetByName('Combos'); const last = sh.getLastRow();
  for (let i = last; i >= 2; i--) {
    if (sh.getRange(i, 1).getValue() === id) {
      const fotoId = sh.getRange(i, 5).getValue();
      if (fotoId) { try { DriveApp.getFileById(fotoId).setTrashed(true); } catch (e) {} }
      sh.deleteRow(i); break;
    }
  }
  const shCP = ss_().getSheetByName('ComboPrecos'); const lastCP = shCP.getLastRow();
  for (let i = lastCP; i >= 2; i--) { if (shCP.getRange(i, 2).getValue() === id) shCP.deleteRow(i); }
  const shCIt = ss_().getSheetByName('ComboItens'); const lastCIt = shCIt.getLastRow();
  for (let i = lastCIt; i >= 2; i--) { if (shCIt.getRange(i, 2).getValue() === id) shCIt.deleteRow(i); }
  registrarLog('Combo excluído', '', id);
  return { ok: true, combos: readCombos(), comboPrecos: readComboPrecos(), comboItens: readComboItens() };
}

/* ---------- ABERTURA / FECHAMENTO DE CAIXA ---------- */
function readSessaoAberta() {
  const sh = ss_().getSheetByName('Caixa'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 8).getValue() === 'Aberto') {
      const row = sh.getRange(i, 1, 1, 9).getValues()[0];
      return { id: row[0], abertura: Utilities.formatDate(new Date(row[1]), FUSO, 'dd/MM/yyyy HH:mm'), aberturaTimestamp: new Date(row[1]).getTime(), fundoCaixa: numPlanilha_(row[2]), status: row[7], usuarioAbertura: row[8] };
    }
  }
  return null;
}
/* ---------- FASE 8C — CONFERÊNCIA DE CAIXA (ITEM 82) ----------
   Caixa ganha: Valor Contado (K) e Diferença (L = contado − esperado). Dinheiro físico = pagamentos das
   formas marcadas "permite troco". Fechar exige informar o valor contado; caixa já fechado não fecha de novo. */
function formasDinheiroNomes_() {
  const nomes = readFormasPagamento().filter(f => f.permiteTroco).map(f => f.nome);
  return nomes.length ? nomes : ['Dinheiro'];
}
function prepararFase8Caixa() {
  const sh = ss_().getSheetByName('Caixa');
  if (sh.getMaxColumns() < 12) sh.insertColumnsAfter(sh.getMaxColumns(), 12 - sh.getMaxColumns());
  if (!String(sh.getRange(1, 11).getValue())) {
    sh.getRange(1, 11, 1, 2).setValues([['Valor Contado', 'Diferença']]);
    sh.getRange(1, 11, 1, 2).setBackground(COR_ESCURO).setFontColor(COR_DOURADO).setFontWeight('bold');
    sh.getRange('K2:L2000').setNumberFormat('R$ #,##0.00');
    sh.setColumnWidth(11, 120); sh.setColumnWidth(12, 110);
  }
  return { ok: true, message: 'Estrutura da Fase 8C pronta.' };
}
/* Roda as três preparações de uma vez (todas seguras para repetir). */
function readSessoesCaixa() {
  const sh = ss_().getSheetByName('Caixa'); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, Math.min(14, sh.getMaxColumns())).getValues().filter(r => r[0]).map(r => ({
    id: r[0], abertura: Utilities.formatDate(new Date(r[1]), FUSO, 'dd/MM/yyyy HH:mm'), aberturaTimestamp: new Date(r[1]).getTime(),
    fundoCaixa: numPlanilha_(r[2]), fechamento: r[3] ? Utilities.formatDate(new Date(r[3]), FUSO, 'dd/MM/yyyy HH:mm') : '', fechamentoTimestamp: r[3] ? new Date(r[3]).getTime() : null,
    totalVendas: numPlanilha_(r[4]), totalDespesas: numPlanilha_(r[5]), saldoFinal: numPlanilha_(r[6]), status: r[7], usuarioAbertura: r[8], usuarioFechamento: r[9],
    valorContado: r[10] === '' || r[10] === undefined ? null : numPlanilha_(r[10]), diferenca: r[11] === '' || r[11] === undefined ? null : numPlanilha_(r[11]),
    reconciliadasQtd: Number(r[12]) || 0, reconciliadoDinheiro: numPlanilha_(r[13]) || 0 // BLOCO 1.1: vendas da contingência reconciliadas depois do fechamento
  })).reverse();
}
/* ---------- BLOCO 1.1 — VENDA DE CONTINGÊNCIA COM A HORA ORIGINAL ----------
   A venda feita durante a queda entra na planilha com a data/hora em que o operador tentou finalizar (e não a da reconciliação).
   Vendas!AG guarda quando ela foi realmente gravada (marca de "veio da contingência"). Caixa!M/N acumulam o que foi reconciliado
   DEPOIS de a sessão fechar (quantidade e dinheiro), para o saldo esperado e a diferença da sessão continuarem batendo. */
const COL_VENDA_REGISTRADA_EM_ = 33, COL_CAIXA_RECONC_QTD_ = 13, COL_CAIXA_RECONC_DIN_ = 14;
function prepararContingenciaTimestamp_() {
  const shV = ss_().getSheetByName('Vendas');
  const temV = shV.getMaxColumns() >= COL_VENDA_REGISTRADA_EM_ && String(shV.getRange(1, COL_VENDA_REGISTRADA_EM_).getValue());
  if (!temV) {
    garantirColuna_(shV, COL_VENDA_REGISTRADA_EM_, 'Registrada em (contingência)', 170);
    shV.getRange(2, COL_VENDA_REGISTRADA_EM_, 7999, 1).setNumberFormat('dd/MM/yyyy HH:mm');
  }
  const shC = ss_().getSheetByName('Caixa');
  const temC = shC.getMaxColumns() >= COL_CAIXA_RECONC_DIN_ && String(shC.getRange(1, COL_CAIXA_RECONC_DIN_).getValue());
  if (!temC) {
    garantirColuna_(shC, COL_CAIXA_RECONC_QTD_, 'Reconciliadas após fechar (qtd)', 160);
    garantirColuna_(shC, COL_CAIXA_RECONC_DIN_, 'Reconciliado em dinheiro (R$)', 170);
    shC.getRange(2, COL_CAIXA_RECONC_DIN_, 1999, 1).setNumberFormat('R$ #,##0.00');
  }
  return { ok: true, message: 'Estrutura da contingência (hora original) pronta.' };
}
/* id da venda -> momento em que foi gravada de verdade, só para as que vieram da contingência com hora original. */
function readVendasContingenciaIds_() {
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  const mapa = {};
  if (last < 2 || sh.getMaxColumns() < COL_VENDA_REGISTRADA_EM_) return mapa;
  const ids = sh.getRange(2, 1, last - 1, 1).getValues();
  const regs = sh.getRange(2, COL_VENDA_REGISTRADA_EM_, last - 1, 1).getValues();
  for (let k = 0; k < ids.length; k++) if (ids[k][0] && regs[k][0]) mapa[ids[k][0]] = new Date(regs[k][0]).getTime();
  return mapa;
}
/* Quantas vendas ainda esperam na fila da contingência (null = não deu para saber; nunca bloqueia o fechamento). */
function contarPendentesContingencia_() {
  try {
    const r = chamarContingencia_('listarPendentes');
    return (r && r.ok) ? (r.pendentes || []).length : null;
  } catch (e) { return null; }
}
/* Dinheiro que entrou na gaveta nessa venda (venda "A Receber" ainda não entrou). */
function dinheiroDaVendaContingencia_(d) {
  if (d.statusPagamento === 'A Receber') return 0;
  const nomes = formasDinheiroNomes_().map(n => String(n).toLowerCase());
  return Math.round((d.pagamentos || []).filter(p => p && nomes.indexOf(String(p.forma).toLowerCase()) !== -1).reduce((t, p) => t + (Number(p.valor) || 0), 0) * 100) / 100;
}
/* Venda reconciliada cuja hora original cai numa sessão JÁ FECHADA: o dinheiro estava na gaveta na hora da contagem, mas o saldo esperado
   gravado não o conhecia (daria "sobra"). Soma a venda ao total e ao saldo da sessão e recalcula a diferença contra o valor contado. */
function ajustarSessaoFechadaPorReconciliacao_(tsOriginal, valorTotal, dinheiro) {
  const sh = ss_().getSheetByName('Caixa'); const last = sh.getLastRow();
  if (last < 2) return null;
  prepararContingenciaTimestamp_();
  const linhas = sh.getRange(2, 1, last - 1, COL_CAIXA_RECONC_DIN_).getValues();
  for (let k = 0; k < linhas.length; k++) {
    const r = linhas[k];
    if (!r[0] || r[7] !== 'Fechado' || !r[3]) continue;
    const ab = new Date(r[1]).getTime(), fe = new Date(r[3]).getTime();
    if (tsOriginal < ab || tsOriginal > fe) continue;
    const i = k + 2;
    const saldo = Math.round((numPlanilha_(r[6]) + dinheiro) * 100) / 100;
    sh.getRange(i, 5).setValue(Math.round((numPlanilha_(r[4]) + valorTotal) * 100) / 100);
    sh.getRange(i, 7).setValue(saldo);
    if (r[10] !== '' && r[10] !== undefined && r[10] !== null) sh.getRange(i, 12).setValue(Math.round((numPlanilha_(r[10]) - saldo) * 100) / 100);
    sh.getRange(i, COL_CAIXA_RECONC_QTD_).setValue((Number(r[12]) || 0) + 1);
    sh.getRange(i, COL_CAIXA_RECONC_DIN_).setValue(Math.round(((numPlanilha_(r[13]) || 0) + dinheiro) * 100) / 100);
    registrarLog('Venda reconciliada após o fechamento do caixa', '', 'Sessão ' + String(r[0]).slice(0, 8) + ' | venda R$ ' + valorTotal.toFixed(2) + ' (dinheiro R$ ' + dinheiro.toFixed(2) + ') somada ao saldo da sessão; diferença recalculada');
    return { sessaoId: r[0], saldo: saldo };
  }
  return null;
}
function abrirCaixa(fundoCaixa, usuario) {
  if (readSessaoAberta()) return { ok: false, message: 'Já existe um caixa aberto. Feche-o antes de abrir outro.' };
  const sh = ss_().getSheetByName('Caixa');
  const id = Utilities.getUuid();
  sh.appendRow([id, new Date(), Number(fundoCaixa) || 0, '', 0, 0, 0, 'Aberto', usuario || '', '']);
  registrarLog('Caixa aberto', '', 'Fundo de caixa: R$ ' + (Number(fundoCaixa) || 0).toFixed(2));
  return { ok: true, message: 'Caixa aberto.', sessaoCaixa: readSessaoAberta() };
}
/* Fechamento do caixa — trava: não fecha com mesa aberta, pedido pendente ou pedido não recebido. */
const STATUS_PEDIDO_FINAIS_ = ['Entregue', 'Retirada', 'Servida'];
function pendenciasFechamentoCaixa_(vendasTodas) {
  const vendas = (vendasTodas || readVendas()).filter(v => v.status === 'Confirmada');
  const rot = v => '#' + (v.numero || String(v.id).slice(-4)) + (v.clienteNome ? ' ' + String(v.clienteNome).split(/\s+/)[0] : '');
  const mesas = readMesas().filter(m => ['Ocupada', 'Aguardando fechamento'].indexOf(m.status) !== -1).map(m => 'Mesa ' + m.numero);
  const pendentes = vendas.filter(v => v.statusPedido && STATUS_PEDIDO_FINAIS_.indexOf(v.statusPedido) === -1).map(v => rot(v) + ' (' + v.statusPedido + ')');
  const naoRecebidos = vendas.filter(v => v.statusPagamento === 'A Receber').map(v => rot(v));
  if (!mesas.length && !pendentes.length && !naoRecebidos.length) return null;
  const lista = (a) => a.slice(0, 6).join(', ') + (a.length > 6 ? ' e mais ' + (a.length - 6) : '');
  const partes = [];
  if (mesas.length) partes.push('Mesas abertas: ' + lista(mesas));
  if (pendentes.length) partes.push('Pedidos pendentes: ' + lista(pendentes));
  if (naoRecebidos.length) partes.push('Pedidos não recebidos: ' + lista(naoRecebidos));
  return { ok: false, pendencias: true, mesas: mesas, pedidos: pendentes, naoRecebidos: naoRecebidos,
    message: 'O caixa não pode ser fechado enquanto houver pendências. ' + partes.join(' | ') + '. Resolva (finalize, receba ou cancele) e tente de novo.' };
}
/* Ao fechar o caixa, fecha também as entregas concluídas e ainda abertas dos entregadores do dia (data da abertura e do fechamento).
   Considera o valor devido como pago, com observação automática; é idempotente (requisição determinística por caixa/entregador/dia). */
function fecharEntregasAutomatico_(caixaId, abertura, fechamento) {
  const datas = {}; datas[Utilities.formatDate(new Date(abertura), FUSO, 'yyyy-MM-dd')] = 1; datas[Utilities.formatDate(fechamento, FUSO, 'yyyy-MM-dd')] = 1;
  const pares = {};
  readVendas().forEach(v => {
    if (v.status !== 'Confirmada' || v.tipoEntrega !== 'Entrega' || v.statusPedido !== 'Entregue' || v.fechamentoEntregaId || !v.entregador || !v.timestampConcluida) return;
    const d = Utilities.formatDate(new Date(v.timestampConcluida), FUSO, 'yyyy-MM-dd');
    if (datas[d]) pares[String(v.entregador).toLowerCase() + '|' + d] = { login: v.entregador, data: d };
  });
  const feitos = [], falhas = [];
  Object.keys(pares).forEach(k => {
    const p = pares[k];
    try {
      const c = calcularFechamentoEntrega_(p.login, p.data);
      const r = fecharPeriodoEntregador(p.login, p.data, c.totalDevido, 'Fechamento automático ao fechar o caixa', 'auto-' + caixaId + '-' + String(p.login).toLowerCase() + '-' + p.data, true);
      if (r.ok) feitos.push(p.login + ' (' + p.data + '): R$ ' + c.totalDevido.toFixed(2)); else falhas.push(p.login + ' (' + p.data + '): ' + r.message);
    } catch (e) { falhas.push(p.login + ' (' + p.data + '): ' + e.message); }
  });
  if (falhas.length) registrarLog('Falha no fechamento automático de entregas', '', falhas.join(' | '));
  return { feitos: feitos, falhas: falhas };
}

function fecharCaixa(id, usuario, valorContado) {
  if (valorContado === undefined || valorContado === null || valorContado === '' || isNaN(Number(valorContado)) || Number(valorContado) < 0) return { ok: false, message: 'Informe quanto dinheiro há na gaveta (pode ser zero).' };
  const contado = Math.round(Number(valorContado) * 100) / 100;
  const sh = ss_().getSheetByName('Caixa'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      if (sh.getRange(i, 8).getValue() === 'Fechado') return { ok: false, message: 'Este caixa já foi fechado.' };
      const bloqueio = pendenciasFechamentoCaixa_(); if (bloqueio) return bloqueio; // trava: mesas abertas, pedidos pendentes ou não recebidos
      const abertura = new Date(sh.getRange(i, 2).getValue()).getTime();
      const fundoCaixa = numPlanilha_(sh.getRange(i, 3).getValue()) || 0;
      const fechamento = new Date();

      const vendasSessao = readVendas().filter(v => v.status === 'Confirmada' && v.timestamp >= abertura && v.timestamp <= fechamento.getTime());
      const despesasSessao = readDespesas().filter(d => d.status === 'Confirmada' && d.situacao === 'Paga' && d.saiuDoCaixa && d.timestamp >= abertura && d.timestamp <= fechamento.getTime());
      const sangriasSessao = readSangrias().filter(s => s.timestamp >= abertura && s.timestamp <= fechamento.getTime());
      /* CORREÇÃO (Módulo 2): o dinheiro conta na sessão em que ENTROU (data do recebimento), não na sessão em que o pedido foi
         criado. Antes, entrega/mesa paga depois do fechamento não entrava em nenhum caixa e a gaveta nunca batia. */
      const fechamentoMs = fechamento.getTime();
      const vendasPagasSessao = readVendas().filter(v => v.status === 'Confirmada' && v.statusPagamento !== 'A Receber'
        && (v.timestampRecebimento || v.timestamp) >= abertura && (v.timestampRecebimento || v.timestamp) <= fechamentoMs);
      const idsVendasPagasSessao = new Set(vendasPagasSessao.map(v => v.id));
      const pagamentosSessao = readPagamentosVenda().filter(p => idsVendasPagasSessao.has(p.vendaId));

      const totalVendas = vendasSessao.reduce((s, v) => s + Number(v.valorTotal), 0);
      const totalPendente = vendasSessao.filter(v => v.statusPagamento === 'A Receber').reduce((s, v) => s + Number(v.valorTotal), 0);
      const porForma = {};
      pagamentosSessao.forEach(p => { porForma[p.forma] = (porForma[p.forma] || 0) + Number(p.valor); });
      const totalVendasDinheiro = formasDinheiroNomes_().reduce((s, n) => s + (porForma[n] || 0), 0);
      const totalDespesas = despesasSessao.reduce((s, d) => s + Number(d.valor), 0);
      const totalSangrias = sangriasSessao.reduce((s, sg) => s + Number(sg.valor), 0);
      const saldoFinal = fundoCaixa + totalVendasDinheiro - totalDespesas - totalSangrias;

      sh.getRange(i, 4).setValue(fechamento);
      sh.getRange(i, 5).setValue(totalVendas);
      sh.getRange(i, 6).setValue(totalDespesas);
      sh.getRange(i, 7).setValue(saldoFinal);
      sh.getRange(i, 8).setValue('Fechado');
      sh.getRange(i, 10).setValue(usuario || '');
      const diferenca = Math.round((contado - saldoFinal) * 100) / 100;
      sh.getRange(i, 11, 1, 2).setValues([[contado, diferenca]]);
      registrarLog('Caixa fechado', '', 'Esperado: R$ ' + saldoFinal.toFixed(2) + ' | Contado: R$ ' + contado.toFixed(2) + ' | Diferença: R$ ' + diferenca.toFixed(2));
      if (Math.abs(diferenca) >= 0.01) registrarLog('Diferença de caixa', '', (diferenca > 0 ? 'SOBRA' : 'FALTA') + ' de R$ ' + Math.abs(diferenca).toFixed(2) + ' no fechamento');
      /* BLOCO 1.1: vendas vindas da contingência já incluídas nesta sessão + aviso (sem bloquear) do que ainda espera na fila. */
      const idsCont = readVendasContingenciaIds_();
      const vendasContSessao = vendasSessao.filter(v => idsCont[v.id]);
      const reconciliadasNaSessao = { quantidade: vendasContSessao.length, valor: Math.round(vendasContSessao.reduce((t, v) => t + Number(v.valorTotal), 0) * 100) / 100 };
      const pendentesContingencia = contarPendentesContingencia_();
      if (pendentesContingencia > 0) registrarLog('Caixa fechado com vendas pendentes na contingência', '', pendentesContingencia + ' venda(s) ainda na fila; entram nesta sessão (com a hora original) quando forem reconciliadas');
      const entregasAuto = fecharEntregasAutomatico_(id, abertura, fechamento);

      return {
        ok: true,
        entregasAuto: entregasAuto,
        vendas: entregasAuto.feitos.length ? readVendasResposta_() : undefined,
        fechamentosEntrega: entregasAuto.feitos.length ? readFechamentosEntrega() : undefined,
        entregasFechadas: entregasAuto.feitos.length ? readEntregasFechadas() : undefined,
        relatorio: {
          abertura: Utilities.formatDate(new Date(abertura), FUSO, 'dd/MM/yyyy HH:mm'), fechamento: Utilities.formatDate(fechamento, FUSO, 'dd/MM/yyyy HH:mm'),
          fundoCaixa: fundoCaixa, totalVendas: totalVendas, totalVendasDinheiro: totalVendasDinheiro, porForma: porForma,
          totalPendente: totalPendente, totalDespesas: totalDespesas, totalSangrias: totalSangrias, saldoFinal: saldoFinal, valorContado: contado, diferenca: diferenca,
          quantidadeVendas: vendasSessao.length, quantidadeDespesas: despesasSessao.length, quantidadeSangrias: sangriasSessao.length,
          reconciliadasNaSessao: reconciliadasNaSessao, pendentesContingencia: pendentesContingencia
        }
      };
    }
  }
  return { ok: false, message: 'Sessão de caixa não encontrada.' };
}

/* ---------- VENDAS (PEDIDOS COM CARRINHO + PAGAMENTO DIVIDIDO) ---------- */

/* FASE 9 — o backend não confia em preço/quantidade vindos do navegador.
   Para Operador/Garçom (e qualquer pedido de origem Cardápio/contingência) o preço unitário
   precisa bater com um preço cadastrado do produto/combo + adicionais. Admin pode lançar livre no Caixa.
   Para desligar (só se o Caixa usar preços fora do cadastro): propriedade do script VALIDAR_PRECO_VENDA = 'Nao'. */
function validarItensVenda_(itens, origem) {
  const desligado = PropertiesService.getScriptProperties().getProperty('VALIDAR_PRECO_VENDA') === 'Nao';
  const exigePreco = !desligado && !(NIVEL_ATUAL === 'Admin' && origem !== 'Cardápio' && String(origem).indexOf('Contingência') !== 0); // contingência: SEMPRE confere o preço, mesmo com Admin reconciliando
  const pp = exigePreco ? readProdutoPrecos() : [];
  const cp = exigePreco ? readComboPrecos() : [];
  const ads = exigePreco ? readAdicionais() : [];
  for (let k = 0; k < itens.length; k++) {
    const it = itens[k]; const nome = it.descricao || 'item';
    const qtd = Number(it.quantidade);
    if (!(qtd > 0) || qtd > 200 || Math.floor(qtd) !== qtd) return 'Quantidade inválida em "' + nome + '".';
    const v = Number(it.valorUnitario);
    if (!(v >= 0)) return 'Preço inválido em "' + nome + '".';
    if (Number(it.custoUnitario || 0) < 0) return 'Custo inválido em "' + nome + '".';
    if (!exigePreco) continue;
    if ((!it.produtoId && !it.comboId) || (it.produtoId && it.comboId)) return '"' + nome + '" não é um item cadastrado de forma válida.';
    const idsAdicionais = Array.isArray(it.adicionaisIds) ? it.adicionaisIds : [];
    for (const adId of idsAdicionais) {
      const ad = ads.find(x => x.id === adId && x.ativo);
      if (!ad) return 'O adicional selecionado para "' + nome + '" não está disponível.';
    }
    const extra = idsAdicionais.reduce((t, id) => { const a = ads.find(x => x.id === id && x.ativo); return t + Number(a.preco); }, 0);
    const lista = it.produtoId ? pp.filter(x => x.produtoId === it.produtoId) : cp.filter(x => x.comboId === it.comboId);
    if (!lista.some(x => Math.abs(Number(x.preco) + extra - v) <= 0.011)) {
      registrarLog('Preço divergente bloqueado', '', nome + ' enviado a R$ ' + v.toFixed(2));
      return 'O preço de "' + nome + '" não confere com o cadastro.';
    }
  }
  return '';
}

function validarPagamentosVenda_(pagamentos, tipoEntrega, nivel) {
  if (!Array.isArray(pagamentos) || !pagamentos.length) return 'Informe ao menos uma forma de pagamento.';
  const formas = readFormasPagamento();
  for (const p of pagamentos) {
    const valor = Number(p && p.valor);
    const forma = String(p && p.forma || '').trim();
    if (!forma) return 'Forma de pagamento não informada.';
    if (!Number.isFinite(valor) || valor <= 0) return 'Cada pagamento deve ter um valor maior que zero.';
    if (forma === 'A Receber (Mesa)') {
      if (['Admin', 'Operador', 'Garçom'].indexOf(nivel) === -1 || tipoEntrega !== 'Mesa') return 'Forma de pagamento inválida para esta operação.';
      continue;
    }
    const fp = formas.find(f => String(f.nome).toLowerCase() === forma.toLowerCase());
    if (!fp) return 'Forma de pagamento não cadastrada: ' + forma;
    if (!fp.ativa) return 'A forma de pagamento está inativa: ' + forma;
  }
  return '';
}

function iniciarVenda(itens, clienteNome, clienteTelefone, pagamentos, tipoEntrega, dadosEntrega, statusPagamento, desconto, senhaAdminConfirmacao, origem, mesaId, requisicaoId, promocaoValidada, opcoes) {
  if (!itens || !itens.length) return { ok: false, message: 'Adicione ao menos um item à venda.' };
  if (!pagamentos || !pagamentos.length) return { ok: false, message: 'Informe ao menos uma forma de pagamento.' };
  if (tipoEntrega === 'Mesa' && !mesaId) return { ok: false, message: 'Informe a mesa.' };
  /* ETAPA 4: o garçom só lança pedido de MESA, sem desconto e sem receber pagamento (fica "A Receber" até o caixa fechar a conta).
     Vale no servidor, não só na tela. */
  if (NIVEL_ATUAL === 'Garçom') {
    if (['Mesa', 'Entrega', 'Retirada'].indexOf(tipoEntrega) === -1) return { ok: false, message: 'O garçom só lança pedidos de mesa, entrega ou retirada.' };
    if (!readSessaoAberta()) return { ok: false, message: 'O caixa está fechado — peça ao caixa para abrir.' };
    if (tipoEntrega !== 'Mesa' && !String(clienteTelefone || '').trim()) return { ok: false, message: 'Informe o cliente (nome e telefone) para pedidos por telefone.' };
    const mesaG = tipoEntrega === 'Mesa' ? readMesas().find(m => m.id === mesaId) : { status: 'Livre', numero: '', garcomResponsavel: '' };
    if (!mesaG) return { ok: false, message: 'Mesa não encontrada.' };
    if (['Livre', 'Ocupada'].indexOf(mesaG.status) === -1) return { ok: false, message: 'A mesa ' + mesaG.numero + ' está "' + mesaG.status + '" — não aceita novos itens.' };
    if (mesaG.status === 'Ocupada' && mesaG.garcomResponsavel && String(mesaG.garcomResponsavel).toLowerCase() !== String(USUARIO_ATUAL).toLowerCase()) return { ok: false, message: 'Esta mesa está sob responsabilidade de outro garçom.' };
    if (mesaG.status === 'Ocupada' && !mesaG.garcomResponsavel) {
      const shMesas = ss_().getSheetByName('Mesas'); const lastMesas = shMesas.getLastRow();
      for (let im = 2; im <= lastMesas; im++) if (shMesas.getRange(im, 1).getValue() === mesaId) { shMesas.getRange(im, 6).setValue(USUARIO_ATUAL || ''); break; }
    }
    origem = 'Garçom'; desconto = null; statusPagamento = 'A Receber';
    if (tipoEntrega === 'Mesa') pagamentos = [{ forma: 'A Receber (Mesa)', valor: (pagamentos && pagamentos[0] && Number(pagamentos[0].valor)) || 0 }];
    else pagamentos = [{ forma: String(pagamentos && pagamentos[0] && pagamentos[0].forma || '').trim(), valor: (pagamentos && pagamentos[0] && Number(pagamentos[0].valor)) || 0 }]; // entrega/retirada: forma que o cliente vai usar; o valor é refeito com a taxa abaixo
  }
  // FASE 9 — idempotência: a mesma requisição (duplo toque, retry) nunca gera duas vendas.
  const chaveReq = requisicaoId ? 'venda:' + String(requisicaoId).slice(0, 80) : '';
  if (chaveReq) {
    const previa = requisicaoBuscar_(chaveReq);
    const jaId = previa ? previa.resultado : '';
    if (jaId) return { ok: true, duplicado: true, id: jaId, message: 'Venda já registrada — requisição repetida ignorada.', vendas: readVendasResposta_(), itensVenda: readItensVendaResposta_(), pagamentosVenda: readPagamentosVendaResposta_(), fidelidade: readFidelidadeResposta_(), clientes: readClientesResposta_(), estoque: readEstoqueResposta_() }
  }
  const erroItens = validarItensVenda_(itens, origem);
  if (erroItens) return { ok: false, message: erroItens };
  const erroEstoque = verificarEstoqueVenda_(itens, origem);
  if (erroEstoque) return { ok: false, message: erroEstoque };

  const shVendas = ss_().getSheetByName('Vendas');
  const shItens = ss_().getSheetByName('ItensVenda');
  const shPagamentos = ss_().getSheetByName('PagamentosVenda');
  const vendaId = Utilities.getUuid();
  /* BLOCO 1.1: só a reconciliação da contingência (origem "Contingência ...") pode fixar a hora da venda; qualquer outro caminho usa o relógio do servidor.
     A hora precisa ser um instante real: não pode estar no futuro nem ter mais de 7 dias. */
  let dataVenda = new Date(), origemContingenciaTs = false;
  if (opcoes && opcoes.timestampOriginal !== undefined && opcoes.timestampOriginal !== null && String(origem).indexOf('Contingência') === 0) {
    const tsO = Number(opcoes.timestampOriginal), agoraMs = Date.now();
    if (Number.isFinite(tsO) && tsO <= agoraMs + 60000 && tsO >= agoraMs - 7 * 24 * 3600000) { dataVenda = new Date(Math.min(tsO, agoraMs)); origemContingenciaTs = true; }
  }

  let valorOriginal = 0, custoTotal = 0;
  const linhasItens = []; // só gravadas depois de todas as validações (evita linhas órfãs em ItensVenda)
  itens.forEach(it => {
    const qtd = Number(it.quantidade) || 1;
    const vUnit = Number(it.valorUnitario) || 0;
    const cUnit = Number(it.custoUnitario) || 0;
    const totalItem = Math.round(qtd * vUnit * 100) / 100;
    valorOriginal += totalItem;
    custoTotal += qtd * cUnit;
    linhasItens.push([Utilities.getUuid(), vendaId, it.produtoId || '', it.comboId || '', it.descricao, qtd, vUnit, cUnit, totalItem, JSON.stringify(it.adicionaisIds || [])]);
  });
  valorOriginal = Math.round(valorOriginal * 100) / 100;
  custoTotal = Math.round(custoTotal * 100) / 100;

  let valorDesconto = 0, descontoDetalhe = '';
  if (promocaoValidada && promocaoValidada.ok) {
    const vPromo = Number(promocaoValidada.desconto) || 0;
    if (vPromo <= 0 || vPromo >= valorOriginal) return { ok: false, message: 'Cupom não pode zerar o pedido.' };
    valorDesconto = Math.round(vPromo * 100) / 100;
    descontoDetalhe = 'Cupom ' + String(promocaoValidada.codigo || '') + ' (R$ ' + valorDesconto.toFixed(2) + ')';
  } else if (desconto && desconto.valor !== undefined && desconto.valor !== null) {
    const valorSolicitado = Number(desconto.valor);
    if (!Number.isFinite(valorSolicitado) || valorSolicitado <= 0) return { ok: false, message: 'Valor de desconto inválido.' };
    if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta — desconto não aplicado.' };
    if (desconto.tipo === 'percentual') {
      if (valorSolicitado > 100) return { ok: false, message: 'O desconto percentual não pode ser maior que 100%.' };
      valorDesconto = Math.round(valorOriginal * (valorSolicitado / 100) * 100) / 100;
      descontoDetalhe = valorSolicitado + '% (R$ ' + valorDesconto.toFixed(2) + ')';
    } else if (desconto.tipo === 'fixo' || !desconto.tipo) {
      if (valorSolicitado > valorOriginal) return { ok: false, message: 'O desconto fixo não pode ser maior que o valor da venda.' };
      valorDesconto = Math.round(valorSolicitado * 100) / 100;
      descontoDetalhe = 'R$ ' + valorDesconto.toFixed(2) + ' fixo';
    } else {
      return { ok: false, message: 'Tipo de desconto inválido.' };
    }
    if (!Number.isFinite(valorDesconto) || valorDesconto <= 0 || valorDesconto >= valorOriginal) return { ok: false, message: 'O desconto não pode deixar a venda com valor zero ou negativo.' };
  }
  const tipo = tipoEntrega === 'Entrega' ? 'Entrega' : (tipoEntrega === 'Mesa' ? 'Mesa' : 'Retirada');
  const de = dadosEntrega || {};
  const taxaEntrega = tipo === 'Entrega' && !de.freteGratis ? calcularTaxaEntrega_(de) : 0;
  const valorTotal = Math.round((valorOriginal - valorDesconto + taxaEntrega) * 100) / 100;
  if(valorTotal < 0.01) return { ok:false, message:'O total da venda precisa ser maior que zero.' };
  if (NIVEL_ATUAL === 'Garçom' && tipoEntrega !== 'Mesa') pagamentos = [{ forma: pagamentos[0].forma, valor: valorTotal }];

  // "A Receber (Mesa)" só existe como pedido a receber, com um único pagamento do valor total.
  if ((pagamentos || []).some(p => p && p.forma === 'A Receber (Mesa)')) {
    if (pagamentos.length !== 1) return { ok: false, message: 'Forma de pagamento inválida para esta operação.' };
    statusPagamento = 'A Receber';
  }
  const erroPagamentos = validarPagamentosVenda_(pagamentos, tipoEntrega, NIVEL_ATUAL);
  if (erroPagamentos) return { ok: false, message: erroPagamentos };
  const somaPagamentos = Math.round(pagamentos.reduce((s, p) => s + Number(p.valor), 0) * 100) / 100;
  if (Math.abs(somaPagamentos - valorTotal) > 0.02) {
    return { ok: false, message: 'A soma dos pagamentos (R$ ' + somaPagamentos.toFixed(2) + ') não bate com o total da venda (R$ ' + valorTotal.toFixed(2) + ').' };
  }

  linhasItens.forEach(l => shItens.appendRow(l));
  const statusPag = statusPagamento === 'A Receber' ? 'A Receber' : 'Pago';
  const formaPagamentoResumo = pagamentos.map(p => p.forma).join(' + ');
  const origemFinal = ['Cardápio', 'Garçom'].indexOf(origem) !== -1 ? origem : 'Balcão';
  const statusPedidoInicial = origemFinal === 'Cardápio' ? 'Recebido' : 'Em preparo';
  const numeroPedido = proximoNumeroPedido_(shVendas); // ETAPA 2: número amigável sequencial (já estamos dentro do lock)
  shVendas.appendRow([
    vendaId, dataVenda, clienteNome || '', clienteTelefone || '', formaPagamentoResumo, valorTotal, custoTotal, 'Confirmada', '',
    tipo, statusPedidoInicial, tipo === 'Entrega' ? (de.endereco || '') : '', tipo === 'Entrega' ? (de.complemento || '') : '', tipo === 'Entrega' ? (de.referencia || '') : '', de.observacoes || '', '', '',
    statusPag, statusPag === 'Pago' ? dataVenda : '',
    valorOriginal, valorDesconto, descontoDetalhe, '', '', origemFinal,
    tipo === 'Mesa' ? mesaId : '', taxaEntrega, '', USUARIO_ATUAL || '', numeroPedido
  ]);
  if (origemContingenciaTs) { // marca "veio da contingência" (Vendas!AG = quando foi gravada de verdade)
    try { prepararContingenciaTimestamp_(); shVendas.getRange(shVendas.getLastRow(), COL_VENDA_REGISTRADA_EM_).setValue(new Date()); }
    catch (e) { registrarLog('Falha ao marcar venda de contingência', '', e.message); }
  }
  if (chaveReq) requisicaoRegistrar_(chaveReq, 'iniciarVenda', vendaId); // registra logo após gravar a venda: janela mínima contra duplicação
  pagamentos.forEach(p => { shPagamentos.appendRow([Utilities.getUuid(), vendaId, p.forma, Number(p.valor) || 0, calcularTaxaPagamento_(p.forma, Number(p.valor) || 0)]); });
  if (tipo === 'Mesa') {
    const mesaAtual = readMesas().find(m => m.id === mesaId);
    if (mesaAtual && mesaAtual.status === 'Livre') editarStatusMesa(mesaId, 'Ocupada');
  }

  ajustarEstoquePorVenda(itens, 1, vendaId);

  if (valorDesconto > 0) {
    registrarLog('Desconto aplicado na venda', clienteTelefone || '', 'Autorizado por ' + (AUTORIZADOR_ATUAL || USUARIO_ATUAL) + ' | Valor original: R$ ' + valorOriginal.toFixed(2) + ' → Desconto: ' + descontoDetalhe + ' → Valor final: R$ ' + valorTotal.toFixed(2));
  }

  let mensagemExtra = '';
  if (clienteTelefone) {
    upsertCliente(clienteTelefone, clienteNome);
    /* CORREÇÃO (Módulo 2): a marca só sai quando o pagamento já entrou (venda de balcão paga).
       Pedido do Cardápio, mesa ou "A Receber" recebe a marca na confirmação do pagamento —
       antes, pedido cancelado/rejeitado também pontuava e o cliente ganhava prêmio sem comprar. */
    if (origemFinal === 'Balcão' && statusPag === 'Pago') {
      addOrStampFidelidade(clienteTelefone, clienteNome, '');
      mensagemExtra = ' Marca de fidelidade adicionada para ' + clienteNome + '.';
    }
  }
  registrarLog('Venda registrada', clienteTelefone || '', 'Total R$ ' + valorTotal.toFixed(2) + ' via ' + formaPagamentoResumo + ' (' + tipo + ', ' + statusPag + ')' + (origemContingenciaTs ? ' | origem: contingência, hora original ' + Utilities.formatDate(dataVenda, FUSO, 'dd/MM/yyyy HH:mm') : ''));

  return {
    ok: true, message: 'Venda registrada: R$ ' + valorTotal.toFixed(2) + '.' + mensagemExtra, id: vendaId, numero: numeroPedido, valorTotal: valorTotal, timestampAplicado: origemContingenciaTs ? dataVenda.getTime() : undefined,
    vendas: readVendasResposta_(), itensVenda: readItensVendaResposta_(), pagamentosVenda: readPagamentosVendaResposta_(),
    fidelidade: readFidelidadeResposta_(), clientes: readClientesResposta_(), estoque: readEstoqueResposta_()
  };
}
function confirmarRecebimentoPedido(vendaId) {
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  if (last < 2) return { ok: false, message: 'Venda não encontrada.' };
  const ids = sh.getRange(2, 1, last - 1, 1).getValues();
  for (let k = 0; k < ids.length; k++) {
    if (ids[k][0] !== vendaId) continue;
    const i = k + 2;
    if (sh.getRange(i, 8).getValue() !== 'Confirmada') return { ok: false, message: 'Este pedido foi cancelado — não dá para receber o pagamento.' };
    // Idempotente: um segundo toque (ou retry) não regrava data nem duplica log.
    if (sh.getRange(i, 18).getValue() === 'Pago') return { ok: true, duplicado: true, message: 'Este pedido já estava com o pagamento confirmado.', vendas: readVendasResposta_() };
    sh.getRange(i, 18, 1, 2).setValues([['Pago', new Date()]]);
    registrarLog('Pagamento confirmado', sh.getRange(i, 4).getValue(), vendaId + ' | por ' + (USUARIO_ATUAL || ''));
    const telConf = sh.getRange(i, 4).getValue();
    if (telConf) addOrStampFidelidade(telConf, sh.getRange(i, 3).getValue(), ''); // marca no momento em que o dinheiro entra
    return { ok: true, vendas: readVendasResposta_(), fidelidade: readFidelidadeResposta_() };
  }
  return { ok: false, message: 'Venda não encontrada.' };
}

/* ---------- PEDIDOS: avançar status (Em preparo → Pronta → Retirada, ou → Saiu para entrega → Entregue) ---------- */
function avancarStatusPedido(vendaId, novoStatus, statusEsperado) {
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  const validos = ['Em preparo', 'Pronta', 'Saiu para entrega', 'Entregue', 'Retirada', 'Servida'];
  if (validos.indexOf(novoStatus) === -1) return { ok: false, message: 'Status inválido.' };
  { const i = linhaDoId_(sh, vendaId);
    if (i > 0) {
      const tipo = sh.getRange(i, 10).getValue();
      const statusAtual = sh.getRange(i, 11).getValue();
      if (sh.getRange(i, 8).getValue() !== 'Confirmada') return { ok: false, message: 'Este pedido foi cancelado.' };
      if (statusEsperado && statusEsperado !== statusAtual) return { ok: false, conflito: true, message: 'Este pedido já foi atualizado por outra pessoa (agora está "' + statusAtual + '"). A tela foi atualizada.', vendas: readVendasResposta_() };
      if (statusAtual === 'Suspenso') return { ok: false, message: 'Este pedido está suspenso — retome antes de avançar.', vendas: readVendasResposta_() };
      if (sh.getRange(i, 28).getValue()) return { ok: false, message: 'Esta entrega já está em um fechamento — não pode mais ser alterada.' };
      if (tipo === 'Retirada' && (novoStatus === 'Saiu para entrega' || novoStatus === 'Entregue' || novoStatus === 'Servida')) return { ok: false, message: 'Pedido de retirada não tem esse status.' };
      if (tipo === 'Entrega' && (novoStatus === 'Retirada' || novoStatus === 'Servida')) return { ok: false, message: 'Pedido de entrega não tem esse status.' };
      if (tipo === 'Mesa' && (novoStatus === 'Saiu para entrega' || novoStatus === 'Entregue' || novoStatus === 'Retirada')) return { ok: false, message: 'Pedido de mesa não tem esse status — use "Servida".' };
      const transicaoValida = (novoStatus === 'Em preparo' && statusAtual === 'Recebido') ||
        (novoStatus === 'Pronta' && statusAtual === 'Em preparo') ||
        (novoStatus === 'Saiu para entrega' && statusAtual === 'Pronta') ||
        (novoStatus === 'Entregue' && statusAtual === 'Saiu para entrega') ||
        (novoStatus === 'Retirada' && statusAtual === 'Pronta') ||
        (novoStatus === 'Servida' && statusAtual === 'Pronta');
      if (!transicaoValida) return { ok: false, message: 'Transição inválida: o pedido está "' + statusAtual + '" e não pode avançar diretamente para "' + novoStatus + '".' };
      const entregadorDoPedido = String(sh.getRange(i, 23).getValue() || '');
      if (NIVEL_ATUAL === 'Cozinha' && ['Em preparo', 'Pronta'].indexOf(novoStatus) === -1) return { ok: false, message: 'A cozinha só pode marcar "Em preparo" e "Pronta".' };
      if (novoStatus === 'Pronta' && statusAtual === 'Recebido') return { ok: false, message: 'Aceite o pedido e inicie o preparo antes de marcá-lo como pronto.' };
      if (NIVEL_ATUAL === 'Garçom') {
        if (!vendaNoEscopoDoUsuario_({
          id: vendaId,
          tipoEntrega: tipo,
          mesaId: sh.getRange(i, 26).getValue(), // coluna 26 = ID da Mesa (a 27 é Taxa Entrega)
          registradoPor: sh.getRange(i, 29).getValue()
        })) return { ok: false, message: 'Este pedido não está no seu escopo operacional.' };
        if (novoStatus !== 'Servida') return { ok: false, message: 'O garçom apenas pode marcar como "Servida" um pedido de sua mesa.' };
      }
      if (NIVEL_ATUAL === 'Entregador') {
        if (tipo !== 'Entrega' || entregadorDoPedido.toLowerCase() !== String(USUARIO_ATUAL).toLowerCase()) return { ok: false, message: 'Esta entrega não está atribuída a você.' };
        if (novoStatus !== 'Saiu para entrega' && novoStatus !== 'Entregue') return { ok: false, message: 'O entregador só pode marcar "Saiu para entrega" e "Entregue".' };
      }
      if (tipo === 'Entrega') {
        if (novoStatus === 'Saiu para entrega') {
          if (statusAtual !== 'Pronta') return { ok: false, message: 'O pedido precisa estar "Pronta" antes de sair para entrega.' };
          if (!entregadorDoPedido) return { ok: false, message: 'Atribua um entregador antes de o pedido sair para entrega.' };
        }
        if (novoStatus === 'Entregue' && statusAtual !== 'Saiu para entrega') return { ok: false, message: 'O pedido precisa ter saído para entrega antes de ser marcado como entregue.' };
      }
      sh.getRange(i, 11).setValue(novoStatus);
      if (novoStatus === 'Pronta') sh.getRange(i, 16).setValue(new Date());
      if (novoStatus === 'Saiu para entrega') sh.getRange(i, 24).setValue(new Date());
      if (novoStatus === 'Entregue' || novoStatus === 'Retirada' || novoStatus === 'Servida') sh.getRange(i, 17).setValue(new Date());
      registrarLog('Status do pedido atualizado', '', vendaId + ' → ' + novoStatus);
      return { ok: true, vendas: readVendasResposta_() };
    }
  }
  return { ok: false, message: 'Venda não encontrada.' };
}
/* ---------- ETAPA 4 — COZINHA E GARÇOM ---------- */
/* Rode UMA vez no editor em planilha que já existe (planilha nova já nasce com a coluna). Pode repetir sem duplicar. */
/* A cozinha aceita (se veio do Cardápio) e começa a preparar. O status do pedido continua o mesmo fluxo
   (Recebido → Em preparo → Pronta); "Início Preparo" só separa "novo" de "em preparo" na tela da cozinha. */
function iniciarPreparoPedido(vendaId) {
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  garantirColuna_(sh, 31, 'Início Preparo', 150);
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() !== vendaId) continue;
    if (sh.getRange(i, 8).getValue() !== 'Confirmada') return { ok: false, message: 'Este pedido foi cancelado.', vendas: readVendasResposta_() };
    const st = sh.getRange(i, 11).getValue();
    if (st !== 'Recebido' && st !== 'Em preparo') return { ok: false, conflito: true, message: 'Este pedido já está "' + st + '". A tela foi atualizada.', vendas: readVendasResposta_() };
    if (st === 'Recebido') { sh.getRange(i, 11).setValue('Em preparo'); registrarLog('Pedido aceito', sh.getRange(i, 4).getValue(), 'Aceito pela cozinha'); }
    if (!sh.getRange(i, 31).getValue()) sh.getRange(i, 31).setValue(new Date());
    registrarLog('Preparo iniciado', '', vendaId);
    return { ok: true, vendas: readVendasResposta_() };
  }
  return { ok: false, message: 'Pedido não encontrado.' };
}
/* Detector da cozinha: consulta LEVE (só ids de pedidos novos, últimas 300 linhas). O app só faz a sincronização
   completa quando aparece um id que ele ainda não viu. */
/* ITEM 3.1 (alternativa sem push): o Entregador e o Garçom também ganham o "detector em segundo plano" do app. Cada um só recebe os ids do que é DELE:
   Entregador → entregas atribuídas a ele e ainda não entregues; Garçom → pedidos "Pronta" das mesas sob a sua responsabilidade. */
function detectarNovosPedidosPerfil_() {
  const login = String(USUARIO_ATUAL || '').toLowerCase();
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  if (last < 2 || !login) return { ok: true, ids: [], recebidos: [], total: 0, entregas: [], prontas: [] };
  const cols = Math.min(31, sh.getMaxColumns()), ini = Math.max(2, last - 299);
  const linhas = sh.getRange(ini, 1, last - ini + 1, cols).getValues();
  const entregas = [], prontas = [];
  if (NIVEL_ATUAL === 'Entregador') {
    linhas.forEach(r => {
      if (!r[0] || r[7] !== 'Confirmada' || r[9] !== 'Entrega' || String(r[22] || '').toLowerCase() !== login) return;
      if (r[10] === 'Entregue' || r[10] === 'Suspenso') return;
      entregas.push(String(r[0]));
    });
  } else if (NIVEL_ATUAL === 'Garçom') {
    const minhasMesas = {}; readMesas().forEach(m => { if (String(m.garcomResponsavel || '').toLowerCase() === login) minhasMesas[m.id] = true; });
    linhas.forEach(r => {
      if (!r[0] || r[7] !== 'Confirmada' || !r[25] || !minhasMesas[r[25]]) return;
      if (r[10] === 'Pronta') prontas.push(String(r[0]));
    });
  }
  return { ok: true, ids: [], recebidos: [], total: 0, entregas: entregas, prontas: prontas };
}
function detectarNovosPedidos() {
  if (NIVEL_ATUAL === 'Entregador' || NIVEL_ATUAL === 'Garçom') return detectarNovosPedidosPerfil_();
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  if (last < 2) return { ok: true, ids: [], recebidos: [], total: 0 };
  const cols = Math.min(31, sh.getMaxColumns());
  const ini = Math.max(2, last - 299);
  const ids = [], recebidos = [];
  sh.getRange(ini, 1, last - ini + 1, cols).getValues().forEach(r => {
    if (!r[0] || r[7] !== 'Confirmada') return;
    const iniciou = cols >= 31 && r[30];
    if (r[10] === 'Recebido') recebidos.push(String(r[0]));
    if (r[10] === 'Recebido' || (r[10] === 'Em preparo' && !iniciou)) ids.push(String(r[0]));
  });
  return { ok: true, ids: ids, recebidos: recebidos, total: ids.length };
}
/* Garçom: só abre mesa livre e pede fechamento de mesa ocupada. Qualquer outra mudança de mesa é do Admin/Operador. */
function editarStatusMesaGarcom_(id, novoStatus) {
  const mesa = readMesas().find(m => m.id === id);
  if (!mesa) return { ok: false, message: 'Mesa não encontrada.' };
  const permitido = (mesa.status === 'Livre' && novoStatus === 'Ocupada') || (mesa.status === 'Ocupada' && novoStatus === 'Aguardando fechamento');
  if (!permitido) return { ok: false, message: 'O garçom só pode abrir uma mesa livre ou pedir o fechamento de uma mesa ocupada.' };
  if (mesa.status === 'Ocupada' && mesa.garcomResponsavel && String(mesa.garcomResponsavel).toLowerCase() !== String(USUARIO_ATUAL).toLowerCase()) return { ok: false, message: 'Esta mesa está sob responsabilidade de outro garçom.' };
  const r = editarStatusMesa(id, novoStatus);
  if (r.ok && novoStatus === 'Ocupada') {
    const sh = ss_().getSheetByName('Mesas'); const last = sh.getLastRow();
    for (let i = 2; i <= last; i++) if (sh.getRange(i, 1).getValue() === id) { sh.getRange(i, 6).setValue(USUARIO_ATUAL || ''); break; }
  }
  if (r.ok && novoStatus === 'Aguardando fechamento') registrarLog('Fechamento de mesa solicitado', '', 'Mesa ' + mesa.numero);
  return r;
}
function atribuirEntregador(vendaId, entregador) {
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  const login = String(entregador || '').trim();
  if (login) {
    const u = readUsuarios().find(x => String(x.login).toLowerCase() === login.toLowerCase());
    if (!u || u.nivel !== 'Entregador') return { ok: false, message: 'Esse usuário não é um entregador cadastrado.' };
    if (!u.ativo) return { ok: false, message: 'Esse entregador está inativo.' };
  }
  { const i = linhaDoId_(sh, vendaId);
    if (i > 0) {
      if (sh.getRange(i, 10).getValue() !== 'Entrega') return { ok: false, message: 'Só pedidos de entrega têm entregador.' };
      if (sh.getRange(i, 8).getValue() !== 'Confirmada') return { ok: false, message: 'Este pedido foi cancelado.' };
      if (sh.getRange(i, 28).getValue()) return { ok: false, message: 'Esta entrega já está em um fechamento — não pode mais ser alterada.' };
      const statusAtual = sh.getRange(i, 11).getValue();
      if (statusAtual === 'Entregue') return { ok: false, message: 'Esta entrega já foi concluída.' };
      if (statusAtual === 'Saiu para entrega' && !login) return { ok: false, message: 'O pedido já saiu para entrega — troque o entregador, não remova.' };
      const anterior = String(sh.getRange(i, 23).getValue() || '');
      sh.getRange(i, 23).setValue(login ? (readUsuarios().find(x => String(x.login).toLowerCase() === login.toLowerCase()).login) : '');
      registrarLog('Entregador atribuído', '', vendaId + ': ' + (anterior || '(nenhum)') + ' → ' + (login || '(nenhum)'));
      return { ok: true, vendas: readVendasResposta_() };
    }
  }
  return { ok: false, message: 'Venda não encontrada.' };
}

function editarVenda(id, itens, motivo, senhaAdminConfirmacao) {
  if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta.' };
  if (!motivo) return { ok: false, message: 'Informe o motivo da edição.' };
  if (!itens || !itens.length) return { ok: false, message: 'A venda precisa ter ao menos um item.' };
  const erroItens = validarItensVenda_(itens, '');
  if (erroItens) return { ok: false, message: erroItens };
  const shVendas = ss_().getSheetByName('Vendas');
  const shItens = ss_().getSheetByName('ItensVenda');
  const last = shVendas.getLastRow();
  { const i = linhaDoId_(shVendas, id);
    if (i > 0) {
      if (shVendas.getRange(i, 8).getValue() !== 'Confirmada') return { ok: false, message: 'Só é possível editar vendas confirmadas.' };
      if (shVendas.getRange(i, 28).getValue()) return { ok: false, message: 'Esta entrega já está em um fechamento — não pode mais ser alterada.' };
      const statusPedidoAtual = shVendas.getRange(i, 11).getValue();
      // ITEM 2.2: também dá para editar enquanto o pedido ainda está "Recebido" (antes do aceite) — o número do pedido não muda.
      if (statusPedidoAtual && statusPedidoAtual !== 'Em preparo' && statusPedidoAtual !== 'Recebido') return { ok: false, message: 'Este pedido já está "' + statusPedidoAtual + '" — não é mais possível editar os itens.' };
      const antesDoAceite = statusPedidoAtual === 'Recebido';
      const clienteTelefone = shVendas.getRange(i, 4).getValue();

      // FASE 9 — a edição respeita desconto, pagamento e estoque (antes descartava o desconto e não mexia no estoque).
      const itensAntigos = readItensVenda().filter(it => it.vendaId === id);
      itens.forEach(it => { if (!it.adicionaisIds) { const ant = itensAntigos.find(a => a.descricao === it.descricao); it.adicionaisIds = ant ? ant.adicionaisIds : []; } });
      const somaNova = Math.round(itens.reduce((t, it) => t + Math.round((Number(it.quantidade) || 1) * (Number(it.valorUnitario) || 0) * 100) / 100, 0) * 100) / 100;
      const descontoAtual = numPlanilha_(shVendas.getRange(i, 21).getValue()) || 0;
      if (descontoAtual >= somaNova) return { ok: false, message: 'Com o desconto já aplicado, o novo total ficaria zero ou negativo.' };
      const totalNovo = Math.round((somaNova - descontoAtual) * 100) / 100;
      const shPag = ss_().getSheetByName('PagamentosVenda'); const linhasPag = [];
      for (let p = 2; p <= shPag.getLastRow(); p++) { if (shPag.getRange(p, 2).getValue() === id) linhasPag.push(p); }
      if (linhasPag.length > 1) return { ok: false, message: 'Venda com pagamento dividido não pode ser editada. Cancele e lance novamente.' };
      const totalAntes = numPlanilha_(shVendas.getRange(i, 6).getValue()) || 0;

      const lastItens = shItens.getLastRow();
      for (let j = lastItens; j >= 2; j--) { if (shItens.getRange(j, 2).getValue() === id) shItens.deleteRow(j); }

      let valorTotal = 0, custoTotal = 0;
      itens.forEach(it => {
        const qtd = Number(it.quantidade) || 1;
        const vUnit = Number(it.valorUnitario) || 0;
        const cUnit = Number(it.custoUnitario) || 0;
        const totalItem = Math.round(qtd * vUnit * 100) / 100;
        valorTotal += totalItem;
        custoTotal += qtd * cUnit;
        shItens.appendRow([Utilities.getUuid(), id, it.produtoId || '', it.comboId || '', it.descricao, qtd, vUnit, cUnit, totalItem, JSON.stringify(it.adicionaisIds || [])]);
      });
      valorTotal = Math.round(valorTotal * 100) / 100;
      custoTotal = Math.round(custoTotal * 100) / 100;

      valorTotal = totalNovo;
      shVendas.getRange(i, 6).setValue(totalNovo);
      shVendas.getRange(i, 7).setValue(custoTotal);
      shVendas.getRange(i, 20).setValue(somaNova);
      if (linhasPag.length === 1) { shPag.getRange(linhasPag[0], 4).setValue(totalNovo); shPag.getRange(linhasPag[0], 5).setValue(calcularTaxaPagamento_(shPag.getRange(linhasPag[0], 3).getValue(), totalNovo)); }
      ajustarEstoquePorVenda(itensAntigos, -1, id);
      ajustarEstoquePorVenda(itens, 1, id);
      registrarLog('Venda editada', clienteTelefone, (antesDoAceite ? '[edição antes do aceite] ' : '') + 'Autorizado por ' + (AUTORIZADOR_ATUAL || USUARIO_ATUAL) + ' | Motivo: ' + motivo + ' | Total: R$ ' + totalAntes.toFixed(2) + ' → R$ ' + valorTotal.toFixed(2));
      // Pedido do cardápio já com pagamento registrado e valor alterado: o cliente precisa refazer/ajustar a cobrança (não bloqueia, só avisa).
      let avisoPag = '';
      try {
        if (antesDoAceite && String(shVendas.getRange(i, 25).getValue()) === 'Cardápio' && String(shVendas.getRange(i, 18).getValue()) === 'Pago' && Math.abs(totalNovo - totalAntes) >= 0.01) {
          avisoPag = ' ATENÇÃO: o valor mudou (R$ ' + totalAntes.toFixed(2) + ' → R$ ' + totalNovo.toFixed(2) + ') e este pedido já consta como pago — acerte a diferença com o cliente.';
        }
      } catch (ePag) {}
      return { ok: true, message: 'Venda atualizada. Novo total: R$ ' + valorTotal.toFixed(2) + '.' + avisoPag, aviso: !!avisoPag, vendas: readVendasResposta_(), itensVenda: readItensVendaResposta_() };
    }
  }
  return { ok: false, message: 'Venda não encontrada.' };
}

function cancelarVenda(id, motivo, senhaAdminConfirmacao, mercadoriaPerdida) {
  if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta.' };
  if (!motivo) return { ok: false, message: 'Informe o motivo do cancelamento.' };
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, id);
    if (i > 0) {
      if (sh.getRange(i, 8).getValue() === 'Cancelada') return { ok: false, message: 'Esta venda já está cancelada.' };
      if (sh.getRange(i, 28).getValue()) return { ok: false, message: 'Esta entrega já está em um fechamento — não pode ser cancelada. Faça o ajuste pelo Financeiro.' };
      let statusPedidoAtual = sh.getRange(i, 11).getValue();
      if (statusPedidoAtual === 'Suspenso') statusPedidoAtual = String(sh.getRange(i, 32).getValue() || 'Em preparo');
      const jaEstavaPronta = statusPedidoAtual && statusPedidoAtual !== 'Em preparo' && statusPedidoAtual !== 'Recebido';
      sh.getRange(i, 8).setValue('Cancelada');
      sh.getRange(i, 9).setValue(motivo);
      const itensDaVenda = readItensVenda().filter(it => it.vendaId === id);
      // Antes de "Pronta", o estoque sempre volta. Depois de "Pronta", só volta se a mercadoria não foi perdida.
      if (!jaEstavaPronta || mercadoriaPerdida === false) ajustarEstoquePorVenda(itensDaVenda, -1, id);
      const estavaPaga = sh.getRange(i, 18).getValue() === 'Pago';
      registrarLog('Venda cancelada', sh.getRange(i, 4).getValue(), 'Autorizado por ' + (AUTORIZADOR_ATUAL || USUARIO_ATUAL) + ' | R$ ' + Number(sh.getRange(i, 6).getValue() || 0).toFixed(2) + ' | ' + motivo + (estavaPaga ? ' | ESTORNO ao cliente pendente (venda estava paga)' : '') + (jaEstavaPronta ? (mercadoriaPerdida ? ' — mercadoria perdida' : ' — mercadoria devolvida ao estoque') : ''));
      return { ok: true, vendas: readVendasResposta_(), estoque: readEstoqueResposta_() };
    }
  }
  return { ok: false, message: 'Venda não encontrada.' };
}

/* ---------- ACEITAR/REJEITAR PEDIDO (ITEM 3.2) ----------
   Só pedidos vindos do Cardápio Digital nascem "Recebido", esperando alguém do
   balcão aceitar antes de ir pra cozinha. Aceitar não pede senha — é operação
   do dia a dia; rejeitar pede, porque cancela e mexe em estoque/dinheiro. */
/* =========================================================
   FASE 7 — ENTREGAS: taxa, remuneração e fechamento (ITENS 51–54)
   Regra: 100% da taxa de entrega vai para o entregador; fechamento =
   soma das taxas + ajuda diária. A taxa NÃO entra no Valor Total da venda
   (esse valor é receita dos produtos e precisa bater com os pagamentos).
   ========================================================= */
function readConfigEntrega() {
  return {
    taxaPadrao: numPlanilha_(lerConfigChave_('TaxaEntregaPadrao', 0)),
    ajudaDiaria: numPlanilha_(lerConfigChave_('AjudaDiariaEntregador', 0))
  };
}
function salvarConfigEntrega(taxaPadrao, ajudaDiaria) {
  const t = Number(taxaPadrao), a = Number(ajudaDiaria);
  if (isNaN(t) || t < 0 || t > 500) return { ok: false, message: 'Taxa de entrega inválida.' };
  if (isNaN(a) || a < 0 || a > 1000) return { ok: false, message: 'Ajuda diária inválida.' };
  const antes = readConfigEntrega();
  salvarConfigChave_('TaxaEntregaPadrao', Math.round(t * 100) / 100);
  salvarConfigChave_('AjudaDiariaEntregador', Math.round(a * 100) / 100);
  registrarLog('Configuração de entrega alterada', '', 'Taxa: R$ ' + antes.taxaPadrao.toFixed(2) + ' → R$ ' + t.toFixed(2) + ' | Ajuda diária: R$ ' + antes.ajudaDiaria.toFixed(2) + ' → R$ ' + a.toFixed(2) + ' (vale só para pedidos e fechamentos futuros)');
  return { ok: true, message: 'Configuração de entrega salva.', configEntrega: readConfigEntrega() };
}
/* Taxa do pedido: sempre a configurada no servidor. Admin/Operador podem
   sobrescrever no lançamento (ex.: bairro mais distante); cliente do Cardápio nunca. */
function calcularTaxaEntrega_(dadosEntrega) {
  if (dadosEntrega && dadosEntrega.freteGratis === true) return 0;
  const padrao = readConfigEntrega().taxaPadrao;
  const podeSobrescrever = NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador';
  if (podeSobrescrever && dadosEntrega && dadosEntrega.taxa !== undefined && dadosEntrega.taxa !== null && dadosEntrega.taxa !== '') {
    const t = Number(dadosEntrega.taxa);
    if (!isNaN(t) && t >= 0 && t <= 500) return Math.round(t * 100) / 100;
  }
  return padrao;
}
function readFechamentosEntrega() {
  const sh = ss_().getSheetByName('FechamentosEntrega'); if (!sh) return [];
  const last = sh.getLastRow(); if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 13).getValues().filter(r => r[0]).map(r => ({
    id: r[0], dataRef: String(r[1]), entregador: r[2], qtd: numPlanilha_(r[3]) || 0, totalTaxas: numPlanilha_(r[4]) || 0, ajudaDiaria: numPlanilha_(r[5]) || 0,
    totalDevido: numPlanilha_(r[6]) || 0, valorPago: numPlanilha_(r[7]) || 0, diferenca: numPlanilha_(r[8]) || 0,
    fechadoEm: Utilities.formatDate(new Date(r[9]), FUSO, 'dd/MM/yyyy HH:mm'), fechadoPor: r[10] || '', observacao: r[11] || '', requisicaoId: r[12] || ''
  }));
}
function readEntregasFechadas() {
  const sh = ss_().getSheetByName('EntregasFechadas'); if (!sh) return [];
  const last = sh.getLastRow(); if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 6).getValues().filter(r => r[0]).map(r => ({
    id: r[0], fechamentoId: r[1], vendaId: r[2], dataRef: String(r[3]), entregador: r[4], taxa: numPlanilha_(r[5]) || 0
  }));
}
function calcularFechamentoEntrega_(login, dataRef) {
  const alvo = String(login || '').toLowerCase();
  const vendas = readVendas().filter(v => v.status === 'Confirmada' && v.tipoEntrega === 'Entrega' && v.statusPedido === 'Entregue' &&
    String(v.entregador).toLowerCase() === alvo && !v.fechamentoEntregaId && v.timestampConcluida &&
    Utilities.formatDate(new Date(v.timestampConcluida), FUSO, 'yyyy-MM-dd') === dataRef);
  const totalTaxas = Math.round(vendas.reduce((s, v) => s + (Number(v.taxaEntrega) || 0), 0) * 100) / 100;
  const jaTeveFechamentoNoDia = readFechamentosEntrega().some(f => String(f.entregador).toLowerCase() === alvo && f.dataRef === dataRef);
  const ajuda = (vendas.length && !jaTeveFechamentoNoDia) ? readConfigEntrega().ajudaDiaria : 0;
  return { vendas: vendas, qtd: vendas.length, totalTaxas: totalTaxas, ajudaDiaria: ajuda, totalDevido: Math.round((totalTaxas + ajuda) * 100) / 100 };
}
function previewFechamentoEntrega(login, dataRef) {
  if (!login || !/^\d{4}-\d{2}-\d{2}$/.test(String(dataRef || ''))) return { ok: false, message: 'Informe o entregador e a data.' };
  const c = calcularFechamentoEntrega_(login, dataRef);
  return { ok: true, qtd: c.qtd, totalTaxas: c.totalTaxas, ajudaDiaria: c.ajudaDiaria, totalDevido: c.totalDevido, vendaIds: c.vendas.map(v => v.id) };
}
function fecharPeriodoEntregador(login, dataRef, valorPago, observacao, requisicaoId, leve) {
  if (!login || !/^\d{4}-\d{2}-\d{2}$/.test(String(dataRef || ''))) return { ok: false, message: 'Informe o entregador e a data.' };
  if (!requisicaoId) return { ok: false, message: 'Requisição sem identificador.' };
  const existente = readFechamentosEntrega().find(f => f.requisicaoId === requisicaoId);
  if (existente && leve) return { ok: true, duplicado: true, message: 'Este fechamento já havia sido registrado.' };
  if (existente) return { ok: true, message: 'Este fechamento já havia sido registrado.', duplicado: true, fechamento: existente, vendas: readVendasResposta_(), fechamentosEntrega: readFechamentosEntrega(), entregasFechadas: readEntregasFechadas() };
  const pago = Number(valorPago);
  if (isNaN(pago) || pago < 0) return { ok: false, message: 'Informe o valor pago ao entregador.' };
  const u = readUsuarios().find(x => String(x.login).toLowerCase() === String(login).toLowerCase());
  if (!u || u.nivel !== 'Entregador') return { ok: false, message: 'Entregador não encontrado.' };
  const c = calcularFechamentoEntrega_(u.login, dataRef);
  if (!c.qtd) return { ok: false, message: 'Não há entregas concluídas em aberto para esse entregador nessa data.' };
  const pagoR = Math.round(pago * 100) / 100;
  const dif = Math.round((pagoR - c.totalDevido) * 100) / 100;
  if (dif !== 0 && !String(observacao || '').trim()) return { ok: false, message: 'O valor pago é diferente do devido (R$ ' + c.totalDevido.toFixed(2) + '). Informe o motivo da diferença.' };
  const fechId = Utilities.getUuid();
  ss_().getSheetByName('FechamentosEntrega').appendRow([fechId, dataRef, u.login, c.qtd, c.totalTaxas, c.ajudaDiaria, c.totalDevido, pagoR, dif, new Date(), USUARIO_ATUAL, observacao || '', requisicaoId]);
  const shEF = ss_().getSheetByName('EntregasFechadas');
  const shV = ss_().getSheetByName('Vendas'); const last = shV.getLastRow();
  const ids = shV.getRange(2, 1, last - 1, 1).getValues().map(r => r[0]);
  c.vendas.forEach(v => {
    shEF.appendRow([Utilities.getUuid(), fechId, v.id, dataRef, u.login, Number(v.taxaEntrega) || 0]);
    const idx = ids.indexOf(v.id);
    if (idx !== -1) shV.getRange(idx + 2, 28).setValue(fechId);
  });
  registrarLog('Fechamento de entregas', '', u.login + ' | ' + dataRef + ' | ' + c.qtd + ' entregas | devido R$ ' + c.totalDevido.toFixed(2) + ' | pago R$ ' + pagoR.toFixed(2) + ' | dif R$ ' + dif.toFixed(2) + (observacao ? ' | ' + observacao : ''));
  if (leve) return { ok: true, message: 'Fechamento registrado.' };
  return { ok: true, message: 'Fechamento registrado: devido R$ ' + c.totalDevido.toFixed(2) + ', pago R$ ' + pagoR.toFixed(2) + '.', vendas: readVendasResposta_(), fechamentosEntrega: readFechamentosEntrega(), entregasFechadas: readEntregasFechadas() };
}

function salvarConfigEstoque(bloquear) {
  salvarConfigChave_('BLOQUEAR_ESTOQUE_NEGATIVO', bloquear === true || bloquear === 'true' ? 'Sim' : 'Não');
  registrarLog('Regra de estoque alterada', '', 'Bloquear venda sem estoque: ' + (bloquear === true || bloquear === 'true' ? 'Sim' : 'Não'));
  return { ok: true, message: 'Regra de estoque salva.', configEstoque: { bloquear: String(lerConfigChave_('BLOQUEAR_ESTOQUE_NEGATIVO', 'Não')) === 'Sim' } };
}
/* ---------- SUSPENDER / RETOMAR PEDIDO (ITEM 11: estado especial "Suspenso") ----------
   Guarda o status anterior na coluna 32 para retomar exatamente de onde parou. */
function suspenderPedido(vendaId, motivo) {
  const m = textoPlanilhaSeguro_(motivo).slice(0, 200);
  if (!m) return { ok: false, message: 'Informe o motivo da suspensão.' };
  const sh = ss_().getSheetByName('Vendas'); garantirColuna_(sh, 32, 'Status Antes da Suspensão', 170);
  const last = sh.getLastRow(); if (last < 2) return { ok: false, message: 'Pedido não encontrado.' };
  const ids = sh.getRange(2, 1, last - 1, 1).getValues();
  for (let k = 0; k < ids.length; k++) {
    if (ids[k][0] !== vendaId) continue;
    const i = k + 2;
    if (sh.getRange(i, 8).getValue() !== 'Confirmada') return { ok: false, message: 'Este pedido foi cancelado.' };
    if (sh.getRange(i, 28).getValue()) return { ok: false, message: 'Esta entrega já está em um fechamento — não pode mais ser alterada.' };
    const atual = sh.getRange(i, 11).getValue();
    if (['Recebido', 'Em preparo', 'Pronta'].indexOf(atual) === -1) return { ok: false, conflito: true, message: 'Só dá para suspender pedido em "Recebido", "Em preparo" ou "Pronta" (agora está "' + atual + '").', vendas: readVendasResposta_() };
    sh.getRange(i, 32).setValue(atual);
    sh.getRange(i, 11).setValue('Suspenso');
    registrarLog('Pedido suspenso', sh.getRange(i, 4).getValue(), vendaId + ' | de "' + atual + '" | ' + m);
    return { ok: true, vendas: readVendasResposta_() };
  }
  return { ok: false, message: 'Pedido não encontrado.' };
}
function retomarPedido(vendaId) {
  const sh = ss_().getSheetByName('Vendas'); garantirColuna_(sh, 32, 'Status Antes da Suspensão', 170);
  const last = sh.getLastRow(); if (last < 2) return { ok: false, message: 'Pedido não encontrado.' };
  const ids = sh.getRange(2, 1, last - 1, 1).getValues();
  for (let k = 0; k < ids.length; k++) {
    if (ids[k][0] !== vendaId) continue;
    const i = k + 2;
    if (sh.getRange(i, 8).getValue() !== 'Confirmada') return { ok: false, message: 'Este pedido foi cancelado.' };
    if (sh.getRange(i, 11).getValue() !== 'Suspenso') return { ok: false, conflito: true, message: 'Este pedido não está suspenso.', vendas: readVendasResposta_() };
    const antes = String(sh.getRange(i, 32).getValue() || 'Em preparo');
    sh.getRange(i, 11).setValue(antes === 'Recebido' || antes === 'Pronta' ? antes : 'Em preparo');
    sh.getRange(i, 32).setValue('');
    registrarLog('Pedido retomado', sh.getRange(i, 4).getValue(), vendaId + ' → ' + antes);
    return { ok: true, vendas: readVendasResposta_() };
  }
  return { ok: false, message: 'Pedido não encontrado.' };
}
function aceitarPedido(vendaId) {
  const sh = ss_().getSheetByName('Vendas'); const last = sh.getLastRow();
  { const i = linhaDoId_(sh, vendaId);
    if (i > 0) {
      if (sh.getRange(i, 11).getValue() !== 'Recebido') return { ok: false, message: 'Esse pedido não está mais aguardando aceite.' };
      sh.getRange(i, 11).setValue('Em preparo');
      registrarLog('Pedido aceito', sh.getRange(i, 4).getValue(), '');
      return { ok: true, vendas: readVendasResposta_() };
    }
  }
  return { ok: false, message: 'Pedido não encontrado.' };
}
function rejeitarPedido(vendaId, motivo, senhaAdminConfirmacao) {
  return cancelarVenda(vendaId, motivo || 'Pedido rejeitado', senhaAdminConfirmacao, false);
}

/* ---------- ACOMPANHAMENTO PÚBLICO DO PEDIDO (ITEM 2.4) ----------
   Sem login — o "código" é só o final do ID da venda, usado num link que o
   cliente recebe na hora de fazer o pedido. Devolve só o que ele precisa ver. */
function getStatusPedidoPublico(codigo) {
  /* SEGURANÇA: o código público são os 8 últimos caracteres do ID. Exige formato válido (mínimo 8) e limita
     consultas que não acham nada, para ninguém varrer códigos e ler pedidos de outros clientes. */
  const alvo = String(codigo || '').trim().toLowerCase();
  if (!/^[0-9a-f-]{8,36}$/.test(alvo)) return { ok: false, message: 'Código do pedido inválido.' };
  if (excedeuTentativas_('statuspub_falhas', 60)) return { ok: false, message: 'Muitas consultas seguidas. Aguarde alguns minutos.', limite: true };
  /* ITEM 17: o app do cliente consulta a cada 20 s. Resposta guardada por 8 s (só de pedido que existe) e busca
     só nos pedidos recentes; se o pedido for antigo, cai na busca completa de sempre. */
  const emCache = cacheLerJson_('sp_' + alvo);
  if (emCache) return decorarCancelamentoPublico_(emCache);
  let venda = readVendasCauda_(600).find(v => String(v.id).toLowerCase().endsWith(alvo));
  if (!venda) venda = readVendas().find(v => String(v.id).toLowerCase().endsWith(alvo));
  if (!venda) { registrarFalha_('statuspub_falhas'); return { ok: false, message: 'Pedido não encontrado. Confira o código.' }; }
  let itensDoPedido = readItensVendaCauda_(2400).filter(it => it.vendaId === venda.id);
  if (!itensDoPedido.length) itensDoPedido = readItensVenda().filter(it => it.vendaId === venda.id);
  const itens = itensDoPedido.map(it => it.quantidade + 'x ' + it.descricao);
  const primeiroNome = String(venda.clienteNome || '').trim().split(/\s+/)[0] || '';
  const resposta = {
    ok: true,
    status: venda.status, statusPedido: venda.statusPedido, tipoEntrega: venda.tipoEntrega,
    motivoCancelamento: venda.motivoCancelamento || '', clienteNome: primeiroNome,
    itens: itens, valorTotal: venda.valorTotal, data: venda.data, statusPagamento: venda.statusPagamento, numero: venda.numero || 0
  };
  resposta.cancelavelPublico = !!(venda.origem === 'Cardápio' && !venda.mesaId && venda.status === 'Confirmada' && venda.statusPedido === 'Recebido' && venda.statusPagamento === 'A Receber');
  resposta.criadoEm = venda.timestamp || 0;
  cacheGravarJson_('sp_' + alvo, resposta, 8);
  return decorarCancelamentoPublico_(resposta);
}
/* ITEM 3.4 — CANCELAR PEDIDO PELO PRÓPRIO CLIENTE (cardápio comum, sem mesa).
   Só vale enquanto o pedido está "Recebido" (ninguém aceitou ainda) e nos primeiros 3 minutos. O tempo restante é calculado a cada
   resposta (o cache de 8 s guarda só o instante de criação), e criadoEm não sai para o público. */
const CANCELAR_PUBLICO_JANELA_MS_ = 3 * 60 * 1000;
function decorarCancelamentoPublico_(r) {
  const out = Object.assign({}, r);
  const resta = Math.max(0, Math.ceil(((Number(out.criadoEm) || 0) + CANCELAR_PUBLICO_JANELA_MS_ - Date.now()) / 1000));
  out.podeCancelar = !!out.cancelavelPublico && resta > 0;
  out.segundosParaCancelar = out.podeCancelar ? resta : 0;
  delete out.cancelavelPublico; delete out.criadoEm;
  return out;
}
function cancelarPedidoCardapioPublico(codigo) {
  const alvo = String(codigo || '').trim().toLowerCase();
  if (!/^[0-9a-f-]{8,36}$/.test(alvo)) return { ok: false, message: 'Código do pedido inválido.' };
  if (excedeuTentativas_('cancpub_falhas', 30)) return { ok: false, message: 'Muitas tentativas seguidas. Ligue para o restaurante.', limite: true };
  let venda = readVendasCauda_(600).find(v => String(v.id).toLowerCase().endsWith(alvo));
  if (!venda) venda = readVendas().find(v => String(v.id).toLowerCase().endsWith(alvo));
  if (!venda || venda.origem !== 'Cardápio' || venda.mesaId) { registrarFalha_('cancpub_falhas'); return { ok: false, message: 'Pedido não encontrado ou não pode ser cancelado por aqui.' }; }
  // limite por telefone: no máximo 3 cancelamentos a cada 10 minutos
  const chaveTel = 'cancpub_' + String(venda.clienteTelefone || '').replace(/\D/g, '').slice(-11);
  if (excedeuTentativas_(chaveTel, 3)) return { ok: false, message: 'Você já cancelou vários pedidos em pouco tempo. Ligue para o restaurante.', limite: true };
  if (venda.status !== 'Confirmada') return { ok: false, message: 'Esse pedido já está cancelado.' };
  if (venda.statusPedido !== 'Recebido') return { ok: false, message: 'O restaurante já aceitou o pedido. Ligue para o restaurante para alterar.' };
  if (venda.statusPagamento !== 'A Receber') return { ok: false, message: 'Este pedido já tem pagamento registrado. Ligue para o restaurante.' };
  if (Date.now() - (Number(venda.timestamp) || 0) > CANCELAR_PUBLICO_JANELA_MS_) return { ok: false, message: 'O prazo de 3 minutos para cancelar já passou. Ligue para o restaurante.' };
  const sh = ss_().getSheetByName('Vendas'); const i = linhaDoId_(sh, venda.id);
  if (i < 1) return { ok: false, message: 'Pedido não encontrado.' };
  // reconfere na própria linha (outro funcionário pode ter aceitado agora há pouco)
  if (sh.getRange(i, 8).getValue() !== 'Confirmada' || sh.getRange(i, 11).getValue() !== 'Recebido') return { ok: false, message: 'O restaurante acabou de aceitar o pedido. Ligue para o restaurante para alterar.' };
  sh.getRange(i, 8).setValue('Cancelada');
  sh.getRange(i, 9).setValue('Cancelado pelo cliente (cardápio, até 3 min)');
  ajustarEstoquePorVenda(readItensVenda().filter(it => it.vendaId === venda.id), -1, venda.id);
  registrarFalha_(chaveTel, 600000);
  registrarLog('Pedido cancelado pelo cliente (cardápio)', venda.clienteNome || '', 'Pedido ' + (venda.numero || '') + ' | R$ ' + Number(venda.valorTotal || 0).toFixed(2));
  cacheLimpar_('sp_' + alvo);
  return { ok: true, message: 'Pedido cancelado.' };
}
/* ---------- FASE 8B — DESPESAS AVULSAS E MENSAIS (ITENS 48, 49) ----------
   Despesas: colunas H..N = Categoria, Vencimento (texto yyyy-MM-dd), Situação (Paga / A pagar),
   ID Recorrente, Competência (yyyy-MM), Saiu do Caixa (Sim/Não), Criada em.
   Regra: só despesa PAGA e CONFIRMADA entra em caixa, lucro e relatórios. "A pagar" é previsto.
   Despesas mensais geram 1 linha por competência (nunca duplica) e o que já foi gerado nunca
   é alterado por mudança futura na regra: histórico preservado. */
const CATEGORIAS_DESPESA = ['Insumos', 'Aluguel', 'Energia', 'Água', 'Gás', 'Internet/Telefone', 'Salários', 'Impostos', 'Manutenção', 'Marketing', 'Embalagens', 'Outros'];
const PERIODICIDADES_DESPESA = { 'Mensal': 1, 'Bimestral': 2, 'Trimestral': 3, 'Semestral': 6, 'Anual': 12 };
const CABECALHO_DESPESAS_EXTRA = ['Categoria', 'Vencimento', 'Situação', 'ID Recorrente', 'Competência', 'Saiu do Caixa', 'Criada em'];
const CABECALHO_DESPESAS_RECORRENTES = ['ID', 'Descrição', 'Categoria', 'Valor', 'Dia Vencimento', 'Periodicidade', 'Ativa', 'Observação', 'Início', 'Término', 'Criada em'];

function criarDespesasRecorrentes(ss) {
  let sh = ss.getSheetByName('DespesasRecorrentes') || ss.insertSheet('DespesasRecorrentes');
  sh.clear();
  sh.setTabColor('#7c1a15');
  formatarCabecalho(sh, CABECALHO_DESPESAS_RECORRENTES);
  [40,220,140,110,110,120,80,220,90,90,140].forEach((w,i)=>sh.setColumnWidth(i+1,w));
  sh.getRange('D2:D500').setNumberFormat('R$ #,##0.00');
  sh.getRange('I2:J500').setNumberFormat('@');
  sh.getRange('K2:K500').setNumberFormat('dd/MM/yyyy HH:mm');
  sh.getRange('G2:G500').setDataValidation(SpreadsheetApp.newDataValidation().requireValueInList(['Sim', 'Não'], true).setAllowInvalid(false).build());
  sh.getRange('F2:F500').setDataValidation(SpreadsheetApp.newDataValidation().requireValueInList(Object.keys(PERIODICIDADES_DESPESA), true).setAllowInvalid(false).build());
  aplicarZebraELinhas(sh, 11, 500);
  sh.hideColumns(1, 1);
}

/* Rode UMA vez na planilha atual (não apaga nada, pode repetir sem duplicar). */
function prepararFase8Despesas() {
  const ss = ss_();
  const sh = ss.getSheetByName('Despesas');
  if (sh.getMaxColumns() < 14) sh.insertColumnsAfter(sh.getMaxColumns(), 14 - sh.getMaxColumns());
  if (!String(sh.getRange(1, 8).getValue())) {
    sh.getRange(1, 8, 1, 7).setValues([CABECALHO_DESPESAS_EXTRA]);
    sh.getRange(1, 8, 1, 7).setBackground(COR_ESCURO).setFontColor(COR_DOURADO).setFontWeight('bold');
    const last = sh.getLastRow();
    if (last >= 2) {
      const datas = sh.getRange(2, 2, last - 1, 1).getValues();
      const preenchimento = datas.map(d => ['Outros', '', 'Paga', '', '', 'Sim', d[0]]);
      sh.getRange(2, 8, last - 1, 7).setValues(preenchimento);
    }
    sh.getRange('I2:I8000').setNumberFormat('@');
    sh.getRange('L2:L8000').setNumberFormat('@');
    sh.getRange('N2:N8000').setNumberFormat('dd/MM/yyyy HH:mm');
    sh.getRange('J2:J8000').setDataValidation(SpreadsheetApp.newDataValidation().requireValueInList(['Paga', 'A pagar'], true).setAllowInvalid(false).build());
    sh.getRange('M2:M8000').setDataValidation(SpreadsheetApp.newDataValidation().requireValueInList(['Sim', 'Não'], true).setAllowInvalid(false).build());
    [130,100,90,90,100,100,140].forEach((w,i)=>sh.setColumnWidth(i+8,w));
    sh.hideColumns(11, 1);
  }
  if (!ss.getSheetByName('DespesasRecorrentes')) criarDespesasRecorrentes(ss);
  return { ok: true, message: 'Estrutura da Fase 8B pronta.' };
}

function dataISOValida_(s) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(s || ''))) return false;
  const p = String(s).split('-').map(Number);
  const d = new Date(p[0], p[1] - 1, p[2]);
  return d.getFullYear() === p[0] && d.getMonth() === p[1] - 1 && d.getDate() === p[2];
}
function competenciaValida_(s) { return /^\d{4}-(0[1-9]|1[0-2])$/.test(String(s || '')); }
function competenciaAtual_() { return Utilities.formatDate(new Date(), FUSO, 'yyyy-MM'); }

function readDespesas() {
  const sh = ss_().getSheetByName('Despesas'); const last = sh.getLastRow();
  if (last < 2) return [];
  const colunas = Math.min(14, sh.getMaxColumns());
  return sh.getRange(2, 1, last - 1, colunas).getValues().filter(r => r[0]).map(r => ({
    id: r[0], data: Utilities.formatDate(new Date(r[1]), FUSO, 'dd/MM/yyyy HH:mm'), timestamp: new Date(r[1]).getTime(),
    descricao: r[2], valor: numPlanilha_(r[3]) || 0, observacao: r[4], status: r[5], motivoCancelamento: r[6],
    categoria: r[7] || 'Outros', vencimento: String(r[8] || ''), situacao: r[9] === 'A pagar' ? 'A pagar' : 'Paga',
    recorrenteId: r[10] || '', competencia: String(r[11] || ''), saiuDoCaixa: r[12] !== 'Não'
  }));
}
function readDespesasRecorrentes() {
  const sh = ss_().getSheetByName('DespesasRecorrentes'); if (!sh) return [];
  const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 11).getValues().filter(r => r[0]).map(r => ({
    id: r[0], descricao: r[1], categoria: r[2] || 'Outros', valor: numPlanilha_(r[3]) || 0, diaVencimento: numPlanilha_(r[4]) || 1,
    periodicidade: r[5] || 'Mensal', ativa: r[6] !== 'Não', observacao: r[7] || '', inicio: String(r[8] || ''), termino: String(r[9] || '')
  }));
}

function addDespesa(descricao, valor, observacao, categoria, vencimento, situacao, saiuDoCaixa) {
  descricao = String(descricao || '').trim();
  if (!descricao) return { ok: false, message: 'Informe a descrição da despesa.' };
  const v = Math.round((Number(valor) || 0) * 100) / 100;
  if (v <= 0) return { ok: false, message: 'Informe um valor maior que zero.' };
  const ehAdmin = NIVEL_ATUAL === 'Admin';
  // Quem não é Admin só lança despesa PAGA, que saiu do caixa (é o que o operador faz no balcão).
  const sit = ehAdmin && situacao === 'A pagar' ? 'A pagar' : 'Paga';
  const caixa = ehAdmin ? saiuDoCaixa !== false : true;
  const cat = CATEGORIAS_DESPESA.indexOf(categoria) !== -1 ? categoria : 'Outros';
  if (sit === 'A pagar' && !dataISOValida_(vencimento)) return { ok: false, message: 'Informe um vencimento válido para a conta a pagar.' };
  const venc = dataISOValida_(vencimento) ? vencimento : '';
  const quando = sit === 'A pagar' ? new Date(venc + 'T12:00:00') : new Date();
  const sh = ss_().getSheetByName('Despesas');
  sh.appendRow([Utilities.getUuid(), quando, descricao, v, observacao || '', 'Confirmada', '', cat, venc, sit, '', venc ? venc.slice(0, 7) : '', sit === 'Paga' && !caixa ? 'Não' : 'Sim', new Date()]);
  registrarLog(sit === 'A pagar' ? 'Conta a pagar registrada' : 'Despesa registrada', '', descricao + ' [' + cat + '] = R$ ' + v.toFixed(2) + (venc ? ' | vence ' + venc : ''));
  return { ok: true, message: sit === 'A pagar' ? 'Conta a pagar registrada: R$ ' + v.toFixed(2) : 'Despesa registrada: R$ ' + v.toFixed(2), despesas: readDespesas() };
}
function editarDespesa(id, descricao, valor, observacao, categoria, vencimento) {
  descricao = String(descricao || '').trim();
  if (!descricao) return { ok: false, message: 'Informe a descrição da despesa.' };
  const v = Math.round((Number(valor) || 0) * 100) / 100;
  if (v <= 0) return { ok: false, message: 'Informe um valor maior que zero.' };
  const sh = ss_().getSheetByName('Despesas'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() !== id) continue;
    if (sh.getRange(i, 6).getValue() !== 'Confirmada') return { ok: false, message: 'Só é possível editar despesas confirmadas.' };
    const antes = readDespesas().find(d => d.id === id);
    if (antes.categoria === AJUSTE_CATEGORIA_DESPESA_) return { ok: false, message: 'Esta despesa nasceu de um Ajuste pós-venda. Para desfazer, cancele o ajuste em Financeiro → Ajustes pós-venda.' };
    const cat = categoria === undefined ? antes.categoria : (CATEGORIAS_DESPESA.indexOf(categoria) !== -1 ? categoria : 'Outros');
    let venc = antes.vencimento;
    if (vencimento !== undefined && vencimento !== '') {
      if (!dataISOValida_(vencimento)) return { ok: false, message: 'Vencimento inválido.' };
      venc = vencimento;
    }
    if (antes.situacao === 'A pagar' && !venc) return { ok: false, message: 'Conta a pagar precisa de vencimento.' };
    sh.getRange(i, 3, 1, 2).setValues([[descricao, v]]);
    sh.getRange(i, 5).setValue(observacao || '');
    sh.getRange(i, 8).setValue(cat);
    if (venc !== antes.vencimento) {
      sh.getRange(i, 9).setValue(venc);
      if (antes.situacao === 'A pagar') sh.getRange(i, 2).setValue(new Date(venc + 'T12:00:00'));
    }
    registrarLog('Despesa editada', '', descricao + ' | valor R$ ' + antes.valor.toFixed(2) + ' → R$ ' + v.toFixed(2) + (venc !== antes.vencimento ? ' | vencimento ' + antes.vencimento + ' → ' + venc : ''));
    return { ok: true, message: 'Despesa atualizada.', despesas: readDespesas() };
  }
  return { ok: false, message: 'Despesa não encontrada.' };
}
/* Marca uma conta "A pagar" como paga. A data do gasto passa a ser AGORA (é quando o dinheiro saiu).
   Se saiu do caixa, exige caixa aberto — senão o valor ficaria fora de qualquer conferência de caixa. */
function pagarDespesa(id, saiuDoCaixa, valorPago) {
  const sh = ss_().getSheetByName('Despesas'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() !== id) continue;
    const d = readDespesas().find(x => x.id === id);
    if (d.status !== 'Confirmada') return { ok: false, message: 'Essa despesa está cancelada.' };
    if (d.situacao !== 'A pagar') return { ok: false, message: 'Essa despesa já foi paga.' };
    const caixa = saiuDoCaixa === true;
    if (caixa && !readSessaoAberta()) return { ok: false, message: 'Abra o caixa para registrar um pagamento que sai do caixa.' };
    let valor = d.valor;
    if (valorPago !== undefined && valorPago !== null && valorPago !== '') {
      valor = Math.round((Number(valorPago) || 0) * 100) / 100;
      if (valor <= 0) return { ok: false, message: 'Informe um valor pago maior que zero.' };
    }
    sh.getRange(i, 2).setValue(new Date());
    sh.getRange(i, 4).setValue(valor);
    sh.getRange(i, 10).setValue('Paga');
    sh.getRange(i, 13).setValue(caixa ? 'Sim' : 'Não');
    registrarLog('Conta paga', '', d.descricao + ' | previsto R$ ' + d.valor.toFixed(2) + ' | pago R$ ' + valor.toFixed(2) + ' | ' + (caixa ? 'saiu do caixa' : 'fora do caixa'));
    return { ok: true, message: 'Pagamento registrado: R$ ' + valor.toFixed(2), despesas: readDespesas() };
  }
  return { ok: false, message: 'Despesa não encontrada.' };
}


/* =========================================================
   ITEM 2.6 — AJUSTES PÓS-VENDA (reembolso, crédito, cortesia, desconto retroativo)
   A venda original NUNCA muda (continua Confirmada, com o mesmo valor). O ajuste é uma linha própria na aba AjustesPosVenda e aparece no
   DRE como "Ajustes pós-venda". Quando sai dinheiro (reembolso / desconto retroativo) também nasce uma Despesa de categoria
   "Ajuste pós-venda" ligada à venda: é ela que faz o dinheiro do caixa bater no fechamento. No DRE essa categoria fica FORA das despesas
   (a fonte única é a aba de ajustes) — assim o valor não é contado duas vezes. Crédito não entra no resultado quando concedido:
   ele vira desconto na compra futura (e aparece em "Descontos" quando for usado).
   ========================================================= */
const AJUSTES_TIPOS_ = ['Reembolso em dinheiro', 'Crédito para próxima compra', 'Cortesia (item grátis)', 'Desconto retroativo'];
const AJUSTES_MOTIVOS_ = ['Produto errado', 'Item faltando', 'Qualidade do produto', 'Atraso na entrega', 'Cobrança em duplicidade', 'Atendimento', 'Outro'];
const AJUSTES_TIPOS_COM_SAIDA_ = ['Reembolso em dinheiro', 'Desconto retroativo'];
const AJUSTE_CATEGORIA_DESPESA_ = 'Ajuste pós-venda';
const CABECALHO_AJUSTES_ = ['ID', 'Data/Hora', 'Venda ID', 'Pedido nº', 'Cliente', 'Telefone', 'Tipo', 'Valor', 'Motivo', 'Detalhe', 'Saída', 'Despesa ID', 'Status', 'Autorizado por', 'Registrado por', 'Cancelado em', 'Motivo do cancelamento'];
function abaAjustes_() {
  const ss = ss_();
  let sh = ss.getSheetByName('AjustesPosVenda');
  if (!sh) {
    sh = ss.insertSheet('AjustesPosVenda');
    formatarCabecalho(sh, CABECALHO_AJUSTES_);
    sh.setFrozenRows(1); sh.setTabColor('#7c1a15');
    sh.getRange('B2:B8000').setNumberFormat('dd/MM/yyyy HH:mm');
    sh.getRange('H2:H8000').setNumberFormat('R$ #,##0.00');
    sh.getRange('P2:P8000').setNumberFormat('dd/MM/yyyy HH:mm');
  }
  return sh;
}
function readAjustesPosVenda() {
  const sh = abaAjustes_(); const last = sh.getLastRow();
  if (last < 2) return [];
  return sh.getRange(2, 1, last - 1, 17).getValues().filter(r => r[0]).map(r => ({
    id: r[0], data: Utilities.formatDate(new Date(r[1]), FUSO, 'dd/MM/yyyy HH:mm'), timestamp: new Date(r[1]).getTime(),
    vendaId: r[2], numero: numPlanilha_(r[3]) || 0, clienteNome: r[4], clienteTelefone: String(r[5] || ''), tipo: r[6], valor: numPlanilha_(r[7]) || 0,
    motivo: r[8], detalhe: r[9], saida: r[10], despesaId: r[11] || '', status: r[12] === 'Cancelado' ? 'Cancelado' : 'Ativo',
    autorizadoPor: r[13], registradoPor: r[14], motivoCancelamento: r[16] || ''
  }));
}
function registrarAjustePosVenda(vendaId, tipo, valor, motivo, detalhe, saidaPedida, senhaAdminConfirmacao) {
  if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta.' };
  if (AJUSTES_TIPOS_.indexOf(tipo) === -1) return { ok: false, message: 'Escolha o tipo de ajuste.' };
  if (AJUSTES_MOTIVOS_.indexOf(motivo) === -1) return { ok: false, message: 'Escolha o motivo do ajuste.' };
  detalhe = String(detalhe || '').trim().slice(0, 200);
  if (motivo === 'Outro' && !detalhe) return { ok: false, message: 'Descreva o motivo (campo "Detalhe") quando escolher "Outro".' };
  const v = Math.round((Number(valor) || 0) * 100) / 100;
  if (!(v > 0)) return { ok: false, message: 'Informe um valor maior que zero.' };
  const venda = readVendas().find(x => x.id === vendaId);
  if (!venda) return { ok: false, message: 'Venda não encontrada.' };
  if (venda.status !== 'Confirmada') return { ok: false, message: 'Só dá para ajustar venda confirmada. Venda cancelada já foi tratada no cancelamento.' };
  if (venda.statusPedido && ['Entregue', 'Retirada', 'Servida'].indexOf(venda.statusPedido) === -1) return { ok: false, message: 'O pedido ainda está "' + venda.statusPedido + '". Antes de terminar, use Editar ou Cancelar. Ajuste pós-venda é para pedido já entregue.' };
  const comSaida = AJUSTES_TIPOS_COM_SAIDA_.indexOf(tipo) !== -1;
  if (comSaida && venda.statusPagamento !== 'Pago') return { ok: false, message: 'Esta venda ainda não foi paga — não há o que devolver. Use Editar ou Cancelar.' };
  const total = Number(venda.valorTotal) || 0;
  if (v > total + 0.001) return { ok: false, message: 'O ajuste (R$ ' + v.toFixed(2) + ') não pode ser maior que o valor da venda (R$ ' + total.toFixed(2) + ').' };
  const ativos = readAjustesPosVenda().filter(a => a.vendaId === vendaId && a.status === 'Ativo');
  if (comSaida) {
    const jaDevolvido = ativos.filter(a => AJUSTES_TIPOS_COM_SAIDA_.indexOf(a.tipo) !== -1).reduce((t, a) => t + a.valor, 0);
    if (jaDevolvido + v > total + 0.001) return { ok: false, message: 'Já foram devolvidos R$ ' + jaDevolvido.toFixed(2) + ' desta venda. Com este ajuste passaria do valor da venda (R$ ' + total.toFixed(2) + ').' };
  }
  return gravarAjustePosVenda_(venda, tipo, v, motivo, detalhe, comSaida, saidaPedida);
}
function gravarAjustePosVenda_(venda, tipo, v, motivo, detalhe, comSaida, saidaPedida) {
  const saida = comSaida ? (saidaPedida === 'Do caixa' ? 'Do caixa' : 'Fora do caixa') : 'Sem saída de dinheiro';
  if (saida === 'Do caixa' && !readSessaoAberta()) return { ok: false, message: 'Abra o caixa para registrar uma devolução que sai do caixa (ou escolha "Fora do caixa").' };
  const sh = abaAjustes_();
  const id = Utilities.getUuid(); let despesaId = '';
  if (comSaida) {
    despesaId = Utilities.getUuid();
    ss_().getSheetByName('Despesas').appendRow([despesaId, new Date(), 'Ajuste pós-venda: ' + tipo + ' — pedido ' + (venda.numero ? 'nº ' + venda.numero : String(venda.id).slice(-8)), v,
      'Venda ' + String(venda.id).slice(-8) + ' | ' + motivo + (detalhe ? ' — ' + detalhe : ''), 'Confirmada', '', AJUSTE_CATEGORIA_DESPESA_, '', 'Paga', '', '', saida === 'Do caixa' ? 'Sim' : 'Não', new Date()]);
  }
  sh.appendRow([id, new Date(), venda.id, venda.numero || '', venda.clienteNome || '', venda.clienteTelefone || '', tipo, v, motivo, detalhe, saida, despesaId, 'Ativo', AUTORIZADOR_ATUAL || USUARIO_ATUAL || '', USUARIO_ATUAL || '', '', '']);
  registrarLog('Ajuste pós-venda registrado', venda.clienteTelefone || '', tipo + ' R$ ' + v.toFixed(2) + ' | pedido ' + (venda.numero || String(venda.id).slice(-8)) + ' | ' + motivo + (detalhe ? ' — ' + detalhe : '') + ' | ' + saida);
  return { ok: true, message: 'Ajuste registrado: ' + tipo + ' de R$ ' + v.toFixed(2) + '.', ajustesPosVenda: readAjustesPosVenda(), despesas: readDespesas() };
}
function cancelarAjustePosVenda(id, motivo, senhaAdminConfirmacao) {
  if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta.' };
  motivo = String(motivo || '').trim().slice(0, 200);
  if (!motivo) return { ok: false, message: 'Informe o motivo do cancelamento do ajuste.' };
  const sh = abaAjustes_(); const i = linhaDoId_(sh, id);
  if (i < 1) return { ok: false, message: 'Ajuste não encontrado.' };
  const a = readAjustesPosVenda().find(x => x.id === id);
  if (!a || a.status === 'Cancelado') return { ok: false, message: 'Este ajuste já está cancelado.' };
  if (a.saida === 'Do caixa') {
    const sessao = readSessaoAberta();
    if (!sessao || a.timestamp < sessao.aberturaTimestamp) return { ok: false, message: 'Esta devolução saiu do caixa de um turno que já foi fechado. Não dá para desfazer sem mexer na conferência daquele dia — registre a diferença como ajuste/despesa nova e fale com o contador.' };
  }
  sh.getRange(i, 13).setValue('Cancelado'); sh.getRange(i, 16).setValue(new Date()); sh.getRange(i, 17).setValue(motivo);
  if (a.despesaId) {
    const shD = ss_().getSheetByName('Despesas'); const j = linhaDoId_(shD, a.despesaId);
    if (j > 0) { shD.getRange(j, 6).setValue('Cancelada'); shD.getRange(j, 7).setValue('Ajuste pós-venda cancelado: ' + motivo); }
  }
  registrarLog('Ajuste pós-venda cancelado', a.clienteTelefone || '', a.tipo + ' R$ ' + a.valor.toFixed(2) + ' | pedido ' + (a.numero || String(a.vendaId).slice(-8)) + ' | ' + motivo);
  return { ok: true, message: 'Ajuste cancelado.', ajustesPosVenda: readAjustesPosVenda(), despesas: readDespesas() };
}

/* ----- despesas mensais ----- */
function validarRecorrente_(d) {
  if (!String(d.descricao || '').trim()) return 'Informe a descrição.';
  if ((Number(d.valor) || 0) <= 0) return 'Informe um valor maior que zero.';
  const dia = Number(d.diaVencimento);
  if (!(dia >= 1 && dia <= 31) || Math.floor(dia) !== dia) return 'O dia do vencimento deve ser de 1 a 31.';
  if (!PERIODICIDADES_DESPESA[d.periodicidade]) return 'Periodicidade inválida.';
  if (!competenciaValida_(d.inicio)) return 'Informe o mês de início.';
  if (d.termino && (!competenciaValida_(d.termino) || d.termino < d.inicio)) return 'O término deve ser um mês igual ou depois do início.';
  return '';
}
function addDespesaRecorrente(descricao, categoria, valor, diaVencimento, periodicidade, observacao, inicio, termino) {
  const d = { descricao: String(descricao || '').trim(), valor: valor, diaVencimento: diaVencimento, periodicidade: periodicidade || 'Mensal', inicio: inicio || competenciaAtual_(), termino: termino || '' };
  const erro = validarRecorrente_(d);
  if (erro) return { ok: false, message: erro };
  if (nomeJaExiste_(readDespesasRecorrentes().filter(x => x.ativa), d.descricao, 'descricao')) return { ok: false, message: 'Já existe uma despesa mensal ativa com essa descrição.' };
  const cat = CATEGORIAS_DESPESA.indexOf(categoria) !== -1 ? categoria : 'Outros';
  const id = Utilities.getUuid();
  ss_().getSheetByName('DespesasRecorrentes').appendRow([id, d.descricao, cat, Math.round(Number(valor) * 100) / 100, Number(diaVencimento), d.periodicidade, 'Sim', observacao || '', d.inicio, d.termino, new Date()]);
  registrarLog('Despesa mensal cadastrada', '', d.descricao + ' = R$ ' + Number(valor).toFixed(2) + ' (' + d.periodicidade + ', dia ' + diaVencimento + ')');
  const geradas = gerarDespesasRecorrentes_(competenciaAtual_());
  return { ok: true, message: 'Despesa mensal cadastrada.' + (geradas ? ' ' + geradas + ' conta(s) gerada(s) neste mês.' : ''), despesasRecorrentes: readDespesasRecorrentes(), despesas: readDespesas() };
}
/* Mudança vale só para competências AINDA NÃO geradas; contas já geradas ficam como estão (histórico). */
function editarDespesaRecorrente(id, descricao, categoria, valor, diaVencimento, periodicidade, observacao, inicio, termino, ativa) {
  const sh = ss_().getSheetByName('DespesasRecorrentes'); const last = sh.getLastRow();
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() !== id) continue;
    const a = readDespesasRecorrentes().find(x => x.id === id);
    const d = { descricao: String(descricao || '').trim(), valor: valor, diaVencimento: diaVencimento, periodicidade: periodicidade, inicio: inicio || a.inicio, termino: termino === undefined ? a.termino : termino };
    const erro = validarRecorrente_(d);
    if (erro) return { ok: false, message: erro };
    const cat = CATEGORIAS_DESPESA.indexOf(categoria) !== -1 ? categoria : a.categoria;
    sh.getRange(i, 2, 1, 3).setValues([[d.descricao, cat, Math.round(Number(valor) * 100) / 100]]);
    sh.getRange(i, 5, 1, 2).setValues([[Number(diaVencimento), d.periodicidade]]);
    if (ativa !== undefined) sh.getRange(i, 7).setValue(ativa === false ? 'Não' : 'Sim');
    sh.getRange(i, 8).setValue(observacao || '');
    sh.getRange(i, 9, 1, 2).setValues([[d.inicio, d.termino || '']]);
    const mudou = [];
    if (a.valor !== Number(valor)) mudou.push('valor R$ ' + a.valor.toFixed(2) + ' → R$ ' + Number(valor).toFixed(2));
    if (a.diaVencimento !== Number(diaVencimento)) mudou.push('dia ' + a.diaVencimento + ' → ' + diaVencimento);
    if (a.periodicidade !== d.periodicidade) mudou.push(a.periodicidade + ' → ' + d.periodicidade);
    if (ativa !== undefined && a.ativa !== (ativa !== false)) mudou.push(ativa === false ? 'desativada' : 'reativada');
    registrarLog('Despesa mensal editada', '', d.descricao + (mudou.length ? ' | ' + mudou.join(' | ') : ''));
    const geradas = gerarDespesasRecorrentes_(competenciaAtual_());
    return { ok: true, message: 'Despesa mensal atualizada.' + (geradas ? ' ' + geradas + ' conta(s) gerada(s) neste mês.' : ''), despesasRecorrentes: readDespesasRecorrentes(), despesas: readDespesas() };
  }
  return { ok: false, message: 'Despesa mensal não encontrada.' };
}
/* Gera a conta "A pagar" da competência (yyyy-MM) para cada despesa mensal ativa que cai nela.
   Idempotente: se já existe linha (paga, a pagar OU cancelada) daquela regra/competência, não gera outra. */
function gerarDespesasRecorrentes_(competencia) {
  const regras = readDespesasRecorrentes().filter(r => r.ativa && r.inicio && r.inicio <= competencia && (!r.termino || competencia <= r.termino));
  if (!regras.length) return 0;
  const existentes = {};
  readDespesas().forEach(d => { if (d.recorrenteId) existentes[d.recorrenteId + '|' + d.competencia] = true; });
  const partes = competencia.split('-').map(Number);
  const diasNoMes = new Date(partes[0], partes[1], 0).getDate();
  const sh = ss_().getSheetByName('Despesas');
  let geradas = 0;
  regras.forEach(r => {
    const pi = r.inicio.split('-').map(Number);
    const meses = (partes[0] * 12 + partes[1]) - (pi[0] * 12 + pi[1]);
    if (meses < 0 || meses % PERIODICIDADES_DESPESA[r.periodicidade] !== 0) return;
    if (existentes[r.id + '|' + competencia]) return;
    const dia = Math.min(r.diaVencimento, diasNoMes);
    const venc = competencia + '-' + (dia < 10 ? '0' : '') + dia;
    sh.appendRow([Utilities.getUuid(), new Date(venc + 'T12:00:00'), r.descricao, r.valor, r.observacao, 'Confirmada', '', r.categoria, venc, 'A pagar', r.id, competencia, 'Não', new Date()]);
    geradas++;
  });
  if (geradas) registrarLog('Despesas mensais geradas', '', competencia + ': ' + geradas + ' conta(s)');
  return geradas;
}
/* Chamada barata: só trabalha 1x por mês (guarda a última competência gerada). */
function garantirDespesasDoMes_(forcar) {
  const comp = competenciaAtual_();
  const props = PropertiesService.getScriptProperties();
  if (!forcar && props.getProperty('ULTIMA_GERACAO_DESPESAS') === comp) return 0;
  const n = gerarDespesasRecorrentes_(comp);
  props.setProperty('ULTIMA_GERACAO_DESPESAS', comp);
  return n;
}
function gerarDespesasMes() {
  const n = garantirDespesasDoMes_(true);
  return { ok: true, message: n ? n + ' conta(s) gerada(s) para este mês.' : 'Nenhuma conta nova: este mês já está gerado.', despesas: readDespesas() };
}
/* Gatilho diário (1h): garante que o mês novo abra com as contas previstas mesmo se ninguém abrir o sistema. */
function tarefaDespesasMensais() {
  const lock = LockService.getScriptLock();
  lock.waitLock(10000);
  try { if (garantirDespesasDoMes_(false)) bumpVersoes_('trigger'); } finally { lock.releaseLock(); }
}
function configurarGeracaoDespesasMensal() {
  ScriptApp.getProjectTriggers().filter(t => t.getHandlerFunction() === 'tarefaDespesasMensais').forEach(t => ScriptApp.deleteTrigger(t));
  ScriptApp.newTrigger('tarefaDespesasMensais').timeBased().everyDays(1).atHour(1).create();
  return { ok: true, message: 'Geração automática mensal ativada.' };
}

function cancelarDespesa(id, motivo, senhaAdminConfirmacao) {
  if (!exigeConfirmacaoAdmin(senhaAdminConfirmacao)) return { ok: false, message: 'Senha de administrador incorreta.' };
  if (!motivo) return { ok: false, message: 'Informe o motivo do cancelamento.' };
  const sh = ss_().getSheetByName('Despesas'); const last = sh.getLastRow();
  { const alvoD = readDespesas().find(d => d.id === id); if (alvoD && alvoD.categoria === AJUSTE_CATEGORIA_DESPESA_) return { ok: false, message: 'Esta despesa nasceu de um Ajuste pós-venda. Para desfazer, cancele o ajuste em Financeiro → Ajustes pós-venda.' }; }
  for (let i = 2; i <= last; i++) {
    if (sh.getRange(i, 1).getValue() === id) { sh.getRange(i, 6).setValue('Cancelada'); sh.getRange(i, 7).setValue(motivo); registrarLog('Despesa cancelada', '', motivo); break; }
  }
  return { ok: true, despesas: readDespesas() };
}

/* =========================================================
   PARTE — BACKUP E RECUPERAÇÃO (Etapa 21)
   ========================================================= */
/* =========================================================
   FASE 10 — ARMAZENAMENTO, BACKUP E RECUPERAÇÃO (ITENS 71–77)
   ========================================================= */
const BACKUP_RETENCAO_DIAS = 7;
const BACKUP_MAX_TENTATIVAS = 3;
const BACKUP_FREQUENCIAS = ['12h', 'diaria', 'semanal'];
/* Abas que a restauração NUNCA sobrescreve: evita trancar o admin para fora
   (Usuários) e apagar o rastro do próprio incidente (Auditoria/Log/Backups). */
const ABAS_PRESERVADAS_RESTAURACAO = ['Usuários', 'Auditoria', 'Log', 'Backups'];
const ARMAZ_ATENCAO_PCT = 70, ARMAZ_CRITICO_PCT = 90;

function abaBackups_() {
  const ss = ss_();
  let sh = ss.getSheetByName('Backups');
  if (!sh) {
    sh = ss.insertSheet('Backups');
    sh.appendRow(['ID', 'Data/Hora', 'Tipo', 'Status', 'Arquivo', 'ArquivoId', 'Tamanho (bytes)', 'Tentativas', 'Erro', 'Usuário']);
    sh.setFrozenRows(1); sh.setTabColor('#5a5a5a');
  }
  if (sh.getMaxColumns() < 11) sh.insertColumnsAfter(sh.getMaxColumns(), 11 - sh.getMaxColumns());
  if (sh.getRange(1, 11).getValue() !== 'Cópia contingência') sh.getRange(1, 11).setValue('Cópia contingência');
  return sh;
}
function obterPastaBackups_() {
  const props = PropertiesService.getScriptProperties();
  const folderId = props.getProperty('PASTA_BACKUPS_ID');
  if (folderId) { try { return DriveApp.getFolderById(folderId); } catch (e) { /* pasta apagada, recria abaixo */ } }
  const raiz = DriveApp.getRootFolder();
  const existentes = raiz.getFoldersByName('Texas Burger - Backups');
  const pasta = existentes.hasNext() ? existentes.next() : raiz.createFolder('Texas Burger - Backups');
  props.setProperty('PASTA_BACKUPS_ID', pasta.getId());
  return pasta;
}
/* Google Sheets nativo devolve getSize()=0; o tamanho real é medido pela exportação xlsx (aproximado). */
function tamanhoAproximadoPlanilha_(fileId) {
  try {
    const r = UrlFetchApp.fetch('https://docs.google.com/spreadsheets/d/' + fileId + '/export?format=xlsx',
      { headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() }, muteHttpExceptions: true });
    return r.getResponseCode() === 200 ? r.getBlob().getBytes().length : 0;
  } catch (e) { return 0; }
}
function obterArmazenamentoDrive_() {
  const usado = DriveApp.getStorageUsed(), limite = DriveApp.getStorageLimit();
  const pct = limite > 0 ? Math.round(usado / limite * 1000) / 10 : null;
  const nivel = pct === null ? 'Indisponível' : pct > ARMAZ_CRITICO_PCT ? 'Crítico' : pct >= ARMAZ_ATENCAO_PCT ? 'Atenção' : 'Normal';
  return { usado: usado, limite: limite, livre: limite > 0 ? Math.max(0, limite - usado) : null, percentual: pct, nivel: nivel };
}
/* ---------- ITEM 16: cópia do backup na conta da contingência ---------- */
function exportarXlsxBase64_(fileId) {
  const r = UrlFetchApp.fetch('https://docs.google.com/spreadsheets/d/' + fileId + '/export?format=xlsx',
    { headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() }, muteHttpExceptions: true });
  if (r.getResponseCode() !== 200) throw new Error('Exportação do backup falhou (HTTP ' + r.getResponseCode() + ').');
  const bytes = r.getBlob().getBytes();
  if (bytes.length > 15 * 1024 * 1024) throw new Error('Backup grande demais para copiar (' + Math.round(bytes.length / 1048576) + ' MB; máximo 15 MB).');
  return Utilities.base64Encode(bytes);
}
function marcarCopiaBackup_(backupId, texto) {
  try {
    const sh = abaBackups_(); const last = sh.getLastRow(); if (last < 2) return;
    const ids = sh.getRange(2, 1, last - 1, 1).getValues();
    for (let i = ids.length - 1; i >= 0; i--) { if (ids[i][0] === backupId) { sh.getRange(i + 2, 11).setValue(texto); return; } }
  } catch (e) {}
}
/* Nunca lança erro: se falhar, o backup local continua valendo; só registra e avisa. */
function copiarBackupParaContingencia_(arquivoId, nome, backupId) {
  const props = PropertiesService.getScriptProperties();
  try {
    const r = chamarContingencia_('guardarBackup', { nome: nome, base64: exportarXlsxBase64_(arquivoId) });
    if (!r || !r.ok) throw new Error((r && r.message) || 'A contingência recusou a cópia.');
    marcarCopiaBackup_(backupId, 'Sim');
    props.deleteProperty('ULTIMA_FALHA_COPIA_BACKUP');
    registrarLog('Cópia do backup guardada na contingência', '', nome);
    return { ok: true };
  } catch (e) {
    const msg = String(e && e.message || e).slice(0, 200);
    marcarCopiaBackup_(backupId, 'Falha: ' + msg);
    props.setProperty('ULTIMA_FALHA_COPIA_BACKUP', JSON.stringify({ quando: new Date().toISOString(), erro: msg }));
    registrarLog('Falha ao copiar backup para a contingência', '', msg);
    return { ok: false, message: msg };
  }
}
/* Núcleo do backup: retry, histórico na aba Backups e falha SEMPRE registrada (ITEM 73). */
function executarBackup_(tipo) {
  const sh = abaBackups_();
  const id = Utilities.getUuid();
  const props = PropertiesService.getScriptProperties();
  let ultimoErro = '', tentativas = 0;
  for (let t = 1; t <= BACKUP_MAX_TENTATIVAS; t++) {
    tentativas = t;
    try {
      const arm = obterArmazenamentoDrive_();
      if (arm.percentual !== null && arm.percentual >= 99) { ultimoErro = 'Google Drive sem espaço livre (' + arm.percentual + '% usado).'; break; }
      const pasta = obterPastaBackups_();
      const nome = 'Backup Texas Burger - ' + Utilities.formatDate(new Date(), FUSO, 'yyyy-MM-dd HH-mm-ss') + (tipo === 'Pré-restauração' ? ' (pré-restauração)' : '');
      const copia = DriveApp.getFileById(ss_().getId()).makeCopy(nome, pasta);
      const tamanho = tamanhoAproximadoPlanilha_(copia.getId()) || copia.getSize();
      sh.appendRow([id, new Date(), tipo, 'Sucesso', nome, copia.getId(), tamanho, t, '', USUARIO_ATUAL || 'sistema']);
      props.setProperty('ULTIMO_BACKUP', new Date().toISOString());
      try { salvarConfigChave_('ULTIMO_BACKUP_INFO', JSON.stringify({ quando: new Date().toISOString(), tipo: tipo, arquivo: nome, arquivoId: copia.getId(), tamanho: tamanho, usuario: USUARIO_ATUAL || 'sistema' })); } catch (eCfg) {} // BLOCO 4.4: cópia do último sucesso fora da aba Backups
      if (tipo === 'Automático') props.setProperty('ULTIMO_BACKUP_AUTO', new Date().toISOString());
      props.deleteProperty('ULTIMA_FALHA_BACKUP');
      const limite = new Date(); limite.setDate(limite.getDate() - BACKUP_RETENCAO_DIAS);
      const arquivos = pasta.getFiles();
      while (arquivos.hasNext()) { const f = arquivos.next(); if (f.getId() !== copia.getId() && f.getDateCreated() < limite) { try { f.setTrashed(true); } catch (e) {} } }
      registrarLog('Backup criado', '', tipo + ': ' + nome);
      let msgCopia = '';
      if (tipo !== 'Pré-restauração') { // a de segurança da restauração fica só local, para não atrasar o restaurar
        const rc = copiarBackupParaContingencia_(copia.getId(), nome, id);
        msgCopia = rc.ok ? ' Cópia guardada também na contingência.' : ' ⚠️ A cópia na contingência falhou: ' + rc.message;
      }
      return { ok: true, message: 'Backup criado: ' + nome + '.' + msgCopia, ultimoBackup: new Date().toISOString(), id: id, arquivoId: copia.getId() };
    } catch (e) {
      ultimoErro = String(e && e.message || e);
      if (t < BACKUP_MAX_TENTATIVAS) Utilities.sleep(2000 * t);
    }
  }
  sh.appendRow([id, new Date(), tipo, 'Falha', '', '', 0, tentativas, ultimoErro, USUARIO_ATUAL || 'sistema']);
  props.setProperty('ULTIMA_FALHA_BACKUP', JSON.stringify({ quando: new Date().toISOString(), tipo: tipo, erro: ultimoErro }));
  registrarLog('Falha no backup', '', tipo + ' após ' + tentativas + ' tentativa(s): ' + ultimoErro);
  return { ok: false, message: 'Backup falhou após ' + tentativas + ' tentativa(s): ' + ultimoErro };
}
/* Gatilho do backup automático (nome mantido: o gatilho antigo continua válido). */
function criarBackupDiario() {
  if (String(lerConfigChave_('BACKUP_AUTO_ATIVO', 'Sim')) === 'Não') return;
  executarBackup_('Automático');
}
function aplicarBackupAutomatico_(ativo, frequencia, hora) {
  ScriptApp.getProjectTriggers().forEach(t => { if (t.getHandlerFunction() === 'criarBackupDiario') ScriptApp.deleteTrigger(t); });
  if (ativo) {
    let b = ScriptApp.newTrigger('criarBackupDiario').timeBased();
    if (frequencia === '12h') b = b.everyHours(12);
    else if (frequencia === 'semanal') b = b.onWeekDay(ScriptApp.WeekDay.MONDAY).atHour(hora);
    else b = b.everyDays(1).atHour(hora);
    b.create();
  }
  salvarConfigChave_('BACKUP_AUTO_ATIVO', ativo ? 'Sim' : 'Não');
  salvarConfigChave_('BACKUP_FREQ', frequencia);
  salvarConfigChave_('BACKUP_HORA', hora);
}
/* Compatível com o uso antigo (rodar uma vez no editor). */
function configurarBackupAutomatico() {
  aplicarBackupAutomatico_(true, 'diaria', 4);
  return 'Backup automático configurado — diário, por volta das 4h, guardando os últimos ' + BACKUP_RETENCAO_DIAS + ' dias.';
}
function configurarBackupAutomaticoApp(ativo, frequencia, hora) {
  const freq = String(frequencia || 'diaria'), h = Number(hora);
  if (BACKUP_FREQUENCIAS.indexOf(freq) === -1) return { ok: false, message: 'Frequência inválida.' };
  if (!(h >= 0 && h <= 23) || h % 1 !== 0) return { ok: false, message: 'Hora inválida (0 a 23).' };
  aplicarBackupAutomatico_(!!ativo, freq, h);
  registrarLog('Backup automático configurado', '', (ativo ? 'ativo, ' + freq + ', ' + h + 'h' : 'desativado'));
  return Object.assign({ message: ativo ? 'Backup automático ativado.' : 'Backup automático desativado.' }, obterStatusBackup());
}
function proximoBackup_(ativo, freq, hora) {
  if (!ativo) return null;
  const agoraD = new Date();
  if (freq === '12h') {
    const ult = PropertiesService.getScriptProperties().getProperty('ULTIMO_BACKUP_AUTO');
    const prox = new Date((ult ? new Date(ult) : agoraD).getTime() + 12 * 3600000);
    return (prox < agoraD ? agoraD : prox).toISOString();
  }
  const ymd = Utilities.formatDate(agoraD, FUSO, 'yyyy-MM-dd');
  let cand = Utilities.parseDate(ymd + ' ' + ('0' + hora).slice(-2) + ':00', FUSO, 'yyyy-MM-dd HH:mm');
  for (let i = 0; i < 9; i++) {
    if (cand > agoraD && (freq !== 'semanal' || Utilities.formatDate(cand, FUSO, 'u') === '1')) break;
    cand = new Date(cand.getTime() + 86400000);
  }
  return cand.toISOString();
}
function obterStatusBackup() {
  const props = PropertiesService.getScriptProperties();
  const temTrigger = ScriptApp.getProjectTriggers().some(t => t.getHandlerFunction() === 'criarBackupDiario');
  const ativo = temTrigger && String(lerConfigChave_('BACKUP_AUTO_ATIVO', 'Sim')) !== 'Não';
  const freq = String(lerConfigChave_('BACKUP_FREQ', 'diaria'));
  const hora = Number(lerConfigChave_('BACKUP_HORA', 4));
  const sh = abaBackups_(); const last = sh.getLastRow();
  const linhas = last < 2 ? [] : sh.getRange(Math.max(2, last - 29), 1, Math.min(30, last - 1), 11).getValues();
  const historico = linhas.reverse().map(r => ({
    id: r[0], quando: r[1] instanceof Date ? r[1].toISOString() : String(r[1]), tipo: r[2], status: r[3],
    arquivo: r[4], arquivoId: r[5], tamanho: numPlanilha_(r[6]) || 0, tentativas: numPlanilha_(r[7]) || 0, erro: r[8], usuario: r[9], copia: r[10] || ''
  }));
  const falhaRaw = props.getProperty('ULTIMA_FALHA_BACKUP');
  // O "último backup" sai do próprio histórico (aba Backups): assim a tela nunca mostra um backup que não aparece na lista.
  let ultimoSucesso = historico.find(h => h.status === 'Sucesso');
  let ultimoPelaCopia = false;
  if (!ultimoSucesso) { // BLOCO 4.4: aba Backups vazia/corrompida -> usa a cópia guardada em Configurações
    try {
      const c = JSON.parse(String(lerConfigChave_('ULTIMO_BACKUP_INFO', '') || '{}'));
      if (c && c.quando) { ultimoSucesso = { quando: c.quando, tipo: c.tipo, status: 'Sucesso', arquivo: c.arquivo, arquivoId: c.arquivoId, tamanho: c.tamanho || 0, usuario: c.usuario }; ultimoPelaCopia = true; }
    } catch (eC) {}
  }
  return {
    ok: true, ultimoBackup: ultimoSucesso ? ultimoSucesso.quando : null, ultimoBackupPelaCopia: ultimoPelaCopia, automaticoAtivo: ativo,
    frequencia: freq, hora: hora, proximoBackup: proximoBackup_(ativo, freq, hora),
    retencaoDias: BACKUP_RETENCAO_DIAS, ultimaFalha: falhaRaw ? JSON.parse(falhaRaw) : null, historico: historico,
    ultimaFalhaCopia: (function () { try { const x = props.getProperty('ULTIMA_FALHA_COPIA_BACKUP'); return x ? JSON.parse(x) : null; } catch (e) { return null; } })()
  };
}
function fazerBackupManual_() { return executarBackup_('Manual'); }

/* ---------- RESTAURAÇÃO (ITEM 74) ----------
   Exige: perfil Admin (permissão da ação) + senha de Admin SEMPRE (mesmo logado como Admin)
   + palavra RESTAURAR + backup existente no histórico com status Sucesso. Antes de tocar em
   qualquer dado, cria um backup de segurança; se ele falhar, a restauração é cancelada. */
function restaurarBackup(backupId, senhaAdmin, confirmacao) {
  if (confirmacao !== 'RESTAURAR') return { ok: false, message: 'Confirmação incorreta. Digite RESTAURAR.' };
  if (!verificarAdmin(senhaAdmin)) return { ok: false, message: 'Senha de administrador incorreta.' };
  const sh = abaBackups_(); const last = sh.getLastRow(); let arquivoId = '', nomeArq = '';
  for (let i = 2; i <= last; i++) {
    const r = sh.getRange(i, 1, 1, 6).getValues()[0];
    if (r[0] === backupId && r[3] === 'Sucesso') { nomeArq = r[4]; arquivoId = r[5]; break; }
  }
  if (!arquivoId) return { ok: false, message: 'Backup não encontrado no histórico (ou não foi concluído com sucesso).' };
  let origem;
  try {
    const f = DriveApp.getFileById(arquivoId);
    if (f.isTrashed()) return { ok: false, message: 'O arquivo deste backup foi apagado do Drive (retenção de ' + BACKUP_RETENCAO_DIAS + ' dias).' };
    origem = SpreadsheetApp.openById(arquivoId);
  } catch (e) { return { ok: false, message: 'Não foi possível abrir o arquivo do backup: ' + e.message }; }
  ligarManutencao_('Restauração de backup ' + nomeArq);  // ITEM 2.8: bloqueia os demais perfis ANTES do backup de segurança (para ele refletir o estado real)
  try { return restaurarBackupAplicar_(origem, nomeArq); } finally { desligarManutencao_(); }
}
function restaurarBackupAplicar_(origem, nomeArq) {
  const seguranca = executarBackup_('Pré-restauração');
  if (!seguranca.ok) return { ok: false, message: 'Restauração cancelada: não foi possível criar o backup de segurança. ' + seguranca.message };
  const destino = ss_(); const restauradas = [], puladas = [];
  try {
    origem.getSheets().forEach(shO => {
      const nome = shO.getName();
      const shD = destino.getSheetByName(nome);
      if (ABAS_PRESERVADAS_RESTAURACAO.indexOf(nome) !== -1 || !shD) { puladas.push(nome); return; }
      const vals = shO.getDataRange().getValues();
      shD.clearContents();
      if (shO.getLastRow() === 0 || !vals.length || !vals[0].length) { restauradas.push(nome); return; }
      if (shD.getMaxRows() < vals.length) shD.insertRowsAfter(shD.getMaxRows(), vals.length - shD.getMaxRows());
      if (shD.getMaxColumns() < vals[0].length) shD.insertColumnsAfter(shD.getMaxColumns(), vals[0].length - shD.getMaxColumns());
      shD.getRange(1, 1, vals.length, vals[0].length).setValues(vals);
      restauradas.push(nome);
    });
    SpreadsheetApp.flush();
  } catch (e) {
    registrarLog('Falha na restauração de backup', '', nomeArq + ': ' + e.message + ' | backup de segurança: ' + seguranca.arquivoId);
    return { ok: false, message: 'A restauração parou no meio (' + e.message + '). Um backup de segurança foi feito antes; peça ajuda para reverter.' };
  }
  registrarLog('Backup restaurado', '', nomeArq + ' | abas: ' + restauradas.length + ' | preservadas/puladas: ' + puladas.join(', '));
  return { ok: true, message: 'Backup restaurado (' + restauradas.length + ' abas). Recarregue o app para ver os dados.', restauradas: restauradas, puladas: puladas };
}

/* ---------- ITEM 18: espaço da conta da contingência ---------- */
function obterArmazenamentoContingencia() {
  try {
    const r = chamarContingencia_('getArmazenamento');
    if (!r || !r.ok) return { ok: false, message: (r && r.message) || 'A contingência não respondeu.' };
    return r;
  } catch (e) { return { ok: false, message: 'Não foi possível falar com a contingência: ' + e.message }; }
}

/* ---------- GOOGLE DRIVE / ARQUIVOS (ITENS 75–77) ---------- */
function obterArmazenamento() {
  const arm = obterArmazenamentoDrive_();
  const cats = { 'Imagens de produtos': { qtd: 0, bytes: 0 }, 'Imagens de combos': { qtd: 0, bytes: 0 }, 'Outras imagens': { qtd: 0, bytes: 0 },
                 'Arquivos de backup': { qtd: 0, bytes: 0 }, 'Arquivos do sistema': { qtd: 1, bytes: 0 } };
  const fotosProd = {}, fotosCombo = {};
  const shP = ss_().getSheetByName('Produtos'), shC = ss_().getSheetByName('Combos');
  if (shP && shP.getLastRow() > 1) shP.getRange(2, 6, shP.getLastRow() - 1, 1).getValues().forEach(r => { if (r[0]) fotosProd[r[0]] = true; });
  if (shC && shC.getLastRow() > 1) shC.getRange(2, 5, shC.getLastRow() - 1, 1).getValues().forEach(r => { if (r[0]) fotosCombo[r[0]] = true; });
  const arquivos = [];
  const varrer = (pasta, categoriaFn, limite) => {
    const it = pasta.getFiles(); let n = 0;
    while (it.hasNext() && n++ < limite) {
      const f = it.next(); const c = categoriaFn(f); const b = f.getSize();
      cats[c].qtd++; cats[c].bytes += b;
      arquivos.push({ nome: f.getName(), categoria: c, tamanho: b, criadoEm: f.getDateCreated().toISOString() });
    }
  };
  try { varrer(obterPastaFotos_(), f => fotosProd[f.getId()] ? 'Imagens de produtos' : fotosCombo[f.getId()] ? 'Imagens de combos' : 'Outras imagens', 500); } catch (e) {}
  try { varrer(obterPastaBackups_(), () => 'Arquivos de backup', 200); } catch (e) {}
  const bk = abaBackups_(); const lb = bk.getLastRow();
  if (lb > 1) { // Sheets nativo não informa tamanho no Drive: soma o tamanho registrado no histórico dos backups ainda existentes
    const ids = {};
    bk.getRange(2, 4, lb - 1, 4).getValues().forEach(r => { if (r[0] === 'Sucesso' && r[2]) ids[r[2]] = numPlanilha_(r[3]) || 0; });
    let soma = 0; const it = obterPastaBackups_().getFiles(); while (it.hasNext()) { const f = it.next(); soma += ids[f.getId()] || 0; }
    if (soma > cats['Arquivos de backup'].bytes) cats['Arquivos de backup'].bytes = soma;
  }
  try { const ssf = DriveApp.getFileById(ss_().getId()); cats['Arquivos do sistema'].bytes = tamanhoAproximadoPlanilha_(ss_().getId()) || ssf.getSize();
        arquivos.push({ nome: ssf.getName() + ' (planilha principal)', categoria: 'Arquivos do sistema', tamanho: cats['Arquivos do sistema'].bytes, criadoEm: ssf.getDateCreated().toISOString() }); } catch (e) {}
  arquivos.sort((a, b) => b.tamanho - a.tamanho);
  return { ok: true, drive: arm, categorias: cats, arquivos: arquivos.slice(0, 30), totalArquivos: arquivos.length };
}

/* =========================================================
   FASE 11 — CACHE, SINCRONIZAÇÃO E CONTINGÊNCIA (ITENS 78–82)
   ========================================================= */
/* ---------- CONTROLE DE VERSÃO (ITEM 80 / FASE 11C) ----------
   Cada registro editável sai do servidor com uma "versão" (_v) = impressão digital do conteúdo. Ao editar, o app devolve a
   versão que estava vendo; se outra pessoa mudou o registro no meio tempo, a edição é RECUSADA (em vez de sobrescrever em silêncio)
   e o app se atualiza. Sem mudar nenhuma aba: a versão é calculada, não gravada. */
function versaoDe_(obj) {
  const bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.MD5, JSON.stringify(obj), Utilities.Charset.UTF_8);
  return bytes.map(b => ('0' + (b & 255).toString(16)).slice(-2)).join('').slice(0, 12);
}
function nomeJaExiste_(lista, nome, campo) {
  const alvo = String(nome || '').trim().toLowerCase();
  return (lista || []).some(x => String(x[campo || 'nome'] || '').trim().toLowerCase() === alvo);
}
/* mapa: lista no resultado -> como calcular a versão de cada item (com o que mais pertence a ele) */
let _memoVersao = null;
/* ITEM 2.3 — versão de VENDA = impressão digital de (status + valores + itens). Só vendas ainda editáveis ganham versão;
   as demais saem sem _v (o app então não manda versaoEsperada e as travas normais do editarVenda continuam valendo). */
let _memoIV = null;
function itensDaVendaParaVersao_(vendaId) {
  if (!_memoIV) { _memoIV = {}; readItensVenda().forEach(it => { (_memoIV[it.vendaId] = _memoIV[it.vendaId] || []).push(it); }); }
  return _memoIV[vendaId] || [];
}
function versaoVenda_(v) {
  if (!v || v.status !== 'Confirmada' || v.fechamentoEntregaId || (v.statusPedido && v.statusPedido !== 'Recebido' && v.statusPedido !== 'Em preparo')) return '';
  const itens = itensDaVendaParaVersao_(v.id).map(it => [it.produtoId || '', it.comboId || '', it.descricao, it.quantidade, it.valorUnitario]);
  return versaoDe_([v.status, v.statusPedido, v.valorTotal, v.valorOriginal, v.valorDesconto, v.formaPagamento, v.statusPagamento, v.tipoEntrega, itens]);
}
function memoVersao_() {
  if (!_memoVersao) _memoVersao = { pp: readProdutoPrecos(), pi: readProdutoIngredientes(), pa: readProdutoAdicionais(), cp: readComboPrecos(), ci: readComboItens() };
  return _memoVersao;
}
const VERSIONADAS = {
  produtos:            { edita: 'editarProduto',           ler: () => readProdutos(),           v: p => { const m = memoVersao_(); return versaoDe_([p, m.pp.filter(x => x.produtoId === p.id), m.pi.filter(x => x.produtoId === p.id), m.pa.filter(x => x.produtoId === p.id)]); } },
  combos:              { edita: 'editarCombo',             ler: () => readCombos(),             v: c => { const m = memoVersao_(); return versaoDe_([c, m.cp.filter(x => x.comboId === c.id), m.ci.filter(x => x.comboId === c.id)]); } },
  adicionais:          { edita: 'editarAdicional',         ler: () => readAdicionais(),         v: a => versaoDe_(a) },
  formasPagamento:     { edita: 'editarFormaPagamento',    ler: () => readFormasPagamento(),    v: f => versaoDe_(f) },
  categorias:          { edita: 'editarCategoria',         ler: () => readCategorias(),         v: c => versaoDe_(c) },
  despesas:            { edita: 'editarDespesa',           ler: () => readDespesas(),           v: d => versaoDe_(d) },
  despesasRecorrentes: { edita: 'editarDespesaRecorrente', ler: () => readDespesasRecorrentes(), v: d => versaoDe_(d) },
  clientes:            { edita: 'salvarCliente',           ler: () => readClientes(),           v: c => versaoDe_(c) },
  // ITEM 2.3: só Admin/Operador editam vendas — para os demais perfis nem calcula (poupa leitura de planilha).
  // BLOCO 4.1: usuários (edita por loginAlvo), cupons e eventos. Mesas não têm ação de edição de campos (só status/exclusão), então ficam de fora.
  usuarios:            { edita: 'editarUsuario',          ler: () => readUsuarios(),           v: u => versaoDe_(u), campoBody: 'loginAlvo', campoItem: 'login' },
  cupons:              { edita: 'editarCupom',            ler: () => readCupons(),             v: c => versaoDe_(c) },
  eventos:             { edita: 'salvarEvento',           ler: () => readEventos(),            v: e => versaoDe_(e) },
  vendas:              { edita: 'editarVenda',             ler: () => readVendas(),             v: x => versaoVenda_(x), ativa: () => NIVEL_ATUAL === 'Admin' || NIVEL_ATUAL === 'Operador' }
};
/* coloca _v em cada item das listas versionadas que aparecem numa resposta (getAll e respostas de edição) */
function anexarVersoes_(resultado) {
  if (!resultado || typeof resultado !== 'object') return resultado;
  _memoVersao = null;
  // ITEM 2.3: se a própria resposta já traz os itens das vendas, reaproveita (evita reler a aba ItensVenda)
  _memoIV = null;
  if (Array.isArray(resultado.itensVenda) && Array.isArray(resultado.vendas)) { _memoIV = {}; resultado.itensVenda.forEach(it => { (_memoIV[it.vendaId] = _memoIV[it.vendaId] || []).push(it); }); }
  Object.keys(VERSIONADAS).forEach(k => {
    if (VERSIONADAS[k].ativa && !VERSIONADAS[k].ativa()) return;
    if (Array.isArray(resultado[k]) && resultado[k].length && resultado[k][0] && typeof resultado[k][0] === 'object' && (resultado[k][0].id || (VERSIONADAS[k].campoItem && resultado[k][0][VERSIONADAS[k].campoItem]))) {
      resultado[k] = resultado[k].map(x => Object.assign({}, x, { _v: VERSIONADAS[k].v(x) }));
    }
  });
  return resultado;
}
/* devolve texto de conflito se a versão que o app viu já não é a atual; '' se pode seguir */
function conflitoDeVersao_(action, body) {
  const chave = Object.keys(VERSIONADAS).find(k => VERSIONADAS[k].edita === action);
  if (!chave) return '';
  const cB = VERSIONADAS[chave].campoBody || 'id', cI = VERSIONADAS[chave].campoItem || 'id'; // BLOCO 4.1: usuário é identificado por login
  if (!body.versaoEsperada || !body[cB]) return '';
  _memoVersao = null; _memoIV = null;
  const atual = VERSIONADAS[chave].ler().find(x => String(x[cI]).toLowerCase() === String(body[cB]).toLowerCase());
  if (!atual) return 'Este registro não existe mais (alguém o excluiu). A tela foi atualizada.';
  if (VERSIONADAS[chave].v(atual) !== String(body.versaoEsperada)) return 'Este registro foi alterado por outra pessoa enquanto você o editava. Atualizamos a tela — confira os dados e faça a alteração de novo.';
  return '';
}

/* Operações que não podem se repetir. O app manda `requisicaoId`; o backend guarda a chave na aba
   Requisicoes SÓ quando a operação deu certo, e devolve "duplicado" nas repetições. */
const ACOES_IDEMPOTENTES = ['addSangria', 'registrarEntradaEstoque', 'registrarPerdaEstoque', 'registrarInventarioEstoque',
  'addOrStampFidelidade', 'resgatarPremioFidelidade', 'fecharContaMesa', 'cancelarVenda', 'editarVenda', 'addFeedback',
  'addDespesa', 'pagarDespesa', 'registrarAjustePosVenda', 'cancelarAjustePosVenda', 'abrirCaixa', 'fecharCaixa', 'salvarCliente', 'rejeitarPedido', 'editarStatusFeedback', 'registrarOcorrencia',
  'toggleResgateIndicacao']; // toggle: dois toques seguidos não desfazem o resgate
const REQUISICOES_MAX_LINHAS = 5000, REQUISICOES_PODA = 1000;

function abaRequisicoes_() {
  const ss = ss_();
  let sh = ss.getSheetByName('Requisicoes');
  if (!sh) {
    sh = ss.insertSheet('Requisicoes');
    sh.appendRow(['Chave', 'Ação', 'Resultado', 'Usuário', 'Data/Hora']);
    sh.setFrozenRows(1); sh.setTabColor('#5a5a5a');
  }
  return sh;
}
function requisicaoBuscar_(chave) {
  const cache = CacheService.getScriptCache();
  const c = cache.get('idem_' + chave);
  if (c) return { resultado: c };
  const sh = abaRequisicoes_(); const last = sh.getLastRow();
  if (last < 2) return null;
  const achou = sh.getRange(2, 1, last - 1, 1).createTextFinder(chave).matchEntireCell(true).matchCase(true).findNext();
  if (!achou) return null;
  const resultado = String(sh.getRange(achou.getRow(), 3).getValue() || '');
  cache.put('idem_' + chave, resultado || '-', 21600);
  return { resultado: resultado };
}
function requisicaoRegistrar_(chave, acao, resultado) {
  const sh = abaRequisicoes_();
  const res = String(resultado || '').slice(0, 200);
  sh.appendRow([chave, acao, res, USUARIO_ATUAL || '', new Date()]);
  CacheService.getScriptCache().put('idem_' + chave, res || '-', 21600);
  const last = sh.getLastRow();
  if (last > REQUISICOES_MAX_LINHAS) sh.deleteRows(2, REQUISICOES_PODA); // poda as mais antigas (ordem de gravação)
}

/* ---------- CONFERÊNCIA DE INTEGRIDADE / RECONCILIAÇÃO (ITEM 82) ----------
   Só lê e aponta divergências — nunca corrige sozinha. */
function conferirIntegridade() {
  const problemas = [];
  const add = (gravidade, tipo, ref, detalhe) => problemas.push({ gravidade: gravidade, tipo: tipo, ref: ref, detalhe: detalhe });
  const vendas = readVendas().filter(v => v.status === 'Confirmada');
  const itens = readItensVenda(), pags = readPagamentosVenda();
  const itensPorVenda = {}, pagPorVenda = {};
  itens.forEach(i => { itensPorVenda[i.vendaId] = (itensPorVenda[i.vendaId] || 0) + 1; });
  pags.forEach(p => { pagPorVenda[p.vendaId] = (pagPorVenda[p.vendaId] || 0) + Number(p.valor); });
  vendas.forEach(v => {
    const ref = v.id.slice(0, 8) + ' (' + v.data + ')';
    if (!itensPorVenda[v.id]) add('Alta', 'Venda sem itens', ref, 'Total R$ ' + Number(v.valorTotal).toFixed(2));
    if (v.statusPagamento !== 'A Receber') {
      const soma = Math.round((pagPorVenda[v.id] || 0) * 100) / 100, total = Math.round(Number(v.valorTotal) * 100) / 100;
      if (!pagPorVenda[v.id]) add('Alta', 'Venda paga sem pagamento registrado', ref, 'Total R$ ' + total.toFixed(2));
      else if (Math.abs(soma - total) > 0.01) add('Alta', 'Pagamentos diferentes do total', ref, 'Total R$ ' + total.toFixed(2) + ' × pagamentos R$ ' + soma.toFixed(2));
    }
  });
  const ordenadas = vendas.slice().sort((a, b) => a.timestamp - b.timestamp);
  for (let i = 1; i < ordenadas.length; i++) {
    const a = ordenadas[i - 1], b = ordenadas[i];
    if (b.clienteTelefone && a.clienteTelefone === b.clienteTelefone && Number(a.valorTotal) === Number(b.valorTotal) && (b.timestamp - a.timestamp) < 120000)
      add('Média', 'Possível venda duplicada', b.id.slice(0, 8) + ' (' + b.data + ')', 'Mesmo cliente e valor R$ ' + Number(b.valorTotal).toFixed(2) + ' em menos de 2 min');
  }
  readEstoque().filter(e => e.ativo && Number(e.quantidade) < 0).forEach(e => add('Média', 'Estoque negativo', e.nome, 'Saldo ' + e.quantidade + ' ' + e.unidade));
  const agoraMs = Date.now();
  readSessoesCaixa().filter(s => s.status === 'Aberto' && agoraMs - s.aberturaTimestamp > 24 * 3600000)
    .forEach(s => add('Média', 'Caixa aberto há mais de 24h', s.id.slice(0, 8), 'Aberto em ' + s.abertura + ' por ' + s.usuarioAbertura));
  readSessoesCaixa().filter(s => s.status === 'Fechado' && s.diferenca !== null && Math.abs(s.diferenca) >= 0.01)
    .slice(0, 10).forEach(s => add('Baixa', 'Diferença no fechamento do caixa', s.fechamento, (s.diferenca > 0 ? 'Sobra' : 'Falta') + ' de R$ ' + Math.abs(s.diferenca).toFixed(2)));
  let contingencia = null;
  try { const r = chamarContingencia_('listarPendentes'); if (r && r.ok) { contingencia = (r.pendentes || []).length; if (contingencia) add('Média', 'Vendas aguardando na contingência', String(contingencia), 'Use "Trazer vendas pendentes" no Armazenamento'); } } catch (e) { /* contingência fora do ar: não é erro desta conferência */ }
  const ordem = { Alta: 0, 'Média': 1, Baixa: 2 };
  problemas.sort((a, b) => ordem[a.gravidade] - ordem[b.gravidade]);
  registrarLog('Conferência de integridade', '', problemas.length + ' divergência(s) em ' + vendas.length + ' venda(s)');
  return { ok: true, problemas: problemas.slice(0, 100), total: problemas.length, vendasConferidas: vendas.length, pendentesContingencia: contingencia };
}

/* Reconciliação automática da contingência (gatilho de tempo, fora do doPost → precisa do próprio lock). */
function reconciliarContingenciaAuto() {
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(25000)) return;
  try {
    USUARIO_ATUAL = 'sistema'; NIVEL_ATUAL = ''; AUTORIZADOR_ATUAL = '';
    const r = chamarContingencia_('listarPendentes');
    if (!r || !r.ok || !(r.pendentes || []).length) return;
    reconciliarContingencia();
    bumpVersoes_('trigger');
  } catch (e) { registrarLog('Falha na reconciliação automática', '', e.message); }
  finally { lock.releaseLock(); }
}

/* ---------- CONTINGÊNCIA — SINCRONIZAÇÃO E RECONCILIAÇÃO (Item 81) ---------- */
function chamarContingencia_(action, extra) {
  const payload = Object.assign({ chave: chaveContingencia_('CONTINGENCIA_CHAVE_SERVIDOR'), action: action }, extra || {});
  const resp = UrlFetchApp.fetch(CONTINGENCIA_API_URL, {
    method: 'post', contentType: 'application/json', payload: JSON.stringify(payload), muteHttpExceptions: true
  });
  return JSON.parse(resp.getContentText());
}

/* ---------- ITEM 17: cópia das fotos na conta da contingência ---------- */
/* Envia só as fotos que a contingência ainda não tem. Para quando passar do tempo (limiteMs) e continua na próxima sincronização. */
function sincronizarFotosContingencia_(limiteMs) {
  const inicio = Date.now();
  const res = { ok: false, mapa: {}, enviadas: 0, faltam: 0, falhas: [], removidas: 0, totalFotos: 0 };
  const ids = {};
  readProdutos().forEach(p => { if (p.fotoId) ids[p.fotoId] = true; });
  readCombos().forEach(c => { if (c.fotoId) ids[c.fotoId] = true; });
  const lista = Object.keys(ids);
  res.totalFotos = lista.length;
  const l = chamarContingencia_('listarFotos');
  if (!l || !l.ok) { res.falhas.push((l && l.message) || 'listarFotos falhou'); return res; }
  res.mapa = l.fotos || {};
  const faltando = lista.filter(id => !res.mapa[id]);
  for (let i = 0; i < faltando.length; i++) {
    if (Date.now() - inicio > limiteMs) { res.faltam = faltando.length - i; break; }
    const id = faltando[i];
    try {
      const bytes = DriveApp.getFileById(id).getBlob().getBytes();
      if (bytes.length > 5 * 1024 * 1024) { res.falhas.push(id + ': maior que 5 MB'); continue; }
      const r = chamarContingencia_('guardarFoto', { idOrigem: id, base64: Utilities.base64Encode(bytes) });
      if (r && r.ok) { res.mapa[id] = r.fotoIdReserva; res.enviadas++; }
      else res.falhas.push(id + ': ' + ((r && r.message) || 'recusada'));
    } catch (e) { res.falhas.push(id + ': ' + e.message); }
  }
  if (!res.faltam && !res.falhas.length && lista.length) { // só limpa órfãs quando tudo está em dia
    try { const rm = chamarContingencia_('removerFotosOrfas', { ids: lista }); if (rm && rm.ok) res.removidas = rm.removidas || 0; } catch (e) {}
  }
  res.ok = true;
  return res;
}
/* Rode UMA vez no editor para a primeira carga (sem o limite de tempo do app): menu de funções -> copiarFotosParaContingenciaAgora -> Executar. */
function copiarFotosParaContingenciaAgora() {
  const r = sincronizarFotosContingencia_(280000);
  Logger.log(JSON.stringify({ enviadas: r.enviadas, faltam: r.faltam, falhas: r.falhas, totalFotos: r.totalFotos }));
  return r.enviadas + ' foto(s) copiada(s); faltam ' + r.faltam + '; ' + r.falhas.length + ' falha(s).';
}

/* Empurra pra contingência tudo que ela precisa pra manter o Cardápio Digital
   e uma versão simples do Caixa funcionando: catálogo, preços, clientes,
   config do banner. NÃO manda vendas/financeiro — isso não é o papel dela. */
function sincronizarContingencia(e) {
  const limiteFotosMs = (e && e.triggerUid) ? 240000 : 20000; // gatilho das 3h tem tempo de sobra; clique no app, não
  let fotos = { mapa: {}, enviadas: 0, faltam: 0, falhas: [], totalFotos: 0 };
  try { fotos = sincronizarFotosContingencia_(limiteFotosMs); } catch (eF) { registrarLog('Falha ao copiar fotos para a contingência', '', eF.message); }
  const reserva = id => (id && fotos.mapa[id]) || '';
  const formas = readFormasPagamento();
  const dados = {
    /* PUBLICO: o que o Cardapio precisa e nada alem (sem custos, sem taxas, sem clientes) */
    publico: {
      categorias: readCategorias(),
      produtos: readProdutos().map(p => ({ id: p.id, nome: p.nome, descricao: p.descricao, categoria: p.categoria, ativo: p.ativo, fotoUrl: p.fotoUrl, fotoReservaId: reserva(p.fotoId), destaque: p.destaque, ordemCardapio: p.ordemCardapio })),
      produtoPrecos: readProdutoPrecos().map(p => ({ produtoId: p.produtoId, formaPagamentoId: p.formaPagamentoId, preco: p.preco })),
      combos: readCombos().map(c => ({ id: c.id, nome: c.nome, categoria: c.categoria, ativo: c.ativo, fotoUrl: c.fotoUrl, fotoReservaId: reserva(c.fotoId), destaque: c.destaque, ordemCardapio: c.ordemCardapio })),
      comboPrecos: readComboPrecos().map(p => ({ comboId: p.comboId, formaPagamentoId: p.formaPagamentoId, preco: p.preco })),
      adicionais: readAdicionais().map(a => ({ id: a.id, nome: a.nome, preco: a.preco, ativo: a.ativo })),
      produtoAdicionais: readProdutoAdicionais(),
      comboItens: readComboItens().map(ci => ({ comboId: ci.comboId, produtoId: ci.produtoId })),
      formasPagamento: formas.map(f => ({ id: f.id, nome: f.nome, ativa: f.ativa, visivelCardapio: f.visivelCardapio, permiteTroco: f.permiteTroco, ordem: f.ordem })),
      configCardapio: Object.assign({}, readConfigCardapio(), { taxaEntrega: readConfigEntrega().taxaPadrao })
    },
    /* INTERNO: so sai com a chave interna (entregue a quem fez login) */
    interno: {
      clientes: readClientesResposta_().map(c => ({ id: c.id, nome: c.nome, telefone: c.telefone })),
      formasPagamentoCompleto: formas
    }
  };
  try {
    const r = chamarContingencia_('atualizarEspelho', { dados: dados });
    const notaFotos = ' Fotos: ' + fotos.enviadas + ' copiada(s) agora' + (fotos.faltam ? ', faltam ' + fotos.faltam + ' (sincronize de novo ou aguarde às 3h)' : '') + (fotos.falhas.length ? ', ' + fotos.falhas.length + ' com falha (veja o Log)' : '') + '.';
    if (r) r.message = ((r.message || '') + notaFotos).trim();
    if (fotos.falhas.length) registrarLog('Fotos que não foram para a contingência', '', fotos.falhas.slice(0, 5).join(' | '));
    registrarLog('Contingência sincronizada', '', (r && r.message) || '');
    return r;
  } catch (e) {
    registrarLog('Falha ao sincronizar contingência', '', e.message);
    return { ok: false, message: 'Não foi possível falar com a API de contingência: ' + e.message };
  }
}

function garantirTriggerContingenciaDiario() {
  const jaTem = ScriptApp.getProjectTriggers().some(t => t.getHandlerFunction() === 'sincronizarContingencia');
  if (!jaTem) ScriptApp.newTrigger('sincronizarContingencia').timeBased().everyDays(1).atHour(3).create();
  const jaTemRec = ScriptApp.getProjectTriggers().some(t => t.getHandlerFunction() === 'reconciliarContingenciaAuto');
  if (!jaTemRec) ScriptApp.newTrigger('reconciliarContingenciaAuto').timeBased().everyMinutes(30).create();
  return { ok: true, message: 'Automático ativado: espelho sincronizado todo dia às 3h e vendas da contingência trazidas a cada 30 min.' };
}

/* Busca o que ficou pendente na fila da contingência (vendas feitas enquanto
   esta planilha estava fora do ar) e reaplica aqui — sem duplicar mesmo que
   essa função rode mais de uma vez (Item 79). */
function reconciliarContingencia() {
  const resultado = { reaplicadas: 0, jaEstavam: 0, ajustadasEmSessaoFechada: 0, falhas: [] };
  let resposta;
  try {
    resposta = chamarContingencia_('listarPendentes');
  } catch (e) {
    return { ok: false, message: 'Não foi possível falar com a API de contingência: ' + e.message };
  }
  if (!resposta.ok) return { ok: false, message: resposta.message || 'A contingência recusou a chamada.' };

  const shReconciliada = ss_().getSheetByName('ContingenciaReconciliada');
  const jaFeitas = new Set();
  const lastR = shReconciliada.getLastRow();
  for (let i = 2; i <= lastR; i++) { const idFila = shReconciliada.getRange(i, 1).getValue(); if (idFila) jaFeitas.add(idFila); }

  (resposta.pendentes || []).forEach(item => {
    if (jaFeitas.has(item.id)) { resultado.jaEstavam++; try { chamarContingencia_('marcarSincronizado', { id: item.id }); } catch (e) {} return; }
    if (item.tipo !== 'venda') { resultado.falhas.push(item.id + ': tipo desconhecido (' + item.tipo + ')'); return; }
    if (item.corrompido || !item.dados || !item.dados.itens) { resultado.falhas.push(item.id + ': dados ilegíveis na fila'); return; }
    try {
      const d = sanitizarEntrada_(item.dados, '', 0); // os dados da fila vieram de fora e não passaram pelo doPost: neutraliza fórmulas aqui também
      /* FASE 9 / 11D: sem desconto, preço sempre conferido, idempotente. Venda do Caixa reaproveita o id da tentativa original:
         se a principal chegou a gravá-la antes de cair, a reconciliação reconhece e NÃO duplica. */
      const ehCaixa = d.origem === 'Caixa';
      /* BLOCO 1.1: a hora original só vale em venda do Caixa e se for coerente com o momento em que a fila a recebeu (até 15 min antes). */
      let opcoesVenda = null;
      if (ehCaixa && d.timestampOriginal) {
        const tsO = Number(d.timestampOriginal), recMs = item.recebidoEm ? new Date(item.recebidoEm).getTime() : NaN;
        if (Number.isFinite(tsO) && Number.isFinite(recMs) && tsO <= recMs + 60000 && tsO >= recMs - 15 * 60000) opcoesVenda = { timestampOriginal: tsO };
        else registrarLog('Hora original ignorada na reconciliação', '', item.id + ': fora do intervalo aceito; usada a hora da reconciliação');
      }
      const r = iniciarVenda(d.itens, d.clienteNome, d.clienteTelefone, d.pagamentos, d.tipoEntrega, d.dadosEntrega, d.statusPagamento, null, '', ehCaixa ? 'Contingência (Caixa)' : 'Cardápio', '', (ehCaixa && d.requisicaoOriginal) ? String(d.requisicaoOriginal).slice(0, 80) : 'cont-' + item.id, null, opcoesVenda);
      if (r && r.ok) {
        shReconciliada.appendRow([item.id, r.id, new Date()]);
        if (d.emergenciaOperador && !r.duplicado) { // BLOCO 1.3: venda feita em modo emergência (aparelho sem sessão na planilha) fica rastreada
          try { registrarAuditoria_('Venda de emergência reconciliada', 'Operador ' + String(d.emergenciaOperador).slice(0, 40) + ' vendeu em modo emergência | venda ' + String(r.id).slice(0, 8) + ' | R$ ' + (Number(r.valorTotal) || 0).toFixed(2) + ' | fila ' + item.id); } catch (eAu) {}
        }
        chamarContingencia_('marcarSincronizado', { id: item.id });
        resultado.reaplicadas++;
        if (r.timestampAplicado && !r.duplicado) { // BLOCO 1.1: hora original caiu numa sessão já fechada -> ajusta saldo e diferença daquela sessão
          try { if (ajustarSessaoFechadaPorReconciliacao_(r.timestampAplicado, Number(r.valorTotal) || 0, dinheiroDaVendaContingencia_(d))) resultado.ajustadasEmSessaoFechada++; }
          catch (eAj) { registrarLog('Falha ao ajustar sessão fechada na reconciliação', '', item.id + ': ' + eAj.message); }
        }
      } else {
        resultado.falhas.push(item.id + ': ' + (r ? r.message : 'sem retorno'));
      }
    } catch (e) {
      resultado.falhas.push(item.id + ': ' + e.message);
    }
  });
  registrarLog('Reconciliação da contingência executada', '', resultado.reaplicadas + ' reaplicadas, ' + resultado.jaEstavam + ' já feitas, ' + resultado.falhas.length + ' falhas, ' + resultado.ajustadasEmSessaoFechada + ' somada(s) a caixa já fechado.');
  return { ok: true, message: resultado.reaplicadas + ' venda(s) reaplicada(s), ' + resultado.jaEstavam + ' já estavam sincronizadas' + (resultado.falhas.length ? ', ' + resultado.falhas.length + ' com falha (veja o log).' : '.'), detalhes: resultado };
}

/* As chaves da contingência (CONTINGENCIA_CHAVE_SERVIDOR e CONTINGENCIA_CHAVE_INTERNA) ficam SOMENTE nas Propriedades do script
   (Configurações do projeto -> Propriedades do script). Nunca escreva chave no código. Para trocar: rotacionarChavesSensiveis() no projeto da contingência. */
