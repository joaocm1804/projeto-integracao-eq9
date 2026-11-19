# Perfilamento Comparativo das Bases SINAN Chikungunya (2023, 2024 e 2025)

Este documento reúne os resultados do perfilamento exploratório executado pelo script [00_perfilamento.py](../notebooks/00_perfilamento.py) sobre os arquivos brutos armazenados em `dados/sinan_chikungunya/` e `dados/externos/` (snapshot obtido em 11 e 12/11/2026). O objetivo é registrar a volumetria, a completude e as divergências de esquema e domínio entre os três anos antes da etapa de integração.

## 1. Estrutura, esquema e formatos

Os três arquivos anuais do SINAN (`CHIKBR23.csv`, `CHIKBR24.csv` e `CHIKBR25.csv`) possuem exatamente as mesmas 122 colunas, dispostas na mesma ordem. Entretanto, o dicionário de dados oficial em PDF (`dic_dados_chikungunya.pdf`) documenta apenas 121 campos, omitindo a coluna `NU_LOTE_I`, presente nos CSVs publicados. Os arquivos principais utilizam vírgula como delimitador, codificação UTF-8/ASCII, cabeçalho na primeira linha e datas no formato `AAAA-MM-DD`.

As fontes externas de enriquecimento apresentam formatos heterogêneos. A Base Territorial do DATASUS usa ponto e vírgula em UTF-8, com exceção de `tb_regsaud.csv`, que adota vírgula e quebras de linha LF, além de vírgula como separador decimal nas coordenadas geográficas. O recorte do CNES usa ponto e vírgula, campos textuais entre aspas e contém caracteres em `LATIN1` (como o byte `0xad` na linha 1983). As bases populacionais do IBGE (SIDRA 4709 do Censo 2022 e SIDRA 6579 das estimativas de 2024 e 2025) estão em JSON com metadados de cabeçalho no índice `0` e marcador `"..."` para valores ausentes. Por fim, as tabelas auxiliares do TabWin (`.cnv` e `.DBF`) estão codificadas em `LATIN1`.

## 2. Volumetria, duplicatas e cobertura de chaves

A tabela abaixo consolida a contagem de registros brutos, duplicatas identificadas e cobertura das chaves de junção com as bases territoriais e de estabelecimentos.

| Métrica | 2023 | 2024 | 2025 | Total |
|---|---:|---:|---:|---:|
| Linhas brutas | 266.442 | 426.214 | 253.753 | 946.409 |
| Duplicatas exatas (linhas excedentes) | 114 | 186 | 105 | 405 |
| Marcadas `NDUPLIC_N = 1` | 67 | 675 | 335 | 1.077 |
| Registros do ES (`SG_UF_NOT = 32`) | 18.249 (6,85%) | 22.983 (5,39%) | 6.029 (2,38%) | 47.261 |
| Cobertura `ID_MUNICIP` (DATASUS) | 100,00% | 100,00% | 100,00% | 100,00% |
| Cobertura `ID_MN_RESI` (DATASUS) | 100,00% | 100,00% | 100,00% | — |
| Cobertura `ID_UNIDADE` (CNES recorte) | 99,27% | 99,07% | 99,52% | — |
| `SEM_PRI` (mín – máx) | 202301–202352 | 202401–202452 | 202501–202553 | — |

O pico de notificações ocorreu em 2024 (426.214 registros), volume 60% superior ao de 2023. As 405 linhas com duplicação exata em todas as 122 colunas correspondem a menos de 0,05% do total e foram removidas nas etapas iniciais do ETL e do ELT, mantendo-se os registros marcados com `NDUPLIC_N = 1` por representarem sinalização operacional da própria ficha. A cobertura municipal é integral em todos os anos (considerando os códigos especiais `666666` e `999999` presentes na base do DATASUS e os 6 casos com `ID_MN_RESI` vazio), enquanto a cobertura do CNES supera 99% nos três anos, motivando a criação do membro substituto `sk_unidade = 0` na dimensão de unidades.

## 3. Completude: nulos e código "Ignorado" (`9`) nas colunas-chave do DW

A tabela seguinte apresenta, para cada ano e atributo selecionado para o Data Warehouse, o percentual de valores vazios (à esquerda da barra) e o percentual preenchido com o código `9` correspondente a "Ignorado" (à direita).

| Coluna | 2023 Vazio / `9` | 2024 Vazio / `9` | 2025 Vazio / `9` |
|---|---|---|---|
| `DT_NOTIFIC` | 0,00% / 0,00% | 0,00% / 0,00% | 0,00% / 0,00% |
| `DT_SIN_PRI` | 0,00% / 0,00% | 0,00% / 0,00% | 0,00% / 0,00% |
| `DT_ENCERRA` | 11,18% / 0,00% | 8,29% / 0,00% | 7,04% / 0,00% |
| `DT_INTERNA` | 97,61% / 0,00% | 97,40% / 0,00% | 96,21% / 0,00% |
| `DT_OBITO` | 99,80% / 0,00% | 99,77% / 0,00% | 99,73% / 0,00% |
| `SG_UF_NOT` | 0,00% / 0,00% | 0,00% / 0,00% | 0,00% / 0,00% |
| `ID_MUNICIP` | 0,00% / 0,00% | 0,00% / 0,00% | 0,00% / 0,00% |
| `ID_MN_RESI` | 0,00% / 0,00% | 0,00% / 0,00% | 0,00% / 0,00% |
| `ID_UNIDADE` | 0,19% / 0,00% | 0,49% / 0,00% | 0,03% / 0,00% |
| `NU_IDADE_N` | 0,00% / 0,00% | 0,00% / 0,00% | 0,00% / 0,00% |
| `CS_SEXO` | 0,00% / 0,00% | 0,00% / 0,00% | 0,00% / 0,00% |
| `CS_GESTANT` | 0,02% / 10,04% | 0,01% / 8,66% | 0,01% / 4,79% |
| `CS_RACA` | 0,00% / 15,46% | 0,00% / 12,41% | 0,00% / 5,41% |
| `CS_ESCOL_N` | 17,46% / 37,72% | 22,36% / 30,55% | 16,85% / 21,82% |
| `HOSPITALIZ` | 33,93% / 2,40% | 26,92% / 1,83% | 20,54% / 0,62% |
| `CLASSI_FIN` | 10,44% / 0,00% | 7,51% / 0,00% | 6,37% / 0,00% |
| `CRITERIO` | 9,67% / 0,00% | 6,80% / 0,00% | 5,38% / 0,00% |
| `CLINC_CHIK` | 39,47% / 0,00% | 32,02% / 0,00% | 38,33% / 0,00% |
| `EVOLUCAO` | 15,70% / 8,31% | 12,35% / 5,76% | 11,66% / 4,99% |
| `RES_CHIKS1` | 48,82% / 0,00% | 47,82% / 0,00% | 97,62% / 0,00% |
| `RES_CHIKS2` | 62,62% / 0,00% | 64,35% / 0,00% | 97,62% / 0,00% |
| `RESUL_PRNT` | 62,29% / 0,00% | 63,39% / 0,00% | 97,62% / 0,00% |
| `ID_OCUPA_N` | 62,21% / 0,00% | 62,41% / 0,00% | 61,43% / 0,00% |

Campos estruturantes como `DT_NOTIFIC`, `DT_SIN_PRI`, `SG_UF_NOT`, `ID_MUNICIP`, `NU_IDADE_N` e `CS_SEXO` têm preenchimento praticamente integral. A elevada taxa de vazios em `DT_INTERNA` (acima de 96%) e `DT_OBITO` (acima de 99,7%) é esperada, pois esses campos só são preenchidos quando há internação ou óbito. Já `CS_ESCOL_N` e `ID_OCUPA_N` apresentam alta proporção de vazios ou ignorados em todos os anos, razão pela qual `ID_OCUPA_N` não foi levada à dimensão de perfil de paciente e os valores faltantes dos demais campos foram explicitamente preservados como `"Ignorado/Branco"`. Destaca-se ainda o comportamento dos campos de sorologia (`RES_CHIKS1`, `RES_CHIKS2` e `RESUL_PRNT`), que passaram de cerca de 48% a 64% de ausência em 2023–2024 para 97,62% de vazios em 2025, permanecendo preenchidos apenas nos registros do Espírito Santo.

## 4. Qualidade temporal e decodificação de idade

Foram verificadas inconsistências cronológicas entre datas clínicas e administrativas, bem como registros fora do padrão de quatro dígitos em `NU_IDADE_N`.

| Verificação | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `DT_SIN_PRI > DT_NOTIFIC` | 0 | 0 | 0 |
| `DT_ENCERRA < DT_NOTIFIC` | 11 | 26 | 20 |
| `DT_OBITO < DT_SIN_PRI` | 0 | 1 | 0 |
| `DT_NOTIFIC` (mín a máx) | 2023-01-01 a 2024-05-20 | 2023-12-31 a 2025-04-02 | 2024-12-29 a 2026-07-07 |
| `DT_SIN_PRI` (mín a máx) | 2023-01-01 a 2023-12-30 | 2023-12-31 a 2025-01-04 | 2024-12-29 a 2026-01-03 |
| `NU_IDADE_N` inválidas | 4 | 3 | 2 |

Como os CSVs são particionados pela semana epidemiológica de início dos sintomas (`SEM_PRI`), os limites de `DT_SIN_PRI` respeitam as fronteiras do calendário epidemiológico MMWR (explicando datas como `2023-12-31` no arquivo de 2024 e `2024-12-29` no de 2025), enquanto `DT_NOTIFIC` estende-se para o ano seguinte em função de notificações tardias. Os 57 casos com `DT_ENCERRA < DT_NOTIFIC` tiveram o intervalo `dias_notificacao_ate_encerramento` convertido em `NULL`, e os 9 registros com `NU_IDADE_N` de dois dígitos sem prefixo foram tratados diretamente como idade em anos.

## 5. Domínios observados vs. dicionário oficial (`.cnv` e PDF)

As tabelas a seguir listam as frequências brutas observadas para os principais campos categóricos selecionados para o modelo dimensional, permitindo confrontar os dados reais com as tabelas `.cnv` do TabWin e com o dicionário em PDF.

### `ID_AGRAVO`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `A92.0` | 266.442 | 426.214 | 247.725 |
| `A920` | 0 | 0 | 6.028 |

Em 2025, os 6.028 registros sem ponto (`A920`) correspondem ao envio do Espírito Santo via e-SUS VS e foram padronizados para `A92.0`.

### `TP_SISTEMA`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `/` | 6 | 0 | 0 |
| `0` | 0 | 22.983 | 6.028 |
| `2` | 243.076 | 394.445 | 243.190 |
| `<VAZIO>` | 23.360 | 8.786 | 4.535 |

O código `2` identifica o SINAN Online e `0` identifica o e-SUS VS a partir de 2024; em 2023, o campo vinha vazio ou preenchido com `/` nos registros do ES.

### `CS_SEXO`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `<VAZIO>` | 0 | 2 | 0 |
| `F` | 156.668 | 251.700 | 148.482 |
| `I` | 483 | 392 | 161 |
| `M` | 109.291 | 174.120 | 105.110 |

### `CS_GESTANT`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `1` | 830 | 1.380 | 1.054 |
| `2` | 1.328 | 1.970 | 1.521 |
| `3` | 1.202 | 1.903 | 1.452 |
| `4` | 610 | 806 | 505 |
| `5` | 100.527 | 167.733 | 107.762 |
| `6` | 135.121 | 215.452 | 129.267 |
| `9` | 26.763 | 36.927 | 12.163 |
| `<VAZIO>` | 61 | 43 | 29 |

### `CS_RACA`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `1` | 47.056 | 103.006 | 87.118 |
| `2` | 13.612 | 24.327 | 12.308 |
| `3` | 4.377 | 6.899 | 4.518 |
| `4` | 159.285 | 237.057 | 134.722 |
| `5` | 931 | 2.034 | 1.365 |
| `9` | 41.181 | 52.890 | 13.722 |
| `<VAZIO>` | 0 | 1 | 0 |

### `CS_ESCOL_N`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `0` | 1.804 | 2.400 | 1.498 |
| `05` | 0 | 0 | 1 |
| `07` | 0 | 0 | 1 |
| `1` | 9.096 | 15.001 | 10.155 |
| `10` | 15.147 | 23.331 | 16.990 |
| `2` | 4.983 | 8.831 | 6.944 |
| `3` | 15.031 | 24.043 | 18.144 |
| `4` | 9.474 | 18.466 | 12.729 |
| `5` | 12.343 | 20.866 | 15.592 |
| `6` | 37.296 | 65.367 | 54.557 |
| `7` | 3.581 | 5.921 | 4.849 |
| `8` | 10.671 | 16.488 | 14.174 |
| `9` | 100.505 | 130.212 | 55.373 |
| `<VAZIO>` | 46.511 | 95.288 | 42.746 |

Em 2025 ocorreram dois registros com zero à esquerda (`05` e `07`) coexistindo com `5` e `7`, exigindo remoção do zero inicial antes do mapeamento com `Escolarnet.cnv` (mantendo `'0'` para Analfabeto).

### `HOSPITALIZ`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `0` | 2 | 0 | 0 |
| `1` | 7.480 | 12.655 | 10.943 |
| `2` | 162.176 | 291.030 | 189.112 |
| `9` | 6.387 | 7.787 | 1.580 |
| `<VAZIO>` | 90.397 | 114.742 | 52.118 |

### `CLASSI_FIN`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `0` | 385 | 0 | 48 |
| `13` | 130.196 | 232.047 | 110.477 |
| `5` | 108.044 | 162.176 | 127.054 |
| `8` | 0 | 0 | 1 |
| `<VAZIO>` | 27.817 | 31.991 | 16.173 |

Embora o PDF oficial mencione os códigos `1`, `2` e `8`, os dados seguem a tabela `Classchik.cnv` (`13` = Chikungunya, `5` = Descartado, `8` = Inconclusivo), somada ao código `0` vindo do e-SUS VS (385 registros em 2023 e 48 em 2025).

### `CRITERIO`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `0` | 308 | 131 | 67 |
| `1` | 114.584 | 215.193 | 149.357 |
| `2` | 122.048 | 175.841 | 86.689 |
| `3` | 3.743 | 6.062 | 3.976 |
| `<VAZIO>` | 25.759 | 28.987 | 13.664 |

### `CLINC_CHIK`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `/` | 3 | 0 | 0 |
| `0` | 0 | 9.703 | 2.576 |
| `1` | 156.444 | 276.208 | 152.145 |
| `2` | 4.842 | 3.839 | 1.773 |
| `<VAZIO>` | 105.153 | 136.464 | 97.259 |

Em `CLINC_CHIK`, os códigos válidos são `1` (Aguda) e `2` (Crônica); os valores `0`, `/` (3 casos em 2023) e vazios foram mapeados para `9` (`Ignorado/Branco`).

### `EVOLUCAO`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `0` | 1.238 | 459 | 214 |
| `1` | 200.669 | 347.598 | 210.610 |
| `2` | 124 | 247 | 131 |
| `3` | 372 | 653 | 503 |
| `4` | 46 | 69 | 39 |
| `9` | 22.151 | 24.564 | 12.670 |
| `<VAZIO>` | 41.842 | 52.624 | 29.586 |

### `RES_CHIKS1`
| Valor bruto | 2023 | 2024 | 2025 |
|---|---:|---:|---:|
| `0` | 11.848 | 13.215 | 2.980 |
| `1` | 34.135 | 68.576 | 811 |
| `2` | 29.316 | 53.746 | 2.179 |
| `3` | 1.229 | 2.186 | 21 |
| `4` | 59.751 | 84.507 | 13 |
| `5` | 85 | 151 | 24 |
| `<VAZIO>` | 130.078 | 203.833 | 247.725 |

A queda abrupta de resultados preenchidos em `RES_CHIKS1` em 2025 (apenas 6.028 registros não vazios, frente a mais de 136 mil em 2023 e 222 mil em 2024) coincide exatamente com o recorte do Espírito Santo naquele ano.
