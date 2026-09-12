# Transparent icon sources — unfinished drafts

Generated with built-in image_gen from the original trail-mug master. These are partial results, not release-ready assets or an Icon Composer package.

| File | Use | Status |
| --- | --- | --- |
| trail-mug-cutout-draft.png | Combined mug, foam, and opaque green trail; transparent surrounding background | Alpha present; visible residue in handle opening and along edges; scale differs from original |
| trail-mug-cutout-1024-draft.png | 1024-square export of combined cutout | Same limitations; alpha preserved |
| foam-layer-draft.png | Isolated foam and drip | Alpha present; requires edge cleanup and manual scale/position alignment |

The generator did not preserve pixel-exact placement. Do not stack these files at identical coordinates and assume alignment. Intended eventual stack, back to front: app background, mug body/handle, green trail, foam.

A cleanup retry did not resolve the cutout artifacts. The body-only attempt produced a visible checkerboard background and was rejected. The trail-only call failed because the image generation usage limit was reached. No usable separate body or trail layer is included.

Next work: clean the combined silhouette and handle opening with a deterministic alpha mask; isolate/register layers from that same source, reconstruct the mug beneath foam/trail, and inspect composites over light and dark backgrounds. Configure and validate themed appearances in the app's icon tooling afterward. No dark/tinted variants or .icon document have been built or tested here.

Only this design folder was added; no live app resources were changed. Original opaque icons remain in generated-v1. Exact prompts are in PROMPTS.md.
