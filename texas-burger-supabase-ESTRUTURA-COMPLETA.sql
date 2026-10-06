-- =====================================================================
-- TEXAS BURGER — SUPABASE — ESTRUTURA COMPLETA + DADOS
-- Projeto: texas-burger (awryywtgqfaxppayzpca) · região sa-east-1 · Postgres 17
-- Gerado em: 2026-10-05 (Fase 3 + correções dos itens 1 a 12 + ETAPAS 4 A 10: seção 14 no final)
--
-- CONTEÚDO (nesta ordem):
--   1. Extensões        2. Tipos (enums)     3. Sequências
--   4. Tabelas (44)     5. PKs / únicos / checks / FKs   6. Índices
--   7. Funções (166)    8. Views (18)
--   9. Dados            10. Triggers (74)    11. RLS + políticas (76)
--  12. Permissões (GRANT/REVOKE)             13. Ajuste das sequências
--  14. Etapas 4 a 10 (sync, reserva, tempo real, backup/arquivo, fotos, integridade, crons)
--
-- OBSERVAÇÕES
--  * Pode ser rodado inteiro no SQL Editor (é idempotente na estrutura
--    e usa ON CONFLICT DO NOTHING nos dados).
--  * Os dados entram com session_replication_role = replica, portanto
--    NÃO disparam os triggers de sync e não checam FKs durante a carga.
--  * public.usuarios depende de auth.users (mesmos ids). Em um projeto
--    NOVO, recrie os logins no Auth antes, ou remova o bloco "usuarios".
--  * Ficaram FORA dos dados (transitórios): fila_sync (365 linhas),
--    tentativas (3) e requisicoes (0). Senhas/hashes ficam em auth.*,
--    que não é exportado aqui.
-- =====================================================================

SET check_function_bodies = false;
SET client_min_messages = warning;

-- 1. EXTENSÕES --------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;

-- 2. TIPOS (ENUMS) ----------------------------------------------------
DO $$ BEGIN CREATE TYPE public.foto_preferida AS ENUM ('principal', 'contingencia', 'auto'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.nivel_acesso AS ENUM ('Admin', 'Operador', 'Garçom', 'Cozinha', 'Entregador', 'Desenvolvedor'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.op_sync AS ENUM ('INSERT', 'UPDATE', 'DELETE'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.origem_venda AS ENUM ('Balcão', 'Cardápio', 'Garçom'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.status_caixa AS ENUM ('Aberto', 'Fechado'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.status_despesa AS ENUM ('Paga', 'A pagar', 'Cancelada'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.status_indicacao AS ENUM ('Pendente', 'Resgatado'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.status_mesa AS ENUM ('Livre', 'Ocupada', 'Aguardando fechamento', 'Fechada', 'Bloqueada/Manutenção'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.status_ocorrencia AS ENUM ('Aberta', 'Em andamento', 'Resolvida'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.status_pagamento AS ENUM ('Pago', 'A Receber'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.status_pedido AS ENUM ('Recebido', 'Em preparo', 'Pronta', 'Saiu para entrega', 'Entregue', 'Retirada', 'Servida', 'Suspenso'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.tipo_backup AS ENUM ('Manual', 'Automático', 'Pré-restauração'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.tipo_mov_estoque AS ENUM ('Entrada', 'Venda', 'Saída', 'Perda', 'Ajuste', 'Inventário'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.unidade_estoque AS ENUM ('un', 'g', 'kg', 'ml', 'l'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.venda_status AS ENUM ('Confirmada', 'Cancelada'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN CREATE TYPE public.venda_tipo AS ENUM ('Retirada', 'Entrega', 'Mesa'); EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- 3. SEQUÊNCIAS (usadas como DEFAULT) ----------------------------------
CREATE SEQUENCE IF NOT EXISTS public.vendas_numero_pedido_seq AS integer START 1 INCREMENT 1;
CREATE SEQUENCE IF NOT EXISTS public.ocorrencias_numero_seq AS integer START 1 INCREMENT 1;

-- 4. TABELAS ----------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.adicionais (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  preco numeric(10,2) DEFAULT 0 NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  ingrediente_id uuid,
  quantidade_descontar numeric(12,3) DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS public.ajustes_pos_venda (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  data_hora timestamp with time zone DEFAULT now() NOT NULL,
  venda_id uuid NOT NULL,
  pedido_numero integer,
  cliente text,
  telefone text,
  tipo text NOT NULL,
  valor numeric(10,2) DEFAULT 0 NOT NULL,
  motivo text,
  detalhe text,
  saida boolean DEFAULT false NOT NULL,
  despesa_id uuid,
  status text DEFAULT 'Ativo'::text NOT NULL,
  autorizado_por uuid,
  registrado_por uuid,
  cancelado_em timestamp with time zone,
  motivo_cancelamento text
);
CREATE TABLE IF NOT EXISTS public.auditoria (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  data_hora timestamp with time zone DEFAULT now() NOT NULL,
  usuario_id uuid,
  usuario_login text,
  perfil text,
  acao text NOT NULL,
  telefone text,
  detalhes text,
  autorizado_por text,
  aparelho text
);
CREATE TABLE IF NOT EXISTS public.backups (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  data_hora timestamp with time zone DEFAULT now() NOT NULL,
  tipo tipo_backup NOT NULL,
  status text DEFAULT 'Em andamento'::text NOT NULL,
  arquivo text,
  tamanho_bytes bigint,
  tentativas integer DEFAULT 0 NOT NULL,
  erro text,
  usuario_id uuid
);
CREATE TABLE IF NOT EXISTS public.caixa_sessoes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  abertura timestamp with time zone DEFAULT now() NOT NULL,
  fundo_caixa numeric(10,2) DEFAULT 0 NOT NULL,
  fechamento timestamp with time zone,
  total_vendas numeric(10,2),
  total_despesas numeric(10,2),
  saldo_final numeric(10,2),
  status status_caixa DEFAULT 'Aberto'::status_caixa NOT NULL,
  usuario_abertura uuid,
  usuario_fechamento uuid,
  valor_contado numeric(10,2),
  diferenca numeric(10,2)
);
CREATE TABLE IF NOT EXISTS public.categorias (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  ativa boolean DEFAULT true NOT NULL,
  ordem integer DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS public.clientes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  telefone text,
  data_nascimento date,
  endereco text,
  como_conheceu text,
  primeiro_contato timestamp with time zone,
  observacoes text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.combo_itens (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  combo_id uuid NOT NULL,
  produto_id uuid NOT NULL,
  quantidade integer DEFAULT 1 NOT NULL
);
CREATE TABLE IF NOT EXISTS public.combo_precos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  combo_id uuid NOT NULL,
  forma_pagamento_id uuid NOT NULL,
  preco numeric(10,2) DEFAULT 0 NOT NULL,
  custo numeric(10,2) DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS public.combos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  categoria_id uuid,
  ativo boolean DEFAULT true NOT NULL,
  destaque boolean DEFAULT false NOT NULL,
  ordem_cardapio integer DEFAULT 0 NOT NULL,
  foto_id_principal text,
  foto_id_contingencia text,
  foto_url_principal text,
  foto_url_contingencia text,
  foto_preferida foto_preferida DEFAULT 'principal'::foto_preferida NOT NULL
);
CREATE TABLE IF NOT EXISTS public.configuracoes_fotos (
  id boolean DEFAULT true NOT NULL,
  onde_guardar text,
  destino_padrao_upload text,
  drive_preferido foto_preferida,
  sincronizacao_drives text,
  backup_frio_storage text,
  replicar_antigas text,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.cupons (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  codigo text NOT NULL,
  nome text,
  tipo text DEFAULT 'percentual'::text NOT NULL,
  valor numeric(10,2) DEFAULT 0 NOT NULL,
  frete_gratis boolean DEFAULT false NOT NULL,
  data_inicio date,
  data_fim date,
  hora_inicio time without time zone,
  hora_fim time without time zone,
  limite_total integer DEFAULT 0 NOT NULL,
  limite_por_cliente integer DEFAULT 1 NOT NULL,
  valor_minimo numeric(10,2) DEFAULT 0 NOT NULL,
  ativa boolean DEFAULT true NOT NULL,
  acumula boolean DEFAULT false NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_por uuid
);
CREATE TABLE IF NOT EXISTS public.cupons_usos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  cupom_id uuid NOT NULL,
  codigo text,
  venda_id uuid,
  cliente_id uuid,
  telefone text,
  desconto numeric(10,2) DEFAULT 0 NOT NULL,
  frete_gratis boolean DEFAULT false NOT NULL,
  data_hora timestamp with time zone DEFAULT now() NOT NULL,
  requisicao_id text
);
CREATE TABLE IF NOT EXISTS public.despesas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  data_hora timestamp with time zone DEFAULT now() NOT NULL,
  descricao text NOT NULL,
  valor numeric(10,2) DEFAULT 0 NOT NULL,
  observacao text,
  status status_despesa DEFAULT 'Paga'::status_despesa NOT NULL,
  motivo_cancelamento text,
  categoria text,
  vencimento date,
  situacao text,
  recorrente_id uuid,
  competencia text,
  saiu_do_caixa boolean DEFAULT true NOT NULL,
  criada_em timestamp with time zone DEFAULT now() NOT NULL,
  requisicao_id text
);
CREATE TABLE IF NOT EXISTS public.despesas_recorrentes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  descricao text NOT NULL,
  categoria text,
  valor numeric(10,2) DEFAULT 0 NOT NULL,
  dia_vencimento integer,
  periodicidade text DEFAULT 'Mensal'::text NOT NULL,
  ativa boolean DEFAULT true NOT NULL,
  observacao text,
  inicio date,
  termino date,
  criada_em timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.entregas_fechadas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  fechamento_id uuid NOT NULL,
  venda_id uuid NOT NULL,
  data_ref date NOT NULL,
  entregador_id uuid,
  taxa numeric(10,2) DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS public.estoque (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  ingrediente text NOT NULL,
  quantidade numeric(12,3) DEFAULT 0 NOT NULL,
  quantidade_minima numeric(12,3) DEFAULT 0 NOT NULL,
  unidade unidade_estoque DEFAULT 'un'::unidade_estoque NOT NULL,
  custo_unitario numeric(10,4) DEFAULT 0 NOT NULL,
  status text
);
CREATE TABLE IF NOT EXISTS public.eventos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  tipo text,
  data date,
  hora_inicio time without time zone,
  hora_fim time without time zone,
  local text,
  contratante text,
  telefone text,
  status text,
  valor_contratado numeric(10,2) DEFAULT 0 NOT NULL,
  valor_recebido numeric(10,2) DEFAULT 0 NOT NULL,
  valor_a_receber numeric(10,2) DEFAULT 0 NOT NULL,
  custo_total numeric(10,2) DEFAULT 0 NOT NULL,
  resultado numeric(10,2) DEFAULT 0 NOT NULL,
  observacoes text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_por uuid,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.eventos_custos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  evento_id uuid NOT NULL,
  descricao text NOT NULL,
  categoria text,
  valor numeric(10,2) DEFAULT 0 NOT NULL,
  data date,
  observacao text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_por uuid,
  requisicao_id text
);
CREATE TABLE IF NOT EXISTS public.eventos_recebimentos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  evento_id uuid NOT NULL,
  valor numeric(10,2) DEFAULT 0 NOT NULL,
  forma_pagamento text,
  data date,
  observacao text,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  criado_por uuid,
  requisicao_id text
);
CREATE TABLE IF NOT EXISTS public.fechamentos_entrega (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  data_ref date NOT NULL,
  entregador_id uuid,
  qtd_entregas integer DEFAULT 0 NOT NULL,
  total_taxas numeric(10,2) DEFAULT 0 NOT NULL,
  ajuda_diaria numeric(10,2) DEFAULT 0 NOT NULL,
  total_devido numeric(10,2) DEFAULT 0 NOT NULL,
  valor_pago numeric(10,2) DEFAULT 0 NOT NULL,
  diferenca numeric(10,2) DEFAULT 0 NOT NULL,
  fechado_em timestamp with time zone DEFAULT now() NOT NULL,
  fechado_por uuid,
  observacao text,
  requisicao_id text
);
CREATE TABLE IF NOT EXISTS public.feedbacks (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  venda_id uuid,
  cliente_id uuid,
  telefone_cliente text,
  nota integer,
  comentario text,
  data timestamp with time zone DEFAULT now() NOT NULL,
  status text DEFAULT 'Novo'::text NOT NULL
);
CREATE TABLE IF NOT EXISTS public.fidelidade (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  cliente_id uuid NOT NULL,
  carimbos integer DEFAULT 0 NOT NULL,
  premios_resgatados integer DEFAULT 0 NOT NULL,
  atualizada_em timestamp with time zone DEFAULT now() NOT NULL,
  observacoes text
);
CREATE TABLE IF NOT EXISTS public.fila_sync (
  id bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  tabela text NOT NULL,
  registro_id text NOT NULL,
  operacao op_sync NOT NULL,
  payload jsonb,
  criado_em timestamp with time zone DEFAULT now() NOT NULL,
  principal_ok_em timestamp with time zone,
  principal_tentativas integer DEFAULT 0 NOT NULL,
  principal_erro text,
  contingencia_ok_em timestamp with time zone,
  contingencia_tentativas integer DEFAULT 0 NOT NULL,
  contingencia_erro text
);
CREATE TABLE IF NOT EXISTS public.formas_pagamento (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  ativa boolean DEFAULT true NOT NULL,
  visivel_cardapio boolean DEFAULT true NOT NULL,
  taxa_percentual numeric(5,2) DEFAULT 0 NOT NULL,
  taxa_fixa numeric(10,2) DEFAULT 0 NOT NULL,
  prazo_dias integer DEFAULT 0 NOT NULL,
  permite_troco boolean DEFAULT false NOT NULL,
  ordem integer DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS public.indicacoes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  indicador_id uuid,
  indicado_id uuid,
  nome_indicador text,
  telefone_indicador text,
  nome_indicado text,
  telefone_indicado text,
  data timestamp with time zone DEFAULT now() NOT NULL,
  status status_indicacao DEFAULT 'Pendente'::status_indicacao NOT NULL,
  observacoes text
);
CREATE TABLE IF NOT EXISTS public.itens_venda (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  venda_id uuid NOT NULL,
  produto_id uuid,
  combo_id uuid,
  descricao text,
  quantidade integer DEFAULT 1 NOT NULL,
  valor_unitario numeric(10,2) DEFAULT 0 NOT NULL,
  custo_unitario numeric(10,2) DEFAULT 0 NOT NULL,
  valor_total_item numeric(10,2) DEFAULT 0 NOT NULL,
  adicionais_ids uuid[] DEFAULT '{}'::uuid[] NOT NULL
);
CREATE TABLE IF NOT EXISTS public.mesas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  numero text NOT NULL,
  status status_mesa DEFAULT 'Livre'::status_mesa NOT NULL,
  capacidade integer,
  observacao text,
  garcom_responsavel_id uuid,
  chamado_tipo text,
  chamado_em timestamp with time zone
);
CREATE TABLE IF NOT EXISTS public.mesas_codigos (
  mesa_id uuid NOT NULL,
  codigo text NOT NULL,
  gerado_em timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.movimentacoes_estoque (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  ingrediente_id uuid NOT NULL,
  tipo tipo_mov_estoque NOT NULL,
  quantidade numeric(12,3) NOT NULL,
  qtd_antes numeric(12,3),
  qtd_depois numeric(12,3),
  motivo_referencia text,
  usuario_id uuid,
  data timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.ocorrencias (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  numero integer DEFAULT nextval('ocorrencias_numero_seq'::regclass) NOT NULL,
  data_hora timestamp with time zone DEFAULT now() NOT NULL,
  tipo text,
  setor text,
  venda_id uuid,
  cliente text,
  telefone text,
  registrado_por uuid,
  responsavel text,
  descricao text,
  solucao text,
  status status_ocorrencia DEFAULT 'Aberta'::status_ocorrencia NOT NULL,
  atualizada_em timestamp with time zone DEFAULT now() NOT NULL,
  historico jsonb DEFAULT '[]'::jsonb NOT NULL
);
CREATE TABLE IF NOT EXISTS public.pagamentos_venda (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  venda_id uuid NOT NULL,
  forma_pagamento text NOT NULL,
  valor numeric(10,2) DEFAULT 0 NOT NULL,
  taxa_aplicada numeric(10,2) DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS public.produto_adicionais (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  produto_id uuid NOT NULL,
  adicional_id uuid NOT NULL
);
CREATE TABLE IF NOT EXISTS public.produto_ingredientes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  produto_id uuid NOT NULL,
  ingrediente_id uuid NOT NULL,
  quantidade_por_unidade numeric(12,3) DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS public.produto_precos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  produto_id uuid NOT NULL,
  forma_pagamento_id uuid NOT NULL,
  preco numeric(10,2) DEFAULT 0 NOT NULL,
  custo numeric(10,2) DEFAULT 0 NOT NULL
);
CREATE TABLE IF NOT EXISTS public.produtos (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  descricao text,
  categoria_id uuid,
  ativo boolean DEFAULT true NOT NULL,
  destaque boolean DEFAULT false NOT NULL,
  estoque_proprio_ingrediente_id uuid,
  ordem_cardapio integer DEFAULT 0 NOT NULL,
  foto_id_principal text,
  foto_id_contingencia text,
  foto_url_principal text,
  foto_url_contingencia text,
  foto_preferida foto_preferida DEFAULT 'principal'::foto_preferida NOT NULL
);
CREATE TABLE IF NOT EXISTS public.promocoes (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  nome text NOT NULL,
  tipo text,
  regra_duplicidade text,
  beneficio text,
  ativa boolean DEFAULT true NOT NULL
);
CREATE TABLE IF NOT EXISTS public.requisicoes (
  chave text NOT NULL,
  acao text NOT NULL,
  resultado jsonb,
  usuario_id uuid,
  data_hora timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.sangrias (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  data_hora timestamp with time zone DEFAULT now() NOT NULL,
  valor numeric(10,2) NOT NULL,
  motivo text,
  usuario_id uuid,
  caixa_id uuid
);
CREATE TABLE IF NOT EXISTS public.sistema (
  chave text NOT NULL,
  valor jsonb NOT NULL,
  atualizado_em timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.tentativas (
  chave text NOT NULL,
  falhas integer DEFAULT 0 NOT NULL,
  bloqueado_ate timestamp with time zone
);
CREATE TABLE IF NOT EXISTS public.usuarios (
  id uuid NOT NULL,
  login text NOT NULL,
  nome text NOT NULL,
  telefone text,
  nivel nivel_acesso NOT NULL,
  ativo boolean DEFAULT true NOT NULL,
  criado_em timestamp with time zone DEFAULT now() NOT NULL
);
CREATE TABLE IF NOT EXISTS public.vendas (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  numero_pedido integer DEFAULT nextval('vendas_numero_pedido_seq'::regclass) NOT NULL,
  data_hora timestamp with time zone DEFAULT now() NOT NULL,
  cliente_id uuid,
  cliente_nome text,
  telefone_cliente text,
  forma_pagamento text,
  valor_total numeric(10,2) DEFAULT 0 NOT NULL,
  custo_total numeric(10,2) DEFAULT 0 NOT NULL,
  status venda_status DEFAULT 'Confirmada'::venda_status NOT NULL,
  motivo_cancelamento text,
  tipo venda_tipo DEFAULT 'Retirada'::venda_tipo NOT NULL,
  status_pedido status_pedido,
  endereco text,
  complemento text,
  referencia text,
  observacoes_entrega text,
  pronta_em timestamp with time zone,
  concluida_em timestamp with time zone,
  status_pagamento status_pagamento DEFAULT 'Pago'::status_pagamento NOT NULL,
  recebido_em timestamp with time zone,
  valor_original numeric(10,2),
  valor_desconto numeric(10,2) DEFAULT 0 NOT NULL,
  desconto_detalhe text,
  entregador_id uuid,
  saiu_em timestamp with time zone,
  origem origem_venda DEFAULT 'Balcão'::origem_venda NOT NULL,
  mesa_id uuid,
  taxa_entrega numeric(10,2) DEFAULT 0 NOT NULL,
  fechamento_entrega_id uuid,
  registrado_por uuid,
  inicio_preparo_em timestamp with time zone,
  caixa_id uuid,
  requisicao_id text,
  status_antes_suspensao text
);

CREATE TABLE IF NOT EXISTS public.versoes_sync (
  grupo text NOT NULL,
  n bigint DEFAULT 0 NOT NULL
);
-- 5. CONSTRAINTS ------------------------------------------------------
DO $$ BEGIN ALTER TABLE ONLY public.adicionais ADD CONSTRAINT adicionais_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.ajustes_pos_venda ADD CONSTRAINT ajustes_pos_venda_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.auditoria ADD CONSTRAINT auditoria_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.backups ADD CONSTRAINT backups_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.caixa_sessoes ADD CONSTRAINT caixa_sessoes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.categorias ADD CONSTRAINT categorias_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.clientes ADD CONSTRAINT clientes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combo_itens ADD CONSTRAINT combo_itens_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combo_precos ADD CONSTRAINT combo_precos_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combos ADD CONSTRAINT combos_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.configuracoes_fotos ADD CONSTRAINT configuracoes_fotos_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.cupons ADD CONSTRAINT cupons_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.cupons_usos ADD CONSTRAINT cupons_usos_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.despesas ADD CONSTRAINT despesas_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.despesas_recorrentes ADD CONSTRAINT despesas_recorrentes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.entregas_fechadas ADD CONSTRAINT entregas_fechadas_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.estoque ADD CONSTRAINT estoque_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.eventos ADD CONSTRAINT eventos_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.eventos_custos ADD CONSTRAINT eventos_custos_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.eventos_recebimentos ADD CONSTRAINT eventos_recebimentos_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.fechamentos_entrega ADD CONSTRAINT fechamentos_entrega_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.feedbacks ADD CONSTRAINT feedbacks_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.fidelidade ADD CONSTRAINT fidelidade_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.fila_sync ADD CONSTRAINT fila_sync_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.formas_pagamento ADD CONSTRAINT formas_pagamento_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.indicacoes ADD CONSTRAINT indicacoes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.itens_venda ADD CONSTRAINT itens_venda_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.mesas ADD CONSTRAINT mesas_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.mesas_codigos ADD CONSTRAINT mesas_codigos_pkey PRIMARY KEY (mesa_id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.movimentacoes_estoque ADD CONSTRAINT movimentacoes_estoque_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.ocorrencias ADD CONSTRAINT ocorrencias_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.pagamentos_venda ADD CONSTRAINT pagamentos_venda_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_adicionais ADD CONSTRAINT produto_adicionais_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_ingredientes ADD CONSTRAINT produto_ingredientes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_precos ADD CONSTRAINT produto_precos_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produtos ADD CONSTRAINT produtos_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.promocoes ADD CONSTRAINT promocoes_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.requisicoes ADD CONSTRAINT requisicoes_pkey PRIMARY KEY (chave); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.sangrias ADD CONSTRAINT sangrias_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.sistema ADD CONSTRAINT sistema_pkey PRIMARY KEY (chave); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.tentativas ADD CONSTRAINT tentativas_pkey PRIMARY KEY (chave); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.usuarios ADD CONSTRAINT usuarios_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.vendas ADD CONSTRAINT vendas_pkey PRIMARY KEY (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.versoes_sync ADD CONSTRAINT versoes_sync_pkey PRIMARY KEY (grupo); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combo_itens ADD CONSTRAINT combo_itens_quantidade_check CHECK ((quantidade > 0)); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combo_precos ADD CONSTRAINT combo_precos_combo_id_forma_pagamento_id_key UNIQUE (combo_id, forma_pagamento_id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.configuracoes_fotos ADD CONSTRAINT configuracoes_fotos_id_check CHECK (id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.cupons ADD CONSTRAINT cupons_codigo_key UNIQUE (codigo); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.despesas_recorrentes ADD CONSTRAINT despesas_recorrentes_dia_vencimento_check CHECK (((dia_vencimento >= 1) AND (dia_vencimento <= 31))); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.entregas_fechadas ADD CONSTRAINT entregas_fechadas_venda_id_key UNIQUE (venda_id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.fechamentos_entrega ADD CONSTRAINT fechamentos_entrega_requisicao_id_key UNIQUE (requisicao_id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.feedbacks ADD CONSTRAINT feedbacks_nota_check CHECK (((nota >= 1) AND (nota <= 5))); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.fidelidade ADD CONSTRAINT fidelidade_carimbos_check CHECK (((carimbos >= 0) AND (carimbos <= 10))); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.fidelidade ADD CONSTRAINT fidelidade_cliente_id_key UNIQUE (cliente_id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.itens_venda ADD CONSTRAINT itens_venda_quantidade_check CHECK ((quantidade > 0)); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.mesas ADD CONSTRAINT mesas_numero_key UNIQUE (numero); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_adicionais ADD CONSTRAINT produto_adicionais_produto_id_adicional_id_key UNIQUE (produto_id, adicional_id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_precos ADD CONSTRAINT produto_precos_produto_id_forma_pagamento_id_key UNIQUE (produto_id, forma_pagamento_id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.usuarios ADD CONSTRAINT usuarios_login_key UNIQUE (login); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.vendas ADD CONSTRAINT vendas_requisicao_id_key UNIQUE (requisicao_id); EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.adicionais ADD CONSTRAINT adicionais_ingrediente_id_fkey FOREIGN KEY (ingrediente_id) REFERENCES public.estoque(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.ajustes_pos_venda ADD CONSTRAINT ajustes_pos_venda_autorizado_por_fkey FOREIGN KEY (autorizado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.ajustes_pos_venda ADD CONSTRAINT ajustes_pos_venda_despesa_id_fkey FOREIGN KEY (despesa_id) REFERENCES public.despesas(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.ajustes_pos_venda ADD CONSTRAINT ajustes_pos_venda_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.ajustes_pos_venda ADD CONSTRAINT ajustes_pos_venda_venda_id_fkey FOREIGN KEY (venda_id) REFERENCES public.vendas(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.auditoria ADD CONSTRAINT auditoria_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.backups ADD CONSTRAINT backups_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.caixa_sessoes ADD CONSTRAINT caixa_sessoes_usuario_abertura_fkey FOREIGN KEY (usuario_abertura) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.caixa_sessoes ADD CONSTRAINT caixa_sessoes_usuario_fechamento_fkey FOREIGN KEY (usuario_fechamento) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combo_itens ADD CONSTRAINT combo_itens_combo_id_fkey FOREIGN KEY (combo_id) REFERENCES public.combos(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combo_itens ADD CONSTRAINT combo_itens_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES public.produtos(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combo_precos ADD CONSTRAINT combo_precos_combo_id_fkey FOREIGN KEY (combo_id) REFERENCES public.combos(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combo_precos ADD CONSTRAINT combo_precos_forma_pagamento_id_fkey FOREIGN KEY (forma_pagamento_id) REFERENCES public.formas_pagamento(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.combos ADD CONSTRAINT combos_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categorias(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.cupons ADD CONSTRAINT cupons_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.cupons_usos ADD CONSTRAINT cupons_usos_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.cupons_usos ADD CONSTRAINT cupons_usos_cupom_id_fkey FOREIGN KEY (cupom_id) REFERENCES public.cupons(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.cupons_usos ADD CONSTRAINT cupons_usos_venda_id_fkey FOREIGN KEY (venda_id) REFERENCES public.vendas(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.despesas ADD CONSTRAINT despesas_recorrente_id_fkey FOREIGN KEY (recorrente_id) REFERENCES public.despesas_recorrentes(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.entregas_fechadas ADD CONSTRAINT entregas_fechadas_entregador_id_fkey FOREIGN KEY (entregador_id) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.entregas_fechadas ADD CONSTRAINT entregas_fechadas_fechamento_id_fkey FOREIGN KEY (fechamento_id) REFERENCES public.fechamentos_entrega(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.entregas_fechadas ADD CONSTRAINT entregas_fechadas_venda_id_fkey FOREIGN KEY (venda_id) REFERENCES public.vendas(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.eventos ADD CONSTRAINT eventos_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.eventos_custos ADD CONSTRAINT eventos_custos_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.eventos_custos ADD CONSTRAINT eventos_custos_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES public.eventos(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.eventos_recebimentos ADD CONSTRAINT eventos_recebimentos_criado_por_fkey FOREIGN KEY (criado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.eventos_recebimentos ADD CONSTRAINT eventos_recebimentos_evento_id_fkey FOREIGN KEY (evento_id) REFERENCES public.eventos(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.fechamentos_entrega ADD CONSTRAINT fechamentos_entrega_entregador_id_fkey FOREIGN KEY (entregador_id) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.fechamentos_entrega ADD CONSTRAINT fechamentos_entrega_fechado_por_fkey FOREIGN KEY (fechado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.feedbacks ADD CONSTRAINT feedbacks_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.feedbacks ADD CONSTRAINT feedbacks_venda_id_fkey FOREIGN KEY (venda_id) REFERENCES public.vendas(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.fidelidade ADD CONSTRAINT fidelidade_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.indicacoes ADD CONSTRAINT indicacoes_indicado_id_fkey FOREIGN KEY (indicado_id) REFERENCES public.clientes(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.indicacoes ADD CONSTRAINT indicacoes_indicador_id_fkey FOREIGN KEY (indicador_id) REFERENCES public.clientes(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.itens_venda ADD CONSTRAINT itens_venda_combo_id_fkey FOREIGN KEY (combo_id) REFERENCES public.combos(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.itens_venda ADD CONSTRAINT itens_venda_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES public.produtos(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.itens_venda ADD CONSTRAINT itens_venda_venda_id_fkey FOREIGN KEY (venda_id) REFERENCES public.vendas(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.mesas ADD CONSTRAINT mesas_garcom_responsavel_id_fkey FOREIGN KEY (garcom_responsavel_id) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.mesas_codigos ADD CONSTRAINT mesas_codigos_mesa_id_fkey FOREIGN KEY (mesa_id) REFERENCES public.mesas(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.movimentacoes_estoque ADD CONSTRAINT movimentacoes_estoque_ingrediente_id_fkey FOREIGN KEY (ingrediente_id) REFERENCES public.estoque(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.movimentacoes_estoque ADD CONSTRAINT movimentacoes_estoque_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.ocorrencias ADD CONSTRAINT ocorrencias_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.ocorrencias ADD CONSTRAINT ocorrencias_venda_id_fkey FOREIGN KEY (venda_id) REFERENCES public.vendas(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.pagamentos_venda ADD CONSTRAINT pagamentos_venda_venda_id_fkey FOREIGN KEY (venda_id) REFERENCES public.vendas(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_adicionais ADD CONSTRAINT produto_adicionais_adicional_id_fkey FOREIGN KEY (adicional_id) REFERENCES public.adicionais(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_adicionais ADD CONSTRAINT produto_adicionais_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES public.produtos(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_ingredientes ADD CONSTRAINT produto_ingredientes_ingrediente_id_fkey FOREIGN KEY (ingrediente_id) REFERENCES public.estoque(id) ON DELETE RESTRICT; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_ingredientes ADD CONSTRAINT produto_ingredientes_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES public.produtos(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_precos ADD CONSTRAINT produto_precos_forma_pagamento_id_fkey FOREIGN KEY (forma_pagamento_id) REFERENCES public.formas_pagamento(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produto_precos ADD CONSTRAINT produto_precos_produto_id_fkey FOREIGN KEY (produto_id) REFERENCES public.produtos(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produtos ADD CONSTRAINT produtos_categoria_id_fkey FOREIGN KEY (categoria_id) REFERENCES public.categorias(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.produtos ADD CONSTRAINT produtos_estoque_proprio_ingrediente_id_fkey FOREIGN KEY (estoque_proprio_ingrediente_id) REFERENCES public.estoque(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.requisicoes ADD CONSTRAINT requisicoes_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.sangrias ADD CONSTRAINT sangrias_caixa_id_fkey FOREIGN KEY (caixa_id) REFERENCES public.caixa_sessoes(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.sangrias ADD CONSTRAINT sangrias_usuario_id_fkey FOREIGN KEY (usuario_id) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.usuarios ADD CONSTRAINT usuarios_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.vendas ADD CONSTRAINT vendas_caixa_id_fkey FOREIGN KEY (caixa_id) REFERENCES public.caixa_sessoes(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.vendas ADD CONSTRAINT vendas_cliente_id_fkey FOREIGN KEY (cliente_id) REFERENCES public.clientes(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.vendas ADD CONSTRAINT vendas_entregador_id_fkey FOREIGN KEY (entregador_id) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.vendas ADD CONSTRAINT vendas_fechamento_entrega_id_fkey FOREIGN KEY (fechamento_entrega_id) REFERENCES public.fechamentos_entrega(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.vendas ADD CONSTRAINT vendas_mesa_id_fkey FOREIGN KEY (mesa_id) REFERENCES public.mesas(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE ONLY public.vendas ADD CONSTRAINT vendas_registrado_por_fkey FOREIGN KEY (registrado_por) REFERENCES public.usuarios(id) ON DELETE SET NULL; EXCEPTION WHEN duplicate_object OR duplicate_table THEN NULL; END $$;

-- 6. ÍNDICES ----------------------------------------------------------
CREATE INDEX IF NOT EXISTS auditoria_data_idx ON public.auditoria USING btree (data_hora DESC);
CREATE UNIQUE INDEX IF NOT EXISTS caixa_um_aberto_uq ON public.caixa_sessoes USING btree (status) WHERE (status = 'Aberto'::status_caixa);
CREATE UNIQUE INDEX IF NOT EXISTS clientes_telefone_uq ON public.clientes USING btree (telefone) WHERE ((telefone IS NOT NULL) AND (telefone <> ''::text));
CREATE INDEX IF NOT EXISTS despesas_data_idx ON public.despesas USING btree (data_hora DESC);
CREATE UNIQUE INDEX IF NOT EXISTS despesas_recorrente_mes_uq ON public.despesas USING btree (recorrente_id, competencia) WHERE (recorrente_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS fila_sync_pend_contingencia_idx ON public.fila_sync USING btree (id) WHERE (contingencia_ok_em IS NULL);
CREATE INDEX IF NOT EXISTS fila_sync_pend_principal_idx ON public.fila_sync USING btree (id) WHERE (principal_ok_em IS NULL);
CREATE INDEX IF NOT EXISTS itens_venda_venda_idx ON public.itens_venda USING btree (venda_id);
CREATE INDEX IF NOT EXISTS mov_estoque_ing_idx ON public.movimentacoes_estoque USING btree (ingrediente_id, data DESC);
CREATE INDEX IF NOT EXISTS pagamentos_venda_venda_idx ON public.pagamentos_venda USING btree (venda_id);
CREATE INDEX IF NOT EXISTS requisicoes_data_idx ON public.requisicoes USING btree (data_hora);
CREATE INDEX IF NOT EXISTS vendas_data_hora_desc_idx ON public.vendas USING btree (data_hora DESC);
CREATE INDEX IF NOT EXISTS vendas_data_idx ON public.vendas USING btree (data_hora DESC);
CREATE INDEX IF NOT EXISTS vendas_entregador_idx ON public.vendas USING btree (entregador_id) WHERE (entregador_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS vendas_id_sufixo8_idx ON public.vendas USING btree ("right"((id)::text, 8));
CREATE INDEX IF NOT EXISTS vendas_mesa_idx ON public.vendas USING btree (mesa_id) WHERE (mesa_id IS NOT NULL);
CREATE INDEX IF NOT EXISTS vendas_status_pedido_idx ON public.vendas USING btree (status_pedido) WHERE (status = 'Confirmada'::venda_status);
CREATE INDEX IF NOT EXISTS vendas_telefone_idx ON public.vendas USING btree (telefone_cliente);

-- 7. FUNÇÕES ----------------------------------------------------------
CREATE OR REPLACE FUNCTION public._agora_br()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select to_char(now() at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI')
$function$;

CREATE OR REPLACE FUNCTION public._ajustar_estoque(p_itens jsonb, p_dir integer, p_venda uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public._auditar(p_acao text, p_detalhes text DEFAULT NULL::text, p_telefone text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into auditoria (usuario_id, usuario_login, perfil, acao, telefone, detalhes, autorizado_por)
  select u.id, u.login, u.nivel::text, p_acao, p_telefone, p_detalhes, nullif(current_setting('app.autorizador', true), '')
  from usuarios u where u.id = auth.uid()
$function$;

CREATE OR REPLACE FUNCTION public._auditar_publico(p_acao text, p_detalhes text, p_tel text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into auditoria (usuario_login, perfil, acao, telefone, detalhes) values ('Cardápio (cliente)', 'Cliente', p_acao, p_tel, p_detalhes)
$function$;

CREATE OR REPLACE FUNCTION public._bump_versao_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_grupos text[]; v_chave text; v_tx text := txid_current()::text;
begin
  -- dispara no COMMIT (gatilho adiado): o carimbo só muda quando a alteração já está visível para todos
  v_grupos := case
    when tg_table_name = 'sistema' then array['cad', 'din']
    when tg_table_name in ('formas_pagamento','categorias','produtos','produto_precos','produto_ingredientes','combos','combo_precos','combo_itens','adicionais','produto_adicionais') then array['cad']
    else array['din'] end;
  v_chave := 'app.vsync_' || array_to_string(v_grupos, '_');
  if coalesce(current_setting(v_chave, true), '') = v_tx then return null; end if;   -- 1 incremento por grupo e por transação
  perform set_config(v_chave, v_tx, true);
  perform 1 from versoes_sync where grupo in ('cad', 'din') order by grupo for update;  -- ordem fixa de travas: sem deadlock
  update versoes_sync set n = n + 1 where grupo = any(v_grupos);
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public._calc_fechamento_entrega(p_login text, p_data date, OUT qtd integer, OUT total_taxas numeric, OUT ajuda numeric, OUT total numeric, OUT ids uuid[])
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid; ja boolean; aj numeric;
begin
  select id into uid from usuarios where lower(login) = lower(p_login) and nivel::text = 'Entregador';
  select count(*)::int, coalesce(round(sum(taxa_entrega), 2), 0), coalesce(array_agg(id), '{}'::uuid[]) into qtd, total_taxas, ids
    from vendas where status = 'Confirmada' and tipo = 'Entrega' and status_pedido::text = 'Entregue' and entregador_id = uid
     and fechamento_entrega_id is null and (concluida_em at time zone 'America/Sao_Paulo')::date = p_data;
  select exists (select 1 from fechamentos_entrega where entregador_id = uid and data_ref = p_data) into ja;
  select coalesce(_num(valor #>> '{}'), 0) into aj from sistema where chave = 'AjudaDiariaEntregador';
  ajuda := case when qtd > 0 and not ja then coalesce(aj, 0) else 0 end;
  total := round(total_taxas + ajuda, 2);
end $function$;

CREATE OR REPLACE FUNCTION public._carimbar_fidelidade(p_tel text, p_nome text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public._categoria_despesa(v text, padrao text DEFAULT 'Outros'::text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case when v = any (array['Insumos','Aluguel','Energia','Água','Gás','Internet/Telefone','Salários','Impostos','Manutenção','Marketing','Embalagens','Outros'])
              then v else padrao end
$function$;

CREATE OR REPLACE FUNCTION public._cfg_gravar(p_chave text, p_valor jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into sistema (chave, valor) values (p_chave, p_valor)
  on conflict (chave) do update set valor = excluded.valor
$function$;

CREATE OR REPLACE FUNCTION public._combo_gravar_itens(p_combo uuid, p_itens jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from combo_itens where combo_id = p_combo;
  insert into combo_itens (combo_id, produto_id, quantidade)
  select p_combo, _uuid(e->>'produtoId'), _num(e->>'quantidade')::int
  from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) e
  where _uuid(e->>'produtoId') is not null and _num(e->>'quantidade') > 0;
end $function$;

CREATE OR REPLACE FUNCTION public._combo_gravar_precos(p_combo uuid, p_precos jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from combo_precos where combo_id = p_combo;
  insert into combo_precos (combo_id, forma_pagamento_id, preco, custo)
  select p_combo, _uuid(e->>'formaPagamentoId'), _num(e->>'preco'), _num(e->>'custo')
  from jsonb_array_elements(coalesce(p_precos, '[]'::jsonb)) e where _uuid(e->>'formaPagamentoId') is not null
  on conflict (combo_id, forma_pagamento_id) do update set preco = excluded.preco, custo = excluded.custo;
end $function$;

CREATE OR REPLACE FUNCTION public._comp_valida(v text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(v ~ '^\d{4}-(0[1-9]|1[0-2])$', false)
$function$;

CREATE OR REPLACE FUNCTION public._competencia_atual()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select to_char(now() at time zone 'America/Sao_Paulo', 'YYYY-MM')
$function$;

CREATE OR REPLACE FUNCTION public._conflito(p_msg text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object('ok', false, 'conflito', true, 'message', p_msg) $function$;

CREATE OR REPLACE FUNCTION public._consumo(p_itens jsonb)
 RETURNS TABLE(ingrediente_id uuid, qtd numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public._criar_login_auth(p_id uuid, p_email text, p_senha text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public._criar_pedido_publico(p jsonb, p_mesa_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_eh_mesa boolean := p_mesa_id is not null; v_mesa mesas%rowtype;
  v_nome text := _texto_publico(p->>'clienteNome', 80);
  v_tel text := case when p_mesa_id is not null then '' else _texto_publico(p->>'clienteTelefone', 20) end;
  v_dig text := case when p_mesa_id is not null then '' else _so_digitos(p->>'clienteTelefone') end;
  v_obs_troco text := _texto_publico(p->>'observacaoTroco', 200);
  v_de jsonb := case when jsonb_typeof(p->'dadosEntrega') = 'object' then p->'dadosEntrega' else '{}'::jsonb end;
  v_end text := _texto_publico(v_de->>'endereco', 200); v_comp text := _texto_publico(v_de->>'complemento', 100); v_ref text := _texto_publico(v_de->>'referencia', 150);
  v_obs_ent text := _texto_publico(coalesce(nullif(p->>'observacoes', ''), v_de->>'observacoes'), 300);
  v_itens jsonb := p->'itens'; v_tipo_in text := p->>'tipoEntrega'; v_ip text := _ip_cliente();
  v_req text := nullif(left(btrim(coalesce(p->>'requisicaoId', '')), 80), '');
  v_forma formas_pagamento%rowtype; v_caixa uuid; v_tipo venda_tipo; v_ja record; v_prod produtos%rowtype; v_comb combos%rowtype;
  it record; r record; v_prod_id uuid; v_comb_id uuid; v_qtd numeric; v_preco numeric; v_custo_u numeric; v_nome_item text; v_extra numeric; v_n_ad int; v_n_ok int;
  v_ads text; v_obs_item text; v_ads_ids jsonb; v_itens_ok jsonb := '[]'::jsonb; v_orig numeric := 0; v_custo numeric := 0;
  v_cod text := ''; v_cup jsonb; v_desc numeric := 0; v_frete boolean := false; v_taxa numeric := 0; v_pad numeric; v_total numeric;
  v_venda uuid := gen_random_uuid(); v_numero int; v_cli uuid; v_chave text; v_obs_final text; v_bloqueia boolean; v_forma_nome text;
begin
  -- repetição do mesmo envio (duplo toque, nova tentativa): devolve o pedido já criado, sem criar outro
  if v_req is not null then
    perform pg_advisory_xact_lock(hashtext('venda:' || v_req));
    select id, numero_pedido, valor_total into v_ja from vendas where requisicao_id = v_req;
    if found then
      return jsonb_build_object('ok', true, 'duplicado', true, 'id', v_ja.id, 'numero', v_ja.numero_pedido, 'valorTotal', v_ja.valor_total, 'message', 'Pedido já recebido — envio repetido ignorado.');
    end if;
  end if;

  if jsonb_typeof(v_itens) <> 'array' or jsonb_array_length(v_itens) = 0 then return _falha('Carrinho vazio.'); end if;
  if jsonb_array_length(v_itens) > 40 then return _falha('Carrinho grande demais.'); end if;
  if v_eh_mesa then
    if v_nome = '' then return _falha('Informe o seu nome.'); end if;
    v_chave := 'pedmesa_' || p_mesa_id::text;
  else
    if v_nome = '' or v_dig = '' then return _falha('Informe nome e telefone.'); end if;
    if length(v_dig) < 10 or length(v_dig) > 13 then return _falha('Informe um telefone válido com DDD.'); end if;
    v_chave := 'pedcard_' || v_dig;
  end if;
  if _excedeu('pedcard_global', 150) then return _falha('Estamos com muitos pedidos no momento. Tente novamente em alguns minutos ou ligue para o restaurante.'); end if;
  if _excedeu('pedcard_ip_' || v_ip, 15) then return _falha('Muitos pedidos em sequência. Aguarde alguns minutos.'); end if;
  if _excedeu(v_chave, case when v_eh_mesa then 8 else 5 end) then
    return _falha(case when v_eh_mesa then 'Muitos pedidos em sequência nesta mesa. Chame o garçom.' else 'Muitos pedidos em sequência. Aguarde alguns minutos.' end);
  end if;

  select id into v_caixa from caixa_sessoes where status = 'Aberto' limit 1;
  if v_caixa is null then return _falha('Estamos fechados no momento. Tente novamente mais tarde.'); end if;

  if v_eh_mesa then
    select * into v_mesa from mesas where id = p_mesa_id for update;
    if not found then return _falha('Mesa não encontrada.'); end if;
    if v_mesa.status::text not in ('Livre', 'Ocupada') then
      return _falha(case when v_mesa.status::text = 'Aguardando fechamento' then 'A conta desta mesa já foi pedida. Chame o garçom para novos pedidos.' else 'Esta mesa não está disponível para pedidos pelo celular. Chame o garçom.' end);
    end if;
    v_tipo := 'Mesa';
    -- mesa: o cliente não escolhe a forma; vale a primeira forma do cardápio só para o preço (o recebimento é feito no fechamento da conta)
    select * into v_forma from formas_pagamento where ativa and visivel_cardapio order by ordem limit 1;
    v_forma_nome := 'A Receber (Mesa)';
  else
    v_tipo := (case when v_tipo_in = 'Entrega' then 'Entrega' else 'Retirada' end)::venda_tipo;
    if v_tipo = 'Entrega' and v_end = '' then return _falha('Informe o endereço de entrega.'); end if;
    select * into v_forma from formas_pagamento where id = _uuid(p->>'formaPagamentoId') and ativa and visivel_cardapio;
    v_forma_nome := v_forma.nome;
  end if;
  if v_forma.id is null then return _falha('Forma de pagamento inválida.'); end if;

  -- itens: tudo vem do cadastro (produto/combo ativo, preço da forma escolhida, adicionais ativos e vinculados)
  for it in select value as e from jsonb_array_elements(v_itens) loop
    v_qtd := _num(it.e->>'quantidade');
    if v_qtd <= 0 then continue; end if;
    if v_qtd > 50 or v_qtd <> floor(v_qtd) then return _falha('Quantidade inválida no carrinho.'); end if;
    v_prod_id := _uuid(it.e->>'produtoId'); v_comb_id := _uuid(it.e->>'comboId');
    if (v_prod_id is null) = (v_comb_id is null) then return _falha('Item inválido no carrinho.'); end if;
    if jsonb_typeof(it.e->'adicionaisIds') = 'array' and jsonb_array_length(it.e->'adicionaisIds') > 20 then return _falha('Adicionais demais em um item.'); end if;
    if v_prod_id is not null then
      select * into v_prod from produtos where id = v_prod_id and ativo;
      if not found then return _falha('Um dos produtos não está mais disponível.'); end if;
      v_nome_item := v_prod.nome;
      select preco, custo into v_preco, v_custo_u from produto_precos where produto_id = v_prod_id and forma_pagamento_id = v_forma.id limit 1;
      if not found then return _falha('"' || v_nome_item || '" não tem preço configurado para essa forma de pagamento.'); end if;
    else
      select * into v_comb from combos where id = v_comb_id and ativo;
      if not found then return _falha('Um dos combos não está mais disponível.'); end if;
      if exists (select 1 from combo_itens ci join produtos pr on pr.id = ci.produto_id where ci.combo_id = v_comb_id and not pr.ativo) then
        return _falha('O combo "' || v_comb.nome || '" está temporariamente indisponível.');
      end if;
      v_nome_item := v_comb.nome;
      select preco, custo into v_preco, v_custo_u from combo_precos where combo_id = v_comb_id and forma_pagamento_id = v_forma.id limit 1;
      if not found then return _falha('"' || v_nome_item || '" não tem preço configurado para essa forma de pagamento.'); end if;
    end if;
    select count(*), coalesce(sum(a.preco), 0),
           count(a.id) filter (where a.ativo and (v_prod_id is null or exists (select 1 from produto_adicionais pa where pa.produto_id = v_prod_id and pa.adicional_id = a.id))),
           coalesce(string_agg(' + ' || a.nome, '' order by s.ord) filter (where a.id is not null), ''),
           coalesce(jsonb_agg(a.id order by s.ord) filter (where a.id is not null), '[]'::jsonb)
      into v_n_ad, v_extra, v_n_ok, v_ads, v_ads_ids
      from jsonb_array_elements_text(case when jsonb_typeof(it.e->'adicionaisIds') = 'array' then it.e->'adicionaisIds' else '[]'::jsonb end) with ordinality as s(x, ord)
      left join adicionais a on a.id = _uuid(s.x);
    if v_n_ad <> v_n_ok then return _falha('Um adicional escolhido para "' || v_nome_item || '" não está disponível.'); end if;
    v_obs_item := _texto_publico(it.e->>'observacao', 100);
    v_itens_ok := v_itens_ok || jsonb_build_array(jsonb_build_object('produtoId', v_prod_id, 'comboId', v_comb_id,
      'descricao', v_nome_item || v_ads || case when v_obs_item <> '' then ' — Obs: ' || v_obs_item else '' end,
      'quantidade', v_qtd, 'valorUnitario', v_preco + v_extra, 'custoUnitario', v_custo_u, 'adicionaisIds', v_ads_ids));
    v_orig := v_orig + round(v_qtd * (v_preco + v_extra), 2); v_custo := v_custo + v_qtd * v_custo_u;
  end loop;
  if jsonb_array_length(v_itens_ok) = 0 then return _falha('Carrinho vazio.'); end if;
  v_orig := round(v_orig, 2); v_custo := round(v_custo, 2);

  select coalesce((select (valor #>> '{}') = 'true' from sistema where chave = 'BLOQUEAR_ESTOQUE_NEGATIVO'), false) into v_bloqueia;
  if v_bloqueia then
    for r in select c.ingrediente_id, c.qtd, e.quantidade from _consumo(v_itens_ok) c join estoque e on e.id = c.ingrediente_id loop
      if r.quantidade + 0.000000001 < r.qtd then return _falha('Um dos itens do pedido acabou. Escolha outro item ou fale com o restaurante.'); end if;
    end loop;
  end if;

  -- cupom (só no cardápio comum; travado por código para dois pedidos simultâneos não estourarem o limite)
  if not v_eh_mesa then
    v_cod := upper(regexp_replace(btrim(coalesce(p->>'codigoCupom', '')), '\s+', '', 'g'));
    if v_cod <> '' then
      perform pg_advisory_xact_lock(hashtext('cupom:' || v_cod));
      v_cup := _cupom_calcular(v_cod, v_tel, v_orig, v_tipo::text);
      if coalesce(v_cup->>'ok', '') <> 'true' then return v_cup; end if;
      v_desc := (v_cup->>'desconto')::numeric; v_frete := (v_cup->>'freteGratis')::boolean;
    end if;
  end if;

  if v_tipo = 'Entrega' and not v_frete then
    select coalesce(_num(valor #>> '{}'), 0) into v_pad from sistema where chave = 'TaxaEntregaPadrao';
    v_taxa := coalesce(v_pad, 0);
  end if;
  v_total := greatest(0.01, round(v_orig - v_desc + v_taxa, 2));
  v_obs_final := coalesce(concat_ws(' — ', nullif(v_obs_ent, ''), nullif(v_obs_troco, '')), '');

  insert into vendas (id, cliente_nome, telefone_cliente, forma_pagamento, valor_total, custo_total, status, tipo, status_pedido,
                      endereco, complemento, referencia, observacoes_entrega, status_pagamento, valor_original, valor_desconto,
                      desconto_detalhe, origem, mesa_id, taxa_entrega, caixa_id, requisicao_id)
  values (v_venda, v_nome, v_tel, v_forma_nome, v_total, v_custo, 'Confirmada', v_tipo, 'Recebido',
          case when v_tipo = 'Entrega' then v_end else '' end, case when v_tipo = 'Entrega' then v_comp else '' end, case when v_tipo = 'Entrega' then v_ref else '' end,
          v_obs_final, 'A Receber', v_orig, v_desc, case when v_cod <> '' then 'Cupom ' || (v_cup->>'codigo') else '' end, 'Cardápio',
          case when v_eh_mesa then p_mesa_id else null end, v_taxa, v_caixa, v_req)
  returning numero_pedido into v_numero;

  insert into itens_venda (venda_id, produto_id, combo_id, descricao, quantidade, valor_unitario, custo_unitario, valor_total_item, adicionais_ids)
  select v_venda, _uuid(e->>'produtoId'), _uuid(e->>'comboId'), e->>'descricao', _num(e->>'quantidade', 1)::int, _num(e->>'valorUnitario'), _num(e->>'custoUnitario'),
         round(_num(e->>'quantidade', 1) * _num(e->>'valorUnitario'), 2),
         coalesce((select array_agg(_uuid(x)) filter (where _uuid(x) is not null) from jsonb_array_elements_text(e->'adicionaisIds') x), '{}')
  from jsonb_array_elements(v_itens_ok) e;

  insert into pagamentos_venda (venda_id, forma_pagamento, valor, taxa_aplicada)
  values (v_venda, v_forma_nome, v_total, case when v_eh_mesa then 0 else round(v_total * v_forma.taxa_percentual / 100 + v_forma.taxa_fixa, 2) end);

  if v_eh_mesa and v_mesa.status::text = 'Livre' then update mesas set status = 'Ocupada' where id = p_mesa_id; end if;
  perform _ajustar_estoque(v_itens_ok, 1, v_venda);
  if v_tel <> '' then v_cli := _upsert_cliente(v_tel, v_nome); end if;
  if v_cod <> '' then
    insert into cupons_usos (cupom_id, codigo, venda_id, cliente_id, telefone, desconto, frete_gratis, requisicao_id)
    values ((v_cup->>'cupomId')::uuid, v_cup->>'codigo', v_venda, v_cli, v_tel, v_desc, v_frete, v_req);
  end if;
  perform _registrar_falha(v_chave, 600); perform _registrar_falha('pedcard_global', 300); perform _registrar_falha('pedcard_ip_' || v_ip, 600);
  perform _auditar_publico(case when v_eh_mesa then 'Pedido recebido pelo cliente na mesa ' || v_mesa.numero else 'Pedido recebido pelo Cardápio' end,
    'Total R$ ' || _dinheiro(v_total) || case when v_cod <> '' then ' | Cupom ' || (v_cup->>'codigo') else '' end, case when v_eh_mesa then v_nome else v_tel end);

  return jsonb_build_object('ok', true, 'message', 'Pedido enviado! Nº ' || v_numero || '. Total: R$ ' || _dinheiro(v_total) || '.',
    'id', v_venda, 'numero', v_numero, 'valorTotal', v_total, 'valorOriginal', v_orig, 'valorDesconto', v_desc,
    'cupom', case when v_cod <> '' then v_cup->>'codigo' else '' end, 'freteGratis', v_frete);
end $function$;

CREATE OR REPLACE FUNCTION public._cupom_calcular(p_codigo text, p_tel text, p_subtotal numeric, p_tipo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c cupons%rowtype; v_cod text := upper(regexp_replace(btrim(coalesce(p_codigo, '')), '\s+', '', 'g'));
  v_tel text := _so_digitos(p_tel); v_bruto numeric := round(coalesce(p_subtotal, 0), 2); v_desc numeric := 0;
  v_agora timestamp := now() at time zone 'America/Sao_Paulo'; v_hh int; v_hi int; v_hf int; v_usos int; v_usos_cli int;
begin
  if v_cod = '' then return _falha('Informe um cupom.'); end if;
  select * into c from cupons where codigo = v_cod and ativa;
  if not found then return _falha('Cupom inválido ou inativo.'); end if;
  if (c.data_inicio is not null and v_agora::date < c.data_inicio) or (c.data_fim is not null and v_agora::date > c.data_fim) then
    return _falha('Este cupom está fora do período de validade.');
  end if;
  if c.hora_inicio is not null and c.hora_fim is not null then
    v_hh := extract(hour from v_agora)::int * 60 + extract(minute from v_agora)::int;
    v_hi := extract(hour from c.hora_inicio)::int * 60 + extract(minute from c.hora_inicio)::int;
    v_hf := extract(hour from c.hora_fim)::int * 60 + extract(minute from c.hora_fim)::int;
    if v_hi <= v_hf then
      if v_hh < v_hi or v_hh > v_hf then return _falha('Este cupom está fora do período de validade.'); end if;
    else
      if v_hh < v_hi and v_hh > v_hf then return _falha('Este cupom está fora do período de validade.'); end if;
    end if;
  end if;
  select count(*), count(*) filter (where v_tel <> '' and _so_digitos(telefone) = v_tel) into v_usos, v_usos_cli from cupons_usos where cupom_id = c.id;
  if c.limite_total > 0 and v_usos >= c.limite_total then return _falha('O limite de utilizações deste cupom foi atingido.'); end if;
  if c.limite_por_cliente > 0 and v_usos_cli >= c.limite_por_cliente then return _falha('Você já atingiu o limite de uso deste cupom.'); end if;
  if v_bruto < c.valor_minimo then return _falha('Este cupom exige pedido mínimo de R$ ' || replace(_dinheiro(c.valor_minimo), '.', ',') || '.'); end if;
  if c.tipo = 'percentual' then
    if c.valor <= 0 or c.valor > 100 then return _falha('Cupom configurado com percentual inválido.'); end if;
    v_desc := round(v_bruto * c.valor / 100, 2);
  elsif c.tipo = 'fixo' then
    if c.valor <= 0 then return _falha('Cupom configurado com valor inválido.'); end if;
    v_desc := least(v_bruto, round(c.valor, 2));
  elsif c.tipo = 'frete' then
    v_desc := 0;
  else
    return _falha('Tipo de cupom não suportado.');
  end if;
  v_desc := round(least(v_desc, greatest(0, v_bruto - 0.01)), 2);
  return jsonb_build_object('ok', true, 'cupomId', c.id, 'codigo', c.codigo, 'nome', c.nome, 'tipo', c.tipo, 'desconto', v_desc,
    'freteGratis', (c.frete_gratis or c.tipo = 'frete'), 'acumula', c.acumula,
    'limiteRestante', case when c.limite_total > 0 then greatest(0, c.limite_total - v_usos - 1) else null end);
end $function$;

CREATE OR REPLACE FUNCTION public._cupom_validar(p jsonb, p_id uuid, OUT erro text, OUT c cupons)
 RETURNS record
 LANGUAGE plpgsql
AS $function$
declare v_cod text := upper(regexp_replace(btrim(coalesce(p->>'codigo', '')), '\s+', '', 'g'));
        v_tipo text := coalesce(nullif(btrim(p->>'tipo'), ''), 'percentual'); v_val numeric := _num(p->>'valor');
begin
  if v_cod !~ '^[A-Z0-9_-]{3,40}$' then erro := 'Código inválido. Use letras, números, _ ou -.'; return; end if;
  if btrim(coalesce(p->>'nome', '')) = '' then erro := 'Informe o nome da promoção.'; return; end if;
  if v_tipo <> all (array['percentual','fixo','frete']) then erro := 'Tipo de cupom inválido.'; return; end if;
  if v_tipo <> 'frete' and v_val <= 0 then erro := 'Valor do benefício inválido.'; return; end if;
  if v_tipo = 'percentual' and v_val > 100 then erro := 'Percentual não pode ultrapassar 100%.'; return; end if;
  if exists (select 1 from cupons where codigo = v_cod and id is distinct from p_id) then erro := 'Já existe um cupom com esse código.'; return; end if;
  c.codigo := v_cod; c.nome := left(btrim(p->>'nome'), 80); c.tipo := v_tipo; c.valor := case when v_tipo = 'frete' then greatest(0, v_val) else round(v_val, 2) end;
  c.frete_gratis := coalesce(p->>'freteGratis', '') in ('true', 't', 'Sim');
  c.data_inicio := _data_iso(btrim(coalesce(p->>'dataInicio', ''))); c.data_fim := _data_iso(btrim(coalesce(p->>'dataFim', '')));
  c.hora_inicio := _hora_valida(p->>'horaInicio'); c.hora_fim := _hora_valida(p->>'horaFim');
  c.limite_total := greatest(0, floor(_num(p->>'limiteTotal'))::int); c.limite_por_cliente := greatest(0, floor(_num(p->>'limitePorCliente'))::int);
  c.valor_minimo := greatest(0, round(_num(p->>'valorMinimo'), 2));
  c.ativa := coalesce(p->>'ativa', '') not in ('false', 'f', 'Não'); c.acumula := coalesce(p->>'acumula', '') in ('true', 't', 'Sim');
end $function$;

CREATE OR REPLACE FUNCTION public._data_iso(v text)
 RETURNS date
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
begin
  if v is null or v !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return v::date;
exception when others then return null;
end $function$;

CREATE OR REPLACE FUNCTION public._dinheiro(v numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select to_char(coalesce(v, 0), 'FM999999990.00')
$function$;

CREATE OR REPLACE FUNCTION public._email_login(p_login text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select translate(lower(btrim(p_login)), 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ', 'aaaaaaceeeeiiiinooooouuuuyy') || '@usuarios.texasburger.app'
$function$;

CREATE OR REPLACE FUNCTION public._erro_recorrente(p_desc text, p_valor numeric, p_dia numeric, p_period text, p_inicio text, p_termino text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case
    when btrim(coalesce(p_desc, '')) = '' then 'Informe a descrição.'
    when coalesce(p_valor, 0) <= 0 then 'Informe um valor maior que zero.'
    when p_valor > 9999999 then 'Valor alto demais.'
    when p_dia is null or p_dia < 1 or p_dia > 31 or p_dia <> floor(p_dia) then 'O dia do vencimento deve ser de 1 a 31.'
    when _meses_periodicidade(p_period) is null then 'Periodicidade inválida.'
    when not _comp_valida(p_inicio) then 'Informe o mês de início.'
    when coalesce(p_termino, '') <> '' and (not _comp_valida(p_termino) or p_termino < p_inicio) then 'O término deve ser um mês igual ou depois do início.'
    else '' end
$function$;

CREATE OR REPLACE FUNCTION public._erro_senha_fraca(p_senha text, p_login text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when length(coalesce(p_senha, '')) < 8 then 'A senha precisa ter ao menos 8 caracteres.'
    when p_login is not null and lower(p_senha) = lower(p_login) then 'A senha não pode ser igual ao login.'
    when p_senha ~ '^(.)\1+$' or lower(p_senha) in ('12345678','123456789','1234567890','87654321','senha123','password','qwertyui','11111111')
      then 'Essa senha é fácil demais de adivinhar. Escolha outra.'
    else '' end
$function$;

CREATE OR REPLACE FUNCTION public._estoque_proprio(p_atual uuid, p_nome text, p_ep jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public._evento_json(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select jsonb_build_object('id', e.id, 'nome', e.nome, 'tipo', coalesce(e.tipo, ''), 'data', coalesce(e.data::text, ''),
    'horaInicio', coalesce(to_char(e.hora_inicio, 'HH24:MI'), ''), 'horaFim', coalesce(to_char(e.hora_fim, 'HH24:MI'), ''),
    'local', coalesce(e.local, ''), 'contratante', coalesce(e.contratante, ''), 'telefone', coalesce(e.telefone, ''), 'status', coalesce(e.status, 'Orçamento'),
    'valorContratado', e.valor_contratado, 'valorRecebido', e.valor_recebido, 'valorAReceber', e.valor_a_receber, 'custoTotal', e.custo_total,
    'resultado', e.resultado, 'observacoes', coalesce(e.observacoes, ''), 'criadoEm', e.criado_em, 'atualizadoEm', e.atualizado_em)
  from eventos e where e.id = p_id
$function$;

CREATE OR REPLACE FUNCTION public._excedeu(p_chave text, p_max integer)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce((select falhas >= p_max and bloqueado_ate > now() from tentativas where chave = p_chave), false)
$function$;

CREATE OR REPLACE FUNCTION public._exige_admin(p_senha text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare v_eu usuarios%rowtype; v_chave text; v_adm record;
begin
  select * into v_eu from usuarios where id = auth.uid() and ativo;
  if not found then return null; end if;
  if v_eu.nivel::text in ('Admin','Desenvolvedor') then perform set_config('app.autorizador', v_eu.login, true); return v_eu.login; end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public._falha(p_msg text)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object('ok', false, 'message', p_msg)
$function$;

CREATE OR REPLACE FUNCTION public._gerar_despesas_recorrentes(p_comp text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public._hora_valida(v text)
 RETURNS time without time zone
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
begin
  if v is null or btrim(v) !~ '^\d{1,2}:\d{2}(:\d{2})?$' then return null; end if;
  return btrim(v)::time;
exception when others then return null;
end $function$;

CREATE OR REPLACE FUNCTION public._idem_gravar(p_chave text, p_acao text, p_resultado jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  insert into requisicoes (chave, acao, resultado, usuario_id) values (p_chave, p_acao, p_resultado, auth.uid())
  on conflict (chave) do nothing
$function$;

CREATE OR REPLACE FUNCTION public._idem_ler(p_chave text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select resultado from requisicoes where chave = p_chave
$function$;

CREATE OR REPLACE FUNCTION public._ip_cliente()
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
declare h jsonb; ip text;
begin
  begin h := nullif(current_setting('request.headers', true), '')::jsonb; exception when others then h := null; end;
  ip := coalesce(nullif(h->>'cf-connecting-ip', ''), nullif(h->>'x-real-ip', ''), nullif(split_part(coalesce(h->>'x-forwarded-for', ''), ',', 1), ''));
  if ip is null then
    ip := 'sem-ip-' || left(md5(coalesce(h->>'user-agent', '') || '|' || coalesce(h->>'accept-language', '')), 12);
  end if;
  return left(btrim(ip), 45);
end $function$;

CREATE OR REPLACE FUNCTION public._itens_da_venda(p_venda uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('produtoId', i.produto_id, 'comboId', i.combo_id, 'quantidade', i.quantidade,
                                               'adicionaisIds', to_jsonb(i.adicionais_ids))), '[]'::jsonb)
  from itens_venda i where i.venda_id = p_venda
$function$;

CREATE OR REPLACE FUNCTION public._limpar_falhas(p_chave text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  delete from tentativas where chave = p_chave
$function$;

CREATE OR REPLACE FUNCTION public._lista_curta(p_itens text[])
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select array_to_string(p_itens[1:6], ', ') || case when coalesce(array_length(p_itens, 1), 0) > 6 then ' e mais ' || (array_length(p_itens, 1) - 6) else '' end
$function$;

CREATE OR REPLACE FUNCTION public._lista_qr_mesas()
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'numero', m.numero, 'codigo', c.codigo)
         order by case when m.numero ~ '^\d{1,9}$' then m.numero::int end, m.numero), '[]'::jsonb)
  from mesas m join mesas_codigos c on c.mesa_id = m.id
$function$;

CREATE OR REPLACE FUNCTION public._login_de(p_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select login from usuarios where id = p_id
$function$;

CREATE OR REPLACE FUNCTION public._meio_dia(d date)
 RETURNS timestamp with time zone
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select (d::timestamp + interval '12 hours') at time zone 'America/Sao_Paulo'
$function$;

CREATE OR REPLACE FUNCTION public._mesa_qr(p_numero text, p_codigo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ip text := _ip_cliente(); v_cod text := btrim(coalesce(p_codigo, '')); v_id uuid;
begin
  if _excedeu('mesaqr_ip_' || v_ip, 15) or _excedeu('mesaqr_fail', 200) then
    return jsonb_build_object('ok', false, 'message', 'Muitas tentativas. Aguarde alguns minutos ou chame o garçom.');
  end if;
  select me.id into v_id from mesas me join mesas_codigos mc on mc.mesa_id = me.id
   where me.numero = btrim(coalesce(p_numero, '')) and v_cod <> '' and mc.codigo = v_cod;
  if v_id is null then
    perform _registrar_falha('mesaqr_ip_' || v_ip, 600); perform _registrar_falha('mesaqr_fail', 600);
    return jsonb_build_object('ok', false, 'invalido', true, 'message', 'QR Code inválido ou desativado. Chame o garçom.');
  end if;
  return jsonb_build_object('ok', true, 'mesaId', v_id);
end $function$;

CREATE OR REPLACE FUNCTION public._meses_periodicidade(p text)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select case p when 'Mensal' then 1 when 'Bimestral' then 2 when 'Trimestral' then 3 when 'Semestral' then 6 when 'Anual' then 12 end
$function$;

CREATE OR REPLACE FUNCTION public._negado()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select jsonb_build_object('ok', false, 'message', 'Seu perfil não tem permissão para esta ação.')
$function$;

CREATE OR REPLACE FUNCTION public._num(v text, padrao numeric DEFAULT 0)
 RETURNS numeric
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  return coalesce(nullif(btrim(v), '')::numeric, padrao);
exception when others then
  return padrao;
end $function$;

CREATE OR REPLACE FUNCTION public._pedido_trava(p jsonb, OUT v vendas, OUT erro jsonb)
 RETURNS record
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  select * into v from vendas where id = _uuid(p->>'vendaId') for update;
  if not found then erro := _falha('Pedido não encontrado.');
  elsif v.status <> 'Confirmada' then erro := _falha('Este pedido foi cancelado.');
  elsif v.fechamento_entrega_id is not null then erro := _falha('Esta entrega já está em um fechamento — não pode mais ser alterada.');
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._precos_ou_base(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when jsonb_typeof(p->'precos') = 'array' and jsonb_array_length(p->'precos') > 0 then p->'precos'
    else coalesce((select jsonb_agg(jsonb_build_object('formaPagamentoId', f.id, 'preco', _num(p->>'precoBase'), 'custo', _num(p->>'custoBase'))) from formas_pagamento f), '[]'::jsonb) end
$function$;

CREATE OR REPLACE FUNCTION public._produto_gravar_adicionais(p_prod uuid, p_ads jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from produto_adicionais where produto_id = p_prod;
  insert into produto_adicionais (produto_id, adicional_id)
  select distinct p_prod, _uuid(x) from jsonb_array_elements_text(coalesce(p_ads, '[]'::jsonb)) x where _uuid(x) is not null
  on conflict (produto_id, adicional_id) do nothing;
end $function$;

CREATE OR REPLACE FUNCTION public._produto_gravar_precos(p_prod uuid, p_precos jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from produto_precos where produto_id = p_prod;
  insert into produto_precos (produto_id, forma_pagamento_id, preco, custo)
  select p_prod, _uuid(e->>'formaPagamentoId'), _num(e->>'preco'), _num(e->>'custo')
  from jsonb_array_elements(coalesce(p_precos, '[]'::jsonb)) e
  where _uuid(e->>'formaPagamentoId') is not null
  on conflict (produto_id, forma_pagamento_id) do update set preco = excluded.preco, custo = excluded.custo;
end $function$;

CREATE OR REPLACE FUNCTION public._produto_gravar_receita(p_prod uuid, p_ingr jsonb, p_proprio uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  delete from produto_ingredientes where produto_id = p_prod;
  insert into produto_ingredientes (produto_id, ingrediente_id, quantidade_por_unidade)
  select p_prod, _uuid(e->>'ingredienteId'), _num(e->>'quantidadePorUnidade')
  from jsonb_array_elements(coalesce(p_ingr, '[]'::jsonb)) e where _uuid(e->>'ingredienteId') is not null;
  if p_proprio is not null then
    insert into produto_ingredientes (produto_id, ingrediente_id, quantidade_por_unidade) values (p_prod, p_proprio, 1);
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public._recalcular_evento(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_contr numeric; v_custos numeric; v_rec numeric;
begin
  select valor_contratado into v_contr from eventos where id = p_id;
  if not found then return; end if;
  select coalesce(sum(valor), 0) into v_custos from eventos_custos where evento_id = p_id;
  select coalesce(sum(valor), 0) into v_rec from eventos_recebimentos where evento_id = p_id;
  update eventos set valor_recebido = v_rec, valor_a_receber = greatest(0, v_contr - v_rec), custo_total = v_custos,
         resultado = round(v_contr - v_custos, 2) where id = p_id;
end $function$;

CREATE OR REPLACE FUNCTION public._registrar_falha(p_chave text, p_seg integer DEFAULT 600)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public._senha_confere(p_user uuid, p_senha text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
  select coalesce((select u.encrypted_password = crypt(p_senha, u.encrypted_password) from auth.users u where u.id = p_user), false)
$function$;

CREATE OR REPLACE FUNCTION public._so_digitos(t text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select regexp_replace(coalesce(t, ''), '\D', '', 'g')
$function$;

CREATE OR REPLACE FUNCTION public._texto_publico(t text, mx integer)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select btrim(left(btrim(replace(replace(regexp_replace(regexp_replace(coalesce(t, ''), '[' || chr(1) || '-' || chr(31) || chr(127) || ']+', ' ', 'g'), '[<>`]', '', 'g'), '"', '”'), '''', '’')), greatest(mx, 0)))
$function$;

CREATE OR REPLACE FUNCTION public._upsert_cliente(p_tel text, p_nome text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid; v_dig text := _so_digitos(p_tel);
begin
  if v_dig = '' then return null; end if;
  -- pedidos simultâneos do mesmo telefone passam um de cada vez (o segundo já encontra o cliente criado pelo primeiro)
  perform pg_advisory_xact_lock(hashtextextended('cliente:' || v_dig, 0));
  select id into v_id from clientes where _so_digitos(telefone) = v_dig limit 1;
  if found then
    if btrim(coalesce(p_nome, '')) <> '' then update clientes set nome = btrim(p_nome) where id = v_id and btrim(coalesce(nome, '')) = ''; end if;
    return v_id;
  end if;
  begin
    v_id := gen_random_uuid();
    insert into clientes (id, nome, telefone, primeiro_contato) values (v_id, btrim(coalesce(p_nome, '')), btrim(p_tel), now());
  exception when unique_violation then
    -- rede de segurança (índice único por dígitos): outro caminho criou o mesmo telefone no meio tempo
    select id into v_id from clientes where _so_digitos(telefone) = v_dig limit 1;
    if v_id is null then raise; end if;
  end;
  return v_id;
end $function$;

CREATE OR REPLACE FUNCTION public._uuid(v text)
 RETURNS uuid
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin
  return nullif(btrim(v), '')::uuid;
exception when others then
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public._validar_forma(pct numeric, fixa numeric, prazo numeric)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public', 'pg_catalog'
AS $function$
  select case
    when pct < 0 or pct > 100 then 'A taxa % deve ficar entre 0 e 100.'
    when fixa < 0 then 'A taxa fixa não pode ser negativa.'
    when prazo < 0 or prazo > 365 or prazo <> floor(prazo) then 'O prazo deve ser um número inteiro de dias (0 a 365).'
    else '' end
$function$;

CREATE OR REPLACE FUNCTION public._versao_conflita(p jsonb, p_tab text, p_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_esp text := btrim(coalesce(p->>'versaoEsperada', '')); v_atual text;
begin
  -- sem versão no pedido (aparelho antigo, contingência): não trava, como na planilha
  if v_esp = '' or p_id is null then return false; end if;
  if p_tab <> all (array['produtos','combos','adicionais','formas_pagamento','categorias','clientes','cupons','eventos','despesas','despesas_recorrentes','usuarios','vendas']) then
    raise exception 'Tabela sem controle de versão: %', p_tab;
  end if;
  -- trava a linha até o fim da transação: ninguém altera entre a conferência e a gravação
  execute format('select 1 from public.%I where id = $1 for update', p_tab) using p_id;
  select ver into v_atual from _versoes_tabela(p_tab, p_id);
  return v_atual is distinct from v_esp;
end $function$;

CREATE OR REPLACE FUNCTION public._versoes_tabela(p_tab text, p_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(rid uuid, ver text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  -- "versão" = carimbo (md5) do conteúdo que a pessoa vê/edita; muda sempre que o registro (ou seus filhos) muda
  if p_tab = 'produtos' then
    return query select x.id, md5(
        (to_jsonb(x) - 'foto_id_principal' - 'foto_id_contingencia' - 'foto_url_principal' - 'foto_url_contingencia' - 'foto_preferida')::text
        || '|' || coalesce((select jsonb_agg(jsonb_build_array(a.forma_pagamento_id, a.preco, a.custo) order by a.forma_pagamento_id)::text from produto_precos a where a.produto_id = x.id), '')
        || '|' || coalesce((select jsonb_agg(jsonb_build_array(a.ingrediente_id, a.quantidade_por_unidade) order by a.ingrediente_id)::text from produto_ingredientes a where a.produto_id = x.id), '')
        || '|' || coalesce((select jsonb_agg(a.adicional_id order by a.adicional_id)::text from produto_adicionais a where a.produto_id = x.id), ''))
      from produtos x where p_id is null or x.id = p_id;
  elsif p_tab = 'combos' then
    return query select x.id, md5(
        (to_jsonb(x) - 'foto_id_principal' - 'foto_id_contingencia' - 'foto_url_principal' - 'foto_url_contingencia' - 'foto_preferida')::text
        || '|' || coalesce((select jsonb_agg(jsonb_build_array(a.forma_pagamento_id, a.preco, a.custo) order by a.forma_pagamento_id)::text from combo_precos a where a.combo_id = x.id), '')
        || '|' || coalesce((select jsonb_agg(jsonb_build_array(a.produto_id, a.quantidade) order by a.produto_id, a.quantidade)::text from combo_itens a where a.combo_id = x.id), ''))
      from combos x where p_id is null or x.id = p_id;
  elsif p_tab = 'vendas' then
    return query select x.id, md5(
        jsonb_build_array(x.status, x.status_pedido, x.valor_total, x.valor_original, x.valor_desconto, x.forma_pagamento, x.status_pagamento, x.tipo)::text
        || '|' || coalesce((select jsonb_agg(jsonb_build_array(i.produto_id, i.combo_id, i.descricao, i.quantidade, i.valor_unitario, i.custo_unitario)
                                              order by i.descricao, i.produto_id, i.combo_id, i.valor_unitario, i.quantidade)::text
                              from itens_venda i where i.venda_id = x.id), ''))
      from vendas x where p_id is null or x.id = p_id;
  elsif p_tab = 'adicionais' then
    return query select x.id, md5(to_jsonb(x)::text) from adicionais x where p_id is null or x.id = p_id;
  elsif p_tab = 'formas_pagamento' then
    return query select x.id, md5(to_jsonb(x)::text) from formas_pagamento x where p_id is null or x.id = p_id;
  elsif p_tab = 'categorias' then
    return query select x.id, md5(to_jsonb(x)::text) from categorias x where p_id is null or x.id = p_id;
  elsif p_tab = 'clientes' then
    return query select x.id, md5(to_jsonb(x)::text) from clientes x where p_id is null or x.id = p_id;
  elsif p_tab = 'cupons' then
    return query select x.id, md5(to_jsonb(x)::text) from cupons x where p_id is null or x.id = p_id;
  elsif p_tab = 'eventos' then
    return query select x.id, md5(to_jsonb(x)::text) from eventos x where p_id is null or x.id = p_id;
  elsif p_tab = 'despesas' then
    return query select x.id, md5(to_jsonb(x)::text) from despesas x where p_id is null or x.id = p_id;
  elsif p_tab = 'despesas_recorrentes' then
    return query select x.id, md5(to_jsonb(x)::text) from despesas_recorrentes x where p_id is null or x.id = p_id;
  elsif p_tab = 'usuarios' then
    return query select x.id, md5(to_jsonb(x)::text) from usuarios x where p_id is null or x.id = p_id;
  else
    raise exception 'Tabela sem controle de versão: %', p_tab;
  end if;
end $function$;

CREATE OR REPLACE FUNCTION public.api_abrir_caixa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_aceitar_pedido(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t record; v vendas;
begin
  if not tem_nivel('Admin','Operador','Cozinha') then return _negado(); end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  if v.status_pedido::text <> 'Recebido' then return _conflito('Esse pedido não está mais aguardando aceite.'); end if;
  update vendas set status_pedido = 'Em preparo' where id = v.id;
  perform _auditar('Pedido aceito', '#' || v.numero_pedido, v.telefone_cliente);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_adicional(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nome text := btrim(coalesce(p->>'nome', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome do adicional.'); end if;
  if exists (select 1 from adicionais where lower(btrim(nome)) = lower(v_nome)) then return _falha('Já existe um adicional com esse nome.'); end if;
  insert into adicionais (nome, preco, ativo, ingrediente_id, quantidade_descontar)
  values (v_nome, _num(p->>'preco'), true, _uuid(p->>'ingredienteId'), coalesce(nullif(_num(p->>'quantidadeDesconto'), 0), 1));
  perform _auditar('Adicional cadastrado', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Adicional cadastrado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_categoria(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_ordem int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' then return _falha('Informe o nome da categoria.'); end if;
  if exists (select 1 from categorias where lower(nome) = lower(v_nome)) then return _falha('Já existe uma categoria com esse nome.'); end if;
  select coalesce(max(ordem), 0) + 1 into v_ordem from categorias;
  insert into categorias (nome, ativa, ordem) values (v_nome, true, v_ordem);
  perform _auditar('Categoria cadastrada', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Categoria cadastrada.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_combo(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_despesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_despesa_recorrente(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_feedback(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nota numeric := _num(p->>'nota'); v_dig text := _so_digitos(p->>'telefone'); v_ip text := _ip_cliente(); v_chave text;
        v_venda uuid := _uuid(p->>'vendaId'); v_cli uuid;
begin
  if v_nota < 1 or v_nota > 5 or v_nota <> floor(v_nota) then return _falha('A nota deve ser de 1 a 5.'); end if;
  if v_dig <> '' and (length(v_dig) < 10 or length(v_dig) > 13) then return _falha('Telefone inválido.'); end if;
  v_chave := 'feedback_' || coalesce(nullif(v_dig, ''), 'anon');
  if _excedeu(v_chave, 5) or _excedeu('feedback_ip_' || v_ip, 10) or _excedeu('feedback_global', 120) then
    return _falha('Muitos feedbacks em sequência. Aguarde alguns minutos.');
  end if;
  if v_venda is not null and not exists (select 1 from vendas where id = v_venda) then v_venda := null; end if;
  if v_dig <> '' then select id into v_cli from clientes where _so_digitos(telefone) = v_dig limit 1; end if;
  insert into feedbacks (venda_id, cliente_id, telefone_cliente, nota, comentario, status)
  values (v_venda, v_cli, v_dig, v_nota::int, _texto_publico(p->>'comentario', 500), 'Novo');
  perform _registrar_falha(v_chave, 600); perform _registrar_falha('feedback_ip_' || v_ip, 600); perform _registrar_falha('feedback_global', 600);
  perform _auditar_publico('Feedback recebido', 'Nota ' || v_nota::int, v_dig);
  return jsonb_build_object('ok', true, 'message', 'Obrigado pelo feedback!');
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_forma_pagamento(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_ingrediente(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_num text := btrim(coalesce(p->>'numero', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_num = '' then return _falha('Informe o número da mesa.'); end if;
  if exists (select 1 from mesas where numero = v_num) then return _falha('Já existe uma mesa com esse número.'); end if;
  insert into mesas (numero, status, capacidade) values (v_num, 'Livre', nullif(_num(p->>'capacidade'), 0)::int);
  perform _auditar('Mesa cadastrada', 'Mesa ' || v_num);
  return jsonb_build_object('ok', true, 'message', 'Mesa cadastrada.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_or_stamp_fidelidade(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tel text := btrim(coalesce(p->>'telefone', '')); v_nome text := btrim(coalesce(p->>'nome', ''));
        v_obs text := left(btrim(coalesce(p->>'observacao', '')), 300); v_cli uuid; f fidelidade%rowtype;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if _so_digitos(v_tel) = '' then return _falha('Informe o telefone do cliente.'); end if;
  select id into v_cli from clientes where _so_digitos(telefone) = _so_digitos(v_tel) limit 1;
  if v_cli is not null then select * into f from fidelidade where cliente_id = v_cli for update; end if;
  if f.id is not null then
    if v_obs <> '' then update fidelidade set observacoes = v_obs where id = f.id; end if;
    if f.carimbos >= 10 then
      return jsonb_build_object('ok', true, 'novo', false, 'message', 'Cartão já está completo (10/10). Resgate o prêmio antes de somar nova marca.');
    end if;
    update fidelidade set carimbos = f.carimbos + 1, atualizada_em = now() where id = f.id;
    perform _auditar('Marca adicionada (fidelidade)', (f.carimbos + 1) || '/10', v_tel);
    return jsonb_build_object('ok', true, 'novo', false, 'message', 'Marca adicionada (' || (f.carimbos + 1) || '/10).');
  end if;
  if v_nome = '' then return _falha('Cliente não encontrado no fidelidade e nome não informado.'); end if;
  v_cli := _upsert_cliente(v_tel, v_nome);
  insert into fidelidade (cliente_id, carimbos, atualizada_em, observacoes) values (v_cli, 1, now(), nullif(v_obs, ''))
  on conflict (cliente_id) do update set carimbos = least(10, fidelidade.carimbos + 1), atualizada_em = now();
  perform _auditar('Cliente novo no fidelidade', v_nome, v_tel);
  return jsonb_build_object('ok', true, 'novo', true, 'message', '1ª marca registrada.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_produto(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_add_sangria(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_adicionar_custo_evento(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ev uuid := _uuid(p->>'eventoId'); v_val numeric := round(_num(p->>'valor'), 2); v_req text := nullif(btrim(coalesce(p->>'requisicaoId', '')), '');
        v_desc text := left(btrim(coalesce(p->>'descricao', '')), 160);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_ev is null or not exists (select 1 from eventos where id = v_ev) then return _falha('Evento não encontrado.'); end if;
  if not (v_val > 0) then return _falha('Valor inválido.'); end if;
  if v_req is not null then
    perform pg_advisory_xact_lock(hashtext('evc' || v_req));
    if exists (select 1 from eventos_custos where requisicao_id = v_req) then
      return jsonb_build_object('ok', true, 'message', 'Lançamento já registrado.', 'evento', _evento_json(v_ev));
    end if;
  end if;
  insert into eventos_custos (evento_id, descricao, categoria, valor, data, observacao, criado_por, requisicao_id)
  values (v_ev, v_desc, left(coalesce(nullif(btrim(p->>'categoria'), ''), 'Outros'), 60), v_val,
          coalesce(_data_iso(btrim(coalesce(p->>'data', ''))), (now() at time zone 'America/Sao_Paulo')::date), left(coalesce(p->>'observacao', ''), 300), auth.uid(), v_req);
  perform _recalcular_evento(v_ev);
  perform _auditar('Custo de evento lançado', v_desc || ' R$ ' || _dinheiro(v_val), v_ev::text);
  return jsonb_build_object('ok', true, 'message', 'Custo lançado.', 'evento', _evento_json(v_ev));
end $function$;

CREATE OR REPLACE FUNCTION public.api_adicionar_recebimento_evento(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ev uuid := _uuid(p->>'eventoId'); v_val numeric := round(_num(p->>'valor'), 2); v_req text := nullif(btrim(coalesce(p->>'requisicaoId', '')), '');
        v_forma text := btrim(coalesce(p->>'forma', '')); e eventos%rowtype;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into e from eventos where id = v_ev for update;
  if e.id is null then return _falha('Evento não encontrado.'); end if;
  if not (v_val > 0) then return _falha('Valor inválido.'); end if;
  if v_forma <> '' and not exists (select 1 from formas_pagamento where ativa and nome = v_forma) then return _falha('Forma de pagamento inválida.'); end if;
  if v_val > greatest(0, e.valor_a_receber) + 0.01 then return _falha('O recebimento não pode ultrapassar o valor a receber do evento.'); end if;
  if v_req is not null then
    perform pg_advisory_xact_lock(hashtext('evr' || v_req));
    if exists (select 1 from eventos_recebimentos where requisicao_id = v_req) then
      return jsonb_build_object('ok', true, 'message', 'Recebimento já registrado.', 'evento', _evento_json(v_ev));
    end if;
  end if;
  insert into eventos_recebimentos (evento_id, valor, forma_pagamento, data, observacao, criado_por, requisicao_id)
  values (v_ev, v_val, nullif(v_forma, ''), coalesce(_data_iso(btrim(coalesce(p->>'data', ''))), (now() at time zone 'America/Sao_Paulo')::date),
          left(coalesce(p->>'observacao', ''), 300), auth.uid(), v_req);
  perform _recalcular_evento(v_ev);
  perform _auditar('Recebimento de evento lançado', 'R$ ' || _dinheiro(v_val) || ' ' || v_forma, v_ev::text);
  return jsonb_build_object('ok', true, 'message', 'Recebimento registrado.', 'evento', _evento_json(v_ev));
end $function$;

CREATE OR REPLACE FUNCTION public.api_alternar_cupom(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_on boolean := coalesce(p->>'ativo', '') in ('true', 't', 'Sim'); v_cod text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  update cupons set ativa = v_on where id = _uuid(p->>'id') returning codigo into v_cod;
  if not found then return _falha('Cupom não encontrado.'); end if;
  perform _auditar(case when v_on then 'Cupom ativado' else 'Cupom desativado' end, v_cod);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_aplicar_preco_calculadora(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_novo numeric := round(_num(p->>'novoPreco'), 2); v_antigo numeric; v_prod uuid := _uuid(p->>'produtoId'); v_forma uuid := _uuid(p->>'formaPagamentoId');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not (v_novo > 0) then return _falha('Preço inválido.'); end if;
  select preco into v_antigo from produto_precos where produto_id = v_prod and forma_pagamento_id = v_forma for update;
  if not found then return _falha('Preço do produto para esta forma de pagamento não encontrado.'); end if;
  update produto_precos set preco = v_novo where produto_id = v_prod and forma_pagamento_id = v_forma;
  perform _auditar('Preço aplicado pela calculadora', 'Produto ' || v_prod || ' | forma ' || v_forma || ' | R$ ' || _dinheiro(v_antigo) || ' → R$ ' || _dinheiro(v_novo));
  return jsonb_build_object('ok', true, 'message', 'Preço aplicado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_atender_chamado_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m mesas; v_nivel nivel_acesso := auth_nivel();
begin
  if v_nivel is null or v_nivel not in ('Admin', 'Operador', 'Garçom') then return _negado(); end if;
  select * into m from mesas where id = _uuid(p->>'mesaId') for update;
  if not found then return _falha('Mesa não encontrada.'); end if;
  if v_nivel = 'Garçom' and m.garcom_responsavel_id is not null and m.garcom_responsavel_id <> auth.uid() then return _falha('Esta mesa está sob responsabilidade de outro garçom.'); end if;
  update mesas set chamado_tipo = null, chamado_em = null where id = m.id;
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_atribuir_entregador(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_atualizar_ocorrencia(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_st text := btrim(coalesce(p->>'status', '')); v_sol text := left(btrim(coalesce(p->>'solucao', '')), 600);
        v_resp text := left(btrim(coalesce(p->>'responsavel', '')), 60); v_esp text := nullif(btrim(coalesce(p->>'statusEsperado', '')), '');
        o ocorrencias%rowtype; v_login text := _login_de(auth.uid()); v_nivel_real text; v_linha text;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if v_st <> all (array['Aberta','Em andamento','Resolvida']) then return _falha('Status inválido.'); end if;
  if v_st = 'Resolvida' and char_length(v_sol) < 3 then return _falha('Descreva a solução para resolver a ocorrência.'); end if;
  select * into o from ocorrencias where id = _uuid(p->>'id') for update;
  if o.id is null then return _falha('Ocorrência não encontrada.'); end if;
  if v_esp is not null and v_esp <> o.status::text then
    return jsonb_build_object('ok', false, 'conflito', true,
      'message', 'Essa ocorrência já foi atualizada por outra pessoa (agora está "' || o.status || '"). Confira a lista.');
  end if;
  select nivel::text into v_nivel_real from usuarios where id = auth.uid();
  v_linha := _agora_br() || ' — ' || coalesce(v_login, '') || ' (' || coalesce(v_nivel_real, '') || '): ' || o.status || ' → ' || v_st
             || case when v_resp <> '' then ' · resp.: ' || v_resp else '' end
             || case when v_sol <> '' then ' · solução: ' || left(v_sol, 80) else '' end;
  update ocorrencias set status = v_st::status_ocorrencia, atualizada_em = now(),
         responsavel = case when v_resp <> '' then v_resp else responsavel end,
         solucao = case when v_sol <> '' then v_sol else solucao end,
         historico = historico || to_jsonb(v_linha)
   where id = o.id;
  perform _auditar('Ocorrência atualizada', '#' || o.numero || ': ' || o.status || ' → ' || v_st || case when v_sol <> '' then ' — ' || left(v_sol, 120) else '' end);
  return jsonb_build_object('ok', true, 'message', 'Ocorrência #' || o.numero || ' atualizada.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_avancar_status_pedido(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_cancelar_ajuste_pos_venda(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_cancelar_despesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_cancelar_evento(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_motivo text := left(btrim(coalesce(p->>'motivo', '')), 300);
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  update eventos set status = 'Cancelado', observacoes = coalesce(observacoes, '') || case when v_motivo <> '' then ' | Cancelamento: ' || v_motivo else '' end
   where id = _uuid(p->>'id');
  if not found then return _falha('Evento não encontrado.'); end if;
  perform _auditar('Evento cancelado', p->>'id', v_motivo);
  return jsonb_build_object('ok', true, 'message', 'Evento cancelado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_cancelar_pedido_cardapio_publico(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_alvo text := lower(btrim(coalesce(p->>'codigo', ''))); v vendas%rowtype; v_ip text := _ip_cliente(); v_chave_tel text; v_id uuid;
begin
  if v_alvo !~ '^[0-9a-f-]{8,36}$' then return _falha('Código do pedido inválido.'); end if;
  if _excedeu('cancpub_ip_' || v_ip, 10) or _excedeu('cancpub_falhas', 60) then
    return jsonb_build_object('ok', false, 'message', 'Muitas tentativas seguidas. Ligue para o restaurante.', 'limite', true);
  end if;
  select id into v_id from vendas where right(id::text, 8) = right(v_alvo, 8) and right(id::text, length(v_alvo)) = v_alvo order by data_hora desc limit 1;
  if v_id is not null then select * into v from vendas where id = v_id for update; end if;
  if v_id is null or v.origem <> 'Cardápio' or v.mesa_id is not null then
    perform _registrar_falha('cancpub_ip_' || v_ip, 600); perform _registrar_falha('cancpub_falhas', 600);
    return _falha('Pedido não encontrado ou não pode ser cancelado por aqui.');
  end if;
  v_chave_tel := 'cancpub_' || right(_so_digitos(v.telefone_cliente), 11);
  if _excedeu(v_chave_tel, 3) then
    return jsonb_build_object('ok', false, 'message', 'Você já cancelou vários pedidos em pouco tempo. Ligue para o restaurante.', 'limite', true);
  end if;
  if v.status <> 'Confirmada' then return _falha('Esse pedido já está cancelado.'); end if;
  if v.status_pedido is distinct from 'Recebido' then return _falha('O restaurante já aceitou o pedido. Ligue para o restaurante para alterar.'); end if;
  if v.status_pagamento <> 'A Receber' then return _falha('Este pedido já tem pagamento registrado. Ligue para o restaurante.'); end if;
  if now() - v.data_hora > interval '3 minutes' then return _falha('O prazo de 3 minutos para cancelar já passou. Ligue para o restaurante.'); end if;
  update vendas set status = 'Cancelada', motivo_cancelamento = 'Cancelado pelo cliente (cardápio, até 3 min)' where id = v.id;
  perform _ajustar_estoque(_itens_da_venda(v.id), -1, v.id);
  perform _registrar_falha(v_chave_tel, 600);
  perform _auditar_publico('Pedido cancelado pelo cliente (cardápio)', 'Pedido ' || v.numero_pedido || ' | R$ ' || _dinheiro(v.valor_total), v.telefone_cliente);
  return jsonb_build_object('ok', true, 'message', 'Pedido cancelado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_cancelar_pedido_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_q jsonb := _mesa_qr(p->>'mesa', p->>'codigo'); m mesas; v vendas%rowtype; v_restantes int;
begin
  if v_q->>'ok' <> 'true' then return v_q; end if;
  select * into m from mesas where id = (v_q->>'mesaId')::uuid for update;
  select * into v from vendas where id = _uuid(p->>'vendaId') for update;
  if not found then return _falha('Pedido não encontrado.'); end if;
  if v.mesa_id is distinct from m.id or v.origem <> 'Cardápio' then return _falha('Pedido não encontrado nesta mesa.'); end if;
  if v.status <> 'Confirmada' then return _falha('Esse pedido já foi cancelado.'); end if;
  if v.status_pedido is distinct from 'Recebido' then return _falha('O restaurante já aceitou este pedido. Chame o garçom para alterar.'); end if;
  update vendas set status = 'Cancelada', motivo_cancelamento = 'Cancelado pelo cliente (mesa ' || m.numero || ')' where id = v.id;
  perform _ajustar_estoque(_itens_da_venda(v.id), -1, v.id);
  perform _auditar_publico('Pedido de mesa cancelado pelo cliente', 'Mesa ' || m.numero || ' | R$ ' || _dinheiro(v.valor_total), v.cliente_nome);
  -- mesa aberta só por esse pedido (sem garçom e sem outro pedido pendente): volta a Livre
  select count(*) into v_restantes from vendas where mesa_id = m.id and status = 'Confirmada' and status_pagamento = 'A Receber';
  if m.status::text = 'Ocupada' and m.garcom_responsavel_id is null and v_restantes = 0 then update mesas set status = 'Livre' where id = m.id; end if;
  return jsonb_build_object('ok', true, 'message', 'Pedido cancelado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_cancelar_venda(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_chamar_garcom_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_q jsonb := _mesa_qr(p->>'mesa', p->>'codigo'); m mesas;
begin
  if v_q->>'ok' <> 'true' then return v_q; end if;
  select * into m from mesas where id = (v_q->>'mesaId')::uuid for update;
  if _excedeu('chamargarcom_' || m.id::text, 3) then return jsonb_build_object('ok', true, 'message', 'Já avisamos o garçom. Já estamos a caminho!'); end if;
  update mesas set chamado_tipo = 'garcom', chamado_em = now() where id = m.id;
  perform _registrar_falha('chamargarcom_' || m.id::text, 600);
  perform _auditar_publico('Garçom chamado pelo cliente na mesa', 'Mesa ' || m.numero, null);
  return jsonb_build_object('ok', true, 'message', 'Garçom chamado! Já estamos a caminho.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_confirmar_recebimento_pedido(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_criar_pedido_cardapio(p jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$ select _criar_pedido_publico(p, null) $function$;

CREATE OR REPLACE FUNCTION public.api_criar_pedido_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_q jsonb := _mesa_qr(p->>'mesa', p->>'codigo');
begin
  if v_q->>'ok' <> 'true' then return v_q; end if;
  return _criar_pedido_publico(p, (v_q->>'mesaId')::uuid);
end $function$;

CREATE OR REPLACE FUNCTION public.api_criar_usuario(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
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
  if v_nivel not in ('Admin','Operador','Garçom','Cozinha','Entregador','Desenvolvedor') then return _falha('Nível de acesso inválido.'); end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_detectar_novos_pedidos(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nivel nivel_acesso := auth_nivel(); v_eu uuid := auth.uid(); v_ids jsonb; v_rec jsonb; v_ent jsonb; v_pro jsonb;
begin
  if v_nivel is null then return _negado(); end if;
  if v_nivel = 'Entregador' then
    select coalesce(jsonb_agg(v.id::text), '[]'::jsonb) into v_ent from (select * from vendas order by data_hora desc limit 300) v
     where v.status = 'Confirmada' and v.tipo = 'Entrega' and v.entregador_id = v_eu and v.status_pedido::text not in ('Entregue', 'Suspenso');
    return jsonb_build_object('ok', true, 'ids', '[]'::jsonb, 'recebidos', '[]'::jsonb, 'total', 0, 'entregas', v_ent, 'prontas', '[]'::jsonb);
  elsif v_nivel = 'Garçom' then
    select coalesce(jsonb_agg(v.id::text), '[]'::jsonb) into v_pro from (select * from vendas order by data_hora desc limit 300) v
     where v.status = 'Confirmada' and v.status_pedido = 'Pronta' and v.mesa_id in (select id from mesas where garcom_responsavel_id = v_eu);
    return jsonb_build_object('ok', true, 'ids', '[]'::jsonb, 'recebidos', '[]'::jsonb, 'total', 0, 'entregas', '[]'::jsonb, 'prontas', v_pro);
  end if;
  select coalesce(jsonb_agg(v.id::text) filter (where v.status_pedido = 'Recebido' or (v.status_pedido = 'Em preparo' and v.inicio_preparo_em is null)), '[]'::jsonb),
         coalesce(jsonb_agg(v.id::text) filter (where v.status_pedido = 'Recebido'), '[]'::jsonb)
    into v_ids, v_rec
    from (select * from vendas order by data_hora desc limit 300) v where v.status = 'Confirmada';
  return jsonb_build_object('ok', true, 'ids', v_ids, 'recebidos', v_rec, 'total', jsonb_array_length(v_ids));
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_adicional(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id'); v_nome text := btrim(coalesce(p->>'nome', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from adicionais where id = v_id) then return _falha('Adicional não encontrado.'); end if;
  if _versao_conflita(p, 'adicionais', v_id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
  update adicionais set nome = case when v_nome = '' then nome else v_nome end, preco = _num(p->>'preco') where id = v_id;
  if p ? 'ativo' then update adicionais set ativo = (coalesce(p->>'ativo','') <> 'false') where id = v_id; end if;
  if p ? 'ingredienteId' then update adicionais set ingrediente_id = _uuid(p->>'ingredienteId') where id = v_id; end if;
  if p ? 'quantidadeDesconto' then update adicionais set quantidade_descontar = coalesce(nullif(_num(p->>'quantidadeDesconto'), 0), 1) where id = v_id; end if;
  perform _auditar('Adicional editado', v_nome);
  return jsonb_build_object('ok', true, 'message', 'Adicional atualizado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_categoria(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id'); v_nome text := btrim(coalesce(p->>'novoNome', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from categorias where id = v_id) then return _falha('Categoria não encontrada.'); end if;
  if _versao_conflita(p, 'categorias', v_id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
  if v_nome <> '' then update categorias set nome = v_nome where id = v_id; end if;
  if p ? 'novoAtivo' then update categorias set ativa = (coalesce(p->>'novoAtivo','') <> 'false') where id = v_id; end if;
  if p ? 'novaOrdem' and p->>'novaOrdem' is not null then update categorias set ordem = _num(p->>'novaOrdem')::int where id = v_id; end if;
  perform _auditar('Categoria atualizada', coalesce(nullif(v_nome, ''), v_id::text));
  return jsonb_build_object('ok', true, 'message', 'Categoria atualizada.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_combo(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id'); v_nome text := btrim(coalesce(p->>'nome', '')); v_det text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from combos where id = v_id) then return _falha('Combo não encontrado.'); end if;
  if _versao_conflita(p, 'combos', v_id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_cupom(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record; v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_id is null or not exists (select 1 from cupons where id = v_id) then return _falha('Cupom não encontrado.'); end if;
  if _versao_conflita(p, 'cupons', v_id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
  select * into v from _cupom_validar(p, v_id);
  if v.erro is not null then return _falha(v.erro); end if;
  update cupons set codigo = (v.c).codigo, nome = (v.c).nome, tipo = (v.c).tipo, valor = (v.c).valor, frete_gratis = (v.c).frete_gratis,
         data_inicio = (v.c).data_inicio, data_fim = (v.c).data_fim, hora_inicio = (v.c).hora_inicio, hora_fim = (v.c).hora_fim,
         limite_total = (v.c).limite_total, limite_por_cliente = (v.c).limite_por_cliente, valor_minimo = (v.c).valor_minimo, ativa = (v.c).ativa, acumula = (v.c).acumula
   where id = v_id;
  perform _auditar('Cupom alterado', (v.c).codigo, (v.c).nome);
  return jsonb_build_object('ok', true, 'message', 'Cupom atualizado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_despesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d despesas%rowtype; v_desc text := btrim(coalesce(p->>'descricao', '')); v_valor numeric := round(_num(p->>'valor'), 2);
        v_cat text; v_venc date; v_venc_txt text := btrim(coalesce(p->>'vencimento', ''));
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_desc = '' then return _falha('Informe a descrição da despesa.'); end if;
  if v_valor <= 0 then return _falha('Informe um valor maior que zero.'); end if;
  if v_valor > 9999999 then return _falha('Valor alto demais.'); end if;
  select * into d from despesas where id = _uuid(p->>'id') for update;
  if not found then return _falha('Despesa não encontrada.'); end if;
  if _versao_conflita(p, 'despesas', d.id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_despesa_recorrente(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a despesas_recorrentes%rowtype; v_desc text; v_valor numeric; v_dia numeric; v_per text; v_ini text; v_ter text; v_erro text; v_cat text; v_ativa boolean;
        v_mudou text[] := '{}'; v_n int;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into a from despesas_recorrentes where id = _uuid(p->>'id') for update;
  if not found then return _falha('Despesa mensal não encontrada.'); end if;
  if _versao_conflita(p, 'despesas_recorrentes', a.id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_forma_pagamento(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  f formas_pagamento%rowtype; v_id uuid := _uuid(p->>'id');
  v_pct numeric; v_fixa numeric; v_prazo numeric; v_erro text; v_novo text; v_mudou text := '';
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into f from formas_pagamento where id = v_id;
  if not found then return _falha('Forma de pagamento não encontrada.'); end if;
  if _versao_conflita(p, 'formas_pagamento', v_id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_ingrediente(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_ordem_cardapio_combo(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from combos where id = v_id) then return _falha('Combo não encontrado.'); end if;
  update combos set ordem_cardapio = _num(p->>'ordem')::int where id = v_id;
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_ordem_cardapio_produto(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from produtos where id = v_id) then return _falha('Produto não encontrado.'); end if;
  update produtos set ordem_cardapio = _num(p->>'ordem')::int where id = v_id;
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_produto(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pr produtos%rowtype; v_id uuid := _uuid(p->>'id'); v_nome text := btrim(coalesce(p->>'nome', '')); v_proprio uuid; v_det text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into pr from produtos where id = v_id;
  if not found then return _falha('Produto não encontrado.'); end if;
  if _versao_conflita(p, 'produtos', v_id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_status_feedback(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_st text := coalesce(nullif(btrim(p->>'novoStatus'), ''), 'Novo');
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if v_st <> all (array['Novo','Visto','Respondido']) then return _falha('Status de feedback inválido.'); end if;
  update feedbacks set status = v_st where id = _uuid(p->>'id');
  if not found then return _falha('Feedback não encontrado.'); end if;
  perform _auditar('Feedback atualizado', 'Status: ' || v_st);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_status_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_usuario(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
declare u usuarios%rowtype; v_alvo text := coalesce(p->>'loginAlvo', ''); v_aut text; v_erro text;
        v_sera_admin boolean; v_sera_ativo boolean; v_contato boolean := false; v_nome text; v_tel text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if p ? 'nome' and length(coalesce(p->>'nome', '')) > 60 then return _falha('O nome pode ter no máximo 60 caracteres.'); end if;
  if p ? 'telefone' and length(coalesce(p->>'telefone', '')) > 25 then return _falha('O telefone pode ter no máximo 25 caracteres.'); end if;
  if p ? 'novoNivel' and coalesce(p->>'novoNivel', '') not in ('Admin','Operador','Garçom','Cozinha','Entregador','Desenvolvedor') then return _falha('Nível de acesso inválido.'); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  select * into u from usuarios where lower(login) = lower(v_alvo);
  if not found then return _falha('Usuário não encontrado.'); end if;
  if _versao_conflita(p, 'usuarios', u.id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
  v_sera_admin := case when p ? 'novoNivel' then p->>'novoNivel' = 'Admin' else u.nivel = 'Admin' end;
  v_sera_ativo := case when p ? 'novoAtivo' then coalesce((p->>'novoAtivo')::boolean, false) else u.ativo end;
  if u.id = auth.uid() and p ? 'novoAtivo' and not v_sera_ativo then
    return _falha('Você não pode desativar o seu próprio acesso.');
  end if;
  if u.id = auth.uid() and p ? 'novoNivel' and p->>'novoNivel' <> u.nivel::text then
    return _falha('Você não pode alterar o seu próprio perfil.');
  end if;
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_venda(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v vendas%rowtype; v_aut text; v_motivo text := btrim(coalesce(p->>'motivo', '')); v_itens jsonb := p->'itens'; v_login text;
  it record; v_qtd numeric; v_v numeric; v_c numeric; v_nome text; v_extra numeric; v_n_ad int; v_n_ok int; v_exige boolean; v_prod uuid; v_comb uuid;
  v_ads jsonb; v_soma numeric := 0; v_custo numeric := 0; v_total numeric; v_novos jsonb := '[]'::jsonb; v_npag int; v_antes numeric; v_st text; v_antes_aceite boolean; v_aviso text := '';
begin
  if not tem_nivel('Admin', 'Operador') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  if v_motivo = '' then return _falha('Informe o motivo da edição.'); end if;
  if jsonb_typeof(v_itens) <> 'array' or jsonb_array_length(v_itens) = 0 then return _falha('A venda precisa ter ao menos um item.'); end if;
  if jsonb_array_length(v_itens) > 60 then return _falha('Itens demais na venda.'); end if;
  select * into v from vendas where id = _uuid(p->>'id') for update;
  if not found then return _falha('Venda não encontrada.'); end if;
  if _versao_conflita(p, 'vendas', v.id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
  if v.status <> 'Confirmada' then return _falha('Só é possível editar vendas confirmadas.'); end if;
  if v.fechamento_entrega_id is not null then return _falha('Esta entrega já está em um fechamento — não pode mais ser alterada.'); end if;
  v_st := v.status_pedido::text;
  if v_st is not null and v_st not in ('Em preparo', 'Recebido') then return _falha('Este pedido já está "' || v_st || '" — não é mais possível editar os itens.'); end if;
  v_antes_aceite := v_st = 'Recebido';
  select count(*) into v_npag from pagamentos_venda where venda_id = v.id;
  if v_npag > 1 then return _falha('Venda com pagamento dividido não pode ser editada. Cancele e lance novamente.'); end if;
  v_exige := not (auth_nivel() = 'Admin' and v.origem::text <> 'Cardápio');

  for it in select value as e from jsonb_array_elements(v_itens) loop
    v_nome := coalesce(nullif(it.e->>'descricao', ''), 'item');
    v_qtd := _num(it.e->>'quantidade'); v_v := _num(it.e->>'valorUnitario', -1); v_c := _num(it.e->>'custoUnitario');
    v_prod := _uuid(it.e->>'produtoId'); v_comb := _uuid(it.e->>'comboId');
    if not (v_qtd > 0) or v_qtd > 200 or v_qtd <> floor(v_qtd) then return _falha('Quantidade inválida em "' || v_nome || '".'); end if;
    if v_v < 0 then return _falha('Preço inválido em "' || v_nome || '".'); end if;
    if v_c < 0 then return _falha('Custo inválido em "' || v_nome || '".'); end if;
    -- adicionais: os enviados; se não vierem, mantém os do item antigo de mesma descrição (como na planilha)
    v_ads := case when jsonb_typeof(it.e->'adicionaisIds') = 'array' then it.e->'adicionaisIds'
                  else coalesce((select to_jsonb(iv.adicionais_ids) from itens_venda iv where iv.venda_id = v.id and iv.descricao = it.e->>'descricao' limit 1), '[]'::jsonb) end;
    if v_exige and not exists (select 1 from itens_venda iv where iv.venda_id = v.id and iv.descricao = it.e->>'descricao' and abs(iv.valor_unitario - v_v) <= 0.001 and abs(iv.custo_unitario - v_c) <= 0.011
                                 and coalesce(iv.produto_id, iv.combo_id) is not distinct from coalesce(v_prod, v_comb)) then
      -- item novo ou com preço mudado: precisa conferir com o cadastro
      if (v_prod is null and v_comb is null) or (v_prod is not null and v_comb is not null) then return _falha('"' || v_nome || '" não é um item cadastrado de forma válida.'); end if;
      select count(*), coalesce(sum(a.preco) filter (where a.ativo), 0), count(*) filter (where a.ativo) into v_n_ad, v_extra, v_n_ok
        from jsonb_array_elements_text(v_ads) x left join adicionais a on a.id = _uuid(x);
      if v_n_ad <> v_n_ok then return _falha('O adicional selecionado para "' || v_nome || '" não está disponível.'); end if;
      if v_prod is not null then
        if not exists (select 1 from produto_precos pp where pp.produto_id = v_prod and abs(pp.preco + v_extra - v_v) <= 0.011) then
          perform _auditar('Preço divergente bloqueado', v_nome || ' enviado a R$ ' || _dinheiro(v_v) || ' (edição de venda)');
          return _falha('O preço de "' || v_nome || '" não confere com o cadastro.');
        end if;
        if not exists (select 1 from produto_precos pp where pp.produto_id = v_prod and abs(pp.preco + v_extra - v_v) <= 0.011 and abs(pp.custo - v_c) <= 0.011) then
          perform _auditar('Custo divergente bloqueado', v_nome || ' enviado com custo R$ ' || _dinheiro(v_c) || ' (edição de venda)');
          return _falha('O custo de "' || v_nome || '" não confere com o cadastro.');
        end if;
      else
        if not exists (select 1 from combo_precos cp where cp.combo_id = v_comb and abs(cp.preco + v_extra - v_v) <= 0.011) then
          perform _auditar('Preço divergente bloqueado', v_nome || ' enviado a R$ ' || _dinheiro(v_v) || ' (edição de venda)');
          return _falha('O preço de "' || v_nome || '" não confere com o cadastro.');
        end if;
        if not exists (select 1 from combo_precos cp where cp.combo_id = v_comb and abs(cp.preco + v_extra - v_v) <= 0.011 and abs(cp.custo - v_c) <= 0.011) then
          perform _auditar('Custo divergente bloqueado', v_nome || ' enviado com custo R$ ' || _dinheiro(v_c) || ' (edição de venda)');
          return _falha('O custo de "' || v_nome || '" não confere com o cadastro.');
        end if;
      end if;
    end if;
    v_novos := v_novos || jsonb_build_array(jsonb_build_object('produtoId', v_prod, 'comboId', v_comb, 'descricao', v_nome, 'quantidade', v_qtd,
                                                                 'valorUnitario', v_v, 'custoUnitario', v_c, 'adicionaisIds', v_ads));
    v_soma := v_soma + round(v_qtd * v_v, 2); v_custo := v_custo + v_qtd * v_c;
  end loop;
  v_soma := round(v_soma, 2); v_custo := round(v_custo, 2);
  if v.valor_desconto >= v_soma then return _falha('Com o desconto já aplicado, o novo total ficaria zero ou negativo.'); end if;
  v_total := round(v_soma - v.valor_desconto + v.taxa_entrega, 2);
  v_antes := v.valor_total;

  perform _ajustar_estoque(_itens_da_venda(v.id), -1, v.id);
  delete from itens_venda where venda_id = v.id;
  insert into itens_venda (venda_id, produto_id, combo_id, descricao, quantidade, valor_unitario, custo_unitario, valor_total_item, adicionais_ids)
  select v.id, _uuid(e->>'produtoId'), _uuid(e->>'comboId'), e->>'descricao', _num(e->>'quantidade', 1)::int, _num(e->>'valorUnitario'), _num(e->>'custoUnitario'),
         round(_num(e->>'quantidade', 1) * _num(e->>'valorUnitario'), 2),
         coalesce((select array_agg(_uuid(x)) filter (where _uuid(x) is not null) from jsonb_array_elements_text(e->'adicionaisIds') x), '{}')
  from jsonb_array_elements(v_novos) e;
  update vendas set valor_total = v_total, custo_total = v_custo, valor_original = v_soma where id = v.id;
  if v_npag = 1 then
    update pagamentos_venda pv set valor = v_total,
      taxa_aplicada = coalesce((select round(v_total * f.taxa_percentual / 100 + f.taxa_fixa, 2) from formas_pagamento f where lower(f.nome) = lower(pv.forma_pagamento) limit 1), 0)
    where pv.venda_id = v.id;
  end if;
  perform _ajustar_estoque(v_novos, 1, v.id);
  select login into v_login from usuarios where id = auth.uid();
  perform _auditar('Venda editada', case when v_antes_aceite then '[edição antes do aceite] ' else '' end || 'Autorizado por ' || coalesce(nullif(current_setting('app.autorizador', true), ''), v_login)
    || ' | Motivo: ' || v_motivo || ' | Total: R$ ' || _dinheiro(v_antes) || ' → R$ ' || _dinheiro(v_total), v.telefone_cliente);
  if v_antes_aceite and v.origem::text = 'Cardápio' and v.status_pagamento::text = 'Pago' and abs(v_total - v_antes) >= 0.01 then
    v_aviso := ' ATENÇÃO: o valor mudou (R$ ' || _dinheiro(v_antes) || ' → R$ ' || _dinheiro(v_total) || ') e este pedido já consta como pago — acerte a diferença com o cliente.';
  end if;
  return jsonb_build_object('ok', true, 'message', 'Venda atualizada. Novo total: R$ ' || _dinheiro(v_total) || '.' || v_aviso, 'aviso', v_aviso <> '');
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_visibilidade_cardapio_combo(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from combos where id = v_id) then return _falha('Combo não encontrado.'); end if;
  if p ? 'ativo' then update combos set ativo = (coalesce(p->>'ativo','') <> 'false') where id = v_id; end if;
  if p ? 'destaque' then update combos set destaque = coalesce((p->>'destaque')::boolean, false) where id = v_id; end if;
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_editar_visibilidade_cardapio_produto(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if not exists (select 1 from produtos where id = v_id) then return _falha('Produto não encontrado.'); end if;
  if p ? 'ativo' then update produtos set ativo = (coalesce(p->>'ativo','') <> 'false') where id = v_id; end if;
  if p ? 'destaque' then update produtos set destaque = coalesce((p->>'destaque')::boolean, false) where id = v_id; end if;
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_encerrar_sessao_remota(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_excluir_adicional(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  delete from adicionais where id = v_id;   -- os vínculos com produtos saem junto
  perform _auditar('Adicional excluído', v_id::text);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_excluir_categoria(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_excluir_cliente(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id'); v_aut text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;
  delete from clientes where id = v_id;   -- vendas antigas ficam com o nome e telefone gravados
  perform _auditar('Cliente excluído', v_id::text);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_excluir_combo(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  delete from combos where id = v_id;   -- preços e itens saem junto
  perform _auditar('Combo excluído', v_id::text);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_excluir_ingrediente(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_excluir_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m mesas%rowtype; v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into m from mesas where id = v_id;
  if found and m.status = 'Ocupada' then return _falha('Não é possível excluir uma mesa ocupada.'); end if;
  delete from mesas where id = v_id;
  perform _auditar('Mesa excluída', coalesce('Mesa ' || m.numero, v_id::text));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_excluir_produto(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if exists (select 1 from combo_itens where produto_id = v_id) then
    return _falha('Este produto faz parte de um ou mais combos. Tire-o dos combos antes de excluir (ou deixe-o inativo).');
  end if;
  delete from produtos where id = v_id;   -- preços, receita e adicionais saem junto
  perform _auditar('Produto excluído', v_id::text);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_excluir_usuario(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_fechar_caixa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  s caixa_sessoes%rowtype; v_login text; v_chave text; v_seg int; v_contado numeric; v_fim timestamptz := now();
  v_mesas text[]; v_pend text[]; v_nrec text[]; v_msgs text[] := '{}';
  v_total numeric; v_pendente numeric; v_qv int; v_desp numeric; v_qd int; v_sang numeric; v_qs int;
  v_forma jsonb; v_dinheiro numeric; v_saldo numeric; v_dif numeric; v_nomes_dinheiro text[];
  v_feitos jsonb := '[]'::jsonb; v_falhas jsonb := '[]'::jsonb; ed record; c record; fid uuid; v_req_auto text;
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

  -- fechamento automático das entregas concluídas na sessão (um fechamento por entregador e por dia)
  for ed in
    select distinct v.entregador_id, u.login, (v.concluida_em at time zone 'America/Sao_Paulo')::date as dia
      from vendas v join usuarios u on u.id = v.entregador_id
     where v.status = 'Confirmada' and v.tipo = 'Entrega' and v.status_pedido::text = 'Entregue'
       and v.entregador_id is not null and v.fechamento_entrega_id is null
       and v.concluida_em >= s.abertura and v.concluida_em <= v_fim
     order by 3, 2
  loop
    begin
      fid := null;
      perform pg_advisory_xact_lock(hashtext(ed.entregador_id::text || ed.dia::text));
      select * into c from _calc_fechamento_entrega(ed.login, ed.dia);
      if c.qtd > 0 then
        v_req_auto := 'auto-' || s.id::text || '-' || lower(ed.login) || '-' || ed.dia::text;
        insert into fechamentos_entrega (data_ref, entregador_id, qtd_entregas, total_taxas, ajuda_diaria, total_devido, valor_pago, diferenca, fechado_por, observacao, requisicao_id)
        values (ed.dia, ed.entregador_id, c.qtd, c.total_taxas, c.ajuda, c.total, c.total, 0, auth.uid(), 'Fechamento automático ao fechar o caixa', v_req_auto)
        on conflict (requisicao_id) do nothing returning id into fid;
        if fid is not null then
          insert into entregas_fechadas (fechamento_id, venda_id, data_ref, entregador_id, taxa)
          select fid, id, ed.dia, ed.entregador_id, taxa_entrega from vendas where id = any(c.ids);
          update vendas set fechamento_entrega_id = fid where id = any(c.ids);
          perform _auditar('Fechamento de entregas (automático)', ed.login || ' | ' || ed.dia || ' | ' || c.qtd || ' entregas | devido e pago R$ ' || _dinheiro(c.total));
          v_feitos := v_feitos || to_jsonb(ed.login || ' (' || to_char(ed.dia, 'DD/MM/YYYY') || '): R$ ' || _dinheiro(c.total));
        end if;
      end if;
    exception when others then
      v_falhas := v_falhas || to_jsonb(ed.login || ' (' || to_char(ed.dia, 'DD/MM/YYYY') || '): ' || sqlerrm);
    end;
  end loop;
  if jsonb_array_length(v_falhas) > 0 then
    perform _auditar('Falha no fechamento automático de entregas', v_falhas::text);
  end if;

  return jsonb_build_object('ok', true, 'entregasAuto', jsonb_build_object('feitos', v_feitos, 'falhas', v_falhas),
    'relatorio', jsonb_build_object(
      'abertura', to_char(s.abertura at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
      'fechamento', to_char(v_fim at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
      'fundoCaixa', s.fundo_caixa, 'totalVendas', v_total, 'totalVendasDinheiro', v_dinheiro, 'porForma', v_forma,
      'totalPendente', v_pendente, 'totalDespesas', v_desp, 'totalSangrias', v_sang, 'saldoFinal', v_saldo,
      'valorContado', v_contado, 'diferenca', v_dif, 'quantidadeVendas', v_qv, 'quantidadeDespesas', v_qd, 'quantidadeSangrias', v_qs,
      'reconciliadasNaSessao', jsonb_build_object('quantidade', 0, 'valor', 0), 'pendentesContingencia', 0));
end $function$;

CREATE OR REPLACE FUNCTION public.api_fechar_conta_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    delete from pagamentos_venda where venda_id = v.id and forma_pagamento = 'A Receber (Mesa)';
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_fechar_periodo_entregador(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_garantir_despesas_do_mes(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_comp text := _competencia_atual(); v_n int := 0;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if coalesce((select valor #>> '{}' from sistema where chave = 'ULTIMA_GERACAO_DESPESAS'), '') <> v_comp then
    v_n := _gerar_despesas_recorrentes(v_comp);
    perform _cfg_gravar('ULTIMA_GERACAO_DESPESAS', to_jsonb(v_comp));
  end if;
  return jsonb_build_object('ok', true, 'geradas', v_n);
end $function$;

CREATE OR REPLACE FUNCTION public.api_gerar_despesas_mes(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_n int; v_comp text := _competencia_atual();
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  v_n := _gerar_despesas_recorrentes(v_comp);
  perform _cfg_gravar('ULTIMA_GERACAO_DESPESAS', to_jsonb(v_comp));
  return jsonb_build_object('ok', true, 'message', case when v_n > 0 then v_n || ' conta(s) gerada(s) para este mês.' else 'Nenhuma conta nova: este mês já está gerado.' end);
end $function$;

CREATE OR REPLACE FUNCTION public.api_gerar_novo_codigo_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m mesas;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into m from mesas where id = _uuid(p->>'mesaId');
  if not found then return _falha('Mesa não encontrada.'); end if;
  insert into mesas_codigos (mesa_id, codigo) values (m.id, substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
    on conflict (mesa_id) do update set codigo = excluded.codigo, gerado_em = now();
  perform _auditar('Código QR da mesa renovado', 'Mesa ' || m.numero || ' — o QR antigo deixou de funcionar');
  return jsonb_build_object('ok', true, 'message', 'Novo código gerado. Imprima o QR da mesa ' || m.numero || ' de novo.', 'mesas', _lista_qr_mesas());
end $function$;

CREATE OR REPLACE FUNCTION public.api_get_mesa_publica(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_q jsonb := _mesa_qr(p->>'mesa', p->>'codigo'); m mesas; v_ped jsonb; v_total numeric;
begin
  if v_q->>'ok' <> 'true' then return v_q; end if;
  select * into m from mesas where id = (v_q->>'mesaId')::uuid;
  select coalesce(round(sum(valor_total), 2), 0) into v_total from vendas where mesa_id = m.id and status = 'Confirmada' and status_pagamento = 'A Receber';
  select coalesce(jsonb_agg(t.j order by t.dh), '[]'::jsonb) into v_ped from (
    select v.data_hora as dh, jsonb_build_object('id', v.id, 'numero', v.numero_pedido,
      'hora', to_char(v.data_hora at time zone 'America/Sao_Paulo', 'HH24:MI'), 'valor', v.valor_total, 'cancelado', v.status = 'Cancelada',
      'status', case when v.status = 'Cancelada' then 'Cancelado' else case v.status_pedido::text when 'Recebido' then 'Aguardando confirmação' when 'Em preparo' then 'Em preparo'
                      when 'Pronta' then 'Pronto' when 'Servida' then 'Servido' when 'Suspenso' then 'Em preparo' else coalesce(v.status_pedido::text, '') end end,
      'podeCancelar', (v.status = 'Confirmada' and v.origem = 'Cardápio' and v.status_pedido = 'Recebido'),
      'itens', (select coalesce(jsonb_agg(jsonb_build_object('quantidade', i.quantidade, 'descricao', i.descricao) order by i.ctid), '[]'::jsonb) from itens_venda i where i.venda_id = v.id)) as j
    from vendas v
    where v.mesa_id = m.id and ((v.status = 'Confirmada' and v.status_pagamento = 'A Receber') or (v.status = 'Cancelada' and v.origem = 'Cardápio' and v.data_hora >= now() - interval '3 hours'))
    order by v.data_hora desc limit 12) t;
  return jsonb_build_object('ok', true, 'mesa', jsonb_build_object('numero', m.numero, 'status', m.status::text, 'chamando', m.chamado_em is not null),
    'pedidos', v_ped, 'total', v_total, 'caixaAberto', exists (select 1 from caixa_sessoes where status = 'Aberto'));
end $function$;

CREATE OR REPLACE FUNCTION public.api_get_qr_mesas(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  insert into mesas_codigos (mesa_id, codigo) select m.id, substr(replace(gen_random_uuid()::text, '-', ''), 1, 12) from mesas m
    where not exists (select 1 from mesas_codigos c where c.mesa_id = m.id);
  return jsonb_build_object('ok', true, 'mesas', _lista_qr_mesas());
end $function$;

CREATE OR REPLACE FUNCTION public.api_get_status_pedido_publico(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_alvo text := lower(btrim(coalesce(p->>'codigo', ''))); v vendas%rowtype; v_ip text := _ip_cliente(); v_itens jsonb; v_resta int; v_cancelavel boolean;
begin
  if v_alvo !~ '^[0-9a-f-]{8,36}$' then return _falha('Código do pedido inválido.'); end if;
  if _excedeu('statuspub_ip_' || v_ip, 40) or _excedeu('statuspub_falhas', 200) then
    return jsonb_build_object('ok', false, 'message', 'Muitas consultas seguidas. Aguarde alguns minutos.', 'limite', true);
  end if;
  select * into v from vendas where right(id::text, 8) = right(v_alvo, 8) and right(id::text, length(v_alvo)) = v_alvo order by data_hora desc limit 1;
  if not found then
    perform _registrar_falha('statuspub_ip_' || v_ip, 600); perform _registrar_falha('statuspub_falhas', 600);
    return _falha('Pedido não encontrado. Confira o código.');
  end if;
  select coalesce(jsonb_agg(i.quantidade || 'x ' || coalesce(i.descricao, '') order by i.ctid), '[]'::jsonb) into v_itens from itens_venda i where i.venda_id = v.id;
  v_cancelavel := v.origem = 'Cardápio' and v.mesa_id is null and v.status = 'Confirmada' and v.status_pedido = 'Recebido' and v.status_pagamento = 'A Receber';
  v_resta := greatest(0, ceil(180 - extract(epoch from (now() - v.data_hora)))::int);
  return jsonb_build_object('ok', true, 'status', v.status::text, 'statusPedido', v.status_pedido::text, 'tipoEntrega', v.tipo::text,
    'motivoCancelamento', coalesce(v.motivo_cancelamento, ''), 'clienteNome', split_part(btrim(coalesce(v.cliente_nome, '')), ' ', 1),
    'itens', v_itens, 'valorTotal', v.valor_total, 'data', to_char(v.data_hora at time zone 'America/Sao_Paulo', 'DD/MM/YYYY HH24:MI'),
    'statusPagamento', v.status_pagamento::text, 'numero', v.numero_pedido,
    'podeCancelar', (v_cancelavel and v_resta > 0), 'segundosParaCancelar', case when v_cancelavel then v_resta else 0 end);
end $function$;

CREATE OR REPLACE FUNCTION public.api_indicar_novo_cliente(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ti text := btrim(coalesce(p->>'telIndicador', '')); v_ni text := btrim(coalesce(p->>'nomeIndicador', ''));
        v_nome text := btrim(coalesce(p->>'nome', '')); v_tel text := btrim(coalesce(p->>'telefone', ''));
        v_r jsonb; v_ja indicacoes%rowtype;
begin
  if not tem_nivel('Admin','Operador','Garçom') then return _negado(); end if;
  if v_nome = '' or v_tel = '' then return _falha('Nome e telefone são obrigatórios.'); end if;
  if v_ti = '' or v_ni = '' then return _falha('Preencha todos os campos.'); end if;
  if _so_digitos(v_ti) = _so_digitos(v_tel) then return _falha('Quem indicou e quem foi indicado não podem ser a mesma pessoa.'); end if;
  v_r := api_salvar_cliente((p - 'id') || jsonb_build_object('nome', v_nome, 'telefone', v_tel));
  if coalesce(v_r->>'ok', '') <> 'true' then return v_r; end if;
  select * into v_ja from indicacoes where _so_digitos(telefone_indicado) = _so_digitos(v_tel) limit 1;
  if v_ja.id is not null then
    return jsonb_build_object('ok', true, 'message', 'Cliente cadastrado, mas: ' || v_nome || ' já foi indicado antes (por ' || coalesce(v_ja.nome_indicador, '') || ').');
  end if;
  insert into indicacoes (indicador_id, indicado_id, nome_indicador, telefone_indicador, nome_indicado, telefone_indicado, status, observacoes)
  values (_upsert_cliente(v_ti, v_ni), _upsert_cliente(v_tel, v_nome), v_ni, v_ti, v_nome, v_tel, 'Pendente', '');
  perform _auditar('Indicação registrada', v_ni || ' indicou ' || v_nome, v_tel);
  return jsonb_build_object('ok', true, 'message', 'Cliente cadastrado e indicação registrada! ' || v_ni || ' ganhará 1 batata pequena na próxima compra.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_iniciar_preparo_pedido(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t record; v vendas;
begin
  if not tem_nivel('Admin','Operador','Cozinha') then return _negado(); end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  if v.status_pedido::text not in ('Recebido','Em preparo') then return _conflito('Este pedido já está "' || coalesce(v.status_pedido::text,'') || '". A tela foi atualizada.'); end if;
  if v.status_pedido::text = 'Recebido' then perform _auditar('Pedido aceito', '#' || v.numero_pedido || ' — aceito pela cozinha', v.telefone_cliente); end if;
  update vendas set status_pedido = 'Em preparo', inicio_preparo_em = coalesce(inicio_preparo_em, now()) where id = v.id;
  perform _auditar('Preparo iniciado', '#' || v.numero_pedido);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_iniciar_venda(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if v_caixa is null then return _falha(case when v_nivel = 'Garçom' then 'O caixa está fechado — peça ao caixa para abrir.' else 'Abra o caixa antes de registrar uma venda.' end); end if;

  -- garçom: só mesa/entrega/retirada, sem desconto, sem receber pagamento; vale no servidor, não só na tela
  if v_nivel = 'Garçom' then
    if v_tipo_in not in ('Mesa','Entrega','Retirada') then return _falha('O garçom só lança pedidos de mesa, entrega ou retirada.'); end if;
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
        if not exists (select 1 from produto_precos pp where pp.produto_id = _uuid(it.e->>'produtoId') and abs(pp.preco + v_extra - v_v) <= 0.011 and abs(pp.custo - v_c) <= 0.011) then
          perform _auditar('Custo divergente bloqueado', v_nome_item || ' enviado com custo R$ ' || _dinheiro(v_c));
          return _falha('O custo de "' || v_nome_item || '" não confere com o cadastro.');
        end if;
      else
        if not exists (select 1 from combo_precos cp where cp.combo_id = _uuid(it.e->>'comboId') and abs(cp.preco + v_extra - v_v) <= 0.011) then
          perform _auditar('Preço divergente bloqueado', v_nome_item || ' enviado a R$ ' || _dinheiro(v_v));
          return _falha('O preço de "' || v_nome_item || '" não confere com o cadastro.');
        end if;
        if not exists (select 1 from combo_precos cp where cp.combo_id = _uuid(it.e->>'comboId') and abs(cp.preco + v_extra - v_v) <= 0.011 and abs(cp.custo - v_c) <= 0.011) then
          perform _auditar('Custo divergente bloqueado', v_nome_item || ' enviado com custo R$ ' || _dinheiro(v_c));
          return _falha('O custo de "' || v_nome_item || '" não confere com o cadastro.');
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_listar_sessoes(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_pagar_despesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_pedir_conta_mesa(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_q jsonb := _mesa_qr(p->>'mesa', p->>'codigo'); m mesas;
begin
  if v_q->>'ok' <> 'true' then return v_q; end if;
  select * into m from mesas where id = (v_q->>'mesaId')::uuid for update;
  if m.status::text = 'Aguardando fechamento' then return jsonb_build_object('ok', true, 'message', 'A conta já foi pedida. Já estamos a caminho!'); end if;
  if m.status::text <> 'Ocupada' then return _falha('Faça um pedido antes de pedir a conta.'); end if;
  if _excedeu('pedirconta_' || m.id::text, 3) then return _falha('Já recebemos seu pedido de conta. Aguarde um instante.'); end if;
  update mesas set status = 'Aguardando fechamento' where id = m.id;
  perform _registrar_falha('pedirconta_' || m.id::text, 600);
  perform _auditar_publico('Conta pedida pelo cliente na mesa', 'Mesa ' || m.numero, null);
  return jsonb_build_object('ok', true, 'message', 'Conta solicitada! Em instantes alguém vem até a sua mesa.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_preview_fechamento_entrega(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare c record;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if btrim(coalesce(p->>'entregador','')) = '' or coalesce(p->>'dataRef','') !~ '^\d{4}-\d{2}-\d{2}$' then return _falha('Informe o entregador e a data.'); end if;
  select * into c from _calc_fechamento_entrega(p->>'entregador', (p->>'dataRef')::date);
  return jsonb_build_object('ok', true, 'qtd', c.qtd, 'totalTaxas', c.total_taxas, 'ajudaDiaria', c.ajuda, 'totalDevido', c.total, 'vendaIds', to_jsonb(coalesce(c.ids, '{}'::uuid[])));
end $function$;

CREATE OR REPLACE FUNCTION public.api_registrar_ajuste_pos_venda(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_registrar_entrada_estoque(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_registrar_inventario_estoque(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_registrar_ocorrencia(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tipo text := btrim(coalesce(p->>'tipo', '')); v_desc text := btrim(coalesce(p->>'descricao', ''));
        v_vid uuid := _uuid(p->>'vendaId'); ve vendas%rowtype; v_niv text := auth_nivel()::text; v_nivel_real text; v_login text := _login_de(auth.uid());
        v_ok boolean := false; v_setor text; v_id uuid; v_num integer;
begin
  if not tem_nivel('Admin','Operador','Garçom','Cozinha','Entregador') then return _negado(); end if;
  if v_tipo <> all (array['Produção','Entrega','Atendimento','Pagamento','Estoque','Outro']) then return _falha('Escolha o tipo da ocorrência.'); end if;
  if char_length(v_desc) < 3 then return _falha('Descreva o que aconteceu.'); end if;
  if char_length(v_desc) > 600 then return _falha('Descrição muito longa (máximo 600 caracteres).'); end if;
  if nullif(btrim(coalesce(p->>'vendaId', '')), '') is not null then
    if v_vid is null then return _falha('Pedido não encontrado.'); end if;
    select * into ve from vendas where id = v_vid;
    if ve.id is null then return _falha('Pedido não encontrado.'); end if;
    v_ok := case v_niv
      when 'Admin' then true when 'Operador' then true
      when 'Entregador' then ve.tipo::text = 'Entrega' and ve.entregador_id = auth.uid()
      when 'Garçom' then ve.mesa_id is not null and ve.registrado_por = auth.uid()
                         and exists (select 1 from mesas m where m.id = ve.mesa_id and m.status::text in ('Ocupada','Aguardando fechamento'))
      when 'Cozinha' then ve.status::text = 'Confirmada' and coalesce(ve.status_pedido::text, '') in ('Recebido','Em preparo','Pronta','Servida','Retirada','Saiu para entrega','Entregue')
      else false end;
    if not v_ok then return _falha('Este pedido não está no seu escopo operacional.'); end if;
  end if;
  select nivel::text into v_nivel_real from usuarios where id = auth.uid();
  v_setor := case v_niv when 'Cozinha' then 'Cozinha' when 'Garçom' then 'Salão' when 'Entregador' then 'Entrega' when 'Operador' then 'Caixa' when 'Admin' then 'Administração' else 'Outro' end;
  insert into ocorrencias (tipo, setor, venda_id, cliente, telefone, registrado_por, descricao, status, historico)
  values (v_tipo, v_setor, ve.id, ve.cliente_nome, ve.telefone_cliente, auth.uid(), v_desc, 'Aberta',
          jsonb_build_array(_agora_br() || ' — ' || coalesce(v_login, '') || ' (' || coalesce(v_nivel_real, v_niv) || '): ocorrência registrada'))
  returning id, numero into v_id, v_num;
  perform _auditar('Ocorrência registrada', '#' || v_num || ' ' || v_tipo
                   || case when ve.id is not null then ' — pedido #' || coalesce(ve.numero_pedido::text, right(ve.id::text, 5)) else '' end
                   || ': ' || left(v_desc, 120));
  return jsonb_build_object('ok', true, 'message', 'Ocorrência #' || v_num || ' registrada.', 'id', v_id);
end $function$;

CREATE OR REPLACE FUNCTION public.api_registrar_perda_estoque(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_rejeitar_pedido(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  return api_cancelar_venda(jsonb_build_object('id', p->>'vendaId', 'motivo', coalesce(nullif(btrim(p->>'motivo'),''), 'Pedido rejeitado'),
    'senhaAdminConfirmacao', p->>'senhaAdminConfirmacao', 'mercadoriaPerdida', 'false'));
end $function$;

CREATE OR REPLACE FUNCTION public.api_resgatar_premio_fidelidade(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tel text := btrim(coalesce(p->>'telefone', '')); v_cli uuid; f fidelidade%rowtype;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if _so_digitos(v_tel) = '' then return _falha('Cliente não encontrado.'); end if;
  select id into v_cli from clientes where _so_digitos(telefone) = _so_digitos(v_tel) limit 1;
  if v_cli is not null then select * into f from fidelidade where cliente_id = v_cli for update; end if;
  if f.id is null then return _falha('Cliente não encontrado.'); end if;
  if f.carimbos < 10 then return _falha('Este cartão ainda não completou 10 marcas.'); end if;
  update fidelidade set carimbos = 0, premios_resgatados = f.premios_resgatados + 1, atualizada_em = now() where id = f.id;
  perform _auditar('Prêmio resgatado (fidelidade)', 'Total de prêmios: ' || (f.premios_resgatados + 1), v_tel);
  return jsonb_build_object('ok', true, 'message', 'Prêmio resgatado — cartão reiniciado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_retomar_pedido(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare t record; v vendas; antes text;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  select * into t from _pedido_trava(p); v := t.v; if t.erro is not null then return t.erro; end if;
  if v.status_pedido::text <> 'Suspenso' then return _conflito('Este pedido não está suspenso.'); end if;
  antes := coalesce(nullif(v.status_antes_suspensao,''), 'Em preparo');
  update vendas set status_pedido = (case when antes in ('Recebido','Pronta') then antes else 'Em preparo' end)::status_pedido, status_antes_suspensao = null where id = v.id;
  perform _auditar('Pedido retomado', '#' || v.numero_pedido || ' → ' || antes, v.telefone_cliente);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_salvar_cliente(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_nome text := btrim(coalesce(p->>'nome', '')); v_tel text := btrim(coalesce(p->>'telefone', ''));
        v_alvo text := nullif(btrim(coalesce(p->>'id', '')), ''); v_nasc date; v_id uuid; v_novo_id uuid := gen_random_uuid();
begin
  if not tem_nivel('Admin','Operador','Garçom') then return _negado(); end if;
  if v_nome = '' or v_tel = '' then return _falha('Nome e telefone são obrigatórios.'); end if;
  if length(v_nome) > 120 then return _falha('Nome muito longo.'); end if;
  if length(v_tel) > 25 then return _falha('Telefone muito longo.'); end if;
  perform pg_advisory_xact_lock(hashtextextended('cliente:' || _so_digitos(v_tel), 0)); -- dois cadastros do mesmo telefone ao mesmo tempo passam um de cada vez
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
  if _versao_conflita(p, 'clientes', v_id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
    update clientes set nome = v_nome, telefone = v_tel, data_nascimento = v_nasc, endereco = coalesce(p->>'endereco', ''), como_conheceu = coalesce(p->>'comoConheceu', '') where id = v_id;
    if p ? 'observacao' then update clientes set observacoes = coalesce(p->>'observacao', '') where id = v_id; end if;
    perform _auditar('Cliente atualizado', v_nome, v_tel);
    return jsonb_build_object('ok', true, 'message', 'Cadastro atualizado.');
  end if;
  insert into clientes (id, nome, telefone, data_nascimento, endereco, como_conheceu, primeiro_contato, observacoes)
  values (v_novo_id, v_nome, v_tel, v_nasc, coalesce(p->>'endereco', ''), coalesce(p->>'comoConheceu', ''), now(), coalesce(p->>'observacao', ''));
  perform _auditar('Cliente cadastrado', v_nome, v_tel);
  return jsonb_build_object('ok', true, 'message', 'Cliente cadastrado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_salvar_config_cardapio(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  perform _cfg_gravar('CardapioKicker', to_jsonb(coalesce(p->>'kicker', '')));
  perform _cfg_gravar('CardapioFrase', to_jsonb(coalesce(p->>'frase', '')));
  if p ? 'tempoEntrega' then perform _cfg_gravar('CardapioTempoEntrega', to_jsonb(coalesce(p->>'tempoEntrega', ''))); end if;
  if p ? 'tempoRetirada' then perform _cfg_gravar('CardapioTempoRetirada', to_jsonb(coalesce(p->>'tempoRetirada', ''))); end if;
  if p ? 'tempoMesa' then perform _cfg_gravar('CardapioTempoMesa', to_jsonb(coalesce(p->>'tempoMesa', ''))); end if;
  perform _auditar('Configuração do Cardápio Digital atualizada');
  return jsonb_build_object('ok', true, 'message', 'Cardápio atualizado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_salvar_config_entrega(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_salvar_config_estoque(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_b boolean := coalesce(p->>'bloquear', '') in ('true', 't');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  perform _cfg_gravar('BLOQUEAR_ESTOQUE_NEGATIVO', to_jsonb(v_b));
  perform _auditar('Regra de estoque alterada', 'Bloquear venda sem estoque: ' || case when v_b then 'Sim' else 'Não' end);
  return jsonb_build_object('ok', true, 'message', 'Regra de estoque salva.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_salvar_config_notificacoes(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_salvar_cupom(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v record;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into v from _cupom_validar(p, null);
  if v.erro is not null then return _falha(v.erro); end if;
  insert into cupons (codigo, nome, tipo, valor, frete_gratis, data_inicio, data_fim, hora_inicio, hora_fim, limite_total, limite_por_cliente, valor_minimo, ativa, acumula, criado_por)
  values ((v.c).codigo, (v.c).nome, (v.c).tipo, (v.c).valor, (v.c).frete_gratis, (v.c).data_inicio, (v.c).data_fim, (v.c).hora_inicio, (v.c).hora_fim, (v.c).limite_total, (v.c).limite_por_cliente, (v.c).valor_minimo, (v.c).ativa, (v.c).acumula, auth.uid());
  perform _auditar('Cupom criado', (v.c).codigo, (v.c).nome || ' | benefício ' || (v.c).tipo || ' ' || (v.c).valor);
  return jsonb_build_object('ok', true, 'message', 'Cupom criado.');
end $function$;

CREATE OR REPLACE FUNCTION public.api_salvar_evento(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_id uuid := _uuid(p->>'id'); v_nome text := left(btrim(coalesce(p->>'nome', '')), 120); v_data date := _data_iso(btrim(coalesce(p->>'data', '')));
        v_st text := coalesce(nullif(btrim(p->>'status'), ''), 'Orçamento'); v_vc numeric; v_novo uuid;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_nome = '' or v_data is null then return _falha('Informe nome e data do evento.'); end if;
  if v_st <> all (array['Orçamento','Confirmado','Em andamento','Concluído','Cancelado']) then v_st := 'Orçamento'; end if;
  v_vc := case when btrim(coalesce(p->>'valorContratado', '')) = '' then 0 else _num(p->>'valorContratado', -1) end;
  if v_vc < 0 then return _falha('Valor contratado inválido.'); end if;
  v_vc := round(v_vc, 2);
  if v_id is not null and exists (select 1 from eventos where id = v_id) then
  if _versao_conflita(p, 'eventos', v_id) then return _conflito('Este registro foi alterado por outra pessoa enquanto você editava. A tela foi atualizada — confira e edite de novo.'); end if;
    update eventos set nome = v_nome, tipo = left(coalesce(p->>'tipo', ''), 60), data = v_data, hora_inicio = _hora_valida(p->>'horaInicio'), hora_fim = _hora_valida(p->>'horaFim'),
           local = left(coalesce(p->>'local', ''), 160), contratante = left(coalesce(p->>'contratante', ''), 120), telefone = left(coalesce(p->>'telefone', ''), 30),
           status = v_st, valor_contratado = v_vc, observacoes = left(coalesce(p->>'observacoes', ''), 1000)
     where id = v_id;
    perform _recalcular_evento(v_id);
    perform _auditar('Evento alterado', v_id::text, v_nome);
    return jsonb_build_object('ok', true, 'message', 'Evento atualizado.', 'evento', _evento_json(v_id));
  end if;
  insert into eventos (nome, tipo, data, hora_inicio, hora_fim, local, contratante, telefone, status, valor_contratado, valor_recebido, valor_a_receber, custo_total, resultado, observacoes, criado_por)
  values (v_nome, left(coalesce(p->>'tipo', ''), 60), v_data, _hora_valida(p->>'horaInicio'), _hora_valida(p->>'horaFim'), left(coalesce(p->>'local', ''), 160),
          left(coalesce(p->>'contratante', ''), 120), left(coalesce(p->>'telefone', ''), 30), v_st, v_vc, 0, v_vc, 0, v_vc, left(coalesce(p->>'observacoes', ''), 1000), auth.uid())
  returning id into v_novo;
  perform _auditar('Evento criado', v_novo::text, v_nome);
  return jsonb_build_object('ok', true, 'message', 'Evento criado.', 'evento', _evento_json(v_novo));
end $function$;

CREATE OR REPLACE FUNCTION public.api_salvar_meta(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tipo text := p->>'tipo'; v_val numeric := _num(p->>'valor');
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  if v_tipo is null or v_tipo not in ('MetaMensal','MetaDiaria') then return _falha('Tipo de meta inválido.'); end if;
  perform _cfg_gravar(v_tipo, to_jsonb(v_val));
  perform _auditar('Meta atualizada', v_tipo || ': R$ ' || to_char(v_val, 'FM999990.00'));
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_seed_cardapio_texas_burger(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_itens jsonb := $j$[
   ["p","Smash Catupiry","Pão de Brioche, Smash de 80 gr, Catupiry, queijo mussarela, alface","Smash",23.50,24.90],
   ["p","Smash Cheddar","Pão de Brioche, Smash de 80 gr, queijo cheddar e cebola caramelizada","Smash",23.50,24.90],
   ["p","Smash Tasty","Pão de Brioche, Smash de 80 gr, queijo mussarela, alface e tomate","Smash",23.50,24.90],
   ["p","Burguer Rustic","1 Hambúrguer 150gr, Queijo, Bacon, Rúcula, Geleia de Pimenta, Pão com gergelim","Texas Gourmet",38.30,40.90],
   ["p","Barbecue Mister","1 Hambúrguer 150gr, Queijo, Picles, Bacon, Barbecue, Cebola Crispy, Pão com gergelim","Texas Gourmet",39.50,41.90],
   ["p","Onion Texas","1 Hambúrguer 150gr, Queijo, Bacon, Anéis de Cebola, Barbecue, Picles","Texas Gourmet",41.70,44.90],
   ["p","X Texas","1 Hambúrguer 200gr linguiça, Queijo, Rúcula, Tomate, Geleia de pimenta","Texas Gourmet",36.00,38.90],
   ["p","Duplo Cheddar","Dois hambúrgueres 150g, duplo cheddar, bacon, cebola caramelizada, molho da casa","Texas Gourmet",48.40,51.90],
   ["p","Picles Cheddar","1 Hambúrguer 150gr, Cheddar, Alface, Tomate, Cebola Roxa, Picles","Texas Gourmet",36.00,38.90],
   ["p","Texas Honey","1 Hambúrguer 150gr, Cheddar, Bacon, mostarda com mel, Pão Brioche","Texas Gourmet",38.30,40.90],
   ["p","Catupiry Bacon","Pão Brioche, 1 Hambúrguer 150gr, Disco Catupiry 100gr, Bacon, Mussarela, Alface, Tomate","Texas Gourmet",45.00,48.90],
   ["p","Cheddar","Pão Brioche, 1 Hambúrguer 150gr, Cheddar cremoso, Bacon, Cebola Caramelizada","Texas Gourmet",34.00,35.90],
   ["p","X Picanha","Pão Brioche, Hambúrguer 150gr de Picanha, Queijo, Rúcula, Tomate","Texas Gourmet",39.40,42.00],
   ["p","X Costela","Pão com Gergelim, Hambúrguer 150gr de Costela, Queijo, Rúcula, Tomate","Texas Gourmet",38.30,41.00],
   ["p","X Salada","Pão, hambúrguer 150g, presunto, queijo, tomate, alface","Lanches de Hambúrguer",28.25,29.90],
   ["p","X Burguer","Pão, hambúrguer 150g, presunto, queijo, tomate","Lanches de Hambúrguer",28.25,29.90],
   ["p","X Bacon","Pão, hambúrguer 150g, bacon crocante, presunto, queijo, tomate, alface","Lanches de Hambúrguer",36.00,38.90],
   ["p","X Egg","Pão, hambúrguer 150g, dois ovos fritos, presunto, queijo, tomate, alface","Lanches de Hambúrguer",31.65,33.90],
   ["p","X Egg Bacon","Pão, hambúrguer 150g, dois ovos, bacon crocante, presunto, queijo, tomate, alface","Lanches de Hambúrguer",39.55,39.90],
   ["p","X Tudo","Pão, hambúrguer 150g, bacon, salsicha, ovo, presunto, queijo, tomate, alface","Lanches de Hambúrguer",39.55,41.90],
   ["p","X Tudo Especial","Pão, hambúrguer 150g, bacon, milho, salsicha, ovo, batata palha, catupiry, queijo, presunto, tomate","Lanches de Hambúrguer",45.00,47.90],
   ["p","Frango Egg","Pão, 250g frango, ovo, queijo, alface, tomate","Lanches de Frango",32.00,33.90],
   ["p","Frango Bacon","Pão, 250g frango crocante, bacon, queijo derretido, tomate, alface","Lanches de Frango",38.00,40.90],
   ["p","Frango Catupiry","Pão, 250g frango, catupiry cremoso, queijo, alface, tomate","Lanches de Frango",34.00,35.90],
   ["p","Frango Bacon Catupiry","Pão, 250g frango, bacon crocante, catupiry cremoso, queijo, alface, tomate","Lanches de Frango",39.00,41.90],
   ["p","Frango Cubano","Pão, 250g frango, milho, batata palha, catupiry cremoso, queijo, alface, tomate","Lanches de Frango",41.70,44.90],
   ["p","Frango Salada","Pão macio, 250g frango, queijo derretido, tomate fresco, alface crocante","Lanches de Frango",31.00,32.90],
   ["p","Churrasco Tudo","Carne suculenta, ingredientes completos","Churrasco",50.85,53.90],
   ["p","Fritas Simples","Batatas em palito, crocantes","Fritas Texas",34.00,35.90],
   ["p","Fritas 3 Queijos","Batata com mussarela, catupiry e cheddar","Fritas Texas",67.80,71.90],
   ["p","Fritas C C B","Batata com cheddar cremoso, catupiry e bacon crocante","Fritas Texas",67.80,71.90],
   ["p","Fritas Cheddar Bacon","Batata com cheddar cremoso e bacon crocante","Fritas Texas",67.80,71.90],
   ["p","Fritas Especial Texas","Batata com carne, frango, catupiry, cheddar, bacon e mussarela","Fritas Texas",90.00,95.90],
   ["p","Frango a Passarinho","","Fritas Texas",50.00,50.00],
   ["p","Batata Recheada Frango Bacon","Frango, bacon crocante, queijo, creme de leite, batata palha — 500g","Batata Recheada",38.30,41.00],
   ["p","Batata Recheada Frango Cubano","Frango, bacon, milho, catupiry, queijo, batata palha — 500g","Batata Recheada",41.70,45.00],
   ["p","Batata Recheada Churrasco Cubano Contra Filé","Carne, bacon, milho, catupiry, queijo, batata palha — 500g","Batata Recheada",50.85,54.90],
   ["p","Batata Recheada Carne e Queijo Contra Filé","Carne suculenta, queijo derretido, batata palha — 500g","Batata Recheada",50.85,54.90],
   ["p","Batata Recheada Presunto e Queijo","Presunto, Catupiry, creme de leite, batata palha — 500g","Batata Recheada",33.00,35.00],
   ["p","Batata Recheada Brócolis e Bacon","Brócolis frescos, bacon defumado, queijo, batata palha — 500g","Batata Recheada",36.00,38.00],
   ["p","Batata Recheada Frango Bacon e Catupiry","Frango, bacon, queijo, catupiry aveludado, creme de leite, palha — 500g","Batata Recheada",41.00,43.00],
   ["p","Franguinho","Mini lanche frango empanado com queijo","Kids",22.60,23.99],
   ["p","Hamburguinho","Mini hambúrguer com queijo derretido","Kids",22.60,23.99],
   ["p","Doguinho","Pão fofinho, salsicha, batata palha, ketchup, maionese","Kids",17.00,17.99],
   ["p","Coca Cola Lata 350ml","","Bebidas",6.00,7.50],
   ["p","Coca Cola Zero Lata 350ml","","Bebidas",6.00,7.50],
   ["p","Coca Cola 1L","","Bebidas",10.00,12.00],
   ["p","Coca Cola Zero 1L","","Bebidas",10.00,12.00],
   ["p","Coca Cola 2L","","Bebidas",16.00,19.00],
   ["p","Coca Cola Zero 2L","","Bebidas",16.00,19.00],
   ["c","Burguer Rustic Combo","Texas Gourmet",49.60,52.90,["Burguer Rustic","Fritas Simples","Coca Cola Lata 350ml"]],
   ["c","Texas Honey Combo","Texas Gourmet",49.60,52.90,["Texas Honey","Fritas Simples","Coca Cola Lata 350ml"]],
   ["c","Duplo Cheddar Combo","Texas Gourmet",59.80,63.90,["Duplo Cheddar","Fritas Simples","Coca Cola Lata 350ml"]],
   ["c","Barbecue Mister Combo","Texas Gourmet",50.00,53.90,["Barbecue Mister","Fritas Simples","Coca Cola Lata 350ml"]],
   ["c","Catupiry Bacon Combo","Texas Gourmet",56.40,59.90,["Catupiry Bacon","Fritas Simples","Coca Cola Lata 350ml"]],
   ["c","Onion Texas Combo","Texas Gourmet",52.00,56.90,["Onion Texas","Fritas Simples","Coca Cola Lata 350ml"]],
   ["c","Cheddar Combo","Texas Gourmet",45.00,47.90,["Cheddar","Fritas Simples","Coca Cola Lata 350ml"]],
   ["c","X Texas Combo","Texas Gourmet",47.00,49.90,["X Texas","Fritas Simples","Coca Cola Lata 350ml"]],
   ["c","Picles Cheddar Combo","Texas Gourmet",47.00,49.90,["Picles Cheddar","Fritas Simples","Coca Cola Lata 350ml"]],
   ["c","Combo Texas","Combos",79.00,84.99,[]],
   ["c","Combo X Bacon","Combos",99.90,107.99,[]],
   ["c","Combo Salada Burguer","Combos",90.00,95.99,[]],
   ["c","Duplo Tudo","Combos",60.00,71.99,[]],
   ["c","Cheddar em Dobro","Combos",90.00,107.99,[]],
   ["c","Dobro Burguer + Churros","Combos",80.00,95.99,[]],
   ["p","Nacho Dog Texas","Pão de cachorro-quente, salsicha, bacon, muito cheddar e cebola caramelizada","Hot Dog Gourmet",21.50,22.90],
   ["p","The Master Dog","Pão de cachorro-quente, salsicha, bacon, molho especial, picles e cebola","Hot Dog Gourmet",21.50,22.90]
  ]$j$::jsonb;
  v_ingr text[] := array['Pão','Pão com gergelim','Pão Brioche','Hambúrguer 150g','Hambúrguer 200g de linguiça','Hambúrguer 150g de Picanha','Hambúrguer 150g de Costela',
    'Frango','Frango crocante','Carne Contra Filé','Bacon','Presunto','Salsicha','Ovo','Queijo Mussarela','Cheddar cremoso','Catupiry','Creme de leite',
    'Rúcula','Alface','Tomate','Anel de Cebola','Cebola Caramelizada','Cebola Roxa','Picles','Milho','Brócolis','Batata palha','Batata frita',
    'Geleia de Pimenta','Molho Barbecue','Mostarda com mel','Molho da casa','Ketchup','Maionese','Hambúrguer Smash 80g','Pão de cachorro-quente'];
  v_adic text[] := array['Hambúrguer extra (150g)','Bacon extra','Ovo extra','Frango extra','Costela extra','Queijo extra (mussarela)','Cheddar extra','Catupiry extra','Cream cheese',
    'Maionese temperada','Maionese verde','Molho rosê','Molho picante/pimenta','Molho ranch','Tomate seco','Pepino','Jalapeño','Cebola frita crocante',
    'Porção extra de batata frita','Batata rústica','Onion rings extra'];
  it jsonb; v_nome text; v_cat text; v_cat_id uuid; v_id uuid; v_ordem int; v_loja numeric; v_ifood numeric; f record; n text; v_comp text; v_pid uuid;
  n_cat int := 0; n_prod int := 0; n_combo int := 0; n_ing int := 0; n_adic int := 0; v_avisos jsonb := '[]'::jsonb; v_msg text;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  perform pg_advisory_xact_lock(hashtext('seed_cardapio_texas'));

  for it in select * from jsonb_array_elements(v_itens) loop
    if it->>0 = 'p' then
      v_nome := it->>1; v_cat := it->>3; v_loja := (it->>4)::numeric; v_ifood := (it->>5)::numeric;
    else
      v_nome := it->>1; v_cat := it->>2; v_loja := (it->>3)::numeric; v_ifood := (it->>4)::numeric;
    end if;
    if it->>0 = 'p' and exists (select 1 from produtos where lower(nome) = lower(v_nome)) then
      v_avisos := v_avisos || to_jsonb('Produto já existia, não duplicado: ' || v_nome); continue;
    end if;
    if it->>0 = 'c' and exists (select 1 from combos where lower(nome) = lower(v_nome)) then
      v_avisos := v_avisos || to_jsonb('Combo já existia, não duplicado: ' || v_nome); continue;
    end if;
    select id into v_cat_id from categorias where lower(nome) = lower(v_cat) order by ordem limit 1;
    if v_cat_id is null then
      insert into categorias (nome, ativa, ordem) values (v_cat, true, coalesce((select max(ordem) from categorias), 0) + 1) returning id into v_cat_id;
      n_cat := n_cat + 1;
    end if;
    v_ordem := greatest(coalesce((select max(ordem_cardapio) from produtos where categoria_id = v_cat_id), 0), coalesce((select max(ordem_cardapio) from combos where categoria_id = v_cat_id), 0)) + 1;
    if it->>0 = 'p' then
      insert into produtos (nome, descricao, categoria_id, ativo, destaque, ordem_cardapio) values (v_nome, it->>2, v_cat_id, true, false, v_ordem) returning id into v_id;
      for f in select id, nome from formas_pagamento loop
        insert into produto_precos (produto_id, forma_pagamento_id, preco, custo) values (v_id, f.id, case when lower(f.nome) like '%ifood%' then v_ifood else v_loja end, 0);
      end loop;
      n_prod := n_prod + 1;
    else
      insert into combos (nome, categoria_id, ativo, destaque, ordem_cardapio) values (v_nome, v_cat_id, true, false, v_ordem) returning id into v_id;
      for f in select id, nome from formas_pagamento loop
        insert into combo_precos (combo_id, forma_pagamento_id, preco, custo) values (v_id, f.id, case when lower(f.nome) like '%ifood%' then v_ifood else v_loja end, 0);
      end loop;
      for v_comp in select jsonb_array_elements_text(it->5) loop
        select id into v_pid from produtos where lower(nome) = lower(v_comp) limit 1;
        if v_pid is not null then insert into combo_itens (combo_id, produto_id, quantidade) values (v_id, v_pid, 1); end if;
      end loop;
      n_combo := n_combo + 1;
    end if;
  end loop;

  foreach n in array v_ingr loop
    if exists (select 1 from estoque where lower(ingrediente) = lower(n)) then
      v_avisos := v_avisos || to_jsonb('Ingrediente já existia, não duplicado: ' || n);
    else
      insert into estoque (ingrediente, quantidade, quantidade_minima, unidade, custo_unitario, status) values (n, 0, 0, 'un', 0, 'Ativo'); n_ing := n_ing + 1;
    end if;
  end loop;
  foreach n in array v_adic loop
    if exists (select 1 from adicionais where lower(nome) = lower(n)) then
      v_avisos := v_avisos || to_jsonb('Adicional já existia, não duplicado: ' || n);
    else
      insert into adicionais (nome, preco, ativo) values (n, 0, true); n_adic := n_adic + 1;
    end if;
  end loop;

  v_msg := n_cat || ' categorias, ' || n_prod || ' produtos, ' || n_combo || ' combos, ' || n_ing || ' ingredientes e ' || n_adic || ' adicionais cadastrados.';
  perform _auditar('Importação inicial de cardápio executada', v_msg);
  return jsonb_build_object('ok', true, 'message', v_msg,
    'detalhes', jsonb_build_object('categorias', n_cat, 'produtos', n_prod, 'combos', n_combo, 'ingredientes', n_ing, 'adicionaisBasicos', n_adic, 'avisos', v_avisos));
end $function$;

CREATE OR REPLACE FUNCTION public.api_simular_precificacao(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare pr produtos%rowtype; f formas_pagamento%rowtype; pp produto_precos%rowtype; v_tec numeric; v_preco numeric := _num(p->>'precoSimulado', 0);
        v_emb numeric := greatest(0, _num(p->>'embalagem')); v_out numeric := greatest(0, _num(p->>'outrosCustos')); v_mp numeric := greatest(0, _num(p->>'taxaMarketplace'));
        v_taxa numeric; v_taxa_mp numeric; v_total numeric; v_res numeric;
begin
  if not tem_nivel('Admin') then return _negado(); end if;
  select * into pr from produtos where id = _uuid(p->>'produtoId');
  if pr.id is null then return _falha('Produto não encontrado.'); end if;
  select * into f from formas_pagamento where id = _uuid(p->>'formaPagamentoId') and ativa;
  if f.id is null then return _falha('Forma de pagamento não encontrada.'); end if;
  select * into pp from produto_precos where produto_id = pr.id and forma_pagamento_id = f.id;
  if pp.id is null then return _falha('Preço do produto para esta forma de pagamento não encontrado.'); end if;
  select coalesce(sum(e.custo_unitario * pi.quantidade_por_unidade), 0) into v_tec
    from produto_ingredientes pi join estoque e on e.id = pi.ingrediente_id where pi.produto_id = pr.id;
  if v_tec <= 0 then v_tec := coalesce(pp.custo, 0); end if;
  if not (v_preco > 0) then return _falha('Preço simulado inválido.'); end if;
  v_taxa := round(v_preco * f.taxa_percentual / 100 + f.taxa_fixa, 2);
  v_taxa_mp := round(v_preco * v_mp / 100, 2);
  v_total := round(v_tec + v_emb + v_out + v_taxa + v_taxa_mp, 2);
  v_res := round(v_preco - v_total, 2);
  return jsonb_build_object('ok', true, 'produto', pr.nome, 'formaPagamento', f.nome, 'precoAtual', pp.preco, 'precoSimulado', v_preco,
    'custoTecnico', round(v_tec, 2), 'embalagem', v_emb, 'outrosCustos', v_out, 'taxaPagamento', v_taxa, 'taxaPagamentoPct', f.taxa_percentual,
    'taxaPagamentoFixa', f.taxa_fixa, 'taxaMarketplace', v_taxa_mp, 'taxaMarketplacePct', v_mp, 'custoTotal', v_total, 'resultado', v_res,
    'margem', round(v_res / v_preco * 100, 2), 'markup', case when v_total > 0 then round(v_preco / v_total, 2) else 0 end);
end $function$;

CREATE OR REPLACE FUNCTION public.api_suspender_pedido(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_toggle_resgate_indicacao(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_tel text := _so_digitos(p->>'telIndicado'); i indicacoes%rowtype; v_novo status_indicacao;
begin
  if not tem_nivel('Admin','Operador') then return _negado(); end if;
  if v_tel <> '' then
    select * into i from indicacoes where _so_digitos(telefone_indicado) = v_tel order by data limit 1 for update;
    if i.id is not null then
      v_novo := case when i.status = 'Resgatado' then 'Pendente' else 'Resgatado' end;
      update indicacoes set status = v_novo where id = i.id;
      perform _auditar('Status de indicação alterado', v_novo::text, p->>'telIndicado');
    end if;
  end if;
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.api_trocar_minha_senha(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.api_validar_cupom_cardapio(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_ip text := _ip_cliente(); v_r jsonb;
begin
  if _excedeu('cupomval_ip_' || v_ip, 15) or _excedeu('cupomval_global', 200) then
    return jsonb_build_object('ok', false, 'message', 'Muitas tentativas de cupom. Aguarde alguns minutos.', 'limite', true);
  end if;
  v_r := _cupom_calcular(p->>'codigo', p->>'telefone', _num(p->>'subtotal'), p->>'tipoEntrega');
  if coalesce(v_r->>'ok', '') <> 'true' then
    perform _registrar_falha('cupomval_ip_' || v_ip, 600); perform _registrar_falha('cupomval_global', 600);
  end if;
  return v_r;
end $function$;

CREATE OR REPLACE FUNCTION public.api_verificar_senha_admin(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth_nivel() is null then return _negado(); end if;
  return jsonb_build_object('ok', _exige_admin(p->>'senha') is not null);
end $function$;

CREATE OR REPLACE FUNCTION public.api_versoes()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  if auth_nivel() is null then return _negado(); end if;
  return jsonb_build_object('ok', true,
    'cad', coalesce((select n::text from versoes_sync where grupo = 'cad'), '0'),
    'din', coalesce((select n::text from versoes_sync where grupo = 'din'), '0'));
end $function$;

CREATE OR REPLACE FUNCTION public.api_versoes_registros(p jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_nivel text := auth_nivel()::text;
  v_mapa jsonb := jsonb_build_object('produtos','produtos','combos','combos','adicionais','adicionais','formasPagamento','formas_pagamento','categorias','categorias',
                                     'clientes','clientes','cupons','cupons','eventos','eventos','despesas','despesas','despesasRecorrentes','despesas_recorrentes',
                                     'usuarios','usuarios','vendas','vendas');
  v_chaves text[]; k text; r jsonb := '{}'::jsonb; m jsonb;
begin
  if v_nivel is null then return _negado(); end if;
  if v_nivel in ('Admin', 'Operador') then
    v_chaves := array['produtos','combos','adicionais','formasPagamento','categorias','clientes','cupons','eventos','despesas','despesasRecorrentes','usuarios','vendas'];
  elsif v_nivel = 'Garçom' then
    v_chaves := array['clientes'];
  else
    return jsonb_build_object('ok', true, 'versoes', '{}'::jsonb);
  end if;
  if jsonb_typeof(p->'chaves') = 'array' then
    v_chaves := array(select c from unnest(v_chaves) c where c in (select jsonb_array_elements_text(p->'chaves')));
  end if;
  foreach k in array v_chaves loop
    select coalesce(jsonb_object_agg(t.rid::text, t.ver), '{}'::jsonb) into m from _versoes_tabela(v_mapa->>k, null) t;
    r := r || jsonb_build_object(k, m);
  end loop;
  return jsonb_build_object('ok', true, 'versoes', r);
end $function$;

CREATE OR REPLACE FUNCTION public.api_vincular_adicionais_em_lote(p jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
end $function$;

CREATE OR REPLACE FUNCTION public.auth_nivel()
 RETURNS nivel_acesso
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select case when u.nivel::text = 'Desenvolvedor' then 'Admin'::nivel_acesso else u.nivel end
  from usuarios u
  where u.id = auth.uid() and u.ativo
    and (coalesce(auth.jwt() ->> 'session_id', '') = ''
         or exists (select 1 from auth.sessions s where s.id = (auth.jwt() ->> 'session_id')::uuid))
$function$;

CREATE OR REPLACE FUNCTION public.enfileirar_sync()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare reg jsonb; rid text;
begin
  if tg_op = 'DELETE' then reg := to_jsonb(old); else reg := to_jsonb(new); end if;
  rid := coalesce(reg->>'id', reg->>'chave');
  insert into fila_sync (tabela, registro_id, operacao, payload)
  values (tg_table_name, rid, tg_op::op_sync, case when tg_op = 'DELETE' then null else reg end);
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.rls_auto_enable()
 RETURNS event_trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog'
AS $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

CREATE OR REPLACE FUNCTION public.tem_nivel(VARIADIC niveis nivel_acesso[])
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select coalesce(auth_nivel() = any(niveis), false)
$function$;

CREATE OR REPLACE FUNCTION public.tocar_atualizado_em()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_catalog'
AS $function$
begin new.atualizado_em := now(); return new; end $function$;

-- índice único por dígitos do telefone (usa a função _so_digitos, por isso fica depois da seção 7)
CREATE UNIQUE INDEX IF NOT EXISTS clientes_telefone_digitos_uq ON public.clientes USING btree (public._so_digitos(telefone)) WHERE ((telefone IS NOT NULL) AND (telefone <> ''::text) AND (public._so_digitos(telefone) <> ''::text));

-- 8. VIEWS ------------------------------------------------------------
CREATE OR REPLACE VIEW public.v_cardapio_adicionais AS
SELECT pa.produto_id,
    a.id AS adicional_id,
    a.nome,
    a.preco
   FROM ((produto_adicionais pa
     JOIN adicionais a ON (((a.id = pa.adicional_id) AND a.ativo)))
     JOIN produtos p ON (((p.id = pa.produto_id) AND p.ativo)));
CREATE OR REPLACE VIEW public.v_cardapio_categorias AS
SELECT id,
    nome,
    ordem
   FROM categorias
  WHERE ativa;
CREATE OR REPLACE VIEW public.v_cardapio_combo_itens AS
SELECT ci.combo_id,
    ci.produto_id,
    ci.quantidade
   FROM (combo_itens ci
     JOIN combos c ON (((c.id = ci.combo_id) AND c.ativo)));
CREATE OR REPLACE VIEW public.v_cardapio_combos AS
SELECT id,
    nome,
    categoria_id,
    destaque,
    ordem_cardapio,
    foto_id_principal,
    foto_id_contingencia,
    foto_url_principal,
    foto_url_contingencia,
    foto_preferida
   FROM combos
  WHERE ativo;
CREATE OR REPLACE VIEW public.v_cardapio_config AS
SELECT chave,
    valor
   FROM sistema
  WHERE (chave = ANY (ARRAY['CardapioKicker'::text, 'CardapioFrase'::text, 'CardapioTempoRetirada'::text, 'CardapioTempoMesa'::text, 'CardapioTempoEntrega'::text, 'TaxaEntregaPadrao'::text, 'MANUTENCAO'::text]));
CREATE OR REPLACE VIEW public.v_cardapio_formas AS
SELECT id,
    nome,
    ordem,
    permite_troco
   FROM formas_pagamento
  WHERE (ativa AND visivel_cardapio);
CREATE OR REPLACE VIEW public.v_cardapio_precos AS
SELECT 'produto'::text AS tipo,
    pp.produto_id AS item_id,
    pp.forma_pagamento_id,
    pp.preco
   FROM ((produto_precos pp
     JOIN produtos p ON (((p.id = pp.produto_id) AND p.ativo)))
     JOIN formas_pagamento f ON (((f.id = pp.forma_pagamento_id) AND f.ativa AND f.visivel_cardapio)))
UNION ALL
 SELECT 'combo'::text AS tipo,
    cp.combo_id AS item_id,
    cp.forma_pagamento_id,
    cp.preco
   FROM ((combo_precos cp
     JOIN combos c ON (((c.id = cp.combo_id) AND c.ativo)))
     JOIN formas_pagamento f ON (((f.id = cp.forma_pagamento_id) AND f.ativa AND f.visivel_cardapio)));
CREATE OR REPLACE VIEW public.v_cardapio_produtos AS
SELECT id,
    nome,
    descricao,
    categoria_id,
    destaque,
    ordem_cardapio,
    foto_id_principal,
    foto_id_contingencia,
    foto_url_principal,
    foto_url_contingencia,
    foto_preferida
   FROM produtos
  WHERE ativo;
CREATE OR REPLACE VIEW public.v_cardapio_status AS
SELECT (EXISTS ( SELECT 1
           FROM caixa_sessoes
          WHERE (caixa_sessoes.status = 'Aberto'::status_caixa))) AS caixa_aberto;
CREATE OR REPLACE VIEW public.v_fidelidade AS
SELECT c.nome,
    c.telefone,
    f.carimbos,
    f.premios_resgatados AS premios,
    f.atualizada_em AS atualizado,
    f.observacoes AS observacao,
    f.cliente_id
   FROM (fidelidade f
     JOIN clientes c ON ((c.id = f.cliente_id)));
CREATE OR REPLACE VIEW public.v_indicacoes AS
SELECT id,
    nome_indicador,
    telefone_indicador,
    nome_indicado,
    telefone_indicado,
    data,
    status,
    observacoes,
    indicador_id,
    indicado_id
   FROM indicacoes i
  WHERE (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]) OR (tem_nivel(VARIADIC ARRAY['Garçom'::nivel_acesso]) AND (_so_digitos(telefone_indicador) <> ''::text) AND (_so_digitos(telefone_indicador) = ( SELECT _so_digitos(u.telefone) AS _so_digitos
           FROM usuarios u
          WHERE (u.id = auth.uid())))));
CREATE OR REPLACE VIEW public.v_itens_venda AS
SELECT id,
    venda_id,
    produto_id,
    combo_id,
    descricao,
    quantidade,
    valor_unitario,
        CASE
            WHEN (auth_nivel() = ANY (ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso])) THEN custo_unitario
            ELSE NULL::numeric
        END AS custo_unitario,
    valor_total_item,
    adicionais_ids
   FROM itens_venda i;
CREATE OR REPLACE VIEW public.v_mesas AS
SELECT m.id,
    m.numero,
    m.status,
    m.capacidade,
    m.observacao,
    m.chamado_tipo,
    m.chamado_em,
    u.login AS garcom_responsavel
   FROM (mesas m
     LEFT JOIN usuarios u ON ((u.id = m.garcom_responsavel_id)))
  WHERE tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso]);
CREATE OR REPLACE VIEW public.v_ocorrencias AS
SELECT id,
    numero,
    data_hora,
    tipo,
    setor,
    venda_id,
    cliente,
    telefone,
    _login_de(registrado_por) AS registrado_por,
    responsavel,
    descricao,
    solucao,
    status,
    atualizada_em,
    historico
   FROM ocorrencias o;
CREATE OR REPLACE VIEW public.v_sessao_aberta AS
SELECT id,
    abertura,
    fundo_caixa,
    _login_de(usuario_abertura) AS usuario_abertura
   FROM caixa_sessoes s
  WHERE ((status = 'Aberto'::status_caixa) AND (auth_nivel() IS NOT NULL));
CREATE OR REPLACE VIEW public.v_vendas AS
SELECT id,
    numero_pedido AS numero,
    data_hora,
    cliente_nome,
        CASE
            WHEN (auth_nivel() = 'Cozinha'::nivel_acesso) THEN NULL::text
            ELSE telefone_cliente
        END AS cliente_telefone,
    forma_pagamento,
    valor_total,
        CASE
            WHEN (auth_nivel() = ANY (ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso])) THEN custo_total
            ELSE NULL::numeric
        END AS custo_total,
    status,
    motivo_cancelamento,
    tipo AS tipo_entrega,
    status_pedido,
        CASE
            WHEN (auth_nivel() = 'Cozinha'::nivel_acesso) THEN NULL::text
            ELSE endereco
        END AS endereco,
        CASE
            WHEN (auth_nivel() = 'Cozinha'::nivel_acesso) THEN NULL::text
            ELSE complemento
        END AS complemento,
        CASE
            WHEN (auth_nivel() = 'Cozinha'::nivel_acesso) THEN NULL::text
            ELSE referencia
        END AS referencia,
    observacoes_entrega,
    pronta_em,
    concluida_em,
    status_pagamento,
    recebido_em,
    valor_original,
    valor_desconto,
    desconto_detalhe,
    _login_de(entregador_id) AS entregador,
    saiu_em,
    origem,
    mesa_id,
    taxa_entrega,
    fechamento_entrega_id,
    _login_de(registrado_por) AS registrado_por,
    inicio_preparo_em
   FROM vendas v;
CREATE OR REPLACE VIEW public.v_cardapio_esgotados AS
WITH ligado AS (
         SELECT COALESCE(( SELECT ((sistema.valor #>> '{}'::text[]) = ANY (ARRAY['true'::text, 'Sim'::text]))
                   FROM sistema
                  WHERE (sistema.chave = 'BLOQUEAR_ESTOQUE_NEGATIVO'::text)), false) AS on_
        ), falta AS (
         SELECT pi.produto_id,
            bool_or(((pi.quantidade_por_unidade > (0)::numeric) AND ((e.quantidade + 0.000000001) < pi.quantidade_por_unidade))) AS f1,
            min(
                CASE
                    WHEN (pi.quantidade_por_unidade > (0)::numeric) THEN (e.quantidade / pi.quantidade_por_unidade)
                    ELSE NULL::numeric
                END) AS razao
           FROM (produto_ingredientes pi
             JOIN estoque e ON ((e.id = pi.ingrediente_id)))
          GROUP BY pi.produto_id
        )
 SELECT 'produto'::text AS tipo,
    p.id
   FROM (v_cardapio_produtos p
     JOIN falta f ON ((f.produto_id = p.id))),
    ligado
  WHERE (ligado.on_ AND f.f1)
UNION ALL
 SELECT 'combo'::text AS tipo,
    b.id
   FROM v_cardapio_combos b,
    ligado
  WHERE (ligado.on_ AND (EXISTS ( SELECT 1
           FROM ((combo_itens ci
             JOIN produto_ingredientes pi ON ((pi.produto_id = ci.produto_id)))
             JOIN estoque e ON ((e.id = pi.ingrediente_id)))
          WHERE ((ci.combo_id = b.id) AND (pi.quantidade_por_unidade > (0)::numeric) AND ((e.quantidade + 0.000000001) < (pi.quantidade_por_unidade * (GREATEST(COALESCE(ci.quantidade, 1), 1))::numeric))))));
CREATE OR REPLACE VIEW public.v_cardapio_mais_pedidos AS
WITH cont AS (
         SELECT COALESCE(('p_'::text || (iv.produto_id)::text), ('c_'::text || (iv.combo_id)::text)) AS chave,
                CASE
                    WHEN (iv.produto_id IS NOT NULL) THEN 'produto'::text
                    ELSE 'combo'::text
                END AS tipo,
            COALESCE(iv.produto_id, iv.combo_id) AS item_id,
            sum(COALESCE(iv.quantidade, 1)) AS qtd
           FROM (itens_venda iv
             JOIN vendas v ON ((v.id = iv.venda_id)))
          WHERE ((v.status = 'Confirmada'::venda_status) AND (v.data_hora >= (now() - '30 days'::interval)) AND ((iv.produto_id IS NOT NULL) OR (iv.combo_id IS NOT NULL)))
          GROUP BY COALESCE(('p_'::text || (iv.produto_id)::text), ('c_'::text || (iv.combo_id)::text)),
                CASE
                    WHEN (iv.produto_id IS NOT NULL) THEN 'produto'::text
                    ELSE 'combo'::text
                END, COALESCE(iv.produto_id, iv.combo_id)
        ), vis AS (
         SELECT c.tipo,
            c.item_id,
            c.qtd
           FROM cont c
          WHERE (((c.tipo = 'produto'::text) AND (EXISTS ( SELECT 1
                   FROM v_cardapio_produtos p
                  WHERE (p.id = c.item_id)))) OR ((c.tipo = 'combo'::text) AND (EXISTS ( SELECT 1
                   FROM v_cardapio_combos b
                  WHERE (b.id = c.item_id)))))
        )
 SELECT tipo,
    item_id AS id,
    (row_number() OVER (ORDER BY qtd DESC, item_id))::integer AS posicao
   FROM vis
  ORDER BY qtd DESC, item_id
 LIMIT 8;
ALTER VIEW public.v_fidelidade SET (security_invoker = true);
ALTER VIEW public.v_itens_venda SET (security_invoker = true);
ALTER VIEW public.v_ocorrencias SET (security_invoker = true);
ALTER VIEW public.v_vendas SET (security_invoker = true);

-- 9. DADOS ------------------------------------------------------------
BEGIN;
SET LOCAL session_replication_role = replica;  -- sem triggers de sync e sem checagem de FK durante a carga

-- usuarios
-- (requer os mesmos ids em auth.users; veja a observação no topo do arquivo)
INSERT INTO public.usuarios SELECT * FROM jsonb_populate_recordset(null::public.usuarios, '[{"id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "nome": "Jonatan", "ativo": true, "login": "Jonatan", "nivel": "Admin", "telefone": null, "criado_em": "2026-10-02T22:45:00+00:00"}, {"id": "a7fb2364-a458-439d-b92d-e7e9933bfba5", "nome": "Caixa", "ativo": true, "login": "Caixa", "nivel": "Operador", "telefone": null, "criado_em": "2026-10-02T22:45:00+00:00"}, {"id": "6d7fc99c-2ef1-4a53-b9eb-7bf3904573af", "nome": "Garçom", "ativo": true, "login": "Garçom", "nivel": "Garçom", "telefone": null, "criado_em": "2026-10-02T22:45:00+00:00"}, {"id": "a1c0b864-b517-4c9e-995c-42394e88fe93", "nome": "Cozinha", "ativo": true, "login": "Cozinha", "nivel": "Cozinha", "telefone": null, "criado_em": "2026-10-02T22:45:00+00:00"}, {"id": "8e442ee3-af30-4da0-ae6c-0312d2ba9223", "nome": "Entregador", "ativo": true, "login": "Entregador", "nivel": "Entregador", "telefone": "11963260715", "criado_em": "2026-10-02T22:45:00+00:00"}]'::jsonb) ON CONFLICT DO NOTHING;

-- configuracoes_fotos
INSERT INTO public.configuracoes_fotos SELECT * FROM jsonb_populate_recordset(null::public.configuracoes_fotos, '[{"id": true, "onde_guardar": null, "atualizado_em": "2026-10-03T16:23:23.875703+00:00", "drive_preferido": null, "replicar_antigas": null, "backup_frio_storage": null, "sincronizacao_drives": null, "destino_padrao_upload": null}]'::jsonb) ON CONFLICT DO NOTHING;

-- sistema
INSERT INTO public.sistema SELECT * FROM jsonb_populate_recordset(null::public.sistema, '[{"chave": "MetaMensal", "valor": 0, "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "MetaDiaria", "valor": 0, "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "BLOQUEAR_ESTOQUE_NEGATIVO", "valor": false, "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "CardapioKicker", "valor": "", "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "CardapioFrase", "valor": "", "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "CardapioTempoRetirada", "valor": "", "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "CardapioTempoMesa", "valor": "", "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "CardapioTempoEntrega", "valor": "", "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "NotificacoesConfig", "valor": null, "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "BACKUP_AUTO_ATIVO", "valor": false, "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "BACKUP_HORA", "valor": 4, "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "BACKUP_FREQ", "valor": "diario", "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "MANUTENCAO", "valor": null, "atualizado_em": "2026-10-03T16:23:23.875703+00:00"}, {"chave": "ULTIMA_GERACAO_DESPESAS", "valor": "2026-10", "atualizado_em": "2026-10-04T14:08:42.811026+00:00"}, {"chave": "TaxaEntregaPadrao", "valor": 8.00, "atualizado_em": "2026-10-04T17:13:29.113404+00:00"}, {"chave": "AjudaDiariaEntregador", "valor": 0.00, "atualizado_em": "2026-10-04T17:13:29.113404+00:00"}]'::jsonb) ON CONFLICT DO NOTHING;

-- categorias
INSERT INTO public.categorias SELECT * FROM jsonb_populate_recordset(null::public.categorias, '[{"id": "75ea8c91-31b4-4b8a-b57c-e1120e5e6835", "nome": "Smash", "ativa": true, "ordem": 1}, {"id": "979f1174-1624-4773-be8a-45a38bf79f69", "nome": "Texas Gourmet", "ativa": true, "ordem": 2}, {"id": "d4ec1678-47a4-4135-b9f3-fbb49b7f6e06", "nome": "Lanches de Hambúrguer", "ativa": true, "ordem": 3}, {"id": "f9386fbd-44ce-4f5b-a6db-3f75bf5f757c", "nome": "Lanches de Frango", "ativa": true, "ordem": 4}, {"id": "71faeb28-1e76-45a9-a64a-a84bb0f8ed01", "nome": "Churrasco", "ativa": true, "ordem": 5}, {"id": "9a732021-a144-477b-9831-9f33a85c5f30", "nome": "Fritas Texas", "ativa": true, "ordem": 6}, {"id": "70d82bfd-93a0-42c6-b784-4bd736f0cdbc", "nome": "Batata Recheada", "ativa": true, "ordem": 7}, {"id": "c00a6047-f5a6-481e-8dd2-2e41b622854f", "nome": "Kids", "ativa": true, "ordem": 8}, {"id": "83e31e11-3bae-40c8-a8c0-fb729b768581", "nome": "Bebidas", "ativa": true, "ordem": 9}, {"id": "b5e9987e-d8e3-4dd7-b0c8-814770bd33df", "nome": "Combos", "ativa": true, "ordem": 10}, {"id": "c1517d71-2845-4fd1-91e5-707c9e4d74ed", "nome": "Hot Dog Gourmet", "ativa": true, "ordem": 11}]'::jsonb) ON CONFLICT DO NOTHING;

-- formas_pagamento
INSERT INTO public.formas_pagamento SELECT * FROM jsonb_populate_recordset(null::public.formas_pagamento, '[{"id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71", "nome": "Dinheiro", "ativa": true, "ordem": 1, "taxa_fixa": 0.00, "prazo_dias": 0, "permite_troco": true, "taxa_percentual": 0.00, "visivel_cardapio": true}, {"id": "17b14f91-68d9-4a94-9374-c64846414581", "nome": "Pix", "ativa": true, "ordem": 2, "taxa_fixa": 0.00, "prazo_dias": 0, "permite_troco": false, "taxa_percentual": 0.00, "visivel_cardapio": true}, {"id": "19f2f926-8a9e-41a7-ba5f-2280b672950e", "nome": "Cartão de Débito", "ativa": true, "ordem": 3, "taxa_fixa": 0.00, "prazo_dias": 0, "permite_troco": false, "taxa_percentual": 0.00, "visivel_cardapio": true}, {"id": "d0e73585-ca32-43f7-8051-8469cc6034ba", "nome": "Cartão de Crédito", "ativa": true, "ordem": 4, "taxa_fixa": 0.00, "prazo_dias": 0, "permite_troco": false, "taxa_percentual": 0.00, "visivel_cardapio": true}, {"id": "212c5286-05f4-47aa-8c00-ed7968551e08", "nome": "Alelo", "ativa": true, "ordem": 5, "taxa_fixa": 0.00, "prazo_dias": 0, "permite_troco": false, "taxa_percentual": 0.00, "visivel_cardapio": true}, {"id": "21d76d26-8608-47b8-b387-1e9f5b150715", "nome": "iFood", "ativa": true, "ordem": 6, "taxa_fixa": 0.00, "prazo_dias": 0, "permite_troco": false, "taxa_percentual": 0.00, "visivel_cardapio": false}]'::jsonb) ON CONFLICT DO NOTHING;

-- estoque
INSERT INTO public.estoque SELECT * FROM jsonb_populate_recordset(null::public.estoque, '[{"id": "d77e9f66-dc34-4636-ab5d-96fbb51b21fa", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Coca Cola Lata 350ml", "custo_unitario": 0.0000, "quantidade_minima": 5.000}, {"id": "52c73474-5488-4404-8887-65a706905f3e", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Coca Cola Zero Lata 350ml", "custo_unitario": 0.0000, "quantidade_minima": 5.000}, {"id": "0502d2f5-70c8-44f3-920b-ee10f22c8ef3", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Coca Cola 1L", "custo_unitario": 0.0000, "quantidade_minima": 5.000}, {"id": "4d1aed3a-dd06-4519-bbf4-db2c174db59a", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Coca Cola Zero 1L", "custo_unitario": 0.0000, "quantidade_minima": 5.000}, {"id": "435cdc1d-1800-4d38-84ad-3ba22fc809eb", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Coca Cola 2L", "custo_unitario": 0.0000, "quantidade_minima": 5.000}, {"id": "a00860db-8d18-4c79-af74-783b3025f6d3", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Coca Cola Zero 2L", "custo_unitario": 0.0000, "quantidade_minima": 5.000}, {"id": "774de063-d27a-44b3-9600-62929ab39a51", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Pão", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "60186adc-05ed-4ade-8165-634077433346", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Pão com gergelim", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "aa6bd6a9-6065-43c2-8a57-406616c6edf0", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Pão Brioche", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "31750f4c-2e8e-4f57-b609-5e95a0aec252", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Hambúrguer 150g", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "45a83290-6920-45d3-bb76-7c5f7dbc00bb", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Hambúrguer 200g de linguiça", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "f39adc02-af43-46eb-b2b5-50c14c2558cf", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Hambúrguer 150g de Picanha", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "e0e0d601-c3d4-4276-9799-aa54eca3d07e", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Hambúrguer 150g de Costela", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "00ccbdd1-3e61-4e0c-b467-04abb8c9f9fc", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Frango", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "b3a46cc2-6b6c-4304-bfac-52e2c3e1de79", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Frango crocante", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "fb24c49d-a4a4-4d4a-9446-1969b8440ebc", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Carne Contra Filé", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "60aabb92-6c29-43f2-a1b5-9cc7217a6cb4", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Bacon", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "a193d8e1-f087-49a5-b078-e5fa4990aedc", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Presunto", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "a0571d1c-21ff-49ac-a040-cbe78dc15944", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Salsicha", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "bfaa5579-33fc-4327-85d8-7a76f7ebeb5b", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Ovo", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "eb106229-8c07-465b-9129-24cadf4c7c00", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Queijo Mussarela", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "d5b72b65-a2c0-43cb-a59c-4bb3bb79035a", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Cheddar cremoso", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "8c352f67-b128-4eb6-b112-38ea50440b03", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Catupiry", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "e8d06141-538b-4bc0-a08c-ec3f40048387", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Creme de leite", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "18ded61d-073a-4c0f-bea8-30b95b40cbdf", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Rúcula", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "d5f83abb-06fc-4c50-aae2-c54c9b3eea35", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Alface", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "f43cc40f-3a3b-40a3-b253-adf393569879", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Tomate", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "4dae510c-cc28-483d-80c8-32d2592f4d9f", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Anel de Cebola", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "46354a04-75b6-47f8-8044-6395ff26e2fd", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Cebola Caramelizada", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "2b9518fb-7248-48dc-a3fb-9d1553f2b058", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Cebola Roxa", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "102e626e-de6c-4354-8a68-108f3639a677", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Picles", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "d146b503-920a-4b79-9814-521148ed2d8c", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Milho", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "53b91edb-66fa-4b11-a1c5-674a78d08750", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Brócolis", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "13f5cd01-df2c-402c-aa1d-d58c4b7340b5", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Batata palha", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "b8511ba5-b6ff-43ec-adc8-1cee823ac124", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Batata frita", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "95f24215-1057-4ca2-97ed-f9e2aadc60f4", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Geleia de Pimenta", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "826e891d-c682-427a-a7c6-d53c14f06ece", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Molho Barbecue", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "32e9ad52-3c43-4b4a-985b-48e9762a59fd", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Mostarda com mel", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "5b3f3d17-4928-445f-8150-6a8ab3e45c94", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Molho da casa", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "328dfe6e-8b6d-4b40-9d19-8439038f9647", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Ketchup", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "c2c6531b-dc84-41d1-a45c-259c979c7cd9", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Maionese", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "4778caf0-60e4-4713-8f59-1e7a3e85cb3b", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Hambúrguer Smash 80g", "custo_unitario": 0.0000, "quantidade_minima": 0.000}, {"id": "0e3054a3-96c8-43dd-b2cc-3bf7ce8769ca", "status": "Ativo", "unidade": "un", "quantidade": 0.000, "ingrediente": "Pão de cachorro-quente", "custo_unitario": 0.0000, "quantidade_minima": 0.000}]'::jsonb) ON CONFLICT DO NOTHING;

-- promocoes
INSERT INTO public.promocoes SELECT * FROM jsonb_populate_recordset(null::public.promocoes, '[{"id": "4238e8ee-8978-42e6-8655-12e4be0f5652", "nome": "Indicação de amigos", "tipo": "Indicação", "ativa": true, "beneficio": "1 batata pequena para quem indicou", "regra_duplicidade": "O indicado só pode aparecer uma vez"}, {"id": "c502d56e-b484-4acf-86a3-774c04944f83", "nome": "Cartão Fidelidade", "tipo": "Fidelidade (carimbos)", "ativa": true, "beneficio": "1 porção de batata frita a cada 10 marcas", "regra_duplicidade": "Soma marca a cada venda com cliente associado"}, {"id": "d5c80a36-e534-4a2b-b1b6-7110b8f6c063", "nome": "Indicação de amigos", "tipo": "Indicação", "ativa": true, "beneficio": "1 batata pequena para quem indicou", "regra_duplicidade": "O indicado só pode aparecer uma vez"}, {"id": "9407cd22-4c89-46c0-9990-1351c9650b49", "nome": "Cartão Fidelidade", "tipo": "Fidelidade (carimbos)", "ativa": true, "beneficio": "1 porção de batata frita a cada 10 marcas", "regra_duplicidade": "Soma marca a cada venda com cliente associado"}]'::jsonb) ON CONFLICT DO NOTHING;

-- adicionais
INSERT INTO public.adicionais SELECT * FROM jsonb_populate_recordset(null::public.adicionais, '[{"id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b", "nome": "Hambúrguer extra (150g)", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149", "nome": "Bacon extra", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "527e67ca-6eca-4b95-ba76-7fa0dd557594", "nome": "Ovo extra", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "375fb3e2-36f3-47be-9d78-7d0d11882a35", "nome": "Frango extra", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "f4943c8c-5948-4e69-806c-71dcf68e1678", "nome": "Costela extra", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "6861e324-b899-48fe-8854-a42e33113ecb", "nome": "Queijo extra (mussarela)", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "081a3274-b818-4fe1-908a-32a8f752e302", "nome": "Cheddar extra", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "c06e9235-09d1-45d3-ad09-e347d8da6c75", "nome": "Catupiry extra", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88", "nome": "Cream cheese", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "a526737c-cfd1-4169-a2fa-d9c62819fd16", "nome": "Maionese temperada", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "b860d589-8024-4632-9a0e-e86bcd112634", "nome": "Maionese verde", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829", "nome": "Molho rosê", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1", "nome": "Molho picante/pimenta", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "80e18270-3011-46cb-a5f3-10197a5d728a", "nome": "Molho ranch", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15", "nome": "Tomate seco", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "44815153-bbb6-4559-ae81-82cd3e3ccae7", "nome": "Pepino", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "21328783-0d86-4fba-b0f9-45caef78e4fd", "nome": "Jalapeño", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e", "nome": "Cebola frita crocante", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "726e8d36-8e80-448a-aa0c-953130ea68b6", "nome": "Porção extra de batata frita", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "08f7b146-1785-44c2-82fc-7ed246ef94e3", "nome": "Batata rústica", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}, {"id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c", "nome": "Onion rings extra", "ativo": true, "preco": 0.00, "ingrediente_id": null, "quantidade_descontar": 1.000}]'::jsonb) ON CONFLICT DO NOTHING;

-- produtos
INSERT INTO public.produtos SELECT * FROM jsonb_populate_recordset(null::public.produtos, '[{"id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "nome": "Smash Catupiry", "ativo": true, "destaque": false, "descricao": "Pão de Brioche, Smash de 80 gr, Catupiry, queijo mussarela, alface", "categoria_id": "75ea8c91-31b4-4b8a-b57c-e1120e5e6835", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1LVyTh4_6kOxuZOUO2U1aoNgF694Tobnr", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "71b73436-5512-4ba4-9719-541b70aec6e0", "nome": "Smash Cheddar", "ativo": true, "destaque": false, "descricao": "Pão de Brioche, Smash de 80 gr, queijo cheddar e cebola caramelizada", "categoria_id": "75ea8c91-31b4-4b8a-b57c-e1120e5e6835", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "1UnVGAUDP0FM___2u2ea1Oa6fiAXtdWOK", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "8581a904-a689-4535-8ffd-0faef973e9a1", "nome": "Smash Tasty", "ativo": true, "destaque": false, "descricao": "Pão de Brioche, Smash de 80 gr, queijo mussarela, alface e tomate", "categoria_id": "75ea8c91-31b4-4b8a-b57c-e1120e5e6835", "foto_preferida": "principal", "ordem_cardapio": 3, "foto_id_principal": "1IggiM5rCWvFV-_Z1jhIGxOq8xTHpJU6y", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "ee5b570a-759c-42aa-929b-efb390436f1a", "nome": "Burguer Rustic", "ativo": true, "destaque": false, "descricao": "1 Hambúrguer 150gr, Queijo, Bacon, Rúcula, Geleia de Pimenta, Pão com gergelim", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1PxZEtjdgU9dq9WYrvG4NyviG5NrAJ7g7", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "nome": "Barbecue Mister", "ativo": true, "destaque": false, "descricao": "1 Hambúrguer 150gr, Queijo, Picles, Bacon, Barbecue, Cebola Crispy, Pão com gergelim", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "196JTEpKV5lOCxq7TIWDWeM4-LmBudfn2", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "nome": "Onion Texas", "ativo": true, "destaque": false, "descricao": "1 Hambúrguer 150gr, Queijo, Bacon, Anéis de Cebola, Barbecue, Picles", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 3, "foto_id_principal": "1My-eTcUxof1qzOx5KmDUSjnt589AUDjm", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "nome": "X Texas", "ativo": true, "destaque": false, "descricao": "1 Hambúrguer 200gr linguiça, Queijo, Rúcula, Tomate, Geleia de pimenta", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 4, "foto_id_principal": "14NNXcOfgt4bCts2x7Uxr1LjFcjeEJvTV", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "7583e038-e58c-41a8-867c-026f1b90d787", "nome": "Duplo Cheddar", "ativo": true, "destaque": false, "descricao": "Dois hambúrgueres 150g, duplo cheddar, bacon, cebola caramelizada, molho da casa", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 5, "foto_id_principal": "1ybRL42WdaZrvAWftJDSTfhqCfeOQOT7z", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "64142b67-ba38-41fe-8e46-68213b65a342", "nome": "Picles Cheddar", "ativo": true, "destaque": false, "descricao": "1 Hambúrguer 150gr, Cheddar, Alface, Tomate, Cebola Roxa, Picles", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 6, "foto_id_principal": "1usHPUJkAcFX9kBBNtYDT1wMz_xYy6qXR", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "nome": "Texas Honey", "ativo": true, "destaque": false, "descricao": "1 Hambúrguer 150gr, Cheddar, Bacon, mostarda com mel, Pão Brioche", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 7, "foto_id_principal": "1sLP3nhi1aB3hTN8lh204YRRqoQf3DAtl", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "4014c744-53bc-4148-8fcf-0799918e88aa", "nome": "Cheddar", "ativo": true, "destaque": false, "descricao": "Pão Brioche, 1 Hambúrguer 150gr, Cheddar cremoso, Bacon, Cebola Caramelizada", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 9, "foto_id_principal": "1k9pwLeClQtkG7Rbk_2LtKoXNvLJzGSs3", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "65226aff-26be-4bbe-9222-62cd159ba207", "nome": "X Picanha", "ativo": true, "destaque": false, "descricao": "Pão Brioche, Hambúrguer 150gr de Picanha, Queijo, Rúcula, Tomate", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 10, "foto_id_principal": "1XAp01s7FPJzzMDvhrtW-VIqbgtbxh6tu", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "nome": "X Costela", "ativo": true, "destaque": false, "descricao": "Pão com Gergelim, Hambúrguer 150gr de Costela, Queijo, Rúcula, Tomate", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 11, "foto_id_principal": "1dMgFEq6tmX0uF8COlYoeo0gsUAM9bUf-", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "nome": "X Salada", "ativo": true, "destaque": false, "descricao": "Pão, hambúrguer 150g, presunto, queijo, tomate, alface", "categoria_id": "d4ec1678-47a4-4135-b9f3-fbb49b7f6e06", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1HIIOXWOSYv4TRTbYBVvMZnqPkdAJI9jL", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "nome": "X Burguer", "ativo": true, "destaque": false, "descricao": "Pão, hambúrguer 150g, presunto, queijo, tomate", "categoria_id": "d4ec1678-47a4-4135-b9f3-fbb49b7f6e06", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "1OEeJscM13vY0Dxcp-oxJz_IHnLgfOowx", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "nome": "X Bacon", "ativo": true, "destaque": false, "descricao": "Pão, hambúrguer 150g, bacon crocante, presunto, queijo, tomate, alface", "categoria_id": "d4ec1678-47a4-4135-b9f3-fbb49b7f6e06", "foto_preferida": "principal", "ordem_cardapio": 3, "foto_id_principal": "1Rx5_H9ln2RekCvkiaVcQabI2xrFwK5Eh", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "dca3fa98-20e5-487f-a479-5920c7783cab", "nome": "X Egg", "ativo": true, "destaque": false, "descricao": "Pão, hambúrguer 150g, dois ovos fritos, presunto, queijo, tomate, alface", "categoria_id": "d4ec1678-47a4-4135-b9f3-fbb49b7f6e06", "foto_preferida": "principal", "ordem_cardapio": 4, "foto_id_principal": "1N2LeFVzTczxJt8vhDkmqAcXfa4GUK16y", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "nome": "X Egg Bacon", "ativo": true, "destaque": false, "descricao": "Pão, hambúrguer 150g, dois ovos, bacon crocante, presunto, queijo, tomate, alface", "categoria_id": "d4ec1678-47a4-4135-b9f3-fbb49b7f6e06", "foto_preferida": "principal", "ordem_cardapio": 5, "foto_id_principal": "1Jn7XsRS_4yEwtJZn3c4KNDMcsVMn4NEI", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "60a58561-6800-44b4-8074-d70d035bb1a2", "nome": "X Tudo", "ativo": true, "destaque": false, "descricao": "Pão, hambúrguer 150g, bacon, salsicha, ovo, presunto, queijo, tomate, alface", "categoria_id": "d4ec1678-47a4-4135-b9f3-fbb49b7f6e06", "foto_preferida": "principal", "ordem_cardapio": 6, "foto_id_principal": "1pMPcOU9XoEMStOhXrtCpq9xp8QPr9EaO", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "nome": "X Tudo Especial", "ativo": true, "destaque": false, "descricao": "Pão, hambúrguer 150g, bacon, milho, salsicha, ovo, batata palha, catupiry, queijo, presunto, tomate", "categoria_id": "d4ec1678-47a4-4135-b9f3-fbb49b7f6e06", "foto_preferida": "principal", "ordem_cardapio": 7, "foto_id_principal": "1I0R8XIvO_64XezzKw45tz2uDgAHsYkX9", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "nome": "Frango Egg", "ativo": true, "destaque": false, "descricao": "Pão, 250g frango, ovo, queijo, alface, tomate", "categoria_id": "f9386fbd-44ce-4f5b-a6db-3f75bf5f757c", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1qNe7ytoI4MiwlM_o5co4zU5ysqlKc5QL", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "nome": "Frango Bacon", "ativo": true, "destaque": false, "descricao": "Pão, 250g frango crocante, bacon, queijo derretido, tomate, alface", "categoria_id": "f9386fbd-44ce-4f5b-a6db-3f75bf5f757c", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "1dzBZRkPisR3KQAXkP0cypnFMsS6ErI8W", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "nome": "Frango Catupiry", "ativo": true, "destaque": false, "descricao": "Pão, 250g frango, catupiry cremoso, queijo, alface, tomate", "categoria_id": "f9386fbd-44ce-4f5b-a6db-3f75bf5f757c", "foto_preferida": "principal", "ordem_cardapio": 3, "foto_id_principal": "1cHY-FrqZsCgcU_3ms14u3GKf1DafXuYH", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "nome": "Frango Bacon Catupiry", "ativo": true, "destaque": false, "descricao": "Pão, 250g frango, bacon crocante, catupiry cremoso, queijo, alface, tomate", "categoria_id": "f9386fbd-44ce-4f5b-a6db-3f75bf5f757c", "foto_preferida": "principal", "ordem_cardapio": 4, "foto_id_principal": "1ukZ_aJ8EtKWWqKNXSf8kiAagh-aAZFqq", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "nome": "Frango Cubano", "ativo": true, "destaque": false, "descricao": "Pão, 250g frango, milho, batata palha, catupiry cremoso, queijo, alface, tomate", "categoria_id": "f9386fbd-44ce-4f5b-a6db-3f75bf5f757c", "foto_preferida": "principal", "ordem_cardapio": 5, "foto_id_principal": "1rtd5hwUlMGmhw44d-YPDEGBmtky-_Jh7", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "43087961-297c-4b43-8ddd-1484188baab2", "nome": "Frango Salada", "ativo": true, "destaque": false, "descricao": "Pão macio, 250g frango, queijo derretido, tomate fresco, alface crocante", "categoria_id": "f9386fbd-44ce-4f5b-a6db-3f75bf5f757c", "foto_preferida": "principal", "ordem_cardapio": 6, "foto_id_principal": "1ibXsUY6lu88EaFYdSESlley2s5Mm0r6R", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "nome": "Churrasco Tudo", "ativo": true, "destaque": false, "descricao": "Carne suculenta, ingredientes completos", "categoria_id": "71faeb28-1e76-45a9-a64a-a84bb0f8ed01", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1FcCapQ4d3lTiKpjlZKcDJsICaErVS9qz", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "1658ebed-648f-4150-bf26-f50993a72243", "nome": "Fritas Simples", "ativo": true, "destaque": false, "descricao": "Batatas em palito, crocantes", "categoria_id": "9a732021-a144-477b-9831-9f33a85c5f30", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1CAgJ-RxM8cE1izxACN7OY6hxDgOkTs0b", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "nome": "Fritas 3 Queijos", "ativo": true, "destaque": false, "descricao": "Batata com mussarela, catupiry e cheddar", "categoria_id": "9a732021-a144-477b-9831-9f33a85c5f30", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "1THRYbwe3Caow1a8n39MDYWINrYaslN0v", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "nome": "Fritas C C B", "ativo": true, "destaque": false, "descricao": "Batata com cheddar cremoso, catupiry e bacon crocante", "categoria_id": "9a732021-a144-477b-9831-9f33a85c5f30", "foto_preferida": "principal", "ordem_cardapio": 3, "foto_id_principal": "15uSX4RUYIrUPrwgZrdVaKvgIKTRMoS76", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "nome": "Fritas Cheddar Bacon", "ativo": true, "destaque": false, "descricao": "Batata com cheddar cremoso e bacon crocante", "categoria_id": "9a732021-a144-477b-9831-9f33a85c5f30", "foto_preferida": "principal", "ordem_cardapio": 4, "foto_id_principal": "1-Kp-LShm0fcBsuWM8hh6GzxCBIq2yCGd", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "nome": "Fritas Especial Texas", "ativo": true, "destaque": false, "descricao": "Batata com carne, frango, catupiry, cheddar, bacon e mussarela", "categoria_id": "9a732021-a144-477b-9831-9f33a85c5f30", "foto_preferida": "principal", "ordem_cardapio": 5, "foto_id_principal": "1DRDNifTtf4RrTa-THW_jqY2gxqTwl4DE", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "nome": "Frango a Passarinho", "ativo": true, "destaque": false, "descricao": null, "categoria_id": "9a732021-a144-477b-9831-9f33a85c5f30", "foto_preferida": "principal", "ordem_cardapio": 6, "foto_id_principal": null, "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "5f5533e0-5760-4edd-a22d-9122097da388", "nome": "Batata Recheada Frango Bacon", "ativo": true, "destaque": false, "descricao": "Frango, bacon crocante, queijo, creme de leite, batata palha — 500g", "categoria_id": "70d82bfd-93a0-42c6-b784-4bd736f0cdbc", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1KfrYAoFBr8g-p8wDWgwHDN-9Bihn5V27", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "nome": "Batata Recheada Frango Cubano", "ativo": true, "destaque": false, "descricao": "Frango, bacon, milho, catupiry, queijo, batata palha — 500g", "categoria_id": "70d82bfd-93a0-42c6-b784-4bd736f0cdbc", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "1Q2rLBOvxWoCxsnhrq1sgUWqsDh45zB53", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "nome": "Batata Recheada Churrasco Cubano Contra Filé", "ativo": true, "destaque": false, "descricao": "Carne, bacon, milho, catupiry, queijo, batata palha — 500g", "categoria_id": "70d82bfd-93a0-42c6-b784-4bd736f0cdbc", "foto_preferida": "principal", "ordem_cardapio": 3, "foto_id_principal": "1a1hXtPnqURUwJl0iOryJChqnfiXehTpZ", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "5c9f187f-de24-4615-9042-78e1773e904b", "nome": "Batata Recheada Carne e Queijo Contra Filé", "ativo": true, "destaque": false, "descricao": "Carne suculenta, queijo derretido, batata palha — 500g", "categoria_id": "70d82bfd-93a0-42c6-b784-4bd736f0cdbc", "foto_preferida": "principal", "ordem_cardapio": 4, "foto_id_principal": "13cIQLF-kFtORkU62G8T0D2ov9mvzWW89", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "nome": "Batata Recheada Presunto e Queijo", "ativo": true, "destaque": false, "descricao": "Presunto, Catupiry, creme de leite, batata palha — 500g", "categoria_id": "70d82bfd-93a0-42c6-b784-4bd736f0cdbc", "foto_preferida": "principal", "ordem_cardapio": 5, "foto_id_principal": "1upy_7gC6pK6tJe-YO8aFcv4x6cK7RZqH", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "nome": "Batata Recheada Brócolis e Bacon", "ativo": true, "destaque": false, "descricao": "Brócolis frescos, bacon defumado, queijo, batata palha — 500g", "categoria_id": "70d82bfd-93a0-42c6-b784-4bd736f0cdbc", "foto_preferida": "principal", "ordem_cardapio": 6, "foto_id_principal": "1tuLsi7hYfwpMDv8C4cYpM25z9Sm2FYGP", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "nome": "Franguinho", "ativo": true, "destaque": false, "descricao": "Mini lanche frango empanado com queijo", "categoria_id": "c00a6047-f5a6-481e-8dd2-2e41b622854f", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1qMX-gGVQuq-68yLVLSCEjbVvQtqep7uK", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "86519e93-90e6-4174-b509-136cf9f43430", "nome": "Hamburguinho", "ativo": true, "destaque": false, "descricao": "Mini hambúrguer com queijo derretido", "categoria_id": "c00a6047-f5a6-481e-8dd2-2e41b622854f", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "1MraEirgXhQQjWf51pthK8NX6vhKLeZGb", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "nome": "Doguinho", "ativo": true, "destaque": false, "descricao": "Pão fofinho, salsicha, batata palha, ketchup, maionese", "categoria_id": "c00a6047-f5a6-481e-8dd2-2e41b622854f", "foto_preferida": "principal", "ordem_cardapio": 3, "foto_id_principal": "1PozA6pupVNjejKTosAywaAuhqeil7lmU", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "nome": "Coca Cola Lata 350ml", "ativo": true, "destaque": false, "descricao": null, "categoria_id": "83e31e11-3bae-40c8-a8c0-fb729b768581", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1VIaC_VNdkTrNkdGGBUZ2V_2DluIQnzgS", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": "d77e9f66-dc34-4636-ab5d-96fbb51b21fa"}, {"id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "nome": "Coca Cola Zero Lata 350ml", "ativo": true, "destaque": false, "descricao": null, "categoria_id": "83e31e11-3bae-40c8-a8c0-fb729b768581", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "1M5EXuRz3FvwkLRT94fsNopIezhFFz3LO", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": "52c73474-5488-4404-8887-65a706905f3e"}, {"id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "nome": "Coca Cola 1L", "ativo": true, "destaque": false, "descricao": null, "categoria_id": "83e31e11-3bae-40c8-a8c0-fb729b768581", "foto_preferida": "principal", "ordem_cardapio": 3, "foto_id_principal": "1aAoqO6LkwjCLUwNGtWoM8ucIotgKi4Ox", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": "0502d2f5-70c8-44f3-920b-ee10f22c8ef3"}, {"id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "nome": "Coca Cola Zero 1L", "ativo": true, "destaque": false, "descricao": null, "categoria_id": "83e31e11-3bae-40c8-a8c0-fb729b768581", "foto_preferida": "principal", "ordem_cardapio": 4, "foto_id_principal": "1dU3WbDn4CWPk6tsjV2ZrI87Km4Y8eC-2", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": "4d1aed3a-dd06-4519-bbf4-db2c174db59a"}, {"id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "nome": "Coca Cola 2L", "ativo": true, "destaque": false, "descricao": null, "categoria_id": "83e31e11-3bae-40c8-a8c0-fb729b768581", "foto_preferida": "principal", "ordem_cardapio": 5, "foto_id_principal": "1jV-S9IIkQuXnQ5nVs_ev5gchpVm4ocVp", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": "435cdc1d-1800-4d38-84ad-3ba22fc809eb"}, {"id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "nome": "Coca Cola Zero 2L", "ativo": true, "destaque": false, "descricao": null, "categoria_id": "83e31e11-3bae-40c8-a8c0-fb729b768581", "foto_preferida": "principal", "ordem_cardapio": 6, "foto_id_principal": "1ZE30p1_82-oHF7E8KI291Xw1wCA42hbR", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": "a00860db-8d18-4c79-af74-783b3025f6d3"}, {"id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "nome": "Nacho Dog Texas", "ativo": true, "destaque": false, "descricao": "Pão de cachorro-quente, salsicha, bacon, muito cheddar e cebola caramelizada", "categoria_id": "c1517d71-2845-4fd1-91e5-707c9e4d74ed", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "1iz9aQkSbJci10foup0NlQTLt859_Cl3L", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "nome": "The Master Dog", "ativo": true, "destaque": false, "descricao": "Pão de cachorro-quente, salsicha, bacon, molho especial, picles e cebola", "categoria_id": "c1517d71-2845-4fd1-91e5-707c9e4d74ed", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "1EStQi7J4ZVJFia8ttth6RJeATMPz43ok", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "nome": "Batata Recheada Frango Bacon e Catupiry", "ativo": true, "destaque": false, "descricao": "Frango, bacon, queijo, catupiry aveludado, creme de leite, palha — 500g", "categoria_id": "70d82bfd-93a0-42c6-b784-4bd736f0cdbc", "foto_preferida": "principal", "ordem_cardapio": 7, "foto_id_principal": "1ENBzff09seYkmpRi1ujkRk2cNHppl-ra", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}, {"id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "nome": "Catupiry Bacon", "ativo": true, "destaque": false, "descricao": "Pão Brioche, 1 Hambúrguer 150gr, Disco Catupiry 100gr, Bacon, Mussarela, Alface, Tomate", "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 8, "foto_id_principal": "1JSjDqCEs9W9-nyKuu4_clIswr81j8X48", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null, "estoque_proprio_ingrediente_id": null}]'::jsonb) ON CONFLICT DO NOTHING;

-- combos
INSERT INTO public.combos SELECT * FROM jsonb_populate_recordset(null::public.combos, '[{"id": "552e573e-f261-4008-a43a-a0346b4600ed", "nome": "Burguer Rustic Combo", "ativo": true, "destaque": false, "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 12, "foto_id_principal": "1aKYu05gRnXB3gKuWI6UdXqr3nTN9RUA5", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "nome": "Texas Honey Combo", "ativo": true, "destaque": false, "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 13, "foto_id_principal": "1rq-yMlsfrEbeZXB0Fz5FH-7k1pULLPQK", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "nome": "Duplo Cheddar Combo", "ativo": true, "destaque": false, "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 14, "foto_id_principal": "1aGunP7-M5FL3DfMWZ0uC_qViWmSDq0zi", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "89813212-c1e9-4cb5-ba73-065023280af1", "nome": "Barbecue Mister Combo", "ativo": true, "destaque": false, "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 15, "foto_id_principal": "110btYqF2V0gJgdjtZ7iEzUEGQekJ7jmS", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "nome": "Catupiry Bacon Combo", "ativo": true, "destaque": false, "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 16, "foto_id_principal": "1ppSBJlGbiGjDNVn64O-IErdBbsBxitMO", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "nome": "Onion Texas Combo", "ativo": true, "destaque": false, "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 17, "foto_id_principal": "1TBCQKsZpjJ2VgFnVn9rDrCaZOr0MmHmU", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "nome": "Cheddar Combo", "ativo": true, "destaque": false, "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 18, "foto_id_principal": "1C-p9bhgXzsRGDpkCLqdLUYE4NVWz9uKT", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "nome": "X Texas Combo", "ativo": true, "destaque": false, "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 19, "foto_id_principal": "1y02s9Jy8oR6Lai7517J_3AP5daXlm61Z", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "a6b948b0-4109-4c4c-831a-660cece144b6", "nome": "Picles Cheddar Combo", "ativo": true, "destaque": false, "categoria_id": "979f1174-1624-4773-be8a-45a38bf79f69", "foto_preferida": "principal", "ordem_cardapio": 20, "foto_id_principal": "1ZWPLe_pizlMPzoHr3SmLnfARkmOKGfQ_", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "658a1f7f-bd39-4e62-982b-cc42d09f2a86", "nome": "Combo Texas", "ativo": true, "destaque": false, "categoria_id": "b5e9987e-d8e3-4dd7-b0c8-814770bd33df", "foto_preferida": "principal", "ordem_cardapio": 1, "foto_id_principal": "15RmES_By-g3ylKNdatk9kpQdHtdyyQd7", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "d49ad88d-6fdf-4510-aa5f-c96ee9fd91d4", "nome": "Combo X Bacon", "ativo": true, "destaque": false, "categoria_id": "b5e9987e-d8e3-4dd7-b0c8-814770bd33df", "foto_preferida": "principal", "ordem_cardapio": 2, "foto_id_principal": "1fdS7fnDJxYbTE0zmvCi29rnq8yBp7nOI", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "3e6ff02c-6132-46b9-99a9-d5bba77d41c1", "nome": "Combo Salada Burguer", "ativo": true, "destaque": false, "categoria_id": "b5e9987e-d8e3-4dd7-b0c8-814770bd33df", "foto_preferida": "principal", "ordem_cardapio": 3, "foto_id_principal": "16s_RBJFnJyo_MhksvineSjFHGQNY8KDW", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "0afc8438-08ba-4566-9e12-12861531f393", "nome": "Duplo Tudo", "ativo": true, "destaque": false, "categoria_id": "b5e9987e-d8e3-4dd7-b0c8-814770bd33df", "foto_preferida": "principal", "ordem_cardapio": 4, "foto_id_principal": "133Wa_16Sx9czzP-9EUPsb0ttwkrgeZZf", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "9c5807ac-3f36-49ea-874f-8db5acd18b2c", "nome": "Cheddar em Dobro", "ativo": true, "destaque": false, "categoria_id": "b5e9987e-d8e3-4dd7-b0c8-814770bd33df", "foto_preferida": "principal", "ordem_cardapio": 5, "foto_id_principal": "19fYXq_GTIe2iEqnaP6lZQVasSRroS2rt", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}, {"id": "113c3645-508f-47f6-ae56-ff3bef65dcd0", "nome": "Dobro Burguer + Churros", "ativo": true, "destaque": false, "categoria_id": "b5e9987e-d8e3-4dd7-b0c8-814770bd33df", "foto_preferida": "principal", "ordem_cardapio": 6, "foto_id_principal": "1YeFeyiWqzJ9BJbtmg6_wm2vjCpQ1v8Xv", "foto_url_principal": null, "foto_id_contingencia": null, "foto_url_contingencia": null}]'::jsonb) ON CONFLICT DO NOTHING;

-- produto_precos
INSERT INTO public.produto_precos SELECT * FROM jsonb_populate_recordset(null::public.produto_precos, '[{"id": "5a3cd266-9d43-4b02-8ee1-56817a33c467", "custo": 0.00, "preco": 21.50, "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "f152e6ab-aa62-4e67-baea-4fd426374de1", "custo": 0.00, "preco": 21.50, "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "1b7b39ee-4bca-4ee1-9233-befe244456a4", "custo": 0.00, "preco": 16.00, "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "51e1ee6c-9910-4bb9-9b7e-1afdeda5d5a8", "custo": 0.00, "preco": 16.00, "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "e584f864-7762-46d9-ab2a-f349f743dd80", "custo": 0.00, "preco": 10.00, "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "08e79f70-604a-4507-8996-63881e8d6157", "custo": 0.00, "preco": 10.00, "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "609be250-e79f-4666-a571-83cffe82c668", "custo": 0.00, "preco": 6.00, "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "2e697973-9725-49c6-973f-7e48175247b1", "custo": 0.00, "preco": 6.00, "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "f2c6b367-4475-4d96-bea2-8091b465485f", "custo": 0.00, "preco": 17.00, "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "2f75970a-0e30-4318-9e74-1fb1fe1172f6", "custo": 0.00, "preco": 22.60, "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "309ea5a1-d7be-42d7-932c-044abbcad1d4", "custo": 0.00, "preco": 22.60, "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "78dca2dd-c972-42a1-9aff-a7a64b42fe56", "custo": 0.00, "preco": 36.00, "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "ad0f71ea-9992-4dda-8f9a-69e2663433a8", "custo": 0.00, "preco": 33.00, "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "ccc6e0ef-3105-436b-8d66-3917a19d47ca", "custo": 0.00, "preco": 50.85, "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "aca31cfe-9d88-43f2-a4d4-e5cfa9f506e8", "custo": 0.00, "preco": 50.85, "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "deeb7a4e-4eef-441b-a23d-b93feddb041f", "custo": 0.00, "preco": 41.70, "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "1a163d06-d0de-4205-89ae-e046a4482f35", "custo": 0.00, "preco": 38.30, "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "a8d54678-88c8-4b0a-a78c-6164d446b3b0", "custo": 0.00, "preco": 50.00, "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "60325e68-10d2-4022-8c57-125aa2a6810c", "custo": 0.00, "preco": 90.00, "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "aa292d71-961b-4cf1-bb5b-f4fc3b5ed8e5", "custo": 0.00, "preco": 67.80, "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "82522516-292b-4d51-814b-b04abdcc5a1f", "custo": 0.00, "preco": 67.80, "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "58937811-765c-4fd0-afb4-b43703b43fce", "custo": 0.00, "preco": 67.80, "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "9bc17854-0d84-40b7-82b0-b02d4476e3d4", "custo": 0.00, "preco": 34.00, "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "e4e3dd5f-4a8f-4c8c-b21f-8af456a2583c", "custo": 0.00, "preco": 50.85, "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "94420789-a1a5-4af6-b6c9-8411ca0b3c90", "custo": 0.00, "preco": 31.00, "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "d18c8e77-5558-424d-bc1b-0d0ef16309c4", "custo": 0.00, "preco": 41.70, "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "945785c9-7133-4713-b2fa-3a0a52449116", "custo": 0.00, "preco": 39.00, "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "b3f57033-787b-40dc-b147-9a628880377e", "custo": 0.00, "preco": 34.00, "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "8ad169af-63dd-4ef8-b5a9-a27411859c79", "custo": 0.00, "preco": 38.00, "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "082da509-b771-4137-9b20-dd7d6ab7a830", "custo": 0.00, "preco": 32.00, "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "22f5e4bf-1bad-4f06-974e-6271e885f5ed", "custo": 0.00, "preco": 45.00, "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "a331bb8c-ac47-4752-b1a3-132d58d5b9b0", "custo": 0.00, "preco": 39.55, "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "1f074f5a-96ce-409b-b98a-73e2f26b877b", "custo": 0.00, "preco": 39.55, "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "533dc9b7-48c6-4121-87d2-5a70b5d92835", "custo": 0.00, "preco": 31.65, "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "556f8a12-14fb-4e73-8441-94d68129cf67", "custo": 0.00, "preco": 36.00, "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "d5cdfb96-f265-4663-b900-c9bba485bc2c", "custo": 0.00, "preco": 28.25, "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "eee95358-fc18-468e-8160-9acaf2e26329", "custo": 0.00, "preco": 28.25, "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "921a8398-10c1-4d7b-a5ee-67b4c19843d6", "custo": 0.00, "preco": 38.30, "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "5b7e2401-0810-4020-9dcd-5f418e529e01", "custo": 0.00, "preco": 39.40, "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "3679779b-5b77-4428-af0a-0391c5ec2320", "custo": 0.00, "preco": 34.00, "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "e67ff5ab-6d66-4d7f-b0d7-59309d2a4a37", "custo": 0.00, "preco": 38.30, "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "b468ec3d-92c3-404a-ba24-5a06221056b7", "custo": 0.00, "preco": 36.00, "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "4ad09c01-05e5-431f-bd04-39bbc6848b19", "custo": 0.00, "preco": 48.40, "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "054364ef-d784-42dc-bac3-5da2c35514f8", "custo": 0.00, "preco": 36.00, "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "8c8a39b5-3262-4281-a2b4-66e52a4ee454", "custo": 0.00, "preco": 41.70, "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "0c0d3c4c-4fb1-41d9-8c55-cd548030f786", "custo": 0.00, "preco": 39.50, "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "f26cab93-3327-4253-ae5d-512af13bfcfe", "custo": 0.00, "preco": 38.30, "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "6c09d5df-1440-4ea0-8775-8d86c7d553cb", "custo": 0.00, "preco": 23.50, "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "b6c0ea8b-8797-4b4a-a06a-24f4e6a7b6e2", "custo": 0.00, "preco": 23.50, "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "79465cf4-360b-45d4-b1d9-801a4039fa6b", "custo": 0.00, "preco": 23.50, "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "8b4b2a51-411c-451c-9657-f13c569b67c6", "custo": 0.00, "preco": 21.50, "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "6b045881-16bf-4596-b2d5-af29bff323c9", "custo": 0.00, "preco": 21.50, "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "c3aefa9d-cbb4-48a4-831f-e0df0a007fad", "custo": 0.00, "preco": 16.00, "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "c23bfee0-0dbf-4fae-af9d-9ee85c95c48a", "custo": 0.00, "preco": 16.00, "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "a72fa154-9cf0-476f-b23c-f68fca7e5cba", "custo": 0.00, "preco": 10.00, "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "eb67aae2-d2f0-4e1b-954e-34f55ca29b9c", "custo": 0.00, "preco": 10.00, "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "28cd0c60-be91-4a05-b680-6ce34df8f517", "custo": 0.00, "preco": 6.00, "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "732b7fb9-cdfb-4cec-b3ee-b8bfd1e25892", "custo": 0.00, "preco": 6.00, "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "972937f0-a1ea-4d22-a7b7-37b9469ebc41", "custo": 0.00, "preco": 17.00, "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "09dbf00a-114a-4f33-83c7-c03b10fee31c", "custo": 0.00, "preco": 22.60, "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "772d51f8-a0bc-484e-bf97-ef93495e2f9c", "custo": 0.00, "preco": 22.60, "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "ccbc5352-d25f-434d-ba42-aaf0f8e82c10", "custo": 0.00, "preco": 36.00, "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "a752a6d0-938e-4cf2-b6b6-85dc4144fc13", "custo": 0.00, "preco": 33.00, "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "535fb8ba-85b6-4c5e-a330-97799cfe48b3", "custo": 0.00, "preco": 50.85, "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "c526a4f5-22b7-44d7-83e3-1c17f4035b70", "custo": 0.00, "preco": 50.85, "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "dcbcc3ba-9e47-4dba-bdf0-8c57c184971f", "custo": 0.00, "preco": 41.70, "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "fdec8450-4775-40c0-9929-f51955b9bdec", "custo": 0.00, "preco": 38.30, "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "c5bc1999-10fd-4bd4-9e84-cc0530e8ab6e", "custo": 0.00, "preco": 50.00, "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "fa6e56ee-3e2a-4031-b23d-98af421da479", "custo": 0.00, "preco": 90.00, "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "6c7ca0b9-5ee5-4051-a0b9-4b47e3dc06e3", "custo": 0.00, "preco": 67.80, "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "44c98aa9-8c54-4fac-b749-6f4cf85846e5", "custo": 0.00, "preco": 67.80, "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "3e4dc2ef-fb61-4dff-ba79-5b8746f6a284", "custo": 0.00, "preco": 67.80, "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "323308e8-d515-4d02-b9ee-cdab0d1722c5", "custo": 0.00, "preco": 34.00, "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "7b01fb48-a0c2-4286-8f3a-24fe2252a831", "custo": 0.00, "preco": 50.85, "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "cfaec2a3-46fa-44e4-ac16-d62d8db84d8d", "custo": 0.00, "preco": 31.00, "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "7bf9eed7-1127-49b9-8778-60bd8b76da71", "custo": 0.00, "preco": 41.70, "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "abea1712-f986-45a4-b14c-ceca80943f25", "custo": 0.00, "preco": 39.00, "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "bd9b4e49-5a29-4a6e-9513-f4541624461c", "custo": 0.00, "preco": 34.00, "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "80d19fdd-ed5b-4509-a928-3c68a66ad76e", "custo": 0.00, "preco": 38.00, "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "9bf57578-0504-4648-81cb-64fcf47ce519", "custo": 0.00, "preco": 32.00, "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "401226a6-19b1-4efb-ab00-0e2bfda11fcf", "custo": 0.00, "preco": 45.00, "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "b91054e3-0511-4e59-8934-6ceb23b7f1e5", "custo": 0.00, "preco": 39.55, "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "47cded56-c07c-4a7a-b7be-7a815dad5f55", "custo": 0.00, "preco": 39.55, "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "f933f5d5-8927-4763-833e-647f591d13f2", "custo": 0.00, "preco": 31.65, "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "dd64a520-8f2c-4abd-936c-f5d53a92c953", "custo": 0.00, "preco": 36.00, "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "4f913649-3feb-45fb-906e-b6a791efd41a", "custo": 0.00, "preco": 28.25, "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "d2fd2478-c887-4da0-bb9c-5ce724e86e1c", "custo": 0.00, "preco": 28.25, "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "1a0e301c-8e0f-419c-a757-860d9ad6464d", "custo": 0.00, "preco": 38.30, "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "ea8fe295-cd2e-475c-ad07-ef591d88552d", "custo": 0.00, "preco": 39.40, "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "8d3ec5e2-c73e-472f-b3a1-09ebd56a8b34", "custo": 0.00, "preco": 34.00, "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "040db079-36db-45e7-9670-4803dc408842", "custo": 0.00, "preco": 38.30, "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "2ea2f40a-da3e-4962-aa32-906309ef6d45", "custo": 0.00, "preco": 36.00, "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "38d578e4-d191-4a51-b27c-7266683d0ba0", "custo": 0.00, "preco": 48.40, "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "53141bdf-b4f6-49da-8073-5aadd7eb8d08", "custo": 0.00, "preco": 36.00, "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "933cd3e9-3d85-4961-b6f1-3c5e8a648598", "custo": 0.00, "preco": 41.70, "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "6f8079ee-5921-4916-a449-3e42be0cd5f4", "custo": 0.00, "preco": 39.50, "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "c52e77e7-b240-45c3-b80e-4e2f7c81d3a4", "custo": 0.00, "preco": 38.30, "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "55e5e74d-49a2-42ae-8ae1-0e8b565e1a93", "custo": 0.00, "preco": 23.50, "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "c5341e3b-4c77-4afb-b364-62f3fc2050c2", "custo": 0.00, "preco": 23.50, "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "8515c874-b132-4527-9df2-0a069559274a", "custo": 0.00, "preco": 23.50, "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "20bacd85-7472-4b5e-8e4b-14da1509418c", "custo": 0.00, "preco": 21.50, "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "f54644fc-f0b8-44fc-b0b9-f051975b8538", "custo": 0.00, "preco": 21.50, "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "08345556-b758-4005-8b41-d243395bc938", "custo": 0.00, "preco": 16.00, "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "acd87060-e2b9-4880-bc14-0d81c466e0b0", "custo": 0.00, "preco": 16.00, "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "e4d55def-4fe9-4698-88e7-d642ed5032c4", "custo": 0.00, "preco": 10.00, "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "29a4cad0-5bd9-4a73-bc68-e31ffe272950", "custo": 0.00, "preco": 10.00, "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "2c7b93ae-7fbe-4e62-b380-5c48e1e3240a", "custo": 0.00, "preco": 6.00, "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "e4b0f3f8-4968-44f9-8ecb-622a7f6bceb5", "custo": 0.00, "preco": 6.00, "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "b20da042-5168-4b20-a3ba-9e4f615a015b", "custo": 0.00, "preco": 17.00, "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "6249f45a-69d4-4f54-9574-24511bfc25db", "custo": 0.00, "preco": 22.60, "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "37e28ce9-7253-4eda-9f8a-8deb8a0bd5f2", "custo": 0.00, "preco": 22.60, "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "c9828324-b00e-4a1d-b21b-ddd328a0f1e8", "custo": 0.00, "preco": 36.00, "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "7392c11b-5e42-4632-8729-968ebd0c3e44", "custo": 0.00, "preco": 33.00, "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "9816fd72-bdf4-4166-a1ac-ddd02d6026af", "custo": 0.00, "preco": 50.85, "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "c97bb014-590d-498b-8c2e-cd0230ea2f3d", "custo": 0.00, "preco": 50.85, "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "1cd6585d-876d-4cb0-bcda-fe44d75fbc30", "custo": 0.00, "preco": 41.70, "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "d6ad367a-50c4-4c23-83d4-477e1ad1a598", "custo": 0.00, "preco": 38.30, "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "f478c421-3d69-49c0-b20f-119690b22e49", "custo": 0.00, "preco": 50.00, "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "278e3c65-5e0b-4edc-9ef6-82d571ff4115", "custo": 0.00, "preco": 90.00, "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "e5ef1236-737c-482d-a700-0e913f8009e5", "custo": 0.00, "preco": 67.80, "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "2e0dd756-00c1-4c2b-b40c-7a1d11a75fd4", "custo": 0.00, "preco": 67.80, "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "b594901c-c4a9-444b-9306-a4c7f79f50be", "custo": 0.00, "preco": 67.80, "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "7cd62a7f-1b8d-49d1-b243-0af2e475d72f", "custo": 0.00, "preco": 34.00, "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "d59ef051-717f-4787-b191-aaa2a66f789d", "custo": 0.00, "preco": 50.85, "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "d9322e2e-4429-4e6a-98c1-3c2389e6da30", "custo": 0.00, "preco": 31.00, "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "369fbe24-e55e-4eb4-b61e-ee6521c1904b", "custo": 0.00, "preco": 41.70, "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "911a4061-fe4b-481f-bf50-9a6ca7c2318f", "custo": 0.00, "preco": 39.00, "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "b3c72e81-1bf1-4fe4-a506-dd703e23738c", "custo": 0.00, "preco": 34.00, "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "42f74de9-f19d-4663-a8db-b1e98ab46a1c", "custo": 0.00, "preco": 38.00, "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "c8a3e11b-ba20-4da1-9f4a-0553eb14b8e8", "custo": 0.00, "preco": 32.00, "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "a60009cf-fb71-4e0b-ab34-af115d412ab8", "custo": 0.00, "preco": 45.00, "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "1a8140f1-f7b1-4999-a374-7debbe9aa1f2", "custo": 0.00, "preco": 39.55, "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "39b7473f-d832-4e5e-91b8-e4ff240e6600", "custo": 0.00, "preco": 39.55, "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "09f01908-3a6b-48d9-b4b7-cf2b333a9d0c", "custo": 0.00, "preco": 31.65, "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "40636ece-ff3f-4cd5-8fd0-2a6ccfe3836c", "custo": 0.00, "preco": 36.00, "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "293c582c-e21a-4d08-b5ca-c67232b49de2", "custo": 0.00, "preco": 28.25, "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "9485ad20-7967-44d9-86b7-8165731a603c", "custo": 0.00, "preco": 28.25, "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "ff98a3ec-2754-4ab1-b30a-6a3c06f73b66", "custo": 0.00, "preco": 38.30, "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "ec1f29dd-620a-49b9-a3b6-92dd81117713", "custo": 0.00, "preco": 39.40, "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "1ff241f8-4283-4217-82c3-202828d1ce3f", "custo": 0.00, "preco": 34.00, "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "c3dc716d-14be-4b4b-9b8a-620fe30e4c0e", "custo": 0.00, "preco": 38.30, "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "e9e81758-54bc-4cdd-ba27-a1fc179bd20e", "custo": 0.00, "preco": 36.00, "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "707f3738-1fa5-448b-b86d-e294bfe173bd", "custo": 0.00, "preco": 48.40, "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "f325fe4c-6fc9-42b5-ba5c-dfad9e9293c5", "custo": 0.00, "preco": 36.00, "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "80cbe7c2-4c29-4ec7-9812-599c2820a199", "custo": 0.00, "preco": 41.70, "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "19e7894c-c581-4443-930c-c238f664861e", "custo": 0.00, "preco": 39.50, "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "0e7a0c93-9e18-41c6-853d-9cea0861f387", "custo": 0.00, "preco": 38.30, "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "d3205b89-4547-4de8-8729-3430ec9c28eb", "custo": 0.00, "preco": 23.50, "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "5cc6484f-8329-4baf-bc70-aa6a520b30f7", "custo": 0.00, "preco": 23.50, "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "a11294b8-09a9-455d-8c72-584c71d837d2", "custo": 0.00, "preco": 23.50, "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "6a6f739c-3dc5-4a85-9968-d62c9a4da4d9", "custo": 0.00, "preco": 21.50, "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "a6509132-922e-4183-b3ba-422bed94cf5d", "custo": 0.00, "preco": 21.50, "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "01d9f45d-6c3d-44bc-9575-57f2006a5108", "custo": 0.00, "preco": 16.00, "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "9cb243dd-df51-46c6-90bf-b5fca4b84315", "custo": 0.00, "preco": 16.00, "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "fa1c5025-c290-4be3-b26f-4c8140bd7f5c", "custo": 0.00, "preco": 10.00, "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "f0a56f29-0d84-4578-9ea9-fdcf3771b8bb", "custo": 0.00, "preco": 10.00, "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "b78a91e6-68ed-4410-b1bf-399e9684f272", "custo": 0.00, "preco": 6.00, "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "fcc0f316-ebbe-46d0-b9fe-95839a7ddd35", "custo": 0.00, "preco": 6.00, "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "cd3fc252-3df2-4f29-829a-d233bdf9346b", "custo": 0.00, "preco": 17.00, "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "01d3b488-f5ca-404d-8055-60d61fbd608d", "custo": 0.00, "preco": 22.60, "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "3c0d9ccc-f1b7-4221-9d35-aa327dd6457b", "custo": 0.00, "preco": 22.60, "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "4aad0c4f-c1f8-42ab-b90d-cd724ff7217b", "custo": 0.00, "preco": 36.00, "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "f85c4b48-9369-420d-8cef-143a769b3edd", "custo": 0.00, "preco": 33.00, "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "dc258a7f-bec2-40e3-8b4e-2ec05260d52b", "custo": 0.00, "preco": 50.85, "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "524933c1-fd31-45c1-8f7f-adcbd9c30ba6", "custo": 0.00, "preco": 50.85, "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "90522a4d-6477-4342-ab49-d7e862156543", "custo": 0.00, "preco": 41.70, "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "21dee84a-70c3-4d65-8c4c-4c153dd8f7a2", "custo": 0.00, "preco": 38.30, "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "2c8723b3-4eac-40f4-a70a-f2a6ec435d5a", "custo": 0.00, "preco": 50.00, "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "00ec219f-6478-449d-be8b-d701296ead0a", "custo": 0.00, "preco": 90.00, "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "359663a0-fc95-4e35-b782-c7afc10d41ed", "custo": 0.00, "preco": 67.80, "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "6c98bb47-c47f-4c2b-b2f6-951b0b07c5e8", "custo": 0.00, "preco": 67.80, "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "93927324-3365-40d6-a06f-46fd53e7d8db", "custo": 0.00, "preco": 67.80, "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "14ec0c4e-eac7-444a-a867-3f68a69447a5", "custo": 0.00, "preco": 34.00, "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "8f279a19-baef-449a-922c-5200d25b7759", "custo": 0.00, "preco": 50.85, "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "765004b1-e2ca-46aa-93b2-b437c4e81950", "custo": 0.00, "preco": 31.00, "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "c8cdb088-fc48-4f61-ae56-3e12f03d18b9", "custo": 0.00, "preco": 41.70, "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "e6fd58cb-b5fc-4635-9c00-22a304b9cec3", "custo": 0.00, "preco": 39.00, "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "6e9a690f-9935-47a9-b762-9c1cb42fc4dc", "custo": 0.00, "preco": 34.00, "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "0185f96e-5387-456c-a6bb-35a327ae15a8", "custo": 0.00, "preco": 38.00, "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "581e6781-b6ce-4427-aa41-c87b123db3db", "custo": 0.00, "preco": 32.00, "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "19d2def6-ad45-4e4c-bb91-28302d44e5d6", "custo": 0.00, "preco": 45.00, "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "689eb4ad-2212-4394-8a6d-c531a3563345", "custo": 0.00, "preco": 39.55, "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "e2db535d-e80f-4dac-b176-468eeee3caeb", "custo": 0.00, "preco": 39.55, "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "fb1447c6-6719-4530-a448-e6a8b5e4882f", "custo": 0.00, "preco": 31.65, "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "6e93332d-0994-47f1-a01a-c1cae0f85ed2", "custo": 0.00, "preco": 36.00, "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "01883992-6145-41f0-a6cc-f4089f59ad50", "custo": 0.00, "preco": 28.25, "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "1653a4de-08d7-443c-80a7-bf2a11bfbff5", "custo": 0.00, "preco": 28.25, "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "fcaf89b6-89b0-45ca-ac85-b858ac7715fa", "custo": 0.00, "preco": 38.30, "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "ad8fe033-9e20-4e50-ac97-6fbdb6bf3368", "custo": 0.00, "preco": 39.40, "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "b7eb43fd-efbe-4780-8d6d-450168d641ae", "custo": 0.00, "preco": 34.00, "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "40bf48e5-d7fa-4d62-a8de-88b621d2f6e3", "custo": 0.00, "preco": 38.30, "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "8d4b4ce6-9b16-471a-aabe-3fd516f17c2b", "custo": 0.00, "preco": 36.00, "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "4328ab7e-a769-44ca-9ef3-a5f1d9b9aeaa", "custo": 0.00, "preco": 48.40, "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "bd0fd808-c5cf-4a80-ba81-b0b74160abb9", "custo": 0.00, "preco": 36.00, "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "05cff8eb-50ba-4318-8884-d662926415ee", "custo": 0.00, "preco": 41.70, "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "c43b268d-bc70-4630-9b1a-0b0bab52e8df", "custo": 0.00, "preco": 39.50, "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "a49dcc95-c043-4af2-b35a-1faf2339abc1", "custo": 0.00, "preco": 38.30, "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "79219cb6-b883-4876-a548-a03f3e4479b0", "custo": 0.00, "preco": 23.50, "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "fcc8a22e-9d97-4ff1-b1f6-d0bdc6c41d78", "custo": 0.00, "preco": 23.50, "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "65db12a1-85af-49e3-b865-8da788e4b1c5", "custo": 0.00, "preco": 23.50, "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "aa6fd4ee-46de-4a80-a1eb-3341ae52b07d", "custo": 0.00, "preco": 21.50, "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "ec063e2f-ad01-4054-a677-1770fc32f3c6", "custo": 0.00, "preco": 21.50, "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "675cda4b-2af7-41aa-a91e-c449ca83d7d6", "custo": 0.00, "preco": 16.00, "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "ae435c17-9774-488b-a165-116d2e8344f9", "custo": 0.00, "preco": 16.00, "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "b771554e-326c-4d3a-baee-7e79ae55c71f", "custo": 0.00, "preco": 10.00, "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "568f1099-d33b-4ebc-8ece-368675d438a6", "custo": 0.00, "preco": 10.00, "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "19e61884-f5ad-43ce-84ab-bf3e66536382", "custo": 0.00, "preco": 6.00, "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "5978d927-3cda-4395-9462-642b142cb1f4", "custo": 0.00, "preco": 6.00, "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "b5f83b2e-6d79-4b87-9e7d-6c816968f9c1", "custo": 0.00, "preco": 17.00, "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "d56d0fea-5bf6-4293-b199-f2697cb78133", "custo": 0.00, "preco": 22.60, "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "791f8590-bb5f-4527-9429-2f115e2eb3bd", "custo": 0.00, "preco": 22.60, "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "9c635f31-4899-4c36-a968-33e163934b60", "custo": 0.00, "preco": 36.00, "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "032d0f59-e5ec-4c3f-a799-f29627add92d", "custo": 0.00, "preco": 33.00, "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "2626e5af-929f-4a99-ac40-35c860fc1f43", "custo": 0.00, "preco": 50.85, "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "da081600-dd64-4b5c-82d8-2536a4dcb6e8", "custo": 0.00, "preco": 50.85, "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "559ec123-314a-4d48-b2ae-b7a312208fc6", "custo": 0.00, "preco": 41.70, "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "5524b7ff-f894-4279-8bdf-e0c7c6070723", "custo": 0.00, "preco": 38.30, "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "9fba9ab2-a5aa-420f-b4be-0a58f0db9360", "custo": 0.00, "preco": 50.00, "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "380ac361-7983-4aa1-8bc3-a31f900c70f2", "custo": 0.00, "preco": 90.00, "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "44147a93-e65b-4d0e-a30b-54da9dd3daa8", "custo": 0.00, "preco": 67.80, "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "bfefeb46-3626-429b-9127-ed648cc25364", "custo": 0.00, "preco": 67.80, "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "8d1b0f3d-bc75-4b7d-b5d5-481efb9f5e1f", "custo": 0.00, "preco": 67.80, "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "190d38d7-fddd-4529-8121-cf36551f1f66", "custo": 0.00, "preco": 34.00, "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "e5b6d3c6-510e-4cf8-9f04-980b6c686a7c", "custo": 0.00, "preco": 50.85, "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "9f4a4a73-7acd-47b7-a677-551f7775745b", "custo": 0.00, "preco": 31.00, "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "f634a8f0-2102-4a06-adcb-b689de4eb991", "custo": 0.00, "preco": 41.70, "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "6b4a9d58-99d3-43d5-a017-8b962a1c6f6f", "custo": 0.00, "preco": 39.00, "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "9fc3675f-d78e-47f9-8e64-ee13137990a5", "custo": 0.00, "preco": 34.00, "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "9222a703-6b46-4ac3-8f59-ebff4de429e7", "custo": 0.00, "preco": 38.00, "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "b41c75ce-05b8-476a-88e0-63d21d1491be", "custo": 0.00, "preco": 32.00, "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "d0fa28dc-adea-4a1e-be7e-0f2a357084cb", "custo": 0.00, "preco": 45.00, "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "1395fbcf-e09b-4bcb-9bf0-b943e12fe35e", "custo": 0.00, "preco": 39.55, "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "05e0f6db-7a5b-46b7-8460-95932b393663", "custo": 0.00, "preco": 39.55, "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "05bc0cd8-7da7-4619-a867-9cf7c8864cf9", "custo": 0.00, "preco": 31.65, "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "47496a6b-0e2d-466c-ad89-dfa1a42af3b6", "custo": 0.00, "preco": 36.00, "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "36dde6ea-bca3-4e0c-8df8-9d890710546b", "custo": 0.00, "preco": 28.25, "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "a7788bd9-a947-484c-895d-7803e01ebb35", "custo": 0.00, "preco": 28.25, "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "b2fdb9b4-3c1a-45f9-a0c1-389750d29f7a", "custo": 0.00, "preco": 38.30, "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "6ec96848-dbb6-4a6f-bbe2-dc39606a8628", "custo": 0.00, "preco": 39.40, "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "df01c3ac-8f3f-4278-98b5-4aa642639ad0", "custo": 0.00, "preco": 34.00, "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "9e026b25-cea4-46fa-82da-e49517371877", "custo": 0.00, "preco": 38.30, "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "1e8999e9-d5cc-480c-8e38-a6a985fa5a09", "custo": 0.00, "preco": 36.00, "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "424a0e07-f69f-4f8e-b536-07b71cdbf693", "custo": 0.00, "preco": 48.40, "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "83a7180d-801e-4054-848c-0c24c8b3d0a4", "custo": 0.00, "preco": 36.00, "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "d03910a4-6999-436f-b648-eb1c4d9a9705", "custo": 0.00, "preco": 41.70, "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "349257cd-9025-4724-951a-831e119dbe12", "custo": 0.00, "preco": 39.50, "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "f897b0e7-5e78-44e0-9860-51182e2276ea", "custo": 0.00, "preco": 38.30, "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "ea8bddd6-e182-4f0b-889f-26a42068f29d", "custo": 0.00, "preco": 23.50, "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "7f322f3e-80c6-41d5-9615-bb48a0724b74", "custo": 0.00, "preco": 23.50, "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "1bd7f6a9-61ed-4c10-a85d-2bf8c7002840", "custo": 0.00, "preco": 23.50, "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "c2a38cd3-1b64-4352-bad2-0ee6fbd6d6fe", "custo": 0.00, "preco": 22.90, "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "34918a96-cc71-4c10-ab8c-2617007d3a89", "custo": 0.00, "preco": 22.90, "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "15e9cb82-611c-42bc-a77c-013b35b273bb", "custo": 0.00, "preco": 19.00, "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "9b68d6c5-c6e3-4130-8d4a-aa68142e4203", "custo": 0.00, "preco": 19.00, "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "43ce09e7-8a4d-4125-90b1-586ac4ca5876", "custo": 0.00, "preco": 12.00, "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "74207a8a-5116-4aa4-aee0-b9a631261c0f", "custo": 0.00, "preco": 12.00, "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "fb1e9601-e639-4669-b001-175c2a988c21", "custo": 0.00, "preco": 7.50, "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "f2ce261c-d906-48e1-9b72-9bfe73c700a4", "custo": 0.00, "preco": 7.50, "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "4ae4dac1-900a-4746-9919-8a22ae86ec74", "custo": 0.00, "preco": 17.99, "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "e012032f-24ae-4677-a20b-80f36acd263a", "custo": 0.00, "preco": 23.99, "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "6a52589c-2fa4-47c1-8a84-94a494948384", "custo": 0.00, "preco": 23.99, "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "c66b2bd5-5afa-46b4-a6be-dac4c9ba63d8", "custo": 0.00, "preco": 38.00, "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "aff59093-034a-4fb1-8725-3b855048c4d0", "custo": 0.00, "preco": 35.00, "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "fde84c7e-a3df-4ba2-a056-bd83b3b90b8b", "custo": 0.00, "preco": 54.90, "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "f802d65e-a373-47f4-9f5b-d4dbce4dfa23", "custo": 0.00, "preco": 54.90, "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "bd7bfdf3-ac92-4db2-b0df-26aef9cd698d", "custo": 0.00, "preco": 45.00, "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "903e5bcd-419c-4eb6-b3d9-337a59d24072", "custo": 0.00, "preco": 41.00, "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "be49b0d6-4a18-4235-b16c-ee60d9851d47", "custo": 0.00, "preco": 50.00, "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "b106844f-0772-46d8-973d-88c288d75c78", "custo": 0.00, "preco": 95.90, "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "9cc3eef7-b7e5-4da7-8f77-98d68bad5816", "custo": 0.00, "preco": 71.90, "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "8d65a250-6bef-4ac6-a4b0-e6cf0ec4d976", "custo": 0.00, "preco": 71.90, "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "c8e54e73-4729-4ba8-9a69-f04c4532a44e", "custo": 0.00, "preco": 71.90, "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "418a60c9-9b8e-4e65-962d-74f4b237f57d", "custo": 0.00, "preco": 35.90, "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "684f9ed1-d73f-453f-bdbd-6180886ff6fd", "custo": 0.00, "preco": 53.90, "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "abfa2a5f-6030-4287-ae9d-03ebef753f14", "custo": 0.00, "preco": 32.90, "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "9f7ba2b1-358e-4968-b4fb-0cbbb78eb349", "custo": 0.00, "preco": 44.90, "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "29065452-c54f-4e0f-9763-4e887cf5a52b", "custo": 0.00, "preco": 41.90, "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "a96627bf-c63d-4f80-974e-f9b660105616", "custo": 0.00, "preco": 35.90, "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "34442323-d341-43f5-9938-439675a752d9", "custo": 0.00, "preco": 40.90, "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "5e5dad69-7af9-47e9-9450-b91cd8f3591b", "custo": 0.00, "preco": 33.90, "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "7035e674-d5d9-4915-a95c-d9672d38bcc7", "custo": 0.00, "preco": 47.90, "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "32859568-366c-4b07-8633-320d6346d541", "custo": 0.00, "preco": 41.90, "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "5e4020d4-5181-4ae2-897f-c0dd286b926a", "custo": 0.00, "preco": 39.90, "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "0ef78518-b71c-457e-b291-7ea06d36f124", "custo": 0.00, "preco": 33.90, "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "65789ffc-38c3-4cbc-80a8-f7f6ee1d9f8e", "custo": 0.00, "preco": 38.90, "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "eccebd0e-5a92-423c-9ac2-78b6f98cc7cb", "custo": 0.00, "preco": 29.90, "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "80800f0e-25eb-4bd8-b3d4-7bfbca1b8c6e", "custo": 0.00, "preco": 29.90, "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "90cc4c09-c1d1-4c05-b5e9-a034efa8b6d3", "custo": 0.00, "preco": 41.00, "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "3eb762d5-5d8a-469b-b71f-7075d023d48c", "custo": 0.00, "preco": 42.00, "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "09cc5920-981a-4478-9b0d-6417fbd0b19e", "custo": 0.00, "preco": 35.90, "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "ec3f42f0-2a53-445e-a2ea-6e4114d9897e", "custo": 0.00, "preco": 40.90, "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "5011aade-aedd-4548-8f87-8ea5089dc87b", "custo": 0.00, "preco": 38.90, "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "90918f49-8887-4d8e-8725-81eadcc9d12e", "custo": 0.00, "preco": 51.90, "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "461a4b04-322f-4ac9-af03-f8741f402507", "custo": 0.00, "preco": 38.90, "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "3bf08ed1-b1c3-4ffc-be99-29f4605d4419", "custo": 0.00, "preco": 44.90, "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "5c1e7e8d-a221-4731-bdbd-09e705860127", "custo": 0.00, "preco": 41.90, "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "0aaa4eab-5137-47fa-91fd-3f51bf36f6d1", "custo": 0.00, "preco": 40.90, "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "c03267d0-0319-4cec-b205-4bf0b287e552", "custo": 0.00, "preco": 24.90, "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "03b4662b-b3d3-4f2b-b1aa-1fc62cc1b5b4", "custo": 0.00, "preco": 24.90, "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "d5b99daf-f3c6-48f3-ae78-96b588f04b3d", "custo": 0.00, "preco": 24.90, "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "fe91bb34-32f3-420e-8c62-c45c3954fe62", "custo": 0.00, "preco": 41.00, "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "2bad62d3-b2bf-42d8-8c83-a8fed5c45b9a", "custo": 0.00, "preco": 41.00, "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "960dc662-4f34-4fce-8d69-596d269f497f", "custo": 0.00, "preco": 41.00, "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "f79b3477-dbc2-4068-baae-c27d408f8b0e", "custo": 0.00, "preco": 41.00, "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "3f4df15c-59db-48fe-958e-877ed648de5f", "custo": 0.00, "preco": 41.00, "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "d7ccbca4-2b85-467e-85a1-107bc6a00227", "custo": 0.00, "preco": 41.00, "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "13ab937e-9a2f-4953-a8cb-225113a9b1a9", "custo": 0.00, "preco": 45.00, "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "0ddf14b8-ab97-4183-a570-b65f3ba9d6dd", "custo": 0.00, "preco": 45.00, "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "aac859ea-2131-45e7-b255-93fafdaa8c3a", "custo": 0.00, "preco": 45.00, "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "8518eada-b8d0-41cc-855f-a0dde401c9b7", "custo": 0.00, "preco": 45.00, "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "b535a99f-3d10-40f2-b49a-e55bc9dae089", "custo": 0.00, "preco": 45.00, "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "ca95f221-f2c1-4389-8982-c703d55415cb", "custo": 0.00, "preco": 45.00, "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}]'::jsonb) ON CONFLICT DO NOTHING;

-- combo_precos
INSERT INTO public.combo_precos SELECT * FROM jsonb_populate_recordset(null::public.combo_precos, '[{"id": "47504365-2a95-4b85-b2cd-882b11bf8fa8", "custo": 0.00, "preco": 80.00, "combo_id": "113c3645-508f-47f6-ae56-ff3bef65dcd0", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "81891451-da27-4b73-9184-4fae46daf506", "custo": 0.00, "preco": 90.00, "combo_id": "9c5807ac-3f36-49ea-874f-8db5acd18b2c", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "1d05cd66-f76c-4d9f-bb13-b7ed81fd8dac", "custo": 0.00, "preco": 60.00, "combo_id": "0afc8438-08ba-4566-9e12-12861531f393", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "4c970bf8-9fcb-43b0-b610-6fa7c9583e2e", "custo": 0.00, "preco": 90.00, "combo_id": "3e6ff02c-6132-46b9-99a9-d5bba77d41c1", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "ecb44a5b-cba8-4c09-97e1-8226f6bd1f68", "custo": 0.00, "preco": 99.90, "combo_id": "d49ad88d-6fdf-4510-aa5f-c96ee9fd91d4", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "1d62382d-d467-4d1f-8dd8-6470b968541d", "custo": 0.00, "preco": 79.00, "combo_id": "658a1f7f-bd39-4e62-982b-cc42d09f2a86", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "b4769bc3-b2b1-4e7d-9a49-ebfbfce002d7", "custo": 0.00, "preco": 47.00, "combo_id": "a6b948b0-4109-4c4c-831a-660cece144b6", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "70f49920-400e-40be-a677-4fb1cbf3e5f1", "custo": 0.00, "preco": 47.00, "combo_id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "5c03aa48-c316-4c0d-adb9-511b7bd28f08", "custo": 0.00, "preco": 45.00, "combo_id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "559313d6-6804-4c3d-8b47-c3d8a9e4b098", "custo": 0.00, "preco": 52.00, "combo_id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "ad6b4b58-504c-4a7d-badf-8b3df29b45cb", "custo": 0.00, "preco": 56.40, "combo_id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "7113fa9a-d56c-4a9d-a2b9-4136ac3b1555", "custo": 0.00, "preco": 50.00, "combo_id": "89813212-c1e9-4cb5-ba73-065023280af1", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "eda55f0a-42bb-4a37-aae6-81b194ae2fec", "custo": 0.00, "preco": 59.80, "combo_id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "9e692d9b-636d-4bf6-9200-a9f7713bcc18", "custo": 0.00, "preco": 49.60, "combo_id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "c6f6e9d7-682a-4d8d-acb8-a8a87fca17fd", "custo": 0.00, "preco": 49.60, "combo_id": "552e573e-f261-4008-a43a-a0346b4600ed", "forma_pagamento_id": "49db43bc-75cc-49e6-a4f2-4cbab36c7e71"}, {"id": "0ce304bd-7297-43cb-8457-09ddfe88164f", "custo": 0.00, "preco": 80.00, "combo_id": "113c3645-508f-47f6-ae56-ff3bef65dcd0", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "fcd91b09-2d5f-4bd0-9029-e45428eae1e7", "custo": 0.00, "preco": 90.00, "combo_id": "9c5807ac-3f36-49ea-874f-8db5acd18b2c", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "bb1fcb31-664b-4f00-a772-503717ecb94d", "custo": 0.00, "preco": 60.00, "combo_id": "0afc8438-08ba-4566-9e12-12861531f393", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "7bef26a3-408c-415d-97f3-59b78b84f48a", "custo": 0.00, "preco": 90.00, "combo_id": "3e6ff02c-6132-46b9-99a9-d5bba77d41c1", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "4b3cc446-a08f-401f-8a16-f1ddc854affd", "custo": 0.00, "preco": 99.90, "combo_id": "d49ad88d-6fdf-4510-aa5f-c96ee9fd91d4", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "0d4f7890-c8d2-46a2-82f8-cb614f5912a9", "custo": 0.00, "preco": 79.00, "combo_id": "658a1f7f-bd39-4e62-982b-cc42d09f2a86", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "33bc89de-0ee7-4e91-b428-976463232a41", "custo": 0.00, "preco": 47.00, "combo_id": "a6b948b0-4109-4c4c-831a-660cece144b6", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "76426228-0e38-420f-aefa-09352cfbbf1e", "custo": 0.00, "preco": 47.00, "combo_id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "09b7e765-80cd-4cc0-bec3-e25d3b3c9658", "custo": 0.00, "preco": 45.00, "combo_id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "3bd5770d-2c80-4291-915c-d00ad51b4199", "custo": 0.00, "preco": 52.00, "combo_id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "e96be971-f38a-436f-9af8-50ac00148a0c", "custo": 0.00, "preco": 56.40, "combo_id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "19bdda30-0ea2-4d1c-8198-f251d218acdb", "custo": 0.00, "preco": 50.00, "combo_id": "89813212-c1e9-4cb5-ba73-065023280af1", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "6b321262-3fe4-443f-877a-29ca5d6edc3b", "custo": 0.00, "preco": 59.80, "combo_id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "35699aca-a49b-43cd-8cec-3ccaa28c9f99", "custo": 0.00, "preco": 49.60, "combo_id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "3e15c2df-5fcb-4af6-abde-cbc4adfd7794", "custo": 0.00, "preco": 49.60, "combo_id": "552e573e-f261-4008-a43a-a0346b4600ed", "forma_pagamento_id": "17b14f91-68d9-4a94-9374-c64846414581"}, {"id": "4992d90c-9d5a-4574-93d7-5ac26666c280", "custo": 0.00, "preco": 80.00, "combo_id": "113c3645-508f-47f6-ae56-ff3bef65dcd0", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "0afd2c36-616c-42bb-b5f4-a404f79061e4", "custo": 0.00, "preco": 90.00, "combo_id": "9c5807ac-3f36-49ea-874f-8db5acd18b2c", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "7f73079a-93f8-4949-919f-0afd716c86bf", "custo": 0.00, "preco": 60.00, "combo_id": "0afc8438-08ba-4566-9e12-12861531f393", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "f56e31ea-44bd-4860-8f6d-ff88c3847a48", "custo": 0.00, "preco": 90.00, "combo_id": "3e6ff02c-6132-46b9-99a9-d5bba77d41c1", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "85dc8784-1f2b-4b9b-a6d2-c694adce45f2", "custo": 0.00, "preco": 99.90, "combo_id": "d49ad88d-6fdf-4510-aa5f-c96ee9fd91d4", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "b0fd20c8-2cca-4c6b-aaf3-89e3816a8941", "custo": 0.00, "preco": 79.00, "combo_id": "658a1f7f-bd39-4e62-982b-cc42d09f2a86", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "83934a14-1c9a-4b80-a8b0-ad9d28ce5972", "custo": 0.00, "preco": 47.00, "combo_id": "a6b948b0-4109-4c4c-831a-660cece144b6", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "8b5eea05-20b4-4320-b65d-b49e2804867c", "custo": 0.00, "preco": 47.00, "combo_id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "670463e3-8a3b-4106-9d7d-3d2fa49a17b8", "custo": 0.00, "preco": 45.00, "combo_id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "4cb1999d-ab6d-449f-8668-bc9fedc64384", "custo": 0.00, "preco": 52.00, "combo_id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "c5d0d176-c2b1-4d64-918f-4aca56d3a9e6", "custo": 0.00, "preco": 56.40, "combo_id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "77f3174b-797d-4820-b579-6e9fabc71139", "custo": 0.00, "preco": 50.00, "combo_id": "89813212-c1e9-4cb5-ba73-065023280af1", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "eff012c0-a375-420c-8fd1-49c22ea1b471", "custo": 0.00, "preco": 59.80, "combo_id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "d88a017c-b954-4882-aa4c-962dc3fbb3bd", "custo": 0.00, "preco": 49.60, "combo_id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "09c28a24-8128-44a9-9b2b-b900d9c9d4f9", "custo": 0.00, "preco": 49.60, "combo_id": "552e573e-f261-4008-a43a-a0346b4600ed", "forma_pagamento_id": "19f2f926-8a9e-41a7-ba5f-2280b672950e"}, {"id": "772c8c0a-c4e7-47b9-ae64-4948f96f03ac", "custo": 0.00, "preco": 80.00, "combo_id": "113c3645-508f-47f6-ae56-ff3bef65dcd0", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "0db7917d-92a0-4534-969f-041c2e0fa832", "custo": 0.00, "preco": 90.00, "combo_id": "9c5807ac-3f36-49ea-874f-8db5acd18b2c", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "0569fa4c-d93a-44bb-8c90-2f533f8d5e3e", "custo": 0.00, "preco": 60.00, "combo_id": "0afc8438-08ba-4566-9e12-12861531f393", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "a5672b7d-5b8c-42be-8718-b60bb8501c17", "custo": 0.00, "preco": 90.00, "combo_id": "3e6ff02c-6132-46b9-99a9-d5bba77d41c1", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "ea7737e1-0e6a-4e7c-a560-bfdc33efaad6", "custo": 0.00, "preco": 99.90, "combo_id": "d49ad88d-6fdf-4510-aa5f-c96ee9fd91d4", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "176b8533-6652-4730-9a10-b86a79f434d7", "custo": 0.00, "preco": 79.00, "combo_id": "658a1f7f-bd39-4e62-982b-cc42d09f2a86", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "363a0bda-a346-4c61-9997-0b8ba1c13f98", "custo": 0.00, "preco": 47.00, "combo_id": "a6b948b0-4109-4c4c-831a-660cece144b6", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "59129440-4827-473d-9572-6aa240b5c38c", "custo": 0.00, "preco": 47.00, "combo_id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "3b999a40-48d6-479a-8223-a0b39ea8f586", "custo": 0.00, "preco": 45.00, "combo_id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "355bb131-38c1-4cdc-8381-8328ba991be6", "custo": 0.00, "preco": 52.00, "combo_id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "7941df41-01f0-405d-a5e9-49b2e75db335", "custo": 0.00, "preco": 56.40, "combo_id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "76e8b19f-aa7b-4887-8af7-05a09cc4ec39", "custo": 0.00, "preco": 50.00, "combo_id": "89813212-c1e9-4cb5-ba73-065023280af1", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "a1544f7e-176d-4100-a53f-20bb8cde1ee3", "custo": 0.00, "preco": 59.80, "combo_id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "1a661064-390b-4773-90bf-20c6edfdd6c8", "custo": 0.00, "preco": 49.60, "combo_id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "cfa68193-9342-44a3-867c-ee79d519bd83", "custo": 0.00, "preco": 49.60, "combo_id": "552e573e-f261-4008-a43a-a0346b4600ed", "forma_pagamento_id": "d0e73585-ca32-43f7-8051-8469cc6034ba"}, {"id": "75a2b874-f71a-469b-9757-8c59d5985485", "custo": 0.00, "preco": 80.00, "combo_id": "113c3645-508f-47f6-ae56-ff3bef65dcd0", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "64ccea8e-ba50-4a9f-bddc-31b37e3d2ed4", "custo": 0.00, "preco": 90.00, "combo_id": "9c5807ac-3f36-49ea-874f-8db5acd18b2c", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "a5b99059-97f3-4451-bd6a-06c25ad2655d", "custo": 0.00, "preco": 60.00, "combo_id": "0afc8438-08ba-4566-9e12-12861531f393", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "1e72b8ed-5f15-4c5d-94fb-4ea4442a7c2d", "custo": 0.00, "preco": 90.00, "combo_id": "3e6ff02c-6132-46b9-99a9-d5bba77d41c1", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "d5900b70-a42e-4123-a750-367d97f67e7a", "custo": 0.00, "preco": 99.90, "combo_id": "d49ad88d-6fdf-4510-aa5f-c96ee9fd91d4", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "976f696f-37a4-43ac-bdb9-dcd6e5197bc9", "custo": 0.00, "preco": 79.00, "combo_id": "658a1f7f-bd39-4e62-982b-cc42d09f2a86", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "b1e13a45-22c7-4827-b650-eb1fbc102a0c", "custo": 0.00, "preco": 47.00, "combo_id": "a6b948b0-4109-4c4c-831a-660cece144b6", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "4135b575-e0db-4a97-8a3f-86ad1864b735", "custo": 0.00, "preco": 47.00, "combo_id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "da329aa0-c718-411a-a9fe-ac0046e7acb9", "custo": 0.00, "preco": 45.00, "combo_id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "88afcdf5-d632-4059-a5f5-367ba37e169b", "custo": 0.00, "preco": 52.00, "combo_id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "25b195fd-ffe4-432e-8d27-24887dd020c8", "custo": 0.00, "preco": 56.40, "combo_id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "bc6ddd9c-d0e7-45f4-8183-7d82470a45b8", "custo": 0.00, "preco": 50.00, "combo_id": "89813212-c1e9-4cb5-ba73-065023280af1", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "bc16b0e9-be5b-47f2-be4c-1b9b8112f0be", "custo": 0.00, "preco": 59.80, "combo_id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "727edec4-d7cf-422e-9db6-5283ea56efb0", "custo": 0.00, "preco": 49.60, "combo_id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "4de6315e-b22c-4192-9639-ffc44df38d16", "custo": 0.00, "preco": 49.60, "combo_id": "552e573e-f261-4008-a43a-a0346b4600ed", "forma_pagamento_id": "212c5286-05f4-47aa-8c00-ed7968551e08"}, {"id": "7d3e508e-217f-4802-997a-ad38c55e0c2d", "custo": 0.00, "preco": 95.99, "combo_id": "113c3645-508f-47f6-ae56-ff3bef65dcd0", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "28cc4d39-2b87-49bc-b17a-14abd712b338", "custo": 0.00, "preco": 107.99, "combo_id": "9c5807ac-3f36-49ea-874f-8db5acd18b2c", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "22ac20f3-3644-4e42-8f3e-41376bb75c05", "custo": 0.00, "preco": 71.99, "combo_id": "0afc8438-08ba-4566-9e12-12861531f393", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "88bf7cff-0835-4203-abc6-02b246f41ccd", "custo": 0.00, "preco": 95.99, "combo_id": "3e6ff02c-6132-46b9-99a9-d5bba77d41c1", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "84095b79-584a-457f-921c-1e92f06c9870", "custo": 0.00, "preco": 107.99, "combo_id": "d49ad88d-6fdf-4510-aa5f-c96ee9fd91d4", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "15f90277-a04b-4bf2-8768-8c72b19237af", "custo": 0.00, "preco": 84.99, "combo_id": "658a1f7f-bd39-4e62-982b-cc42d09f2a86", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "149a0fc4-1343-4a59-9075-2a1f9da0d15d", "custo": 0.00, "preco": 49.90, "combo_id": "a6b948b0-4109-4c4c-831a-660cece144b6", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "b342bbac-a291-4932-a621-a26903b31e42", "custo": 0.00, "preco": 49.90, "combo_id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "1894793d-5397-4d44-b3ee-ed05f21dd3e8", "custo": 0.00, "preco": 47.90, "combo_id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "f465e2d4-e5af-4d3e-b6ec-5c62d0ff93ef", "custo": 0.00, "preco": 56.90, "combo_id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "5061c4b3-8037-4036-b987-2be4e5714695", "custo": 0.00, "preco": 59.90, "combo_id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "ef0e6087-6374-445b-a7dd-de6e01fd69ae", "custo": 0.00, "preco": 53.90, "combo_id": "89813212-c1e9-4cb5-ba73-065023280af1", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "9abc6b65-92f8-459a-8325-d7d880a605ce", "custo": 0.00, "preco": 63.90, "combo_id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "1649d7c2-3a14-415e-a03b-df7b6d9a2e1e", "custo": 0.00, "preco": 52.90, "combo_id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}, {"id": "3f3e8b81-120e-4563-a9e7-8fdcd2da916a", "custo": 0.00, "preco": 52.90, "combo_id": "552e573e-f261-4008-a43a-a0346b4600ed", "forma_pagamento_id": "21d76d26-8608-47b8-b387-1e9f5b150715"}]'::jsonb) ON CONFLICT DO NOTHING;

-- combo_itens
INSERT INTO public.combo_itens SELECT * FROM jsonb_populate_recordset(null::public.combo_itens, '[{"id": "2ac158a4-c9e0-4dbe-990f-9ea40ed412f2", "combo_id": "552e573e-f261-4008-a43a-a0346b4600ed", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "quantidade": 1}, {"id": "bf86f889-bc56-441c-8b52-596651649a48", "combo_id": "552e573e-f261-4008-a43a-a0346b4600ed", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "quantidade": 1}, {"id": "28ab027d-f312-4e8f-b6c9-7c3f7cebb1dd", "combo_id": "552e573e-f261-4008-a43a-a0346b4600ed", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "quantidade": 1}, {"id": "3846caf6-35d2-4486-b572-af292b857237", "combo_id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "quantidade": 1}, {"id": "b04cabe5-cde6-4f4e-88ee-40d2e4a90acd", "combo_id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "quantidade": 1}, {"id": "9ced3265-bb30-4cc1-b5c4-0050355bcf8f", "combo_id": "018041a9-0b05-463c-a2ee-84cb5f19c283", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "quantidade": 1}, {"id": "305ee417-f891-4d06-9064-c58ea9a87ad7", "combo_id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "quantidade": 1}, {"id": "5526e8a5-094d-43cb-b929-717a021faf75", "combo_id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "quantidade": 1}, {"id": "c569c345-b7d0-423c-8d0b-5269819dc0bf", "combo_id": "92a0d5b3-0757-4068-ab08-4751e8fcc9f9", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "quantidade": 1}, {"id": "58e249a5-d567-4a24-974c-3414d2b5468d", "combo_id": "89813212-c1e9-4cb5-ba73-065023280af1", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "quantidade": 1}, {"id": "88650a9a-07aa-4adc-bb1e-a807a9a93835", "combo_id": "89813212-c1e9-4cb5-ba73-065023280af1", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "quantidade": 1}, {"id": "51cbce92-55c1-41bd-83c5-1ab45de6dc34", "combo_id": "89813212-c1e9-4cb5-ba73-065023280af1", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "quantidade": 1}, {"id": "bcee07a8-311e-495f-b717-fbe3858a4d94", "combo_id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "quantidade": 1}, {"id": "20e2dccc-d1f4-44f8-b48f-b8fc3aecd371", "combo_id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "quantidade": 1}, {"id": "9c274e73-bb59-4968-be46-d40de100a2a2", "combo_id": "9fdec5ac-97ac-41b8-a203-bd4dd0d8f514", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "quantidade": 1}, {"id": "f0c6bb77-7634-4574-a56f-6f0b522a130d", "combo_id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "quantidade": 1}, {"id": "e3f5987e-d57e-4fa2-8e2a-3bcf1870db9f", "combo_id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "quantidade": 1}, {"id": "b14ef464-48f7-4443-b146-51e67562406b", "combo_id": "98eb2ce5-964e-410a-8791-44033cffdbb4", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "quantidade": 1}, {"id": "5b48201f-19d4-44f8-9079-759b1e8d8294", "combo_id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "quantidade": 1}, {"id": "25217790-4c36-405f-a6fe-90d709b4955c", "combo_id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "quantidade": 1}, {"id": "a9643a5b-436a-4caa-9b3d-50395238fcb7", "combo_id": "22d0c53b-2feb-48af-9e1f-6ae042f5700c", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "quantidade": 1}, {"id": "4bf0b276-b6fa-4d86-86b1-ca8ab8c624ad", "combo_id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "quantidade": 1}, {"id": "a5aa599c-b6e3-438b-a2e7-02e9788ffc52", "combo_id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "quantidade": 1}, {"id": "6e76c853-2fb1-47d8-8536-d1fe6afd3193", "combo_id": "4924d6fc-c2bd-4852-ab08-eda7edf6567a", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "quantidade": 1}, {"id": "04c82796-0811-43a9-bf65-67eee591cc45", "combo_id": "a6b948b0-4109-4c4c-831a-660cece144b6", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "quantidade": 1}, {"id": "3107f841-f72d-4a7a-979c-b9118eb53d20", "combo_id": "a6b948b0-4109-4c4c-831a-660cece144b6", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "quantidade": 1}, {"id": "af461816-8de2-410c-b2c1-a7664f486705", "combo_id": "a6b948b0-4109-4c4c-831a-660cece144b6", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "quantidade": 1}]'::jsonb) ON CONFLICT DO NOTHING;

-- produto_ingredientes
INSERT INTO public.produto_ingredientes SELECT * FROM jsonb_populate_recordset(null::public.produto_ingredientes, '[{"id": "8d603e19-3341-4b66-aad8-2d6718d52c2d", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "ingrediente_id": "d77e9f66-dc34-4636-ab5d-96fbb51b21fa", "quantidade_por_unidade": 1.000}, {"id": "f2ebbeea-4de8-45c8-88c1-81e7171027cc", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "ingrediente_id": "52c73474-5488-4404-8887-65a706905f3e", "quantidade_por_unidade": 1.000}, {"id": "d300817e-a313-44b4-942e-63183eab5f26", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "ingrediente_id": "0502d2f5-70c8-44f3-920b-ee10f22c8ef3", "quantidade_por_unidade": 1.000}, {"id": "01e52b29-c151-4c11-8dff-f02e5312b97b", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "ingrediente_id": "4d1aed3a-dd06-4519-bbf4-db2c174db59a", "quantidade_por_unidade": 1.000}, {"id": "c87f9667-9421-46f6-a06d-06d6167b84cd", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "ingrediente_id": "435cdc1d-1800-4d38-84ad-3ba22fc809eb", "quantidade_por_unidade": 1.000}, {"id": "b70869b1-b8cd-490e-9808-e90103962837", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "ingrediente_id": "a00860db-8d18-4c79-af74-783b3025f6d3", "quantidade_por_unidade": 1.000}]'::jsonb) ON CONFLICT DO NOTHING;

-- produto_adicionais
INSERT INTO public.produto_adicionais SELECT * FROM jsonb_populate_recordset(null::public.produto_adicionais, '[{"id": "6218c665-0fb9-4868-bbc4-809ecb00aade", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "8a05b230-a303-477d-850e-88569c168267", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "4392c5a3-976b-43f8-86d2-efc65f988c5a", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "33910c5f-e340-42d7-ac2e-3ca859c9cd9f", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "a9063ca3-ef7d-42e8-8295-22ced3655486", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "7beeda31-4007-4fdc-9188-831886b77a7b", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "d63bba9b-8932-4ed7-aa41-64b9c74a3ae0", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "dd3d37e4-ebc3-47c2-9b83-4ca65a76d56f", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "cbdc18e2-13e5-499b-8c2f-4206f6642ed0", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "746d0bc5-adb7-4beb-8e75-03502b44f859", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "ac65b79c-2a1b-4fce-9169-8a4b57d8545e", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "71848d3b-5edc-47c1-99cf-c4a0aa69b1d7", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "b9a13fd0-45c0-414c-b2f3-9f36792320b8", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "e16f7b0e-00a4-41d6-a09e-fc236da5c1c5", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "e5e8efd3-d448-418c-8550-d905ea5bf0b0", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "09f5de00-b999-4b27-b6ec-8771e3a75fb8", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "5f3c5498-4968-4f03-956e-646de7466809", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "e8ea7707-322a-44c8-951e-77c143db0790", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "7c204a19-f1ed-4fcb-8ce8-cf139b87c84d", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "f34d5569-55b4-4bda-8932-9544a8ab5831", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "edb431ed-3b4c-4928-bc3e-a3817d112fbf", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "9cdae160-0bb9-450c-84b1-fb1af457ba25", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "1de747b1-dc2f-4749-a39b-7265a1e110b3", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "a34dc4f1-80de-4dc1-ab24-3cf015ba3325", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "ae204bae-1b40-4a0f-a111-bb482936b85c", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "ad7db8eb-5614-4a53-a736-151b13da0a00", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "39f8cc6a-2bfb-4f40-bd93-015da2c63fe2", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "1791b88c-37e4-4e96-a92a-2026363023da", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "f827d2e5-3859-4672-b6f1-96ff0f7fc8ec", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "4ef3ff85-1330-400b-ad75-b84c8875357f", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "a216221e-a989-48d0-9fac-544af0b0d9bf", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "d2154410-612b-49ee-85f4-285a04167078", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "ddde5825-c4b8-476a-9cf0-5420b60c686e", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "04b3e84a-1120-468e-b914-78d8a5651182", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "4cdcf167-37fb-4ad9-8bd7-2b10dc708ae3", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "dcc5c305-81d3-4ee1-9747-17e1e7a07929", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "547b266d-8061-43a7-9226-503d567f90dd", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "7734c936-b024-4332-92a6-14a9b0f1ee2a", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "4c82f856-aac1-454f-9ebf-f0b25e81bf8a", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "aeb2dfad-fdea-4302-93c3-6abbc3369283", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "685635d5-247e-4e2b-8f5f-2e6765864d2b", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "4cac5714-9b2a-4d4b-a29f-c6042f36d7f8", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "8a713974-345c-4fe6-bb4c-911ba3fb408d", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "dd66f8ed-9a51-4295-9abf-406f0e414ee1", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "0aa4b979-8b45-44a9-96b0-92963d54e4ea", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "d925ea11-8699-4655-acf5-0bb15879a4c8", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "2b4d7411-e6ae-4738-9e3d-30597e0d1050", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "da1190b3-109e-4e38-b0b6-96937319a8a3", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "85e6bb9f-dab9-4a41-9480-c66fe4745d97", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "39a97d80-059f-4cb9-8ce0-739c44f46423", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "505fd45b-38b5-4152-a98a-9ceb949e5ec8", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "e7e7ad5f-08da-4cd0-a2e4-2b27adedb9e8", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "3f0b536f-09d5-42bc-8677-0766112b0762", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "988875e8-a191-4078-849a-891529256aed", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "02df0601-e65e-4545-b48c-c86afae44bf3", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "f4aa8d00-aef3-43c4-893d-bf06376c40db", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "8e6bf666-9b27-4caf-89f2-c35d36a6b1ad", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "1f80cfc7-4c33-4204-baf0-7a8897460458", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "ae4a53e3-fc83-4b7f-986c-9405d1481da0", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "abf6e404-b709-4f45-8a68-3edbfdfb4b57", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "fa317fdc-9388-407f-a008-a3bbed89a500", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "c9793f4c-6223-40cb-8cd3-2e029ecbbf7a", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "d30ee803-a039-4760-8eac-dfb1237f4109", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "b9174c21-9d9f-43e5-a09d-9eff406ad176", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "3d9b35b9-2f40-421d-8439-fe54fbaad85b", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "ddb3e2d9-c366-43da-bbb1-2d02795c7ccc", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "59abad45-8513-441e-8b77-535842921299", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "b9179b5b-c1fd-44f2-af66-2679a4f12244", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "6cd6aecd-8cd4-4b08-87fa-50486c52308f", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "9cfdd033-2c96-4056-ad43-1a905dc9c638", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "f4b55a25-5ae1-4c08-a01d-7912792a97c6", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "e8dee3d9-2893-44d9-a791-de86a6ff3a1a", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "a45438b8-ed84-4523-98db-52a9ba5e8639", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "9cfe2266-85f7-4bdc-821a-90b57fc1daf2", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "e8b9372b-bc96-454c-8b5d-355854e68891", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "dc580bb7-f2e3-4a68-9532-797097eee90a", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "4dd44a4f-1899-4bb1-8fe8-da36194058c7", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "f5d7d054-d736-4a0e-8209-ab55ec9329c1", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "09bf2f23-fb36-45f5-9a76-ae4b4cd7901b", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "aa33e1f7-e0ce-4179-ba62-fd4789e1c4ec", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "df297aa8-77df-4503-9f04-b51d96ee98e4", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "59ef9799-2f25-49fd-bab7-1a06f02bce34", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "8ce1dc0a-1044-4ab5-9355-e584d4854de2", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "a3390fc0-eb50-40dd-8ae3-8b50642bb412", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "649fab5f-49fb-4ae3-aced-ef25e0a31ea3", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "93aced72-97a9-4fcd-8f43-2c4668dadfcf", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "19521755-2443-4853-9c35-641f4bfb663e", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "8a997bad-38e1-4f77-a952-3ee4bb541bf7", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "0be50fa6-11f2-4822-9f9f-808f881e7581", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "f300d7d0-eb44-45a3-9bc6-3baa07c8a910", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "b3dc9d4b-a238-4da0-8610-708dd4787384", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "27f5b1b9-fc8a-4a93-b75f-d99a89d4b931", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "2571d825-3cd7-4981-9345-44fd62cd0a10", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "4c0f3da3-f937-42fc-84bb-272622185fca", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "90ef3cb2-9f99-4433-baca-62080f2160a3", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "16ebeeee-7f74-4383-a973-c7a2a1042381", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "90cbb4d9-6ffd-45a8-8337-a323222483ba", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "62f4c8ef-2dd2-4277-9d90-e59d910994ed", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "fffa82a6-09c9-4482-b6fc-3886f144057e", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "7e11259f-da10-4c5f-ada6-9e7d91705c7a", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "69156675-6b94-42e4-87f5-a13bb65bc26b", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "5a5b28cf-de46-47a7-aea2-36ff07304d7e", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "58053d75-1f6c-4cdb-b01e-a9e526bd783d", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "8b841712-f95f-4bac-b79e-67d6dd26c0f0", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "90fdd3bb-113e-43e9-980e-159e4334b828", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "d6550c34-01df-4978-a83f-46bf72523969", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "cb039433-7efb-4f12-aa1b-2a9f32023758", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "bd53fab6-de2b-4667-852d-bdaeef431d67", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "3c512ddf-d566-4175-8e33-3f57eae3f9d3", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "0ae54208-c61b-4dfd-8042-fea85d5dc4d2", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "07bbc3d8-59f1-4d6d-b434-190df11e8022", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "ac2b8dfe-7afa-40d1-b8cb-3340d2a6fa9d", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "52e03145-7b91-42d9-8908-72557603f163", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "cd90d85c-a300-436b-8af0-1cc3da922cd5", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "9a6ffccd-2649-493c-ac3b-83293ad35caf", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "99e93e80-be36-4a77-9725-295fb1d047f4", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "648e58cb-e177-4fcf-8abe-2084469d07fa", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "e55cb853-a432-4226-9a64-f9049d5f1f86", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "1bbc312f-f2e6-48b4-a88b-292ce27cb639", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "7f54f9dc-adb3-4f1f-976b-bbd7a1dcb472", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "afe7b44a-ae96-463b-8fac-6b9be112485b", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "eca6c532-57c0-4d39-b87b-153c6f86bd83", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "d4dcf614-20ee-4a4e-a868-12e05bae13a0", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "baab63aa-9d6f-4293-a67c-276b7e249c3b", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "1b70e146-9f84-4cc3-9da5-589d87ff322d", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "1017b1f0-c35d-45d4-ae7e-5307527c4c61", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "769c521f-a7e7-4c7a-94df-a182db78fd3e", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "df178a55-fe29-4b30-a612-55d193fce13d", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "fabd3dcc-e984-441b-a8f7-bedbc253ee1e", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "13f8de4d-8158-4455-98f8-780592fe3e55", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "feb168b1-3432-4ab3-9d7a-93582046a5f4", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "cca47d75-40f0-4c21-941c-34b8c3c749df", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "b68c7c5d-4692-4005-8ff1-90685969687c", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "73a2a611-10cf-4d39-bd6b-d77871bc32ae", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "e0588d52-62d7-4f23-87da-d7033ffc9243", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "1d00ec23-9f67-4e17-96cb-c32b000007cc", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "cb9d78cb-daf4-42b6-ae2c-48251ed5c56b", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "eef465af-7f05-4d73-8204-37568288d583", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "3801356f-b2be-4ba4-a4b0-476b030e8b12", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "ba78f90a-90a2-4fad-a783-d3a050b54841", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "d20845fe-3ade-454c-8163-40a978c01bd4", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "66799e42-2b1d-4ef4-b747-033576c83944", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "3ddb6d97-5582-43dc-98af-6576a1194413", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "4854c051-0fb2-4a4a-936e-40e33a065188", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "15f937bc-3749-484e-8177-fd60e1d77fbf", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "505acace-1ddc-4f66-8785-aeab20d63c50", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "5e64c018-e82c-4ed5-a991-f9f70c50e6ad", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "bc09ecbd-c5ae-40dd-b70f-101ffe1ee133", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "d7410590-dd61-4432-97d5-e16d3315c98e", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "ed798621-7162-4c70-9fab-f1a7f7f870d2", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "519cd0f3-35ee-4cc1-a6ff-88affce261bf", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "9d1cf2fd-f921-4ab6-9706-d14aabe9995f", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "1ec942a3-3564-4694-b6c9-8c0a2f9d898c", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "def69e3f-a8c2-47f0-bf2b-a73ff4b809f4", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "ef34dbc0-d11c-4fc7-94b8-c7bec37a665c", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "3bd9777e-901e-4ead-9cf5-7e415b5339dd", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "33b38e79-943d-4e58-904a-f57555e3ab19", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "1b8a139f-051d-463d-8e19-73733b77672c", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "e3c62c6a-6d52-4557-8cbc-870eab409090", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "8fe2ec8f-bcde-45c2-ac76-67b4567bae7d", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "c89b4300-19b6-4262-9b0e-431d5e33ae16", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "eb13c7b8-7fd3-4657-ab60-86f95022508d", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "c8a1e7e7-4a0f-4899-be87-10e962576d82", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "183fbfd1-f5c5-4673-879c-825d3dd6d24c", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "12df9228-ffa0-4442-9c48-6b953dbf0d05", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "ab45c5cd-5304-4227-8107-6e7475f4ec99", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "b37f5617-6caf-4df2-8c3d-37475bfd44d2", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "04c37020-4e74-4cd1-9a7c-75644175ca95", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "42f5ae41-e606-404e-92a8-c0a800c3b3f4", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "cbfda7d9-8873-449f-b52b-5e508de0b46f", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "68487461-7474-43a3-8d74-6a13a1efec20", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "ccd805b0-beee-4213-b812-09924db1c2cc", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "a49166b8-73e8-4b7c-b3d6-05632d917fd0", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "3926666d-0748-4b55-8e6c-db173b410e50", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "d14e0a29-0856-4bec-ab3c-c964a50b9ecc", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "01c9a785-e1b3-41b1-a705-9d395f73749b", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "d1978cef-cf65-4fc5-a523-1fc2848426e7", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "16f5d8b7-72e9-4336-ae4c-7793d76f3a25", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "00e7608e-b75d-4b84-8908-ce8b6997bb13", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "59880644-92d6-4470-92e1-39e30f353870", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "21e8015f-42fc-4dbd-bbc7-daa4208a04f5", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "d20144c4-37a2-47e5-ae05-1753a5ad7a8f", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "874af384-8278-4605-af48-4d994b36b421", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "76994b27-2def-4932-8267-f7e10bd4fd6b", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "c5eae900-e7c3-4eaa-b174-a7d548ac8934", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "8c462617-a3fd-4ff1-a30f-942dbdeb3375", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "6b9e5687-b918-4831-b6f7-1adc55d53c27", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "88518d24-4d03-4f49-ba9f-a70014ac2239", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "a779fbf9-546d-46eb-98a4-940e375eeb5e", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "cb049558-18d5-40e2-9710-a8d66e9614cb", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "6934d2b3-ac50-449a-b6f1-6db25877e61e", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "95ba2393-551f-4e35-aa5b-62a265fbe2b2", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "9043e24d-d5fa-4c39-a315-2b84490b4629", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "43356e64-b616-42d0-9933-6f183c5971bb", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "0fe6e63d-d364-4bac-842e-543553a9fea2", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "dbcf6691-98d3-4b8c-8cc3-e0567a9bfbcc", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "cb676004-f19c-4def-8f28-bb6fa3d4112a", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "de47a0a6-122d-44bb-b6ab-d6f7827de732", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "d7cf0210-aa2e-421f-b896-d94dcb499ec0", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "87810b0b-2efb-49cb-8342-530180e59ad3", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "02accfaa-f091-4019-b3f6-eec185d1d488", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "ff1c2ec8-55e5-475f-b3ae-f07e2fde13e0", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "8df2f6b6-f194-4e30-a422-cd1f19838621", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "64af12a1-a262-4a93-95da-1bf81f166a9b", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "1e39d3b2-7fa2-42b1-83ca-29ccb0d581c9", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "ab895c61-5668-484b-b055-3165dfa60913", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "4293e4e5-9362-426b-8061-964f56b5719c", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "fb1de191-3787-41e3-850a-6205c663cfab", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "0d4186da-865e-4830-b977-9d4e571540ec", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "010d5481-6931-4868-9279-01f36f8322a1", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "a2745d90-3af8-4167-ae31-7c2426c9f73a", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "92c7bf86-46ee-44e6-ae0d-79a28a849075", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "ac96570f-beae-4a76-aa7e-5855cdb54cae", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "1a1e04b4-e478-4016-bd42-cc740ea7f815", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "4f820fba-39c5-41b9-9eb8-e4b0214aff6b", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "f30f27b9-38f1-400c-9f9d-003ce0b97e25", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "1d4ebbdd-b8b8-4d7f-8c6e-9c0432888df4", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "1def3fdb-4993-41b5-86c6-7b00d0914b2d", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "33033a4b-6537-47dc-841a-712b2d10852e", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "3cdb3720-6917-4f82-876c-d6962d7a39f8", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "c01ca5ed-32d1-4a54-9133-9c45981cb87a", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "aca05d57-5900-4f5d-87f0-1ec70a6762a2", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "6147c088-d0f6-4551-adab-4de334a8cd86", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "44c162fb-65b2-42c2-80e4-8bd25fcfce64", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "eb564597-87f3-4068-8cdb-a609574a94ae", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "7dba7a1d-704f-4fcd-bdcc-76cc33c53c73", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "ec2a09e7-6ee6-449a-813e-8ebee7b0243b", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "d7ddbc2e-2bac-43c2-b8ff-b22eb279fe59", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "6c3d2651-1d2a-4e9c-be3b-8210c8e5821d", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "56779a86-d037-4b46-82fd-abe6bdc9e9be", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "ad3c52ff-cd8a-4ec9-a23a-01c1efe645d4", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "b14d23c8-c913-4f81-bb18-96028414fa6e", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "579fd438-f368-4a35-9248-223dae9c475c", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "10e7184d-ced1-45df-9c7f-f61d71884ac7", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "5b2bc3e8-4334-4783-8a3f-17c4e163bbba", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "762078bb-9a4f-4f90-b015-52d8e84f8b27", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "0f3d94d9-0302-4c4a-9c9d-f37389b6469b", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "1e527edd-b027-4f04-8d22-811300c6f2ee", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "c3b432cf-1f73-4b33-8a63-a32a060d42a7", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "cf5aa0b0-cf70-472b-83be-ee2231158f6f", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "3a13b7b0-9b84-40d6-9195-e1a75dfedbb2", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "3794ae62-20ec-42d3-a7d8-9bd99ecc1518", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "6c26d54e-b9c4-47af-a9fa-d63749e28477", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "137dca16-6e36-474b-8202-b6079b37850b", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "3d160320-3f2c-4d51-9f5f-39374013b2e7", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "4072bd35-376b-43b6-895c-33847af29b90", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "e5632192-f8ef-4a34-8aaa-f27c6d965a2b", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "6a065d39-44e3-413b-b898-57bef8a4da21", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "ff427395-3fca-4370-9909-c27a220a9200", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "346efcc6-0670-4ec6-b5fb-cf6a3e9f9bbd", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "ce39af60-fa6a-49d0-90d3-8620a2f9d340", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "fa02fe6b-fa26-45a8-b8a1-61b4cade5d2f", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "2f0a062c-2f29-4ab7-b0dc-1f59ed42492f", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "acd3bf9c-d0c1-4783-b7d5-34eb512d73a5", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "21bbeab9-19ca-49b3-8d8c-482af84ce188", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "bf0d7f64-8734-48b9-994b-7d25153ebd23", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "1b938f25-c809-45bc-8784-48f47e94f739", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "83347362-91cc-4f17-8359-4cd79af1058f", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "12f1ee6e-05ec-4c2a-9f34-faee2334ba6d", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "dc78dc01-f127-4c04-8688-8a72ef6be4ec", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "e65a29b7-766d-439b-9d12-782302bb3a9b", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "6c0fcd7a-d055-43a5-8663-c3e07dcb9c58", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "be988386-7a69-438f-a730-3f9635ce6852", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "c7f19dc7-9a91-41b1-af2c-6cff515a03ec", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "ca1d9e2f-58df-4ea0-801a-0061e04bfeb9", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "bd70ebaf-9532-4d40-a12f-026f7d81fbc9", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "55c2eb90-a8af-427f-813c-39a05075cff1", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "a905a63b-8882-4018-badb-202dc2880cfd", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "9370d02f-c72f-4cd7-af79-3bbf82f28377", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "309b0d08-2dc7-4d51-b837-cb9f7a69ade3", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "36764e1d-4ee7-4e0f-8398-6eaa174a0c48", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "06f1cb45-1024-46d0-be81-38162168db3c", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "11daa912-314b-4a33-bc84-40b821b8f9fa", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "80538740-b572-4622-a8c7-2357c5e52cbc", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "842b914c-8b9e-4545-8dde-8c42fde17e11", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "d51981d2-f0f6-4e41-95fc-175db47dd8bd", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "b6519b01-880a-4cd1-8500-bf67422885f8", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "9903c970-2d01-4842-bfc1-3b5a9f4af840", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "00dd0ebb-143d-40de-907d-14c68f3a2f25", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "829c34dd-10d4-4c80-9bf8-51a59c688c2a", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "bbabfdab-77d3-4c68-9c1c-0b3cdde8260e", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "5b064667-4f63-4997-9bed-baddd5d5b755", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "8f181e7e-e38d-4695-8b76-5041215d81a2", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "78a122a8-18e9-4701-9285-a448561ea329", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "48fb0c90-6206-44c2-83ff-52908c8a18af", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "4d1f10dc-aae1-49a8-81f3-2735261871f5", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "cb1c7506-503f-412e-af8f-2f2be68600b1", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "1523c63a-3d42-4a58-97f9-b8e9f725fe2e", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "e25b7371-ea5f-4a3a-92ae-3189704ab927", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "4781fbc8-838b-47ae-a7d3-32cb6bb68705", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "d524627c-0ab1-46ca-a98b-fe88d26c8502", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "3fee715d-36e3-4dc0-9f01-6ff5b6c301b0", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "071517db-6467-4458-8a7f-626b892a1e33", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "21cc46d1-ffde-4c4c-a9ae-c3e790c52b03", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "3238f1d0-7ff5-419b-a1eb-959bc108ed5b", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "d7d78d23-d5d5-4956-9347-9fd491289012", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "21ba7e96-75f5-4e28-a7fb-4cfd150ef0cb", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "5232d8cd-5ec2-40eb-b692-a61f370bf86a", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "ceaf31a4-cbb5-4453-b345-42cee1ea044d", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "e3f0e0a0-0311-4acd-a68d-4d55bf1cc73a", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "2822d371-cc9f-4be8-9441-cb13b5eda967", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "dedf1c1b-5f7a-45cc-9849-090cad6ac364", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "769fd641-6a47-4087-bd7f-1d3ee6d1f767", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "40c20619-81f5-4b4f-b828-fc7ec504e832", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "5c203782-c28b-4522-8dcd-c0fa6424bc28", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "ca97a949-569a-4ca9-a96d-49e7871a4bf9", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "bbda4e2e-4edb-462b-9c21-5edc5bec7b39", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "3666c035-b111-4cb4-a937-a2ed2220d287", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "fdba7312-0e79-493c-b6de-b87fc506a769", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "badaf600-8562-4c0b-b877-e9d1a0da7c8a", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "a7e35937-af18-45d3-b314-2685a36b866c", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "6c54b051-4005-4bf2-bf55-8597e5084afc", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "cb35b6cf-de56-4cbe-afd7-ce455bda509c", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "9561df3c-2ead-43be-964e-e6b83efac0b2", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "092ff40b-6544-498c-9c6e-b7780c785c02", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "fc468338-24a6-476d-9391-ec61347a92ca", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "8f9b9382-fcbd-4fe8-971e-d65b753fe85e", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "1258af1d-355e-4c7a-a406-5f9d8143b809", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "45d1dc7f-e3ae-4d3d-8afd-8e4f656015e4", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "f56273ff-73af-49a9-b2f6-4f45d7566c26", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "68877258-8a8c-4cfa-ba46-53d1711ef17b", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "15ff897c-cc02-4ff6-b929-bae293b85b67", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "559fc490-9d38-4283-9ae0-e40d23ad024d", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "d823dafd-6622-4ecb-a343-0f374cc9e37e", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "deb98079-ff20-4ee5-9aed-1772040b64cc", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "9335a7a8-59d5-4f6d-8d7b-b17577a617b7", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "63652936-a0eb-4731-bb47-584b7dd049ce", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "fe0656a7-3822-4197-bb09-7a14e8011bc4", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "1e2d2dc2-d586-4ef3-af5c-929dfb71e050", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "ecf691a8-f355-4132-9acc-7624f7965ea8", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "3d5432ac-e0d0-45be-a588-c62885be0139", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "f256e464-0e08-4fd2-b6dc-84617bb22b25", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "8f6ee51d-51a8-4f48-867b-f3577af1027b", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "c4a0d6a3-236a-49ee-948d-99d71198f6be", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "49190f81-9505-49a5-9591-0c4cd1af6d1f", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "9d48f8f4-8117-4d11-be11-2adfd75a65cf", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "97849dc7-9e78-4964-a3c3-09eb7c08ec44", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "b315d89b-7a16-4655-a2dc-b9b1f9ad4872", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "a740c3d6-5424-4057-8fc7-16ac09b41964", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "bd2c7d0d-e260-4844-9e18-12ab61703e33", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "71a1118d-b71e-488c-aad5-7d07dee0ab66", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "2efa2ef3-5d17-48b0-a7c4-57cc4893a926", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "bb889883-b94a-49e6-a2cf-499557d4c8bf", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "9a15feae-4005-4883-9459-fc6903c7c42a", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "71c17c17-c41b-4f9a-bf00-abce188ff51c", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "3f577936-3120-41fb-af90-c8d667d94da7", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "3ee74f80-fdd9-49c0-bfaf-be9368063e1b", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "86fce857-85db-4ab1-be6d-8b980fb0a070", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "2e367146-5f1f-46aa-956f-6a6937020d02", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "67c642ad-77f8-4f01-97da-9de6e9d1b4ab", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "4bcb658e-ff2d-4155-a43a-f7fcd25d5db5", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "bcfc3bff-2caf-4378-9498-5380f2377f13", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "a3f3410f-48ac-4ace-9684-344136558af1", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "dcf3528a-f772-46d4-af07-98ec86f57b1d", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "5c234cd9-ed69-4eb5-9c8b-23a9f5d9412d", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "50b858c8-6d40-463c-bbf6-5265b49a246b", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "ec4f51a5-ec35-4083-810d-bb6a7c6a3ef7", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "f5be1597-8425-4eb1-a479-f5e4526a17b1", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "d6a4fad0-43cf-4111-a475-25050fdfb04d", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "4eff5ed8-5b19-4bef-ad7b-2e3409d36238", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "9d3ee129-b6ad-4530-a305-a21dcace2886", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "34e7b7d9-c1aa-4d4e-ba35-f94797dbc1be", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "fce261cc-8c17-4fff-8a8c-684a45e88c1a", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "302f6cbc-f770-43b3-b36a-d1c6d576b15d", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "822e27ae-78f4-4546-bb2c-b9bf5a104420", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "e887219d-1d9c-4e9d-8245-e5349eac4ac6", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "4a814bb8-a03d-42a8-8d8b-3ac3fe92bdd6", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "7e76182d-e295-4158-a502-31d509263c46", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "ea2a1c60-1ccd-4289-87f4-64a358a733b0", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "ad5e7543-56ca-4563-a17c-6e97ad77e795", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "06a83176-c714-448e-896f-c55a216747a2", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "6af7bcd8-68cb-45af-8c8c-17df5e7f5c45", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "fa8d4307-8d78-423c-81a2-1cfa3df4c758", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "2ca4cb93-e6de-47e4-b176-f8d7bc183988", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "7aef71bc-b21c-484a-9acb-56c9aa15d2a3", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "51fb6727-5052-40bd-8d0c-b02090b3c7ea", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "7488da52-1fbc-4953-868f-8014283bb324", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "12973af9-c415-4937-882e-01dc8aeb48cd", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "7b692b7c-3b59-46cb-b95a-c37b59dfa7a6", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "7a1b2485-6fff-4186-a2b1-086cb7dc94b1", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "45239eed-cc9f-42da-a5af-343d4f886d0a", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "9eb94516-aa3c-4739-a35c-324c5eaea2db", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "bb199c99-de06-482a-859d-f13c4ba35496", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "00be0d0d-ab87-4b81-a254-f36336afbc8a", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "da865a10-2152-4458-9c6c-7f29775d8539", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "ad49c115-51e2-486e-9e93-1ae3f34c60ac", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "200528d9-d53d-47ad-9f29-ba3a44179292", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "58401fe0-8148-4051-bc6c-7c4c23159b1e", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "136c6806-b666-4fcc-8f43-40a180f33ec2", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "5b1cdfc5-8413-45a7-8f7f-d83943a8688c", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "1c7619fb-6adf-4f88-9a2f-cf6762f2fe8d", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "6538abb6-1d4e-4e4c-af3f-a94cb001132b", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "dba8d97f-93f4-460f-af93-3ab9ebbc4652", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "c4248df3-0f99-4fb8-9531-b164dbb37c5e", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "84c123e9-87a8-4603-ac07-2a96e6c0e9e4", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "04db756e-ba13-4397-a1b0-37a00407b68c", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "527139be-4c61-42fe-9c4b-fd1950dc8a1a", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "92ce17e0-a39f-4ac2-b440-bc1cbdafa8df", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "8fd4ca08-6c3a-4405-a3b8-f911d29281e6", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "f4dfa740-ad1a-4371-8383-d200968dc2a5", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "86a10fe4-c908-4c34-87b5-6c1cfbd71226", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "bb940e6c-5d63-403e-a6d1-1b01f43b6286", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "a9727f80-0857-440d-a8aa-7ff5d79f661e", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "cb32e49e-b59c-400d-bba8-635375936dcc", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "e81b0947-dea1-4a9e-b907-e3c3866b4551", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "72bae29d-4e45-401b-a2ae-d0171ffb4b71", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "b96781a3-3867-42b2-b144-9922b81eb506", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "4ffb1538-2163-4eb8-b3ac-d0e28c3b1f73", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "d1c59ca4-8a7f-4fea-ba41-bc3a8b08de83", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "1519b74e-22a5-47c0-8fff-a4b4979bd57b", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "450c69ea-b699-4dbc-94da-8e2f0a459564", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "a35fa4bd-ecac-4510-b5e6-0fb3b94e0635", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "ae374fbd-2b66-4cdf-ae95-8c84f2c9f898", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "45066074-1ecd-453d-88aa-8269b97b51ac", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "0cf45a19-e7d1-464d-b9da-0bf3a658b17a", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "87917d18-c9ce-448a-881f-19e200659172", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "0d6d525b-6dbe-44e7-a4b4-7879c74a3e45", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "c3e74c68-b5ea-412d-85ad-1f9de0cf9009", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "01b95b34-0474-4b85-b130-d46a6d4e2312", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "ab1a9264-2951-4fe3-8693-236c07ddf97c", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "e0e90c20-914e-4a40-bcd2-3dff66e288b6", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "d60da670-ca70-4652-b026-e87177c31dbe", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "3a5ddec3-bf92-4fda-ae72-de907144c848", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "fc3ce8e6-b8e7-42b1-b160-53bdecea555a", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "b18b02c3-6af1-4a34-a2d9-451e1cd10cb3", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "445c3aed-6f1d-4ffb-8a56-f326829a40b0", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "39b82998-09cc-4867-b4cf-324618496692", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "4cb5ebd0-d874-49ef-a90e-d09342a29c65", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "8c8e6d57-d8ec-4cca-bd43-4fb7e10ffd4d", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "91c23f1e-f64a-463c-8135-32333e8b15fa", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "4aa5afbd-1bdd-4c39-9fa6-7a4978697a80", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "784d0036-f550-4c4e-b806-4c023e540785", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "7ca87eb0-35d6-4b23-b8ff-2967b9acc00d", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "688974eb-5c3c-499d-b972-507146e96aea", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "e96615be-2e48-4feb-8014-66a03abddd97", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "f65d6da2-2e69-4cc6-84e2-252072180716", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "c164e128-50ef-43ee-a46f-7e4506492f8c", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "41766d5c-6f50-4c5d-b7e8-09722646c5e2", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "895b551f-815c-4af0-907a-8cb75b420679", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "7a6d1d19-86a7-4854-a079-656d41568cb0", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "7637346b-ebfa-445c-b618-a58f252b7fd7", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "35ce6895-545d-436a-b2b8-57d68232a87e", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "70a08536-00be-4c82-8912-d04d1e064671", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "1e685cfc-8cb1-4090-945b-89099e0183b8", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "62f6713c-2d6c-4cf9-a0bb-441555309166", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "78cb8d40-0aeb-4385-be76-c96e277147b9", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "76ae7a87-38a1-4333-b366-6cb75ce44c89", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "cb18d19c-1679-499f-b8d0-10df53df800e", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "2e69200a-f4e0-4ee4-a299-646cb55ea5c6", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "be6f5646-6423-4d93-846e-ac9eae7e67e5", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "bc46cb9e-396b-4783-ab42-534e1bfa5728", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "9ae80d1d-2668-4469-a789-36a59b6e0aa5", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "60a9de32-8da6-4e56-bad5-370b83c3ab48", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "b5f99e39-bf8d-402e-bf93-df705e7b4e68", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "326140ca-f9a1-401e-9343-d2de0f6b4de1", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "56c12404-a843-42d0-b74c-9b88ede1c4a7", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "8f7ea8cc-e915-4af8-8baf-bda90c1b1228", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "55dd2958-5df8-4460-ab0e-3e551a1425df", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "f2713c83-466a-45c8-b7df-f9e831791a78", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "3ff5290a-8dfc-44a3-afc3-2370995a0d92", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "2a1a2af8-303c-4a03-b740-74b5897f3400", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "82f99f0e-d39a-4403-a5e8-b906f76a515c", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "aeec09a8-e09f-412c-a8e9-c33549876e7a", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "d030dc6e-84bb-4370-86b6-0afa0784d549", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "156297ad-ad5c-4571-b02f-3f1f04a99143", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "38be4677-6851-4e13-9ad6-1240f09816e5", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "c3920f30-30c1-4fa6-8795-a21e4aaa5af1", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "5c71e569-8d51-4b9c-a4ef-7013a6f6e711", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "0733710e-862c-4a05-b652-5bc9aff788b4", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "0c8763c2-d732-46a5-9666-2d32f60fe1d5", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "93e919cc-9610-4d9a-a498-5b6356226ba8", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "335e48de-a1fb-486e-b402-204d1498b990", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "890dd29b-830f-4af7-88b6-e2a675f3b8f7", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "69900e61-55a2-4472-97cb-7eb4600eda70", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "e83eb768-c11e-4d8d-a94f-36fc0ba39ca6", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "09d90800-1f11-4567-b317-fc98aa2d4ec4", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "1bca7fb1-d0a7-4f9f-bbd1-df4b14c587e4", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "6a1f1344-1426-4871-aeb3-1fab39ca221a", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "3622f72f-803a-4b59-b19f-6d336926271d", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "43db23f5-51f1-4ea2-90b1-9b5ba75f9994", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "ec2eb72e-79d3-4528-8221-53dd8901a6ad", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "b9878083-9ef0-4c32-87cb-a2f90961d863", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "96c5b890-e16d-4830-9d09-a5041759dc73", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "36a3d4d4-9bc4-43f5-97f8-0eee6a079c67", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "f2ad4e58-ce52-4cbc-9610-ec436965efa0", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "c624a21f-fe44-4278-a546-7ae2ed2706f5", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "a3ca3a42-6615-4e2e-abd8-52c9314f8e31", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "cd9562da-9db2-4721-876e-b89683e35ec5", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "f01ab5fe-e2fa-4f83-887a-8a4f1aa89f83", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "c647b514-0199-4f2d-be76-0a7287b1f962", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "5aed7632-b2f8-4e2e-86db-21ebd998df89", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "103f7f54-15a2-456a-8351-da590ee6bd3a", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "5e5caf3a-19b9-4b6d-82d4-4cba9dc6c4af", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "ed9da13b-a549-4b29-8988-c91cf89d401b", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "33b088cc-b338-43cf-845d-f1a3b5a38c12", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "ca29d527-92bc-4faf-b834-6a87aee5df05", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "39ddbb47-78a2-44d2-9de7-5cf2e032f6cc", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "69e863bf-dfbc-43ae-b3f4-1c8a0c3ef406", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "a9184384-e8c1-4bfb-9406-5daa533d6a5f", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "8ddc7122-cbf1-467e-be2f-4d7ce6371478", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "c2a7ed40-211f-41d1-a9aa-f29b91f63a0f", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "dad09c62-c49f-4412-b936-cd58c42540a0", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "8554e263-87c6-45f8-a23b-f2720a9e2739", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "07c7e5e8-0619-497e-8df3-636fce1b8ebb", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "73a956b8-7039-485f-81ae-f6ba65953c32", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "e27cdb9d-61d7-41a5-a775-cff0373b2c4f", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "93674e65-c4c4-4d2a-b2b3-08d896c9074f", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "d621274c-ca90-476e-a6a3-589c751439ed", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "8d2d723d-2736-418c-828e-1907494441cd", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "011ccd46-4c2e-48cb-8d73-1b168bdfcbe9", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "e16af5e8-d58e-48f5-bc11-09b37c708c3f", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "0cda2875-7594-4744-af49-383d93ce99f7", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "547b3f4c-1a15-4a28-986f-e31e7fe4f446", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "21eb80a4-5c90-4108-b4c8-f21bc32f8003", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "dc251ac6-477c-43d5-b769-31cedf0519d4", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "e1629436-f710-42b7-bb3d-9d72b9342ce8", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "2c279de1-9775-4e80-819e-1f6811465dee", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "13a24577-41f1-4f78-b760-5c7ea0c81e55", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "012a9164-67c7-4b23-a2b7-4e1d9d37d59e", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "f831bc52-6eb9-4d8d-92e3-0e6c9e1f9d8a", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "ef0f65c5-154b-4cb0-ae77-b21e4282ac29", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "210523e8-8bb0-4e10-9cb6-2b92872d2607", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "82c1edf5-d95d-41c0-b36f-6839228403d4", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "112c88b3-db0f-47bc-ae98-d4c4b45de2f3", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "42d13a5e-486c-4648-bc9b-f4a1941e9c41", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "c638bbea-dbe0-4c81-9169-daf2643f6e21", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "eca38730-0fe2-4b5b-abfa-4f0cc906942f", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "55c6f698-3daf-4e52-8e27-e8c90ebe6268", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "14b33105-6106-4802-adff-9aa840b2edb2", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "1471c9f3-235a-45d7-8ba0-bb861fe65c4b", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "5b557318-e1a8-4dd7-8793-995a481d0ab8", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "2656afaf-cf13-4570-a32d-134b9cac0f86", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "2a14c26f-d672-489d-ae87-81db23cbb734", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "08562775-d273-4102-8e05-3814a969d6d9", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "34387db2-194a-418b-8de7-a0ea56f0a9c7", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "e966e144-3b1f-4dd2-a2c8-3ba7f3aa4d93", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "3fc76f73-f742-4c3b-9c92-dcac305ca961", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "bcecb7a7-bcc6-4cf8-a4eb-434cc1c748ea", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "0b5cca90-5266-4e38-ac5f-57510606157b", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "fa0d665f-c3c3-4601-b619-7b535152efc5", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "444086de-5cc6-499c-bc19-d899767c6942", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "99a23066-3da2-494e-bb42-60381c37402c", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "6f8361b3-00f4-47b2-b142-8b69d67eefa4", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "a6b8cf50-30ad-41d9-b6f4-eb68728d0ec7", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "43e39fb1-e07f-45dd-86ec-6e88483cec06", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "07dfad5b-4551-4b8f-b969-1fb455ef84be", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "882207c7-2931-4aac-b2aa-06a62d9492e5", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "d0a911a6-3c85-4834-8eba-fa00689365a8", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "ca67b4d9-17b5-43cf-8e49-9b6afdf7c14f", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "e12149de-5c3a-42ea-9575-49d0fbd10c83", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "3db4d9ea-cd2a-41cc-a137-f2613410b0a0", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "20511fe9-979a-4966-8cf7-53bd51e5585b", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "4a737c8d-8e5f-4df5-ac53-975de1da4a22", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "4203ef70-ad7c-489a-91ed-6e9a5469be0c", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "670556bf-3e2d-4042-9eb2-b9e5f124af4f", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "d2515a79-f3c9-4333-94bc-ce13eb5fe264", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "978cf0f3-1e86-4f22-9f4d-b600aab589e5", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "eec3262d-9ee3-4cac-a76c-5aba4661c137", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "48b528c7-c657-4f9f-94d1-f219a1a19418", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "c7b503b5-b76f-42c6-8e6b-ee7061b2fbfe", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "2910ea7c-a50e-4386-b051-e8b92c9c0977", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "1b840c1b-d266-44dd-af1d-88cdca4be317", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "67d94a64-533c-4e83-aad6-4d6b2338ccc1", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "11a6863c-9255-465a-96c3-57ebb988099e", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "50c02066-8a35-46bb-9901-266b666db7c1", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "09490edd-5670-4046-bf22-84eeecfff911", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "a7768fd1-e15d-40e3-b386-29d98d0222db", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "67530680-e9c0-4526-a9fd-93bc13c98baa", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "004d78d6-bb4c-406d-bb15-a64a9c9c54b2", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "e0c7af8a-0d42-4d41-b5cd-88607728ef90", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "6d0fee21-a4bd-41d7-af9c-cf7ebece766c", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "4d144371-bf75-4ae6-b4c4-473e31614a6a", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "a88d2788-cd4d-458c-bdb5-767d44f277d7", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "244e67d5-3149-4d21-b6c2-758c1873dc1e", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "a18c077e-3c56-498f-b10a-fd33e154e884", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "5fe81d11-5e8a-4712-98da-e44638c8164b", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "366c475d-64dc-4d34-aaa4-59af5bfc36e8", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "7c2b3070-c479-42f7-bcc1-0565aab0b630", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "33b881e0-3c8a-462f-8d6b-02107074ec38", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "2b443d2c-a2a0-4da7-9ca6-81df92811680", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "5f2a719f-c64c-4d88-a2c9-84734700f846", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "793d0fcb-f77c-4557-a74e-e8e548f53620", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "a546a1fd-b794-49b0-b563-fa51dc6077d8", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "8cff109a-f763-45cf-bfe6-12e1c1c8224a", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "fad71614-de09-4532-a0ab-fbc60075840f", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "a5ff3d9a-91d2-46b7-89a5-a60bce4261af", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "6eb97e88-6b65-4f75-88f0-7ac9c0718a87", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "659e1fde-d59d-4f24-99f9-236bb712a419", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "2969ad63-b1e2-4b9f-8a00-e8e2a5b65e7f", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "377d3c40-44a8-48f6-9622-bd25263dc603", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "85555495-3b89-4067-89f8-761ff41b5f3a", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "790674dc-f79f-40bb-ac89-2bd84ea8a214", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "9c1415fd-9594-4239-be15-c057d0255409", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "7c882cf0-6f52-4a98-8094-8f3900d300ff", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "d27b4a86-4474-4556-804e-5a3aeedba5bd", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "055493dd-ed02-41e2-b626-763093b5abf8", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "345f3ad9-13da-42f4-86a3-b431772c207e", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "d5688544-481a-4076-ade9-05ff1f36df42", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "d23367f4-1405-4ba2-bf94-70e107140265", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "a6bf1e2b-f4e5-4aff-99b2-a7c1e6388ba7", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "57645406-ce00-40ff-bf81-7fea2cf87e73", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "19ff2e6d-7824-4e5b-9926-d16f1a5c9783", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "d6feec56-6159-4756-861e-9c7a8f18411d", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "ad7fb344-44fd-41db-8f66-e4970b0bf924", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "277c1d94-fe1e-4c3b-9f16-c8a7ce22ed21", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "6b67ce96-8b7d-4d1a-9bae-20ddf980659a", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "c006c9f2-a83b-4d00-a734-75ecec1f7378", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "d218103d-2f5a-414f-9a5f-82ff16bb74ea", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "2791d99d-3836-473c-87cb-782344920c6d", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "cee7d608-181a-446e-a513-8f74b7796d27", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "d4f086d6-10db-4dcb-baa0-9b1bf5b859f0", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "b69d7d8d-a95d-4284-b08f-ddd30aa6f6a3", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "a0794522-92d6-470f-b395-e0aac5d5125f", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "ed44076d-b34f-4ab0-a097-9ba3560fc58b", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "dd0c6ce4-9d89-4732-8dfb-119c8823f1b2", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "3fbf664a-664a-4fca-b149-b34d4165afa6", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "061e9306-d73c-4562-bef4-5651cf9ea019", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "47fc76e2-9f85-45b9-8fd1-f24139f3034e", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "6bbc4c5f-1b35-44f4-999c-f00e51dd2028", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "e78892b4-59bc-4bf9-bb13-959c4fbc3040", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "975893a3-a236-4ad3-8de4-3580168c8d90", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "5fc99a8e-2940-4f76-8ef9-a274c0ba5aa3", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "137ceb98-65f4-48ab-a19a-e93d015b0396", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "c010e51e-4f63-47dc-8f04-88312c0c142f", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "3fb8e36b-100c-4dfb-aa2d-ef5b8abfdc34", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "6bb00f5b-2d1a-4239-988e-658cf928f51d", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "c23f165f-ee0d-49cc-8e45-c67293e9a1cb", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "b12f87ba-ab97-4599-be22-2ada1ec164b5", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "e3596d58-d180-40b9-933d-dd970f9b6821", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "ffd3387a-5e08-4e24-8c4e-1a38b1f33ccf", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "4fd0e6a6-edbb-4129-9ee1-0a990b50a016", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "fdb9d895-2aa0-4a5c-8ea8-161b6b2bb73f", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "0093a1c0-8e6a-4591-815d-0e05d8678ea9", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "b7f8253a-d2a2-4b3d-9029-8b8ff1d572dd", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "bff896f3-705b-4a12-92fd-37a5fb2cd01a", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "d5db737c-4ff5-4a16-bd43-433e02ceacc8", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "b10ebb1b-ab22-4200-a461-8b2bd33c04cf", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "359f06bc-d87e-4ca5-9c7a-0e094e49ae1a", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "8e76ced2-d6a3-40c1-9799-60ec776a192d", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "45caa8bf-fc91-4132-866e-83bc462f4f1e", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "a3a71bf2-7dd9-4aa2-8247-148126ab2916", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "58ededa9-261c-49b2-be13-fdfd4fd62392", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "9e24a107-bdd0-4fbc-bf21-7a46bfc059cb", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "5bfc2599-1e46-491a-90a9-936c32c8597e", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "c974929a-9334-40c4-b100-8c32c70a06f5", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "c26a6cd7-0750-4226-85b7-f9b4fa772abb", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "b33e990b-5e56-4ceb-9d9a-a033ea6b8f00", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "becfa9fc-3704-44db-b7ec-fb1dfdae4ee3", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "b575a27d-486d-431c-8235-1e13fe5b4b77", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "d9e3aa20-bda2-4198-8a83-38741bae3bcf", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "9f9a9c10-3db0-4d0f-a7a3-d19d8557c80a", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "f99ce98d-ee8c-4a84-a949-ef338d0e56c6", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "68b2ab45-ae41-4156-9b0b-51c381545e48", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "bef69d94-3a85-4c9b-b0c2-485bad991d18", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "deb03212-251d-4a29-9f43-77c9486d61ad", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "84771d47-ea99-4b60-a035-535e4e9d0e73", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "fa8e712a-7240-4eef-a31d-9b775ca5c04e", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "0de0b9ce-44a6-4739-b1c5-f0a0b7ff51be", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "a7db0bb3-9105-4101-8f8d-ca08cc777043", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "f693b635-1375-4a28-8f9f-ae54e1f02c82", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "7258bbf4-c515-4c54-a36f-fd515b97f66a", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "6bd96828-6e3d-4260-bf60-704d39641c7e", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "b239b78c-5918-4b44-b8af-464be0c130d5", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "cca3061c-27b0-4f9c-9a69-70eff43dec07", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "6cb174a4-47ad-4ac2-b08d-04018e0982d0", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "8b18e50c-0f22-4896-bf6c-2f3c23d3f972", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "7db3f2fa-3899-4c3b-91c4-73605d07ec96", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "0149cd77-853d-4377-aad2-8ff75cb40560", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "1048a526-9e24-42c7-8e90-8d4929d670ba", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "335ac5d3-1999-400c-a281-f180294198e7", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "5406980b-adba-4369-8766-3cb671ac91ae", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "45f38dcd-ac2e-4362-a925-07bec940593e", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "f316f09f-18ba-4c28-82a0-31a9b44e9e6b", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "847cfcb9-e55e-4323-a4bb-409cd7b5b424", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "f84d522a-7285-48f4-8114-e3a472b07bd4", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "90102ecd-1f5e-4a7d-8c81-d83e81a29319", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "d3d24ced-2697-48d5-946f-54005150362d", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "8ae6e6b9-6126-4706-8131-d30d949e2534", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "8bfda7e5-c602-4b4a-b2f0-72892fca0eae", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "30553ec7-8141-4e53-9186-0d2086b34f8b", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "8faecf94-2e9a-4463-b3c5-9066eee79bdc", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "19eda525-3e87-4d08-b2cb-4838cf026e67", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "3064b009-c058-4585-b462-a6146e76e303", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "7f0250f5-00b6-48d6-a343-7bf7862c2798", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "55bf457a-6084-4290-a913-b984d2b80477", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "b1e5e4c8-e3f8-407d-adb5-31dfcb71024a", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "7bc2eeac-fed4-4117-abb1-743b780a3c79", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "cf5b5be4-4b5a-427e-9794-d71b8539e0ea", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "03fe7b38-a1e6-4eaf-ab60-37d0c20cd376", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "5e96c997-5c94-441e-aee9-b5a28dc07e7e", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "a400225e-964d-454d-b29d-808b15bd7217", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "d87d8ebc-56d4-4dd8-b4e9-0a1d5d2c5f50", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "eacd7734-70a3-47af-80f4-a6baef688b3d", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "810e94c6-7cbf-4dd7-8ba4-cf09529230da", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "43fc6880-111c-444b-af59-2342d2ef83ce", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "c0255f36-a309-4f61-b593-f56855562f5d", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "5ca710bc-7b26-4869-99c9-7b3a4ea5560c", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "e0faac99-fb8d-48a9-b3c3-bf1ff5dfd764", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "1170ed40-4b66-4858-a027-990559b08917", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "4a3cfab1-03c6-44f3-8520-9867c2131f89", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "cda3174d-d259-47e0-8906-1af492a7b2c4", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "b655859f-ca20-443e-be7f-aa3f34169a05", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "e364a41d-42da-4b08-999a-79bd56f6790e", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "939ed9a9-1044-49c2-b33c-4ec058818f5c", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "ab55c92a-560c-452e-b806-22b64c2aa859", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "1d9a3d12-ca79-4828-bdac-087fea6b5a2b", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "6e256a0c-77a5-401f-b276-cad2b68d342f", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "4a8b6e50-1c1b-4c0c-bb50-98320be35b70", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "d4740a90-45c5-488d-b42b-65db6bfaf84a", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "296ded40-3565-450f-be50-b426b0ee5780", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "84fa0565-ca47-4591-b45b-a1d5d9b75b0d", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "25e40fbd-49a5-449a-ae18-1e0cd06f95c0", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "beb7deca-9880-40d7-94f3-969be921d18c", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "65292eba-055f-4eb0-a855-423ac76d5f51", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "d19d5c51-4059-477a-921f-f45914da4759", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "b275e52a-abca-4f81-af40-5b08af610598", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "239766b5-c3eb-45f7-87f2-4933f5d531fe", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "19b3b673-d603-4edf-bae4-16665c1c603a", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "02681133-9d8e-41e1-9083-de56cf8a3e2b", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "3e52a1a9-1a54-4b26-9960-a346e507909b", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "1086f4db-98ca-4075-98da-a6c3bfd088ef", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "a89cedf1-3c5a-4731-8b8d-bc72a0979187", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "bc5f8d91-6c22-4c16-8295-1efe1ae46958", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "c6f6bea2-bfe4-4f78-9d7b-c3260488d0c3", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "c6507983-e29c-469b-83ba-c938907128a1", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "5ad49548-1ea7-4793-8cb3-509870b2330f", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "bc85971c-491d-4af3-b8a6-f01afe9f2d2d", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "3294771a-359b-460d-94d5-f76618d20455", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "ef9807b6-22b3-49ab-9079-7f002c9f24ea", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "13aa9ce3-57a4-4900-8ae3-e9c5e45fc8b7", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "72a06887-5e19-42bc-a908-55371278001c", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "f49d3d24-c02a-4baa-817d-867ebb58f7dd", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "36d23388-fab7-448e-a5a3-3e68d47db2e1", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "f3e3cdc7-eec9-4a0e-9c6f-6fabb526db11", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "09342c7c-ebb2-47f2-bdf8-f1f36f816965", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "da0b1068-20db-47e3-839e-b8942f8b5556", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "7d60b39d-7d08-49e0-80d3-db53c5c8d5ed", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "d88dbcb8-ddf5-430f-8966-91d07bf610d4", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "86151977-91b6-4ab5-b412-aae6cfca95e1", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "35158afb-4cb5-4573-a471-748d356f685a", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "c0f8a3fe-9315-4a8f-8381-015b75348fe3", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "a56186f5-26d5-4b46-80f3-a19f91ba79ee", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "7e39af87-5beb-4add-add8-8edff7f21c7c", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "600cde3c-a7e3-4458-b4e5-22258d8458d6", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "7958c47d-5299-43b3-a6d2-6aa846fe7b1e", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "78755ebb-23ec-462d-8c16-ded1bcf36a76", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "1700acea-7767-4856-8e1b-1a918c8daef5", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "961874d2-7c6e-4d8e-a77f-e6611b9229b7", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "1b379fc2-c9b9-4390-ad96-07885236a3cf", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "4ec544ab-119a-4ad5-b6d3-a57a4f62c6b5", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "d12b1fe6-3f38-4f7b-967a-7fba73ac42e3", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "cebb3693-a27f-4593-8853-ffc6816e2284", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "9881605c-0c99-4585-8f1a-7cc11b3815ca", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "567f53c2-217f-4620-b61f-9bc6de6e2a4b", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "cc925dcd-4192-4321-b2d0-c22aef90696d", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "da678bca-fb37-469b-9758-43da81e09fcf", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "2611c73b-6d4f-4f31-843d-939e0313c020", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "d983b536-34fb-43e2-bc5b-706fa5654f17", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "8b1dea84-3041-4a89-8b0f-d10a503f04d6", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "9affefef-fa8b-40fa-a716-314992e63146", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "acae33ac-bc70-48f2-b6c9-4109bfdf3875", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "a29bc0d8-a3db-4e73-b0d1-688bb7e7d68d", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "a969b59a-1fb4-44b5-82a3-2a81530b284c", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "ad8a1b7e-c23b-4c59-b1eb-cc3809a4cdef", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "7d7bbe1e-be7b-48d4-bc3e-1f039db5e176", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "9c6c51a2-8d36-476d-8493-6de6a25c162c", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "7f1b347e-1971-4412-90b2-566a5449cd88", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "52083cb9-4c02-44fa-9729-5ca1790ee615", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "c77cfa7e-64d5-4448-9959-a6cc10ad6877", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "5be03279-f2d1-40b9-a29c-4b66492607ad", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "b9aaf65e-e85e-4a51-8c1e-5b968e52996a", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "0c56d53d-7613-4990-8c26-a5e6098889be", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "e505ac1e-d730-401f-be3c-fbe7d26824a2", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "999fc04e-9b3e-4bb3-b814-9fbbd2196f46", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "8430b7fb-c4a8-4e94-a7b4-4c67caaf1494", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "57263075-923a-488c-911c-1cf7b704ca7c", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "a7ee3a68-576b-4ea5-a6b7-67240460fd3b", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "6af34f67-252c-4b76-b66d-940453759104", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "978c68c9-8e18-4ad8-a5e1-efecc2f2a95e", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "6c278b94-e9a6-4dff-b6ab-a246183129e7", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "d8af3128-95a2-4db6-be31-a4739a99c85a", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "b6df6d33-cb18-40a4-937d-d0d953747886", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "3199f24d-5fc4-4489-9b2f-8bc01a29fb82", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "5340708d-faa9-4f28-8931-a523f98d91f1", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "185b70b6-83ea-4971-b640-a662f2fee739", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "528b6031-6ef3-4d26-a579-b5887c4b16f8", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "84f9ef7b-68aa-4ff1-82c8-4cc6055cba78", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "79d885bb-a343-446e-bc53-95df45d0fb97", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "4c48597b-2b25-47ba-b3c5-59dffe50f775", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "4f64ae8b-68d3-4489-b36a-cbb91e9da797", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "b90114bd-2d01-412d-bbaa-9b2b5f01d42d", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "911c693f-ba0b-43c5-a6e3-f762a3fe5ad8", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "10537f01-23b4-4f2a-8caf-0275836237d6", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "a2213615-d40b-4722-8aff-883e4ed135f3", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "5a40e37a-f391-4776-84c2-c402b309be0c", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "170825a9-d685-4ba0-9b09-921667d88f3f", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "d768e517-c514-46ad-a44d-bd2dc154a0a4", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "549827c2-d5f8-4da7-8576-a78c12403f5c", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "63c62e7a-c374-426f-a160-02155f9a9add", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "35cc289d-e8da-4e71-a098-9782fdf7a1f7", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "e3b10a41-6b4e-4de8-9d5d-bb7e0b5b037b", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "593fab32-8b73-4f38-b285-04d00d2cfea9", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "ba6b73c0-c0fd-49c2-a0c6-d8074e8c273a", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "d28a7c53-dab1-447e-b9d6-c3f202a01848", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "4cbe8f6c-8107-45f5-ab9b-6a0fd921f34f", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "9b6f8005-4f40-44e6-be01-1d62bf335d1d", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "8049cfbe-8a25-442f-a814-9a35a6a566c3", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "78184e0e-281e-42f2-b987-94c9d5d1345f", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "5001e0b6-24fe-4068-92ed-04512f6de662", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "8fc93949-8f75-4012-bdd2-cc2899a299b7", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "9e59ac0b-a7f5-4124-a634-c9d3863e1032", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "3364eee9-61f6-404d-bab8-5fb69bb007df", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "fc96af6f-659a-4b6f-ab7b-af4c3306de7b", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "b873477c-ef4f-49d3-a99c-75e842df82f3", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "c057d478-75af-4152-9bb2-d04a26d65529", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "0a73bf68-a1f2-4199-9c48-e8ce8895fabc", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "5b9d4abd-77be-4c90-b9f8-0dce10945b42", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "6027529e-087e-49df-b24f-0247ecdf435a", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "8ce95933-6446-4c55-8904-bb15eea4b22c", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "83ef4475-46ec-424f-9030-95c425d9ce4a", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "3ea2f10b-d279-4c07-980f-d2eda57eba35", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "365e83d4-4066-45fb-862a-8d5455a2c8c3", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "86646dec-e5c3-4c5c-b93e-3b9cd920409a", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "98a7b587-c038-4c38-a8ad-444316d7e36f", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "75a482e8-7903-457f-ace8-5e02c82b0eda", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "3c0b12db-a20b-45b5-8495-db0903b91214", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "32479414-035e-4ed0-8369-7f686251d961", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "c28c5fae-6c4d-421c-af39-40b7803542cd", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "a84775f2-978e-4d02-b9ed-3d672a730436", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "40d75806-6d11-43ba-8603-1443d9eff371", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "21479a48-6192-43d9-b997-b14195bdb79a", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "d50c36de-6b7f-450a-9253-ac29fb048d78", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "87fd116d-74ae-472b-993b-c59f2206903d", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "8bca17de-3a48-40ed-98c4-df5d9f7877b2", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "1f478c03-fed5-471d-bee0-535f2495a777", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "c7db5e9e-3fc7-44a3-9fa0-c659ea59b20f", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "ea4b87c2-063c-49d0-ac2d-10ba9e445baa", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "272aecfc-ebc9-4b18-bdf7-1c593f9d604c", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "21de83d5-7208-4de2-bbb8-71fd28164c30", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "2d45a3d8-8af9-4ca7-b600-1732aa8ce127", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "825af969-a353-4bd3-af96-9a000834825f", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "16524327-ac7d-47ce-9fb5-21ad2e82fdc1", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "390f7d58-673d-4f05-83cd-33a72f801e19", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "7c06e17c-0f3a-4095-95fb-2e4176e05feb", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "bc927810-b1e2-4f18-ad12-ac40ee1b1cc9", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "9c24a869-7e66-4d0d-b00e-f3d429b1a180", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "cf0a1cde-b464-4294-8f78-cf2b49aed0af", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "a38923b1-6a7e-42ef-97ac-cfdd04fc52d8", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "44a4fd62-8a57-4b48-aa1d-13f549c60425", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "d7b170c7-f3db-40b9-b148-593305808460", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "1711e9f8-994c-49a2-9917-03d320922db7", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "b5906c29-180d-4bab-9bbb-c3808f7c3a2b", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "c4e3d25c-502c-47b1-acc7-5553daa44598", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "a97be4f4-1cf8-4513-a126-c8d90101b461", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "96c399af-c834-4f3c-b523-95966f78a2e1", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "837ab983-8faf-434c-a62b-ed00405e4b4d", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "52cfbb3e-db05-406f-8cd1-40927425e2ee", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "5b60e198-b31c-4816-a038-41807fe55b0f", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "34c66589-a162-4796-9069-19c62faa9848", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "1d9af8f1-fe7e-4793-9ddb-8589538e787d", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "05a092d4-3907-4c76-9247-7c860423812d", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "8c9d2234-5ad1-4c91-ab12-bf038343fb73", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "349b395b-8d02-444e-9e5b-4de8af6a7413", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "a339b9c3-df84-4608-9c76-5add984176de", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "4edf6d30-cc3e-47b5-a9f8-60e9387fce1b", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "73fe136b-525e-41b7-b048-3201ec6260d7", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "935ec73b-21ff-4966-a513-dd3f02a82d00", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "ca319b9d-2fb6-4e21-9777-6fae6e913b71", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "1f2d6775-7abd-4a71-938c-11d3ac644af4", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "54ef7f85-50ef-4f72-b861-b57ba567baab", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "5ad834e5-8e21-464c-8cbf-46e7137f0e11", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "b34c6f94-5d37-41e2-bd69-1ddccb218524", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "9f834fae-a893-410c-9849-4ee207bd5d09", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "342b5967-1dbd-46ac-8b45-decfcc91b72e", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "7decfd32-fa5c-46dc-bc0e-1e37c75530c6", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "69c5bc89-651d-402c-a3c6-6dee8fa108d2", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "ea395687-6054-48d6-b6b1-3d28631d5a79", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "c2a67836-9c80-4fab-956a-f40442e309f0", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "0013cc38-87cf-4440-80f7-9f12db22f3b2", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "a825af77-8672-4f66-b30f-c121e05dba39", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "4ca27b5c-9320-48d5-beb4-467dc275192b", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "eb3f40fc-2d90-4760-a229-8fb6fd4f84b4", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "a76ec8d4-cfb8-48bc-bccc-6b53c1ddd857", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "80e84c08-43e1-4c7b-8367-b7409ef50880", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "f841bb12-e183-4967-a5be-7fe2078c4252", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "f850a792-6c17-4e00-b10a-36b6bfeac771", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "85776d80-b525-48ee-8fc2-7a6cfa45a654", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "628d8d4f-025a-45e7-8d5e-7ae1cb90bb73", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "87869d37-49fa-4115-a2cf-7d6ad269814d", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "7ee86673-f1ba-4d72-8963-bfd9b7f5035a", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "aa94c96d-54c4-46b1-98c0-91edc378b87f", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "35a30416-fab5-43c6-be8f-0fa13568ef09", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "cd8186cd-1296-475a-8559-731f07b83a38", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "b4b95b59-485e-48a7-b067-2be538d79b37", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "ea45203c-b520-485e-8a47-e48612396a56", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "6e3fd3a6-7417-4546-9420-c029d71d99ac", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "b824e105-8988-4554-a175-4686afecc5ad", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "bc2d9514-2811-4d94-9538-4949b3ecf627", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "01c71961-2426-43ea-82a7-9fab4fa857a8", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "67c051d1-0e47-4591-a586-df3899a7e09d", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "f7a0c4f9-8c74-4136-88d4-4c374ff41759", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "52fae6ec-3a4a-4ee7-857f-6cf4eead9480", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "ba5fc22e-cd21-4a87-943d-86042bf2ee68", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "977a488d-2ad4-4c22-b136-ae01abe63355", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "d5466f17-5474-4060-bfa1-a64d44d42351", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "37e92e35-77cf-4c3d-aad2-35a1cdb4b25f", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "efafd6a8-2630-4f76-875e-1adb5be16ebe", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "2e1762b9-0bdf-4dc8-a0f4-5cfe9f3d9a77", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "9ffffd87-c4fd-41be-bd9e-0348bc695a11", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "03e97b82-4994-49c8-a68b-cfdcddad81eb", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "e94cf07b-b7f7-4cde-b23e-f54e099b4328", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "5033aae5-5cf2-4fbd-872b-56a9879e71c9", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "716b99b5-281f-44e3-b164-559e2e8cd5ce", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "c53027b9-66a6-45a3-abbb-0f4cccf76777", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "42ba91b4-711c-41d7-bb18-e946f9e1c958", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "eb4004d5-49c5-4537-9640-d14107916028", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "08a54b33-56a9-4701-b3eb-1b62d0ac2623", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "2f4f2259-d32d-4bde-a22a-a06a5e76cdc9", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "5e916e12-3071-4d4c-8ddd-625c3621e4a1", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "3d4bc7ca-094c-4c0d-8cab-2bf2ed6f5ed9", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "77a05b2a-94e8-41bb-9a94-30c7fd25caaa", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "c4a06053-f2df-4819-b45c-190715504d43", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "1d16e8ed-e0d3-492e-b181-d32ce725c2b4", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "da5194ad-2a97-48b6-a739-709d4046a19d", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "7400e9e2-8dec-4c40-86ab-90dfacb512ef", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "518bdc48-751d-4f29-8ab4-e7f787f93214", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "75e93564-f192-4d5a-a931-5eaeeda32df7", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "922a4450-c49f-434b-ba17-ecfd04bd34b5", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "234311b7-b496-4a5b-85b2-5aaa7d5bc803", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "1468a27e-1978-47c7-9d7e-76d7571697ab", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "5f0e04ca-368b-42aa-b213-ed3c5983058b", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "dee88572-832e-40a9-a92f-03f0a3cf9fe2", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "7a0513e6-954e-4194-be79-53b3f649f43d", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "9fb90f33-892a-4507-9c8b-d8872a8abfba", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "0f6fd370-8f06-4a2c-b6db-56b16bd602f6", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "2107a364-0fa5-456a-a414-f537d904de03", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "0203e15b-67f6-4c85-a43d-b76f22de9a68", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "1bae06f5-1a91-4219-9128-38e5f05a671b", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "44d0eb41-052f-4c70-b804-580ed63f689b", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "c42e96c8-5816-4d66-a1e2-b0fcb2366d03", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "fab5a32e-0009-40fe-9af4-260f249646a2", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "2d0cfc17-4524-412c-b056-a1b6c693fefa", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "423faaea-8196-4ad9-bc99-55bba0824c1b", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "3aeacf24-9f46-4d30-aa9e-169d25563cec", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "bd42656f-6cb1-4e4a-a358-20bc7704252a", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "fe536e35-2bd9-4354-b283-79efdde2a3b8", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "0e499b6d-7873-472f-b12a-9660ac901ea9", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "aa10cc0a-750b-4b4d-bfd1-ab9f1cf1f418", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "c325aa16-25e4-46ea-afdf-2c7e761179ea", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "62117e34-49d1-4d19-886a-8514a55d6e4f", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "9499e486-bba7-4a60-9b45-432e008cafd9", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "6741229a-654f-468c-9cff-ddfaf325c17a", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "889551ae-3860-4517-b3eb-3f7d5bda05db", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "1b5685fa-b8f7-40df-a2d0-960018783ea8", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "de74466d-9e33-4b5e-8992-093846b12982", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "4d95033b-f861-4092-816f-c2ae821a6ee0", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "c138f998-19b6-40e2-a3f0-29b5bc29f874", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "9ef92b50-ef35-4af6-8f4b-70e3b7ea4e49", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "ad33ebea-2c9e-4a1c-877f-9b7c1f21fc7e", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "0249fab0-d1b1-4343-81b6-6eeb096885a9", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "f980e8c6-f113-4115-a527-621ddbef19d0", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "769bf16c-8b95-4875-b4c6-65a58948c5d6", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "c1959619-559a-4d76-a1db-3c47203a80d0", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "cb0b1291-517e-4597-be93-995f8c70d6c3", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "a701260c-a18a-4090-ad16-71bf9ea55876", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "80f36a93-0306-491b-9ef1-6e2fd61c38d2", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "6ba0b067-1d11-442d-a570-6a695104111b", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "a9dd7665-a3e9-4150-8dbb-495739cbf91c", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "1bcc5076-52a9-4eec-81f9-d6d7d5ec4eb3", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "b562c812-add1-414e-b8a6-8a1d87290e85", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "6868970d-e78a-4bfc-9e95-d4388c2b1863", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "123e0b78-1e21-4959-8fe9-a470e9e518e7", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "a523f6aa-27bf-49bd-a21f-dfd4a8aa03a8", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "d9bc66a8-094c-48ab-af79-7a76d78f5467", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "58fd81b6-27f3-40c0-b405-9cc2eab3dd4c", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "2ded511a-8968-4b43-8d3a-c1c9301612ed", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "fc57c53f-0668-4ee0-a688-17db9eab3f4e", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "3dfff994-dcd5-4f1b-a3fa-5a0e46a1217e", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "69a4a7ec-6aeb-4f21-875d-8c82cb9ec840", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "8ba502df-b528-4597-8ff4-b14b6f611d5a", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "51bf3ffe-da77-4f1c-83e6-8f0adfe27f13", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "4a3cbdbc-35b0-4638-aa4f-077ae37d1a81", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "9e556f7f-57c7-41fd-8c88-d2e85fb98c4e", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "9af127d1-65c6-40bf-a4a6-9970a14c0493", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "a5450553-a9ff-4fdc-a8d6-637844a41b82", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "c8afb2fe-6353-4895-85e3-277db996f329", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "b2a92a36-ff36-40ee-857b-2c734d01299c", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "a522eb01-6c7e-4075-9942-8a8d173bcf7a", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "cd1e4e34-d183-494c-aee0-01be46d9d3ab", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "559ad171-f9f6-4523-a477-fa76913cfb62", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "d5d4f866-33d4-44de-bc08-3cb3602d8a54", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "c5358185-c3c4-480c-a4a4-332e5eff3498", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "e34fc637-b1b8-44e8-9e1b-50c4547b2e72", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "6f27fdac-4b19-4b4d-ae28-30f93a484150", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "58dac7d7-ca36-4d48-a948-11f9f40b034e", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "a4e9c61a-35d5-42bd-8a62-51adc00f4dcb", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "edd6febc-5826-4331-a507-7e606cc759b9", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "ede625b6-3efa-42ef-88ee-19e47f34d6d6", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "f7a94b99-eb08-4184-a827-10d56ab13007", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "f80a1eaa-9e2f-4475-8c1a-f7a0217febc1", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "c4d6372d-8594-45fb-9770-22720f602bac", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "fb6ab5f3-1f97-4cb0-ba38-94dc4869de88", "produto_id": "71b73436-5512-4ba4-9719-541b70aec6e0", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "e4a92d4a-2c08-48f6-97e8-cd14162886ac", "produto_id": "8581a904-a689-4535-8ffd-0faef973e9a1", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "e15ed167-b2e7-4c08-901e-e56108225125", "produto_id": "ee5b570a-759c-42aa-929b-efb390436f1a", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "8c2b14a0-23f5-4d18-966e-0bddbf47e548", "produto_id": "400ed17e-5cf0-4a76-ac12-8c3ca074103c", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "b86dbc83-14ab-4265-a67b-f9c0c2eb79cd", "produto_id": "d96d6d4d-a32d-461f-ad10-d6bac52fc729", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "13b76389-dd0c-4642-a6d9-5de5478a2a5d", "produto_id": "b8cfab2c-856b-40b0-870b-a36cfe11ef96", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "909046d0-6020-4d9c-9a47-d91157468ade", "produto_id": "7583e038-e58c-41a8-867c-026f1b90d787", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "87baf5b5-6171-4260-8b22-4c7118ba1c0e", "produto_id": "64142b67-ba38-41fe-8e46-68213b65a342", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "124eb1cb-0cba-476a-967f-4e9dd62eff73", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "dc8f96d9-24ff-4066-9d16-8e6d967fdd6f", "produto_id": "4014c744-53bc-4148-8fcf-0799918e88aa", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "c8ff180d-d47f-4cdf-bba2-3e5c038f71f6", "produto_id": "65226aff-26be-4bbe-9222-62cd159ba207", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "3259c159-7685-4c71-b9e7-3cb61807f2b6", "produto_id": "9288b06c-ad35-4e4b-99d1-845cd2fd8b72", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "a3c2ca8d-3013-4839-a55a-90bf99ea5b93", "produto_id": "69f282b2-c2b1-4e69-8cf0-236a3cc55c5b", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "e990f4d5-1473-486c-a7c1-54cf179b7bff", "produto_id": "d44c0f41-cdf3-428b-bb6d-8e960a22529d", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "b33c0cb6-862e-4a53-994e-68d6647b8a7f", "produto_id": "4436ddb0-689e-4b7e-954a-faa1999288a7", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "f48bea38-097b-4bb8-a897-df8aa645cafb", "produto_id": "dca3fa98-20e5-487f-a479-5920c7783cab", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "b5b8311b-aac4-4e7a-9b1c-4f09bec5dae6", "produto_id": "c5d1d013-4b5d-4006-892b-d41292f3a1f7", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "988ad7d2-6f32-4b70-a5ba-0d7452739a55", "produto_id": "60a58561-6800-44b4-8074-d70d035bb1a2", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "516a315e-a90d-46c7-9315-d6bf0049108e", "produto_id": "5fb6f8d6-49ed-4587-be09-333b67419ac0", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "84553972-2a30-486c-87cd-1a31d05efadb", "produto_id": "f8f7cef0-be70-4335-99e0-53dd3ad00b45", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "cb0f99bb-dd27-44df-b385-86f3c086d169", "produto_id": "37a9d977-55ed-4ff2-a8dc-38c271a1e6a3", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "ac957741-ddcb-428c-bb40-95f403354fa3", "produto_id": "93ea5ac0-5b1f-42ce-9289-478820d9108d", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "cb9af867-0002-4ab4-bd74-3ac651f4ae58", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "1206dbc2-3acf-4761-b273-8a668d67ce2b", "produto_id": "717f21cc-de1d-4881-942a-4601e8bf45f0", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "2b83db5b-bbb6-4500-b060-5ea06d6bdc2f", "produto_id": "43087961-297c-4b43-8ddd-1484188baab2", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "1e4032d8-87aa-4700-8715-900a4ec011d1", "produto_id": "d0bb7b9e-1857-446c-9e61-48e7c23f51e2", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "241dfd7e-505f-4eed-b4de-90db356ae564", "produto_id": "1658ebed-648f-4150-bf26-f50993a72243", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "c22233cc-a78b-4e1d-a106-f890fd25f94f", "produto_id": "63841581-68f3-4cfa-bc81-c78466e5ec5b", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "1aa204b5-1767-445b-beeb-455ff9028f41", "produto_id": "8e155a9a-175c-4fb8-890e-97409b2953c8", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "375b8757-5a9b-4a50-8b34-3edc474560a9", "produto_id": "c5a83fe3-5587-42ea-a160-c16f3b83d2d8", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "90ff3cf9-b7a8-40df-8f5b-091d9167c618", "produto_id": "a5bf9dcb-7066-4b50-acd4-04f560e5eb3b", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "0db5e1af-a292-45c7-a2d9-17046d523d2f", "produto_id": "bf6331a3-74f5-44bb-8b82-635a399c4878", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "e446ecba-663c-4d30-9b52-c3bdc9cfc6a3", "produto_id": "5f5533e0-5760-4edd-a22d-9122097da388", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "66f7b48a-d9b9-4f95-be86-ec50da9a0d5b", "produto_id": "3338daa5-5f14-4236-92b6-1cee71c509b2", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "9529c2c5-698d-44db-83f0-e23a06268212", "produto_id": "76ec1153-89e4-46e4-9c3d-a953e37e6f92", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "bda834c9-49b5-4699-b099-3eecca84fd3e", "produto_id": "5c9f187f-de24-4615-9042-78e1773e904b", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "e993cee4-10e7-4fc4-8f05-9fac97cb6909", "produto_id": "50516989-1011-4b8c-bde9-9ed0750f4a07", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "dc2b5c1b-5d3e-4c5d-8f39-88b1272d8376", "produto_id": "e9243992-5df7-4cfc-82cd-b8ee1d02e69f", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "d63d28a0-eb8e-4408-8e68-04af6da8cd4b", "produto_id": "d84ddbbc-8922-419f-8d2c-0a94b2e123a2", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "4defc2dd-32c4-4963-9449-7155e6ab8694", "produto_id": "86519e93-90e6-4174-b509-136cf9f43430", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "c728f2af-7c45-47b5-9e2b-395ad06f8451", "produto_id": "5a98547e-4cca-4a74-bc73-6822c3b8d069", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "0345cc6d-a836-4950-bffb-25bdde45f16e", "produto_id": "fb925849-fdb1-45d4-8e7f-8a3b57084595", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "7a759bcb-4ad9-4f97-bbd2-cd2bd8d6d23c", "produto_id": "f6777e04-f0b8-442f-ac33-ae1af4752932", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "b41ba705-4166-4c7f-82f1-29dca1b3cc17", "produto_id": "fb1ad5ae-9041-4688-accc-2745ff3b8550", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "6f9627b5-4a5b-4cbb-88cd-04f6d813e892", "produto_id": "dbdba3e8-488c-4eca-b84c-108ba9de45ba", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "ba50495b-33af-43f4-823e-1ccf1b5fe7c7", "produto_id": "7fa58aa9-40e3-4a45-b314-ad9086d83d26", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "080c65c9-3a3b-4e7f-90c9-f96c02e108b4", "produto_id": "e5708074-2b1a-41f3-a9fe-a3a954ecc8e1", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "09dafc99-becc-4134-8eb1-80183a866a1a", "produto_id": "f4bc7c7f-14c6-42af-ad10-ea3740840d94", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "3ef4fdec-7027-4188-88ac-a77c1b7d0268", "produto_id": "e2582ee2-3930-41e3-89b4-fc0a517ad88e", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "4ab16eba-d2fd-41da-9383-41179bf74281", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "9c6d0eae-6a8d-4714-bfee-3a8ef35bf35f", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "a6366a4e-0235-4716-974b-ce7543a22cec", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "550df3b0-35e7-44ee-b2be-0bbced790462", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "4b76d213-ac5a-4b64-be6e-f04fc9a39d12", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "522a5a7e-703c-4f41-9e5e-3eca4c0466a7", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "f32615d4-8818-43ed-967c-0812879d9ff6", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "4ae2d229-8b9c-47be-8713-026549aa13d5", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "c3977163-be8b-4756-936a-8255d1768ec4", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "b1c7bcc5-29f5-4938-a446-c40475e76ffa", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "8dc9be3a-7db1-4542-a993-18f28ccb0f74", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "2002ab99-367a-468e-bd2f-92ce52a9a6bb", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "76b4899a-8d4f-470b-ba86-ee55df501ca6", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "c949978a-9fc4-4281-bd20-fa2a8dec3c74", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "633bc680-bf0e-4cd6-b3f2-3311f9fe7a0b", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "92d48bb1-305e-41ef-8aac-d5a9d2991d49", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "dea09024-2aeb-487c-924c-2e53eb8e7473", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "dc1450fc-bf55-426d-8c04-2fdf3a289c1d", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "21621505-fa93-4472-8e86-f3efdc7adacc", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "a4dcad33-dbee-4d69-9b82-3cb66d652893", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "515dbf77-5caf-4228-b0a0-7ff1817f7aae", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}, {"id": "699b1c07-116b-46dd-b717-5060987b7b87", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "081a3274-b818-4fe1-908a-32a8f752e302"}, {"id": "8e2d6535-d14b-4b2b-8c89-6b1e88aff819", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "08f7b146-1785-44c2-82fc-7ed246ef94e3"}, {"id": "91aeaaf7-40e7-4f7b-9f4b-cbfb11cc4ad5", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "1d9cc231-ec6a-4425-9571-1da72ea37d0b"}, {"id": "03da47aa-983c-4abb-8fdd-6d2fd3fcc01e", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "21328783-0d86-4fba-b0f9-45caef78e4fd"}, {"id": "74bf3e8b-1b33-4535-8aba-b89ee8db22c6", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "375fb3e2-36f3-47be-9d78-7d0d11882a35"}, {"id": "d170669a-344d-46d3-af90-afc081cd959e", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "3c79ebec-03f0-4bb7-a376-41b01eaa4fa1"}, {"id": "8d37c6fd-5b25-4285-a456-40b416dfa101", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "44815153-bbb6-4559-ae81-82cd3e3ccae7"}, {"id": "dd299412-c420-4dbc-9407-095f4cbdfb52", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "527e67ca-6eca-4b95-ba76-7fa0dd557594"}, {"id": "fab6e590-e3fa-4e9a-b98e-2bec71f85f8c", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "61f8634c-53a5-4e3f-b4eb-df9a3aebf829"}, {"id": "0ff751f6-c97c-4407-9333-2dab64d36e6d", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "6861e324-b899-48fe-8854-a42e33113ecb"}, {"id": "ee263584-e102-4114-8c2c-88671e8269c4", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "71d2a3f3-f891-452b-9b2f-7c36fcfdcb15"}, {"id": "95151795-fb11-4cca-b0ce-a290847a205f", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "726e8d36-8e80-448a-aa0c-953130ea68b6"}, {"id": "853641b8-57d2-42cc-9efb-e70896bb178e", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "80e18270-3011-46cb-a5f3-10197a5d728a"}, {"id": "8d683657-b68e-4a19-9543-2421a8d3d1cb", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "86b5d225-8dd5-4569-8dad-06f7ab013b3e"}, {"id": "4de06c12-5dcb-4d0e-906f-88ccdaad2119", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "a526737c-cfd1-4169-a2fa-d9c62819fd16"}, {"id": "1e42b4f3-a90c-49a2-b083-6b3a284b8a2f", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "aeec0c9c-2f3c-4db0-9bce-b625018c7149"}, {"id": "fc4b19b6-a07b-4ba7-ae5a-1055cdbcf42a", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "b860d589-8024-4632-9a0e-e86bcd112634"}, {"id": "91bfc41d-a592-49d5-97a3-ae07d29b8d9a", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "bc592a40-9298-4707-9ef3-e2f1d5f5238c"}, {"id": "d9e002e0-6516-49c6-9026-4e7931a5247a", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "c06e9235-09d1-45d3-ad09-e347d8da6c75"}, {"id": "67cd1a97-fb34-41c0-ba35-d50bc3403ac7", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "dc16b7c5-3a49-44a3-ada1-4caeddaf6f88"}, {"id": "83132c15-d628-47d1-bc92-4363df5d7c00", "produto_id": "25b30ac0-81b5-46bd-b3ad-876b48a78251", "adicional_id": "f4943c8c-5948-4e69-806c-71dcf68e1678"}]'::jsonb) ON CONFLICT DO NOTHING;

-- clientes
INSERT INTO public.clientes SELECT * FROM jsonb_populate_recordset(null::public.clientes, '[{"id": "4c44d8c2-e528-4dd3-a9d9-91deffa68b3b", "nome": "Lucas Ricardo", "endereco": "Av Prudêncio Ortiz, 364, Jaboticabal", "telefone": "(16) 99622-4986", "criado_em": "2026-10-04T10:58:59.171+00:00", "observacoes": "", "como_conheceu": "Outro", "data_nascimento": "1995-12-28", "primeiro_contato": "2026-10-04T10:58:59.171+00:00"}]'::jsonb) ON CONFLICT DO NOTHING;

-- fidelidade
INSERT INTO public.fidelidade SELECT * FROM jsonb_populate_recordset(null::public.fidelidade, '[{"id": "6a317769-86d0-4707-a4c2-1330d8274c60", "carimbos": 3, "cliente_id": "4c44d8c2-e528-4dd3-a9d9-91deffa68b3b", "observacoes": null, "atualizada_em": "2026-10-04T14:10:24.896849+00:00", "premios_resgatados": 0}]'::jsonb) ON CONFLICT DO NOTHING;

-- mesas
INSERT INTO public.mesas SELECT * FROM jsonb_populate_recordset(null::public.mesas, '[{"id": "6ce68177-48f7-4aad-a759-96034c371d5f", "numero": "1", "status": "Livre", "capacidade": 4, "chamado_em": null, "observacao": null, "chamado_tipo": null, "garcom_responsavel_id": null}]'::jsonb) ON CONFLICT DO NOTHING;

-- caixa_sessoes
INSERT INTO public.caixa_sessoes SELECT * FROM jsonb_populate_recordset(null::public.caixa_sessoes, '[{"id": "d1389d31-dbff-4c37-89dd-fda22c72cc17", "status": "Aberto", "abertura": "2026-10-04T10:44:19.832464+00:00", "diferenca": null, "fechamento": null, "fundo_caixa": 100.00, "saldo_final": null, "total_vendas": null, "valor_contado": null, "total_despesas": null, "usuario_abertura": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_fechamento": null}]'::jsonb) ON CONFLICT DO NOTHING;

-- vendas
INSERT INTO public.vendas SELECT * FROM jsonb_populate_recordset(null::public.vendas, '[{"id": "6ae32da0-8576-4ddb-8634-889649f5844c", "tipo": "Retirada", "origem": "Balcão", "status": "Confirmada", "mesa_id": null, "saiu_em": null, "caixa_id": "d1389d31-dbff-4c37-89dd-fda22c72cc17", "endereco": "", "data_hora": "2026-10-04T10:59:58.90609+00:00", "pronta_em": "2026-10-04T11:34:26.690053+00:00", "cliente_id": null, "referencia": "", "complemento": "", "custo_total": 0.00, "recebido_em": "2026-10-04T10:59:58.90609+00:00", "valor_total": 40.00, "cliente_nome": "Lucas Ricardo", "concluida_em": "2026-10-04T11:34:28.078937+00:00", "taxa_entrega": 0.00, "entregador_id": null, "numero_pedido": 1, "requisicao_id": "r-1791111598496-387g5sr2", "status_pedido": "Retirada", "registrado_por": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "valor_desconto": 40.00, "valor_original": 80.00, "forma_pagamento": "Dinheiro", "desconto_detalhe": "50% (R$ 40.00)", "status_pagamento": "Pago", "telefone_cliente": "(16) 99622-4986", "inicio_preparo_em": null, "motivo_cancelamento": null, "observacoes_entrega": "", "fechamento_entrega_id": null, "status_antes_suspensao": null}, {"id": "13b25d4d-0082-46dd-89f0-dc07aa3ac932", "tipo": "Retirada", "origem": "Balcão", "status": "Confirmada", "mesa_id": null, "saiu_em": null, "caixa_id": "d1389d31-dbff-4c37-89dd-fda22c72cc17", "endereco": "", "data_hora": "2026-10-04T11:01:57.404999+00:00", "pronta_em": "2026-10-04T11:34:29.196433+00:00", "cliente_id": null, "referencia": "", "complemento": "", "custo_total": 0.00, "recebido_em": "2026-10-04T11:01:57.404999+00:00", "valor_total": 39.65, "cliente_nome": "Lucas Ricardo", "concluida_em": "2026-10-04T11:34:30.627451+00:00", "taxa_entrega": 0.00, "entregador_id": null, "numero_pedido": 2, "requisicao_id": "r-1791111717593-0vr6g04i", "status_pedido": "Retirada", "registrado_por": "a7fb2364-a458-439d-b92d-e7e9933bfba5", "valor_desconto": 39.65, "valor_original": 79.30, "forma_pagamento": "Dinheiro", "desconto_detalhe": "50% (R$ 39.65)", "status_pagamento": "Pago", "telefone_cliente": "(16) 99622-4986", "inicio_preparo_em": null, "motivo_cancelamento": null, "observacoes_entrega": "", "fechamento_entrega_id": null, "status_antes_suspensao": null}, {"id": "957fcd6b-3977-4449-b209-8e19e9d76f6a", "tipo": "Entrega", "origem": "Cardápio", "status": "Confirmada", "mesa_id": null, "saiu_em": "2026-10-04T14:10:30.781714+00:00", "caixa_id": "d1389d31-dbff-4c37-89dd-fda22c72cc17", "endereco": "Avenida Prudêncio Ortiz, 364", "data_hora": "2026-10-04T14:08:06.479992+00:00", "pronta_em": "2026-10-04T14:10:29.08764+00:00", "cliente_id": null, "referencia": "", "complemento": "", "custo_total": 0.00, "recebido_em": "2026-10-04T14:10:24.896849+00:00", "valor_total": 31.50, "cliente_nome": "Lucas Ricardo", "concluida_em": "2026-10-04T14:10:42.542497+00:00", "taxa_entrega": 8.00, "entregador_id": "8e442ee3-af30-4da0-ae6c-0312d2ba9223", "numero_pedido": 6, "requisicao_id": "r-1791122885948-dynh3nva", "status_pedido": "Entregue", "registrado_por": null, "valor_desconto": 0.00, "valor_original": 23.50, "forma_pagamento": "Cartão de Débito", "desconto_detalhe": "", "status_pagamento": "Pago", "telefone_cliente": "16996224986", "inicio_preparo_em": null, "motivo_cancelamento": null, "observacoes_entrega": "", "fechamento_entrega_id": null, "status_antes_suspensao": null}]'::jsonb) ON CONFLICT DO NOTHING;

-- itens_venda
INSERT INTO public.itens_venda SELECT * FROM jsonb_populate_recordset(null::public.itens_venda, '[{"id": "dbe3d22a-f97b-49d2-be60-0e39a2662acb", "combo_id": null, "venda_id": "6ae32da0-8576-4ddb-8634-889649f5844c", "descricao": "Batata Recheada Frango Bacon e Catupiry", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "quantidade": 1, "adicionais_ids": [], "custo_unitario": 0.00, "valor_unitario": 41.00, "valor_total_item": 41.00}, {"id": "2d724494-ceb5-4a52-877f-4c1cbf1aee94", "combo_id": null, "venda_id": "6ae32da0-8576-4ddb-8634-889649f5844c", "descricao": "Frango Bacon Catupiry", "produto_id": "2b54201e-9524-4e52-9615-53eef6fae6f6", "quantidade": 1, "adicionais_ids": [], "custo_unitario": 0.00, "valor_unitario": 39.00, "valor_total_item": 39.00}, {"id": "89dae0aa-7b8b-4dc3-b48a-43be41c93ba1", "combo_id": null, "venda_id": "13b25d4d-0082-46dd-89f0-dc07aa3ac932", "descricao": "Batata Recheada Frango Bacon e Catupiry", "produto_id": "13d9f0c0-5fe6-41ee-8b62-fc3ca16a35f2", "quantidade": 1, "adicionais_ids": [], "custo_unitario": 0.00, "valor_unitario": 41.00, "valor_total_item": 41.00}, {"id": "063f48c0-a739-4cfa-a016-4c66ea8b92e4", "combo_id": null, "venda_id": "13b25d4d-0082-46dd-89f0-dc07aa3ac932", "descricao": "Texas Honey", "produto_id": "3c8204c5-6801-49bb-9fec-5ecc6fbb26db", "quantidade": 1, "adicionais_ids": [], "custo_unitario": 0.00, "valor_unitario": 38.30, "valor_total_item": 38.30}, {"id": "df9774bb-8bbf-4f37-ac17-4b22440169b3", "combo_id": null, "venda_id": "957fcd6b-3977-4449-b209-8e19e9d76f6a", "descricao": "Smash Catupiry", "produto_id": "59fc09ea-7730-40ef-b700-6388068e3ec8", "quantidade": 1, "adicionais_ids": [], "custo_unitario": 0.00, "valor_unitario": 23.50, "valor_total_item": 23.50}]'::jsonb) ON CONFLICT DO NOTHING;

-- pagamentos_venda
INSERT INTO public.pagamentos_venda SELECT * FROM jsonb_populate_recordset(null::public.pagamentos_venda, '[{"id": "8945f428-fffd-4eae-a17f-b8c720fb0492", "valor": 40.00, "venda_id": "6ae32da0-8576-4ddb-8634-889649f5844c", "taxa_aplicada": 0.00, "forma_pagamento": "Dinheiro"}, {"id": "7d6e65a7-6ff8-4866-b6cd-8a0e35c3244d", "valor": 39.65, "venda_id": "13b25d4d-0082-46dd-89f0-dc07aa3ac932", "taxa_aplicada": 0.00, "forma_pagamento": "Dinheiro"}, {"id": "9f7f2eac-b73c-4cf0-a512-2b5d8ea159bd", "valor": 31.50, "venda_id": "957fcd6b-3977-4449-b209-8e19e9d76f6a", "taxa_aplicada": 0.00, "forma_pagamento": "Cartão de Débito"}]'::jsonb) ON CONFLICT DO NOTHING;

-- auditoria
INSERT INTO public.auditoria OVERRIDING SYSTEM VALUE SELECT * FROM jsonb_populate_recordset(null::public.auditoria, '[{"id": 8, "acao": "Caixa aberto", "perfil": "Admin", "aparelho": null, "detalhes": "Fundo de caixa: R$ 100.00", "telefone": null, "data_hora": "2026-10-04T10:44:19.832464+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 9, "acao": "Usuário excluído", "perfil": "Admin", "aparelho": null, "detalhes": "Lucas", "telefone": null, "data_hora": "2026-10-04T10:55:52.766455+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": "Jonatan"}, {"id": 1, "acao": "Adicionais vinculados em lote", "perfil": "Admin", "aparelho": null, "detalhes": "52 produtos x 21 adicionais", "telefone": null, "data_hora": "2026-10-04T02:13:00.215339+00:00", "usuario_id": null, "usuario_login": "Lucas", "autorizado_por": null}, {"id": 2, "acao": "Produto editado", "perfil": "Admin", "aparelho": null, "detalhes": "Batata Recheada Frango Bacon e Catupiry — Preços alterados: iFood: R$ 43.00 → R$ 42.00", "telefone": null, "data_hora": "2026-10-04T02:26:41.494268+00:00", "usuario_id": null, "usuario_login": "Lucas", "autorizado_por": null}, {"id": 3, "acao": "Produto editado", "perfil": "Admin", "aparelho": null, "detalhes": "Batata Recheada Frango Bacon e Catupiry — Preços alterados: Dinheiro: R$ 41.00 → R$ 42.00; Pix: R$ 41.00 → R$ 42.00; Cartão de Débito: R$ 41.00 → R$ 42.00; Cartão de Crédito: R$ 41.00 → R$ 42.00; Alelo: R$ 41.00 → R$ 42.00", "telefone": null, "data_hora": "2026-10-04T02:27:05.216451+00:00", "usuario_id": null, "usuario_login": "Lucas", "autorizado_por": null}, {"id": 4, "acao": "Produto editado", "perfil": "Admin", "aparelho": null, "detalhes": "Batata Recheada Frango Bacon e Catupiry — Preços alterados: Dinheiro: R$ 42.00 → R$ 41.00; Pix: R$ 42.00 → R$ 41.00; Cartão de Débito: R$ 42.00 → R$ 41.00; Cartão de Crédito: R$ 42.00 → R$ 41.00; Alelo: R$ 42.00 → R$ 41.00; iFood: R$ 42.00 → R$ 41.00", "telefone": null, "data_hora": "2026-10-04T02:27:13.594904+00:00", "usuario_id": null, "usuario_login": "Lucas", "autorizado_por": null}, {"id": 5, "acao": "Produto editado", "perfil": "Admin", "aparelho": null, "detalhes": "Catupiry Bacon — Preços alterados: iFood: R$ 48.90 → R$ 46.00", "telefone": null, "data_hora": "2026-10-04T02:27:36.672255+00:00", "usuario_id": null, "usuario_login": "Lucas", "autorizado_por": null}, {"id": 6, "acao": "Produto editado", "perfil": "Admin", "aparelho": null, "detalhes": "Catupiry Bacon — Preços alterados: Dinheiro: R$ 45.00 → R$ 46.00; Pix: R$ 45.00 → R$ 46.00; Cartão de Débito: R$ 45.00 → R$ 46.00; Cartão de Crédito: R$ 45.00 → R$ 46.00; Alelo: R$ 45.00 → R$ 46.00", "telefone": null, "data_hora": "2026-10-04T02:27:48.474438+00:00", "usuario_id": null, "usuario_login": "Lucas", "autorizado_por": null}, {"id": 7, "acao": "Produto editado", "perfil": "Admin", "aparelho": null, "detalhes": "Catupiry Bacon — Preços alterados: Dinheiro: R$ 46.00 → R$ 45.00; Pix: R$ 46.00 → R$ 45.00; Cartão de Débito: R$ 46.00 → R$ 45.00; Cartão de Crédito: R$ 46.00 → R$ 45.00; Alelo: R$ 46.00 → R$ 45.00; iFood: R$ 46.00 → R$ 45.00", "telefone": null, "data_hora": "2026-10-04T02:28:03.288141+00:00", "usuario_id": null, "usuario_login": "Lucas", "autorizado_por": null}, {"id": 10, "acao": "Usuário editado", "perfil": "Admin", "aparelho": null, "detalhes": "Entregador (nome/telefone alterado)", "telefone": null, "data_hora": "2026-10-04T10:56:53.505232+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": "Jonatan"}, {"id": 11, "acao": "Cliente cadastrado", "perfil": "Admin", "aparelho": null, "detalhes": "Lucas Ricardo", "telefone": "(16) 99622-4986", "data_hora": "2026-10-04T10:58:59.171+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 12, "acao": "Desconto aplicado na venda", "perfil": "Admin", "aparelho": null, "detalhes": "Autorizado por Jonatan | Valor original: R$ 80.00 → Desconto: 50% (R$ 40.00) → Valor final: R$ 40.00", "telefone": "(16) 99622-4986", "data_hora": "2026-10-04T10:59:58.90609+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": "Jonatan"}, {"id": 13, "acao": "Cliente novo no fidelidade", "perfil": "Admin", "aparelho": null, "detalhes": "Lucas Ricardo", "telefone": "(16) 99622-4986", "data_hora": "2026-10-04T10:59:58.90609+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": "Jonatan"}, {"id": 14, "acao": "Venda registrada", "perfil": "Admin", "aparelho": null, "detalhes": "Total R$ 40.00 via Dinheiro (Retirada, Pago)", "telefone": "(16) 99622-4986", "data_hora": "2026-10-04T10:59:58.90609+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": "Jonatan"}, {"id": 15, "acao": "Desconto aplicado na venda", "perfil": "Operador", "aparelho": null, "detalhes": "Autorizado por Jonatan | Valor original: R$ 79.30 → Desconto: 50% (R$ 39.65) → Valor final: R$ 39.65", "telefone": "(16) 99622-4986", "data_hora": "2026-10-04T11:01:57.404999+00:00", "usuario_id": "a7fb2364-a458-439d-b92d-e7e9933bfba5", "usuario_login": "Caixa", "autorizado_por": "Jonatan"}, {"id": 16, "acao": "Marca adicionada (fidelidade)", "perfil": "Operador", "aparelho": null, "detalhes": "2/10", "telefone": "(16) 99622-4986", "data_hora": "2026-10-04T11:01:57.404999+00:00", "usuario_id": "a7fb2364-a458-439d-b92d-e7e9933bfba5", "usuario_login": "Caixa", "autorizado_por": "Jonatan"}, {"id": 17, "acao": "Venda registrada", "perfil": "Operador", "aparelho": null, "detalhes": "Total R$ 39.65 via Dinheiro (Retirada, Pago)", "telefone": "(16) 99622-4986", "data_hora": "2026-10-04T11:01:57.404999+00:00", "usuario_id": "a7fb2364-a458-439d-b92d-e7e9933bfba5", "usuario_login": "Caixa", "autorizado_por": "Jonatan"}, {"id": 85, "acao": "Pedido recebido pelo Cardápio", "perfil": "Cliente", "aparelho": null, "detalhes": "Total R$ 31.50", "telefone": "16996224986", "data_hora": "2026-10-04T14:08:06.479992+00:00", "usuario_id": null, "usuario_login": "Cardápio (cliente)", "autorizado_por": null}, {"id": 86, "acao": "Entregador atribuído", "perfil": "Admin", "aparelho": null, "detalhes": "#6: (nenhum) → Entregador", "telefone": null, "data_hora": "2026-10-04T14:09:02.848148+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 87, "acao": "Pedido aceito", "perfil": "Admin", "aparelho": null, "detalhes": "#6", "telefone": "16996224986", "data_hora": "2026-10-04T14:09:03.90825+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 88, "acao": "Marca adicionada (fidelidade)", "perfil": "Admin", "aparelho": null, "detalhes": "3/10", "telefone": "16996224986", "data_hora": "2026-10-04T14:10:24.896849+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 89, "acao": "Pagamento confirmado", "perfil": "Admin", "aparelho": null, "detalhes": "#6", "telefone": "16996224986", "data_hora": "2026-10-04T14:10:24.896849+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 90, "acao": "Status do pedido atualizado", "perfil": "Admin", "aparelho": null, "detalhes": "#6 → Pronta", "telefone": null, "data_hora": "2026-10-04T14:10:29.08764+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 27, "acao": "Status do pedido atualizado", "perfil": "Admin", "aparelho": null, "detalhes": "#1 → Pronta", "telefone": null, "data_hora": "2026-10-04T11:34:26.690053+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 28, "acao": "Status do pedido atualizado", "perfil": "Admin", "aparelho": null, "detalhes": "#1 → Retirada", "telefone": null, "data_hora": "2026-10-04T11:34:28.078937+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 29, "acao": "Status do pedido atualizado", "perfil": "Admin", "aparelho": null, "detalhes": "#2 → Pronta", "telefone": null, "data_hora": "2026-10-04T11:34:29.196433+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 30, "acao": "Status do pedido atualizado", "perfil": "Admin", "aparelho": null, "detalhes": "#2 → Retirada", "telefone": null, "data_hora": "2026-10-04T11:34:30.627451+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 91, "acao": "Status do pedido atualizado", "perfil": "Admin", "aparelho": null, "detalhes": "#6 → Saiu para entrega", "telefone": null, "data_hora": "2026-10-04T14:10:30.781714+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 92, "acao": "Status do pedido atualizado", "perfil": "Admin", "aparelho": null, "detalhes": "#6 → Entregue", "telefone": null, "data_hora": "2026-10-04T14:10:42.542497+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}, {"id": 93, "acao": "Configuração de entrega alterada", "perfil": "Admin", "aparelho": null, "detalhes": "Taxa: R$ 8.00 → R$ 8.00 | Ajuda diária: R$ 0.00 → R$ 0.00 (vale só para pedidos e fechamentos futuros)", "telefone": null, "data_hora": "2026-10-04T17:13:29.113404+00:00", "usuario_id": "98a655a7-3d3b-4826-b6ac-e7c81fe5a0e1", "usuario_login": "Jonatan", "autorizado_por": null}]'::jsonb) ON CONFLICT DO NOTHING;

-- versoes_sync (carimbos do sync incremental; só aumentam)
INSERT INTO public.versoes_sync (grupo, n) VALUES ('cad', 0), ('din', 0) ON CONFLICT DO NOTHING;

COMMIT;

-- 10. TRIGGERS --------------------------------------------------------
DROP TRIGGER IF EXISTS adicionais_sync ON public.adicionais;
CREATE TRIGGER adicionais_sync AFTER INSERT OR DELETE OR UPDATE ON public.adicionais FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS ajustes_pos_venda_sync ON public.ajustes_pos_venda;
CREATE TRIGGER ajustes_pos_venda_sync AFTER INSERT OR DELETE OR UPDATE ON public.ajustes_pos_venda FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS caixa_sessoes_sync ON public.caixa_sessoes;
CREATE TRIGGER caixa_sessoes_sync AFTER INSERT OR DELETE OR UPDATE ON public.caixa_sessoes FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS categorias_sync ON public.categorias;
CREATE TRIGGER categorias_sync AFTER INSERT OR DELETE OR UPDATE ON public.categorias FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS clientes_sync ON public.clientes;
CREATE TRIGGER clientes_sync AFTER INSERT OR DELETE OR UPDATE ON public.clientes FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS combo_itens_sync ON public.combo_itens;
CREATE TRIGGER combo_itens_sync AFTER INSERT OR DELETE OR UPDATE ON public.combo_itens FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS combo_precos_sync ON public.combo_precos;
CREATE TRIGGER combo_precos_sync AFTER INSERT OR DELETE OR UPDATE ON public.combo_precos FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS combos_sync ON public.combos;
CREATE TRIGGER combos_sync AFTER INSERT OR DELETE OR UPDATE ON public.combos FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS fotos_cfg_atualizado ON public.configuracoes_fotos;
CREATE TRIGGER fotos_cfg_atualizado BEFORE UPDATE ON public.configuracoes_fotos FOR EACH ROW EXECUTE FUNCTION public.tocar_atualizado_em();
DROP TRIGGER IF EXISTS cupons_sync ON public.cupons;
CREATE TRIGGER cupons_sync AFTER INSERT OR DELETE OR UPDATE ON public.cupons FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS cupons_usos_sync ON public.cupons_usos;
CREATE TRIGGER cupons_usos_sync AFTER INSERT OR DELETE OR UPDATE ON public.cupons_usos FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS despesas_sync ON public.despesas;
CREATE TRIGGER despesas_sync AFTER INSERT OR DELETE OR UPDATE ON public.despesas FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS despesas_recorrentes_sync ON public.despesas_recorrentes;
CREATE TRIGGER despesas_recorrentes_sync AFTER INSERT OR DELETE OR UPDATE ON public.despesas_recorrentes FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS entregas_fechadas_sync ON public.entregas_fechadas;
CREATE TRIGGER entregas_fechadas_sync AFTER INSERT OR DELETE OR UPDATE ON public.entregas_fechadas FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS estoque_sync ON public.estoque;
CREATE TRIGGER estoque_sync AFTER INSERT OR DELETE OR UPDATE ON public.estoque FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS eventos_atualizado ON public.eventos;
CREATE TRIGGER eventos_atualizado BEFORE UPDATE ON public.eventos FOR EACH ROW EXECUTE FUNCTION public.tocar_atualizado_em();
DROP TRIGGER IF EXISTS eventos_sync ON public.eventos;
CREATE TRIGGER eventos_sync AFTER INSERT OR DELETE OR UPDATE ON public.eventos FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS eventos_custos_sync ON public.eventos_custos;
CREATE TRIGGER eventos_custos_sync AFTER INSERT OR DELETE OR UPDATE ON public.eventos_custos FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS eventos_recebimentos_sync ON public.eventos_recebimentos;
CREATE TRIGGER eventos_recebimentos_sync AFTER INSERT OR DELETE OR UPDATE ON public.eventos_recebimentos FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS fechamentos_entrega_sync ON public.fechamentos_entrega;
CREATE TRIGGER fechamentos_entrega_sync AFTER INSERT OR DELETE OR UPDATE ON public.fechamentos_entrega FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS feedbacks_sync ON public.feedbacks;
CREATE TRIGGER feedbacks_sync AFTER INSERT OR DELETE OR UPDATE ON public.feedbacks FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS fidelidade_sync ON public.fidelidade;
CREATE TRIGGER fidelidade_sync AFTER INSERT OR DELETE OR UPDATE ON public.fidelidade FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS formas_pagamento_sync ON public.formas_pagamento;
CREATE TRIGGER formas_pagamento_sync AFTER INSERT OR DELETE OR UPDATE ON public.formas_pagamento FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS indicacoes_sync ON public.indicacoes;
CREATE TRIGGER indicacoes_sync AFTER INSERT OR DELETE OR UPDATE ON public.indicacoes FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS itens_venda_sync ON public.itens_venda;
CREATE TRIGGER itens_venda_sync AFTER INSERT OR DELETE OR UPDATE ON public.itens_venda FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS mesas_sync ON public.mesas;
CREATE TRIGGER mesas_sync AFTER INSERT OR DELETE OR UPDATE ON public.mesas FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS movimentacoes_estoque_sync ON public.movimentacoes_estoque;
CREATE TRIGGER movimentacoes_estoque_sync AFTER INSERT OR DELETE OR UPDATE ON public.movimentacoes_estoque FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS ocorrencias_sync ON public.ocorrencias;
CREATE TRIGGER ocorrencias_sync AFTER INSERT OR DELETE OR UPDATE ON public.ocorrencias FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS pagamentos_venda_sync ON public.pagamentos_venda;
CREATE TRIGGER pagamentos_venda_sync AFTER INSERT OR DELETE OR UPDATE ON public.pagamentos_venda FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS produto_adicionais_sync ON public.produto_adicionais;
CREATE TRIGGER produto_adicionais_sync AFTER INSERT OR DELETE OR UPDATE ON public.produto_adicionais FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS produto_ingredientes_sync ON public.produto_ingredientes;
CREATE TRIGGER produto_ingredientes_sync AFTER INSERT OR DELETE OR UPDATE ON public.produto_ingredientes FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS produto_precos_sync ON public.produto_precos;
CREATE TRIGGER produto_precos_sync AFTER INSERT OR DELETE OR UPDATE ON public.produto_precos FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS produtos_sync ON public.produtos;
CREATE TRIGGER produtos_sync AFTER INSERT OR DELETE OR UPDATE ON public.produtos FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS promocoes_sync ON public.promocoes;
CREATE TRIGGER promocoes_sync AFTER INSERT OR DELETE OR UPDATE ON public.promocoes FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS sangrias_sync ON public.sangrias;
CREATE TRIGGER sangrias_sync AFTER INSERT OR DELETE OR UPDATE ON public.sangrias FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS sistema_atualizado ON public.sistema;
CREATE TRIGGER sistema_atualizado BEFORE UPDATE ON public.sistema FOR EACH ROW EXECUTE FUNCTION public.tocar_atualizado_em();
DROP TRIGGER IF EXISTS sistema_sync ON public.sistema;
CREATE TRIGGER sistema_sync AFTER INSERT OR DELETE OR UPDATE ON public.sistema FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();
DROP TRIGGER IF EXISTS vendas_sync ON public.vendas;
CREATE TRIGGER vendas_sync AFTER INSERT OR DELETE OR UPDATE ON public.vendas FOR EACH ROW EXECUTE FUNCTION public.enfileirar_sync();

-- carimbo de versão para o sync incremental (dispara no COMMIT)
DROP TRIGGER IF EXISTS adicionais_versao ON public.adicionais;
CREATE CONSTRAINT TRIGGER adicionais_versao AFTER INSERT OR DELETE OR UPDATE ON public.adicionais DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS ajustes_pos_venda_versao ON public.ajustes_pos_venda;
CREATE CONSTRAINT TRIGGER ajustes_pos_venda_versao AFTER INSERT OR DELETE OR UPDATE ON public.ajustes_pos_venda DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS caixa_sessoes_versao ON public.caixa_sessoes;
CREATE CONSTRAINT TRIGGER caixa_sessoes_versao AFTER INSERT OR DELETE OR UPDATE ON public.caixa_sessoes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS categorias_versao ON public.categorias;
CREATE CONSTRAINT TRIGGER categorias_versao AFTER INSERT OR DELETE OR UPDATE ON public.categorias DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS clientes_versao ON public.clientes;
CREATE CONSTRAINT TRIGGER clientes_versao AFTER INSERT OR DELETE OR UPDATE ON public.clientes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS combo_itens_versao ON public.combo_itens;
CREATE CONSTRAINT TRIGGER combo_itens_versao AFTER INSERT OR DELETE OR UPDATE ON public.combo_itens DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS combo_precos_versao ON public.combo_precos;
CREATE CONSTRAINT TRIGGER combo_precos_versao AFTER INSERT OR DELETE OR UPDATE ON public.combo_precos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS combos_versao ON public.combos;
CREATE CONSTRAINT TRIGGER combos_versao AFTER INSERT OR DELETE OR UPDATE ON public.combos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS cupons_versao ON public.cupons;
CREATE CONSTRAINT TRIGGER cupons_versao AFTER INSERT OR DELETE OR UPDATE ON public.cupons DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS cupons_usos_versao ON public.cupons_usos;
CREATE CONSTRAINT TRIGGER cupons_usos_versao AFTER INSERT OR DELETE OR UPDATE ON public.cupons_usos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS despesas_versao ON public.despesas;
CREATE CONSTRAINT TRIGGER despesas_versao AFTER INSERT OR DELETE OR UPDATE ON public.despesas DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS despesas_recorrentes_versao ON public.despesas_recorrentes;
CREATE CONSTRAINT TRIGGER despesas_recorrentes_versao AFTER INSERT OR DELETE OR UPDATE ON public.despesas_recorrentes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS entregas_fechadas_versao ON public.entregas_fechadas;
CREATE CONSTRAINT TRIGGER entregas_fechadas_versao AFTER INSERT OR DELETE OR UPDATE ON public.entregas_fechadas DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS estoque_versao ON public.estoque;
CREATE CONSTRAINT TRIGGER estoque_versao AFTER INSERT OR DELETE OR UPDATE ON public.estoque DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS eventos_versao ON public.eventos;
CREATE CONSTRAINT TRIGGER eventos_versao AFTER INSERT OR DELETE OR UPDATE ON public.eventos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS eventos_custos_versao ON public.eventos_custos;
CREATE CONSTRAINT TRIGGER eventos_custos_versao AFTER INSERT OR DELETE OR UPDATE ON public.eventos_custos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS eventos_recebimentos_versao ON public.eventos_recebimentos;
CREATE CONSTRAINT TRIGGER eventos_recebimentos_versao AFTER INSERT OR DELETE OR UPDATE ON public.eventos_recebimentos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS fechamentos_entrega_versao ON public.fechamentos_entrega;
CREATE CONSTRAINT TRIGGER fechamentos_entrega_versao AFTER INSERT OR DELETE OR UPDATE ON public.fechamentos_entrega DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS feedbacks_versao ON public.feedbacks;
CREATE CONSTRAINT TRIGGER feedbacks_versao AFTER INSERT OR DELETE OR UPDATE ON public.feedbacks DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS fidelidade_versao ON public.fidelidade;
CREATE CONSTRAINT TRIGGER fidelidade_versao AFTER INSERT OR DELETE OR UPDATE ON public.fidelidade DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS formas_pagamento_versao ON public.formas_pagamento;
CREATE CONSTRAINT TRIGGER formas_pagamento_versao AFTER INSERT OR DELETE OR UPDATE ON public.formas_pagamento DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS indicacoes_versao ON public.indicacoes;
CREATE CONSTRAINT TRIGGER indicacoes_versao AFTER INSERT OR DELETE OR UPDATE ON public.indicacoes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS itens_venda_versao ON public.itens_venda;
CREATE CONSTRAINT TRIGGER itens_venda_versao AFTER INSERT OR DELETE OR UPDATE ON public.itens_venda DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS mesas_versao ON public.mesas;
CREATE CONSTRAINT TRIGGER mesas_versao AFTER INSERT OR DELETE OR UPDATE ON public.mesas DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS movimentacoes_estoque_versao ON public.movimentacoes_estoque;
CREATE CONSTRAINT TRIGGER movimentacoes_estoque_versao AFTER INSERT OR DELETE OR UPDATE ON public.movimentacoes_estoque DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS ocorrencias_versao ON public.ocorrencias;
CREATE CONSTRAINT TRIGGER ocorrencias_versao AFTER INSERT OR DELETE OR UPDATE ON public.ocorrencias DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS pagamentos_venda_versao ON public.pagamentos_venda;
CREATE CONSTRAINT TRIGGER pagamentos_venda_versao AFTER INSERT OR DELETE OR UPDATE ON public.pagamentos_venda DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS produto_adicionais_versao ON public.produto_adicionais;
CREATE CONSTRAINT TRIGGER produto_adicionais_versao AFTER INSERT OR DELETE OR UPDATE ON public.produto_adicionais DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS produto_ingredientes_versao ON public.produto_ingredientes;
CREATE CONSTRAINT TRIGGER produto_ingredientes_versao AFTER INSERT OR DELETE OR UPDATE ON public.produto_ingredientes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS produto_precos_versao ON public.produto_precos;
CREATE CONSTRAINT TRIGGER produto_precos_versao AFTER INSERT OR DELETE OR UPDATE ON public.produto_precos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS produtos_versao ON public.produtos;
CREATE CONSTRAINT TRIGGER produtos_versao AFTER INSERT OR DELETE OR UPDATE ON public.produtos DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS promocoes_versao ON public.promocoes;
CREATE CONSTRAINT TRIGGER promocoes_versao AFTER INSERT OR DELETE OR UPDATE ON public.promocoes DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS sangrias_versao ON public.sangrias;
CREATE CONSTRAINT TRIGGER sangrias_versao AFTER INSERT OR DELETE OR UPDATE ON public.sangrias DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS sistema_versao ON public.sistema;
CREATE CONSTRAINT TRIGGER sistema_versao AFTER INSERT OR DELETE OR UPDATE ON public.sistema DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS usuarios_versao ON public.usuarios;
CREATE CONSTRAINT TRIGGER usuarios_versao AFTER INSERT OR DELETE OR UPDATE ON public.usuarios DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();
DROP TRIGGER IF EXISTS vendas_versao ON public.vendas;
CREATE CONSTRAINT TRIGGER vendas_versao AFTER INSERT OR DELETE OR UPDATE ON public.vendas DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION public._bump_versao_sync();

-- 11. RLS E POLÍTICAS -------------------------------------------------
ALTER TABLE public.adicionais ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ajustes_pos_venda ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.backups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.caixa_sessoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categorias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.clientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combo_itens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combo_precos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.combos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.configuracoes_fotos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cupons_usos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.despesas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.despesas_recorrentes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entregas_fechadas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.estoque ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eventos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eventos_custos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.eventos_recebimentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fechamentos_entrega ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.feedbacks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fidelidade ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.fila_sync ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.formas_pagamento ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.indicacoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.itens_venda ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mesas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.mesas_codigos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.movimentacoes_estoque ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ocorrencias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pagamentos_venda ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produto_adicionais ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produto_ingredientes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produto_precos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produtos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promocoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.requisicoes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sangrias ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sistema ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tentativas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.usuarios ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.vendas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.versoes_sync ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "adicionais_admin" ON public.adicionais;
CREATE POLICY adicionais_admin ON public.adicionais AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "adicionais_ler" ON public.adicionais;
CREATE POLICY adicionais_ler ON public.adicionais AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "ajustes_pos_venda_ler_admin" ON public.ajustes_pos_venda;
CREATE POLICY ajustes_pos_venda_ler_admin ON public.ajustes_pos_venda AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "auditoria_ler_admin" ON public.auditoria;
CREATE POLICY auditoria_ler_admin ON public.auditoria AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "backups_ler_admin" ON public.backups;
CREATE POLICY backups_ler_admin ON public.backups AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "caixa_ler" ON public.caixa_sessoes;
CREATE POLICY caixa_ler ON public.caixa_sessoes AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "categorias_admin" ON public.categorias;
CREATE POLICY categorias_admin ON public.categorias AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "categorias_ler" ON public.categorias;
CREATE POLICY categorias_ler ON public.categorias AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "clientes_alterar" ON public.clientes;
CREATE POLICY clientes_alterar ON public.clientes AS PERMISSIVE FOR UPDATE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso]));
DROP POLICY IF EXISTS "clientes_criar" ON public.clientes;
CREATE POLICY clientes_criar ON public.clientes AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso]));
DROP POLICY IF EXISTS "clientes_excluir" ON public.clientes;
CREATE POLICY clientes_excluir ON public.clientes AS PERMISSIVE FOR DELETE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "clientes_ler" ON public.clientes;
CREATE POLICY clientes_ler ON public.clientes AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso]));
DROP POLICY IF EXISTS "combo_itens_admin" ON public.combo_itens;
CREATE POLICY combo_itens_admin ON public.combo_itens AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "combo_itens_ler" ON public.combo_itens;
CREATE POLICY combo_itens_ler ON public.combo_itens AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "combo_precos_admin" ON public.combo_precos;
CREATE POLICY combo_precos_admin ON public.combo_precos AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "combo_precos_ler" ON public.combo_precos;
CREATE POLICY combo_precos_ler ON public.combo_precos AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "combos_admin" ON public.combos;
CREATE POLICY combos_admin ON public.combos AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "combos_ler" ON public.combos;
CREATE POLICY combos_ler ON public.combos AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "fotos_cfg_admin" ON public.configuracoes_fotos;
CREATE POLICY fotos_cfg_admin ON public.configuracoes_fotos AS PERMISSIVE FOR UPDATE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "fotos_cfg_ler" ON public.configuracoes_fotos;
CREATE POLICY fotos_cfg_ler ON public.configuracoes_fotos AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "cupons_ler_admin" ON public.cupons;
CREATE POLICY cupons_ler_admin ON public.cupons AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "cupons_usos_ler" ON public.cupons_usos;
CREATE POLICY cupons_usos_ler ON public.cupons_usos AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "despesas_alterar" ON public.despesas;
CREATE POLICY despesas_alterar ON public.despesas AS PERMISSIVE FOR UPDATE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "despesas_criar" ON public.despesas;
CREATE POLICY despesas_criar ON public.despesas AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "despesas_ler" ON public.despesas;
CREATE POLICY despesas_ler ON public.despesas AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "despesas_recorrentes_ler_admin" ON public.despesas_recorrentes;
CREATE POLICY despesas_recorrentes_ler_admin ON public.despesas_recorrentes AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "entregas_fechadas_ler" ON public.entregas_fechadas;
CREATE POLICY entregas_fechadas_ler ON public.entregas_fechadas AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "entregas_fechadas_ler_admin" ON public.entregas_fechadas;
CREATE POLICY entregas_fechadas_ler_admin ON public.entregas_fechadas AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "entregas_fechadas_ler_entregador" ON public.entregas_fechadas;
CREATE POLICY entregas_fechadas_ler_entregador ON public.entregas_fechadas AS PERMISSIVE FOR SELECT TO authenticated USING ((tem_nivel(VARIADIC ARRAY['Entregador'::nivel_acesso]) AND (entregador_id = ( SELECT auth.uid() AS uid))));
DROP POLICY IF EXISTS "estoque_admin" ON public.estoque;
CREATE POLICY estoque_admin ON public.estoque AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "estoque_ler" ON public.estoque;
CREATE POLICY estoque_ler ON public.estoque AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "eventos_ler_admin" ON public.eventos;
CREATE POLICY eventos_ler_admin ON public.eventos AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "eventos_custos_ler_admin" ON public.eventos_custos;
CREATE POLICY eventos_custos_ler_admin ON public.eventos_custos AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "eventos_recebimentos_ler_admin" ON public.eventos_recebimentos;
CREATE POLICY eventos_recebimentos_ler_admin ON public.eventos_recebimentos AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "fechamentos_entrega_ler" ON public.fechamentos_entrega;
CREATE POLICY fechamentos_entrega_ler ON public.fechamentos_entrega AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "fechamentos_entrega_ler_admin" ON public.fechamentos_entrega;
CREATE POLICY fechamentos_entrega_ler_admin ON public.fechamentos_entrega AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "fechamentos_entrega_ler_entregador" ON public.fechamentos_entrega;
CREATE POLICY fechamentos_entrega_ler_entregador ON public.fechamentos_entrega AS PERMISSIVE FOR SELECT TO authenticated USING ((tem_nivel(VARIADIC ARRAY['Entregador'::nivel_acesso]) AND (entregador_id = ( SELECT auth.uid() AS uid))));
DROP POLICY IF EXISTS "feedbacks_ler" ON public.feedbacks;
CREATE POLICY feedbacks_ler ON public.feedbacks AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "feedbacks_status" ON public.feedbacks;
CREATE POLICY feedbacks_status ON public.feedbacks AS PERMISSIVE FOR UPDATE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "fidelidade_ler" ON public.fidelidade;
CREATE POLICY fidelidade_ler ON public.fidelidade AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "fila_sync_ler_admin" ON public.fila_sync;
CREATE POLICY fila_sync_ler_admin ON public.fila_sync AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "formas_pagamento_admin" ON public.formas_pagamento;
CREATE POLICY formas_pagamento_admin ON public.formas_pagamento AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "formas_pagamento_ler" ON public.formas_pagamento;
CREATE POLICY formas_pagamento_ler ON public.formas_pagamento AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "indicacoes_ler" ON public.indicacoes;
CREATE POLICY indicacoes_ler ON public.indicacoes AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "itens_venda_alterar" ON public.itens_venda;
CREATE POLICY itens_venda_alterar ON public.itens_venda AS PERMISSIVE FOR UPDATE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "itens_venda_criar" ON public.itens_venda;
CREATE POLICY itens_venda_criar ON public.itens_venda AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso]) AND (EXISTS ( SELECT 1
   FROM vendas v
  WHERE (v.id = itens_venda.venda_id)))));
DROP POLICY IF EXISTS "itens_venda_ler" ON public.itens_venda;
CREATE POLICY itens_venda_ler ON public.itens_venda AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM vendas v
  WHERE (v.id = itens_venda.venda_id))));
DROP POLICY IF EXISTS "mesas_admin_criar" ON public.mesas;
CREATE POLICY mesas_admin_criar ON public.mesas AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "mesas_admin_excluir" ON public.mesas;
CREATE POLICY mesas_admin_excluir ON public.mesas AS PERMISSIVE FOR DELETE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "mesas_ler" ON public.mesas;
CREATE POLICY mesas_ler ON public.mesas AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso]));
DROP POLICY IF EXISTS "mesas_status" ON public.mesas;
CREATE POLICY mesas_status ON public.mesas AS PERMISSIVE FOR UPDATE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso]));
DROP POLICY IF EXISTS "mov_estoque_ler" ON public.movimentacoes_estoque;
CREATE POLICY mov_estoque_ler ON public.movimentacoes_estoque AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "ocorrencias_alterar" ON public.ocorrencias;
CREATE POLICY ocorrencias_alterar ON public.ocorrencias AS PERMISSIVE FOR UPDATE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "ocorrencias_criar" ON public.ocorrencias;
CREATE POLICY ocorrencias_criar ON public.ocorrencias AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((auth_nivel() IS NOT NULL) AND (registrado_por = auth.uid())));
DROP POLICY IF EXISTS "ocorrencias_ler" ON public.ocorrencias;
CREATE POLICY ocorrencias_ler ON public.ocorrencias AS PERMISSIVE FOR SELECT TO authenticated USING ((tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]) OR (registrado_por = auth.uid())));
DROP POLICY IF EXISTS "pagamentos_venda_alterar" ON public.pagamentos_venda;
CREATE POLICY pagamentos_venda_alterar ON public.pagamentos_venda AS PERMISSIVE FOR UPDATE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "pagamentos_venda_criar" ON public.pagamentos_venda;
CREATE POLICY pagamentos_venda_criar ON public.pagamentos_venda AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Garçom'::nivel_acesso]) AND (EXISTS ( SELECT 1
   FROM vendas v
  WHERE (v.id = pagamentos_venda.venda_id)))));
DROP POLICY IF EXISTS "pagamentos_venda_ler" ON public.pagamentos_venda;
CREATE POLICY pagamentos_venda_ler ON public.pagamentos_venda AS PERMISSIVE FOR SELECT TO authenticated USING ((tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso, 'Entregador'::nivel_acesso]) AND (EXISTS ( SELECT 1
   FROM vendas v
  WHERE (v.id = pagamentos_venda.venda_id)))));
DROP POLICY IF EXISTS "produto_adicionais_admin" ON public.produto_adicionais;
CREATE POLICY produto_adicionais_admin ON public.produto_adicionais AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "produto_adicionais_ler" ON public.produto_adicionais;
CREATE POLICY produto_adicionais_ler ON public.produto_adicionais AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "produto_ingredientes_admin" ON public.produto_ingredientes;
CREATE POLICY produto_ingredientes_admin ON public.produto_ingredientes AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "produto_ingredientes_ler" ON public.produto_ingredientes;
CREATE POLICY produto_ingredientes_ler ON public.produto_ingredientes AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "produto_precos_admin" ON public.produto_precos;
CREATE POLICY produto_precos_admin ON public.produto_precos AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "produto_precos_ler" ON public.produto_precos;
CREATE POLICY produto_precos_ler ON public.produto_precos AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "produtos_admin" ON public.produtos;
CREATE POLICY produtos_admin ON public.produtos AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "produtos_ler" ON public.produtos;
CREATE POLICY produtos_ler ON public.produtos AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "promocoes_admin" ON public.promocoes;
CREATE POLICY promocoes_admin ON public.promocoes AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "promocoes_ler" ON public.promocoes;
CREATE POLICY promocoes_ler ON public.promocoes AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "sangrias_criar" ON public.sangrias;
CREATE POLICY sangrias_criar ON public.sangrias AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "sangrias_ler" ON public.sangrias;
CREATE POLICY sangrias_ler ON public.sangrias AS PERMISSIVE FOR SELECT TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "sistema_admin" ON public.sistema;
CREATE POLICY sistema_admin ON public.sistema AS PERMISSIVE FOR ALL TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso]));
DROP POLICY IF EXISTS "sistema_ler" ON public.sistema;
CREATE POLICY sistema_ler ON public.sistema AS PERMISSIVE FOR SELECT TO authenticated USING ((auth_nivel() IS NOT NULL));
DROP POLICY IF EXISTS "usuarios_ler_proprio" ON public.usuarios;
CREATE POLICY usuarios_ler_proprio ON public.usuarios AS PERMISSIVE FOR SELECT TO authenticated USING (((id = auth.uid()) OR tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso])));
DROP POLICY IF EXISTS "vendas_alterar" ON public.vendas;
CREATE POLICY vendas_alterar ON public.vendas AS PERMISSIVE FOR UPDATE TO authenticated USING (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso])) WITH CHECK (tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]));
DROP POLICY IF EXISTS "vendas_criar" ON public.vendas;
CREATE POLICY vendas_criar ON public.vendas AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]) OR (tem_nivel(VARIADIC ARRAY['Garçom'::nivel_acesso]) AND (registrado_por = auth.uid()))));
DROP POLICY IF EXISTS "vendas_ler" ON public.vendas;
CREATE POLICY vendas_ler ON public.vendas AS PERMISSIVE FOR SELECT TO authenticated USING ((tem_nivel(VARIADIC ARRAY['Admin'::nivel_acesso, 'Operador'::nivel_acesso]) OR (tem_nivel(VARIADIC ARRAY['Garçom'::nivel_acesso]) AND ((tipo = 'Mesa'::venda_tipo) OR (registrado_por = auth.uid()))) OR (tem_nivel(VARIADIC ARRAY['Cozinha'::nivel_acesso]) AND (status = 'Confirmada'::venda_status) AND (status_pedido = ANY (ARRAY['Recebido'::status_pedido, 'Em preparo'::status_pedido, 'Pronta'::status_pedido, 'Suspenso'::status_pedido]))) OR (tem_nivel(VARIADIC ARRAY['Entregador'::nivel_acesso]) AND (tipo = 'Entrega'::venda_tipo) AND (entregador_id = auth.uid()))));

-- 12. PERMISSÕES ------------------------------------------------------
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
GRANT ALL ON TABLE public.adicionais TO authenticated, service_role;
GRANT ALL ON TABLE public.ajustes_pos_venda TO authenticated, service_role;
GRANT ALL ON TABLE public.auditoria TO authenticated, service_role;
GRANT ALL ON TABLE public.backups TO authenticated, service_role;
GRANT ALL ON TABLE public.caixa_sessoes TO authenticated, service_role;
GRANT ALL ON TABLE public.categorias TO authenticated, service_role;
GRANT ALL ON TABLE public.clientes TO authenticated, service_role;
GRANT ALL ON TABLE public.combo_itens TO authenticated, service_role;
GRANT ALL ON TABLE public.combo_precos TO authenticated, service_role;
GRANT ALL ON TABLE public.combos TO authenticated, service_role;
GRANT ALL ON TABLE public.configuracoes_fotos TO authenticated, service_role;
GRANT ALL ON TABLE public.cupons TO authenticated, service_role;
GRANT ALL ON TABLE public.cupons_usos TO authenticated, service_role;
GRANT ALL ON TABLE public.despesas TO authenticated, service_role;
GRANT ALL ON TABLE public.despesas_recorrentes TO authenticated, service_role;
GRANT ALL ON TABLE public.entregas_fechadas TO authenticated, service_role;
GRANT ALL ON TABLE public.estoque TO authenticated, service_role;
GRANT ALL ON TABLE public.eventos TO authenticated, service_role;
GRANT ALL ON TABLE public.eventos_custos TO authenticated, service_role;
GRANT ALL ON TABLE public.eventos_recebimentos TO authenticated, service_role;
GRANT ALL ON TABLE public.fechamentos_entrega TO authenticated, service_role;
GRANT ALL ON TABLE public.feedbacks TO authenticated, service_role;
GRANT ALL ON TABLE public.fidelidade TO authenticated, service_role;
GRANT ALL ON TABLE public.fila_sync TO authenticated, service_role;
GRANT ALL ON TABLE public.formas_pagamento TO authenticated, service_role;
GRANT ALL ON TABLE public.indicacoes TO authenticated, service_role;
GRANT ALL ON TABLE public.itens_venda TO authenticated, service_role;
GRANT ALL ON TABLE public.mesas TO authenticated, service_role;
GRANT ALL ON TABLE public.mesas_codigos TO authenticated, service_role;
GRANT ALL ON TABLE public.movimentacoes_estoque TO authenticated, service_role;
GRANT ALL ON TABLE public.ocorrencias TO authenticated, service_role;
GRANT ALL ON TABLE public.pagamentos_venda TO authenticated, service_role;
GRANT ALL ON TABLE public.produto_adicionais TO authenticated, service_role;
GRANT ALL ON TABLE public.produto_ingredientes TO authenticated, service_role;
GRANT ALL ON TABLE public.produto_precos TO authenticated, service_role;
GRANT ALL ON TABLE public.produtos TO authenticated, service_role;
GRANT ALL ON TABLE public.promocoes TO authenticated, service_role;
GRANT ALL ON TABLE public.requisicoes TO authenticated, service_role;
GRANT ALL ON TABLE public.sangrias TO authenticated, service_role;
GRANT ALL ON TABLE public.sistema TO authenticated, service_role;
GRANT ALL ON TABLE public.tentativas TO authenticated, service_role;
GRANT ALL ON TABLE public.usuarios TO authenticated, service_role;
GRANT ALL ON TABLE public.vendas TO authenticated, service_role;
REVOKE ALL ON TABLE public.versoes_sync FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.versoes_sync TO service_role;
REVOKE ALL ON TABLE public.v_cardapio_adicionais FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_adicionais TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_adicionais TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_adicionais TO anon;
REVOKE ALL ON TABLE public.v_cardapio_categorias FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_categorias TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_categorias TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_categorias TO anon;
REVOKE ALL ON TABLE public.v_cardapio_combo_itens FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_combo_itens TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_combo_itens TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_combo_itens TO anon;
REVOKE ALL ON TABLE public.v_cardapio_combos FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_combos TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_combos TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_combos TO anon;
REVOKE ALL ON TABLE public.v_cardapio_config FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_config TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_config TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_config TO anon;
REVOKE ALL ON TABLE public.v_cardapio_esgotados FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_esgotados TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_esgotados TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_esgotados TO anon;
REVOKE ALL ON TABLE public.v_cardapio_formas FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_formas TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_formas TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_formas TO anon;
REVOKE ALL ON TABLE public.v_cardapio_mais_pedidos FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_mais_pedidos TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_mais_pedidos TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_mais_pedidos TO anon;
REVOKE ALL ON TABLE public.v_cardapio_precos FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_precos TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_precos TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_precos TO anon;
REVOKE ALL ON TABLE public.v_cardapio_produtos FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_produtos TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_produtos TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_produtos TO anon;
REVOKE ALL ON TABLE public.v_cardapio_status FROM anon, authenticated;
GRANT ALL ON TABLE public.v_cardapio_status TO service_role;
GRANT SELECT ON TABLE public.v_cardapio_status TO authenticated;
GRANT SELECT ON TABLE public.v_cardapio_status TO anon;
REVOKE ALL ON TABLE public.v_fidelidade FROM anon, authenticated;
GRANT ALL ON TABLE public.v_fidelidade TO service_role;
GRANT SELECT ON TABLE public.v_fidelidade TO authenticated;
REVOKE ALL ON TABLE public.v_indicacoes FROM anon, authenticated;
GRANT ALL ON TABLE public.v_indicacoes TO service_role;
GRANT SELECT ON TABLE public.v_indicacoes TO authenticated;
REVOKE ALL ON TABLE public.v_itens_venda FROM anon, authenticated;
GRANT ALL ON TABLE public.v_itens_venda TO service_role;
GRANT SELECT ON TABLE public.v_itens_venda TO authenticated;
REVOKE ALL ON TABLE public.v_mesas FROM anon, authenticated;
GRANT ALL ON TABLE public.v_mesas TO service_role;
GRANT SELECT ON TABLE public.v_mesas TO authenticated;
REVOKE ALL ON TABLE public.v_ocorrencias FROM anon, authenticated;
GRANT ALL ON TABLE public.v_ocorrencias TO service_role;
GRANT SELECT ON TABLE public.v_ocorrencias TO authenticated;
REVOKE ALL ON TABLE public.v_sessao_aberta FROM anon, authenticated;
GRANT ALL ON TABLE public.v_sessao_aberta TO service_role;
GRANT SELECT ON TABLE public.v_sessao_aberta TO authenticated;
REVOKE ALL ON TABLE public.v_vendas FROM anon, authenticated;
GRANT ALL ON TABLE public.v_vendas TO service_role;
GRANT SELECT ON TABLE public.v_vendas TO authenticated;
REVOKE ALL ON FUNCTION public._agora_br() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._agora_br() TO service_role;
REVOKE ALL ON FUNCTION public._ajustar_estoque(p_itens jsonb, p_dir integer, p_venda uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._ajustar_estoque(p_itens jsonb, p_dir integer, p_venda uuid) TO service_role;
REVOKE ALL ON FUNCTION public._auditar(p_acao text, p_detalhes text, p_telefone text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._auditar(p_acao text, p_detalhes text, p_telefone text) TO service_role;
REVOKE ALL ON FUNCTION public._auditar_publico(p_acao text, p_detalhes text, p_tel text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._auditar_publico(p_acao text, p_detalhes text, p_tel text) TO service_role;
REVOKE ALL ON FUNCTION public._bump_versao_sync() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._bump_versao_sync() TO service_role;
REVOKE ALL ON FUNCTION public._calc_fechamento_entrega(p_login text, p_data date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._calc_fechamento_entrega(p_login text, p_data date) TO service_role;
REVOKE ALL ON FUNCTION public._carimbar_fidelidade(p_tel text, p_nome text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._carimbar_fidelidade(p_tel text, p_nome text) TO service_role;
REVOKE ALL ON FUNCTION public._categoria_despesa(v text, padrao text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._categoria_despesa(v text, padrao text) TO service_role;
REVOKE ALL ON FUNCTION public._cfg_gravar(p_chave text, p_valor jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cfg_gravar(p_chave text, p_valor jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._combo_gravar_itens(p_combo uuid, p_itens jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._combo_gravar_itens(p_combo uuid, p_itens jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._combo_gravar_precos(p_combo uuid, p_precos jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._combo_gravar_precos(p_combo uuid, p_precos jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._comp_valida(v text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._comp_valida(v text) TO service_role;
REVOKE ALL ON FUNCTION public._competencia_atual() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._competencia_atual() TO service_role;
REVOKE ALL ON FUNCTION public._conflito(p_msg text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._conflito(p_msg text) TO service_role;
REVOKE ALL ON FUNCTION public._consumo(p_itens jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._consumo(p_itens jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._criar_login_auth(p_id uuid, p_email text, p_senha text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._criar_login_auth(p_id uuid, p_email text, p_senha text) TO service_role;
REVOKE ALL ON FUNCTION public._criar_pedido_publico(p jsonb, p_mesa_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._criar_pedido_publico(p jsonb, p_mesa_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public._cupom_calcular(p_codigo text, p_tel text, p_subtotal numeric, p_tipo text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cupom_calcular(p_codigo text, p_tel text, p_subtotal numeric, p_tipo text) TO service_role;
REVOKE ALL ON FUNCTION public._cupom_validar(p jsonb, p_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._cupom_validar(p jsonb, p_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public._data_iso(v text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._data_iso(v text) TO service_role;
REVOKE ALL ON FUNCTION public._dinheiro(v numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._dinheiro(v numeric) TO service_role;
REVOKE ALL ON FUNCTION public._email_login(p_login text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._email_login(p_login text) TO service_role;
REVOKE ALL ON FUNCTION public._erro_recorrente(p_desc text, p_valor numeric, p_dia numeric, p_period text, p_inicio text, p_termino text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._erro_recorrente(p_desc text, p_valor numeric, p_dia numeric, p_period text, p_inicio text, p_termino text) TO service_role;
REVOKE ALL ON FUNCTION public._erro_senha_fraca(p_senha text, p_login text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._erro_senha_fraca(p_senha text, p_login text) TO service_role;
REVOKE ALL ON FUNCTION public._estoque_proprio(p_atual uuid, p_nome text, p_ep jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._estoque_proprio(p_atual uuid, p_nome text, p_ep jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._evento_json(p_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._evento_json(p_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public._excedeu(p_chave text, p_max integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._excedeu(p_chave text, p_max integer) TO service_role;
REVOKE ALL ON FUNCTION public._exige_admin(p_senha text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._exige_admin(p_senha text) TO service_role;
REVOKE ALL ON FUNCTION public._falha(p_msg text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._falha(p_msg text) TO service_role;
REVOKE ALL ON FUNCTION public._gerar_despesas_recorrentes(p_comp text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._gerar_despesas_recorrentes(p_comp text) TO service_role;
REVOKE ALL ON FUNCTION public._hora_valida(v text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._hora_valida(v text) TO service_role;
REVOKE ALL ON FUNCTION public._idem_gravar(p_chave text, p_acao text, p_resultado jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._idem_gravar(p_chave text, p_acao text, p_resultado jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._idem_ler(p_chave text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._idem_ler(p_chave text) TO service_role;
REVOKE ALL ON FUNCTION public._ip_cliente() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._ip_cliente() TO service_role;
REVOKE ALL ON FUNCTION public._itens_da_venda(p_venda uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._itens_da_venda(p_venda uuid) TO service_role;
REVOKE ALL ON FUNCTION public._limpar_falhas(p_chave text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._limpar_falhas(p_chave text) TO service_role;
REVOKE ALL ON FUNCTION public._lista_curta(p_itens text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._lista_curta(p_itens text[]) TO service_role;
REVOKE ALL ON FUNCTION public._lista_qr_mesas() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._lista_qr_mesas() TO service_role;
REVOKE ALL ON FUNCTION public._login_de(p_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._login_de(p_id uuid) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public._meio_dia(d date) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._meio_dia(d date) TO service_role;
REVOKE ALL ON FUNCTION public._mesa_qr(p_numero text, p_codigo text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._mesa_qr(p_numero text, p_codigo text) TO service_role;
REVOKE ALL ON FUNCTION public._meses_periodicidade(p text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._meses_periodicidade(p text) TO service_role;
REVOKE ALL ON FUNCTION public._negado() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._negado() TO service_role;
REVOKE ALL ON FUNCTION public._num(v text, padrao numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._num(v text, padrao numeric) TO service_role;
REVOKE ALL ON FUNCTION public._pedido_trava(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._pedido_trava(p jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._precos_ou_base(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._precos_ou_base(p jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._produto_gravar_adicionais(p_prod uuid, p_ads jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._produto_gravar_adicionais(p_prod uuid, p_ads jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._produto_gravar_precos(p_prod uuid, p_precos jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._produto_gravar_precos(p_prod uuid, p_precos jsonb) TO service_role;
REVOKE ALL ON FUNCTION public._produto_gravar_receita(p_prod uuid, p_ingr jsonb, p_proprio uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._produto_gravar_receita(p_prod uuid, p_ingr jsonb, p_proprio uuid) TO service_role;
REVOKE ALL ON FUNCTION public._recalcular_evento(p_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._recalcular_evento(p_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public._registrar_falha(p_chave text, p_seg integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._registrar_falha(p_chave text, p_seg integer) TO service_role;
REVOKE ALL ON FUNCTION public._senha_confere(p_user uuid, p_senha text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._senha_confere(p_user uuid, p_senha text) TO service_role;
REVOKE ALL ON FUNCTION public._so_digitos(t text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._so_digitos(t text) TO authenticated, service_role; -- v_indicacoes (carga do app) chama esta função
REVOKE ALL ON FUNCTION public._texto_publico(t text, mx integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._texto_publico(t text, mx integer) TO service_role;
REVOKE ALL ON FUNCTION public._upsert_cliente(p_tel text, p_nome text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._upsert_cliente(p_tel text, p_nome text) TO service_role;
REVOKE ALL ON FUNCTION public._uuid(v text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._uuid(v text) TO service_role;
REVOKE ALL ON FUNCTION public._validar_forma(pct numeric, fixa numeric, prazo numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._validar_forma(pct numeric, fixa numeric, prazo numeric) TO service_role;
REVOKE ALL ON FUNCTION public._versao_conflita(p jsonb, p_tab text, p_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._versao_conflita(p jsonb, p_tab text, p_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public._versoes_tabela(p_tab text, p_id uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._versoes_tabela(p_tab text, p_id uuid) TO service_role;
REVOKE ALL ON FUNCTION public.api_abrir_caixa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_abrir_caixa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_aceitar_pedido(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_aceitar_pedido(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_adicional(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_adicional(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_categoria(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_categoria(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_combo(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_combo(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_despesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_despesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_despesa_recorrente(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_despesa_recorrente(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_feedback(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_feedback(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_add_forma_pagamento(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_forma_pagamento(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_ingrediente(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_ingrediente(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_mesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_or_stamp_fidelidade(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_or_stamp_fidelidade(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_produto(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_produto(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_add_sangria(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_add_sangria(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_adicionar_custo_evento(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_adicionar_custo_evento(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_adicionar_recebimento_evento(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_adicionar_recebimento_evento(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_alternar_cupom(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_alternar_cupom(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_aplicar_preco_calculadora(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_aplicar_preco_calculadora(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_atender_chamado_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_atender_chamado_mesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_atribuir_entregador(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_atribuir_entregador(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_atualizar_ocorrencia(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_atualizar_ocorrencia(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_avancar_status_pedido(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_avancar_status_pedido(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_cancelar_ajuste_pos_venda(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_cancelar_ajuste_pos_venda(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_cancelar_despesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_cancelar_despesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_cancelar_evento(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_cancelar_evento(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_cancelar_pedido_cardapio_publico(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_cancelar_pedido_cardapio_publico(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_cancelar_pedido_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_cancelar_pedido_mesa(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_cancelar_venda(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_cancelar_venda(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_chamar_garcom_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_chamar_garcom_mesa(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_confirmar_recebimento_pedido(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_confirmar_recebimento_pedido(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_criar_pedido_cardapio(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_criar_pedido_cardapio(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_criar_pedido_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_criar_pedido_mesa(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_criar_usuario(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_criar_usuario(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_detectar_novos_pedidos(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_detectar_novos_pedidos(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_adicional(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_adicional(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_categoria(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_categoria(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_combo(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_combo(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_cupom(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_cupom(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_despesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_despesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_despesa_recorrente(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_despesa_recorrente(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_forma_pagamento(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_forma_pagamento(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_ingrediente(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_ingrediente(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_ordem_cardapio_combo(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_ordem_cardapio_combo(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_ordem_cardapio_produto(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_ordem_cardapio_produto(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_produto(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_produto(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_status_feedback(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_status_feedback(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_status_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_status_mesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_usuario(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_usuario(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_venda(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_venda(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_visibilidade_cardapio_combo(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_visibilidade_cardapio_combo(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_editar_visibilidade_cardapio_produto(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_editar_visibilidade_cardapio_produto(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_encerrar_sessao_remota(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_encerrar_sessao_remota(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_excluir_adicional(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_excluir_adicional(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_excluir_categoria(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_excluir_categoria(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_excluir_cliente(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_excluir_cliente(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_excluir_combo(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_excluir_combo(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_excluir_ingrediente(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_excluir_ingrediente(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_excluir_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_excluir_mesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_excluir_produto(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_excluir_produto(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_excluir_usuario(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_excluir_usuario(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_fechar_caixa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_fechar_caixa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_fechar_conta_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_fechar_conta_mesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_fechar_periodo_entregador(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_fechar_periodo_entregador(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_garantir_despesas_do_mes(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_garantir_despesas_do_mes(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_gerar_despesas_mes(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_gerar_despesas_mes(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_gerar_novo_codigo_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_gerar_novo_codigo_mesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_get_mesa_publica(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_get_mesa_publica(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_get_qr_mesas(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_get_qr_mesas(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_get_status_pedido_publico(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_get_status_pedido_publico(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_indicar_novo_cliente(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_indicar_novo_cliente(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_iniciar_preparo_pedido(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_iniciar_preparo_pedido(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_iniciar_venda(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_iniciar_venda(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_listar_sessoes(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_listar_sessoes(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_pagar_despesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_pagar_despesa(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_pedir_conta_mesa(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_pedir_conta_mesa(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_preview_fechamento_entrega(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_preview_fechamento_entrega(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_registrar_ajuste_pos_venda(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_registrar_ajuste_pos_venda(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_registrar_entrada_estoque(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_registrar_entrada_estoque(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_registrar_inventario_estoque(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_registrar_inventario_estoque(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_registrar_ocorrencia(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_registrar_ocorrencia(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_registrar_perda_estoque(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_registrar_perda_estoque(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_rejeitar_pedido(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_rejeitar_pedido(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_resgatar_premio_fidelidade(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_resgatar_premio_fidelidade(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_retomar_pedido(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_retomar_pedido(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_salvar_cliente(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_salvar_cliente(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_salvar_config_cardapio(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_salvar_config_cardapio(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_salvar_config_entrega(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_salvar_config_entrega(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_salvar_config_estoque(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_salvar_config_estoque(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_salvar_config_notificacoes(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_salvar_config_notificacoes(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_salvar_cupom(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_salvar_cupom(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_salvar_evento(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_salvar_evento(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_salvar_meta(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_salvar_meta(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_seed_cardapio_texas_burger(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_seed_cardapio_texas_burger(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_simular_precificacao(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_simular_precificacao(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_suspender_pedido(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_suspender_pedido(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_toggle_resgate_indicacao(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_toggle_resgate_indicacao(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_trocar_minha_senha(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_trocar_minha_senha(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_validar_cupom_cardapio(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_validar_cupom_cardapio(p jsonb) TO service_role, authenticated, anon;
REVOKE ALL ON FUNCTION public.api_verificar_senha_admin(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_verificar_senha_admin(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_versoes() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_versoes() TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_versoes_registros(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_versoes_registros(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.api_vincular_adicionais_em_lote(p jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_vincular_adicionais_em_lote(p jsonb) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.auth_nivel() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auth_nivel() TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.enfileirar_sync() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.enfileirar_sync() TO service_role;
REVOKE ALL ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.rls_auto_enable() TO service_role;
REVOKE ALL ON FUNCTION public.tem_nivel(VARIADIC niveis nivel_acesso[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tem_nivel(VARIADIC niveis nivel_acesso[]) TO service_role, authenticated;
REVOKE ALL ON FUNCTION public.tocar_atualizado_em() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tocar_atualizado_em() TO service_role;

-- 13. AJUSTE DAS SEQUÊNCIAS -------------------------------------------
SELECT setval('public.vendas_numero_pedido_seq', 34, true);
SELECT setval(pg_get_serial_sequence('public.auditoria','id'), 188, true);
SELECT setval(pg_get_serial_sequence('public.fila_sync','id'), 2767, true);
-- ocorrencias_numero_seq: ainda não usada (começa em 1)

-- OPCIONAL (exige superusuário; o Supabase já cria): trigger de evento que liga RLS em tabelas novas
-- CREATE EVENT TRIGGER ensure_rls ON ddl_command_end EXECUTE FUNCTION public.rls_auto_enable();

-- FIM

-- 14. ETAPAS 4 A 10 --------------------------------------------------
-- Antes: SELECT vault.create_secret('<service_role_key>','service_key');  (uma vez)
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ═════ ETAPA 4 — SINCRONIZAÇÃO EM SEGUNDO PLANO ═════
CREATE INDEX IF NOT EXISTS fila_sync_pend_principal_idx ON public.fila_sync (id) WHERE principal_ok_em IS NULL;
CREATE INDEX IF NOT EXISTS fila_sync_pend_contingencia_idx ON public.fila_sync (id) WHERE contingencia_ok_em IS NULL;

CREATE TABLE IF NOT EXISTS public.sync_estado (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  principal_ultimo_ok timestamptz, principal_ultimo_erro timestamptz, principal_ultimo_erro_msg text,
  contingencia_ultimo_ok timestamptz, contingencia_ultimo_erro timestamptz, contingencia_ultimo_erro_msg text,
  contingencia_atraso_minutos int NOT NULL DEFAULT 60,
  alerta_itens_limite int NOT NULL DEFAULT 500,
  alerta_horas_limite int NOT NULL DEFAULT 6,
  atualizado_em timestamptz NOT NULL DEFAULT now());
INSERT INTO public.sync_estado (id) VALUES (true) ON CONFLICT DO NOTHING;
ALTER TABLE public.sync_estado ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sync_estado_admin ON public.sync_estado;
CREATE POLICY sync_estado_admin ON public.sync_estado FOR ALL TO authenticated
  USING (tem_nivel('Admin')) WITH CHECK (tem_nivel('Admin'));
GRANT ALL ON public.sync_estado TO authenticated, service_role;

-- Mesma função de antes + trava: o arquivamento apaga SEM enfileirar
-- (senão o DELETE chegaria na planilha e apagaria o que foi arquivado lá).
CREATE OR REPLACE FUNCTION public.enfileirar_sync()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
declare reg jsonb; rid text;
begin
  if current_setting('txb.sem_fila', true) = 'on' then return null; end if;
  if tg_op = 'DELETE' then reg := to_jsonb(old); else reg := to_jsonb(new); end if;
  rid := coalesce(reg->>'id', reg->>'chave');
  insert into fila_sync (tabela, registro_id, operacao, payload)
  values (tg_table_name, rid, tg_op::op_sync, case when tg_op = 'DELETE' then null else reg end);
  return null;
end $function$;

CREATE OR REPLACE FUNCTION public.api_sync_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_e sync_estado%rowtype;
BEGIN
  IF NOT tem_nivel('Admin','Operador') THEN RETURN _negado(); END IF;
  SELECT * INTO v_e FROM sync_estado WHERE id=true;
  RETURN jsonb_build_object('ok',true,
    'pendentes_principal',(SELECT count(*) FROM fila_sync WHERE principal_ok_em IS NULL),
    'pendentes_contingencia',(SELECT count(*) FROM fila_sync WHERE contingencia_ok_em IS NULL),
    'erros_principal',(SELECT count(*) FROM fila_sync WHERE principal_erro IS NOT NULL AND principal_ok_em IS NULL),
    'erros_contingencia',(SELECT count(*) FROM fila_sync WHERE contingencia_erro IS NOT NULL AND contingencia_ok_em IS NULL),
    'principal_ultimo_ok',v_e.principal_ultimo_ok,'principal_ultimo_erro',v_e.principal_ultimo_erro,
    'principal_ultimo_erro_msg',v_e.principal_ultimo_erro_msg,
    'contingencia_ultimo_ok',v_e.contingencia_ultimo_ok,'contingencia_ultimo_erro',v_e.contingencia_ultimo_erro,
    'contingencia_ultimo_erro_msg',v_e.contingencia_ultimo_erro_msg,
    'itens_mais_antigos',(SELECT coalesce(jsonb_agg(x ORDER BY x->>'em'),'[]'::jsonb) FROM (
        SELECT jsonb_build_object('tabela',tabela,'id',registro_id,'em',criado_em,'tentativas',principal_tentativas,'erro',principal_erro) x
        FROM fila_sync WHERE principal_ok_em IS NULL ORDER BY id LIMIT 20) q),
    'alerta_itens',v_e.alerta_itens_limite,'alerta_horas',v_e.alerta_horas_limite);
END $$;
REVOKE ALL ON FUNCTION public.api_sync_status() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.api_sync_status() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.api_sync_lote(p_limite int DEFAULT 100)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT jsonb_build_object('ok',true,'itens',coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'tabela',tabela,'registro_id',registro_id,'operacao',operacao,'payload',payload,'criado_em',criado_em)
    ORDER BY id),'[]'::jsonb))
  FROM (SELECT * FROM fila_sync WHERE principal_ok_em IS NULL ORDER BY id LIMIT p_limite) t $$;

CREATE OR REPLACE FUNCTION public.api_sync_marcar(p_ids bigint[], p_destino text, p_ok boolean, p_erro text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF p_destino = 'principal' THEN
    IF p_ok THEN UPDATE fila_sync SET principal_ok_em=now(), principal_erro=NULL WHERE id = ANY(p_ids);
    ELSE UPDATE fila_sync SET principal_tentativas=principal_tentativas+1, principal_erro=left(coalesce(p_erro,'erro'),500) WHERE id = ANY(p_ids); END IF;
    UPDATE sync_estado SET
      principal_ultimo_ok = CASE WHEN p_ok THEN now() ELSE principal_ultimo_ok END,
      principal_ultimo_erro = CASE WHEN NOT p_ok THEN now() ELSE principal_ultimo_erro END,
      principal_ultimo_erro_msg = CASE WHEN NOT p_ok THEN left(coalesce(p_erro,''),500) ELSE principal_ultimo_erro_msg END,
      atualizado_em=now() WHERE id=true;
  ELSE
    IF p_ok THEN UPDATE fila_sync SET contingencia_ok_em=now(), contingencia_erro=NULL WHERE id = ANY(p_ids);
    ELSE UPDATE fila_sync SET contingencia_tentativas=contingencia_tentativas+1, contingencia_erro=left(coalesce(p_erro,'erro'),500) WHERE id = ANY(p_ids); END IF;
    UPDATE sync_estado SET
      contingencia_ultimo_ok = CASE WHEN p_ok THEN now() ELSE contingencia_ultimo_ok END,
      contingencia_ultimo_erro = CASE WHEN NOT p_ok THEN now() ELSE contingencia_ultimo_erro END,
      contingencia_ultimo_erro_msg = CASE WHEN NOT p_ok THEN left(coalesce(p_erro,''),500) ELSE contingencia_ultimo_erro_msg END,
      atualizado_em=now() WHERE id=true;
  END IF;
  RETURN jsonb_build_object('ok',true);
END $$;

CREATE OR REPLACE FUNCTION public.api_sync_limpar()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n int;
BEGIN
  WITH d AS (DELETE FROM fila_sync WHERE principal_ok_em IS NOT NULL AND contingencia_ok_em IS NOT NULL
    AND principal_ok_em < now() - interval '30 days' RETURNING id) SELECT count(*) INTO v_n FROM d;
  RETURN jsonb_build_object('ok',true,'removidos',v_n);
END $$;

-- O alerta vai para a auditoria (não existe a tabela ai_insights nesta estrutura)
CREATE OR REPLACE FUNCTION public.api_sync_verificar_alerta()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_e sync_estado%rowtype; v_pend int; v_horas numeric;
BEGIN
  SELECT * INTO v_e FROM sync_estado WHERE id=true;
  SELECT count(*) INTO v_pend FROM fila_sync WHERE principal_ok_em IS NULL;
  v_horas := CASE WHEN v_pend = 0 THEN 0 WHEN v_e.principal_ultimo_ok IS NULL THEN 999
                  ELSE extract(epoch from (now()-v_e.principal_ultimo_ok))/3600 END;
  IF (v_pend > v_e.alerta_itens_limite OR v_horas > v_e.alerta_horas_limite)
     AND NOT EXISTS (SELECT 1 FROM auditoria WHERE acao='ALERTA: fila de sincronização parada' AND data_hora > now() - interval '6 hours') THEN
    INSERT INTO auditoria (usuario_login, acao, detalhes)
    VALUES ('sistema','ALERTA: fila de sincronização parada', v_pend||' itens pendentes · último envio há '||round(v_horas)||'h');
  END IF;
  RETURN jsonb_build_object('ok',true,'pendentes',v_pend,'horas',v_horas);
END $$;

REVOKE ALL ON FUNCTION public.api_sync_lote(int), public.api_sync_marcar(bigint[],text,boolean,text),
  public.api_sync_limpar(), public.api_sync_verificar_alerta() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_sync_lote(int), public.api_sync_marcar(bigint[],text,boolean,text),
  public.api_sync_limpar(), public.api_sync_verificar_alerta() TO service_role;

-- ═════ ETAPA 5 — MODO RESERVA (limites; o app hoje usa 3 falhas fixas) ═════
CREATE TABLE IF NOT EXISTS public.contingencia_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  timeout_supabase_ms int NOT NULL DEFAULT 8000,
  falhas_para_planilha int NOT NULL DEFAULT 3,
  timeout_planilha_ms int NOT NULL DEFAULT 12000,
  falhas_para_contingencia int NOT NULL DEFAULT 3,
  reconciliacao_lote int NOT NULL DEFAULT 50,
  atualizado_em timestamptz NOT NULL DEFAULT now());
INSERT INTO public.contingencia_config (id) VALUES (true) ON CONFLICT DO NOTHING;
ALTER TABLE public.contingencia_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS contingencia_config_admin ON public.contingencia_config;
CREATE POLICY contingencia_config_admin ON public.contingencia_config FOR ALL TO authenticated
  USING (tem_nivel('Admin')) WITH CHECK (tem_nivel('Admin'));
GRANT ALL ON public.contingencia_config TO authenticated, service_role;

-- ═════ ETAPA 6 — TEMPO REAL (vendas e mesas) ═════
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['vendas','mesas'] LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename=t) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
    END IF;
  END LOOP;
END $$;

-- ═════ ETAPA 7 — BACKUP + ARQUIVAMENTO ═════
-- (tabela backups já existe: leitura só Admin; escrita é feita pela Edge Function com a chave de serviço.
--  Liga/desliga e hora do backup automático continuam nas chaves BACKUP_AUTO_ATIVO / BACKUP_HORA da tabela sistema.)
CREATE TABLE IF NOT EXISTS public.backup_config (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  auto_retencao_dias int NOT NULL DEFAULT 7,
  arquivar_ativo boolean NOT NULL DEFAULT true,
  arquivar_dias int NOT NULL DEFAULT 90 CHECK (arquivar_dias >= 30),
  atualizado_em timestamptz NOT NULL DEFAULT now());
INSERT INTO public.backup_config (id) VALUES (true) ON CONFLICT DO NOTHING;
ALTER TABLE public.backup_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS backup_config_admin ON public.backup_config;
CREATE POLICY backup_config_admin ON public.backup_config FOR ALL TO authenticated
  USING (tem_nivel('Admin')) WITH CHECK (tem_nivel('Admin'));
GRANT ALL ON public.backup_config TO authenticated, service_role;

CREATE TABLE IF NOT EXISTS public.arquivo_historico (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tabela text NOT NULL,
  registro_id uuid NOT NULL,
  arquivado_em timestamptz NOT NULL DEFAULT now(),
  data_referencia date NOT NULL,
  UNIQUE (tabela, registro_id));
ALTER TABLE public.arquivo_historico ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS arquivo_historico_admin ON public.arquivo_historico;
CREATE POLICY arquivo_historico_admin ON public.arquivo_historico FOR SELECT TO authenticated USING (tem_nivel('Admin'));
GRANT SELECT ON public.arquivo_historico TO authenticated; GRANT ALL ON public.arquivo_historico TO service_role;

-- Só arquiva venda ENCERRADA (cancelada, ou paga e já entregue/retirada/servida) e sem vínculo que impeça apagar
-- (ajustes_pos_venda e entregas_fechadas têm ON DELETE RESTRICT: essas vendas ficam no Supabase).
CREATE OR REPLACE FUNCTION public.api_arquivar_lote_vendas(p_dias int, p_limite int DEFAULT 200)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_corte timestamptz := now() - (greatest(p_dias,30)||' days')::interval; v_ids uuid[];
BEGIN
  SELECT array_agg(id) INTO v_ids FROM (
    SELECT v.id FROM vendas v
    WHERE v.data_hora < v_corte
      AND (v.status = 'Cancelada' OR (v.status_pagamento = 'Pago' AND coalesce(v.status_pedido::text,'Entregue') IN ('Entregue','Retirada','Servida')))
      AND NOT EXISTS (SELECT 1 FROM ajustes_pos_venda a WHERE a.venda_id = v.id)
      AND NOT EXISTS (SELECT 1 FROM entregas_fechadas e WHERE e.venda_id = v.id)
    ORDER BY v.data_hora LIMIT p_limite) x;
  RETURN jsonb_build_object('ok',true,
    'ids', coalesce(to_jsonb(v_ids),'[]'::jsonb),
    'vendas', (SELECT coalesce(jsonb_agg(to_jsonb(v)),'[]'::jsonb) FROM vendas v WHERE v.id = ANY(coalesce(v_ids,'{}'))),
    'itens', (SELECT coalesce(jsonb_agg(to_jsonb(i)),'[]'::jsonb) FROM itens_venda i WHERE i.venda_id = ANY(coalesce(v_ids,'{}'))),
    'pagamentos', (SELECT coalesce(jsonb_agg(to_jsonb(p)),'[]'::jsonb) FROM pagamentos_venda p WHERE p.venda_id = ANY(coalesce(v_ids,'{}'))));
END $$;

CREATE OR REPLACE FUNCTION public.api_arquivar_confirmar_vendas(p_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n int;
BEGIN
  PERFORM set_config('txb.sem_fila','on',true);   -- vale só nesta transação
  INSERT INTO arquivo_historico (tabela, registro_id, data_referencia)
    SELECT 'vendas', unnest(p_ids), CURRENT_DATE ON CONFLICT DO NOTHING;
  DELETE FROM itens_venda WHERE venda_id = ANY(p_ids);
  DELETE FROM pagamentos_venda WHERE venda_id = ANY(p_ids);
  WITH d AS (DELETE FROM vendas WHERE id = ANY(p_ids) RETURNING id) SELECT count(*) INTO v_n FROM d;
  RETURN jsonb_build_object('ok',true,'removidos',v_n);
EXCEPTION WHEN foreign_key_violation THEN
  RETURN _falha('Venda ainda referenciada por outra tabela: '||SQLERRM);
END $$;

CREATE OR REPLACE FUNCTION public.api_arquivar_lote_caixa(p_dias int, p_limite int DEFAULT 100)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_corte timestamptz := now() - (greatest(p_dias,30)||' days')::interval; v_ids uuid[];
BEGIN
  SELECT array_agg(id) INTO v_ids FROM (
    SELECT c.id FROM caixa_sessoes c
    WHERE c.status = 'Fechado' AND c.fechamento < v_corte
      AND NOT EXISTS (SELECT 1 FROM vendas v WHERE v.caixa_id = c.id)   -- só depois das vendas dele
    ORDER BY c.fechamento LIMIT p_limite) x;
  RETURN jsonb_build_object('ok',true,
    'ids', coalesce(to_jsonb(v_ids),'[]'::jsonb),
    'caixas', (SELECT coalesce(jsonb_agg(to_jsonb(c)),'[]'::jsonb) FROM caixa_sessoes c WHERE c.id = ANY(coalesce(v_ids,'{}'))),
    'sangrias', (SELECT coalesce(jsonb_agg(to_jsonb(s)),'[]'::jsonb) FROM sangrias s WHERE s.caixa_id = ANY(coalesce(v_ids,'{}'))));
END $$;

CREATE OR REPLACE FUNCTION public.api_arquivar_confirmar_caixa(p_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_n int;
BEGIN
  PERFORM set_config('txb.sem_fila','on',true);
  INSERT INTO arquivo_historico (tabela, registro_id, data_referencia)
    SELECT 'caixa_sessoes', unnest(p_ids), CURRENT_DATE ON CONFLICT DO NOTHING;
  DELETE FROM sangrias WHERE caixa_id = ANY(p_ids);
  WITH d AS (DELETE FROM caixa_sessoes WHERE id = ANY(p_ids) RETURNING id) SELECT count(*) INTO v_n FROM d;
  RETURN jsonb_build_object('ok',true,'removidos',v_n);
EXCEPTION WHEN foreign_key_violation THEN
  RETURN _falha('Caixa ainda referenciado por outra tabela: '||SQLERRM);
END $$;

REVOKE ALL ON FUNCTION public.api_arquivar_lote_vendas(int,int), public.api_arquivar_confirmar_vendas(uuid[]),
  public.api_arquivar_lote_caixa(int,int), public.api_arquivar_confirmar_caixa(uuid[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_arquivar_lote_vendas(int,int), public.api_arquivar_confirmar_vendas(uuid[]),
  public.api_arquivar_lote_caixa(int,int), public.api_arquivar_confirmar_caixa(uuid[]) TO service_role;

CREATE OR REPLACE FUNCTION public.api_espaco_uso()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_db bigint;
BEGIN
  IF NOT tem_nivel('Admin') THEN RETURN _negado(); END IF;
  SELECT pg_database_size(current_database()) INTO v_db;
  RETURN jsonb_build_object('ok',true,'db_bytes',v_db,'db_mb',round(v_db/1024.0/1024.0,2),
    'limite_mb',500,'percentual',round(v_db/1024.0/1024.0/500*100,1),
    'vendas_total',(SELECT count(*) FROM vendas),
    'vendas_arquivadas',(SELECT count(*) FROM arquivo_historico WHERE tabela='vendas'),
    'backups_total',(SELECT count(*) FROM backups),
    'backups_bytes',(SELECT coalesce(sum(tamanho_bytes),0) FROM backups));
END $$;
REVOKE ALL ON FUNCTION public.api_espaco_uso() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.api_espaco_uso() TO authenticated, service_role;

-- ═════ ETAPA 8 — FOTOS (SÓ DRIVE) ═════
ALTER TABLE public.configuracoes_fotos ADD COLUMN IF NOT EXISTS historico_fotos_ativo boolean NOT NULL DEFAULT true;
-- a linha existente estava com tudo vazio; preenche só o que está vazio
UPDATE public.configuracoes_fotos SET
  onde_guardar          = coalesce(onde_guardar, 'drive_apenas'),
  destino_padrao_upload = coalesce(destino_padrao_upload, 'principal'),
  drive_preferido       = coalesce(drive_preferido, 'auto'::foto_preferida),
  sincronizacao_drives  = coalesce(sincronizacao_drives, 'manual'),
  replicar_antigas      = coalesce(replicar_antigas, 'ativas')
WHERE id = true;

CREATE TABLE IF NOT EXISTS public.fotos_historico (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, produto_id uuid, combo_id uuid,
  acao text NOT NULL CHECK (acao IN ('upload','substituir','mover','remover','replicar')),
  drive_origem text, drive_destino text, foto_id_antigo text, foto_id_novo text,
  usuario_id uuid REFERENCES public.usuarios(id) ON DELETE SET NULL,
  criado_em timestamptz NOT NULL DEFAULT now());
ALTER TABLE public.fotos_historico ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fotos_historico_ler ON public.fotos_historico;
CREATE POLICY fotos_historico_ler ON public.fotos_historico FOR SELECT TO authenticated USING (tem_nivel('Admin','Operador'));
GRANT SELECT ON public.fotos_historico TO authenticated; GRANT ALL ON public.fotos_historico TO service_role;

-- ═════ ETAPA 9 — INTEGRIDADE ═════
CREATE TABLE IF NOT EXISTS public.integridade_checks (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, criado_em timestamptz NOT NULL DEFAULT now(),
  supabase_vendas int, planilha_vendas int, diferenca_vendas int,
  status text NOT NULL DEFAULT 'ok' CHECK (status IN ('ok','divergencia','erro')), detalhe jsonb);
ALTER TABLE public.integridade_checks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS integridade_checks_ler ON public.integridade_checks;
CREATE POLICY integridade_checks_ler ON public.integridade_checks FOR SELECT TO authenticated USING (tem_nivel('Admin'));
GRANT SELECT ON public.integridade_checks TO authenticated; GRANT ALL ON public.integridade_checks TO service_role;

-- ═════ CRONS (horários em UTC; chave lida do Vault) ═════
SELECT cron.unschedule(jobname) FROM cron.job WHERE jobname IN
  ('sync-fila-2min','sync-limpar-diario','sync-alerta-30min','backup-diario','backup-horario','arquivar-diario','integridade-semanal');

CREATE OR REPLACE FUNCTION public.chamar_edge(p_funcao text, p_body jsonb DEFAULT '{}'::jsonb)
RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path TO 'public','extensions' AS $$
  SELECT net.http_post(
    url := 'https://awryywtgqfaxppayzpca.supabase.co/functions/v1/'||p_funcao,
    headers := jsonb_build_object('Content-Type','application/json',
      'Authorization','Bearer '||(SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='service_key')),
    body := p_body) $$;
REVOKE ALL ON FUNCTION public.chamar_edge(text,jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chamar_edge(text,jsonb) TO service_role;

SELECT cron.schedule('sync-fila-2min','*/2 * * * *', $$ SELECT public.chamar_edge('sync-fila'); $$);
SELECT cron.schedule('sync-limpar-diario','0 6 * * *', $$ SELECT public.api_sync_limpar(); $$);
SELECT cron.schedule('sync-alerta-30min','*/30 * * * *', $$ SELECT public.api_sync_verificar_alerta(); $$);
-- roda de hora em hora; a função só faz o backup na hora configurada (BACKUP_HORA, horário de Brasília) e se BACKUP_AUTO_ATIVO=true
SELECT cron.schedule('backup-horario','0 * * * *', $$ SELECT public.chamar_edge('criar-backup','{"tipo":"Automático","cron":true}'); $$);
SELECT cron.schedule('arquivar-diario','0 8 * * *', $$ SELECT public.chamar_edge('arquivar-antigos'); $$);                     -- 5h
SELECT cron.schedule('integridade-semanal','0 9 * * 0', $$ SELECT public.chamar_edge('conferir-integridade'); $$);               -- dom 6h
-- FIM
