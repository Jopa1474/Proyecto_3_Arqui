import argparse
import csv
import os
from typing import Dict, List

import matplotlib.pyplot as plt


def load_rows(csv_path: str) -> List[Dict[str, int]]:
    rows: List[Dict[str, int]] = []
    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            rows.append({k: int(v) for k, v in row.items()})
    if not rows:
        raise ValueError(f"CSV sin datos: {csv_path}")
    return rows


def make_single_plot(
    benchmark_data: Dict[str, List[Dict[str, int]]],
    out_path: str,
    field: str,
    title: str,
) -> None:
    plt.figure(figsize=(12, 5))

    for name, rows in benchmark_data.items():
        cycles = [r["cycle"] for r in rows]
        values = [r[field] / 10.0 for r in rows]
        plt.plot(cycles, values, linewidth=2.0, label=name)

    plt.title(title)
    plt.xlabel("Ciclo")
    plt.ylabel("Hit rate (%)")
    plt.ylim(0, 100)
    plt.grid(alpha=0.25)
    plt.legend(loc="best")
    plt.tight_layout()
    plt.savefig(out_path)
    plt.close()


def make_combined_plot(benchmark_data: Dict[str, List[Dict[str, int]]], out_path: str) -> None:
    fig, axes = plt.subplots(2, 1, figsize=(12, 8), sharex=True)

    for name, rows in benchmark_data.items():
        cycles = [r["cycle"] for r in rows]
        l1 = [r["l1_hit_rate_x1000"] / 10.0 for r in rows]
        l2 = [r["l2_hit_rate_x1000"] / 10.0 for r in rows]
        axes[0].plot(cycles, l1, linewidth=2.0, label=name)
        axes[1].plot(cycles, l2, linewidth=2.0, label=name)

    axes[0].set_title("Comparacion de benchmarks: L1 hit rate vs tiempo")
    axes[0].set_ylabel("L1 hit rate (%)")
    axes[0].set_ylim(0, 100)
    axes[0].grid(alpha=0.25)
    axes[0].legend(loc="best")

    axes[1].set_title("Comparacion de benchmarks: L2 hit rate vs tiempo")
    axes[1].set_xlabel("Ciclo")
    axes[1].set_ylabel("L2 hit rate (%)")
    axes[1].set_ylim(0, 100)
    axes[1].grid(alpha=0.25)
    axes[1].legend(loc="best")

    plt.tight_layout()
    plt.savefig(out_path)
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(description="Genera graficas comparativas entre benchmarks")
    parser.add_argument("--input-dir", default="sim", help="Carpeta donde estan los CSV de benchmarks")
    parser.add_argument("--outdir", default="sim/plots/comparison", help="Carpeta de salida")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    bench_files = {
        "benchmark_1_sequential": os.path.join(args.input_dir, "cache_timeline_benchmark_1_sequential.csv"),
        "benchmark_2_stride": os.path.join(args.input_dir, "cache_timeline_benchmark_2_stride.csv"),
        "benchmark_3_random": os.path.join(args.input_dir, "cache_timeline_benchmark_3_random.csv"),
        "benchmark_4_thousands": os.path.join(args.input_dir, "cache_timeline_benchmark_4_thousands.csv"),
    }

    benchmark_data: Dict[str, List[Dict[str, int]]] = {}
    for name, path in bench_files.items():
        if not os.path.exists(path):
            raise FileNotFoundError(f"No se encontro {path}. Ejecuta primero make plots-benchmarks")
        benchmark_data[name] = load_rows(path)

    make_single_plot(
        benchmark_data,
        os.path.join(args.outdir, "benchmark_comparison_l1_hit_rate_vs_time.svg"),
        "l1_hit_rate_x1000",
        "Comparacion de benchmarks: L1 hit rate vs tiempo",
    )

    make_single_plot(
        benchmark_data,
        os.path.join(args.outdir, "benchmark_comparison_l2_hit_rate_vs_time.svg"),
        "l2_hit_rate_x1000",
        "Comparacion de benchmarks: L2 hit rate vs tiempo",
    )

    make_combined_plot(
        benchmark_data,
        os.path.join(args.outdir, "benchmark_comparison_l1_l2_hit_rate_vs_time.svg"),
    )

    print(f"Graficas comparativas generadas en: {args.outdir}")
    print(" - benchmark_comparison_l1_hit_rate_vs_time.svg")
    print(" - benchmark_comparison_l2_hit_rate_vs_time.svg")
    print(" - benchmark_comparison_l1_l2_hit_rate_vs_time.svg")


if __name__ == "__main__":
    main()
