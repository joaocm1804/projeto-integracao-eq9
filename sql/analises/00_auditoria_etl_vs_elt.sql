-- ============================================================================
-- Auditoria de Equivalência entre os Schemas dw_etl e dw_elt
-- Compara contagens das dimensões, tabela fato e somas das medidas-chave.
-- ============================================================================

SELECT 'dim_tempo' AS tabela,
       (SELECT COUNT(*) FROM dw_etl.dim_tempo) AS etl_linhas,
       (SELECT COUNT(*) FROM dw_elt.dim_tempo) AS elt_linhas
UNION ALL
SELECT 'dim_localidade',
       (SELECT COUNT(*) FROM dw_etl.dim_localidade),
       (SELECT COUNT(*) FROM dw_elt.dim_localidade)
UNION ALL
SELECT 'dim_paciente_perfil',
       (SELECT COUNT(*) FROM dw_etl.dim_paciente_perfil),
       (SELECT COUNT(*) FROM dw_elt.dim_paciente_perfil)
UNION ALL
SELECT 'dim_classificacao',
       (SELECT COUNT(*) FROM dw_etl.dim_classificacao),
       (SELECT COUNT(*) FROM dw_elt.dim_classificacao)
UNION ALL
SELECT 'dim_unidade',
       (SELECT COUNT(*) FROM dw_etl.dim_unidade),
       (SELECT COUNT(*) FROM dw_elt.dim_unidade)
UNION ALL
SELECT 'fato_notificacao',
       (SELECT COUNT(*) FROM dw_etl.fato_notificacao),
       (SELECT COUNT(*) FROM dw_elt.fato_notificacao);

-- Comparação das métricas agregadas por ano de origem
SELECT
    'ETL' AS pipeline,
    ano_arquivo_origem,
    COUNT(*) AS total_notificacoes,
    SUM(flag_confirmado) AS confirmados,
    SUM(flag_hospitalizado) AS hospitalizados,
    SUM(flag_obito_agravo) AS obitos_agravo,
    ROUND(AVG(dias_sintoma_ate_notificacao), 2) AS media_dias_sintoma_not,
    ROUND(AVG(dias_notificacao_ate_encerramento), 2) AS media_dias_encerra
FROM dw_etl.fato_notificacao
GROUP BY ano_arquivo_origem
UNION ALL
SELECT
    'ELT' AS pipeline,
    ano_arquivo_origem,
    COUNT(*),
    SUM(flag_confirmado),
    SUM(flag_hospitalizado),
    SUM(flag_obito_agravo),
    ROUND(AVG(dias_sintoma_ate_notificacao), 2),
    ROUND(AVG(dias_notificacao_ate_encerramento), 2)
FROM dw_elt.fato_notificacao
GROUP BY ano_arquivo_origem
ORDER BY ano_arquivo_origem, pipeline;
