-- ============================================================================
-- Análise 2: Distribuição Geográfica e Taxa de Incidência por 100 mil hab.
-- Pergunta de negócio: Quais UFs e Regiões concentraram as maiores taxas de
-- incidência de chikungunya por 100 mil habitantes (casos confirmados) em
-- 2023, 2024 e 2025, e houve deslocamento geográfico entre os anos?
-- ============================================================================

WITH pop_uf AS (
    SELECT
        sg_uf,
        nome_uf,
        nome_regiao,
        SUM(COALESCE(pop_2023, 0)) AS pop_2023,
        SUM(COALESCE(pop_2024, 0)) AS pop_2024,
        SUM(COALESCE(pop_2025, 0)) AS pop_2025
    FROM dw_elt.dim_localidade
    GROUP BY sg_uf, nome_uf, nome_regiao
),
casos_uf AS (
    SELECT
        l.sg_uf,
        f.ano_arquivo_origem AS ano,
        SUM(f.qtd_notificacoes) AS notificacoes,
        SUM(f.flag_confirmado) AS confirmados
    FROM dw_elt.fato_notificacao f
    JOIN dw_elt.dim_localidade l ON f.sk_localidade_residencia = l.sk_localidade
    WHERE l.sg_uf <> 'XX'
    GROUP BY l.sg_uf, f.ano_arquivo_origem
)
SELECT
    p.nome_regiao,
    c.sg_uf,
    p.nome_uf,
    c.ano,
    c.notificacoes,
    c.confirmados,
    CASE c.ano
        WHEN 2023 THEN p.pop_2023
        WHEN 2024 THEN p.pop_2024
        WHEN 2025 THEN p.pop_2025
    END AS populacao_uf,
    ROUND(
        100000.0 * c.confirmados / NULLIF(
            CASE c.ano
                WHEN 2023 THEN p.pop_2023
                WHEN 2024 THEN p.pop_2024
                WHEN 2025 THEN p.pop_2025
            END, 0
        ), 2
    ) AS incidencia_confirmados_100k
FROM casos_uf c
JOIN pop_uf p ON c.sg_uf = p.sg_uf
ORDER BY c.ano, incidencia_confirmados_100k DESC NULLS LAST;
