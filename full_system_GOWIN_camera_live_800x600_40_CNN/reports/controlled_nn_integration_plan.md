# Controlled NN Integration Plan

Date: 2026-05-24

## Gate Conditions

NN integration is allowed only after:

1. 784-pixel capture export works on board.
2. Python dump inference workflow is used on real captures.
3. Preload packer TB remains passing.
4. A resource variant places successfully.
5. Debug UART/readback is disabled or reduced enough to recover CLS margin.

Current status: blocked by resource/placement.

## Planned Data Path

```text
capture_done
  -> streaming_mnist_preload_packer reads dual-clock MNIST RAM
  -> 392 preload words feed nn_system image preload interface
  -> nn_system streams params from SPI flash offset 0x200000
  -> result_class latched
  -> simple result output only
```

## Initial Output Options

Preferred, cheapest first:

1. UART print result if the UART dump path is still present.
2. LED/debug bits if board routing is available.
3. Small seven-seg-style HDMI digit only after the NN path works.

Do not add:

- processed 28x28 preview,
- bit boxes,
- heavy renderer overlay,
- new filters,
- new NN buffers if the current dual-clock RAM can be reused.

## Resource Strategy

Before the next P&R attempt:

- set `DEBUG_DUMP_ENABLE=0` or remove UART dump logic from the NN variant,
- keep only the preload packer and a small result output,
- reuse the existing MNIST RAM,
- verify that BSRAM remains at 10/10 or less,
- reject the branch if placement still fails.
