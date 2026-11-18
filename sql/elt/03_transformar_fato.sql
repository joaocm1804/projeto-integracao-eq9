-- ============================================================================
-- ELT - Etapa 3: Construção da Tabela Fato dentro do PostgreSQL (dw_elt)
-- Une os 3 anos deduplicados, aplica padronizações/métricas e resolve as
-- chaves substitutas (Surrogate Keys) via JOIN com as 5 dimensões.
-- ============================================================================

DROP TABLE IF EXISTS dw_elt.fato_notificacao CASCADE;

CREATE TABLE dw_elt.fato_notificacao AS
WITH sinan_dedup AS (
    SELECT DISTINCT 2023::SMALLINT AS ano_arquivo_origem, * FROM stg_elt.stg_sinan_2023
    UNION ALL
    SELECT DISTINCT 2024::SMALLINT AS ano_arquivo_origem, * FROM stg_elt.stg_sinan_2024
    UNION ALL
    SELECT DISTINCT 2025::SMALLINT AS ano_arquivo_origem, * FROM stg_elt.stg_sinan_2025
),
preparado AS (
    SELECT
        ano_arquivo_origem,
        CASE WHEN TRIM(id_agravo) = 'A920' THEN 'A92.0' ELSE TRIM(id_agravo) END AS id_agravo_padronizado,
        CASE
            WHEN NULLIF(TRIM(tp_sistema), '') IS NULL OR TRIM(tp_sistema) = '/' THEN 'IGN'
            ELSE TRIM(tp_sistema)
        END AS tp_sistema,
        TRIM(dt_notific)::DATE AS dt_notific_d,
        TRIM(dt_sin_pri)::DATE AS dt_sin_pri_d,
        NULLIF(TRIM(dt_encerra), '')::DATE AS dt_encerra_d,
        COALESCE(NULLIF(TRIM(id_municip), ''), '000000') AS co_mun_not,
        COALESCE(NULLIF(TRIM(id_mn_resi), ''), '000000') AS co_mun_res,
        CASE
            WHEN NULLIF(TRIM(id_unidade), '') IS NULL THEN '0000000'
            ELSE LPAD(LTRIM(TRIM(id_unidade), '0'), 7, '0')
        END AS co_cnes_norm,
        -- Campos de perfil
        CASE WHEN TRIM(cs_sexo) IN ('F', 'M') THEN TRIM(cs_sexo) ELSE 'I' END AS sexo_cod,
        CASE
            WHEN TRIM(nu_idade_n) ~ '^[123][0-9]{3}$' THEN 0
            WHEN TRIM(nu_idade_n) ~ '^4[0-9]{3}$' THEN SUBSTRING(TRIM(nu_idade_n) FROM 2 FOR 3)::INT
            WHEN TRIM(nu_idade_n) ~ '^[0-9]{1,2}$' THEN TRIM(nu_idade_n)::INT
            ELSE NULL
        END AS idade_anos,
        CASE WHEN TRIM(cs_raca) IN ('1','2','3','4','5') THEN TRIM(cs_raca) ELSE '9' END AS raca_cod,
        CASE
            WHEN NULLIF(TRIM(cs_escol_n), '') IS NULL THEN '9'
            WHEN TRIM(cs_escol_n) IN ('0', '00') THEN '0'
            WHEN LTRIM(TRIM(cs_escol_n), '0') IN ('1','2','3','4','5','6','7','8','10') THEN LTRIM(TRIM(cs_escol_n), '0')
            ELSE '9'
        END AS escolaridade_cod,
        CASE WHEN TRIM(cs_gestant) IN ('1','2','3','4','5','6') THEN TRIM(cs_gestant) ELSE '9' END AS gestante_cod,
        -- Campos de classificação
        CASE WHEN TRIM(classi_fin) IN ('5','8','13') THEN TRIM(classi_fin) ELSE '9' END AS classi_fin_cod,
        CASE WHEN TRIM(criterio) IN ('1','2','3') THEN TRIM(criterio) ELSE '9' END AS criterio_cod,
        CASE WHEN TRIM(evolucao) IN ('1','2','3','4') THEN TRIM(evolucao) ELSE '9' END AS evolucao_cod,
        CASE WHEN TRIM(hospitaliz) IN ('1','2') THEN TRIM(hospitaliz) ELSE '9' END AS hospitaliz_cod,
        CASE WHEN TRIM(clinc_chik) IN ('1','2') THEN TRIM(clinc_chik) ELSE '9' END AS clinc_chik_cod
    FROM sinan_dedup
),
com_faixa AS (
    SELECT
        *,
        CASE
            WHEN idade_anos IS NULL THEN 'Ignorado'
            WHEN idade_anos < 1 THEN '< 1 ano'
            WHEN idade_anos BETWEEN 1 AND 4 THEN '1-4 anos'
            WHEN idade_anos BETWEEN 5 AND 9 THEN '5-9 anos'
            WHEN idade_anos BETWEEN 10 AND 14 THEN '10-14 anos'
            WHEN idade_anos BETWEEN 15 AND 19 THEN '15-19 anos'
            WHEN idade_anos BETWEEN 20 AND 39 THEN '20-39 anos'
            WHEN idade_anos BETWEEN 40 AND 59 THEN '40-59 anos'
            WHEN idade_anos BETWEEN 60 AND 69 THEN '60-69 anos'
            WHEN idade_anos BETWEEN 70 AND 79 THEN '70-79 anos'
            ELSE '80+ anos'
        END AS faixa_etaria
    FROM preparado
)
SELECT
    ROW_NUMBER() OVER ()::BIGINT AS sk_notificacao,
    tn.sk_tempo AS sk_tempo_notificacao,
    ts.sk_tempo AS sk_tempo_sintomas,
    COALESCE(ln.sk_localidade, 0) AS sk_localidade_notificacao,
    COALESCE(lr.sk_localidade, 0) AS sk_localidade_residencia,
    dp.sk_paciente_perfil,
    dc.sk_classificacao,
    COALESCE(du.sk_unidade, 0) AS sk_unidade,
    f.ano_arquivo_origem,
    f.id_agravo_padronizado::VARCHAR(10),
    f.tp_sistema::VARCHAR(10),
    1::SMALLINT AS qtd_notificacoes,
    CASE WHEN f.classi_fin_cod = '13' THEN 1::SMALLINT ELSE 0::SMALLINT END AS flag_confirmado,
    CASE WHEN f.evolucao_cod = '2' THEN 1::SMALLINT ELSE 0::SMALLINT END AS flag_obito_agravo,
    CASE WHEN f.hospitaliz_cod = '1' THEN 1::SMALLINT ELSE 0::SMALLINT END AS flag_hospitalizado,
    (f.dt_notific_d - f.dt_sin_pri_d)::INT AS dias_sintoma_ate_notificacao,
    CASE
        WHEN f.dt_encerra_d IS NULL OR f.dt_encerra_d < f.dt_notific_d THEN NULL
        ELSE (f.dt_encerra_d - f.dt_notific_d)::INT
    END AS dias_notificacao_ate_encerramento,
    f.idade_anos::SMALLINT
FROM com_faixa f
JOIN dw_elt.dim_tempo tn ON f.dt_notific_d = tn.data_completa
JOIN dw_elt.dim_tempo ts ON f.dt_sin_pri_d = ts.data_completa
LEFT JOIN dw_elt.dim_localidade ln ON f.co_mun_not = ln.co_municip_6
LEFT JOIN dw_elt.dim_localidade lr ON f.co_mun_res = lr.co_municip_6
JOIN dw_elt.dim_paciente_perfil dp
    ON f.sexo_cod = dp.sexo_cod
   AND f.faixa_etaria = dp.faixa_etaria
   AND f.raca_cod = dp.raca_cod
   AND f.escolaridade_cod = dp.escolaridade_cod
   AND f.gestante_cod = dp.gestante_cod
JOIN dw_elt.dim_classificacao dc
    ON f.classi_fin_cod = dc.classi_fin_cod
   AND f.criterio_cod = dc.criterio_cod
   AND f.evolucao_cod = dc.evolucao_cod
   AND f.hospitaliz_cod = dc.hospitaliz_cod
   AND f.clinc_chik_cod = dc.clinc_chik_cod
LEFT JOIN dw_elt.dim_unidade du ON f.co_cnes_norm = du.co_cnes;

ALTER TABLE dw_elt.fato_notificacao
    ADD PRIMARY KEY (sk_notificacao),
    ADD CONSTRAINT fk_elt_tempo_not FOREIGN KEY (sk_tempo_notificacao) REFERENCES dw_elt.dim_tempo (sk_tempo),
    ADD CONSTRAINT fk_elt_tempo_sin FOREIGN KEY (sk_tempo_sintomas) REFERENCES dw_elt.dim_tempo (sk_tempo),
    ADD CONSTRAINT fk_elt_loc_not FOREIGN KEY (sk_localidade_notificacao) REFERENCES dw_elt.dim_localidade (sk_localidade),
    ADD CONSTRAINT fk_elt_loc_res FOREIGN KEY (sk_localidade_residencia) REFERENCES dw_elt.dim_localidade (sk_localidade),
    ADD CONSTRAINT fk_elt_pac FOREIGN KEY (sk_paciente_perfil) REFERENCES dw_elt.dim_paciente_perfil (sk_paciente_perfil),
    ADD CONSTRAINT fk_elt_cls FOREIGN KEY (sk_classificacao) REFERENCES dw_elt.dim_classificacao (sk_classificacao),
    ADD CONSTRAINT fk_elt_unid FOREIGN KEY (sk_unidade) REFERENCES dw_elt.dim_unidade (sk_unidade);
