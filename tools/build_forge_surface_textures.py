"""Build small seamless PBR finishes for the garage, without rebaking its meshes."""
from pathlib import Path
import numpy as np
from PIL import Image

OUTPUT = Path(__file__).resolve().parents[1] / "art/forge-garage/finishes"
SIZE = 512
rng = np.random.default_rng(20261003)


def noise(grid):
    # Repeat the first row/column before interpolation to keep tile boundaries continuous.
    cells = rng.random((grid, grid)).astype(np.float32)
    tiled = np.pad(cells, ((0, 1), (0, 1)), mode="wrap")
    coords = np.arange(SIZE) * grid / SIZE
    a = coords.astype(int)
    t = coords - a
    t = t * t * (3 - 2 * t)
    low = tiled[a[:, None], a[None, :]] * (1 - t[None, :]) + tiled[a[:, None], a[None, :] + 1] * t[None, :]
    high = tiled[a[:, None] + 1, a[None, :]] * (1 - t[None, :]) + tiled[a[:, None] + 1, a[None, :] + 1] * t[None, :]
    return low * (1 - t[:, None]) + high * t[:, None]


def save(name, tone, height, roughness, normal_strength):
    # Albedo carries restrained wear; physical color comes from the shared material palette.
    Image.fromarray(np.uint8(np.clip(tone, 0, 1) * 255)).convert("RGB").save(OUTPUT / f"{name}_albedo.png")
    Image.fromarray(np.uint8(np.clip(roughness, 0, 1) * 255)).save(OUTPUT / f"{name}_roughness.png")
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * normal_strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * normal_strength
    normals = np.stack((-dx, dy, np.ones_like(dx)), axis=-1)
    normals /= np.linalg.norm(normals, axis=-1, keepdims=True)
    Image.fromarray(np.uint8((normals * 0.5 + 0.5) * 255)).save(OUTPUT / f"{name}_normal.png")


def main():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    coarse, medium, fine = noise(5), noise(25), noise(128)
    pores = np.clip((noise(180) - 0.71) * 5, 0, 1)
    concrete = 0.78 + (coarse - 0.5) * 0.20 + (medium - 0.5) * 0.08 + (fine - 0.5) * 0.03 - pores * 0.05
    save("concrete", concrete, medium * 0.06 + fine * 0.045 - pores * 0.04, 0.83 + fine * 0.13, 2.0)
    y, x = np.mgrid[:SIZE, :SIZE]
    grain = noise(128)
    scratches = np.maximum(0, np.sin(x / SIZE * np.pi * 140) - 0.96) * (noise(12) > 0.60)
    steel = 0.86 + (coarse - 0.5) * 0.06 + (grain - 0.5) * 0.06 + scratches * 1.2
    save("paint", steel, grain * 0.065 + scratches * 0.25, 0.64 + medium * 0.22 - scratches, 2.2)
    brushed = np.sin(y / SIZE * np.pi * 216) * 0.018
    save("metal", 0.87 + brushed + (grain - 0.5) * 0.05, brushed + grain * 0.026, 0.43 + medium * 0.22, 2.0)
    woodgrain = np.sin(x / SIZE * np.pi * 22 + medium * 0.7) * 0.045
    save("wood", 0.82 + woodgrain + (coarse - 0.5) * 0.12 + (grain - 0.5) * 0.05, woodgrain + grain * 0.025, 0.79 + medium * 0.12, 2.2)
    glass = 0.36 + noise(5) * 0.22 + noise(12) * 0.12
    Image.fromarray(np.uint8(glass * 255)).convert("RGB").save(OUTPUT / "glass_albedo.png")
    print(f"Garage finishes: 13 seamless 512px maps in {OUTPUT}")


if __name__ == "__main__":
    main()
