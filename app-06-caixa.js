/* ---------- PAINÉIS DO CAIXA (sem rolar a tela: Cliente → Itens → Pagamento) ---------- */
let painelCaixaAtual = 'cliente';
function mudarPainelCaixa(painel){
  painelCaixaAtual = painel;
  ['cliente','forma','itens','finalizar'].forEach(p=>{
    document.getElementById('painel'+p.charAt(0).toUpperCase()+p.slice(1)).style.display = (p===painel) ? 'block' : 'none';
    document.getElementById('painel'+p.charAt(0).toUpperCase()+p.slice(1)+'Btn').classList.toggle('active', p===painel);
  });
  if(painel==='itens') atualizarGarcomMesaInfo();
}
function atualizarContagemPainelItens(){
  const el = document.getElementById('painelItensContagem');
  if(el) el.textContent = carrinhoAtual.length ? '('+carrinhoAtual.length+')' : '';
}
let tipoDescontoAtual = 'percentual';
function setTipoDesconto(tipo){
  tipoDescontoAtual = tipo;
  document.getElementById('descTipoPercentualBtn').classList.toggle('active', tipo==='percentual');
  document.getElementById('descTipoFixoBtn').classList.toggle('active', tipo==='fixo');
  atualizarPreviewDesconto();
}
function valorDescontoAtualNumero(){ const el = document.getElementById('descValor'); return el ? (Number(el.value) || 0) : 0; }
function valorDescontoCalculado(){
  const bruto = totalCarrinho();
  const v = valorDescontoAtualNumero();
  if(v<=0) return 0;
  return tipoDescontoAtual==='percentual' ? Math.round(bruto*(v/100)*100)/100 : Math.round(v*100)/100;
}
/* Taxa de entrega desta venda: só existe quando o tipo é Entrega. Campo vazio = taxa padrão cadastrada; campo preenchido (0 a 500) = valor digitado.
   Mesma regra do servidor (valor fora de 0–500 ou inválido volta para a padrão), para o total da tela bater com o total gravado. */
function taxaEntregaVenda(){
  if(tipoEntregaAtual!=='Entrega') return 0;
  const padrao = Math.round((Number(configEntrega && configEntrega.taxaPadrao)||0)*100)/100;
  const el = document.getElementById('vTaxaEntrega');
  const txt = el ? String(el.value||'').trim().replace(',','.') : '';
  if(txt==='') return padrao;
  const n = Number(txt);
  return (isFinite(n) && n>=0 && n<=500) ? Math.round(n*100)/100 : padrao;
}
/* ---------- ACRÉSCIMO DA FORMA DE PAGAMENTO ----------
   Os valores de cada pagamento são a PARTE DO PEDIDO paga naquela forma (sem acréscimo); o servidor soma o acréscimo da forma.
   Aqui o acréscimo só é calculado para mostrar ao operador quanto cobrar. */
/* O % do acréscimo não incide sobre a taxa de entrega: 'fator' = parte do valor que NÃO é taxa de entrega (1 = sem taxa). */
function fatorBaseAcrescimo_(){
  const t = taxaEntregaVenda(); if(!(t>0)) return 1;
  const tot = totalComDesconto(); return tot>0 ? Math.max(0, (tot-t)/tot) : 1;
}
function acrescimoForma_(nome, valor, fator){
  const v = Number(valor)||0; if(v<=0) return 0;
  const f = (formasPagamento||[]).find(x=>x.nome===nome); if(!f) return 0;
  if(fator===undefined) fator = fatorBaseAcrescimo_();
  return Math.round((v*fator*(f.acrescimoPct||0)/100 + (f.acrescimoFixo||0))*100)/100;
}
function acrescimoTotalVenda_(){
  if(tipoEntregaAtual==='Mesa' && !mesaPagaAgora_()) return 0;
  return Math.round(pagamentosAtuais.reduce((s,p)=>s+acrescimoForma_(p.forma, p.valor),0)*100)/100;
}
function totalComDesconto(){
  const bruto = totalCarrinho();
  const desc = valorDescontoCalculado();
  const total = bruto - desc;
  const base = total>0 ? Math.round(total*100)/100 : bruto;
  return Math.round((base + taxaEntregaVenda())*100)/100;
}
function atualizarPreviewDesconto(){
  const bruto = totalCarrinho();
  const desc = valorDescontoCalculado();
  const total = totalComDesconto();
  document.getElementById('descSubtotal').textContent = formatarMoeda(bruto);
  document.getElementById('descValorCalc').textContent = formatarMoeda(desc);
  const taxaPrev = taxaEntregaVenda(), elTaxaPrev = document.getElementById('descTaxaLinha');
  if(elTaxaPrev){ elTaxaPrev.style.display = taxaPrev>0 ? '' : 'none'; document.getElementById('descTaxa').textContent = formatarMoeda(taxaPrev); }
  document.getElementById('descTotalFinal').textContent = formatarMoeda(total);
  co