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
        raise ValueError(f"CSV sin datos: {csv_path}")

    return {key: int(value) for key, value in rows[-1].items()}


def cache_total_accesses(row: Dict[str, int]) -> int:
    return (
        row["l1_read_hits"]
        + row["l1_read_misses"]
        + row["l1_write_hits"]
        + row["l1_write_misses"]
    )


def fmt_fixed(value: float) -> str:
    return f"{value:.3f}"


def fmt_ipc_x1000(value: int) -> str:
    return f"{value / 1000.0:.3f}"


def build_rows(cache_rows: Dict[str, Dict[str, int]], nocache_rows: Dict[str, Dict[str, int]]) -> List[List[str]]:
    rows: List[List[str]] = []

    for bench_name in cache_rows.keys():
        cache_row = cache_rows[bench_name]
        nocache_row = nocache_rows[bench_name]
        cache_cycles = cache_row["perf_cycles"]
        nocache_cycles = nocache_row["perf_cycles"]
        speedup = (nocache_cycles / cache_cycles) if cache_cycles else 0.0

        rows.append(
            [
                bench_name,
                str(nocache_cycles),
                str(cache_cycles),
                fmt_fixed(speedup),
                fmt_ipc_x1000(nocache_row["ipc_x1000"]),
                fmt_ipc_x1000(cache_row["ipc_x1000"]),
                str(nocache_row["mem_accesses"]),
                str(cache_row["mem_accesses"]),
                str(cache_total_accesses(cache_row)),
            ]
        )

    return rows


def draw_bar_charts(
    benchmarks: List[Tuple[str, str]],
    cache_rows: Dict[str, Dict[str, int]],
    nocache_rows: Dict[str, Dict[str, int]],
    outdir: str,
) -> None:
    labels = [label for label, _ in benchmarks]
    short_labels = [f"B{i+1}" for i in range(len(labels))]

    cache_cycles  = [cache_rows[l]["perf_cycles"] for l in labels]
    nocache_cycles = [nocache_rows[l]["perf_cycles"] for l in labels]
    cache_ipc  = [cache_rows[l]["ipc_x1000"] / 1000.0 for l in labels]
    nocache_ipc = [nocache_rows[l]["ipc_x1000"] / 1000.0 for l in labels]
    speedups = [
        (nocache_rows[l]["perf_cycles"] / cache_rows[l]["perf_cycles"])
        if cache_rows[l]["perf_cycles"] else 0.0
        for l in labels
    ]

    x = range(len(labels))
    bar_w = 0.35
    colors_cache   = "#3b82f6"   # blue
    colors_nocache = "#f97316"   # orange

    # --- Cycles comparison ---
    fig, ax = plt.subplots(figsize=(10, 5.5))
    bars_nc = ax.bar([i - bar_w / 2 for i in x], nocache_cycles, bar_w,
                     label="No-cache (legacy)", color=colors_nocache, edgecolor="white")
    bars_c  = ax.bar([i + bar_w / 2 for i in x], cache_cycles, bar_w,
                     label="With cache (P4)", color=colors_cache, edgecolor="white")
    ax.set_xticks(list(x))
    ax.set_xticklabels(labels, rotation=12, ha="right")
    ax.set_ylabel("Total cycles")
    ax.set_title("Cache vs No-cache: Total Cycles per Benchmark")
    ax.legend()
    ax.yaxis.set_major_formatter(plt.FuncFormatter(lambda v, _: f"{int(v):,}"))
    ax.bar_label(bars_nc, fmt=lambda v: f"{int(v):,}", padding=3, fontsize=8)
    ax.bar_label(bars_c,  fmt=lambda v: f"{int(v):,}", padding=3, fontsize=8)
    ax.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(outdir, "cache_vs_nocache_cycles.png"), dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(" - cache_vs_nocache_cycles.png")

    # --- IPC comparison ---
    fig, ax = plt.subplots(figsize=(10, 5.5))
    bars_nc = ax.bar([i - bar_w / 2 for i in x], nocache_ipc, bar_w,
                     label="No-cache", color=colors_nocache, edgecolor="white")
    bars_c  = ax.bar([i + bar_w / 2 for i in x], cache_ipc, bar_w,
                     label="With cache (P4)", color=colors_cache, edgecolor="white")
    ax.set_xticks(list(x))
    ax.set_xticklabels(labels, rotation=12, ha="right")
    ax.set_ylabel("IPC")
    ax.set_title("Cache vs No-cache: IPC per Benchmark")
    ax.legend()
    ax.bar_label(bars_nc, fmt="%.3f", padding=3, fontsize=8)
    ax.bar_label(bars_c,  fmt="%.3f", padding=3, fontsize=8)
    ax.grid(axis="y", alpha=0.3)
    plt.tight_layout()
    plt.savefig(os.path.join(outdir, "cache_vs_nocache_ipc.png"), dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(" - cache_vs_nocache_ipc.png")

    # --- Speedup chart ---
    fig, ax = plt.subplots(figsize=(9, 5))
    bars = ax.bar(short_labels, speedups, color=colors_cache, edgecolor="white", width=0.5)
    ax.axhline(1.0, color="gray", linewidth=1.2, linestyle="--", label="Speedup = 1 (no gain)")
    ax.set_ylabel("Speedup  (no-cache cycles / cache cycles)")
    ax.set_title("Cache Speedup per Benchmark")
    ax.legend()
    ax.bar_label(bars, fmt="%.2fx", padding=4, fontsize=10, fontweight="bold")
    ax.grid(axis="y", alpha=0.3)
    # Annotate full benchmark names below short labels
    for i, label in enumerate(labels):
        ax.annotate(label, xy=(i, 0), xytext=(0, -28), textcoords="offset points",
                    ha="center", fontsize=8, color="#555")
    plt.tight_layout()
    plt.savefig(os.path.join(outdir, "cache_vs_nocache_speedup.png"), dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(" - cache_vs_nocache_speedup.png")


def draw_table(rows: List[List[str]], output_path: str) -> None:
    fig, ax = plt.subplots(figsize=(16, 4.8))
    ax.axis("off")
    ax.set_title("Cache vs No-cache Benchmark Comparison", loc="left", fontsize=16, fontweight="bold", pad=12)

    table = ax.table(
        cellText=rows,
        colLabels=[
            "Benchmark",
            "No-cache cycles",
            "Cache cycles",
            "Speedup",
            "No-cache IPC",
            "Cache IPC",
            "No-cache accesses",
            "Cache RAM accesses",
            "Cache total accesses",
        ],
        cellLoc="center",
        colLoc="center",
        loc="center",
    )
    table.auto_set_font_size(False)
    table.set_fontsize(9.5)
    table.scale(1.0, 1.6)

    for (row_idx, _), cell in table.get_celld().items():
        cell.set_edgecolor("#d0d0d0")
        if row_idx == 0:
            cell.set_facecolor("#1f2937")
            cell.set_text_props(color="white", weight="bold")
        elif row_idx % 2 == 0:
            cell.set_facecolor("#f7f7f7")

    plt.tight_layout()
    plt.savefig(output_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description="Genera una tabla comparativa cache vs no-cache")
    parser.add_argument("--input-dir", default="sim", help="Carpeta con los CSV")
    parser.add_argument("--outdir", default="sim/plots/comparison", help="Carpeta de salida")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    benchmarks: List[Tuple[str, str]] = [
        ("Benchmark 1 - Sequential", "benchmark_1_sequential"),
        ("Benchmark 2 - Stride", "benchmark_2_stride"),
        ("Benchmark 3 - Random", "benchmark_3_random"),
        ("Benchmark 4 - Thousands", "benchmark_4_thousands"),
    ]

    cache_rows: Dict[str, Dict[str, int]] = {}
    nocache_rows: Dict[str, Dict[str, int]] = {}

    for label, stem in benchmarks:
        cache_rows[label] = load_last_row(os.path.join(args.input_dir, f"cache_timeline_{stem}.csv"))
        nocache_rows[label] = load_last_row(os.path.join(args.input_dir, f"nocache_timeline_{stem}.csv"))

    rows = build_rows(cache_rows, nocache_rows)
    output_path = os.path.join(args.outdir, "cache_vs_nocache_summary.png")
    draw_table(rows, output_path)
    print(f"Tabla comparativa generada en: {output_path}")

    print("Graficas de barras:")
    draw_bar_charts(benchmarks, cache_rows, nocache_rows, args.outdir)


if __name__ == "__main__":
    main()