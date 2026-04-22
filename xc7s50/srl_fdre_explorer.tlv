\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
\SV
   m5_makerchip_module
\TLV
   // =============================================================================
   // SRL16E + FDRE FAMILY EXPLORER
   // Teaches: shift register primitives, flip-flop variants, reset types,
   //          CE behavior, INIT parameter, resource comparison
   // XC7S50 / Vivado context
   // =============================================================================

   |shift
      @1
         $reset = *reset;
         $data_in = *cyc_cnt[0];
         $tap_addr[4:0] = *cyc_cnt[9:5];
         $shift_reg[31:0] = $reset ? 32'b0 : {$shift_reg[30:0], $data_in};
         $tap_out = $shift_reg[$tap_addr];
         $q15 = $shift_reg[15];
         $q31 = $shift_reg[31];
         `BOGUS_USE($tap_out $q15 $q31)

   |ffreg
      @1
         $reset = *reset;
         $data_in[7:0] = *cyc_cnt[7:0];
         $ce = (*cyc_cnt[2:0] != 3'b111);
         $fdre_q[7:0] = $reset ? 8'b0 : $ce ? $data_in : >>1$fdre_q;
         $fdce_q[7:0] = $reset ? 8'b0 : $data_in;
         $init_val[7:0] = 8'hAB;
         `BOGUS_USE($fdre_q $fdce_q $init_val)

   *passed = *cyc_cnt > 300;
   *failed = 1'b0;

   /viz
      \viz_js
         box: {width: 1550, height: 950, fill: "#0a0a0a"},

         init() {
            const self = this;
            const VI = {};
            this._VI = VI;

            VI._labels    = {};
            VI._objects   = {};
            VI._clickZones = [];

            VI.redraw = function() {
               if (self._viz && self._viz.pane) {
                  self._viz.pane.unrender();
                  self._viz.pane.render();
               }
               self.getCanvas().renderAll();
            };

            const canvasEl = fabric.document.querySelector("canvas");
            VI.toCanvasCoords = function(cx, cy) {
               if (!canvasEl) return {x: 0, y: 0};
               const r = canvasEl.getBoundingClientRect();
               const vpt = self.getCanvas().viewportTransform || [1, 0, 0, 1, 0, 0];
               return {
                  x: Math.round((cx - r.left - vpt[4]) / vpt[0]),
                  y: Math.round((cy - r.top  - vpt[5]) / vpt[3])
               };
            };

            VI.label = function(id, text, x, y, color, fz, ff, align) {
               const c = self.getCanvas();
               const txt = String(text);
               if (!VI._labels[id]) {
                  const obj = new fabric.Text(txt, {
                     left: x, top: y,
                     fontSize: fz || 12,
                     fill: color || "#e0e0e0",
                     selectable: false, evented: false,
                     fontFamily: ff || "monospace",
                     originX: align || "left"
                  });
                  c.add(obj);
                  VI._labels[id] = obj;
               } else {
                  VI._labels[id].set({text: txt, left: x, top: y});
                  if (color) VI._labels[id].set("fill", color);
                  if (fz)    VI._labels[id].set("fontSize", fz);
               }
            };

            VI.rect = function(id, x, y, w, h, fill, stroke, sw, rx) {
               const c  = self.getCanvas();
               const fw = Math.max(w, 1);
               const fh = Math.max(h, 1);
               if (!VI._objects[id]) {
                  const obj = new fabric.Rect({
                     left: x, top: y, width: fw, height: fh,
                     fill: fill || "#333",
                     stroke: stroke || "transparent",
                     strokeWidth: sw || 0,
                     rx: rx || 0, ry: rx || 0,
                     selectable: false, evented: false
                  });
                  c.add(obj);
                  VI._objects[id] = obj;
               } else {
                  VI._objects[id].set({left: x, top: y, width: fw, height: fh});
                  if (fill)   VI._objects[id].set("fill",   fill);
                  if (stroke) VI._objects[id].set("stroke", stroke);
               }
            };

            VI.onClick = function(id, x, y, w, h, cb) {
               VI._clickZones = VI._clickZones.filter(function(z) { return z.id !== id; });
               VI._clickZones.push({id: id, x: x, y: y, w: w, h: h, cb: cb});
            };

            VI.clearAll = function() {
               self.getCanvas().clear();
               self.getCanvas().selection = false;
               VI._labels     = {};
               VI._objects    = {};
               VI._clickZones = [];
            };

            fabric.document.addEventListener("mouseup", function(e) {
               const pos = VI.toCanvasCoords(e.clientX, e.clientY);
               VI._clickZones.forEach(function(z) {
                  if (pos.x >= z.x && pos.x <= z.x + z.w &&
                      pos.y >= z.y && pos.y <= z.y + z.h) {
                     z.cb(pos.x, pos.y);
                  }
               });
            });

            this._firstRender  = true;
            this._expSRL       = false;
            this._expSHREG     = false;
            this._expTap       = false;
            this._expTiming    = false;
            this._expFDCE      = false;
            this._expCE        = false;
         },

         onTraceData() {
            this._firstRender = true;
         },

         render() {
            const VI = this._VI; if (!VI) return;
            VI.clearAll();
            const pane = this._viz.pane;
            const wd   = pane.waveData;
            if (!wd) return;
            const cyc  = pane.cyc;

            const getSig = function(name, c, def) {
               try { return wd.getSignalValueAtCycleByName(name, c).asInt(def); } catch(e) { return def; }
            };

            const safeCyc = function(c) {
               return Math.max(wd.startCycle, Math.min(wd.endCycle, c));
            };

            const toHex2 = function(v) {
               return "0x" + (v & 0xFF).toString(16).toUpperCase().padStart(2, "0");
            };
            const toHex8 = function(v) {
               return "0x" + (v >>> 0).toString(16).toUpperCase().padStart(8, "0");
            };
            const toBin8 = function(v) {
               let s = "";
               for (let i = 7; i >= 0; i--) { s += ((v >> i) & 1).toString(); }
               return s;
            };

            // ================================================================
            // Live signals
            // ================================================================
            const shift_reg = getSig("TLV|shift$shift_reg", cyc, 0);
            const tap_addr  = getSig("TLV|shift$tap_addr",  cyc, 0);
            const tap_out   = getSig("TLV|shift$tap_out",   cyc, 0);
            const q15       = getSig("TLV|shift$q15",       cyc, 0);
            const q31       = getSig("TLV|shift$q31",       cyc, 0);
            const data_in   = getSig("TLV|shift$data_in",   cyc, 0);
            const fdre_q    = getSig("TLV|ffreg$fdre_q",    cyc, 0);
            const fdce_q    = getSig("TLV|ffreg$fdce_q",    cyc, 0);
            const ce        = getSig("TLV|ffreg$ce",        cyc, 1);
            const ff_din    = getSig("TLV|ffreg$data_in",   cyc, 0);
            const ff_rst    = getSig("TLV|ffreg$reset",     cyc, 0);

            // ================================================================
            // PANEL L: SRL16E / SRLC32E EXPLORER
            // x=10, y=10, w=755, h=930
            // ================================================================
            VI.rect("pl_bg", 10, 10, 755, 930, "#0d1117", "#2a4a6b", 2, 6);
            VI.label("pl_title", "SRL16E / SRLC32E  SHIFT REGISTER EXPLORER", 387, 18, "#4fc3f7", 13, "sans-serif", "center");

            // ---- 32-cell shift chain ----
            VI.rect("pl_chain_bg", 15, 38, 746, 94, "#06090d", "#334466", 1, 4);
            VI.label("pl_chain_t", "SRLC32E SHIFT CHAIN  (bit[0]=oldest, bit[31]=newest)", 387, 42, "#546e7a", 9, "sans-serif", "center");

            const CELL_W = 22;
            const CELL_H = 30;
            const CHAIN_X0 = 18;
            const CHAIN_Y0 = 55;

            // Data-in label + arrow
            VI.label("pl_din_l", "D_in=" + data_in, CHAIN_X0, CHAIN_Y0 - 14, data_in ? "#f44336" : "#4caf50", 9, "monospace");
            VI.rect("pl_din_arr", CHAIN_X0 + 54, CHAIN_Y0 + CELL_H / 2 - 1, 10, 2, data_in ? "#f44336" : "#4caf50");

            for (let ci = 0; ci < 32; ci++) {
               (function(i) {
                  const bit  = (shift_reg >> i) & 1;
                  const cx   = CHAIN_X0 + 64 + i * (CELL_W + 1);
                  const fill = bit ? "#1a3a1a" : "#0d0d1a";
                  const str  = bit ? "#4caf50" : "#2a3b5a";
                  VI.rect("pl_cell_" + i, cx, CHAIN_Y0, CELL_W, CELL_H, fill, str, 1, 2);
                  VI.label("pl_cbit_" + i, String(bit), cx + CELL_W / 2, CHAIN_Y0 + 9, bit ? "#4caf50" : "#546e7a", 9, "monospace", "center");
                  // Position label every 8 cells
                  if (i % 8 === 0 || i === 31 || i === 15) {
                     VI.label("pl_cidx_" + i, String(i), cx + CELL_W / 2, CHAIN_Y0 + CELL_H + 3, "#37474f", 7, "monospace", "center");
                  }
               })(ci);
            }

            // Shift direction arrow
            VI.rect("pl_sarr", CHAIN_X0 + 64, CHAIN_Y0 + CELL_H + 14, 703, 2, "#2a4a6b");
            VI.label("pl_sarrl", "shift direction ->", CHAIN_X0 + 64, CHAIN_Y0 + CELL_H + 18, "#2a4a6b", 8, "sans-serif");

            // ---- Programmable tap pointer ----
            const tapX = CHAIN_X0 + 64 + tap_addr * (CELL_W + 1) + CELL_W / 2;
            VI.rect("pl_tap_line", tapX - 1, CHAIN_Y0 + CELL_H, 2, 22, "#ff9800");
            VI.rect("pl_tap_tri",  tapX - 5, CHAIN_Y0 + CELL_H + 22, 10, 6, "#ff9800");
            VI.label("pl_tap_lbl", "A[4:0]=" + tap_addr, tapX, CHAIN_Y0 + CELL_H + 30, "#ff9800", 8, "monospace", "center");

            // Q15 and Q31 fixed output wires
            const q15x = CHAIN_X0 + 64 + 15 * (CELL_W + 1) + CELL_W / 2;
            const q31x = CHAIN_X0 + 64 + 31 * (CELL_W + 1) + CELL_W / 2;
            VI.rect("pl_q15_line", q15x - 1, CHAIN_Y0 - 14, 2, 14, "#81c784");
            VI.label("pl_q15_lbl", "Q15=" + q15, q15x, CHAIN_Y0 - 22, "#81c784", 8, "monospace", "center");
            VI.rect("pl_q31_line", q31x - 1, CHAIN_Y0 - 14, 2, 14, "#ce93d8");
            VI.label("pl_q31_lbl", "Q31=" + q31, q31x, CHAIN_Y0 - 22, "#ce93d8", 8, "monospace", "center");

            // TAP output display
            VI.rect("pl_tap_out_bg", 15, 148, 200, 48, "#100a00", "#ff9800", 2, 5);
            VI.label("pl_tap_out_t", "TAP OUTPUT  A=" + tap_addr, 115, 153, "#ff9800", 9, "monospace", "center");
            VI.label("pl_tap_out_v", String(tap_out), 115, 167, tap_out ? "#f44336" : "#4caf50", 18, "monospace", "center");
            VI.label("pl_sreg_hex",  toHex8(shift_reg), 230, 170, "#546e7a", 10, "monospace");

            // ---- Resource comparison ----
            VI.rect("pl_res_bg", 15, 204, 746, 130, "#070c07", "#334455", 1, 4);
            VI.label("pl_res_t", "RESOURCE COMPARISON", 387, 210, "#4fc3f7", 11, "sans-serif", "center");

            // 32 FDRE column
            VI.rect("pl_ff32_bg", 20, 226, 350, 100, "#0a0a0a", "#546e7a", 1, 4);
            VI.label("pl_ff32_t", "32 FDRE flip-flops", 195, 231, "#ffd54f", 10, "monospace", "center");
            for (let fi = 0; fi < 32; fi++) {
               (function(i) {
                  const fx = 26 + (i % 16) * 20;
                  const fy = 244 + Math.floor(i / 16) * 22;
                  VI.rect("pl_ffbox_" + i, fx, fy, 14, 16, "#0d2035", "#4fc3f7", 1, 2);
                  VI.label("pl_fflbl_" + i, "F", fx + 7, fy + 3, "#4fc3f7", 8, "monospace", "center");
               })(fi);
            }
            VI.label("pl_ff32_cost", "32 BEL sites consumed", 195, 295, "#f44336", 8, "sans-serif", "center");
            VI.label("pl_ff32_sub",  "8 FFs per Slice = 4 Slices minimum", 195, 306, "#546e7a", 7, "sans-serif", "center");

            // 1 SRLC32E column
            VI.rect("pl_srl1_bg", 380, 226, 375, 100, "#0a0a0a", "#546e7a", 1, 4);
            VI.label("pl_srl1_t", "1 SRLC32E", 567, 231, "#ffd54f", 10, "monospace", "center");
            VI.rect("pl_srl1_box", 450, 244, 234, 40, "#0d2035", "#81c784", 2, 4);
            VI.label("pl_srl1_lbl", "SRLC32E", 567, 250, "#81c784", 12, "monospace", "center");
            VI.label("pl_srl1_sub", "LUT6 configured as SRL", 567, 265, "#546e7a", 8, "sans-serif", "center");
            VI.label("pl_srl1_cost", "1 BEL site consumed (SliceM only)", 567, 295, "#4caf50", 8, "sans-serif", "center");
            VI.label("pl_srl1_sub2", "SliceL cannot implement SRL", 567, 306, "#546e7a", 7, "sans-serif", "center");

            // Ratio label
            VI.rect("pl_ratio_bg", 20, 310, 746, 18, "#0a1500", "#4caf50", 1, 3);
            VI.label("pl_ratio_l", "32x BEL area reduction  |  8x Slice reduction  |  All 32 depths available via A[4:0] address", 387, 313, "#4caf50", 9, "monospace", "center");

            // ---- RESET LIMITATION warning ----
            VI.rect("pl_rst_bg", 15, 342, 746, 96, "#100505", "#f44336", 2, 5);
            VI.label("pl_rst_t",  "CRITICAL: SRL HAS NO RESET INPUT", 387, 349, "#f44336", 12, "sans-serif", "center");
            VI.label("pl_rst_1",  "SRL16E and SRLC32E primitives have NO synchronous and NO asynchronous reset.", 387, 365, "#ef9a9a", 9, "sans-serif", "center");
            VI.label("pl_rst_2",  "If synthesis infers SRL from a shift register that has a reset condition,", 387, 377, "#ef9a9a", 9, "sans-serif", "center");
            VI.label("pl_rst_3",  "the reset logic is SILENTLY DROPPED by Vivado. This is a functional bug.", 387, 389, "#f44336", 9, "sans-serif", "center");
            VI.rect("pl_rst_fix", 20, 403, 746, 16, "#1a0000", "#ff9800", 1, 3);
            VI.label("pl_rst_fix1","(* SHREG_EXTRACT = \"no\" *) -- prevents SRL inference, forces FDRE chain", 387, 406, "#ff9800", 9, "monospace", "center");
            VI.label("pl_rst_4",  "Use FDRE chain when reset is required. Use SRL only for reset-free delay lines.", 387, 423, "#78909c", 8, "sans-serif", "center");

            // ---- INIT parameter ----
            VI.rect("pl_init_bg", 15, 446, 746, 68, "#070712", "#7e57c2", 1, 4);
            VI.label("pl_init_t",  "INIT PARAMETER: configuration-time preload", 387, 452, "#b39ddb", 10, "sans-serif", "center");
            VI.label("pl_init_1",  "INIT[31:0] = 32'hDEADBEEF  -- SRL powers up with this content in bit cells", 387, 466, "#ce93d8", 9, "monospace", "center");
            VI.label("pl_init_2",  "Bit[0] = INIT[0] (first output), Bit[31] = INIT[31] (last in chain).", 387, 477, "#9c27b0", 8, "sans-serif", "center");
            VI.label("pl_init_3",  "INIT is useful for delay-line initialization or known startup states.", 387, 488, "#7e57c2", 8, "sans-serif", "center");
            VI.label("pl_init_4",  "Current shift_reg = " + toHex8(shift_reg) + "  (live, cycles from reset)", 387, 500, "#546e7a", 8, "monospace", "center");

            // ---- Cascade connection ----
            VI.rect("pl_casc_bg", 15, 522, 746, 80, "#07070a", "#334466", 1, 4);
            VI.label("pl_casc_t",  "CASCADE FOR 64-BIT DEPTH:  SRLC32E.Q31 -> SRLC32E.D", 387, 528, "#4fc3f7", 10, "sans-serif", "center");

            VI.rect("pl_casc_s1", 30, 544, 120, 36, "#0d2035", "#4fc3f7", 2, 4);
            VI.label("pl_casc_s1t", "SRLC32E #1", 90, 548, "#4fc3f7", 9, "monospace", "center");
            VI.label("pl_casc_s1d", "depth 0-31", 90, 560, "#546e7a", 7, "sans-serif", "center");
            VI.rect("pl_casc_arr", 150, 559, 60, 2, "#ce93d8");
            VI.label("pl_casc_q31", "Q31", 165, 550, "#ce93d8", 8, "monospace");
            VI.rect("pl_casc_s2", 210, 544, 120, 36, "#0d2035", "#81c784", 2, 4);
            VI.label("pl_casc_s2t", "SRLC32E #2", 270, 548, "#81c784", 9, "monospace", "center");
            VI.label("pl_casc_s2d", "depth 32-63", 270, 560, "#546e7a", 7, "sans-serif", "center");
            VI.label("pl_casc_a1",  "A[4:0] on each SRL selects tap within its 32-cell window.", 540, 548, "#546e7a", 8, "sans-serif");
            VI.label("pl_casc_a2",  "No additional routing: Q31 is the dedicated cascade output.", 540, 559, "#37474f", 8, "sans-serif");
            VI.label("pl_casc_a3",  "SRL16E uses Q15 as cascade. SRLC32E uses Q31.", 540, 570, "#37474f", 8, "sans-serif");
            VI.label("pl_casc_a4",  "Both share the same SliceM LUT BEL.", 540, 581, "#263238", 7, "sans-serif");

            // ---- Waveform strip: last 20 cycles shift_reg LSB ----
            VI.rect("pl_wave_bg", 15, 610, 746, 80, "#06090c", "#334466", 1, 4);
            VI.label("pl_wave_t",  "SHIFT REGISTER WAVEFORM  (last 20 cycles, bits [7:0])", 387, 616, "#4fc3f7", 9, "sans-serif", "center");

            const WL_X0   = 20;
            const WL_CW   = 35;
            const WL_ROWS = 20;
            const WL_Y0   = 630;

            for (let wi = 0; wi < WL_ROWS; wi++) {
               (function(i) {
                  const wc  = safeCyc(cyc - (WL_ROWS - 1 - i));
                  const wb  = getSig("TLV|shift$shift_reg", wc, 0) & 0xFF;
                  const isc = (wc === cyc);
                  const wx  = WL_X0 + i * WL_CW;
                  VI.rect("pl_wv_bg_" + i, wx, WL_Y0, WL_CW - 1, 50, isc ? "#101820" : "#06090c", isc ? "#4fc3f7" : "#1a2a3a", 1, 0);
                  for (let b = 0; b < 8; b++) {
                     (function(bit) {
                        const bv   = (wb >> bit) & 1;
                        const bx   = wx + (WL_CW - 1) / 8 * bit;
                        const bfill = bv ? "#1a3a1a" : "#0d0d1a";
                        VI.rect("pl_wvb_" + i + "_" + bit, bx, WL_Y0 + 2, Math.max(Math.floor((WL_CW - 1) / 8), 1), 20, bfill, bv ? "#4caf50" : "#1a2a3a", 1, 0);
                     })(b);
                  }
                  VI.label("pl_wvc_" + i, String(wc), wx + WL_CW / 2, WL_Y0 + 62, "#37474f", 7, "monospace", "center");
               })(wi);
            }
            VI.label("pl_wave_legend", "Each column = 1 cycle. Green bit = 1, dark = 0. Rightmost column = current.", 387, 690, "#37474f", 7, "sans-serif", "center");

            // ---- Clickable expanders ----
            const self = this;

            // [1] SRL vs FF chain
            VI.rect("pl_exp1_btn", 15, 700, 746, 16, this._expSRL ? "#0e1a0e" : "#07100a", this._expSRL ? "#4caf50" : "#335533", 1, 3);
            VI.label("pl_exp1_lbl", (this._expSRL ? "[-]" : "[+]") + " When to use SRL vs FF chain", 20, 702, "#81c784", 8, "monospace");
            VI.onClick("pl_exp1_btn", 15, 700, 746, 16, function() { self._expSRL = !self._expSRL; VI.redraw(); });
            if (this._expSRL) {
               VI.rect("pl_exp1_bg", 15, 717, 746, 58, "#05100a", "#335533", 1, 3);
               VI.label("pl_e1l1", "USE SRL:  pure delay line (FIFO, pipeline bubble), no reset needed, depth > 4.", 387, 720, "#81c784", 8, "sans-serif", "center");
               VI.label("pl_e1l2", "USE FF chain:  reset required, CE per-stage needed, timing visibility important.", 387, 731, "#81c784", 8, "sans-serif", "center");
               VI.label("pl_e1l3", "USE FF chain:  multi-tap access (SRL only has one addressable tap output).", 387, 742, "#ffd54f", 8, "sans-serif", "center");
               VI.label("pl_e1l4", "SRL timing: CLK-to-Q same as FF. Setup/hold same as FF. Address adds mux delay.", 387, 753, "#546e7a", 8, "sans-serif", "center");
               VI.label("pl_e1l5", "SRL depth 1-16 uses SRL16E (1 LUT). Depth 17-32 uses SRLC32E (1 LUT).", 387, 764, "#37474f", 7, "sans-serif", "center");
            }

            // [2] SHREG_EXTRACT
            const e2Y = this._expSRL ? 776 : 718;
            VI.rect("pl_exp2_btn", 15, e2Y, 746, 16, this._expSHREG ? "#1a0e00" : "#100a00", this._expSHREG ? "#ff9800" : "#554433", 1, 3);
            VI.label("pl_exp2_lbl", (this._expSHREG ? "[-]" : "[+]") + " SHREG_EXTRACT attribute details", 20, e2Y + 2, "#ffc107", 8, "monospace");
            VI.onClick("pl_exp2_btn", 15, e2Y, 746, 16, function() { self._expSHREG = !self._expSHREG; VI.redraw(); });
            if (this._expSHREG) {
               VI.rect("pl_exp2_bg", 15, e2Y + 17, 746, 46, "#100a00", "#554433", 1, 3);
               VI.label("pl_e2l1", "(* SHREG_EXTRACT = \"yes\" *) -- default. Vivado MAY infer SRL if no reset.", e2Y + 17 + 3,  390, "#ff9800", 8, "monospace");
               VI.label("pl_e2l2", "(* SHREG_EXTRACT = \"no\"  *) -- FORCES FF chain. Required with reset.", e2Y + 17 + 14, 390, "#ffd54f", 8, "monospace");
               VI.label("pl_e2l3", "Apply per-register in RTL: (* SHREG_EXTRACT = \"no\" *) reg [31:0] my_delay;", e2Y + 17 + 25, 390, "#ff9800", 8, "monospace");
               VI.label("pl_e2l4", "Or set globally: set_property SHREG_EXTRACT no [get_cells my_design/*]", e2Y + 17 + 36, 390, "#78909c", 8, "monospace");
               // NOTE: label args are (id, text, x, y, ...) -- fix coordinate order:
               VI.label("pl_e2la1", "(* SHREG_EXTRACT = \"yes\" *) -- default. Vivado MAY infer SRL if no reset.", 20, e2Y + 20, "#ff9800", 8, "monospace");
               VI.label("pl_e2la2", "(* SHREG_EXTRACT = \"no\"  *) -- FORCES FF chain. Required with reset.",     20, e2Y + 31, "#ffd54f", 8, "monospace");
               VI.label("pl_e2la3", "Apply per-reg in RTL: (* SHREG_EXTRACT=\"no\" *) reg [31:0] my_delay;",     20, e2Y + 42, "#ff9800", 8, "monospace");
               VI.label("pl_e2la4", "Global XDC: set_property SHREG_EXTRACT no [get_cells my_design/*]",          20, e2Y + 53, "#78909c", 8, "monospace");
            }

            // [3] Multi-tap requires FF
            const e3Y = e2Y + (this._expSHREG ? 64 : 18);
            VI.rect("pl_exp3_btn", 15, e3Y, 746, 16, this._expTap ? "#0d0d1a" : "#070710", this._expTap ? "#7e57c2" : "#334", 1, 3);
            VI.label("pl_exp3_lbl", (this._expTap ? "[-]" : "[+]") + " Why multi-tap access requires FFs not SRLs", 20, e3Y + 2, "#b39ddb", 8, "monospace");
            VI.onClick("pl_exp3_btn", 15, e3Y, 746, 16, function() { self._expTap = !self._expTap; VI.redraw(); });
            if (this._expTap) {
               VI.rect("pl_exp3_bg", 15, e3Y + 17, 746, 36, "#07060e", "#334", 1, 3);
               VI.label("pl_e3l1", "SRL has ONE muxed output: only A[4:0] selects which tap. One output only.", 20, e3Y + 20, "#b39ddb", 8, "sans-serif");
               VI.label("pl_e3l2", "If your design needs out[3], out[7], out[15] simultaneously: use FF chain.", 20, e3Y + 31, "#9c27b0", 8, "sans-serif");
               VI.label("pl_e3l3", "Q15/Q31 are additional outputs but fixed -- not arbitrary multi-tap.", 20, e3Y + 42, "#7e57c2", 8, "sans-serif");
            }

            // [4] SRL timing vs FF
            const e4Y = e3Y + (this._expTap ? 54 : 18);
            VI.rect("pl_exp4_btn", 15, e4Y, 746, 16, this._expTiming ? "#0d0d0a" : "#070700", this._expTiming ? "#ffd54f" : "#443300", 1, 3);
            VI.label("pl_exp4_lbl", (this._expTiming ? "[-]" : "[+]") + " SRL timing differences vs FF clock-to-Q", 20, e4Y + 2, "#ffd54f", 8, "monospace");
            VI.onClick("pl_exp4_btn", 15, e4Y, 746, 16, function() { self._expTiming = !self._expTiming; VI.redraw(); });
            if (this._expTiming) {
               VI.rect("pl_exp4_bg", 15, e4Y + 17, 746, 46, "#0a0a00", "#443300", 1, 3);
               VI.label("pl_e4l1", "SRL CLK-to-Q: ~0.4ns (Artix-7 -1). FF CLK-to-Q: ~0.45ns. SRL is slightly faster.", 20, e4Y + 20, "#ffd54f", 8, "sans-serif");
               VI.label("pl_e4l2", "SRL setup/hold: same as FF D-input. No timing penalty for data input.", 20, e4Y + 31, "#ffd54f", 8, "sans-serif");
               VI.label("pl_e4l3", "SRL address A[4:0]: setup ~0.5ns before CLK. Address is NOT retimed!", 20, e4Y + 42, "#f44336", 8, "sans-serif");
               VI.label("pl_e4l4", "If address changes late, output glitch occurs one cycle. Register the address.", 20, e4Y + 53, "#ff9800", 7, "sans-serif");
            }

            // ================================================================
            // PANEL R: FDRE / FDCE / FDSE / FDPE COMPARISON
            // x=775, y=10, w=765, h=930
            // ================================================================
            VI.rect("pr_bg", 775, 10, 765, 930, "#0d1117", "#2a4a6b", 2, 6);
            VI.label("pr_title", "FDRE / FDCE / FDSE / FDPE  FLIP-FLOP VARIANTS", 1157, 18, "#4fc3f7", 13, "sans-serif", "center");

            // Same physical BEL banner
            VI.rect("pr_bel_bg", 780, 34, 756, 16, "#0a0014", "#7e57c2", 2, 3);
            VI.label("pr_bel_l",  "Same physical BEL -- variant configured by bits in configuration frame, not different silicon", 1157, 37, "#b39ddb", 8, "sans-serif", "center");

            // ---- Four FF variant diagrams ----
            const FF_VARIANTS = [
               {id: "fdre", name: "FDRE", rst: "R",   rtype: "SYNC",  rlevel: "active-H", result: "->0", color: "#4fc3f7", pref: "PREFERRED"},
               {id: "fdse", name: "FDSE", rst: "S",   rtype: "SYNC",  rlevel: "active-H", result: "->1", color: "#81c784", pref: ""},
               {id: "fdce", name: "FDCE", rst: "CLR", rtype: "ASYNC", rlevel: "active-H", result: "->0", color: "#ff9800", pref: ""},
               {id: "fdpe", name: "FDPE", rst: "PRE", rtype: "ASYNC", rlevel: "active-H", result: "->1", color: "#ce93d8", pref: ""}
            ];

            for (let vi2 = 0; vi2 < FF_VARIANTS.length; vi2++) {
               (function(i) {
                  const v  = FF_VARIANTS[i];
                  const VX = 780 + i * 192;
                  const VY = 56;

                  VI.rect("pr_ff_bg_" + v.id, VX, VY, 185, 185, "#07080e", v.color, 2, 5);
                  VI.label("pr_ff_nm_" + v.id, v.name, VX + 92, VY + 6, v.color, 13, "monospace", "center");
                  if (v.pref) {
                     VI.rect("pr_pref_" + v.id, VX + 4, VY + 22, 177, 14, "#001a00", "#4caf50", 1, 2);
                     VI.label("pr_prefl_" + v.id, "PREFERRED VARIANT", VX + 92, VY + 24, "#4caf50", 8, "sans-serif", "center");
                  }

                  // BEL body
                  VI.rect("pr_bel_" + v.id, VX + 40, VY + 40, 105, 90, "#0d1020", v.color, 1, 3);

                  // Pins
                  VI.label("pr_d_" + v.id,   "D",     VX + 20, VY + 58, "#e0e0e0", 9, "monospace");
                  VI.rect("pr_dw_" + v.id,    VX + 30, VY + 63, 10, 2, "#e0e0e0");
                  VI.label("pr_clk_" + v.id,  "CLK",   VX + 14, VY + 78, "#4fc3f7", 9, "monospace");
                  VI.rect("pr_clkw_" + v.id,  VX + 30, VY + 83, 10, 2, "#4fc3f7");
                  VI.label("pr_ce_" + v.id,   "CE",    VX + 20, VY + 98, "#ffd54f", 9, "monospace");
                  VI.rect("pr_cew_" + v.id,   VX + 30, VY + 103, 10, 2, "#ffd54f");
                  VI.label("pr_r_" + v.id,    v.rst,   VX + 16, VY + 118, "#f44336", 9, "monospace");
                  VI.rect("pr_rw_" + v.id,    VX + 30, VY + 123, 10, 2, "#f44336");
                  VI.label("pr_q_" + v.id,    "Q",     VX + 150, VY + 78, v.color, 9, "monospace");
                  VI.rect("pr_qw_" + v.id,    VX + 145, VY + 83, 10, 2, v.color);

                  // Truth table style
                  VI.rect("pr_tt_" + v.id, VX + 4, VY + 138, 177, 42, "#0a0a0a", "#334466", 1, 3);
                  VI.label("pr_tt1_" + v.id, v.rtype + " " + v.rst + " (" + v.rlevel + ")", VX + 92, VY + 141, v.color, 7, "sans-serif", "center");
                  VI.label("pr_tt2_" + v.id, v.rst + "=1 at clkedge: Q" + v.result, VX + 92, VY + 152, "#e0e0e0", 7, "monospace", "center");
                  VI.label("pr_tt3_" + v.id, "CE=0: Q holds (any " + v.rst + ")", VX + 92, VY + 163, "#78909c", 7, "sans-serif", "center");
                  VI.label("pr_tt4_" + v.id, "INIT=0 default (config-time)", VX + 92, VY + 174, "#37474f", 7, "sans-serif", "center");
               })(vi2);
            }

            // ---- CE behavior waveform ----
            VI.rect("pr_ce_bg", 780, 250, 756, 120, "#06090c", "#334466", 1, 4);
            VI.label("pr_ce_t",  "CLOCK ENABLE (CE) BEHAVIOR -- LIVE", 1157, 256, "#4fc3f7", 11, "sans-serif", "center");

            // Draw 16-cycle CE waveform
            const CE_X0   = 790;
            const CE_CW   = 44;
            const CE_NCYC = 16;
            const CE_Y_CLK  = 274;
            const CE_Y_CE   = 295;
            const CE_Y_FDRE = 316;
            const CE_Y_FDCE = 337;

            VI.label("pr_ce_clk_l",  "CLK",       780, CE_Y_CLK,  "#4fc3f7", 8, "monospace");
            VI.label("pr_ce_ce_l",   "CE",         780, CE_Y_CE,   "#ffd54f", 8, "monospace");
            VI.label("pr_ce_fdre_l", "FDRE Q",     780, CE_Y_FDRE, "#4fc3f7", 8, "monospace");
            VI.label("pr_ce_fdce_l", "FDCE Q",     780, CE_Y_FDCE, "#ff9800", 8, "monospace");

            for (let ci2 = 0; ci2 < CE_NCYC; ci2++) {
               (function(i) {
                  const wc     = safeCyc(cyc - (CE_NCYC - 1 - i));
                  const wce    = getSig("TLV|ffreg$ce",     wc, 1);
                  const wfdre  = getSig("TLV|ffreg$fdre_q", wc, 0) & 0xF;
                  const wfdce  = getSig("TLV|ffreg$fdce_q", wc, 0) & 0xF;
                  const wclk   = (wc % 2);
                  const isc    = (wc === cyc);
                  const wx     = CE_X0 + i * CE_CW;

                  if (isc) { VI.rect("pr_ce_cur_" + i, wx, CE_Y_CLK - 4, CE_CW, 78, "#101820", "#4fc3f7", 1, 0); }

                  // CLK bar
                  VI.rect("pr_ce_clkb_" + i, wx, CE_Y_CLK + (wclk ? 0 : 8), CE_CW - 1, wclk ? 8 : 3, wclk ? "#0d2035" : "#060a10", wclk ? "#4fc3f7" : "#2a3b5a", 1, 0);
                  // CE bar
                  VI.rect("pr_ce_ceb_" + i, wx, CE_Y_CE + (wce ? 0 : 8), CE_CW - 1, wce ? 8 : 3, wce ? "#1a1a00" : "#0a0a00", wce ? "#ffd54f" : "#443300", 1, 0);
                  // FDRE Q
                  VI.rect("pr_ce_fdrb_" + i, wx, CE_Y_FDRE + (wfdre ? 0 : 8), CE_CW - 1, wfdre ? 8 : 3, wfdre ? "#0d2035" : "#060a10", wfdre ? "#4fc3f7" : "#2a3b5a", 1, 0);
                  // FDCE Q
                  VI.rect("pr_ce_fdcb_" + i, wx, CE_Y_FDCE + (wfdce ? 0 : 8), CE_CW - 1, wfdce ? 8 : 3, wfdce ? "#1a0d00" : "#0a0600", wfdce ? "#ff9800" : "#443300", 1, 0);

                  if (!wce) { VI.label("pr_ce_hold_" + i, "HOLD", wx + CE_CW / 2, CE_Y_FDRE + 5, "#546e7a", 6, "monospace", "center"); }
                  VI.label("pr_ce_cyc_" + i, String(wc), wx + CE_CW / 2, CE_Y_FDCE + 16, "#37474f", 6, "monospace", "center");
               })(ci2);
            }
            VI.label("pr_ce_note1", "CE=0: FDRE holds Q. Clock tree STILL TOGGLES. Only the D-input mux is gated.", 1157, 360, "#ffd54f", 8, "sans-serif", "center");
            VI.label("pr_ce_note2", "CE does NOT stop the clock. Use clock gating (BUFGCE) if power is critical.", 1157, 372, "#546e7a", 8, "sans-serif", "center");

            // ---- Sync vs Async reset timing ----
            VI.rect("pr_rst_bg", 780, 388, 756, 140, "#060809", "#334466", 1, 4);
            VI.label("pr_rst_t",  "SYNCHRONOUS vs ASYNCHRONOUS RESET TIMING", 1157, 394, "#4fc3f7", 11, "sans-serif", "center");

            // FDRE (sync reset)
            VI.rect("pr_fdre_bg", 785, 412, 360, 108, "#06100a", "#4caf50", 1, 4);
            VI.label("pr_fdre_t",  "FDRE -- Synchronous Reset", 965, 418, "#4caf50", 10, "sans-serif", "center");
            VI.label("pr_fdre_l1", "R=1 at clock edge -> Q=0 next cycle.", 795, 432, "#a5d6a7", 8, "monospace");
            VI.label("pr_fdre_l2", "R must meet SETUP/HOLD relative to CLK.", 795, 443, "#a5d6a7", 8, "monospace");
            VI.label("pr_fdre_l3", "Timing: standard data timing check.", 795, 454, "#4caf50", 8, "monospace");
            VI.label("pr_fdre_l4", "Reset propagates through logic path.", 795, 465, "#4caf50", 8, "monospace");
            VI.rect("pr_fdre_adv", 790, 478, 350, 34, "#001a00", "#4caf50", 1, 3);
            VI.label("pr_fdre_a1", "ADVANTAGES:", 795, 481, "#4caf50", 8, "monospace");
            VI.label("pr_fdre_a2", "No recovery/removal check. No async reset tree.", 795, 492, "#81c784", 8, "monospace");
            VI.label("pr_fdre_a3", "Simpler timing analysis. Preferred by Xilinx.", 795, 503, "#81c784", 8, "monospace");

            // FDCE (async reset)
            VI.rect("pr_fdce_bg", 1155, 412, 372, 108, "#100a00", "#ff9800", 1, 4);
            VI.label("pr_fdce_t",  "FDCE -- Asynchronous Clear", 1341, 418, "#ff9800", 10, "sans-serif", "center");
            VI.label("pr_fdce_l1", "CLR=1 -> Q=0 IMMEDIATELY (no clock edge).", 1165, 432, "#ffd54f", 8, "monospace");
            VI.label("pr_fdce_l2", "CLR deassertion must be SYNCHRONOUS.", 1165, 443, "#f44336", 8, "monospace");
            VI.label("pr_fdce_l3", "RECOVERY check: CLR deassertion before CLK.", 1165, 454, "#ff9800", 8, "monospace");
            VI.label("pr_fdce_l4", "REMOVAL check: CLR after CLK edge.", 1165, 465, "#ff9800", 8, "monospace");
            VI.rect("pr_fdce_warn", 1160, 478, 360, 34, "#1a0000", "#f44336", 1, 3);
            VI.label("pr_fdce_w1", "WARNING: Async deassertion causes metastability!", 1165, 481, "#f44336", 8, "monospace");
            VI.label("pr_fdce_w2", "Must use synchronizer on reset deassertion path.", 1165, 492, "#ef9a9a", 8, "monospace");
            VI.label("pr_fdce_w3", "Use async assert / sync deassert pattern only.", 1165, 503, "#ef9a9a", 8, "monospace");

            // ---- Live FF values ----
            VI.rect("pr_live_bg", 780, 536, 756, 62, "#06080a", "#334466", 1, 4);
            VI.label("pr_live_t",  "LIVE SIGNAL VALUES (current cycle " + cyc + ")", 1157, 542, "#4fc3f7", 10, "sans-serif", "center");

            VI.rect("pr_live_fdre", 785, 558, 240, 34, ff_rst ? "#1a0000" : (ce ? "#071207" : "#0f0f00"), ff_rst ? "#f44336" : (ce ? "#4caf50" : "#ffd54f"), 1, 3);
            VI.label("pr_lfdre_t",  "FDRE",                     905, 561, "#4fc3f7", 9, "monospace", "center");
            VI.label("pr_lfdre_q",  "Q = " + toHex2(fdre_q) + "  (" + toBin8(fdre_q) + ")", 905, 574, "#4fc3f7", 8, "monospace", "center");
            VI.label("pr_lfdre_ce", "CE=" + ce + "  RST=" + ff_rst, 905, 585, ce ? "#ffd54f" : "#f44336", 7, "monospace", "center");

            VI.rect("pr_live_fdce", 1035, 558, 240, 34, ff_rst ? "#1a0000" : "#071207", ff_rst ? "#f44336" : "#ff9800", 1, 3);
            VI.label("pr_lfdce_t",  "FDCE",                     1155, 561, "#ff9800", 9, "monospace", "center");
            VI.label("pr_lfdce_q",  "Q = " + toHex2(fdce_q) + "  (" + toBin8(fdce_q) + ")", 1155, 574, "#ff9800", 8, "monospace", "center");
            VI.label("pr_lfdce_n",  "Always samples D (no CE gating)", 1155, 585, "#78909c", 7, "sans-serif", "center");

            VI.label("pr_live_din", "D_in = " + toHex2(ff_din), 1290, 570, "#546e7a", 9, "monospace");
            VI.label("pr_live_dif", ce ? "CE=1: both FFs capture D" : "CE=0: FDRE holds, FDCE captures D", 1290, 583, ce ? "#4caf50" : "#ffd54f", 7, "sans-serif");

            // ---- INIT parameter panel ----
            VI.rect("pr_init_bg", 780, 606, 756, 64, "#07070d", "#7e57c2", 1, 4);
            VI.label("pr_init_t",  "INIT PARAMETER: configuration-time vs runtime state", 1157, 612, "#b39ddb", 10, "sans-serif", "center");
            VI.label("pr_init_l1", "INIT=0 (default): FF powers up Q=0 at configuration. This is separate from reset.", 1157, 626, "#ce93d8", 9, "sans-serif", "center");
            VI.label("pr_init_l2", "INIT=1: FF powers up Q=1. Useful for active-low reset logic (SR-FF patterns).", 1157, 637, "#9c27b0", 9, "sans-serif", "center");
            VI.label("pr_init_l3", "INIT is a bitstream parameter, not a port. It is applied once at power-on/config.", 1157, 648, "#7e57c2", 8, "sans-serif", "center");
            VI.label("pr_init_l4", "Runtime RESET (R/S/CLR/PRE) overrides INIT on first assertion.", 1157, 659, "#546e7a", 8, "sans-serif", "center");

            // ---- Power comparison ----
            VI.rect("pr_pwr_bg", 780, 678, 756, 72, "#060906", "#334466", 1, 4);
            VI.label("pr_pwr_t",  "CE POWER BEHAVIOR: clock gating vs CE gating", 1157, 684, "#4fc3f7", 10, "sans-serif", "center");
            VI.rect("pr_pwr_ce",  785, 698, 360, 46, "#0a0a00", "#ffd54f", 1, 3);
            VI.label("pr_pce_t",  "CE Gating (FDRE with CE=0)", 965, 702, "#ffd54f", 9, "sans-serif", "center");
            VI.label("pr_pce_l1", "CLK still arrives at FF clock pin every cycle.", 795, 714, "#ff9800", 8, "monospace");
            VI.label("pr_pce_l2", "Dynamic power: CLK switching still dissipated.", 795, 725, "#ff9800", 8, "monospace");
            VI.label("pr_pce_l3", "Only D-mux switching is gated. Partial savings.", 795, 736, "#546e7a", 8, "sans-serif");
            VI.rect("pr_pwr_clk", 1155, 698, 372, 46, "#001500", "#4caf50", 1, 3);
            VI.label("pr_pclk_t",  "BUFGCE Clock Gating (true gate)", 1341, 702, "#4caf50", 9, "sans-serif", "center");
            VI.label("pr_pclk_l1", "Clock tree disabled at BUFGCE output.", 1165, 714, "#81c784", 8, "monospace");
            VI.label("pr_pclk_l2", "FF clock pin does NOT toggle. Full power save.", 1165, 725, "#4caf50", 8, "monospace");
            VI.label("pr_pclk_l3", "Constraint: BUFGCE enable must be glitch-free.", 1165, 736, "#546e7a", 8, "sans-serif");

            // ---- Clickable expanders ----
            // [5] FDCE sync reset preference
            VI.rect("pr_exp5_btn", 780, 758, 756, 16, this._expFDCE ? "#100a00" : "#080500", this._expFDCE ? "#ff9800" : "#443300", 1, 3);
            VI.label("pr_exp5_lbl", (this._expFDCE ? "[-]" : "[+]") + " Why synchronous reset (FDRE) is strongly preferred over FDCE", 785, 760, "#ffc107", 8, "monospace");
            VI.onClick("pr_exp5_btn", 780, 758, 756, 16, function() { self._expFDCE = !self._expFDCE; VI.redraw(); });
            if (this._expFDCE) {
               VI.rect("pr_exp5_bg", 780, 775, 756, 58, "#080500", "#443300", 1, 3);
               VI.label("pr_e5l1", "FDRE: no recovery/removal timing check -- simpler STA. Reset path is data path.", 785, 778, "#ffd54f", 8, "sans-serif");
               VI.label("pr_e5l2", "FDCE: needs dedicated async reset routing tree. Can cause glitches if reset races CLK.", 785, 789, "#ff9800", 8, "sans-serif");
               VI.label("pr_e5l3", "FDCE: deassertion metastability requires synchronizer (adds 2 cycles of latency).", 785, 800, "#f44336", 8, "sans-serif");
               VI.label("pr_e5l4", "FDCE: Vivado adds recovery/removal constraints -- can cause hard-to-fix timing fails.", 785, 811, "#ef9a9a", 8, "sans-serif");
               VI.label("pr_e5l5", "Use FDCE ONLY: power-on reset (POR) networks, safety-critical immediate shutdown.", 785, 822, "#78909c", 8, "sans-serif");
            }

            // [6] CE detailed
            const e6Y = 758 + (this._expFDCE ? 76 : 18);
            VI.rect("pr_exp6_btn", 780, e6Y, 756, 16, this._expCE ? "#0d0d00" : "#070700", this._expCE ? "#ffd54f" : "#333300", 1, 3);
            VI.label("pr_exp6_lbl", (this._expCE ? "[-]" : "[+]") + " CE signal internals and clock-enable arc timing", 785, e6Y + 2, "#fff176", 8, "monospace");
            VI.onClick("pr_exp6_btn", 780, e6Y, 756, 16, function() { self._expCE = !self._expCE; VI.redraw(); });
            if (this._expCE) {
               VI.rect("pr_exp6_bg", 780, e6Y + 17, 756, 46, "#070700", "#333300", 1, 3);
               VI.label("pr_e6l1", "CE internally controls a 2-to-1 mux: CE=1 selects D, CE=0 selects Q (feedback).", 785, e6Y + 20, "#fff176", 8, "sans-serif");
               VI.label("pr_e6l2", "The mux is before the FF D-input. Clock still registers the mux output every cycle.", 785, e6Y + 31, "#ffd54f", 8, "sans-serif");
               VI.label("pr_e6l3", "CE setup time: ~0.3ns before CLK. If CE changes late: may violate setup -> X/metastable.", 785, e6Y + 42, "#ff9800", 8, "sans-serif");
               VI.label("pr_e6l4", "CE=0 for N cycles: Q is stable for N cycles regardless of D toggling. Zero glitch.", 785, e6Y + 53, "#546e7a", 8, "sans-serif");
            }

            // ================================================================
            // GLOBAL CYCLE SCRUBBER
            // ================================================================
            VI.rect("sc_bg", 10, 944, 1530, 3, "#1a2a3a");
            const scRange = Math.max(1, wd.endCycle - wd.startCycle);
            const scX = 10 + (cyc - wd.startCycle) * 1530 / scRange;
            VI.rect("sc_h", Math.min(scX, 1530), 941, 4, 8, "#4fc3f7");
            VI.onClick("sc_bg", 10, 941, 1530, 11, function(x) {
               var nc = Math.round(wd.startCycle + (x - 10) * scRange / 1530);
               try { pane.session.setCycle(Math.max(wd.startCycle, Math.min(wd.endCycle, nc))); } catch(e) {}
               VI.redraw();
            });

            // ================================================================
            // CAMERA AUTO-CENTERING
            // ================================================================
            if (this._firstRender) {
               this._firstRender = false;
               try {
                  pane.content.contentScale = 0.85;
                  pane.content.userFocus    = {x: 775, y: 475};
                  pane.content.refreshContentPosition();
               } catch(e) {}
            }
         }
\SV
   endmodule
