/* =====================================================================
   CONFIGURAÇÃO DESTE RESTAURANTE — é o ÚNICO arquivo que muda de um restaurante para outro.
   Quem gera este arquivo é o Painel de Revenda (aba "Ligações" → "Gerar arquivo de configuração").
   Só entram endereços e chaves PÚBLICAS: senha e chaves secretas nunca ficam aqui.
   A marca (nome, cores, logos) pode ser ajustada depois pelo dono em Administrador → Sistema → Aparência.
   ===================================================================== */
window.RESTAURANTE = {
  motor: 'https://lucassricardo95.github.io/motor/texas-estavel/',   // sistema que este restaurante usa: texas-estavel (acompanha as atualizações) ou uma versão fixa, ex.: .../motor/texas-v1.27/
  slug: 'texas-burger',
  nome: 'Texas Burger',
  siteUrl: 'https://texasburguer.github.io/apptexasburguer/',
  supabaseUrl: 'https://awryywtgqfaxppayzpca.supabase.co',
  supabaseChave: 'sb_publishable_tCN4tLlRshbP8OOmfDcVZA_LqqMMbRg',
  apiUrl: 'https://script.google.com/macros/s/AKfycbwCftUm-1pxhA8XLNqMB7dMUJxbj5GOsYHgFHZDqlbAH0XXRkUlsOKJkGTlGzR1LWxVpQ/exec',
  contingenciaUrl: 'https://script.google.com/macros/s/AKfycby3WljBnr7gpJrHdkbTvBCh5uIXqS4KCS6wkBYB5idxf5gI04efoDumQj264kR_smoW/exec',
  pushChave: 'BK1UHD8LyT7jX5dBSaXZ4YdsnHIRa6JrYofIWpHMhEfFh3Lam6akQcpzhJERF_T6tg0JlXA3--hHk0geAzolFyI',
  marca: {
    slogan: 'Sabor que conquista',
    assistente: 'Tex',
    tema: 'brasa',
    cores: { destaque: '#e0b53a', botao: '#d20807', fundo: '#0b0705' },
    logos: { cardapio: 'img/logo-texas-burger.webp', impressao: '', icone: 'img/icon-512.png' },
    // Tema dos mini jogos do cliente (generico, burger ou churros)
    jogos: { tema: 'burger', nomes: { memoria: 'Memória Texas' } }
  },
  modulos: { ifood: true, nfce: true, mercadopago: true, infinitepay: true, mesas: true, ponto: true, eventos: true, planilhas: true, ia: true }
};
