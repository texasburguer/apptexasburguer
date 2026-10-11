
/* ---------- base ---------- */
async function sb410Token_(){
  let s = sbSessaoLer_(); if(!s) throw new SbSessaoExpirada_();
  if(Date.now() > s.expira){ if(!(await sbRenovar_())) throw new SbSessaoExpirada_(); s = sbSessaoLer_(); }
  return s.access_token;
}
async function sb410Rpc_(fn){
  const t = await sb410Token_();
  const r = await sbJson_(SUPABASE_URL_+'/rest/v1/rpc/'+fn, { method:'POST', headers:{ apikey:SUPABASE_CHAVE_, Authorization:'Bearer '+t, 'Content-Type':'application/json' }, body:'{}' }, 20000, 1);
  return await r.json();
}
async function sb410Edge_(nome, corpo, ms){
  const t = await sb410Token_();
  const r = await sbJson_(SUPABASE_URL_+'/functions/v1/'+nome, { method:'POST', headers:{ Authorization:'Bearer '+t, 'Content-Type':'application/json' }, body: JSON.stringify(corpo||{}) }, ms||60000);
  return await r.json().catch(()=>({ ok:false, message:'Resposta inválida do servidor.' }));
}
const sb410Fmt_ = iso => iso ? new Date(iso).toLocaleString('pt-BR') : '—';
const sb410Admin_ = () => !!currentUser && currentUser.nivel === 'Admin';
const sb410Gestor_ = () => !!currentUser && (currentUser.nivel === 'Admin' || currentUser.nivel === 'Operador');

/* ---------- cartões (criados uma vez; ficam em Backup e espaço e em Sincronização e contingência) ---------- */
function sb410Montar_(){
  const aba = document.getElementById('tab-armazenamento');
  if(!aba || !USAR_SUPABASE_ || document.getElementById('sb410Sync')) return;
  aba.insertAdjacentHTML('beforeend', `
  <div class="card" id="sb410Sync"><h2>Cópia na planilha principal</h2><p class="sub">O cardápio, os clientes e as vendas são copiados para a planilha a cada 2 minutos, sozinhos.</p><div id="sb410SyncBox">Carregando…</div>
    <button class="small-gold" style="width:100%;padding:10px;margin-top:8px;" onclick="sb410SyncAgora()">Sincronizar agora</button></div>
  <div class="card" id="sb410Bk"><h2>Backup do Supabase</h2>
    <div style="border:1px solid #3a2c1c;border-radius:10px;padding:10px;margin-bottom:10px;">
      <label style="display:flex;gap:8px;align-items:center;font-weight:600;"><input type="checkbox" id="sb410BkAuto" style="width:auto;"> Backup automático diário</label>
      <div class="obs-line" id="sb410BkAutoSt" style="margin:4px 0 8px;"></div>
      <label for="sb410BkHora">Horário (Brasília)</label>
      <select id="sb410BkHora" style="width:100%;margin-bottom:8px;"></select>
      <label for="sb410BkRet">Guardar os backups automáticos por</label>
      <select id="sb410BkRet" style="width:100%;margin-bottom:8px;"><option value="3">3 dias</option><option value="7">7 dias</option><option value="14">14 dias</option><option value="30">30 dias</option></select>
      <button class="small-gold" style="width:100%;padding:10px;" onclick="sb410BkCfgSalvar()">Salvar configuração</button>
      <div class="msg" id="sb410BkCfgMsg"></div>
      <div class="obs-line">Backups manuais e os de antes de uma restauração nunca são apagados sozinhos.</div>
    </div>
    <div id="sb410BkBox">Carregando…</div>
    <button class="small-gold" style="width:100%;padding:10px;margin-top:8px;" onclick="sb410BkAgora()">Fazer backup agora</button></div>
  <div class="card" id="sb410Esp"><h2>Uso do Supabase</h2><div id="sb410EspBox">Carregando…</div></div>
  <div class="card" id="sb410Integ"><h2>Conferência de integridade</h2>
    <p class="sub">Compara as vendas de hoje no Supabase com a planilha (a conferência automática, às 6h10, confere o dia anterior).</p>
    <button class="ghost" style="width:100%;padding:10px;" onclick="sb410Integ()">Conferir agora</button><div class="msg" id="sb410IntegMsg"></div></div>`);
  const mover = (id, destino) => { const c = document.getElementById(id), d = document.getElementById('tab-'+destino); if(c && d && c.parentNode !== d) d.appendChild(c); };
  mover('sb410Sync','integridade'); mover('sb410Integ','integridade');
  // Backup e espaço: Backup, Uso do Supabase (com o arquivamento) e, por último, o Google Drive
  mover('sb410Esp','armazenamento');
  { const dc = document.getElementById('driveCard'), ta = document.getElementById('tab-armazenamento'); if(dc && ta) ta.appendChild(dc); }
}
function sb410Carregar_(){
  sb410Montar_();
  try{ const s = document.getElementById('tab-integridade'); if(s && s.classList.contains('active')) contAbrirTela_(); }catch(e){}
  try{ // no servidor novo os cartões antigos (planilha) não têm dados: ficam escondidos, os sb410* fazem o papel deles
    const velhos = ['Backup','Histórico e restauração','Conferência de integridade'];
    document.querySelectorAll('#tab-armazenamento > .card, #tab-integridade > .card').forEach(c=>{
      if(c.id && c.id.indexOf('sb410') === 0) return;
      const h = c.querySelector('h2'); if(h && velhos.indexOf(h.textContent.trim()) !== -1) c.style.display = 'none';
    });
  }catch(e){}
  if(!sb410Gestor_()) return;
  sb410SyncStatus();
  const adm = sb410Admin_();
  ['sb410Bk','sb410Esp','driveCard','sb410Integ'].forEach(id=>{ const e=document.getElementById(id); if(e) e.style.display = adm ? '' : 'none'; });
  if(adm){ sb410VerificarAlertaBackup_(); sb410BkLista(); sb410BkCfgCarregar(); sb410Espaco(); }
}

/* ---------- Etapa 4: sincronização ---------- */
async function sb410SyncStatus(){
  const box = document.getElementById('sb410SyncBox'); if(!box) return;
  try{
    const j = await sb410Rpc_('api_sync_status');
    if(!j || !j.ok){ box.textContent = 'Sem dados.'; return; }
    const horas = j.principal_ultimo_ok ? Math.round((Date.now()-new Date(j.principal_ultimo_ok).getTime())/3600000) : null;
    const travada = j.pendentes_principal > (j.alerta_itens||500) || (j.pendentes_principal>0 && (horas===null || horas > (j.alerta_horas||6)));
    box.innerHTML = `<div class="stat-row">
      <div class="stat-box"><b>${j.pendentes_principal}</b>Pendentes</div>
      <div class="stat-box"><b>${j.erros_principal}</b>Com erro</div></div>
      <span class="obs-line">Último envio para a planilha: ${sb410Fmt_(j.principal_ultimo_ok)}${(j.principal_ultimo_erro && (!j.principal_ultimo_ok || new Date(j.principal_ultimo_erro) > new Date(j.principal_ultimo_ok)))?' · <b>com erro agora</b>: '+escH(j.principal_ultimo_erro_msg||'sem detalhe'):''}</span>
      ${travada?'<span class="obs-line" style="color:#ffb3ab;">⚠️ Fila parada — confira o acesso às planilhas e a cota do Apps Script.</span>':''}`;
  }catch(e){ box.textContent = 'Não foi possível carregar.'; }
}
async function sb410SyncAgora(){
  const box = document.getElementById('sb410SyncBox'); if(box) box.textContent = 'Sincronizando…';
  try{ const j = await sb410Edge_('sync-fila', {}, 90000); if(!j.ok) alert('Falha: '+(j.message||'erro')); }catch(e){ alert('Sem conexão.'); }
  sb410SyncStatus();
}

/* ---------- Etapa 7: backup e espaço ---------- */
async function sb410BkLista(){
  const box = document.getElementById('sb410BkBox'); if(!box) return;
  try{
    const l = await sbSelecionar_('backups','order=data_hora.desc&limit=10',true);
    box.innerHTML = l.length ? l.map(b=>`<div style="margin:6px 0;"><b>${sb410Fmt_(b.data_hora)}</b> · ${escH(b.tipo)} · <span class="badge ${b.status==='Sucesso'?'done':(b.status==='Erro'?'baixo':'pend')}">${escH(b.status)}</span>
      ${b.tamanho_bytes?`<span class="obs-line">${Math.round(b.tamanho_bytes/1024)} KB${b.erro?' · '+escH(b.erro):''}${b.status==='Sucesso'?(b.copia_drive_em?' · ☁️ cópia no Drive':(b.copia_drive_erro?' · ⚠️ sem cópia no Drive: '+escH(b.copia_drive_erro):' · sem cópia no Drive')):''}</span>`:(b.erro?`<span class="obs-line">${escH(b.erro)}</span>`:'')}
      ${b.status==='Sucesso'?`<button class="ghost" style="margin-top:4px;padding:4px 10px;font-size:11px;" onclick="sb410BkRestaurar('${escH(b.id)}')">Restaurar</button>`:''}
      ${b.status==='Sucesso'&&!b.copia_drive_em?`<button class="ghost" style="margin-top:4px;padding:4px 10px;font-size:11px;" onclick="sb410BkReenviarDrive('${escH(b.id)}')">Enviar ao Drive</button>`:''}
      ${b.status!=='Em andamento'?`<button class="ghost" style="margin-top:4px;padding:4px 10px;font-size:11px;color:#e0443a;border-color:#e0443a;" onclick="sb410BkExcluir('${escH(b.id)}')">Excluir</button>`:''}</div>`).join('')
      : '<span class="obs-line">Nenhum backup ainda.</span>';
  }catch(e){ box.textContent = 'Não foi possível carregar.'; }
}
/* ALERTA DE BACKUP (só Admin). Substitui o alerta antigo, que dependia do módulo removido.
   Avisa em Notificações → Sistema quando: o último backup deu erro; ou não há backup com sucesso dentro do prazo
   (30 h com o automático ligado — ele é diário —, 72 h com ele desligado). Também marca a aba Administrador. */
let _bkAlertaTimer_ = null;
async function sb410VerificarAlertaBackup_(){
  try{
    if(!currentUser || currentUser.nivel !== 'Admin' || currentUser.emergencia) return;
    const l = await sbSelecionar_('backups','select=data_hora,tipo,status,erro&order=data_hora.desc&limit=10',true);
    let auto = true;
    try{ const c = await sbSelecionar_('sistema','chave=eq.BACKUP_AUTO_ATIVO',true); auto = !c.length || c[0].valor === true; }catch(e){}
    const ok = l.find(b=>b.status==='Sucesso'), ult = l[0];
    const limiteH = auto ? 30 : 72;
    let msg = '';
    if(!ok) msg = 'Nenhum backup com sucesso foi encontrado. Faça um em Administrador → Sistema → Backup.';
    else if(ult && ult.status === 'Erro') msg = 'O último backup falhou em ' + sb410Fmt_(ult.data_hora) + (ult.erro ? ' (' + String(ult.erro).slice(0,120) + ')' : '') + '. Último com sucesso: ' + sb410Fmt_(ok.data_hora) + '.';
    else if(Date.now() - Date.parse(ok.data_hora) > limiteH*3600*1000) msg = 'Faz mais de ' + limiteH + ' horas sem backup com sucesso (último: ' + sb410Fmt_(ok.data_hora) + '). Confira em Administrador → Sistema → Backup.';
    sistemaAlertas_.backup = msg;
    if(msg) marcarAlertaAdmin_(true);
    renderNotificacoes();
  }catch(e){ /* sem conexão: não alarma, tenta de novo na próxima */ }
}
function sb410IniciarAlertaBackup_(){
  if(_bkAlertaTimer_) return;
  setTimeout(sb410VerificarAlertaBackup_, 6000);
  _bkAlertaTimer_ = setInterval(sb410VerificarAlertaBackup_, 30*60*1000);
}
async function sb410BkCfgCarregar(){
  const h = document.getElementById('sb410BkHora');
  if(h && !h.options.length) for(let i=0;i<24;i++) h.insertAdjacentHTML('beforeend','<option value="'+i+'">'+String(i).padStart(2,'0')+':00</option>');
  try{
    const c = await sbSelecionar_('sistema','chave=in.(BACKUP_AUTO_ATIVO,BACKUP_HORA)',true);
    const v = k => (c.find(x=>x.chave===k)||{}).valor;
    const bc = await sbSelecionar_('backup_config','id=eq.true',true);
    const on = v('BACKUP_AUTO_ATIVO') === true;
    const a = document.getElementById('sb410BkAuto'), r = document.getElementById('sb410BkRet'), st = document.getElementById('sb410BkAutoSt');
    if(a) a.checked = on;
    if(h) h.value = String(v('BACKUP_HORA') ?? 4);
    if(r && bc[0]) r.value = String(bc[0].auto_retencao_dias);
    if(st) st.textContent = on ? 'Ligado: um backup por dia no horário escolhido.' : '⚠️ Desligado: nenhum backup é feito sozinho. Só os manuais.';
  }catch(e){}
}
async function sb410BkCfgSalvar(){
  const on = !!document.getElementById('sb410BkAuto').checked, hora = Number(document.getElementById('sb410BkHora').value), ret = Number(document.getElementById('sb410BkRet').value);
  const m = document.getElementById('sb410BkCfgMsg'); if(m) m.textContent = 'Salvando…';
  try{
    const t = await sb410Token_();
    const H = { apikey:SUPABASE_CHAVE_, Authorization:'Bearer '+t, 'Content-Type':'application/json', Prefer:'return=minimal' };
    const pat = (url, corpo) => sbJson_(SUPABASE_URL_+'/rest/v1/'+url, { method:'PATCH', headers:H, body:JSON.stringify(corpo) });
    await pat('sistema?chave=eq.BACKUP_AUTO_ATIVO', { valor:on });
    await pat('sistema?chave=eq.BACKUP_HORA', { valor:hora });
    await pat('sistema?chave=eq.BACKUP_FREQ', { valor:'diario' });
    await pat('backup_config?id=eq.true', { auto_retencao_dias:ret });
    if(m) m.textContent = 'Configuração salva.';
    sb410BkCfgCarregar();
  }catch(e){ if(m) m.textContent = 'Não foi possível salvar agora.'; }
}
let _sb410BkOcupado_ = false;
async function sb410BkAgora(){
  if(_sb410BkOcupado_) return; _sb410BkOcupado_ = true;
  const box = document.getElementById('sb410BkBox'); if(box) box.insertAdjacentHTML('afterbegin', '<div class="obs-line" id="sb410BkFazendo">Fazendo backup… pode levar alguns segundos.</div>');
  try{ const j = await sb410Edge_('criar-backup', { tipo:'Manual' }, 120000);
    alert(j.ok ? 'Backup feito ('+Math.round((j.tamanho||0)/1024)+' KB).' + (j.drive ? ' Cópia no Drive: ok.' : ' ATENÇÃO: a cópia no Drive não foi feita' + (j.driveErro ? ' ('+j.driveErro+')' : '') + '.') : 'Erro: '+(j.message||'falha')); }catch(e){ alert('Sem conexão.'); }
  _sb410BkOcupado_ = false; sb410BkLista(); setTimeout(sb410VerificarAlertaBackup_, 1500);
}
/* Restaurar e excluir backup: pedem a senha do Administrador no pop-up (confere na hora) e o servidor confere de novo. */
function sb410BkRestaurar(id){
  if(!confirm('Restaurar este backup? Os dados atuais serão substituídos (usuários, auditoria e backups são preservados). Um backup de segurança é feito antes.')) return;
  abrirModalSenhaAdmin(async function(senha){
    try{ const j = await sb410Edge_('restaurar-backup', { backupId:id, senhaAdmin:senha }, 240000);
      alert(j.message || (j.ok?'Restaurado.':'Erro.')); if(j.ok) location.reload(); }catch(e){ alert('Sem conexão. Confira o estado antes de repetir.'); }
  });
}
function sb410BkExcluir(id){
  if(!confirm('Excluir este backup? O arquivo no Supabase será apagado e não dá para desfazer. A cópia que já está no Google Drive não é apagada.')) return;
  abrirModalSenhaAdmin(async function(senha){
    try{ const j = await sb410Edge_('excluir-backup', { backupId:id, senhaAdmin:senha }, 60000);
      alert(j.message || (j.ok?'Backup excluído.':'Erro.')); }catch(e){ alert('Sem conexão. Tente de novo.'); }
    sb410BkLista(); setTimeout(sb410VerificarAlertaBackup_, 1500);
  });
}
async function sb410BkReenviarDrive(id){
  const box = document.getElementById('sb410BkBox'); if(box) box.insertAdjacentHTML('afterbegin', '<div class="obs-line">Enviando ao Drive… pode levar até 2 minutos.</div>');
  try{ const j = await sb410Edge_('criar-backup', { reenviarDrive:id }, 170000);
    alert(j.ok ? 'Cópia enviada ao Drive.' : 'Não foi possível enviar ao Drive: ' + (j.message || 'falha')); }catch(e){ alert('Sem conexão. Tente de novo.'); }
  sb410BkLista();
}
async function sb410Espaco(){
  const box = document.getElementById('sb410EspBox'); if(!box) return;
  try{
    const j = await sb410Rpc_('api_espaco_uso');
    if(!j || !j.ok){ box.textContent = '—'; return; }
    const cor = j.percentual > 90 ? '#e0443a' : j.percentual > 70 ? '#f5902e' : '#4cc35f';
    box.innerHTML = `<div style="height:12px;background:#3a2c1c;border-radius:6px;overflow:hidden;"><div style="width:${Math.min(100,j.percentual)}%;height:100%;background:${cor};"></div></div>
      <div class="stat-row" style="margin-top:10px;"><div class="stat-box"><b>${j.db_mb} MB</b>Usado</div><div class="stat-box"><b>${j.percentual}%</b>De 500 MB</div>
      <div class="stat-box"><b>${j.vendas_total}</b>Vendas ativas</div><div class="stat-box"><b>${j.vendas_arquivadas}</b>Arquivadas</div></div>
      <span class="obs-line" id="sb410ArqTexto">Vendas com mais de 90 dias vão para a planilha (abas Arquivo_*) e saem do Supabase, todo dia de madrugada.</span>
      <div style="margin-top:10px;border-top:1px solid #3a2c1c;padding-top:10px;">
        <label for="sb410ArqDias">Regra de arquivamento (vale para o envio automático e para o botão abaixo): mandar para a planilha o que tem mais de</label>
        <select id="sb410ArqDias" onchange="sb410ArqSalvarRegra(this.value)" style="width:100%;margin:6px 0;"><option value="90">90 dias</option><option value="60">60 dias</option><option value="30">30 dias (mínimo permitido)</option></select>
        <button class="small-gold" style="width:100%;padding:10px;" onclick="sb410ArquivarAgora()">Mandar para a planilha agora</button>
        <div class="msg" id="sb410ArqMsg"></div>
      </div>
      <div style="margin-top:10px;border-top:1px solid #3a2c1c;padding-top:10px;">
        <label style="display:flex;align-items:center;gap:8px;margin:0;"><input type="checkbox" id="sb410EmergAtivo" onchange="sb410EmergSalvar()" style="width:auto;margin:0;"> Proteção de espaço: se o uso chegar a</label>
        <select id="sb410EmergPct" onchange="sb410EmergSalvar()" style="width:100%;margin:6px 0;"><option value="90">90% do limite</option><option value="95">95% do limite</option><option value="98">98% do limite</option></select>
        <span class="obs-line">Aí o sistema manda para a planilha as vendas e caixas já encerrados, do mais antigo para o mais novo (mesmo com menos de 30 dias; o que tem menos de 1 dia fica), e só apaga do Supabase o que a planilha confirmou. Pedido em andamento e caixa aberto nunca saem. Verifica de hora em hora.</span>
        <div class="msg" id="sb410EmergMsg"></div>
      </div>`;
    sb410ArqCarregarRegra_(); sb410EmergCarregar_();
  }catch(e){ box.textContent = '—'; }
}
function sb410ArqTexto_(d){ const t = document.getElementById('sb410ArqTexto'); if(t) t.textContent = 'Vendas com mais de ' + d + ' dias vão para a planilha (abas Arquivo_*) e saem do Supabase, todo dia de madrugada. Os relatórios buscam o que foi arquivado.'; }
async function sb410ArqCarregarRegra_(){
  try{ const c = await sbSelecionar_('backup_config','id=eq.true',true); const d = c && c[0] && Number(c[0].arquivar_dias);
    const sel = document.getElementById('sb410ArqDias'); if(d && sel){ if(![30,60,90].includes(d)){ const o = document.createElement('option'); o.value = d; o.textContent = d + ' dias'; sel.appendChild(o); } sel.value = String(d); sb410ArqTexto_(d); } }catch(e){}
}
async function sb410EmergCarregar_(){
  try{ const c = await sbSelecionar_('backup_config','id=eq.true',true); const r = c && c[0]; if(!r) return;
    const a = document.getElementById('sb410EmergAtivo'), p = document.getElementById('sb410EmergPct');
    if(a) a.checked = r.arquivar_emerg_ativo !== false; if(p && r.arquivar_emerg_pct) p.value = String(r.arquivar_emerg_pct); }catch(e){}
}
async function sb410EmergSalvar(){
  const a = document.getElementById('sb410EmergAtivo'), p = document.getElementById('sb410EmergPct'), m = document.getElementById('sb410EmergMsg');
  try{ const t = await sb410Token_();
    const r = await sbJson_(SUPABASE_URL_+'/rest/v1/backup_config?id=eq.true', { method:'PATCH', headers:{ apikey:SUPABASE_CHAVE_, Authorization:'Bearer '+t, 'Content-Type':'application/json', Prefer:'return=minimal' }, body: JSON.stringify({ arquivar_emerg_ativo: !!(a&&a.checked), arquivar_emerg_pct: Number(p&&p.value)||95, atualizado_em:new Date().toISOString() }) }, 15000);
    if(!r.ok) throw new Error('falha');
    if(m) m.textContent = a && a.checked ? 'Salvo: proteção ligada aos ' + (p.value) + '%.' : 'Salvo: proteção desligada.';
  }catch(e){ if(m) m.textContent = 'Não foi possível salvar agora.'; }
}
async function sb410ArqSalvarRegra(v){
  const dias = Math.max(30, Number(v) || 90), m = document.getElementById('sb410ArqMsg');
  try{ const t = await sb410Token_();
    const r = await sbJson_(SUPABASE_URL_+'/rest/v1/backup_config?id=eq.true', { method:'PATCH', headers:{ apikey:SUPABASE_CHAVE_, Authorization:'Bearer '+t, 'Content-Type':'application/json', Prefer:'return=minimal' }, body: JSON.stringify({ arquivar_dias:dias, atualizado_em:new Date().toISOString() }) }, 15000);
    if(!r.ok) throw new Error('falha');
    sb410ArqTexto_(dias); if(m) m.textContent = 'Regra salva: arquivar o que tem mais de ' + dias + ' dias (a partir da próxima madrugada).';
  }catch(e){ if(m) m.textContent = 'Não foi possível salvar a regra agora.'; }
}

async function sb410ArquivarAgora(){
  const dias = Number((document.getElementById('sb410ArqDias')||{}).value) || 90;
  if(!confirm('Mandar para a planilha as vendas e caixas fechados com mais de ' + dias + ' dias e tirá-los do Supabase? Eles continuam guardados nas abas Arquivo_* da planilha. Pode levar alguns minutos; não feche a página.')) return;
  const m = document.getElementById('sb410ArqMsg'); if(m) m.textContent = 'Arquivando…';
  try{
    const j = await sb410Edge_('arquivar-antigos', { dias: dias, manual: true }, 280000);
    if(m) m.textContent = j.ok ? ('Pronto: ' + (j.vendas||0) + ' venda(s) e ' + (j.caixas||0) + ' caixa(s) arquivados.') : ('Parou: ' + (j.message || j.erro || 'falha') + ' (' + (j.vendas||0) + ' venda(s) e ' + (j.caixas||0) + ' caixa(s) já arquivados).');
  }catch(e){ if(m) m.textContent = 'Sem conexão. Confira o resultado antes de repetir.'; }
  sb410Espaco();
}


/* Chamada pelo roteador (sbRotear_) no lugar do "ainda não migrada" — ver LEIA-ME */
/* Fotos: sempre no Drive principal, com cópia no Drive da contingência (o espelho de 10 min também copia as que faltarem). */
async function sbUploadFoto_(action, p){
  const destino = 'ambos';
  const corpo = { nomeBase:p.nomeBase, base64Data:p.base64Data, mimeType:p.mimeType, destino };
  if(action === 'uploadFotoCombo') corpo.comboId = p.comboId; else corpo.produtoId = p.produtoId;
  const j = await sb410Edge_('upload-foto', corpo, 90000);
  if(j && j.ok){
    j.fotoId = j.id_principal || j.id_contingencia; j.fotoUrl = sbFotoUrl_(j.fotoId);
    // quem chama espera as listas atualizadas (r.produtos / r.combos)
    const lista = action === 'uploadFotoCombo' ? combos : produtos, alvo = action === 'uploadFotoCombo' ? p.comboId : p.produtoId;
    const it = (lista || []).find(x => x.id === alvo);
    if(it && j.id_principal){ it.fotoId = j.id_principal; it.fotoUrl = j.fotoUrl; }
    j.produtos = produtos; j.combos = combos;
  }
  return j;
}

async function sbRemoverFoto_(action, p){
  const corpo = action === 'excluirFotoCombo' ? { comboId: p.comboId } : { produtoId: p.produtoId };
  const j = await sb410Edge_('remover-foto', corpo, 60000);
  if(j && j.ok){
    const lista = action === 'excluirFotoCombo' ? combos : produtos, alvo = action === 'excluirFotoCombo' ? p.comboId : p.produtoId;
    const it = (lista || []).find(x => x.id === alvo);
    if(it){ it.fotoId = ''; it.fotoUrl = ''; }
    j.produtos = produtos; j.combos = combos;
  }
  return j;
}

/* ---------- Etapa 9: integridade ---------- */
async function sb410Integ(){
  const m = document.getElementById('sb410IntegMsg'); if(m) m.textContent = 'Conferindo…';
  try{ const j = await sb410Edge_('conferir-integridade', {}, 60000);
    if(!m) return;
    if(j.ok){
      const fila = Number(j.pendentes_fila)||0, dif = Number(j.dif)||0, bate = Math.abs(dif) <= Math.max(1, fila);
      const dia = j.dia ? j.dia.split('-').reverse().join('/') : 'hoje';
      m.className = 'msg ' + (bate ? 'ok' : 'warn');
      m.textContent = (bate ? '✅ Tudo certo. ' : '⚠️ Diferença encontrada. ') + 'Dia ' + dia + ': ' + j.supabase + ' venda(s) no Supabase e ' + j.planilha + ' na planilha' + (dif ? ' (diferença de ' + dif + (fila ? ', ' + fila + ' ainda na fila de envio' : '') + ')' : '') + '.';
    } else { m.className = 'msg warn'; m.textContent = 'Erro: '+(j.message||'falha'); } }
  catch(e){ if(m){ m.className = 'msg warn'; m.textContent = 'Sem conexão.'; } }
}

/* ---------- gancho: ao abrir Administrador → Sistema → Backup e espaço / Sincronização e contingência ---------- */
(function(){
  const orig = window.abrirAdministrador;
  if(typeof orig !== 'function') return;
  window.abrirAdministrador = function(sub){
    const r = orig.apply(this, arguments);
    try{ if(['armazenamento','integridade'].some(id=>{ const s = document.getElementById('tab-'+id); return s && s.classList.contains('active'); })) sb410Carregar_(); }catch(e){}
    return r;
  };
})();
