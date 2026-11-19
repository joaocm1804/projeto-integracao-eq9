# Modelagem Dimensional (Esquema Estrela) e Dicionário de Dados

Este documento formaliza o modelo dimensional do Data Warehouse de Febre de Chikungunya (SINAN 2023–2025) segundo a terminologia de Elmasri e Navathe, detalhando as regras de transformação derivadas do [perfilamento comparativo](perfilamento_comparativo.md) e o dicionário completo das tabelas carregadas.

## 1. Visão geral do Esquema Estrela

O Data Warehouse foi implantado no SGBD PostgreSQL (executado localmente na máquina virtual do Google Colab) em dois schemas paralelos para permitir comparação entre paradigmas de integração: `dw_etl`, populado pelo pipeline ETL em Python (`pandas`), e `dw_elt`, populado pelo pipeline ELT por meio de área de *staging* (`stg_elt`) e scripts SQL executados no próprio banco.

A tabela fato `fato_notificacao` tem como grão uma notificação individual de caso suspeito ou confirmado de Chikungunya. Após a remoção das 405 duplicatas exatas identificadas nos arquivos brutos, a tabela consolida 946.004 registros referentes aos anos epidemiológicos de 2023, 2024 e 2025. O modelo adota cinco tabelas dimensão, sendo duas delas utilizadas em múltiplos papéis (*role-playing dimensions*): `dim_tempo` é referenciada tanto pela data de notificação (`sk_tempo_notificacao`, oriunda de `DT_NOTIFIC`) quanto pela data de início dos sintomas (`sk_tempo_sintomas`, oriunda de `DT_SIN_PRI`), enquanto `dim_localidade` atende ao município notificante (`sk_localidade_notificacao`, de `ID_MUNICIP`) e ao município de residência do paciente (`sk_localidade_residencia`, de `ID_MN_RESI`).

As duas dimensões principais estruturam-se em hierarquias analíticas bem definidas. Em `dim_tempo`, os níveis seguem a progressão Dia, Semana Epidemiológica (critério MMWR), Mês, Trimestre e Ano Civil. Em `dim_localidade`, a agregação geográfica percorre Município, Região de Saúde, Macrorregião de Saúde, Unidade da Federação (UF) e Grande Região. Os diagramas da modelagem e dos fluxos de carga encontram-se em [diagramas.drawio](diagramas.drawio).

## 2. Regras de transformação baseadas no perfilamento

Todas as nove regras abaixo foram implementadas de maneira equivalente no pipeline ETL (Python) e no pipeline ELT (SQL), assegurando que ambos produzam exatamente os mesmos conjuntos de linhas e métricas.

| # | Regra | Problema observado no perfilamento | Tratamento definido |
|---|---|---|---|
| 1 | Remoção de duplicatas exatas | 114 (2023) + 186 (2024) + 105 (2025) = 405 linhas idênticas | Deduplicar considerando todas as 122 colunas, reduzindo de 946.409 para 946.004 registros. |
| 2 | Padronização de datas | `DT_ENCERRA < DT_NOTIFIC` em 57 registros (11 em 2023, 26 em 2024, 20 em 2025); `DT_OBITO < DT_SIN_PRI` em 1 registro (2024); `DT_SIN_PRI > DT_NOTIFIC` = 0 | Converter `DT_NOTIFIC` e `DT_SIN_PRI` para `DATE`. Calcular `dias_sintoma_ate_notificacao = DT_NOTIFIC - DT_SIN_PRI`. Para `dias_notificacao_ate_encerramento`, atribuir `NULL` quando `DT_ENCERRA` for vazio ou anterior a `DT_NOTIFIC`. |
| 3 | Decodificação de `NU_IDADE_N` | Prefixo de unidade (`1`=hora, `2`=dia, `3`=mês, `4`=ano) e 9 registros com 2 dígitos sem prefixo (4 em 2023, 3 em 2024, 2 em 2025) | Códigos de 4 dígitos iniciados em `1`, `2` ou `3` são convertidos em `0` anos; códigos `4xxx` viram `xxx` anos; valores de 2 dígitos são lidos diretamente em anos. Derivar `faixa_etaria` oficial (`< 1 ano`, `1–4`, `5–9`, `10–14`, `15–19`, `20–39`, `40–59`, `60–69`, `70–79`, `80+`). |
| 4 | Harmonização do ES e códigos atípicos | ES usa `0` onde o SINAN usa vazio, `A920` em 2025, `ID_REGIONA` CIR (5 dígitos), `TP_SISTEMA` vazio ou `/` em 2023 e `CLASSI_FIN = 0` (385 em 2023, 48 em 2025); `CLINC_CHIK` tem `/` (3 em 2023) | Normalizar `ID_AGRAVO` (`A920` para `A92.0`); padronizar `TP_SISTEMA` vazio ou `/` para `'IGN'`; desconsiderar `ID_REGIONA` e derivar Região de Saúde e Macrorregião via `tb_municip`; mapear `0` e `/` para `"Ignorado/Branco"` quando não forem categorias válidas (exceto `CS_ESCOL_N`, em que `0 = Analfabeto`). |
| 5 | Normalização de `CS_ESCOL_N` | Valores com zero à esquerda (`05`, `07`) misturados com `5` e `7` | Remover zeros à esquerda antes de decodificar, mantendo `'0'` como `Analfabeto` e `'10'` como `Não se aplica`, conforme `Escolarnet.cnv`. |
| 6 | Tradução de domínios (`.cnv` e PDF) | `CLASSI_FIN` traz `13`, `5`, `8` e `0` (divergindo do PDF); `CRITERIO` traz `1`, `2`, `3` e `0` | Adotar `.cnv` como fonte oficial: `CLASSI_FIN` (`13`=Chikungunya, `5`=Descartado, `8`=Inconclusivo, `0`/vazio=`Ignorado/Branco`); `CRITERIO` (`1`=Laboratorial, `2`=Clínico-epidemiológico, `3`=Em investigação, `0`/vazio=`Ignorado/Branco`); `EVOLUCAO` (`1`=Cura, `2`=Óbito pelo agravo, `3`=Óbito outras causas, `4`=Óbito em investigação, `0`/`9`/vazio=`Ignorado/Branco`). |
| 7 | Preservação de Ignorado/Branco | Alto percentual de campos vazios e código `9` | Manter todos os registros com campos nulos ou código `9`, mapeando-os explicitamente para `"Ignorado/Branco"` nas dimensões. |
| 8 | Fontes externas e encoding | `CO_MUNICIP` (6 dígitos) vs. SIDRA (7 dígitos); SIDRA 6579 sem dados para 2023; `cnes_estabelecimentos_recorte_chik.csv` com byte `0xad` (`LATIN1`); vírgula decimal na Base Territorial; `"..."` no SIDRA; `666666`/`999999` sem UF | `CO_MUNICIP` liga o SINAN a `tb_municip`, e `CO_MUNICDV` liga às populações (SIDRA 4709 para `pop_2023`; SIDRA 6579 para `pop_2024` e `pop_2025`). Ler CNES em `LATIN1`, padronizar `ID_UNIDADE` e `CO_CNES` com `LPAD(..., 7, '0')` como `TEXT` e mapear ausentes para `sk_unidade = 0`. Atribuir `sg_uf = 'XX'` para `666666` e `999999`. |
| 9 | Chaves substitutas (*Surrogate Keys*) | Chaves naturais compostas ou textuais nas dimensões | Gerar chaves inteiras sequenciais em todas as dimensões para indexação e junção na tabela fato. |

## 3. Dicionário de dados do Data Warehouse

### 3.1 Tabela Fato: `fato_notificacao`

Reúne as chaves estrangeiras para as cinco dimensões, atributos degenerados de rastreabilidade (`ano_arquivo_origem`, `id_agravo_padronizado`, `tp_sistema`), indicadores binários de desfecho e métricas calculadas de intervalo e idade.

| Coluna | Tipo | Descrição | Domínio / Exemplo | Origem (Coluna e Ano) | Regra de Transformação |
|---|---|---|---|---|---|
| `sk_notificacao` | `BIGINT` (PK) | Chave substituta da notificação | `1` a `946004` | Gerada no DW (2023–2025) | Sequencial após deduplicação |
| `sk_tempo_notificacao` | `INT` (FK) | FK para `dim_tempo` (data da notificação) | FK válida em `dim_tempo` | `DT_NOTIFIC` (2023–2025) | Lookup em `dim_tempo.data_completa` |
| `sk_tempo_sintomas` | `INT` (FK) | FK para `dim_tempo` (início dos sintomas) | FK válida em `dim_tempo` | `DT_SIN_PRI` (2023–2025) | Lookup em `dim_tempo.data_completa` |
| `sk_localidade_notificacao` | `INT` (FK) | FK para `dim_localidade` (município notificante) | FK válida em `dim_localidade` | `ID_MUNICIP` (2023–2025) | Lookup por `co_municip_6` |
| `sk_localidade_residencia` | `INT` (FK) | FK para `dim_localidade` (município de residência) | FK válida em `dim_localidade` | `ID_MN_RESI` (2023–2025) | Lookup por `co_municip_6` |
| `sk_paciente_perfil` | `INT` (FK) | FK para `dim_paciente_perfil` | FK válida | `CS_SEXO`, `NU_IDADE_N`, `CS_RACA`, `CS_ESCOL_N`, `CS_GESTANT` | Lookup pela combinação padronizada |
| `sk_classificacao` | `INT` (FK) | FK para `dim_classificacao` | FK válida | `CLASSI_FIN`, `CRITERIO`, `EVOLUCAO`, `HOSPITALIZ`, `CLINC_CHIK` | Lookup pela combinação padronizada |
| `sk_unidade` | `INT` (FK) | FK para `dim_unidade` (estabelecimento CNES) | FK válida (`0` = não identificada) | `ID_UNIDADE` (2023–2025) | `LPAD(trim(ID_UNIDADE), 7, '0')` ou `0` |
| `ano_arquivo_origem` | `SMALLINT` | Ano epidemiológico do arquivo de origem | `2023`, `2024`, `2025` | Nome do arquivo (`CHIKBR23/24/25`) | Atribuído na extração |
| `id_agravo_padronizado` | `VARCHAR(10)` | Código CID-10 padronizado | `A92.0` | `ID_AGRAVO` (2023–2025) | Converte `A920` para `A92.0` |
| `tp_sistema` | `VARCHAR(10)` | Sistema de origem da notificação | `2` (SINAN), `0` (e-SUS VS), `IGN` | `TP_SISTEMA` (2023–2025) | Vazio ou `/` convertido em `IGN` |
| `qtd_notificacoes` | `SMALLINT` | Medida aditiva de contagem | `1` | Derivada | Constante `1` por notificação |
| `flag_confirmado` | `SMALLINT` | Indicador de caso confirmado | `0` ou `1` | `CLASSI_FIN` (2023–2025) | `1` se `CLASSI_FIN = '13'`, senão `0` |
| `flag_obito_agravo` | `SMALLINT` | Indicador de óbito por Chikungunya | `0` ou `1` | `EVOLUCAO` (2023–2025) | `1` se `EVOLUCAO = '2'`, senão `0` |
| `flag_hospitalizado` | `SMALLINT` | Indicador de hospitalização | `0` ou `1` | `HOSPITALIZ` (2023–2025) | `1` se `HOSPITALIZ = '1'`, senão `0` |
| `dias_sintoma_ate_notificacao` | `INT` | Intervalo entre sintomas e notificação | `>= 0` | `DT_NOTIFIC`, `DT_SIN_PRI` | `DT_NOTIFIC - DT_SIN_PRI` |
| `dias_notificacao_ate_encerramento` | `INT` | Intervalo entre notificação e encerramento | `>= 0` ou `NULL` | `DT_ENCERRA`, `DT_NOTIFIC` | `NULL` se vazio ou `< DT_NOTIFIC` |
| `idade_anos` | `SMALLINT` | Idade do paciente em anos completos | `0` a `120` | `NU_IDADE_N` (2023–2025) | Decodificação prefixo `1/2/3/4` e 2 dígitos |

### 3.2 Dimensão: `dim_tempo`

Contém o conjunto distinto de datas encontradas em `DT_NOTIFIC` e `DT_SIN_PRI`, enriquecido com atributos de calendário civil e cálculo da semana epidemiológica no padrão MMWR (semana de domingo a sábado, em que a semana 1 é a primeira com ao menos quatro dias no novo ano).

| Coluna | Tipo | Descrição | Domínio / Exemplo | Origem | Regra de Transformação |
|---|---|---|---|---|---|
| `sk_tempo` | `INT` (PK) | Chave substituta temporal | `1` a `N` | Gerada das datas únicas | Sequencial por `data_completa` |
| `data_completa` | `DATE` | Data no calendário civil | `2023-01-01` a `2026-07-07` | `DT_NOTIFIC`, `DT_SIN_PRI` | União distinta das datas convertidas |
| `dia` | `SMALLINT` | Dia do mês | `1` a `31` | Derivada | `EXTRACT(DAY)` |
| `mes` | `SMALLINT` | Mês do ano | `1` a `12` | Derivada | `EXTRACT(MONTH)` |
| `nome_mes` | `VARCHAR(15)` | Nome do mês em português | `Janeiro` a `Dezembro` | Derivada | Mapeamento de 1 a 12 |
| `trimestre` | `SMALLINT` | Trimestre civil | `1` a `4` | Derivada | `EXTRACT(QUARTER)` |
| `ano_civil` | `SMALLINT` | Ano do calendário civil | `2023` a `2026` | Derivada | `EXTRACT(YEAR)` |
| `semana_epidemiologica` | `SMALLINT` | Número da semana epidemiológica | `1` a `53` | Calculada (MMWR) | Domingo a sábado; SE 1 >= 4 dias no ano |
| `ano_epidemiologico` | `SMALLINT` | Ano epidemiológico da semana | `2023` a `2026` | Calculada (MMWR) | Ano referente à SE MMWR |
| `semana_epi_codigo` | `VARCHAR(6)` | Código ano+semana | `202301` a `202553` | Calculada | `ano_epi * 100 + se` (2 dígitos) |

### 3.3 Dimensão: `dim_localidade`

Integra os municípios brasileiros da Base Territorial do DATASUS (incluindo Regiões e Macrorregiões de Saúde) às populações oficiais do IBGE e coordenadas geográficas. O membro `sk_localidade = 0` é reservado aos 6 casos em que `ID_MN_RESI` veio vazio.

| Coluna | Tipo | Descrição | Domínio / Exemplo | Origem | Regra de Transformação |
|---|---|---|---|---|---|
| `sk_localidade` | `INT` (PK) | Chave substituta geográfica | `0` (não informado), `1` a `5725` | Gerada no DW | `0` reservado para `ID_MN_RESI` vazio (6 casos) |
| `co_municip_6` | `VARCHAR(6)` | Código IBGE/DATASUS (6 dígitos) | `261160` | `tb_municip.CO_MUNICIP` | Texto de 6 caracteres |
| `co_municip_7` | `VARCHAR(7)` | Código IBGE com DV (7 dígitos) | `2611606` | `tb_municip.CO_MUNICDV` | Texto de 7 caracteres |
| `nome_municipio` | `VARCHAR(100)` | Nome do município ou RA/Ignorado | `Recife` | `tb_municip.DS_NOMEPAD` | Trim |
| `co_regsaud` | `VARCHAR(20)` | Código da Região de Saúde (CIR) | `26001` ou `Não informado` | `rl_municip_regsaud` | Ordenado e deduplicado |
| `nome_regsaud` | `VARCHAR(120)` | Nome da Região de Saúde | `1ª Região - Recife` | `tb_regsaud.DS_NOMEPAD` | Vazio ou ausente mapeado para `Não informado` |
| `co_macsaud` | `VARCHAR(20)` | Código da Macrorregião de Saúde | `2601` ou `Não informado` | `rl_regsaud_macsaud` | Ordenado e deduplicado |
| `nome_macsaud` | `VARCHAR(120)` | Nome da Macrorregião de Saúde | `Metropolitana` | `tb_macsaud.DS_NOMEPAD` | Vazio ou ausente mapeado para `Não informado` |
| `sg_uf` | `VARCHAR(2)` | Sigla da UF | `PE`, `SP`, `ES`, `XX` | `tb_uf.CO_SIGLA` | `XX` para `666666` e `999999` |
| `nome_uf` | `VARCHAR(50)` | Nome da UF | `Pernambuco` | `tb_uf.DS_NOMEPAD` | `Estrangeiro/Inválido` para `XX` |
| `nome_regiao` | `VARCHAR(30)` | Grande Região do Brasil | `Nordeste`, `Sudeste` | `tb_regiao.NO_REGIAO` | `Estrangeiro/Inválido` para `XX` |
| `co_status` | `VARCHAR(10)` | Status territorial DATASUS | `ATIVO`, `REG ADM`, `IGNR` | `tb_municip.CO_STATUS` | Preserva membros especiais |
| `pop_2023` | `INT` | População base de 2023 (Censo 2022) | Inteiro ou `NULL` | `sidra_4709_censo_2022.json` | Join por `D1C = co_municip_7` |
| `pop_2024` | `INT` | População estimada 2024 | Inteiro ou `NULL` | `sidra_6579` (`D3C='2024'`) | `"..."` convertido para `NULL` |
| `pop_2025` | `INT` | População estimada 2025 | Inteiro ou `NULL` | `sidra_6579` (`D3C='2025'`) | `"..."` convertido para `NULL` |
| `latitude` | `NUMERIC(10,6)` | Latitude do município | `-8.047562` | `tb_municip.NU_LATITUD` | `replace(',', '.')::numeric` |
| `longitude` | `NUMERIC(10,6)` | Longitude do município | `-34.876964` | `tb_municip.NU_LONGIT` | `replace(',', '.')::numeric` |

### 3.4 Dimensão: `dim_paciente_perfil`

Armazena as combinações distintas dos atributos sociodemográficos padronizados do paciente, mantendo pares de código e descrição decodificados a partir das tabelas `.cnv`.

| Coluna | Tipo | Descrição | Domínio / Exemplo | Origem | Regra de Transformação |
|---|---|---|---|---|---|
| `sk_paciente_perfil` | `INT` (PK) | Chave substituta do perfil | `1` a `N` | Gerada no DW | Sequencial pela combinação distinta |
| `sexo_cod` / `sexo_desc` | `VARCHAR(3)` / `(20)` | Sexo | `F`, `M`, `I` | `CS_SEXO` / `Sexo.cnv` | Vazio mapeado para `I` (`Ignorado/Branco`) |
| `faixa_etaria` / `ordem_faixa_etaria` | `VARCHAR(20)` / `SMALLINT` | Faixa etária | `< 1 ano` a `80+ anos` | `NU_IDADE_N` | Derivada de `idade_anos` |
| `raca_cod` / `raca_desc` | `VARCHAR(3)` / `(30)` | Raça/cor | `1`..`5`, `9` | `CS_RACA` / `Raca.cnv` | Vazio ou `0` mapeado para `9` |
| `escolaridade_cod` / `escolaridade_desc` | `VARCHAR(3)` / `(50)` | Escolaridade | `0`..`8`, `10`, `9` | `CS_ESCOL_N` / `Escolarnet.cnv` | `lstrip('0')` (mantendo `'0'`); vazio para `9` |
| `gestante_cod` / `gestante_desc` | `VARCHAR(3)` / `(40)` | Idade gestacional | `1`..`6`, `9` | `CS_GESTANT` / `gestante.cnv` | Vazio ou `0` mapeado para `9` |

### 3.5 Dimensão: `dim_classificacao`

Agrupa as combinações únicas de desfecho clínico, critério de confirmação, evolução, internação e forma clínica do agravo.

| Coluna | Tipo | Descrição | Domínio / Exemplo | Origem | Regra de Transformação |
|---|---|---|---|---|---|
| `sk_classificacao` | `INT` (PK) | Chave substituta de classificação | `1` a `N` | Gerada no DW | Sequencial pela combinação distinta |
| `classi_fin_cod` / `classi_fin_desc` | `VARCHAR(3)` / `(30)` | Classificação final | `13`, `5`, `8`, `9` | `CLASSI_FIN` / `Classchik.cnv` | Vazio ou `0` mapeado para `9` |
| `criterio_cod` / `criterio_desc` | `VARCHAR(3)` / `(35)` | Critério de confirmação | `1`, `2`, `3`, `9` | `CRITERIO` / `Confdesc.cnv` | Vazio ou `0` mapeado para `9` |
| `evolucao_cod` / `evolucao_desc` | `VARCHAR(3)` / `(35)` | Evolução do caso | `1`..`4`, `9` | `EVOLUCAO` / `evochik.cnv` | Vazio ou `0` mapeado para `9` |
| `hospitaliz_cod` / `hospitaliz_desc` | `VARCHAR(3)` / `(25)` | Hospitalização | `1`, `2`, `9` | `HOSPITALIZ` / `Sim_nao.cnv` | Vazio ou `0` mapeado para `9` |
| `clinc_chik_cod` / `clinc_chik_desc` | `VARCHAR(3)` / `(25)` | Forma clínica | `1`, `2`, `9` | `CLINC_CHIK` / `Clinic_chi.cnv` | Vazio, `0` ou `/` mapeado para `9` |

### 3.6 Dimensão: `dim_unidade`

Reúne os estabelecimentos notificantes oriundos do recorte do CNES, decodificados com `TipoUnidade.cnv`. O identificador `sk_unidade = 0` atua como membro padrão para notificações sem CNES ou cujo código não consta no recorte.

| Coluna | Tipo | Descrição | Domínio / Exemplo | Origem | Regra de Transformação |
|---|---|---|---|---|---|
| `sk_unidade` | `INT` (PK) | Chave substituta da unidade | `0` (não identificada), `1` a `26845` | Gerada no DW | `0` reservado para não identificadas |
| `co_cnes` | `VARCHAR(7)` | Código CNES padronizado | `0000000` a `9999999` | `cnes_estabelecimentos_recorte_chik.csv` | `LATIN1`, `LPAD(trim(CO_CNES), 7, '0')` |
| `nome_fantasia` | `VARCHAR(150)` | Nome fantasia do estabelecimento | Texto ou `Unidade não identificada` | `NO_FANTASIA` | Trim; `sk=0` recebe `Unidade não identificada` |
| `tp_unidade_cod` / `tp_unidade_desc` | `VARCHAR(5)` / `(100)` | Tipo de estabelecimento | `01`..`85` | `TP_UNIDADE` / `TipoUnidade.cnv` | Mapeamento oficial |
| `co_municipio_gestor` | `VARCHAR(6)` | Município gestor da unidade | `261160` | `CO_IBGE` | 6 dígitos (`LPAD`) |
| `esfera_adm` | `VARCHAR(30)` | Tipo de gestão | `E`, `M`, `D`, `S` | `TP_GESTAO` | Padronizado |
