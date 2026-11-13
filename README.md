# Pipeline de Dados: Febre de Chikungunya no Brasil (SINAN 2023–2025)

> Projeto de Integração de Dados — Banco de Dados (CIn/UFPE, 2026.2) — Equipe 9

Integração das notificações de febre de chikungunya de **2023, 2024 e 2025** num **Data Warehouse em esquema estrela** (PostgreSQL),
construído por dois caminhos para comparação: **ETL** (transformação em Python/Pandas antes da carga) e **ELT** (carga bruta e transformação em SQL dentro do banco, com dbt).

## Fonte dos dados

- **Base:** [Arboviroses — Febre de Chikungunya (Ministério da Saúde / SINAN)](https://dadosabertos.saude.gov.br/dataset/arboviroses-febre-de-chikungunya)
- **Arquivos:** `CHIKBR23.csv`, `CHIKBR24.csv`, `CHIKBR25.csv` (~946 mil notificações, 122 colunas), versionados como os `.csv.zip` oficiais em [`dados/sinan_chikungunya/`](dados/sinan_chikungunya/)
- **Fontes externas de enriquecimento** (base territorial do DATASUS, população do IBGE, CNES e tabelas auxiliares do Sinan): [`dados/externos/`](dados/externos/)
- **Dicionário de dados:** [`docs/dic_dados_chikungunya.pdf`](docs/dic_dados_chikungunya.pdf)
- **Procedência, formato e armadilhas de cada fonte:** [`dados/README.md`](dados/README.md)

## Estrutura do repositório

```
.
├── dados/
│   ├── sinan_chikungunya/ # Bases de 2023, 2024 e 2025 (zips oficiais do OpenDataSUS)
│   └── externos/          # Fontes de enriquecimento das dimensões
├── docs/                  # Enunciado, dicionário de dados, relatório e diagramas
├── notebooks/
│   ├── 00_exploracao.ipynb          # Análise exploratória e definição das regras de limpeza
│   └── 01_configuracao_banco.ipynb  # Configuração do PostgreSQL e do dbt (Colab ou local)
├── dbt_chikungunya/       # Projeto dbt do pipeline ELT (transformações SQL dentro do banco)
│   ├── models/staging/    # Limpeza e unificação dos 3 anos
│   ├── models/marts/      # Dimensões e fato do esquema estrela
│   └── profiles.yml       # Conexão do dbt com o banco (sem senha no arquivo)
├── analysis/              # Consultas SQL das análises e insights
├── .env.example           # Modelo de conexão para quem roda localmente
├── requirements.txt       # Bibliotecas Python do projeto
└── README.md
```

## Banco de dados

Usamos o **PostgreSQL**, no banco `chikungunya_dw`, separado nestes schemas:

| Schema | O que guarda | Quem cria |
|---|---|---|
| `raw` | Dados brutos dos CSVs, sem tratamento (ELT) | notebook ELT |
| `etl_dw` | Esquema estrela gerado pelo ETL (Pandas) | notebook ETL |
| `elt_staging` | Limpeza e unificação dos três anos (ELT) | dbt |
| `elt_dw` | Esquema estrela gerado pelo ELT | dbt |

O banco em si **não fica no GitHub**. O repositório guarda só o código que cria e preenche o banco.

## Como obter os dados

Não é preciso baixar nada: os dados já vêm no repositório, em `dados/`.

- As bases do SINAN ficam em `dados/sinan_chikungunya/` como os **`.csv.zip` oficiais** do OpenDataSUS, porque o `CHIKBR24.csv` (~120 MB) passa do limite de 100 MB por arquivo do GitHub. O pandas lê o zip direto: `pd.read_csv('dados/sinan_chikungunya/CHIKBR23.csv.zip')`.
- Os zips congelam o snapshot de 11/11/2026 (2023: 12/11/2026). O OpenDataSUS republica os arquivos todo dia, então ler daqui garante resultados reproduzíveis.

## Como executar

O projeto roda tanto no **Google Colab** quanto **localmente**. A primeira seção de cada notebook
(copiada do `01_configuracao_banco.ipynb`) descobre onde está rodando e configura o banco:

| | Google Colab | Local |
|---|---|---|
| PostgreSQL | Instalado automaticamente na sessão (é apagado quando a sessão fecha) | O que está instalado na sua máquina |
| Dados de conexão | Definidos no próprio notebook | Lidos do arquivo `.env` |
| Dados | Pasta `dados/` do repositório clonado | Pasta `dados/` |
| Backup do banco | Google Drive | Pasta do projeto |

O dbt usa a mesma conexão do notebook: o `dbt_chikungunya/profiles.yml` lê as variáveis `PG_*` definidas no começo do notebook.

### Google Colab

1. Abra o notebook pelo Colab (`Arquivo › Abrir notebook › GitHub`).
2. Execute tudo (`Ambiente de execução › Executar tudo`) e autorize o acesso ao Drive quando pedir (ele guarda só o backup do banco).

### Localmente

Pré-requisitos: **Python 3.10 a 3.12** (o dbt ainda não funciona no 3.13+) e **PostgreSQL** instalado e rodando.

1. Copie o `.env.example` para `.env` e preencha com o usuário e a senha do seu PostgreSQL.
   O banco `chikungunya_dw` é criado automaticamente pelo notebook.
2. Crie um ambiente virtual e instale as bibliotecas:
   ```bash
   python3.12 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```
3. Abra os notebooks (com o ambiente virtual ativado):
   ```bash
   jupyter notebook notebooks/
   ```

### Backup do banco

No Colab o banco é apagado quando a sessão fecha. Para não rodar o pipeline inteiro de novo, salvamos um backup
com `pg_dump` no Google Drive e restauramos com `pg_restore`. O exemplo está na seção 3 do `01_configuracao_banco.ipynb`.

## Tecnologias

| Tecnologia | Uso |
|---|---|
| Python 3 + Pandas | Exploração e pipeline ETL |
| Google Colab | Ambiente de execução dos notebooks |
| PostgreSQL | Data Warehouse final |
| dbt | Transformações SQL do pipeline ELT |
| Git/GitHub | Versionamento e registro das contribuições |
