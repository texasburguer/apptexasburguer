/* Fase 6 (usabilidade): estados "carregando / vazio / erro" e tabelas em cartões no celular.
   Funções globais; não dependem de outros arquivos para carregar. */
(function(){
  'use strict';
  var esc = function(t){ return String(t == null ? '' : t).replace(/[&<>"]/g, function(c){ return ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'})[c]; }); };

  /* Carregando: n barras animadas (mesmo pulso do cardápio). */
  window.esqueletoLista_ = function(n){
    n = Math.max(1, Math.min(8, n || 3));
    return '<div class="esqueleto" role="status" aria-label="Carregando">' + new Array(n + 1).join('<i></i>') + '</div>';
  };
  /* Vazio: texto + (opcional) botão de ação. acaoJs é o texto do onclick, ex.: "abrirFormModal('produtoNovoModal')". */
  window.estadoVazio_ = function(texto, botaoTxt, acaoJs){
    return '<div class="estado-vazio">' + esc(texto) +
      (botaoTxt && acaoJs ? '<br><button type="button" class="small-gold" onclick="' + esc(acaoJs) + '">' + esc(botaoTxt) + '</button>' : '') + '</div>';
  };
  /* Erro: texto + botão "Tentar de novo". */
  window.estadoErro_ = function(texto, acaoJs){
    return '<div class="estado-erro">' + esc(texto || 'Não foi possível carregar agora.') +
      (acaoJs ? '<br><button type="button" class="ghost" onclick="' + esc(acaoJs) + '">Tentar de novo</button>' : '') + '</div>';
  };

  /* Tabelas em cartões (celular): copia o título de cada coluna para o data-label das células.
     O CSS (estilo-base.css, "tab-cartoes") faz o resto; no computador continuam tabelas. */
  var TABELAS = ['vTable', 'despTable', 'hcTable'];
  function rotular(tbody, rotulos){
    Array.prototype.forEach.call(tbody.rows, function(tr){
      if(tr.classList.contains('empty-row')) return;
      Array.prototype.forEach.call(tr.cells, function(td, i){ td.setAttribute('data-label', rotulos[i] || ''); });
    });
  }
  function ligar(id){
    var tbody = document.getElementById(id); if(!tbody) return;
    var tabela = tbody.closest('table'); if(!tabela) return;
    tabela.classList.add('tab-cartoes');
    var rotulos = Array.prototype.map.call(tabela.querySelectorAll('thead th'), function(th){ return String(th.textContent || '').trim(); });
    rotular(tbody, rotulos);
    try{
      var t; new MutationObserver(function(){ clearTimeout(t); t = setTimeout(function(){ rotular(tbody, rotulos); }, 20); }).observe(tbody, { childList: true });
    }catch(e){}
  }
  function iniciar(){ TABELAS.forEach(ligar); }
  if(document.readyState === 'loading') document.addEventListener('DOMContentLoaded', iniciar); else iniciar();
})();
