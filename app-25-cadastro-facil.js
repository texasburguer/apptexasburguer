/* ============================================================
   CADASTRO FÁCIL — produto em 3 tipos, receita rápida, ingrediente simples, preços em lote, bebidas separadas, aviso.
   - "Preparado aqui": receita (busca por digitação, criar ingrediente na hora, copiar de outro produto). Custo = receita.
   - "Comprado pronto": estoque próprio (bebidas etc.). Custo = "paguei R$ X por N unidades".
   - "Sem controle": custo digitado.
   A receita guarda a quantidade na unidade do ingrediente (kg, l, un); a tela pede gramas/ml quando o ingrediente é kg/l.
   O banco recalcula o custo dos produtos e combos sozinho quando o preço de um ingrediente muda (gatilhos no Supabase).
   ============================================================ */
var CF_TIPO_ = { p:'receita', pp:'receita' };
var _cfEsc_ = { p:null, pp:null };
var _cfEstAba_ = 'ing';
var _cfLote_ = {};
var _cfEeUnAntes_ = '';
const CF_UN_NOME_ = { un:'unidades', kg:'kg', g:'gramas', l:'litros', ml:'ml' };
const CF_AJUDA_TIPO_ = {
  receita: 'Lanches, porções e tudo que é montado aqui. O custo sai da receita e se atualiza sozinho.',
  pronto: 'Bebidas e itens que você compra prontos. Cada venda baixa 1 do estoque e o custo sai do que você pagou.',
  manual: 'Sem receita e sem estoque. Digite o custo se souber.'
};

function cfNum_(v){ const n = Number(String(v == null ? '' : v).replace(',', '.')); return isFinite(n) ? n : 0; }
function cfVal_(id){ const el = document.getElementById(id); return el ? el.value : ''; }
function cfSet_(id, v){ const el = document.getElementById(id); if(el) el.value = (v == null ? '' : v); }
function cfNorm_(s){ return String(s || '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim(); }
function cfMoeda4_(n){ return 'R$ ' + (Number(n) || 0).toLocaleString('pt-BR', { minimumFractionDigits:2, maximumFractionDigits:4 }); }
function cfQtdTxt_(n){ return (Math.round((Number(n) || 0) * 1000) / 1000).toLocaleString('pt-BR', { maximumFractionDigits:3 }); }
function cfIngr_(id){ return (estoque || []).find(e => e.id === id); }
function cfEhBebida_(estoqueId){ return (produtos || []).some(p => p.estoqueProprioIngredienteId === estoqueId); }
function cfFatorUso_(un){ return (un === 'kg' || un === 'l') ? 1000 : 1; }
function cfUnUso_(un){ return un === 'kg' ? 'g' : (un === 'l' ? 'ml' : (un || 'un')); }
function cfFator_(de, para){
  de = de || 'un'; para = para || 'un';
  if(de === para) return 1;
  const m = { 'kg>g':1000, 'g>kg':0.001, 'l>ml':1000, 'ml>l':0.001 };
  return m[de + '>' + para] || null;
}
function cfLista_(pre){ return pre === 'p' ? ingredientesProdutoNovo : ingredientesProdutoEdicao; }
function cfSetLista_(pre, v){ if(pre === 'p') ingredientesProdutoNovo = v; else ingredientesProdutoEdicao = v; }
function cfUsos_(estoqueId){
  const nomes = [];
  (produtoIngredientes || []).forEach(v => {
    if(v.ingredienteId !== estoqueId) return;
    const p = (produtos || []).find(x => x.id === v.produtoId);
    if(p && p.estoqueProprioIngredienteId !== estoqueId && nomes.indexOf(p.nome) === -1) nomes.push(p.nome);
  });
  return nomes;
}

/* ---------- TIPO DO PRODUTO ---------- */
function cfSetTipo(pre, t){
  if(pre === 'pp'){
    const p = (produtos || []).find(x => x.id === produtoEditandoId);
    if(p && p.estoqueProprioIngredienteId && t !== 'pronto'){ showMsg('ppMsg', 'Este produto tem estoque próprio, então continua como "Comprado pronto".', 'warn'); t = 'pronto'; }
  }
  CF_TIPO_[pre] = t;
  document.querySelectorAll('#' + pre + 'TipoBotoes [data-tipo]').forEach(b => b.classList.toggle('active', b.dataset.tipo === t));
  const aj = document.getElementById(pre + 'TipoAjuda'); if(aj) aj.textContent = CF_AJUDA_TIPO_[t] || '';
  const sr = document.getElementById(pre + 'SecReceita'), sp = document.getElementById(pre + 'SecPronto');
  if(sr) sr.style.display = t === 'receita' ? '' : 'none';
  if(sp) sp.style.display = t === 'pronto' ? '' : 'none';
  const chk = document.getElementById(pre + 'EstoqueProprioAtivo');
  if(chk){ chk.checked = (t === 'pronto'); toggleEstoqueProprioUI(pre); }
  cfAtualizarCusto(pre);
  if(pre === 'p') cfAdicionaisNovo_();
}
/* ADICIONAIS do produto novo: já vêm marcados os que a maioria dos produtos da mesma categoria tem.
   "Comprado pronto" (bebida/item pronto) vem sem nenhum. Se a pessoa mexer nos quadradinhos, vale a escolha dela. */
let _cfAdTocado_ = false;
function cfAdicionaisSugeridos_(categoria){
  const prods = (produtos || []).filter(p => p.categoria === categoria && p.ativo !== false && !p.estoqueProprioIngredienteId);
  if(!categoria || !prods.length) return [];
  const ids = {}; prods.forEach(p => { ids[p.id] = 1; });
  const cont = {};
  (produtoAdicionais || []).forEach(pa => { if(ids[pa.produtoId]) cont[pa.adicionalId] = (cont[pa.adicionalId] || 0) + 1; });
  const ativos = {}; (adicionais || []).forEach(a => { if(a.ativo !== false) ativos[a.id] = 1; });
  return Object.keys(cont).filter(id => ativos[id] && cont[id] * 2 >= prods.length);
}
function cfAdicionaisNovo_(){
  const nota = document.getElementById('pAdicionaisNota');
  if(_cfAdTocado_) return;
  const cat = (document.getElementById('pCategoria') || {}).value || '';
  const pronto = CF_TIPO_.p === 'pronto', ids = pronto ? [] : cfAdicionaisSugeridos_(cat);
  if(typeof renderAdicionaisChecklist === 'function') renderAdicionaisChecklist('pAdicionaisLista', ids);
  if(nota) nota.textContent = pronto ? 'Produto comprado pronto (ex.: bebida) vem sem adicionais.'
    : (ids.length ? ids.length + ' marcado(s) automaticamente: são os que os outros produtos desta categoria têm. Desmarque o que não vale para este.' : '');
}
(function(){
  const ligar = () => {
    const cat = document.getElementById('pCategoria'), box = document.getElementById('pAdicionaisLista');
    if(cat && !cat._cfAd){ cat._cfAd = 1; cat.addEventListener('change', cfAdicionaisNovo_); }
    if(box && !box._cfAd){ box._cfAd = 1; box.addEventListener('change', e => { if(e.target && e.target.type === 'checkbox'){ _cfAdTocado_ = true; const n = document.getElementById('pAdicionaisNota'); if(n) n.textContent = ''; } }); }
  };
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', ligar); else ligar();
})();
function cfIniciarProduto(pre, p){
  let t = CF_TIPO_[pre] || 'receita';
  if(p){
    if(p.estoqueProprioIngredienteId) t = 'pronto';
    else if((produtoIngredientes || []).some(v => v.produtoId === p.id)) t = 'receita';
    else t = cfNum_(precoDisplayProduto(p.id).custo) > 0 ? 'manual' : 'receita';
    const e = p.estoqueProprioIngredienteId ? cfIngr_(p.estoqueProprioIngredienteId) : null;
    cfSet_(pre + 'PrValor', e && cfNum_(e.custo) > 0 ? cfNum_(e.custo) : '');
    cfSet_(pre + 'PrQtd', e && cfNum_(e.custo) > 0 ? 1 : '');
  }
  _cfEsc_[pre] = null; cfSet_(pre + 'RwBusca', ''); cfSet_(pre + 'RwQtd', '');
  if(!p){ try{ showMsg(pre + 'Msg', '', ''); }catch(err){} }
  if(pre === 'p' && !p) _cfAdTocado_ = false;
  const sug = document.getElementById(pre + 'RwSug'); if(sug) sug.innerHTML = '';
  cfRwMostrarEscolhido_(pre); cfRwPopularCopiar(pre); cfRwRender(pre); cfSetTipo(pre, t);
}
/* custo da receita e do item pronto */
function cfCustoReceita_(pre){
  return Math.round(cfLista_(pre).reduce((s, it) => { const e = cfIngr_(it.ingredienteId); return s + cfNum_(it.quantidadePorUnidade) * (e ? cfNum_(e.custo) : 0); }, 0) * 100) / 100;
}
function cfCustoPronto_(pre){
  const v = cfNum_(cfVal_(pre + 'PrValor')), q = cfNum_(cfVal_(pre + 'PrQtd'));
  if(!(v > 0)) return 0;
  return Math.round((q > 0 ? v / q : v) * 10000) / 10000;
}
function cfAtualizarCusto(pre){
  const t = CF_TIPO_[pre], c = document.getElementById(pre + 'Custo'), nota = document.getElementById(pre + 'CustoNota');
  if(!c) return;
  if(t === 'receita'){
    c.value = cfLista_(pre).length ? cfCustoReceita_(pre).toFixed(2) : '';
    c.readOnly = true;
    if(nota) nota.textContent = cfLista_(pre).length ? 'Calculado pela receita. Muda sozinho quando o preço de um ingrediente muda.' : 'Monte a receita acima: o custo aparece aqui sozinho.';
  } else if(t === 'pronto'){
    const cu = cfCustoPronto_(pre);
    c.value = cu > 0 ? cu.toFixed(2) : ''; c.readOnly = true;
    if(nota) nota.textContent = cu > 0 ? ('Calculado pelo que você pagou: ' + cfMoeda4_(cu) + ' por unidade.') : 'Informe quanto pagou e por quantas unidades.';
  } else {
    c.readOnly = false;
    if(nota) nota.textContent = 'Sem receita: digite o custo se souber (em branco = custo não informado).';
  }
  cfAtualizarMargem(pre);
}
function cfAtualizarMargem(pre){
  const el = document.getElementById(pre + 'MargemPreview'); if(!el) return;
  const preco = cfNum_(cfVal_(pre + 'Preco')), custo = cfNum_(cfVal_(pre + 'Custo'));
  if(!(custo > 0)){ el.textContent = 'custo não informado'; return; }
  /* imposto sobre a venda (alíquota do mês) sai da margem; o custo do produto continua só ingredientes/compra */
  const pctImp = (typeof impostoPctHoje_ === 'function') ? impostoPctHoje_() : 0, imp = preco * pctImp / 100;
  const m = preco - custo - imp;
  el.textContent = formatarMoeda(m) + ' (' + (preco > 0 ? (m / preco * 100) : 0).toFixed(0) + '%)' + (pctImp > 0 ? ' · já tirado o imposto de ' + String(pctImp).replace('.',',') + '%' : '');
}
/* custo enviado junto com o estoque próprio ("Comprado pronto") */
function cfCustoEstoqueProprio(pre){ return cfCustoPronto_(pre); }

/* ---------- RECEITA: busca, criar, adicionar, copiar ---------- */
function cfRwBuscar(pre){
  const txt = cfVal_(pre + 'RwBusca').trim(), q = cfNorm_(txt), box = document.getElementById(pre + 'RwSug');
  _cfEsc_[pre] = null; cfRwMostrarEscolhido_(pre);
  if(!box) return;
  if(!q){ box.innerHTML = ''; return; }
  const lista = (estoque || []).filter(e => e.ativo !== false && !cfEhBebida_(e.id));
  const ach = lista.filter(e => cfNorm_(e.nome).indexOf(q) !== -1)
    .sort((a, b) => ((cfNorm_(a.nome).indexOf(q) === 0 ? 0 : 1) - (cfNorm_(b.nome).indexOf(q) === 0 ? 0 : 1)) || a.nome.localeCompare(b.nome)).slice(0, 6);
  const exato = lista.some(e => cfNorm_(e.nome) === q);
  box.innerHTML = ach.map(e => `<button type="button" class="cf-sug-item" onclick="cfRwEscolher('${pre}','${e.id}')">${escH(e.nome)} <span>${escH(e.unidade || 'un')}${cfNum_(e.custo) > 0 ? ' · ' + cfMoeda4_(e.custo) + '/' + escH(e.unidade || 'un') : ' · sem preço'}</span></button>`).join('')
    + (exato ? '' : `<button type="button" class="cf-sug-item cf-criar" onclick="cfRwNovo('${pre}')">+ criar “${escH(txt)}”</button>`);
}
function cfRwEscolher(pre, id){
  _cfEsc_[pre] = id; const e = cfIngr_(id);
  cfSet_(pre + 'RwBusca', e ? e.nome : '');
  const box = document.getElementById(pre + 'RwSug'); if(box) box.innerHTML = '';
  cfRwMostrarEscolhido_(pre);
  const q = document.getElementById(pre + 'RwQtd'); if(q){ q.value = ''; try{ q.focus(); }catch(err){} }
}
function cfRwMostrarEscolhido_(pre){
  const e = _cfEsc_[pre] ? cfIngr_(_cfEsc_[pre]) : null, lbl = document.getElementById(pre + 'RwQtdLbl'), q = document.getElementById(pre + 'RwQtd');
  if(lbl) lbl.textContent = e ? ('Quanto de ' + e.nome + ' vai em cada um (' + cfUnUso_(e.unidade) + ')') : 'Quantidade por unidade vendida';
  if(q) q.placeholder = e ? (cfUnUso_(e.unidade) === 'un' ? 'Ex: 1' : 'Ex: 150') : 'Qtd';
}
function cfRwNovo(pre){
  const nome = cfVal_(pre + 'RwBusca').trim(), box = document.getElementById(pre + 'RwSug');
  if(!nome || !box) return;
  box.innerHTML = `<div class="cf-novo">
    <b>Novo ingrediente: ${escH(nome)}</b>
    <label for="${pre}NvUn">Como você compra</label>
    <select id="${pre}NvUn" onchange="cfRwNovoUn('${pre}')"><option value="kg">Por quilo (kg)</option><option value="un">Por unidade (un)</option><option value="l">Por litro (l)</option><option value="g">Por grama (g)</option><option value="ml">Por mililitro (ml)</option></select>
    <div class="row2">
      <div><label for="${pre}NvValor">Paguei (R$)</label><input type="number" id="${pre}NvValor" step="0.01" min="0" inputmode="decimal" placeholder="Ex: 40"></div>
      <div><label for="${pre}NvQtd" id="${pre}NvQtdLbl">por quantos kg</label><input type="number" id="${pre}NvQtd" step="0.001" min="0" inputmode="decimal" value="1"></div>
    </div>
    <div class="btnrow"><button type="button" class="small-gold" onclick="cfRwCriar('${pre}')">Criar e usar na receita</button><button type="button" class="ghost" onclick="document.getElementById('${pre}RwSug').innerHTML=''">Cancelar</button></div>
    <div class="msg" id="${pre}NvMsg"></div>
  </div>`;
}
function cfRwNovoUn(pre){ const l = document.getElementById(pre + 'NvQtdLbl'); if(l) l.textContent = 'por quantos ' + (CF_UN_NOME_[cfVal_(pre + 'NvUn')] || ''); }
async function cfRwCriar(pre){
  const nome = cfVal_(pre + 'RwBusca').trim(), unidade = cfVal_(pre + 'NvUn') || 'un';
  const v = cfNum_(cfVal_(pre + 'NvValor')), q = cfNum_(cfVal_(pre + 'NvQtd'));
  if(!nome){ showMsg(pre + 'NvMsg', 'Digite o nome do ingrediente.', 'warn'); return; }
  const custo = v > 0 ? Math.round((q > 0 ? v / q : v) * 10000) / 10000 : 0;
  try{
    const r = await apiCall('addIngrediente', { nome, quantidade:0, minimo:0, unidade, custo });
    if(r && r.estoque) estoque = r.estoque;
    if(r && r.movimentacoesEstoque) movimentacoesEstoque = r.movimentacoesEstoque;
    if(!r || !r.ok){ showMsg(pre + 'NvMsg', (r && r.message) || 'Não foi possível criar.', 'warn'); return; }
    salvarCache();
    const e = (estoque || []).find(x => cfNorm_(x.nome) === cfNorm_(nome));
    try{ renderEstoque(); popularSelectIngredientes('pIngredienteSelect'); popularSelectIngredientes('ppIngredienteSelect'); popularSelectAdicionalIngrediente(); }catch(err){}
    if(e) cfRwEscolher(pre, e.id);
    showMsg(pre + 'Msg', 'Ingrediente "' + nome + '" criado' + (custo > 0 ? '' : ' (sem preço: dê o preço depois em Estoque → Preços em lote)') + '. Agora informe a quantidade.', 'ok');
  }catch(err){ showMsg(pre + 'NvMsg', 'Sem conexão. Tente de novo.', 'warn'); }
}
function cfRwAdicionar(pre){
  const id = _cfEsc_[pre], e = id ? cfIngr_(id) : null;
  if(!e){ showMsg(pre + 'Msg', 'Escolha um ingrediente da lista (ou toque em "+ criar").', 'warn'); return; }
  const q = cfNum_(cfVal_(pre + 'RwQtd'));
  if(!(q > 0)){ showMsg(pre + 'Msg', 'Informe quanto de ' + e.nome + ' vai em cada um.', 'warn'); return; }
  const qtdEst = Math.round(q / cfFatorUso_(e.unidade) * 1000) / 1000;
  if(!(qtdEst > 0)){ showMsg(pre + 'Msg', 'Quantidade muito pequena para ' + e.unidade + '. Cadastre esse ingrediente em gramas (g) ou ml.', 'warn'); return; }
  const lista = cfLista_(pre).slice(), ja = lista.find(x => x.ingredienteId === id);
  if(ja){ ja.quantidadePorUnidade = qtdEst; showMsg(pre + 'Msg', e.nome + ' já estava na receita: quantidade trocada.', 'ok'); }
  else lista.push({ ingredienteId:id, ingredienteNome:e.nome, quantidadePorUnidade:qtdEst, unidade:e.unidade || 'un' });
  cfSetLista_(pre, lista);
  _cfEsc_[pre] = null; cfSet_(pre + 'RwBusca', ''); cfSet_(pre + 'RwQtd', ''); cfRwMostrarEscolhido_(pre);
  cfRwRender(pre);
  const b = document.getElementById(pre + 'RwBusca'); if(b){ try{ b.focus(); }catch(err){} }
}
function cfRwRemover(pre, idx){ const l = cfLista_(pre).slice(); l.splice(idx, 1); cfSetLista_(pre, l); cfRwRender(pre); }
function cfRwRender(pre){
  const box = document.getElementById(pre + 'IngredientesLista'); if(!box) return;
  const lista = cfLista_(pre); let semPreco = 0;
  box.innerHTML = lista.map((it, idx) => {
    const e = cfIngr_(it.ingredienteId), un = (e && e.unidade) || it.unidade || 'un', custoU = e ? cfNum_(e.custo) : 0;
    const qUso = cfNum_(it.quantidadePorUnidade) * cfFatorUso_(un);
    if(!(custoU > 0)) semPreco++;
    const linha = custoU > 0 ? formatarMoeda(cfNum_(it.quantidadePorUnidade) * custoU) : '<span class="cf-sem">sem preço</span>';
    return `<div class="ingrediente-row"><span>${cfQtdTxt_(qUso)} ${escH(cfUnUso_(un))} de ${escH((e && e.nome) || it.ingredienteNome || '?')} · ${linha}</span><button type="button" class="rm-row" aria-label="Tirar da receita" onclick="cfRwRemover('${pre}',${idx})">✕</button></div>`;
  }).join('') || '<div class="notif-empty">Nenhum ingrediente na receita ainda.</div>';
  const tot = document.getElementById(pre + 'RwTotal');
  if(tot) tot.innerHTML = lista.length ? ('Custo da receita: <b>' + formatarMoeda(cfCustoReceita_(pre)) + '</b>' + (semPreco ? ' · <span class="cf-sem">' + semPreco + ' ingrediente(s) sem preço</span>' : '')) : '';
  cfAtualizarCusto(pre);
}
function cfRwPopularCopiar(pre){
  const sel = document.getElementById(pre + 'RwCopiar'); if(!sel) return;
  const atual = pre === 'pp' ? produtoEditandoId : null;
  const com = (produtos || []).filter(p => p.id !== atual && (produtoIngredientes || []).some(v => v.produtoId === p.id && v.ingredienteId !== p.estoqueProprioIngredienteId))
    .sort((a, b) => a.nome.localeCompare(b.nome));
  sel.innerHTML = '<option value="">📋 Copiar receita de outro produto…</option>' + com.map(p => `<option value="${p.id}">${escH(p.nome)}</option>`).join('');
  sel.style.display = com.length ? '' : 'none';
}
async function cfRwCopiar(pre, prodId){
  const sel = document.getElementById(pre + 'RwCopiar');
  if(!prodId) return;
  const p = (produtos || []).find(x => x.id === prodId);
  if(p && cfLista_(pre).length && !await confirmarTxt_('Trocar a receita atual pela de "' + p.nome + '"? Depois você ajusta o que for diferente.')){ if(sel) sel.value = ''; return; }
  const nova = (produtoIngredientes || []).filter(v => v.produtoId === prodId && (!p || v.ingredienteId !== p.estoqueProprioIngredienteId))
    .map(v => { const e = cfIngr_(v.ingredienteId); return { ingredienteId:v.ingredienteId, ingredienteNome:(e && e.nome) || v.ingredienteNome, quantidadePorUnidade:cfNum_(v.quantidadePorUnidade), unidade:(e && e.unidade) || 'un' }; });
  cfSetLista_(pre, nova); if(sel) sel.value = '';
  cfRwRender(pre);
  showMsg(pre + 'Msg', 'Receita copiada de "' + (p ? p.nome : '') + '". Ajuste o que for diferente.', 'ok');
}
/* o que vai para o servidor ao salvar o produto */
function cfIngredientesParaSalvar(pre){ return CF_TIPO_[pre] === 'receita' ? cfLista_(pre) : []; }

/* ---------- COMBO: custo = soma dos produtos ---------- */
function cfCustoCombo(pre){
  const lista = pre === 'ko' ? itensComboNovo : itensComboEdicao, c = document.getElementById(pre + 'Custo'); if(!c) return;
  let nota = document.getElementById(pre + 'CustoNota');
  if(!nota){ nota = document.createElement('p'); nota.className = 'sub'; nota.id = pre + 'CustoNota'; const row = c.closest('.row2') || c.parentNode; row.parentNode.insertBefore(nota, row.nextSibling); }
  if(lista && lista.length){
    const v = lista.reduce((s, it) => s + cfNum_(it.quantidade) * cfNum_(precoDisplayProduto(it.produtoId).custo), 0);
    c.value = (Math.round(v * 100) / 100).toFixed(2); c.readOnly = true;
    nota.textContent = 'Custo = soma dos produtos do combo. Muda sozinho quando o custo deles muda.';
  } else { c.readOnly = false; nota.textContent = ''; }
  if(pre === 'ko'){ try{ atualizarMargemPreviewCombo(); }catch(err){} }
}

/* ---------- INGREDIENTE: "paguei R$ X por N" ---------- */
function cfAbrirNovoIngrediente(){
  ['eNome','eCompraValor','eCompraQtd','eCusto','eQtd','eMin'].forEach(id => cfSet_(id, ''));
  cfSet_('eUnidade', 'un'); cfIngAtualizar('e'); showMsg('eMsg', '', '');
  abrirFormModal('ingredienteNovoModal');
}
function cfIngAtualizar(pre, digitouCusto){
  const un = cfVal_(pre + 'Unidade') || 'un';
  const lbl = document.getElementById(pre + 'CompraQtdLbl'); if(lbl) lbl.textContent = 'por quantos ' + (CF_UN_NOME_[un] || un);
  const cl = document.getElementById(pre + 'CustoLbl'); if(cl) cl.textContent = 'Custo por ' + un + ' (R$)';
  if(!digitouCusto){
    const v = cfNum_(cfVal_(pre + 'CompraValor')), q = cfNum_(cfVal_(pre + 'CompraQtd'));
    if(v > 0) cfSet_(pre + 'Custo', Math.round((q > 0 ? v / q : v) * 10000) / 10000);
    else if(pre === 'e') cfSet_('eCusto', '');
  }
  const c = cfNum_(cfVal_(pre + 'Custo')), nota = document.getElementById(pre + 'CustoNota');
  if(nota) nota.textContent = c > 0 ? ('Custo: ' + cfMoeda4_(c) + ' por ' + un + (un === 'kg' || un === 'l' ? ' (= ' + cfMoeda4_(c / 1000) + ' por ' + cfUnUso_(un) + ')' : '')) : 'Informe quanto pagou para o sistema calcular o custo.';
}
function cfEeAbrir(i){ _cfEeUnAntes_ = (i && i.unidade) || 'un'; cfSet_('eeCompraValor', ''); cfSet_('eeCompraQtd', ''); const a = document.getElementById('eeUnidadeAviso'); if(a) a.textContent = ''; cfIngAtualizar('ee', true); }
function cfEeUnidadeMudou(){
  const id = cfVal_('eeId'), novo = cfVal_('eeUnidade'), aviso = document.getElementById('eeUnidadeAviso');
  const antes = _cfEeUnAntes_ || 'un', f = cfFator_(antes, novo), usos = cfUsos_(id);
  if(novo === antes){ if(aviso) aviso.textContent = ''; }
  else if(f){
    // mostra os números já convertidos; ao salvar, o banco converte também as receitas
    const i = cfIngr_(id) || {};
    cfSet_('eeQtd', Math.round(cfNum_(i.quantidade) * f * 1000) / 1000);
    cfSet_('eeMin', Math.round(cfNum_(i.minimo) * f * 1000) / 1000);
    cfSet_('eeCusto', Math.round(cfNum_(i.custo) / f * 10000) / 10000);
    if(aviso) aviso.textContent = 'Convertido de ' + antes + ' para ' + novo + ': estoque, mínimo e custo já ajustados' + (usos.length ? '; as receitas serão convertidas ao salvar.' : '.');
  } else if(aviso){
    aviso.textContent = usos.length ? ('⚠️ Trocar de ' + antes + ' para ' + novo + ' não converte sozinho. Revise a quantidade deste ingrediente na receita de: ' + usos.join(', ') + '.') : ('Trocar de ' + antes + ' para ' + novo + ': confira "Tenho agora" e o custo.');
  }
  cfIngAtualizar('ee', true);
}
/* antes de salvar a edição: troca de unidade compatível vai primeiro pelo banco (converte receitas e estoque sem lançar "ajuste") */
async function cfEeAntesDeSalvar(){
  const id = cfVal_('eeId'), novo = cfVal_('eeUnidade'), antes = _cfEeUnAntes_ || 'un';
  if(novo === antes) return true;
  const f = cfFator_(antes, novo), usos = cfUsos_(id);
  if(!f){
    if(usos.length && !await confirmarTxt_('Este ingrediente está na receita de: ' + usos.join(', ') + '.\n\nTrocar de ' + antes + ' para ' + novo + ' NÃO converte as quantidades. Depois de salvar, abra essas receitas e confira.\n\nContinuar?', 'Trocar a unidade', false, 'Unidade sem conversão')) return false;
    return true;
  }
  const r = await apiCall('salvarPrecosLote', { itens:[{ id, unidade:novo, custo:cfNum_(cfVal_('eeCusto')) }] });
  if(!r || !r.ok){ showMsg('eeMsg', (r && r.message) || 'Não foi possível trocar a unidade.', 'warn'); return false; }
  cfAplicarRespostaCustos_(r);
  _cfEeUnAntes_ = novo;
  return true;
}
function cfAplicarRespostaCustos_(r){
  if(!r) return;
  if(r.estoque) estoque = r.estoque;
  if(r.produtoPrecos) produtoPrecos = r.produtoPrecos;
  if(r.comboPrecos) comboPrecos = r.comboPrecos;
  if(r.produtoIngredientes) produtoIngredientes = r.produtoIngredientes;
  if(r.adicionais) adicionais = r.adicionais;
  if(r.movimentacoesEstoque) movimentacoesEstoque = r.movimentacoesEstoque;
  salvarCache();
}
function cfRenderTudo_(){
  ['renderEstoque','renderProdutos','renderCombos','renderMovimentacoesEstoque','renderNotificacoes'].forEach(fn => { try{ if(typeof window[fn] === 'function') window[fn](); }catch(err){} });
  try{ popularSelectProdutos(); popularSelectCombos(); }catch(err){}
}

/* ---------- PREÇOS EM LOTE ---------- */
function cfLoteItens_(){ return (estoque || []).filter(e => e.ativo !== false && !cfEhBebida_(e.id)).slice().sort((a, b) => a.nome.localeCompare(b.nome)); }
function cfAbrirLote(){
  _cfLote_ = {};
  const chk = document.getElementById('plSoSemPreco');
  if(chk) chk.checked = cfLoteItens_().some(e => !(cfNum_(e.custo) > 0));
  cfSet_('plBusca', ''); showMsg('plMsg', '', '');
  cfLoteRender(); abrirFormModal('precosLoteModal');
}
function cfLoteRender(){
  const box = document.getElementById('plLista'); if(!box) return;
  const so = !!(document.getElementById('plSoSemPreco') || {}).checked, q = cfNorm_(cfVal_('plBusca'));
  const lista = cfLoteItens_().filter(e => (!so || !(cfNum_(e.custo) > 0) || _cfLote_[e.id]) && (!q || cfNorm_(e.nome).indexOf(q) !== -1));
  box.innerHTML = lista.length ? lista.map(e => {
    const st = _cfLote_[e.id] || { unidade:e.unidade || 'un', valor:'', qtd:'' };
    return `<div class="cf-lote-row">
      <div class="cf-lote-nome"><b>${escH(e.nome)}</b><span>${cfNum_(e.custo) > 0 ? 'hoje: ' + cfMoeda4_(e.custo) + ' por ' + escH(e.unidade || 'un') : '<span class="cf-sem">sem preço</span>'}</span></div>
      <div class="cf-lote-campos">
        <select aria-label="Como compra ${escH(e.nome)}" onchange="cfLoteMudar('${e.id}','unidade',this.value)">${['un','kg','g','l','ml'].map(u => `<option value="${u}"${u === st.unidade ? ' selected' : ''}>${u}</option>`).join('')}</select>
        <input type="number" min="0" step="0.01" inputmode="decimal" placeholder="Paguei R$" aria-label="Quanto pagou por ${escH(e.nome)}" value="${escH(st.valor)}" oninput="cfLoteMudar('${e.id}','valor',this.value)">
        <input type="number" min="0" step="0.001" inputmode="decimal" placeholder="por 1" aria-label="Por quanto de ${escH(e.nome)}" value="${escH(st.qtd)}" oninput="cfLoteMudar('${e.id}','qtd',this.value)">
      </div>
      <div class="cf-lote-res" id="plRes_${e.id}">${cfLoteRes_(e, st)}</div>
    </div>`;
  }).join('') : '<div class="notif-empty">' + (so ? 'Todos os ingredientes já têm preço. Desmarque "só sem preço" para ver todos.' : 'Nenhum ingrediente encontrado.') + '</div>';
}
function cfLoteMudar(id, campo, v){
  const e = cfIngr_(id); if(!e) return;
  const st = _cfLote_[id] || (_cfLote_[id] = { unidade:e.unidade || 'un', valor:'', qtd:'' });
  st[campo] = v;
  const el = document.getElementById('plRes_' + id); if(el) el.innerHTML = cfLoteRes_(e, st);
}
function cfLoteRes_(e, st){
  const v = cfNum_(st.valor), q = cfNum_(st.qtd) || 1, partes = [];
  if(v > 0) partes.push('= ' + cfMoeda4_(v / q) + ' por ' + st.unidade);
  if(st.unidade !== (e.unidade || 'un')){
    if(cfFator_(e.unidade, st.unidade)) partes.push('as receitas são convertidas de ' + (e.unidade || 'un') + ' para ' + st.unidade);
    else { const u = cfUsos_(e.id); partes.push(u.length ? '⚠️ revise a quantidade na receita de: ' + escH(u.join(', ')) : 'unidade trocada'); }
  }
  return partes.join(' · ');
}
async function cfLoteSalvar(){
  const itens = [];
  Object.keys(_cfLote_).forEach(id => {
    const e = cfIngr_(id); if(!e) return;
    const st = _cfLote_[id], it = { id }; let mudou = false;
    if(st.unidade && st.unidade !== (e.unidade || 'un')){ it.unidade = st.unidade; mudou = true; }
    const v = cfNum_(st.valor), q = cfNum_(st.qtd) || 1;
    if(v > 0){ it.custo = Math.round(v / q * 10000) / 10000; mudou = true; }
    if(mudou) itens.push(it);
  });
  if(!itens.length){ showMsg('plMsg', 'Nada para salvar: preencha "Paguei R$" de algum ingrediente.', 'warn'); return; }
  const revisar = itens.filter(it => it.unidade && !cfFator_((cfIngr_(it.id) || {}).unidade, it.unidade) && cfUsos_(it.id).length);
  if(revisar.length && !await confirmarTxt_('Alguns ingredientes trocaram de unidade sem conversão automática (ex.: un → kg):\n• ' + revisar.map(it => (cfIngr_(it.id) || {}).nome).join('\n• ') + '\n\nDepois de salvar, confira a quantidade deles nas receitas. Continuar?', 'Continuar', false, 'Confira as receitas')) return;
  const btn = document.getElementById('plBtn'); if(btn) btn.disabled = true;
  try{
    const r = await apiCall('salvarPrecosLote', { itens });
    if(r && r.ok){ cfAplicarRespostaCustos_(r); _cfLote_ = {}; cfLoteRender(); cfRenderTudo_(); showMsg('plMsg', r.message || 'Preços salvos.', 'ok'); }
    else showMsg('plMsg', (r && r.message) || 'Não foi possível salvar.', 'warn');
  }catch(err){ showMsg('plMsg', 'Sem conexão. Confira os preços antes de tentar de novo.', 'warn'); }
  finally{ if(btn) btn.disabled = false; }
}

/* ---------- ESTOQUE: Ingredientes × Bebidas e itens prontos ---------- */
function cfEstoqueAba(a){
  _cfEstAba_ = a === 'beb' ? 'beb' : 'ing';
  const bi = document.getElementById('estAbaIng'), bb = document.getElementById('estAbaBeb');
  if(bi) bi.classList.toggle('active', _cfEstAba_ === 'ing');
  if(bb) bb.classList.toggle('active', _cfEstAba_ === 'beb');
  const n = document.getElementById('estNovoIngBox'), h = document.getElementById('estBebAjuda');
  if(n) n.style.display = _cfEstAba_ === 'ing' ? '' : 'none';
  if(h) h.style.display = _cfEstAba_ === 'beb' ? '' : 'none';
  try{ renderEstoque(); }catch(err){}
}
function cfEstoqueFiltro(i){ return _cfEstAba_ === 'beb' ? cfEhBebida_(i.id) : !cfEhBebida_(i.id); }
function cfEstoqueContagem_(){
  const ing = (estoque || []).filter(i => !cfEhBebida_(i.id)).length, beb = (estoque || []).length - ing;
  const bi = document.getElementById('estAbaIng'), bb = document.getElementById('estAbaBeb');
  if(bi) bi.textContent = 'Ingredientes (' + ing + ')';
  if(bb) bb.textContent = 'Bebidas e itens prontos (' + beb + ')';
}
function cfCustoLinhaEstoque(i){
  return cfNum_(i.custo) > 0 ? (cfMoeda4_(i.custo) + ' por ' + escH(i.unidade || 'un')) : '<span class="cf-sem">sem preço</span>';
}

/* ---------- AVISO DE CADASTRO INCOMPLETO ---------- */
function cfProdutosSemCusto_(){ return (produtos || []).filter(p => p.ativo !== false && !(cfNum_(precoDisplayProduto(p.id).custo) > 0)); }
function cfAvisos(){
  const ingSem = (estoque || []).filter(e => e.ativo !== false && !cfEhBebida_(e.id) && !(cfNum_(e.custo) > 0)).length;
  const bebSem = (estoque || []).filter(e => e.ativo !== false && cfEhBebida_(e.id) && !(cfNum_(e.custo) > 0)).length;
  const prodSem = cfProdutosSemCusto_().length;
  const ap = document.getElementById('cfAvisoProdutos');
  if(ap) ap.innerHTML = (prodSem || ingSem) ? `<div class="cf-aviso">⚠️ <b>Cadastro incompleto:</b> ${prodSem} produto(s) sem custo${ingSem ? ' · ' + ingSem + ' ingrediente(s) sem preço' : ''}. Sem custo, a margem e o lucro dos relatórios ficam errados.
    <div class="btnrow">${ingSem ? '<button type="button" class="small-gold" onclick="cfAbrirLote()">💲 Dar preço aos ingredientes</button>' : ''}${prodSem ? '<button type="button" class="ghost" onclick="cfProximoSemCusto()">Abrir o próximo produto sem custo</button>' : ''}</div></div>` : '';
  const ae = document.getElementById('cfAvisoEstoque');
  if(ae) ae.innerHTML = (ingSem || bebSem) ? `<div class="cf-aviso">⚠️ ${ingSem ? ingSem + ' ingrediente(s) sem preço' : ''}${ingSem && bebSem ? ' · ' : ''}${bebSem ? bebSem + ' bebida(s)/item(ns) pronto(s) sem custo' : ''}.
    ${ingSem ? '<div class="btnrow"><button type="button" class="small-gold" onclick="cfAbrirLote()">💲 Dar preço agora</button></div>' : ''}</div>` : '';
  cfEstoqueContagem_();
}
function cfProximoSemCusto(){ const p = cfProdutosSemCusto_()[0]; if(p) abrirEditarProduto(p.id); }

/* ---------- VENDA COM CUSTO ALTERADO ----------
   O banco confere o custo de cada item com o cadastro. Se o custo mudou com a tela aberta (preço de ingrediente, compra recebida),
   a venda é recusada com "O custo de ... não confere". Aqui a tela busca os custos novos e tenta de novo UMA vez. O preço nunca é trocado. */
function cfCustoMudou(r){ return !!(r && r.ok === false && /O custo de .* não confere com o cadastro/i.test(r.message || '')); }
async function cfAtualizarCustosItens(lista){
  try{
    const r = await apiCall('getDadosGrupo', { grupo:'cad' });
    if(!r || r.ok === false) return false;
    if(r.produtoPrecos) produtoPrecos = r.produtoPrecos;
    if(r.comboPrecos) comboPrecos = r.comboPrecos;
    salvarCache();
  }catch(err){ return false; }
  (lista || []).forEach(it => {
    if(it.produtoId) it.custoUnitario = cfNum_(precoDisplayProduto(it.produtoId).custo);
    else if(it.comboId) it.custoUnitario = cfNum_(precoDisplayCombo(it.comboId).custo);
  });
  return true;
}

/* estado inicial do formulário de novo produto */
(function(){
  function iniciar(){ try{ cfIniciarProduto('p', null); }catch(err){} try{ cfIngAtualizar('e'); }catch(err){} }
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', iniciar); else iniciar();
})();
