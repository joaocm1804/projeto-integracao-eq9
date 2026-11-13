# Dados externos (fontes de enriquecimento)

Esta pasta reúne as fontes **externas** ao SINAN que usamos para enriquecer as dimensões do Data Warehouse de chikungunya. Os arquivos estão **brutos, do jeito que vieram da fonte**. Nenhuma limpeza ou conversão foi feita aqui, porque essas transformações pertencem aos pipelines ETL e ELT e precisam aparecer neles como evidência.

A única exceção é o CNES, que foi **recortado por linhas**: o arquivo original tem 185 MB e passa do limite de 100 MB do GitHub (detalhes na seção 3).

- **Data de obtenção:** 11/11/2026 (população do IBGE e recorte do CNES refeitos em 12/11/2026, com a troca de 2026 por 2023)
- **Banco de destino:** PostgreSQL

## 1. Estrutura

```
dados/externos/
├── base_territorial_datasus/   → dimensão Localidade (município → região de saúde → macro → UF → região)
├── populacao_ibge/             → população para taxa de incidência por 100 mil hab.
├── cnes/                       → dimensão Unidade Notificadora
└── sinan_auxiliar/
    ├── cnv/                    → domínios oficiais dos códigos do SINAN (TabWin)
    └── dbf/                    → regionais de vigilância e ocupações do Sinan
```

## 2. Fontes, para que servem e como se ligam ao SINAN

| Pasta | Origem | Uso no DW | Chave de junção com o SINAN | Cobertura medida nos 946 mil registros (2023 a 2025) |
|---|---|---|---|---|
| `base_territorial_datasus/` | DATASUS, Base Territorial jun/2026: `ftp://ftp.datasus.gov.br/territorio/tabelas/2026/06-base_territorial_jun26.zip` | Hierarquia geográfica e de saúde, coordenadas, área, semiárido, Amazônia Legal, capital | `CO_MUNICIP` (6 dígitos) = `ID_MUNICIP`, `ID_MN_RESI`, `COMUNINF`, `MUNICIPIO` | **100%** (fora os `0` que o ES usa em `COMUNINF`/`MUNICIPIO`), inclusive as RAs do DF (`5399xx`) e os "município ignorado" (`xx0000`) |
| `populacao_ibge/` | IBGE, SIDRA tabela 6579 (Estimativas de População): `https://apisidra.ibge.gov.br/values/t/6579/n6/all/v/all/p/2024,2025`. IBGE, SIDRA tabela 4709 (Censo 2022, população residente): `https://apisidra.ibge.gov.br/values/t/4709/n6/all/v/93/p/2022` | Denominador da incidência, por município e ano (2023, 2024, 2025). A tabela 6579 **não tem 2022 nem 2023** (o IBGE não publicou estimativas em torno do Censo), então o denominador de 2023 sai do Censo 2022 (ver seção 5.1) | `D1C` (7 dígitos) = `tb_municip.CO_MUNICDV` | 6579: 5.571 municípios × 2 anos, com um valor ausente (`...`): Boa Esperança do Norte/MT em 2024, município criado depois. 4709: 5.570 municípios (sem Boa Esperança do Norte). |
| `cnes/` | OpenDataSUS, CNES Estabelecimentos: `https://s3.sa-east-1.amazonaws.com/ckan.saude.gov.br/CNES/cnes_estabelecimentos.zip` (versão de 11/06/2025) | Nome, tipo, esfera e gestão da unidade notificadora | `CO_CNES` = `ID_UNIDADE` (ver armadilha 4.3) | **99,5%** das notificações |
| `sinan_auxiliar/cnv/` | DATASUS, `ftp://ftp.datasus.gov.br/dissemin/publicos/SINAN/AUXILIAR/TAB_SINANONLINE.zip` (e `TipoUnidade.cnv` do `TAB_SINANNET.zip`) | **Fonte autoritativa dos domínios** (substitui o PDF do dicionário onde os dois divergem) | Valor do próprio campo | n/a |
| `sinan_auxiliar/dbf/` | DATASUS, `ftp://ftp.datasus.gov.br/dissemin/publicos/SINAN/AUXILIAR/TAB_SINANNET.zip` | `REGIONET`: regionais de vigilância do Sinan. `OCUPANET`: ocupações (CBO). | `ID_REGIONA` / `ID_OCUPA_N` | REGIONET 94% (99% fora do ES); OCUPANET 95,2% (sem o código `0`) |

### Arquivos `.cnv` mais importantes

| Arquivo | Campo do SINAN | Por que importa |
|---|---|---|
| `Classchik.cnv` | `CLASSI_FIN` | Define **5 = Descartado** e **13 = Chikungunya**. O PDF do dicionário diz 1/2/8, o que não bate com os dados. |
| `Clinic_chi.cnv` | `CLINC_CHIK` | 1 = Aguda, 2 = Crônica |
| `evochik.cnv` | `EVOLUCAO` | Cura, óbito pelo agravo, óbito por outras causas, etc. |
| `Confdesc.cnv` | `CRITERIO` | Laboratório, clínico-epidemiológico |
| `Fxidad*NET.cnv`, `IdadedetNET.cnv` | `NU_IDADE_N` | Faixas etárias oficiais do SINAN, sobre a idade codificada (1º dígito = unidade) |
| `ChikNON.def` | todos | Definição TabWin da base de chikungunya: diz qual `.cnv` decodifica cada campo |
| `TipoUnidade.cnv` | `cnes.TP_UNIDADE` | Descrição do tipo de estabelecimento |

`Raca.cnv` foi renomeado de `Raça.cnv`, para evitar problemas de nome não-ASCII no git e no Colab.

## 3. Recorte do CNES

O arquivo original (`cnes_estabelecimentos.csv`, 574.006 estabelecimentos, 185 MB) foi filtrado para manter **só os estabelecimentos que aparecem como `ID_UNIDADE` em alguma notificação de 2023, 2024 ou 2025**. O resultado tem 26.845 linhas. Colunas, ordem, aspas e bytes de cada linha foram preservados.

Regra do filtro: `CO_CNES` sem zeros à esquerda ∈ {`ID_UNIDADE` sem zeros à esquerda, nos três CSVs}.

- Das 27.202 unidades distintas no SINAN, 357 não existem no CNES atual. São unidades desativadas, que somam 4.470 notificações (0,47%).
- O `UNIDANET.DBF` (25 MB) **não foi trazido**, porque cobre só parte dessas unidades (na versão anterior, com 2024 a 2026, eram 0,25% a mais). Essas unidades devem virar um membro "Unidade não identificada" na dimensão.

## 4. Armadilhas para carregar no PostgreSQL

Os arquivos **não seguem um padrão único**, e cada um precisa de parâmetros próprios no `COPY`:

| Arquivo | Delimitador | Encoding | Quebra de linha | Observação |
|---|---|---|---|---|
| `tb_municip.csv`, `tb_uf.csv`, `tb_regiao.csv`, `rl_*.csv` | `;` | UTF-8 (ASCII) | CRLF | |
| `tb_macsaud.csv` | `;` | UTF-8 | CRLF | |
| `tb_regsaud.csv` | **`,`** | UTF-8 | **LF** | É o único com vírgula como delimitador |
| `cnes_estabelecimentos_recorte_chik.csv` | `;` | UTF-8 | CRLF | Texto entre aspas duplas |
| `sidra_6579_...json`, `sidra_4709_...json` | JSON | UTF-8 | | O 1º elemento do array é o **cabeçalho**, não um dado |
| `*.cnv`, `*.def` | formato TabWin (largura fixa) | **LATIN1** | CRLF | Não é CSV, precisa de parser |
| `*.DBF` | dBase III | LATIN1 | | No Colab: `pip install dbfread` |

O modo CSV do `COPY` aceita CRLF sem configuração extra. Exemplo:

```sql
COPY stg_tb_municip FROM '/caminho/tb_municip.csv'
  WITH (FORMAT csv, HEADER true, DELIMITER ';', ENCODING 'UTF8');
```

1. **Vírgula decimal:** em `tb_municip.csv`, `NU_LATITUD`, `NU_LONGIT` e `NU_AREA` usam vírgula (por exemplo, `-11,9355`). Carregar como `text` no staging e converter com `replace(col, ',', '.')::numeric`.
2. **O cabeçalho do CSV difere do `_layout.txt`:** o `tb_municip.csv` tem as colunas `UF` e `MACRORREGIONAL`, que o layout não lista. Vale o cabeçalho do CSV; o layout é do formato de largura fixa (`.txt`).
3. **Zeros à esquerda no CNES:** `CO_CNES` vem sem zeros (`19`), enquanto o `ID_UNIDADE` do SINAN às vezes vem com zeros (`0010219`) e às vezes sem (`12165`). Normalizar os dois lados com `lpad(x, 7, '0')`. Por isso **códigos devem ser `text`, nunca inteiro**.
4. **Valor ausente no SIDRA:** é `"..."`, e precisa virar `NULL`.
5. **Códigos que não são municípios:** `CO_STATUS` em `tb_municip` vale `ATIVO`, `REG ADM` (RAs do DF), `IGNR`/`IGNOR` (ignorado), `TRANS` ou `EXTIN`. Esses registros devem continuar na dimensão como membros especiais, porque as notificações apontam para eles.

**Sugestão para o ELT:** carregar os JSONs do SIDRA como `jsonb` e transformar dentro do banco com `jsonb_array_elements`. É um exemplo direto de transformação feita no banco, que é o que diferencia o ELT.

## 5. Decisão de modelagem que essas fontes sustentam

O `ID_REGIONA` do SINAN **não** é a Região de Saúde oficial do SUS (CIR). Em cerca de 94% dos registros ele é a regional de vigilância do Sinan (4 dígitos, como `1341 = GVE XVI Botucatu`). Só o Espírito Santo, que vem do e-SUS VS, usa o código CIR (5 dígitos). Para a hierarquia ficar uniforme nos três anos, Região de Saúde e Macrorregião são derivadas **do município**, por `rl_municip_regsaud` e `rl_regsaud_macsaud`.

### 5.1 População de 2023

O IBGE não publicou estimativas municipais para 2022 e 2023: a série da tabela 6579 pula de 2021 para 2024, por causa do Censo 2022. Para o denominador de 2023 há duas opções, e as duas usam só os arquivos desta pasta:

- **Censo 2022 (tabela 4709) como aproximação de 2023.** É a opção mais simples e usa um dado oficial, sem estimativa nossa.
- **Interpolação geométrica entre o Censo 2022 (ref. 01/08/2022) e a estimativa de 2024 (ref. 01/07/2024).** É mais precisa, e a interpolação vira uma transformação documentada no pipeline.

Boa Esperança do Norte/MT não existe no Censo 2022 nem na estimativa de 2024, então fica sem denominador em 2023 e 2024.

## 6. Snapshot das bases principais (SINAN chikungunya)

Os arquivos ficam em [`../sinan_chikungunya/`](../sinan_chikungunya/), documentados em [`../README.md`](../README.md). O OpenDataSUS republica os arquivos **diariamente**, então os números podem mudar. Em 11/11/2026 (2024 e 2025) e 12/11/2026 (2023) a versão publicada era idêntica às cópias locais:

| Arquivo | Linhas | MD5 | Download oficial (zip) |
|---|---|---|---|
| `CHIKBR23.csv` | 266.442 | `46d8674f22ef555f6f24a52a75c4e0f4` | `https://s3.sa-east-1.amazonaws.com/ckan.saude.gov.br/SINAN/Chikungunya/csv/CHIKBR23.csv.zip` |
| `CHIKBR24.csv` | 426.214 | `19b805c4ebd28f6c9b0437aa11f3c9b0` | `.../csv/CHIKBR24.csv.zip` |
| `CHIKBR25.csv` | 253.753 | `6d290c223719b97c8e6612317242ea75` | `.../csv/CHIKBR25.csv.zip` |

O `CHIKBR24.csv` (120 MB) passa do limite de 100 MB do GitHub, por isso o repositório versiona os zips oficiais (de 4 a 10 MB, com conteúdo idêntico) e ignora os CSVs descompactados.

## 7. Integridade (MD5 dos arquivos desta pasta)

```
091a824d922a8749b047968ecb4f2b2b  base_territorial_datasus/rl_municip_regsaud.csv
661b66fff8f79b5bf6b88174ebe73edc  base_territorial_datasus/rl_regsaud_macsaud.csv
6ffff7907509565520ea03947ad39c21  base_territorial_datasus/tb_macsaud.csv
134733182571213ccbb1e5a4e456e633  base_territorial_datasus/tb_municip.csv
db38e47bb94413b7cd6f6f17fe8d0c40  base_territorial_datasus/tb_regiao.csv
8980d7e6449440583a77c5fc92d559d3  base_territorial_datasus/tb_regsaud.csv
a058f7879e2b81afa6e95553cfd4bcaa  base_territorial_datasus/tb_uf.csv
b352a85990f4a0919c1571f3673c0eb7  cnes/cnes_estabelecimentos_recorte_chik.csv
c30f37e26a0c04477b265daa814ca6e5  populacao_ibge/sidra_4709_censo_2022.json
54140e5f508d49c91c3063a30df090a1  populacao_ibge/sidra_6579_estimativas_2024_2025.json
75ccaa10b1fdf4690db94c461381ebc5  sinan_auxiliar/dbf/REGIONET.DBF
32dc05159226d4d7cdf162378c174dff  sinan_auxiliar/dbf/OCUPANET.DBF
```

## 8. O que ficou de fora, e por quê

| Fonte | Motivo |
|---|---|
| API de localidades do IBGE | Não tem RAs do DF nem códigos "ignorado". A base do DATASUS já cobre 100%. |
| `UNIDANET.DBF` (25 MB) | Ganho de só 0,25% de cobertura sobre o CNES atual (seção 3) |
| Tabela CBO oficial do MTE | Não há CSV com link estável. O `OCUPANET` cobre 95,2%, e `ID_OCUPA_N` só está preenchido em 35 a 40% das notificações. |
| Calendário / semana epidemiológica | Não precisa de fonte: é gerado por código, pela regra MMWR (semana de domingo a sábado; a SE 1 tem pelo menos 4 dias no ano novo). |
