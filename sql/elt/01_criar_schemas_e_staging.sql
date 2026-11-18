-- ============================================================================
-- ELT - Etapa 1: Criação dos schemas e tabelas de staging (dados crus)
-- Todas as colunas textuais/numéricas são carregadas como TEXT (e JSONB para
-- o SIDRA) para preservar o estado natural e evitar falhas de tipo no COPY.
-- ============================================================================

DROP SCHEMA IF EXISTS stg_elt CASCADE;
DROP SCHEMA IF EXISTS dw_elt CASCADE;

CREATE SCHEMA stg_elt;
CREATE SCHEMA dw_elt;

-- 1. Staging SINAN Chikungunya (2023, 2024, 2025)
CREATE TABLE stg_elt.stg_sinan_2023 (
    tp_not TEXT, id_agravo TEXT, dt_notific TEXT, sem_not TEXT, nu_ano TEXT,
    sg_uf_not TEXT, id_municip TEXT, id_regiona TEXT, id_unidade TEXT,
    dt_sin_pri TEXT, sem_pri TEXT, ano_nasc TEXT, nu_idade_n TEXT,
    cs_sexo TEXT, cs_gestant TEXT, cs_raca TEXT, cs_escol_n TEXT,
    sg_uf TEXT, id_mn_resi TEXT, id_rg_resi TEXT, id_pais TEXT,
    dt_invest TEXT, id_ocupa_n TEXT, febre TEXT, mialgia TEXT,
    cefaleia TEXT, exantema TEXT, vomito TEXT, nausea TEXT,
    dor_costas TEXT, conjuntvit TEXT, artrite TEXT, artralgia TEXT,
    petequia_n TEXT, leucopenia TEXT, laco TEXT, dor_retro TEXT,
    diabetes TEXT, hematolog TEXT, hepatopat TEXT, renal TEXT,
    hipertensa TEXT, acido_pept TEXT, auto_imune TEXT, dt_chik_s1 TEXT,
    dt_chik_s2 TEXT, dt_prnt TEXT, res_chiks1 TEXT, res_chiks2 TEXT,
    resul_prnt TEXT, dt_soro TEXT, resul_soro TEXT, dt_ns1 TEXT,
    resul_ns1 TEXT, dt_viral TEXT, resul_vi_n TEXT, dt_pcr TEXT,
    resul_pcr_ TEXT, sorotipo TEXT, histopa_n TEXT, imunoh_n TEXT,
    hospitaliz TEXT, dt_interna TEXT, uf TEXT, municipio TEXT,
    tpautocto TEXT, coufinf TEXT, copaisinf TEXT, comuninf TEXT,
    classi_fin TEXT, criterio TEXT, doenca_tra TEXT, clinc_chik TEXT,
    evolucao TEXT, dt_obito TEXT, dt_encerra TEXT, alrm_hipot TEXT,
    alrm_plaq TEXT, alrm_vom TEXT, alrm_sang TEXT, alrm_hemat TEXT,
    alrm_abdom TEXT, alrm_letar TEXT, alrm_hepat TEXT, alrm_liq TEXT,
    dt_alrm TEXT, grav_pulso TEXT, grav_conv TEXT, grav_ench TEXT,
    grav_insuf TEXT, grav_taqui TEXT, grav_extre TEXT, grav_hipot TEXT,
    grav_hemat TEXT, grav_melen TEXT, grav_metro TEXT, grav_sang TEXT,
    grav_ast TEXT, grav_mioc TEXT, grav_consc TEXT, grav_orgao TEXT,
    dt_grav TEXT, mani_hemor TEXT, epistaxe TEXT, gengivo TEXT,
    metro TEXT, petequias TEXT, hematura TEXT, sangram TEXT,
    laco_n TEXT, plasmatico TEXT, evidencia TEXT, plaq_menor TEXT,
    con_fhd TEXT, complica TEXT, nu_lote_i TEXT, tp_sistema TEXT,
    nduplic_n TEXT, dt_digita TEXT, cs_flxret TEXT, flxrecebi TEXT,
    migrado_w TEXT
);

CREATE TABLE stg_elt.stg_sinan_2024 (LIKE stg_elt.stg_sinan_2023);
CREATE TABLE stg_elt.stg_sinan_2025 (LIKE stg_elt.stg_sinan_2023);

-- 2. Staging Base Territorial DATASUS
CREATE TABLE stg_elt.stg_tb_municip (
    co_municip TEXT, co_municdv TEXT, co_status TEXT, co_tipo TEXT,
    ds_nome TEXT, uf TEXT, macrorregional TEXT, ds_nomepad TEXT,
    ds_observ TEXT, co_regiao TEXT, co_uf TEXT, co_alter TEXT,
    co_alterdv TEXT, in_capital TEXT, in_amazleg TEXT, in_semiar TEXT,
    in_frontzn TEXT, dt_instal TEXT, dt_extin TEXT, co_sucess TEXT,
    nu_ordem TEXT, nu_ordmap TEXT, nu_latitud TEXT, nu_longit TEXT,
    nu_altitud TEXT, nu_area TEXT
);

CREATE TABLE stg_elt.stg_tb_uf (
    co_uf TEXT, ds_sigla TEXT, co_status TEXT, ds_nome TEXT,
    ds_nomepad TEXT, co_sucess TEXT, co_regiao TEXT, nu_area TEXT
);

CREATE TABLE stg_elt.stg_tb_regiao (
    co_regiao TEXT, no_regiao TEXT, sg_regiao TEXT, st_registro_ativo TEXT
);

CREATE TABLE stg_elt.stg_tb_regsaud (
    co_regsaud TEXT, co_status TEXT, ds_nome TEXT,
    ds_nomepad TEXT, ds_abrev TEXT, nu_ordem TEXT
);

CREATE TABLE stg_elt.stg_tb_macsaud (
    co_macsaud TEXT, co_status TEXT, ds_nome TEXT,
    ds_nomepad TEXT, ds_abrev TEXT, nu_ordem TEXT
);

CREATE TABLE stg_elt.stg_rl_municip_regsaud (
    co_municip TEXT, co_regsaud TEXT
);

CREATE TABLE stg_elt.stg_rl_regsaud_macsaud (
    co_regsaud TEXT, co_macrorregional TEXT
);

-- 3. Staging CNES (recorte) e TipoUnidade (.cnv)
CREATE TABLE stg_elt.stg_cnes (
    co_cnes TEXT, co_unidade TEXT, co_uf TEXT, co_ibge TEXT,
    nu_cnpj_mantenedora TEXT, no_razao_social TEXT, no_fantasia TEXT,
    co_natureza_organizacao TEXT, ds_natureza_organizacao TEXT,
    tp_gestao TEXT, co_nivel_hierarquia TEXT, ds_nivel_hierarquia TEXT,
    co_esfera_administrativa TEXT, ds_esfera_administrativa TEXT,
    co_atividade TEXT, tp_unidade TEXT, co_cep TEXT, no_logradouro TEXT,
    nu_endereco TEXT, no_bairro TEXT, nu_telefone TEXT,
    nu_latitude TEXT, nu_longitude TEXT, co_turno_atendimento TEXT,
    ds_turno_atendimento TEXT, nu_cnpj TEXT, no_email TEXT,
    co_natureza_jur TEXT, st_centro_cirurgico TEXT,
    st_centro_obstetrico TEXT, st_centro_neonatal TEXT,
    st_atend_hospitalar TEXT, st_servico_apoio TEXT,
    st_atend_ambulatorial TEXT, co_motivo_desab TEXT,
    co_ambulatorial_sus TEXT
);

CREATE TABLE stg_elt.stg_tipo_unidade (
    tp_unidade_cod TEXT,
    tp_unidade_desc TEXT
);

-- 4. Staging IBGE SIDRA 4709 (Censo 2022) e 6579 (2024–2025) como JSONB bruto
CREATE TABLE stg_elt.stg_sidra_raw (
    fonte TEXT NOT NULL,
    payload JSONB NOT NULL
);
