# Relatório Técnico: Integração e Modelagem de Dados de Febre de Chikungunya (SINAN 2023–2025)

**Disciplina:** CIn0137 — Banco de Dados (UFPE/CIn, período 2026.2)  
**Professora:** Valéria Cesário Times  
**Atividade:** Projeto de Integração de Dados (AV5)  
**Tema:** Notificações de Febre de Chikungunya no Brasil (2023 a 2025)

## 1. Justificativa e recorte da base de dados

A vigilância das arboviroses urbanas no Brasil depende da consolidação de registros administrativos oriundos de diferentes sistemas e esferas de gestão. Neste projeto, optou-se por integrar as notificações de Febre de Chikungunya (CID-10 `A92.0`) registradas no Sistema de Informação de Agravos de Notificação (SINAN) e publicadas no portal OpenDataSUS, cobrindo os anos epidemiológicos de 2023, 2024 e 2025.

A escolha desse recorte temporal evita o uso dos dados ainda parciais de 2026, permitindo comparar três anos epidemiológicos completos de 52 ou 53 semanas. No snapshot congelado em 11 e 12/11/2026, os três arquivos somam 946.409 notificações brutas, distribuídas em 266.442 registros em 2023 (`CHIKBR23.csv`), 426.214 em 2024 (`CHIKBR24.csv`) e 253.753 em 2025 (`CHIKBR25.csv`). Como os dados de 2025 ainda podem receber atualizações tardias de encerramento nas republicações diárias do OpenDataSUS, o congelamento local dos arquivos garante a reprodutibilidade das cargas e consultas.

Do ponto de vista de integração, a base oferece problemas reais de heterogeneidade sem perda de cobertura nacional. Embora os CSVs dos três anos possuam a mesma estrutura tabular de 122 colunas, há diferenças operacionais entre os registros enviados via SINAN Online e os importados do sistema estadual e-SUS VS (Espírito Santo), além de divergências entre o dicionário oficial em PDF e as tabelas auxiliares `.cnv` do TabWin. A carga principal foi ainda combinada com três fontes externas em formatos distintos: a Base Territorial do DATASUS, as séries populacionais do IBGE via SIDRA (4709 do Censo 2022 e 6579 das estimativas de 2024 e 2025, em JSON) e o recorte de estabelecimentos do CNES (codificação `LATIN1`). Como o volume total fica abaixo de 1 milhão de linhas, foi possível processar todo o território nacional em PostgreSQL local no ambiente do Google Colab, sem necessidade de amostragem.

## 2. Perfilamento comparativo e inconsistências observadas

O levantamento exploratório foi automatizado no script [00_perfilamento.py](../notebooks/00_perfilamento.py) e documentado em [perfilamento_comparativo.md](perfilamento_comparativo.md). A comparação entre 2023, 2024 e 2025 evidenciou os pontos listados a seguir.

Na verificação estrutural, todos os três arquivos mantiveram exatamente as mesmas 122 colunas na mesma ordem. Contudo, o dicionário oficial em PDF (`dic_dados_chikungunya.pdf`) descreve apenas 121 campos, omitindo a coluna `NU_LOTE_I`.

Quanto à unicidade, foram encontradas 405 linhas exatamente duplicadas considerando todas as colunas (114 em 2023, 186 em 2024 e 105 em 2025). Após a remoção dessas repetições exatas, o conjunto útil passou para 946.004 notificações.

Os registros oriundos do Espírito Santo (`e-SUS VS`, totalizando 18.249 notificações em 2023, 22.983 em 2024 e 6.029 em 2025) apresentaram comportamento próprio ao longo do triênio. Em 2023, o campo `TP_SISTEMA` aparece vazio (e com o caractere `/` em 6 registros) e há 385 notificações com `CLASSI_FIN = 0`; já em 2024 e 2025, o sistema passa a preencher `TP_SISTEMA = 0`. Em 2025, o código do agravo aparece como `A920` sem ponto, diferindo do padrão `A92.0` dos demais anos. Nos três arquivos, `ID_REGIONA` do ES utiliza códigos da Comissão Intergestores Regional (CIR) de 5 dígitos. Em vez de descartar o estado, decidiu-se manter os registros e harmonizá-los durante as transformações, derivando Região de Saúde e Macrorregião a partir do código do município na tabela `tb_municip`.

Nos campos laboratoriais de sorologia IgM (`RES_CHIKS1`, `RES_CHIKS2` e `RESUL_PRNT`), observou-se queda acentuada de preenchimento em 2025, ano em que 97,62% das notificações vieram com esses campos vazios, restando preenchimento apenas no Espírito Santo. Essa mudança afeta a leitura direta do critério de confirmação laboratorial na comparação anual.

Em relação aos domínios, constatou-se divergência direta entre o dicionário PDF e os valores presentes nos CSVs. Para `CLASSI_FIN`, o PDF indica os códigos `1`, `2` e `8`, mas os arquivos trazem `13` (Chikungunya), `5` (Descartado) e `8` (Inconclusivo), além de `0` nos casos atípicos do e-SUS VS. Adotou-se como referência oficial a tabela `Classchik.cnv` do TabWin.

Por fim, o perfilamento identificou anomalias pontuais de preenchimento e codificação: mistura de zeros à esquerda em `CS_ESCOL_N` (`05` e `07` junto de `5` e `7`), 9 registros de `NU_IDADE_N` informados com dois dígitos sem o prefixo de unidade (4 em 2023, 3 em 2024 e 2 em 2025), o caractere `/` em `CLINC_CHIK` em 3 registros de 2023, 57 notificações com `DT_ENCERRA` anterior a `DT_NOTIFIC` e 1 byte `0xad` em codificação `LATIN1` na linha 1983 do arquivo de recorte do CNES.

## 3. Modelagem dimensional

Seguindo a abordagem de Elmasri e Navathe para ambientes analíticos, o Data Warehouse foi projetado em Esquema Estrela (*Star Schema*). O grão da tabela fato (`fato_notificacao`) corresponde a uma notificação individual única, resultando em 946.004 linhas após a deduplicação.

A tabela fato conecta-se a cinco dimensões analíticas. Duas delas operam no padrão de múltiplos papéis (*role-playing dimensions*): `dim_tempo` é referenciada tanto para a data de notificação (`sk_tempo_notificacao`) quanto para a data de início dos sintomas (`sk_tempo_sintomas`), enquanto `dim_localidade` (enriquecida com a hierarquia territorial do DATASUS e as populações do IBGE SIDRA 4709 e 6579) atende tanto ao município notificante (`sk_localidade_notificacao`) quanto ao município de residência (`sk_localidade_residencia`), com chave `0` reservada aos 6 registros sem município de residência informado. As demais dimensões agrupam o perfil sociodemográfico do paciente (`dim_paciente_perfil`), o desfecho e critério clínico (`dim_classificacao`) e o estabelecimento notificante (`dim_unidade`, integrada ao CNES e a `TipoUnidade.cnv`, com membro `sk_unidade = 0` para unidades ausentes ou não localizadas).

O detalhamento de atributos, tipos e domínios encontra-se em [modelagem_e_dicionario.md](modelagem_e_dicionario.md), e os diagramas da arquitetura constam em [diagramas.drawio](diagramas.drawio).

## 4. Processo de integração e regras de tratamento

Para garantir equivalência entre os dois fluxos implementados, aplicou-se o mesmo conjunto de regras de limpeza e conformidade tanto em Python quanto em SQL. Inicialmente, o volume bruto de 946.409 linhas foi reduzido para 946.004 após a remoção das 405 duplicatas exatas considerando todas as 122 colunas.

As datas de notificação, início de sintomas e encerramento foram convertidas para o tipo `DATE`, permitindo calcular `dias_sintoma_ate_notificacao` e `dias_notificacao_ate_encerramento`. Nos 57 registros em que a data de encerramento antecedia a notificação, o intervalo foi convertido em `NULL` para não distorcer médias. A partir das datas válidas, derivaram-se também o ano e a semana epidemiológica segundo o padrão MMWR.

Para a idade (`NU_IDADE_N`), valores iniciados pelos prefixos `1` (hora), `2` (dia) ou `3` (mês) foram convertidos em `0` ano completo; valores no padrão `4xxx` tiveram o prefixo removido; e os 9 registros com apenas dois dígitos foram interpretados diretamente em anos, gerando na sequência 10 faixas etárias padronizadas.

Na harmonização de domínios, `A920` foi unificado para `A92.0`, os valores vazios ou `/` de `TP_SISTEMA` receberam o rótulo `IGN`, e os zeros à esquerda de `CS_ESCOL_N` foram removidos preservando o código `0` (Analfabeto). Valores nulos, barras e códigos `9` ou `0` sem categoria válida foram mantidos explicitamente nas dimensões como `"Ignorado/Branco"`, evitando a perda de registros nas contagens globais.

Na junção com as fontes externas, utilizou-se o código municipal de 6 dígitos (`CO_MUNICIP`) para o DATASUS e o de 7 dígitos (`CO_MUNICDV`) para o IBGE. Como a pesquisa SIDRA 6579 não possui estimativa publicada para 2023, empregou-se o Censo Demográfico de 2022 (SIDRA 4709) como denominador populacional desse ano e a série 6579 para 2024 e 2025. O arquivo do CNES foi lido em `LATIN1`, com preenchimento à esquerda para 7 caracteres (`LPAD`) no formato texto para `ID_UNIDADE` e `CO_CNES`. Na Base Territorial, as vírgulas decimais de latitude e longitude foram trocadas por ponto e o marcador `"..."` do SIDRA foi convertido em `NULL`. Por fim, geraram-se chaves substitutas inteiras (*surrogate keys*) em todas as dimensões para compor as chaves estrangeiras da tabela fato.

## 5. Comparação entre os pipelines ETL e ELT

O projeto implementou duas rotas paralelas no PostgreSQL para comparar os paradigmas ETL (schema `dw_etl`) e ELT (schema `dw_elt`) sobre os mesmos dados de entrada.

| Critério | Pipeline ETL (`dw_etl`) | Pipeline ELT (`dw_elt`) |
|---|---|---|
| Local de transformação | Em Python (`pandas`), fora do banco de dados | No interior do PostgreSQL, via scripts SQL em `/sql/elt/` |
| Estratégia de carga | Carrega tabelas já limpas e modeladas via `COPY` | Carrega dados brutos em `stg_elt` (`TEXT` e `JSONB`) e transforma com `CTAS`, `JOIN` e `jsonb_array_elements` |
| Pontos positivos observados | Tratamento direto de arquivos `.cnv` em `LATIN1`, manipulação simples de strings e inspeção intermediária passo a passo | Preservação do dado bruto dentro do SGBD para rastreabilidade e uso do otimizador do PostgreSQL nas junções e agregações |
| Limitações observadas | Maior consumo de memória RAM no Google Colab durante concatenações e junções de tabelas | Maior verbosidade do código SQL para regras procedurais, exigindo pré-carga auxiliar para os arquivos `.cnv` |
| Adequação no projeto | Prático para exploração inicial, validação de hipóteses e prototipação | Organizado para reexecução determinística, versionamento das regras em SQL e auditoria dentro do banco |

A consistência entre os dois schemas foi verificada pela consulta de auditoria [00_auditoria_etl_vs_elt.sql](../sql/analises/00_auditoria_etl_vs_elt.sql), que confronta a contagem de linhas de todas as dimensões, o total de fatos e as somas anuais de casos confirmados, hospitalizações, óbitos e médias de intervalos temporais.

## 6. Consultas analíticas sobre o Esquema Estrela

As consultas de negócio estão armazenadas em `/sql/analises/` e são executadas com geração de gráficos no notebook [02_pipeline_elt_chikungunya.ipynb](../notebooks/elt/02_pipeline_elt_chikungunya.ipynb).

A primeira consulta, [01_sazonalidade_semanas_epi.sql](../sql/analises/01_sazonalidade_semanas_epi.sql), relaciona a tabela fato com `dim_tempo` pelo papel de início dos sintomas (`sk_tempo_sintomas`). Ela calcula o volume semanal de notificações, o total de casos confirmados e a taxa de confirmação ao longo das semanas epidemiológicas de 2023, 2024 e 2025, além de produzir um consolidado anual com hospitalizações e óbitos pelo agravo.

A segunda consulta, [02_incidencia_geografica_uf_regiao.sql](../sql/analises/02_incidencia_geografica_uf_regiao.sql), cruza a tabela fato com `dim_localidade` pelo município de residência (`sk_localidade_residencia`), filtrando registros estrangeiros ou inválidos (`sg_uf <> 'XX'`). A consulta agrega os casos confirmados por UF e Grande Região e calcula a taxa de incidência por 100 mil habitantes associando cada ano ao seu respectivo denominador populacional (`pop_2023`, `pop_2024` e `pop_2025`).

A terceira consulta, [03_perfil_gravidade_criterio.sql](../sql/analises/03_perfil_gravidade_criterio.sql), divide-se em duas visões: primeiro une `fato_notificacao` a `dim_paciente_perfil` para medir notificações, confirmações, taxa de hospitalização e letalidade por faixa etária e sexo (excluindo categorias ignoradas); em seguida, usa `dim_classificacao` para observar a participação anual dos critérios de confirmação (laboratorial vs. clínico-epidemiológico) entre os casos confirmados, levando em conta na leitura de 2025 a lacuna nos exames de sorologia IgM fora do Espírito Santo.

## 7. Considerações finais

A construção deste projeto mostrou que dados abertos de saúde exigem perfilamento contínuo sempre que o recorte é alterado. A substituição do ano incompleto de 2026 pelo ano fechado de 2023 expôs anomalias que não apareciam isoladamente em 2024 e 2025, como o caractere `/` em `CLINC_CHIK` e `TP_SISTEMA`, o byte `0xad` no CNES e a ausência da série populacional 6579 para 2023, solucionada com o Censo 2022 (SIDRA 4709).

Implementar a mesma especificação dimensional em `pandas` e em SQL puro ajudou a evidenciar na prática as diferenças entre ETL e ELT: enquanto o Python simplifica a leitura de formatos legados (`.cnv` e `LATIN1`) e o tratamento de strings irregulares, o modelo ELT centraliza o dado bruto em área de *staging* e torna o processo de transformação auditável diretamente no SGBD. Por fim, o congelamento do snapshot dos arquivos fonte aliado ao versionamento dos scripts SQL e notebooks assegura que qualquer execução no Google Colab reproduza os mesmos números obtidos nas análises.
