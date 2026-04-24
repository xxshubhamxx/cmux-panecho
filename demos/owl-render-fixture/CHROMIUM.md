# Chromium host notes

The verified AWS host is `cmux-aws-mac` at Chromium checkout `~/chromium/src`,
base commit `0bd9366db7`.

The Swift verifier expects a Chromium build with:

- `fresh_owl/owl_fresh_bridge.*`, exposing a C ABI that launches Content Shell
  through Mojo and forwards `OwlFreshHost` events into Swift callbacks.
- `content/shell/browser/owl_fresh_host_mac.mm`, implementing the host-side
  Mojo service and publishing compositor context ids.
- `ui/accelerated_widget_mac/owl_fresh_context.*`, storing the latest
  browser-process relay `CAContext` id for the shell host to publish.
- `ui/accelerated_widget_mac/display_ca_layer_tree.*`, creating a
  browser-process relay `CAContext` that wraps Chromium's GPU-process
  compositor `CAContext`.

The relay is important. Publishing the GPU-process context id directly produced
blank Swift `CALayerHost` windows. The passing path publishes the browser-process
relay context id and lets Swift retarget its `CALayerHost.contextId` when Mojo
reports a newer id.

The AWS build used for the current screenshots was rebuilt with:

```bash
cd ~/chromium/src
third_party/ninja/ninja -C out/Release content_shell owl_fresh_bridge
```
