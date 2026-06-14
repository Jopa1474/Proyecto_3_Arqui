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
        raise ValueError("El CSV no contiene datos")
    return rows


def save_stall_timeline(rows: List[Dict[str, int]], outdir: str) -> None:
    cycles = [r["cycle"] for r in rows]
    cache_stall = [r["cache_stall"] for r in rows]
    stall_l1 = [r["stall_l1_miss"] for r in rows]
    stall_l2 = [r["stall_l2_miss"] for r in rows]

    plt.figure(figsize=(12, 4))
    plt.step(cycles, cache_stall, where="post", label="cache_stall (global)", linewidth=1.8)
    plt.step(cycles, stall_l1, where="post", label="stall_l1_miss", linewidth=1.2)
    plt.step(cycles, stall_l2, where="post", label="stall_l2_miss", linewidth=1.2)
    plt.title("Timeline de stalls de cache")
    plt.xlabel("Ciclo")
    plt.ylabel("Señal (0/1)")
    plt.ylim(-0.1, 1.2)
    plt.grid(alpha=0.25)
    plt.legend(loc="upper right")
    plt.tight_layout()
    plt.savefig(os.path.join(outdir, "cache_stall_timeline.svg"))
    plt.close()


def save_hit_percentage_timeline(rows: List[Dict[str, int]], outdir: str) -> None:
    cycles = [r["cycle"] for r in rows]

    l1_hit_pct = [r["l1_hit_rate_x1000"] / 10.0 for r in rows]
    l2_hit_pct = [r["l2_hit_rate_x1000"] / 10.0 for r in rows]

    plt.figure(figsize=(12, 5))
    plt.plot(cycles, l1_hit_pct, label="L1 hit rate (%)", linewidth=2.2)
    plt.plot(cycles, l2_hit_pct, label="L2 hit rate (%)", linewidth=2.2)
    plt.title("Porcentaje de hit vs tiempo")
    plt.xlabel("Ciclo")
    plt.ylabel("Hit rate (%)")
    plt.ylim(0, 100)
    plt.grid(alpha=0.25)
    plt.legend(loc="upper left")
    plt.tight_layout()
    plt.savefig(os.path.join(outdir, "cache_hit_rate_vs_time.svg"))
    plt.close()


def save_derived_metrics(rows: List[Dict[str, int]], outdir: str) -> None:
    cycles = [r["cycle"] for r in rows]

    ipc = [r["ipc_x1000"] / 1000.0 for r in rows]
    l1_hit = [r["l1_hit_rate_x1000"] / 10.0 for r in rows]
    l2_hit = [r["l2_hit_rate_x1000"] / 10.0 for r in rows]
    amat = [r["amat_x1000"] / 1000.0 for r in rows]

    fig, axes = plt.subplots(2, 1, figsize=(12, 7), sharex=True)

    axes[0].plot(cycles, ipc, label="IPC", linewidth=2.0)
    axes[0].plot(cycles, amat, label="AMAT (ciclos)", linewidth=2.0)
    axes[0].set_ylabel("Valor")
    axes[0].set_title("Metricas derivadas durante el warm-up")
    axes[0].grid(alpha=0.25)
    axes[0].legend(loc="upper right")

    axes[1].plot(cycles, l1_hit, label="L1 hit rate (%)", linewidth=2.0)
    axes[1].plot(cycles, l2_hit, label="L2 hit rate (%)", linewidth=2.0)
    axes[1].set_xlabel("Ciclo")
    axes[1].set_ylabel("Porcentaje")
    axes[1].grid(alpha=0.25)
    axes[1].legend(loc="lower right")

    plt.tight_layout()
    plt.savefig(os.path.join(outdir, "cache_derived_metrics.svg"))
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Genera graficas con matplotlib del comportamiento de cache usando un CSV timeline"
    )
    parser.add_argument("--input", required=True, help="Ruta al CSV de timeline")
    parser.add_argument("--outdir", default="sim/plots", help="Carpeta de salida")
    args = parser.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    rows = load_rows(args.input)

    cycles = [r["cycle"] for r in rows]

    # Se mantiene para validación básica del CSV.
    _ = cycles

    save_stall_timeline(rows, args.outdir)
    save_hit_percentage_timeline(rows, args.outdir)
    save_derived_metrics(rows, args.outdir)

    print(f"Graficas generadas en: {args.outdir}")
    print(" - cache_stall_timeline.svg")
    print(" - cache_hit_rate_vs_time.svg")
    print(" - cache_derived_metrics.svg")


if __name__ == "__main__":
    main()
