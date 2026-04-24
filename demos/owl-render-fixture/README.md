# OWL render fixture

This verifier is the first visual gate for the OWL effort. It launches a Chromium host executable on macOS, renders deterministic HTML fixtures, writes PNG artifacts, and checks pixel colors in the captured images.

`OwlLayerHostVerifier` is the current first architecture gate. Swift loads the OWL bridge dylib, launches Content Shell through Mojo, waits for Chromium to publish a browser-process portal `CAContext` id over Mojo, hosts that id in a native `CALayerHost`, screenshots the Swift-owned host window, and checks the pixels. `Scripts/run-layer-host-fixture-verifier-gui.sh` uses a Chromium-owned layer fixture context to prove the Mojo plus native display plumbing. `Scripts/run-layer-host-verifier-gui.sh` uses the real Chromium compositor portal and runs a deterministic canvas fixture plus `https://example.com/` by default. Set `OWL_LAYER_HOST_INPUT_CHECK=1` to also verify real mouse/key input changes web content from `OWL_INPUT_READY` to `OWL_INPUT_CLICKED`.

`OwlLayerHostSelfTest` is the smallest local rendering gate. Direct mode draws deterministic red, green, blue, and text layers into a normal Swift layer-backed `NSWindow`, proving the window capture environment. Layer-host mode creates a private `CAContext` in Swift, draws the same layers into it, hosts that context in the same Swift `CALayerHost` window path, screenshots the window, and checks the pixels. This isolates whether `CAContext` plus `CALayerHost` plus screenshot capture works before involving Chromium.

On the AWS Mac, visual LayerHost checks must run from the logged-in Aqua bootstrap, not as direct SSH children. SSH-launched windows show up in `CGWindowList`, but WindowServer can return black screenshots. Use `Scripts/run-layer-host-self-test-gui.sh` for the direct plus same-process `CAContext` gates, `Scripts/run-layer-host-fixture-verifier-gui.sh` for the Chromium-owned fixture gate, and `Scripts/run-layer-host-verifier-gui.sh` for the real Chromium compositor gate.

Run on the AWS M1 Ultra host:

For the native Swift display-path gate:

```bash
cd ~/cmux-owl-render-fixture
./Scripts/run-layer-host-self-test-gui.sh
```

Artifacts are written to `artifacts/layer-host-self-test-gui-latest/`.

For the Chromium-owned fixture gate:

```bash
cd ~/cmux-owl-render-fixture
./Scripts/run-layer-host-fixture-verifier-gui.sh
```

Artifacts are written to `artifacts/layer-host-fixture-gui-latest/`.

For the real Chromium compositor gate:

```bash
cd ~/cmux-owl-render-fixture
./Scripts/run-layer-host-verifier-gui.sh
```

Artifacts are written to `artifacts/layer-host-gui-latest/`.

For the real Chromium compositor plus input gate:

```bash
cd ~/cmux-owl-render-fixture
OWL_LAYER_HOST_INPUT_CHECK=1 ./Scripts/run-layer-host-verifier-gui.sh
```

The input run writes both `input-fixture-before-click.png` and
`input-fixture-after-click.png`.
