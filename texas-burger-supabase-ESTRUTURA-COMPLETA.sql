-- ============================================================
-- TEXAS BURGER — SUPABASE — ESTRUTURA COMPLETA ATUALIZADA
-- Projeto: texas-burger
-- Project ref: awryywtgqfaxppayzpca
-- Região: sa-east-1
-- PostgreSQL: 17.11.0.002
-- Atualizado em: 2026-10-04
--
-- Este arquivo registra a estrutura/migrações consolidadas aplicadas
-- ao projeto e, principalmente, as alterações do PLANO UNIFICADO.
-- A base canônica é o banco Supabase atual.
--
-- IMPORTANTE:
-- 1) Não executar este arquivo sobre uma base vazia como se fosse um
--    dump físico completo: ele é um pacote de estrutura + correções
--    incrementais sobre a estrutura Texas Burger já existente.
-- 2) Os dados existentes NÃO são apagados.
-- 3) As funções abaixo dependem das funções auxiliares já existentes
--    no projeto (tem_nivel, _negado, _falha, _exige_admin, etc.).
-- ============================================================

begin;

-- ============================================================
-- 1. PERFIS / NÍVEL DESENVOLVEDOR
-- ============================================================
-- O tipo já contém:
-- Admin, Operador, Garçom, Cozinha, Entregador, Desenvolvedor
--
-- auth_nivel() já trata Desenvolvedor como Admin para permissões
-- administrativas, enquanto o nível real permanece preservado em
-- public.usuarios.nivel.

-- Proteção da edição de usuários:
-- somente Desenvolvedor pode criar/atribuir/alterar uma conta
-- Desenvolvedor; contas Desenvolvedor não podem ser alteradas por
-- Admin comum.

create or replace function public.api_editar_usuario(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  u usuarios%rowtype;
  v_alvo text := coalesce(p->>'loginAlvo', '');
  v_aut text; v_erro text;
  v_sera_admin boolean; v_sera_ativo boolean;
  v_contato boolean := false; v_nome text; v_tel text;
  v_nivel_real nivel_acesso;
begin
  if not tem_nivel('Admin') then return _negado(); end if;

  select nivel into v_nivel_real
    from usuarios
   where id = auth.uid() and ativo;
  if v_nivel_real is null then return _negado(); end if;

  if p ? 'novoNivel'
     and coalesce(p->>'novoNivel', '') not in
       ('Admin','Operador','Garçom','Cozinha','Entregador','Desenvolvedor') then
    return _falha('Nível de acesso inválido.');
  end if;

  if p ? 'novoNivel'
     and p->>'novoNivel' = 'Desenvolvedor'
     and v_nivel_real <> 'Desenvolvedor' then
    return _falha('Somente um Desenvolvedor pode conceder o nível Desenvolvedor.');
  end if;

  v_aut := _exige_admin(p->>'senhaAdminConfirmacao');
  if v_aut is null then return _falha('Senha de administrador incorreta.'); end if;

  select * into u from usuarios where lower(login) = lower(v_alvo);
  if not found then return _falha('Usuário não encontrado.'); end if;

  if u.nivel = 'Desenvolvedor' and v_nivel_real <> 'Desenvolvedor' then
    return _falha('A conta de Desenvolvedor é protegida e só pode ser alterada por um Desenvolvedor.');
  end if;

  if p ? 'nome' and length(coalesce(p->>'nome', '')) > 60 then
    return _falha('O nome pode ter no máximo 60 caracteres.');
  end if;
  if p ? 'telefone' and length(coalesce(p->>'telefone', '')) > 25 then
    return _falha('O telefone pode ter no máximo 25 caracteres.');
  end if;

  v_sera_admin := case when p ? 'novoNivel'
    then p->>'novoNivel' = 'Admin' else u.nivel = 'Admin' end;
  v_sera_ativo := case when p ? 'novoAtivo'
    then coalesce((p->>'novoAtivo')::boolean, false) else u.ativo end;

  if u.id = auth.uid() and p ? 'novoAtivo' and not v_sera_ativo then
    return _falha('Você não pode desativar o seu próprio acesso.');
  end if;
  if u.id = auth.uid() and p ? 'novoNivel'
     and p->>'novoNivel' <> u.nivel::text then
    return _falha('Você não pode alterar o seu próprio perfil.');
  end if;

  if u.nivel = 'Admin' and (not v_sera_admin or not v_sera_ativo) then
    if not exists (
      select 1 from usuarios
       where nivel = 'Admin' and ativo and id <> u.id
    ) then
      return _falha('Não é possível remover o último administrador ativo.');
    end if;
  end if;

  if coalesce(p->>'novaSenha', '') <> '' then
    v_erro := _erro_senha_fraca(p->>'novaSenha', u.login);
    if v_erro <> '' then return _falha(v_erro); end if;
    update auth.users
       set encrypted_password = crypt(p->>'novaSenha', gen_salt('bf')),
           updated_at = now()
     where id = u.id;
    delete from auth.sessions where user_id = u.id;
  end if;

  if p ? 'novoNivel' then
    update usuarios
       set nivel = (p->>'novoNivel')::nivel_acesso
     where id = u.id;
  end if;

  if p ? 'novoAtivo' then
    update usuarios set ativo = v_sera_ativo where id = u.id;
    if not v_sera_ativo then
      delete from auth.sessions where user_id = u.id;
    end if;
  end if;

  if p ? 'nome' then
    v_nome := btrim(coalesce(p->>'nome', ''));
    if v_nome <> coalesce(u.nome, '') then
      update usuarios set nome = v_nome where id = u.id;
      v_contato := true;
    end if;
  end if;

  if p ? 'telefone' then
    v_tel := btrim(coalesce(p->>'telefone', ''));
    if v_tel <> coalesce(u.telefone, '') then
      update usuarios set telefone = v_tel where id = u.id;
      v_contato := true;
    end if;
  end if;

  perform _auditar(
    'Usuário editado',
    u.login ||
    case when coalesce(p->>'novaSenha', '') <> '' then ' (senha alterada)' else '' end ||
    case when v_contato then ' (nome/telefone alterado)' else '' end ||
    case when p ? 'novoNivel' then ' nível=' || (p->>'novoNivel') else '' end ||
    case when p ? 'novoAtivo' then ' ativo=' || case when v_sera_ativo then 'Sim' else 'Não' end else '' end
  );

  return jsonb_build_object('ok', true, 'message', 'Usuário atualizado.');
end
$$;

-- A exclusão de Desenvolvedor é protegida por trigger existente:
-- usuarios_proteger_desenvolvedor.
-- A migração aplicada no banco também contém a trava equivalente
-- em api_excluir_usuario.

-- ============================================================
-- 2. MESA / QR / GARÇOM
-- ============================================================

create or replace function public.api_atender_chamado_mesa(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  m mesas;
  v_nivel nivel_acesso := auth_nivel();
begin
  if v_nivel is null or v_nivel not in ('Admin', 'Operador', 'Garçom') then
    return _negado();
  end if;

  select * into m
    from mesas
   where id = _uuid(p->>'mesaId')
   for update;

  if not found then return _falha('Mesa não encontrada.'); end if;

  if v_nivel = 'Garçom'
     and m.garcom_responsavel_id is not null
     and m.garcom_responsavel_id <> auth.uid() then
    return _falha('Esta mesa está sob responsabilidade de outro garçom.');
  end if;

  update mesas
     set chamado_tipo = null,
         chamado_em = null,
         garcom_responsavel_id = case
           when v_nivel = 'Garçom' and garcom_responsavel_id is null
             then auth.uid()
           else garcom_responsavel_id
         end
   where id = m.id;

  return jsonb_build_object('ok', true);
end
$$;

-- Fechamento de mesa não permite que um Garçom assuma/feche conta
-- de mesa pertencente a outro garçom e bloqueia a forma interna
-- "A Receber (Mesa)" como pagamento final.

-- ============================================================
-- 3. PEDIDOS / INÍCIO DO PREPARO
-- ============================================================

create or replace function public.api_avancar_status_pedido(p jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  t record;
  v vendas;
  novo text := p->>'novoStatus';
  atual text;
  eu uuid := auth.uid();
  lg text;
  nv text;
begin
  if not tem_nivel('Admin','Operador','Cozinha','Garçom','Entregador') then
    return _negado();
  end if;

  if novo not in ('Em preparo','Pronta','Saiu para entrega','Entregue','Retirada','Servida') then
    return _falha('Status inválido.');
  end if;

  select * into t from _pedido_trava(p);
  if t.erro is not null then return t.erro; end if;

  v := t.v;
  atual := coalesce(v.status_pedido::text, '');
  lg := _login_de(eu);
  select nivel::text into nv from usuarios where id = eu;

  if nullif(p->>'statusEsperado','') is not null
     and p->>'statusEsperado' <> atual then
    return _conflito('Este pedido já foi atualizado por outra pessoa (agora está "' || atual || '"). A tela foi atualizada.');
  end if;

  if atual = 'Suspenso' then
    return _falha('Este pedido está suspenso — retome antes de avançar.');
  end if;
  if v.tipo = 'Retirada' and novo in ('Saiu para entrega','Entregue','Servida') then
    return _falha('Pedido de retirada não tem esse status.');
  end if;
  if v.tipo = 'Entrega' and novo in ('Retirada','Servida') then
    return _falha('Pedido de entrega não tem esse status.');
  end if;
  if v.tipo = 'Mesa' and novo in ('Saiu para entrega','Entregue','Retirada') then
    return _falha('Pedido de mesa não tem esse status — use "Servida".');
  end if;

  if not (
    (novo='Em preparo' and atual='Recebido') or
    (novo='Pronta' and atual='Em preparo') or
    (novo='Saiu para entrega' and atual='Pronta') or
    (novo='Entregue' and atual='Saiu para entrega') or
    (novo in ('Retirada','Servida') and atual='Pronta')
  ) then
    if novo = 'Pronta' and atual = 'Recebido' then
      return _falha('Aceite o pedido e inicie o preparo antes de marcá-lo como pronto.');
    end if;
    return _falha('Transição inválida: o pedido está "' || atual || '" e não pode avançar diretamente para "' || novo || '".');
  end if;

  if nv = 'Cozinha' and novo not in ('Em preparo','Pronta') then
    return _falha('A cozinha só pode marcar "Em preparo" e "Pronta".');
  end if;

  if nv = 'Garçom' then
    if not (
      v.registrado_por = eu or
      exists (select 1 from mesas m where m.id = v.mesa_id and m.garcom_responsavel_id = eu)
    ) then
      return _falha('Este pedido não está no seu escopo operacional.');
    end if;
    if novo <> 'Servida' then
      return _falha('O garçom apenas pode marcar como "Servida" um pedido de sua mesa.');
    end if;
  end if;

  if nv = 'Entregador' then
    if v.tipo <> 'Entrega' or v.entregador_id is distinct from eu then
      return _falha('Esta entrega não está atribuída a você.');
    end if;
    if novo not in ('Saiu para entrega','Entregue') then
      return _falha('O entregador só pode marcar "Saiu para entrega" e "Entregue".');
    end if;
  end if;

  if novo = 'Saiu para entrega' and v.entregador_id is null then
    return _falha('Atribua um entregador antes de o pedido sair para entrega.');
  end if;

  update vendas set
    status_pedido = novo::status_pedido,
    inicio_preparo_em = case
      when novo = 'Em preparo' then coalesce(inicio_preparo_em, now())
      else inicio_preparo_em
    end,
    pronta_em = case when novo = 'Pronta' then now() else pronta_em end,
    saiu_em = case when novo = 'Saiu para entrega' then now() else saiu_em end,
    concluida_em = case when novo in ('Entregue','Retirada','Servida') then now() else concluida_em end
  where id = v.id;

  perform _auditar('Status do pedido atualizado', '#' || v.numero_pedido || ' → ' || novo);
  return jsonb_build_object('ok', true);
end
$$;

-- ============================================================
-- 4. FORMAS DE PAGAMENTO OPERACIONAIS
-- ============================================================

create or replace view public.v_formas_operacional as
select id, nome, ordem, permite_troco
  from public.formas_pagamento
 where ativa;

alter table public.formas_pagamento enable row level security;

drop policy if exists formas_pagamento_ler on public.formas_pagamento;
create policy formas_pagamento_ler
on public.formas_pagamento
for select
to authenticated
using (tem_nivel('Admin','Operador'));

-- A política administrativa permanece restrita a Admin.
-- Não criar acesso adicional para Cozinha/Garçom/Entregador.

-- ============================================================
-- 5. RATE LIMIT — CARDÁPIO PÚBLICO
-- ============================================================
-- Limites consolidados aplicados nos RPCs públicos:
--   pedcard_ip_<IP>       = 40 requisições
--   pedcard_<telefone>    = 5 requisições
--   pedmesa_<mesa>        = 8 requisições
--   pedcard_global        = 150 requisições
-- A janela/controle é feito pelas funções _excedeu/_registrar_falha
-- e pela tabela public.tentativas.

-- ============================================================
-- 6. IDEMPOTÊNCIA
-- ============================================================
-- Os RPCs de criação pública/caixa utilizam requisicao_id/chave de
-- requisição e proteção transacional para impedir duplicação.
-- A tabela public.requisicoes mantém a chave como PK.
-- Vendas também possuem requisicao_id UNIQUE.

-- ============================================================
-- 7. VALIDAÇÃO DE COMBOS + ADICIONAIS
-- ============================================================
-- As RPCs de criação/edição de venda e pedido público validam:
--   - produto OU combo, nunca os dois ao mesmo tempo;
--   - adicionais pertencentes ao produto/estrutura permitida;
--   - quantidade válida;
--   - combinação consistente antes da gravação.
-- Esta validação foi aplicada na migração unified_plan_dev_and_combo_guards.

-- ============================================================
-- 8. MIGRAÇÕES APLICADAS NO PROJETO
-- ============================================================
-- Registro consolidado do banco em 2026-10-04:
--
-- 20261004111915 etapa_3c2b1_andamento_pedidos
-- 20261004111943 etapa_3c2b1_corrige_acesso_campo_v
-- 20261004112239 etapa_3c2b2_mesa_e_fechamento_entregador
-- 20261004113128 etapa_3_correcao_seguranca_permissoes
-- 20261004113405 etapa_3c2b2_entregador_le_proprios_fechamentos
-- 20261004115132 etapa_3c3a_financeiro
-- 20261004115947 etapa_3_perfil_desenvolvedor_enum
-- 20261004120011 etapa_3_perfil_desenvolvedor_funcoes
-- 20261004122635 etapa_3c3c_relacionamento_cupons_eventos
-- 20261004122754 etapa_3c3c_visao_ocorrencias
-- 20261004140308 etapa_3c4a_pedido_cardapio_publico
-- 20261004140659 etapa_3c4b_mesa_publica_qr
-- 20261004185351 etapa_3c4c_editar_venda_feedback_detector
-- 20261004185647 etapa_3_corrige_pagamento_duplicado_fechar_mesa
-- 20261004190527 etapa_3c5_mais_pedidos_e_esgotados
-- 20261004190851 etapa_3c6_importar_cardapio_inicial
-- 20261004194538 fase3_item4_calc_fechamento_coalesce_ids
-- 20261004194549 fase3_item1_fechar_caixa_fecha_entregas
-- 20261004194555 fase3_item2_venda_exige_caixa_aberto
-- 20261004194603 fase3_item3_combo_com_produto_inativo
-- 20261004194611 fase3_item5_salvar_cliente_limites
-- 20261004194620 fase3_item6_editar_usuario_travas_proprio_acesso
-- 20261004195920 item7a_versao_otimista_base
-- 20261004195929 item7b_versao_otimista_rpcs
-- 20261004195946 item8_sync_incremental_versoes
-- 20261004200048 item9_texto_publico_portavel
-- 20261004200052 item10_views_somente_leitura
-- 20261004200100 item11_cliente_race_indice_digitos
-- 20261004200123 item12_custo_conferido_com_cadastro
-- 20261004201851 fase3_ip_cliente_fallback_e_limite_pedidos
-- 20261004202844 rate_limit_pedcard_global_janela_300s
-- 20261004203428 liberar_so_digitos_para_authenticated
-- 20261004211236 dev_protection_excluir_usuario
-- 20261004211320 mesa_qr_garcom
-- 20261004211326 mesa_qr_atendimento
-- 20261004211335 inicio_preparo_pedido
-- 20261004211406 formas_pagamento_operacional
-- 20261004211412 formas_pagamento_policy_restrita
-- 20261004211838 unified_plan_dev_and_combo_guards
-- 20261004212319 protect_developer_in_api_editar_usuario

-- ============================================================
-- 9. TESTES DE CONSISTÊNCIA DO PLANO UNIFICADO
-- ============================================================

-- Dev protegido / enum presente
select exists (
  select 1 from pg_enum e
  join pg_type t on t.oid=e.enumtypid
  where t.typname='nivel_acesso' and e.enumlabel='Desenvolvedor'
) as desenvolvedor_no_enum;

-- Campo de início de preparo
select exists (
  select 1 from information_schema.columns
  where table_schema='public'
    and table_name='vendas'
    and column_name='inicio_preparo_em'
) as inicio_preparo_em_presente;

-- View operacional
select to_regclass('public.v_formas_operacional') as view_formas_operacional;

-- Rate limit por IP: tabela operacional
select to_regclass('public.tentativas') as tabela_tentativas;

-- Idempotência de venda
select exists (
  select 1 from information_schema.columns
  where table_schema='public'
    and table_name='vendas'
    and column_name='requisicao_id'
) as vendas_requisicao_id;

commit;

-- ============================================================
-- FIM
-- ============================================================
-- Observação: este arquivo foi atualizado com base no estado real
-- do projeto Supabase em 04/10/2026. Ele preserva a arquitetura
-- existente e registra as correções do Plano Unificado sem criar
-- cadastros ou sistemas paralelos.
