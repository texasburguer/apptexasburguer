/* Texas Burger — service worker v39: avisos com o app fechado (push da equipe e do cliente) + notificações + abertura instantânea + casca/ícones/logo guardados.
   Precisa ficar na MESMA pasta do HTML, em endereço https.
   - Página: mostra a cópia guardada NA HORA e confere a rede em segundo plano. Se a página mudou, avisa o app ("Nova versão disponível").
   - Ícones, logo e manifest: guardados (cache primeiro).
   - Fotos do Google Drive: só são guardadas se o navegador conseguir ler a resposta (modo "cors"); senão o navegador cuida delas.
   - BACKEND: NADA de Apps Script (script.google.com) nem de Supabase (*.supabase.co) é guardado aqui.
     Dados, pedidos, login e RPCs nunca passam pelo cache do service worker — sempre vão direto para a rede.
   - O único cache de dados é o de fotos (FOTOS) e o da casca/ícones (SHELL/ASSETS). Não adicionar outros. */
const SHELL = 'texas-shell-v130';
const ASSETS = 'texas-assets-v8';   // trocou ícone/logo/manifest/leaflet? suba para v5
const FOTOS = 'texas-fotos-v1';
/* Código do app dividido em arquivos (app-*.js e estilo-*.css). Cada arquivo tem ?v=<impressão digital> na página; o cache guarda
   pela endereço COMPLETO, então uma página antiga sempre acha os arquivos antigos dela e a nova acha os novos (nunca mistura versões).
   A lista abaixo é gerada pelo script de selagem (selar.py) a cada entrega. */
const CODIGO = 'texas-codigo-v5';   // trocou o nome = todo aparelho descarta o cache de código antigo (inclusive cópia vazia)
const LISTA = [/*LISTA-INICIO*/
  'css/estilo-base.css?v=205e0ad2',
  'js/app-01-base-e-api.js?v=a577d7bf',
  'js/app-02-abas.js?v=4172dc0a',
  'js/app-03-cadastros.js?v=46167420',
  'js/app-04-pedidos-entrega.js?v=04c0dcf4',
  'js/app-05-avisos-push.js?v=5ff06049',
  'js/app-06-caixa.js?v=d8657313',
  'js/app-07-impressao.js?v=5c9f0484',
  'js/app-08-vendas-despesas.js?v=0b8d9a34',
  'js/app-09-ajuda.js?v=6c228ecc',
  'js/app-10-backup-financeiro.js?v=a9361edd',
  'js/app-11-admin-integracoes.js?v=32bb5e8a',
  'js/app-12-gestao-ia.js?v=0232103e',
  'js/app-13-conexao-sync.js?v=4169baef',
  'js/app-14-relatorios.js?v=89a1208a',
  'js/app-15-cardapio-cliente.js?v=b3549f0c',
  'js/app-16-sessao-final.js?v=ef1da8ab',
  'js/app-17-sessao-supabase.js?v=6eb3d678',
  'js/app-18-queda-supabase.js?v=c3cdfe49',
  'css/estilo-ia-cardapio.css?v=b19ce938',
  'js/app-19-ia.js?v=37d36dbd',
  'js/app-20-balao-interno.js?v=c974eb7b',
  'js/app-21-localizacao.js?v=bb28de16',
  'css/estilo-equipe.css?v=10e8510c',
  'js/app-22-navegacao-inferior.js?v=9c0835e7',
  'js/app-23-janelas-popup.js?v=6f031891',
  'js/app-24-acessibilidade.js?v=1567f2c1',
  'js/app-25-cadastro-facil.js?v=ad9fdcff',
  'js/app-26-visual.js?v=3c963d27',
  'css/estilo-conta-pagamento.css?v=c8bbf776',
  'js/app-28-dialogos.js?v=58e2325f',
  'js/app-27-conta-cliente.js?v=2228f1aa',
  'js/app-29-usabilidade.js?v=8c6dd0c8',
  'js/app-30-teclado-pc.js?v=6ada025e',
  'js/app-31-alertas.js?v=cc24a649',
  'js/app-33-escala.js?v=345a54d7',
  'js/app-34-eventos.js?v=69bb2d23',
  'js/app-35-equipe-extras.js?v=650e4df1',
  'js/app-36-gestao.js?v=bb125f4f',
  'js/app-37-ponto-rapido.js?v=2dcb25e1',
  'js/app-38-ponto-rosto.js?v=d58fe8fd',
  'js/app-39-fotos-registros.js?v=b24b7995',
  'js/app-40-etiquetas.js?v=5ac4487f',
  'js/app-41-ifood-extras.js?v=e6801644',
  'js/app-42-ifood-catalogo.js?v=60701d5d',
  'js/app-43-erros-visiveis.js?v=bcc87052',
  'js/app-44-ifood-vinheta.js?v=de438ee2',
  'js/app-45-ver-cardapio.js?v=a75737b8',
  'js/app-46-cardapio-hoje.js?v=4cc0f76b',
  'js/app-47-cardapio-facil.js?v=4a7fab83',
  'js/app-51-infinitepay.js?v=a3fdd917',
  'js/app-52-ifood-financeiro.js?v=bf3223c9',
  'js/app-53-ifood-entregador.js?v=b0e6ddfa',
  'js/app-54-ifood-indicadores.js?v=144d8d09',
  'js/app-55-ifood-roteiro.js?v=7de45218',
  'js/app-50-ifood-homologacao.js?v=72eb9915',
  'js/app-49-jogos.js?v=792e66dd',
  'js/jogo-burger.js?v=d67a1a42',
  'js/jogo-chuva.js?v=c0a88274',
  'js/jogo-memoria.js?v=5246b144',
  'js/jogo-cobra.js?v=651a89f6',
  'js/app-48-armazenamento.js?v=c4160c65',
  'js/app-32-equipe.js?v=5f1d4bd8',
/*LISTA-FIM*/];
const FOTOS_MAX = 150;
const PRE = ['manifest.webmanifest', 'img/icon-192.png', 'img/badge-96.png', 'img/apple-touch-icon.png', 'img/logo-texas-burger.webp', 'img/logo-impressao-cor.png', 'sons/ifood-novo-pedido.mp3'];
const HOSTS_FOTO = ['drive.google.com', 'lh3.googleusercontent.com'];

self.addEventListener('install', e => e.waitUntil((async () => {
  const c = await caches.open(ASSETS);
  await Promise.all(PRE.map(u => c.add(u).catch(() => {})));
  try { const cc = await caches.open(CODIGO); await Promise.all(LISTA.map(async u => { try { const rs = await fetch(u, { cache: 'reload' }); if (rs && rs.ok && !(await vazia_(rs))) await cc.put(u, rs); } catch (err) {} })); } catch (err) {}
  await self.skipWaiting();
})()));

self.addEventListener('activate', e => e.waitUntil((async () => {
  let trocou = false;   // v117: se um aparelho tinha cache de versão antiga, a página abre de novo sozinha com o código novo (uma vez)
  for (const k of await caches.keys()) {
    if ((k.indexOf('texas-shell') === 0 && k !== SHELL) || (k.indexOf('texas-assets') === 0 && k !== ASSETS) || (k.indexOf('texas-codigo') === 0 && k !== CODIGO)) { await caches.delete(k); trocou = true; }
  }
  try {   /* limpa do cache de código o que não está na lista atual */
    const cc = await caches.open(CODIGO);
    const validos = new Set(LISTA.map(u => new URL(u, self.registration.scope).href));
    for (const rq of await cc.keys()) if (!validos.has(rq.url)) await cc.delete(rq);
  } catch (err) {}
  await self.clients.claim();
  if (trocou) { try { for (const c of await self.clients.matchAll({ type: 'window' })) { if (c.url && c.visibilityState !== 'hidden') c.navigate(c.url).catch(() => {}); } } catch (err) {} }
})()));

/* Resposta vazia (0 byte) nunca vale como cópia boa: pode vir de envio incompleto ao GitHub. Não guardar e não servir. */
async function vazia_(res) {
  try { const b = await res.clone().blob(); return b.size === 0; } catch (err) { return false; }
}

async function avisarNovaVersao_() {
  const lista = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
  lista.forEach(cl => cl.postMessage({ tipo: 'nova-versao' }));
}

/* Página: cópia guardada na hora + atualização em segundo plano (stale-while-revalidate). */
function paginaRapida_(r) {
  let fim = Promise.resolve();
  const resposta = (async () => {
    const c = await caches.open(SHELL);
    const copia = await c.match('./');
    const rede = fetch(r).then(async res => {
      if (res && res.ok) {
        if (copia) {
          try { const [a, b] = await Promise.all([res.clone().text(), copia.clone().text()]); if (a !== b) avisarNovaVersao_(); } catch (err) {}
        }
        await c.put('./', res.clone());
      }
      return res;
    });
    fim = rede.catch(() => {});
    return copia || rede;
  })();
  return { resposta, fim: resposta.then(() => fim, () => {}) };
}

async function cacheDepoisRede_(r, nome) {
  const c = await caches.open(nome);
  const hit = await c.match(r);
  if (hit && !(await vazia_(hit))) return hit;
  if (hit) await c.delete(r);
  const res = await fetch(r);
  if (res && res.ok && !(await vazia_(res))) c.put(r, res.clone());
  return res;
}

/* Código do app (app-*.js, estilo-*.css): cache primeiro, pelo endereço completo (com ?v=). */
async function codigoCache_(r) {
  const c = await caches.open(CODIGO);
  const hit = await c.match(r);
  if (hit && !(await vazia_(hit))) return hit;
  if (hit) await c.delete(r);
  const res = await fetch(r);
  if (res && res.ok && !(await vazia_(res))) c.put(r, res.clone());
  return res;
}

async function aparar_(c) {
  const ks = await c.keys();
  for (let i = 0; i < ks.length - FOTOS_MAX; i++) await c.delete(ks[i]);
}
async function fotoCache_(r) {
  const c = await caches.open(FOTOS);
  const hit = await c.match(r);
  if (hit) return hit;
  const res = await fetch(r);
  if (res && res.ok && res.type !== 'opaque') { await c.put(r, res.clone()); aparar_(c); }
  return res;
}

self.addEventListener('fetch', e => {
  const r = e.request;
  if (r.method !== 'GET') return;
  const url = new URL(r.url);
  if (r.mode === 'navigate' && url.origin === self.location.origin) {
    const p = paginaRapida_(r);
    e.respondWith(p.resposta); e.waitUntil(p.fim);
    return;
  }
  if (url.origin === self.location.origin) {
    if (/\/(app|estilo)-[^/]+\.(js|css)$/.test(url.pathname)) { e.respondWith(codigoCache_(r)); return; }
    if (PRE.some(p => url.pathname.endsWith('/' + p)) || /\.(png|webp|jpe?g|svg|woff2?|mp3)$/i.test(url.pathname) || url.pathname.indexOf('/vendor/leaflet/') !== -1) e.respondWith(cacheDepoisRede_(r, ASSETS));
    return;
  }
  /* foto do Drive: só intercepta quando o app pediu em modo "cors" (com crossorigin="anonymous"); no modo normal o navegador cuida */
  if (r.mode === 'cors' && HOSTS_FOTO.indexOf(url.hostname) !== -1) { e.respondWith(fotoCache_(r)); return; }
  /* tudo o mais (inclusive script.google.com) passa direto, sem cache */
});

/* Toque no aviso: abre o app. Aviso do cliente traz um endereço ./?pedido=XXXXXXXX ou ./?feedback=XXXXXXXX:
   com o app aberto, manda a mensagem "abrir-url" para a página abrir a tela certa; fechado, abre direto nesse endereço. */
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const d = e.notification.data || {};
  const url = /^\.\/\?(pedido|feedback)=[0-9a-f]{8}$/.test(String(d.url || '')) ? d.url : './';
  e.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const c of list) { if ('focus' in c) { if (url !== './') c.postMessage({ tipo: 'abrir-url', url }); return c.focus(); } }
    if (self.clients.openWindow) return self.clients.openWindow(url);
  }));
});

/* Push (app fechado): o servidor manda { titulo, texto, tag, tipo, url }. Sem dados pessoais do cliente. */
self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = { titulo: 'Texas Burger', texto: e.data ? e.data.text() : '' }; }
  const titulo = String(d.titulo || 'Texas Burger').slice(0, 80);
  e.waitUntil(self.registration.showNotification(titulo, {
    body: String(d.texto || '').slice(0, 140), tag: String(d.tag || 'texas'), renotify: true,
    icon: 'img/icon-192.png', badge: 'img/badge-96.png', vibrate: [250, 120, 250, 120, 400], requireInteraction: d.tipo === 'pedido' || d.tipo === 'alerta',
    data: { url: String(d.url || './') }
  }));
});
