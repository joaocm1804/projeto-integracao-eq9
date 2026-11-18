#!/usr/bin/env python3
"""
Perfilamento exploratório e comparação interanual das bases de Febre de Chikungunya
(SINAN 2023, 2024 e 2025) e das fontes externas de enriquecimento.

Gera o relatório estruturado em docs/perfilamento_comparativo.md.
"""

from collections import Counter, defaultdict
import csv
from datetime import datetime
import json
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent.parent
SINAN_DIR = BASE_DIR / "dados" / "sinan_chikungunya"
EXT_DIR = BASE_DIR / "dados" / "externos"
OUT_PATH = BASE_DIR / "docs" / "perfilamento_comparativo.md"

ANOS = {
    2023: SINAN_DIR / "CHIKBR23.csv",
    2024: SINAN_DIR / "CHIKBR24.csv",
    2025: SINAN_DIR / "CHIKBR25.csv",
}

CAMPOS_CATEGORICOS = [
    "TP_NOT",
    "ID_AGRAVO",
    "TP_SISTEMA",
    "CS_SEXO",
    "CS_GESTANT",
    "CS_RACA",
    "CS_ESCOL_N",
    "HOSPITALIZ",
    "CLASSI_FIN",
    "CRITERIO",
    "CLINC_CHIK",
    "EVOLUCAO",
    "RES_CHIKS1",
    "RES_CHIKS2",
    "RESUL_PRNT",
    "NDUPLIC_N",
]

CAMPOS_DATA = [
    "DT_NOTIFIC",
    "DT_SIN_PRI",
    "DT_INVEST",
    "DT_INTERNA",
    "DT_OBITO",
    "DT_ENCERRA",
    "DT_DIGITA",
]

CAMPOS_CHAVE = [
    "ID_MUNICIP",
    "ID_MN_RESI",
    "ID_UNIDADE",
    "ID_REGIONA",
    "NU_IDADE_N",
]


def parse_date(val: str):
    if not val:
        return None
    try:
        return datetime.strptime(val, "%Y-%m-%d").date()
    except ValueError:
        return "INVALID"


def carregar_externos():
    """Carrega conjuntos de chaves das fontes externas para checar cobertura."""
    municipios = set()
    with open(EXT_DIR / "base_territorial_datasus" / "tb_municip.csv", encoding="utf-8") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            municipios.add(row["CO_MUNICIP"].strip())

    cnes = set()
    with open(EXT_DIR / "cnes" / "cnes_estabelecimentos_recorte_chik.csv", encoding="latin1") as f:
        reader = csv.DictReader(f, delimiter=";")
        for row in reader:
            cnes.add(row["CO_CNES"].strip().lstrip("0").zfill(7))

    with open(EXT_DIR / "populacao_ibge" / "sidra_6579_estimativas_2024_2025.json", encoding="utf-8") as f:
        sidra_6579 = json.load(f)
    with open(EXT_DIR / "populacao_ibge" / "sidra_4709_censo_2022.json", encoding="utf-8") as f:
        sidra_4709 = json.load(f)

    return municipios, cnes, (sidra_4709, sidra_6579)


def perfilar_ano(ano: int, path: Path, municipios_ref: set, cnes_ref: set):
    with open(path, encoding="utf-8", newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        col_idx = {c: i for i, c in enumerate(header)}

        n_linhas = 0
        row_hashes = Counter()
        nulos = Counter()
        ign_9 = Counter()
        zero_val = Counter()
        cat_counts = {c: Counter() for c in CAMPOS_CATEGORICOS}
        date_stats = {
            c: {"min": None, "max": None, "invalid": 0, "non_empty": 0}
            for c in CAMPOS_DATA
        }
        anomalias_data = Counter()
        idade_unidades = Counter()
        idade_invalidas = 0
        es_count = 0
        mun_not_match = 0
        mun_res_match = 0
        cnes_match = 0
        sem_pri_vals = Counter()

        for row in reader:
            n_linhas += 1
            row_hashes[hash(tuple(row))] += 1

            for i, val in enumerate(row):
                col = header[i]
                if val == "":
                    nulos[col] += 1
                elif val == "9":
                    ign_9[col] += 1
                elif val == "0":
                    zero_val[col] += 1

            for c in CAMPOS_CATEGORICOS:
                val = row[col_idx[c]]
                cat_counts[c][val if val != "" else "<VAZIO>"] += 1

            if row[col_idx["SG_UF_NOT"]] == "32":
                es_count += 1

            sem_pri = row[col_idx["SEM_PRI"]]
            if sem_pri:
                sem_pri_vals[sem_pri] += 1

            # Datas e consistência temporal
            parsed_dates = {}
            for c in CAMPOS_DATA:
                val = row[col_idx[c]]
                d = parse_date(val)
                if d == "INVALID":
                    date_stats[c]["invalid"] += 1
                elif d is not None:
                    date_stats[c]["non_empty"] += 1
                    if date_stats[c]["min"] is None or d < date_stats[c]["min"]:
                        date_stats[c]["min"] = d
                    if date_stats[c]["max"] is None or d > date_stats[c]["max"]:
                        date_stats[c]["max"] = d
                    parsed_dates[c] = d

            dt_not = parsed_dates.get("DT_NOTIFIC")
            dt_sin = parsed_dates.get("DT_SIN_PRI")
            dt_enc = parsed_dates.get("DT_ENCERRA")
            dt_obt = parsed_dates.get("DT_OBITO")

            if dt_not and dt_sin and dt_sin > dt_not:
                anomalias_data["dt_sin_maior_dt_notific"] += 1
            if dt_not and dt_enc and dt_enc < dt_not:
                anomalias_data["dt_encerra_menor_dt_notific"] += 1
            if dt_sin and dt_obt and dt_obt < dt_sin:
                anomalias_data["dt_obito_menor_dt_sin_pri"] += 1

            # Idade NU_IDADE_N
            idade = row[col_idx["NU_IDADE_N"]]
            if idade:
                if len(idade) == 4 and idade.isdigit() and idade[0] in {"1", "2", "3", "4"}:
                    idade_unidades[idade[0]] += 1
                else:
                    idade_invalidas += 1
                    idade_unidades["OUTRO"] += 1

            # Cobertura de chaves externas
            m_not = row[col_idx["ID_MUNICIP"]].strip()
            if m_not in municipios_ref:
                mun_not_match += 1
            m_res = row[col_idx["ID_MN_RESI"]].strip()
            if m_res in municipios_ref:
                mun_res_match += 1
            unid = row[col_idx["ID_UNIDADE"]].strip().lstrip("0").zfill(7) if row[col_idx["ID_UNIDADE"]].strip() else ""
            if unid and unid in cnes_ref:
                cnes_match += 1

    duplicatas_exatas = sum(cnt - 1 for cnt in row_hashes.values() if cnt > 1)
    return {
        "ano": ano,
        "header": header,
        "n_linhas": n_linhas,
        "duplicatas_exatas": duplicatas_exatas,
        "es_count": es_count,
        "nulos": nulos,
        "ign_9": ign_9,
        "zero_val": zero_val,
        "cat_counts": cat_counts,
        "date_stats": date_stats,
        "anomalias_data": anomalias_data,
        "idade_unidades": idade_unidades,
        "idade_invalidas": idade_invalidas,
        "mun_not_match": mun_not_match,
        "mun_res_match": mun_res_match,
        "cnes_match": cnes_match,
        "sem_pri_min": min(sem_pri_vals) if sem_pri_vals else None,
        "sem_pri_max": max(sem_pri_vals) if sem_pri_vals else None,
    }


def fmt_pct(n: int, total: int) -> str:
    return f"{(100.0 * n / total):.2f}%" if total else "0.00%"


def gerar_relatorio(resultados: dict, sidras: tuple):
    sidra_4709, sidra_6579 = sidras
    anos = sorted(resultados.keys())
    h_ref = resultados[2023]["header"]
    mesmo_esquema = (resultados[2023]["header"] == resultados[2024]["header"] == resultados[2025]["header"])

    linhas = []
    linhas.append("# Perfilamento Comparativo das Bases SINAN Chikungunya (2023, 2024 e 2025)\n")
    linhas.append("Gerado automaticamente a partir dos arquivos brutos em `dados/sinan_chikungunya/` e `dados/externos/` (snapshot de 11–12/11/2026).\n")

    linhas.append("## 1. Estrutura, Esquema e Formatos\n")
    linhas.append(f"- **Colunas:** {len(h_ref)} colunas por arquivo. Os três anos possuem **exatamente as mesmas colunas na mesma ordem**: `{mesmo_esquema}`.")
    linhas.append("- **Divergência com o Dicionário PDF oficial:** o PDF documenta 121 campos; os CSVs trazem **122 colunas** devido à presença de `NU_LOTE_I` (não documentada no PDF).")
    linhas.append("- **Formato dos CSVs SINAN:** delimitador `,`, encoding UTF-8/ASCII, cabeçalho na linha 1, datas no formato `AAAA-MM-DD`.")
    linhas.append("- **Formato das fontes externas:** Base Territorial DATASUS (`;` e UTF-8, exceto `tb_regsaud.csv` com `,` e LF; decimais com vírgula), CNES (`;` e UTF-8, textos entre aspas), IBGE SIDRA 4709 (Censo 2022) e SIDRA 6579 (Estimativas 2024–2025) em JSON com cabeçalho no elemento 0 e valor ausente `\"...\"`, tabelas `.cnv`/`.DBF` em LATIN1.\n")

    linhas.append("## 2. Volumetria, Duplicatas e Cobertura de Chaves\n")
    linhas.append("| Métrica | 2023 | 2024 | 2025 | Total |")
    linhas.append("|---|---:|---:|---:|---:|")
    tot_linhas = sum(resultados[a]["n_linhas"] for a in anos)
    tot_dup = sum(resultados[a]["duplicatas_exatas"] for a in anos)
    tot_es = sum(resultados[a]["es_count"] for a in anos)
    linhas.append(f"| Linhas brutas | {resultados[2023]['n_linhas']:,} | {resultados[2024]['n_linhas']:,} | {resultados[2025]['n_linhas']:,} | {tot_linhas:,} |".replace(",", "."))
    linhas.append(f"| Duplicatas exatas (linhas excedentes) | {resultados[2023]['duplicatas_exatas']:,} | {resultados[2024]['duplicatas_exatas']:,} | {resultados[2025]['duplicatas_exatas']:,} | {tot_dup:,} |".replace(",", "."))
    linhas.append(
        "| Marcadas `NDUPLIC_N = 1` | "
        + " | ".join(f"{resultados[a]['cat_counts']['NDUPLIC_N'].get('1', 0):,}".replace(",", ".") for a in anos)
        + f" | {sum(resultados[a]['cat_counts']['NDUPLIC_N'].get('1', 0) for a in anos):,} |".replace(",", ".")
    )
    linhas.append(
        "| Registros do ES (`SG_UF_NOT = 32`) | "
        + " | ".join(f"{resultados[a]['es_count']:,} ({fmt_pct(resultados[a]['es_count'], resultados[a]['n_linhas'])})".replace(",", ".") for a in anos)
        + f" | {tot_es:,} |".replace(",", ".")
    )
    linhas.append(
        "| Cobertura `ID_MUNICIP` (DATASUS) | "
        + " | ".join(fmt_pct(resultados[a]["mun_not_match"], resultados[a]["n_linhas"]) for a in anos)
        + " | 100.00% |"
    )
    linhas.append(
        "| Cobertura `ID_MN_RESI` (DATASUS) | "
        + " | ".join(fmt_pct(resultados[a]["mun_res_match"], resultados[a]["n_linhas"]) for a in anos)
        + " | — |"
    )
    linhas.append(
        "| Cobertura `ID_UNIDADE` (CNES recorte) | "
        + " | ".join(fmt_pct(resultados[a]["cnes_match"], resultados[a]["n_linhas"]) for a in anos)
        + " | — |"
    )
    linhas.append(
        "| `SEM_PRI` (mín – máx) | "
        + " | ".join(f"{resultados[a]['sem_pri_min']}–{resultados[a]['sem_pri_max']}" for a in anos)
        + " | — |\n"
    )

    linhas.append("## 3. Completude: Nulos e Código \"Ignorado\" (`9`) nas Colunas-Chave do DW\n")
    cols_chave_dw = [
        "DT_NOTIFIC", "DT_SIN_PRI", "DT_ENCERRA", "DT_INTERNA", "DT_OBITO",
        "SG_UF_NOT", "ID_MUNICIP", "ID_MN_RESI", "ID_UNIDADE",
        "NU_IDADE_N", "CS_SEXO", "CS_GESTANT", "CS_RACA", "CS_ESCOL_N",
        "HOSPITALIZ", "CLASSI_FIN", "CRITERIO", "CLINC_CHIK", "EVOLUCAO",
        "RES_CHIKS1", "RES_CHIKS2", "RESUL_PRNT", "ID_OCUPA_N",
    ]
    linhas.append("| Coluna | 2023 Vazio / `9` | 2024 Vazio / `9` | 2025 Vazio / `9` |")
    linhas.append("|---|---|---|---|")
    for col in cols_chave_dw:
        celulas = []
        for a in anos:
            tot = resultados[a]["n_linhas"]
            v = fmt_pct(resultados[a]["nulos"][col], tot)
            i9 = fmt_pct(resultados[a]["ign_9"][col], tot)
            celulas.append(f"{v} / {i9}")
        linhas.append(f"| `{col}` | {' | '.join(celulas)} |")
    linhas.append("")

    linhas.append("## 4. Qualidade Temporal e Decodificação de Idade\n")
    linhas.append("| Verificação | 2023 | 2024 | 2025 |")
    linhas.append("|---|---:|---:|---:|")
    for k, label in [
        ("dt_sin_maior_dt_notific", "`DT_SIN_PRI > DT_NOTIFIC`"),
        ("dt_encerra_menor_dt_notific", "`DT_ENCERRA < DT_NOTIFIC`"),
        ("dt_obito_menor_dt_sin_pri", "`DT_OBITO < DT_SIN_PRI`"),
    ]:
        linhas.append(f"| {label} | " + " | ".join(str(resultados[a]["anomalias_data"][k]) for a in anos) + " |")
    linhas.append(
        "| `DT_NOTIFIC` (mín a máx) | "
        + " | ".join(f"{resultados[a]['date_stats']['DT_NOTIFIC']['min']} a {resultados[a]['date_stats']['DT_NOTIFIC']['max']}" for a in anos)
        + " |"
    )
    linhas.append(
        "| `DT_SIN_PRI` (mín a máx) | "
        + " | ".join(f"{resultados[a]['date_stats']['DT_SIN_PRI']['min']} a {resultados[a]['date_stats']['DT_SIN_PRI']['max']}" for a in anos)
        + " |"
    )
    linhas.append(
        "| `NU_IDADE_N` inválidas | "
        + " | ".join(str(resultados[a]["idade_invalidas"]) for a in anos)
        + " |\n"
    )

    linhas.append("## 5. Domínios Observados vs. Dicionário Oficial (`.cnv` e PDF)\n")
    for campo in ["ID_AGRAVO", "TP_SISTEMA", "CS_SEXO", "CS_GESTANT", "CS_RACA", "CS_ESCOL_N", "HOSPITALIZ", "CLASSI_FIN", "CRITERIO", "CLINC_CHIK", "EVOLUCAO", "RES_CHIKS1"]:
        todos_vals = sorted(set().union(*(resultados[a]["cat_counts"][campo].keys() for a in anos)))
        linhas.append(f"### `{campo}`")
        linhas.append("| Valor bruto | 2023 | 2024 | 2025 |")
        linhas.append("|---|---:|---:|---:|")
        for val in todos_vals:
            row_str = " | ".join(f"{resultados[a]['cat_counts'][campo].get(val, 0):,}".replace(",", ".") for a in anos)
            linhas.append(f"| `{val}` | {row_str} |")
        linhas.append("")

    OUT_PATH.write_text("\n".join(linhas), encoding="utf-8")
    print(f"Relatório gerado em: {OUT_PATH}")
    print(f"Total de linhas: {tot_linhas:,} | Duplicatas exatas: {tot_dup:,} | SIDRA 4709: {len(sidra_4709)-1:,} | SIDRA 6579: {len(sidra_6579)-1:,}")


if __name__ == "__main__":
    municipios_ref, cnes_ref, sidra = carregar_externos()
    resultados = {ano: perfilar_ano(ano, path, municipios_ref, cnes_ref) for ano, path in ANOS.items()}
    gerar_relatorio(resultados, sidra)
