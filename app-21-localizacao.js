
(function(){
  'use strict';
  const $ = id => document.getElementById(id);
  const INTERVALO_MS = 18000;
  let timer = null, ids = [];

  /* ---------- ENTREGADOR: envio de posição ---------- */
  const souEntregadorReal_ = () => !!(typeof currentUser !== 'undefined' && currentUser && currentUser.nivel === 'Entregador' && !currentUser.verComo);
  function enviar_(pos){
    const lat = Number(pos.coords.latitude), lng = Number(pos.coords.longitude), pr = Number(pos.coords.accuracy);
    if(!Number.isFinite(lat) || !Number.isFinite(lng)) return;
    ids.slice().forEach(id => {
      sbRpc_('entrega_atualizar_posicao', { p:{ vendaId:id, lat:lat, lng:lng, precisaoM:Number.isFinite(pr) ? Math.min(pr, 5000) : null } }).catch(() => {});
    });
  }
  function ler_(){
    if(!ids.length || !navigator.geolocation || document.hidden || navigator.onLine === false) return;
    try{ navigator.geolocation.getCurrentPosition(enviar_, () => {}, { enableHighAccuracy:true, timeout:10000, maximumAge:5000 }); }catch(e){}
  }
  function parar_(){ if(timer){ clearInterval(timer); timer = null; } ids = []; }
  function sincronizar_(){
    if(!souEntregadorReal_()){ if(timer) parar_(); return; }
    const meu = loginVisao_();
    const novos = (vendas || []).filter(v => v.status === 'Confirmada' && v.tipoEntrega === 'Entrega' && v.statusPedido === 'Saiu para entrega' && v.entregador === meu).map(v => v.id);
    const mudou = novos.length !== ids.length || novos.some(i => ids.indexOf(i) === -1);
    ids = novos;
    if(!ids.length){ parar_(); return; }
    if(!timer){ timer = setInterval(ler_, INTERVALO_MS); ler_(); }
    else if(mudou) ler_();
  }
  window.entregaLocalizacaoSincronizar_ = sincronizar_;

  /* ---------- EQUIPE: "Ver localização" ---------- */
  let mapaId = null, mapaTimer = null;
  window.botaoVerLocalizacao_ = function(v){
    if(!v || v.statusPedido !== 'Saiu para entrega' || !v.entregador) return '';
    if(!currentUser || (currentUser.nivel !== 'Admin' && currentUser.nivel !== 'Operador')) return '';
    return '<div class="btnrow" style="margin-top:6px;"><button type="button" class="ghost" onclick="abrirMapaEntrega_(\'' + escH(v.id) + '\')">📍 Ver localização</button></div>';
  };
  function modal_(){
    let m = $('mapaEntregaModal');
    if(!m){
      m = document.createElement('div'); m.className = 'modal-overlay'; m.id = 'mapaEntregaModal';
      m.innerHTML = '<div class="modal-box" style="max-width:420px;"><div class="modal-header"><h2>📍 Localização do entregador</h2><button class="close-btn" type="button" aria-label="Fechar" onclick="fecharMapaEntrega_()">✕</button></div><div id="mapaEntregaCorpo"><div id="mapaEntregaTxt"></div><div id="mapaEntregaMapa" style="display:none;position:relative;height:300px;margin-top:8px;border-radius:8px;overflow:hidden;background:#2a2a2a;touch-action:manipulation;"></div></div></div>';
      document.body.appendChild(m);
    }
    return m;
  }

  /* ---------- MAPA EMBUTIDO (tiles do OpenStreetMap em <img>; não depende de biblioteca nem de pasta vendor/) ---------- */
  let zoom_ = 16, ultimoPonto_ = null;
  function tile_(lat, lng, z){ const n = Math.pow(2, z), r = lat * Math.PI / 180; return { x:(lng + 180) / 360 * n, y:(1 - Math.log(Math.tan(r) + 1 / Math.cos(r)) / Math.PI) / 2 * n, n:n }; }
  function mapaOculto_(){ const d = $('mapaEntregaMapa'); if(d) d.style.display = 'none'; }
  window.mapaEntregaZoom_ = function(d){ zoom_ = Math.max(12, Math.min(18, zoom_ + d)); if(ultimoPonto_) mapaDesenhar_(ultimoPonto_.lat, ultimoPonto_.lng, ultimoPonto_.semSinal); };
  function mapaDesenhar_(lat, lng, semSinal){
    const div = $('mapaEntregaMapa'); if(!div || !Number.isFinite(lat) || !Number.isFinite(lng)) return;
    if(!$('mapaEntregaModal') || !$('mapaEntregaModal').classList.contains('open')) return;
    ultimoPonto_ = { lat:lat, lng:lng, semSinal:!!semSinal };
    div.style.display = 'block';
    const W = div.clientWidth || 340, H = div.clientHeight || 280, t = tile_(lat, lng, zoom_);
    const cx = Math.floor(t.x), cy = Math.floor(t.y), ox = (t.x - cx) * 256, oy = (t.y - cy) * 256;
    const dxMax = Math.ceil((W / 2) / 256) + 1, dyMax = Math.ceil((H / 2) / 256) + 1;
    let h = '';
    for(let dy = -dyMax; dy <= dyMax; dy++){
      const ty = cy + dy; if(ty < 0 || ty >= t.n) continue;
      for(let dx = -dxMax; dx <= dxMax; dx++){
        const tx = ((cx + dx) % t.n + t.n) % t.n;
        h += '<img alt="" draggable="false" referrerpolicy="origin" src="https://tile.openstreetmap.org/' + zoom_ + '/' + tx + '/' + ty + '.png" style="position:absolute;width:256px;height:256px;left:' + Math.round(W / 2 - ox + dx * 256) + 'px;top:' + Math.round(H / 2 - oy + dy * 256) + 'px;">';
      }
    }
    const cor = semSinal ? '#999' : '#d4af37';
    h += '<div style="position:absolute;left:' + (W / 2 - 11) + 'px;top:' + (H / 2 - 11) + 'px;width:22px;height:22px;border-radius:50%;background:' + cor + ';border:3px solid #fff;box-shadow:0 0 0 3px rgba(0,0,0,.35);box-sizing:border-box;"></div>';
    h += '<div style="position:absolute;left:8px;top:8px;display:flex;flex-direction:column;gap:6px;"><button type="button" aria-label="Aproximar" onclick="mapaEntregaZoom_(1)" style="width:36px;height:36px;padding:0;margin:0;border-radius:8px;background:#fff;color:#111;border:1px solid #999;font-size:20px;font-weight:700;line-height:1;">+</button><button type="button" aria-label="Afastar" onclick="mapaEntregaZoom_(-1)" style="width:36px;height:36px;padding:0;margin:0;border-radius:8px;background:#fff;color:#111;border:1px solid #999;font-size:20px;font-weight:700;line-height:1;">−</button></div>';
    h += '<div style="position:absolute;right:0;bottom:0;background:rgba(255,255,255,.8);color:#222;font-size:10px;padding:1px 5px;">© OpenStreetMap</div>';
    div.innerHTML = h;
  }
  async function carregarMapa_(){
    const corpo = $('mapaEntregaTxt'); if(!corpo || !mapaId) return;
    let r = null;
    try{ r = await sbRpc_('entrega_ver_posicao', { p:{ vendaId:mapaId } }); }catch(e){ r = null; }
    if(!$('mapaEntregaModal') || !$('mapaEntregaModal').classList.contains('open')) return;
    if(!r || !r.ok){ mapaOculto_(); corpo.innerHTML = '<p class="sub">Não foi possível ler a posição agora. Tentando de novo em instantes…</p>'; return; }
    if(r.estado === 'aguardando'){ mapaOculto_(); corpo.innerHTML = '<p class="sub">Aguardando o entregador iniciar a entrega.</p>'; return; }
    if(r.estado === 'sem_posicao'){ mapaOculto_(); corpo.innerHTML = '<p class="sub">Posição indisponível. O entregador ainda não enviou a localização (precisa permitir o GPS e manter o app aberto).</p>'; return; }
    const seg = Number(r.atualizadoHaSeg) || 0;
    const quando = seg < 90 ? 'há ' + seg + ' s' : 'há ' + Math.round(seg / 60) + ' min';
    corpo.innerHTML = (r.estado === 'sem_sinal' ? '<p class="sub" style="color:#f0d78c;">Posição indisponível. Última atualização ' + escH(quando) + '.</p>' : '<p class="sub">Atualizado ' + escH(quando) + '</p>') +
      (r.km != null ? '<p class="sub">A <b>' + escH(String(r.km).replace('.', ',')) + ' km</b> do destino</p>' : (r.destinoCompartilhado ? '' : '<p class="sub">O cliente não compartilhou o destino (a distância fica indisponível).</p>'));
    mapaDesenhar_(Number(r.lat), Number(r.lng), r.estado === 'sem_sinal');
  }
window.abrirMapaEntrega_ = function(vendaId){
    mapaId = String(vendaId || ''); const m = modal_(); m.classList.add('open');
    $('mapaEntregaTxt').innerHTML = '<p class="sub">⏳ Buscando a posição…</p>'; mapaOculto_();
    carregarMapa_(); clearInterval(mapaTimer); mapaTimer = setInterval(() => { if(!document.hidden) carregarMapa_(); }, INTERVALO_MS);
  };
  window.fecharMapaEntrega_ = function(){
    const m = $('mapaEntregaModal'); if(m) m.classList.remove('open');
    clearInterval(mapaTimer); mapaTimer = null; mapaId = null; ultimoPonto_ = null;
  };

  /* ---------- CLIENTE: distância aproximada + compartilhar destino (opcional) ---------- */
  const CHAVE_DEST = 'txb_destino_compartilhado_v1';
  const jaCompartilhou_ = c => { try{ return (JSON.parse(localStorage.getItem(CHAVE_DEST) || '{}') || {})[c] === 1; }catch(e){ return false; } };
  const marcarCompartilhou_ = c => { try{ const o = JSON.parse(localStorage.getItem(CHAVE_DEST) || '{}') || {}; o[c] = 1; const ks = Object.keys(o); if(ks.length > 30) delete o[ks[0]]; localStorage.setItem(CHAVE_DEST, JSON.stringify(o)); }catch(e){} };
  const autoLoc_ = {};   /* por pedido: 'pedindo' | 'falhou' (a permissão é pedida sozinha, uma vez por pedido) */
  window.acLocalAtualizar_ = async function(codigo, r){
    const box = $('acLocal'); if(!box) return;
    window.__acUltimo_ = { codigo:codigo, r:r };
    if(!r || r.tipoEntrega !== 'Entrega' || r.status === 'Cancelada' || ['Recebido','Em preparo','Pronta','Saiu para entrega'].indexOf(r.statusPedido) === -1){ box.innerHTML = ''; return; }
    let html = '';
    if(r.statusPedido === 'Saiu para entrega'){
      let d = null; try{ d = await sbRpcPublico_('api_distancia_entrega_publico', { p:{ codigo:codigo } }); }catch(e){ d = null; }
      if(d && d.ok && d.estado === 'ok') html += '<p class="sub" style="margin-top:8px;">🛵 O entregador está a cerca de <b>' + escH(String(d.km).replace('.', ',')) + ' km</b>.</p>';
      else if(d && d.ok && d.estado === 'sem_sinal') html += '<p class="sub" style="margin-top:8px;">🛵 Posição do entregador indisponível no momento.</p>';
    }
    if(!jaCompartilhou_(codigo) && navigator.geolocation && autoLoc_[codigo] !== 'falhou'){
      if(!autoLoc_[codigo]){ autoLoc_[codigo] = 'pedindo'; setTimeout(() => window.acCompartilharDestino_(codigo, true), 0); }
      html += '<p class="sub" style="margin-top:8px;font-size:11.5px;" id="acLocalMsg">📍 Pedindo permissão de localização para o entregador chegar até você…</p>';
    } else if(!jaCompartilhou_(codigo) && navigator.geolocation){
      html += '<div style="margin-top:8px;"><p class="sub" style="font-size:11.5px;">Não conseguimos pegar sua localização automaticamente. Libere a localização no navegador e toque abaixo.</p><button type="button" class="ghost" onclick="acCompartilharDestino_(\'' + escH(codigo) + '\')">📍 Compartilhar minha localização</button><p class="sub" style="margin-top:4px;font-size:11.5px;">Opcional. Ajuda o entregador a chegar e permite mostrar a distância aproximada. O restaurante não guarda a localização depois da entrega.</p><div class="msg" id="acLocalMsg"></div></div>';
    } else if(jaCompartilhou_(codigo)){
      html += '<p class="sub" style="margin-top:8px;font-size:11.5px;">✅ Localização compartilhada.</p>';
    }
    box.innerHTML = html;
  };
  window.acCompartilharDestino_ = function(codigo, auto){
    if(!navigator.geolocation){ showMsg('acLocalMsg', 'Seu aparelho não oferece localização.', 'warn'); return; }
    navigator.geolocation.getCurrentPosition(async pos => {
      const lat = Number(pos.coords.latitude), lng = Number(pos.coords.longitude);
      if(!Number.isFinite(lat) || !Number.isFinite(lng)) return;
      let r = null; try{ r = await sbRpcPublico_('api_compartilhar_destino_pedido', { p:{ codigo:codigo, lat:lat, lng:lng } }); }catch(e){ r = null; }
      if(r && r.ok){ marcarCompartilhou_(codigo); delete autoLoc_[codigo]; const b = $('acLocal'); if(b) b.innerHTML = '<p class="sub" style="margin-top:8px;font-size:11.5px;">✅ Localização compartilhada.</p>'; }
      else { autoLoc_[codigo] = 'falhou'; showMsg('acLocalMsg', (r && r.message) || 'Não foi possível enviar agora. O acompanhamento continua normalmente.', 'warn'); }
    }, () => { autoLoc_[codigo] = 'falhou'; if(typeof window.acLocalAtualizar_ === 'function' && window.__acUltimo_ && window.__acUltimo_.codigo === codigo) window.acLocalAtualizar_(codigo, window.__acUltimo_.r); else showMsg('acLocalMsg', 'Não foi possível obter sua localização. O acompanhamento continua normalmente.', 'warn'); }, { enableHighAccuracy:true, timeout:15000, maximumAge:30000 });
  };

  /* ---------- CLIENTE: captura silenciosa ao entrar + envio junto da criação do pedido ---------- */
  let posSilenciosa_ = null;   /* { lat, lng, t } só em memória, nunca vai para o localStorage */
  let capturando_ = false;
  window.cdCapturarLocalSilenciosa_ = function(){
    if(capturando_ || !navigator.geolocation) return;
    capturando_ = true;
    const fim = () => { capturando_ = false; };
    try{
      navigator.geolocation.getCurrentPosition(pos => {
        const lat = Number(pos.coords.latitude), lng = Number(pos.coords.longitude);
        if(Number.isFinite(lat) && Number.isFinite(lng)) posSilenciosa_ = { lat:lat, lng:lng, t:Date.now() };
        fim();
      }, fim, { enableHighAccuracy:true, timeout:15000, maximumAge:60000 });
    }catch(e){ fim(); }
  };
  window.__posCd_ = function(){ return posSilenciosa_ ? { lat:posSilenciosa_.lat, lng:posSilenciosa_.lng } : null; };
  window.cdEnviarLocalDoPedido_ = async function(vendaId){
    try{
      if(!vendaId) return;
      const codigo = String(vendaId).slice(-8);
      if(jaCompartilhou_(codigo)) return;
      /* se ainda não capturou, tenta uma última vez sem travar nada */
      if(!posSilenciosa_) window.cdCapturarLocalSilenciosa_();
      if(!posSilenciosa_) return;   /* sem permissão/sinal: o acompanhamento oferece o botão como antes */
      const r = await sbRpcPublico_('api_compartilhar_destino_pedido', { p:{ codigo:codigo, lat:posSilenciosa_.lat, lng:posSilenciosa_.lng } });
      if(r && r.ok) marcarCompartilhou_(codigo);
    }catch(e){ /* silencioso: nunca atrapalha o pedido */ }
  };

  /* ---------- ganchos (envolvem funções existentes sem trocar o comportamento delas) ---------- */
  function envolver(nome, depois){
    const orig = window[nome]; if(typeof orig !== 'function' || orig.__f5) return;
    const nova = function(){ const r = orig.apply(this, arguments); try{ depois.apply(this, arguments); }catch(e){} return r; };
    nova.__f5 = true; window[nome] = nova;
  }
  envolver('renderEntregas', sincronizar_);
  if(typeof window.sair === 'function' && !window.sair.__f5){
    const so = window.sair;
    window.sair = async function(){ parar_(); fecharMapaEntrega_(); return so.apply(this, arguments); };
    window.sair.__f5 = true;
  }
})();
