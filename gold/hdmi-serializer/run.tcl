set script_dir [file dirname [file normalize [info script]]]
set out_root [file join $script_dir output]
file mkdir $out_root
set summary [open [file join $out_root summary.tsv] w]
puts $summary "case\tstatus\tdetail"

foreach width {8 10} {
    foreach divide {1 2 4} {
        set name "oserdes${width}_bufr${divide}"
        set out [file join $out_root $name]
        file mkdir $out
        set status PASS
        set detail ok
        if {[catch {
            create_project -in_memory -part xc7s50csga324-1
            read_verilog [file join $script_dir top.v]
            read_xdc [file join $script_dir top.xdc]
            synth_design -top top -part xc7s50csga324-1 \
                -generic DATA_WIDTH=$width -generic BUFR_DIVIDE=$divide
            opt_design
            place_design
            route_design
            write_checkpoint -force [file join $out routed.dcp]
            write_bitstream -force [file join $out golden.bit]
            report_route_status -file [file join $out route-status.txt]
            report_timing_summary -file [file join $out timing.txt]
            report_drc -file [file join $out drc.txt]
            set fh [open [file join $out cells.tsv] w]
            puts $fh "cell\tref\tloc\tbel"
            foreach c [get_cells -hierarchical] {
                puts $fh "$c\t[get_property REF_NAME $c]\t[get_property LOC $c]\t[get_property BEL $c]"
            }
            close $fh
            set fh [open [file join $out routed-pips.txt] w]
            foreach p [get_pips -of_objects [get_nets -hierarchical]] { puts $fh $p }
            close $fh
            close_project
        } err opts]} {
            set status FAIL
            set detail [string map {"\n" " | " "\t" " "} $err]
            set fh [open [file join $out failure.txt] w]
            puts $fh $err
            puts $fh $opts
            close $fh
            catch {close_project}
        }
        puts $summary "$name\t$status\t$detail"
        flush $summary
    }
}
close $summary
exit
