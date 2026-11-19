# Pipeline de Dados: Febre de Chikungunya no Brasil (SINAN 2023–2025)

> Projeto de Integração de Dados — Banco de Dados (CIn/UFPE, 2026.2) — Equipe 9

Integração das notificações de febre de chikungunya de **2023, 2024 e 2025** num **Data Warehouse em esquema estrela** (PostgreSQL),
construído por dois caminhos para comparação:

- **ETL:** os dados são extraídos, limpos e modelados em Python/Pandas e só depois carregados no banco (schema `dw_etl`).
- **ELT:** os arquivos são carregados brutos numa área de *staging* (`stg_elt`) e toda a transformação acontece dentro do PostgreSQL, com scripts SQL versionados em [`sql/elt/`](sql/elt/) (schema `dw_elt`).

Os dois pipelines aplicam as mesmas regras de limpeza e geram o mesmo esquema estrela. Assim dá para comparar os resultados.

## Fonte dos dados

- **Base:** [Arboviroses — Febre de Chikungunya (Ministério da Saúde / SINAN)](https://dadosabertos.saude.gov.br/dataset/arboviroses-febre-de-chikungunya)
- **Arquivos:** `CHIKBR23.csv`, `CHIKBR24.csv`, `CHIKBR25.csv` (946.409 notificações brutas, 122 colunas), versionados como os `.csv.zip` oficiais em [`dados/sinan_chikungunya/`](dados/sinan_chikungunya/)
- **Fontes externas de enriquecimento** (base territorial do DATASUS, população do IBGE/SIDRA, CNES e tabelas auxiliares do Sinan): [`dados/externos/`](dados/externos/)
- **Dicionário de dados oficial:** [`docs/dic_dados_chikungunya.pdf`](docs/dic_dados_chikungunya.pdf)
- **Procedência, formato e armadilhas de cada fonte:** [`dados/README.md`](dados/README.md)

## Documentação

| Documento | Conteúdo |
|---|---|
| [`docs/relatorio.md`](docs/relatorio.md) | Relatório do projeto: justificativa, integração, transformações, comparação ETL × ELT e análises |
| [`docs/modelagem_e_dicionario.md`](docs/modelagem_e_dicionario.md) | Esquema estrela, regras de transformação e dicionário de dados do DW |
| [`docs/perfilamento_comparativo.md`](docs/perfilamento_comparativo.md) | Perfilamento das três bases e das fontes externas, com as diferenças entre os anos |
| [`docs/diagramas.drawio`](docs/diagramas.drawio) | Diagramas do fluxo de integração (ETL × ELT) e do esquema estrela (abrir no [draw.io](https://app.diagrams.net/)) |
| [`docs/Projeto de integração - 2026.2.docx`](docs/) | Enunciado do projeto |

## Estrutura do repositório

```
.
├── dados/
│   ├── sinan_chikungunya/   # Bases de 2023, 2024 e 2025 (zips oficiais do OpenDataSUS)
│   └── externos/            # Fontes de enriquecimento das dimensões
├── docs/                    # Relatório, modelagem, perfilamento, diagramas e enunciado
├── notebooks/
│   ├── 00_exploracao.ipynb          # Análise exploratória inicial
│   ├── 00_perfilamento.py           # Script que gera docs/perfilamento_comparativo.md
│   ├── 01_configuracao_banco.ipynb  # Configuração e teste do PostgreSQL (Colab ou local) e backup
│   ├── etl/
│   │   └── etl.ipynb                # Pipeline ETL (Pandas → dw_etl)
│   └── elt/
│       └── 02_pipeline_elt_chikungunya.ipynb  # Pipeline ELT (staging → SQL → dw_elt) e análises
├── sql/
│   ├── elt/                 # Scripts de transformação do ELT, executados pelo notebook ELT
│   │   ├── 01_criar_schemas_e_staging.sql
│   │   ├── 02_transformar_dimensoes.sql
│   │   └── 03_transformar_fato.sql
│   └── analises/            # Consultas das análises e auditoria ETL × ELT
│       ├── 00_auditoria_etl_vs_elt.sql
│       ├── 01_sazonalidade_semanas_epi.sql
│       ├── 02_incidencia_geografica_uf_regiao.sql
│       └── 03_perfil_gravidade_criterio.sql
├── .env.example             # Modelo de conexão para quem roda localmente
├── requirements.txt         # Bibliotecas Python do projeto
└── README.md
```

## Banco de dados

Usamos o **PostgreSQL**, no banco `chikungunya_dw`, separado nestes schemas:

| Schema | O que guarda | Quem cria |
|---|---|---|
| `dw_etl` | Esquema estrela gerado pelo ETL | `notebooks/etl/etl.ipynb` |
| `stg_elt` | Dados brutos do SINAN e das fontes externas, sem tratamento (colunas `TEXT` e `JSONB`) | `sql/elt/01_criar_schemas_e_staging.sql` |
| `dw_elt` | Esquema estrela gerado pelo ELT | `sql/elt/02_transformar_dimensoes.sql` e `03_transformar_fato.sql` |

### Esquema estrela

Grão: **uma notificação**. Depois de remover 405 linhas duplicadas, a fato tem 946.004 registros.

| Tabela | Tipo | Conteúdo |
|---|---|---|
| `fato_notificacao` | Fato | Chaves das dimensões, indicadores (confirmado, hospitalizado, óbito) e intervalos em dias |
| `dim_tempo` | Dimensão (2 papéis) | Data da notificação e do início dos sintomas: dia, semana epidemiológica, mês, trimestre, ano |
| `dim_localidade` | Dimensão (2 papéis) | Município notificante e de residência: município, região de saúde, macrorregião, UF, região e população |
| `dim_paciente_perfil` | Dimensão | Sexo, faixa etária, raça/cor, escolaridade e gestação |
| `dim_classificacao` | Dimensão | Classificação final, critério de confirmação, forma clínica, hospitalização e evolução |
| `dim_unidade` | Dimensão | Estabelecimento notificante (CNES), tipo de unidade e esfera administrativa |

Os atributos de cada tabela estão em [`docs/modelagem_e_dicionario.md`](docs/modelagem_e_dicionario.md).

O banco em si **não fica no GitHub**. O repositório guarda só o código que cria e preenche o banco.

## Como obter os dados

Não é preciso baixar nada: os dados já vêm no repositório, em `dados/`.

- As bases do SINAN ficam em `dados/sinan_chikungunya/` como os **`.csv.zip` oficiais** do OpenDataSUS, porque o `CHIKBR24.csv` (~120 MB) passa do limite de 100 MB por arquivo do GitHub. Os notebooks de ETL e ELT descompactam os zips na primeira execução.
- Os zips congelam o snapshot de 11/11/2026 (2023: 12/11/2026). O OpenDataSUS republica os arquivos todo dia, então ler daqui garante resultados reproduzíveis.

## Como executar

Os notebooks foram feitos para o **Google Colab**, mas também rodam **localmente**. A primeira célula de cada um
descobre onde está rodando e prepara o ambiente.

| | Google Colab | Local |
|---|---|---|
| Repositório e dados | Clonados automaticamente em `/content` | Pasta do projeto |
| PostgreSQL | Instalado na sessão, com usuário `dw_user` e banco `chikungunya_dw` (apagado quando a sessão fecha) | O que está instalado na sua máquina |
| Conexão | Definida no próprio notebook | ETL: arquivo `.env`. ELT: `dw_user`/`dw_pass` fixos no notebook |

### Ordem de execução

1. `notebooks/etl/etl.ipynb`: extrai, transforma em Pandas e carrega o esquema estrela em `dw_etl`.
2. `notebooks/elt/02_pipeline_elt_chikungunya.ipynb`: carrega os dados brutos em `stg_elt`, executa os scripts de `sql/elt/` e gera `dw_elt`. No fim roda as três análises de `sql/analises/` e gera os gráficos.
3. `sql/analises/00_auditoria_etl_vs_elt.sql` (opcional): confere se `dw_etl` e `dw_elt` têm as mesmas contagens e somas. Precisa dos dois pipelines já executados no mesmo banco.

### Google Colab

1. Abra o notebook pelo Colab (`Arquivo › Abrir notebook › GitHub`) e cole o endereço do repositório.
2. Execute tudo (`Ambiente de execução › Executar tudo`).

Para rodar os dois pipelines no mesmo banco (necessário para a auditoria), use a mesma sessão do Colab.

### Localmente

Pré-requisitos: **Python 3.10 ou superior** e **PostgreSQL** instalado e rodando.

1. Copie o `.env.example` para `.env` e preencha com o usuário e a senha do seu PostgreSQL.
2. Crie um ambiente virtual e instale as bibliotecas:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```
3. Rode o `notebooks/01_configuracao_banco.ipynb` uma vez para criar o banco `chikungunya_dw`.
4. O notebook ELT conecta com o usuário `dw_user` e a senha `dw_pass`. Crie esse usuário no seu PostgreSQL ou ajuste a variável `DB_URI` na primeira célula.
5. Abra os notebooks a partir da raiz do projeto (o ELT usa caminhos relativos, como `dados/` e `sql/`):
   ```bash
   jupyter notebook
   ```

### Backup do banco

No Colab o banco é apagado quando a sessão fecha. Para não rodar o pipeline inteiro de novo, dá para salvar um backup
com `pg_dump` e restaurar com `pg_restore`. O exemplo está na seção 3 do `01_configuracao_banco.ipynb`.

## Análises

As consultas ficam em [`sql/analises/`](sql/analises/) e usam o esquema estrela `dw_elt`:

1. **Sazonalidade:** notificações, confirmados e taxa de confirmação por semana epidemiológica de início dos sintomas.
2. **Incidência geográfica:** casos confirmados por 100 mil habitantes, por UF e Grande Região, com a população de cada ano.
3. **Perfil e gravidade:** hospitalização e letalidade por faixa etária e sexo, e participação de cada critério de confirmação por ano.

Os resultados e gráficos estão no notebook ELT e no [relatório](docs/relatorio.md).

## Tecnologias

| Tecnologia | Uso |
|---|---|
| Python 3 + Pandas | Exploração, perfilamento e pipeline ETL |
| Google Colab | Ambiente de execução dos notebooks |
| PostgreSQL | Data Warehouse (staging e esquemas estrela) |
| SQL | Transformações do pipeline ELT dentro do banco e consultas analíticas |
| SQLAlchemy + psycopg2 | Conexão dos notebooks com o PostgreSQL e carga via `COPY` |
| Matplotlib | Gráficos das análises |
| draw.io | Diagramas do fluxo de integração e do esquema estrela |
| Git/GitHub | Versionamento e registro das contribuições |
