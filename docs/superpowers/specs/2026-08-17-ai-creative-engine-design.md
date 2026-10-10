# AI Creative Engine (Gendo-like) Specification

## 1. Overview
The AI Creative Engine is an integrated generative studio module for the Creative Canvas Studio application (comprising Infinite Canvas, Drawing Studio, and AI Creative Engine). Inspired by specialized visual and architectural AI workflows (such as Gendo.ai, ControlNet, and ComfyUI), this subsystem enables direct image generation, multi-modal editing, visual transformation, video motion synthesis, composition reasoning, and an intelligent canvas agent.

---

## 2. Architecture & Subsystems

```
AI Creative Engine (Gendo-like)
│
├── 1. Generation Engine
│   ├── Text → Image (DALL-E 3, SDXL, Flux)
│   ├── Sketch → Image (ControlNet scribble/canny guidance from Drawing Studio)
│   ├── Image → Image (Img2Img denoising & architectural rendering)
│   ├── Image → Video (Motion diffusion / camera path synthesis)
│   └── Reference → Image (IP-Adapter style & subject matching)
│
├── 2. Generative Editing Engine
│   ├── Inpainting (Brush/Lasso Selection Mask fill)
│   ├── Outpainting (Canvas boundaries expansion)
│   ├── Replace Object (Segmented mask + replacement prompt)
│   ├── Remove Object (Content-aware generative erase)
│   ├── Add Object (Context-aware insertion)
│   └── Background Replace (Auto foreground cutout + environment prompt)
│
├── 3. Visual Transformation Engine
│   ├── Style Transfer (Architectural styles, clay models, watercolors, line-art)
│   ├── Material Transfer (PBR textures: glass, marble, brushed metal, timber)
│   ├── Relighting (Day/Golden Hour/Night HDR relighting with normal maps)
│   ├── Recolor (Palette-guided re-tinting)
│   └── Restyle (Mood & atmosphere shift)
│
├── 4. Enhancement Engine
│   ├── Upscale (2x, 4x, 8x ESRGAN / latent upscaler)
│   ├── Denoise (Grain & artifact suppression)
│   ├── Sharpen (Edge micro-contrast boosting)
│   ├── Restore (Face restoration & architectural line correction)
│   └── Detail Enhancement (Texture & foliage synthesis)
│
├── 5. Composition AI Engine
│   ├── Populate (Auto entourage: 3D scale-accurate humans, trees, vehicles)
│   ├── Remove (Semantic clutter removal)
│   ├── Rearrange (Depth-aware repositioning)
│   ├── Expand Scene (Generative environment extension)
│   └── Smart Cutout (Segment Anything Model - SAM)
│
├── 6. Video AI Engine
│   ├── Image → Video (Dynamic scene animation)
│   ├── First / Last Frame (Keyframe temporal morphing)
│   ├── Camera Motion (Pan, Tilt, Orbit, Zoom, Drone Flythrough)
│   ├── Animate Object (Isolated layer kinematics)
│   └── Video Restyle (Temporal coherent visual restyling)
│
└── 7. AI Assistant (Canvas Autonomous Agent)
    ├── Understand Canvas (Multimodal scene inspection & layout graph)
    ├── Understand Selection (Context analysis of selected nodes/layers)
    ├── Call Tools (Auto-execution of canvas operations: create, transform, layer)
    ├── Generate & Edit (Autonomous workflow execution)
    └── Arrange (Auto-alignment, smart grid, design cleanup)
```

---

## 3. Data Models

### 3.1 `AICapability` Enum
Extended to encompass all 30+ creative capabilities across the 7 sub-engines:
- **Generation**: `textToImage`, `sketchToImage`, `imageToImage`, `imageToVideo`, `referenceToImage`
- **Generative Editing**: `inpainting`, `outpainting`, `replaceObject`, `removeObject`, `addObject`, `backgroundReplace`
- **Transformation**: `styleTransfer`, `materialTransfer`, `relighting`, `recolor`, `restyle`
- **Enhancement**: `upscale`, `denoise`, `sharpen`, `restore`, `detailEnhancement`
- **Composition**: `populate`, `compositionRemove`, `rearrange`, `expandScene`, `smartCutout`
- **Video AI**: `videoFromImage`, `firstLastFrame`, `cameraMotion`, `animateObject`, `videoRestyle`
- **Assistant**: `understandCanvas`, `understandSelection`, `callTools`, `agentGenerate`, `agentEdit`, `agentArrange`

### 3.2 `AICreativeParams`
A flexible parameters payload supporting:
- `prompt` & `negativePrompt`
- `stylePreset` (e.g. Photorealistic Architecture, Clay Render, Cyberpunk, Watercolor, Anime)
- `denoisingStrength` (0.0 to 1.0)
- `controlNetType` & `controlNetStrength`
- `seedImageUrl`, `referenceImageUrl`, `maskBase64`
- `cameraMotionType` (Pan Left/Right, Zoom In/Out, Orbit, Tilt)
- `upscaleFactor` (2x, 4x, 8x)
- `relightingPreset` (Golden Hour, Cyberpunk Neon, Studio Softbox, Dramatic Sun)
- `entourageCategory` (People, Vehicles, Foliage, Furniture)

---

## 4. REST API & Remote Backend Protocol
The remote backend service communicates via standard REST/JSON endpoints:
1. `POST /v1/ai/generate` — Starts async generation or manipulation jobs.
2. `POST /v1/ai/vision/analyze` — Multimodal vision analysis for canvas understanding.
3. `POST /v1/ai/agent/action` — AI Agent function calling & canvas tool execution.
4. `GET /v1/ai/jobs/{id}` — Task polling for video & diffusion progress.

---

## 5. UI Integration
1. **AI Creative Studio Panel (`AICreativeStudioPanel`)**:
   - Tabbed categorized navigation: Generation, Edit & Inpaint, Visual Transform, Enhance, Composition, Video AI, and AI Assistant.
   - Live parameter sliders, reference image picker, style preset tiles, camera motion directional pads.
2. **Infinite Canvas Context Menu & Quick Bar**:
   - One-click trigger for "Generative Fill", "Architectural Upscale", "Segment & Cutout", and "Animate Scene".
3. **Drawing Studio Interop**:
   - Direct export of active stroke layers as Sketch/ControlNet input.
   - Sending selection masks (Lasso / Wand) directly to Inpainting / Generative Fill.
   - Injecting AI generation results as new Drawing Layers or Canvas Nodes.
