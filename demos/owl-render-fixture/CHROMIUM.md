# Chromium host notes

The verified AWS host is `cmux-aws-mac` at Chromium checkout `~/chromium/src`,
base commit `0bd9366db7`.

`chromium-patches/aws-m1-ultra-verified-owl-host.patch` captures the exact
dirty Chromium working tree that produced the verified artifacts. It is a
checkpoint patch, not an upstream-ready Chromium change. Keep it until the
Chromium work is split into a smaller proper branch.

The Swift verifier expects a Chromium build with:

- `fresh_owl/owl_fresh_mojo_runtime.*`, exposing one generic Mojo invocation
  entry point that launches Content Shell through Mojo, binds `OwlFreshSession`,
  and then binds child remotes for profile, web view, input, surface tree, and
  native surfaces before returning `OwlFreshClient` events into Swift callbacks.
- `content/shell/browser/owl_fresh_host_mac.mm`, implementing the host-side
  Mojo service, input forwarding, capture diagnostics, and compositor context
  publication.
- `ui/accelerated_widget_mac/owl_fresh_context.*`, storing the latest
  browser-process portal `CAContext` id for the shell host to publish.
- `ui/accelerated_widget_mac/display_ca_layer_tree.*`, presenting Chromium's
  compositor `CAContext` inside that browser-process portal.

The portal is important. Publishing the GPU-process context id directly produced
blank Swift `CALayerHost` windows. The passing path publishes a browser-process
portal context id, hosts Chromium's compositor `CAContext` inside that portal,
then Swift hosts the portal id in `CALayerHost`.

`Mojo/OwlFresh.mojom` is the Swift-side source of truth for `OwlFreshClient`,
`OwlFreshSession`, and the child `OwlFreshProfile`, `OwlFreshWebView`,
`OwlFreshInput`, `OwlFreshSurfaceTreeHost`, and `OwlFreshNativeSurfaceHost`
surfaces. `OwlMojoBindingsGenerator` emits
`Sources/OwlMojoBindingsGenerated/OwlFresh.generated.swift`, and the verifier
uses those generated Swift request/event and transport types before invoking
the generic Mojo runtime. Host control no longer calls per-method C symbols.

The verified gate now includes input. `run-layer-host-verifier-gui.sh` can run
the real Chromium compositor input fixtures with `OWL_LAYER_HOST_INPUT_CHECK=1`;
the passing output shows `OWL_INPUT_READY` turning into `OWL_INPUT_CLICKED`,
then proves form input by typing `hello owl`, checking a checkbox, clicking
submit, and asserting the post-input DOM state through Mojo. It also verifies
Command, Option, Control, and Shift modifier delivery while a text input is
focused. Mouse events use Chromium's routed input path so controls activate
normally. The gate still rejects DevTools and remote debugging paths.
The scroll fixture now requires Chromium to land on a specific numbered content
row, and the text fixture verifies caret editing plus Shift-Arrow selection
replacement in one rendered page.

The AWS build used for the current screenshots was rebuilt with:

```bash
cd ~/chromium/src
third_party/ninja/ninja -C out/Release content_shell owl_fresh_mojo_runtime
```
