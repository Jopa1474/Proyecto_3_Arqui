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


def build_sections(row: Dict[str, int]) -> List[Tuple[str, List[Tuple[str, str]]]]:
    return [
        (
            "Pipeline counters",
            [
                ("Total cycles", fmt_int(row["perf_cycles"])),
                ("Instructions retired", fmt_int(row["perf_instr"])),
                ("Total data accesses", fmt_int(row["mem_accesses"])),
                ("Branch stalls", fmt_int(row["perf_stall_branch"])),
                ("Load-use stalls", fmt_int(row["perf_stall_load_use"])),
            ],
        ),
        (
            "Memory counters",
            [
                ("Memory reads", fmt_int(row["mem_reads"])),
                ("Memory writes", fmt_int(row["mem_writes"])),
                ("Memory accesses", fmt_int(row["mem_accesses"])),
                ("Memory busy cycles", fmt_int(row["mem_cycles"])),
            ],
        ),
        (
            "Derived metrics",
            [
                ("IPC", fmt_fixed(row["ipc_x1000"])),
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

    for (row_idx, _), cell in table.get_celld().items():
        cell.set_edgecolor("#d0d0d0")
        if row_idx == 0:
            cell.set_facecolor("#1f2937")
            cell.set_text_props(color="white", weight="bold")
        elif row_idx % 2 == 0:
            cell.set_facecolor("#f7f7f7")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Genera una tabla resumen en imagen con las metricas finales del datapath sin cache"
    )
    parser.add_argument("--input", required=True, help="Ruta al CSV de timeline")
    parser.add_argument("--outdir", default="sim/plots", help="Carpeta de salida")
    parser.add_argument("--benchmark-name", default="Benchmark", help="Nombre visible del benchmark")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    row = load_last_row(args.input)
    sections = build_sections(row)

    fig, axes = plt.subplots(len(sections), 1, figsize=(12, 8.5))
    if len(sections) == 1:
        axes = [axes]

    fig.suptitle(f"{args.benchmark_name} - Legacy Datapath Summary", fontsize=16, fontweight="bold")

    for ax, (section_title, section_rows) in zip(axes, sections):
        draw_section(ax, section_title, section_rows)

    plt.tight_layout(rect=(0, 0, 1, 0.96))
    output_path = os.path.join(args.outdir, "benchmark_summary_table.png")
    plt.savefig(output_path, dpi=200, bbox_inches="tight")
    plt.close(fig)

    print(f"Tabla resumen generada en: {output_path}")


if __name__ == "__main__":
    main()