# Fog motion visual validation

The capture harness loads the actual arena and starts a local live duel. Combat and automatic observer/fog updates are disabled. The observer follows the same smooth six-second ellipse around the shipped NorthWestBlock for both renderers, with a fixed 1/60 second simulation step. Both recordings use Godot 4.7.2's production Mobile renderer on the RTX 3070 Laptop GPU at 960×540. Each recording captures 180 actual viewport frames and four snapshots at quarter turns. Raw frame PNGs were removed after assembly; retained snapshots, metrics and compact previews preserve the review.

The compact comparison GIFs are 720×222, 15 fps and six seconds long. One 128-color palette is shared by every frame to avoid palette flicker. Frames come directly from the Godot viewport; preview assembly only resizes and labels the before/after panels. Larger preliminary GIFs were removed after the compact previews were verified.

| Recording | Fog CPU mean | p95 | Max |
| --- | ---: | ---: | ---: |
| Before / fixed overview | 0.236 ms | 1.039 ms | 1.443 ms |
| After / fixed overview | 1.946 ms | 5.875 ms | 6.770 ms |
| Before / normal follow camera | 0.255 ms | 1.104 ms | 1.908 ms |
| After / normal follow camera | 1.969 ms | 5.965 ms | 7.033 ms |

CPU measurements time only the fog's manual physics and render parameter updates, excluding screenshots and other scene work. The final after implementation measured here uses a 192² world opacity mask, 512 rays and a 0.05 second refresh interval. The refresh clock epsilon fix is included: the final run refreshed every third 60 Hz simulation tick, or 20 Hz, producing 128 profile updates across 24 warmup and 360 recorded simulation steps.

A fixed ground region outside the player's route was compared between adjacent overview PNGs. Its p95 mean luma change fell from 1.540 to 0.984 on the 0–255 scale (36% lower), and the maximum mean frame change fell from 2.838 to 1.840 (35% lower). The p95 proportion of pixels changing more than 12 luma levels fell from 2.72% to 0.130% (95% lower). These metrics describe motion smoothness in that region; they do not validate gameplay visibility rules.

The four recording folders retain `metrics.json` and snapshots. The overview folders also retain `temporal_metrics.json`. To recreate a clip, first rerun `tools/capture_fog_motion.gd` for both corresponding versions and views to regenerate raw frames, then run `assemble_motion.py --compact before_overview after_overview` using the bundled Python/Pillow runtime. The preserved before renderer is loaded from `.godot/fog_organic_baseline/fog_of_war.gd` and is intentionally outside the captured deliverable.
