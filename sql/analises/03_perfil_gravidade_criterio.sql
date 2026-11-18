-- ============================================================================
-- Análise 3: Perfil Demográfico, Gravidade e Critério de Confirmação
-- Pergunta de negócio: Como variam as taxas de confirmação, hospitalização e
-- letalidade por faixa etária e sexo? Qual a proporção de confirmação
-- laboratorial vs. clínico-epidemiológica ao longo de 2023–2025?
-- ============================================================================

-- 3A. Perfil e gravidade por faixa etária e sexo
SELECT
    p.ordem_faixa_etaria,
    p.faixa_etaria,
    p.sexo_desc,
    SUM(f.qtd_notificacoes) AS notificacoes,
    SUM(f.flag_confirmado) AS confirmados,
    SUM(f.flag_hospitalizado) AS hospitalizados,
    SUM(f.flag_obito_agravo) AS obitos,
    ROUND(100.0 * SUM(f.flag_hospitalizado) / NULLIF(SUM(f.flag_confirmado), 0), 2) AS pct_hosp_entre_confirmados,
    ROUND(100.0 * SUM(f.flag_obito_agravo) / NULLIF(SUM(f.flag_confirmado), 0), 3) AS letalidade_pct
FROM dw_elt.fato_notificacao f
JOIN dw_elt.dim_paciente_perfil p ON f.sk_paciente_perfil = p.sk_paciente_perfil
WHERE p.sexo_cod IN ('F', 'M')
  AND p.ordem_faixa_etaria < 99
GROUP BY p.ordem_faixa_etaria, p.faixa_etaria, p.sexo_desc
ORDER BY p.ordem_faixa_etaria, p.sexo_desc;

-- 3B. Critério de confirmação entre os casos confirmados (CLASSI_FIN = 13) por ano
SELECT
    f.ano_arquivo_origem AS ano,
    c.criterio_desc,
    SUM(f.qtd_notificacoes) AS total_confirmados,
    ROUND(
        100.0 * SUM(f.qtd_notificacoes) / SUM(SUM(f.qtd_notificacoes)) OVER (PARTITION BY f.ano_arquivo_origem),
        2
    ) AS pct_no_ano
FROM dw_elt.fato_notificacao f
JOIN dw_elt.dim_classificacao c ON f.sk_classificacao = c.sk_classificacao
WHERE f.flag_confirmado = 1
GROUP BY f.ano_arquivo_origem, c.criterio_desc
ORDER BY f.ano_arquivo_origem, total_confirmados DESC;
