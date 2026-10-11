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
  if(!confirm('Excluir esta mesa?')) return;
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
  tbody.innerHTML = usuarios.map(u=>{
    const protegido = (u.nivel === 'Desenvolvedor' && !souDev);
    const acoes = protegido
      ? '<span class="obs-line" title="Este acesso é protegido: só o próprio Desenvolvedor altera.">🔒 protegido</span>'
      : `<button class="ghost" data-usr-acao="editar" data-usr-login="${escH(u.login)}">editar</button><button class="ghost" data-usr-acao="toggle" data-usr-login="${escH(u.login)}" data-usr-ativo="${u.ativo?1:0}">${u.ativo?'desativar':'ativar'}</button>${u.nivel==='Desenvolvedor' ? '' : `<button class="ghost" data-usr-acao="excluir" data-usr-login="${escH(u.login)}">excluir</button>`}`;
    return `<tr><td>${escH(u.login)}${u.nome?`<div class="obs-line">${escH(u.nome)}</div>`:''}${u.nivel==='Entregador'?`<div class="obs-line">${u.telefone?'📞 '+escH(u.telefone):'⚠ sem telefone'}</div>`:''}</td><td>${u.nivel}</td><td><span class="badge ${u.ativo?'done':'baixo'}">${u.ativo?'Ativo':'Inativo'}</span></td>
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
      ${x.atual?'':`<div class="btnrow" style="margin-top:8px;"><button class="ghost" data-sess-encerrar="${escH(x.sessaoId)}">Encerrar</button></div>`}
    </div>`).join('');
}
async function encerrarSessaoRemotaUI_(sessaoId){
  if(!confirm('Encerrar esta sessão? O aparelho será desconectado.')) return;
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
  box.innerHTML = '<div class="notif-empty">Carregando…</div>';
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
      ${c.link?`<div class="obs-line" style="overflow-wrap:anywhere;">🔗 <a href="${escH(c.link)}" target="_blank" rel="noopener noreferrer" style="color:var(--gold);">Abrir</a> · ${escH(c.link)}</div>`:''}
      ${c.temSenha?`<div class="obs-line">🔑 <span id="ctSenhaVer_${c.id}">••••••••</span> <button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;margin-left:6px;" onclick="verSenhaConta_('${c.id}')">Ver senha</button></div>`:''}
      ${c.observacao?`<div class="obs-line">${escH(c.observacao)}</div>`:''}
      <div class="btnrow" style="margin-top:8px;"><button class="ghost" onclick="abrirContaModal_('${c.id}')">Editar</button><button class="ghost" onclick="excluirContaUI_('${c.id}')">Excluir</button></div>
    </div>`).join('');
}
function contaCopiar_(btn, txt){
  const t = document.createElement('textarea'); t.innerHTML = txt; const v = t.value;
  (navigator.clipboard ? navigator.clipboard.writeText(v) : Promise.reject()).then(()=>{ btn.textContent = 'Copiado'; setTimeout(()=>btn.textContent='Copiar', 1500); }).catch(()=>{ prompt('Copie:', v); });
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
  if(!confirm('Excluir a conta "' + c.servico + '"' + (c.temSenha ? ' e a senha guardada dela' : '') + '?')) return;
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
  gemini: { nome:'Gemini (Google)', link:'https://aistudio.google.com/apikey' },
  groq:   { nome:'Groq', link:'https://console.groq.com/keys' },
  nvidia: { nome:'NVIDIA (reserva)', link:'https://build.nvidia.com/settings/api-keys', extra:true, dica:'IA de reserva: só entra quando o Gemini e a Groq falham. Precisa de conta gratuita no NVIDIA Developer Program.' },
  cloudflare: { nome:'Cloudflare (reserva)', link:'https://dash.cloudflare.com/profile/api-tokens', extra:true, conta:true, dica:'IA de reserva: precisa de DOIS dados — o Account ID e um token com permissão "Workers AI".' }
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
        : (info.extra ? `<div class="obs-line">Sem chave: tudo segue como hoje (Gemini e Groq).</div>` : `<div class="obs-line">⚠️ Sem chave cadastrada: esta IA não funciona.</div>`)}
      ${info.dica?`<div class="obs-line">${escH(info.dica)}</div>`:''}
      ${c.descansando?`<div class="obs-line">😴 Descansando: deu erros agora há pouco; o sistema usa as outras IAs e tenta de novo sozinho.</div>`:''}
      ${info.link?`<div class="obs-line">🔗 <a href="${info.link}" target="_blank" rel="noopener noreferrer" style="color:var(--gold);">Onde pegar uma chave nova</a></div>`:''}
      <div class="btnrow" style="margin-top:8px;"><button class="ghost" onclick="abrirChaveIaModal_('${c.provedor}')">Trocar chave</button>${c.temChave?`<button class="ghost" onclick="testarChaveIa_('${c.provedor}','testeIa_${c.provedor}',this)">🧪 Testar</button>`:''}</div>
      <div class="obs-line" id="testeIa_${c.provedor}"></div>
    </div>`; }).join('') || '<div class="notif-empty">Nenhuma IA configurada.</div>';
  const eb = document.getElementById('iaExtrasBox');
  if(eb) eb.innerHTML = `<div class="notif-card"><label style="display:flex;gap:8px;align-items:flex-start;cursor:pointer;"><input type="checkbox" id="iaExtrasPub" ${iaExtrasPublico_?'checked':''} onchange="salvarIaExtras_(this.checked)" style="width:auto;margin-top:4px;"> <span><b>Usar as IAs de reserva também no atendimento ao cliente (cardápio)</b><div class="obs-line">Deixe desligado até confirmar os termos de privacidade de cada provedor: as conversas dos clientes passariam por ele. Desligado, NVIDIA e Cloudflare atendem só o uso interno (equipe).</div></span></label></div>`;
}
/* Teste de cada IA (só Admin/Desenvolvedor): faz uma pergunta mínima ao provedor e mostra se respondeu. Não gasta a cota das consultas. */
const TESTE_IA_MOTIVO_ = { sem_chave:'Sem chave cadastrada.', sem_conta:'Falta o Account ID da Cloudflare.', http_400:'O provedor recusou o pedido (confira o modelo configurado).', http_401:'Chave recusada (errada, expirada ou sem permissão). Troque a chave.', http_403:'Chave sem permissão para usar a IA. Confira as permissões da chave.', http_404:'Endereço ou modelo não encontrado nesse provedor.', http_429:'Limite do plano gratuito atingido agora. Tente mais tarde.', rede_ou_timeout:'Sem resposta do provedor no tempo esperado.', vazio:'O provedor respondeu, mas vazio.', erro:'Erro inesperado.' };
function testeIaMotivo_(cod){ cod = String(cod||'erro'); return TESTE_IA_MOTIVO_[cod] || (/^http_5/.test(cod) ? 'O provedor está com problema do lado dele (' + cod.replace('http_','erro ') + '). Tente mais tarde.' : 'Falhou (' + cod + ').'); }
async function testarChaveIa_(prov, alvoId, btn){
  const el = document.getElementById(alvoId); if(!el) return false;
  if(btn){ btn.disabled = true; }
  el.className = 'obs-line'; el.textContent = '⏳ Testando… pode levar alguns segundos';
  let ok = false;
  try{
    if(!window.IA || !IA.chamar) throw new Error('sem_ia');
    const r = await IA.chamar('testar_ia', { provedor: prov }, { forcar:true, ttl:1 });
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
window.INTEG_ = window.INTEG_ || { ifood:false, nfce:false, nfceModo:'homologacao', impostoPct:0 };
async function carregarIntegFlags_(){
  try{ const r = await apiCall('integracoesFlags', {}); if(r && r.ok){ window.INTEG_ = { ifood:!!r.ifood, nfce:!!r.nfce, nfceModo:r.nfceModo||'homologacao', impostoPct:Number(r.impostoPct)||0 }; try{ atualizarCpfBox_(); }catch(e){} } }catch(e){}
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
    opcoes:[] }
};
let integStatus_ = [];
async function carregarIntegracoes_(){
  const box = document.getElementById('integLista'); if(!box) return;
  try{
    const r = await apiCall('integracoesStatus', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="notif-empty">' + escH((r && r.message) || 'Não foi possível carregar agora.') + '</div>'; return; }
    integStatus_ = r.integracoes || []; renderIntegracoes_();
  }catch(e){ box.innerHTML = '<div class="notif-empty">Sem conexão para carregar.</div>'; }
}
function renderIntegracoes_(){
  const box = document.getElementById('integLista'); if(!box) return;
  const bt = 'class="ghost" style="width:auto;padding:4px 10px;min-height:32px;margin-left:6px;"';
  box.innerHTML = integStatus_.map(it=>{ const inf = INTEG_INFO_[it.provedor]; if(!inf) return '';
    const seg = it.segredos || {};
    return `<div class="notif-card" style="border-left:4px solid ${it.ligado?'#2e9e5b':'#888'};">
      <div><b>${inf.icone} ${escH(inf.nome)}</b> — ${it.ligado?'<span style="color:#2e9e5b;">LIGADO'+(it.provedor==='nfce'?' ('+(it.modo==='producao'?'produção':'teste')+')':'')+'</span>':'<span style="color:#aaa;">desligado</span>'}</div>
      <details style="margin-top:6px;"><summary style="cursor:pointer;color:var(--gold);">📖 Guia passo a passo</summary>${inf.guia.map(g=>`<div class="obs-line">${escH(g)}</div>`).join('')}</details>
      <div style="margin-top:8px;"><b>Chaves</b>${inf.segredos.map(([k,r])=>`<div class="obs-line">${seg[k]?'✅':'⬜'} ${escH(r)} ${seg[k]?'<span id="isVer_'+k+'">••••'+escH(seg[k].final||'')+'</span> <button '+bt+' onclick="verIntegSegredo_(\''+k+'\')">Ver</button>':''} <button ${bt} onclick="abrirIntegSegredo_('${k}','${escH(r)}')">${seg[k]?'Trocar':'Digitar'}</button></div>`).join('')}</div>
      <div style="margin-top:8px;"><b>Checklist</b>${(it.checklist||[]).map(c=>`<label class="obs-line" style="display:flex;gap:8px;align-items:flex-start;${c.auto?'':'cursor:pointer;'}"><input type="checkbox" ${c.feito?'checked':''} ${c.auto?'disabled':''} onchange="marcarIntegPasso_('${it.provedor}','${c.id}',this.checked)" style="width:auto;margin-top:3px;"> <span>${escH(c.titulo)}${c.auto?' <i>(o sistema marca sozinho)</i>':''}</span></label>`).join('')}</div>
      ${inf.opcoes.length?`<div style="margin-top:8px;"><b>Ajustes</b>${inf.opcoes.map(([k,t])=>`<label class="obs-line" style="display:flex;gap:8px;align-items:flex-start;cursor:pointer;"><input type="checkbox" ${(it.config||{})[k]?'checked':''} onchange="salvarIntegOpcao_('${it.provedor}','${k}',this.checked)" style="width:auto;margin-top:3px;"> <span>${escH(t)}</span></label>`).join('')}</div>`:''}
      <div class="btnrow" style="margin-top:10px;">
        ${it.ligado
          ? `<button class="ghost" onclick="desligarInteg_('${it.provedor}')">Desligar</button>`
          : (it.provedor==='nfce'
              ? `<button class="primary" ${it.podeLigar?'':'disabled'} onclick="ligarInteg_('nfce','homologacao')">Ligar em TESTE</button><button class="ghost" ${it.podeLigar?'':'disabled'} onclick="ligarInteg_('nfce','producao')">Ligar em PRODUÇÃO</button>`
              : `<button class="primary" ${it.podeLigar?'':'disabled'} onclick="ligarInteg_('${it.provedor}','producao')">Ligar</button>`)}
        <button class="ghost" onclick="verLogInteg_('${it.provedor}')">Ver registro</button>
      </div>
      ${(!it.ligado && !it.podeLigar)?`<div class="obs-line">Ainda falta: ${escH((it.pendencias||[]).join('; '))}</div>`:''}
      ${it.provedor==='ifood'?ifoodExtraHtml_(it):''}
      ${it.provedor==='nfce'?fiscalExtraHtml_(it):''}
      <div id="integLog_${it.provedor}"></div>
    </div>`; }).join('') || '<div class="notif-empty">Nada disponível.</div>';
}
async function marcarIntegPasso_(prov, item, feito){
  try{ const r = await apiCall('integracoesMarcar', { provedor:prov, item, feito:!!feito }); if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; } else showMsg('integMsg', (r&&r.message)||'Não foi possível salvar.', 'warn'); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
  renderIntegracoes_();
}
async function salvarIntegOpcao_(prov, chave, valor){
  try{ const r = await apiCall('integracoesConfig', { provedor:prov, config:{ [chave]: !!valor } }); if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; } else showMsg('integMsg', (r&&r.message)||'Não foi possível salvar.', 'warn'); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
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
      if(r && r.ok){ document.getElementById('isValor').value=''; integStatus_ = r.integracoes||integStatus_; renderIntegracoes_(); fecharFormModal('integSegredoModal'); showMsg('integMsg', r.message||'Salvo.', 'ok'); }
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
      if(!r || !r.ok){ showMsg('integMsg', (r&&r.message)||'Não foi possível mostrar.', 'warn'); return; }
      const antes = el.textContent; el.textContent = r.valor; el.style.fontFamily='monospace'; el.style.overflowWrap='anywhere';
      clearTimeout(el._t); el._t = setTimeout(()=>{ el.textContent = antes; el.style.fontFamily=''; }, 30000);
    }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
  });
}
function ligarInteg_(prov, modo){
  const nome = INTEG_INFO_[prov].nome;
  if(!confirm('Ligar ' + nome + (prov==='nfce' ? (modo==='producao'?' em PRODUÇÃO (notas valem de verdade)':' em TESTE') : '') + '?\n\nA partir daqui o sistema passa a usar essa integração. Dá para desligar a qualquer momento.')) return;
  abrirModalSenhaAdmin(async function(senhaAdm){
    try{
      const r = await apiCall('integracoesLigar', { provedor:prov, modo, senhaAdmin: senhaAdm });
      if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; renderIntegracoes_(); carregarIntegFlags_(); showMsg('integMsg', r.message||'Ligado.', 'ok'); }
      else showMsg('integMsg', (r&&r.message)||'Não foi possível ligar.', 'warn');
    }catch(e){ showMsg('integMsg','Sem conexão. Tente de novo.','warn'); }
  });
}
function desligarInteg_(prov){
  if(!confirm('Desligar ' + INTEG_INFO_[prov].nome + '? O sistema volta a funcionar como antes; o que já foi gravado fica guardado.')) return;
  abrirModalSenhaAdmin(async function(senhaAdm){
    try{
      const r = await apiCall('integracoesDesligar', { provedor:prov, senhaAdmin: senhaAdm });
      if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; renderIntegracoes_(); carregarIntegFlags_(); showMsg('integMsg', r.message||'Desligado.', 'ok'); }
      else showMsg('integMsg', (r&&r.message)||'Não foi possível desligar.', 'warn');
    }catch(e){ showMsg('integMsg','Sem conexão. Tente de novo.','warn'); }
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

/* ---- Nota fiscal (Fase 4): dados da empresa, perfis fiscais, itens sem perfil, planilha do contador. Só aparece no cartão "Nota fiscal". ---- */
function fiscalExtraHtml_(it){
  return `<div style="margin-top:10px;border-top:1px solid var(--gold);padding-top:8px;">
    <div class="btnrow">
      <button class="ghost" onclick="carregarFiscalEmpresa_()">Dados fiscais da empresa</button>
      <button class="ghost" onclick="carregarFiscalPerfis_()">Perfis fiscais</button>
      <button class="ghost" onclick="carregarFiscalSem_()">Itens sem perfil</button>
      <button class="ghost" onclick="carregarNfceLista_('')">Notas fiscais</button>
      <button class="ghost" onclick="carregarNfceConf_()">Conferência</button>
      <button class="ghost" onclick="carregarNfcePacote_()">Pacote do contador</button>
      <button class="ghost" onclick="baixarPlanilhaFiscal_()">Baixar planilha do contador</button>
      <button class="ghost" onclick="document.getElementById('fiscalArq').click()">Enviar planilha preenchida</button>
      <input type="file" id="fiscalArq" accept=".csv,text/csv,text/plain" style="display:none;" onchange="enviarPlanilhaFiscal_(this)">
    </div>
    ${nfceOpcoesHtml_(it)}<div id="nfceLista"></div><div id="nfceConf"></div><div id="nfcePac"></div><div id="fiscalEmpresa"></div><div id="fiscalPerfis"></div><div id="fiscalSem"></div></div>`;
}
const FISCAL_CAMPOS_ = [['razaoSocial','razao_social','Razão social'],['nomeFantasia','nome_fantasia','Nome fantasia'],['cnpj','cnpj','CNPJ (só números)'],['inscricaoEstadual','inscricao_estadual','Inscrição estadual'],
  ['cep','cep','CEP'],['logradouro','logradouro','Rua / avenida'],['numero','numero','Número'],['complemento','complemento','Complemento'],['bairro','bairro','Bairro'],['municipio','municipio','Cidade'],
  ['codigoMunicipio','codigo_municipio','Código do município (7 números — o contador informa)'],['uf','uf','Estado (ex.: SP)'],['telefone','telefone','Telefone'],['cscId','csc_id','Número do CSC (identificador, não o código secreto)'],
  ['serie','serie','Série das notas (normalmente 1)'],['aliquotaSimples','aliquota_simples','Alíquota efetiva do Simples em % (o contador informa; só para estimar o imposto no resultado)']];
async function carregarFiscalEmpresa_(){
  const box = document.getElementById('fiscalEmpresa'); if(!box) return;
  try{
    const r = await apiCall('fiscalEmpresaLer', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    const e = r.empresa || {};
    box.innerHTML = `<div class="notif-card"><b>Dados fiscais da empresa</b> ${r.completa?'✅ completos':'⬜ incompletos'}${r.temCsc?'':' · falta digitar o CSC secreto (cartão Chaves, acima)'}
      <label for="fiscRegime">Regime</label><select id="fiscRegime"><option value="simples" ${e.regime==='simples'?'selected':''}>Simples Nacional</option><option value="mei" ${e.regime==='mei'?'selected':''}>MEI</option><option value="normal" ${e.regime==='normal'?'selected':''}>Lucro presumido/real</option></select>
      ${FISCAL_CAMPOS_.map(([k,c,t])=>`<label for="fisc_${k}">${escH(t)}</label><input id="fisc_${k}" maxlength="120" value="${escH(e[c]==null?'':e[c])}">`).join('')}
      <div class="btnrow" style="margin-top:8px;"><button class="primary" onclick="salvarFiscalEmpresa_()">Salvar dados fiscais</button></div><div class="msg" id="fiscEmpMsg"></div></div>`;
  }catch(err){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function salvarFiscalEmpresa_(){
  const p = { regime: document.getElementById('fiscRegime').value };
  FISCAL_CAMPOS_.forEach(([k])=>{ p[k] = document.getElementById('fisc_'+k).value.trim(); });
  try{ const r = await apiCall('fiscalEmpresaSalvar', p); showMsg('fiscEmpMsg', (r && r.message) || 'Não foi possível salvar.', r && r.ok ? 'ok' : 'warn'); if(r && r.ok){ carregarIntegracoes_(); } }
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
    <div style="margin-top:8px;"><b>Perfis por categoria</b>${(r.categorias||[]).map(c=>`<div class="obs-line">${escH(c.nome)}: <select onchange="atribuirFiscal_('categoria','${c.id}',this.value)">${opts(c.perfilId)}</select></div>`).join('')}</div>
    <div style="margin-top:8px;"><b>${e.id?'Editar perfil':'Novo perfil'}</b>
      <input type="hidden" id="fscId" value="${g('id')}">
      <label for="fscNome">Nome (ex.: Lanches)</label><input id="fscNome" maxlength="60" value="${g('nome')}">
      <label for="fscNcm">NCM (8 números)</label><input id="fscNcm" maxlength="12" value="${g('ncm')}">
      <label for="fscCest">CEST (7 números, se o contador pedir)</label><input id="fscCest" maxlength="9" value="${g('cest')}">
      <label for="fscCfop">CFOP</label><input id="fscCfop" maxlength="4" value="${g('cfop','5102')}">
      <label for="fscCsosn">CSOSN (Simples/MEI, ex.: 102)</label><input id="fscCsosn" maxlength="4" value="${g('csosn')}">
      <label for="fscCst">CST do ICMS (só regime normal)</label><input id="fscCst" maxlength="2" value="${g('cstIcms')}">
      <label for="fscOrigem">Origem da mercadoria (0 = nacional)</label><input id="fscOrigem" maxlength="1" value="${g('origem','0')}">
      <label for="fscUn">Unidade</label><input id="fscUn" maxlength="6" value="${g('unidade','UN')}">
      <label class="obs-line" style="display:flex;gap:8px;"><input type="checkbox" id="fscAtivo" ${e.id && e.ativo===false?'':'checked'} style="width:auto;"> Perfil ativo</label>
      <div class="btnrow" style="margin-top:8px;"><button class="primary" onclick="salvarFiscalPerfil_()">Salvar perfil</button>${e.id?'<button class="ghost" onclick="renderFiscalPerfis_()">Cancelar</button>':''}</div><div class="msg" id="fscMsg"></div></div></div>`;
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
  if(!confirm('Excluir este perfil fiscal?')) return;
  try{ const r = await apiCall('fiscalPerfilExcluir', { id }); if(r && r.ok){ fiscalPerfisCache_ = r; renderFiscalPerfis_(); carregarIntegracoes_(); } else alert((r&&r.message)||'Não foi possível excluir.'); }catch(e){ alert('Sem conexão.'); }
}
async function atribuirFiscal_(alvo, id, perfilId){
  try{ const r = await apiCall('fiscalAtribuir', { alvo, id, perfilId: perfilId||null });
    if(r && r.ok){ fiscalPerfisCache_ = r; renderFiscalPerfis_(); carregarIntegracoes_(); if(document.getElementById('fiscalSem') && document.getElementById('fiscalSem').innerHTML) carregarFiscalSem_(); } else alert((r&&r.message)||'Não foi possível salvar.');
  }catch(e){ alert('Sem conexão.'); }
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
      ${it.map((x,i)=>`<div class="obs-line">${x.tipo==='combo'?'🍱':'🍔'} ${escH(x.nome)} <span style="color:var(--muted);">${escH(x.categoria||'')}</span> <select onchange="atribuirFiscal_('${x.tipo}','${x.id}',this.value)">${opt}</select></div>`).join('')}</div>`;
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function aplicarFiscalTodos_(){
  const pid = document.getElementById('fsTodos').value; if(!pid) return alert('Escolha o perfil.');
  if(!confirm('Aplicar este perfil a todos os itens da lista?')) return;
  try{ const r = await apiCall('fiscalAtribuir', { alvo:'lote', perfilId:pid, ids:(window._fiscalSem||[]).map(x=>({ tipo:x.tipo, id:x.id })) });
    if(r && r.ok){ fiscalPerfisCache_ = r; carregarFiscalSem_(); carregarIntegracoes_(); } else alert((r&&r.message)||'Não foi possível salvar.'); }catch(e){ alert('Sem conexão.'); }
}
const FISCAL_PLAN_COLS_ = ['tipo','id','nome','categoria','perfil','ncm','cest','cfop','csosn','cstIcms','origem','unidade'];
async function baixarPlanilhaFiscal_(){
  try{ const r = await apiCall('fiscalExportar', {});
    if(!r || !r.ok) return alert((r&&r.message)||'Não foi possível gerar.');
    baixarCsv_('planilha-fiscal.csv', FISCAL_PLAN_COLS_, (r.linhas||[]).map(l=>FISCAL_PLAN_COLS_.map(c=>l[c]==null?'':l[c])));
  }catch(e){ alert('Sem conexão.'); }
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
    const linhas = csvLinhas_(await f.text()); if(linhas.length < 2) return alert('Planilha vazia.');
    const cab = linhas[0].map(x=>x.trim().toLowerCase().replace(/[^a-z]/g,'')), ix = n => cab.indexOf(n.toLowerCase());
    const col = { tipo:ix('tipo'), id:ix('id'), nome:ix('nome'), perfil:ix('perfil'), ncm:ix('ncm'), cest:ix('cest'), cfop:ix('cfop'), csosn:ix('csosn'), cstIcms:ix('csticms'), origem:ix('origem'), unidade:ix('unidade') };
    if(col.perfil < 0 || col.ncm < 0) return alert('Não achei as colunas "perfil" e "ncm". Use a planilha baixada aqui.');
    const dados = linhas.slice(1).map(l=>{ const o = {}; Object.keys(col).forEach(k=>{ o[k] = col[k] >= 0 ? (l[col[k]]||'').trim() : ''; }); return o; });
    if(!confirm('Aplicar ' + dados.length + ' linha(s) da planilha? Isso cria/atualiza perfis e liga os itens a eles.')) return;
    const r = await apiCall('fiscalImportar', { linhas: dados });
    if(r && r.ok){ fiscalPerfisCache_ = r; alert(r.message || 'Aplicado.'); carregarIntegracoes_(); if(document.getElementById('fiscalPerfis')) renderFiscalPerfis_(); } else alert((r&&r.message)||'Não foi possível aplicar.');
  }catch(e){ alert('Não consegui ler o arquivo.'); }
}

/* ---- Nota fiscal (Fase 5): onde/quando emitir, lista de notas, reemitir, DANFE, treino. Só aparece no cartão "Nota fiscal". ---- */
function nfceOpcoesHtml_(it){
  const c = it.config || {}, canais = Array.isArray(c.canais) ? c.canais : ['balcao'], quando = c.emitirQuando || 'pagamento';
  return `<div style="margin-top:8px;"><b>Onde e quando emitir a nota</b>
    ${[['balcao','Balcão (Caixa)'],['cardapio','Cardápio online'],['ifood','iFood'],['mesa','Mesa / Garçom']].map(([k,t])=>`<label class="obs-line" style="display:flex;gap:8px;align-items:flex-start;cursor:pointer;"><input type="checkbox" ${canais.indexOf(k)!==-1?'checked':''} onchange="salvarNfceCanal_('${k}',this.checked)" style="width:auto;margin-top:3px;"> ${t}</label>`).join('')}
    <label class="obs-line" for="nfceQuando">Emitir a nota</label>
    <select id="nfceQuando" onchange="salvarNfceConfig_({ emitirQuando:this.value })"><option value="pagamento" ${quando==='pagamento'?'selected':''}>quando a venda for paga (recomendado no balcão)</option><option value="entrega" ${quando==='entrega'?'selected':''}>quando o pedido for entregue (recomendado no delivery)</option></select>
    <div class="obs-line">Dica: comece só com o Balcão e confira com o contador antes de incluir os outros.</div></div>`;
}
async function salvarNfceConfig_(config){
  try{ const r = await apiCall('integracoesConfig', { provedor:'nfce', config }); if(r && r.ok){ integStatus_ = r.integracoes||integStatus_; } else showMsg('integMsg', (r&&r.message)||'Não foi possível salvar.', 'warn'); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
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
      <div class="btnrow" style="margin-top:6px;">${chip('','Todas')}${chip('autorizada','Autorizadas')}${chip('rejeitada','Rejeitadas')}${chip('pendencia','Pendências')}${chip('contingencia','Contingência')}${chip('pendente','Aguardando')}${dev?'<button class="ghost" onclick="simularNfce_()">🧪 Nota de treino</button>':''}</div>
      ${(r.itens||[]).map(n=>`<div class="obs-line" style="border-top:1px solid var(--line,#333);padding-top:6px;margin-top:6px;">
        <b>#${escH(n.pedido==null?'?':n.pedido)}</b> ${escH(n.cliente||'')} — ${formatarMoeda(Number(n.valor)||0)} — ${NFCE_ESTADO_ROT_[n.estado]||escH(n.estado)}${n.ambiente!=='producao'?' <span style="color:#d9a441;">['+(n.ambiente==='simulado'?'treino':'teste')+']</span>':''}${n.numero?' · nº '+escH(n.numero)+'/'+escH(n.serie||1):''}${n.cpf?' · com CPF':''}
        ${n.erro?`<div style="color:#ffb3ab;">${escH(n.erro)}</div>`:''}
        <div class="btnrow" style="margin-top:4px;">
          ${['rejeitada','pendencia','erro','duvida','dispensada'].indexOf(n.estado)!==-1?`<button class="ghost" style="width:auto;padding:4px 10px;min-height:32px;" onclick="reemitirNfce_(${n.id})">Reemitir</button>`:''}
          ${n.estado==='autorizada'&&n.danfe?`<a class="ghost" style="padding:4px 10px;" href="${escH(n.danfe)}" target="_blank" rel="noopener">Abrir DANFE (cupom)</a>`:''}
          ${n.estado==='autorizada'&&n.xml?`<a class="ghost" style="padding:4px 10px;" href="${escH(n.xml)}" target="_blank" rel="noopener">XML</a>`:''}
          ${n.estado==='autorizada'&&(n.consulta||n.danfe)?`<a class="ghost" style="padding:4px 10px;" href="https://wa.me/?text=${encodeURIComponent('Sua nota fiscal: '+(n.consulta||n.danfe))}" target="_blank" rel="noopener">Enviar ao cliente</a>`:''}
        </div></div>`).join('') || '<div class="obs-line">Nenhuma nota nesta lista ainda.</div>'}</div>`;
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function reemitirNfce_(id){
  if(!confirm('Tentar emitir esta nota de novo?')) return;
  try{ const r = await apiCall('nfceReemitir', { id }); showMsg('integMsg', (r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); setTimeout(()=>carregarNfceLista_(), 5000); carregarNfceLista_(); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
}
async function simularNfce_(){
  try{ const r = await apiCall('nfceSimular', {}); showMsg('integMsg', (r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); setTimeout(()=>carregarNfceLista_(), 8000); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
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
  if(!confirm('Criar a nota desta venda agora?')) return;
  try{ const r = await apiCall('nfceEmitirVenda', { vendaId }); showMsg('nfceConfMsg', (r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); setTimeout(carregarNfceConf_, 6000); }catch(e){ showMsg('nfceConfMsg','Sem conexão.','warn'); }
}
function inutilizarNfce_(serie, ini, fim){
  const just = prompt('Motivo da inutilização (mínimo 15 letras):', 'Numeração pulada por falha de emissão');
  if(!just || just.trim().length < 15) return alert('Escreva um motivo com pelo menos 15 letras.');
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
    <div class="btnrow" style="margin-top:6px;"><button class="primary" onclick="baixarPacoteNfce_()">Baixar planilha do mês</button></div>
    <div id="nfcePacLinks"></div><div class="obs-line">A Focus também baixa todos os XML do mês no painel dela.</div></div>`;
}
async function baixarPacoteNfce_(){
  const v = (document.getElementById('nfcePacMes')||{}).value || ''; const [ano, mes] = v.split('-').map(Number);
  try{
    const r = await apiCall('nfcePacote', { ano, mes });
    if(!r || !r.ok) return alert((r&&r.message)||'Não foi possível gerar.');
    const cab = ['Pedido','Emitida em','Número','Série','Chave','Valor','Situação','Cancelada em','CPF informado','XML'];
    baixarCsv_('notas-fiscais-' + ano + '-' + String(mes).padStart(2,'0') + '.csv', cab, (r.notas||[]).map(n=>[n.pedido==null?'':n.pedido, n.emitidaEm||'', n.numero||'', n.serie||'', n.chave||'', csvNum_(n.valor), n.estado, n.canceladaEm||'', n.comCpf?'sim':'não', n.xml||'']));
    const el = document.getElementById('nfcePacLinks');
    if(el) el.innerHTML = (r.notas||[]).length ? '<div class="obs-line">'+r.notas.length+' nota(s) no mês ('+escH(r.ambiente==='producao'?'produção':'teste')+')'+((r.inutilizacoes||[]).length?' · '+r.inutilizacoes.length+' inutilização(ões)':'')+'</div>' + r.notas.filter(n=>n.xml).map(n=>`<div class="obs-line"><a href="${escH(n.xml)}" target="_blank" rel="noopener">XML nº ${escH(n.numero||'')}</a></div>`).join('') : '<div class="obs-line">Nenhuma nota neste mês.</div>';
  }catch(e){ alert('Sem conexão.'); }
}

/* ---- iFood: pedidos, itens ligados, simulação (aparecem dentro do cartão Integrações) ---- */
function ifoodExtraHtml_(it){
  const dev = currentUser && currentUser.nivelReal === 'Desenvolvedor';
  return `<div style="margin-top:10px;border-top:1px solid var(--gold);padding-top:8px;">
    <div class="btnrow">
      <button class="ghost" onclick="carregarIfoodLoja_()">Loja no iFood</button>
      <button class="ghost" onclick="carregarIfoodNeg_()">Negociações</button>
      <button class="ghost" onclick="carregarIfoodPedidos_()">Pedidos do iFood</button>
      <button class="ghost" onclick="carregarIfoodItens_()">Itens do iFood</button>
      <button class="ghost" onclick="carregarIfoodPrecos_()">Preços</button>
      <button class="ghost" onclick="carregarIfoodFin_()">Financeiro</button>
      <button class="ghost" onclick="carregarIfoodAval_()">Avaliações</button>
      <button class="ghost" onclick="carregarIfoodRel_()">Relatório por canal</button>
      <button class="ghost" onclick="reprocessarIfood_()">Refazer pedidos sem ligação</button>
      ${dev?'<button class="ghost" onclick="simularIfood_()">🧪 Simular pedido do iFood (treino)</button>':''}
    </div>
    <div id="ifoodLoja"></div><div id="ifoodNeg"></div><div id="ifoodPedidos"></div><div id="ifoodItens"></div><div id="ifoodPrecos"></div><div id="ifoodFin"></div><div id="ifoodAval"></div><div id="ifoodRel"></div></div>`;
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
      <div class="btnrow" style="margin-top:6px;"><button class="ghost" onclick="lojaIfoodAcao_('pausar',30)">Pausar 30 min</button><button class="ghost" onclick="lojaIfoodAcao_('pausar',60)">Pausar 1 h</button><button class="ghost" onclick="lojaIfoodAcao_('retomar')">Retomar</button><button class="ghost" onclick="lojaIfoodAcao_('fechar')">Fechar</button><button class="ghost" onclick="lojaIfoodAcao_('abrir')">Abrir</button></div></div>`;
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
async function lojaIfoodAcao_(acao, minutos){
  try{ const r = await apiCall('ifoodLojaAcao', { acao, minutos }); showMsg('integMsg', (r && r.message) || 'Não foi possível.', r && r.ok ? 'ok' : 'warn'); setTimeout(carregarIfoodLoja_, 4000); carregarIfoodLoja_(); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
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
  if(acao==='recusar' && !confirm('Recusar o pedido do cliente? O iFood pode decidir por ele depois.')) return;
  try{ const r = await apiCall('ifoodNegociacaoResponder', { id, acao, alternativaId }); showMsg('integMsg', (r && r.message) || 'Não foi possível.', r && r.ok ? 'ok' : 'warn'); carregarIfoodNeg_(); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
}

const R$_ = v => 'R$ ' + Number(v||0).toFixed(2).replace('.',',');
let ifoodPrecosDados_ = null;
async function carregarIfoodPrecos_(){
  const box = document.getElementById('ifoodPrecos'); if(!box) return;
  try{
    const r = await apiCall('ifoodPrecos', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    ifoodPrecosDados_ = r;
    box.innerHTML = `<div class="notif-card"><b>Preços: sistema × iFood</b>
      <div class="btnrow" style="margin-top:6px;"><button class="ghost" onclick="pedirCatalogoIfood_()">Importar cardápio do iFood</button><button class="ghost" onclick="aplicarPrecosIfood_()">Gravar preços do iFood no sistema</button>${r.enviarLigado?'<button class="ghost" onclick="enviarPrecosIfood_()">Enviar nossos preços ao iFood</button>':''}</div>
      <div class="obs-line">${r.enviarLigado?'Envio ligado. Variação máxima por envio: '+r.limitePct+'%.':'Para enviar preços ao iFood, ligue antes o ajuste "Enviar nossos preços ao iFood".'}</div></div>` +
      ((r.itens||[]).map((i,ix)=>`<div class="notif-card" style="border-left:4px solid ${i.pct>20?'#e0a800':'#2e9e5b'};"><label style="display:flex;gap:8px;align-items:flex-start;"><input type="checkbox" class="ifPrecoSel" value="${escH(i.chave)}" style="width:auto;margin-top:4px;"> <span><b>${escH(i.nome||i.nomeIfood)}</b><div class="obs-line">Sistema ${i.precoSistema!=null?R$_(i.precoSistema):'—'} · iFood ${i.precoIfood!=null?R$_(i.precoIfood):'não importado'}${i.pct!=null?' · diferença '+(i.diff>0?'+':'')+R$_(i.diff)+' ('+i.pct+'%)':''}${i.pct>20?' ⚠️ fora do padrão':''}</div></span></label></div>`).join('') || '<div class="obs-line">Ligue itens do iFood a produtos e importe o cardápio para comparar.</div>') +
      ((r.historico||[]).length?'<div class="notif-card"><b>Histórico</b>'+r.historico.map(h=>`<div class="obs-line">${escH(fmtDiaHoraBr_(h.quando))} · ${escH(h.nome||'')} · ${h.antes!=null?R$_(h.antes):'—'} → ${R$_(h.depois)} · ${escH(h.origem)} (${escH(h.estado)})${h.erro?' ❗'+escH(h.erro):''} ${h.origem==='enviar'&&h.estado==='ok'?'<button class="ghost" style="width:auto;padding:2px 8px;min-height:28px;" onclick="desfazerPrecoIfood_('+h.id+')">Desfazer</button>':''}</div>`).join('')+'</div>':'');
  }catch(e){ box.innerHTML = '<div class="obs-line">Sem conexão.</div>'; }
}
const selPrecosIfood_ = ()=>[...document.querySelectorAll('.ifPrecoSel:checked')].map(x=>x.value);
async function pedirCatalogoIfood_(){ try{ const r = await apiCall('ifoodPrecosPedirCatalogo', {}); showMsg('integMsg',(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); } }
async function aplicarPrecosIfood_(){
  const ch = selPrecosIfood_(); if(!ch.length) return showMsg('integMsg','Marque os itens que quer gravar no sistema.','warn');
  if(!confirm('Gravar no sistema o preço do iFood de '+ch.length+' item(ns)? (muda o campo "Preço no iFood")')) return;
  try{ const r = await apiCall('ifoodPrecosAplicar', { chaves: ch }); showMsg('integMsg',(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); carregarIfoodPrecos_(); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
}
async function enviarPrecosIfood_(){
  const ch = selPrecosIfood_(); if(!ch.length) return showMsg('integMsg','Marque os itens que quer enviar ao iFood.','warn');
  if(!confirm('ENVIAR ao iFood o nosso preço de '+ch.length+' item(ns)? Os clientes do iFood passarão a ver o novo preço. Dá para desfazer pelo histórico.')) return;
  try{ const r = await apiCall('ifoodPrecosEnviar', { chaves: ch, confirmar: 'true' }); showMsg('integMsg',(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); carregarIfoodPrecos_(); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
}
async function desfazerPrecoIfood_(id){
  if(!confirm('Reenviar o preço anterior ao iFood?')) return;
  try{ const r = await apiCall('ifoodPrecosDesfazer', { id }); showMsg('integMsg',(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); carregarIfoodPrecos_(); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
}
async function carregarIfoodFin_(){
  const box = document.getElementById('ifoodFin'); if(!box) return;
  try{
    const r = await apiCall('ifoodFinanceiro', {});
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    box.innerHTML = `<div class="notif-card"><b>A receber do iFood:</b> ${R$_(r.aReceber.valor)} em ${r.aReceber.pedidos} pedido(s) pagos no app, ainda sem repasse.
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
  try{ const r = await apiCall('ifoodAvaliacaoResponder', { id, texto: t }); showMsg('integMsg',(r&&r.message)||'Não foi possível.', r&&r.ok?'ok':'warn'); carregarIfoodAval_(); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
}
async function carregarIfoodRel_(){
  const box = document.getElementById('ifoodRel'); if(!box) return;
  try{
    const r = await apiCall('ifoodRelatorio', { dias: 30 });
    if(!r || !r.ok){ box.innerHTML = '<div class="obs-line">' + escH((r && r.message) || 'Não foi possível carregar.') + '</div>'; return; }
    const f = r.ifood || {};
    box.innerHTML = `<div class="notif-card"><b>Vendas por canal — últimos ${r.dias} dias</b>` + (r.canais||[]).map(c=>`<div class="obs-line">${escH(c.canal)}: ${c.pedidos} pedido(s) · ${R$_(c.total)} · ticket ${R$_(c.ticket)} · margem ${c.margemPct}% · cancelados ${c.cancelados}</div>`).join('') + `</div>
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
  box.innerHTML = '<p class="sub" style="margin-top:8px;">Cada item do iFood precisa estar ligado a um produto do sistema para baixar os ingredientes e calcular o custo. Itens aparecem aqui quando chegam em pedidos.</p>' +
    ((r.itens||[]).map((i,ix)=>{
      const pend = !i.ligado && !i.ignorar;
      return `<div class="notif-card" style="border-left:4px solid ${pend?'#e0a800':'#2e9e5b'};">
        <b>${escH(i.nome)}</b> <span class="obs-line" style="display:inline;">(${i.tipo==='opcao'?'opção/adicional':'item'} · código ${escH(i.chave)})</span>
        ${i.ligado?`<div class="obs-line">✅ Ligado a: ${escH(i.ligadoNome||'—')} (${escH(i.ligado)}) <button class="ghost" style="width:auto;padding:2px 8px;min-height:28px;" onclick="ligarIfoodItem_(${ix},'desligar')">Desfazer</button></div>`:''}
        ${i.ignorar?`<div class="obs-line">🚫 Ignorado (não baixa estoque) <button class="ghost" style="width:auto;padding:2px 8px;min-height:28px;" onclick="ligarIfoodItem_(${ix},'desligar')">Desfazer</button></div>`:''}
        ${pend?`<div class="obs-line">⚠️ Sem ligação.</div>
          ${i.sugestao?`<div class="obs-line">Sugestão: <b>${escH(i.sugestao.nome)}</b> <button class="small-gold" onclick="ligarIfoodItem_(${ix},'sugestao')">Usar sugestão</button></div>`:''}
          <select id="ifSel_${ix}"><option value="">Escolher no sistema…</option>${i.tipo==='opcao'?'<optgroup label="Adicionais">'+op('adicional',r.adicionais)+'</optgroup>':''}<optgroup label="Produtos">${op('produto',r.produtos)}</optgroup><optgroup label="Combos">${op('combo',r.combos)}</optgroup></select>
          <div class="btnrow" style="margin-top:6px;"><button class="ghost" onclick="ligarIfoodItem_(${ix},'escolha')">Ligar</button><button class="ghost" onclick="ligarIfoodItem_(${ix},'ignorar')">Ignorar este item</button></div>`:''}
      </div>`; }).join('') || '<div class="obs-line">Nenhum item do iFood conhecido ainda.</div>');
}
async function ligarIfoodItem_(ix, modo){
  const r0 = ifoodItensDados_; const i = r0 && r0.itens[ix]; if(!i) return;
  let corpo = { chave: i.chave };
  if(modo==='sugestao' && i.sugestao){ corpo.tipo = i.sugestao.tipo; corpo.id = i.sugestao.id; }
  else if(modo==='escolha'){ const v = (document.getElementById('ifSel_'+ix)||{}).value || ''; if(!v) return showMsg('integMsg','Escolha um item do sistema.','warn'); const p = v.split(':'); corpo.tipo = p[0]; corpo.id = p[1]; }
  else if(modo==='ignorar'){ corpo.ignorar = true; }
  else if(modo==='desligar'){ corpo.tipo = 'desligar'; }
  try{
    const r = await apiCall('ifoodLigarItem', corpo);
    if(r && r.ok){ ifoodItensDados_ = r; renderIfoodItens_(); showMsg('integMsg','Salvo. Pedidos antigos sem ligação podem ser refeitos com "Refazer pedidos sem ligação".','ok'); }
    else showMsg('integMsg',(r&&r.message)||'Não foi possível salvar.','warn');
  }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
}
async function reprocessarIfood_(){
  if(!confirm('Refazer os pedidos do iFood que ficaram sem ligação, com as ligações atuais? (corrige custo e estoque)')) return;
  try{ const r = await apiCall('ifoodReprocessar', {}); if(r && r.ok){ showMsg('integMsg', r.message||'Pronto.','ok'); carregarIfoodPedidos_(); } else showMsg('integMsg',(r&&r.message)||'Não foi possível.','warn'); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
}
async function simularIfood_(){
  if(!confirm('Criar um pedido de TESTE do iFood? Ele vira uma venda de verdade (marcada como teste) — cancele depois. Nada é enviado ao iFood.')) return;
  try{ const r = await apiCall('ifoodSimular', { pagoNoApp: true }); if(r && r.ok){ showMsg('integMsg', r.message||'Criado.','ok'); carregarIfoodPedidos_(); } else showMsg('integMsg',(r&&r.message)||'Não foi possível.','warn'); }catch(e){ showMsg('integMsg','Sem conexão.','warn'); }
}

