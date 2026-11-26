# Graphist

A macOS desktop app for fast, animated 2D graphics rendered with **Metal**, built
with **Swift**, **SwiftUI** and the **command-line tools** (no Xcode project).

- Targets **macOS 26 Tahoe** and later.
- Multiple windows (File ▸ New Window / ⌘N). Each window has its own Metal
  view, command queue, renderer and scene.
- New windows open on **Golden Particles**: 150,000 GPU-simulated particles
  swirling on black with light trails. Click and drag to stir them.
- Graphics are packaged as **scenes**, small self-contained units (Swift + Metal)
  that you can edit, add, and switch between from each window's toolbar.

---

## Requirements

| | |
|---|---|
| macOS | 26 (Tahoe) or later |
| Xcode | 26 or later (Swift 6.2 toolchain + macOS 26 SDK) |
| Metal toolchain | Optional but recommended (see below) |

```bash
# Use the full Xcode toolchain (not just the Command Line Tools)
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# Starting with Xcode 26 the Metal shader compiler is a separate download (once per machine)
xcodebuild -downloadComponent MetalToolchain
```

If the Metal toolchain isn't installed, the build still works: shader sources are
bundled into the app and compiled at launch. Precompiling them into a `.metallib`
gives faster startup and catches shader errors at build time.

## Build and run

```bash
git clone <this repo> graphist
cd graphist
make app          # -> build/Graphist.app (release, ad-hoc signed)
open build/Graphist.app
```

Other targets (`make help`):

| Command | What it does |
|---|---|
| `make app` | Release build of `build/Graphist.app` for this Mac's architecture |
| `make universal` | Same, but arm64 + x86_64 |
| `make debug` | Debug Swift build + shader debug info (for GPU frame capture) |
| `make run` | `make app`, then launch it |
| `make dev` | `swift run` with **live shaders**: edit `Shaders/`, press **⌘R** in a window |
| `make sign` / `make notarize` / `make release` | Developer ID signing and notarization ([docs/SIGNING.md](docs/SIGNING.md)) |
| `make clean` | Remove `.build/` and `build/` |

Under the hood `make app` runs [`scripts/build-app.sh`](scripts/build-app.sh), which:

1. `swift build -c release`
2. Assembles `Graphist.app` (`Contents/MacOS`, `Info.plist` from `Packaging/`, resources)
3. Compiles every `Shaders/**/*.metal` with `xcrun metal` and links them into
   `Contents/Resources/Graphist.metallib`
4. Ad-hoc signs the bundle so it runs locally

The script reads these environment variables: `CONFIG`, `UNIVERSAL=1`, `BUNDLE_ID`, `VERSION`,
`BUILD_NUMBER`, `SHADERS=auto|metallib|source`. For example:

```bash
BUNDLE_ID=com.yourcompany.graphist VERSION=1.0.0 make app
```

To edit and debug in Xcode, run `xed .` (or `open Package.swift`). Running from
Xcode loads shaders straight from the repository's `Shaders/` folder.

---

## Project layout

```
Package.swift                     SwiftPM manifest (macOS 26, Swift 6.2)
Sources/Graphist/
  App/
    GraphistApp.swift             @main, WindowGroup (multi-window)
    CanvasWindow.swift            One window: canvas + toolbar (scene picker, reload, stats)
  Engine/                         Generic plumbing; you rarely need to touch this
    GraphicsScene.swift           ★ The GraphicsScene protocol + SceneContext / FrameContext
    Renderer.swift                Per-window MTKViewDelegate: frame pacing, timing, triple buffering
    MetalCanvas.swift             SwiftUI ⇄ MTKView bridge, mouse input
    ShaderLibrary.swift           Loads/compiles shaders, pipeline helpers
    GPU.swift                     Shared MTLDevice + shader library
    RenderStats.swift             FPS etc. for the overlay
  Toolkit/                        Reusable drawing helpers
    ShapeRenderer.swift           Instanced SDF circles / rects / lines (one draw call)
    RGBA.swift                    sRGB color type (hex, HSB) → linear for the GPU
  Scenes/                         ★ What gets drawn
    SceneCatalog.swift            ★ Register scenes here
    GoldenParticles/              Default scene: compute + additive points + HDR trails
    Orbits/                       Example using ShapeRenderer (no custom shaders)
    ShaderPlayground/             Minimal full-screen fragment shader template
Shaders/                          ★ Metal sources (any .metal here is compiled automatically)
  Common/GraphistCommon.h         Shared helpers (coordinate conversion, random, color)
  Common/Fullscreen.metal         graphist_fullscreen_vertex
  Toolkit/Shapes.metal            Shaders for ShapeRenderer
  GoldenParticles/…               Shaders for each scene
  ShaderPlayground/…
Packaging/                        Info.plist template, entitlements
scripts/                          build-app.sh, sign-and-notarize.sh
docs/SIGNING.md                   Code signing & notarization guide
```

## How rendering works

```
SwiftUI WindowGroup ──► CanvasWindow ──► MetalCanvas (NSViewRepresentable)
                                              │ owns
                                              ▼
                       CanvasMTKView ◄── Renderer (MTKViewDelegate, 1 per window)
                       (display link,         │ per frame: wait for a free frame slot (max 3 in flight),
                        sRGB drawable,        │ build FrameContext (time, dt, size, pointer, command buffer)
                        mouse tracking)       ▼
                                        GraphicsScene.render(frame:)
                                        (compute passes, offscreen passes, drawable pass)
```

- Rendering runs on the main thread, driven by `MTKView`'s display link, at up to
  120 Hz on ProMotion displays. The CPU can encode up to 3 frames ahead of the GPU.
- The drawable is `bgra8Unorm_srgb`. **Shaders output linear color** and blending
  happens in linear space. `RGBA` converts sRGB picker values for you.
- **Coordinates are points, origin top-left, y down**, the same as SwiftUI.
  `frame.size.scale` converts to pixels.
- Errors from scene creation or shader compilation appear in a red banner in the
  window. The app keeps running.

## Adding or editing graphics

### Edit an existing scene

- **Look and behaviour** of the golden particles: the tunables at the top of
  `GoldenParticlesScene.swift` (count, trail length, brightness) and the flow field
  in `Shaders/GoldenParticles/GoldenParticles.metal`.
- **Fast shader iteration:** run `make dev`, edit any `.metal` file, then press **⌘R**
  in a window. The scene is recreated and the shaders recompile without restarting
  the app. Compiler errors appear in the window.

### Add a new scene

1. **Swift:** create `Sources/Graphist/Scenes/MyScene/MyScene.swift`:

   ```swift
   import Foundation
   import Metal
   import simd

   final class MyScene: GraphicsScene {
       static let title = "My Scene"
       private let shapes: ShapeRenderer

       init(context: SceneContext) throws {
           shapes = try ShapeRenderer(context: context)
       }

       func render(frame: FrameContext) {
           let c = frame.size.points * 0.5
           let r = 50 + 20 * sin(Float(frame.time) * 2)
           shapes.circle(center: c, radius: r, color: .gold)
           shapes.circle(center: frame.pointer.location, radius: 8, color: .white, strokeWidth: 2)

           guard let encoder = frame.makeDrawableEncoder(clearColor: RGBA(hex: 0x101018)) else { return }
           shapes.draw(in: encoder, frame: frame)
           encoder.endEncoding()
       }
   }
   ```

2. **Register** it in `Sources/Graphist/Scenes/SceneCatalog.swift`:
   `SceneEntry(MyScene.self)`. The first entry is the default for new windows.

3. **Custom shaders (optional):** add `Shaders/MyScene/MyScene.metal`, with
   `#include "GraphistCommon.h"` for the shared helpers. Look functions up by name with
   `context.shaders.makeRenderPipeline(label:vertex:fragment:pixelFormat:blend:)`
   or `makeComputePipeline(_:)`. `ShaderPlaygroundScene` is the smallest template.
   For a full-screen effect, use `graphist_fullscreen_vertex` and draw 3 vertices.

Rules to keep in mind:

- Shader **function names must be unique** across all `.metal` files, because they
  are linked into one library. Prefix them with the scene name and mark helpers
  `static`.
- Swift structs passed to shaders (uniforms, instances) must **match the Metal
  struct layout** exactly. Use `SIMD2/SIMD4<Float>`, `Float` and `UInt32`, avoid
  `SIMD3`, and keep field order identical.
- Each `render(frame:)` **must render into the drawable** through
  `frame.makeDrawableEncoder(...)`. Before that, encode as many compute or offscreen
  passes as you like on `frame.commandBuffer`.
- Offscreen textures that depend on window size belong in `resize(to:)`.
- CPU-written per-frame buffers need `context.maxFramesInFlight` copies, selected
  with `frame.inFlightIndex`. `ShapeRenderer` already does this. Small uniforms can
  use `setVertexBytes`/`setFragmentBytes` instead.

---

## Code signing and distribution

See **[docs/SIGNING.md](docs/SIGNING.md)**. In short: change the bundle ID,
create a **Developer ID Application** certificate, store notary credentials once
with `xcrun notarytool store-credentials`, then run:

```bash
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" make release
```

This produces a signed, notarized, stapled `build/Graphist-<version>.zip` that
opens without Gatekeeper warnings on any Mac running macOS 26 or later.
