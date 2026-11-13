# Dados do projeto

Esta pasta contém **todas as fontes de dados** usadas no Data Warehouse de chikungunya, **brutas, do jeito que foram obtidas**. Nenhuma limpeza, conversão ou padronização foi feita aqui. Essas transformações pertencem aos pipelines ETL e ELT e precisam aparecer neles como evidência do processo de integração.

- **Data de obtenção:** 11/11/2026 (2023: 12/11/2026)
- **Banco de destino:** PostgreSQL

```
dados/
├── README.md                     ← este arquivo
├── sinan_chikungunya/            ← FONTES PRINCIPAIS: as 3 bases a integrar (2023, 2024, 2025)
│   ├── CHIKBR23.csv.zip
│   ├── CHIKBR24.csv.zip
│   ├── CHIKBR25.csv.zip
│   └── dic_dados_chikungunya.pdf
└── externos/                     ← FONTES DE ENRIQUECIMENTO das dimensões (ver externos/README.md)
    ├── base_territorial_datasus/
    ├── populacao_ibge/
    ├── cnes/
    └── sinan_auxiliar/
```

## 1. `sinan_chikungunya/`: fontes principais

São as notificações de **Febre de Chikungunya** do SINAN (Sistema de Informação de Agravos de Notificação), do Ministério da Saúde, publicadas no OpenDataSUS. Cada arquivo corresponde a um ano e é uma das **três fontes heterogêneas** que o projeto integra.

| Arquivo | O que é | Linhas | Tamanho (CSV) | MD5 do CSV |
|---|---|---|---|---|
| `CHIKBR23.csv.zip` | Notificações com início de sintomas no **ano epidemiológico de 2023** (01/01/2023 a 30/12/2023) | 266.442 | 74 MB | `46d8674f22ef555f6f24a52a75c4e0f4` |
| `CHIKBR24.csv.zip` | Notificações do **ano epidemiológico de 2024** (31/12/2023 a 04/01/2025) | 426.214 | 120 MB | `19b805c4ebd28f6c9b0437aa11f3c9b0` |
| `CHIKBR25.csv.zip` | Notificações do **ano epidemiológico de 2025** (29/12/2024 a 03/01/2026) | 253.753 | 70 MB | `6d290c223719b97c8e6612317242ea75` |
| `dic_dados_chikungunya.pdf` | Dicionário de dados oficial (Sinan Online), com os 121 campos: nome, tipo, categorias e regras de preenchimento | n/a | 0,5 MB | `1b24b5c98b15a47fa514b3b98c95eff4` |

- **Origem:** <https://dadosabertos.saude.gov.br/dataset/arboviroses-febre-de-chikungunya>
- **Download direto:** `https://s3.sa-east-1.amazonaws.com/ckan.saude.gov.br/SINAN/Chikungunya/csv/CHIKBR{23,24,25}.csv.zip`

### Por que zips e não CSVs?

O `CHIKBR24.csv` tem 120 MB e passa do limite de 100 MB por arquivo do GitHub. Os zips são os **arquivos oficiais do OpenDataSUS**, sem nenhuma alteração, e o MD5 do CSV dentro deles bate com a tabela acima. Os CSVs descompactados ficam fora do git (`.gitignore`). Para obtê-los localmente:

```bash
cd dados/sinan_chikungunya && unzip -o 'CHIKBR*.csv.zip'
```

### Formato dos CSVs

- **Delimitador** `,`, **encoding** ASCII/UTF-8, com cabeçalho.
- **122 colunas idênticas nos três anos**: mesmos nomes, na mesma ordem.
- Uma linha = **uma notificação individual** (`TP_NOT = 2` em 100% dos registros). Não existe identificador de paciente.
- Datas no formato `AAAA-MM-DD`. Os demais campos são códigos, decodificados pelas tabelas de `externos/sinan_auxiliar/`.

### O que é preciso saber antes de usar

1. **O arquivo é particionado pelo ano epidemiológico dos primeiros sintomas** (`SEM_PRI`), não pelo ano de notificação. O arquivo de 2023 contém notificações feitas até maio de 2024, e o de 2024, até abril de 2025. Por isso os três arquivos **não se sobrepõem**.
2. **O dicionário PDF diverge dos dados em `CLASSI_FIN`.** O PDF diz 1/2/8, mas os dados trazem `13 = Chikungunya` e `5 = Descartado`, conforme a tabela oficial `externos/sinan_auxiliar/cnv/Classchik.cnv`. Onde os dois divergem, vale o `.cnv`.
3. **`NU_LOTE_I` existe no CSV mas não está no dicionário** (122 colunas contra 121 campos documentados).
4. **Cerca de 40 colunas são só de dengue** (`ALRM_*`, `GRAV_*`, `MANI_HEMOR` até `COMPLICA`, `SOROTIPO`, NS1) e estão vazias ou zeradas.
5. **O Espírito Santo vem de outro sistema** (e-SUS VS): preenche "não se aplica" com `0` em vez de vazio e usa código CIR em `ID_REGIONA` nos três anos. A identificação muda de um ano para o outro: em 2023 o `TP_SISTEMA` vem **vazio** (e `/` em 6 registros), em 2024 e 2025 vem `0`. Em 2025 também usa `A920` em vez de `A92.0`. Os 385 registros com `CLASSI_FIN = 0` em 2023 são todos do ES.
6. **A sorologia IgM some em 2025:** `RES_CHIKS1`, `RES_CHIKS2` e `RESUL_PRNT` estão vazios em todas as UFs, menos no ES. Isso é da publicação oficial, e não erro de download (conferido com a versão publicada em 11/11/2026).
7. **2023 e 2024 estão fechados, mas 2025 ainda recebe encerramentos.** Comparações de classificação final e evolução entre anos devem levar isso em conta.
8. **Duplicatas exatas:** 114 (2023), 186 (2024) e 105 (2025), além de 1.077 registros marcados com `NDUPLIC_N = 1` (67, 675 e 335).
9. **Idade codificada:** em `NU_IDADE_N`, o 1º dígito é a unidade (1 = hora, 2 = dia, 3 = mês, 4 = ano). Por exemplo, `4044` significa 44 anos.

### Reprodutibilidade

O OpenDataSUS **republica os arquivos diariamente**, e 2025 ainda vai mudar com novos encerramentos. Os zips desta pasta congelam o snapshot de 11/11/2026 (2023: 12/11/2026). Os notebooks devem ler **daqui**, e não do link oficial, para que os resultados sejam reproduzíveis.

## 2. `externos/`: fontes de enriquecimento

Estas fontes não são integradas como "anos". Elas alimentam os **atributos e hierarquias das dimensões**, e o detalhamento completo está em [`externos/README.md`](externos/README.md).

| Pasta | Fonte | Uso no DW |
|---|---|---|
| `base_territorial_datasus/` | DATASUS, Base Territorial jun/2026 | Dimensão Localidade: Município → Região de Saúde → Macrorregião de Saúde → UF → Região |
| `populacao_ibge/` | IBGE, SIDRA 6579 (estimativas 2024 e 2025) e SIDRA 4709 (Censo 2022, base para 2023) | Taxa de incidência por 100 mil habitantes |
| `cnes/` | OpenDataSUS, CNES (recorte com as unidades presentes nas notificações) | Dimensão Unidade Notificadora |
| `sinan_auxiliar/` | DATASUS, tabelas TabWin do Sinan (`.cnv` e `.DBF`) | Decodificação oficial dos domínios dos campos |
