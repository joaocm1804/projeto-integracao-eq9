-- ============================================================================
-- Análise 1: Sazonalidade e Evolução Temporal por Semana Epidemiológica
-- Pergunta de negócio: Como evoluem as notificações e confirmações de
-- chikungunya ao longo das semanas epidemiológicas dos três anos completos
-- (2023, 2024 e 2025) e quais são os picos sazonais?
-- ============================================================================

SELECT
    t.ano_epidemiologico,
    t.semana_epidemiologica,
    SUM(f.qtd_notificacoes) AS total_notificacoes,
    SUM(f.flag_confirmado) AS total_confirmados,
    ROUND(100.0 * SUM(f.flag_confirmado) / NULLIF(SUM(f.qtd_notificacoes), 0), 2) AS taxa_confirmacao_pct
FROM dw_elt.fato_notificacao f
JOIN dw_elt.dim_tempo t ON f.sk_tempo_sintomas = t.sk_tempo
WHERE t.ano_epidemiologico IN (2023, 2024, 2025)
GROUP BY t.ano_epidemiologico, t.semana_epidemiologica
ORDER BY t.ano_epidemiologico, t.semana_epidemiologica;

-- Consolidado anual completo (2023, 2024 e 2025)
SELECT
    t.ano_epidemiologico,
    SUM(f.qtd_notificacoes) AS total_notificacoes,
    SUM(f.flag_confirmado) AS total_confirmados,
    SUM(f.flag_hospitalizado) AS total_hospitalizados,
    SUM(f.flag_obito_agravo) AS total_obitos_agravo
FROM dw_elt.fato_notificacao f
JOIN dw_elt.dim_tempo t ON f.sk_tempo_sintomas = t.sk_tempo
WHERE t.ano_epidemiologico IN (2023, 2024, 2025)
GROUP BY t.ano_epidemiologico
ORDER BY t.ano_epidemiologico;
