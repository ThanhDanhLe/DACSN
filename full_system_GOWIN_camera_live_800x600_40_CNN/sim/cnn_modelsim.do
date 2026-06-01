if {[file exists sim/work_cnn]} {
    vdel -lib sim/work_cnn -all
}
vlib sim/work_cnn

vlog -work sim/work_cnn -f sim/cnn_tests.prj

vsim -onfinish stop -lib sim/work_cnn tb_leaf_cnn_helpers
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_leaf_cnn_index_helpers
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_leaf_mnist_helpers
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_digit_to_7seg
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_sevenseg_digit_overlay
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_cdc_result_class_latch
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_camera_live_state_flow
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_streaming_mnist_capture_equivalence
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_mnist28_upscale_renderer
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_cnn_param_streamer
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_cnn_compute_lwdd
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_cnn_system
run -all
quit -sim

vsim -onfinish stop -lib sim/work_cnn tb_cnn_reduced_top_integration
run -all
quit -sim

quit -f
