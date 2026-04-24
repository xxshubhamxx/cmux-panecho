# Chromium host notes

The verified AWS host is `cmux-aws-mac` at Chromium checkout `~/chromium/src`,
base commit `0bd9366db7`.

`chromium-patches/aws-m1-ultra-verified-owl-host.patch` captures the exact
dirty Chromium working tree that produced the verified artifacts. It is a
checkpoint patch, not an upstream-ready Chromium change. Keep it until the
Chromium work is split into a smaller proper branch.

The Swift verifier expects a Chromium build with:

- `fresh_owl/owl_fresh_bridge.*`, exposing a C ABI that launches Content Shell
  through Mojo and forwards `OwlFreshHost` events into Swift callbacks.
- `content/shell/browser/owl_fresh_host_mac.mm`, implementing the host-side
  Mojo service, input forwarding, capture diagnostics, and compositor context
  publication.
- `ui/accelerated_widget_mac/owl_fresh_context.*`, storing the latest
  browser-process portal `CAContext` id for the shell host to publish.
- `ui/accelerated_widget_mac/display_ca_layer_tree.*`, exporting Chromium's
  browser-process display layer subtree through that portal.

The portal is important. Publishing the GPU-process context id directly produced
blank Swift `CALayerHost` windows. The passing path publishes a browser-process
portal context id and keeps that portal pointed at Chromium's display layer
subtree, then Swift hosts the portal id in `CALayerHost`.

The verified gate now includes input. `run-layer-host-verifier-gui.sh` can run
the real Chromium compositor input fixture with `OWL_LAYER_HOST_INPUT_CHECK=1`;
the passing output shows `OWL_INPUT_READY` turning into `OWL_INPUT_CLICKED`
through Mojo mouse/key forwarding, with no DevTools or remote debugging path.

The AWS build used for the current screenshots was rebuilt with:

```bash
cd ~/chromium/src
third_party/ninja/ninja -C out/Release content_shell owl_fresh_bridge
```
