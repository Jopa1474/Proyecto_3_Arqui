import argparse
import csv
import os
from typing import Dict, List, Tuple

import matplotlib.pyplot as plt


def load_last_row(csv_path: str) -> Dict[str, int]:
    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        raise ValueError("El CSV no contiene datos")

    return {key: int(value) for key, value in rows[-1].items()}


def fmt_int(value: int) -> str:
    return f"{value:d}"


def fmt_fixed(value: int, scale: int = 1000) -> str:
    return f"{value / scale:.3f}"


def fmt_percent_x1000(value: int) -> str:
    return f"{value / 10.0:.1f}%"


def total_data_accesses(row: Dict[str, int]) -> int:
    return (
        row["l1_read_hits"]
        + row["l1_read_misses"]
        + row["l1_write_hits"]
        + row["l1_write_misses"]
    )


def build_sections(row: Dict[str, int]) -> List[Tuple[str, List[Tuple[str, str]]]]:
    return [
        (
            "Pipeline counters",
            [
                ("Total cycles", fmt_int(row["perf_cycles"])),
                ("Instructions retired", fmt_int(row["perf_instr"])),
                ("Total data accesses", fmt_int(total_data_accesses(row))),
                ("Cache stall cycles", fmt_int(row["perf_stall_cache"])),
                ("L1 miss stalls", fmt_int(row["perf_stall_l1"])),
                ("L2 miss stalls", fmt_int(row["perf_stall_l2"])),
                ("Branch stalls", fmt_int(row["perf_stall_branch"])),
                ("Load-use stalls", fmt_int(row["perf_stall_load_use"])),
            ],
        ),
        (
            "Cache / memory counters",
            [
                ("L1 read hits", fmt_int(row["l1_read_hits"])),
                ("L1 read misses", fmt_int(row["l1_read_misses"])),
                ("L1 write hits", fmt_int(row["l1_write_hits"])),
                ("L1 write misses", fmt_int(row["l1_write_misses"])),
                ("L2 read hits", fmt_int(row["l2_read_hits"])),
                ("L2 read misses", fmt_int(row["l2_read_misses"])),
                ("L2 write hits", fmt_int(row["l2_write_hits"])),
                ("L2 write misses", fmt_int(row["l2_write_misses"])),
                ("RAM accesses", fmt_int(row["mem_accesses"])),
                ("RAM busy cycles", fmt_int(row["mem_cycles"])),
            ],
        ),
        (
            "Derived metrics",
            [
                ("IPC", fmt_fixed(row["ipc_x1000"])),
                ("L1 hit rate", fmt_percent_x1000(row["l1_hit_rate_x1000"])),
                ("L1 miss rate", fmt_percent_x1000(row["l1_miss_rate_x1000"])),
                ("L2 hit rate", fmt_percent_x1000(row["l2_hit_rate_x1000"])),
                ("L2 miss rate", fmt_percent_x1000(row["l2_miss_rate_x1000"])),
                ("AMAT (cycles)", fmt_fixed(row["amat_x1000"])),
            ],
        ),
    ]


def draw_section(ax, title: str, rows: List[Tuple[str, str]]) -> None:
    ax.axis("off")
    ax.set_title(title, loc="left", fontsize=12, fontweight="bold", pad=10)

    table = ax.table(
        cellText=[[label, value] for label, value in rows],
        colLabels=["Metric", "Value"],
        cellLoc="left",
        colLoc="left",
        loc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.scale(1.0, 1.35)

    for (row_idx, col_idx), cell in table.get_celld().items():
        cell.set_edgecolor("#d0d0d0")
        if row_idx == 0:
            cell.set_facecolor("#1f2937")
            cell.set_text_props(color="white", weight="bold")
        elif row_idx % 2 == 0:
            cell.set_facecolor("#f7f7f7")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Genera una tabla resumen en imagen con las metricas finales del benchmark"
    )
    parser.add_argument("--input", required=True, help="Ruta al CSV de timeline")
    parser.add_argument("--outdir", default="sim/plots", help="Carpeta de salida")
    parser.add_argument("--benchmark-name", default="Benchmark", help="Nombre visible del benchmark")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    row = load_last_row(args.input)
    sections = build_sections(row)

    fig, axes = plt.subplots(len(sections), 1, figsize=(12, 10))
    if len(sections) == 1:
        axes = [axes]

    fig.suptitle(f"{args.benchmark_name} - Summary Metrics", fontsize=16, fontweight="bold")

    for ax, (section_title, section_rows) in zip(axes, sections):
        draw_section(ax, section_title, section_rows)

    plt.tight_layout(rect=(0, 0, 1, 0.96))
    output_path = os.path.join(args.outdir, "benchmark_summary_table.png")
    plt.savefig(output_path, dpi=200, bbox_inches="tight")
    plt.close(fig)

    print(f"Tabla resumen generada en: {output_path}")


if __name__ == "__main__":
    main()