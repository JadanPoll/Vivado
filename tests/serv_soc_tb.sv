// Targeted integration test: actual SERV + Servile + Servant + ROM + GPIO.
// This does NOT substitute a synthetic CPU or hand-stub the memory bus.
// It checks only the first real firmware write; the long blink interval
// and silicon configuration require separate observation.
`timescale 1ns/1ps
module serv_soc_tb;
  reg clk = 0;
  reg BTN = 0;
  wire LED;
  top dut(.clk(clk), .BTN(BTN), .LED(LED));
  always #5 clk = ~clk; // 100 MHz Urbana clock

  integer cycles = 0;
  reg saw_fetch = 0;
  reg saw_boot_word = 0;
  reg saw_next_instruction = 0;
  reg saw_gpio_store = 0;

  always @(posedge clk) begin
    cycles = cycles + 1;
    if (!dut.cpu_reset) begin
      if (dut.soc.dbg_mem_ack) begin
        saw_fetch = 1;
        if (dut.soc.dbg_mem_adr == 32'h00000000) begin
          if (dut.soc.dbg_mem_rdt !== 32'h40000537)
            $fatal(1,"ROM mismatch at PC=0: observed %h, expected 40000537",dut.soc.dbg_mem_rdt);
          saw_boot_word = 1;
          $display("SERV: reset fetch ACK and correct first ROM word at cycle %0d",cycles);
        end
        if (dut.soc.dbg_mem_adr == 32'h00000004)
          saw_next_instruction = 1;
      end
      if (dut.soc.dbg_gpio_store) begin
        saw_gpio_store = 1;
        if (!saw_boot_word || !saw_next_instruction)
          $fatal(1,"GPIO store without confirmed ROM fetch and PC advancement");
        if (dut.soc.wb_gpio_dat !== 1'b0)
          $fatal(1,"First GPIO write should be zero, observed %b",dut.soc.wb_gpio_dat);
        $display("SERV: CPU GPIO store observed at cycle %0d, address %h",cycles,dut.soc.wb_ext_adr);
        #1;
        if (LED !== 1'b0)
          $fatal(1,"GPIO output did not reflect CPU store (LED=%b)",LED);
        $display("PASS: reset -> BRAM instruction -> fetch ACK -> PC progress -> MMIO GPIO -> LED");
        $finish;
      end
    end
    if(cycles > 20000)
      $fatal(1,"Timeout at %0d cycles: fetch=%b boot=%b advance=%b gpio=%b pc=%h ack=%b",
             cycles,saw_fetch,saw_boot_word,saw_next_instruction,saw_gpio_store,
             dut.soc.wb_mem_adr,dut.soc.wb_mem_ack);
  end
endmodule
