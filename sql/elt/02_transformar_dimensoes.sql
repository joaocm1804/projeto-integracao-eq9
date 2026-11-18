-- ============================================================================
-- ELT - Etapa 2: Transformação das Dimensões dentro do PostgreSQL (dw_elt)
-- Utiliza CTAS, CTEs, jsonb_array_elements, LPAD, REPLACE e CASE WHEN.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. dim_tempo (com Semana Epidemiológica pela regra MMWR)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS dw_elt.dim_tempo CASCADE;

CREATE TABLE dw_elt.dim_tempo AS
WITH datas_brutas AS (
    SELECT DISTINCT dt::DATE AS data_completa
    FROM (
        SELECT dt_notific AS dt FROM stg_elt.stg_sinan_2023
        UNION ALL SELECT dt_sin_pri FROM stg_elt.stg_sinan_2023
        UNION ALL SELECT dt_notific FROM stg_elt.stg_sinan_2024
        UNION ALL SELECT dt_sin_pri FROM stg_elt.stg_sinan_2024
        UNION ALL SELECT dt_notific FROM stg_elt.stg_sinan_2025
        UNION ALL SELECT dt_sin_pri FROM stg_elt.stg_sinan_2025
    ) u
    WHERE NULLIF(TRIM(dt), '') IS NOT NULL
),
calc_mmwr AS (
    SELECT
        data_completa,
        EXTRACT(DAY FROM data_completa)::SMALLINT AS dia,
        EXTRACT(MONTH FROM data_completa)::SMALLINT AS mes,
        EXTRACT(QUARTER FROM data_completa)::SMALLINT AS trimestre,
        EXTRACT(YEAR FROM data_completa)::SMALLINT AS ano_civil,
        (data_completa - EXTRACT(DOW FROM data_completa)::INT + 3) AS quarta_epi
    FROM datas_brutas
),
com_se AS (
    SELECT
        data_completa,
        dia,
        mes,
        CASE mes
            WHEN 1 THEN 'Janeiro'   WHEN 2 THEN 'Fevereiro' WHEN 3 THEN 'Março'
            WHEN 4 THEN 'Abril'     WHEN 5 THEN 'Maio'      WHEN 6 THEN 'Junho'
            WHEN 7 THEN 'Julho'     WHEN 8 THEN 'Agosto'    WHEN 9 THEN 'Setembro'
            WHEN 10 THEN 'Outubro'  WHEN 11 THEN 'Novembro' WHEN 12 THEN 'Dezembro'
        END AS nome_mes,
        trimestre,
        ano_civil,
        EXTRACT(YEAR FROM quarta_epi)::SMALLINT AS ano_epidemiologico,
        (((quarta_epi - MAKE_DATE(EXTRACT(YEAR FROM quarta_epi)::INT, 1, 1)) / 7) + 1)::SMALLINT AS semana_epidemiologica
    FROM calc_mmwr
)
SELECT
    ROW_NUMBER() OVER (ORDER BY data_completa)::INT AS sk_tempo,
    data_completa,
    dia,
    mes,
    nome_mes,
    trimestre,
    ano_civil,
    semana_epidemiologica,
    ano_epidemiologico,
    (ano_epidemiologico::TEXT || LPAD(semana_epidemiologica::TEXT, 2, '0'))::VARCHAR(6) AS semana_epi_codigo
FROM com_se
ORDER BY data_completa;

ALTER TABLE dw_elt.dim_tempo ADD PRIMARY KEY (sk_tempo);
CREATE UNIQUE INDEX idx_elt_dim_tempo_data ON dw_elt.dim_tempo (data_completa);

-- ----------------------------------------------------------------------------
-- 2. dim_localidade (DATASUS Base Territorial + IBGE SIDRA 4709/6579 via JSONB)
--    pop_2023 utiliza Censo 2022 (SIDRA 4709) como denominador oficial de 2023.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS dw_elt.dim_localidade CASCADE;

CREATE TABLE dw_elt.dim_localidade AS
WITH sidra_linhas AS (
    SELECT fonte, elem
    FROM stg_elt.stg_sidra_raw,
         jsonb_array_elements(payload) WITH ORDINALITY AS t(elem, ord)
    WHERE ord > 1  -- Pula o elemento 0 (cabeçalho)
),
sidra_pop AS (
    SELECT
        elem->>'D1C' AS co_municip_7,
        MAX(CASE WHEN fonte = 'SIDRA_4709_2022' AND elem->>'D3C' = '2022' AND elem->>'V' <> '...' THEN (elem->>'V')::INT END) AS pop_2023,
        MAX(CASE WHEN fonte = 'SIDRA_6579_2024_2025' AND elem->>'D3C' = '2024' AND elem->>'V' <> '...' THEN (elem->>'V')::INT END) AS pop_2024,
        MAX(CASE WHEN fonte = 'SIDRA_6579_2024_2025' AND elem->>'D3C' = '2025' AND elem->>'V' <> '...' THEN (elem->>'V')::INT END) AS pop_2025
    FROM sidra_linhas
    GROUP BY elem->>'D1C'
),
regsaud_dedup AS (
    SELECT DISTINCT ON (TRIM(co_municip))
        TRIM(co_municip) AS co_municip,
        TRIM(co_regsaud) AS co_regsaud
    FROM stg_elt.stg_rl_municip_regsaud
    ORDER BY TRIM(co_municip), TRIM(co_regsaud)
),
macsaud_dedup AS (
    SELECT DISTINCT ON (TRIM(co_regsaud))
        TRIM(co_regsaud) AS co_regsaud,
        TRIM(co_macrorregional) AS co_macsaud
    FROM stg_elt.stg_rl_regsaud_macsaud
    ORDER BY TRIM(co_regsaud), TRIM(co_macrorregional)
)
SELECT
    0 AS sk_localidade,
    '000000'::VARCHAR(6) AS co_municip_6,
    '0000000'::VARCHAR(7) AS co_municip_7,
    'Município não informado'::VARCHAR(100) AS nome_municipio,
    'Não informado'::VARCHAR(20) AS co_regsaud,
    'Não informado'::VARCHAR(120) AS nome_regsaud,
    'Não informado'::VARCHAR(20) AS co_macsaud,
    'Não informado'::VARCHAR(120) AS nome_macsaud,
    'XX'::VARCHAR(2) AS sg_uf,
    'Não informado'::VARCHAR(50) AS nome_uf,
    'Não informado'::VARCHAR(30) AS nome_regiao,
    'IGNR'::VARCHAR(10) AS co_status,
    NULL::INT AS pop_2023,
    NULL::INT AS pop_2024,
    NULL::INT AS pop_2025,
    NULL::NUMERIC(10,6) AS latitude,
    NULL::NUMERIC(10,6) AS longitude
UNION ALL
SELECT
    ROW_NUMBER() OVER (ORDER BY TRIM(m.co_municip))::INT AS sk_localidade,
    TRIM(m.co_municip)::VARCHAR(6) AS co_municip_6,
    TRIM(m.co_municdv)::VARCHAR(7) AS co_municip_7,
    TRIM(COALESCE(NULLIF(TRIM(m.ds_nomepad), ''), m.ds_nome))::VARCHAR(100) AS nome_municipio,
    COALESCE(rs.co_regsaud, 'Não informado')::VARCHAR(20) AS co_regsaud,
    COALESCE(NULLIF(TRIM(rs.ds_nomepad), ''), 'Não informado')::VARCHAR(120) AS nome_regsaud,
    COALESCE(ms.co_macsaud, 'Não informado')::VARCHAR(20) AS co_macsaud,
    COALESCE(NULLIF(TRIM(ms.ds_nomepad), ''), 'Não informado')::VARCHAR(120) AS nome_macsaud,
    COALESCE(NULLIF(TRIM(u.ds_sigla), ''), NULLIF(TRIM(m.uf), ''), 'XX')::VARCHAR(2) AS sg_uf,
    COALESCE(NULLIF(INITCAP(TRIM(u.ds_nomepad)), ''), 'Estrangeiro/Inválido')::VARCHAR(50) AS nome_uf,
    COALESCE(NULLIF(INITCAP(TRIM(r.no_regiao)), ''), 'Estrangeiro/Inválido')::VARCHAR(30) AS nome_regiao,
    TRIM(m.co_status)::VARCHAR(10) AS co_status,
    p.pop_2023,
    p.pop_2024,
    p.pop_2025,
    REPLACE(NULLIF(TRIM(m.nu_latitud), ''), ',', '.')::NUMERIC(10,6) AS latitude,
    REPLACE(NULLIF(TRIM(m.nu_longit), ''), ',', '.')::NUMERIC(10,6) AS longitude
FROM stg_elt.stg_tb_municip m
LEFT JOIN stg_elt.stg_tb_uf u ON TRIM(m.co_uf) = TRIM(u.co_uf)
LEFT JOIN stg_elt.stg_tb_regiao r ON TRIM(m.co_regiao) = TRIM(r.co_regiao)
LEFT JOIN regsaud_dedup rmr ON TRIM(m.co_municip) = rmr.co_municip
LEFT JOIN stg_elt.stg_tb_regsaud rs ON rmr.co_regsaud = TRIM(rs.co_regsaud)
LEFT JOIN macsaud_dedup rms ON TRIM(rs.co_regsaud) = rms.co_regsaud
LEFT JOIN stg_elt.stg_tb_macsaud ms ON rms.co_macsaud = TRIM(ms.co_macsaud)
LEFT JOIN sidra_pop p ON TRIM(m.co_municdv) = p.co_municip_7;

ALTER TABLE dw_elt.dim_localidade ADD PRIMARY KEY (sk_localidade);
CREATE UNIQUE INDEX idx_elt_dim_loc_cod6 ON dw_elt.dim_localidade (co_municip_6);

-- ----------------------------------------------------------------------------
-- 3. dim_paciente_perfil
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS dw_elt.dim_paciente_perfil CASCADE;

CREATE TABLE dw_elt.dim_paciente_perfil AS
WITH sinan_unificado AS (
    SELECT cs_sexo, nu_idade_n, cs_raca, cs_escol_n, cs_gestant FROM stg_elt.stg_sinan_2023
    UNION ALL
    SELECT cs_sexo, nu_idade_n, cs_raca, cs_escol_n, cs_gestant FROM stg_elt.stg_sinan_2024
    UNION ALL
    SELECT cs_sexo, nu_idade_n, cs_raca, cs_escol_n, cs_gestant FROM stg_elt.stg_sinan_2025
),
normalizado AS (
    SELECT
        CASE WHEN TRIM(cs_sexo) IN ('F', 'M') THEN TRIM(cs_sexo) ELSE 'I' END AS sexo_cod,
        CASE
            WHEN TRIM(nu_idade_n) ~ '^[123][0-9]{3}$' THEN 0
            WHEN TRIM(nu_idade_n) ~ '^4[0-9]{3}$' THEN SUBSTRING(TRIM(nu_idade_n) FROM 2 FOR 3)::INT
            WHEN TRIM(nu_idade_n) ~ '^[0-9]{1,2}$' THEN TRIM(nu_idade_n)::INT
            ELSE NULL
        END AS idade_calc,
        CASE WHEN TRIM(cs_raca) IN ('1','2','3','4','5') THEN TRIM(cs_raca) ELSE '9' END AS raca_cod,
        CASE
            WHEN NULLIF(TRIM(cs_escol_n), '') IS NULL THEN '9'
            WHEN TRIM(cs_escol_n) IN ('0', '00') THEN '0'
            WHEN LTRIM(TRIM(cs_escol_n), '0') IN ('1','2','3','4','5','6','7','8','10') THEN LTRIM(TRIM(cs_escol_n), '0')
            ELSE '9'
        END AS escolaridade_cod,
        CASE WHEN TRIM(cs_gestant) IN ('1','2','3','4','5','6') THEN TRIM(cs_gestant) ELSE '9' END AS gestante_cod
    FROM sinan_unificado
),
com_faixa AS (
    SELECT DISTINCT
        sexo_cod,
        CASE sexo_cod WHEN 'F' THEN 'Feminino' WHEN 'M' THEN 'Masculino' ELSE 'Ignorado/Branco' END AS sexo_desc,
        CASE
            WHEN idade_calc IS NULL THEN 'Ignorado'
            WHEN idade_calc < 1 THEN '< 1 ano'
            WHEN idade_calc BETWEEN 1 AND 4 THEN '1-4 anos'
            WHEN idade_calc BETWEEN 5 AND 9 THEN '5-9 anos'
            WHEN idade_calc BETWEEN 10 AND 14 THEN '10-14 anos'
            WHEN idade_calc BETWEEN 15 AND 19 THEN '15-19 anos'
            WHEN idade_calc BETWEEN 20 AND 39 THEN '20-39 anos'
            WHEN idade_calc BETWEEN 40 AND 59 THEN '40-59 anos'
            WHEN idade_calc BETWEEN 60 AND 69 THEN '60-69 anos'
            WHEN idade_calc BETWEEN 70 AND 79 THEN '70-79 anos'
            ELSE '80+ anos'
        END AS faixa_etaria,
        CASE
            WHEN idade_calc IS NULL THEN 99
            WHEN idade_calc < 1 THEN 1
            WHEN idade_calc BETWEEN 1 AND 4 THEN 2
            WHEN idade_calc BETWEEN 5 AND 9 THEN 3
            WHEN idade_calc BETWEEN 10 AND 14 THEN 4
            WHEN idade_calc BETWEEN 15 AND 19 THEN 5
            WHEN idade_calc BETWEEN 20 AND 39 THEN 6
            WHEN idade_calc BETWEEN 40 AND 59 THEN 7
            WHEN idade_calc BETWEEN 60 AND 69 THEN 8
            WHEN idade_calc BETWEEN 70 AND 79 THEN 9
            ELSE 10
        END AS ordem_faixa_etaria,
        raca_cod,
        CASE raca_cod
            WHEN '1' THEN 'Branca' WHEN '2' THEN 'Preta' WHEN '3' THEN 'Amarela'
            WHEN '4' THEN 'Parda'  WHEN '5' THEN 'Indígena' ELSE 'Ignorado/Branco'
        END AS raca_desc,
        escolaridade_cod,
        CASE escolaridade_cod
            WHEN '0' THEN 'Analfabeto'
            WHEN '1' THEN '1ª a 4ª série incompleta do EF'
            WHEN '2' THEN '4ª série completa do EF'
            WHEN '3' THEN '5ª a 8ª série incompleta do EF'
            WHEN '4' THEN 'Ensino fundamental completo'
            WHEN '5' THEN 'Ensino médio incompleto'
            WHEN '6' THEN 'Ensino médio completo'
            WHEN '7' THEN 'Educação superior incompleta'
            WHEN '8' THEN 'Educação superior completa'
            WHEN '10' THEN 'Não se aplica'
            ELSE 'Ignorado/Branco'
        END AS escolaridade_desc,
        gestante_cod,
        CASE gestante_cod
            WHEN '1' THEN '1º Trimestre' WHEN '2' THEN '2º Trimestre' WHEN '3' THEN '3º Trimestre'
            WHEN '4' THEN 'Idade gestacional ignorada' WHEN '5' THEN 'Não' WHEN '6' THEN 'Não se aplica'
            ELSE 'Ignorado/Branco'
        END AS gestante_desc
    FROM normalizado
)
SELECT
    ROW_NUMBER() OVER (ORDER BY sexo_cod, ordem_faixa_etaria, raca_cod, escolaridade_cod, gestante_cod)::INT AS sk_paciente_perfil,
    *
FROM com_faixa;

ALTER TABLE dw_elt.dim_paciente_perfil ADD PRIMARY KEY (sk_paciente_perfil);
CREATE UNIQUE INDEX idx_elt_dim_pac_nat ON dw_elt.dim_paciente_perfil (sexo_cod, faixa_etaria, raca_cod, escolaridade_cod, gestante_cod);

-- ----------------------------------------------------------------------------
-- 4. dim_classificacao
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS dw_elt.dim_classificacao CASCADE;

CREATE TABLE dw_elt.dim_classificacao AS
WITH sinan_unificado AS (
    SELECT classi_fin, criterio, evolucao, hospitaliz, clinc_chik FROM stg_elt.stg_sinan_2023
    UNION ALL
    SELECT classi_fin, criterio, evolucao, hospitaliz, clinc_chik FROM stg_elt.stg_sinan_2024
    UNION ALL
    SELECT classi_fin, criterio, evolucao, hospitaliz, clinc_chik FROM stg_elt.stg_sinan_2025
),
normalizado AS (
    SELECT DISTINCT
        CASE WHEN TRIM(classi_fin) IN ('5','8','13') THEN TRIM(classi_fin) ELSE '9' END AS classi_fin_cod,
        CASE WHEN TRIM(criterio) IN ('1','2','3') THEN TRIM(criterio) ELSE '9' END AS criterio_cod,
        CASE WHEN TRIM(evolucao) IN ('1','2','3','4') THEN TRIM(evolucao) ELSE '9' END AS evolucao_cod,
        CASE WHEN TRIM(hospitaliz) IN ('1','2') THEN TRIM(hospitaliz) ELSE '9' END AS hospitaliz_cod,
        CASE WHEN TRIM(clinc_chik) IN ('1','2') THEN TRIM(clinc_chik) ELSE '9' END AS clinc_chik_cod
    FROM sinan_unificado
)
SELECT
    ROW_NUMBER() OVER (ORDER BY classi_fin_cod, criterio_cod, evolucao_cod, hospitaliz_cod, clinc_chik_cod)::INT AS sk_classificacao,
    classi_fin_cod,
    CASE classi_fin_cod
        WHEN '13' THEN 'Chikungunya' WHEN '5' THEN 'Descartado' WHEN '8' THEN 'Inconclusivo' ELSE 'Ignorado/Branco'
    END AS classi_fin_desc,
    criterio_cod,
    CASE criterio_cod
        WHEN '1' THEN 'Laboratorial' WHEN '2' THEN 'Clínico-epidemiológico' WHEN '3' THEN 'Em investigação' ELSE 'Ignorado/Branco'
    END AS criterio_desc,
    evolucao_cod,
    CASE evolucao_cod
        WHEN '1' THEN 'Cura' WHEN '2' THEN 'Óbito pelo agravo notificado'
        WHEN '3' THEN 'Óbito por outras causas' WHEN '4' THEN 'Óbito em investigação' ELSE 'Ignorado/Branco'
    END AS evolucao_desc,
    hospitaliz_cod,
    CASE hospitaliz_cod WHEN '1' THEN 'Sim' WHEN '2' THEN 'Não' ELSE 'Ignorado/Branco' END AS hospitaliz_desc,
    clinc_chik_cod,
    CASE clinc_chik_cod WHEN '1' THEN 'Aguda' WHEN '2' THEN 'Crônica' ELSE 'Ignorado/Branco' END AS clinc_chik_desc
FROM normalizado;

ALTER TABLE dw_elt.dim_classificacao ADD PRIMARY KEY (sk_classificacao);
CREATE UNIQUE INDEX idx_elt_dim_cls_nat ON dw_elt.dim_classificacao (classi_fin_cod, criterio_cod, evolucao_cod, hospitaliz_cod, clinc_chik_cod);

-- ----------------------------------------------------------------------------
-- 5. dim_unidade (CNES + TipoUnidade.cnv + membro especial 0)
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS dw_elt.dim_unidade CASCADE;

CREATE TABLE dw_elt.dim_unidade AS
SELECT
    0 AS sk_unidade,
    '0000000'::VARCHAR(7) AS co_cnes,
    'Unidade não identificada'::VARCHAR(150) AS nome_fantasia,
    '00'::VARCHAR(5) AS tp_unidade_cod,
    'Não identificado'::VARCHAR(100) AS tp_unidade_desc,
    '000000'::VARCHAR(6) AS co_municipio_gestor,
    'Não informado'::VARCHAR(30) AS esfera_adm
UNION ALL
SELECT
    ROW_NUMBER() OVER (ORDER BY LPAD(LTRIM(TRIM(c.co_cnes), '0'), 7, '0'))::INT AS sk_unidade,
    LPAD(LTRIM(TRIM(c.co_cnes), '0'), 7, '0')::VARCHAR(7) AS co_cnes,
    COALESCE(NULLIF(TRIM(c.no_fantasia), ''), TRIM(c.no_razao_social), 'Sem nome')::VARCHAR(150) AS nome_fantasia,
    LPAD(TRIM(c.tp_unidade), 2, '0')::VARCHAR(5) AS tp_unidade_cod,
    COALESCE(t.tp_unidade_desc, 'Outros/Não informado')::VARCHAR(100) AS tp_unidade_desc,
    LPAD(TRIM(c.co_ibge), 6, '0')::VARCHAR(6) AS co_municipio_gestor,
    COALESCE(NULLIF(TRIM(c.tp_gestao), ''), 'Não informado')::VARCHAR(30) AS esfera_adm
FROM stg_elt.stg_cnes c
LEFT JOIN stg_elt.stg_tipo_unidade t
    ON LPAD(TRIM(c.tp_unidade), 2, '0') = LPAD(TRIM(t.tp_unidade_cod), 2, '0');

ALTER TABLE dw_elt.dim_unidade ADD PRIMARY KEY (sk_unidade);
CREATE UNIQUE INDEX idx_elt_dim_unid_cnes ON dw_elt.dim_unidade (co_cnes);
