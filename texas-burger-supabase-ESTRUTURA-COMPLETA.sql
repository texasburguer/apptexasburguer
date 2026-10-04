-- =====================================================================
-- TEXAS BURGER — ESTRUTURA COMPLETA DO SUPABASE (até a Etapa 3c-3b (financeiro ligado à página; sem mudança no banco nesta entrega))
-- Tabelas, regras (RLS), visões, funções api_* e correções de segurança, na ordem certa.
-- NÃO contém dados (cadastros/usuários/vendas): os dados estão no projeto; backup = Etapa 7.
-- Para recriar do zero: rode este arquivo e depois 01_cadastros.sql + 02_usuarios.sql + 03_conferencia.sql.
-- =====================================================================


-- >>>>>>>>>> 01_tabelas.sql <<<<<<<<<<
-- =====================================================================
-- Texas Burger — Etapa 1 (parte 1/2): tipos, tabelas, índices e gatilhos
-- Rodar no Supabase: SQL Editor → colar → Run. Rodar ANTES do 02_seguranca_rls.sql.
-- Pode ser rodado em projeto vazio. Para refazer do zero: apagar o schema public
-- (só vale enquanto a página não está em uso).
-- Regras: UUID em tudo · valores em NUMERIC(10,2) · datas em TIMESTAMPTZ · status em ENUM.
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- 1. ENUMs (valores idênticos aos usados hoje na planilha/app)
-- ---------------------------------------------------------------------
create type nivel_acesso     as enum ('Admin','Operador','Garçom','Cozinha','Entregador');
create type venda_status     as enum ('Confirmada','Cancelada');
create type venda_tipo       as enum ('Retirada','Entrega','Mesa');
create type status_pedido    as enum ('Recebido','Em preparo','Pronta','Saiu para entrega','Entregue','Retirada','Servida','Suspenso');
create type status_pagamento as enum ('Pago','A Receber');
create type origem_venda     as enum ('Balcão','Cardápio','Garçom');
create type status_mesa      as enum ('Livre','Ocupada','Aguardando fechamento','Fechada','Bloqueada/Manutenção');
create type tipo_mov_estoque as enum ('Entrada','Venda','Saída','Perda','Ajuste','Inventário');
create type unidade_estoque  as enum ('un','g','kg','ml','l');
create type status_caixa     as enum ('Aberto','Fechado');
create type status_despesa   as enum ('Paga','A pagar','Cancelada');
create type status_ocorrencia as enum ('Aberta','Em andamento','Resolvida');
create type status_indicacao as enum ('Pendente','Resgatado');
create type tipo_backup      as enum ('Manual','Automático','Pré-restauração');
create type foto_preferida   as enum ('principal','contingencia','auto');
create type op_sync          as enum ('INSERT','UPDATE','DELETE');

-- ---------------------------------------------------------------------
-- 2. Usuários (ligados ao Supabase Auth)
--    O login do app ("joao") vira o e-mail "joao@usuarios.texasburger.app" no Auth.
--    A senha NÃO fica nesta tabela: o Auth guarda o hash.
-- ---------------------------------------------------------------------
create table usuarios (
  id         uuid primary key references auth.users(id) on delete cascade,
  login      text not null unique,
  nome       text not null,
  telefone   text,                         -- sempre texto
  nivel      nivel_acesso not null,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. Cadastros
-- ---------------------------------------------------------------------
create table clientes (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  telefone text,
  data_nascimento date,
  endereco text,
  como_conheceu text,
  primeiro_contato timestamptz,
  observacoes text,
  criado_em timestamptz not null default now()
);
create unique index clientes_telefone_uq on clientes (telefone) where telefone is not null and telefone <> '';

create table formas_pagamento (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  ativa boolean not null default true,
  visivel_cardapio boolean not null default true,
  taxa_percentual numeric(5,2) not null default 0,
  taxa_fixa numeric(10,2) not null default 0,
  prazo_dias integer not null default 0,
  permite_troco boolean not null default false,
  ordem integer not null default 0
);

create table categorias (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  ativa boolean not null default true,
  ordem integer not null default 0
);

create table estoque (               -- ingredientes
  id uuid primary key default gen_random_uuid(),
  ingrediente text not null,
  quantidade numeric(12,3) not null default 0,
  quantidade_minima numeric(12,3) not null default 0,
  unidade unidade_estoque not null default 'un',
  custo_unitario numeric(10,4) not null default 0,   -- custo por unidade pode ter mais casas
  status text
);

create table produtos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  descricao text,
  categoria_id uuid references categorias(id) on delete set null,
  ativo boolean not null default true,
  destaque boolean not null default false,
  estoque_proprio_ingrediente_id uuid references estoque(id) on delete set null,
  ordem_cardapio integer not null default 0,
  -- fotos (Complemento B). foto_preferida só decide a exibição; escolhas ficam para a Etapa 8
  foto_id_principal text,
  foto_id_contingencia text,
  foto_url_principal text,
  foto_url_contingencia text,
  foto_preferida foto_preferida not null default 'principal'
);

create table combos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  categoria_id uuid references categorias(id) on delete set null,
  ativo boolean not null default true,
  destaque boolean not null default false,
  ordem_cardapio integer not null default 0,
  foto_id_principal text,
  foto_id_contingencia text,
  foto_url_principal text,
  foto_url_contingencia text,
  foto_preferida foto_preferida not null default 'principal'
);

create table produto_precos (
  id uuid primary key default gen_random_uuid(),
  produto_id uuid not null references produtos(id) on delete cascade,
  forma_pagamento_id uuid not null references formas_pagamento(id) on delete cascade,
  preco numeric(10,2) not null default 0,
  custo numeric(10,2) not null default 0,
  unique (produto_id, forma_pagamento_id)
);

create table combo_precos (
  id uuid primary key default gen_random_uuid(),
  combo_id uuid not null references combos(id) on delete cascade,
  forma_pagamento_id uuid not null references formas_pagamento(id) on delete cascade,
  preco numeric(10,2) not null default 0,
  custo numeric(10,2) not null default 0,
  unique (combo_id, forma_pagamento_id)
);

create table combo_itens (
  id uuid primary key default gen_random_uuid(),
  combo_id uuid not null references combos(id) on delete cascade,
  produto_id uuid not null references produtos(id) on delete restrict,
  quantidade integer not null default 1 check (quantidade > 0)
);

create table produto_ingredientes (
  id uuid primary key default gen_random_uuid(),
  produto_id uuid not null references produtos(id) on delete cascade,
  ingrediente_id uuid not null references estoque(id) on delete restrict,
  quantidade_por_unidade numeric(12,3) not null default 0
);

create table adicionais (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  preco numeric(10,2) not null default 0,
  ativo boolean not null default true,
  ingrediente_id uuid references estoque(id) on delete set null,   -- baixa de estoque
  quantidade_descontar numeric(12,3) not null default 0
);

create table produto_adicionais (
  id uuid primary key default gen_random_uuid(),
  produto_id uuid not null references produtos(id) on delete cascade,
  adicional_id uuid not null references adicionais(id) on delete cascade,
  unique (produto_id, adicional_id)
);

create table promocoes (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  tipo text,
  regra_duplicidade text,
  beneficio text,
  ativa boolean not null default true
);

create table cupons (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  nome text,
  tipo text not null default 'percentual',
  valor numeric(10,2) not null default 0,
  frete_gratis boolean not null default false,
  data_inicio date,
  data_fim date,
  hora_inicio time,
  hora_fim time,
  limite_total integer not null default 0,
  limite_por_cliente integer not null default 1,
  valor_minimo numeric(10,2) not null default 0,
  ativa boolean not null default true,
  acumula boolean not null default false,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id) on delete set null
);

create table mesas (
  id uuid primary key default gen_random_uuid(),
  numero text not null unique,
  status status_mesa not null default 'Livre',
  capacidade integer,
  observacao text,
  garcom_responsavel_id uuid references usuarios(id) on delete set null,
  -- chamados: hoje ficam em Configurações (JSON); aqui viram colunas
  chamado_tipo text,                      -- 'garcom' | 'conta' | null
  chamado_em timestamptz
);

-- Segredo do QR de cada mesa, em tabela à parte: só Edge Function lê (RLS sem política = ninguém do app lê).
-- Fica FORA da fila de sincronização de propósito (ver nota no README: como a planilha valida QR em modo reserva).
create table mesas_codigos (
  mesa_id uuid primary key references mesas(id) on delete cascade,
  codigo text not null,
  gerado_em timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 4. Caixa e entregas
-- ---------------------------------------------------------------------
create table caixa_sessoes (
  id uuid primary key default gen_random_uuid(),
  abertura timestamptz not null default now(),
  fundo_caixa numeric(10,2) not null default 0,
  fechamento timestamptz,
  total_vendas numeric(10,2),
  total_despesas numeric(10,2),
  saldo_final numeric(10,2),
  status status_caixa not null default 'Aberto',
  usuario_abertura uuid references usuarios(id) on delete set null,
  usuario_fechamento uuid references usuarios(id) on delete set null,
  valor_contado numeric(10,2),
  diferenca numeric(10,2)
);
-- só pode existir UM caixa aberto por vez
create unique index caixa_um_aberto_uq on caixa_sessoes ((status)) where status = 'Aberto';

create table fechamentos_entrega (
  id uuid primary key default gen_random_uuid(),
  data_ref date not null,
  entregador_id uuid references usuarios(id) on delete set null,
  qtd_entregas integer not null default 0,
  total_taxas numeric(10,2) not null default 0,
  ajuda_diaria numeric(10,2) not null default 0,
  total_devido numeric(10,2) not null default 0,
  valor_pago numeric(10,2) not null default 0,
  diferenca numeric(10,2) not null default 0,
  fechado_em timestamptz not null default now(),
  fechado_por uuid references usuarios(id) on delete set null,
  observacao text,
  requisicao_id text unique
);

-- ---------------------------------------------------------------------
-- 5. Vendas
-- ---------------------------------------------------------------------
create sequence vendas_numero_pedido_seq;

create table vendas (
  id uuid primary key default gen_random_uuid(),
  numero_pedido integer not null default nextval('vendas_numero_pedido_seq'),
  data_hora timestamptz not null default now(),
  cliente_id uuid references clientes(id) on delete set null,
  cliente_nome text,
  telefone_cliente text,
  forma_pagamento text,
  valor_total numeric(10,2) not null default 0,
  custo_total numeric(10,2) not null default 0,
  status venda_status not null default 'Confirmada',
  motivo_cancelamento text,
  tipo venda_tipo not null default 'Retirada',
  status_pedido status_pedido,
  endereco text,
  complemento text,
  referencia text,
  observacoes_entrega text,
  pronta_em timestamptz,
  concluida_em timestamptz,
  status_pagamento status_pagamento not null default 'Pago',
  recebido_em timestamptz,
  valor_original numeric(10,2),
  valor_desconto numeric(10,2) not null default 0,
  desconto_detalhe text,
  entregador_id uuid references usuarios(id) on delete set null,
  saiu_em timestamptz,
  origem origem_venda not null default 'Balcão',
  mesa_id uuid references mesas(id) on delete set null,
  taxa_entrega numeric(10,2) not null default 0,
  fechamento_entrega_id uuid references fechamentos_entrega(id) on delete set null,
  registrado_por uuid references usuarios(id) on delete set null,
  inicio_preparo_em timestamptz,
  caixa_id uuid references caixa_sessoes(id) on delete set null,
  requisicao_id text unique                   -- idempotência: mesma requisição não vira 2 vendas
);
create index vendas_data_idx        on vendas (data_hora desc);
create index vendas_status_pedido_idx on vendas (status_pedido) where status = 'Confirmada';
create index vendas_telefone_idx    on vendas (telefone_cliente);
create index vendas_entregador_idx  on vendas (entregador_id) where entregador_id is not null;
create index vendas_mesa_idx        on vendas (mesa_id) where mesa_id is not null;

create table itens_venda (
  id uuid primary key default gen_random_uuid(),
  venda_id uuid not null references vendas(id) on delete cascade,
  produto_id uuid references produtos(id) on delete set null,
  combo_id uuid references combos(id) on delete set null,
  descricao text,
  quantidade integer not null default 1 check (quantidade > 0),
  valor_unitario numeric(10,2) not null default 0,
  custo_unitario numeric(10,2) not null default 0,
  valor_total_item numeric(10,2) not null default 0,
  adicionais_ids uuid[] not null default '{}'
);
create index itens_venda_venda_idx on itens_venda (venda_id);

create table pagamentos_venda (
  id uuid primary key default gen_random_uuid(),
  venda_id uuid not null references vendas(id) on delete cascade,
  forma_pagamento text not null,
  valor numeric(10,2) not null default 0,
  taxa_aplicada numeric(10,2) not null default 0
);
create index pagamentos_venda_venda_idx on pagamentos_venda (venda_id);

create table entregas_fechadas (
  id uuid primary key default gen_random_uuid(),
  fechamento_id uuid not null references fechamentos_entrega(id) on delete cascade,
  venda_id uuid not null references vendas(id) on delete restrict,
  data_ref date not null,
  entregador_id uuid references usuarios(id) on delete set null,
  taxa numeric(10,2) not null default 0,
  unique (venda_id)                               -- uma entrega só entra em um fechamento
);

create table cupons_usos (
  id uuid primary key default gen_random_uuid(),
  cupom_id uuid not null references cupons(id) on delete cascade,
  codigo text,
  venda_id uuid references vendas(id) on delete set null,
  cliente_id uuid references clientes(id) on delete set null,
  telefone text,
  desconto numeric(10,2) not null default 0,
  frete_gratis boolean not null default false,
  data_hora timestamptz not null default now(),
  requisicao_id text
);

-- ---------------------------------------------------------------------
-- 6. Estoque, despesas e financeiro
-- ---------------------------------------------------------------------
create table movimentacoes_estoque (
  id uuid primary key default gen_random_uuid(),
  ingrediente_id uuid not null references estoque(id) on delete restrict,
  tipo tipo_mov_estoque not null,
  quantidade numeric(12,3) not null,
  qtd_antes numeric(12,3),
  qtd_depois numeric(12,3),
  motivo_referencia text,
  usuario_id uuid references usuarios(id) on delete set null,
  data timestamptz not null default now()
);
create index mov_estoque_ing_idx on movimentacoes_estoque (ingrediente_id, data desc);

create table despesas_recorrentes (
  id uuid primary key default gen_random_uuid(),
  descricao text not null,
  categoria text,
  valor numeric(10,2) not null default 0,
  dia_vencimento integer check (dia_vencimento between 1 and 31),
  periodicidade text not null default 'Mensal',
  ativa boolean not null default true,
  observacao text,
  inicio date,
  termino date,
  criada_em timestamptz not null default now()
);

create table despesas (
  id uuid primary key default gen_random_uuid(),
  data_hora timestamptz not null default now(),
  descricao text not null,
  valor numeric(10,2) not null default 0,
  observacao text,
  status status_despesa not null default 'Paga',
  motivo_cancelamento text,
  categoria text,
  vencimento date,
  situacao text,
  recorrente_id uuid references despesas_recorrentes(id) on delete set null,
  competencia text,                         -- 'yyyy-MM'
  saiu_do_caixa boolean not null default true,
  criada_em timestamptz not null default now(),
  requisicao_id text
);
create index despesas_data_idx on despesas (data_hora desc);
create unique index despesas_recorrente_mes_uq on despesas (recorrente_id, competencia) where recorrente_id is not null;

create table sangrias (
  id uuid primary key default gen_random_uuid(),
  data_hora timestamptz not null default now(),
  valor numeric(10,2) not null,
  motivo text,
  usuario_id uuid references usuarios(id) on delete set null,
  caixa_id uuid references caixa_sessoes(id) on delete set null
);

create table ajustes_pos_venda (
  id uuid primary key default gen_random_uuid(),
  data_hora timestamptz not null default now(),
  venda_id uuid not null references vendas(id) on delete restrict,
  pedido_numero integer,
  cliente text,
  telefone text,
  tipo text not null,
  valor numeric(10,2) not null default 0,
  motivo text,
  detalhe text,
  saida boolean not null default false,
  despesa_id uuid references despesas(id) on delete set null,
  status text not null default 'Ativo',
  autorizado_por uuid references usuarios(id) on delete set null,
  registrado_por uuid references usuarios(id) on delete set null,
  cancelado_em timestamptz,
  motivo_cancelamento text
);

create table eventos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  tipo text,
  data date,
  hora_inicio time,
  hora_fim time,
  local text,
  contratante text,
  telefone text,
  status text,
  valor_contratado numeric(10,2) not null default 0,
  valor_recebido numeric(10,2) not null default 0,
  valor_a_receber numeric(10,2) not null default 0,
  custo_total numeric(10,2) not null default 0,
  resultado numeric(10,2) not null default 0,
  observacoes text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id) on delete set null,
  atualizado_em timestamptz not null default now()
);

create table eventos_custos (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references eventos(id) on delete cascade,
  descricao text not null,
  categoria text,
  valor numeric(10,2) not null default 0,
  data date,
  observacao text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id) on delete set null,
  requisicao_id text
);

create table eventos_recebimentos (
  id uuid primary key default gen_random_uuid(),
  evento_id uuid not null references eventos(id) on delete cascade,
  valor numeric(10,2) not null default 0,
  forma_pagamento text,
  data date,
  observacao text,
  criado_em timestamptz not null default now(),
  criado_por uuid references usuarios(id) on delete set null,
  requisicao_id text
);

-- ---------------------------------------------------------------------
-- 7. Relacionamento com clientes
-- ---------------------------------------------------------------------
create table fidelidade (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null unique references clientes(id) on delete cascade,
  carimbos integer not null default 0 check (carimbos between 0 and 10),
  premios_resgatados integer not null default 0,
  atualizada_em timestamptz not null default now(),
  observacoes text
);

create table indicacoes (
  id uuid primary key default gen_random_uuid(),
  indicador_id uuid references clientes(id) on delete set null,
  indicado_id uuid references clientes(id) on delete set null,
  nome_indicador text,
  telefone_indicador text,
  nome_indicado text,
  telefone_indicado text,
  data timestamptz not null default now(),
  status status_indicacao not null default 'Pendente',
  observacoes text
);

create table feedbacks (
  id uuid primary key default gen_random_uuid(),
  venda_id uuid references vendas(id) on delete set null,
  cliente_id uuid references clientes(id) on delete set null,
  telefone_cliente text,
  nota integer check (nota between 1 and 5),
  comentario text,
  data timestamptz not null default now(),
  status text not null default 'Novo'
);

create sequence ocorrencias_numero_seq;
create table ocorrencias (
  id uuid primary key default gen_random_uuid(),
  numero integer not null default nextval('ocorrencias_numero_seq'),
  data_hora timestamptz not null default now(),
  tipo text,
  setor text,
  venda_id uuid references vendas(id) on delete set null,
  cliente text,
  telefone text,
  registrado_por uuid references usuarios(id) on delete set null,
  responsavel text,
  descricao text,
  solucao text,
  status status_ocorrencia not null default 'Aberta',
  atualizada_em timestamptz not null default now(),
  historico jsonb not null default '[]'::jsonb
);

-- ---------------------------------------------------------------------
-- 8. Tabelas de apoio do sistema
-- ---------------------------------------------------------------------
-- Substitui a aba Configurações (chave/valor). Também guarda flags (ex.: manutencao).
create table sistema (
  chave text primary key,
  valor jsonb not null,
  atualizado_em timestamptz not null default now()
);

create table auditoria (
  id bigint generated always as identity primary key,
  data_hora timestamptz not null default now(),
  usuario_id uuid references usuarios(id) on delete set null,
  usuario_login text,
  perfil text,
  acao text not null,
  telefone text,
  detalhes text,
  autorizado_por text,
  aparelho text
);
create index auditoria_data_idx on auditoria (data_hora desc);

create table backups (
  id uuid primary key default gen_random_uuid(),
  data_hora timestamptz not null default now(),
  tipo tipo_backup not null,
  status text not null default 'Em andamento',
  arquivo text,
  tamanho_bytes bigint,
  tentativas integer not null default 0,
  erro text,
  usuario_id uuid references usuarios(id) on delete set null
);

-- Idempotência: guarda o resultado da requisição para repetir a mesma resposta sem refazer.
create table requisicoes (
  chave text primary key,
  acao text not null,
  resultado jsonb,
  usuario_id uuid references usuarios(id) on delete set null,
  data_hora timestamptz not null default now()
);
create index requisicoes_data_idx on requisicoes (data_hora);

-- Fila para espelhar as gravações nas planilhas (Etapa 4). Um item, dois destinos.
create table fila_sync (
  id bigint generated always as identity primary key,
  tabela text not null,
  registro_id text not null,
  operacao op_sync not null,
  payload jsonb,
  criado_em timestamptz not null default now(),
  principal_ok_em timestamptz,
  principal_tentativas integer not null default 0,
  principal_erro text,
  contingencia_ok_em timestamptz,
  contingencia_tentativas integer not null default 0,
  contingencia_erro text
);
create index fila_sync_pend_principal_idx   on fila_sync (id) where principal_ok_em is null;
create index fila_sync_pend_contingencia_idx on fila_sync (id) where contingencia_ok_em is null;

-- Decisões de fotos (Etapa 8). Colunas SEM padrão: o Admin escolhe na Etapa 8, nada é decidido antes.
create table configuracoes_fotos (
  id boolean primary key default true check (id),   -- linha única
  onde_guardar text,            -- 'drives' | 'storage' | 'ambos'
  destino_padrao_upload text,   -- 'principal' | 'contingencia' | 'ambos' | 'perguntar'
  drive_preferido foto_preferida,
  sincronizacao_drives text,    -- 'semanal' | 'manual' | 'desligada'
  backup_frio_storage text,     -- 'semanal' | 'desligado'
  replicar_antigas text,        -- 'todas' | 'ativos' | 'nenhuma'
  atualizado_em timestamptz not null default now()
);
insert into configuracoes_fotos (id) values (true);

-- Chaves iniciais (as mesmas da aba Configurações atual)
insert into sistema (chave, valor) values
  ('MetaMensal', '0'), ('MetaDiaria', '0'),
  ('BLOQUEAR_ESTOQUE_NEGATIVO', 'false'),
  ('TaxaEntregaPadrao', '0'), ('AjudaDiariaEntregador', '0'),
  ('CardapioKicker', '""'), ('CardapioFrase', '""'),
  ('CardapioTempoRetirada', '""'), ('CardapioTempoMesa', '""'), ('CardapioTempoEntrega', '""'),
  ('NotificacoesConfig', 'null'),
  ('BACKUP_AUTO_ATIVO', 'false'), ('BACKUP_HORA', '4'), ('BACKUP_FREQ', '"diario"'),
  ('MANUTENCAO', 'null');

-- ---------------------------------------------------------------------
-- 9. Gatilhos
-- ---------------------------------------------------------------------
-- 9.1 Fila de sincronização: toda gravação de negócio entra na fila automaticamente.
create or replace function enfileirar_sync() returns trigger
language plpgsql security definer set search_path = public as $$
declare reg jsonb; rid text;
begin
  if tg_op = 'DELETE' then reg := to_jsonb(old); else reg := to_jsonb(new); end if;
  rid := coalesce(reg->>'id', reg->>'chave');
  insert into fila_sync (tabela, registro_id, operacao, payload)
  values (tg_table_name, rid, tg_op::op_sync, case when tg_op = 'DELETE' then null else reg end);
  return null;
end $$;

-- 9.2 Registrar quando atualizou
create or replace function tocar_atualizado_em() returns trigger
language plpgsql as $$
begin new.atualizado_em := now(); return new; end $$;

create trigger sistema_atualizado before update on sistema
  for each row execute function tocar_atualizado_em();
create trigger eventos_atualizado before update on eventos
  for each row execute function tocar_atualizado_em();
create trigger fotos_cfg_atualizado before update on configuracoes_fotos
  for each row execute function tocar_atualizado_em();

-- 9.3 Liga a fila em TODAS as tabelas que as planilhas espelham.
-- (usuarios fica de fora: senha/hash nunca vai para planilha. auditoria/backups/requisicoes/fila_sync também.)
do $$
declare t text;
begin
  foreach t in array array[
    'clientes','formas_pagamento','categorias','estoque','produtos','combos','produto_precos','combo_precos',
    'combo_itens','produto_ingredientes','adicionais','produto_adicionais','promocoes','cupons','mesas',
    'caixa_sessoes','fechamentos_entrega','vendas','itens_venda','pagamentos_venda','entregas_fechadas',
    'cupons_usos','movimentacoes_estoque','despesas_recorrentes','despesas','sangrias','ajustes_pos_venda',
    'eventos','eventos_custos','eventos_recebimentos','fidelidade','indicacoes','feedbacks','ocorrencias','sistema'
  ] loop
    execute format('create trigger %I after insert or update or delete on %I
                    for each row execute function enfileirar_sync()', t || '_sync', t);
  end loop;
end $$;


-- >>>>>>>>>> 02_seguranca_rls.sql <<<<<<<<<<
-- =====================================================================
-- Texas Burger — Etapa 1 (parte 2/2): segurança (RLS) e visões públicas
-- Rodar DEPOIS do 01_tabelas.sql.
--
-- Princípios
--  * RLS ligado em TODAS as tabelas. Sem política = ninguém do app acessa.
--  * Visitante (anon) NÃO lê nenhuma tabela. Só lê as visões v_cardapio_* (colunas seguras).
--  * As permissões seguem a matriz que já existe no app (PERMISSOES_ACAO do Apps Script).
--  * Operações sensíveis (vendas, caixa, estoque, cupons, backup, usuários, pedidos públicos)
--    NÃO têm política de escrita para o app: só as Edge Functions (service role) gravam.
--    Assim ninguém consegue burlar a regra de negócio chamando o banco direto.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Funções auxiliares
-- ---------------------------------------------------------------------
create or replace function auth_nivel() returns nivel_acesso
language sql stable security definer set search_path = public as $$
  select nivel from usuarios where id = auth.uid() and ativo
$$;

create or replace function tem_nivel(variadic niveis nivel_acesso[]) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(auth_nivel() = any(niveis), false)
$$;

revoke all on function auth_nivel() from public, anon;
revoke all on function tem_nivel(nivel_acesso[]) from public, anon;
grant execute on function auth_nivel() to authenticated;
grant execute on function tem_nivel(nivel_acesso[]) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Privilégios base: visitante sem nada; logado só com RLS decidindo
-- ---------------------------------------------------------------------
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
alter default privileges in schema public revoke all on tables    from anon;
alter default privileges in schema public revoke all on sequences from anon;

-- ---------------------------------------------------------------------
-- 3. Liga RLS em tudo (inclusive tabelas criadas e esquecidas)
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 4. Usuários: cada um vê a si mesmo; Admin vê todos. Criar/editar/excluir = Edge Function.
-- ---------------------------------------------------------------------
create policy usuarios_ler_proprio on usuarios for select to authenticated
  using (id = auth.uid() or tem_nivel('Admin'));

-- ---------------------------------------------------------------------
-- 5. Cadastros: todo usuário ativo lê; só Admin altera
--    (produtos, preços e combos precisam aparecer para Garçom e Cozinha)
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'categorias','produtos','combos','produto_precos','combo_precos','combo_itens',
    'produto_ingredientes','adicionais','produto_adicionais','formas_pagamento','promocoes','sistema'
  ] loop
    execute format('create policy %I on %I for select to authenticated using (auth_nivel() is not null)', t||'_ler', t);
    execute format('create policy %I on %I for all to authenticated using (tem_nivel(''Admin'')) with check (tem_nivel(''Admin''))', t||'_admin', t);
  end loop;
end $$;

-- Admin-only (ler e escrever): financeiro avançado, eventos, cupons, ajustes, recorrentes
do $$
declare t text;
begin
  foreach t in array array[
    'cupons','despesas_recorrentes','ajustes_pos_venda','eventos','eventos_custos','eventos_recebimentos',
    'fechamentos_entrega','entregas_fechadas','backups','auditoria','fila_sync'
  ] loop
    -- leitura só do Admin; escrita só pelas Edge Functions (sem política de escrita)
    execute format('create policy %I on %I for select to authenticated using (tem_nivel(''Admin''))', t||'_ler_admin', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- 6. Clientes, fidelidade, indicações
-- ---------------------------------------------------------------------
create policy clientes_ler   on clientes for select to authenticated using (tem_nivel('Admin','Operador','Garçom'));
create policy clientes_criar on clientes for insert to authenticated with check (tem_nivel('Admin','Operador','Garçom'));
create policy clientes_alterar on clientes for update to authenticated
  using (tem_nivel('Admin','Operador','Garçom')) with check (tem_nivel('Admin','Operador','Garçom'));
create policy clientes_excluir on clientes for delete to authenticated using (tem_nivel('Admin'));

create policy fidelidade_ler on fidelidade for select to authenticated using (tem_nivel('Admin','Operador'));
create policy indicacoes_ler on indicacoes for select to authenticated using (tem_nivel('Admin','Operador'));
-- carimbar / resgatar / indicar = Edge Function (regra de fidelidade e anti-duplicidade)

-- ---------------------------------------------------------------------
-- 7. Mesas
-- ---------------------------------------------------------------------
create policy mesas_ler on mesas for select to authenticated using (tem_nivel('Admin','Operador','Garçom'));
create policy mesas_status on mesas for update to authenticated
  using (tem_nivel('Admin','Operador','Garçom')) with check (tem_nivel('Admin','Operador','Garçom'));
create policy mesas_admin_criar   on mesas for insert to authenticated with check (tem_nivel('Admin'));
create policy mesas_admin_excluir on mesas for delete to authenticated using (tem_nivel('Admin'));
-- mesas_codigos: sem política nenhuma → só Edge Function (service role)

-- ---------------------------------------------------------------------
-- 8. Vendas (o ponto mais delicado)
--    Admin/Operador: veem tudo.
--    Garçom: vendas de mesa e as que ele mesmo registrou.
--    Cozinha: só pedidos em andamento (Recebido, Em preparo, Pronta, Suspenso).
--    Entregador: só as entregas atribuídas a ele.
--    Ninguém apaga venda: cancelar é mudar o status (Edge Function).
-- ---------------------------------------------------------------------
create policy vendas_ler on vendas for select to authenticated using (
  tem_nivel('Admin','Operador')
  or (tem_nivel('Garçom') and (tipo = 'Mesa' or registrado_por = auth.uid()))
  or (tem_nivel('Cozinha') and status = 'Confirmada' and status_pedido in ('Recebido','Em preparo','Pronta','Suspenso'))
  or (tem_nivel('Entregador') and tipo = 'Entrega' and entregador_id = auth.uid())
);
create policy vendas_criar on vendas for insert to authenticated with check (
  tem_nivel('Admin','Operador') or (tem_nivel('Garçom') and registrado_por = auth.uid())
);
create policy vendas_alterar on vendas for update to authenticated
  using (tem_nivel('Admin','Operador')) with check (tem_nivel('Admin','Operador'));
-- Sem política de DELETE: ninguém apaga venda pelo app.
-- Avançar status (Cozinha/Garçom/Entregador) e cancelar passam pela Edge Function.

-- itens e pagamentos seguem a visibilidade da venda (a RLS de vendas vale dentro do exists)
create policy itens_venda_ler on itens_venda for select to authenticated
  using (exists (select 1 from vendas v where v.id = itens_venda.venda_id));
create policy itens_venda_criar on itens_venda for insert to authenticated
  with check (tem_nivel('Admin','Operador','Garçom') and exists (select 1 from vendas v where v.id = itens_venda.venda_id));
create policy itens_venda_alterar on itens_venda for update to authenticated
  using (tem_nivel('Admin','Operador')) with check (tem_nivel('Admin','Operador'));

create policy pagamentos_venda_ler on pagamentos_venda for select to authenticated
  using (tem_nivel('Admin','Operador','Garçom') and exists (select 1 from vendas v where v.id = pagamentos_venda.venda_id));
create policy pagamentos_venda_criar on pagamentos_venda for insert to authenticated
  with check (tem_nivel('Admin','Operador','Garçom') and exists (select 1 from vendas v where v.id = pagamentos_venda.venda_id));
create policy pagamentos_venda_alterar on pagamentos_venda for update to authenticated
  using (tem_nivel('Admin','Operador')) with check (tem_nivel('Admin','Operador'));

create policy cupons_usos_ler on cupons_usos for select to authenticated using (tem_nivel('Admin','Operador'));

-- ---------------------------------------------------------------------
-- 9. Caixa, despesas, sangrias, estoque
-- ---------------------------------------------------------------------
create policy caixa_ler on caixa_sessoes for select to authenticated using (tem_nivel('Admin','Operador'));
-- abrir/fechar caixa = Edge Function

create policy despesas_ler    on despesas for select to authenticated using (tem_nivel('Admin','Operador'));
create policy despesas_criar  on despesas for insert to authenticated with check (tem_nivel('Admin','Operador'));
create policy despesas_alterar on despesas for update to authenticated
  using (tem_nivel('Admin')) with check (tem_nivel('Admin'));

create policy sangrias_ler   on sangrias for select to authenticated using (tem_nivel('Admin','Operador'));
create policy sangrias_criar on sangrias for insert to authenticated with check (tem_nivel('Admin','Operador'));

create policy estoque_ler on estoque for select to authenticated using (tem_nivel('Admin','Operador'));
create policy estoque_admin on estoque for all to authenticated
  using (tem_nivel('Admin')) with check (tem_nivel('Admin'));
create policy mov_estoque_ler on movimentacoes_estoque for select to authenticated using (tem_nivel('Admin','Operador'));
-- entrada, perda e inventário = Edge Function (grava movimentação e saldo juntos, na mesma transação)

-- ---------------------------------------------------------------------
-- 10. Feedbacks e ocorrências
-- ---------------------------------------------------------------------
create policy feedbacks_ler on feedbacks for select to authenticated using (tem_nivel('Admin','Operador'));
create policy feedbacks_status on feedbacks for update to authenticated
  using (tem_nivel('Admin','Operador')) with check (tem_nivel('Admin','Operador'));
-- feedback do cliente entra pela Edge Function pública (anti-spam)

create policy ocorrencias_ler on ocorrencias for select to authenticated using (
  tem_nivel('Admin','Operador') or registrado_por = auth.uid()
);
create policy ocorrencias_criar on ocorrencias for insert to authenticated with check (
  auth_nivel() is not null and registrado_por = auth.uid()
);
create policy ocorrencias_alterar on ocorrencias for update to authenticated
  using (tem_nivel('Admin','Operador')) with check (tem_nivel('Admin','Operador'));

-- ---------------------------------------------------------------------
-- 11. Fotos: todos leem a configuração; só Admin altera
-- ---------------------------------------------------------------------
create policy fotos_cfg_ler   on configuracoes_fotos for select to authenticated using (auth_nivel() is not null);
create policy fotos_cfg_admin on configuracoes_fotos for update to authenticated
  using (tem_nivel('Admin')) with check (tem_nivel('Admin'));

-- requisicoes: sem política → só Edge Function.

-- ---------------------------------------------------------------------
-- 12. Cardápio público (visitante sem login) — SOMENTE por estas visões
--     As visões rodam com o dono (ignoram RLS) e expõem só colunas seguras:
--     sem custo, sem estoque, sem cupons, sem código de QR.
--     (O alerta "Security Definer View" do Supabase para estas visões é esperado.)
-- ---------------------------------------------------------------------
create or replace view v_cardapio_categorias as
  select id, nome, ordem from categorias where ativa;

create or replace view v_cardapio_formas as
  select id, nome, ordem, permite_troco from formas_pagamento where ativa and visivel_cardapio;

create or replace view v_cardapio_produtos as
  select id, nome, descricao, categoria_id, destaque, ordem_cardapio,
         foto_id_principal, foto_id_contingencia, foto_url_principal, foto_url_contingencia, foto_preferida
  from produtos where ativo;

create or replace view v_cardapio_combos as
  select id, nome, categoria_id, destaque, ordem_cardapio,
         foto_id_principal, foto_id_contingencia, foto_url_principal, foto_url_contingencia, foto_preferida
  from combos where ativo;

create or replace view v_cardapio_combo_itens as
  select ci.combo_id, ci.produto_id, ci.quantidade
  from combo_itens ci join combos c on c.id = ci.combo_id and c.ativo;

-- preço por forma de pagamento visível (SEM o custo)
create or replace view v_cardapio_precos as
  select 'produto'::text as tipo, pp.produto_id as item_id, pp.forma_pagamento_id, pp.preco
    from produto_precos pp join produtos p on p.id = pp.produto_id and p.ativo
    join formas_pagamento f on f.id = pp.forma_pagamento_id and f.ativa and f.visivel_cardapio
  union all
  select 'combo', cp.combo_id, cp.forma_pagamento_id, cp.preco
    from combo_precos cp join combos c on c.id = cp.combo_id and c.ativo
    join formas_pagamento f on f.id = cp.forma_pagamento_id and f.ativa and f.visivel_cardapio;

create or replace view v_cardapio_adicionais as
  select pa.produto_id, a.id as adicional_id, a.nome, a.preco
  from produto_adicionais pa join adicionais a on a.id = pa.adicional_id and a.ativo
  join produtos p on p.id = pa.produto_id and p.ativo;

-- só as chaves de configuração que o cliente pode ver (+ flag de manutenção)
create or replace view v_cardapio_config as
  select chave, valor from sistema
  where chave in ('CardapioKicker','CardapioFrase','CardapioTempoRetirada','CardapioTempoMesa',
                  'CardapioTempoEntrega','TaxaEntregaPadrao','MANUTENCAO');

grant select on
  v_cardapio_categorias, v_cardapio_formas, v_cardapio_produtos, v_cardapio_combos,
  v_cardapio_combo_itens, v_cardapio_precos, v_cardapio_adicionais, v_cardapio_config
to anon, authenticated;

-- Pedido do cardápio, pedido de mesa, cancelamento, feedback, validação de cupom e status do pedido:
-- visitante NÃO grava nem lê tabela. Tudo isso será Edge Function pública (Etapa 3), com limite de tentativas.

-- ---------------------------------------------------------------------
-- 13. Conferência (rode e veja o resultado — deve retornar ZERO linhas em ambas)
-- ---------------------------------------------------------------------
-- (a) tabelas sem RLS:
--   select tablename from pg_tables where schemaname='public' and not rowsecurity;
-- (b) tabelas que o visitante (anon) consegue acessar:
--   select table_name, privilege_type from information_schema.role_table_grants
--   where grantee='anon' and table_schema='public' and table_name not like 'v\_cardapio\_%';


-- >>>>>>>>>> 01_visao_status_cardapio.sql <<<<<<<<<<
-- Texas Burger — Etapa 3a: visão pública mínima para o cardápio saber se o caixa está aberto.
-- Rodar UMA vez no SQL Editor (antes de testar o cardápio). Expõe só "true/false", nada mais do caixa.
create or replace view v_cardapio_status as
  select exists (select 1 from caixa_sessoes where status = 'Aberto') as caixa_aberto;

grant select on v_cardapio_status to anon, authenticated;


-- >>>>>>>>>> 01_funcoes_cadastros.sql <<<<<<<<<<
-- =====================================================================
-- Texas Burger — Etapa 3b: GRAVAÇÕES dos cadastros (funções no banco)
-- Rodar no SQL Editor DEPOIS da Etapa 3a. Pode rodar de novo (create or replace).
--
-- Por que funções no banco: cada ação mexe em várias tabelas de uma vez (ex.: produto + preços + receita + adicionais).
-- Dentro de uma função tudo acontece junto ou nada acontece (transação), a permissão é conferida no servidor e o
-- registro de auditoria é gravado na mesma hora. O app chama a função com o login do funcionário.
-- Resposta no mesmo formato de antes: {ok:true, message:...} ou {ok:false, message:...}.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Ajustes de leitura que a 3b precisa
-- ---------------------------------------------------------------------
-- Operador também enxerga a lista de usuários (como no sistema antigo; não há senha nessa tabela).
drop policy if exists usuarios_ler_proprio on usuarios;
create policy usuarios_ler_proprio on usuarios for select to authenticated
  using (id = auth.uid() or tem_nivel('Admin','Operador'));

-- Mesas com o login do garçom responsável (a tabela guarda só o id dele)
create or replace view v_mesas as
  select m.id, m.numero, m.status, m.capacidade, m.observacao, m.chamado_tipo, m.chamado_em,
         u.login as garcom_responsavel
  from mesas m left join usuarios u on u.id = m.garcom_responsavel_id
  where tem_nivel('Admin','Operador','Garçom');
grant select on v_mesas to authenticated;

-- ---------------------------------------------------------------------
-- 1. Auxiliares
-- ---------------------------------------------------------------------
create or replace function _negado() returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', false, 'message', 'Seu perfil não tem permissão para esta ação.')
$$;

create or replace function _falha(p_msg text) returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', false, 'message', p_msg)
$$;

-- número seguro (texto inválido vira o padrão, como Number(x)||0 no sistema antigo)
create or replace function _num(v text, padrao numeric default 0) returns numeric
language plpgsql immutable as $$
begin
  return coalesce(nullif(btrim(v), '')::numeric, padrao);
exception when others then
  return padrao;
end $$;

-- uuid seguro (texto vazio ou inválido vira null)
create or replace function _uuid(v text) returns uuid
language plpgsql immutable as $$
begin
  return nullif(btrim(v), '')::uuid;
exception when others then
  return null;
end $$;

-- grava no registro de auditoria (usuário vem do login da chamada)
create or replace function _auditar(p_acao text, p_detalhes text default null, p_telefone text default null) returns void
language sql security definer set search_path = public as $$
  insert into auditoria (usuario_id, usuario_login, perfil, acao, telefone, detalhes)
  select u.id, u.login, u.nivel::text, p_acao, p_telefone, p_detalhes from usuarios u where u.id = auth.uid()
$$;

-- grava uma configuração (chave/valor)
create or replace function _cfg_gravar(p_chave text, p_valor jsonb) returns void
language sql security definer set search_path = public as $$
  insert into sistema (chave, valor) values (p_chave, p_valor)
  on conflict (chave) do update set valor = excluded.valor
$$;

-- ---------------------------------------------------------------------
-- 2. Formas de pagamento
-- ---------------------------------------------------------------------
create or replace function _validar_forma(pct numeric, fixa numeric, prazo numeric) returns text
language sql immutable as $$
  select case
    when pct < 0 or pct > 100 then 'A taxa % deve ficar entre 0 e 100.'
    when fixa < 0 then 'A taxa fixa não pode ser negativa.'
    when prazo < 0 or prazo > 365 or prazo <> floor(prazo) then 'O prazo deve ser um número inteiro de dias (0 a 365).'
    else '' end
$$;

create or replace function api_add_forma_pagamento(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_nome text := btrim(coalesce(p->>'nome', ''));
  v_pct numeric := _num(p->>'taxaPct'); v_fixa numeric := _num(p->>'taxaFixa'); v_prazo numeric := _num(p->>'prazoDias');
  v_troco boolean := coalesce((p->>'permiteTroco')::boolean, false);
  v_erro text; v_id uuid := gen_random_uuid(); v_ordem int; v_ref uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome da forma de pagamento.'); end if;
  if exists (select 1 from formas_pagamento where lower(nome) = lower(v_nome)) then return _falha('Já existe uma forma de pagamento com esse nome.'); end if;
  v_erro := _validar_forma(v_pct, v_fixa, v_prazo);
  if v_erro <> '' then return _falha(v_erro); end if;
  select coalesce(max(ordem), 0) + 1 into v_ordem from formas_pagamento;
  -- referência para o preço inicial: a primeira forma (pela ordem) que já existia
  select id into v_ref from formas_pagamento order by ordem, id limit 1;
  insert into formas_pagamento (id, nome, ativa, visivel_cardapio, taxa_percentual, taxa_fixa, prazo_dias, permite_troco, ordem)
  values (v_id, v_nome, true, true, v_pct, v_fixa, v_prazo::int, v_troco, v_ordem);
  -- a nova forma já nasce com o preço/custo da referência em todos os produtos e combos
  insert into produto_precos (produto_id, forma_pagamento_id, preco, custo)
    select pr.id, v_id, coalesce(pp.preco, 0), coalesce(pp.custo, 0)
    from produtos pr left join produto_precos pp on pp.produto_id = pr.id and pp.forma_pagamento_id = v_ref;
  insert into combo_precos (combo_id, forma_pagamento_id, preco, custo)
    select c.id, v_id, coalesce(cp.preco, 0), coalesce(cp.custo, 0)
    from combos c left join combo_precos cp on cp.combo_id = c.id and cp.forma_pagamento_id = v_ref;
  perform _auditar('Forma de pagamento cadastrada', v_nome || ' | taxa ' || v_pct || '% + R$ ' || to_char(v_fixa, 'FM999990.00') || ' | prazo ' || v_prazo::int || 'd | troco ' || case when v_troco then 'sim' else 'não' end);
  return jsonb_build_object('ok', true, 'message', 'Forma de pagamento cadastrada.');
end $$;

create or replace function api_editar_forma_pagamento(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  f formas_pagamento%rowtype; v_id uuid := _uuid(p->>'id');
  v_pct numeric; v_fixa numeric; v_prazo numeric; v_erro text; v_novo text; v_mudou text := '';
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into f from formas_pagamento where id = v_id;
  if not found then return _falha('Forma de pagamento não encontrada.'); end if;
  v_pct   := case when p ? 'novaTaxaPct'   then _num(p->>'novaTaxaPct')   else f.taxa_percentual end;
  v_fixa  := case when p ? 'novaTaxaFixa'  then _num(p->>'novaTaxaFixa')  else f.taxa_fixa end;
  v_prazo := case when p ? 'novoPrazoDias' then _num(p->>'novoPrazoDias') else f.prazo_dias end;
  v_erro := _validar_forma(v_pct, v_fixa, v_prazo);
  if v_erro <> '' then return _falha(v_erro); end if;
  v_novo := btrim(coalesce(p->>'novoNome', ''));
  if v_novo <> '' and v_novo <> f.nome then
    if exists (select 1 from formas_pagamento where id <> f.id and lower(nome) = lower(v_novo)) then return _falha('Já existe uma forma de pagamento com esse nome.'); end if;
    -- vendas antigas guardam o NOME da forma; renomear quebraria o vínculo
    if exists (select 1 from pagamentos_venda where forma_pagamento = f.nome) or exists (select 1 from vendas where forma_pagamento = f.nome) then
      return _falha('Essa forma já foi usada em vendas e não pode ser renomeada. Desative e cadastre uma nova.');
    end if;
    update formas_pagamento set nome = v_novo where id = f.id;
  end if;
  if p ? 'novoAtivo' then update formas_pagamento set ativa = (coalesce(p->>'novoAtivo','') <> 'false') where id = f.id; end if;
  if p ? 'novoVisivelCardapio' then update formas_pagamento set visivel_cardapio = (coalesce(p->>'novoVisivelCardapio','') <> 'false') where id = f.id; end if;
  if p ? 'novoPermiteTroco' then update formas_pagamento set permite_troco = coalesce((p->>'novoPermiteTroco')::boolean, false) where id = f.id; end if;
  if p ? 'novaOrdem' then update formas_pagamento set ordem = _num(p->>'novaOrdem')::int where id = f.id; end if;
  update formas_pagamento set taxa_percentual = v_pct, taxa_fixa = v_fixa, prazo_dias = v_prazo::int where id = f.id;
  if v_pct <> f.taxa_percentual then v_mudou := v_mudou || ' | taxa % ' || f.taxa_percentual || ' → ' || v_pct; end if;
  if v_fixa <> f.taxa_fixa then v_mudou := v_mudou || ' | taxa fixa R$ ' || to_char(f.taxa_fixa, 'FM999990.00') || ' → R$ ' || to_char(v_fixa, 'FM999990.00'); end if;
  if v_prazo <> f.prazo_dias then v_mudou := v_mudou || ' | prazo ' || f.prazo_dias || 'd → ' || v_prazo::int || 'd'; end if;
  perform _auditar('Forma de pagamento atualizada', coalesce(nullif(v_novo, ''), f.nome) || v_mudou);
  return jsonb_build_object('ok', true, 'message', 'Forma de pagamento atualizada.');
end $$;

-- ---------------------------------------------------------------------
-- 3. Categorias
-- ---------------------------------------------------------------------
create or replace function api_add_categoria(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_ordem int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome da categoria.'); end if;
  if exists (select 1 from categorias where lower(nome) = lower(v_nome)) then return _falha('Já existe uma categoria com esse nome.'); end if;
  select coalesce(max(ordem), 0) + 1 into v_ordem from categorias;
  insert into categorias (nome, ativa, ordem) values (v_nome, true, v_ordem);
  perform _auditar('Categoria cadastrada', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Categoria cadastrada.');
end $$;

create or replace function api_editar_categoria(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id'); v_nome text := btrim(coalesce(p->>'novoNome', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from categorias where id = v_id) then return _falha('Categoria não encontrada.'); end if;
  if v_nome <> '' then update categorias set nome = v_nome where id = v_id; end if;
  if p ? 'novoAtivo' then update categorias set ativa = (coalesce(p->>'novoAtivo','') <> 'false') where id = v_id; end if;
  if p ? 'novaOrdem' and p->>'novaOrdem' is not null then update categorias set ordem = _num(p->>'novaOrdem')::int where id = v_id; end if;
  perform _auditar('Categoria atualizada', coalesce(nullif(v_nome, ''), v_id::text));
  return jsonb_build_object('ok', true, 'message', 'Categoria atualizada.');
end $$;

create or replace function api_excluir_categoria(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id'); v_prod int; v_comb int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select count(*) into v_prod from produtos where categoria_id = v_id;
  select count(*) into v_comb from combos where categoria_id = v_id;
  if v_prod + v_comb > 0 then
    return _falha((v_prod + v_comb) || ' item(ns) usam essa categoria (' || v_prod || ' produto(s), ' || v_comb || ' combo(s)). Mova-os para outra categoria antes de excluir.');
  end if;
  delete from categorias where id = v_id;
  perform _auditar('Categoria excluída', v_id::text);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. Ingredientes (cadastro do estoque; entrada/perda/inventário ficam para a etapa 3c)
-- ---------------------------------------------------------------------
create or replace function api_add_ingrediente(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_qtd numeric := _num(p->>'quantidade'); v_id uuid := gen_random_uuid();
        v_un text := coalesce(nullif(p->>'unidade', ''), 'un');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome do ingrediente.'); end if;
  if exists (select 1 from estoque where lower(btrim(ingrediente)) = lower(v_nome)) then return _falha('Já existe um ingrediente com esse nome.'); end if;
  if v_un not in ('un','g','kg','ml','l') then v_un := 'un'; end if;
  insert into estoque (id, ingrediente, quantidade, quantidade_minima, unidade, custo_unitario, status)
  values (v_id, v_nome, v_qtd, _num(p->>'minimo'), v_un::unidade_estoque, _num(p->>'custo'), 'Ativo');
  if v_qtd > 0 then
    insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
    values (v_id, 'Entrada', v_qtd, 0, v_qtd, 'Estoque inicial do cadastro', auth.uid());
  end if;
  perform _auditar('Ingrediente cadastrado', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Ingrediente cadastrado.');
end $$;

create or replace function api_editar_ingrediente(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e estoque%rowtype; v_id uuid := _uuid(p->>'id'); v_qtd numeric := _num(p->>'quantidade'); v_nome text := btrim(coalesce(p->>'nome', ''));
        v_un text := coalesce(nullif(p->>'unidade', ''), 'un');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into e from estoque where id = v_id;
  if not found then return _falha('Ingrediente não encontrado.'); end if;
  if v_nome = '' then v_nome := e.ingrediente; end if;
  if v_un not in ('un','g','kg','ml','l') then v_un := 'un'; end if;
  update estoque set ingrediente = v_nome, quantidade = v_qtd, quantidade_minima = _num(p->>'minimo'),
         unidade = v_un::unidade_estoque, custo_unitario = _num(p->>'custo') where id = e.id;
  if p ? 'ativo' then update estoque set status = case when coalesce(p->>'ativo','') = 'false' then 'Inativo' else 'Ativo' end where id = e.id; end if;
  if v_qtd <> e.quantidade then
    insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
    values (e.id, 'Ajuste', v_qtd - e.quantidade, e.quantidade, v_qtd, 'Edição manual do cadastro', auth.uid());
  end if;
  perform _auditar('Estoque atualizado', v_nome || ': ' || e.quantidade || ' → ' || v_qtd || ' ' || v_un);
  return jsonb_build_object('ok', true, 'message', 'Estoque atualizado.');
end $$;

create or replace function api_excluir_ingrediente(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if exists (select 1 from produto_ingredientes where ingrediente_id = v_id) then
    return _falha('Este ingrediente faz parte da receita de algum produto. Tire-o das receitas antes de excluir (ou deixe-o inativo).');
  end if;
  if exists (select 1 from movimentacoes_estoque where ingrediente_id = v_id) then
    return _falha('Este ingrediente tem histórico de movimentações e não pode ser excluído. Deixe-o inativo.');
  end if;
  delete from estoque where id = v_id;
  perform _auditar('Ingrediente excluído', v_id::text);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 5. Adicionais
-- ---------------------------------------------------------------------
create or replace function api_add_adicional(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nome text := btrim(coalesce(p->>'nome', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome do adicional.'); end if;
  if exists (select 1 from adicionais where lower(btrim(nome)) = lower(v_nome)) then return _falha('Já existe um adicional com esse nome.'); end if;
  insert into adicionais (nome, preco, ativo, ingrediente_id, quantidade_descontar)
  values (v_nome, _num(p->>'preco'), true, _uuid(p->>'ingredienteId'), coalesce(nullif(_num(p->>'quantidadeDesconto'), 0), 1));
  perform _auditar('Adicional cadastrado', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Adicional cadastrado.');
end $$;

create or replace function api_editar_adicional(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id'); v_nome text := btrim(coalesce(p->>'nome', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from adicionais where id = v_id) then return _falha('Adicional não encontrado.'); end if;
  update adicionais set nome = case when v_nome = '' then nome else v_nome end, preco = _num(p->>'preco') where id = v_id;
  if p ? 'ativo' then update adicionais set ativo = (coalesce(p->>'ativo','') <> 'false') where id = v_id; end if;
  if p ? 'ingredienteId' then update adicionais set ingrediente_id = _uuid(p->>'ingredienteId') where id = v_id; end if;
  if p ? 'quantidadeDesconto' then update adicionais set quantidade_descontar = coalesce(nullif(_num(p->>'quantidadeDesconto'), 0), 1) where id = v_id; end if;
  perform _auditar('Adicional editado', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Adicional atualizado.');
end $$;

create or replace function api_excluir_adicional(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  delete from adicionais where id = v_id;   -- os vínculos com produtos saem junto
  perform _auditar('Adicional excluído', v_id::text);
  return jsonb_build_object('ok', true);
end $$;

create or replace function api_vincular_adicionais_em_lote(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_cats uuid[]; v_ads uuid[]; v_prod int; v_novas int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select coalesce(array_agg(_uuid(x)) filter (where _uuid(x) is not null), '{}') into v_cats from jsonb_array_elements_text(coalesce(p->'categorias', '[]'::jsonb)) x;
  select coalesce(array_agg(a.id), '{}') into v_ads from adicionais a
    where a.id in (select _uuid(x) from jsonb_array_elements_text(coalesce(p->'adicionaisIds', '[]'::jsonb)) x);
  if coalesce(array_length(v_cats, 1), 0) = 0 then return _falha('Escolha ao menos uma categoria.'); end if;
  if coalesce(jsonb_array_length(coalesce(p->'adicionaisIds', '[]'::jsonb)), 0) = 0 then return _falha('Escolha ao menos um adicional.'); end if;
  if coalesce(array_length(v_ads, 1), 0) = 0 then return _falha('Nenhum adicional válido selecionado.'); end if;
  select count(*) into v_prod from produtos where categoria_id = any(v_cats);
  if v_prod = 0 then return _falha('Não há produtos nessas categorias.'); end if;
  with ins as (
    insert into produto_adicionais (produto_id, adicional_id)
    select pr.id, a from produtos pr cross join unnest(v_ads) a where pr.categoria_id = any(v_cats)
    on conflict (produto_id, adicional_id) do nothing returning 1)
  select count(*) into v_novas from ins;
  perform _auditar('Adicionais vinculados em lote', v_prod || ' produtos x ' || array_length(v_ads, 1) || ' adicionais');
  return jsonb_build_object('ok', true, 'message', case when v_novas > 0 then v_novas || ' vínculos criados em ' || v_prod || ' produtos.' else 'Esses vínculos já existiam.' end);
end $$;

-- ---------------------------------------------------------------------
-- 6. Produtos
-- ---------------------------------------------------------------------
-- cria/atualiza o "estoque próprio" (produto vendido pronto, ex.: refrigerante) e devolve o id do ingrediente
create or replace function _estoque_proprio(p_atual uuid, p_nome text, p_ep jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_qtd numeric; v_un text;
begin
  if p_ep is null or jsonb_typeof(p_ep) <> 'object' or coalesce((p_ep->>'ativo')::boolean, false) is not true then
    return p_atual;   -- sem estoque próprio ativo: mantém o que já existia
  end if;
  v_un := coalesce(nullif(p_ep->>'unidade', ''), 'un');
  if v_un not in ('un','g','kg','ml','l') then v_un := 'un'; end if;
  if p_atual is not null and exists (select 1 from estoque where id = p_atual) then
    update estoque set ingrediente = p_nome, quantidade_minima = _num(p_ep->>'minimo'), unidade = v_un::unidade_estoque,
           custo_unitario = _num(p_ep->>'custo') where id = p_atual;   -- mantém a quantidade atual
    return p_atual;
  end if;
  select id into v_id from estoque where ingrediente = p_nome limit 1;   -- já existe um com esse nome: reaproveita
  if v_id is not null then return v_id; end if;
  v_id := gen_random_uuid(); v_qtd := _num(p_ep->>'quantidade');
  insert into estoque (id, ingrediente, quantidade, quantidade_minima, unidade, custo_unitario, status)
  values (v_id, p_nome, v_qtd, _num(p_ep->>'minimo'), v_un::unidade_estoque, _num(p_ep->>'custo'), 'Ativo');
  if v_qtd > 0 then
    insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
    values (v_id, 'Entrada', v_qtd, 0, v_qtd, 'Estoque inicial do cadastro', auth.uid());
  end if;
  return v_id;
end $$;

-- troca os preços de um produto (apaga e grava de novo, como a planilha fazia)
create or replace function _produto_gravar_precos(p_prod uuid, p_precos jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from produto_precos where produto_id = p_prod;
  insert into produto_precos (produto_id, forma_pagamento_id, preco, custo)
  select p_prod, _uuid(e->>'formaPagamentoId'), _num(e->>'preco'), _num(e->>'custo')
  from jsonb_array_elements(coalesce(p_precos, '[]'::jsonb)) e
  where _uuid(e->>'formaPagamentoId') is not null
  on conflict (produto_id, forma_pagamento_id) do update set preco = excluded.preco, custo = excluded.custo;
end $$;

create or replace function _produto_gravar_receita(p_prod uuid, p_ingr jsonb, p_proprio uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from produto_ingredientes where produto_id = p_prod;
  insert into produto_ingredientes (produto_id, ingrediente_id, quantidade_por_unidade)
  select p_prod, _uuid(e->>'ingredienteId'), _num(e->>'quantidadePorUnidade')
  from jsonb_array_elements(coalesce(p_ingr, '[]'::jsonb)) e where _uuid(e->>'ingredienteId') is not null;
  if p_proprio is not null then
    insert into produto_ingredientes (produto_id, ingrediente_id, quantidade_por_unidade) values (p_prod, p_proprio, 1);
  end if;
end $$;

create or replace function _produto_gravar_adicionais(p_prod uuid, p_ads jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from produto_adicionais where produto_id = p_prod;
  insert into produto_adicionais (produto_id, adicional_id)
  select distinct p_prod, _uuid(x) from jsonb_array_elements_text(coalesce(p_ads, '[]'::jsonb)) x where _uuid(x) is not null
  on conflict (produto_id, adicional_id) do nothing;
end $$;

-- lista de preços: a enviada pelo app, ou o "preço base" repetido em todas as formas
create or replace function _precos_ou_base(p jsonb) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when jsonb_typeof(p->'precos') = 'array' and jsonb_array_length(p->'precos') > 0 then p->'precos'
    else coalesce((select jsonb_agg(jsonb_build_object('formaPagamentoId', f.id, 'preco', _num(p->>'precoBase'), 'custo', _num(p->>'custoBase'))) from formas_pagamento f), '[]'::jsonb) end
$$;

create or replace function api_add_produto(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_id uuid := gen_random_uuid(); v_cat uuid := _uuid(p->>'categoria');
        v_ordem int; v_proprio uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome do produto.'); end if;
  if exists (select 1 from produtos where lower(btrim(nome)) = lower(v_nome)) then return _falha('Já existe um produto com esse nome.'); end if;
  v_proprio := _estoque_proprio(null, v_nome, p->'estoqueProprio');
  select coalesce(max(ordem_cardapio), 0) + 1 into v_ordem from produtos where categoria_id is not distinct from v_cat;
  insert into produtos (id, nome, descricao, categoria_id, ativo, destaque, estoque_proprio_ingrediente_id, ordem_cardapio)
  values (v_id, v_nome, coalesce(p->>'descricao', ''), v_cat, true, coalesce((p->>'destaque')::boolean, false), v_proprio, v_ordem);
  perform _produto_gravar_precos(v_id, _precos_ou_base(p));
  perform _produto_gravar_receita(v_id, p->'ingredientes', v_proprio);
  perform _produto_gravar_adicionais(v_id, p->'adicionaisIds');
  perform _auditar('Produto cadastrado', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Produto cadastrado.', 'id', v_id);
end $$;

create or replace function api_editar_produto(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr produtos%rowtype; v_id uuid := _uuid(p->>'id'); v_nome text := btrim(coalesce(p->>'nome', '')); v_proprio uuid; v_det text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into pr from produtos where id = v_id;
  if not found then return _falha('Produto não encontrado.'); end if;
  if v_nome = '' then return _falha('Informe o nome do produto.'); end if;
  -- detalhe dos preços que mudaram (para a auditoria), lido antes de gravar
  if jsonb_typeof(p->'precos') = 'array' then
    select coalesce(string_agg(f.nome || ': R$ ' || to_char(a.preco, 'FM999990.00') || ' → R$ ' || to_char(_num(e->>'preco'), 'FM999990.00'), '; '), '') into v_det
    from jsonb_array_elements(p->'precos') e
    join produto_precos a on a.produto_id = v_id and a.forma_pagamento_id = _uuid(e->>'formaPagamentoId')
    join formas_pagamento f on f.id = a.forma_pagamento_id
    where a.preco <> _num(e->>'preco');
  end if;
  v_proprio := _estoque_proprio(pr.estoque_proprio_ingrediente_id, v_nome, p->'estoqueProprio');
  update produtos set nome = v_nome, descricao = coalesce(p->>'descricao', ''), categoria_id = _uuid(p->>'categoria'),
         ativo = (coalesce(p->>'ativo','') <> 'false'), estoque_proprio_ingrediente_id = v_proprio where id = v_id;
  if p ? 'destaque' then update produtos set destaque = coalesce((p->>'destaque')::boolean, false) where id = v_id; end if;
  if jsonb_typeof(p->'precos') = 'array' then perform _produto_gravar_precos(v_id, p->'precos'); end if;
  perform _produto_gravar_receita(v_id, p->'ingredientes', v_proprio);
  if p ? 'adicionaisIds' then perform _produto_gravar_adicionais(v_id, p->'adicionaisIds'); end if;
  perform _auditar('Produto editado', v_nome || case when coalesce(v_det, '') <> '' then ' — Preços alterados: ' || v_det else '' end);
  return jsonb_build_object('ok', true, 'message', 'Produto atualizado.');
end $$;

create or replace function api_excluir_produto(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if exists (select 1 from combo_itens where produto_id = v_id) then
    return _falha('Este produto faz parte de um ou mais combos. Tire-o dos combos antes de excluir (ou deixe-o inativo).');
  end if;
  delete from produtos where id = v_id;   -- preços, receita e adicionais saem junto
  perform _auditar('Produto excluído', v_id::text);
  return jsonb_build_object('ok', true);
end $$;

create or replace function api_editar_visibilidade_cardapio_produto(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from produtos where id = v_id) then return _falha('Produto não encontrado.'); end if;
  if p ? 'ativo' then update produtos set ativo = (coalesce(p->>'ativo','') <> 'false') where id = v_id; end if;
  if p ? 'destaque' then update produtos set destaque = coalesce((p->>'destaque')::boolean, false) where id = v_id; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function api_editar_ordem_cardapio_produto(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from produtos where id = v_id) then return _falha('Produto não encontrado.'); end if;
  update produtos set ordem_cardapio = _num(p->>'ordem')::int where id = v_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 7. Combos
-- ---------------------------------------------------------------------
create or replace function _combo_gravar_precos(p_combo uuid, p_precos jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from combo_precos where combo_id = p_combo;
  insert into combo_precos (combo_id, forma_pagamento_id, preco, custo)
  select p_combo, _uuid(e->>'formaPagamentoId'), _num(e->>'preco'), _num(e->>'custo')
  from jsonb_array_elements(coalesce(p_precos, '[]'::jsonb)) e where _uuid(e->>'formaPagamentoId') is not null
  on conflict (combo_id, forma_pagamento_id) do update set preco = excluded.preco, custo = excluded.custo;
end $$;

create or replace function _combo_gravar_itens(p_combo uuid, p_itens jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from combo_itens where combo_id = p_combo;
  insert into combo_itens (combo_id, produto_id, quantidade)
  select p_combo, _uuid(e->>'produtoId'), _num(e->>'quantidade')::int
  from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) e
  where _uuid(e->>'produtoId') is not null and _num(e->>'quantidade') > 0;
end $$;

create or replace function api_add_combo(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_id uuid := gen_random_uuid(); v_cat uuid := _uuid(p->>'categoria'); v_ordem int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome do combo.'); end if;
  if exists (select 1 from combos where lower(btrim(nome)) = lower(v_nome)) then return _falha('Já existe um combo com esse nome.'); end if;
  select coalesce(max(ordem_cardapio), 0) + 1 into v_ordem from combos where categoria_id is not distinct from v_cat;
  insert into combos (id, nome, categoria_id, ativo, destaque, ordem_cardapio)
  values (v_id, v_nome, v_cat, true, coalesce((p->>'destaque')::boolean, false), v_ordem);
  perform _combo_gravar_precos(v_id, _precos_ou_base(p));
  perform _combo_gravar_itens(v_id, p->'itens');
  perform _auditar('Combo cadastrado', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Combo cadastrado.', 'id', v_id);
end $$;

create or replace function api_editar_combo(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id'); v_nome text := btrim(coalesce(p->>'nome', '')); v_det text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from combos where id = v_id) then return _falha('Combo não encontrado.'); end if;
  if v_nome = '' then return _falha('Informe o nome do combo.'); end if;
  if jsonb_typeof(p->'precos') = 'array' then
    select coalesce(string_agg(f.nome || ': R$ ' || to_char(a.preco, 'FM999990.00') || ' → R$ ' || to_char(_num(e->>'preco'), 'FM999990.00'), '; '), '') into v_det
    from jsonb_array_elements(p->'precos') e
    join combo_precos a on a.combo_id = v_id and a.forma_pagamento_id = _uuid(e->>'formaPagamentoId')
    join formas_pagamento f on f.id = a.forma_pagamento_id
    where a.preco <> _num(e->>'preco');
  end if;
  update combos set nome = v_nome, categoria_id = _uuid(p->>'categoria'), ativo = (coalesce(p->>'ativo','') <> 'false') where id = v_id;
  if p ? 'destaque' then update combos set destaque = coalesce((p->>'destaque')::boolean, false) where id = v_id; end if;
  if jsonb_typeof(p->'precos') = 'array' then perform _combo_gravar_precos(v_id, p->'precos'); end if;
  if jsonb_typeof(p->'itens') = 'array' then perform _combo_gravar_itens(v_id, p->'itens'); end if;
  perform _auditar('Combo editado', v_nome || case when coalesce(v_det, '') <> '' then ' — Preços alterados: ' || v_det else '' end);
  return jsonb_build_object('ok', true, 'message', 'Combo atualizado.');
end $$;

create or replace function api_excluir_combo(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  delete from combos where id = v_id;   -- preços e itens saem junto
  perform _auditar('Combo excluído', v_id::text);
  return jsonb_build_object('ok', true);
end $$;

create or replace function api_editar_visibilidade_cardapio_combo(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from combos where id = v_id) then return _falha('Combo não encontrado.'); end if;
  if p ? 'ativo' then update combos set ativo = (coalesce(p->>'ativo','') <> 'false') where id = v_id; end if;
  if p ? 'destaque' then update combos set destaque = coalesce((p->>'destaque')::boolean, false) where id = v_id; end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function api_editar_ordem_cardapio_combo(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from combos where id = v_id) then return _falha('Combo não encontrado.'); end if;
  update combos set ordem_cardapio = _num(p->>'ordem')::int where id = v_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 8. Mesas
-- ---------------------------------------------------------------------
create or replace function api_add_mesa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_num text := btrim(coalesce(p->>'numero', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_num = '' then return _falha('Informe o número da mesa.'); end if;
  if exists (select 1 from mesas where numero = v_num) then return _falha('Já existe uma mesa com esse número.'); end if;
  insert into mesas (numero, status, capacidade) values (v_num, 'Livre', nullif(_num(p->>'capacidade'), 0)::int);
  perform _auditar('Mesa cadastrada', 'Mesa ' || v_num);
  return jsonb_build_object('ok', true, 'message', 'Mesa cadastrada.');
end $$;

create or replace function api_editar_status_mesa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m mesas%rowtype; v_id uuid := _uuid(p->>'id'); v_novo text := p->>'novoStatus'; v_eu uuid := auth.uid(); v_nivel nivel_acesso := auth_nivel();
begin
  if v_nivel is null or v_nivel not in ('Admin','Operador','Garçom') then return _negado(); end if;
  if v_novo is null or v_novo not in ('Livre','Ocupada','Aguardando fechamento','Fechada','Bloqueada/Manutenção') then return _falha('Status de mesa inválido.'); end if;
  select * into m from mesas where id = v_id;
  if not found then return _falha('Mesa não encontrada.'); end if;
  if v_nivel = 'Garçom' then
    if not ((m.status = 'Livre' and v_novo = 'Ocupada') or (m.status = 'Ocupada' and v_novo = 'Aguardando fechamento')) then
      return _falha('O garçom só pode abrir uma mesa livre ou pedir o fechamento de uma mesa ocupada.');
    end if;
    if m.status = 'Ocupada' and m.garcom_responsavel_id is not null and m.garcom_responsavel_id <> v_eu then
      return _falha('Esta mesa está sob responsabilidade de outro garçom.');
    end if;
    update mesas set status = v_novo::status_mesa where id = m.id;
    if v_novo = 'Ocupada' then update mesas set garcom_responsavel_id = v_eu where id = m.id; end if;
    if p ? 'observacao' then update mesas set observacao = p->>'observacao' where id = m.id; end if;
    if v_novo = 'Aguardando fechamento' then perform _auditar('Fechamento de mesa solicitado', 'Mesa ' || m.numero); end if;
  else
    update mesas set status = v_novo::status_mesa where id = m.id;
    if p ? 'observacao' then update mesas set observacao = p->>'observacao' where id = m.id; end if;
    if v_novo = 'Livre' then update mesas set garcom_responsavel_id = null where id = m.id; end if;
  end if;
  perform _auditar('Status de mesa alterado', 'Mesa ' || m.numero || ': ' || m.status || ' → ' || v_novo);
  return jsonb_build_object('ok', true);
end $$;

create or replace function api_excluir_mesa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m mesas%rowtype; v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into m from mesas where id = v_id;
  if found and m.status = 'Ocupada' then return _falha('Não é possível excluir uma mesa ocupada.'); end if;
  delete from mesas where id = v_id;
  perform _auditar('Mesa excluída', coalesce('Mesa ' || m.numero, v_id::text));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 9. Configurações e metas
-- ---------------------------------------------------------------------
create or replace function api_salvar_config_notificacoes(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_antes jsonb; v_novo jsonb; k text; e jsonb; v_perfis jsonb;
        v_ids text[] := array['pedido','entrega','estoque','financeiro','ocorrencia','sistema','fidelidade','indicacao','aniversario','inativos'];
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if jsonb_typeof(p->'eventos') <> 'object' then return _falha('Configuração inválida.'); end if;
  select coalesce(valor, '{}'::jsonb) into v_antes from sistema where chave = 'NotificacoesConfig';
  if v_antes is null or jsonb_typeof(v_antes) <> 'object' then v_antes := '{}'::jsonb; end if;
  v_novo := v_antes;
  foreach k in array v_ids loop
    e := p->'eventos'->k;
    if e is null or jsonb_typeof(e) <> 'object' then continue; end if;
    select coalesce(jsonb_agg(distinct x), '[]'::jsonb) into v_perfis
      from jsonb_array_elements_text(case when jsonb_typeof(e->'perfis') = 'array' then e->'perfis' else '[]'::jsonb end) x
      where x in ('Admin','Operador','Cozinha');
    v_novo := v_novo || jsonb_build_object(k, jsonb_build_object('ativo', (coalesce(e->>'ativo','') <> 'false'), 'perfis', v_perfis));
  end loop;
  if length(v_novo::text) > 4000 then return _falha('Configuração grande demais.'); end if;
  perform _cfg_gravar('NotificacoesConfig', v_novo);
  if v_novo <> v_antes then perform _auditar('Configuração de notificações alterada', 'Eventos atualizados'); end if;
  return jsonb_build_object('ok', true, 'message', case when v_novo <> v_antes then 'Notificações atualizadas.' else 'Nada mudou.' end);
end $$;

create or replace function api_salvar_config_estoque(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_b boolean := coalesce(p->>'bloquear', '') in ('true', 't');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  perform _cfg_gravar('BLOQUEAR_ESTOQUE_NEGATIVO', to_jsonb(v_b));
  perform _auditar('Regra de estoque alterada', 'Bloquear venda sem estoque: ' || case when v_b then 'Sim' else 'Não' end);
  return jsonb_build_object('ok', true, 'message', 'Regra de estoque salva.');
end $$;

create or replace function api_salvar_config_cardapio(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  perform _cfg_gravar('CardapioKicker', to_jsonb(coalesce(p->>'kicker', '')));
  perform _cfg_gravar('CardapioFrase', to_jsonb(coalesce(p->>'frase', '')));
  if p ? 'tempoEntrega' then perform _cfg_gravar('CardapioTempoEntrega', to_jsonb(coalesce(p->>'tempoEntrega', ''))); end if;
  if p ? 'tempoRetirada' then perform _cfg_gravar('CardapioTempoRetirada', to_jsonb(coalesce(p->>'tempoRetirada', ''))); end if;
  if p ? 'tempoMesa' then perform _cfg_gravar('CardapioTempoMesa', to_jsonb(coalesce(p->>'tempoMesa', ''))); end if;
  perform _auditar('Configuração do Cardápio Digital atualizada');
  return jsonb_build_object('ok', true, 'message', 'Cardápio atualizado.');
end $$;

create or replace function api_salvar_config_entrega(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t numeric := _num(p->>'taxaPadrao', -1); a numeric := _num(p->>'ajudaDiaria', -1); v_t0 numeric; v_a0 numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if t < 0 or t > 500 then return _falha('Taxa de entrega inválida.'); end if;
  if a < 0 or a > 1000 then return _falha('Ajuda diária inválida.'); end if;
  select coalesce(_num(valor #>> '{}'), 0) into v_t0 from sistema where chave = 'TaxaEntregaPadrao';
  select coalesce(_num(valor #>> '{}'), 0) into v_a0 from sistema where chave = 'AjudaDiariaEntregador';
  perform _cfg_gravar('TaxaEntregaPadrao', to_jsonb(round(t, 2)));
  perform _cfg_gravar('AjudaDiariaEntregador', to_jsonb(round(a, 2)));
  perform _auditar('Configuração de entrega alterada', 'Taxa: R$ ' || to_char(coalesce(v_t0, 0), 'FM999990.00') || ' → R$ ' || to_char(t, 'FM999990.00')
    || ' | Ajuda diária: R$ ' || to_char(coalesce(v_a0, 0), 'FM999990.00') || ' → R$ ' || to_char(a, 'FM999990.00') || ' (vale só para pedidos e fechamentos futuros)');
  return jsonb_build_object('ok', true, 'message', 'Configuração de entrega salva.');
end $$;

create or replace function api_salvar_meta(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_tipo text := p->>'tipo'; v_val numeric := _num(p->>'valor');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_tipo is null or v_tipo not in ('MetaMensal','MetaDiaria') then return _falha('Tipo de meta inválido.'); end if;
  perform _cfg_gravar(v_tipo, to_jsonb(v_val));
  perform _auditar('Meta atualizada', v_tipo || ': R$ ' || to_char(v_val, 'FM999990.00'));
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 10. Clientes (cadastrar/editar; excluir fica para a 3c, que tem confirmação de senha do Admin)
-- ---------------------------------------------------------------------
create or replace function _so_digitos(t text) returns text language sql immutable as $$
  select regexp_replace(coalesce(t, ''), '\D', '', 'g')
$$;

create or replace function api_salvar_cliente(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_tel text := btrim(coalesce(p->>'telefone', ''));
        v_alvo text := nullif(btrim(coalesce(p->>'id', '')), ''); v_nasc date; v_id uuid; v_novo_id uuid := gen_random_uuid();
begin
  if not tem_nivel('Admin','Operador','Garçom') then return _negado(); end if;
  if v_nome = '' or v_tel = '' then return _falha('Nome e telefone são obrigatórios.'); end if;
  begin v_nasc := nullif(btrim(coalesce(p->>'dataNascimento', '')), '')::date; exception when others then v_nasc := null; end;
  -- o cliente que estamos editando (por id; por compatibilidade, também pelo telefone original)
  if v_alvo is not null then
    select id into v_id from clientes where id::text = v_alvo or _so_digitos(telefone) = _so_digitos(v_alvo) limit 1;
  end if;
  if exists (select 1 from clientes where _so_digitos(telefone) = _so_digitos(v_tel) and id is distinct from v_id) then
    return _falha('Já existe outro cliente cadastrado com esse telefone.');
  end if;
  if v_alvo is not null then
    if v_id is null then return _falha('Cliente não encontrado para edição.'); end if;
    update clientes set nome = v_nome, telefone = v_tel, data_nascimento = v_nasc, endereco = coalesce(p->>'endereco', ''), como_conheceu = coalesce(p->>'comoConheceu', '') where id = v_id;
    if p ? 'observacao' then update clientes set observacoes = coalesce(p->>'observacao', '') where id = v_id; end if;
    perform _auditar('Cliente atualizado', v_nome, v_tel);
    return jsonb_build_object('ok', true, 'message', 'Cadastro atualizado.');
  end if;
  insert into clientes (id, nome, telefone, data_nascimento, endereco, como_conheceu, primeiro_contato, observacoes)
  values (v_novo_id, v_nome, v_tel, v_nasc, coalesce(p->>'endereco', ''), coalesce(p->>'comoConheceu', ''), now(), coalesce(p->>'observacao', ''));
  perform _auditar('Cliente cadastrado', v_nome, v_tel);
  return jsonb_build_object('ok', true, 'message', 'Cliente cadastrado.');
end $$;

-- ---------------------------------------------------------------------
-- 11. Quem pode chamar: só usuário logado (nunca o visitante)
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as assinatura, p.proname from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'api\_%' or p.proname like '\_%') loop
    execute format('revoke all on function %s from public, anon', f.assinatura);
    if f.proname like 'api\_%' then execute format('grant execute on function %s to authenticated', f.assinatura); end if;
  end loop;
end $$;
-- (as funções auxiliares com "_" no começo ficam sem acesso direto: só as "api_" as usam por dentro)
grant execute on function _num(text, numeric), _uuid(text), _so_digitos(text) to authenticated;

-- FIM DO ARQUIVO


-- >>>>>>>>>> 01_usuarios_estoque_sangria.sql <<<<<<<<<<
-- =====================================================================
-- Texas Burger — Etapa 3c, parte 1: usuários e senhas, estoque (entrada/perda/inventário), sangria, excluir cliente
-- Rodar DEPOIS da 3b (usa as funções auxiliares dela). Arquivo único. Pode rodar de novo (create or replace).
-- Caixa e vendas ficam para a 3c-2; pedidos públicos, cupons, fidelidade, despesas e eventos, para a 3c-3.
-- =====================================================================

-- =====================================================================
-- Texas Burger — Etapa 3c, parte 1: usuários e senhas, estoque (entrada/perda/inventário), sangria, excluir cliente
-- Rodar DEPOIS da 3b (usa as funções auxiliares dela). Pode rodar de novo (create or replace).
--
-- Caixa e vendas ficam para a 3c-2; pedidos públicos, cupons, fidelidade, despesas e eventos, para a 3c-3.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Peças de apoio
-- ---------------------------------------------------------------------
-- Controle de tentativas erradas de senha (substitui o "cache" do Apps Script). Sem política = só o servidor acessa.
create table if not exists tentativas (
  chave text primary key,
  falhas integer not null default 0,
  bloqueado_ate timestamptz
);
alter table tentativas enable row level security;

create or replace function _excedeu(p_chave text, p_max int) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select falhas >= p_max and bloqueado_ate > now() from tentativas where chave = p_chave), false)
$$;

-- O prazo de bloqueio conta a partir do PRIMEIRO erro e não é renovado a cada novo erro.
create or replace function _registrar_falha(p_chave text, p_seg int default 600) returns int
language plpgsql security definer set search_path = public as $$
declare t tentativas%rowtype;
begin
  select * into t from tentativas where chave = p_chave for update;
  if not found then
    insert into tentativas (chave, falhas, bloqueado_ate) values (p_chave, 1, now() + make_interval(secs => p_seg));
    return 1;
  end if;
  if t.bloqueado_ate is null or t.bloqueado_ate <= now() then
    update tentativas set falhas = 1, bloqueado_ate = now() + make_interval(secs => p_seg) where chave = p_chave;
    return 1;
  end if;
  update tentativas set falhas = falhas + 1 where chave = p_chave;
  return t.falhas + 1;
end $$;

create or replace function _limpar_falhas(p_chave text) returns void
language sql security definer set search_path = public as $$
  delete from tentativas where chave = p_chave
$$;

-- Auditoria passa a registrar "autorizado por" (Admin que digitou a senha, quando quem agiu foi o Operador)
create or replace function _auditar(p_acao text, p_detalhes text default null, p_telefone text default null) returns void
language sql security definer set search_path = public as $$
  insert into auditoria (usuario_id, usuario_login, perfil, acao, telefone, detalhes, autorizado_por)
  select u.id, u.login, u.nivel::text, p_acao, p_telefone, p_detalhes, nullif(current_setting('app.autorizador', true), '')
  from usuarios u where u.id = auth.uid()
$$;

-- Quem está logado só vale enquanto a SESSÃO dele existir: ao encerrar um aparelho remotamente, o acesso cai na hora.
create or replace function auth_nivel() returns nivel_acesso
language sql stable security definer set search_path = public as $$
  select u.nivel from usuarios u
  where u.id = auth.uid() and u.ativo
    and (coalesce(auth.jwt() ->> 'session_id', '') = ''
         or exists (select 1 from auth.sessions s where s.id = (auth.jwt() ->> 'session_id')::uuid))
$$;

-- Senha de uma pessoa confere? (compara com o hash guardado pelo Auth)
create or replace function _senha_confere(p_user uuid, p_senha text) returns boolean
language sql stable security definer set search_path = public, auth, extensions as $$
  select coalesce((select u.encrypted_password = crypt(p_senha, u.encrypted_password) from auth.users u where u.id = p_user), false)
$$;

create or replace function _erro_senha_fraca(p_senha text, p_login text) returns text
language sql immutable as $$
  select case
    when length(coalesce(p_senha, '')) < 8 then 'A senha precisa ter ao menos 8 caracteres.'
    when p_login is not null and lower(p_senha) = lower(p_login) then 'A senha não pode ser igual ao login.'
    when p_senha ~ '^(.)\1+$' or lower(p_senha) in ('12345678','123456789','1234567890','87654321','senha123','password','qwertyui','11111111')
      then 'Essa senha é fácil demais de adivinhar. Escolha outra.'
    else '' end
$$;

-- login digitado → e-mail interno (sem acento, minúsculo): igual ao que o app faz
create or replace function _email_login(p_login text) returns text
language sql immutable as $$
  select translate(lower(btrim(p_login)), 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ', 'aaaaaaceeeeiiiinooooouuuuyy') || '@usuarios.texasburger.app'
$$;

-- Confirmação do Admin: o Admin autoriza a si mesmo; os demais precisam da senha de um Admin ativo.
-- Devolve o login de quem autorizou (ou null se não autorizado) e deixa o nome para a auditoria.
create or replace function _exige_admin(p_senha text) returns text
language plpgsql security definer set search_path = public, auth, extensions as $$
declare v_eu usuarios%rowtype; v_chave text; v_adm record;
begin
  select * into v_eu from usuarios where id = auth.uid() and ativo;
  if not found then return null; end if;
  if v_eu.nivel = 'Admin' then perform set_config('app.autorizador', v_eu.login, true); return v_eu.login; end if;
  if coalesce(p_senha, '') = '' then return null; end if;
  v_chave := 'falhas_admin_' || lower(v_eu.login);
  if _excedeu(v_chave, 5) then return null; end if;
  select us.login into v_adm from usuarios us join auth.users au on au.id = us.id
    where us.nivel = 'Admin' and us.ativo and au.encrypted_password = crypt(p_senha, au.encrypted_password) limit 1;
  if found then
    perform _limpar_falhas(v_chave);
    perform set_config('app.autorizador', v_adm.login, true);
    return v_adm.login;
  end if;
  perform _registrar_falha(v_chave);
  perform _auditar('Falha na senha de administrador', 'Tentativa por ' || v_eu.login);
  return null;
end $$;

-- ---------------------------------------------------------------------
-- 1. Confirmar senha de Admin (usada pelo Operador antes de ações sensíveis)
-- ---------------------------------------------------------------------
create or replace function api_verificar_senha_admin(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth_nivel() is null then return _negado(); end if;
  return jsonb_build_object('ok', _exige_admin(p->>'senha') is not null);
end $$;

-- ---------------------------------------------------------------------
-- 2. Usuários
-- ---------------------------------------------------------------------
create or replace function _criar_login_auth(p_id uuid, p_email text, p_senha text) returns void
language plpgsql security definer set search_path = public, auth, extensions as $$
begin
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token)
  values ('00000000-0000-0000-0000-000000000000', p_id, 'authenticated', 'authenticated', p_email,
    crypt(p_senha, gen_salt('bf')), now(),
    '{"provider":"email","providers":["email"]}'::jsonb, '{}'::jsonb, now(), now(), '', '', '', '', '', '', '', '');
  insert into auth.identities (id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at)
  values (gen_random_uuid(), p_id, jsonb_build_object('sub', p_id::text, 'email', p_email, 'email_verified', true, 'phone_verified', false),
          'email', p_id::text, now(), now(), now());
end $$;

create or replace function api_criar_usuario(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare v_login text := btrim(coalesce(p->>'novoLogin', '')); v_senha text := coalesce(p->>'novaSenha', ''); v_nivel text := p->>'nivel';
        v_erro text; v_id uuid := gen_random_uuid(); v_email text; v_aut text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_login = '' or v_senha = '' or coalesce(v_nivel, '') = '' then return _falha('Preencha login, senha e nível de acesso.'); end if;
  if v_login !~ '^[A-Za-z0-9\u00C0-\u00FF][A-Za-z0-9\u00C0-\u00FF._-]{2,29}$' then
    return _falha('Login inválido: use de 3 a 30 caracteres (letras, números, ponto, hífen ou sublinhado), começando por letra ou número e sem espaços.');
  end if;
  v_erro := _erro_senha_fraca(v_senha, v_login);
  if v_erro <> '' then return _falha(v_erro); end if;
  if v_nivel not in ('Admin','Operador','Garçom','Cozinha','Entregador') then return _falha('Nível de acesso inválido.'); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  v_email := _email_login(v_login);
  if exists (select 1 from usuarios where lower(login) = lower(v_login)) or exists (select 1 from auth.users where lower(email) = v_email) then
    return _falha('Já existe um usuário com esse login.');
  end if;
  perform _criar_login_auth(v_id, v_email, v_senha);
  insert into usuarios (id, login, nome, telefone, nivel, ativo)
  values (v_id, v_login, left(coalesce(p->>'nome', ''), 60), left(coalesce(p->>'telefone', ''), 25), v_nivel::nivel_acesso, true);
  perform _auditar('Usuário criado', v_login || ' (' || v_nivel || ')');
  return jsonb_build_object('ok', true, 'message', 'Usuário criado.');
end $$;

create or replace function api_editar_usuario(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare u usuarios%rowtype; v_alvo text := coalesce(p->>'loginAlvo', ''); v_aut text; v_erro text;
        v_sera_admin boolean; v_sera_ativo boolean; v_contato boolean := false; v_nome text; v_tel text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if p ? 'nome' and length(coalesce(p->>'nome', '')) > 60 then return _falha('O nome pode ter no máximo 60 caracteres.'); end if;
  if p ? 'telefone' and length(coalesce(p->>'telefone', '')) > 25 then return _falha('O telefone pode ter no máximo 25 caracteres.'); end if;
  if p ? 'novoNivel' and coalesce(p->>'novoNivel', '') not in ('Admin','Operador','Garçom','Cozinha','Entregador') then return _falha('Nível de acesso inválido.'); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  select * into u from usuarios where lower(login) = lower(v_alvo);
  if not found then return _falha('Usuário não encontrado.'); end if;
  v_sera_admin := case when p ? 'novoNivel' then p->>'novoNivel' = 'Admin' else u.nivel = 'Admin' end;
  v_sera_ativo := case when p ? 'novoAtivo' then coalesce((p->>'novoAtivo')::boolean, false) else u.ativo end;
  if u.nivel = 'Admin' and (not v_sera_admin or not v_sera_ativo) then
    if not exists (select 1 from usuarios where nivel = 'Admin' and ativo and id <> u.id) then
      return _falha('Não é possível remover o último administrador ativo.');
    end if;
  end if;
  if coalesce(p->>'novaSenha', '') <> '' then
    v_erro := _erro_senha_fraca(p->>'novaSenha', u.login);
    if v_erro <> '' then return _falha(v_erro); end if;
    update auth.users set encrypted_password = crypt(p->>'novaSenha', gen_salt('bf')), updated_at = now() where id = u.id;
    delete from auth.sessions where user_id = u.id;   -- senha nova: o usuário entra de novo em todos os aparelhos
  end if;
  if p ? 'novoNivel' then update usuarios set nivel = (p->>'novoNivel')::nivel_acesso where id = u.id; end if;
  if p ? 'novoAtivo' then
    update usuarios set ativo = v_sera_ativo where id = u.id;
    if not v_sera_ativo then delete from auth.sessions where user_id = u.id; end if;
  end if;
  if p ? 'nome' then v_nome := btrim(coalesce(p->>'nome', '')); if v_nome <> coalesce(u.nome, '') then update usuarios set nome = v_nome where id = u.id; v_contato := true; end if; end if;
  if p ? 'telefone' then v_tel := btrim(coalesce(p->>'telefone', '')); if v_tel <> coalesce(u.telefone, '') then update usuarios set telefone = v_tel where id = u.id; v_contato := true; end if; end if;
  perform _auditar('Usuário editado', u.login || case when coalesce(p->>'novaSenha', '') <> '' then ' (senha alterada)' else '' end
    || case when v_contato then ' (nome/telefone alterado)' else '' end
    || case when p ? 'novoNivel' then ' nível=' || (p->>'novoNivel') else '' end
    || case when p ? 'novoAtivo' then ' ativo=' || case when v_sera_ativo then 'Sim' else 'Não' end else '' end);
  return jsonb_build_object('ok', true, 'message', 'Usuário atualizado.');
end $$;

create or replace function api_excluir_usuario(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare u usuarios%rowtype; v_aut text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  select * into u from usuarios where lower(login) = lower(coalesce(p->>'loginAlvo', ''));
  if not found then return _falha('Usuário não encontrado.'); end if;
  if u.nivel = 'Admin' and not exists (select 1 from usuarios where nivel = 'Admin' and ativo and id <> u.id) then
    return _falha('Não é possível excluir o último administrador.');
  end if;
  perform _auditar('Usuário excluído', u.login);
  delete from auth.users where id = u.id;   -- leva junto a linha de usuarios, a identidade e as sessões; o histórico fica (autor vira vazio)
  return jsonb_build_object('ok', true);
end $$;

create or replace function api_trocar_minha_senha(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare u usuarios%rowtype; v_atual text := coalesce(p->>'senhaAtual', ''); v_nova text := coalesce(p->>'novaSenha', ''); v_chave text; v_erro text;
        v_sessao uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
begin
  select * into u from usuarios where id = auth.uid();
  if not found then return _falha('Sessão inválida. Faça login novamente.'); end if;
  if v_atual = '' or v_nova = '' then return _falha('Preencha a senha atual e a nova senha.'); end if;
  v_chave := 'falhas_troca_' || lower(u.login);
  if _excedeu(v_chave, 5) then return _falha('Muitas tentativas erradas. Aguarde 10 minutos e tente de novo.'); end if;
  if not u.ativo then return _falha('Este acesso está desativado.'); end if;
  if not _senha_confere(u.id, v_atual) then
    perform _registrar_falha(v_chave);
    perform _auditar('Falha ao trocar a própria senha', 'Senha atual incorreta: ' || u.login);
    return _falha('A senha atual está incorreta.');
  end if;
  if v_nova = v_atual then return _falha('A nova senha precisa ser diferente da atual.'); end if;
  v_erro := _erro_senha_fraca(v_nova, u.login);
  if v_erro <> '' then return _falha(v_erro); end if;
  update auth.users set encrypted_password = crypt(v_nova, gen_salt('bf')), updated_at = now() where id = u.id;
  perform _limpar_falhas(v_chave);
  delete from auth.sessions where user_id = u.id and id is distinct from v_sessao;   -- outros aparelhos precisam entrar de novo
  perform _auditar('Senha alterada pelo próprio usuário', u.login);
  return jsonb_build_object('ok', true, 'message', 'Senha alterada. Em outros aparelhos você precisará entrar de novo.');
end $$;

create or replace function api_listar_sessoes(p jsonb) returns jsonb
language plpgsql stable security definer set search_path = public, auth, extensions as $$
declare v_atual uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  return jsonb_build_object('ok', true, 'sessoes', coalesce((
    select jsonb_agg(x order by (x->>'vistoMs')::bigint desc) from (
      select jsonb_build_object(
        'sessaoId', left(replace(s.id::text, '-', ''), 12), 'login', u.login, 'nivel', u.nivel, 'deviceId', '',
        'ua', coalesce(s.user_agent, ''),
        'criadaEm', to_char(s.created_at at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
        'vistoEm', to_char(coalesce(s.refreshed_at, s.updated_at, s.created_at) at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
        'vistoMs', (extract(epoch from coalesce(s.refreshed_at, s.updated_at, s.created_at)) * 1000)::bigint,
        'atual', s.id = v_atual) as x
      from auth.sessions s join usuarios u on u.id = s.user_id
    ) t), '[]'::jsonb));
end $$;

create or replace function api_encerrar_sessao_remota(p jsonb) returns jsonb
language plpgsql security definer set search_path = public, auth, extensions as $$
declare v_alvo text := coalesce(p->>'sessaoId', ''); s record; v_atual uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_alvo !~ '^[0-9a-f]{12}$' then return _falha('Sessão inválida.'); end if;
  select se.id, us.login, se.user_agent into s from auth.sessions se join usuarios us on us.id = se.user_id
    where left(replace(se.id::text, '-', ''), 12) = v_alvo limit 1;
  if not found then return _falha('Sessão não encontrada (talvez já tenha expirado).'); end if;
  if s.id = v_atual then return _falha('Esta é a sua sessão atual. Use "Sair" para encerrá-la.'); end if;
  delete from auth.sessions where id = s.id;
  perform _auditar('Acesso encerrado remotamente (usuário)', 'Sessão de ' || s.login || ' | ' || coalesce(s.user_agent, ''));
  return jsonb_build_object('ok', true, 'message', 'Sessão de ' || s.login || ' encerrada.');
end $$;

-- ---------------------------------------------------------------------
-- 3. Excluir cliente (precisa da senha de Admin quando quem pede não é Admin)
-- ---------------------------------------------------------------------
create or replace function api_excluir_cliente(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_id uuid := _uuid(p->>'id'); v_aut text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  delete from clientes where id = v_id;   -- vendas antigas ficam com o nome e telefone gravados
  perform _auditar('Cliente excluído', v_id::text);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 4. Estoque: entrada, perda e inventário (saldo e histórico gravados juntos, com trava contra duas mudanças ao mesmo tempo)
-- ---------------------------------------------------------------------
-- repetir o mesmo pedido (mesmo requisicaoId) devolve a resposta da primeira vez, sem mexer de novo
create or replace function _idem_ler(p_chave text) returns jsonb
language sql stable security definer set search_path = public as $$
  select resultado from requisicoes where chave = p_chave
$$;
create or replace function _idem_gravar(p_chave text, p_acao text, p_resultado jsonb) returns void
language sql security definer set search_path = public as $$
  insert into requisicoes (chave, acao, resultado, usuario_id) values (p_chave, p_acao, p_resultado, auth.uid())
  on conflict (chave) do nothing
$$;

create or replace function api_registrar_entrada_estoque(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e estoque%rowtype; v_qtd numeric := _num(p->>'quantidade'); v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb; v_depois numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  if v_qtd <= 0 then return _falha('Informe uma quantidade de entrada maior que zero.'); end if;
  select * into e from estoque where id = _uuid(p->>'ingredienteId') for update;
  if not found then return _falha('Ingrediente não encontrado.'); end if;
  v_depois := e.quantidade + v_qtd;
  update estoque set quantidade = v_depois where id = e.id;
  insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
  values (e.id, 'Entrada', v_qtd, e.quantidade, v_depois, coalesce(nullif(p->>'motivo', ''), 'Reposição de estoque'), auth.uid());
  perform _auditar('Entrada de estoque', e.ingrediente || ': +' || v_qtd);
  v_r := jsonb_build_object('ok', true, 'message', 'Entrada registrada.');
  if v_req is not null then perform _idem_gravar(v_req, 'registrarEntradaEstoque', v_r); end if;
  return v_r;
end $$;

create or replace function api_registrar_perda_estoque(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e estoque%rowtype; v_qtd numeric := _num(p->>'quantidade'); v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb; v_depois numeric; v_motivo text := btrim(coalesce(p->>'motivo', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  if v_qtd <= 0 then return _falha('Informe uma quantidade de perda maior que zero.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo da perda.'); end if;
  select * into e from estoque where id = _uuid(p->>'ingredienteId') for update;
  if not found then return _falha('Ingrediente não encontrado.'); end if;
  v_depois := greatest(0, e.quantidade - v_qtd);
  update estoque set quantidade = v_depois where id = e.id;
  insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
  values (e.id, 'Perda', -v_qtd, e.quantidade, v_depois, v_motivo, auth.uid());
  perform _auditar('Perda de estoque', e.ingrediente || ': -' || v_qtd || ' (' || v_motivo || ')');
  v_r := jsonb_build_object('ok', true, 'message', 'Perda registrada.');
  if v_req is not null then perform _idem_gravar(v_req, 'registrarPerdaEstoque', v_r); end if;
  return v_r;
end $$;

create or replace function api_registrar_inventario_estoque(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare e estoque%rowtype; v_nova numeric := _num(p->>'novaQuantidade', -1); v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  if v_nova < 0 then return _falha('Informe uma quantidade de inventário válida.'); end if;
  select * into e from estoque where id = _uuid(p->>'ingredienteId') for update;
  if not found then return _falha('Ingrediente não encontrado.'); end if;
  update estoque set quantidade = v_nova where id = e.id;
  insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
  values (e.id, 'Inventário', v_nova - e.quantidade, e.quantidade, v_nova, coalesce(nullif(p->>'motivo', ''), 'Contagem de inventário'), auth.uid());
  perform _auditar('Inventário de estoque', e.ingrediente || ': ' || e.quantidade || ' → ' || v_nova || ' (contagem física)');
  v_r := jsonb_build_object('ok', true, 'message', 'Inventário registrado.');
  if v_req is not null then perform _idem_gravar(v_req, 'registrarInventarioEstoque', v_r); end if;
  return v_r;
end $$;

-- ---------------------------------------------------------------------
-- 5. Sangria (retirada de dinheiro da gaveta)
-- ---------------------------------------------------------------------
create or replace function api_add_sangria(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_valor numeric := _num(p->>'valor'); v_motivo text := btrim(coalesce(p->>'motivo', '')); v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  if v_valor <= 0 then return _falha('Informe um valor de sangria maior que zero.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo da sangria.'); end if;
  insert into sangrias (valor, motivo, usuario_id, caixa_id)
  values (round(v_valor, 2), v_motivo, auth.uid(), (select id from caixa_sessoes where status = 'Aberto' limit 1));
  perform _auditar('Sangria registrada', v_motivo || ' = R$ ' || to_char(v_valor, 'FM999990.00'));
  v_r := jsonb_build_object('ok', true, 'message', 'Sangria registrada: R$ ' || to_char(v_valor, 'FM999990.00'));
  if v_req is not null then perform _idem_gravar(v_req, 'addSangria', v_r); end if;
  return v_r;
end $$;

-- ---------------------------------------------------------------------
-- 6. Quem pode chamar (mesma regra da 3b): só usuário logado; auxiliares "_" sem acesso direto
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as assinatura, p.proname from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'api\_%' or p.proname like '\_%' or p.proname in ('auth_nivel')) loop
    execute format('revoke all on function %s from public, anon', f.assinatura);
    if f.proname like 'api\_%' or f.proname = 'auth_nivel' then execute format('grant execute on function %s to authenticated', f.assinatura); end if;
  end loop;
end $$;
grant execute on function _num(text, numeric), _uuid(text), _so_digitos(text) to authenticated;

-- FIM DO ARQUIVO


-- >>>>>>>>>> 01_caixa_vendas.sql <<<<<<<<<<
-- =====================================================================
-- Texas Burger — Etapa 3c-2a: CAIXA (abrir/fechar), VENDA (iniciarVenda) e CANCELAR VENDA
-- Rodar DEPOIS da 3b e da 3c-1 (usa funções delas). Arquivo único. Pode rodar de novo (create or replace).
--
-- Fica para a 3c-2b: andamento do pedido (aceitar/preparo/pronto/entregar), suspender, receber pagamento,
-- entregadores e fechamento de entrega, editar venda, fechar conta da mesa.
-- Fica para a 3c-3: cupons, pedido pelo cardápio/QR, despesas, contingência.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. Ajustes de estrutura e de leitura
-- ---------------------------------------------------------------------
alter table vendas add column if not exists status_antes_suspensao text;   -- usado ao suspender/retomar (3c-2b) e ao cancelar

create or replace function _login_de(p_id uuid) returns text
language sql stable security definer set search_path = public as $$
  select login from usuarios where id = p_id
$$;
grant execute on function _login_de(uuid) to authenticated;

-- Vendas para o app: mesmas colunas e nomes de antes; dados sensíveis só para quem pode ver
-- (custo: Admin/Operador; telefone e endereço: não vão para a Cozinha). As linhas visíveis seguem as regras de acesso da tabela.
create or replace view v_vendas with (security_invoker = true) as
select v.id, v.numero_pedido as numero, v.data_hora, v.cliente_nome,
       case when auth_nivel() = 'Cozinha' then null else v.telefone_cliente end as cliente_telefone,
       v.forma_pagamento, v.valor_total,
       case when auth_nivel() in ('Admin','Operador') then v.custo_total else null end as custo_total,
       v.status, v.motivo_cancelamento, v.tipo as tipo_entrega, v.status_pedido,
       case when auth_nivel() = 'Cozinha' then null else v.endereco end as endereco,
       case when auth_nivel() = 'Cozinha' then null else v.complemento end as complemento,
       case when auth_nivel() = 'Cozinha' then null else v.referencia end as referencia,
       v.observacoes_entrega, v.pronta_em, v.concluida_em, v.status_pagamento, v.recebido_em,
       v.valor_original, v.valor_desconto, v.desconto_detalhe,
       _login_de(v.entregador_id) as entregador, v.saiu_em, v.origem, v.mesa_id, v.taxa_entrega,
       v.fechamento_entrega_id, _login_de(v.registrado_por) as registrado_por, v.inicio_preparo_em
from vendas v;

create or replace view v_itens_venda with (security_invoker = true) as
select i.id, i.venda_id, i.produto_id, i.combo_id, i.descricao, i.quantidade, i.valor_unitario,
       case when auth_nivel() in ('Admin','Operador') then i.custo_unitario else null end as custo_unitario,
       i.valor_total_item, i.adicionais_ids
from itens_venda i;

create or replace view v_fidelidade with (security_invoker = true) as
select c.nome, c.telefone, f.carimbos, f.premios_resgatados as premios, f.atualizada_em as atualizado,
       f.observacoes as observacao, f.cliente_id
from fidelidade f join clientes c on c.id = f.cliente_id;

-- Sessão de caixa aberta: todo usuário logado precisa saber se há caixa aberto (ex.: o garçom)
create or replace view v_sessao_aberta as
select s.id, s.abertura, s.fundo_caixa, _login_de(s.usuario_abertura) as usuario_abertura
from caixa_sessoes s
where s.status = 'Aberto' and auth_nivel() is not null;

grant select on v_vendas, v_itens_venda, v_fidelidade, v_sessao_aberta to authenticated;

-- Pagamentos: Admin/Operador e o Entregador (das próprias entregas), como no sistema antigo
drop policy if exists pagamentos_venda_ler on pagamentos_venda;
create policy pagamentos_venda_ler on pagamentos_venda for select to authenticated
  using (tem_nivel('Admin','Operador','Entregador') and exists (select 1 from vendas v where v.id = pagamentos_venda.venda_id));

-- ---------------------------------------------------------------------
-- 1. Auxiliares: consumo de estoque, baixa/estorno, cliente e fidelidade
-- ---------------------------------------------------------------------
-- quanto de cada ingrediente os itens consomem (produto, combo e adicionais)
create or replace function _consumo(p_itens jsonb) returns table (ingrediente_id uuid, qtd numeric)
language sql stable security definer set search_path = public as $$
  with it as (
    select _uuid(e->>'produtoId') as produto_id, _uuid(e->>'comboId') as combo_id,
           _num(e->>'quantidade') as q, e->'adicionaisIds' as ads
    from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) e
  ), consumo as (
    select pi.ingrediente_id, pi.quantidade_por_unidade * it.q as qtd
      from it join produto_ingredientes pi on pi.produto_id = it.produto_id
    union all
    select pi.ingrediente_id, pi.quantidade_por_unidade * ci.quantidade * it.q
      from it join combo_itens ci on ci.combo_id = it.combo_id
              join produto_ingredientes pi on pi.produto_id = ci.produto_id
    union all
    select a.ingrediente_id, coalesce(nullif(a.quantidade_descontar, 0), 1) * it.q
      from it
      cross join lateral jsonb_array_elements_text(case when jsonb_typeof(it.ads) = 'array' then it.ads else '[]'::jsonb end) x
      join adicionais a on a.id = _uuid(x)
      where a.ingrediente_id is not null
  )
  select c.ingrediente_id, sum(c.qtd) from consumo c where c.ingrediente_id is not null group by c.ingrediente_id having sum(c.qtd) <> 0
$$;

-- baixa (direção 1) ou estorno (direção -1) do estoque, com histórico; trava as linhas em ordem fixa
create or replace function _ajustar_estoque(p_itens jsonb, p_dir int, p_venda uuid) returns void
language plpgsql security definer set search_path = public as $$
declare r record; e estoque%rowtype; v_delta numeric; v_novo numeric;
        v_ref text := case when p_venda is not null then 'Venda #' || left(p_venda::text, 8) else case when p_dir > 0 then 'Venda' else 'Estorno de venda' end end;
begin
  for r in select * from _consumo(p_itens) order by ingrediente_id loop
    select * into e from estoque where id = r.ingrediente_id for update;
    if not found then continue; end if;
    v_delta := p_dir * r.qtd;
    v_novo := round(e.quantidade - v_delta, 3);
    update estoque set quantidade = v_novo where id = e.id;
    if p_dir > 0 and v_novo < 0 then perform _auditar('Estoque negativo', e.ingrediente || ': ' || v_novo || ' (' || v_ref || ')'); end if;
    if v_delta <> 0 then
      insert into movimentacoes_estoque (ingrediente_id, tipo, quantidade, qtd_antes, qtd_depois, motivo_referencia, usuario_id)
      values (e.id, (case when p_dir > 0 then 'Venda' else 'Saída' end)::tipo_mov_estoque, -v_delta, e.quantidade, v_novo, v_ref, auth.uid());
    end if;
  end loop;
end $$;

create or replace function _itens_da_venda(p_venda uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('produtoId', i.produto_id, 'comboId', i.combo_id, 'quantidade', i.quantidade,
                                               'adicionaisIds', to_jsonb(i.adicionais_ids))), '[]'::jsonb)
  from itens_venda i where i.venda_id = p_venda
$$;

-- acha o cliente pelo telefone (só dígitos) ou cria; devolve o id
create or replace function _upsert_cliente(p_tel text, p_nome text) returns uuid
language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_dig text := _so_digitos(p_tel);
begin
  if v_dig = '' then return null; end if;
  select id into v_id from clientes where _so_digitos(telefone) = v_dig limit 1;
  if found then
    if btrim(coalesce(p_nome, '')) <> '' then update clientes set nome = btrim(p_nome) where id = v_id and btrim(coalesce(nome, '')) = ''; end if;
    return v_id;
  end if;
  v_id := gen_random_uuid();
  insert into clientes (id, nome, telefone, primeiro_contato) values (v_id, btrim(coalesce(p_nome, '')), btrim(p_tel), now());
  return v_id;
end $$;

-- soma 1 marca no cartão de fidelidade (até 10)
create or replace function _carimbar_fidelidade(p_tel text, p_nome text) returns void
language plpgsql security definer set search_path = public as $$
declare v_cli uuid := _upsert_cliente(p_tel, p_nome); f fidelidade%rowtype;
begin
  if v_cli is null then return; end if;
  select * into f from fidelidade where cliente_id = v_cli for update;
  if found then
    if f.carimbos < 10 then
      update fidelidade set carimbos = f.carimbos + 1, atualizada_em = now() where cliente_id = v_cli;
      perform _auditar('Marca adicionada (fidelidade)', (f.carimbos + 1) || '/10', p_tel);
    end if;
  else
    insert into fidelidade (cliente_id, carimbos, atualizada_em) values (v_cli, 1, now());
    perform _auditar('Cliente novo no fidelidade', coalesce(p_nome, ''), p_tel);
  end if;
end $$;

create or replace function _dinheiro(v numeric) returns text language sql immutable as $$
  select to_char(coalesce(v, 0), 'FM999999990.00')
$$;

-- ---------------------------------------------------------------------
-- 2. Abrir caixa
-- ---------------------------------------------------------------------
create or replace function api_abrir_caixa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_fundo numeric := round(_num(p->>'fundoCaixa'), 2);
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if v_fundo < 0 then return _falha('O fundo de caixa não pode ser negativo.'); end if;
  if exists (select 1 from caixa_sessoes where status = 'Aberto') then return _falha('Já existe um caixa aberto. Feche-o antes de abrir outro.'); end if;
  begin
    insert into caixa_sessoes (fundo_caixa, usuario_abertura, status) values (v_fundo, auth.uid(), 'Aberto');
  exception when unique_violation then
    return _falha('Já existe um caixa aberto. Feche-o antes de abrir outro.');
  end;
  perform _auditar('Caixa aberto', 'Fundo de caixa: R$ ' || _dinheiro(v_fundo));
  return jsonb_build_object('ok', true, 'message', 'Caixa aberto.');
end $$;

-- ---------------------------------------------------------------------
-- 3. Fechar caixa (pede a senha de quem está fechando; trava se houver pendências)
-- ---------------------------------------------------------------------
create or replace function _lista_curta(p_itens text[]) returns text
language sql immutable as $$
  select array_to_string(p_itens[1:6], ', ') || case when coalesce(array_length(p_itens, 1), 0) > 6 then ' e mais ' || (array_length(p_itens, 1) - 6) else '' end
$$;

create or replace function api_fechar_caixa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  s caixa_sessoes%rowtype; v_login text; v_chave text; v_seg int; v_contado numeric; v_fim timestamptz := now();
  v_mesas text[]; v_pend text[]; v_nrec text[]; v_msgs text[] := '{}';
  v_total numeric; v_pendente numeric; v_qv int; v_desp numeric; v_qd int; v_sang numeric; v_qs int;
  v_forma jsonb; v_dinheiro numeric; v_saldo numeric; v_dif numeric; v_nomes_dinheiro text[];
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  select login into v_login from usuarios where id = auth.uid();
  v_chave := 'falhas_senha_propria_' || lower(coalesce(v_login, ''));
  if _excedeu(v_chave, 5) then
    select greatest(1, extract(epoch from (bloqueado_ate - now()))::int) into v_seg from tentativas where chave = v_chave;
    return jsonb_build_object('ok', false, 'bloqueioSegundos', v_seg, 'message', 'Muitas tentativas erradas. Aguarde ' || ceil(v_seg / 60.0)::int || ' min e tente de novo.');
  end if;
  if coalesce(p->>'senhaConfirmacao', '') = '' or not _senha_confere(auth.uid(), p->>'senhaConfirmacao') then
    perform _registrar_falha(v_chave);
    return _falha('Senha incorreta. O caixa não foi fechado.');
  end if;
  perform _limpar_falhas(v_chave);
  if nullif(btrim(coalesce(p->>'valorContado', '')), '') is null or _num(p->>'valorContado', -1) < 0 then
    return _falha('Informe quanto dinheiro há na gaveta (pode ser zero).');
  end if;
  v_contado := round(_num(p->>'valorContado'), 2);
  select * into s from caixa_sessoes where id = _uuid(p->>'id') for update;
  if not found then return _falha('Sessão de caixa não encontrada.'); end if;
  if s.status = 'Fechado' then return _falha('Este caixa já foi fechado.'); end if;

  -- trava: mesas abertas, pedidos pendentes ou não recebidos
  select coalesce(array_agg('Mesa ' || numero order by numero), '{}') into v_mesas from mesas where status in ('Ocupada','Aguardando fechamento');
  select coalesce(array_agg('#' || numero_pedido || case when btrim(coalesce(cliente_nome, '')) <> '' then ' ' || split_part(btrim(cliente_nome), ' ', 1) else '' end || ' (' || status_pedido || ')' order by numero_pedido), '{}')
    into v_pend from vendas where status = 'Confirmada' and status_pedido is not null and status_pedido not in ('Entregue','Retirada','Servida');
  select coalesce(array_agg('#' || numero_pedido || case when btrim(coalesce(cliente_nome, '')) <> '' then ' ' || split_part(btrim(cliente_nome), ' ', 1) else '' end order by numero_pedido), '{}')
    into v_nrec from vendas where status = 'Confirmada' and status_pagamento = 'A Receber';
  if coalesce(array_length(v_mesas, 1), 0) + coalesce(array_length(v_pend, 1), 0) + coalesce(array_length(v_nrec, 1), 0) > 0 then
    if array_length(v_mesas, 1) > 0 then v_msgs := v_msgs || ('Mesas abertas: ' || _lista_curta(v_mesas)); end if;
    if array_length(v_pend, 1) > 0 then v_msgs := v_msgs || ('Pedidos pendentes: ' || _lista_curta(v_pend)); end if;
    if array_length(v_nrec, 1) > 0 then v_msgs := v_msgs || ('Pedidos não recebidos: ' || _lista_curta(v_nrec)); end if;
    return jsonb_build_object('ok', false, 'pendencias', true, 'mesas', to_jsonb(v_mesas), 'pedidos', to_jsonb(v_pend), 'naoRecebidos', to_jsonb(v_nrec),
      'message', 'O caixa não pode ser fechado enquanto houver pendências. ' || array_to_string(v_msgs, ' | ') || '. Resolva (finalize, receba ou cancele) e tente de novo.');
  end if;

  select coalesce(sum(valor_total), 0), coalesce(sum(valor_total) filter (where status_pagamento = 'A Receber'), 0), count(*)
    into v_total, v_pendente, v_qv from vendas where status = 'Confirmada' and data_hora >= s.abertura and data_hora <= v_fim;
  select coalesce(sum(valor), 0), count(*) into v_desp, v_qd from despesas
    where status = 'Paga' and saiu_do_caixa and data_hora >= s.abertura and data_hora <= v_fim;
  select coalesce(sum(valor), 0), count(*) into v_sang, v_qs from sangrias where data_hora >= s.abertura and data_hora <= v_fim;
  -- o dinheiro conta na sessão em que ENTROU (data do recebimento), não em que o pedido foi criado
  select coalesce(jsonb_object_agg(forma, tot), '{}'::jsonb) into v_forma from (
    select pv.forma_pagamento as forma, sum(pv.valor) as tot
    from pagamentos_venda pv join vendas v on v.id = pv.venda_id
    where v.status = 'Confirmada' and v.status_pagamento <> 'A Receber'
      and coalesce(v.recebido_em, v.data_hora) >= s.abertura and coalesce(v.recebido_em, v.data_hora) <= v_fim
    group by pv.forma_pagamento) t;
  select coalesce(array_agg(nome), '{}') into v_nomes_dinheiro from formas_pagamento where permite_troco;
  if coalesce(array_length(v_nomes_dinheiro, 1), 0) = 0 then v_nomes_dinheiro := array['Dinheiro']; end if;
  select coalesce(sum((value)::numeric), 0) into v_dinheiro from jsonb_each_text(v_forma) where key = any(v_nomes_dinheiro);
  v_saldo := s.fundo_caixa + v_dinheiro - v_desp - v_sang;
  v_dif := round(v_contado - v_saldo, 2);

  update caixa_sessoes set fechamento = v_fim, total_vendas = v_total, total_despesas = v_desp, saldo_final = v_saldo, status = 'Fechado',
         usuario_fechamento = auth.uid(), valor_contado = v_contado, diferenca = v_dif where id = s.id;
  perform _auditar('Caixa fechado', 'Esperado: R$ ' || _dinheiro(v_saldo) || ' | Contado: R$ ' || _dinheiro(v_contado) || ' | Diferença: R$ ' || _dinheiro(v_dif));
  if abs(v_dif) >= 0.01 then
    perform _auditar('Diferença de caixa', case when v_dif > 0 then 'SOBRA' else 'FALTA' end || ' de R$ ' || _dinheiro(abs(v_dif)) || ' no fechamento');
  end if;

  return jsonb_build_object('ok', true, 'entregasAuto', jsonb_build_object('feitos', '[]'::jsonb),
    'relatorio', jsonb_build_object(
      'abertura', to_char(s.abertura at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
      'fechamento', to_char(v_fim at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
      'fundoCaixa', s.fundo_caixa, 'totalVendas', v_total, 'totalVendasDinheiro', v_dinheiro, 'porForma', v_forma,
      'totalPendente', v_pendente, 'totalDespesas', v_desp, 'totalSangrias', v_sang, 'saldoFinal', v_saldo,
      'valorContado', v_contado, 'diferenca', v_dif, 'quantidadeVendas', v_qv, 'quantidadeDespesas', v_qd, 'quantidadeSangrias', v_qs,
      'reconciliadasNaSessao', jsonb_build_object('quantidade', 0, 'valor', 0), 'pendentesContingencia', 0));
end $$;

-- ---------------------------------------------------------------------
-- 4. Iniciar venda (balcão, mesa, entrega/retirada por telefone)
-- ---------------------------------------------------------------------
create or replace function api_iniciar_venda(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_nivel nivel_acesso := auth_nivel(); v_eu uuid := auth.uid(); v_login text;
  v_itens jsonb := p->'itens'; v_pags jsonb := p->'pagamentos'; v_tipo_in text := p->>'tipoEntrega';
  v_mesa_id uuid := _uuid(p->>'mesaId'); v_mesa mesas%rowtype; v_mesa_status text; v_mesa_garcom uuid;
  v_origem text := coalesce(nullif(p->>'origem', ''), 'Balcão'); v_status_pag text := p->>'statusPagamento';
  v_nome text := btrim(coalesce(p->>'clienteNome', '')); v_tel text := btrim(coalesce(p->>'clienteTelefone', ''));
  v_de jsonb := case when jsonb_typeof(p->'dadosEntrega') = 'object' then p->'dadosEntrega' else '{}'::jsonb end;
  v_desc jsonb := case when jsonb_typeof(p->'desconto') = 'object' then p->'desconto' else null end;
  v_req text := nullif(left(coalesce(p->>'requisicaoId', ''), 80), ''); v_ja uuid;
  it record; pg record; v_exige boolean; v_qtd numeric; v_v numeric; v_c numeric; v_nome_item text; v_extra numeric; v_n_ad int; v_n_ok int;
  v_orig numeric := 0; v_custo numeric := 0; v_total_item numeric; v_desc_val numeric := 0; v_desc_det text := ''; v_sol numeric; v_aut text;
  v_tipo venda_tipo; v_taxa numeric := 0; v_total numeric; v_soma numeric := 0; v_erro text; v_venda uuid := gen_random_uuid();
  v_pad numeric; v_t numeric; v_forma_row formas_pagamento%rowtype; v_resumo text; v_origem_final origem_venda; v_status_pedido_ini status_pedido;
  v_status_pag_final status_pagamento; v_numero int; v_msg_extra text := ''; v_caixa uuid; v_bloqueia boolean; r record;
begin
  if v_nivel is null or v_nivel not in ('Admin','Operador','Garçom') then return _negado(); end if;
  if jsonb_typeof(v_itens) <> 'array' or jsonb_array_length(v_itens) = 0 then return _falha('Adicione ao menos um item à venda.'); end if;
  if jsonb_typeof(v_pags) <> 'array' or jsonb_array_length(v_pags) = 0 then return _falha('Informe ao menos uma forma de pagamento.'); end if;
  if v_tipo_in = 'Mesa' and v_mesa_id is null then return _falha('Informe a mesa.'); end if;
  if v_origem like 'Contingência%' then return _falha('Vendas da contingência ainda não foram migradas (etapa 3c-3).'); end if;
  if coalesce(p->'promocaoValidada'->>'ok', '') = 'true' then return _falha('Cupons ainda não foram migrados para o novo servidor (etapa 3c-3). Faça a venda sem cupom por enquanto.'); end if;
  select login into v_login from usuarios where id = v_eu;
  select id into v_caixa from caixa_sessoes where status = 'Aberto' limit 1;

  -- garçom: só mesa/entrega/retirada, sem desconto, sem receber pagamento; vale no servidor, não só na tela
  if v_nivel = 'Garçom' then
    if v_tipo_in not in ('Mesa','Entrega','Retirada') then return _falha('O garçom só lança pedidos de mesa, entrega ou retirada.'); end if;
    if v_caixa is null then return _falha('O caixa está fechado — peça ao caixa para abrir.'); end if;
    if v_tipo_in <> 'Mesa' and v_tel = '' then return _falha('Informe o cliente (nome e telefone) para pedidos por telefone.'); end if;
    if v_tipo_in = 'Mesa' then
      select * into v_mesa from mesas where id = v_mesa_id for update;
      if not found then return _falha('Mesa não encontrada.'); end if;
      if v_mesa.status not in ('Livre','Ocupada') then return _falha('A mesa ' || v_mesa.numero || ' está "' || v_mesa.status || '" — não aceita novos itens.'); end if;
      if v_mesa.status = 'Ocupada' and v_mesa.garcom_responsavel_id is not null and v_mesa.garcom_responsavel_id <> v_eu then
        return _falha('Esta mesa está sob responsabilidade de outro garçom.');
      end if;
    end if;
    v_origem := 'Garçom'; v_desc := null; v_status_pag := 'A Receber';
    if v_tipo_in = 'Mesa' then
      v_pags := jsonb_build_array(jsonb_build_object('forma', 'A Receber (Mesa)', 'valor', _num(v_pags->0->>'valor')));
    else
      v_pags := jsonb_build_array(jsonb_build_object('forma', btrim(coalesce(v_pags->0->>'forma', '')), 'valor', _num(v_pags->0->>'valor')));
    end if;
  elsif v_tipo_in = 'Mesa' then
    select * into v_mesa from mesas where id = v_mesa_id for update;
    if not found then return _falha('Mesa não encontrada.'); end if;
  end if;

  if v_tipo_in = 'Mesa' then v_mesa_status := v_mesa.status::text; v_mesa_garcom := v_mesa.garcom_responsavel_id; end if;

  -- idempotência: a mesma requisição (duplo toque, nova tentativa) nunca gera duas vendas
  if v_req is not null then
    perform pg_advisory_xact_lock(hashtext('venda:' || v_req));
    select id into v_ja from vendas where requisicao_id = v_req;
    if found then return jsonb_build_object('ok', true, 'duplicado', true, 'id', v_ja, 'message', 'Venda já registrada — requisição repetida ignorada.'); end if;
  end if;

  -- itens: quantidade, preço, custo e (para quem não é Admin) preço conferido com o cadastro
  v_exige := not (v_nivel = 'Admin' and v_origem <> 'Cardápio');
  for it in select value as e from jsonb_array_elements(v_itens) loop
    v_nome_item := coalesce(nullif(it.e->>'descricao', ''), 'item');
    v_qtd := _num(it.e->>'quantidade'); v_v := _num(it.e->>'valorUnitario', -1); v_c := _num(it.e->>'custoUnitario');
    if not (v_qtd > 0) or v_qtd > 200 or v_qtd <> floor(v_qtd) then return _falha('Quantidade inválida em "' || v_nome_item || '".'); end if;
    if v_v < 0 then return _falha('Preço inválido em "' || v_nome_item || '".'); end if;
    if v_c < 0 then return _falha('Custo inválido em "' || v_nome_item || '".'); end if;
    if v_exige then
      if (_uuid(it.e->>'produtoId') is null and _uuid(it.e->>'comboId') is null) or (_uuid(it.e->>'produtoId') is not null and _uuid(it.e->>'comboId') is not null) then
        return _falha('"' || v_nome_item || '" não é um item cadastrado de forma válida.');
      end if;
      select count(*), coalesce(sum(a.preco) filter (where a.ativo), 0), count(*) filter (where a.ativo)
        into v_n_ad, v_extra, v_n_ok
        from jsonb_array_elements_text(case when jsonb_typeof(it.e->'adicionaisIds') = 'array' then it.e->'adicionaisIds' else '[]'::jsonb end) x
        left join adicionais a on a.id = _uuid(x);
      if v_n_ad <> v_n_ok then return _falha('O adicional selecionado para "' || v_nome_item || '" não está disponível.'); end if;
      if _uuid(it.e->>'produtoId') is not null then
        if not exists (select 1 from produto_precos pp where pp.produto_id = _uuid(it.e->>'produtoId') and abs(pp.preco + v_extra - v_v) <= 0.011) then
          perform _auditar('Preço divergente bloqueado', v_nome_item || ' enviado a R$ ' || _dinheiro(v_v));
          return _falha('O preço de "' || v_nome_item || '" não confere com o cadastro.');
        end if;
      else
        if not exists (select 1 from combo_precos cp where cp.combo_id = _uuid(it.e->>'comboId') and abs(cp.preco + v_extra - v_v) <= 0.011) then
          perform _auditar('Preço divergente bloqueado', v_nome_item || ' enviado a R$ ' || _dinheiro(v_v));
          return _falha('O preço de "' || v_nome_item || '" não confere com o cadastro.');
        end if;
      end if;
    end if;
    v_total_item := round(v_qtd * v_v, 2);
    v_orig := v_orig + v_total_item; v_custo := v_custo + v_qtd * v_c;
  end loop;
  v_orig := round(v_orig, 2); v_custo := round(v_custo, 2);

  -- estoque (só se a regra "bloquear venda sem estoque" estiver ligada)
  select coalesce((select (valor #>> '{}') = 'true' from sistema where chave = 'BLOQUEAR_ESTOQUE_NEGATIVO'), false) into v_bloqueia;
  if v_bloqueia then
    for r in select c.ingrediente_id, c.qtd, e.ingrediente, e.quantidade from _consumo(v_itens) c join estoque e on e.id = c.ingrediente_id loop
      if r.quantidade + 0.000000001 < r.qtd then
        if v_origem = 'Cardápio' then return _falha('Um dos itens do pedido acabou. Escolha outro item ou fale com o restaurante.'); end if;
        return _falha('Estoque insuficiente de "' || r.ingrediente || '" (tem ' || r.quantidade || ', a venda precisa de ' || round(r.qtd, 3) || ').');
      end if;
    end loop;
  end if;

  -- desconto manual (precisa da senha de Admin quando quem lança não é Admin)
  if v_desc is not null and v_desc->>'valor' is not null then
    v_sol := _num(v_desc->>'valor', -1);
    if v_sol <= 0 then return _falha('Valor de desconto inválido.'); end if;
    v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
    if v_aut is null then return _falha('Senha de administrador incorreta — desconto não aplicado.'); end if;
    if v_desc->>'tipo' = 'percentual' then
      if v_sol > 100 then return _falha('O desconto percentual não pode ser maior que 100%.'); end if;
      v_desc_val := round(v_orig * (v_sol / 100), 2);
      v_desc_det := v_sol || '% (R$ ' || _dinheiro(v_desc_val) || ')';
    elsif coalesce(v_desc->>'tipo', 'fixo') = 'fixo' then
      if v_sol > v_orig then return _falha('O desconto fixo não pode ser maior que o valor da venda.'); end if;
      v_desc_val := round(v_sol, 2);
      v_desc_det := 'R$ ' || _dinheiro(v_desc_val) || ' fixo';
    else
      return _falha('Tipo de desconto inválido.');
    end if;
    if v_desc_val <= 0 or v_desc_val >= v_orig then return _falha('O desconto não pode deixar a venda com valor zero ou negativo.'); end if;
  end if;

  -- tipo, taxa de entrega e total
  v_tipo := case v_tipo_in when 'Entrega' then 'Entrega' when 'Mesa' then 'Mesa' else 'Retirada' end::venda_tipo;
  if v_tipo = 'Entrega' and coalesce(v_de->>'freteGratis', '') <> 'true' then
    select coalesce(_num(valor #>> '{}'), 0) into v_pad from sistema where chave = 'TaxaEntregaPadrao';
    v_taxa := coalesce(v_pad, 0);
    if v_nivel in ('Admin','Operador') and nullif(btrim(coalesce(v_de->>'taxa', '')), '') is not null then
      v_t := _num(v_de->>'taxa', -1);
      if v_t >= 0 and v_t <= 500 then v_taxa := round(v_t, 2); end if;
    end if;
  end if;
  v_total := round(v_orig - v_desc_val + v_taxa, 2);
  if v_total < 0.01 then return _falha('O total da venda precisa ser maior que zero.'); end if;
  if v_nivel = 'Garçom' and v_tipo_in <> 'Mesa' then
    v_pags := jsonb_build_array(jsonb_build_object('forma', v_pags->0->>'forma', 'valor', v_total));
  end if;

  -- pagamentos
  if exists (select 1 from jsonb_array_elements(v_pags) e where e->>'forma' = 'A Receber (Mesa)') then
    if jsonb_array_length(v_pags) <> 1 then return _falha('Forma de pagamento inválida para esta operação.'); end if;
    v_status_pag := 'A Receber';
  end if;
  for pg in select value as e from jsonb_array_elements(v_pags) loop
    if btrim(coalesce(pg.e->>'forma', '')) = '' then return _falha('Forma de pagamento não informada.'); end if;
    if not (_num(pg.e->>'valor', 0) > 0) then return _falha('Cada pagamento deve ter um valor maior que zero.'); end if;
    if btrim(pg.e->>'forma') = 'A Receber (Mesa)' then
      if v_nivel not in ('Admin','Operador','Garçom') or v_tipo_in <> 'Mesa' then return _falha('Forma de pagamento inválida para esta operação.'); end if;
      continue;
    end if;
    select * into v_forma_row from formas_pagamento where lower(nome) = lower(btrim(pg.e->>'forma')) limit 1;
    if not found then return _falha('Forma de pagamento não cadastrada: ' || btrim(pg.e->>'forma')); end if;
    if not v_forma_row.ativa then return _falha('A forma de pagamento está inativa: ' || btrim(pg.e->>'forma')); end if;
  end loop;
  select round(coalesce(sum(_num(e->>'valor')), 0), 2) into v_soma from jsonb_array_elements(v_pags) e;
  if abs(v_soma - v_total) > 0.02 then
    return _falha('A soma dos pagamentos (R$ ' || _dinheiro(v_soma) || ') não bate com o total da venda (R$ ' || _dinheiro(v_total) || ').');
  end if;

  -- grava tudo
  v_status_pag_final := case when v_status_pag = 'A Receber' then 'A Receber' else 'Pago' end::status_pagamento;
  v_origem_final := (case when v_origem in ('Cardápio','Garçom') then v_origem else 'Balcão' end)::origem_venda;
  v_status_pedido_ini := (case when v_origem_final = 'Cardápio' then 'Recebido' else 'Em preparo' end)::status_pedido;
  select string_agg(btrim(e->>'forma'), ' + ') into v_resumo from jsonb_array_elements(v_pags) e;

  insert into vendas (id, cliente_nome, telefone_cliente, forma_pagamento, valor_total, custo_total, status, tipo, status_pedido,
                      endereco, complemento, referencia, observacoes_entrega, status_pagamento, recebido_em, valor_original, valor_desconto,
                      desconto_detalhe, origem, mesa_id, taxa_entrega, registrado_por, caixa_id, requisicao_id)
  values (v_venda, v_nome, v_tel, v_resumo, v_total, v_custo, 'Confirmada', v_tipo, v_status_pedido_ini,
          case when v_tipo = 'Entrega' then coalesce(v_de->>'endereco', '') else '' end,
          case when v_tipo = 'Entrega' then coalesce(v_de->>'complemento', '') else '' end,
          case when v_tipo = 'Entrega' then coalesce(v_de->>'referencia', '') else '' end,
          coalesce(v_de->>'observacoes', ''), v_status_pag_final, case when v_status_pag_final = 'Pago' then now() else null end,
          v_orig, v_desc_val, v_desc_det, v_origem_final, case when v_tipo = 'Mesa' then v_mesa_id else null end, v_taxa, v_eu, v_caixa, v_req)
  returning numero_pedido into v_numero;

  insert into itens_venda (venda_id, produto_id, combo_id, descricao, quantidade, valor_unitario, custo_unitario, valor_total_item, adicionais_ids)
  select v_venda, _uuid(e->>'produtoId'), _uuid(e->>'comboId'), e->>'descricao', _num(e->>'quantidade', 1)::int,
         _num(e->>'valorUnitario'), _num(e->>'custoUnitario'), round(_num(e->>'quantidade', 1) * _num(e->>'valorUnitario'), 2),
         coalesce((select array_agg(_uuid(x)) filter (where _uuid(x) is not null)
                   from jsonb_array_elements_text(case when jsonb_typeof(e->'adicionaisIds') = 'array' then e->'adicionaisIds' else '[]'::jsonb end) x), '{}')
  from jsonb_array_elements(v_itens) e;

  insert into pagamentos_venda (venda_id, forma_pagamento, valor, taxa_aplicada)
  select v_venda, btrim(e->>'forma'), _num(e->>'valor'),
         coalesce((select round(_num(e->>'valor') * f.taxa_percentual / 100 + f.taxa_fixa, 2) from formas_pagamento f where f.nome = btrim(e->>'forma')), 0)
  from jsonb_array_elements(v_pags) e;

  if v_tipo = 'Mesa' and v_mesa_status = 'Livre' then
    update mesas set status = 'Ocupada', garcom_responsavel_id = case when v_nivel = 'Garçom' then v_eu else garcom_responsavel_id end where id = v_mesa_id;
  elsif v_tipo = 'Mesa' and v_nivel = 'Garçom' and v_mesa_garcom is null then
    update mesas set garcom_responsavel_id = v_eu where id = v_mesa_id;
  end if;

  perform _ajustar_estoque(v_itens, 1, v_venda);

  if v_desc_val > 0 then
    perform _auditar('Desconto aplicado na venda', 'Autorizado por ' || coalesce(nullif(current_setting('app.autorizador', true), ''), v_login) || ' | Valor original: R$ ' || _dinheiro(v_orig)
      || ' → Desconto: ' || v_desc_det || ' → Valor final: R$ ' || _dinheiro(v_total), v_tel);
  end if;
  if v_tel <> '' then
    perform _upsert_cliente(v_tel, v_nome);
    if v_origem_final = 'Balcão' and v_status_pag_final = 'Pago' then
      perform _carimbar_fidelidade(v_tel, v_nome);
      v_msg_extra := ' Marca de fidelidade adicionada para ' || v_nome || '.';
    end if;
  end if;
  perform _auditar('Venda registrada', 'Total R$ ' || _dinheiro(v_total) || ' via ' || v_resumo || ' (' || v_tipo || ', ' || v_status_pag_final || ')', v_tel);

  return jsonb_build_object('ok', true, 'message', 'Venda registrada: R$ ' || _dinheiro(v_total) || '.' || v_msg_extra,
                            'id', v_venda, 'numero', v_numero, 'valorTotal', v_total);
end $$;

-- ---------------------------------------------------------------------
-- 5. Cancelar venda (senha de Admin; devolve estoque conforme o andamento do pedido)
-- ---------------------------------------------------------------------
create or replace function api_cancelar_venda(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v vendas%rowtype; v_aut text; v_motivo text := btrim(coalesce(p->>'motivo', '')); v_st text; v_pronta boolean; v_login text;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo do cancelamento.'); end if;
  select * into v from vendas where id = _uuid(p->>'id') for update;
  if not found then return _falha('Venda não encontrada.'); end if;
  if v.status = 'Cancelada' then return _falha('Esta venda já está cancelada.'); end if;
  if v.fechamento_entrega_id is not null then return _falha('Esta entrega já está em um fechamento — não pode ser cancelada. Faça o ajuste pelo Financeiro.'); end if;
  v_st := v.status_pedido::text;
  if v_st = 'Suspenso' then v_st := coalesce(nullif(v.status_antes_suspensao, ''), 'Em preparo'); end if;
  v_pronta := v_st is not null and v_st <> '' and v_st not in ('Em preparo', 'Recebido');
  update vendas set status = 'Cancelada', motivo_cancelamento = v_motivo where id = v.id;
  -- antes de "Pronta" o estoque sempre volta; depois, só se a mercadoria não foi perdida
  if not v_pronta or coalesce(p->>'mercadoriaPerdida', '') = 'false' then
    perform _ajustar_estoque(_itens_da_venda(v.id), -1, v.id);
  end if;
  select login into v_login from usuarios where id = auth.uid();
  perform _auditar('Venda cancelada', 'Autorizado por ' || coalesce(nullif(current_setting('app.autorizador', true), ''), v_login) || ' | R$ ' || _dinheiro(v.valor_total) || ' | ' || v_motivo
    || case when v.status_pagamento = 'Pago' then ' | ESTORNO ao cliente pendente (venda estava paga)' else '' end
    || case when v_pronta then case when coalesce(p->>'mercadoriaPerdida', '') = 'false' then ' — mercadoria devolvida ao estoque' else ' — mercadoria perdida' end else '' end, v.telefone_cliente);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 6. Quem pode chamar (mesma regra das etapas anteriores)
-- ---------------------------------------------------------------------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as assinatura, p.proname from pg_proc p
           join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'api\_%' or p.proname like '\_%' or p.proname = 'auth_nivel') loop
    execute format('revoke all on function %s from public, anon', f.assinatura);
    if f.proname like 'api\_%' or f.proname = 'auth_nivel' then execute format('grant execute on function %s to authenticated', f.assinatura); end if;
  end loop;
end $$;
grant execute on function _num(text, numeric), _uuid(text), _so_digitos(text), _login_de(uuid) to authenticated;

-- FIM DO ARQUIVO


-- >>>>>>>>>> 01_andamento_pedidos.sql <<<<<<<<<<
-- Texas Burger — Etapa 3c-2b (parte 1): andamento dos pedidos (v-etapa-03c2b1)
-- Precisa do 01_caixa_vendas.sql já rodado. Pode rodar de novo sem problema.
begin;

create or replace function _pedido_trava(p jsonb, out v vendas, out erro jsonb) language plpgsql security definer set search_path = public as $$
begin
  select * into v from vendas where id = _uuid(p->>'vendaId') for update;
  if not found then erro := _falha('Pedido não encontrado.');
  elsif v.status <> 'Confirmada' then erro := _falha('Este pedido foi cancelado.');
  elsif v.fechamento_entrega_id is not null then erro := _falha('Esta entrega já está em um fechamento — não pode mais ser alterada.');
  end if;
end $$;

create or replace function _conflito(p_msg text) returns jsonb language sql immutable as $$
  select jsonb_build_object('ok', false, 'conflito', true, 'message', p_msg) $$;

-- aceitar (Recebido -> Em preparo)
create or replace function api_aceitar_pedido(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t record; v vendas;
begin
  if not tem_nivel('Admin','Operador','Cozinha') then return _negado(); end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  if v.status_pedido::text <> 'Recebido' then return _conflito('Esse pedido não está mais aguardando aceite.'); end if;
  update vendas set status_pedido = 'Em preparo' where id = v.id;
  perform _auditar('Pedido aceito', '#' || v.numero_pedido, v.telefone_cliente);
  return jsonb_build_object('ok', true);
end $$;

-- iniciar preparo (aceita se ainda Recebido e marca o início)
create or replace function api_iniciar_preparo_pedido(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t record; v vendas;
begin
  if not tem_nivel('Admin','Operador','Cozinha') then return _negado(); end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  if v.status_pedido::text not in ('Recebido','Em preparo') then return _conflito('Este pedido já está "' || coalesce(v.status_pedido::text,'') || '". A tela foi atualizada.'); end if;
  if v.status_pedido::text = 'Recebido' then perform _auditar('Pedido aceito', '#' || v.numero_pedido || ' — aceito pela cozinha', v.telefone_cliente); end if;
  update vendas set status_pedido = 'Em preparo', inicio_preparo_em = coalesce(inicio_preparo_em, now()) where id = v.id;
  perform _auditar('Preparo iniciado', '#' || v.numero_pedido);
  return jsonb_build_object('ok', true);
end $$;

-- avançar status (mesmas transições e travas por perfil da planilha)
create or replace function api_avancar_status_pedido(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t record; v vendas; novo text := p->>'novoStatus'; atual text; eu uuid := auth.uid(); lg text; nv text;
begin
  if not tem_nivel('Admin','Operador','Cozinha','Garçom','Entregador') then return _negado(); end if;
  if novo not in ('Em preparo','Pronta','Saiu para entrega','Entregue','Retirada','Servida') then return _falha('Status inválido.'); end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  v := t.v; atual := coalesce(v.status_pedido::text, ''); lg := _login_de(eu);
  select nivel::text into nv from usuarios where id = eu;
  if nullif(p->>'statusEsperado','') is not null and p->>'statusEsperado' <> atual then
    return _conflito('Este pedido já foi atualizado por outra pessoa (agora está "' || atual || '"). A tela foi atualizada.'); end if;
  if atual = 'Suspenso' then return _falha('Este pedido está suspenso — retome antes de avançar.'); end if;
  if v.tipo = 'Retirada' and novo in ('Saiu para entrega','Entregue','Servida') then return _falha('Pedido de retirada não tem esse status.'); end if;
  if v.tipo = 'Entrega' and novo in ('Retirada','Servida') then return _falha('Pedido de entrega não tem esse status.'); end if;
  if v.tipo = 'Mesa' and novo in ('Saiu para entrega','Entregue','Retirada') then return _falha('Pedido de mesa não tem esse status — use "Servida".'); end if;
  if not ((novo='Em preparo' and atual='Recebido') or (novo='Pronta' and atual='Em preparo') or (novo='Saiu para entrega' and atual='Pronta')
       or (novo='Entregue' and atual='Saiu para entrega') or (novo in ('Retirada','Servida') and atual='Pronta')) then
    if novo = 'Pronta' and atual = 'Recebido' then return _falha('Aceite o pedido e inicie o preparo antes de marcá-lo como pronto.'); end if;
    return _falha('Transição inválida: o pedido está "' || atual || '" e não pode avançar diretamente para "' || novo || '".'); end if;
  if nv = 'Cozinha' and novo not in ('Em preparo','Pronta') then return _falha('A cozinha só pode marcar "Em preparo" e "Pronta".'); end if;
  if nv = 'Garçom' then
    if not (v.registrado_por = eu or exists (select 1 from mesas m where m.id = v.mesa_id and lower(m.garcom_responsavel::text) = lower(lg))) then return _falha('Este pedido não está no seu escopo operacional.'); end if;
    if novo <> 'Servida' then return _falha('O garçom apenas pode marcar como "Servida" um pedido de sua mesa.'); end if;
  end if;
  if nv = 'Entregador' then
    if v.tipo <> 'Entrega' or v.entregador_id is distinct from eu then return _falha('Esta entrega não está atribuída a você.'); end if;
    if novo not in ('Saiu para entrega','Entregue') then return _falha('O entregador só pode marcar "Saiu para entrega" e "Entregue".'); end if;
  end if;
  if novo = 'Saiu para entrega' and v.entregador_id is null then return _falha('Atribua um entregador antes de o pedido sair para entrega.'); end if;
  update vendas set status_pedido = novo::status_pedido,
    pronta_em = case when novo = 'Pronta' then now() else pronta_em end,
    saiu_em = case when novo = 'Saiu para entrega' then now() else saiu_em end,
    concluida_em = case when novo in ('Entregue','Retirada','Servida') then now() else concluida_em end
  where id = v.id;
  perform _auditar('Status do pedido atualizado', '#' || v.numero_pedido || ' → ' || novo);
  return jsonb_build_object('ok', true);
end $$;

-- suspender / retomar
create or replace function api_suspender_pedido(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t record; v vendas; m text := left(btrim(coalesce(p->>'motivo','')), 200);
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if m = '' then return _falha('Informe o motivo da suspensão.'); end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  if v.status_pedido::text not in ('Recebido','Em preparo','Pronta') then
    return _conflito('Só dá para suspender pedido em "Recebido", "Em preparo" ou "Pronta" (agora está "' || coalesce(v.status_pedido::text,'') || '").'); end if;
  update vendas set status_antes_suspensao = status_pedido::text, status_pedido = 'Suspenso' where id = v.id;
  perform _auditar('Pedido suspenso', '#' || v.numero_pedido || ' | de "' || v.status_pedido::text || '" | ' || m, v.telefone_cliente);
  return jsonb_build_object('ok', true);
end $$;

create or replace function api_retomar_pedido(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t record; v vendas; antes text;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  if v.status_pedido::text <> 'Suspenso' then return _conflito('Este pedido não está suspenso.'); end if;
  antes := coalesce(nullif(v.status_antes_suspensao,''), 'Em preparo');
  update vendas set status_pedido = (case when antes in ('Recebido','Pronta') then antes else 'Em preparo' end)::status_pedido, status_antes_suspensao = null where id = v.id;
  perform _auditar('Pedido retomado', '#' || v.numero_pedido || ' → ' || antes, v.telefone_cliente);
  return jsonb_build_object('ok', true);
end $$;

-- rejeitar = cancelar (senha de Admin; a mercadoria volta ao estoque)
create or replace function api_rejeitar_pedido(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  return api_cancelar_venda(jsonb_build_object('id', p->>'vendaId', 'motivo', coalesce(nullif(btrim(p->>'motivo'),''), 'Pedido rejeitado'),
    'senhaAdminConfirmacao', p->>'senhaAdminConfirmacao', 'mercadoriaPerdida', 'false'));
end $$;

-- atribuir entregador (login vazio = remover)
create or replace function api_atribuir_entregador(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t record; v vendas; u usuarios; lg text := btrim(coalesce(p->>'entregador','')); ant text;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if lg <> '' then
    select * into u from usuarios where lower(login) = lower(lg);
    if not found or u.nivel::text <> 'Entregador' then return _falha('Esse usuário não é um entregador cadastrado.'); end if;
    if not u.ativo then return _falha('Esse entregador está inativo.'); end if;
  end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  if v.tipo <> 'Entrega' then return _falha('Só pedidos de entrega têm entregador.'); end if;
  if v.status_pedido::text = 'Entregue' then return _falha('Esta entrega já foi concluída.'); end if;
  if v.status_pedido::text = 'Saiu para entrega' and lg = '' then return _falha('O pedido já saiu para entrega — troque o entregador, não remova.'); end if;
  ant := coalesce(_login_de(v.entregador_id), '(nenhum)');
  update vendas set entregador_id = case when lg = '' then null else u.id end where id = v.id;
  perform _auditar('Entregador atribuído', '#' || v.numero_pedido || ': ' || ant || ' → ' || coalesce(nullif(lg,''), '(nenhum)'));
  return jsonb_build_object('ok', true);
end $$;

-- confirmar recebimento (A Receber -> Pago; carimba a fidelidade na hora em que o dinheiro entra)
create or replace function api_confirmar_recebimento_pedido(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t record; v vendas;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  select * into t from _pedido_trava(p); v := t.v;
  if t.erro is not null then return case when v.status = 'Cancelada' then _falha('Este pedido foi cancelado — não dá para receber o pagamento.') else t.erro end; end if;
  if v.status_pagamento = 'Pago' then return jsonb_build_object('ok', true, 'duplicado', true, 'message', 'Este pedido já estava com o pagamento confirmado.'); end if;
  update vendas set status_pagamento = 'Pago', recebido_em = now() where id = v.id;
  if nullif(v.telefone_cliente,'') is not null then perform _carimbar_fidelidade(v.telefone_cliente, v.cliente_nome); end if;
  perform _auditar('Pagamento confirmado', '#' || v.numero_pedido, v.telefone_cliente);
  return jsonb_build_object('ok', true);
end $$;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as assinatura, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like 'api\_%' or p.proname like '\_%') loop
    execute format('revoke all on function %s from public, anon', f.assinatura);
    if f.proname like 'api\_%' then execute format('grant execute on function %s to authenticated', f.assinatura); end if;
  end loop;
end $$;
commit;
-- FIM DO ARQUIVO


-- >>>>>>>>>> 04_etapa3c2b2_e_correcoes.sql <<<<<<<<<<
-- =====================================================================
-- Texas Burger — Etapa 3c-2b2 + correções de segurança (v-etapa-03c2b2)
-- Rodar DEPOIS dos outros arquivos (tabelas, RLS, cadastros, usuários/estoque,
-- caixa/vendas, andamento de pedidos). Pode rodar de novo sem problema.
-- Reflete exatamente o que está hoje no projeto Supabase "texas-burger".
-- =====================================================================
begin;

-- 1) Corrige o escopo do Garçom em api_avancar_status_pedido (usa o ID da mesa, não o nome)
create or replace function api_avancar_status_pedido(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare t record; v vendas; novo text := p->>'novoStatus'; atual text; eu uuid := auth.uid(); lg text; nv text;
begin
  if not tem_nivel('Admin','Operador','Cozinha','Garçom','Entregador') then return _negado(); end if;
  if novo not in ('Em preparo','Pronta','Saiu para entrega','Entregue','Retirada','Servida') then return _falha('Status inválido.'); end if;
  select * into t from _pedido_trava(p); if t.erro is not null then return t.erro; end if;
  v := t.v; atual := coalesce(v.status_pedido::text, ''); lg := _login_de(eu);
  select nivel::text into nv from usuarios where id = eu;
  if nullif(p->>'statusEsperado','') is not null and p->>'statusEsperado' <> atual then
    return _conflito('Este pedido já foi atualizado por outra pessoa (agora está "' || atual || '"). A tela foi atualizada.'); end if;
  if atual = 'Suspenso' then return _falha('Este pedido está suspenso — retome antes de avançar.'); end if;
  if v.tipo = 'Retirada' and novo in ('Saiu para entrega','Entregue','Servida') then return _falha('Pedido de retirada não tem esse status.'); end if;
  if v.tipo = 'Entrega' and novo in ('Retirada','Servida') then return _falha('Pedido de entrega não tem esse status.'); end if;
  if v.tipo = 'Mesa' and novo in ('Saiu para entrega','Entregue','Retirada') then return _falha('Pedido de mesa não tem esse status — use "Servida".'); end if;
  if not ((novo='Em preparo' and atual='Recebido') or (novo='Pronta' and atual='Em preparo') or (novo='Saiu para entrega' and atual='Pronta')
       or (novo='Entregue' and atual='Saiu para entrega') or (novo in ('Retirada','Servida') and atual='Pronta')) then
    if novo = 'Pronta' and atual = 'Recebido' then return _falha('Aceite o pedido e inicie o preparo antes de marcá-lo como pronto.'); end if;
    return _falha('Transição inválida: o pedido está "' || atual || '" e não pode avançar diretamente para "' || novo || '".'); end if;
  if nv = 'Cozinha' and novo not in ('Em preparo','Pronta') then return _falha('A cozinha só pode marcar "Em preparo" e "Pronta".'); end if;
  if nv = 'Garçom' then
    if not (v.registrado_por = eu or exists (select 1 from mesas m where m.id = v.mesa_id and m.garcom_responsavel_id = eu)) then return _falha('Este pedido não está no seu escopo operacional.'); end if;
    if novo <> 'Servida' then return _falha('O garçom apenas pode marcar como "Servida" um pedido de sua mesa.'); end if;
  end if;
  if nv = 'Entregador' then
    if v.tipo <> 'Entrega' or v.entregador_id is distinct from eu then return _falha('Esta entrega não está atribuída a você.'); end if;
    if novo not in ('Saiu para entrega','Entregue') then return _falha('O entregador só pode marcar "Saiu para entrega" e "Entregue".'); end if;
  end if;
  if novo = 'Saiu para entrega' and v.entregador_id is null then return _falha('Atribua um entregador antes de o pedido sair para entrega.'); end if;
  update vendas set status_pedido = novo::status_pedido,
    pronta_em = case when novo = 'Pronta' then now() else pronta_em end,
    saiu_em = case when novo = 'Saiu para entrega' then now() else saiu_em end,
    concluida_em = case when novo in ('Entregue','Retirada','Servida') then now() else concluida_em end
  where id = v.id;
  perform _auditar('Status do pedido atualizado', '#' || v.numero_pedido || ' → ' || novo);
  return jsonb_build_object('ok', true);
end $$;

-- 2) Fechamento de entregador
create or replace function _calc_fechamento_entrega(p_login text, p_data date,
  out qtd int, out total_taxas numeric, out ajuda numeric, out total numeric, out ids uuid[])
language plpgsql security definer set search_path = public as $$
declare uid uuid; ja boolean; aj numeric;
begin
  select id into uid from usuarios where lower(login) = lower(p_login) and nivel::text = 'Entregador';
  select count(*)::int, coalesce(round(sum(taxa_entrega), 2), 0), array_agg(id) into qtd, total_taxas, ids
    from vendas where status = 'Confirmada' and tipo = 'Entrega' and status_pedido::text = 'Entregue' and entregador_id = uid
     and fechamento_entrega_id is null and (concluida_em at time zone 'America/Sao_Paulo')::date = p_data;
  select exists (select 1 from fechamentos_entrega where entregador_id = uid and data_ref = p_data) into ja;
  select coalesce(_num(valor #>> '{}'), 0) into aj from sistema where chave = 'AjudaDiariaEntregador';
  ajuda := case when qtd > 0 and not ja then coalesce(aj, 0) else 0 end;
  total := round(total_taxas + ajuda, 2);
end $$;

create or replace function api_preview_fechamento_entrega(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare c record;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if btrim(coalesce(p->>'entregador','')) = '' or coalesce(p->>'dataRef','') !~ '^\d{4}-\d{2}-\d{2}$' then return _falha('Informe o entregador e a data.'); end if;
  select * into c from _calc_fechamento_entrega(p->>'entregador', (p->>'dataRef')::date);
  return jsonb_build_object('ok', true, 'qtd', c.qtd, 'totalTaxas', c.total_taxas, 'ajudaDiaria', c.ajuda, 'totalDevido', c.total, 'vendaIds', to_jsonb(coalesce(c.ids, '{}'::uuid[])));
end $$;

create or replace function api_fechar_periodo_entregador(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u usuarios; c record; pago numeric; dif numeric; fid uuid; d date;
        req text := btrim(coalesce(p->>'requisicaoId','')); obs text := btrim(coalesce(p->>'observacao',''));
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if btrim(coalesce(p->>'entregador','')) = '' or coalesce(p->>'dataRef','') !~ '^\d{4}-\d{2}-\d{2}$' then return _falha('Informe o entregador e a data.'); end if;
  if req = '' then return _falha('Requisição sem identificador.'); end if;
  if exists (select 1 from fechamentos_entrega where requisicao_id = req) then
    return jsonb_build_object('ok', true, 'duplicado', true, 'message', 'Este fechamento já havia sido registrado.'); end if;
  pago := _num(p->>'valorPago', -1);
  if pago < 0 then return _falha('Informe o valor pago ao entregador.'); end if;
  select * into u from usuarios where lower(login) = lower(p->>'entregador') and nivel::text = 'Entregador';
  if not found then return _falha('Entregador não encontrado.'); end if;
  d := (p->>'dataRef')::date;
  perform pg_advisory_xact_lock(hashtext(u.id::text || d::text));
  select * into c from _calc_fechamento_entrega(u.login, d);
  if c.qtd = 0 then return _falha('Não há entregas concluídas em aberto para esse entregador nessa data.'); end if;
  pago := round(pago, 2); dif := round(pago - c.total, 2);
  if dif <> 0 and obs = '' then return _falha('O valor pago é diferente do devido (R$ ' || _dinheiro(c.total) || '). Informe o motivo da diferença.'); end if;
  insert into fechamentos_entrega (data_ref, entregador_id, qtd_entregas, total_taxas, ajuda_diaria, total_devido, valor_pago, diferenca, fechado_por, observacao, requisicao_id)
  values (d, u.id, c.qtd, c.total_taxas, c.ajuda, c.total, pago, dif, auth.uid(), nullif(obs,''), req) returning id into fid;
  insert into entregas_fechadas (fechamento_id, venda_id, data_ref, entregador_id, taxa)
  select fid, id, d, u.id, taxa_entrega from vendas where id = any(c.ids);
  update vendas set fechamento_entrega_id = fid where id = any(c.ids);
  perform _auditar('Fechamento de entregas', u.login || ' | ' || d || ' | ' || c.qtd || ' entregas | devido R$ ' || _dinheiro(c.total) || ' | pago R$ ' || _dinheiro(pago) || ' | dif R$ ' || _dinheiro(dif) || case when obs <> '' then ' | ' || obs else '' end);
  return jsonb_build_object('ok', true, 'message', 'Fechamento registrado: devido R$ ' || _dinheiro(c.total) || ', pago R$ ' || _dinheiro(pago) || '.');
end $$;

-- 3) Fechar conta da mesa
create or replace function api_fechar_conta_mesa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare m mesas; eu uuid := auth.uid(); nv text; ids uuid[]; total numeric; soma numeric; pg record; resumo text; v record; parte numeric; forma formas_pagamento;
begin
  if not tem_nivel('Admin','Operador','Garçom') then return _negado(); end if;
  select * into m from mesas where id = _uuid(p->>'mesaId') for update;
  if not found then return _falha('Mesa não encontrada.'); end if;
  select nivel::text into nv from usuarios where id = eu;
  if nv = 'Garçom' and m.garcom_responsavel_id is distinct from eu then return _falha('Esta mesa não está sob a sua responsabilidade.'); end if;
  if exists (select 1 from jsonb_array_elements(coalesce(p->'pagamentos','[]'::jsonb)) e where btrim(coalesce(e->>'forma','')) = 'A Receber (Mesa)') then return _falha('Forma de pagamento inválida para esta operação.'); end if;
  select array_agg(id), coalesce(round(sum(valor_total), 2), 0) into ids, total from vendas where mesa_id = m.id and status = 'Confirmada' and status_pagamento = 'A Receber';
  if ids is null then
    update mesas set status = 'Livre', garcom_responsavel_id = null, chamado_tipo = null, chamado_em = null where id = m.id;
    perform _auditar('Status de mesa alterado', 'Mesa ' || m.numero || ' → Livre');
    return jsonb_build_object('ok', true, 'message', 'Essa mesa não tinha conta pendente. Liberada.');
  end if;
  if not exists (select 1 from caixa_sessoes where status = 'Aberto') then return _falha('Abra o caixa antes de fechar a conta da mesa — o valor recebido precisa entrar no fechamento do caixa.'); end if;
  if jsonb_typeof(p->'pagamentos') <> 'array' or jsonb_array_length(p->'pagamentos') = 0 then return _falha('Informe ao menos uma forma de pagamento.'); end if;
  for pg in select value as e from jsonb_array_elements(p->'pagamentos') loop
    if btrim(coalesce(pg.e->>'forma','')) = '' then return _falha('Forma de pagamento não informada.'); end if;
    if not (_num(pg.e->>'valor', 0) > 0) then return _falha('Cada pagamento deve ter um valor maior que zero.'); end if;
    select * into forma from formas_pagamento where lower(nome) = lower(btrim(pg.e->>'forma')) limit 1;
    if not found then return _falha('Forma de pagamento não cadastrada: ' || btrim(pg.e->>'forma')); end if;
    if not forma.ativa then return _falha('A forma de pagamento está inativa: ' || btrim(pg.e->>'forma')); end if;
  end loop;
  select round(coalesce(sum(_num(e->>'valor')), 0), 2) into soma from jsonb_array_elements(p->'pagamentos') e;
  if abs(soma - total) > 0.02 then return _falha('A soma dos pagamentos (R$ ' || _dinheiro(soma) || ') não bate com a conta da mesa (R$ ' || _dinheiro(total) || ').'); end if;
  select string_agg(btrim(e->>'forma'), ' + ') into resumo from jsonb_array_elements(p->'pagamentos') e;
  for v in select id, valor_total, telefone_cliente, cliente_nome from vendas where id = any(ids) loop
    update vendas set forma_pagamento = resumo, status_pagamento = 'Pago', recebido_em = now() where id = v.id;
    for pg in select value as e from jsonb_array_elements(p->'pagamentos') loop
      parte := round(_num(pg.e->>'valor') * (case when total > 0 then v.valor_total / total else 1.0 / array_length(ids, 1) end), 2);
      insert into pagamentos_venda (venda_id, forma_pagamento, valor, taxa_aplicada)
      values (v.id, btrim(pg.e->>'forma'), parte, coalesce((select round(parte * f.taxa_percentual / 100 + f.taxa_fixa, 2) from formas_pagamento f where lower(f.nome) = lower(btrim(pg.e->>'forma'))), 0));
    end loop;
  end loop;
  perform _carimbar_fidelidade(t.tel, t.nome) from (select distinct on (regexp_replace(telefone_cliente, '\D', '', 'g')) telefone_cliente as tel, cliente_nome as nome
    from vendas where id = any(ids) and nullif(telefone_cliente,'') is not null) t;
  update mesas set status = 'Livre', garcom_responsavel_id = null, chamado_tipo = null, chamado_em = null where id = m.id;
  perform _auditar('Conta de mesa fechada', 'Mesa ' || m.numero || ': R$ ' || _dinheiro(total) || ' | ' || resumo || ' | recebido por ' || coalesce(_login_de(eu), '?') || ' (' || nv || ')');
  return jsonb_build_object('ok', true, 'message', 'Conta da mesa ' || m.numero || ' fechada — R$ ' || _dinheiro(total) || '.');
end $$;

-- 4) Regras de leitura dos fechamentos (Admin/Operador veem tudo; Entregador vê só os seus)
drop policy if exists fechamentos_entrega_ler on fechamentos_entrega;
create policy fechamentos_entrega_ler on fechamentos_entrega for select to authenticated using (tem_nivel('Admin','Operador'));
drop policy if exists entregas_fechadas_ler on entregas_fechadas;
create policy entregas_fechadas_ler on entregas_fechadas for select to authenticated using (tem_nivel('Admin','Operador'));
drop policy if exists fechamentos_entrega_ler_entregador on fechamentos_entrega;
create policy fechamentos_entrega_ler_entregador on fechamentos_entrega for select to authenticated using (tem_nivel('Entregador') and entregador_id = (select auth.uid()));
drop policy if exists entregas_fechadas_ler_entregador on entregas_fechadas;
create policy entregas_fechadas_ler_entregador on entregas_fechadas for select to authenticated using (tem_nivel('Entregador') and entregador_id = (select auth.uid()));
grant select on fechamentos_entrega, entregas_fechadas to authenticated;

-- 5) Correção de segurança (permissões)
do $$
declare r record;
begin
  -- views: só leitura
  for r in select c.oid::regclass as v from pg_class c where c.relnamespace='public'::regnamespace and c.relkind='v' loop
    execute format('revoke insert, update, delete, truncate, references, trigger on %s from anon, authenticated, public', r.v);
  end loop;
  -- funções: só as api_* (e _login_de, usada pela v_vendas) ficam acessíveis; o resto é interno
  for r in select p.oid::regprocedure as f, p.proname from pg_proc p
           where p.pronamespace='public'::regnamespace and p.prokind='f' loop
    execute format('revoke execute on function %s from public, anon', r.f);
    if r.proname like 'api\_%' escape '\' or r.proname in ('_login_de') then
      execute format('grant execute on function %s to authenticated', r.f);
    else
      execute format('revoke execute on function %s from authenticated', r.f);
    end if;
  end loop;
  -- search_path fixo nas funções auxiliares
  for r in select p.oid::regprocedure as f from pg_proc p
           where p.pronamespace='public'::regnamespace and p.prokind='f'
             and p.proname in ('_validar_forma','_erro_senha_fraca','_email_login','tocar_atualizado_em','_negado','_falha','_dinheiro','_uuid','_so_digitos','_lista_curta','_num','_conflito') loop
    execute format('alter function %s set search_path = public, pg_catalog', r.f);
  end loop;
end $$;

commit;
-- FIM DO ARQUIVO


-- >>>>>>>>>> 05_etapa3c3a_financeiro.sql <<<<<<<<<<
-- =====================================================================
-- Texas Burger — Etapa 3c-3a: FINANCEIRO (v-etapa-03c3a)
-- Despesas, contas a pagar, despesas mensais (recorrentes) e ajustes pós-venda.
-- Rodar DEPOIS de 04_etapa3c2b2_e_correcoes.sql. Pode rodar de novo sem problema (create or replace).
--
-- Como o status é guardado no banco (diferente da planilha):
--   despesas.status    = 'Paga' | 'A pagar' | 'Cancelada'   (a planilha usava Confirmada/Cancelada + Situação)
--   despesas.situacao  = 'Paga' | 'A pagar'                 (espelho do status; fica o último valor se cancelar)
--   despesas_recorrentes.inicio / termino = PRIMEIRO DIA do mês (a planilha guardava 'aaaa-mm')
--   ajustes_pos_venda.saida = true quando sai dinheiro; "do caixa ou fora" fica em despesas.saiu_do_caixa da despesa ligada
-- Fica para a 3c-3b: editar venda, cupons, eventos, fidelidade/indicações, feedbacks e ocorrências.
-- Fica para a 3c-3c: pedidos públicos (cardápio e QR da mesa).
-- =====================================================================
begin;

-- ---------------------------------------------------------------------
-- 0. Peças de apoio
-- ---------------------------------------------------------------------
create or replace function _data_iso(v text) returns date language plpgsql immutable as $$
begin
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return v::date;
exception when others then return null;
end $$;

create or replace function _comp_valida(v text) returns boolean language sql immutable as $$
  select coalesce(v ~ '^\d{4}-(0[1-9]|1[0-2])$', false)
$$;

create or replace function _meio_dia(d date) returns timestamptz language sql immutable as $$
  select (d::timestamp + interval '12 hours') at time zone 'America/Sao_Paulo'
$$;

create or replace function _competencia_atual() returns text language sql stable as $$
  select to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM')
$$;

create or replace function _categoria_despesa(v text, padrao text default 'Outros') returns text language sql immutable as $$
  select case when v = any (array['Insumos','Aluguel','Energia','Água','Gás','Internet/Telefone','Salários','Impostos','Manutenção','Marketing','Embalagens','Outros'])
              then v else padrao end
$$;

create or replace function _meses_periodicidade(p text) returns int language sql immutable as $$
  select case p when 'Mensal' then 1 when 'Bimestral' then 2 when 'Trimestral' then 3 when 'Semestral' then 6 when 'Anual' then 12 end
$$;

create or replace function _erro_recorrente(p_desc text, p_valor numeric, p_dia numeric, p_period text, p_inicio text, p_termino text) returns text
language sql immutable as $$
  select case
    when btrim(coalesce(p_desc, '')) = '' then 'Informe a descrição.'
    when coalesce(p_valor, 0) <= 0 then 'Informe um valor maior que zero.'
    when p_valor > 9999999 then 'Valor alto demais.'
    when p_dia is null or p_dia < 1 or p_dia > 31 or p_dia <> floor(p_dia) then 'O dia do vencimento deve ser de 1 a 31.'
    when _meses_periodicidade(p_period) is null then 'Periodicidade inválida.'
    when not _comp_valida(p_inicio) then 'Informe o mês de início.'
    when coalesce(p_termino, '') <> '' and (not _comp_valida(p_termino) or p_termino < p_inicio) then 'O término deve ser um mês igual ou depois do início.'
    else '' end
$$;

-- ---------------------------------------------------------------------
-- 1. Despesas avulsas e contas a pagar
-- ---------------------------------------------------------------------
-- Operador só lança despesa PAGA que saiu do caixa (o que faz no balcão); só o Admin cria "A pagar" ou "fora do caixa".
create or replace function api_add_despesa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_desc text := btrim(coalesce(p->>'descricao', '')); v_valor numeric := round(_num(p->>'valor'), 2);
        v_admin boolean := tem_nivel('Admin'); v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb;
        v_sit text; v_caixa boolean; v_cat text; v_venc date := _data_iso(p->>'vencimento'); v_quando timestamptz;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  if v_desc = '' then return _falha('Informe a descrição da despesa.'); end if;
  if v_valor <= 0 then return _falha('Informe um valor maior que zero.'); end if;
  if v_valor > 9999999 then return _falha('Valor alto demais.'); end if;
  v_sit := case when v_admin and p->>'situacao' = 'A pagar' then 'A pagar' else 'Paga' end;
  v_caixa := case when v_admin then coalesce(p->>'saiuDoCaixa', '') <> 'false' else true end;
  v_cat := _categoria_despesa(p->>'categoria');
  if v_sit = 'A pagar' and v_venc is null then return _falha('Informe um vencimento válido para a conta a pagar.'); end if;
  v_quando := case when v_sit = 'A pagar' then _meio_dia(v_venc) else now() end;
  insert into despesas (data_hora, descricao, valor, observacao, status, categoria, vencimento, situacao, competencia, saiu_do_caixa, requisicao_id)
  values (v_quando, v_desc, v_valor, coalesce(p->>'observacao', ''), v_sit::status_despesa, v_cat, v_venc, v_sit,
          case when v_venc is not null then to_char(v_venc, 'YYYY-MM') end,
          case when v_sit = 'Paga' then v_caixa else true end, v_req);
  perform _auditar(case when v_sit = 'A pagar' then 'Conta a pagar registrada' else 'Despesa registrada' end,
                   v_desc || ' [' || v_cat || '] = R$ ' || _dinheiro(v_valor) || case when v_venc is not null then ' | vence ' || v_venc else '' end);
  v_r := jsonb_build_object('ok', true, 'message', case when v_sit = 'A pagar' then 'Conta a pagar registrada: R$ ' || _dinheiro(v_valor) else 'Despesa registrada: R$ ' || _dinheiro(v_valor) end);
  if v_req is not null then perform _idem_gravar(v_req, 'addDespesa', v_r); end if;
  return v_r;
end $$;

create or replace function api_editar_despesa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d despesas%rowtype; v_desc text := btrim(coalesce(p->>'descricao', '')); v_valor numeric := round(_num(p->>'valor'), 2);
        v_cat text; v_venc date; v_venc_txt text := btrim(coalesce(p->>'vencimento', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_desc = '' then return _falha('Informe a descrição da despesa.'); end if;
  if v_valor <= 0 then return _falha('Informe um valor maior que zero.'); end if;
  if v_valor > 9999999 then return _falha('Valor alto demais.'); end if;
  select * into d from despesas where id = _uuid(p->>'id') for update;
  if not found then return _falha('Despesa não encontrada.'); end if;
  if d.status = 'Cancelada' then return _falha('Só é possível editar despesas confirmadas.'); end if;
  if d.categoria = 'Ajuste pós-venda' then return _falha('Esta despesa nasceu de um Ajuste pós-venda. Para desfazer, cancele o ajuste em Financeiro → Ajustes pós-venda.'); end if;
  v_cat := case when p ? 'categoria' then _categoria_despesa(p->>'categoria') else d.categoria end;
  v_venc := d.vencimento;
  if v_venc_txt <> '' then
    v_venc := _data_iso(v_venc_txt);
    if v_venc is null then return _falha('Vencimento inválido.'); end if;
  end if;
  if d.status = 'A pagar' and v_venc is null then return _falha('Conta a pagar precisa de vencimento.'); end if;
  update despesas set descricao = v_desc, valor = v_valor, observacao = coalesce(p->>'observacao', ''), categoria = v_cat,
         vencimento = v_venc,
         data_hora = case when v_venc is distinct from d.vencimento and d.status = 'A pagar' then _meio_dia(v_venc) else data_hora end
   where id = d.id;
  perform _auditar('Despesa editada', v_desc || ' | valor R$ ' || _dinheiro(d.valor) || ' → R$ ' || _dinheiro(v_valor)
    || case when v_venc is distinct from d.vencimento then ' | vencimento ' || coalesce(d.vencimento::text, '—') || ' → ' || coalesce(v_venc::text, '—') else '' end);
  return jsonb_build_object('ok', true, 'message', 'Despesa atualizada.');
end $$;

-- Marca uma conta "A pagar" como paga. A data do gasto passa a ser AGORA (quando o dinheiro saiu).
-- Se saiu do caixa, exige caixa aberto (senão o valor ficaria fora de qualquer conferência de caixa).
create or replace function api_pagar_despesa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d despesas%rowtype; v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb; v_caixa boolean := (coalesce(p->>'saiuDoCaixa', '') = 'true'); v_valor numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  select * into d from despesas where id = _uuid(p->>'id') for update;
  if not found then return _falha('Despesa não encontrada.'); end if;
  if d.status = 'Cancelada' then return _falha('Essa despesa está cancelada.'); end if;
  if d.status <> 'A pagar' then return _falha('Essa despesa já foi paga.'); end if;
  if v_caixa and not exists (select 1 from caixa_sessoes where status = 'Aberto') then
    return _falha('Abra o caixa para registrar um pagamento que sai do caixa.');
  end if;
  v_valor := d.valor;
  if nullif(btrim(coalesce(p->>'valorPago', '')), '') is not null then
    v_valor := round(_num(p->>'valorPago'), 2);
    if v_valor <= 0 then return _falha('Informe um valor pago maior que zero.'); end if;
    if v_valor > 9999999 then return _falha('Valor alto demais.'); end if;
  end if;
  update despesas set data_hora = now(), valor = v_valor, status = 'Paga', situacao = 'Paga', saiu_do_caixa = v_caixa where id = d.id;
  perform _auditar('Conta paga', d.descricao || ' | previsto R$ ' || _dinheiro(d.valor) || ' | pago R$ ' || _dinheiro(v_valor) || ' | ' || case when v_caixa then 'saiu do caixa' else 'fora do caixa' end);
  v_r := jsonb_build_object('ok', true, 'message', 'Pagamento registrado: R$ ' || _dinheiro(v_valor));
  if v_req is not null then perform _idem_gravar(v_req, 'pagarDespesa', v_r); end if;
  return v_r;
end $$;

create or replace function api_cancelar_despesa(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare d despesas%rowtype; v_aut text; v_motivo text := btrim(coalesce(p->>'motivo', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo do cancelamento.'); end if;
  select * into d from despesas where id = _uuid(p->>'id') for update;
  if not found then return _falha('Despesa não encontrada.'); end if;
  if d.categoria = 'Ajuste pós-venda' then return _falha('Esta despesa nasceu de um Ajuste pós-venda. Para desfazer, cancele o ajuste em Financeiro → Ajustes pós-venda.'); end if;
  if d.status = 'Cancelada' then return _falha('Esta despesa já está cancelada.'); end if;
  update despesas set status = 'Cancelada', motivo_cancelamento = v_motivo where id = d.id;
  perform _auditar('Despesa cancelada', d.descricao || ' = R$ ' || _dinheiro(d.valor) || ' | ' || v_motivo);
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------
-- 2. Despesas mensais (recorrentes)
-- ---------------------------------------------------------------------
-- Gera a conta "A pagar" da competência (aaaa-mm) para cada regra ativa que cai nela.
-- Nunca duplica (índice único regra+competência) e o que já foi gerado nunca é alterado por mudança futura na regra.
create or replace function _gerar_despesas_recorrentes(p_comp text) returns int
language plpgsql security definer set search_path = public as $$
declare r record; v_ini date; v_dias int; v_dia int; v_venc date; v_meses int; v_n int := 0; v_lin int;
begin
  if not _comp_valida(p_comp) then return 0; end if;
  v_ini := (p_comp || '-01')::date;
  v_dias := extract(day from (v_ini + interval '1 month' - interval '1 day'))::int;
  for r in select * from despesas_recorrentes
            where ativa and inicio is not null and date_trunc('month', inicio)::date <= v_ini
              and (termino is null or v_ini <= date_trunc('month', termino)::date) loop
    v_meses := (extract(year from v_ini)::int * 12 + extract(month from v_ini)::int) - (extract(year from r.inicio)::int * 12 + extract(month from r.inicio)::int);
    continue when v_meses < 0 or v_meses % coalesce(_meses_periodicidade(r.periodicidade), 1) <> 0;
    v_dia := least(coalesce(r.dia_vencimento, 1), v_dias);
    v_venc := v_ini + (v_dia - 1);
    insert into despesas (data_hora, descricao, valor, observacao, status, categoria, vencimento, situacao, recorrente_id, competencia, saiu_do_caixa)
    values (_meio_dia(v_venc), r.descricao, r.valor, coalesce(r.observacao, ''), 'A pagar', coalesce(r.categoria, 'Outros'), v_venc, 'A pagar', r.id, p_comp, false)
    on conflict (recorrente_id, competencia) where recorrente_id is not null do nothing;
    get diagnostics v_lin = row_count;
    v_n := v_n + v_lin;
  end loop;
  if v_n > 0 then perform _auditar('Despesas mensais geradas', p_comp || ': ' || v_n || ' conta(s)'); end if;
  return v_n;
end $$;

create or replace function api_add_despesa_recorrente(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_desc text := btrim(coalesce(p->>'descricao', '')); v_valor numeric := round(_num(p->>'valor'), 2); v_dia numeric := _num(p->>'diaVencimento', 0);
        v_per text := coalesce(nullif(p->>'periodicidade', ''), 'Mensal'); v_ini text := coalesce(nullif(p->>'inicio', ''), _competencia_atual());
        v_ter text := coalesce(p->>'termino', ''); v_erro text; v_n int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_erro := _erro_recorrente(v_desc, v_valor, v_dia, v_per, v_ini, v_ter);
  if v_erro <> '' then return _falha(v_erro); end if;
  if exists (select 1 from despesas_recorrentes where ativa and lower(btrim(descricao)) = lower(v_desc)) then
    return _falha('Já existe uma despesa mensal ativa com essa descrição.');
  end if;
  insert into despesas_recorrentes (descricao, categoria, valor, dia_vencimento, periodicidade, ativa, observacao, inicio, termino)
  values (v_desc, _categoria_despesa(p->>'categoria'), v_valor, v_dia::int, v_per, true, coalesce(p->>'observacao', ''),
          (v_ini || '-01')::date, case when v_ter <> '' then (v_ter || '-01')::date end);
  perform _auditar('Despesa mensal cadastrada', v_desc || ' = R$ ' || _dinheiro(v_valor) || ' (' || v_per || ', dia ' || v_dia::int || ')');
  v_n := _gerar_despesas_recorrentes(_competencia_atual());
  return jsonb_build_object('ok', true, 'message', 'Despesa mensal cadastrada.' || case when v_n > 0 then ' ' || v_n || ' conta(s) gerada(s) neste mês.' else '' end);
end $$;

-- A mudança vale só para competências AINDA NÃO geradas; contas já geradas ficam como estão (histórico).
create or replace function api_editar_despesa_recorrente(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare a despesas_recorrentes%rowtype; v_desc text; v_valor numeric; v_dia numeric; v_per text; v_ini text; v_ter text; v_erro text; v_cat text; v_ativa boolean;
        v_mudou text[] := '{}'; v_n int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into a from despesas_recorrentes where id = _uuid(p->>'id') for update;
  if not found then return _falha('Despesa mensal não encontrada.'); end if;
  v_desc := case when p ? 'descricao' then btrim(coalesce(p->>'descricao', '')) else a.descricao end;
  v_valor := case when p ? 'valor' then round(_num(p->>'valor'), 2) else a.valor end;
  v_dia := case when p ? 'diaVencimento' then _num(p->>'diaVencimento', 0) else a.dia_vencimento end;
  v_per := case when p ? 'periodicidade' then p->>'periodicidade' else a.periodicidade end;
  v_ini := coalesce(nullif(p->>'inicio', ''), to_char(a.inicio, 'YYYY-MM'));
  v_ter := case when p ? 'termino' then coalesce(p->>'termino', '') else coalesce(to_char(a.termino, 'YYYY-MM'), '') end;
  v_erro := _erro_recorrente(v_desc, v_valor, v_dia, v_per, v_ini, v_ter);
  if v_erro <> '' then return _falha(v_erro); end if;
  v_cat := _categoria_despesa(p->>'categoria', a.categoria);
  v_ativa := case when p ? 'ativa' then coalesce(p->>'ativa', '') <> 'false' else a.ativa end;
  update despesas_recorrentes set descricao = v_desc, categoria = v_cat, valor = v_valor, dia_vencimento = v_dia::int, periodicidade = v_per, ativa = v_ativa,
         observacao = case when p ? 'observacao' then coalesce(p->>'observacao', '') else observacao end,
         inicio = (v_ini || '-01')::date, termino = case when v_ter <> '' then (v_ter || '-01')::date end
   where id = a.id;
  if a.valor <> v_valor then v_mudou := v_mudou || ('valor R$ ' || _dinheiro(a.valor) || ' → R$ ' || _dinheiro(v_valor)); end if;
  if a.dia_vencimento <> v_dia::int then v_mudou := v_mudou || ('dia ' || a.dia_vencimento || ' → ' || v_dia::int); end if;
  if a.periodicidade <> v_per then v_mudou := v_mudou || (a.periodicidade || ' → ' || v_per); end if;
  if a.ativa <> v_ativa then v_mudou := v_mudou || (case when v_ativa then 'reativada' else 'desativada' end); end if;
  perform _auditar('Despesa mensal editada', v_desc || case when array_length(v_mudou, 1) > 0 then ' | ' || array_to_string(v_mudou, ' | ') else '' end);
  v_n := _gerar_despesas_recorrentes(_competencia_atual());
  return jsonb_build_object('ok', true, 'message', 'Despesa mensal atualizada.' || case when v_n > 0 then ' ' || v_n || ' conta(s) gerada(s) neste mês.' else '' end);
end $$;

-- Botão "Gerar contas do mês" (força a geração, mesmo se o mês já foi gerado antes)
create or replace function api_gerar_despesas_mes(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_n int; v_comp text := _competencia_atual();
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_n := _gerar_despesas_recorrentes(v_comp);
  perform _cfg_gravar('ULTIMA_GERACAO_DESPESAS', to_jsonb(v_comp));
  return jsonb_build_object('ok', true, 'message', case when v_n > 0 then v_n || ' conta(s) gerada(s) para este mês.' else 'Nenhuma conta nova: este mês já está gerado.' end);
end $$;

-- Chamada barata para a página fazer ao entrar: só trabalha 1x por mês (guarda o último mês gerado).
-- Faz o papel do gatilho diário da planilha enquanto não houver agendador no banco (decisão pendente, ver entrega).
create or replace function api_garantir_despesas_do_mes(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_comp text := _competencia_atual(); v_n int := 0;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if coalesce((select valor #>> '{}' from sistema where chave = 'ULTIMA_GERACAO_DESPESAS'), '') <> v_comp then
    v_n := _gerar_despesas_recorrentes(v_comp);
    perform _cfg_gravar('ULTIMA_GERACAO_DESPESAS', to_jsonb(v_comp));
  end if;
  return jsonb_build_object('ok', true, 'geradas', v_n);
end $$;

-- ---------------------------------------------------------------------
-- 3. Ajustes pós-venda (reembolso, crédito, cortesia, desconto retroativo)
-- A venda original NUNCA muda. O ajuste é um registro próprio; quando sai dinheiro (reembolso / desconto retroativo)
-- nasce também uma despesa "Ajuste pós-venda" ligada à venda — é ela que faz o dinheiro do caixa bater no fechamento.
-- ---------------------------------------------------------------------
create or replace function api_registrar_ajuste_pos_venda(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_aut text; v_aut_id uuid; v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb;
        v_tipo text := btrim(coalesce(p->>'tipo', '')); v_motivo text := btrim(coalesce(p->>'motivo', '')); v_det text := left(btrim(coalesce(p->>'detalhe', '')), 200);
        v_valor numeric := round(_num(p->>'valor'), 2); ve vendas%rowtype; v_saida boolean; v_onde text; v_ja numeric; v_desp uuid; v_ref text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  if v_tipo <> all (array['Reembolso em dinheiro','Crédito para próxima compra','Cortesia (item grátis)','Desconto retroativo']) then return _falha('Escolha o tipo de ajuste.'); end if;
  if v_motivo <> all (array['Produto errado','Item faltando','Qualidade do produto','Atraso na entrega','Cobrança em duplicidade','Atendimento','Outro']) then return _falha('Escolha o motivo do ajuste.'); end if;
  if v_motivo = 'Outro' and v_det = '' then return _falha('Descreva o motivo (campo "Detalhe") quando escolher "Outro".'); end if;
  if not (v_valor > 0) then return _falha('Informe um valor maior que zero.'); end if;
  select * into ve from vendas where id = _uuid(p->>'vendaId') for update;
  if not found then return _falha('Venda não encontrada.'); end if;
  if ve.status <> 'Confirmada' then return _falha('Só dá para ajustar venda confirmada. Venda cancelada já foi tratada no cancelamento.'); end if;
  if ve.status_pedido is not null and ve.status_pedido::text not in ('Entregue','Retirada','Servida') then
    return _falha('O pedido ainda está "' || ve.status_pedido || '". Antes de terminar, use Editar ou Cancelar. Ajuste pós-venda é para pedido já entregue.');
  end if;
  v_saida := v_tipo in ('Reembolso em dinheiro', 'Desconto retroativo');
  if v_saida and ve.status_pagamento::text is distinct from 'Pago' then return _falha('Esta venda ainda não foi paga — não há o que devolver. Use Editar ou Cancelar.'); end if;
  if v_valor > ve.valor_total + 0.001 then return _falha('O ajuste (R$ ' || _dinheiro(v_valor) || ') não pode ser maior que o valor da venda (R$ ' || _dinheiro(ve.valor_total) || ').'); end if;
  if v_saida then
    select coalesce(sum(valor), 0) into v_ja from ajustes_pos_venda where venda_id = ve.id and status = 'Ativo' and tipo in ('Reembolso em dinheiro', 'Desconto retroativo');
    if v_ja + v_valor > ve.valor_total + 0.001 then
      return _falha('Já foram devolvidos R$ ' || _dinheiro(v_ja) || ' desta venda. Com este ajuste passaria do valor da venda (R$ ' || _dinheiro(ve.valor_total) || ').');
    end if;
  end if;
  v_onde := case when v_saida then (case when p->>'saida' = 'Do caixa' then 'Do caixa' else 'Fora do caixa' end) else 'Sem saída de dinheiro' end;
  if v_onde = 'Do caixa' and not exists (select 1 from caixa_sessoes where status = 'Aberto') then
    return _falha('Abra o caixa para registrar uma devolução que sai do caixa (ou escolha "Fora do caixa").');
  end if;
  v_ref := coalesce('nº ' || ve.numero_pedido, right(ve.id::text, 8));
  if v_saida then
    insert into despesas (descricao, valor, observacao, status, categoria, situacao, saiu_do_caixa)
    values ('Ajuste pós-venda: ' || v_tipo || ' — pedido ' || v_ref, v_valor,
            'Venda ' || right(ve.id::text, 8) || ' | ' || v_motivo || case when v_det <> '' then ' — ' || v_det else '' end,
            'Paga', 'Ajuste pós-venda', 'Paga', (v_onde = 'Do caixa'))
    returning id into v_desp;
  end if;
  select id into v_aut_id from usuarios where lower(login) = lower(v_aut);
  insert into ajustes_pos_venda (venda_id, pedido_numero, cliente, telefone, tipo, valor, motivo, detalhe, saida, despesa_id, status, autorizado_por, registrado_por)
  values (ve.id, ve.numero_pedido, ve.cliente_nome, ve.telefone_cliente, v_tipo, v_valor, v_motivo, v_det, v_saida, v_desp, 'Ativo', v_aut_id, auth.uid());
  perform _auditar('Ajuste pós-venda registrado', v_tipo || ' R$ ' || _dinheiro(v_valor) || ' | pedido ' || v_ref || ' | ' || v_motivo
                   || case when v_det <> '' then ' — ' || v_det else '' end || ' | ' || v_onde, ve.telefone_cliente);
  v_r := jsonb_build_object('ok', true, 'message', 'Ajuste registrado: ' || v_tipo || ' de R$ ' || _dinheiro(v_valor) || '.');
  if v_req is not null then perform _idem_gravar(v_req, 'registrarAjustePosVenda', v_r); end if;
  return v_r;
end $$;

create or replace function api_cancelar_ajuste_pos_venda(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare v_aut text; v_req text := nullif(p->>'requisicaoId', ''); v_r jsonb; v_motivo text := left(btrim(coalesce(p->>'motivo', '')), 200);
        a ajustes_pos_venda%rowtype; d despesas%rowtype; s caixa_sessoes%rowtype; v_ref text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_req is not null then perform pg_advisory_xact_lock(hashtext(v_req)); v_r := _idem_ler(v_req); if v_r is not null then return v_r; end if; end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo do cancelamento do ajuste.'); end if;
  select * into a from ajustes_pos_venda where id = _uuid(p->>'id') for update;
  if not found then return _falha('Ajuste não encontrado.'); end if;
  if a.status = 'Cancelado' then return _falha('Este ajuste já está cancelado.'); end if;
  if a.despesa_id is not null then
    select * into d from despesas where id = a.despesa_id for update;
    if found and d.saiu_do_caixa then
      select * into s from caixa_sessoes where status = 'Aberto' limit 1;
      if not found or a.data_hora < s.abertura then
        return _falha('Esta devolução saiu do caixa de um turno que já foi fechado. Não dá para desfazer sem mexer na conferência daquele dia — registre a diferença como ajuste/despesa nova e fale com o contador.');
      end if;
    end if;
  end if;
  update ajustes_pos_venda set status = 'Cancelado', cancelado_em = now(), motivo_cancelamento = v_motivo where id = a.id;
  if a.despesa_id is not null then
    update despesas set status = 'Cancelada', motivo_cancelamento = 'Ajuste pós-venda cancelado: ' || v_motivo where id = a.despesa_id;
  end if;
  v_ref := coalesce('nº ' || a.pedido_numero, right(a.venda_id::text, 8));
  perform _auditar('Ajuste pós-venda cancelado', a.tipo || ' R$ ' || _dinheiro(a.valor) || ' | pedido ' || v_ref || ' | ' || v_motivo, a.telefone);
  v_r := jsonb_build_object('ok', true, 'message', 'Ajuste cancelado.');
  if v_req is not null then perform _idem_gravar(v_req, 'cancelarAjustePosVenda', v_r); end if;
  return v_r;
end $$;

-- ---------------------------------------------------------------------
-- 4. Quem pode chamar (mesma regra das etapas anteriores): só as api_* ficam acessíveis ao funcionário logado;
--    as auxiliares com "_" ficam só para uso interno do banco.
-- ---------------------------------------------------------------------
do $$
declare r record;
begin
  for r in select p.oid::regprocedure as f, p.proname from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
             and (p.proname like 'api\_%' escape '\' or p.proname in ('_data_iso','_comp_valida','_meio_dia','_competencia_atual','_categoria_despesa','_meses_periodicidade','_erro_recorrente','_gerar_despesas_recorrentes')) loop
    execute format('revoke execute on function %s from public, anon', r.f);
    if r.proname like 'api\_%' escape '\' then
      execute format('grant execute on function %s to authenticated', r.f);
    else
      execute format('revoke execute on function %s from authenticated', r.f);
    end if;
  end loop;
end $$;

commit;
-- FIM DO ARQUIVO
