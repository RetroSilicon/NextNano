# Creates and names the new project, sets the directory, and defines the FPGA part number
# create_project -name nanoNext -dir ./nanoNextProject -pn GW2AR-LV18QN88C8/I7 -device_version C -force

set_device GW2AR-LV18QN88C8/I7 -name GW2AR-18C -device_version C

add_file tang/bram_gowin_filled_single_clock.vhd
add_file tang/gowin_rpll.vhd

add_file audio/ym2149.vhd
add_file audio/turbosound.vhd
add_file audio/soundrive.vhd
add_file audio/i2s.vhd
add_file audio/audio_mixer.vhd
add_file audio/i2s/i2s_transmit.vhd
add_file audio/i2s/i2s_slave.vhd
add_file audio/i2s/i2s_receive.vhd
add_file audio/i2s/i2s_master.vhd

add_file cpu/t80na_ce.vhd

add_file cpu/t80n_pack.vhd
add_file cpu/t80n_mcode.vhd
add_file cpu/t80n_alu.vhd
add_file cpu/t80n.vhd
add_file device/multiface.vhd
add_file device/dma.vhd
add_file device/divmmc.vhd
add_file device/copper.vhd
add_file device/im2_control.vhd
add_file device/im2_device.vhd
add_file device/im2_peripheral.vhd
add_file device/peripherals.vhd

add_file input/keyboard/keymaps.vhd
add_file misc/debounce.vhd
add_file video/zxula_timing.vhd
add_file video/zxula.vhd
add_file video/tilemap.vhd
add_file video/sprites.vhd
add_file video/lores.vhd
add_file video/layer2.vhd
add_file serial/uart.vhd
add_file serial/uart_rx.vhd
add_file serial/uart_tx.vhd

add_file serial/spi_master_next_CE.vhd

add_file serial/fifop.vhd

add_file rom/bootrom.vhd

add_file device/ctc_chan.vhd
add_file device/ctc.vhd

add_file zxnext.vhd

add_file mister/zxnext_top_02.vhd

add_file tang/ZXNext_tang.sv

add_file sdram/ram_wrapper.sv

add_file video/scand2.sv
add_file tang/pcm_to_i2s.v
add_file usb/usb_keyboard.vhd
add_file usb/fpga_companion.v
add_file usb/hid.v
add_file usb/mcu_spi_new.v
add_file usb/sys_ctrl.v

add_file video/hdmi/encoder.vhd
add_file video/hdmi/hdmi_framer_gowin_test.v
add_file video/hdmi/hdmi.vhd
add_file video/hdmi/hdmidataencoder.v
add_file video/hdmi/hdmidelay.vhd
add_file video/hdmi/hdmi_out_gowin.v
add_file tang/hdmi_rpll.v

add_file nextNano.cst

add_file nextNano.sdc

add_file zxNano.gsc

set_option -synthesis_tool gowinsynthesis
set_option -output_base_name nextNano
set_option -verilog_std sysv2017
set_option -vhdl_std vhd2008
set_option -top_module ZXNext_tang
set_option -use_mspi_as_gpio 0
set_option -use_sspi_as_gpio 1
set_option -print_all_synthesis_warning 0
set_option -rw_check_on_ram 1

set_option -correct_hold_violation 0
set_option -place_option 2
set_option -route_option 1
set_option -ioreg_in_iob 1

set_option -gen_text_timing_rpt 1
set_option -gen_posp 1
set_option -gen_sdf 1


run all


