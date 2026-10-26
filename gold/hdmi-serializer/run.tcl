set script_dir [file dirname [file normalize [info script]]]
set out_root [file join $script_dir output]
file mkdir $out_root

set cases {}
set experiment "seed"
if {[llength $argv] > 0} {
    set experiment [lindex $argv 0]
} elseif {[info exists ::env(FRONTIER_EXPERIMENT)]} {
    set experiment $::env(FRONTIER_EXPERIMENT)
}
if {$experiment eq "tq_buf"} {
    # One-variable experiment selected by frontier/investigate.py. The existing
    # width-10/divide-1 DDR specimen is the control; do not rerun the matrix.
    lappend cases [list 10 1 BUF oserdes10_bufr1_tqbuf]
    set summary_name summary-tqbuf.tsv
} elseif {$experiment eq "seed"} {
    foreach width {8 10} {
        foreach divide {1 2 4} {
            lappend cases [list $width $divide DDR "oserdes${width}_bufr${divide}"]
        }
    }
    set summary_name summary.tsv
} else {
    error "Unknown FRONTIER_EXPERIMENT=$experiment (expected seed or tq_buf)"
}

set summary [open [file join $out_root $summary_name] w]
puts $summary "case\tstatus\tdetail"

foreach case $cases {
        lassign $case width divide tq_rate name
        set out [file join $out_root $name]
        file mkdir $out
        set status PASS
        set detail ok
        if {[catch {
            create_project -in_memory -part xc7s50csga324-1
            read_verilog [file join $script_dir top.v]
            read_xdc [file join $script_dir top.xdc]
            synth_design -top top -part xc7s50csga324-1 \
                -generic DATA_WIDTH=$width -generic BUFR_DIVIDE=$divide \
                -generic DATA_RATE_TQ=$tq_rate
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
close $summary
exit
