/* ---------- ACOMPANHAMENTO PÚBLICO DO PEDIDO (ITEM 2.4) ----------
   Não depende mais de parâmetro na URL (isso travava o sistema interno
   quando ?pedido= ficava preso num atalho/aba fixa do caixa). O histórico
   de pedidos do cliente fica salvo no localStorage do próprio aparelho
   e é lido quando ele toca em "Acompanhe seu pedido" no rodapé. */
const HISTORICO_PEDIDOS_CLIENTE_KEY = 'txb_historico_pedidos_cliente';
const ETAPAS_PEDIDO = ['Recebido','Aceito/Em preparo','Pronto/Saiu pra entrega','Entregue/Retirado'];
let acompanhamentoIntervalId = null;

function salvarPedidoNoHistoricoCliente(codigo, nomeCliente, numero){
  if(!codigo) return;
  try{
    const historico = lerHistoricoPedidosCliente();
    if(!historico.some(p=>p.codigo===codigo)){
      historico.unshift({ codigo, nome: nomeCliente || '', numero: numero || 0, timestamp: Date.now() });
      localStorage.setItem(HISTORICO_PEDIDOS_CLIENTE_KEY, JSON.stringify(historico.slice(0,20)));
    }
  } catch(e){ /* localStorage indisponível — o cliente só não verá o histórico depois */ }
}
function lerHistoricoPedidosCliente(){
  try{
    const raw = localStorage.getItem(HISTORICO_PEDIDOS_CLIENTE_KEY);
    return raw ? JSON.parse(raw) : [];
  } catch(e){ return []; }
}
function etapaAtualPedido(r){
  if(r.status==='Cancelada') return -1;
  if(r.statusPedido==='Recebido') return 0;
  if(r.statusPedido==='Em preparo' || r.statusPedido==='Suspenso') return 1;
  if(r.statusPedido==='Pronta' || r.statusPedido==='Saiu para entrega') return 2;
  if(r.statusPedido==='Entregue' || r.statusPedido==='Retirada' || r.statusPedido==='Servida') return 3;
  return 0;
}
function abrirAcompanhamentoPedido(){
  const historico = lerHistoricoPedidosCliente();
  document.getElementById('acompanhamentoConteudo').innerHTML = '<p class="sub">Carregando...</p>';
  document.getElementById('acompanhamentoPedido').classList.add('open');
  if(!historico.length){
    document.getElementById('acompanhamentoConteudo').innerHTML = '<p class="sub">Nenhum pedido encontrado neste aparelho. O acompanhamento funciona no mesmo navegador usado pra fazer o pedido.</p>';
    return;
  }
  if(historico.length === 1){ abrirStatusPedido(historico[0].codigo); return; }
  mostrarListaPedidosCliente(historico);
}
function mostrarListaPedidosCliente(historico){
  if(acompanhamentoIntervalId){ clearInterval(acompanhamentoIntervalId); acompanhamentoIntervalId = null; }
  const linhas = historico.map(p=>{
    const data = new Date(p.timestamp).toLocaleString('pt-BR',{day:'2-digit',month:'2-digit',hour:'2-digit',minute:'2-digit'});
    return `<button class="ghost" style="display:block;width:100%;text-align:left;margin-bottom:8px;" onclick="abrirStatusPedido('${p.codigo}')">Pedido ${p.numero?('nº '+p.numero):('#'+p.codigo)} — ${data}</button>`;
  }).join('');
  document.getElementById('acompanhamentoConteudo').innerHTML = `<h2>Seus pedidos</h2><p class="sub">Toque num pedido pra ver o status.</p>${linhas}`;
}
function abrirStatusPedido(codigo){
  if(acompanhamentoIntervalId){ clearInterval(acompanhamentoIntervalId); acompanhamentoIntervalId = null; }
  carregarStatusPedido(codigo);
  acompanhamentoIntervalId = setInterval(()=>{ if(!document.hidden) carregarStatusPedido(codigo); }, 20000);
}
/* ITEM 12 — botão de voltar à lista (só quando há mais de um pedido neste aparelho) */
function acompanhamentoVoltarHtml_(){
  return lerHistoricoPedidosCliente().length > 1
    ? '<button type="button" class="ac-voltar" onclick="voltarParaListaPedidos()">← Todos os pedidos</button>'
    : '';
}
function voltarParaListaPedidos(){
  mostrarListaPedidosCliente(lerHistoricoPedidosCliente()); // já para a atualização automática
}
async function carregarStatusPedido(codigo){
  const box = document.getElementById('acompanhamentoConteudo');
  const voltar = acompanhamentoVoltarHtml_();
  try{
    const r = await apiCall('getStatusPedidoPublico', { codigo });
    if(!r.ok){ if(acompanhamentoIntervalId){ clearInterval(acompanhamentoIntervalId); acompanhamentoIntervalId = null; } box.innerHTML = voltar + '<p class="sub">'+escH(r.message||'Pedido não encontrado.')+'</p>'; return; }
    if(r.status==='Cancelada'){
      box.innerHTML = voltar + `<h2>Pedido cancelado</h2><p class="sub">${escH(r.motivoCancelamento || 'Esse pedido foi cancelado.')}</p>`;
      return;
    }
    const etapa = etapaAtualPedido(r);
    const linhasEtapas = ETAPAS_PEDIDO.map((nome,i)=>`<div class="obs-line" style="color:${i<=etapa?'var(--gold)':'var(--muted)'};font-weight:${i===etapa?'700':'400'};">${i<=etapa?'✅':'⬜'} ${nome}</div>`).join('');
    const aReceber = r.statusPagamento==='A Receber' ? '<p class="sub" style="margin-top:8px;">💰 Pagamento a combinar na entrega/retirada.</p>' : '<p class="sub" style="margin-top:8px;">✅ Pagamento confirmado.</p>';
    box.innerHTML = voltar + `<h2>Pedido${r.numero?' nº '+r.numero:''} de ${escH(r.clienteNome||'você')}</h2>
      <p class="sub">${escH(r.itens.join(', '))}</p>
      <p class="sub">Total: <b style="color:var(--gold);">${formatarMoeda(r.valorTotal)}</b></p>
      <div style="margin-top:14px;">${linhasEtapas}</div>
      ${aReceber}
      <div id="acLocal"></div>
      ${window.chatPublicoLigado_===true ? `<div style="margin-top:14px;"><button type="button" class="ghost" onclick="abrirAjudaPedidoDoAcompanhamento_('${codigo}','${String(r.numero||'').replace(/\D/g,'')}')">🆘 Preciso de ajuda</button></div>` : ''}
      ${r.podeCancelar ? `<div style="margin-top:14px;"><button type="button" class="ghost" id="acCancelarBtn" onclick="cancelarPedidoPeloCliente('${codigo}')">✖ Cancelar pedido (<span id="acCancelarSeg">${r.segundosParaCancelar}</span>s)</button><p class="sub" style="margin-top:6px;">Você pode cancelar nos primeiros 3 minutos, enquanto o restaurante ainda não aceitou.</p><div id="acCancelarMsg" class="msg"></div></div>` : ''}`;
    iniciarContagemCancelar_(r.podeCancelar ? r.segundosParaCancelar : 0);
    if(window.acLocalAtualizar_) acLocalAtualizar_(codigo, r);
  } catch(e){ box.innerHTML = voltar + '<p class="sub">Não foi possível atualizar agora. Tentando de novo em instantes...</p>'; }
}
/* ITEM 3.4 — cliente cancela o próprio pedido (cardápio comum). O servidor é quem decide (status, 3 min, limite por telefone). */
let _acCancelarTimer_ = null;
function iniciarContagemCancelar_(seg){
  if(_acCancelarTimer_){ clearInterval(_acCancelarTimer_); _acCancelarTimer_ = null; }
  if(!seg) return;
  let resta = seg;
  _acCancelarTimer_ = setInterval(()=>{
    resta--;
    const el = document.getElementById('acCancelarSeg');
    if(!el || resta <= 0){ clearInterval(_acCancelarTimer_); _acCancelarTimer_ = null; const b = document.getElementById('acCancelarBtn'); if(b) b.parentElement.remove(); return; }
    el.textContent = resta;
  }, 1000);
}
let _acCancelando_ = false;
async function cancelarPedidoPeloCliente(codigo){
  if(_acCancelando_) return;
  if(!confirm('Cancelar este pedido?')) return;
  _acCancelando_ = true;
  const btn = document.getElementById('acCancelarBtn'); if(btn) btn.disabled = true;
  try{
    const r = await apiCall('cancelarPedidoCardapioPublico', { codigo });
    if(r && r.ok){ iniciarContagemCancelar_(0); await carregarStatusPedido(codigo); }
    else { showMsg('acCancelarMsg', (r && r.message) || 'Não foi possível cancelar. Ligue para o restaurante.', 'warn'); if(btn) btn.disabled = false; }
  } catch(e){ showMsg('acCancelarMsg', 'Sem conexão agora. Tente de novo ou ligue para o restaurante.', 'warn'); if(btn) btn.disabled = false; }
  finally{ _acCancelando_ = false; }
}
function voltarParaCardapio(){
  iniciarContagemCancelar_(0);
  if(acompanhamentoIntervalId){ clearInterval(acompanhamentoIntervalId); acompanhamentoIntervalId = null; }
  document.getElementById('acompanhamentoPedido').classList.remove('open');
}
document.addEventListener('keydown', function(e){
  if(e.key === 'Escape' && document.getElementById('acompanhamentoPedido').classList.contains('open')) voltarParaCardapio();
});
function mostrarLinkAcompanhamento(vendaId, nomeCliente, numero){
  if(!vendaId) return;
  const codigo = vendaId.slice(-8);
  salvarPedidoNoHistoricoCliente(codigo, nomeCliente, numero);
}
/* ---------- CACHE DO CARDÁPIO NO CELULAR (Etapa 2) ----------
   Abre na hora com o último cardápio salvo e atualiza em segundo plano. Preço e disponibilidade são
   sempre conferidos pelo servidor quando o pedido é enviado, então um cache velho nunca vende errado. */
const CD_CACHE_KEY_ = 'cdCache_v1';
function cdLerCache_(){ try{ const r = JSON.parse(localStorage.getItem(CD_CACHE_KEY_)||'null'); return (r && r.dados && r.dados.produtos) ? r : null; }catch(e){ return null; } }
function cdSalvarCache_(dados){ try{ localStorage.setItem(CD_CACHE_KEY_, JSON.stringify({ t: Date.now(), dados })); }catch(e){} }
/* Busca o cardápio no Supabase (o caminho antigo, pela planilha, foi retirado). */
async function cdBuscarGet_(versaoAtual){
  const d = await sbCardapioPublico_(); if(d && d.manutencao){ mostrarManutencao_(d.message); throw new Error('manutencao'); } if(!d || !d.produtos) throw new Error('Resposta inválida'); return d;
}
/* Estado mostrado ao cliente: cardápio fechado pelo restaurante (mensagem dele) > caixa fechado > aberto. */
function cdStatusTexto_(){
  if(cdDados && cdDados.cardapioBloqueio && !mesaQr) return '🔴 ' + cdDados.cardapioBloqueio;
  return cdDados && cdDados.caixaAberto ? '🟢 Estamos abertos' : '🔴 Estamos fechados no momento';
}
function cdPintar_(deCache){
  document.getElementById('cdStatusCaixa').textContent = modoContingenciaAtivo ? '🟠 Estamos com instabilidade — seu pedido pode demorar um pouco mais pra ser confirmado' : (deCache ? '⏳ Atualizando…' : cdStatusTexto_());
  if(cdDados.config){
    document.getElementById('cdKicker').textContent = cdDados.config.kicker;
    document.getElementById('cdFrase').textContent = cdDados.config.frase;
    const infoEl = document.getElementById('cdInfoRestaurante'), infoH = cdInfoRestauranteHtml_(cdDados.config.restaurante);
    if(infoEl){ infoEl.innerHTML = infoH; infoEl.style.display = infoH ? '' : 'none'; }
  }
  renderCdCategorias();
  renderCdSecoes();
  if(!deCache) { try{ cdOferecerCarrinhoSalvo_(); }catch(e){} }
  const selForma = document.getElementById('cdFormaPagamento');
  const formaAtual = selForma.value;
  selForma.innerHTML = (cdDados.formasPagamento||[]).map(f=>`<option value="${f.id}">${escH(f.nome)}</option>`).join('');
  if(formaAtual && Array.from(selForma.options).some(o=>o.value===formaAtual)) selForma.value = formaAtual;
  onMudarFormaPagamentoCd();
  if(mesaQr && !_modoMesaIniciado){ _modoMesaIniciado = true; iniciarModoMesa_(); }
}
/* Visitas ao cardápio: 1 por aparelho por dia. Aparelho que já entrou no sistema interno (equipe) nunca conta. */
function cdContarVisita_(){
  setTimeout(async ()=>{
    try{
      if(typeof currentUser !== 'undefined' && currentUser) return;
      if(localStorage.getItem('cdAparelhoEquipe') === '1' || localStorage.getItem(SESSAO_KEY)) return;
      const hoje = dataLocalISO(new Date());
      if(localStorage.getItem('cdVisitaDia') === hoje) return;
      let ap = localStorage.getItem('cdAparelhoId');
      if(!ap || !/^[a-z0-9]{16,40}$/.test(ap)){ ap = Array.from(crypto.getRandomValues(new Uint8Array(12)), b=>b.toString(16).padStart(2,'0')).join(''); localStorage.setItem('cdAparelhoId', ap); }
      const r = await sbRpcPublico_('api_registrar_visita_cardapio', { p:{ aparelho: ap } });
      if(r && r.ok) localStorage.setItem('cdVisitaDia', hoje);
    }catch(e){}
  }, 3000);
}
async function carregarCardapioPublico(){
  if(!window._cdVisitaChamada_){ window._cdVisitaChamada_ = true; cdContarVisita_(); }
  try{ if(!mesaQr && window.cdCapturarLocalSilenciosa_) window.cdCapturarLocalSilenciosa_(); }catch(e){}
  if(!window._cdAvisosChamado_){ window._cdAvisosChamado_ = true; setTimeout(()=>{ if(window.cdAvisosIniciar_) window.cdAvisosIniciar_(); }, 1200); }
  const cache = cdLerCache_();
  if(cache){ cdDados = cache.dados; modoContingenciaAtivo = false; cdPintar_(true); }
  try{
    const fresco = await cdBuscarGet_(cache && cache.dados ? cache.dados.versao : '');
    if(fresco.igual){ // ITEM 18: nada mudou no servidor — não redesenha (evita "pulo" na rolagem), só confirma aberto/fechado
      modoContingenciaAtivo = false;
      document.getElementById('cdStatusCaixa').textContent = cdStatusTexto_();
      return;
    }
    cdDados = fresco; modoContingenciaAtivo = false;
    cdSalvarCache_(fresco);
    cdPintar_(false);
    return;
  } catch(e){ /* principal fora do ar: tenta a contingência abaixo */ }
  const semCardapio = ()=>{ if(!cache) document.getElementById('cdListaProdutos').innerHTML = '<p class="sub">Não foi possível carregar o cardápio agora. Tente novamente em instantes.</p>'; };
  try{
    const rEspelho = await fetchContingencia_({
      method: 'post', body: JSON.stringify({ action: 'getEspelhoPublico', chave: CONTINGENCIA_CHAVE_PUBLICA })
    }, TIMEOUT_CONT_LEITURA_MS_, 0);
    if(!rEspelho.ok || !rEspelho.espelho || !rEspelho.espelho.produtos){ semCardapio(); return; }
    cdDados = adaptarEspelhoParaCardapio(rEspelho.espelho);
    modoContingenciaAtivo = true;
    setConexaoStatus('contingencia');
  } catch(e2){ semCardapio(); return; }
  cdPintar_(false);
}
/* Transforma o espelho (dados brutos das tabelas) no mesmo formato que
   getCardapioPublico() devolveria — pra reaproveitar toda a renderização
   do cardápio sem precisar de uma versão paralela dela. */
function adaptarEspelhoParaCardapio(espelho){
  const categorias = (espelho.categorias||[]).filter(c=>c.ativa);
  const usaReserva = x => Object.assign({}, x, { fotoUrl: x.fotoReservaId ? ('https://drive.google.com/uc?export=view&id=' + x.fotoReservaId) : (x.fotoUrl || '') });
  const produtos = (espelho.produtos||[]).filter(p=>p.ativo).sort((a,b)=>(a.ordemCardapio||0)-(b.ordemCardapio||0)).map(usaReserva);
  const combos = (espelho.combos||[]).filter(c=>c.ativo).sort((a,b)=>(a.ordemCardapio||0)-(b.ordemCardapio||0)).map(usaReserva);
  const formasPagamento = (espelho.formasPagamento||[]).filter(f=>f.ativa && f.visivelCardapio);
  return {
    categorias, produtos, combos, formasPagamento,
    produtoPrecos: espelho.produtoPrecos||[], comboPrecos: espelho.comboPrecos||[],
    adicionais: (espelho.adicionais||[]).filter(a=>a.ativo), produtoAdicionais: espelho.produtoAdicionais||[], comboItens: espelho.comboItens||[],
    maisPedidos: [], esgotados: { produtos: [], combos: [] }, config: espelho.configCardapio || { kicker:'', frase:'' },
    caixaAberto: true,
    cardapioBloqueio: cdBloqueioDoEspelho_((espelho.configCardapio||{}).fechamento)
  };
}
/* Contingência: o espelho leva as regras de fechamento; a data é conferida no aparelho (o servidor não está disponível). */
function cdBloqueioDoEspelho_(f){
  try{
    if(!f) return '';
    if(f.manual && String(f.manual.ativo)==='true') return String(f.manual.mensagem||'').trim() || 'Estamos fechados no momento. Voltamos em breve!';
    const hoje = new Date(Date.now()-3*3600000).toISOString().slice(0,10);
    const p = (f.periodos||[]).find(x=>String(x.inicio).slice(0,10) <= hoje && hoje <= String(x.fim).slice(0,10));
    return p ? (String(p.mensagem||'').trim() || 'Estamos fechados neste período. Voltamos em breve!') : '';
  }catch(e){ return ''; }
}

function renderCdCategorias(){
  const cont = document.getElementById('cdCategorias');
  const cats = cdDados.categorias || [];
  cont.innerHTML = '<button class="'+(cdCategoriaAtiva==='todas'?'active':'')+'" onclick="selecionarCdCategoria(\'todas\')">Todas</button>' +
    cats.map(c=>`<button class="${cdCategoriaAtiva===c.id?'active':''}" onclick="selecionarCdCategoria('${c.id}')">${escH(c.nome)}</button>`).join('');
  if(!cont._bordasOk){
    cont._bordasOk = true;
    cont.addEventListener('scroll', cdAtualizarBordasCategorias_, { passive:true });
    window.addEventListener('resize', cdAtualizarBordasCategorias_);
  }
  // centraliza a categoria escolhida (só na própria barra, sem rolar a página)
  const ativo = cont.querySelector('button.active');
  if(ativo){ cont.scrollTo({ left: Math.max(0, ativo.offsetLeft - (cont.clientWidth - ativo.offsetWidth)/2), behavior:'smooth' }); }
  cdAtualizarBordasCategorias_();
  setTimeout(cdAtualizarBordasCategorias_, 300); // depois que a fonte carrega e o layout assenta
}
function cdAtualizarBordasCategorias_(){
  const c = document.getElementById('cdCategorias'); if(!c) return;
  const max = c.scrollWidth - c.clientWidth;
  c.style.setProperty('--fade-esq', c.scrollLeft > 4 ? '30px' : '0px');
  c.style.setProperty('--fade-dir', (max > 4 && c.scrollLeft < max - 4) ? '30px' : '0px');
}
function selecionarCdCategoria(id){ cdCategoriaAtiva = id; renderCdCategorias(); renderCdSecoes(); }

/* Forma de pagamento escolhida no carrinho (ou a primeira do cardápio). */
function cdFormaAtualId_(){
  const s = document.getElementById('cdFormaPagamento');
  if(s && s.value) return s.value;
  const f = (cdDados && cdDados.formasPagamento || [])[0];
  return f ? f.id : '';
}
function cdFormaAtual_(){ const id = cdFormaAtualId_(); return ((cdDados && cdDados.formasPagamento) || []).find(f=>f.id===id) || null; }
/* Preço único: o item custa o mesmo em qualquer forma; o que muda é o acréscimo da forma de pagamento. */
function cdPrecoDe(tipo, id){
  const lista = tipo==='produto' ? (cdDados.produtoPrecos||[]) : (cdDados.comboPrecos||[]);
  const chave = tipo==='produto' ? 'produtoId' : 'comboId';
  const ref = (cdDados.formasPagamento||[])[0];
  const preco = (ref && lista.find(p=>p[chave]===id && p.formaPagamentoId===ref.id)) || lista.find(p=>p[chave]===id);
  return preco ? Number(preco.preco) : null;
}
function cdAcrescimoDe_(forma, base){
  if(!forma || !(base > 0)) return 0;
  return Math.round((base * (forma.acrescimoPct||0) / 100 + (forma.acrescimoFixo||0)) * 100) / 100;
}
/* Aviso ao cliente: a forma escolhida tem acréscimo. */
function cdAtualizarAvisoForma_(){
  const el = document.getElementById('cdAvisoForma'); if(!el) return;
  const acr = acrescimoCdAtual_();
  if(!(acr > 0)){ el.style.display = 'none'; return; }
  const f = cdFormaAtual_();
  const semAcr = ((cdDados && cdDados.formasPagamento) || []).filter(x=>!(x.acrescimoPct>0) && !(x.acrescimoFixo>0));
  el.style.display = 'block';
  el.innerHTML = '⚠️ <b>Atenção:</b> pagando em <b>' + escH(f.nome) + '</b> você paga <b>' + cdFormatarPreco(acr) + ' a mais</b> (acréscimo da forma de pagamento). Total com acréscimo: <b>' + cdFormatarPreco(totalCarrinhoCd()) + '</b>.'
    + (semAcr.length ? ' Em ' + semAcr.map(x=>escH(x.nome)).join(' ou ') + ' não há acréscimo.' : '');
}
function cdFormatarPreco(v){ return v==null ? 'Consulte' : formatarMoeda(v); }

function cdEsgotado_(tipo, id){ const e = (cdDados && cdDados.esgotados) || {}; return ((tipo==='produto' ? e.produtos : e.combos) || []).indexOf(id) !== -1; }
function cdCardHTML(tipo, item){
  const preco = cdPrecoDe(tipo, item.id);
  const foto = item.fotoUrl || '';
  const esg = cdEsgotado_(tipo, item.id);
  return `<div class="cd-card${esg?' esgotado':''}">
    ${foto?`<img src="${fotoSrc_(foto, 500)}" onerror="fotoFalhou_(this)" loading="lazy" decoding="async" alt="" onclick="cdAmpliarFoto_('${tipo}','${item.id}')" style="cursor:zoom-in;">`:''}
    <div class="cd-info">
      <div class="cd-nome">${escH(item.nome)}</div>
      ${item.descricao?`<div class="cd-desc">${escH(item.descricao)}</div>`:''}
      <div class="cd-linha"><div class="cd-preco">${cdFormatarPreco(preco)}</div>
      ${esg?'<button class="cd-add esg" disabled>Esgotado</button>':`<button class="cd-add" aria-label="Adicionar ${escH(item.nome)}" onclick="abrirCdItemModal('${tipo}','${item.id}')">+</button>`}</div>
    </div>
  </div>`;
}

function renderCdSecoes(){
  const visaoTodas = cdCategoriaAtiva==='todas';

  // item completo do cadastro (maisPedidos vem sem descrição)
  const completo = (m)=> ((m.tipo==='produto' ? cdDados.produtos : cdDados.combos)||[]).find(x=>x.id===m.id) || m;

  const maisPedidos = visaoTodas ? (cdDados.maisPedidos||[]) : [];
  const idsMais = new Set(maisPedidos.map(m=>m.tipo+':'+m.id));

  // Destaques: não repete o que já está em "Mais pedidos"
  const destaques = [
    ...(cdDados.produtos||[]).filter(p=>p.destaque).map(p=>({ tipo:'produto', item:p })),
    ...(cdDados.combos||[]).filter(c=>c.destaque).map(c=>({ tipo:'combo', item:c }))
  ].filter(d=> !idsMais.has(d.tipo+':'+d.item.id));

  // ITEM 4: o que já aparece em cima não se repete em Produtos/Combos (só na visão "Todas")
  const jaMostrados = new Set(idsMais);
  if(visaoTodas) destaques.forEach(d=>jaMostrados.add(d.tipo+':'+d.item.id));

  const produtos = (cdDados.produtos||[]).filter(p=> (visaoTodas || p.categoria===cdCategoriaAtiva) && !jaMostrados.has('produto:'+p.id));
  const combos   = (cdDados.combos||[]).filter(c=> (visaoTodas || c.categoria===cdCategoriaAtiva) && !jaMostrados.has('combo:'+c.id));

  const maisPedidosEl = document.getElementById('cdMaisPedidos');
  const destaquesEl = document.getElementById('cdDestaques');
  if(maisPedidos.length){
    maisPedidosEl.innerHTML = '<div class="cd-secao-titulo">⭐ Mais pedidos</div><div class="cd-grid cd-cat-lista">' +
      maisPedidos.map(m=>cdCardHTML(m.tipo, completo(m))).join('') + '</div>';
  } else maisPedidosEl.innerHTML = '';

  if(visaoTodas && destaques.length){
    destaquesEl.innerHTML = '<div class="cd-secao-titulo">📌 Destaques</div><div class="cd-grid cd-cat-lista">' +
      destaques.map(d=>cdCardHTML(d.tipo, d.item)).join('') + '</div>';
  } else destaquesEl.innerHTML = '';

  const listaEl = document.getElementById('cdListaProdutos');

  if(!visaoTodas){
    let html = '';
    if(produtos.length) html += '<div class="cd-secao-titulo">Produtos</div><div class="cd-grid">' + produtos.map(p=>cdCardHTML('produto',p)).join('') + '</div>';
    if(combos.length)   html += '<div class="cd-secao-titulo">Combos</div><div class="cd-grid">'   + combos.map(c=>cdCardHTML('combo',c)).join('')   + '</div>';
    // só diz "nada disponível" se realmente não há nada (nem em cima, nem embaixo)
    if(!produtos.length && !combos.length && !jaMostrados.size) html = '<p class="sub">Nada disponível nessa categoria no momento.</p>';
    listaEl.innerHTML = html;
    return;
  }

  // "Todas": cada categoria com seu título; no celular o bloco rola para o lado, no PC é grade
  let html = '';
  let total = jaMostrados.size;
  (cdDados.categorias||[]).forEach(cat => {
    const prods = (cdDados.produtos||[]).filter(p => p.categoria===cat.id && !jaMostrados.has('produto:'+p.id));
    const cbos  = (cdDados.combos||[]).filter(c => c.categoria===cat.id && !jaMostrados.has('combo:'+c.id));
    if(!prods.length && !cbos.length) return;
    total += prods.length + cbos.length;
    html += `<section class="cd-cat-bloco"><div class="cd-secao-titulo">${escH(cat.nome)}</div>`
          + `<div class="cd-grid cd-cat-lista">`
          + prods.map(p=>cdCardHTML('produto',p)).join('')
          + cbos.map(c=>cdCardHTML('combo',c)).join('')
          + `</div></section>`;
  });
  const orfP = (cdDados.produtos||[]).filter(p => !p.categoria && !jaMostrados.has('produto:'+p.id));
  const orfC = (cdDados.combos||[]).filter(c => !c.categoria && !jaMostrados.has('combo:'+c.id));
  if(orfP.length || orfC.length){
    total += orfP.length + orfC.length;
    html += `<section class="cd-cat-bloco"><div class="cd-secao-titulo">Outros</div><div class="cd-grid cd-cat-lista">`
          + orfP.map(p=>cdCardHTML('produto',p)).join('')
          + orfC.map(c=>cdCardHTML('combo',c)).join('')
          + `</div></section>`;
  }
  if(!total) html = '<p class="sub">Nada disponível no momento.</p>';
  listaEl.innerHTML = html;
}

/* ---------- MODAL DE ITEM (quantidade + adicionais) ITEM 20 ---------- */
function cdAmpliarFoto_(tipo, id){
  const item = ((tipo==='produto' ? cdDados.produtos : cdDados.combos)||[]).find(x=>x.id===id); if(!item || !item.fotoUrl) return;
  let ov = document.getElementById('cdFotoOv'); if(ov) ov.remove();
  ov = document.createElement('div'); ov.id = 'cdFotoOv';
  const esg = cdEsgotado_(tipo, id), preco = cdFormatarPreco(cdPrecoDe(tipo, id));
  const fechar = () => { const o = document.getElementById('cdFotoOv'); if(o) o.remove(); };
  const box = document.createElement('div'); box.className = 'cdfo-box';
  const img = document.createElement('img'); img.src = fotoSrc_(item.fotoUrl, 1000); img.alt = '';
  const info = document.createElement('div'); info.className = 'cdfo-info';
  const nome = document.createElement('div'); nome.className = 'cdfo-nome'; nome.textContent = item.nome;
  info.appendChild(nome);
  if(item.descricao){ const d = document.createElement('div'); d.className = 'cdfo-desc'; d.textContent = item.descricao; info.appendChild(d); }
  const pr = document.createElement('div'); pr.className = 'cdfo-preco'; pr.textContent = preco; info.appendChild(pr);
  const b = document.createElement('button'); b.type = 'button'; b.className = 'cdfo-add'; b.textContent = esg ? 'Esgotado' : 'Adicionar'; b.disabled = esg;
  if(!esg) b.onclick = () => { fechar(); abrirCdItemModal(tipo, id); };
  const x = document.createElement('button'); x.type = 'button'; x.className = 'cdfo-x'; x.textContent = '✕'; x.setAttribute('aria-label', 'Fechar'); x.onclick = fechar;
  info.appendChild(b); box.appendChild(x); box.appendChild(img); box.appendChild(info); ov.appendChild(box);
  ov.addEventListener('click', e => { if(e.target === ov) fechar(); });
  document.body.appendChild(ov);
}
function abrirCdItemModal(tipo, id){
  const lista = tipo==='produto' ? cdDados.produtos : cdDados.combos;
  const item = lista.find(x=>x.id===id);
  if(!item) return;
  if(cdEsgotado_(tipo, id) || mesaBloqueada_) return;
  const preco = cdPrecoDe(tipo, id) || 0;
  let adicionaisDoItem = [];
  {
    // produto: os adicionais vinculados a ele; combo: os adicionais dos produtos que o compõem
    const produtoIds = tipo==='produto' ? [id] : (cdDados.comboItens||[]).filter(ci=>ci.comboId===id).map(ci=>ci.produtoId);
    const ids = (cdDados.produtoAdicionais||[]).filter(pa=>produtoIds.includes(pa.produtoId)).map(pa=>pa.adicionalId);
    adicionaisDoItem = (cdDados.adicionais||[]).filter(a=>ids.includes(a.id));
  }
  cdItemAtual = { tipo, id, nome: item.nome, precoBase: preco, qtd: 1, adicionaisDisponiveis: adicionaisDoItem, adicionaisEscolhidos: [] };
  document.getElementById('cdItemNome').textContent = item.nome;
  document.getElementById('cdItemDesc').textContent = item.descricao || '';
  document.getElementById('cdItemQtd').textContent = '1';
  { const av = document.getElementById('cdItemAvisoAdic'); if(av) av.style.display = 'none'; const ob = document.getElementById('cdItemObs'); if(ob) ob.value = ''; }
  const cont = document.getElementById('cdItemAdicionais');
  cont.innerHTML = adicionaisDoItem.length ? ('<div class="cd-secao-titulo" style="margin-top:6px;">Adicionais</div>' +
    adicionaisDoItem.map(a=>`<label class="cd-adicional-linha"><span><input type="checkbox" data-adid="${a.id}" onchange="toggleCdAdicional('${a.id}')"> ${escH(a.nome)}</span><span>+ ${cdFormatarPreco(a.preco)}</span></label>`).join('')) : '';
  atualizarCdItemTotal();
  document.getElementById('cdItemModal').classList.add('open');
}
function fecharCdItemModal(){ document.getElementById('cdItemModal').classList.remove('open'); cdItemAtual = null; }
function toggleCdAdicional(adId){
  if(!cdItemAtual) return;
  const ad = cdItemAtual.adicionaisDisponiveis.find(a=>a.id===adId);
  const idx = cdItemAtual.adicionaisEscolhidos.findIndex(a=>a.id===adId);
  if(idx>=0) cdItemAtual.adicionaisEscolhidos.splice(idx,1); else cdItemAtual.adicionaisEscolhidos.push(ad);
  atualizarAvisoAdicionaisCd_();
  atualizarCdItemTotal();
}
function cdAvisoQtdMax_(){ alert('O máximo é ' + QTD_MAX_ITEM_ + ' unidades por item. Para uma quantidade maior, fale com o restaurante.'); }
function alterarQtdCdItem(delta){
  if(!cdItemAtual) return;
  if(cdItemAtual.qtd + delta > QTD_MAX_ITEM_){ const q = document.getElementById('cdItemQtd'); if(q){ q.style.color = '#e74c3c'; setTimeout(()=>{ q.style.color = ''; }, 1200); } try{ cdAvisoQtdMax_(); }catch(e){} return; }
  cdItemAtual.qtd = Math.max(1, cdItemAtual.qtd + delta);
  document.getElementById('cdItemQtd').textContent = cdItemAtual.qtd;
  atualizarAvisoAdicionaisCd_();
  atualizarCdItemTotal();
}
/* Aviso: com mais de 1 unidade e adicionais marcados, eles valem para todas as unidades. */
function atualizarAvisoAdicionaisCd_(){
  const el = document.getElementById('cdItemAvisoAdic'); if(!el) return;
  el.style.display = (cdItemAtual && cdItemAtual.qtd > 1 && cdItemAtual.adicionaisDisponiveis.length) ? 'block' : 'none';
}
function atualizarCdItemTotal(){
  if(!cdItemAtual) return;
  const extra = cdItemAtual.adicionaisEscolhidos.reduce((s,a)=>s+a.preco,0);
  const total = (cdItemAtual.precoBase + extra) * cdItemAtual.qtd;
  document.getElementById('cdItemPrecoTotal').textContent = cdFormatarPreco(total);
}
function confirmarAddCarrinho(){
  if(!cdItemAtual) return;
  cdCarrinho.push({ tipo: cdItemAtual.tipo, id: cdItemAtual.id, nome: cdItemAtual.nome, precoBase: cdItemAtual.precoBase, qtd: cdItemAtual.qtd, adicionais: cdItemAtual.adicionaisEscolhidos.slice(), obs: ((document.getElementById('cdItemObs')||{}).value||'').trim().slice(0,100) });
  fecharCdItemModal();
  atualizarFabCarrinho();
}
function cdPrecoItemCarrinho(it){ return (it.precoBase + it.adicionais.reduce((s,a)=>s+a.preco,0)) * it.qtd; }
function subtotalCarrinhoCd(){ return Math.round(cdCarrinho.reduce((s,it)=>s+cdPrecoItemCarrinho(it),0)*100)/100; }
function taxaEntregaCdAtual(){ const tipo=(document.getElementById('cdTipoEntrega')||{}).value; const taxa=Number(cdDados.config&&cdDados.config.taxaEntrega)||0; return tipo==='Entrega' && !(cdCupomAplicado&&cdCupomAplicado.freteGratis) ? taxa : 0; }
function totalSemAcrescimoCd_(){ return Math.round((subtotalCarrinhoCd()+taxaEntregaCdAtual()-Number(cdCupomAplicado&&cdCupomAplicado.desconto||0))*100)/100; }
function acrescimoCdAtual_(){
  if((typeof mesaQr !== 'undefined' && mesaQr) || !cdCarrinho.length) return 0;   // mesa: o acréscimo entra no fechamento da conta
  return cdAcrescimoDe_(cdFormaAtual_(), Math.max(0.01, totalSemAcrescimoCd_() - taxaEntregaCdAtual()));   // o % não incide sobre a taxa de entrega
}
function totalCarrinhoCd(){ return Math.round((totalSemAcrescimoCd_() + acrescimoCdAtual_())*100)/100; }
function cdAtualizarTotal_(){
  const el = document.getElementById('cdCarrinhoTotal');
  if(el) el.textContent = cdFormatarPreco(cdCarrinho.length ? Math.max(0.01, totalCarrinhoCd()) : 0);
  cdAtualizarAvisoForma_();
}
/* Carrinho guardado só neste aparelho (não vai para o servidor). Vale 24 horas. */
var CD_CARRINHO_KEY_ = 'tb_carrinho_v1', _cdCarrinhoOferecido_ = false;
function cdSalvarCarrinho_(){
  try{
    if(typeof mesaQr !== 'undefined' && mesaQr) return;
    if(!cdCarrinho.length){ if(_cdCarrinhoOferecido_ || !localStorage.getItem(CD_CARRINHO_KEY_)) { localStorage.removeItem(CD_CARRINHO_KEY_); } return; }
    localStorage.setItem(CD_CARRINHO_KEY_, JSON.stringify({ em: Date.now(), itens: cdCarrinho.map(it=>({ tipo:it.tipo, id:it.id, qtd:it.qtd, obs:it.obs||'', adicionais:(it.adicionais||[]).map(a=>a.id) })) }));
  }catch(e){}
}
function cdLerCarrinhoSalvo_(){
  try{
    const j = JSON.parse(localStorage.getItem(CD_CARRINHO_KEY_) || 'null');
    if(!j || !Array.isArray(j.itens) || !j.itens.length || Date.now() - j.em > 24*3600*1000) { if(j) localStorage.removeItem(CD_CARRINHO_KEY_); return null; }
    return j;
  }catch(e){ return null; }
}
function cdOferecerCarrinhoSalvo_(){
  if(_cdCarrinhoOferecido_ || (typeof mesaQr !== 'undefined' && mesaQr) || cdCarrinho.length) return;
  const j = cdLerCarrinhoSalvo_(); if(!j) { _cdCarrinhoOferecido_ = true; return; }
  _cdCarrinhoOferecido_ = true;
  const n = j.itens.reduce((s,i)=>s+(Number(i.qtd)||0),0);
  document.getElementById('cdCarrinhoSalvoTxt').textContent = '🛒 Você deixou ' + n + (n===1?' item':' itens') + ' no carrinho. Quer continuar de onde parou?';
  document.getElementById('cdCarrinhoSalvo').style.display = 'block';
}
function cdDescartarCarrinhoSalvo_(){ try{ localStorage.removeItem(CD_CARRINHO_KEY_); }catch(e){} document.getElementById('cdCarrinhoSalvo').style.display = 'none'; }
function cdContinuarCarrinhoSalvo_(){
  const j = cdLerCarrinhoSalvo_(); document.getElementById('cdCarrinhoSalvo').style.display = 'none';
  if(!j) return;
  let perdidos = 0; const novo = [];
  j.itens.forEach(i=>{
    const lista = i.tipo==='produto' ? cdDados.produtos : cdDados.combos;
    const item = (lista||[]).find(x=>x.id===i.id);
    if(!item || cdEsgotado_(i.tipo, i.id)){ perdidos++; return; }
    const adicionais = (i.adicionais||[]).map(id=>(cdDados.adicionais||[]).find(a=>a.id===id)).filter(Boolean).map(a=>({ id:a.id, nome:a.nome, preco:Number(a.preco)||0 }));
    novo.push({ tipo:i.tipo, id:i.id, nome:item.nome, precoBase:cdPrecoDe(i.tipo, i.id)||0, qtd:Math.max(1, Math.min(99, Number(i.qtd)||1)), adicionais, obs:String(i.obs||'').slice(0,100) });
  });
  cdCarrinho = novo; atualizarFabCarrinho();
  if(perdidos) alert(perdidos + (perdidos===1?' item não está':' itens não estão') + ' mais disponível' + (perdidos===1?'':'is') + ' e ficou de fora. Os preços foram atualizados.');
  if(novo.length && typeof abrirCarrinhoPublico === 'function') { try{ abrirCarrinhoPublico(); }catch(e){} }
}
function atualizarFabCarrinho(){
  cdSalvarCarrinho_();
  const fab = document.getElementById('cdFabCarrinho');
  if(!cdCarrinho.length){ fab.classList.remove('show'); return; }
  const totalQtd = cdCarrinho.reduce((s,it)=>s+it.qtd,0);
  const totalValor = cdCarrinho.reduce((s,it)=>s+cdPrecoItemCarrinho(it),0);
  document.getElementById('cdFabQtd').textContent = totalQtd + (totalQtd===1?' item':' itens');
  document.getElementById('cdFabTotal').textContent = cdFormatarPreco(totalValor);
  fab.classList.add('show');
}

/* ---------- CARRINHO / CHECKOUT ---------- */
/* Nome e telefone do cliente ficam só no aparelho dele (silenciosamente) e voltam preenchidos no próximo pedido. O endereço NÃO é guardado: vem sempre pela localização. */
function cdPreencherContato_(){
  try{
    const nm = document.getElementById('cdNome'), tl = document.getElementById('cdTelefone');
    if(nm && !nm.value) nm.value = localStorage.getItem('cdClienteNome') || '';
    if(tl && !tl.value) tl.value = localStorage.getItem('cdClienteTel') || '';
  }catch(e){}
}
function cdGuardarContato_(nome, tel){ try{ if(nome) localStorage.setItem('cdClienteNome', String(nome).slice(0,80)); if(tel) localStorage.setItem('cdClienteTel', String(tel).slice(0,20)); }catch(e){} }
function abrirCarrinhoPublico(){
  if(mesaQr){
    const t = document.getElementById('cdTipoEntrega'); if(t) t.value = 'Retirada';
    const av = document.getElementById('cdAvisoMesa'); if(av){ av.textContent = '🍽️ Pedido da Mesa '+mesaQr.numero+'. O restaurante confirma antes de preparar e você paga no caixa, no final.'; av.style.display = ''; }
    const nm = document.getElementById('cdNome'); if(nm && !nm.value){ try{ nm.value = localStorage.getItem('cdNomeMesa')||''; }catch(e){} }
  }else{ cdPreencherContato_(); }
  cdCupomAplicado=null; if(document.getElementById('cdCupom'))document.getElementById('cdCupom').value=''; if(document.getElementById('cdCupomMsg'))document.getElementById('cdCupomMsg').textContent=''; if(document.getElementById('cdCupomResumo'))document.getElementById('cdCupomResumo').textContent='';
  renderCdCarrinho();
  onMudarTipoCdEntrega();
  document.getElementById('cdCarrinhoModal').classList.add('open');
  if(!mesaQr && window.contaPreencherCheckout_) window.contaPreencherCheckout_();   // conta do cliente: dados, endereços e cupons
}
let cdPedidoConcluido = false; // true depois que o pedido foi enviado: ao fechar a janela, o carrinho é esvaziado
function cdLimparAposPedido_(){
  cdPararContagemWa_();
  cdCarrinho = []; cdCupomAplicado = null; cdPedidoConcluido = false; try{ localStorage.removeItem(CD_CARRINHO_KEY_); }catch(e){}
  const v = (id, val)=>{ const el=document.getElementById(id); if(el) el.value = val; };
  v('cdCupom',''); v('cdObservacoes',''); v('cdTrocoPara','');
  const pt = document.getElementById('cdPrecisaTroco'); if(pt) pt.checked = false;
  const tb = document.getElementById('cdTrocoParaBox'); if(tb) tb.style.display = 'none';
  const cm = document.getElementById('cdCupomMsg'); if(cm) cm.textContent = '';
  const cr = document.getElementById('cdCupomResumo'); if(cr) cr.textContent = '';
  const ck = document.getElementById('cdCheckoutMsg'); if(ck){ ck.textContent = ''; ck.className = 'msg'; }
  const cf = document.getElementById('cdConfirmacaoPedido'); if(cf) cf.innerHTML = '';
  const btn = document.getElementById('cdEnviarPedidoBtn'); if(btn){ btn.disabled = false; btn.textContent = 'Enviar pedido'; }
  renderCdCarrinho(); atualizarFabCarrinho();
}
function fecharCarrinhoPublico(){
  document.getElementById('cdCarrinhoModal').classList.remove('open');
  if(cdPedidoConcluido) cdLimparAposPedido_();
}
function renderCdCarrinho(){
  const cont = document.getElementById('cdCarrinhoItens');
  if(!cdCarrinho.length){ cont.innerHTML = '<p class="sub">Seu carrinho está vazio.</p>'; }
  else cont.innerHTML = cdCarrinho.map((it,i)=>`<div class="cd-adicional-linha">
      <span>${it.qtd}x ${escH(it.nome)}${it.adicionais.length?' ('+it.adicionais.map(a=>escH(a.nome)).join(', ')+')':''}${it.obs?'<br><small style="color:var(--muted);">📝 '+escH(it.obs)+'</small>':''}</span>
      <span>${cdFormatarPreco(cdPrecoItemCarrinho(it))} <button class="link-btn" onclick="removerDoCarrinho(${i})">remover</button></span>
    </div>`).join('');
  cdAtualizarTotal_();
}
function removerDoCarrinho(i){ cdCarrinho.splice(i,1); renderCdCarrinho(); atualizarFabCarrinho(); }
/* CEP → rua e bairro (ViaCEP). Só preenche se o campo de endereço estiver vazio ou já tiver vindo de um CEP; o número é sempre do cliente. */
var _cepUltimo_ = {};
async function onDigitarCep_(inp, idEnd, idAviso){
  let d = String(inp.value).replace(/\D/g,'').slice(0,8);
  inp.value = d.length > 5 ? d.slice(0,5) + '-' + d.slice(5) : d;
  const aviso = document.getElementById(idAviso), campo = document.getElementById(idEnd);
  if(aviso) aviso.style.display = 'none';
  if(d.length !== 8 || !campo) return;
  try{
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 8000);
    const r = await fetch('https://viacep.com.br/ws/' + d + '/json/', { signal: ctl.signal });
    clearTimeout(t);
    const j = r.ok ? await r.json() : null;
    if(!j || j.erro){ if(aviso){ aviso.style.display = 'block'; aviso.textContent = 'CEP não encontrado. Digite o endereço normalmente.'; } return; }
    const txt = [j.logradouro, j.bairro].filter(Boolean).join(', ').replace(/[<>]/g,'').slice(0,120);
    const atual = campo.value.trim();
    if(txt && (!atual || atual === _cepUltimo_[idEnd] || (typeof cdEndAuto_ !== 'undefined' && cdEndAuto_ && idEnd==='cdEndereco'))){
      campo.value = (idEnd==='cdEndereco') ? txt : txt + ', '; _cepUltimo_[idEnd] = campo.value.trim(); if(idEnd==='cdEndereco') cdEndAuto_ = false;
      try{ campo.dispatchEvent(new Event('input', {bubbles:true})); }catch(e){}
    }
    if(idEnd==='cdEndereco' && j.localidade){ const cc = document.getElementById('cdCidade'); if(cc) cc.value = [j.localidade, j.uf].filter(Boolean).join(' - '); }
    if(aviso){ aviso.style.display = 'block'; aviso.textContent = '📍 ' + [j.localidade, j.uf].filter(Boolean).join(' - ') + (txt ? ' — confira e digite o número da casa.' : ' — este CEP não tem rua; digite o endereço.'); }
  }catch(e){ /* sem internet ou ViaCEP fora do ar: o cliente digita normalmente */ }
}
var cdEndAuto_ = false, cdEndTentou_ = false;

/* Endereço pré-preenchido pela localização (OpenStreetMap). Só rua e bairro: o número é sempre do cliente. */
async function cdPreencherEnderecoPorLocal_(){
  const campo = document.getElementById('cdEndereco'), aviso = document.getElementById('cdEnderecoAviso');
  if(!campo || cdEndTentou_ || campo.value.trim()) return;
  cdEndTentou_ = true;
  let pos = null;
  for(let i = 0; i < 8 && !pos; i++){
    if(window.__posCd_) pos = window.__posCd_();
    if(!pos) await new Promise(r => setTimeout(r, 700));
  }
  if(!pos){ cdEndTentou_ = false; return; }   /* sem localização: segue como antes e tenta de novo na próxima troca */
  try{
    const ctl = new AbortController(); const t = setTimeout(() => ctl.abort(), 8000);
    const r = await fetch('https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=17&addressdetails=1&accept-language=pt-BR&lat=' + encodeURIComponent(pos.lat) + '&lon=' + encodeURIComponent(pos.lng), { signal: ctl.signal });
    clearTimeout(t);
    if(!r.ok) return;
    const j = await r.json(); const a = (j && j.address) || {};
    const rua = a.road || a.pedestrian || a.residential || '';
    const bairro = a.suburb || a.neighbourhood || a.quarter || a.city_district || '';
    const cidade = String(a.city || a.town || a.village || a.municipality || '').replace(/[<>]/g, '').slice(0, 60);
    const uf = String(a['ISO3166-2-lvl4'] || '').replace(/^BR-/, '');
    if(cidade){ const cc = document.getElementById('cdCidade'); if(cc && !cc.value.trim()) cc.value = cidade + (uf ? ' - ' + uf : ''); }
    const txt = [rua, bairro].filter(Boolean).join(', ').replace(/[<>]/g, '').slice(0, 120);
    if(!txt || campo.value.trim()) return;   /* não sobrescreve o que o cliente já digitou */
    campo.value = txt; cdEndAuto_ = true;
    if(aviso){ aviso.style.display = 'block'; aviso.textContent = '📍 Preenchemos rua, bairro e cidade pela sua localização. Confira e digite o NÚMERO da casa.'; }
    try{ const n = document.getElementById('cdNumero'); if(n && !n.value.trim()) n.focus({ preventScroll:true }); }catch(e){}
  }catch(e){ /* silencioso: o cliente digita normalmente */ }
}
function onMudarTipoCdEntrega(){
  const tipo = document.getElementById('cdTipoEntrega').value;
  if(tipo==='Entrega'){ try{ cdPreencherEnderecoPorLocal_(); }catch(e){} }
  document.getElementById('cdEnderecoBox').style.display = tipo==='Entrega' ? 'block':'none';
  const tempo = tipo==='Entrega' ? (cdDados.config&&cdDados.config.tempoEntrega) : (cdDados.config&&cdDados.config.tempoRetirada);
  const taxaCd = Number(cdDados.config && cdDados.config.taxaEntrega) || 0;
  const freteGratis=!!(cdCupomAplicado&&cdCupomAplicado.freteGratis); document.getElementById('cdTempoEstimado').textContent = (tempo ? ('⏱️ Tempo estimado: '+tempo) : '') + ((tipo==='Entrega' && taxaCd>0) ? ((tempo?' · ':'') + (freteGratis?'🛵 Frete grátis':'🛵 Taxa de entrega: R$ '+taxaCd.toFixed(2).replace('.',',')+' incluída no total')) : '');
  cdAtualizarTotal_();
}
function onMudarFormaPagamentoCd(){
  const sel = document.getElementById('cdFormaPagamento');
  try{ cdAtualizarTotal_(); }catch(e){}
  const forma = (cdDados.formasPagamento||[]).find(f=>f.id===sel.value);
  const ehDinheiro = forma && forma.nome.toLowerCase()==='dinheiro';
  document.getElementById('cdTrocoBox').style.display = ehDinheiro ? 'block' : 'none';
  if(!ehDinheiro){ document.getElementById('cdPrecisaTroco').checked = false; document.getElementById('cdTrocoParaBox').style.display = 'none'; }
}
function onTogglePrecisaTroco(){
  document.getElementById('cdTrocoParaBox').style.display = document.getElementById('cdPrecisaTroco').checked ? 'block' : 'none';
}
async function finalizarPedidoPublico(){
  if(mesaQr) return finalizarPedidoMesa_();
  if(cdDados && cdDados.cardapioBloqueio) return showMsg('cdCheckoutMsg', cdDados.cardapioBloqueio, 'warn'); // cardápio fechado pelo restaurante
  const nome = document.getElementById('cdNome').value.trim();
  const telefone = document.getElementById('cdTelefone').value.trim();
  const tipoEntrega = document.getElementById('cdTipoEntrega').value;
  const formaPagamentoId = document.getElementById('cdFormaPagamento').value;
  if(!nome || !telefone) return showMsg('cdCheckoutMsg','Informe nome e telefone.','warn');
  if(!cdCarrinho.length) return showMsg('cdCheckoutMsg','Seu carrinho está vazio.','warn');
  cdGuardarContato_(nome, telefone);
  const dadosEntrega = tipoEntrega==='Entrega' ? {
    endereco: document.getElementById('cdEndereco').value.trim().replace(/[,\s]+$/,''),
    numero: (document.getElementById('cdNumero')||{value:''}).value.trim(),
    cidade: (document.getElementById('cdCidade')||{value:''}).value.trim(),
    complemento: document.getElementById('cdComplemento').value.trim(),
    referencia: document.getElementById('cdReferencia').value.trim(), observacoes: (document.getElementById('cdObservacoes')||{}).value.trim()
  } : null;
  if(tipoEntrega==='Entrega' && !dadosEntrega.endereco) return showMsg('cdCheckoutMsg','Informe o endereço de entrega.','warn');
  if(tipoEntrega==='Entrega' && !dadosEntrega.numero){ try{ document.getElementById('cdNumero').focus(); }catch(e){} return showMsg('cdCheckoutMsg','Informe o NÚMERO da casa (ou "s/n" se não tiver). Sem o número o pedido não é enviado.','warn'); }
  if(tipoEntrega==='Entrega' && !dadosEntrega.cidade){ try{ document.getElementById('cdCidade').focus(); }catch(e){} return showMsg('cdCheckoutMsg','Informe a cidade da entrega.','warn'); }
  const formaEscolhida = (cdDados.formasPagamento||[]).find(f=>f.id===formaPagamentoId);
  const precisaTrocoBox = document.getElementById('cdPrecisaTroco');
  const ehDinheiro = formaEscolhida && formaEscolhida.nome.toLowerCase()==='dinheiro';
  if(ehDinheiro && precisaTrocoBox && precisaTrocoBox.checked){
    const trocoPara = Number(document.getElementById('cdTrocoPara').value)||0;
    if(trocoPara <= totalCarrinhoCd()) return showMsg('cdCheckoutMsg','O valor pro troco precisa ser maior que o total do pedido.','warn');
  }
  const trocoParaObs = (ehDinheiro && precisaTrocoBox && precisaTrocoBox.checked) ? ('Troco para R$ '+Number(document.getElementById('cdTrocoPara').value).toFixed(2)) : '';

  const btn = document.getElementById('cdEnviarPedidoBtn');
  btn.disabled = true; btn.textContent = 'Enviando...';

  const _preventivoPublico = !modoContingenciaAtivo && servidorLento_() && !cdCupomAplicado && !!CONTINGENCIA_CHAVE_PUBLICA; // BLOCO 1.2 (com cupom não: a contingência não aplica desconto)
  let _contFalhou = false;
  if(modoContingenciaAtivo || _preventivoPublico){
    try{
      const idFila = (_idFilaContingencia = _idFilaContingencia || ('cd-' + Date.now() + '-' + Math.random().toString(36).slice(2,8))); // mesmo id em toda nova tentativa: a fila da contingência não duplica
      const itens = cdCarrinho.map(it=>{
        const extra = it.adicionais.reduce((s,a)=>s+a.preco,0);
        const nomeComAdicionais = it.nome + (it.adicionais.length ? ' + '+it.adicionais.map(a=>a.nome).join(', ') : '') + (it.obs ? ' — Obs: '+it.obs : '');
        const base = { descricao: nomeComAdicionais, quantidade: it.qtd, valorUnitario: it.precoBase + extra, custoUnitario: 0, adicionaisIds: it.adicionais.map(a=>a.id) };
        return it.tipo==='produto' ? Object.assign({produtoId: it.id}, base) : Object.assign({comboId: it.id}, base);
      });
      const total = itens.reduce((s,it)=>s+it.valorUnitario*it.quantidade, 0);
      const forma = (cdDados.formasPagamento||[]).find(f=>f.id===formaPagamentoId);
      const dados = {
        itens, clienteNome: nome, clienteTelefone: telefone,
        pagamentos: [{ forma: forma?forma.nome:'', valor: total }],
        tipoEntrega, statusPagamento: 'A Receber', desconto: null, senhaAdminConfirmacao: '', origem: 'Cardápio',
        /* na contingência o endereço vai completo num campo só (número e cidade junto) */
        dadosEntrega: dadosEntrega ? Object.assign({}, dadosEntrega, { endereco: [dadosEntrega.endereco + (dadosEntrega.numero ? ', nº ' + dadosEntrega.numero : ''), dadosEntrega.cidade].filter(Boolean).join(' — ') }) : null
      };
      const r = await fetchContingencia_({
        method: 'post', body: JSON.stringify({ action: 'enfileirar', chave: CONTINGENCIA_CHAVE_PUBLICA, id: idFila, tipo: 'venda', dados })
      }, TIMEOUT_CONT_ENVIO_MS_, TIMEOUT_CONT_REPETICOES_);
      if(r.ok){
        showMsg('cdCheckoutMsg', 'Pedido recebido! Estamos com uma instabilidade — seu pedido foi guardado e vai ser confirmado assim que normalizar. Guarde este código: ' + idFila.slice(-6).toUpperCase(), 'ok');
        cdUltimaVendaId = null; mostrarBotaoWhatsappContingencia({id:idFila,numero:idFila.slice(-6).toUpperCase(),valorTotal:Math.round((total+acrescimoCdAtual_())*100)/100}); _idFilaContingencia = null;
        cdPedidoConcluido = true;
        btn.disabled=true; btn.textContent='Pedido guardado';
      } else { _contFalhou = true; showMsg('cdCheckoutMsg', 'Não foi possível registrar o pedido agora. Tente novamente em instantes.', 'warn'); btn.disabled=false; btn.textContent='Enviar pedido'; }
    } catch(e){
      if(!(e && e.timeout)) _contFalhou = true; // erro de rede (não chegou a guardar): no modo preventivo tenta a planilha; timeout não, para não duplicar
      showMsg('cdCheckoutMsg', (e && e.timeout) ? 'Não conseguimos confirmar o envio a tempo. Toque em Enviar pedido de novo — o pedido não será duplicado.' : 'Não foi possível enviar o pedido. Tente novamente.','warn');
      btn.disabled=false; btn.textContent='Enviar pedido';
    }
    if(!(_preventivoPublico && _contFalhou)) return;
    btn.disabled=true; btn.textContent='Enviando...'; // contingência recusou/ficou fora: segue para a planilha principal
  }

  const itens = cdCarrinho.map(it=>({
    produtoId: it.tipo==='produto' ? it.id : undefined,
    comboId: it.tipo==='combo' ? it.id : undefined,
    quantidade: it.qtd,
    adicionaisIds: it.adicionais.map(a=>a.id),
    observacao: it.obs || ''
  }));
  const _reqCont = { itens, clienteTelefone: telefone, tipoEntrega, formaPagamentoId };
  try{
    const r = await apiCall('criarPedidoCardapio', { requisicaoId: reqIdPersist_('pedido_cardapio', _reqCont), itens, clienteNome: nome, clienteTelefone: telefone, tipoEntrega, dadosEntrega, formaPagamentoId, observacaoTroco: trocoParaObs, codigoCupom: cdCupomAplicado ? cdCupomAplicado.codigo : '', observacoes: (document.getElementById('cdObservacoes')||{}).value.trim() });
    if(r.ok){
      reqIdConfirmado_('pedido_cardapio', _reqCont);
      showMsg('cdCheckoutMsg', r.message, 'ok');
      cdUltimaVendaId = r.id;
      mostrarBotaoWhatsappPedido(r);
      mostrarLinkAcompanhamento(r.id, nome, r.numero);
      if(window.cdAvisosPosPedido_) window.cdAvisosPosPedido_(String(r.id).slice(-8));
      if(tipoEntrega==='Entrega' && window.cdEnviarLocalDoPedido_) window.cdEnviarLocalDoPedido_(r.id);
      cdPedidoConcluido = true;
      btn.disabled=true; btn.textContent='Pedido enviado';
    } else { showMsg('cdCheckoutMsg', r.message, 'warn'); btn.disabled=false; btn.textContent='Enviar pedido'; }
  } catch(e){ showMsg('cdCheckoutMsg','Não foi possível enviar o pedido. Tente novamente.','warn'); btn.disabled=false; btn.textContent='Enviar pedido'; }
}


let cdCupomAplicado = null;
async function aplicarCupomPublicoUI(){
  const codigo=document.getElementById('cdCupom').value.trim(); const msg=document.getElementById('cdCupomMsg');
  if(!codigo){msg.textContent='Digite o código do cupom.';msg.className='msg warn';return;}
  if(modoContingenciaAtivo){msg.textContent='Cupons ficam indisponíveis durante a contingência. Envie o pedido sem cupom ou tente novamente quando normalizar.';msg.className='msg warn';return;}
  const telefone=document.getElementById('cdTelefone').value.trim(); const subtotal=subtotalCarrinhoCd(); const tipo=document.getElementById('cdTipoEntrega').value;
  try{const r=await apiCall('validarCupomCardapio',{codigo,telefone,subtotal,tipoEntrega:tipo,itens:cdCarrinho}); if(r.ok){cdCupomAplicado=r;msg.textContent='Cupom aplicado: '+r.codigo;msg.className='msg ok';document.getElementById('cdCupomResumo').textContent=(r.desconto>0?'Desconto: -R$ '+Number(r.desconto).toFixed(2).replace('.',',')+' · ':'')+(r.freteGratis?'Frete grátis':'');document.getElementById('cdCarrinhoTotal').textContent=cdFormatarPreco(Math.max(0.01,totalCarrinhoCd()));onMudarTipoCdEntrega();}else{cdCupomAplicado=null;msg.textContent=r.message;msg.className='msg warn';document.getElementById('cdCupomResumo').textContent='';}}catch(e){msg.textContent='Não foi possível validar o cupom agora.';msg.className='msg warn';}
}
function cdEnderecoTexto_(){
  const v = id => ((document.getElementById(id)||{}).value||'').trim();
  return [v('cdEndereco').replace(/[,\s]+$/,'') + (v('cdNumero') ? ', nº ' + v('cdNumero') : ''), v('cdCidade'), v('cdComplemento'), v('cdReferencia') ? 'Ref.: ' + v('cdReferencia') : ''].filter(Boolean).join(' — ');
}
function mostrarBotaoWhatsappPedido(r){
  const box=document.getElementById('cdCheckoutMsg'); if(!box||!r||!r.id)return;
  const numero=r.numero||String(r.id).slice(-8).toUpperCase(); const itens=cdCarrinho.map(it=>`${it.qtd}x ${it.nome}${it.adicionais.length?' + '+it.adicionais.map(a=>a.nome).join(', '):''}`).join('\n');
  const nome=document.getElementById('cdNome').value.trim(); const tel=document.getElementById('cdTelefone').value.trim(); const tipo=document.getElementById('cdTipoEntrega').value; const total=Number(r.valorTotal||0);
  const endereco=tipo==='Entrega' ? cdEnderecoTexto_() : 'Retirada no balcão';
  const obs=(document.getElementById('cdObservacoes')||{}).value || '';
  const forma=(document.getElementById('cdFormaPagamento')||{}).selectedOptions ? ((document.getElementById('cdFormaPagamento').selectedOptions[0]||{}).textContent||'') : '';
  const cup=r.cupom?`\nCupom: ${r.cupom} (-R$ ${Number(r.valorDesconto||0).toFixed(2).replace('.',',')})`:'';
  const frete=r.freteGratis?'\nFrete: GRÁTIS':'';
  const taxa=(tipo==='Entrega' && !r.freteGratis)?`\nTaxa de entrega: R$ ${(Number(total)-Number(r.valorOriginal||0)+Number(r.valorDesconto||0)).toFixed(2).replace('.',',')}`:'';
  const msg=`🍔 TEXAS BURGER\nPedido #${numero}\nCliente: ${nome}\nWhatsApp: ${tel}\nPagamento: ${forma||'Não informado'}\n\n${itens}\n\nModalidade: ${tipo}\n${endereco}${obs?'\nObservações: '+obs:''}\nTotal: R$ ${total.toFixed(2).replace('.',',')}${taxa}${cup}${frete}`;
  const url='https://wa.me/5517988323473?text='+encodeURIComponent(msg);
  cdMostrarConfirmacaoPedido_(url, numero, false, r.id);
}


/* ---------- CONFIRMAÇÃO FIXA DO PEDIDO + WHATSAPP (abre sozinho em 3 s, com opção de cancelar) ----------
   O botão antes ficava dentro da caixa de mensagem, que se apaga em 6 s. Agora fica num cartão que não some. */
let _cdWaTimer = null;
function cdPararContagemWa_(){ if(_cdWaTimer){ clearInterval(_cdWaTimer); _cdWaTimer = null; } }
document.addEventListener('visibilitychange', ()=>{ if(document.hidden) cdPararContagemWa_(); });
window.addEventListener('pagehide', cdPararContagemWa_);
/* ITEM 11 — o app já está instalado neste aparelho? (mesmo critério do Item 7) */
function cdAppJaInstalado_(){
  try{
    if(window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true) return true;
    return localStorage.getItem('txAppInstalado') === '1';
  }catch(e){ return false; }
}
/* ITEM 11 — abre o pop-up de acompanhamento (Item 9) direto no pedido recém-feito */
function cdAbrirAcompanhamentoDoPedido_(vendaId){
  const codigo = String(vendaId || '').slice(-8); // mesmo código salvo por mostrarLinkAcompanhamento
  if(!codigo) return;
  document.getElementById('acompanhamentoConteudo').innerHTML = '<p class="sub">Carregando...</p>';
  document.getElementById('acompanhamentoPedido').classList.add('open');
  abrirStatusPedido(codigo);
}
window.addEventListener('appinstalled', function(){
  document.querySelectorAll('.cd-conf-instalar').forEach(function(e){ e.style.display = 'none'; });
});
function cdMostrarConfirmacaoPedido_(url, numero, contingencia, vendaId){
  const host = document.getElementById('cdConfirmacaoPedido'); if(!host) return;
  cdPararContagemWa_();
  host.innerHTML = '';
  const card = document.createElement('div'); card.className = 'cd-conf-card';
  const t = document.createElement('div'); t.className = 'cd-conf-titulo';
  t.textContent = contingencia ? '✅ Pedido guardado! Código ' + numero : '✅ Pedido enviado! Nº ' + numero;
  card.appendChild(t);
  const p = document.createElement('div'); p.className = 'cd-conf-texto';
  p.textContent = 'Toque no botão verde para enviar os detalhes do pedido pelo WhatsApp da loja.';
  card.appendChild(p);
  const a = document.createElement('a'); a.className = 'cd-conf-wa'; a.href = url; a.target = '_blank'; a.rel = 'noopener';
  a.textContent = '📲 Enviar pedido pelo WhatsApp';
  card.appendChild(a);
  const cont = document.createElement('div'); cont.className = 'cd-conf-cont';
  const txt = document.createElement('span'); cont.appendChild(txt);
  const cancel = document.createElement('button'); cancel.type = 'button'; cancel.className = 'cd-conf-cancel'; cancel.textContent = 'Cancelar';
  cont.appendChild(cancel);
  card.appendChild(cont);

  /* ===== ITEM 11 — Acompanhar agora (só pedido normal) ===== */
  if(!contingencia && vendaId){
    const ac = document.createElement('div'); ac.className = 'cd-conf-acoes';
    const bAc = document.createElement('button'); bAc.type = 'button'; bAc.className = 'cd-conf-sec';
    bAc.textContent = '📦 Acompanhar agora';
    bAc.onclick = function(){ cdPararContagemWa_(); cont.style.display = 'none'; cdAbrirAcompanhamentoDoPedido_(vendaId); };
    ac.appendChild(bAc);
    card.appendChild(ac);
  }
  /* ===== ITEM 11 — Convite para instalar o app (some se já instalado) ===== */
  if(!cdAppJaInstalado_()){
    const inst = document.createElement('div'); inst.className = 'cd-conf-instalar';
    const itx = document.createElement('div'); itx.className = 'cd-conf-inst-txt';
    itx.innerHTML = '<b>Peça mais rápido da próxima vez</b>Instale o app Texas Burger na tela inicial do seu celular.';
    inst.appendChild(itx);
    const bIn = document.createElement('button'); bIn.type = 'button'; bIn.className = 'cd-conf-sec';
    bIn.textContent = '📲 Instalar app';
    bIn.onclick = function(){ cdPararContagemWa_(); cont.style.display = 'none'; if(window.instalarApp) window.instalarApp(); };
    inst.appendChild(bIn);
    card.appendChild(inst);
  }

  const dica = document.createElement('div'); dica.className = 'cd-conf-dica';
  dica.textContent = contingencia ? 'Guarde este código: ele identifica o seu pedido.' : 'Para ver o status a qualquer momento, toque em "Acompanhe seu pedido", no rodapé.';
  card.appendChild(dica);
  host.appendChild(card);
  try{ card.scrollIntoView({ behavior:'smooth', block:'center' }); }catch(e){}
  let resta = 3;
  const mostrar = ()=>{ txt.textContent = 'Abrindo o WhatsApp em ' + resta + 's…'; };
  mostrar();
  _cdWaTimer = setInterval(()=>{
    resta--;
    if(resta <= 0){ cdPararContagemWa_(); cont.style.display = 'none'; window.location.href = url; return; }
    mostrar();
  }, 1000);
  cancel.onclick = ()=>{ cdPararContagemWa_(); txt.textContent = 'Abertura automática cancelada.'; cancel.style.display = 'none'; };
  a.addEventListener('click', ()=>{ cdPararContagemWa_(); cont.style.display = 'none'; });
}

function mostrarBotaoWhatsappContingencia(r){
  const box=document.getElementById('cdCheckoutMsg'); if(!box||!r||!r.id)return;
  const itens=cdCarrinho.map(it=>`${it.qtd}x ${it.nome}${it.adicionais.length?' + '+it.adicionais.map(a=>a.nome).join(', '):''}`).join('\n');
  const nome=document.getElementById('cdNome').value.trim(); const tel=document.getElementById('cdTelefone').value.trim(); const tipo=document.getElementById('cdTipoEntrega').value; const total=Number(r.valorTotal||0);
  const endereco=tipo==='Entrega' ? cdEnderecoTexto_() : 'Retirada no balcão';
  const obs=(document.getElementById('cdObservacoes')||{}).value || '';
  const msg=`🍔 TEXAS BURGER\nPEDIDO EM CONTINGÊNCIA\nCódigo: ${r.numero||String(r.id).slice(-6).toUpperCase()}\nCliente: ${nome}\nWhatsApp: ${tel}\n\n${itens}\n\nModalidade: ${tipo}\n${endereco}${obs?'\nObservações: '+obs:''}\nTotal informado: R$ ${total.toFixed(2).replace('.',',')}`;
  cdMostrarConfirmacaoPedido_('https://wa.me/5517988323473?text='+encodeURIComponent(msg), r.numero||String(r.id).slice(-6).toUpperCase(), true);
}
/* ---------- FEEDBACK (ITEM 34) — sempre disponível, com ou sem pedido ---------- */
let cdUltimaVendaId = null;
let cdNotaEscolhida = 0;
let cdFeedbackCodigo_ = '', cdFeedbackOrigem_ = 'formulario';   // pedido (8 últimos do id) e de onde veio: formulario | aviso | chat
function abrirFeedbackPublico(){
  cdNotaEscolhida = 0; cdFeedbackCodigo_ = ''; cdFeedbackOrigem_ = 'formulario';
  document.querySelectorAll('#cdEstrelas span').forEach(s=>s.classList.remove('on'));
  document.getElementById('cdFeedbackComentario').value = '';
  document.getElementById('cdFeedbackMsg').innerHTML = '';
  const titulo = document.getElementById('cdFeedbackTitulo');
  if(cdUltimaVendaId){
    titulo.textContent = 'Como foi seu pedido?';
    document.getElementById('cdFeedbackNome').value = document.getElementById('cdNome') ? document.getElementById('cdNome').value : '';
    document.getElementById('cdFeedbackTelefone').value = document.getElementById('cdTelefone') ? document.getElementById('cdTelefone').value : '';
  } else {
    titulo.textContent = 'Fale com a gente';
    document.getElementById('cdFeedbackNome').value = '';
    document.getElementById('cdFeedbackTelefone').value = '';
  }
  document.getElementById('cdFeedbackModal').classList.add('open');
}
function fecharFeedbackPublico(){ document.getElementById('cdFeedbackModal').classList.remove('open'); }
/* feedback aberto pelo aviso "Como foi seu pedido?" (origem aviso) ou pelo atendente do chat (origem chat, já com o texto do cliente) */
function cdAbrirFeedbackEspecial_(o){
  abrirFeedbackPublico();
  cdFeedbackOrigem_ = o.origem === 'chat' ? 'chat' : 'aviso';
  cdFeedbackCodigo_ = /^[0-9a-f]{8}$/.test(String(o.codigo || '')) ? String(o.codigo) : '';
  if(o.titulo) document.getElementById('cdFeedbackTitulo').textContent = o.titulo;
  if(o.comentario) document.getElementById('cdFeedbackComentario').value = String(o.comentario).slice(0, 500);
  const m = document.getElementById('cdFeedbackModal'); if(m) m.style.zIndex = '10050';   // por cima do chat
}
document.addEventListener('click', (e)=>{
  const estrela = e.target.closest('#cdEstrelas span');
  if(estrela){
    cdNotaEscolhida = Number(estrela.dataset.n);
    document.querySelectorAll('#cdEstrelas span').forEach(s=> s.classList.toggle('on', Number(s.dataset.n) <= cdNotaEscolhida));
  }
});
async function enviarFeedbackPublico(){
  if(!cdNotaEscolhida) return showMsg('cdFeedbackMsg','Toque nas estrelas para dar uma nota.','warn');
  try{
    const r = await apiCallFila('addFeedback', {
      vendaId: cdFeedbackCodigo_ ? undefined : cdUltimaVendaId,
      codigo: cdFeedbackCodigo_ || undefined,
      origem: cdFeedbackOrigem_,
      telefone: document.getElementById('cdFeedbackTelefone').value.trim(),
      nome: document.getElementById('cdFeedbackNome').value.trim(),
      nota: cdNotaEscolhida,
      comentario: document.getElementById('cdFeedbackComentario').value.trim()
    });
    showMsg('cdFeedbackMsg', r.message || 'Obrigado!', 'ok');
    setTimeout(fecharFeedbackPublico, 1000);
  } catch(e){ showMsg('cdFeedbackMsg','Não foi possível enviar agora.','warn'); }
}

