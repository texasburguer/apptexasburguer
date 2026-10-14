/* TEXAS BURGER — Leitor Fiscal IA (Etapa 10)
 * A IA apenas propõe dados. Nenhuma compra/estoque/financeiro é gravado até Confirmar.
 * Fotos são reduzidas no dispositivo e enviadas ao bucket privado fiscal-notas.
 */
(function(){
  'use strict';
  const $ = id => document.getElementById(id);
  const esc = s => String(s == null ? '' : s).replace(/[&<>"'`]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;','`':'&#96;'}[c]));
  const fmt = n => (typeof formatarMoeda === 'function' ? formatarMoeda(Number(n)||0) : 'R$ '+(Number(n)||0).toFixed(2));
  let atual = null, fornecedores = [], estoqueAtual = [], arquivoPath = null, objetoUpload = null, bloqueado = false;
  function pode(){ return !!(typeof currentUser!=='undefined' && currentUser && ['Admin','Operador'].includes(currentUser.nivel) && !currentUser.emergencia); }
  function sessao(){ try { const s=sbSessaoLer_(); return s && s.access_token ? s.access_token : ''; } catch(_) { return ''; } }
  async function token(){ let t=sessao(); if(!t && typeof sbRenovar_==='function' && await sbRenovar_()) t=sessao(); return t; }
  function msg(t, cls){ const e=$('fiscalLeitorMsg'); if(e){e.textContent=t||'';e.className='msg '+(cls||'');} }
  function card(){
    if($('fiscalLeitorCard')) return;
    const anchor=$('iaAjudaCard') || $('tab-ia'); if(!anchor) return;
    const c=document.createElement('div'); c.className='card ia-card'; c.id='fiscalLeitorCard';
    c.innerHTML='<h2>🧾 Leitor Fiscal IA</h2><p class="sub">Envie uma foto da nota/cupom, um XML de NF-e ou cole o texto. A IA só prepara uma proposta; estoque, compra e financeiro só mudam após sua confirmação. Acesso restrito à equipe.</p>'+
      '<div class="ia-linha"><label for="fiscalNotaArquivo">Foto ou XML da nota</label><input id="fiscalNotaArquivo" type="file" accept="image/*,.xml,.txt,text/plain,application/xml" /></div>'+
      '<div class="ia-linha"><label for="fiscalNotaTexto">Ou colar texto da nota</label><textarea id="fiscalNotaTexto" rows="4" maxlength="20000" placeholder="Cole aqui o texto extraído da nota ou cupom fiscal"></textarea></div>'+
      '<div class="ia-linha"><button class="primary" type="button" id="fiscalLerBtn">Ler nota e preparar conferência</button><button class="ghost" type="button" id="fiscalLimparBtn">Limpar</button></div><div id="fiscalLeitorMsg" class="msg"></div><div id="fiscalLeitorResultado"></div>';
    anchor.insertAdjacentElement('afterend',c);
    $('fiscalLerBtn').addEventListener('click', ler);
    $('fiscalLimparBtn').addEventListener('click', limpar);
  }
  function limpar(){ atual=null;arquivoPath=null;objetoUpload=null; $('fiscalNotaArquivo').value='';$('fiscalNotaTexto').value='';$('fiscalLeitorResultado').innerHTML='';msg(''); }
  async function comprinhas(){
    if(!fornecedores.length){ const r=await apiCall('listarCompras',{}); if(!r||!r.ok) throw new Error((r&&r.message)||'Não consegui carregar fornecedores.'); fornecedores=r.fornecedores||[]; }
    estoqueAtual=Array.isArray(window.estoque)?window.estoque:[];
  }
  async function reduzirFoto(file){
    if(!file.type.startsWith('image/')) throw new Error('Escolha uma imagem, XML ou texto.');
    if(file.size>15*1024*1024) throw new Error('A imagem original é grande demais (máximo 15 MB).');
    const url=URL.createObjectURL(file);
    try{ const img=await new Promise((ok,no)=>{const i=new Image();i.onload=()=>ok(i);i.onerror=no;i.src=url;});
      const max=1800, ratio=Math.min(1,max/Math.max(img.width,img.height)); const c=document.createElement('canvas');c.width=Math.max(1,Math.round(img.width*ratio));c.height=Math.max(1,Math.round(img.height*ratio));
      c.getContext('2d').drawImage(img,0,0,c.width,c.height);
      const blob=await new Promise(ok=>c.toBlob(ok,'image/jpeg',0.78)); if(!blob) throw new Error('Não consegui preparar a imagem.');
      if(blob.size>5*1024*1024) throw new Error('A foto continua acima de 5 MB. Tente outra foto mais simples.'); return blob;
    } finally { URL.revokeObjectURL(url); }
  }
  function uidDoToken(t){try{const b=t.split('.')[1].replace(/-/g,'+').replace(/_/g,'/');return JSON.parse(decodeURIComponent(escape(atob(b)))).sub||'';}catch(_){return '';}}
  async function uploadFoto(file){
    const t=await token(); if(!t) throw new Error('Sua sessão expirou. Entre novamente.');
    const blob=await reduzirFoto(file), id=(crypto.randomUUID?crypto.randomUUID():Date.now()+'-'+Math.random().toString(16).slice(2));
    const uid=uidDoToken(t); if(!uid) throw new Error('Não consegui validar sua sessão. Entre novamente.');
    const path=uid+'/'+id+'.jpg';
    const r=await fetch(SUPABASE_URL_+'/storage/v1/object/fiscal-notas/'+path,{method:'POST',headers:{apikey:SUPABASE_CHAVE_,Authorization:'Bearer '+t,'Content-Type':'image/jpeg','x-upsert':'false'},body:blob});
    const j=await r.json().catch(()=>({})); if(!r.ok) throw new Error(j.message||j.error||'Não consegui guardar a foto com segurança.');
    return path;
  }
  async function chamarLeitor(body){
    const t=await token(); if(!t) throw new Error('Sua sessão expirou. Entre novamente.');
    const r=await fetch(SUPABASE_URL_+'/functions/v1/leitor-fiscal',{method:'POST',headers:{apikey:SUPABASE_CHAVE_,Authorization:'Bearer '+t,'Content-Type':'application/json'},body:JSON.stringify(body)});
    const j=await r.json().catch(()=>null); if(!r.ok||!j||!j.ok) throw new Error((j&&j.message)||'A leitura não foi concluída.'); return j;
  }
  async function ler(){
    if(!pode()) return msg('Este recurso está disponível somente para Admin e Operador.','warn'); if(bloqueado)return;
    const f=$('fiscalNotaArquivo').files[0], texto=$('fiscalNotaTexto').value.trim(); if(!f&&!texto)return msg('Envie uma foto/XML ou cole o texto da nota.','warn');
    bloqueado=true; $('fiscalLerBtn').disabled=true; $('fiscalLeitorResultado').innerHTML='';msg('Preparando a leitura com segurança…','warn');
    try{
      await comprinhas(); let body={acao:'ler',texto:texto||'',origem:texto?'texto':'foto'};
      if(f){
        if(/\.xml$/i.test(f.name)||f.type==='application/xml'||f.type==='text/xml'||f.type==='text/plain'){
          const raw=await f.text(); if(raw.length>200000) throw new Error('O XML/texto ultrapassa 200 KB.'); body={acao:'ler',origem:/<\?xml|<NFe|<nfeProc/i.test(raw)?'xml':'texto',texto:raw};
        } else { arquivoPath=await uploadFoto(f); body={acao:'ler',origem:'foto',storagePath:arquivoPath}; }
      }
      const r=await chamarLeitor(body); atual=r.leitura; renderResultado(r.leitura);
      msg(r.duplicada?'Esta chave fiscal já foi usada em outra leitura. Confira o histórico antes de continuar.':'Leitura pronta para conferência. Nada foi lançado ainda.',r.duplicada?'warn':'ok');
    }catch(e){msg(e.message||'Falha ao ler a nota. Você pode corrigir o texto ou digitar os itens manualmente.','warn');}
    finally{bloqueado=false;$('fiscalLerBtn').disabled=false;}
  }
  function renderResultado(d){
    if(!d){return;} const itens=Array.isArray(d.itens)?d.itens:[];
    const bloqueada=(d.estado==='duplicada'||(d.alertas||[]).some(a=>String(a).startsWith('BLOQUEIO:'))); const opts=fornecedores.filter(f=>f.ativo!==false).map(f=>'<option value="'+esc(f.id)+'" '+(norm(f.nome)===norm(d.fornecedorNome)?'selected':'')+'>'+esc(f.nome)+'</option>').join('');
    const stock=estoqueAtual.filter(e=>e.ativo!==false);
    const rows=itens.map((it,i)=>'<tr data-fiscal-item="'+i+'"><td><input data-k="descricao" value="'+esc(it.descricao||'')+'" maxlength="80" aria-label="Descrição do item"></td><td><input data-k="quantidade" type="number" min="0.001" step="0.001" value="'+esc(it.quantidade||1)+'" aria-label="Quantidade"></td><td><input data-k="unidade" value="'+esc(it.unidade||'un')+'" maxlength="10" aria-label="Unidade"></td><td><input data-k="valorTotal" type="number" min="0" step="0.01" value="'+esc(it.valorTotal||0)+'" aria-label="Valor total do item"></td><td><select data-k="ingredienteId"><option value="">Não vincular ao estoque</option>'+stock.map(e=>'<option value="'+esc(e.id)+'" '+(String(it.ingredienteId||'')===String(e.id)?'selected':'')+'>'+esc(e.nome||e.ingrediente||'Ingrediente')+'</option>').join('')+'</select></td></tr>').join('');
    $('fiscalLeitorResultado').innerHTML='<div class="notif-card" style="margin-top:12px"><h3>Conferência antes de lançar</h3>'+
      (d.alertas||[]).map(a=>'<p class="ia-aviso">⚠️ '+esc(a)+'</p>').join('')+
      '<p><b>Emitente:</b> '+esc(d.emitenteNome||'Não identificado')+' · <b>CNPJ:</b> '+esc(d.emitenteCnpj||'Não identificado')+'</p><p><b>Data:</b> '+esc(d.dataEmissao||'—')+' · <b>Número:</b> '+esc(d.numeroDocumento||'—')+' · <b>Chave:</b> '+esc(d.chaveNfe||'não identificada')+'</p>'+
      '<div class="ia-linha"><label for="fiscalFornecedor">Fornecedor cadastrado</label><select id="fiscalFornecedor"><option value="">Selecione o fornecedor</option>'+opts+'</select></div>'+
      '<div style="overflow-x:auto"><table class="tabela"><thead><tr><th>Item</th><th>Qtd.</th><th>Un.</th><th>Total R$</th><th>Vincular ao estoque</th></tr></thead><tbody>'+rows+'</tbody></table></div>'+
      '<div class="ia-linha"><label for="fiscalTotal">Total da nota (R$)</label><input id="fiscalTotal" type="number" min="0" step="0.01" value="'+esc(d.total||0)+'"></div>'+
      '<div class="ia-linha"><label for="fiscalObs">Observação</label><input id="fiscalObs" maxlength="300" value="'+esc('Leitura pelo Tex'+(d.numeroDocumento?' · Doc. '+d.numeroDocumento:''))+'"></div>'+
      '<div class="ia-linha"><label for="fiscalPagamento">Como foi paga esta compra?</label><select id="fiscalPagamento"><option value="caixa">Dinheiro do caixa aberto</option><option value="outro">Pix / transferência / cartão</option><option value="prazo">A prazo (Contas a Pagar)</option><option value="dividido">Pagamento dividido (precisa conferir manualmente)</option></select></div>'+
      '<div class="ia-linha" id="fiscalVencBox" hidden><label for="fiscalVenc">Vencimento</label><input id="fiscalVenc" type="date"></div>'+
      '<p class="ia-aviso">Confira a soma dos itens com o total da nota. A leitura pode errar. Se houver pagamento dividido, revise e lance manualmente até a conferência da etapa de divisão estar disponível.</p>'+
      '<div class="btnrow"><button class="primary" type="button" id="fiscalConfirmarBtn" '+(bloqueada?'disabled':'')+'>Confirmar e lançar compra</button><button class="ghost" type="button" id="fiscalDescartarBtn">Descartar leitura</button></div><div id="fiscalConfirmarMsg" class="msg"></div></div>';
    $('fiscalPagamento').addEventListener('change',()=>{$('fiscalVencBox').hidden=$('fiscalPagamento').value!=='prazo';});
    $('fiscalConfirmarBtn').addEventListener('click',confirmar); $('fiscalDescartarBtn').addEventListener('click',descartar);
  }
  function norm(s){return String(s||'').normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLowerCase().trim();}
  async function confirmar(){
    const box=$('fiscalLeitorResultado'), m=$('fiscalConfirmarMsg'); if(!atual||!pode())return; if(atual.estado==='duplicada'||(atual.alertas||[]).some(a=>String(a).startsWith('BLOQUEIO:'))){m.textContent='Bloqueado: nota duplicada ou emitida pelo próprio Texas Burger. Nada foi gravado.';return;}
    const fornecedorId=$('fiscalFornecedor').value, pagamento=$('fiscalPagamento').value;
    if(!fornecedorId){m.textContent='Selecione um fornecedor cadastrado.';return;}
    const itens=Array.from(box.querySelectorAll('[data-fiscal-item]')).map(tr=>({descricao:tr.querySelector('[data-k="descricao"]').value.trim(),quantidade:Number(tr.querySelector('[data-k="quantidade"]').value),unidade:tr.querySelector('[data-k="unidade"]').value.trim()||'un',valorTotal:Number(tr.querySelector('[data-k="valorTotal"]').value),ingredienteId:tr.querySelector('[data-k="ingredienteId"]').value||undefined}));
    if(!itens.length||itens.some(i=>!i.descricao||!Number.isFinite(i.quantidade)||i.quantidade<=0||!Number.isFinite(i.valorTotal)||i.valorTotal<0)){m.textContent='Revise descrição, quantidade e valor de todos os itens.';return;}
    const soma=Math.round(itens.reduce((s,i)=>s+i.valorTotal,0)*100)/100,total=Math.round(Number($('fiscalTotal').value)*100)/100;
    if(!Number.isFinite(total)||total<=0){m.textContent='Informe o total correto da nota.';return;}
    if(Math.abs(soma-total)>0.05&&!confirm('A soma dos itens ('+fmt(soma)+') difere do total da nota ('+fmt(total)+'). Deseja continuar mesmo assim?'))return;
    if(pagamento==='dividido'){m.textContent='Pagamento dividido ainda precisa ser lançado manualmente para não distorcer caixa e contas a pagar. Nada foi gravado.';return;}
    if(pagamento==='prazo'&&!$('fiscalVenc').value){m.textContent='Informe o vencimento da conta a pagar.';return;}
    if(!confirm('Confirmar a compra de '+fmt(total)+'? Esta ação lançará os itens no estoque e no financeiro.'))return;
    const btn=$('fiscalConfirmarBtn');btn.disabled=true;m.textContent='Gravando compra…';
    try{
      const r=await apiCall('registrarCompra',{requisicaoId:'fiscal-'+atual.id,fornecedorId,data:atual.dataEmissao||new Date().toISOString().slice(0,10),status:'Recebida',pagamento:pagamento==='prazo'?'A pagar':'Pago',vencimento:pagamento==='prazo'?$('fiscalVenc').value:'',saiuDoCaixa:pagamento==='caixa',observacao:$('fiscalObs').value.trim(),origem:'ia',itens});
      if(!r||!r.ok)throw new Error((r&&r.message)||'Não foi possível gravar a compra.');
      await chamarLeitor({acao:'confirmar',leituraId:atual.id,compraId:r.id||null});
      m.textContent='Compra confirmada. '+(r.message||'Estoque e financeiro atualizados.')+' · Leitura registrada por '+(currentUser.login||currentUser.nome||'usuário')+'.';btn.disabled=true;carregarHistorico();$('fiscalDescartarBtn').disabled=true;
      try{if(typeof carregarCompras_==='function')await carregarCompras_();}catch(_){}
    }catch(e){m.textContent=(e.message||'Falha ao gravar.')+' Confira Compras recentes antes de tentar novamente.';btn.disabled=false;}
  }
  async function descartar(){ if(!atual||!confirm('Descartar esta leitura? Nada será lançado.'))return; try{await chamarLeitor({acao:'descartar',leituraId:atual.id});$('fiscalLeitorResultado').innerHTML='';msg('Leitura descartada. Nada foi lançado.','ok');atual=null;}catch(e){msg(e.message||'Não foi possível descartar.','warn');} }
  function dataHora(v){if(!v)return '—';try{return new Date(v).toLocaleString('pt-BR',{dateStyle:'short',timeStyle:'short'});}catch(_){return String(v);}}
  function htmlHistorico(lista){
    if(!Array.isArray(lista)||!lista.length)return '<div class="notif-empty">Nenhuma nota fiscal lida pelo Tex ainda.</div>';
    return lista.map(x=>'<div class="notif-card"><b>🧾 Lida pelo Tex</b> · '+esc(x.emitente_nome||'Emitente não identificado')+'<div class="obs-line">'+esc(x.data_emissao||'Data não identificada')+' · Documento '+esc(x.numero_documento||'—')+' · '+fmt(x.total||0)+'</div><div class="obs-line">Estado: '+esc(x.estado||'lida')+(x.compra_id?' · Compra vinculada':'')+'</div><div class="obs-line">Lida por: '+esc(x.lido_por||'—')+' · '+dataHora(x.criada_em)+'</div>'+(x.estado==='confirmada'?'<div class="obs-line">Confirmada por: '+esc(x.confirmado_por||'—')+' · '+dataHora(x.confirmada_em)+'</div>':'')+'</div>').join('');
  }
  async function carregarHistorico(){
    if(!pode())return;
    const a=$('fiscalLeitorHistorico'),b=$('fiscalHistoricoFinanceiroLista');
    try{const r=await chamarLeitor({acao:'historico'});const h=htmlHistorico(r.leituras||[]);if(a)a.innerHTML=h;if(b)b.innerHTML=h;}
    catch(e){const h='<div class="notif-empty">Não foi possível carregar o histórico agora.</div>';if(a)a.innerHTML=h;if(b)b.innerHTML=h;}
  }
  function init(){ if(!pode())return; card(); carregarHistorico(); }
  document.addEventListener('DOMContentLoaded',init); const old=window.IA&&window.IA.abrirAba; if(window.IA&&typeof old==='function')window.IA.abrirAba=async function(){await old.apply(this,arguments);init();};
  window.fiscalLeitorAbrir_=init;
})();
