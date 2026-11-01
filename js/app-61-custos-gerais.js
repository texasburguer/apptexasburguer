/* =====================================================================
   CUSTOS GERAIS (v1.24) · Administrador → Custos e precificação
   % de perdas e desperdício (entra no custo dos produtos) e custo por pedido (sacola, lacre),
   que entra no custo de cada venda. As taxas das formas de pagamento aparecem só para conferência
   (o lugar de mudar é Formas de pagamento).
   ===================================================================== */
(function(){
  'use strict';
  function br_(v){ return Number(v || 0).toFixed(2).replace('.', ','); }
  function preencher_(r){
    const v = (id, x) => { const e = document.getElementById(id); if(e) e.value = x; };
    v('cgPerda', r.perdaPct); v('cgEntrega', r.entrega); v('cgRetirada', r.retirada); v('cgMesa', r.mesa);
    const t = document.getElementById('cgTaxas');
    if(t) t.innerHTML = '<div class="sub"><b>Taxas das formas de pagamento</b> (mude em <a href="#" onclick="abrirAdministrador(\'pagamentos\');return false;">Formas de pagamento</a>): '
      + (r.taxas || []).map(f => escH(f.nome) + ' ' + br_(f.pct) + '%' + (Number(f.fixa) > 0 ? ' + R$ ' + br_(f.fixa) : '')).join(' · ') + '</div>';
  }
  window.carregarCustosGerais_ = async function(){
    if(!document.getElementById('cgCard')) return;
    try{
      const r = await sbRpc_('api_custos_gerais', { p:{} });
      if(!r || r.ok !== true){ showMsg('cgMsg', '⚠️ ' + ((r && r.message) || 'Não consegui carregar os custos gerais.'), 'warn'); return; }
      preencher_(r);
    }catch(e){ showMsg('cgMsg', '📡 Sem conexão para carregar os custos gerais.', 'warn'); }
  };
  window.salvarCustosGerais_ = async function(){
    const n = id => Number(String((document.getElementById(id) || {}).value || '0').replace(',', '.'));
    const p = { salvar:true, perdaPct:n('cgPerda'), entrega:n('cgEntrega'), retirada:n('cgRetirada'), mesa:n('cgMesa') };
    if([p.perdaPct, p.entrega, p.retirada, p.mesa].some(x => !isFinite(x) || x < 0)){ showMsg('cgMsg', '⚠️ Confira os números: use 0 ou mais.', 'warn'); return; }
    try{
      const r = await sbRpc_('api_custos_gerais', { p });
      if(r && r.ok){ preencher_(r); showMsg('cgMsg', r.message || 'Salvo.', 'ok'); try{ if(typeof sincronizarEmSegundoPlano === 'function') sincronizarEmSegundoPlano(); }catch(e){} }
      else showMsg('cgMsg', '⚠️ ' + ((r && r.message) || 'Não foi possível salvar.'), 'warn');
    }catch(e){ showMsg('cgMsg', '⚠️ Não foi possível salvar agora. Confira a internet e tente de novo.', 'warn'); }
  };
})();
