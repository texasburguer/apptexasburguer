/* ---------- TABS ---------- */
/* "Administrador" (ITEM 4, 50, 66) não é uma seção única — é um hub que agrupa
   Produtos e Estoque, Financeiro e Usuários e Permissões, que continuam sendo
   as mesmas seções de sempre (nenhum cadastro foi duplicado). */
const ADMIN_GRUPOS = [
  { nome:'📊 Painel',     subs:['visaogeral', 'ocorrencias', 'feedbacks', 'relatorios'] },
  { nome:'💰 Financeiro', subs:['financeiro', 'analise', 'ajustes', 'historico'] },
  { nome:'🍔 Catálogo',   subs:['produtos', 'estoque', 'compras', 'custosprecificacao', 'cardapiodigital'] },
  { nome:'🎟️ Campanhas',  subs:['promocoes', 'eventos'] },
  { nome:'🏪 Operação',   subs:['restaurante', 'pagamentos', 'taxasentregas', 'notifadmin'] },
  { nome:'⚙️ Sistema',    subs:['usuarios', 'auditoria', 'armazenamento', 'integridade', 'contas'] }
];
const ADMIN_SUBABAS = ADMIN_GRUPOS.reduce((a,g)=>a.concat(g.subs), []);
/* a barra do Administrador existia copiada em 13 telas. Agora há UMA definição, desenhada em todas. */
const ADMIN_SUBABAS_ROTULOS = { contas:'Contas e acessos', visaogeral:'Visão Geral', ocorrencias:'Ocorrências', feedbacks:'Feedbacks', relatorios:'Relatórios', financeiro:'Contas e despesas', analise:'Análise', ajustes:'Ajustes pós-venda', historico:'Histórico', produtos:'Produtos', estoque:'Estoque', compras:'Compras e fornecedores', custosprecificacao:'Custos e Precificação', cardapiodigital:'Cardápio Digital', promocoes:'Promoções', eventos:'Eventos', restaurante:'Mesas e QR Codes', pagamentos:'Pagamentos', taxasentregas:'Entregadores e taxas', notifadmin:'Configurar notificações', usuarios:'Usuários e Permissões', auditoria:'Auditoria', armazenamento:'Backup e espaço', integridade:'Sincronização e contingência' };
const ADMIN_GRUPOS_OPERADOR_ = [ { nome:'💬 Atendimento', subs:['ocorrencias', 'feedbacks'] } ];
function gruposAdmin_(){ return (currentUser && currentUser.nivel==='Operador') ? ADMIN_GRUPOS_OPERADOR_ : ADMIN_GRUPOS; }
function montarBarrasAdmin_(alvo, grupoIdx){
  /* alvo = tela aberta; sem alvo, mostra só os grupos (ou as telas do grupo escolhido), nada aberto até tocar */
  const grupos = gruposAdmin_();
  const ativo = alvo ? (grupos.find(g=>g.subs.includes(alvo)) || grupos[0]) : (grupoIdx != null ? grupos[grupoIdx] : (grupos.length === 1 ? grupos[0] : null));
  const abas = grupos.length>1 ? grupos.map((g,i)=>`<button class="admin-gbtn${g===ativo?' active':''}" onclick="abrirAdminGrupo_(${i})">${g.nome}</button>`).join('') : '';
  const subs = ativo ? (`<div class="admin-grupo">${grupos.length>1 ? ativo.nome : (ativo.nome+' — o que você pode tratar aqui')}</div>` + ativo.subs.map(id=>`<button data-sub="${id}" class="${id===alvo?'active':''}" onclick="abrirAdministrador('${id}')">${ADMIN_SUBABAS_ROTULOS[id]}</button>`).join('')) : '';
  document.querySelectorAll('.admin-subnav[data-admin-nav]').forEach(nav=>{ nav.innerHTML = abas + subs; });
  _adminGrupoAtivo_ = ativo ? grupos.indexOf(ativo) : null;
  /* Computador: menu lateral com todos os grupos e telas à vista (um clique). No celular ele fica escondido (CSS). */
  const lat = document.getElementById('adminLateral');
  if(lat) lat.innerHTML = grupos.map(g=>`<div class="al-grupo">${g.nome}</div>` + g.subs.map(id=>`<button type="button" data-sub="${id}" class="${id===alvo?'active':''}" onclick="abrirAdministrador('${id}')">${ADMIN_SUBABAS_ROTULOS[id]}</button>`).join('')).join('');
}
let _adminGrupoAtivo_ = null;
/* Entrar no Admin: só os grupos, nenhuma tela aberta. Tocar num grupo mostra as telas dele; a tela abre só quando você toca nela. */
function abrirAdminGrupo_(i){
  if(i != null && i === _adminGrupoAtivo_ && gruposAdmin_().length > 1) i = null;   // tocar de novo no grupo aberto fecha o menu dele
  montarBarrasAdmin_(null, i);
  document.querySelectorAll('.tab-btn').forEach(b=>b.classList.remove('active'));
  const bt = document.querySelector('[data-tab="administrador"]'); if(bt) bt.classList.add('active');
  ativarApenasSecao_('tab-admininicio');
}
function abrirAdminInicio_(){ abrirAdminGrupo_(null); }
montarBarrasAdmin_('visaogeral');
(function(){ const inicial=document.querySelector('section.tab.active'); if(inicial) ativarApenasSecao_(inicial.id); })();
function ativarApenasSecao_(id){
  /* telas do Administrador: no computador ganham o menu lateral (estilo-14-computador.css) */
  try{ document.body.classList.toggle('adm-ativo', id === 'tab-admininicio' || (typeof ADMIN_SUBABAS !== 'undefined' && ADMIN_SUBABAS.indexOf(String(id).replace(/^tab-/,'')) !== -1)); }catch(e){}
  document.querySelectorAll('section.tab').forEach(sec=>{
    const ativa = sec.id === id;
    sec.classList.toggle('active', ativa);
    // Blindagem visual: mesmo que alguma regra CSS externa/antiga esteja interferindo,
    // somente a seção escolhida pode ocupar a tela.
    sec.hidden = !ativa;
    sec.style.setProperty('display', ativa ? 'block' : 'none', 'important');
    sec.setAttribute('aria-hidden', ativa ? 'false' : 'true');
  });
  /* MELHORIA 4.4 — telas pesadas só são desenhadas a cada sincronização quando estão na tela; ao entrar nelas, desenham na hora. */
  try{ if(id==='tab-notificacoes') renderNotificacoes(); else if(id==='tab-relatorios') gerarRelatorio(); }catch(e){}
}
/* Abas internas: mostra só os cards marcados com data-painel="nome" (um card pode ter mais de um nome, separados por espaço).
   Cards sem data-painel ficam sempre visíveis. Lembra a última aba escolhida em cada tela. */
const _abaInterna_ = { 'tab-produtos':'produtos', 'tab-cardapiodigital':'categorias', 'tab-historico':'vendas' };
function abaInterna_(tabId, q){
  const sec = document.getElementById(tabId); if(!sec) return;
  _abaInterna_[tabId] = q;
  sec.querySelectorAll('[data-painel]').forEach(p=>{ p.style.display = (p.dataset.painel.split(' ').indexOf(q) !== -1) ? '' : 'none'; });
  sec.querySelectorAll('.seg-abas button').forEach(b=>b.classList.toggle('active', b.dataset.aba === q));
}
function abrirAdministrador(sub){
  if(sub === 'drive') sub = 'armazenamento';   // "Espaço e fotos" virou parte de "Backup e espaço"
  const permitidos = gruposAdmin_().reduce((a,g)=>a.concat(g.subs), []);
  const alvo = (ADMIN_SUBABAS.includes(sub) && permitidos.includes(sub)) ? sub : permitidos[0];
  montarBarrasAdmin_(alvo);
  document.querySelectorAll('.tab-btn').forEach(b=>b.classList.remove('active'));
  document.querySelector('[data-tab="administrador"]').classList.add('active');
  ativarApenasSecao_('tab-'+alvo);
  if(alvo==='armazenamento' && apiConfigurada()){ carregarArmazenamento(); }
  if(_abaInterna_['tab-'+alvo]) abaInterna_('tab-'+alvo, _abaInterna_['tab-'+alvo]);
  if((alvo==='visaogeral' || alvo==='relatorios') && apiConfigurada()) sincronizarEmSegundoPlano(); // ITEM 92: atualiza ao entrar, sem refresh periódico
  if(alvo==='taxasentregas'){ renderEntregasFinanceiro(); if(apiConfigurada()) atualizarAoEntrar_(); }
  if(alvo==='promocoes'){ renderCuponsUI(); lgpdCarregarUI_(); }
  if(alvo==='eventos'){ renderEventosUI(); }
  if(alvo==='custosprecificacao'){ prepararCalculadoraUI(); }
  if(alvo==='compras') carregarCompras_();
  if(alvo==='contas'){ carregarContas_(); carregarChavesIa_(); carregarIntegracoes_(); }
  if(alvo==='auditoria') carregarAuditoria_();
  if(alvo==='visaogeral') carregarSaude_();
  if(alvo==='ocorrencias') renderOcorrencias();
  if(alvo==='notifadmin') renderConfigNotificacoes();
  if(alvo==='visaogeral') renderVisaoGeral(); if(alvo==='relatorios') renderRelatorio();
  if(alvo==='feedbacks') renderFeedbacks();
}
document.querySelectorAll('.tab-btn').forEach(btn=>{
  btn.addEventListener('click', ()=>{
    if(btn.classList.contains('hidden-tab')) return;
    if(btn.dataset.tab==='administrador'){ abrirAdminInicio_(); return; }
    document.querySelectorAll('.tab-btn').forEach(b=>b.classList.remove('active'));
    btn.classList.add('active');
    ativarApenasSecao_('tab-'+btn.dataset.tab);
    if(btn.dataset.tab==='inicio') { try{ renderInicio(); }catch(e){} }
    if(btn.dataset.tab==='meusganhos') { try{ renderMeusGanhos(); }catch(e){} }
  });
});
/* Pedidos e Entregas NÃO atualizam mais ao abrir a aba. A atualização é: botão "Atualizar" (na hora) ou o timer de 3 minutos
   (só quando seguroParaSincronizar() permite, para não mexer em venda ou formulário em andamento). */
const SYNC_INTERVALO_MS = 3*60*1000; // 3 minutos: usado pelo timer geral e pelo detector da Cozinha (menos chamadas ao Apps Script)
let ultimaSyncMs = 0;
function atualizarAoEntrar_(){
  if(!apiConfigurada() || Date.now()-ultimaSyncMs < 15000) return;
  sincronizarEmSegundoPlano();
}
/* Botão "Atualizar": puxa agora, sem a espera de 15s (o servidor já serializa as chamadas). */
async function atualizarAgora_(){
  if(!apiConfigurada()) return;
  if(!seguroParaSincronizar()){ alert('Termine ou feche o que está aberto (venda, formulário ou janela) e toque em Atualizar de novo.'); return; }
  _versoesLocais = null; // o botão Atualizar sempre baixa tudo
  await sincronizarEmSegundoPlano();
}
function mostrarUltimaSync_(){
  const t = new Date(ultimaSyncMs), pad = n=>String(n).padStart(2,'0');
  const txt = ultimaSyncMs ? 'Atualizado às '+pad(t.getHours())+':'+pad(t.getMinutes()) : 'Atualiza sozinho a cada 3 min.';
  document.querySelectorAll('[data-ultima-sync]').forEach(el=>{ el.textContent = txt; });
}

/* ============================================================
   CACHE LOCAL
   ============================================================ */
function salvarCache(){
  try{
    localStorage.setItem(CACHE_KEY, JSON.stringify({
      _dono: currentUser ? String(currentUser.login).toLowerCase() : '',
      clientes, promocoes, indicacoes, fidelidade: fidelidadeClientes,
      formasPagamento, categorias, produtos, produtoPrecos, produtoIngredientes, estoque, combos, comboPrecos, comboItens,
      adicionais, produtoAdicionais, feedbacks, ocorrencias, configCardapio, movimentacoesEstoque, maisPedidos, mesas,
      vendas, itensVenda, pagamentosVenda, despesas, categoriasDespesa, despesasRecorrentes, ajustesPosVenda, sangrias, metas, sessaoCaixa, historicoCaixa, usuarios, logRecentes,
      configEntrega, fechamentosEntrega, entregasFechadas, configNotificacoes
    }));
  } catch(e){ /* armazenamento indisponível, sem problema */ }
  emergenciaSalvarCatalogo_(); // BLOCO 1.3
}
function carregarCache(){
  try{
    const raw = localStorage.getItem(CACHE_KEY);
    if(!raw) return false;
    const d = JSON.parse(raw);
    normalizarNumerosDados_(d); // cache antigo pode ter números como texto
    /* SEGURANÇA: o cache só vale para o usuário que o gerou. Outro funcionário (ex.: entregador) no mesmo aparelho nunca vê os dados do Admin. */
    if(!currentUser || d._dono !== String(currentUser.login).toLowerCase()){ localStorage.removeItem(CACHE_KEY); return false; }
    clientes = d.clientes||[]; promocoes = d.promocoes||[]; cupons = d.cupons||[]; eventos = d.eventos||[]; indicacoes = d.indicacoes||[];
    fidelidadeClientes = d.fidelidade||[]; formasPagamento = d.formasPagamento||[]; categorias = d.categorias||[];
    produtos = d.produtos||[]; produtoPrecos = d.produtoPrecos||[]; produtoIngredientes = d.produtoIngredientes||[];
    estoque = d.estoque||[]; combos = d.combos||[]; comboPrecos = d.comboPrecos||[]; comboItens = d.comboItens||[];
    adicionais = d.adicionais||[]; produtoAdicionais = d.produtoAdicionais||[]; feedbacks = d.feedbacks||[]; ocorrencias = d.ocorrencias||[];
    configCardapio = d.configCardapio || configCardapio;
    maisPedidos = d.maisPedidos || maisPedidos;
    mesas = d.mesas || mesas;
    movimentacoesEstoque = d.movimentacoesEstoque || movimentacoesEstoque;
    vendas = d.vendas||[]; itensVenda = d.itensVenda||[]; pagamentosVenda = d.pagamentosVenda||[]; despesas = d.despesas||[]; categoriasDespesa = d.categoriasDespesa||[]; despesasRecorrentes = d.despesasRecorrentes||[]; ajustesPosVenda = d.ajustesPosVenda||[]; sangrias = d.sangrias||[];
    metas = d.metas||{mensal:0,diaria:0}; sessaoCaixa = d.sessaoCaixa||null; historicoCaixa = d.historicoCaixa||[];
    usuarios = d.usuarios||[]; logRecentes = d.logRecentes||[];
    configEntrega = d.configEntrega || configEntrega; fechamentosEntrega = d.fechamentosEntrega||[]; entregasFechadas = d.entregasFechadas||[];
    configEstoque = d.configEstoque || configEstoque;
    configNotificacoes = d.configNotificacoes || null;
    return true;
  } catch(e){ return false; }
}

/* ============================================================
   CLIENTES
   ============================================================ */
function setFiltroClientes(modo){
  document.getElementById('filtroTodosBtn').classList.toggle('active', modo==='todos');
  document.getElementById('filtroInativosBtn').classList.toggle('active', modo==='inativos');
  document.getElementById('diasInativoBox').style.display = modo==='inativos' ? 'block' : 'none';
  renderClientes();
}
/* Última venda de cada telefone, montada uma única vez (antes, cada cliente varria todas as vendas: 300 clientes x 3000 vendas).
   Refaz sozinha se a lista de vendas mudar. */
let _cacheUltVendaTel = null, _cacheUltVendaChave = '';
function ultimaVendaPorTel_(){
  const chave = vendas.length+'|'+(vendas.length? (vendas[0].id||'')+(vendas[vendas.length-1].id||'') : '');
  if(_cacheUltVendaTel && _cacheUltVendaChave===chave) return _cacheUltVendaTel;
  const m = {};
  vendas.forEach(v=>{ const t = normTel(v.clienteTelefone); if(!t || !v.timestamp) return; if(!m[t] || v.timestamp>m[t]) m[t] = v.timestamp; });
  _cacheUltVendaTel = m; _cacheUltVendaChave = chave;
  return m;
}
function ultimaAtividadeCliente(cliente){
  const tel = normTel(cliente.telefone);
  const candidatos = [];
  if(cliente.primeiroContato) candidatos.push(parseDataBR(cliente.primeiroContato));
  const fid = fidelidadeClientes.find(f=>normTel(f.telefone)===tel);
  if(fid && fid.atualizado) candidatos.push(parseDataBR(fid.atualizado));
  const ultVenda = ultimaVendaPorTel_()[tel];
  if(ultVenda) candidatos.push(ultVenda);
  const validos = candidatos.filter(Boolean);
  return validos.length ? Math.max(...validos) : null;
}

function onMudarTipoCupom_(){
  const t = document.getElementById('cupTipo').value;
  document.getElementById('cupFaixasBox').style.display = t==='progressivo' ? '' : 'none';
  document.getElementById('cupValorBox').style.display = (t==='progressivo' || t==='frete') ? 'none' : '';
}
function faixasDoTexto_(txt){
  return String(txt||'').split(/\n/).map(l=>l.trim()).filter(Boolean).map(l=>{ const n = l.replace(/R\$/gi,'').replace(/,/g,'.').match(/\d+(?:\.\d+)?/g)||[]; return { minimo:Number(n[0])||0, desconto:Number(n[1])||0 }; });
}
function faixasResumo_(c){ return (c.faixas||[]).map(f=>'R$ '+Number(f.desconto).toFixed(2).replace('.',',')+' acima de R$ '+Number(f.minimo).toFixed(2).replace('.',',')).join(' · '); }
const CUP_AUTO_ = {
  boas_vindas:{ t:'🎉 Boas-vindas', d:'Quem cria a conta recebe este cupom.' },
  aniversario:{ t:'🎂 Aniversário', d:'No dia do aniversário (conta com data de nascimento e criada há mais de 30 dias).' },
  indicacao_indicado:{ t:'🎁 Indique e ganhe — quem foi indicado', d:'Quando o indicado conclui o primeiro pedido com a conta.' }
};
function cupBeneficio_(c){ return c.tipo==='percentual'?c.valor+'%':c.tipo==='fixo'?'R$ '+Number(c.valor).toFixed(2).replace('.',','):c.tipo==='progressivo'?faixasResumo_(c):'Frete grátis'; }
function cupClienteNome_(id){ const c=(clientes||[]).find(x=>x.id===id); return c ? (c.nome||'Sem nome') : 'cliente'; }
function renderCuponsUI(){
  const box=document.getElementById('cupLista'); if(!box) return;
  const arr=cupons||[], comuns=arr.filter(c=>!c.automatico), autos=arr.filter(c=>c.automatico);
  const ab=document.getElementById('cupAutoLista');
  if(ab) ab.innerHTML=Object.keys(CUP_AUTO_).map(k=>{ const c=autos.find(x=>x.automatico===k); if(!c) return `<div class="notif-card"><b>${CUP_AUTO_[k].t}</b><div class="obs-line">Ainda não configurado no banco.</div></div>`;
    return `<div class="notif-card"><b>${CUP_AUTO_[k].t}</b> · ${c.ativa?'<b>LIGADO</b>':'desligado'}<div class="obs-line">${escH(CUP_AUTO_[k].d)}</div><div class="obs-line">Benefício: ${escH(cupBeneficio_(c))}${c.valorMinimo?' · pedido mínimo R$ '+Number(c.valorMinimo).toFixed(2).replace('.',','):''} · vale ${c.validadeDias} dias${c.mensagem?' · “'+escH(c.mensagem)+'”':''}</div><button class="small-gold" onclick="abrirCupomUI('${c.id}')">Editar</button> <button class="ghost" onclick="alternarCupomUI('${c.id}',${!c.ativa})">${c.ativa?'Desligar':'Ligar'}</button></div>`; }).join('');
  if(ab) ab.innerHTML+=`<div class="notif-card"><b>🎁 Indique e ganhe — quem indicou</b><div class="obs-line">Quem indicou ganha 1 <b>produto-prêmio</b> quando o amigo conclui o 1º pedido. Marque quais produtos valem em <b>Editar produto › Mais opções › Prêmio de indicação</b>. Sem produto marcado, ninguém ganha.</div></div>`;
  box.innerHTML=comuns.length?comuns.map(c=>{
    const tags=[c.somenteConta?'🔐 só com conta':'',c.clienteId?'👤 só para '+escH(cupClienteNome_(c.clienteId)):'',c.visivelConta?'👁 visível na conta':''].filter(Boolean).join(' · ');
    return `<div class="notif-card"><b>${escH(c.codigo)}</b> — ${escH(c.nome)} · ${escH(cupBeneficio_(c))} · ${c.ativa?'ATIVO':'INATIVO'}<div class="obs-line">Uso: ${c.limiteTotal?c.limiteTotal:'ilimitado'} · por cliente: ${c.limitePorCliente?c.limitePorCliente:'ilimitado'} · mínimo: R$ ${Number(c.valorMinimo).toFixed(2)}${tags?' · '+tags:''}</div><button class="small-gold" onclick="abrirCupomUI('${c.id}')">Editar</button> <button class="ghost" onclick="alternarCupomUI('${c.id}',${!c.ativa})">${c.ativa?'Desativar':'Ativar'}</button></div>`; }).join(''):'<div class="notif-empty">Nenhum cupom cadastrado.</div>';
}
function cupClienteLabel_(c){ return (c.nome||'Sem nome')+' — '+(c.telefone||'sem telefone'); }
function abrirCupomUI(id){
  const c=id?(cupons||[]).find(x=>x.id===id):null, v=(i,val)=>{ document.getElementById(i).value=val==null?'':val; };
  const dl=document.getElementById('cupClienteLista'); if(dl) dl.innerHTML=(clientes||[]).slice(0,3000).map(x=>`<option value="${escH(cupClienteLabel_(x))}"></option>`).join('');
  v('cupId',c?c.id:''); v('cupAuto',c?c.automatico:''); v('cupCodigo',c?c.codigo:''); v('cupNome',c?c.nome:''); v('cupTipo',c?c.tipo:'percentual'); v('cupValor',c?c.valor:'');
  v('cupFaixas',c&&c.tipo==='progressivo'?(c.faixas||[]).map(f=>f.minimo+' '+f.desconto).join('\n'):''); v('cupInicio',c?c.dataInicio:''); v('cupFim',c?c.dataFim:'');
  v('cupLimite',c?c.limiteTotal:'0'); v('cupLimiteCliente',c?c.limitePorCliente:'1'); v('cupMinimo',c?c.valorMinimo:'0'); v('cupValidadeDias',c?c.validadeDias:'30'); v('cupMensagem',c?c.mensagem:'');
  document.getElementById('cupFrete').checked=!!(c&&c.freteGratis); document.getElementById('cupAtiva').checked=c?c.ativa:true;
  document.getElementById('cupSomenteConta').checked=!!(c&&c.somenteConta); document.getElementById('cupVisivelConta').checked=!!(c&&c.visivelConta);
  v('cupCliente',c&&c.clienteId?cupClienteLabel_((clientes||[]).find(x=>x.id===c.clienteId)||{nome:'(cliente)',telefone:''}):'');
  const auto=!!(c&&c.automatico);
  document.getElementById('cupValidadeBox').style.display=auto?'':'none'; document.getElementById('cupContaBox').style.display=auto?'none':'';
  const av=document.getElementById('cupAutoAviso'); av.style.display=auto?'':'none'; av.textContent=auto?(CUP_AUTO_[c.automatico].t+' — '+CUP_AUTO_[c.automatico].d):'';
  document.getElementById('cupTitulo').textContent=c?(auto?'Cupom automático':'Editar cupom'):'Novo cupom'; document.getElementById('cupSalvarBtn').textContent=c?'Salvar alterações':'Criar cupom';
  document.getElementById('cupMsg').className='msg'; document.getElementById('cupMsg').textContent='';
  onMudarTipoCupom_(); abrirFormModal('cupomNovoModal');
}
async function salvarCupomUI(){
  const id=cupId.value; let clienteId='';
  const txt=cupCliente.value.trim();
  if(txt){ const f=(clientes||[]).find(x=>cupClienteLabel_(x)===txt); if(!f) return showMsg('cupMsg','Escolha o cliente na lista que aparece ao digitar.','warn'); clienteId=f.id; }
  const p={id,codigo:cupCodigo.value,nome:cupNome.value,tipo:cupTipo.value,valor:cupValor.value,faixas:cupTipo.value==='progressivo'?faixasDoTexto_(cupFaixas.value):[],freteGratis:cupFrete.checked,dataInicio:cupInicio.value,dataFim:cupFim.value,horaInicio:'',horaFim:'',limiteTotal:cupLimite.value,limitePorCliente:cupLimiteCliente.value,valorMinimo:cupMinimo.value,ativa:cupAtiva.checked,acumula:false,
    automatico:cupAuto.value,validadeDias:cupValidadeDias.value,mensagem:cupMensagem.value,somenteConta:cupSomenteConta.checked,visivelConta:cupVisivelConta.checked,clienteId};
  try{const r=await apiCall(id?'editarCupom':'salvarCupom',p);showMsg('cupMsg',r.message,r.ok?'ok':'warn');if(r.ok){cupons=r.cupons||[];renderCuponsUI();fecharFormModal('cupomNovoModal');showMsg('cupMsgLista',r.message,'ok');}}catch(e){showMsg('cupMsg','Erro ao salvar cupom.','warn');}
}
/* ---- Privacidade (LGPD) das contas — só Administrador ---- */
let _lgpdT=0;
function lgpdPintar_(r){
  document.getElementById('lgpdCard').style.display='';
  document.getElementById('lgpdResumo').textContent='Contas de clientes: '+r.contas+' · aceitaram promoções: '+r.contasPromo+' · cadastros anonimizados: '+r.anonimizados+' · versão do Aviso: '+r.versao;
  document.getElementById('lgpdAnos').value=r.anos; document.getElementById('lgpdRazao').value=r.razaoSocial||''; document.getElementById('lgpdCnpj').value=r.cnpj||'';
  document.getElementById('lgpdLink').textContent='Endereço do Aviso para colocar no Google: '+location.origin+location.pathname+'?privacidade=1';
}
async function lgpdCarregarUI_(){
  if(!currentUser||currentUser.nivel!=='Admin'||!apiConfigurada()||Date.now()-_lgpdT<30000) return; _lgpdT=Date.now();
  try{ const r=await apiCall('lgpdConfig',{}); if(r&&r.ok) lgpdPintar_(r); }catch(e){}
}
async function lgpdEnviar_(p){ try{ const r=await apiCall('lgpdConfig',p); showMsg('lgpdMsg',r.message||'Pronto.',r.ok?'ok':'warn'); if(r.ok) lgpdPintar_(r); }catch(e){ showMsg('lgpdMsg','Não foi possível salvar agora.','warn'); } }
function lgpdSalvarAnos_(){ lgpdEnviar_({anos:document.getElementById('lgpdAnos').value}); }
function lgpdSalvarResp_(){ lgpdEnviar_({razaoSocial:document.getElementById('lgpdRazao').value,cnpj:document.getElementById('lgpdCnpj').value}); }
async function lgpdNovaVersao_(){ if(!confirm('Todos os clientes com conta vão precisar aceitar o Aviso de novo. Publicar nova versão?')) return; lgpdEnviar_({novaVersaoAviso:true}); }
async function alternarCupomUI(id,ativo){try{const r=await apiCall('alternarCupom',{id,ativo});if(r.ok){cupons=r.cupons||[];renderCuponsUI();}else alert(r.message);}catch(e){alert('Não foi possível alterar o cupom.');}}
function limparEventoUI(){['evId','evNome','evTipo','evData','evHoraInicio','evHoraFim','evLocal','evContratante','evTelefone','evValor','evObs'].forEach(id=>{const e=document.getElementById(id);if(e)e.value='';});document.getElementById('evStatus').value='Orçamento';document.getElementById('evMovId').value='';}
function evPreencherFormas_(){ const sel=document.getElementById('evRecForma'); if(!sel) return; const atual=sel.value; sel.innerHTML=(formasPagamento||[]).filter(f=>f.ativa!==false).map(f=>`<option value="${escH(f.nome)}">${escH(f.nome)}</option>`).join(''); if(atual) sel.value=atual; }
function renderEventosUI(){evPreencherFormas_();const box=document.getElementById('evLista');if(!box)return;box.innerHTML=(eventos||[]).length?(eventos||[]).slice().reverse().map(e=>`<div class="notif-card"><b>${escH(e.nome)}</b> · ${escH(/^\d{4}-\d{2}-\d{2}/.test(String(e.data||'')) ? String(e.data).slice(0,10).split('-').reverse().join('/') : (e.data||''))} · ${escH(e.status)}<div class="obs-line">Contratante: ${escH(e.contratante||'—')} · Contratado: ${formatarMoeda(e.valorContratado)} · Recebido: ${formatarMoeda(e.valorRecebido)} · A receber: ${formatarMoeda(e.valorAReceber)} · Custos: ${formatarMoeda(e.custoTotal)} · Resultado: ${formatarMoeda(e.resultado)}</div><button class="small-gold" onclick="selecionarEventoUI('${e.id}')">Gerenciar</button>${e.status!=='Cancelado'?` <button class="ghost" onclick="cancelarEventoUI('${e.id}')">Cancelar</button>`:''}</div>`).join(''):'<div class="notif-empty">Nenhum evento.</div>';}
function selecionarEventoUI(id){const e=(eventos||[]).find(x=>x.id===id);if(!e)return;document.getElementById('evId').value=e.id;document.getElementById('evNome').value=e.nome;document.getElementById('evTipo').value=e.tipo||'';document.getElementById('evData').value=e.data instanceof Date?'':String(e.data||'').slice(0,10);document.getElementById('evHoraInicio').value=e.horaInicio||'';document.getElementById('evHoraFim').value=e.horaFim||'';document.getElementById('evLocal').value=e.local||'';document.getElementById('evContratante').value=e.contratante||'';document.getElementById('evTelefone').value=e.telefone||'';document.getElementById('evStatus').value=e.status||'Orçamento';document.getElementById('evValor').value=e.valorContratado||0;document.getElementById('evObs').value=e.observacoes||'';document.getElementById('evMovId').value=e.id;abrirFormModal('eventoModal');}
async function salvarEventoUI(){const p={id:evId.value,nome:evNome.value,tipo:evTipo.value,data:evData.value,horaInicio:evHoraInicio.value,horaFim:evHoraFim.value,local:evLocal.value,contratante:evContratante.value,telefone:evTelefone.value,status:evStatus.value,valorContratado:evValor.value,observacoes:evObs.value};try{const r=await apiCall('salvarEvento',p);showMsg('evMsg',r.message,r.ok?'ok':'warn');if(r.ok){eventos=r.eventos||[];renderEventosUI();selecionarEventoUI(r.evento.id);}}catch(e){showMsg('evMsg','Erro ao salvar evento.','warn');}}
async function cancelarEventoUI(id){const f=await vsForm({titulo:'Cancelar evento',campos:[{id:'motivo',rotulo:'Motivo do cancelamento (opcional)',tipo:'texto'}],ok:'Cancelar evento',perigo:true});if(!f)return;const motivo=f.motivo;try{const r=await apiCall('cancelarEvento',{id,motivo});if(r.ok){eventos=r.eventos||[];renderEventosUI();}else alert(r.message);}catch(e){alert('Erro ao cancelar.');}}
async function lancarCustoEventoUI(){const id=document.getElementById('evMovId').value;if(!id)return showMsg('evMovMsg','Selecione um evento.','warn');const p={eventoId:id,descricao:evCustoDesc.value,categoria:evCustoCat.value,valor:evCustoValor.value,data:evCustoData.value,observacao:'' ,requisicaoId:novaRequisicao_()};try{const r=await apiCall('adicionarCustoEvento',p);showMsg('evMovMsg',r.message,r.ok?'ok':'warn');if(r.ok){const i=eventos.findIndex(e=>e.id===id);if(i>=0)eventos[i]=r.evento;renderEventosUI();evCustoDesc.value='';evCustoCat.value='';evCustoValor.value='';evCustoData.value='';}}catch(e){showMsg('evMovMsg','Erro ao lançar custo.','warn');}}
async function lancarRecebimentoEventoUI(){const id=document.getElementById('evMovId').value;if(!id)return showMsg('evMovMsg','Selecione um evento.','warn');const p={eventoId:id,valor:evRecValor.value,forma:evRecForma.value,data:'',observacao:'',requisicaoId:novaRequisicao_()};try{const r=await apiCall('adicionarRecebimentoEvento',p);showMsg('evMovMsg',r.message,r.ok?'ok':'warn');if(r.ok){const i=eventos.findIndex(e=>e.id===id);if(i>=0)eventos[i]=r.evento;renderEventosUI();evRecValor.value='';}}catch(e){showMsg('evMovMsg','Erro ao lançar recebimento.','warn');}}
function calcTrocarProduto_(){ const e=document.getElementById('calcPrecoSimulado'); if(e) e.value=''; calcularCustoUI(); }
async function calcularCustoUI(){const p=document.getElementById('calcProduto').value,f=document.getElementById('calcForma').value;if(!p||!f)return;const prec=(produtoPrecos||[]).find(x=>x.produtoId===p&&x.formaPagamentoId===f);document.getElementById('calcCusto').textContent=formatarMoeda(prec?prec.custo:0);document.getElementById('calcPrecoAtual').textContent=formatarMoeda(prec?prec.preco:0);if(!document.getElementById('calcPrecoSimulado').value)document.getElementById('calcPrecoSimulado').value=prec?prec.preco:'';if(!apiConfigurada())return;try{const r=await apiCall('simularPrecificacao',{produtoId:p,formaPagamentoId:f,precoSimulado:document.getElementById('calcPrecoSimulado').value,embalagem:document.getElementById('calcEmbalagem').value,outrosCustos:document.getElementById('calcOutros').value,taxaMarketplace:document.getElementById('calcMarketplace').value});if(r.ok){document.getElementById('calcCusto').textContent=formatarMoeda(r.custoTecnico);document.getElementById('calcResultado').textContent='Custo total: '+formatarMoeda(r.custoTotal)+' · taxa pagamento: '+formatarMoeda(r.taxaPagamento)+(Number(r.impostos)>0?' · imposto ('+String(r.impostosPct).replace('.',',')+'%): '+formatarMoeda(r.impostos):'')+' · resultado: '+formatarMoeda(r.resultado)+' · margem: '+r.margem.toFixed(2).replace('.',',')+'% · markup: '+r.markup.toFixed(2)+'x';}else document.getElementById('calcResultado').textContent=r.message;}catch(e){document.getElementById('calcResultado').textContent='Não foi possível simular agora.';}}
function prepararCalculadoraUI(){const sp=document.getElementById('calcProduto'),sf=document.getElementById('calcForma');if(!sp||!sf)return;sp.innerHTML=(produtos||[]).filter(p=>p.ativo).map(p=>`<option value="${p.id}">${escH(p.nome)}</option>`).join('');sf.innerHTML=(formasPagamento||[]).filter(f=>f.ativa).map(f=>`<option value="${f.id}">${escH(f.nome)}</option>`).join('');calcularCustoUI();}
async function aplicarPrecoCalculadoraUI(){const p=document.getElementById('calcProduto').value,f=document.getElementById('calcForma').value,v=document.getElementById('calcPrecoSimulado').value;try{if(!(Number(v)>0)){showMsg('calcMsg','Informe o preço base simulado.','warn');return;}if(!confirm('Aplicar R$ '+Number(v).toFixed(2).replace('.',',')+' como preço base deste produto? Vale para todas as formas de pagamento (o acréscimo de cada forma é somado na venda).'))return;const r=await apiCall('aplicarPrecoCalculadora',{produtoId:p,formaPagamentoId:f,novoPreco:v});showMsg('calcMsg',r.message,r.ok?'ok':'warn');if(r.ok){produtoPrecos=r.produtoPrecos||produtoPrecos;document.getElementById('calcPrecoSimulado').value='';calcularCustoUI();}}catch(e){showMsg('calcMsg','Erro ao aplicar preço.','warn');}}
function renderClientes(){
  const filtro = document.getElementById('cSearch').value.toLowerCase();
  const modoInativos = document.getElementById('filtroInativosBtn').classList.contains('active');
  const dias = Number(document.getElementById('diasInativo').value) || 30;
  const tbody = document.getElementById('cTable');
  let lista = clientes.filter(c => clienteCombinaBusca_(c, filtro));
  if(modoInativos){
    const agora = Date.now();
    lista = lista.filter(c=>{ const ult = ultimaAtividadeCliente(c); return !ult || (agora - ult) / 86400000 > dias; });
  }
  lista = lista.slice().reverse();
  if(lista.length===0){ tbody.innerHTML = '<tr class="empty-row"><td colspan="3">Nenhum cliente encontrado.</td></tr>'; return; }
  tbody.innerHTML = lista.map(c=>`<tr><td>${c.nome?escH(c.nome):'<em style="color:var(--muted);">(sem nome)</em>'}</td><td>${escH(c.telefone)}</td><td><button class="small-gold" onclick="abrirPerfilCliente('${c.id}')">abrir</button></td></tr>`).join('');
}
var _histFiltro_ = { tel:'', per:'todos', tipo:'todos', pag:'todos' };
function histFiltroMudou_(){
  _histFiltro_.per = document.getElementById('hfPer').value; _histFiltro_.tipo = document.getElementById('hfTipo').value; _histFiltro_.pag = document.getElementById('hfPag').value;
  renderHistoricoCliente(_histFiltro_.tel, true);
}
function renderHistoricoCliente(telefone, manterFiltro){
  const box = document.getElementById('mHistoricoSection');
  if(!box) return;
  const tel = normTel(telefone);
  if(!manterFiltro || _histFiltro_.tel !== tel) _histFiltro_ = { tel: tel, per:'todos', tipo:'todos', pag:'todos' };
  const todos = vendas.filter(v=>normTel(v.clienteTelefone)===tel && v.status==='Confirmada').sort((a,b)=>b.timestamp-a.timestamp);
  const F = _histFiltro_, limite = F.per==='todos' ? 0 : Date.now() - Number(F.per)*86400000;
  const pedidos = todos.filter(v=> (!limite || v.timestamp >= limite) && (F.tipo==='todos' || v.tipoEntrega===F.tipo) && (F.pag==='todos' || (F.pag==='receber' ? v.statusPagamento==='A Receber' : v.statusPagamento!=='A Receber')));
  const sel = (id, atual, ops) => `<select id="${id}" onchange="histFiltroMudou_()" style="width:auto;display:inline-block;margin:0 6px 6px 0;">${ops.map(o=>`<option value="${o[0]}"${String(atual)===String(o[0])?' selected':''}>${o[1]}</option>`).join('')}</select>`;
  const barraFiltros = todos.length < 2 ? '' : `<div style="margin-bottom:8px;">`
    + sel('hfPer', F.per, [['todos','Todo o período'],['7','Últimos 7 dias'],['30','Últimos 30 dias'],['90','Últimos 90 dias']])
    + sel('hfTipo', F.tipo, [['todos','Entrega e retirada'],['Entrega','Só entrega'],['Retirada','Só retirada'],['Mesa','Só mesa']])
    + sel('hfPag', F.pag, [['todos','Pago ou a receber'],['pago','Só pagos'],['receber','Só a receber']]) + `</div>`;
  if(todos.length && pedidos.length===0){ box.innerHTML = '<div class="modal-section"><h3>Histórico de pedidos</h3>'+barraFiltros+'<div class="notif-empty">Nenhum pedido com esses filtros.</div></div>'; return; }
  if(pedidos.length===0){ box.innerHTML = '<div class="modal-section"><h3>Histórico de pedidos</h3><div class="notif-empty">Nenhum pedido ainda.</div></div>'; return; }
  const totalGasto = pedidos.reduce((s,v)=>s+Number(v.valorTotal),0);
  const ticketMedio = totalGasto / pedidos.length;
  let html = `<div class="modal-section"><h3>Histórico de pedidos</h3>
    ${barraFiltros}
    <div style="font-size:12.5px;color:var(--muted);margin-bottom:10px;">
      ${pedidos.length} pedido(s) · Total gasto: <b style="color:var(--gold);">${formatarMoeda(totalGasto)}</b> · Ticket médio: <b style="color:var(--gold);">${formatarMoeda(ticketMedio)}</b>
    </div>
    <div class="obs-line" style="margin-bottom:8px;">Mostra só os pedidos que ainda estão no sistema. Pedidos mais antigos ficam arquivados na planilha e não entram nesta soma (veja em Relatórios, "Outro mês").</div>
    <div style="max-height:220px;overflow-y:auto;">`;
  html += pedidos.map(v=>{
    const tipoIcone = v.tipoEntrega==='Entrega' ? '🛵 Entrega' : '🥡 Retirada';
    const endereco = v.tipoEntrega==='Entrega' && v.endereco ? `<div class="obs-line">${escH(v.endereco)}${escH(v.complemento?', '+v.complemento:'')}</div>` : '';
    return `<div class="notif-card">
      <div>${v.data} — <b>${formatarMoeda(v.valorTotal)}</b></div>
      <div class="obs-line">${itensDoPedido(v.id)}</div>
      <div class="obs-line">${tipoIcone} · ${escH(v.formaPagamento)}${v.statusPagamento==='A Receber'?' · 💰 a receber':''} · ${v.statusPedido||''}</div>
      ${endereco}
    </div>`;
  }).join('');
  html += `</div></div>`;
  box.innerHTML = html;
}
function abrirPerfilCliente(clienteId){
  modalClienteId = clienteId;
  const cliente = clienteId ? clientes.find(c=>c.id===clienteId) : null;
  document.getElementById('mTitulo').textContent = cliente ? 'Perfil do cliente' : 'Novo cliente';
  document.getElementById('mNome').value = cliente ? cliente.nome : '';
  document.getElementById('mTelefone').value = cliente ? cliente.telefone : '';
  document.getElementById('mNascimento').value = cliente ? (cliente.dataNascimento||'') : '';
  document.getElementById('mComoConheceu').value = cliente ? (cliente.comoConheceu||'') : '';
  document.getElementById('mEndereco').value = cliente ? (cliente.endereco||'') : '';
  document.getElementById('mObs').value = cliente ? (cliente.observacao||'') : '';
  document.getElementById('mExcluirBtn').style.display = cliente ? 'block' : 'none';
  document.getElementById('mMsg').className = 'msg';
  if(cliente) renderHistoricoCliente(cliente.telefone); else document.getElementById('mHistoricoSection').innerHTML = '';
  const box = document.getElementById('mPromoSections');
  if(!cliente){ box.innerHTML = ''; }
  else {
    const tel = normTel(cliente.telefone);
    const fid = fidelidadeClientes.find(f=>normTel(f.telefone)===tel);
    const indicou = indicacoes.filter(i=>normTel(i.telIndicador)===tel);
    const foiIndicadoPor = indicacoes.find(i=>normTel(i.telIndicado)===tel);
    let html = `<div class="modal-section"><h3>Indicações</h3>`;
    html += indicou.length ? `<div class="info-line">Indicou: ${escH(indicou.map(i=>i.nomeIndicado).join(', '))}</div>` : `<div class="info-line">Ainda não indicou ninguém.</div>`;
    html += foiIndicadoPor ? `<div class="info-line">Foi indicado por: ${escH(foiIndicadoPor.nomeIndicador)}</div>` : '';
    const premiosInd = (produtos||[]).filter(p=>p.ativo && p.premioIndicacao);
    if(indicou.some(i=>!i.resgatado)){
      html += premiosInd.length
        ? `<div style="margin-top:8px;"><label>Prêmio da indicação:</label><select id="mPremioIndSel">${premiosInd.map(p=>`<option value="${p.id}">${escH(p.nome)}</option>`).join('')}</select><button class="small-gold" style="width:100%;margin-top:6px;" onclick="resgatarBrindeCliente_('Indicação')">🎁 Resgatar indicação</button></div>`
        : `<div class="obs-line">Nenhum prêmio cadastrado. Fale com o gerente.</div>`;
    }
    html += `<button class="small-gold" onclick="abrirModalIndicado()">Indicou alguém</button></div>`;
    const carimbos = fid ? fid.carimbos : 0;
    html += `<div class="modal-section"><h3>Cartão Fidelidade</h3><div class="punch">`;
    for(let i=1;i<=10;i++) html += `<div class="hole ${i<=carimbos?'filled':''}" role="img" aria-label="${i<=carimbos?'Marca '+i+' carimbada':'Marca '+i+' vazia'}"></div>`;
    const premiosFid = (produtos||[]).filter(p=>p.ativo && p.premioFidelidade);
    html += `</div><div class="info-line">${carimbos} de 10 marcas${fid&&fid.premios?(' · '+fid.premios+' prêmio(s) resgatado(s)'):''}</div>`;
    if(carimbos >= 10){
      html += premiosFid.length
        ? `<div style="margin-top:8px;"><label>Prêmio:</label><select id="mPremioFidSel">${premiosFid.map(p=>`<option value="${p.id}">${escH(p.nome)}</option>`).join('')}</select><button class="small-gold" style="width:100%;margin-top:6px;" onclick="resgatarBrindeCliente_('Fidelidade')">🎁 Resgatar prêmio</button></div>`
        : `<div class="obs-line">Nenhum prêmio cadastrado. Fale com o gerente.</div><button class="small-gold" style="width:100%;margin-top:6px;" onclick="showMsg('mMsg','Nenhum prêmio cadastrado. Fale com o gerente.','warn')">Resgatar prêmio</button>`;
    }
    html += `<div class="btnrow"><button class="small-gold" style="flex:1;" onclick="adicionarMarcaModal()">+1 marca</button></div></div>`;
    box.innerHTML = html;
  }
  const boxFeedback = document.getElementById('mFeedbackSection');
  if(boxFeedback){
    if(!cliente){ boxFeedback.innerHTML = ''; }
    else {
      const tel = normTel(cliente.telefone);
      const feedbacksDoCliente = feedbacks.filter(f=>normTel(f.telefone)===tel).sort((a,b)=>(b.data||'').localeCompare(a.data||''));
      let htmlFb = '<div class="modal-section"><h3>Feedbacks enviados</h3>';
      htmlFb += feedbacksDoCliente.length ? feedbacksDoCliente.map(f=>`<div class="notif-card">
          <div>${'★'.repeat(Math.max(0,Math.min(5,f.nota||0)))}${'☆'.repeat(5-Math.max(0,Math.min(5,f.nota||0)))} <span class="obs-line">${f.data}</span></div>
          ${f.comentario?`<div style="margin-top:4px;">${escH(f.comentario)}</div>`:''}
        </div>`).join('') : '<div class="notif-empty">Nenhum feedback enviado ainda.</div>';
      htmlFb += '</div>';
      boxFeedback.innerHTML = htmlFb;
    }
  }
  document.getElementById('clienteModal').classList.add('open');
}
function fecharModalCliente(){ document.getElementById('clienteModal').classList.remove('open'); }
async function salvarModalCliente(){
  const nome = document.getElementById('mNome').value.trim();
  const telefone = document.getElementById('mTelefone').value.trim();
  const dataNascimento = document.getElementById('mNascimento').value;
  const comoConheceu = document.getElementById('mComoConheceu').value;
  const endereco = document.getElementById('mEndereco').value.trim();
  const observacao = document.getElementById('mObs').value.trim();
  if(!nome || !telefone){ showMsg('mMsg','Nome e telefone são obrigatórios.','warn'); return; }
  try{
    const r = await apiCallFila('salvarCliente', { id: modalClienteId, nome, telefone, dataNascimento, endereco, comoConheceu, observacao });
    if(r.ok){
      clientes = r.clientes || clientes; renderClientes(); salvarCache();
      showMsg('mMsg', r.message, 'ok');
      if(r.enfileirado) return;
      const salvo = clientes.find(c=>normTel(c.telefone)===normTel(telefone));
      modalClienteId = salvo ? salvo.id : modalClienteId;
      document.getElementById('mExcluirBtn').style.display = 'block';
    } else { showMsg('mMsg', r.message, 'warn'); }
  } catch(e){ showMsg('mMsg','Não foi possível salvar.','warn'); }
}
function excluirModalCliente(){
  if(!modalClienteId) return;
  if(!confirm('Excluir este cliente do cadastro? O histórico de promoções dele permanece registrado.')) return;
  const executar = async (senha)=>{
    try{
      const r = await apiCall('excluirCliente', { id: modalClienteId, senhaAdminConfirmacao: senha||'' });
      if(r.ok){ clientes = r.clientes || clientes; renderClientes(); salvarCache(); fecharModalCliente(); }
      else showMsg('mMsg', r.message, 'warn');
    } catch(e){ showMsg('mMsg','Não foi possível excluir.','warn'); }
  };
  if(precisaConfirmarAdmin()) abrirModalSenhaAdmin(executar); else executar();
}
/* recarrega o perfil aberto (mesmo cliente, pelo id) e mantém o modal aberto com a mensagem de sucesso */
function reabrirPerfilAtual_(telefone, msg){
  let id = modalClienteId;
  if(!id){ const t = normTel(telefone); const c = clientes.find(x => normTel(x.telefone) === t); id = c ? c.id : null; }
  const modal = document.getElementById('clienteModal') || document.querySelector('#mTitulo') && document.querySelector('#mTitulo').closest('.modal-overlay');
  const rolagem = modal ? (modal.querySelector('.modal-box') || modal).scrollTop : 0;
  abrirPerfilCliente(id);
  if(modal){ modal.classList.add('open'); const box = modal.querySelector('.modal-box') || modal; box.scrollTop = rolagem; }
  if(msg) showMsg('mMsg', msg, 'ok');
}
async function adicionarMarcaModal(){
  const nome = document.getElementById('mNome').value.trim();
  const telefone = document.getElementById('mTelefone').value.trim();
  try{ const r = await apiCallFila('addOrStampFidelidade', { telefone, nome, observacao: '' }, 'Carimbo de fidelidade'); if(r.fidelidade) fidelidadeClientes = r.fidelidade; salvarCache(); showMsg('mMsg', r.message, r.ok?'ok':'warn'); if(r.ok) reabrirPerfilAtual_(telefone, r.message); }
  catch(e){ showMsg('mMsg','Não foi possível registrar.','warn'); }
}
async function resgatarBrindeCliente_(tipo){
  if(!sessaoCaixa){ showMsg('mMsg','Abra o caixa antes de lançar o brinde.','warn'); return; }
  const selId = tipo==='Fidelidade' ? 'mPremioFidSel' : 'mPremioIndSel';
  const produtoId = (document.getElementById(selId)||{}).value;
  if(!produtoId){ showMsg('mMsg','Nenhum prêmio disponível.','warn'); return; }
  const p = produtos.find(x=>x.id===produtoId);
  if(!confirm('Lançar "'+(p?p.nome:'brinde')+'" como prêmio?\n\nZera o cartão (ou marca a indicação) e baixa o estoque.')) return;
  const telefone = document.getElementById('mTelefone').value.trim();
  const ind = tipo==='Indicação' ? indicacoes.find(i=>normTel(i.telIndicador)===normTel(telefone) && !i.resgatado) : null;
  const telIndicado = ind ? ind.telIndicado : null;
  if(tipo==='Indicação' && !telIndicado){ showMsg('mMsg','Indicação pendente não encontrada.','warn'); return; }
  try{
    const r = await apiCall('registrarBrinde', { tipo, produtoId, telefone, telIndicado });
    if(r.fidelidade) fidelidadeClientes = r.fidelidade;
    if(r.indicacoes) indicacoes = r.indicacoes;
    if(r.estoque) estoque = r.estoque;
    if(r.movimentacoesEstoque) movimentacoesEstoque = r.movimentacoesEstoque;
    salvarCache();
    showMsg('mMsg', r.message, r.ok?'ok':'warn');
    if(r.ok) reabrirPerfilAtual_(telefone, r.message);
  }catch(e){ showMsg('mMsg','Não foi possível resgatar.','warn'); }
}
function abrirModalIndicado(){
  const nome = document.getElementById('mNome').value.trim();
  const telefone = document.getElementById('mTelefone').value.trim();
  document.getElementById('indicadoDe').textContent = 'Indicado por: ' + nome + ' (' + telefone + ')';
  document.getElementById('ndNome').value=''; document.getElementById('ndTelefone').value='';
  document.getElementById('ndNascimento').value=''; document.getElementById('ndEndereco').value='';
  document.getElementById('indicadoModal').dataset.telIndicador = telefone;
  document.getElementById('indicadoModal').dataset.nomeIndicador = nome;
  document.getElementById('indicadoModal').classList.add('open');
}
function fecharModalIndicado(){ document.getElementById('indicadoModal').classList.remove('open'); }
async function salvarNovoIndicado(){
  const modal = document.getElementById('indicadoModal');
  const telIndicador = modal.dataset.telIndicador, nomeIndicador = modal.dataset.nomeIndicador;
  const nome = document.getElementById('ndNome').value.trim();
  const telefone = document.getElementById('ndTelefone').value.trim();
  const dataNascimento = document.getElementById('ndNascimento').value;
  const endereco = document.getElementById('ndEndereco').value.trim();
  if(!nome || !telefone){ showMsg('ndMsg','Nome e telefone são obrigatórios.','warn'); return; }
  try{
    const r = await apiCall('indicarNovoCliente', { telIndicador, nomeIndicador, nome, telefone, dataNascimento, endereco, comoConheceu: 'Indicação', observacao: '' });
    if(r.ok){
      clientes = r.clientes || clientes; indicacoes = r.indicacoes || indicacoes; salvarCache();
      showMsg('ndMsg', r.message, 'ok'); renderClientes();
      setTimeout(()=>{ fecharModalIndicado(); abrirPerfilCliente(telIndicador); }, 900);
    } else { showMsg('ndMsg', r.message, 'warn'); }
  } catch(e){ showMsg('ndMsg','Não foi possível registrar.','warn'); }
}

/* ============================================================
   PRODUTOS
   ============================================================ */
/* ITEM 14 — foto do Drive que carrega de verdade dentro de <img> */
function fotoIdDrive_(u){
  const s = String(u || '');
  const m = s.match(/[?&]id=([\w-]{10,})/) || s.match(/\/d\/([\w-]{10,})/);
  return m ? m[1] : '';
}
function fotoSrc_(u, largura){
  const id = fotoIdDrive_(u);
  if(!id) return u || '';
  return 'https://drive.google.com/thumbnail?id=' + id + '&sz=w' + (largura || 800);
}
function fotoFalhou_(img){
  if(!img) return;
  const id = fotoIdDrive_(img.currentSrc || img.src);
  const tentativa = Number(img.dataset.ft || 0);
  const alternativas = [
    'https://lh3.googleusercontent.com/d/' + id,
    'https://drive.google.com/uc?export=view&id=' + id
  ];
  if(!id || tentativa >= alternativas.length){ img.onerror = null; img.style.display = 'none'; return; }
  img.dataset.ft = String(tentativa + 1);
  img.src = alternativas[tentativa];
}

