if {[file exists sim/work_mnist28]} {
    vdel -lib sim/work_mnist28 -all
}
vlib sim/work_mnist28

vlog -work sim/work_mnist28 src/leaf_cells/leaf_addr_28_mul_shiftadd.v
vlog -work sim/work_mnist28 src/video/mnist28_row_cache_bridge.v
vlog -work sim/work_mnist28 src/video/mnist_display_buffer.v
vlog -work sim/work_mnist28 src/video/mnist28_upscale_renderer.v
vlog -work sim/work_mnist28 sim/tb_mnist28_upscale_renderer.v

vsim -onfinish stop -lib sim/work_mnist28 tb_mnist28_upscale_renderer
run -all
quit -f
