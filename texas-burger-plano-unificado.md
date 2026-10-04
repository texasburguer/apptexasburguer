# Texas Burger — Plano Unificado

Junta em um só plano: (1) Migração Sheets → Supabase, (2) Complementos A (Backup/Restauração) e B (Fotos com escolha de destino) e (3) Refatoração do `index.html` em módulos.

## 1. Decisões que valem para todo o plano

- **Google Sheets não sai do sistema.** Ele continua como reserva.
- **Cascata de 3 níveis:** Supabase (principal) → planilha principal (assume se o Supabase falhar) → planilha de contingência (último recurso).
- **Planilhas sempre atualizadas**, em segundo plano, por fila. Se a planilha estiver fora do ar, a página continua funcionando.
- **Rápido e seguro:** a página nunca espera pela planilha; segredos só no servidor.
- **Sem risco de perda de dados:** a página ainda não está em uso, então dá para testar e refazer.
- **Ajuste em relação aos planos originais:** os planos diziam que a planilha seria só espelho de leitura. Como a planilha precisa **assumir** o sistema numa queda, ela mantém as ações de escrita do Apps Script e existe uma **reconciliação** quando o Supabase volta.

### Forma de trabalho

- **A IA implementadora entrega os arquivos ao final de cada etapa.** Você testa e só então libera a próxima. Nada de avançar duas etapas sem aprovação.
- **Cada entrega é uma versão guardada** (ex.: `v-etapa-03`), para você poder voltar a qualquer ponto.
- **Cada entrega vem com:** lista do que mudou, o que foi testado e o que você deve testar.
- **Tudo que é opcional ou tem mais de um caminho possível é perguntado a você antes de ser feito.** A IA implementadora não decide sozinha nem implementa "por padrão". Ela faz a pergunta no início da etapa em que o ponto aparece, com as opções, o que cada uma custa e uma recomendação, e espera sua resposta. A lista completa está na seção 7 (Decisões opcionais), e cada ponto vem marcado com **[PERGUNTAR]** na etapa correspondente.
- **Quando a IA espera uma resposta sua:** se a decisão bloqueia a etapa inteira, ela para e aguarda. Se bloqueia só um subitem, ela executa o resto da etapa e deixa o subitem marcado como **[AGUARDANDO RESPOSTA]**, sem decidir por você. Quem responde pelo projeto é você (se o dono também decidir, vocês alinham antes de responder à IA).
- **Marco de segurança antes da Etapa 11:** a versão aprovada ao fim da Etapa 10 é congelada como **"versão estável pré-modularização"**. A Etapa 11 só reorganiza o código, não muda o comportamento, então, se o resultado não ficar como você quer, **você simplesmente continua usando a versão da Etapa 10**. Nada do que foi construído antes (Supabase, cascata, backup, fotos) depende da modularização.

## 2. Arquitetura

| Nível | Quem | Papel |
|---|---|---|
| 1 | **Supabase** (Postgres, Auth, Storage, Realtime, Edge Functions) | Fonte principal de tudo |
| 2 | **Planilha principal** (Apps Script atual) | Espelho atualizado e reserva que assume |
| 3 | **Planilha de contingência** (segundo Apps Script) | Último recurso |

**Gravação:** página → Supabase → fila de sincronização (`fila_sync`) → planilha principal → contingência. Falha em um espelho só faz o item ficar na fila e ser tentado de novo.

**Leitura em queda:** Supabase (timeout curto) → planilha principal → contingência. Em modo reserva, vendas vão para uma fila local (IndexedDB) e são reconciliadas quando o Supabase voltar.

**Lógica sensível** (fechamento de caixa, estoque, restauração, upload de foto) roda em Edge Functions, não no navegador.

## 3. Etapas

### Etapa 0 — Mapeamento e decisões (sem código)

- Listar abas das planilhas, ações (`action`) chamadas pelo `index.html` e funções dos `.gs`.
- Separar dados transacionais (vendas, pedidos, caixa, estoque) de configuração (produtos, categorias, usuários).
- Definir o identificador único comum aos 3 sistemas (UUID).
- Levantar os **handlers inline** do HTML (`onclick=`, `onchange=`, `oninput=` etc.): no `index.html` atual são cerca de **364 `onclick` e 85 outros handlers**, todos chamando funções globais. Isso define como a Etapa 11 será feita (ver 11.0).
- **Entrega:** mapeamento aba → tabela e ação → função.

### Etapa 1 — Modelagem e segurança no Supabase

- Tabelas com UUID, `NUMERIC(10,2)` para valores, `TIMESTAMPTZ` para datas e ENUMs para status.
- Tabelas de apoio: `fila_sync`, `sistema` (configurações e flags; substitui a aba Configurações), `backups`, `auditoria`, `configuracoes_fotos`.
- Colunas de foto em `produtos` e `combos`: `foto_id_principal`, `foto_id_contingencia`, `foto_url_principal`, `foto_url_contingencia`, `foto_preferida` (principal / contingência / auto).
- RLS por perfil: Admin e Operador (acesso total), Garçom (lê produtos e mesas, insere vendas, sem deletar), Cozinha, Entregador (só as próprias entregas).
- Autenticação: Supabase Auth ou login atual. **[PERGUNTAR]** (ver seção 7).
- **Entrega:** SQL de criação + políticas de acesso.

### Etapa 2 — Migração dos dados e validação

- Script que lê as planilhas, trata formatos (moeda, datas, telefone e senha como texto) e insere no Supabase (tabelas "pai" antes das "filho").
- Fotos existentes: preencher `foto_id_principal` e `foto_preferida = principal`.
- Validar contagens e somas (vendas, estoque, caixa) entre planilha e Supabase.
- **Entrega:** script de migração + relatório de conferência.

### Etapa 3 — Camada de dados da página (núcleo)

- Trocar o `apiCall` por uma camada única com a ordem Supabase → planilha principal → contingência.
- Mesma interface para o resto do código, para não quebrar telas.
- Timeouts curtos, retry, idempotência (sem venda duplicada) e indicador de qual nível está ativo.
- Mover para Edge Functions as ações complexas (fechar caixa, estoque, cancelar venda).
- **Entrega:** `index.html` lendo e gravando no Supabase com fallback.

### Etapa 4 — Sincronização em segundo plano (núcleo)

- Processo que consome a `fila_sync` e envia em **lote** para a planilha principal e depois para a contingência (cuidado com a cota do Apps Script). **[PERGUNTAR]** se a contingência recebe contínuo ou em intervalos maiores.
- Tela em Administrador: status da fila, última sincronização de cada planilha, itens com erro, botão "Sincronizar agora".
- **Alerta de fila parada:** avisar o Admin quando a `fila_sync` passar de um número de itens ou ficar horas sem sincronizar (a divergência cresce quanto mais tempo a planilha fica sem atualizar, por exemplo por cota esgotada). **[PERGUNTAR]** os limites; sugestão: mais de 500 itens ou mais de 6 horas.
- **Entrega:** sincronização contínua com monitoramento.

### Etapa 5 — Modo reserva e reconciliação (núcleo)

- Regras de troca de nível (segundos sem resposta, falhas seguidas). **[PERGUNTAR]** os valores.
- Planilha principal pronta para assumir (dados em dia, ações compatíveis).
- Fila local no aparelho para vendas feitas em modo reserva.
- **Os três níveis fora do ar ao mesmo tempo:** a página entra em **modo offline** (IndexedDB), mostra um aviso claro e permite registrar vendas na fila local, que é enviada quando algum nível voltar. Funções que dependem de dados novos (ex.: pedidos do cardápio público, tempo real) ficam indisponíveis e isso deve ser sinalizado na tela.
- Reconciliação ao voltar: enviar ao Supabase sem duplicar nem perder.
- **Entrega:** teste de queda simulada (desligar Supabase, vender, religar, conferir).

### Etapa 6 — Tempo real e desempenho

- **[PERGUNTAR]** Supabase Realtime no lugar do polling (Pedidos e Cozinha hoje a cada 3 minutos), ou manter o polling. Botão Atualizar continua nos dois casos.
- Revisar carregamento inicial e cache do PWA (`sw.js`).
- **Entrega:** cozinha e pedidos atualizando sozinhos.

### Etapa 7 — Backup e restauração (Complemento A)

Três camadas:

| Camada | Frequência | Onde | Propósito |
|---|---|---|---|
| 1. Backup lógico (app) | Manual + 1x/dia | Supabase Storage (bucket privado) e, se você quiser, Drive **[PERGUNTAR]** | Restauração rápida pelo app |
| 2. Backup nativo do Supabase | 1x/dia, 7 dias | Infraestrutura Supabase | Emergência (não restaurável por API) |
| 3. Planilhas | Contínua (fila) | Drive do dono | Backup visual e reserva ativa |

- **Backup (Edge Function `criar-backup`):** lê as tabelas, gera `.json.gz`, salva no Storage, registra em `backups` (tipo Manual / Automático / Pré-restauração). Backup automático diário, retenção, horário e ferramenta de agendamento (`pg_cron` ou GitHub Actions) **[PERGUNTAR]**; sugestão: 1x/dia às 4h, últimos 7.
- **Restauração (`restaurar-backup`):** exige senha do Admin; cria backup "pré-restauração" (se falhar, cancela); ativa flag de manutenção em `sistema`; restaura em **uma única transação**; preserva usuários, auditoria e backups; registra na auditoria.
- Backup inclui as colunas e tabelas de foto.
- Estimativa: ~2 a 5 MB por backup, ~35 MB com 7 backups (bem abaixo do limite gratuito).
- **Entrega:** "Fazer backup agora", lista de backups e "Restaurar" funcionando.

### Etapa 8 — Fotos com escolha de destino (Complemento B)

- **Upload (`upload-foto`):** valida a imagem (JPG/PNG/WEBP, até 5 MB) e envia para Drive principal, Drive da contingência ou ambos, via Service Account com credenciais em secrets. `remover-foto` e `sincronizar-fotos` completam o conjunto.
- Onde guardar as fotos (só Drives, só Supabase Storage, ou os dois) **[PERGUNTAR]**.
- **Modal "Onde salvar esta foto?"**: Principal / Contingência / Ambos, com "Lembrar minha escolha". Indicadores na listagem: 🟢 principal, 🔵 contingência, 🟣 ambos, ⚠️ quebrada.
- **Editar foto existente:** Substituir / Mover para outro Drive / Remover.
- **Cardápio público:** usa a foto preferida e troca para a outra se der erro (`onerror` ou timeout de 3 s). O PWA guarda no cache as duas versões quando houver.
- **Decisões do Admin (tela Administrador → Armazenamento → Fotos), salvas em `configuracoes_fotos`:**
  - Drive preferido para exibição (Principal / Contingência / Automático).
  - Destino padrão no upload (Principal / Contingência / Ambos / Perguntar sempre).
  - Histórico de fotos (`fotos_historico`) ligado ou desligado.
  - Sincronização entre drives: semanal, manual ou desligada.
  - Backup frio das fotos no Supabase Storage: semanal ou desligado.
  - Replicar fotos antigas para a contingência: todas, só de produtos ativos ou nenhuma.
- Permissões: Admin e Operador escolhem o destino; os demais só visualizam.
- **Entrega:** upload, fallback e tela de configuração de fotos.

### Etapa 9 — Operação contínua (plano gratuito)

- **Ping a cada 2 dias** (e não 3) para o Supabase não pausar após 7 dias sem uso: com 2 dias, ainda sobra margem se dois pings seguidos falharem. Ferramenta: UptimeRobot, cron-job.org ou GitHub Actions **[PERGUNTAR]**.
- **[PERGUNTAR]** Alerta se Supabase ou planilhas pararem de responder: por e-mail, Telegram, WhatsApp ou nenhum.
- Conferência periódica Supabase x planilhas (totais batem?).
- Se pausar: "Restore project" no painel (1 a 2 minutos).
- **Alerta de espaço do banco (limite de 500 MB):** aviso automático ao passar de 70% e de 90%, com ação sugerida em cada nível (limpar backups antigos, comprimir fotos, arquivar vendas antigas). **[PERGUNTAR]** os percentuais e como quer ser avisado.
- **Entrega:** monitoramento ativo.

### Etapa 10 — Testes e virada

- Roteiro: login por perfil, venda completa, cancelamento, fechamento de caixa, pedido do cardápio público, pedido de mesa, cozinha, entrega, backup e restauração, upload de foto.
- Testes de falha: Supabase fora, planilha principal fora, ambas fora, internet do aparelho caindo, restauração interrompida.
- Teste de permissão: Operador tentando restaurar backup deve ser bloqueado.
- **[PERGUNTAR] Teste de carga simulada (opcional):** várias vendas em sequência rápida, para ver se a fila drena e o sistema continua responsivo. Para o movimento de um restaurante pode ser dispensável.
- Como a página não está em uso, a virada é direta: apontar o `index.html` para o Supabase e desativar o fluxo antigo.
- **Entrega:** checklist de testes aprovado.

### Etapa 10.5 — Atualizar o mapeamento antes da modularização

- Só acontece se você escolher fazer a Etapa 11.
- Refazer o mapeamento de funções, variáveis globais e handlers inline sobre a **versão estável pré-modularização**, porque o `api.js` (Etapa 3), o `backup.js` (Etapa 7) e a tela de fotos (Etapa 8) já terão mudado o código.
- Conferir de novo a contagem de handlers inline (`onclick=` e similares).
- Congelar e guardar a versão estável (ponto de retorno).
- **Entrega:** mapeamento atualizado, aprovado por você antes de qualquer arquivo ser movido.

### Etapa 11 — Refatoração do `index.html` em módulos (por último) — **[PERGUNTAR]** se quer fazer

**Objetivo:** reduzir o `index.html` (milhares de linhas) a um arquivo enxuto só com a estrutura, separando CSS, HTML e JavaScript por responsabilidade e por domínio, **sem quebrar nenhuma funcionalidade**.

**Marco de segurança:** esta etapa parte da "versão estável pré-modularização" (fim da Etapa 10). Se o resultado não ficar como você quer, volta-se a essa versão sem perda nenhuma. A IA entrega os arquivos ao final de **cada subetapa** (11.2, 11.3...), cada uma com seu ponto de retorno.

**Regras de ouro**

1. **Incremental:** extrair um módulo, testar, validar e só então ir para o próximo. Nunca mover tudo de uma vez.
2. **Git:** commit antes de cada extração; se quebrar, reverte e tenta de novo.
3. **Testar a cada passo:** abrir a página e testar a funcionalidade correspondente.
4. **Não misturar refatoração com feature nova:** só mover, sem "melhorar" no meio.
5. **Ordem:** sempre do que tem menos dependências para o que tem mais (CSS → utils → config → state → API → UI → módulos → main).

**Observação sobre a migração:** quando esta etapa começar, o `api.js` já será a camada de dados criada na Etapa 3 (Supabase → planilha principal → contingência), e o `backup.js` já terá backup/restauração da Etapa 7 e a tela de fotos da Etapa 8. Alguns nomes de função abaixo podem ter mudado até lá; o mapeamento da Etapa 0 deve ser atualizado antes de começar.

#### 11.0 — Decisão sobre handlers inline (obrigatória antes de começar)

Hoje o `index.html` é um único `<script>` clássico de ~10.000 linhas, sem `type="module"`. Os botões chamam funções globais direto no HTML (`onclick="salvarCliente()"`). Com módulos (`<script type="module">`), **as funções deixam de ser globais e esses botões param de funcionar**. Há duas saídas; a IA implementadora deve escolher uma e aplicá-la em todo o projeto:

- **[PERGUNTAR]** Qual opção usar. A recomendação da IA é a A, mas a decisão é sua.
- **Opção A (recomendada): expor na `window`.** Cada módulo exporta suas funções e o `main.js` as registra em `window` (ex.: `Object.assign(window, { salvarCliente, ... })`). O HTML quase não muda, o risco é baixo e dá para fazer módulo por módulo.
- **Opção B: trocar por `addEventListener`.** Mais limpa, mas exige reescrever ~450 pontos do HTML e aumenta o risco de quebrar botões. Só se você escolher.

Regra: **a cada módulo extraído, todas as funções chamadas por handlers inline precisam estar acessíveis.** Validar clicando nos botões do módulo, não só abrindo a tela.

#### 11.1 — Preparação e diagnóstico

- **Mapear dependências:** quais funções chamam quais (ex.: `renderCarrinho()` → `atualizarPreviewDesconto()` → `totalCarrinho()`); quais variáveis globais são usadas em vários módulos (`currentUser`, `carrinhoAtual`, `vendas`, `produtos`); quais funções são de uso exclusivo de um módulo; **quais funções são chamadas por handlers inline do HTML** (essas precisam ficar acessíveis, ver 11.0).
- **Definir a estrutura de pastas:**

```
/
├── index.html            (enxuto)
├── css/
│   ├── base.css          (variáveis, reset, tipografia)
│   ├── layout.css        (header, grids, containers)
│   └── componentes.css   (botões, modais, cards, tabelas)
├── js/
│   ├── config.js         (constantes globais)
│   ├── utils.js          (funções auxiliares puras)
│   ├── state.js          (estado global da aplicação)
│   ├── api.js            (comunicação com backend)
│   ├── ui.js             (funções visuais genéricas)
│   ├── modulos/
│   │   ├── auth.js          (login, sessão, usuários)
│   │   ├── clientes.js      (CRUD de clientes)
│   │   ├── produtos.js      (produtos, combos, adicionais)
│   │   ├── estoque.js       (ingredientes e movimentações)
│   │   ├── caixa.js         (abertura, fechamento, venda)
│   │   ├── cozinha.js       (tela da cozinha, preparo)
│   │   ├── pedidos.js       (pedidos, entregas, mesas)
│   │   ├── cardapio.js      (cardápio digital público)
│   │   ├── financeiro.js    (despesas, DRE, contas)
│   │   ├── relatorios.js    (visão geral, relatórios)
│   │   ├── backup.js        (backup, contingência)
│   │   ├── notificacoes.js  (mural de avisos)
│   │   ├── qrcode.js        (gerador de QR Code)
│   │   └── admin.js         (Administrador geral)
│   └── main.js           (ponto de entrada, inicialização)
├── manifest.webmanifest
├── sw.js
└── icons/
```

#### 11.2 — Extrair o CSS

- Copiar todo o conteúdo do `<style>` e dividir em `base.css`, `layout.css` e `componentes.css`.
- No `<head>`, trocar o `<style>` por 3 tags `<link rel="stylesheet">`.
- **Validar:** visual idêntico e sem erros de CSS no console.

#### 11.3 — Criar o `state.js` (o mais crítico)

- Identificar **todas** as variáveis globais soltas no script (`currentUser`, `clientes`, `produtos`, `vendas`, `carrinhoAtual`, `sessaoCaixa`, etc.) e agrupá-las num objeto único `AppState`.
- Criar funções de acesso controlado (`getState()`, `setState()`, `updateState()`), para nenhum módulo alterar o estado diretamente.
- **Compatibilidade temporária:** manter variáveis globais apontando para o `AppState` (ex.: `let currentUser = AppState.currentUser`) para o código antigo continuar funcionando durante a transição.
- **Validar:** login, adicionar item ao carrinho e conferir se o `AppState` atualiza.

#### 11.4 — Extrair configurações e utilitários

- **`config.js`:** `API_URL`, `CONTINGENCIA_API_URL`, `CONTINGENCIA_CHAVE_PUBLICA`; constantes (`QTD_MAX_ITEM_`, `SYNC_INTERVALO_MS`, `FILA_MAX_TENTATIVAS`, etc.); listas fixas (`ADMIN_GRUPOS`, `NOTIF_EVENTOS_UI_`, `CATEGORIAS_DESPESA_PADRAO`, etc.).
- **`utils.js`** (funções puras, sem depender de estado): `formatarMoeda`, `escH`, `numPlanilha_`, `normTel`, `dataLocalISO`, `parseDataBR`, `arred2`, `fmtPct`, `pctDe`, `idemHash_`, `novaRequisicao_`, etc.
- **Validar:** formatação de valores, cadastro de cliente (usa `normTel`), exibição de datas.

#### 11.5 — Extrair a camada de API (`api.js`)

- **Comunicação:** `apiCall`, `_apiCallRaw`, `postApi_`, `fetchContingencia_`, `apiCallFila`.
- **Timeout, retry e idempotência:** `idemChave_`, `idemId_`, `idemLimpar_`.
- **Fila:** `filaSalvar_`, `filaEnviarItem_`, `filaProcessar`.
- **Contingência:** `emergenciaTentarEntrar_`, `emergenciaVigiar_`.
- Depende de `state.js` (token atual) e `config.js` (URLs); exporta `apiCall` para os módulos.
- **Validar:** login, carregamento de dados (`getAll`), envio de uma venda.

#### 11.6 — Extrair a UI genérica (`ui.js`)

- **Visuais reutilizáveis:** `showMsg`, `abrirFormModal`, `fecharFormModal`, `copiarTextoComFallback`, `_carregandoInicio_`, `_carregandoFim_`, `mostrarNotificacao_`, `somAlerta_`, `tocarAlertaNovaEntrega`, `atualizarTelaLigadaUI_`.
- **Renderização genérica** (as que não são de um módulo específico): `renderClientes`, `renderProdutos`, `renderCombos`.
- **Validar:** abrir e fechar modais, mensagens de sucesso/erro, alertas sonoros.

#### 11.7 — Extrair os módulos de domínio, um por um

Do mais independente ao mais complexo:

1. **`qrcode.js`:** `QR_`, `abrirQrMesas`, `renderQrPreview_`, `imprimirPlacasQr_`. *Validar:* gerar QR Code de uma mesa.
2. **`clientes.js`:** `salvarCliente`, `excluirCliente`, `abrirPerfilCliente`, `renderHistoricoCliente`, `adicionarMarcaModal`, `resgatarPremioModal`, `abrirModalIndicado`, `salvarNovoIndicado`. *Validar:* cadastrar, editar, excluir, ver histórico.
3. **`produtos.js`:** `registrarProduto`, `editarProduto`, `excluirProduto`, `registrarCombo`, `editarCombo`, `excluirCombo`, `registrarAdicional`, `registrarCategoria`, `vincularAdicionaisCategorias`, `renderProdutos`, `renderCombos`, `renderAdicionais`, `renderCategorias`, `uploadFotoProduto`, `uploadFotoCombo`. *Validar:* cadastrar produto, editar preço, enviar foto, criar combo.
4. **`estoque.js`:** `registrarIngrediente`, `editarEstoquePrompt`, `registrarEntradaEstoque`, `registrarPerdaEstoque`, `registrarInventarioEstoque`, `renderEstoque`, `renderMovimentacoesEstoque`, `salvarBloqueioEstoque`. *Validar:* cadastrar ingrediente, lançar entrada, ver movimentações.
5. **`caixa.js` (o mais complexo):** `abrirCaixa`, `fecharCaixa`, `iniciarVenda`, `adicionarItemCarrinho`, `renderCarrinho`, `renderPagamentos`, `finalizarVenda`, `finalizarVendaConfirmada`, `venderEmContingencia_`, `abrirModalCancelar`, `confirmarCancelamento`, `editarVenda`, `renderStatusCaixa`, `renderLancamentos`, `recalcularCarrinhoPorFormasSelecionadas`, e a lógica de mesa (`fecharContaMesaUI`, `confirmarFecharConta`, `liberarMesaSemConta_`). *Validar:* abrir caixa, venda completa (item + pagamento + finalizar), cancelar venda, fechar caixa.
6. **`pedidos.js`:** `renderPedidos`, `renderEntregas`, `avancarPedido`, `aceitarPedidoUI`, `rejeitarPedidoUI`, `suspenderPedidoUI`, `retomarPedidoUI`, `atribuirEntregador`, `confirmarRecebimento`, `renderMesasPopup_`, `atualizarMesasPopup_`, `imprimirEntregaPedido`, `botaoAvisarCliente_`, `botaoEnviarEntregador_`. *Validar:* ver pedidos, aceitar, avançar status, atribuir entregador, fechar mesa.
7. **`cozinha.js`:** `renderCozinha`, `cozinhaIniciar`, `imprimirComandaPedido`, `imprimirNovosCozinha`, `cardCozinha_`, detector (`iniciarDetectorCozinha`, `detectarNovosCozinha_`), `manterTelaLigada_`. *Validar:* ver pedidos na cozinha, iniciar preparo, marcar como pronto.
8. **`cardapio.js`:** `carregarCardapioPublico`, `renderCdCategorias`, `renderCdSecoes`, `abrirCdItemModal`, `abrirCarrinhoPublico`, `finalizarPedidoPublico`, `finalizarPedidoMesa_`, `abrirFeedbackPublico`, `enviarFeedbackPublico`, `abrirAcompanhamentoPedido`, `mostrarBotaoWhatsappPedido`, `cdMostrarConfirmacaoPedido_`. *Validar:* abrir cardápio, adicionar item, finalizar pedido, ver acompanhamento.
9. **`financeiro.js`:** `abrirModalDespesa`, `salvarDespesaModal`, `abrirModalContaPagar`, `pagarDespesa`, `abrirModalRecorrente`, `gerarContasDoMes`, `renderDespesas`, `renderContasPagar`, `renderDespesasRecorrentes`, `renderResumoPrevisto`, `renderFluxoPrevisto`, `registrarAjusteUI`, `cancelarAjusteUI`, `renderAjustes`. *Validar:* lançar despesa, pagar conta, ver previsto x pago.
10. **`relatorios.js`:** `gerarRelatorio`, `renderizarGrafico`, `renderDRE`, `calcularDRE`, `renderVisaoGeral`, `renderRelatorio`, `renderDesempenhoEntregas`, `copiarRel`, `whatsappRel`, `imprimirRelatorio`. *Validar:* DRE de um mês, gráfico, imprimir relatório.
11. **`backup.js`:** `fazerBackupAgora`, `restaurarBackupUI`, `carregarStatusBackup`, `salvarBackupAutomatico`, `carregarArmazenamento`, `sincronizarContingenciaUI`, `reconciliarContingenciaUI`, `carregarStatusContingencia`, `conferirIntegridadeUI`. *Validar:* fazer backup, ver histórico, conferir integridade.
12. **`notificacoes.js`:** `renderNotificacoes`, `renderConfigNotificacoes`, `salvarConfigNotificacoesUI`, `toggleResgateNotif`, `renderFeedbacks`, `setFiltroFeedbacks`, `alterarStatusFeedback`, `renderOcorrencias`, `abrirModalOcorrencia`, `confirmarOcorrencia`, `abrirGerirOcorrencia`, `confirmarGerirOcorrencia`. *Validar:* ver mural, marcar feedback como visto, registrar ocorrência.
13. **`auth.js`:** `tentarLogin`, `entrarNoApp`, `sair`, `abrirModalTrocarSenha`, `confirmarTrocarSenha`, `criarUsuarioApp`, `editarUsuarioPrompt`, `confirmarEditarUsuario`, `excluirUsuarioPrompt`, `renderUsuarios`, `carregarSessoes_`, `renderSessoes_`, `encerrarSessaoRemotaUI_`, `abrirModalSenhaAdmin`, `confirmarSenhaAdminGenerica`, `aplicarPermissoesNivel`. *Validar:* login, logout, criar e editar usuário, ver sessões ativas.
14. **`admin.js`:** `abrirAdministrador`, `montarBarrasAdmin_`, `renderConfigCardapio`, `salvarConfigCardapioUI`, `renderCuponsUI`, `salvarCupomUI`, `alternarCupomUI`, `renderEventosUI`, `salvarEventoUI`, `cancelarEventoUI`, `renderLog`, `renderConfigNotificacoes`. *Validar:* navegar pelas sub-abas do Administrador e salvar configurações.

#### 11.8 — Extrair o `main.js` (ponto de entrada)

- Mover a inicialização: `init()`, `renderizarTudo()`, `configurarSincronizacaoAutomatica()`, `sincronizarEmSegundoPlano()`, `setConexaoStatus`, `atualizarBloqueioVendaOffline`.
- Registro do Service Worker, restauração de sessão (`tentarRestaurarSessao`), instalação do PWA (`instalarApp`, `adiarInstalarApp`), olhinho da senha, QR Code do app, etc.
- O `main.js` é o único arquivo que importa todos os módulos e chama `init()` no final.
- **Validar:** abrir a página, fazer login, ver se tudo renderiza.

#### 11.9 — Ajustar o `index.html`

- Manter só a estrutura semântica (divs, sections, modais), os `<link>` de CSS no `<head>` e `<script type="module" src="js/main.js">` no fim do `<body>`.
- Todos os IDs usados pelos módulos continuam no HTML (ex.: `#carrinhoLista`, `#pagamentosLista`, `#loginUsuario`).
- **Validar:** visual e funcionalidade idênticos ao original.

#### 11.10 — Testes finais

- **Smoke test:** login como Admin, Operador, Garçom, Cozinha e Entregador; cadastrar cliente, produto, combo e ingrediente; abrir caixa, vender, cancelar, fechar; pedidos na cozinha, avançar status, atribuir entregador; cardápio público e pedido; DRE e impressão; backup e restauração; contingência (desligar a internet e tentar vender).
- **Console:** sem erros e sem avisos de dependência circular.
- **Desempenho:** carregar em menos de 2 segundos; service worker funcionando offline (incluir os novos CSS e JS no cache do `sw.js` e **subir a versão do cache**, senão aparelhos antigos ficam com a versão velha).

#### 11.11 — Documentação

- `README.md`: estrutura de pastas, como os módulos se comunicam e como adicionar uma funcionalidade nova.
- Comentário de cabeçalho em cada `.js` explicando sua responsabilidade.

**Entrega:** estrutura modular com o mesmo comportamento do `index.html` original.

## 4. Ordem e dependências

```
0 Mapeamento → 1 Supabase → 2 Migração → 3 Camada de dados
  → 4 Sync em 2º plano → 5 Modo reserva → 6 Tempo real
  → 7 Backup → 8 Fotos → 9 Operação → 10 Testes/virada → 10.5 Mapeamento → 11 Modularização
```

As etapas **3, 4 e 5** são o núcleo da sua ideia (Supabase principal, planilhas assumindo, atualização em segundo plano) e devem ser fechadas antes das demais.

## 5. De onde veio cada parte

| Plano original | Onde entrou |
|---|---|
| Migração, Fases 1 e 2 (modelagem, dados) | Etapas 1 e 2 |
| Migração, Fase 3 (front-end, tempo real, Edge Functions) | Etapas 3 e 6 |
| Migração, Fases 4 e 5 (Sheets e contingência) | Etapas 4 e 5, adaptadas para a cascata |
| Migração, Fases 6 e 7 (cutover, ping) | Etapas 10 e 9 |
| Complemento A (backup) | Etapa 7 |
| Complemento B (fotos) | Etapa 8 e colunas na Etapa 1 |
| Refatoração modular (fases 1 a 11 do plano original, com todas as funções por módulo) | Etapa 11 (subetapas 11.1 a 11.11) |

## 6. Riscos e cuidados

- **Cota do Apps Script:** sincronizar sempre em lote.
- **Planilha muito atrasada:** se a `fila_sync` ficar parada por muito tempo (cota, por exemplo), a divergência cresce; por isso o alerta da Etapa 4.
- **Divergência de dados:** fluxo normal de mão única (Supabase → planilhas); o caminho inverso só existe na reconciliação e precisa de teste.
- **Telefone e senha numéricos:** manter colunas como texto nas planilhas.
- **Segredos:** chaves do Supabase service role, Service Account e chaves da contingência só no servidor.
- **Handlers inline x módulos:** sem tratar o ponto 11.0, os botões quebram na Etapa 11.
- **Cache do service worker:** a cada entrega que muda arquivos, subir a versão do cache do `sw.js`.
- **Plano gratuito:** pausa por inatividade e limite de 500 MB de banco e 1 GB de Storage; acompanhar o uso.
- **Backup sem teste de restauração não vale:** a Etapa 10 inclui restaurar de verdade.

## 7. Decisões opcionais (a IA pergunta a você antes de fazer)

Regra: **nada desta lista é implementado sem a sua resposta.** Se você não responder, a etapa (ou o subitem, se o resto puder andar) fica parada, marcada como **[AGUARDANDO RESPOSTA]**.

| Etapa | Decisão | Opções |
|---|---|---|
| 1 | Autenticação | Supabase Auth ou manter o login atual |
| 4 | Frequência da sincronização da contingência | Contínua ou em intervalos maiores (economiza cota) |
| 4 | Limites do alerta de fila parada | Sugestão: 500 itens ou 6 horas |
| 5 | Regra de troca de nível | Segundos sem resposta e número de falhas antes de usar a planilha principal |
| 6 | Tempo real | Supabase Realtime ou manter o polling de 3 minutos |
| 7 | Backup lógico: cópia extra no Drive | Sim ou não |
| 7 | Backup automático: horário, retenção e agendador | Sugestão: 1x/dia às 4h, últimos 7; `pg_cron` ou GitHub Actions |
| 8 | Onde guardar as fotos | Só Drives, só Supabase Storage ou ambos |
| 8 | Destino padrão do upload | Principal, Contingência, Ambos ou Perguntar sempre |
| 8 | Drive preferido para exibição | Principal, Contingência ou Automático |
| 8 | Histórico de fotos (`fotos_historico`) | Ligado ou desligado |
| 8 | Sincronização de fotos entre drives | Semanal, manual ou desligada |
| 8 | Backup frio das fotos no Supabase Storage | Semanal ou desligado |
| 8 | Fotos antigas na contingência | Replicar todas, só de produtos ativos ou nenhuma |
| 9 | Ferramenta do ping anti-pausa | UptimeRobot, cron-job.org ou GitHub Actions |
| 9 | Alerta de espaço do banco | Sugestão: avisos aos 70% e 90% |
| 9 | Alertas de queda | E-mail, Telegram, WhatsApp ou nenhum |
| 10 | Teste de carga simulada | Fazer ou dispensar |
| 11 | Fazer a modularização | Sim ou não (a versão da Etapa 10 já fica guardada) |
| 11 | Handlers inline | Opção A (expor na `window`) ou B (`addEventListener`) |

Se surgir qualquer outro ponto opcional durante a implementação, a regra vale do mesmo jeito: pergunta primeiro.
