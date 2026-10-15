/* ---------- MESAS (ITEM 55) ---------- */
function renderMesas(){
  const tbody = document.getElementById('mesaTable');
  if(!tbody) return;
  if(!mesas.length){ tbody.innerHTML = '<tr class="empty-row"><td colspan="3">Nenhuma mesa cadastrada ainda.</td></tr>'; return; }
  const opcoesStatus = ['Livre','Ocupada','Aguardando fechamento','Fechada','Bloqueada/Manutenção'];
  tbody.innerHTML = mesas.map(m=>`<tr>
    <td>Mesa ${m.numero}${m.capacidade?' <span class="obs-line">('+m.capacidade+' lugares)</span>':''}</td>
    <td><select onchange="mudarStatusMesa('${m.id}', this.value)">${opcoesStatus.map(s=>`<option value="${s}" ${s===m.status?'selected':''}>${s}</option>`).join('')}</select></td>
    <td><button class="ghost" onclick="excluirMesaConfirm('${m.id}')">excluir</button></td>
  </tr>`).join('');
}
async function registrarMesa(){
  const numero = document.getElementById('mesaNumero').value.trim();
  const capacidade = document.getElementById('mesaCapacidade').value;
  if(!numero){ showMsg('mesaMsg','Informe o número da mesa.','warn'); return; }
  try{
    const r = await apiCall('addMesa', { numero, capacidade });
    if(r.ok){ mesas = r.mesas || mesas; salvarCache(); renderMesas(); renderMesasPickerCaixa(); document.getElementById('mesaNumero').value=''; document.getElementById('mesaCapacidade').value=''; showMsg('mesaMsg', r.message, 'ok'); }
    else showMsg('mesaMsg', r.message, 'warn');
  } catch(e){ showMsg('mesaMsg','Não foi possível cadastrar.','warn'); }
}
async function mudarStatusMesa(id, novoStatus){
  try{ const r = await apiCall('editarStatusMesa', { id, novoStatus }); if(r.ok){ mesas = r.mesas || mesas; salvarCache(); renderMesas(); renderMesasPickerCaixa(); renderMesasPopup_(); atualizarAlertaMesas_(); } }
  catch(e){ showMsg('mesaMsg','Não foi possível atualizar.','warn'); }
}
async function excluirMesaConfirm(id){
  if(!await confirmarTxt_('Excluir esta mesa?')) return;
  try{ const r = await apiCall('excluirMesa', { id }); if(r.ok){ mesas = r.mesas || mesas; salvarCache(); renderMesas(); renderMesasPickerCaixa(); } else showMsg('mesaMsg', r.message, 'warn'); }
  catch(e){ showMsg('mesaMsg','Não foi possível excluir.','warn'); }
}

/* MELHORIA 5.1 — nome de cliente e login de usuário não são mais colocados dentro de um onclick (quebrava com aspas/apóstrofo):
   ficam em data-* e um único ouvinte de clique chama a função certa. */
document.addEventListener('click', e=>{
  const c = e.target.closest && e.target.closest('[data-cliente-nome]');
  if(c){ selecionarClienteVenda(c.dataset.clienteNome, c.dataset.clienteTel); return; }
  const se = e.target.closest && e.target.closest('[data-sess-encerrar]');
  if(se){ encerrarSessaoRemotaUI_(se.dataset.sessEncerrar); return; }
  const b = e.target.closest && e.target.closest('[data-usr-acao]');
  if(!b) return;
  const lg = b.dataset.usrLogin;
  if(b.dataset.usrAcao==='editar') editarUsuarioPrompt(lg);
  else if(b.dataset.usrAcao==='toggle') toggleAtivoUsuario(lg, b.dataset.usrAtivo==='1');
  else if(b.dataset.usrAcao==='excluir') excluirUsuarioPrompt(lg);
});
function renderUsuarios(){
  const tbody = document.getElementById('uTable');
  try{ carregarSessoes_(false); }catch(e){}
  if(!usuarios.length){ tbody.innerHTML = '<tr class="empty-row"><td colspan="4">Nenhum usuário.</td></tr>'; return; }
  const souDev = !!(currentUser && currentUser.nivelReal === 'Desenvolvedor');
  tbody.innerHTML = usuarios.map((u,iu)=>{
    const protegido = (u.nivel === 'Desenvolvedor' && !souDev);
    const acoes = protegido
      ? '<span class="obs-line" title="Este acesso é protegido: só o próprio Desenvolvedor altera.">🔒 protegido</span>'
      : `<button type="button" class="ghost vs-mais" aria-label="Ações de ${escH(u.login)}" onclick="event.stopPropagation();vsAcoesUsuario(${iu})">⋯</button>`;
    return `<tr${protegido ? '' : ` class="vs-linha" onclick="vsAcoesUsuario(${iu})"`}><td>${escH(u.login)}${u.nome?`<div class="obs-line">${escH(u.nome)}</div>`:''}${u.nivel==='Entregador'?`<div class="obs-line">${u.telefone?'📞 '+escH(u.telefone):'⚠ sem telefone'}</div>`:''}</td><td>${u.nivel}</td><td><span class="badge ${u.ativo?'done':'baixo'}">${u.ativo?'Ativo':'Inativo'}</span></td>
    <td>${acoes}</td></tr>`;
  }).join('');
}
/* ITEM 2.1 — Sessões ativas (Admin). Só leitura + encerrar; nenhum limite de sessões simultâneas (começar só com rastreio). */
let _sessoesCarregadasEm = 0;
async function carregarSessoes_(forcar){
  const box = document.getElementById('sessLista');
  if(!box || !currentUser || currentUser.nivel !== 'Admin') return;
  if(!forcar && (Date.now() - _sessoesCarregadasEm < 60000 || !box.offsetParent)) return;
  _sessoesCarregadasEm = Date.now();
  try{
    const r = await apiCall('listarSessoes', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="notif-empty">Não foi possível carregar as sessões.</div>'; return; }
    renderSessoes_(r.sessoes || []);
  }catch(e){ box.innerHTML = '<div class="notif-empty">Sem conexão para listar as sessões.</div>'; }
}
function renderSessoes_(lista){
  const box = document.getElementById('sessLista');
  if(!lista.length){ box.innerHTML = '<div class="notif-empty">Nenhuma sessão registrada ainda. Sessões aparecem a partir do próximo login de cada pessoa.</div>'; return; }
  box.innerHTML = lista.map(x=>`<div class="notif-card">
      <div><b>${escH(x.login)}</b> <span class="obs-line">${escH(x.nivel)}${x.atual?' · esta sessão':''}</span></div>
      <div class="obs-line">${escH(x.ua||'aparelho não informado')}${x.ip?' · IP '+escH(x.ip):''}${x.deviceId?' · id '+escH(x.deviceId):''}</div>
      <div class="obs-line">Entrou ${escH(x.criadaEm)} · visto ${escH(x.vistoEm)}</div>
      ${x.atual?'':`<div class="btnrow mt-2"><button class="ghost" data-sess-encerrar="${escH(x.sessaoId)}">Encerrar</button></div>`}
    </div>`).join('');
}
async function encerrarSessaoRemotaUI_(sessaoId){
  if(!await confirmarTxt_('Encerrar esta sessão? O aparelho será desconectado.')) return;
  try{
    const r = await apiCall('encerrarSessaoRemota', { sessaoId });
    showMsg('sessMsg', (r && r.message) || (r && r.ok ? 'Sessão encerrada.' : 'Não foi possível encerrar.'), r && r.ok ? 'ok' : 'warn');
  }catch(e){ showMsg('sessMsg', 'Sem conexão. Tente de novo.', 'warn'); }
  carregarSessoes_(true);
}
const SAUDE_COR_ = { ok:'#2f9e44', atencao:'#f0a500', problema:'#d6336c' }, SAUDE_ROT_ = { ok:'Tudo certo', atencao:'Atenção', problema:'Precisa de cuidado' };
/* Saúde do sistema: a lista vive dentro de "Conexão e servidores"; no Painel fica só uma linha com a bolinha geral (toque abre a tela). */
async function carregarSaude_(){
  const card = document.getElementById('saudeCard'), sec = document.getElementById('saudeSecao');
  const nivel = currentUser && currentUser.nivel; const pode = (nivel==='Admin' || nivel==='Desenvolvedor');
  if(card) card.style.display = pode ? '' : 'none';
  if(sec) sec.style.display = pode ? '' : 'none';
  if(!pode){ window._saudeGeral_ = null; return; }
  try{ const sb = document.getElementById('reservaSimBtn'); if(sb){ sb.style.display = nivel==='Desenvolvedor' ? '' : 'none'; sb.textContent = window._sb5Simulado_ ? '✅ Encerrar simulação' : '🧪 Simular queda (treino)'; } }catch(e){}
  const dots = ['saudeDot','saudeDotModal'].map(i=>document.getElementById(i)).filter(Boolean), ress = ['saudeResumo','saudeResumoModal'].map(i=>document.getElementById(i)).filter(Boolean), lis = document.getElementById('saudeLista');
  const pintar = (cor, txt)=>{ dots.forEach(d=>d.style.background = cor); ress.forEach(r=>r.textContent = txt); };
  try{
    const r = await apiCall('saudeSistema', {});
    if(!r || !r.ok){ pintar('#888', (r && r.message) || 'Não foi possível verificar agora.'); if(lis) lis.innerHTML = ''; return; }
    const ruins = (r.itens||[]).filter(i=>i.nivel!=='ok');
    window._saudeGeral_ = r.geral; try{ atualizarConnDot_(); }catch(e){}
    pintar(SAUDE_COR_[r.geral] || '#888', SAUDE_ROT_[r.geral] + (ruins.length ? ': ' + ruins.map(i=>i.titulo).join(', ') : '.') + ' · verificado às ' + String(r.em||'').split(' ')[1]);
    if(lis) lis.innerHTML = (r.itens||[]).map(i=>`<div class="notif-card" style="border-left:4px solid ${SAUDE_COR_[i.nivel]||'#888'};"><b>${escH(i.titulo)}</b><div class="obs-line">${escH(i.texto)}</div></div>`).join('');
  }catch(e){ pintar('#888', 'Sem conexão para verificar.'); }
}
/* confere a Saúde de tempos em tempos para a bolinha do topo (só Admin/Desenvolvedor, só com a tela aberta) */
setInterval(()=>{ try{ const n = currentUser && currentUser.nivel; if((n==='Admin'||n==='Desenvolvedor') && !document.hidden) carregarSaude_(); }catch(e){} }, 300000);
async function carregarAuditoria_(){
  const box = document.getElementById('logLista'); if(!box) return;
  box.innerHTML = (typeof esqueletoLista_ === 'function') ? esqueletoLista_(3) : '<div class="notif-empty">Carregando…</div>';
  try{
    const r = await apiCall('listarAuditoria', { dias: Number(document.getElementById('audDias').value)||30, busca: document.getElementById('audBusca').value });
    if(!r || !r.ok){ box.innerHTML = '<div class="notif-empty">' + escH((r && r.message) || 'Não foi possível carregar agora.') + '</div>'; return; }
    logRecentes = (r.itens||[]).map(x=>({ data:x.data, usuario:x.usuario, perfil:x.perfil, acao:escH(x.acao), detalhes:x.detalhes, autorizador:escH(x.autorizador||''), aparelho:x.aparelho, ip:x.ip }));
    renderLog();
    if((r.itens||[]).length>=300) box.insertAdjacentHTML('beforeend','<div class="obs-line">Mostrando os 300 registros mais recentes. Use a busca ou um período menor para ver os mais antigos.</div>');
  }catch(e){ box.innerHTML = '<div class="notif-empty">Sem conexão para carregar a auditoria.</div>'; }
}
function renderLog(){
  const box = document.getElementById('logLista');
  if(!logRecentes.length){ box.innerHTML = '<div class="notif-empty">Nenhuma ação sensível registrada ainda.</div>'; return; }
  box.innerHTML = logRecentes.map(l=>`<div class="log-item"><div class="quando">${l.data} · ${escH(l.usuario||'—')}${l.perfil?(' ('+l.perfil+')'):''}</div><div>${l.acao}${escH(l.detalhes?(' — '+l.detalhes):'')}</div>${l.autorizador?`<div class="quando">Autorizado por ${l.autorizador}</div>`:''}${l.ip?`<div class="quando">🌐 IP ${escH(l.ip)}</div>`:''}${l.aparelho?`<div class="quando">📱 ${escH(l.aparelho)}</div>`:''}</div>`).join('');
}

/* ---------- CONTAS E ACESSOS (Admin → Sistema): e-mails, links e senhas das contas do sistema. Senha fica no cofre do Supabase. ---------- */
let contasLista_ = [];
async function carregarContas_(){
  const box = document.getElementById('contasLista'); if(!box) return;
  try{
    const r = await apiCall('listarContas', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="notif-empty">' + escH((r && r.message) || 'Não foi possível carregar agora.') + '</div>'; return; }
    contasLista_ = r.contas || []; renderContas_();
  }catch(e){ box.innerHTML = '<div class="notif-empty">Sem conexão para carregar as contas.</div>'; }
}
function renderContas_(){
  const box = document.getElementById('contasLista'); if(!box) return;
  if(!contasLista_.length){ box.innerHTML = '<div class="notif-empty">Nenhuma conta cadastrada ainda.</div>'; return; }
  box.innerHTML = contasLista_.map(c=>`<div class="notif-card">
      <div><b>${escH(c.servico)}</b></div>
      ${c.email?`<div class="obs-line">📧 ${escH(c.email)} <button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;margin-left:6px;" onclick="contaCopiar_(this,'${escH(c.email).replace(/'/g,'&#39;')}')">Copiar</button></div>`:''}
      ${c.link?`<div class="obs-line" style="overflow-wrap:anywhere;">🔗 <a href="${escH(c.link)}" target="_blank" rel="noopener noreferrer" title="${escH(c.link)}" class="txt-ouro">Abrir ${escH(contaHost_(c.link))}</a></div>`:''}
      ${c.temSenha?`<div class="obs-line">🔑 <span id="ctSenhaVer_${c.id}">••••••••</span> <button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;margin-left:6px;" onclick="verSenhaConta_('${c.id}')">Ver senha</button></div>`:''}
      ${c.observacao?`<div class="obs-line">${escH(c.observacao)}</div>`:''}
      <div class="btnrow mt-2"><button class="ghost" onclick="abrirContaModal_('${c.id}')">Editar</button><button class="ghost" onclick="excluirContaUI_('${c.id}')">Excluir</button></div>
    </div>`).join('');
}
function contaHost_(u){ try{ return new URL(u).host.replace(/^www\./,''); }catch(e){ return ''; } }
function contaCopiar_(btn, txt){
  const t = document.createElement('textarea'); t.innerHTML = txt; const v = t.value;
  (navigator.clipboard ? navigator.clipboard.writeText(v) : Promise.reject()).then(()=>{ btn.textContent = 'Copiado'; setTimeout(()=>btn.textContent='Copiar', 1500); }).catch(()=>{ vsForm({ titulo:'Copie o valor', campos:[{ id:'v', rotulo:'Toque e segure para copiar', tipo:'texto', valor:v, max:2000 }], ok:'Fechar' }); });
}
function abrirContaModal_(id){
  const c = contasLista_.find(x=>x.id===id) || null;
  document.getElementById('contaModalTitulo').textContent = c ? 'Editar conta' : 'Nova conta';
  document.getElementById('ctId').value = c ? c.id : '';
  document.getElementById('ctServico').value = c ? c.servico : '';
  document.getElementById('ctEmail').value = c ? c.email : '';
  document.getElementById('ctLink').value = c ? c.link : '';
  document.getElementById('ctObs').value = c ? c.observacao : '';
  document.getElementById('ctSenha').value = '';
  document.getElementById('ctSenha').placeholder = (c && c.temSenha) ? 'Já tem senha guardada — deixe em branco para não mudar' : 'Senha da conta (opcional)';
  document.getElementById('ctRemover').checked = false;
  document.getElementById('ctRemoverBox').style.display = (c && c.temSenha) ? '' : 'none';
  document.getElementById('ctMsg').className = 'msg';
  abrirFormModal('contaModal');
}
async function salvarContaUI_(){
  const p = { id: document.getElementById('ctId').value || undefined, servico: document.getElementById('ctServico').value.trim(), email: document.getElementById('ctEmail').value.trim(),
    link: document.getElementById('ctLink').value.trim(), observacao: document.getElementById('ctObs').value.trim(), senha: document.getElementById('ctSenha').value, removerSenha: document.getElementById('ctRemover').checked };
  if(!p.servico) return showMsg('ctMsg', 'Informe o nome do serviço.', 'warn');
  if(!iniciarOperacaoUnica('salvarConta')) return;
  try{
    const r = await apiCall('salvarConta', p);
    if(r && r.ok){ document.getElementById('ctSenha').value = ''; contasLista_ = r.contas || contasLista_; renderContas_(); fecharFormModal('contaModal'); showMsg('contasMsg', r.message || 'Conta salva.', 'ok'); }
    else showMsg('ctMsg', (r && r.message) || 'Não foi possível salvar.', 'warn');
  }catch(e){ showMsg('ctMsg', 'Sem conexão. Tente de novo.', 'warn'); }
  finally{ finalizarOperacaoUnica('salvarConta'); }
}
async function excluirContaUI_(id){
  const c = contasLista_.find(x=>x.id===id); if(!c) return;
  if(!await confirmarTxt_('Excluir a conta "' + c.servico + '"' + (c.temSenha ? ' e a senha guardada dela' : '') + '?')) return;
  try{
    const r = await apiCall('excluirConta', { id });
    if(r && r.ok){ contasLista_ = r.contas || contasLista_.filter(x=>x.id!==id); renderContas_(); showMsg('contasMsg', r.message || 'Conta excluída.', 'ok'); }
    else showMsg('contasMsg', (r && r.message) || 'Não foi possível excluir.', 'warn');
  }catch(e){ showMsg('contasMsg', 'Sem conexão. Tente de novo.', 'warn'); }
}
function verSenhaConta_(id){
  abrirModalSenhaAdmin(async function(senhaAdm){
    const el = document.getElementById('ctSenhaVer_' + id); if(!el) return;
    try{
      const r = await apiCall('verSenhaConta', { id, senhaAdmin: senhaAdm });
      if(!r || !r.ok){ showMsg('contasMsg', (r && r.message) || 'Não foi possível mostrar a senha.', 'warn'); return; }
      el.textContent = r.senha; el.style.fontFamily = 'monospace'; el.style.color = 'var(--cream)';
      clearTimeout(el._t); el._t = setTimeout(()=>{ el.textContent = '••••••••'; el.style.fontFamily = ''; }, 30000);   // esconde de novo em 30 s
    }catch(e){ showMsg('contasMsg', 'Sem conexão. Tente de novo.', 'warn'); }
  });
}

/* ---------- CHAVES DAS IAs (Contas e acessos): ficam em ai_segredos, onde os assistentes já leem. Ver e trocar pedem senha de administrador. ---------- */
const CHAVES_IA_INFO_ = {
  gemini: { nome:'Gemini (Google) — chat / último recurso', link:'https://aistudio.google.com/apikey' },
  groq:   { nome:'Groq', link:'https://console.groq.com/keys' },
  nvidia: { nome:'NVIDIA — 3º recurso', link:'https://build.nvidia.com/settings/api-keys', extra:true, dica:'IA de reserva: só entra quando o Gemini e a Groq falham. Precisa de conta gratuita no NVIDIA Developer Program.' },
  cloudflare: { nome:'Cloudflare — 4º recurso', link:'https://dash.cloudflare.com/profile/api-tokens', extra:true, conta:true, dica:'IA de reserva: precisa de DOIS dados — o Account ID e um token com permissão "Workers AI".' },
  gemini_2: { nome:'Gemini 2 (Google) — 6º recurso de texto', link:'https://aistudio.google.com/apikey', extra:true, dica:'Segunda chave do Gemini, agora usada exclusivamente para texto. Entra no circuito depois das outras cinco IAs.' },
  groq_2: { nome:'Groq 2 — 2º recurso de texto', link:'https://console.groq.com/keys', extra:true, dica:'Segunda chave Groq para atendimento de texto.' }
};
let chavesIaLista_ = [], iaExtrasPublico_ = false;
async function carregarChavesIa_(){
  const box = document.getElementById('chavesIaLista'); if(!box) return;
  try{
    const r = await apiCall('listarChavesIa', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="notif-empty">' + escH((r && r.message) || 'Não foi possível carregar agora.') + '</div>'; return; }
    chavesIaLista_ = r.chaves || []; iaExtrasPublico_ = !!r.extrasPublico; renderChavesIa_();
  }catch(e){ box.innerHTML = '<div class="notif-empty">Sem conexão para carregar as chaves.</div>'; }
}
function renderChavesIa_(){
  const box = document.getElementById('chavesIaLista'); if(!box) return;
  const bt = 'class="ghost" style="width:auto;padding:4px 10px;min-height:32px;margin-left:6px;"';
  box.innerHTML = chavesIaLista_.map(c=>{ const info = CHAVES_IA_INFO_[c.provedor] || { nome:c.provedor, link:'' };
    return `<div class="notif-card">
      <div><b>${escH(info.nome)}</b></div>
      ${c.temChave
        ? `<div class="obs-line">🔑 <span id="ciVer_${c.provedor}">••••••••${escH(c.final||'')}</span> <button ${bt} onclick="verChaveIa_('${c.provedor}')">Ver chave</button></div>
           <div class="obs-line">Trocada em ${escH(c.atualizadoEm ? fmtDiaHoraBr_(c.atualizadoEm) : '—')}</div>`
        : (info.extra ? `<div class="obs-line">Sem chave: esta IA fica fora do circuito até você cadastrar a chave.</div>` : `<div class="obs-line">⚠️ Sem chave cadastrada: esta IA não funciona.</div>`)}
      ${info.dica?`<div class="obs-line">${escH(info.dica)}</div>`:''}
      ${c.descansando?`<div class="obs-line">😴 Descansando: deu erros agora há pouco; o sistema usa as outras IAs e tenta de novo sozinho.</div>`:''}
      ${info.link?`<div class="obs-line">🔗 <a href="${info.link}" target="_blank" rel="noopener noreferrer" class="txt-ouro">Onde pegar uma chave nova</a></div>`:''}
      <div class="btnrow mt-2"><button class="ghost" onclick="abrirChaveIaModal_('${c.provedor}')">Trocar chave</button>${c.temChave?`<button class="ghost" onclick="testarChaveIa_('${c.provedor}','testeIa_${c.provedor}',this)">🧪 Testar</button>`:''}</div>
      <div class="obs-line" id="testeIa_${c.provedor}"></div>
    </div>`; }).join('') || '<div class="notif-empty">Nenhuma IA configurada.</div>';
  const eb = document.getElementById('iaExtrasBox');
  if(eb) eb.innerHTML = `<div class="notif-card"><label style="display:flex;gap:8px;align-items:flex-start;cursor:pointer;"><input type="checkbox" id="iaExtrasPub" ${iaExtrasPublico_?'checked':''} onchange="salvarIaExtras_(this.checked)" class="largura-auto mt-1"> <span><b>Usar as IAs de reserva também no atendimento ao cliente (cardápio)</b><div class="obs-line">Deixe desligado até confirmar os termos de privacidade de cada provedor: as conversas dos clientes passariam por ele. Desligado, NVIDIA e Cloudflare atendem só o uso interno (equipe).</div></span></label></div>`;
}
/* Teste de cada IA (só Admin/Desenvolvedor): faz uma pergunta mínima ao provedor e mostra se respondeu. Não gasta a cota das consultas. */
const TESTE_IA_MOTIVO_ = { sem_chave:'Sem chave cadastrada.', sem_conta:'Falta o Account ID da Cloudflare.', http_400:'O provedor recusou o pedido (confira o modelo configurado).', http_401:'Chave recusada (errada, expirada ou sem permissão). Troque a chave.', http_403:'Chave sem permissão para usar a IA. Confira as permissões da chave.', http_404:'Endereço ou modelo não encontrado nesse provedor.', http_429:'Limite do plano gratuito atingido agora. Tente mais tarde.', http_503:'Serviço/modelo temporariamente indisponível. Tente novamente.', rede_ou_timeout:'Sem resposta do provedor no tempo esperado.', vazio:'O provedor respondeu, mas vazio.', erro:'Erro inesperado.' };
function testeIaMotivo_(cod){ cod = String(cod||'erro'); return TESTE_IA_MOTIVO_[cod] || (/^http_5/.test(cod) ? 'O provedor está com problema do lado dele (' + cod.replace('http_','erro ') + '). Tente mais tarde.' : 'Falhou (' + cod + ').'); }
async function testarChaveIa_(prov, alvoId, btn){
  const el = document.getElementById(alvoId); if(!el) return false;
  if(btn){ btn.disabled = true; }
  el.className = 'obs-line'; el.textContent = '⏳ Testando… pode levar alguns segundos';
  let ok = false;
  try{
    if(!window.IA || !IA.chamar) throw new Error('sem_ia');
    const acaoTeste = 'testar_ia';
    const r = await IA.chamar(acaoTeste, { provedor: prov }, { forcar:true, ttl:1 });
    if(r && r.ok){
      ok = !!r.funcionando;
      el.textContent = ok ? ('✅ Funcionando · respondeu em ' + (Math.round((r.ms||0)/100)/10).toString().replace('.',',') + ' s' + (r.modelo ? ' · modelo ' + r.modelo : ''))
                          : ('❌ ' + testeIaMotivo_(r.codigo));
    }else if(r && r.codigo === 'sem_permissao'){ el.textContent = '⚠️ Só o Administrador pode testar.'; }
    else if(r && (r.codigo === 'rede' || r.codigo === 'offline' || r.codigo === 'pausado' || r.codigo === 'sessao')){ el.textContent = '⚠️ Não consegui falar com o servidor agora. Confira a conexão e tente de novo.'; }
    else{ el.textContent = '⚠️ Não foi possível testar agora.'; }
  }catch(e){ el.textContent = '⚠️ Não foi possível testar agora.'; }
  if(btn){ btn.disabled = false; }
  return ok;
}
async function testarTodasIas_(provs, btn, pref){
  if(btn) btn.disabled = true;
  for(const pv of provs){ await testarChaveIa_(pv, (pref || 'testeIa_') + pv); }
  if(btn) btn.disabled = false;
}
function salvarIaExtras_(marcado){
  abrirModalSenhaAdmin(async function(senhaAdm){
    try{
      const r = await apiCall('salvarIaExtras', { publico: !!marcado, senhaAdmin: senhaAdm });
      if(r && r.ok){ iaExtrasPublico_ = !!marcado; chavesIaLista_ = r.chaves || chavesIaLista_; renderChavesIa_(); showMsg('chavesIaMsg', r.message || 'Salvo.', 'ok'); }
      else { showMsg('chavesIaMsg', (r && r.message) || 'Não foi possível salvar.', 'warn'); renderChavesIa_(); }
    }catch(e){ showMsg('chavesIaMsg', 'Sem conexão. Tente de novo.', 'warn'); renderChavesIa_(); }
  });
}
function verChaveIa_(prov){
  abrirModalSenhaAdmin(async function(senhaAdm){
    const el = document.getElementById('ciVer_' + prov); if(!el) return;
    try{
      const r = await apiCall('verChaveIa', { provedor: prov, senhaAdmin: senhaAdm });
      if(!r || !r.ok){ showMsg('chavesIaMsg', (r && r.message) || 'Não foi possível mostrar a chave.', 'warn'); return; }
      const antes = el.textContent;
      el.textContent = r.chave + (r.contaId ? ' · conta ' + r.contaId : ''); el.style.fontFamily = 'monospace'; el.style.color = 'var(--cream)'; el.style.overflowWrap = 'anywhere';
      clearTimeout(el._t); el._t = setTimeout(()=>{ el.textContent = antes; el.style.fontFamily = ''; }, 30000);   // esconde de novo em 30 s
    }catch(e){ showMsg('chavesIaMsg', 'Sem conexão. Tente de novo.', 'warn'); }
  });
}
function abrirChaveIaModal_(prov){
  const info = CHAVES_IA_INFO_[prov] || { nome:prov };
  document.getElementById('chaveIaTitulo').textContent = 'Trocar chave — ' + info.nome;
  document.getElementById('ciProvedor').value = prov;
  document.getElementById('ciChave').value = '';
  document.getElementById('ciAjuda').textContent = 'Cole a chave nova inteira. A antiga deixa de ser usada assim que você salvar.';
  document.getElementById('ciMsg').className = 'msg';
  document.getElementById('ciConta').value = ''; document.getElementById('ciContaBox').style.display = info.conta ? '' : 'none';
  if(info.conta) document.getElementById('ciAjuda').textContent = 'Cole o token novo inteiro. O Account ID só precisa ser digitado na primeira vez (ou se mudar).';
  abrirFormModal('chaveIaModal');
}
function salvarChaveIaUI_(){
  const prov = document.getElementById('ciProvedor').value, chave = document.getElementById('ciChave').value.trim();
  if(chave.length < 20 || /\s/.test(chave)) return showMsg('ciMsg', 'Chave inválida. Copie a chave inteira, sem espaços.', 'warn');
  abrirModalSenhaAdmin(async function(senhaAdm){
    if(!iniciarOperacaoUnica('salvarChaveIa')) return;
    try{
      const r = await apiCall('salvarChaveIa', { provedor: prov, chave, contaId: (document.getElementById('ciConta').value||'').trim(), senhaAdmin: senhaAdm });
      if(r && r.ok){ document.getElementById('ciChave').value = ''; chavesIaLista_ = r.chaves || chavesIaLista_; renderChavesIa_(); fecharFormModal('chaveIaModal'); showMsg('chavesIaMsg', r.message || 'Chave salva.', 'ok'); }
      else showMsg('ciMsg', (r && r.message) || 'Não foi possível salvar.', 'warn');
    }catch(e){ showMsg('ciMsg', 'Sem conexão. Tente de novo.', 'warn'); }
    finally{ finalizarOperacaoUnica('salvarChaveIa'); }
  });
}

/* ---------- INTEGRAÇÕES (iFood e Nota fiscal): nascem DESLIGADAS; desligado = sistema idêntico ao de antes ---------- */
window.INTEG_ = window.INTEG_ || { ifood:false, nfce:false, mp:false, nfceModo:'homologacao', impostoPct:0, impostoPadrao:0, impostoMeses:{} };
async function carregarIntegFlags_(){
  try{ const r = await apiCall('integracoesFlags', {}); if(r && r.ok){
    window.INTEG_ = { ifood:!!r.ifood, nfce:!!r.nfce, mp:!!r.mercadopago, nfceModo:r.nfceModo||'homologacao', impostoPct:Number(r.impostoPct)||0, impostoPadrao:Number(r.impostoPadrao)||0, impostoMeses:(r.impostoMeses && typeof r.impostoMeses==='object') ? r.impostoMeses : {} };
    try{ atualizarCpfBox_(); }catch(e){}
    try{ mpFaixaAtualizar_(true); }catch(e){}
    /* a alíquota do imposto chega depois do login: redesenha o que já estiver aberto com ela */
    try{ const at = (document.querySelector('section.tab.active')||{}).id || '';
      if(at==='tab-visaogeral') renderVisaoGeral();
      if(at==='tab-relatorios'){ gerarRelatorio(); renderRelatorio(); } }catch(e){}
  } }catch(e){}
  return window.INTEG_;
}
const INTEG_INFO_ = {
  ifood: { nome:'iFood', icone:'🛵',
    segredos:[['ifood_client_id','Client ID'],['ifood_client_secret','Client Secret'],['ifood_merchant_id','Código da loja (Merchant ID)']],
    guia:[
      'Quem faz: o DONO do restaurante (precisa do CNPJ e do acesso ao Portal do Parceiro do iFood).',
      '1) Entre no portal de desenvolvedores do iFood (developer.ifood.com.br) com o login do restaurante e crie a conta de desenvolvedor.',
      '2) Crie um aplicativo do tipo "Distribuído" (ou o tipo que o iFood indicar para a sua loja) e peça os módulos: Pedidos, Catálogo, Loja (Merchant), Financeiro e Avaliações.',
      '3) O iFood mostra o Client ID e o Client Secret. Copie e digite aqui (botões abaixo). NUNCA mande por mensagem.',
      '4) O código da loja (Merchant ID) aparece no Portal do Parceiro. Digite aqui também.',
      '5) O iFood exige uma HOMOLOGAÇÃO (testes obrigatórios) antes de liberar para valer. Quando ele aprovar, marque o passo no checklist.',
      '6) Na aba Itens do iFood (quando ligado), ligue cada item do iFood ao seu produto.',
      '⚠️ Esta parte ainda não foi testada com o iFood de verdade: os detalhes podem pedir ajuste na primeira ligação.'],
    opcoes:[['confirmacaoAutomatica','Confirmar pedidos do iFood automaticamente (o iFood cancela sozinho se demorar mais de ~8 min)'],['abrirFecharComCaixa','Abrir e fechar a loja no iFood junto com o caixa'],['pausarSemEstoque','Pausar no iFood o item que acabar no estoque'],['enviarPrecos','Permitir enviar nossos preços ao iFood (com trava de variação e histórico)']] },
  nfce: { nome:'Nota fiscal (NFC-e)', icone:'🧾',
    segredos:[['nfce_token_homologacao','Token da Focus NFe — TESTE (homologação)'],['nfce_token_producao','Token da Focus NFe — PRODUÇÃO'],['nfce_csc','CSC — código de segurança secreto (Sefaz)']],
    guia:[
      'Quem faz: o dono e o contador do restaurante.',
      '1) O contador define, para cada tipo de produto: NCM, CFOP e situação tributária (CSOSN). Sem isso nenhuma nota sai certa.',
      '2) Certificado digital A1 (arquivo) em nome da empresa, comprado numa certificadora.',
      '3) Credenciamento na Sefaz do estado para emitir NFC-e e obtenção do CSC (código de segurança) — o contador faz.',
      '4) Crie a conta na Focus NFe (focusnfe.com.br; há 30 dias de teste), cadastre a empresa lá enviando o certificado. A Focus dá um token de teste e outro de produção.',
      '5) Digite os tokens e o CSC aqui (botões "Chaves") e preencha, nos botões do cartão, os "Dados fiscais da empresa" e os "Perfis fiscais". Dica: "Baixar planilha do contador" gera uma planilha com todos os produtos para ele preencher; depois use "Enviar planilha preenchida".',
      '6) Ligue primeiro em TESTE (homologação), emita uma nota de teste e peça ao contador para conferir. Só depois passe para PRODUÇÃO.',
      '⚠️ Esta parte ainda não foi testada com a Focus NFe de verdade.'],
    opcoes:[] },
  mercadopago: { nome:'Mercado Pago (Pix e cartão no site)', icone:'💳',
    segredos:[['mp_public_key_teste','Chave pública (Public Key) — TESTE'],['mp_access_token_teste','Access Token — TESTE'],['mp_public_key_producao','Chave pública (Public Key) — PRODUÇÃO'],['mp_access_token_producao','Access Token — PRODUÇÃO'],['mp_webhook_secret','Chave secreta do aviso (webhook)']],
    guia:[
      'Quem faz: o DONO do restaurante (a conta de vendedor é dele). Os nomes das telas do Mercado Pago podem mudar um pouco; siga o sentido de cada passo.',
      '1) Conta de vendedor: tenha uma conta no Mercado Pago com a verificação de identidade (e da empresa, se for CNPJ) concluída. Sem isso, o dinheiro do Pix e do cartão não é liberado. Marque o passo no checklist quando estiver pronto.',
      '2) Aplicação: entre em mercadopago.com.br/developers > Suas integrações > Criar aplicação. Em tipo de pagamento escolha pagamentos online e, como produto, Checkout Transparente (é o que deixa o cliente pagar sem sair do nosso site).',
      '3) Credenciais de TESTE: na aplicação, abra Credenciais de teste. Copie a Public Key e o Access Token de teste e digite aqui (botões \"Digitar\" da lista Chaves). NUNCA mande por mensagem.',
      '4) Aviso (webhook): na aplicação, vá em Webhooks > Configurar notificações. Cole o endereço que aparece neste cartão (botão Copiar) como URL e marque o evento \"Order (Mercado Pago)\". Salve, revele a Chave secreta e digite aqui em \"Chave secreta do aviso\". É por esse aviso que o pedido sabe que foi pago.',
      '5) Teste guiado (Pix e cartão): ligue em TESTE, faça um pedido de teste pelo cardápio pagando com Pix e outro com cartão de teste. Quando os dois aparecerem como aprovados aqui no cartão, o passo do checklist se marca sozinho. ATENÇÃO: o pedido de teste vira pedido de verdade na cozinha e no caixa; avise a equipe e cancele depois.',
      '6) Produção: na aplicação, ative as credenciais de produção (o Mercado Pago pode pedir mais dados da empresa), copie a Public Key e o Access Token de produção e digite aqui. Depois toque em \"Ligar em PRODUÇÃO\". Dá para desligar a qualquer hora; o cardápio volta a funcionar só com pagamento na entrega.',
      '⚠️ Esta parte ainda não foi testada com o Mercado Pago de verdade: os detalhes podem pedir ajuste na primeira ligação (a Etapa 8 do plano é esse teste).'],
    opcoes:[] }
};
let integStatus_ = [];
function integMsgId_(){ const a = (typeof _abaInterna_ !== 'undefined' && _abaInterna_['tab-contas']) || ''; return 'integMsg_' + (['ifood','nfce','mercadopago'].includes(a) ? a : 'ifood'); }
async function carregarIntegracoes_(){
  const caixas = ['ifood','nfce','mercadopago'].map(p=>document.getElementById('integLista_'+p)).filter(Boolean); if(!caixas.length) return;
  const erro = t=>{ caixas.forEach(b=>{ b.innerHTML = '<div class="notif-empty">' + escH(t) + '</div>'; }); };
  try{
    const r = await apiCall('integracoesStatus', {});
    if(!r || !r.ok){ erro((r && r.message) || 'Não foi possível carregar agora.'); return; }
    integStatus_ = r.integracoes || []; renderIntegracoes_();
  }catch(e){ erro('Sem conexão para carregar.'); }
}
function integResumoHtml_(it, inf){
  const mp = it.provedor === 'mercadopago', prod = mp && mpModoAtual_(it) === 'producao';
  const ck = (it.checklist||[]).filter(c=>!(mp && !prod && (c.id==='teste_guiado' || c.id==='chaves_producao')));
  const pend = mp ? ((prod ? it.pendenciasProducao : it.pendenciasTeste) || []) : (it.pendencias || []);
  const total = ck.length || 1, feitos = Math.max(0, total - pend.length), pct = Math.round(feitos * 100 / total);
  const quem = String((inf.guia||[])[0] || '').replace(/^Quem faz:\s*/i, '');
  let msg, cls;
  if(it.ligado){ msg = '✅ Funcionando' + (it.provedor==='ifood' ? '' : ' em ' + (it.modo==='producao' ? 'PRODUÇÃO' : 'TESTE')) + '. Nada a fazer agora; use as ferramentas do dia a dia mais abaixo.'; cls = 'ok'; }
  else if(!pend.length){ msg = '🎉 Tudo pronto' + (mp ? ' para o modo ' + (prod ? 'PRODUÇÃO' : 'TESTE') : '') + '. Falta só ligar (botão "Ligar", mais abaixo).'; cls = 'ok'; }
  else { msg = '👉 Próximo passo: ' + pend[0]; cls = 'falta'; }
  return `<div class="ig-res ${cls}">
    <div class="ig-res-topo"><b>${it.ligado ? 'LIGADO' : 'DESLIGADO'}</b><span>${feitos} de ${total} passos prontos</span></div>
    <div class="ig-barra"><i style="width:${pct}%"></i></div>
    <div class="ig-prox">${escH(msg)}</div>
    ${pend.length > 1 ? `<div class="ig-resto">Depois: ${pend.slice(1).map(x=>escH(x)).join(' · ')}</div>` : ''}
    ${quem ? `<div class="ig-quem">Quem faz: ${escH(quem)}</div>` : ''}
    <button type="button" class="ghost ig-guiabtn" onclick="integAbrirGuia_('${it.provedor}')">📖 Ver como fazer, passo a passo</button>
  </div>`;
}
function integAbrirGuia_(prov){
  const g = prov === 'mercadopago' ? document.getElementById('mpGuia') : document.getElementById('integGuia_' + prov);
  if(!g) return;
  if(g.tagName === 'DETAILS') g.open = true; else g.hidden = false;
  try{ g.scrollIntoView({ behavior:'smooth', block:'start' }); }catch(e){}
}
function integCardHtml_(it, inf){
  const bt = 'class="ghost" style="width:auto;padding:4px 10px;min-height:32px;margin-left:6px;"', seg = it.segredos || {};
  const sec = (tit, corpo, sub)=>`<div class="ig-sec"><h3>${tit}</h3>${sub?`<p class="ig-sub">${sub}</p>`:''}${corpo}</div>`;
  const chaves = inf.segredos.map(([k,r])=>`<div class="obs-line">${seg[k]?'✅':'⬜'} ${escH(r)} ${seg[k]?'<span id="isVer_'+k+'">••••'+escH(seg[k].final||'')+'</span> <button '+bt+' onclick="verIntegSegredo_(\''+k+'\')">Ver</button>':''} <button ${bt} onclick="abrirIntegSegredo_('${k}','${escH(r)}')">${seg[k]?'Trocar':'Digitar'}</button></div>`).join('');
  const lista = (it.checklist||[]).map(c=>`<label class="obs-line" style="display:flex;gap:8px;align-items:flex-start;${c.auto?'':'cursor:pointer;'}"><input type="checkbox" ${c.feito?'checked':''} ${c.auto?'disabled':''} onchange="marcarIntegPasso_('${it.provedor}','${c.id}',this.checked)" style="width:auto;margin-top:3px;"> <span>${escH(c.titulo)}${c.auto?' <i>(o sistema marca sozinho)</i>':''}</span></label>`).join('');
  const opcoes = inf.opcoes.length ? inf.opcoes.map(([k,t])=>`<label class="obs-line" style="display:flex;gap:8px;align-items:flex-start;cursor:pointer;"><input type="checkbox" ${(it.config||{})[k]?'checked':''} onchange="salvarIntegOpcao_('${it.provedor}','${k}',this.checked)" style="width:auto;margin-top:3px;"> <span>${escH(t)}</span></label>`).join('') : '';
  const nf = it.provedor === 'nfce', fo = it.provedor === 'ifood';
  return `<div class="ig-card ${it.ligado?'on':''}">
    ${integResumoHtml_(it, inf)}
    ${sec('📖 Como fazer', `<details id="integGuia_${it.provedor}" class="ig-guia"><summary>Abrir o passo a passo</summary>${inf.guia.map(g=>`<div class="obs-line">${escH(g)}</div>`).join('')}</details>`)}
    ${sec('🔑 Chaves e códigos', chaves, 'Digite só aqui, nunca por mensagem. Pede a sua senha de administrador.')}
    ${sec('✅ Lista de conferência', lista)}
    ${nf ? sec('🧾 Cadastro fiscal', fiscalExtraHtml_(it, 'setup'), 'O contador define; você cadastra aqui antes de ligar.') : ''}
    ${nf ? sec('⚙️ Onde e quando emitir', nfceOpcoesHtml_(it)) : ''}
    ${fo ? sec('⚙️ Ajustes', opcoes) : ''}
    ${fo ? sec('🔗 Ligar os itens aos produtos', ifoodExtraHtml_(it, 'setup'), 'Cada item do iFood precisa estar ligado a um produto seu.') : ''}
    ${sec('🔌 Ligar ou desligar', `<div class="btnrow">${integBotoes_(it)}</div>${(!it.ligado && !it.podeLigar)?`<div class="obs-line">Ainda falta: ${escH((it.pendencias||[]).join('; '))}</div>`:''}`, 'Pede a sua senha de administrador. Dá para desligar a qualquer momento.')}
    ${sec('📊 No dia a dia', (nf ? fiscalExtraHtml_(it, 'dia') : ifoodExtraHtml_(it, 'dia')) + `<div class="btnrow mt-2"><button class="ghost" onclick="verLogInteg_('${it.provedor}')">Ver registro</button></div><div id="integLog_${it.provedor}"></div>`, it.ligado ? '' : 'Só funciona depois que estiver ligado.')}
  </div>`;
}
function renderIntegracoes_(){
  (integStatus_||[]).forEach(it=>{
    const inf = INTEG_INFO_[it.provedor], box = document.getElementById('integLista_' + it.provedor); if(!inf || !box) return;
    box.innerHTML = it.provedor === 'mercadopago' ? mpCardHtml_(it, inf) : integCardHtml_(it, inf);
  });
  if(document.getElementById('mpRecentes')) carregarMpRecentes_();
  if(document.getElementById('mpPendenciasDecisaoBox')) mpCarregarPendenciasDecisao_();
}
async function marcarIntegPasso_(prov, item, feito){
  try{ const r = await apiCall('integracoesMarcar', { provedor:prov, item, feito:!!feito }); if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; } else showMsg(integMsgId_(), (r&&r.message)||'Não foi possível salvar.', 'warn'); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
  renderIntegracoes_();
}
async function salvarIntegOpcao_(prov, chave, valor){
  try{ const r = await apiCall('integracoesConfig', { provedor:prov, config:{ [chave]: !!valor } }); if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; } else showMsg(integMsgId_(), (r&&r.message)||'Não foi possível salvar.', 'warn'); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
  renderIntegracoes_();
}
function abrirIntegSegredo_(chave, rotulo){
  document.getElementById('isChave').value = chave; document.getElementById('isTitulo').textContent = rotulo;
  document.getElementById('isValor').value = ''; document.getElementById('isMsg').className = 'msg'; abrirFormModal('integSegredoModal');
}
function salvarIntegSegredo_(){
  const chave = document.getElementById('isChave').value, valor = document.getElementById('isValor').value.trim();
  if(valor.length < 8 || /\s/.test(valor)) return showMsg('isMsg', 'Valor inválido. Copie inteiro, sem espaços.', 'warn');
  abrirModalSenhaAdmin(async function(senhaAdm){
    if(!iniciarOperacaoUnica('integSegredo')) return;
    try{
      const r = await apiCall('integracoesSalvarSegredo', { chave, valor, senhaAdmin: senhaAdm });
      if(r && r.ok){ document.getElementById('isValor').value=''; integStatus_ = r.integracoes||integStatus_; renderIntegracoes_(); fecharFormModal('integSegredoModal'); showMsg(integMsgId_(), r.message||'Salvo.', 'ok'); }
      else showMsg('isMsg', (r&&r.message)||'Não foi possível salvar.', 'warn');
    }catch(e){ showMsg('isMsg','Sem conexão. Tente de novo.','warn'); }
    finally{ finalizarOperacaoUnica('integSegredo'); }
  });
}
function verIntegSegredo_(chave){
  abrirModalSenhaAdmin(async function(senhaAdm){
    const el = document.getElementById('isVer_'+chave); if(!el) return;
    try{
      const r = await apiCall('integracoesVerSegredo', { chave, senhaAdmin: senhaAdm });
      if(!r || !r.ok){ showMsg(integMsgId_(), (r&&r.message)||'Não foi possível mostrar.', 'warn'); return; }
      const antes = el.textContent; el.textContent = r.valor; el.style.fontFamily='monospace'; el.style.overflowWrap='anywhere';
      clearTimeout(el._t); el._t = setTimeout(()=>{ el.textContent = antes; el.style.fontFamily=''; }, 30000);
    }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
  });
}
async function ligarInteg_(prov, modo){
  const nome = INTEG_INFO_[prov].nome;
  const amb = prov==='nfce' ? (modo==='producao'?' em PRODUÇÃO (notas valem de verdade)':' em TESTE')
            : prov==='mercadopago' ? (modo==='producao'?' em PRODUÇÃO (os clientes passam a pagar de verdade pelo site)':' em TESTE (só quem estiver na lista de e-mails de teste vê o pagamento online)') : '';
  if(!await confirmarTxt_('Ligar ' + nome + amb + '?\n\nA partir daqui o sistema passa a usar essa integração. Dá para desligar a qualquer momento.')) return;
  abrirModalSenhaAdmin(async function(senhaAdm){
    try{
      const r = await apiCall('integracoesLigar', { provedor:prov, modo, senhaAdmin: senhaAdm });
      if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; renderIntegracoes_(); carregarIntegFlags_(); showMsg(integMsgId_(), r.message||'Ligado.', 'ok'); }
      else showMsg(integMsgId_(), (r&&r.message)||'Não foi possível ligar.', 'warn');
    }catch(e){ showMsg(integMsgId_(),'Sem conexão. Tente de novo.','warn'); }
  });
}
async function desligarInteg_(prov){
  if(!await confirmarTxt_('Desligar ' + INTEG_INFO_[prov].nome + '? O sistema volta a funcionar como antes; o que já foi gravado fica guardado.')) return;
  abrirModalSenhaAdmin(async function(senhaAdm){
    try{
      const r = await apiCall('integracoesDesligar', { provedor:prov, senhaAdmin: senhaAdm });
      if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; renderIntegracoes_(); carregarIntegFlags_(); showMsg(integMsgId_(), r.message||'Desligado.', 'ok'); }
      else showMsg(integMsgId_(), (r&&r.message)||'Não foi possível desligar.', 'warn');
    }catch(e){ showMsg(integMsgId_(),'Sem conexão. Tente de novo.','warn'); }
  });
}
async function verLogInteg_(prov){
  const el = document.getElementById('integLog_'+prov); if(!el) return;
  try{
    const r = await apiCall('integracoesLog', { provedor:prov });
    const it = (r && r.itens) || [];
    el.innerHTML = it.length ? '<div style="margin-top:8px;max-height:220px;overflow:auto;">' + it.map(x=>`<div class="obs-line">${escH(x.em)} · ${x.nivel==='erro'?'❌':x.nivel==='aviso'?'⚠️':'•'} ${escH(x.texto)}</div>`).join('') + '</div>' : '<div class="obs-line">Nenhum registro ainda.</div>';
  }catch(e){ el.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}

/* ---- Mercado Pago (Etapa 4): botões, pendências, formas online, ajustes e teste guiado. Só aparece no cartão "Mercado Pago". ---- */
function integBotoes_(it){
  if(it.provedor==='mercadopago'){
    if(it.ligado){
      return `<button class="ghost" onclick="desligarInteg_('mercadopago')">Desligar</button>` + (it.modo==='producao'
        ? `<button class="ghost" onclick="ligarInteg_('mercadopago','homologacao')">Voltar para TESTE</button>`
        : `<button class="primary" ${it.podeLigarProducao?'':'disabled'} onclick="ligarInteg_('mercadopago','producao')">Passar para PRODUÇÃO</button>`);
    }
    return `<button class="primary" ${it.podeLigarTeste?'':'disabled'} onclick="ligarInteg_('mercadopago','homologacao')">Ligar em TESTE</button><button class="ghost" ${it.podeLigarProducao?'':'disabled'} onclick="ligarInteg_('mercadopago','producao')">Ligar em PRODUÇÃO</button>`;
  }
  return it.ligado
    ? `<button class="ghost" onclick="desligarInteg_('${it.provedor}')">Desligar</button>`
    : (it.provedor==='nfce'
        ? `<button class="primary" ${it.podeLigar?'':'disabled'} onclick="ligarInteg_('nfce','homologacao')">Ligar em TESTE</button><button class="ghost" ${it.podeLigar?'':'disabled'} onclick="ligarInteg_('nfce','producao')">Ligar em PRODUÇÃO</button>`
        : `<button class="primary" ${it.podeLigar?'':'disabled'} onclick="ligarInteg_('${it.provedor}','producao')">Ligar</button>`);
}
/* ---- Cartão do Mercado Pago no Admin: mesmo desenho da Prévia_Mercado_Pago.html (título com estado, lista ✓/!, campos, chave liga/desliga, guia) ---- */
let mpModoVisto_ = '';   // modo que o Admin está olhando: 'homologacao' (teste) ou 'producao'
function mpModoAtual_(it){ return (it.ligado && it.modo) ? it.modo : (mpModoVisto_ || 'homologacao'); }
function mpEscolherModo_(m){ mpModoVisto_ = m; renderIntegracoes_(); }
function mpGuiaAlternar_(){ const g = document.getElementById('mpGuia'); if(g) g.hidden = !g.hidden; }
function mpAlternarLigado_(){
  const it = (integStatus_||[]).find(x=>x.provedor==='mercadopago'); if(!it) return;
  if(it.ligado) return desligarInteg_('mercadopago');
  ligarInteg_('mercadopago', mpModoAtual_(it));
}
function mpCardHtml_(it, inf){
  const seg = it.segredos || {}, modo = mpModoAtual_(it), prod = modo === 'producao';
  const pode = prod ? it.podeLigarProducao : it.podeLigarTeste;
  const bt = 'class="ghost" style="width:auto;padding:4px 10px;min-height:32px;margin:0;"';
  const camp = (k, rot)=>`<div class="mp-camp">${escH(rot)}<span class="v">${seg[k] ? `<span id="isVer_${k}">••••${escH(seg[k].final||'')}</span><button ${bt} onclick="verIntegSegredo_('${k}')">Ver</button>` : '<span class="txt-muted">ainda não digitada</span>'}<button ${bt} onclick="abrirIntegSegredo_('${k}','${escH(rot)}')">${seg[k]?'Trocar':'Digitar'}</button></span></div>`;
  const lista = (it.checklist||[]).map(c=>{
    const ic = `<span class="mp-i ${c.feito?'v':'p'}" aria-hidden="true">${c.feito?'✓':'!'}</span>`;
    return c.auto ? `<li>${ic}<span>${escH(c.titulo)}</span></li>`
      : `<li><label style="display:flex;gap:8px;align-items:flex-start;cursor:pointer;"><input type="checkbox" ${c.feito?'checked':''} onchange="marcarIntegPasso_('mercadopago','${c.id}',this.checked)" style="position:absolute;opacity:0;width:1px;height:1px;">${ic}<span>${escH(c.titulo)} <small class="txt-muted">(toque para marcar)</small></span></label></li>`;
  }).join('');
  const formasOn = (it.formas||[]).filter(f=>f.aceitaOnline && f.tipoOnline).map(f=>mpRotuloTipo_(f.tipoOnline));
  const min = Number((it.config||{}).pixValidadeMin) || 15;
  const estado = it.ligado ? 'LIGADO · ' + (it.modo==='producao' ? 'PRODUÇÃO' : 'TESTE') : 'DESLIGADO';
  const trocaModo = it.ligado ? (it.modo==='producao'
      ? `<button class="mp-admbtn" onclick="ligarInteg_('mercadopago','homologacao')">Voltar para TESTE</button>`
      : `<button class="mp-admbtn" ${it.podeLigarProducao?'':'disabled'} onclick="ligarInteg_('mercadopago','producao')">Passar para PRODUÇÃO</button>`) : '';
  return `<div class="mp-adm ${it.ligado?'on':''}">
    <h3>${inf.icone} Mercado Pago <span class="mp-estado ${it.ligado?'on':''}">${estado}</span></h3>
    <p class="mp-sub">Pagamento dentro do cardápio. Desligado, o cardápio funciona como sempre.</p>
    ${integResumoHtml_(it, inf)}
    <ul class="mp-lista">${lista}</ul>
    ${mpPendenciasHtml_(it)}
    <div class="mp-camp">Modo<div class="mp-modo"><button type="button" aria-pressed="${!prod}" ${it.ligado?'disabled':''} onclick="mpEscolherModo_('homologacao')">Teste</button><button type="button" aria-pressed="${prod}" ${it.ligado?'disabled':''} onclick="mpEscolherModo_('producao')">Produção</button></div></div>
    ${camp(prod?'mp_public_key_producao':'mp_public_key_teste', 'Chave pública (Public Key)')}
    ${camp(prod?'mp_access_token_producao':'mp_access_token_teste', 'Token de acesso (Access Token)')}
    ${camp('mp_webhook_secret', 'Chave secreta do webhook')}
    <div class="mp-camp">Formas pagas online<span class="v">${formasOn.length ? escH(formasOn.join(' · ')) : '<span class="txt-muted">nenhuma escolhida</span>'}</span></div>
    <div class="mp-camp">Validade do Pix<span class="v">${min} minutos</span></div>
    <button type="button" class="mp-sw" role="switch" aria-checked="${!!it.ligado}" ${(!it.ligado && !pode)?'disabled':''} onclick="mpAlternarLigado_()"><i></i><span>Ligar Mercado Pago <small>(pede a senha do Admin)</small></span></button>
    ${trocaModo}
    <button type="button" class="mp-admbtn" onclick="mpGuiaAlternar_()">Ver guia passo a passo</button>
    <div id="mpGuia" class="mp-guia" hidden>${inf.guia.map(g=>`<div class="obs-line">${escH(g)}</div>`).join('')}</div>
    <div class="btnrow"><button class="ghost" onclick="verLogInteg_('mercadopago')">Ver registro</button></div>
    <div id="integLog_mercadopago"></div>
    ${mpExtraHtml_(it)}
  </div>`;
}
function mpPendenciasHtml_(it){
  const l = [];
  if(!it.ligado && !it.podeLigarTeste) l.push('Para ligar em TESTE ainda falta: ' + (it.pendenciasTeste||[]).join('; '));
  if(!(it.ligado && it.modo==='producao') && !it.podeLigarProducao) l.push('Para ' + (it.ligado ? 'passar para' : 'ligar em') + ' PRODUÇÃO ainda falta: ' + (it.pendenciasProducao||[]).join('; '));
  return l.map(t=>`<div class="obs-line">${escH(t)}</div>`).join('');
}
function mpRotuloTipo_(t){ return t==='pix' ? 'Pix' : t==='debito' ? 'Cartão de débito' : t==='credito' ? 'Cartão de crédito' : String(t||''); }
function mpTipoDoNome_(nome){   // mesmo critério do banco: o tipo vem do nome da forma
  const n = String(nome||'').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g,'');
  return /(^|[^a-z])pix([^a-z]|$)/.test(n) ? 'pix' : /credito/.test(n) ? 'credito' : /debito/.test(n) ? 'debito' : '';
}
function mpExtraHtml_(it){
  const cfg = it.config || {};
  const url = (typeof SUPABASE_URL_!=='undefined' ? SUPABASE_URL_ : '') + '/functions/v1/mp-webhook';
  const bt = 'class="ghost" style="width:auto;padding:4px 10px;min-height:32px;margin-left:6px;"';
  const formas = (it.formas||[]).map(f=>{
    const tp = f.aceitaOnline ? (f.tipoOnline||mpTipoDoNome_(f.nome)) : mpTipoDoNome_(f.nome), on = !!f.aceitaOnline;
    if(!tp) return `<div class="obs-line d-flex gap-2 ai-centro fx-wrap"><span style="min-width:120px;">${escH(f.nome)}</span><span style="opacity:.75;">Só na entrega (não há pagamento online para esta forma)</span></div>`;
    return `<div class="obs-line d-flex gap-2 ai-centro fx-wrap"><span style="min-width:120px;">${escH(f.nome)}</span>
      <select class="largura-auto" onchange="mpFormaOnline_('${f.id}', this.value==='on')" aria-label="Pagar online com ${escH(f.nome)}">
        <option value="off" ${on?'':'selected'}>Só na entrega</option><option value="on" ${on?'selected':''}>Também online (${mpRotuloTipo_(tp)})</option></select></div>`;
  }).join('') || '<div class="obs-line">Nenhuma forma de pagamento ativa no cardápio.</div>';
  const emails = Array.isArray(cfg.emailsTeste) ? cfg.emailsTeste.join(', ') : '';
  return `<div class="mt-3">
    <b>🔔 Endereço do aviso (webhook)</b>
    <div class="obs-line" style="overflow-wrap:anywhere;font-family:monospace;">${escH(url)} <button ${bt} onclick="contaCopiar_(this,'${escH(url)}')">Copiar</button></div>
    <div class="obs-line">No Mercado Pago: Webhooks &gt; Configurar notificações &gt; cole este endereço e marque o evento "Order (Mercado Pago)".</div>
  </div>
  <div class="mt-3"><b>💳 Formas de pagamento pelo site</b>
    <div class="obs-line">Para cada forma, escolha: só na entrega ou também online. Online funciona para Pix, cartão de crédito e cartão de débito. Elas continuam valendo também na entrega. Os preços, taxas e acréscimos são os de cada forma.</div>${formas}</div>
  <div class="mt-3"><b>⚙️ Ajustes</b>
    <label class="obs-line" for="mpPixMin">Validade do Pix (minutos, de 5 a 120; combinado: 15)</label>
    <input type="number" id="mpPixMin" min="5" max="120" value="${Number(cfg.pixValidadeMin)||15}" style="width:90px;" onchange="salvarMpConfig_({ pixValidadeMin: Number(this.value) })">
    <label class="obs-line" for="mpEmailsTeste">E-mails que veem o pagamento online em TESTE (até 5, separados por vírgula): a conta Google que você vai usar no cardápio</label>
    <input type="text" id="mpEmailsTeste" value="${escH(emails)}" maxlength="300" placeholder="voce@gmail.com" onchange="salvarMpEmails_(this.value)">
    <label class="obs-line" for="mpEmailPagador">E-mail do comprador de teste do Mercado Pago (só em TESTE; deixe vazio para usar o e-mail da conta)</label>
    <input type="text" id="mpEmailPagador" value="${escH(cfg.emailPagadorTeste||'')}" maxlength="120" placeholder="test_user_...@testuser.com" onchange="salvarMpConfig_({ emailPagadorTeste: this.value.trim() })">
    <label class="obs-line" style="display:flex;gap:8px;align-items:flex-start;cursor:pointer;"><input type="checkbox" ${cfg.testeNoCardapio?'checked':''} onchange="salvarMpConfig_({ testeNoCardapio: this.checked })" style="width:auto;margin-top:3px;"> <span>Em TESTE, mostrar o pagamento online a TODOS os clientes (não recomendado: com chave de teste ninguém consegue pagar de verdade)</span></label>
  </div>
  <div class="mt-3"><b>🧪 Teste guiado</b>
    <div class="obs-line">1) Ligue em TESTE. 2) Digite acima o e-mail da conta Google que você usa no cardápio. 3) Abra o cardápio, entre com essa conta e faça um pedido de entrega pagando pelo site com cada forma que você ligou como online (Pix, crédito, débito). 4) Nos cartões (no cartão de teste do Mercado Pago, use o nome do titular APRO para aprovar e OTHE para recusar; confira a lista atual no site do Mercado Pago). 5) Quando todas as formas ligadas aparecerem aprovadas abaixo, o passo do checklist se marca sozinho.</div>
    <div class="obs-line">⚠️ O pedido de teste aprovado vira pedido de verdade na cozinha e no caixa (e baixa estoque). Avise a equipe e cancele depois.</div>
    <div class="btnrow mt-2"><button class="ghost" onclick="mpAbrirCardapio_()">Abrir o cardápio</button><button class="ghost" onclick="carregarMpRecentes_()">Atualizar lista</button></div>
    <div id="mpRecentes">${(typeof esqueletoLista_ === 'function') ? esqueletoLista_(2) : '<div class="obs-line">Carregando…</div>'}</div>
    <div style="margin-top:10px;border-top:1px solid var(--gold);padding-top:8px;"><b>📊 No dia a dia: pagamentos que precisam de decisão</b><div class="obs-line">Use esta lista quando o dinheiro tiver sido aprovado, mas o pedido não puder entrar automaticamente na cozinha. Reembolsar registra a decisão e chama o Mercado Pago para devolver.</div><button class="ghost" onclick="mpCarregarPendenciasDecisao_()">Atualizar pendências</button><div id="mpPendenciasDecisaoBox"><div class="obs-line">Toque em Atualizar pendências.</div></div></div>
  </div>`;
}
function mpAbrirCardapio_(){
  const it = (integStatus_||[]).find(x=>x.provedor==='mercadopago');
  if(!it || !it.ligado){ showMsg(integMsgId_(),'Ligue o Mercado Pago em TESTE antes de testar.','warn'); return; }
  window.open('https://texasburguer.github.io/apptexasburguer/', '_blank', 'noopener');
}
async function carregarMpRecentes_(){
  const box = document.getElementById('mpRecentes'); if(!box) return;
  try{
    const r = await apiCall('mpPagamentosRecentes', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r&&r.message)||'Não foi possível carregar.') + '</div>'; return; }
    const it = r.itens || [];
    const rot = {aguardando:'aguardando',aprovado:'aprovado',recusado:'recusado',expirado:'vencido',cancelado:'cancelado',reembolso_parcial:'reembolso parcial',reembolsado:'reembolsado',erro:'erro'};
    box.innerHTML = `<div class="obs-line">${mpTestesHtml_(r)}${r.aDecidir?` · ⚠️ ${r.aDecidir} pagamento(s) esperando decisão (seguir ou reembolsar)`:''}</div>`
      + (it.length ? '<div style="max-height:200px;overflow:auto;margin-top:6px;">' + it.map(x=>`<div class="obs-line">${escH(x.em)} · ${x.modo==='producao'?'produção':'teste'} · ${x.metodo==='pix'?'Pix':x.metodo==='debito'?'Débito':'Crédito'} · R$ ${Number(x.valor).toFixed(2).replace('.',',')} · ${escH(rot[x.status]||x.status)}${x.aDecidir?' · A DECIDIR':''}${x.detalhe?' · '+escH(x.detalhe):''}</div>`).join('') + '</div>' : '<div class="obs-line">Nenhum pagamento online ainda.</div>');
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
/* Faixa do Caixa: só aparece com o Mercado Pago LIGADO e pagamento esperando decisão (Admin/Operador). Sem pendência, não aparece nada. */
let _mpFaixaEm_ = 0;
function mpFaixaMostrar_(n){
  const card = document.getElementById('mpPendenciasCaixaCard'); if(!card) return;
  const txt = document.getElementById('mpFaixaTxt'), box = document.getElementById('mpPendenciasDecisaoCaixaBox');
  if(!n || !(window.INTEG_ && INTEG_.mp)){ card.style.display = 'none'; if(box){ box.hidden = true; box.innerHTML = ''; } return; }
  card.style.display = '';
  if(txt) txt.textContent = n === 1 ? '1 pagamento online aguardando decisão' : n + ' pagamentos online aguardando decisão';
}
async function mpFaixaAtualizar_(forcar){
  const card = document.getElementById('mpPendenciasCaixaCard'); if(!card) return;
  const nivel = currentUser && currentUser.nivel;
  if(!(window.INTEG_ && INTEG_.mp) || !(nivel === 'Admin' || nivel === 'Operador' || nivel === 'Desenvolvedor') || (currentUser && currentUser.emergencia)){ mpFaixaMostrar_(0); return; }
  if(!forcar && Date.now() - _mpFaixaEm_ < 60000) return;
  _mpFaixaEm_ = Date.now();
  try{
    const r = await apiCall('mpPendenciasDecisao', {});
    mpFaixaMostrar_(r && r.ok ? (r.itens || []).length : 0);
  }catch(e){ mpFaixaMostrar_(0); }
}
function mpFaixaAlternar_(){
  const box = document.getElementById('mpPendenciasDecisaoCaixaBox'), btn = document.getElementById('mpFaixaBtn'), ver = document.getElementById('mpFaixaVer'); if(!box) return;
  const abrir = box.hidden;
  box.hidden = !abrir;
  if(btn) btn.setAttribute('aria-expanded', abrir ? 'true' : 'false');
  if(ver) ver.textContent = abrir ? 'Fechar' : 'Ver';
  if(abrir) mpCarregarPendenciasDecisao_();
}
async function mpCarregarPendenciasDecisao_(){
  const boxes = [document.getElementById('mpPendenciasDecisaoBox'), document.getElementById('mpPendenciasDecisaoCaixaBox')].filter(Boolean); if(!boxes.length) return;
  boxes.forEach(box=>box.innerHTML = (typeof esqueletoLista_ === 'function') ? esqueletoLista_(2) : '<div class="obs-line">Carregando pendências…</div>');
  try{
    const r = await apiCall('mpPendenciasDecisao', {});
    if(!r || !r.ok){ boxes.forEach(box=>box.innerHTML = '<div class="obs-line">'+escH((r&&r.message)||'Não foi possível carregar as pendências.')+'</div>'); return; }
    const itens = r.itens || [];
    mpFaixaMostrar_(itens.length);
    if(!itens.length){ boxes.forEach(box=>box.innerHTML = '<div class="obs-line">Nenhum pagamento aguardando decisão.</div>'); return; }
    const html = itens.map(x=>`<div class="notif-card mt-2">
      <b>${escH(x.metodo==='pix'?'Pix':x.metodo==='debito'?'Cartão de débito':'Cartão de crédito')} · ${formatarMoeda(Number(x.valor)||0)}</b>
      <div class="obs-line">${escH(x.clienteNome||'Cliente sem nome')} · ${escH(x.telefone||'sem telefone')}</div>
      <div class="obs-line">${escH(x.criadoEm||'')} · ${escH(x.modo==='producao'?'Produção':'Teste')}</div>
      <div class="obs-line">Motivo: ${escH(x.motivo||'Pagamento aprovado sem pedido confirmado.')}</div>
      <div class="btnrow"><button class="primary" onclick="mpDecidirPagamento_('${escH(x.pagamentoId)}','seguir')">Liberar pedido</button><button class="ghost" onclick="mpDecidirPagamento_('${escH(x.pagamentoId)}','reembolsar')">Reembolsar</button></div>
    </div>`).join('');
    boxes.forEach(box=>box.innerHTML=html);
  }catch(e){ boxes.forEach(box=>box.innerHTML = '<div class="obs-line">Sem conexão. Tente novamente.</div>'); }
}
async function mpDecidirPagamento_(pagamentoId, decisao){
  if(!pagamentoId || !['seguir','reembolsar'].includes(decisao)) return;
  const aviso = decisao==='seguir'
    ? 'Liberar este pedido para a cozinha? Confirme que há caixa aberto e que a equipe consegue preparar.'
    : 'Registrar a decisão de reembolsar e solicitar a devolução integral ao Mercado Pago?';
  if(!await confirmarTxt_(aviso)) return;
  const box = document.getElementById('mpPendenciasDecisaoBox');
  if(box) box.insertAdjacentHTML('afterbegin','<div class="obs-line">Registrando decisão…</div>');
  try{
    const r = await apiCall('mpDecidirPagamento', { pagamentoId, decisao });
    if(!r || !r.ok){ showMsg(integMsgId_(),(r&&r.message)||'Não foi possível registrar a decisão.','warn'); await mpCarregarPendenciasDecisao_(); return; }
    if(decisao==='reembolsar'){
      const rr = await sb410Edge_('mp-reembolsar', { pagamentoId }, 60000);
      if(!rr || !rr.ok){ showMsg(integMsgId_(),'A decisão foi registrada, mas a devolução não foi confirmada: '+((rr&&rr.message)||'sem resposta')+'. Confira o painel do Mercado Pago antes de repetir.','warn'); }
      else showMsg(integMsgId_(),'Reembolso confirmado pelo Mercado Pago: '+(rr.message||'devolução registrada.'),'ok');
    } else showMsg(integMsgId_(),r.message||'Pedido liberado.','ok');
    await mpCarregarPendenciasDecisao_(); await carregarMpRecentes_();
  }catch(e){ showMsg(integMsgId_(),'Não foi possível confirmar o resultado. Confira o status antes de repetir.','warn'); await mpCarregarPendenciasDecisao_(); }
}
async function mpCarregarResumoOperacional_(){
  const box = document.getElementById('relMpOnlineBox'); if(!box) return;
  box.innerHTML = (typeof esqueletoLista_ === 'function') ? esqueletoLista_(2) : '<div class="obs-line">Carregando resumo…</div>';
  try{
    const r = await apiCall('mpResumoOperacional', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">'+escH((r&&r.message)||'Não foi possível carregar o resumo.')+'</div>'; return; }
    const it = r.itens||[];
    box.innerHTML = `<div class="obs-line">Período: ${escH(r.periodo||'mês atual')} · ${Number(r.quantidade)||0} transação(ões) processada(s) · Total líquido após reembolsos: <b>${formatarMoeda(Number(r.total)||0)}</b> · Taxas registradas: <b>${formatarMoeda(Number(r.taxas)||0)}</b></div>` +
      (it.length?'<div class="mt-2">'+it.map(x=>`<div class="obs-line">${escH(x.metodo==='pix'?'Pix online':'Cartão online')}: ${Number(x.quantidade)||0} pagamento(s) · ${formatarMoeda(Number(x.total)||0)} recebidos · ${formatarMoeda(Number(x.taxas)||0)} em taxas</div>`).join('')+'</div>':'<div class="obs-line">Ainda não há pagamentos online aprovados neste mês.</div>');
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão. Tente novamente.</div>'; }
}
async function salvarMpConfig_(config){
  try{ const r = await apiCall('integracoesConfig', { provedor:'mercadopago', config }); if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; showMsg(integMsgId_(), r.message||'Ajustes salvos.', 'ok'); } else showMsg(integMsgId_(), (r&&r.message)||'Não foi possível salvar.', 'warn'); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
  renderIntegracoes_();
}
function salvarMpEmails_(txt){
  const lista = String(txt||'').split(/[,;\s]+/).map(x=>x.trim().toLowerCase()).filter(Boolean);
  if(lista.length > 5){ showMsg(integMsgId_(),'No máximo 5 e-mails.','warn'); return; }
  salvarMpConfig_({ emailsTeste: lista });
}
function mpTestesHtml_(r){
  const mp = (integStatus_||[]).find(x=>x.provedor==='mercadopago') || {}, tipos = [...new Set((mp.formas||[]).filter(f=>f.aceitaOnline && f.tipoOnline).map(f=>f.tipoOnline))];
  if(!tipos.length) return '⬜ Ligue pelo menos uma forma online acima para poder testar';
  const ok = { pix:r.testePix, credito:r.testeCredito, debito:r.testeDebito };
  return tipos.map(t=>`${ok[t]?'✅':'⬜'} ${mpRotuloTipo_(t)} aprovado em TESTE`).join(' · ');
}
async function mpFormaOnline_(formaId, ligar){
  try{ const r = await apiCall('mpFormaOnline', { formaId, aceitaOnline: !!ligar, tipoOnline: '' }); if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; showMsg(integMsgId_(), r.message||'Salvo.', 'ok'); carregarIntegFlags_(); } else showMsg(integMsgId_(), (r&&r.message)||'Não foi possível salvar.', 'warn'); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
  renderIntegracoes_();
}

/* ---- Nota fiscal (Fase 4): dados da empresa, perfis fiscais, itens sem perfil, planilha do contador. Só aparece no cartão "Nota fiscal". ---- */
function fiscalExtraHtml_(it, parte){
  if(parte === 'dia') return `<div><div class="btnrow">
      <button class="ghost" onclick="carregarNfceLista_('')">Notas fiscais</button>
      <button class="ghost" onclick="carregarNfceConf_()">Conferência</button>
      <button class="ghost" onclick="carregarNfcePacote_()">Pacote do contador</button>
    </div><div id="nfceLista"></div><div id="nfceConf"></div><div id="nfcePac"></div></div>`;
  return `<div>
    <div class="btnrow">
      <button class="ghost" onclick="carregarFiscalEmpresa_()">Dados fiscais da empresa</button>
      <button class="ghost" onclick="carregarFiscalPerfis_()">Perfis fiscais</button>
      <button class="ghost" onclick="carregarFiscalSem_()">Itens sem perfil</button>
      <button class="ghost" onclick="baixarPlanilhaFiscal_()">Baixar planilha do contador</button>
      <button class="ghost" onclick="document.getElementById('fiscalArq').click()">Enviar planilha preenchida</button>
      <input type="file" id="fiscalArq" accept=".csv,text/csv,text/plain" style="display:none;" onchange="enviarPlanilhaFiscal_(this)">
    </div>
    <div id="fiscalEmpresa"></div><div id="fiscalPerfis"></div><div id="fiscalSem"></div></div>`;
}
const FISCAL_CAMPOS_ = [['razaoSocial','razao_social','Razão social'],['nomeFantasia','nome_fantasia','Nome fantasia'],['cnpj','cnpj','CNPJ (só números)'],['inscricaoEstadual','inscricao_estadual','Inscrição estadual'],
  ['cep','cep','CEP'],['logradouro','logradouro','Rua / avenida'],['numero','numero','Número'],['complemento','complemento','Complemento'],['bairro','bairro','Bairro'],['municipio','municipio','Cidade'],
  ['codigoMunicipio','codigo_municipio','Código do município (7 números — o contador informa)'],['uf','uf','Estado (ex.: SP)'],['telefone','telefone','Telefone'],['cscId','csc_id','Número do CSC (identificador, não o código secreto)'],
  ['serie','serie','Série das notas (normalmente 1)'],['aliquotaSimples','aliquota_simples','Alíquota padrão do imposto em % (vale para os meses sem alíquota própria em Painel → Relatórios, cartão DRE; só para estimar o imposto no resultado e nas margens)']];
async function carregarFiscalEmpresa_(){
  const box = document.getElementById('fiscalEmpresa'); if(!box) return;
  try{
    const r = await apiCall('fiscalEmpresaLer', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    const e = r.empresa || {};
    box.innerHTML = `<div class="notif-card"><b>Dados fiscais da empresa</b> ${r.completa?'✅ completos':'⬜ incompletos'}${r.temCsc?'':' · falta digitar o CSC secreto (cartão Chaves, acima)'}
      <label for="fiscRegime">Regime</label><select id="fiscRegime"><option value="simples" ${e.regime==='simples'?'selected':''}>Simples Nacional</option><option value="mei" ${e.regime==='mei'?'selected':''}>MEI</option><option value="normal" ${e.regime==='normal'?'selected':''}>Lucro presumido/real</option></select>
      ${FISCAL_CAMPOS_.map(([k,c,t])=>`<label for="fisc_${k}">${escH(t)}</label><input id="fisc_${k}" maxlength="120" value="${escH(e[c]==null?'':e[c])}">`).join('')}
      <div class="btnrow mt-2"><button class="primary" onclick="salvarFiscalEmpresa_()">Salvar dados fiscais</button></div><div class="msg" id="fiscEmpMsg"></div></div>`;
  }catch(err){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function salvarFiscalEmpresa_(){
  const p = { regime: document.getElementById('fiscRegime').value };
  FISCAL_CAMPOS_.forEach(([k])=>{ p[k] = document.getElementById('fisc_'+k).value.trim(); });
  try{ const r = await apiCall('fiscalEmpresaSalvar', p); showMsg('fiscEmpMsg', (r && r.message) || 'Não foi possível salvar.', r && r.ok ? 'ok' : 'warn'); if(r && r.ok){ carregarIntegracoes_(); carregarIntegFlags_(); } }
  catch(e){ showMsg('fiscEmpMsg','Sem conexão.','warn'); }
}
let fiscalPerfisCache_ = null;
async function carregarFiscalPerfis_(){
  const box = document.getElementById('fiscalPerfis'); if(!box) return;
  try{
    const r = await apiCall('fiscalPerfis', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    fiscalPerfisCache_ = r; renderFiscalPerfis_();
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
function renderFiscalPerfis_(editar){
  const box = document.getElementById('fiscalPerfis'); const r = fiscalPerfisCache_; if(!box || !r) return;
  const ps = r.perfis || [], opts = sel => '<option value="">(herdar / nenhum)</option>' + ps.filter(x=>x.ativo).map(x=>`<option value="${x.id}" ${sel===x.id?'selected':''}>${escH(x.nome)}</option>`).join('');
  const e = editar || {}; const g = (k, d)=> escH(e[k]==null ? (d||'') : e[k]);
  box.innerHTML = `<div class="notif-card"><b>Perfis fiscais</b> · ${r.semPerfil>0?'⚠️ '+r.semPerfil+' item(ns) ainda sem perfil':'✅ todos os itens têm perfil'}
    ${ps.map(x=>`<div class="obs-line">${x.id===r.padraoId?'⭐ ':''}<b>${escH(x.nome)}</b> — NCM ${escH(x.ncm)} · CFOP ${escH(x.cfop)} · ${x.csosn?'CSOSN '+escH(x.csosn):'CST '+escH(x.cstIcms||'')} · ${x.usos} uso(s)${x.ativo?'':' · desativado'}
      <button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;" onclick="editarFiscalPerfil_('${x.id}')">Editar</button>
      <button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;" onclick="atribuirFiscal_('padrao',null,'${x.id}')">Usar como padrão</button>
      <button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;" onclick="excluirFiscalPerfil_('${x.id}')">Excluir</button></div>`).join('') || '<div class="obs-line">Nenhum perfil ainda. Crie abaixo (o contador informa NCM e CSOSN).</div>'}
    ${r.padraoId?`<div class="obs-line"><button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;" onclick="atribuirFiscal_('padrao',null,'')">Tirar o perfil padrão</button></div>`:''}
    <div class="mt-2"><b>Perfis por categoria</b>${(r.categorias||[]).map(c=>`<div class="obs-line">${escH(c.nome)}: <select onchange="atribuirFiscal_('categoria','${c.id}',this.value)">${opts(c.perfilId)}</select></div>`).join('')}</div>
    <div class="mt-2"><b>${e.id?'Editar perfil':'Novo perfil'}</b>
      <input type="hidden" id="fscId" value="${g('id')}">
      <label for="fscNome">Nome (ex.: Lanches)</label><input id="fscNome" maxlength="60" value="${g('nome')}">
      <label for="fscNcm">NCM (8 números)</label><input id="fscNcm" maxlength="12" value="${g('ncm')}">
      <label for="fscCest">CEST (7 números, se o contador pedir)</label><input id="fscCest" maxlength="9" value="${g('cest')}">
      <label for="fscCfop">CFOP</label><input id="fscCfop" maxlength="4" value="${g('cfop','5102')}">
      <label for="fscCsosn">CSOSN (Simples/MEI, ex.: 102)</label><input id="fscCsosn" maxlength="4" value="${g('csosn')}">
      <label for="fscCst">CST do ICMS (só regime normal)</label><input id="fscCst" maxlength="2" value="${g('cstIcms')}">
      <label for="fscOrigem">Origem da mercadoria (0 = nacional)</label><input id="fscOrigem" maxlength="1" value="${g('origem','0')}">
      <label for="fscUn">Unidade</label><input id="fscUn" maxlength="6" value="${g('unidade','UN')}">
      <label class="obs-line d-flex gap-2"><input type="checkbox" id="fscAtivo" ${e.id && e.ativo===false?'':'checked'} class="largura-auto"> Perfil ativo</label>
      <div class="btnrow mt-2"><button class="primary" onclick="salvarFiscalPerfil_()">Salvar perfil</button>${e.id?'<button class="ghost" onclick="renderFiscalPerfis_()">Cancelar</button>':''}</div><div class="msg" id="fscMsg"></div></div></div>`;
}
function editarFiscalPerfil_(id){ const x = ((fiscalPerfisCache_||{}).perfis||[]).find(p=>p.id===id); if(x) renderFiscalPerfis_(x); }
async function salvarFiscalPerfil_(){
  const v = id => document.getElementById(id).value.trim();
  const p = { id:v('fscId')||null, nome:v('fscNome'), ncm:v('fscNcm'), cest:v('fscCest'), cfop:v('fscCfop'), csosn:v('fscCsosn'), cstIcms:v('fscCst'), origem:v('fscOrigem'), unidade:v('fscUn'), ativo:document.getElementById('fscAtivo').checked };
  try{ const r = await apiCall('fiscalPerfilSalvar', p);
    if(r && r.ok){ fiscalPerfisCache_ = r; renderFiscalPerfis_(); showMsg('fscMsg', r.message||'Salvo.', 'ok'); carregarIntegracoes_(); } else showMsg('fscMsg', (r&&r.message)||'Não foi possível salvar.', 'warn');
  }catch(e){ showMsg('fscMsg','Sem conexão.','warn'); }
}
async function excluirFiscalPerfil_(id){
  if(!await confirmarTxt_('Excluir este perfil fiscal?')) return;
  try{ const r = await apiCall('fiscalPerfilExcluir', { id }); if(r && r.ok){ fiscalPerfisCache_ = r; renderFiscalPerfis_(); carregarIntegracoes_(); } else avisar((r&&r.message)||'Não foi possível excluir.'); }catch(e){ avisar('Sem conexão.'); }
}
async function atribuirFiscal_(alvo, id, perfilId){
  try{ const r = await apiCall('fiscalAtribuir', { alvo, id, perfilId: perfilId||null });
    if(r && r.ok){ fiscalPerfisCache_ = r; renderFiscalPerfis_(); carregarIntegracoes_(); if(document.getElementById('fiscalSem') && document.getElementById('fiscalSem').innerHTML) carregarFiscalSem_(); } else avisar((r&&r.message)||'Não foi possível salvar.');
  }catch(e){ avisar('Sem conexão.'); }
}
async function carregarFiscalSem_(){
  const box = document.getElementById('fiscalSem'); if(!box) return;
  try{
    const [a, b] = await Promise.all([apiCall('fiscalSemPerfil', {}), apiCall('fiscalPerfis', {})]);
    if(!a || !a.ok){ box.innerHTML = '<div class="obs-line">' + escH((a && a.message) || 'Não foi possível carregar.') + '</div>'; return; }
    if(b && b.ok) fiscalPerfisCache_ = b;
    const ps = ((b && b.perfis) || []).filter(x=>x.ativo), it = a.itens || [];
    if(!it.length){ box.innerHTML = '<div class="notif-card">✅ Todos os produtos e combos têm perfil fiscal.</div>'; return; }
    const opt = '<option value="">Escolher perfil…</option>' + ps.map(x=>`<option value="${x.id}">${escH(x.nome)}</option>`).join('');
    window._fiscalSem = it;
    box.innerHTML = `<div class="notif-card"><b>${it.length} item(ns) sem perfil fiscal</b>
      <div class="obs-line">Aplicar a todos: <select id="fsTodos">${opt}</select> <button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;" onclick="aplicarFiscalTodos_()">Aplicar</button></div>
      ${it.map((x,i)=>`<div class="obs-line">${x.tipo==='combo'?'🍱':'🍔'} ${escH(x.nome)} <span class="txt-muted">${escH(x.categoria||'')}</span> <select onchange="atribuirFiscal_('${x.tipo}','${x.id}',this.value)">${opt}</select></div>`).join('')}</div>`;
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function aplicarFiscalTodos_(){
  const pid = document.getElementById('fsTodos').value; if(!pid) return avisar('Escolha o perfil.');
  if(!await confirmarTxt_('Aplicar este perfil a todos os itens da lista?')) return;
  try{ const r = await apiCall('fiscalAtribuir', { alvo:'lote', perfilId:pid, ids:(window._fiscalSem||[]).map(x=>({ tipo:x.tipo, id:x.id })) });
    if(r && r.ok){ fiscalPerfisCache_ = r; carregarFiscalSem_(); carregarIntegracoes_(); } else avisar((r&&r.message)||'Não foi possível salvar.'); }catch(e){ avisar('Sem conexão.'); }
}
const FISCAL_PLAN_COLS_ = ['tipo','id','nome','categoria','perfil','ncm','cest','cfop','csosn','cstIcms','origem','unidade'];
async function baixarPlanilhaFiscal_(){
  try{ const r = await apiCall('fiscalExportar', {});
    if(!r || !r.ok) return avisar((r&&r.message)||'Não foi possível gerar.');
    baixarCsv_('planilha-fiscal.csv', FISCAL_PLAN_COLS_, (r.linhas||[]).map(l=>FISCAL_PLAN_COLS_.map(c=>l[c]==null?'':l[c])));
  }catch(e){ avisar('Sem conexão.'); }
}
function csvLinhas_(txt){
  txt = String(txt||'').replace(/^﻿/, ''); const sep = (txt.split('\n')[0].match(/;/g)||[]).length >= (txt.split('\n')[0].match(/,/g)||[]).length ? ';' : ',';
  const out = []; let l = [], c = '', q = false;
  for(let i=0;i<txt.length;i++){ const ch = txt[i];
    if(q){ if(ch==='"'){ if(txt[i+1]==='"'){ c+='"'; i++; } else q=false; } else c+=ch; }
    else if(ch==='"') q=true; else if(ch===sep){ l.push(c); c=''; }
    else if(ch==='\n'||ch==='\r'){ if(ch==='\r'&&txt[i+1]==='\n') i++; l.push(c); c=''; if(l.some(x=>x!=='')) out.push(l); l=[]; }
    else c+=ch; }
  l.push(c); if(l.some(x=>x!=='')) out.push(l); return out;
}
async function enviarPlanilhaFiscal_(inp){
  const f = inp.files && inp.files[0]; inp.value = ''; if(!f) return;
  try{
    const linhas = csvLinhas_(await f.text()); if(linhas.length < 2) return avisar('Planilha vazia.');
    const cab = linhas[0].map(x=>x.trim().toLowerCase().replace(/[^a-z]/g,'')), ix = n => cab.indexOf(n.toLowerCase());
    const col = { tipo:ix('tipo'), id:ix('id'), nome:ix('nome'), perfil:ix('perfil'), ncm:ix('ncm'), cest:ix('cest'), cfop:ix('cfop'), csosn:ix('csosn'), cstIcms:ix('csticms'), origem:ix('origem'), unidade:ix('unidade') };
    if(col.perfil < 0 || col.ncm < 0) return avisar('Não achei as colunas "perfil" e "ncm". Use a planilha baixada aqui.');
    const dados = linhas.slice(1).map(l=>{ const o = {}; Object.keys(col).forEach(k=>{ o[k] = col[k] >= 0 ? (l[col[k]]||'').trim() : ''; }); return o; });
    if(!await confirmarTxt_('Aplicar ' + dados.length + ' linha(s) da planilha? Isso cria/atualiza perfis e liga os itens a eles.')) return;
    const r = await apiCall('fiscalImportar', { linhas: dados });
    if(r && r.ok){ fiscalPerfisCache_ = r; avisar(r.message || 'Aplicado.'); carregarIntegracoes_(); if(document.getElementById('fiscalPerfis')) renderFiscalPerfis_(); } else avisar((r&&r.message)||'Não foi possível aplicar.');
  }catch(e){ avisar('Não consegui ler o arquivo.'); }
}

/* ---- Nota fiscal (Fase 5): onde/quando emitir, lista de notas, reemitir, DANFE, treino. Só aparece no cartão "Nota fiscal". ---- */
function nfceOpcoesHtml_(it){
  const c = it.config || {}, canais = Array.isArray(c.canais) ? c.canais : ['balcao'], quando = c.emitirQuando || 'pagamento';
  return `<div class="mt-2"><b>Onde e quando emitir a nota</b>
    ${[['balcao','Balcão (Caixa)'],['cardapio','Cardápio online'],['ifood','iFood'],['mesa','Mesa / Garçom']].map(([k,t])=>`<label class="obs-line" style="display:flex;gap:8px;align-items:flex-start;cursor:pointer;"><input type="checkbox" ${canais.indexOf(k)!==-1?'checked':''} onchange="salvarNfceCanal_('${k}',this.checked)" style="width:auto;margin-top:3px;"> ${t}</label>`).join('')}
    <label class="obs-line" for="nfceQuando">Emitir a nota</label>
    <select id="nfceQuando" onchange="salvarNfceConfig_({ emitirQuando:this.value })"><option value="pagamento" ${quando==='pagamento'?'selected':''}>quando a venda for paga (recomendado no balcão)</option><option value="entrega" ${quando==='entrega'?'selected':''}>quando o pedido for entregue (recomendado no delivery)</option></select>
    <div class="obs-line">Dica: comece só com o Balcão e confira com o contador antes de incluir os outros.</div></div>`;
}
async function salvarNfceConfig_(config){
  try{ const r = await apiCall('integracoesConfig', { provedor:'nfce', config }); if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; } else showMsg(integMsgId_(), (r&&r.message)||'Não foi possível salvar.', 'warn'); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
  renderIntegracoes_();
}
function salvarNfceCanal_(canal, marcado){
  const it = (integStatus_||[]).find(x=>x.provedor==='nfce'); const atual = ((it && it.config && it.config.canais) || ['balcao']).filter(x=>x!==canal);
  if(marcado) atual.push(canal);
  return salvarNfceConfig_({ canais: atual });
}
const NFCE_ESTADO_ROT_ = { pendente:'⏳ aguardando emissão', emitindo:'⏳ emitindo', duvida:'⏳ conferindo com a Focus', autorizada:'✅ autorizada', rejeitada:'❌ rejeitada', contingencia:'🟠 em contingência', pendencia:'⚠️ parada (pendência)', cancelando:'⏳ cancelando', cancelada:'⛔ cancelada', erro:'❌ erro de comunicação', dispensada:'— sem nota (valor zero)' };
let nfceFiltro_ = '';
async function carregarNfceLista_(estado){
  const box = document.getElementById('nfceLista'); if(!box) return;
  if(estado !== undefined) nfceFiltro_ = estado || '';
  try{
    const r = await apiCall('nfceLista', { estado: nfceFiltro_ });
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    const ct = r.contagem || {}, dev = currentUser && currentUser.nivelReal === 'Desenvolvedor';
    const chip = (k,t)=>`<button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;${nfceFiltro_===k?'border-color:var(--gold);':''}" onclick="carregarNfceLista_('${k}')">${t}${k&&ct[k]?' ('+ct[k]+')':''}</button>`;
    box.innerHTML = `<div class="notif-card"><b>Notas fiscais</b> · neste mês: ${r.mes||0} de 500 do plano (produção)
      <div class="btnrow mt-2">${chip('','Todas')}${chip('autorizada','Autorizadas')}${chip('rejeitada','Rejeitadas')}${chip('pendencia','Pendências')}${chip('contingencia','Contingência')}${chip('pendente','Aguardando')}${dev?'<button class="ghost" onclick="simularNfce_()">🧪 Nota de treino</button>':''}</div>
      ${(r.itens||[]).map(n=>`<div class="obs-line" style="border-top:1px solid var(--line,#333);padding-top:6px;margin-top:6px;">
        <b>#${escH(n.pedido==null?'?':n.pedido)}</b> ${escH(n.cliente||'')} — ${formatarMoeda(Number(n.valor)||0)} — ${NFCE_ESTADO_ROT_[n.estado]||escH(n.estado)}${n.ambiente!=='producao'?' <span style="color:#d9a441;">['+(n.ambiente==='simulado'?'treino':'teste')+']</span>':''}${n.numero?' · nº '+escH(n.numero)+'/'+escH(n.serie||1):''}${n.cpf?' · com CPF':''}
        ${n.erro?`<div style="color:#ffb3ab;">${escH(n.erro)}</div>`:''}
        <div class="btnrow mt-1">
          ${['rejeitada','pendencia','erro','duvida','dispensada'].indexOf(n.estado)!==-1?`<button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;" onclick="reemitirNfce_(${n.id})">Reemitir</button>`:''}
          ${n.estado==='autorizada'&&n.danfe?`<a class="ghost" style="padding:4px 10px;" href="${escH(n.danfe)}" target="_blank" rel="noopener">Abrir DANFE (cupom)</a>`:''}
          ${n.estado==='autorizada'&&n.xml?`<a class="ghost" style="padding:4px 10px;" href="${escH(n.xml)}" target="_blank" rel="noopener">XML</a>`:''}
          ${n.estado==='autorizada'&&(n.consulta||n.danfe)?`<a class="ghost" style="padding:4px 10px;" href="https://wa.me/?text=${encodeURIComponent('Sua nota fiscal: '+(n.consulta||n.danfe))}" target="_blank" rel="noopener">Enviar ao cliente</a>`:''}
        </div></div>`).join('') || '<div class="obs-line">Nenhuma nota nesta lista ainda.</div>'}</div>`;
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function reemitirNfce_(id){
  if(!await confirmarTxt_('Tentar emitir esta nota de novo?')) return;
  try{ const r = await apiCall('nfceReemitir', { id }); showMsg(integMsgId_(), (r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); setTimeout(()=>carregarNfceLista_(), 5000); carregarNfceLista_(); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}
async function simularNfce_(){
  try{ const r = await apiCall('nfceSimular', {}); showMsg(integMsgId_(), (r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); setTimeout(()=>carregarNfceLista_(), 8000); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}
function atualizarCpfBox_(){ const b = document.getElementById('vCpfBox'); if(b) b.style.display = (window.INTEG_ && INTEG_.nfce && !(typeof souGarcom_==='function' && souGarcom_())) ? '' : 'none'; }

/* ---- Nota fiscal (Fase 6): conferência Vendas × Notas, numeração pulada (inutilizar), pacote do contador ---- */
async function carregarNfceConf_(){
  const box = document.getElementById('nfceConf'); if(!box) return;
  try{
    const r = await apiCall('nfceConferencia', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    const bt = 'class="ghost" style="width:auto;padding:4px 10px;min-height:32px;"';
    const t = r.totais || {};
    box.innerHTML = `<div class="notif-card"><b>Conferência (últimos ${r.dias} dias)</b>
      <div class="obs-line">Vendas dos canais escolhidos: ${formatarMoeda(Number(t.vendas)||0)} · notas autorizadas: ${formatarMoeda(Number(t.notas)||0)}</div>
      <div class="obs-line">${(r.semNota||[]).length ? '⚠️ '+r.semNota.length+' venda(s) que deveriam ter nota e não têm:' : '✅ Nenhuma venda sem nota.'}</div>
      ${(r.semNota||[]).map(v=>`<div class="obs-line">#${escH(v.pedido)} ${escH(v.cliente||'')} — ${formatarMoeda(Number(v.valor)||0)} <button ${bt} onclick="emitirVendaNfce_('${v.vendaId}')">Emitir nota</button></div>`).join('')}
      <div class="obs-line">${r.comProblema ? '❌ '+r.comProblema+' nota(s) com problema (veja a lista "Rejeitadas"/"Pendências").' : '✅ Nenhuma nota com problema.'}</div>
      ${(r.cancelarManual||[]).length ? '<div class="obs-line">⚠️ Cancelamentos que o contador precisa orientar:</div>' + r.cancelarManual.map(n=>`<div class="obs-line">#${escH(n.pedido==null?'?':n.pedido)} nota ${escH(n.numero||'')} — ${escH(n.motivo||'')}</div>`).join('') : ''}
      <div class="obs-line">${(r.buracos||[]).length ? '⚠️ Numeração pulada:' : '✅ Sem números pulados.'}</div>
      ${(r.buracos||[]).map(g=>`<div class="obs-line">Série ${g.serie}: números ${g.ini}${g.fim!==g.ini?' a '+g.fim:''} <button ${bt} onclick="inutilizarNfce_(${g.serie},${g.ini},${g.fim})">Inutilizar</button></div>`).join('')}
      ${(r.inutilizacoes||[]).length ? '<div class="obs-line">Últimas inutilizações: '+r.inutilizacoes.map(i=>`série ${i.serie} ${i.ini}-${i.fim} (${escH(i.estado)})`).join('; ')+'</div>' : ''}
      <div class="msg" id="nfceConfMsg"></div></div>`;
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function emitirVendaNfce_(vendaId){
  if(!await confirmarTxt_('Criar a nota desta venda agora?')) return;
  try{ const r = await apiCall('nfceEmitirVenda', { vendaId }); showMsg('nfceConfMsg', (r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); setTimeout(carregarNfceConf_, 6000); }catch(e){ showMsg('nfceConfMsg','Sem conexão.','warn'); }
}
async function inutilizarNfce_(serie, ini, fim){
  const f = await vsForm({ titulo:'Inutilizar numeração', texto:'Série ' + serie + ', números ' + ini + (fim && fim !== ini ? ' a ' + fim : '') + '.', ok:'Continuar',
    campos:[ { id:'just', rotulo:'Motivo (mínimo 15 letras)', tipo:'texto', obrigatorio:true, minLetras:15, max:255, valor:'Numeração pulada por falha de emissão' } ] });
  if(!f) return; const just = f.just;
  abrirModalSenhaAdmin(async function(senhaAdm){
    try{ const r = await apiCall('nfceInutilizar', { serie, ini, fim, justificativa:just.trim(), senhaAdmin:senhaAdm }); showMsg('nfceConfMsg', (r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); setTimeout(carregarNfceConf_, 6000); }
    catch(e){ showMsg('nfceConfMsg','Sem conexão.','warn'); }
  });
}
async function carregarNfcePacote_(){
  const box = document.getElementById('nfcePac'); if(!box) return;
  const hoje = new Date(); const mesPad = hoje.getFullYear() + '-' + String(hoje.getMonth()+1).padStart(2,'0');
  box.innerHTML = `<div class="notif-card"><b>Pacote do contador</b>
    <label for="nfcePacMes">Mês</label><input type="month" id="nfcePacMes" value="${mesPad}">
    <div class="btnrow mt-2"><button class="primary" onclick="baixarPacoteNfce_()">Baixar planilha do mês</button></div>
    <div id="nfcePacLinks"></div><div class="obs-line">A Focus também baixa todos os XML do mês no painel dela.</div></div>`;
}
async function baixarPacoteNfce_(){
  const v = (document.getElementById('nfcePacMes')||{}).value || ''; const [ano, mes] = v.split('-').map(Number);
  try{
    const r = await apiCall('nfcePacote', { ano, mes });
    if(!r || !r.ok) return avisar((r&&r.message)||'Não foi possível gerar.');
    const cab = ['Pedido','Emitida em','Número','Série','Chave','Valor','Situação','Cancelada em','CPF informado','XML'];
    baixarCsv_('notas-fiscais-' + ano + '-' + String(mes).padStart(2,'0') + '.csv', cab, (r.notas||[]).map(n=>[n.pedido==null?'':n.pedido, n.emitidaEm||'', n.numero||'', n.serie||'', n.chave||'', csvNum_(n.valor), n.estado, n.canceladaEm||'', n.comCpf?'sim':'não', n.xml||'']));
    const el = document.getElementById('nfcePacLinks');
    if(el) el.innerHTML = (r.notas||[]).length ? '<div class="obs-line">'+r.notas.length+' nota(s) no mês ('+escH(r.ambiente==='producao'?'produção':'teste')+')'+((r.inutilizacoes||[]).length?' · '+r.inutilizacoes.length+' inutilização(ões)':'')+'</div>' + r.notas.filter(n=>n.xml).map(n=>`<div class="obs-line"><a href="${escH(n.xml)}" target="_blank" rel="noopener">XML nº ${escH(n.numero||'')}</a></div>`).join('') : '<div class="obs-line">Nenhuma nota neste mês.</div>';
  }catch(e){ avisar('Sem conexão.'); }
}

/* ---- iFood: pedidos, itens ligados, simulação (aparecem dentro do cartão Integrações) ---- */
function ifoodExtraHtml_(it, parte){
  const dev = currentUser && currentUser.nivelReal === 'Desenvolvedor';
  const aviso = (()=>{ const f = (formasPagamento||[]).find(x=>String(x.nome||'').toLowerCase()==='ifood'); return (f && (Number(f.taxaPct)>0 || Number(f.taxaFixa)>0)) ? '' : '<div class="obs-line">⚠️ Cadastre a comissão do iFood em Operação → Pagamentos, na forma "iFood" (taxa %). Ela é tirada de cada pedido nos relatórios até o repasse trazer a comissão real.</div>'; })();
  if(parte === 'setup') return `<div class="btnrow"><button class="ghost" onclick="carregarIfoodItens_()">Itens do iFood</button><button class="ghost" onclick="reprocessarIfood_()">Refazer pedidos sem ligação</button></div>${aviso}<div id="ifoodItens"></div>`;
  return `<div>
    <div class="btnrow">
      <button class="ghost" onclick="carregarIfoodLoja_()">Loja no iFood</button>
      <button class="ghost" onclick="carregarIfoodNeg_()">Negociações</button>
      <button class="ghost" onclick="carregarIfoodPedidos_()">Pedidos do iFood</button>
      <button class="ghost" onclick="carregarIfoodPrecos_()">Preços</button>
      <button class="ghost" onclick="carregarIfoodFin_()">Financeiro</button>
      <button class="ghost" onclick="carregarIfoodAval_()">Avaliações</button>
      <button class="ghost" onclick="carregarIfoodRel_()">Relatório por canal</button>
      ${dev?'<button class="ghost" onclick="simularIfood_()">🧪 Simular pedido do iFood (treino)</button>':''}
    </div>
    <div id="ifoodLoja"></div><div id="ifoodNeg"></div><div id="ifoodPedidos"></div><div id="ifoodPrecos"></div><div id="ifoodFin"></div><div id="ifoodAval"></div><div id="ifoodRel"></div></div>`;
}
const IFOOD_ESTADO_ROT_ = { novo:'aguardando confirmação', confirmado:'confirmado', em_preparo:'em preparo', pronto:'pronto', despachado:'saiu para entrega', concluido:'concluído', cancelado:'cancelado' };

async function carregarIfoodLoja_(){
  const box = document.getElementById('ifoodLoja'); if(!box) return;
  try{
    const r = await apiCall('ifoodLoja', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    const l = r.loja || {}; const pausa = l.pausada_ate && new Date(l.pausada_ate) > new Date();
    box.innerHTML = `<div class="notif-card" style="border-left:4px solid ${l.verificado_em?(l.disponivel?'#2e9e5b':'#c0392b'):'#888'};">
      <b>Loja no iFood:</b> ${l.verificado_em?(l.disponivel?'🟢 aberta':'🔴 fechada/indisponível'):'ainda não verificada'}${l.situacao?' ('+escH(l.situacao)+')':''}${pausa?' · pausada até '+escH(fmtDiaHoraBr_(l.pausada_ate)):''}
      ${l.motivo?`<div class="obs-line">${escH(l.motivo)}</div>`:''}
      <div class="btnrow mt-2"><button class="ghost" onclick="lojaIfoodAcao_('pausar',30)">Pausar 30 min</button><button class="ghost" onclick="lojaIfoodAcao_('pausar',60)">Pausar 1 h</button><button class="ghost" onclick="lojaIfoodAcao_('retomar')">Retomar</button><button class="ghost" onclick="lojaIfoodAcao_('fechar')">Fechar</button><button class="ghost" onclick="lojaIfoodAcao_('abrir')">Abrir</button></div></div>`;
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function lojaIfoodAcao_(acao, minutos){
  try{ const r = await apiCall('ifoodLojaAcao', { acao, minutos }); showMsg(integMsgId_(), (r && r.message) || 'Não foi possível.', r && r.ok ? 'ok' : 'warn'); setTimeout(carregarIfoodLoja_, 4000); carregarIfoodLoja_(); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}
async function carregarIfoodNeg_(){
  const box = document.getElementById('ifoodNeg'); if(!box) return;
  try{
    const r = await apiCall('ifoodNegociacoes', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    box.innerHTML = (r.itens||[]).map(n=>{ const aberta = n.estado==='aberta' && n.segundos>0;
      return `<div class="notif-card" style="border-left:4px solid ${aberta?'#e0a800':'#888'};">
        <b>Pedido iFood #${escH(n.pedido||'')}</b> — ${escH(n.tipo||'cancelamento')} · ${escH(n.estado)}
        <div class="obs-line">${escH(n.motivo||'')}</div>
        ${aberta?`<div class="obs-line">⏱ Responder em até ${Math.floor(n.segundos/60)} min ${n.segundos%60} s</div>
          <div class="btnrow"><button class="primary" onclick="negIfood_('${escH(n.id)}','aceitar')">Aceitar</button><button class="ghost" onclick="negIfood_('${escH(n.id)}','recusar')">Recusar</button>
          ${(n.alternativas||[]).map(a=>`<button class="ghost" onclick="negIfood_('${escH(n.id)}','alternativa','${escH(a.id||'')}')">${escH(a.type||a.id||'Alternativa')}</button>`).join('')}</div>`:''}
      </div>`; }).join('') || '<div class="obs-line">Nenhuma negociação.</div>';
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function negIfood_(id, acao, alternativaId){
  if(acao==='recusar' && !await confirmarTxt_('Recusar o pedido do cliente? O iFood pode decidir por ele depois.')) return;
  try{ const r = await apiCall('ifoodNegociacaoResponder', { id, acao, alternativaId }); showMsg(integMsgId_(), (r && r.message) || 'Não foi possível.', r && r.ok ? 'ok' : 'warn'); carregarIfoodNeg_(); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}

const R$_ = v => formatarMoeda(v);
let ifoodPrecosDados_ = null;
async function carregarIfoodPrecos_(){
  const box = document.getElementById('ifoodPrecos'); if(!box) return;
  try{
    const r = await apiCall('ifoodPrecos', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    ifoodPrecosDados_ = r;
    box.innerHTML = `<div class="notif-card"><b>Preços: sistema × iFood</b>
      <div class="btnrow mt-2"><button class="ghost" onclick="pedirCatalogoIfood_()">Importar cardápio do iFood</button><button class="ghost" onclick="aplicarPrecosIfood_()">Gravar preços do iFood no sistema</button>${r.enviarLigado?'<button class="ghost" onclick="enviarPrecosIfood_()">Enviar nossos preços ao iFood</button>':''}</div>
      <div class="obs-line">${r.enviarLigado?'Envio ligado. Variação máxima por envio: '+r.limitePct+'%.':'Para enviar preços ao iFood, ligue antes o ajuste "Enviar nossos preços ao iFood".'}</div></div>` +
      ((r.itens||[]).map((i,ix)=>`<div class="notif-card" style="border-left:4px solid ${i.pct>20?'#e0a800':'#2e9e5b'};"><label style="display:flex;gap:8px;align-items:flex-start;"><input type="checkbox" class="ifPrecoSel largura-auto mt-1" value="${escH(i.chave)}"> <span><b>${escH(i.nome||i.nomeIfood)}</b><div class="obs-line">Sistema ${i.precoSistema!=null?R$_(i.precoSistema):'—'} · iFood ${i.precoIfood!=null?R$_(i.precoIfood):'não importado'}${i.pct!=null?' · diferença '+(i.diff>0?'+':'')+R$_(i.diff)+' ('+i.pct+'%)':''}${i.pct>20?' ⚠️ fora do padrão':''}</div></span></label></div>`).join('') || '<div class="obs-line">Ligue itens do iFood a produtos e importe o cardápio para comparar.</div>') +
      ((r.historico||[]).length?'<div class="notif-card"><b>Histórico</b>'+r.historico.map(h=>`<div class="obs-line">${escH(fmtDiaHoraBr_(h.quando))} · ${escH(h.nome||'')} · ${h.antes!=null?R$_(h.antes):'—'} → ${R$_(h.depois)} · ${escH(h.origem)} (${escH(h.estado)})${h.erro?' ❗'+escH(h.erro):''} ${h.origem==='enviar'&&h.estado==='ok'?'<button class="ghost" style="width:auto;padding:2px 8px;min-height:28px;" onclick="desfazerPrecoIfood_('+h.id+')">Desfazer</button>':''}</div>`).join('')+'</div>':'');
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
const selPrecosIfood_ = ()=>[...document.querySelectorAll('.ifPrecoSel:checked')].map(x=>x.value);
async function pedirCatalogoIfood_(){ try{ const r = await apiCall('ifoodPrecosPedirCatalogo', {}); showMsg(integMsgId_(),(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); } }
async function aplicarPrecosIfood_(){
  const ch = selPrecosIfood_(); if(!ch.length) return showMsg(integMsgId_(),'Marque os itens que quer gravar no sistema.','warn');
  if(!await confirmarTxt_('Gravar no sistema o preço do iFood de '+ch.length+' item(ns)? (muda o campo "Preço no iFood")')) return;
  try{ const r = await apiCall('ifoodPrecosAplicar', { chaves: ch }); showMsg(integMsgId_(),(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); carregarIfoodPrecos_(); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}
async function enviarPrecosIfood_(){
  const ch = selPrecosIfood_(); if(!ch.length) return showMsg(integMsgId_(),'Marque os itens que quer enviar ao iFood.','warn');
  if(!await confirmarTxt_('ENVIAR ao iFood o nosso preço de '+ch.length+' item(ns)? Os clientes do iFood passarão a ver o novo preço. Dá para desfazer pelo histórico.', 'Enviar ao iFood', false, 'Enviar preços ao iFood')) return;
  try{ const r = await apiCall('ifoodPrecosEnviar', { chaves: ch, confirmar: 'true' }); showMsg(integMsgId_(),(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); carregarIfoodPrecos_(); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}
async function desfazerPrecoIfood_(id){
  if(!await confirmarTxt_('Reenviar o preço anterior ao iFood?')) return;
  try{ const r = await apiCall('ifoodPrecosDesfazer', { id }); showMsg(integMsgId_(),(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); carregarIfoodPrecos_(); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}
async function carregarIfoodFin_(){
  const box = document.getElementById('ifoodFin'); if(!box) return;
  try{
    const r = await apiCall('ifoodFinanceiro', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    box.innerHTML = `<div class="notif-card"><b>A receber do iFood:</b> ${R$_(r.aReceber.valor)} em ${r.aReceber.pedidos} pedido(s) pagos no app, ainda sem repasse (já sem a comissão${Number(r.aReceber.bruto)>Number(r.aReceber.valor)?'; valor dos pedidos '+R$_(r.aReceber.bruto):''}).
      <div class="obs-line">Até o repasse chegar, a comissão é a estimada (taxa % da forma "iFood" em Pagamentos); quando o repasse chega, o sistema troca pela comissão real.</div>
      <div class="obs-line">Recebido nos últimos 30 dias: ${R$_(r.recebido30d.valor)} em ${r.recebido30d.repasses} repasse(s) · comissão real registrada: ${R$_(r.comissao30d)}</div></div>` +
      ((r.repasses||[]).map(x=>`<div class="obs-line">${escH(x.pagoEm||'')} · ${R$_(x.valor)} · ${x.pedidos} pedido(s)</div>`).join(''));
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function carregarIfoodAval_(){
  const box = document.getElementById('ifoodAval'); if(!box) return;
  try{
    const r = await apiCall('ifoodAvaliacoes', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    box.innerHTML = `<div class="obs-line">Nota média (30 dias): ${r.media30d!=null?r.media30d:'—'}</div>` + ((r.itens||[]).map(a=>`<div class="notif-card" style="border-left:4px solid ${a.nota<=2?'#c0392b':'#2e9e5b'};">⭐ ${a.nota} ${a.pedido?'· pedido #'+escH(a.pedido):''} <div class="obs-line">${escH(a.comentario||'(sem comentário)')}</div>
      ${a.resposta?`<div class="obs-line">↩ ${escH(a.resposta)}</div>`:`<input type="text" id="avR_${escH(a.id)}" maxlength="600" placeholder="Sua resposta"> <button class="ghost" onclick="responderAvalIfood_('${escH(a.id)}')">Responder</button>`}</div>`).join('') || '<div class="obs-line">Nenhuma avaliação ainda.</div>');
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function responderAvalIfood_(id){
  const t = (document.getElementById('avR_'+id)||{}).value || '';
  try{ const r = await apiCall('ifoodAvaliacaoResponder', { id, texto: t }); showMsg(integMsgId_(),(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); carregarIfoodAval_(); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}
async function carregarIfoodRel_(){
  const box = document.getElementById('ifoodRel'); if(!box) return;
  try{
    const r = await apiCall('ifoodRelatorio', { dias: 30 });
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    const f = r.ifood || {};
    box.innerHTML = `<div class="notif-card"><b>Vendas por canal — últimos ${r.dias} dias</b>` + (r.canais||[]).map(c=>`<div class="obs-line">${escH(c.canal)}: ${c.pedidos} pedido(s) · ${R$_(c.total)} · ticket ${R$_(c.ticket)} · margem ${c.margemPct}% · cancelados ${c.cancelados}</div>`).join('') + `<div class="obs-line txt-muted">Margem = total − custo dos produtos − taxas e comissões − imposto estimado.</div></div>
      <div class="notif-card"><b>iFood</b><div class="obs-line">Tempo médio para confirmar: ${f.confirmacaoMediaMin!=null?f.confirmacaoMediaMin+' min':'—'} · itens sem ligação: ${f.itensSemLigacao||0} · comissão real: ${R$_(f.comissaoReal)}</div>
      ${(f.cancelamentos||[]).length?'<div class="obs-line">Cancelamentos: '+f.cancelamentos.map(x=>escH(x.motivo)+' ('+x.qtd+')').join('; ')+'</div>':''}
      ${(f.maisVendidos||[]).length?'<div class="obs-line">Mais vendidos no iFood: '+f.maisVendidos.map(x=>escH(x.nome)+' ('+x.qtd+')').join('; ')+'</div>':''}</div>`;
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function carregarIfoodPedidos_(){
  const box = document.getElementById('ifoodPedidos'); if(!box) return;
  try{
    const r = await apiCall('ifoodPedidos', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    const e = r.estado || {};
    const cab = `<div class="obs-line">Última consulta ao iFood: ${e.ultimaConsultaOk ? escH(fmtDiaHoraBr_(e.ultimaConsultaOk)) : 'nunca'}${e.ultimoPedido ? ' · último pedido: ' + escH(fmtDiaHoraBr_(e.ultimoPedido)) : ''}${e.ultimoErro ? ' · ⚠️ ' + escH(e.ultimoErro) : ''}</div>`;
    box.innerHTML = cab + ((r.pedidos||[]).map(p=>`<div class="notif-card" style="border-left:4px solid ${p.cancelado?'#c0392b':(p.semLigacao?'#e0a800':'#2e9e5b')};">
      <b>iFood #${escH(p.numero||'')}</b> ${p.simulado?'<i>(teste)</i>':''} → venda #${escH(String(p.venda||'—'))} · R$ ${Number(p.total||0).toFixed(2).replace('.',',')} · ${escH(IFOOD_ESTADO_ROT_[p.estado]||p.estado)}${p.cancelado?' · venda cancelada':''}
      ${p.semLigacao?`<div class="obs-line">⚠️ ${p.semLigacao} item(ns) sem ligação: custo e estoque pendentes.</div>`:''}
      ${p.acaoErro?`<div class="obs-line">❗ Ação não confirmada no iFood: ${escH(p.acaoErro)}</div>`:''}
      <div class="obs-line">${escH(fmtDiaHoraBr_(p.em))}</div></div>`).join('') || '<div class="obs-line">Nenhum pedido do iFood ainda.</div>');
  }catch(er){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
let ifoodItensDados_ = null;
async function carregarIfoodItens_(){
  const box = document.getElementById('ifoodItens'); if(!box) return;
  try{
    const r = await apiCall('ifoodItens', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    ifoodItensDados_ = r; renderIfoodItens_();
  }catch(er){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
function renderIfoodItens_(){
  const box = document.getElementById('ifoodItens'); const r = ifoodItensDados_; if(!box || !r) return;
  const op = (tipo, lista)=> (lista||[]).map(x=>`<option value="${tipo}:${escH(x.id)}">${escH(x.nome)}</option>`).join('');
  box.innerHTML = '<p class="sub mt-2">Cada item do iFood precisa estar ligado a um produto do sistema para baixar os ingredientes e calcular o custo. Itens aparecem aqui quando chegam em pedidos.</p>' +
    ((r.itens||[]).map((i,ix)=>{
      const pend = !i.ligado && !i.ignorar;
      return `<div class="notif-card" style="border-left:4px solid ${pend?'#e0a800':'#2e9e5b'};">
        <b>${escH(i.nome)}</b> <span class="obs-line" style="display:inline;">(${i.tipo==='opcao'?'opção/adicional':'item'} · código ${escH(i.chave)})</span>
        ${i.ligado?`<div class="obs-line">✅ Ligado a: ${escH(i.ligadoNome||'—')} (${escH(i.ligado)}) <button class="ghost" style="width:auto;padding:2px 8px;min-height:28px;" onclick="ligarIfoodItem_(${ix},'desligar')">Desfazer</button></div>`:''}
        ${i.ignorar?`<div class="obs-line">🚫 Ignorado (não baixa estoque) <button class="ghost" style="width:auto;padding:2px 8px;min-height:28px;" onclick="ligarIfoodItem_(${ix},'desligar')">Desfazer</button></div>`:''}
        ${pend?`<div class="obs-line">⚠️ Sem ligação.</div>
          ${i.sugestao?`<div class="obs-line">Sugestão: <b>${escH(i.sugestao.nome)}</b> <button class="small-gold" onclick="ligarIfoodItem_(${ix},'sugestao')">Usar sugestão</button></div>`:''}
          <select id="ifSel_${ix}"><option value="">Escolher no sistema…</option>${i.tipo==='opcao'?'<optgroup label="Adicionais">'+op('adicional',r.adicionais)+'</optgroup>':''}<optgroup label="Produtos">${op('produto',r.produtos)}</optgroup><optgroup label="Combos">${op('combo',r.combos)}</optgroup></select>
          <div class="btnrow mt-2"><button class="ghost" onclick="ligarIfoodItem_(${ix},'escolha')">Ligar</button><button class="ghost" onclick="ligarIfoodItem_(${ix},'ignorar')">Ignorar este item</button></div>`:''}
      </div>`; }).join('') || '<div class="obs-line">Nenhum item do iFood conhecido ainda.</div>');
}
async function ligarIfoodItem_(ix, modo){
  const r0 = ifoodItensDados_; const i = r0 && r0.itens[ix]; if(!i) return;
  let corpo = { chave: i.chave };
  if(modo==='sugestao' && i.sugestao){ corpo.tipo = i.sugestao.tipo; corpo.id = i.sugestao.id; }
  else if(modo==='escolha'){ const v = (document.getElementById('ifSel_'+ix)||{}).value || ''; if(!v) return showMsg(integMsgId_(),'Escolha um item do sistema.','warn'); const p = v.split(':'); corpo.tipo = p[0]; corpo.id = p[1]; }
  else if(modo==='ignorar'){ corpo.ignorar = true; }
  else if(modo==='desligar'){ corpo.tipo = 'desligar'; }
  try{
    const r = await apiCall('ifoodLigarItem', corpo);
    if(r && r.ok){ ifoodItensDados_ = r; renderIfoodItens_(); showMsg(integMsgId_(),'Salvo. Pedidos antigos sem ligação podem ser refeitos com "Refazer pedidos sem ligação".','ok'); }
    else showMsg(integMsgId_(),(r&&r.message)||'Não foi possível salvar.','warn');
  }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}
async function reprocessarIfood_(){
  if(!await confirmarTxt_('Refazer os pedidos do iFood que ficaram sem ligação, com as ligações atuais? (corrige custo e estoque)')) return;
  try{ const r = await apiCall('ifoodReprocessar', {}); if(r && r.ok){ showMsg(integMsgId_(), r.message||'Pronto.','ok'); carregarIfoodPedidos_(); } else showMsg(integMsgId_(),(r&&r.message)||'Não foi possível.','warn'); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}
async function simularIfood_(){
  if(!await confirmarTxt_('Criar um pedido de TESTE do iFood? Ele vira uma venda de verdade (marcada como teste) — cancele depois. Nada é enviado ao iFood.')) return;
  try{ const r = await apiCall('ifoodSimular', { pagoNoApp: true }); if(r && r.ok){ showMsg(integMsgId_(), r.message||'Criado.','ok'); carregarIfoodPedidos_(); } else showMsg(integMsgId_(),(r&&r.message)||'Não foi possível.','warn'); }catch(e){ showMsg(integMsgId_(),'Sem conexão.','warn'); }
}

