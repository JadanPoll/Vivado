\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
\SV
   m5_makerchip_module
\TLV
   // =============================================================================
   // METASTABILITY AND CLOCK DOMAIN CROSSING EXPLORER
   // Teaches: metastability theory, MTBF calculation, CDC implementation patterns
   // XC7S50 / Vivado context
   // =============================================================================

   |domain_a
      @1
         $reset = *reset;
         $clk_a = *cyc_cnt[0];
         $data_src[7:0] = *cyc_cnt[15:8];
         $toggle = $reset ? 1'b0 : ($clk_a && !>>1$clk_a) ? !>>1$toggle : >>1$toggle;
         $pulse = ($clk_a && !>>1$clk_a && (*cyc_cnt[3:0] == 4'b0000));
         `BOGUS_USE($toggle $pulse $data_src)
         
   |sync2ff
      @1
         $reset = *reset;
         $clk_b = *cyc_cnt[1];
         $async_in = |domain_a$toggle;
         $ff1[0:0] = $reset ? 1'b0 : ($clk_b && !>>1$clk_b) ? $async_in : >>1$ff1;
         $ff2[0:0] = $reset ? 1'b0 : ($clk_b && !>>1$clk_b) ? $ff1 : >>1$ff2;
         $metastable_window = ($clk_b && !>>1$clk_b && ($async_in != >>1$async_in));
         $sync_out = $ff2;
         `BOGUS_USE($ff1 $ff2 $sync_out $metastable_window)

   |gray_fifo
      @1
         $reset = *reset;
         $wr_ptr_bin[3:0] = $reset ? 4'b0 : >>1$wr_ptr_bin + 1;
         $wr_ptr_gray[3:0] = $wr_ptr_bin ^ ($wr_ptr_bin >> 1);
         $rd_ptr_bin[3:0] = $reset ? 4'b0 : (>>1$rd_ptr_bin < >>1$wr_ptr_bin) ? >>1$rd_ptr_bin + 1 : >>1$rd_ptr_bin;
         $rd_ptr_gray[3:0] = $rd_ptr_bin ^ ($rd_ptr_bin >> 1);
         $empty = ($wr_ptr_gray == $rd_ptr_gray);
         $gray_bits_changing[3:0] = $wr_ptr_gray ^ >>1$wr_ptr_gray;
         `BOGUS_USE($wr_ptr_gray $rd_ptr_gray $empty $gray_bits_changing)

   *passed = *cyc_cnt > 400;
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

            this._firstRender = true;
            this._expandA = false;
            this._expandB = false;
            this._expandC = false;
            this._expandD = false;
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
            const cyc = pane.cyc;

            const getSig = function(name, c, def) {
               try { return wd.getSignalValueAtCycleByName(name, c).asInt(def); } catch(e) { return def; }
            };

            const safeCyc = function(c) {
               return Math.max(wd.startCycle, Math.min(wd.endCycle, c));
            };

            const toBin4 = function(v) {
               const n = v & 0xF;
               return (((n >> 3) & 1).toString() + ((n >> 2) & 1).toString() +
                       ((n >> 1) & 1).toString() + (n & 1).toString());
            };

            const popcount = function(v) {
               let x = v & 0xFFFF; let n = 0;
               while (x) { n += (x & 1); x >>>= 1; }
               return n;
            };

            // ================================================================
            // Live signal values
            // ================================================================
            const clk_a     = getSig("TLV|domain_a$clk_a",          cyc, 0);
            const toggle    = getSig("TLV|domain_a$toggle",          cyc, 0);
            const clk_b     = getSig("TLV|sync2ff$clk_b",            cyc, 0);
            const async_in  = getSig("TLV|sync2ff$async_in",         cyc, 0);
            const ff1       = getSig("TLV|sync2ff$ff1",              cyc, 0);
            const ff2       = getSig("TLV|sync2ff$ff2",              cyc, 0);
            const meta_win  = getSig("TLV|sync2ff$metastable_window",cyc, 0);
            const sync_out  = getSig("TLV|sync2ff$sync_out",         cyc, 0);
            const wr_bin    = getSig("TLV|gray_fifo$wr_ptr_bin",     cyc, 0);
            const wr_gray   = getSig("TLV|gray_fifo$wr_ptr_gray",    cyc, 0);
            const rd_bin    = getSig("TLV|gray_fifo$rd_ptr_bin",     cyc, 0);
            const rd_gray   = getSig("TLV|gray_fifo$rd_ptr_gray",    cyc, 0);
            const fifo_empty = getSig("TLV|gray_fifo$empty",         cyc, 1);
            const prevWrBin  = getSig("TLV|gray_fifo$wr_ptr_bin",   safeCyc(cyc - 1), 0);
            const prevWrGray = getSig("TLV|gray_fifo$wr_ptr_gray",  safeCyc(cyc - 1), 0);
            const binBitsChg  = popcount(wr_bin  ^ prevWrBin);
            const grayBitsChg = popcount(wr_gray ^ prevWrGray);

            // ================================================================
            // PANEL A: METASTABILITY PHYSICS + MTBF
            // x=15, y=15, w=500, h=450
            // ================================================================
            VI.rect("pa_bg", 15, 15, 500, 450, "#0d1117", "#2a4a6b", 2, 6);
            VI.label("pa_title", "METASTABILITY PHYSICS + MTBF", 265, 22, "#4fc3f7", 13, "sans-serif", "center");

            // ---- Bistable latch diagram ----
            VI.rect("pa_lat_bg", 20, 40, 232, 120, "#080c10", "#334466", 1, 4);
            VI.label("pa_lat_t", "BISTABLE LATCH (cross-coupled inverters)", 22, 42, "#546e7a", 8, "sans-serif");

            VI.rect("pa_inv1", 38, 62, 52, 26, "#0d2035", "#4fc3f7", 1, 3);
            VI.label("pa_inv1l", "INV1", 64, 70, "#4fc3f7", 9, "monospace", "center");
            VI.rect("pa_inv2", 142, 62, 52, 26, "#0d2035", "#4fc3f7", 1, 3);
            VI.label("pa_inv2l", "INV2", 168, 70, "#4fc3f7", 9, "monospace", "center");

            VI.rect("pa_w1",  90, 68, 52, 2, "#81c784");
            VI.rect("pa_w2l", 38, 84,  2, 20, "#81c784");
            VI.rect("pa_w2h", 38, 103, 158, 2, "#81c784");
            VI.rect("pa_w2r", 194, 84,  2, 20, "#81c784");

            VI.label("pa_q",  "Q",     22,  68, "#a5d6a7", 8, "monospace");
            VI.label("pa_qb", "Q/bar", 200, 68, "#a5d6a7", 8, "monospace");

            VI.rect("pa_s0", 20, 114, 58, 16, "#0a1a0a", "#4caf50", 1, 3);
            VI.label("pa_s0l", "STABLE Q=0",  49, 118, "#4caf50", 8, "monospace", "center");
            VI.rect("pa_s1", 155, 114, 58, 16, "#1a0a0a", "#f44336", 1, 3);
            VI.label("pa_s1l", "STABLE Q=1", 184, 118, "#f44336", 8, "monospace", "center");

            VI.rect("pa_mp",  92, 108, 48, 20, "#1a1000", "#ff9800", 2, 3);
            VI.label("pa_mp1", "VDD/2", 116, 111, "#ff9800", 7, "monospace", "center");
            VI.label("pa_mp2", "META",  116, 120, "#ffc107", 7, "monospace", "center");
            VI.rect("pa_al",  73, 117, 17, 2, "#ff9800");
            VI.rect("pa_ar", 142, 117, 17, 2, "#ff9800");
            VI.rect("pa_alh",  70, 113,  4,  8, "#ff9800");
            VI.rect("pa_arh", 157, 113,  4,  8, "#ff9800");

            VI.label("pa_ln1", "2 stable equilibria: Q=0 or Q=1.", 22, 138, "#37474f", 8, "sans-serif");
            VI.label("pa_ln2", "Metastable point resolves exponentially.", 22, 148, "#37474f", 8, "sans-serif");

            // ---- Resolution curve ----
            VI.rect("pa_rc_bg", 20, 167, 232, 102, "#080c10", "#334466", 1, 4);
            VI.label("pa_rc_t",   "EXPONENTIAL RESOLUTION",         22, 169, "#546e7a", 8, "sans-serif");
            VI.label("pa_rc_eq",  "V(t) = V_meta * e^(t / tau)",   22, 179, "#ffd54f", 9, "monospace");
            VI.label("pa_rc_tau", "tau = 35ps  (28nm TSMC CMOS)",  22, 190, "#ce93d8", 8, "monospace");
            VI.label("pa_rc_d1",  "FF resolves when V(t) crosses", 22, 201, "#546e7a", 8, "sans-serif");
            VI.label("pa_rc_d2",  "downstream gate switching threshold.", 22, 210, "#546e7a", 8, "sans-serif");

            const expData = [0, 1, 2, 4, 7, 11, 17, 24, 32, 40, 44, 46];
            for (let ei = 0; ei < expData.length; ei++) {
               (function(i) {
                  const bh = expData[i];
                  VI.rect("pa_eu_" + i, 26 + i * 15, 243 - bh, 11, Math.max(bh, 1), "#4fc3f7");
                  VI.rect("pa_ed_" + i, 26 + i * 15, 245,       11, Math.max(bh, 1), "#ef9a9a");
               })(ei);
            }
            VI.rect("pa_mhl", 26, 243, 180, 2, "#ff9800");
            VI.label("pa_mhll", "Vmeta", 210, 238, "#ff9800", 7, "monospace");
            VI.label("pa_vdd",  "-> VDD", 210, 220, "#4fc3f7", 7, "monospace");
            VI.label("pa_gnd",  "-> GND", 210, 252, "#ef9a9a", 7, "monospace");
            VI.label("pa_tl",   "t ->",    26, 261, "#37474f", 7, "monospace");

            // ---- Setup time violation window ----
            VI.rect("pa_sw_bg", 20, 276, 232, 80, "#080c10", "#334466", 1, 4);
            VI.label("pa_sw_t",  "METASTABILITY WINDOW  T_W = 60ps", 22, 278, "#ffd54f", 9, "monospace");

            VI.rect("pa_clk_lo", 28, 325, 42, 2, "#4fc3f7");
            VI.rect("pa_clk_ed", 70, 311, 2, 16, "#4fc3f7");
            VI.rect("pa_clk_hi", 72, 311, 48, 2, "#4fc3f7");
            VI.label("pa_clk_l", "CLK",  22, 319, "#4fc3f7", 7, "monospace");

            VI.rect("pa_ws",  57, 308, 26, 20, "#ff980040");
            VI.rect("pa_wsl", 57, 308,  2, 20, "#ff9800");
            VI.rect("pa_wsr", 83, 308,  2, 20, "#ff9800");
            VI.label("pa_twl", "T_W", 62, 296, "#ff9800", 7, "monospace");
            VI.label("pa_sf1", "safe", 34, 328, "#4caf50", 7);
            VI.label("pa_md",  "META", 59, 328, "#f44336", 7);
            VI.label("pa_sf2", "safe", 92, 328, "#4caf50", 7);

            VI.rect("pa_dat_lo", 28, 336, 32, 2, "#ce93d8");
            VI.rect("pa_dat_ed", 60, 326,  2, 12, "#ce93d8");
            VI.rect("pa_dat_hi", 62, 326, 56, 2, "#ce93d8");
            VI.label("pa_dat_l", "DATA", 22, 330, "#ce93d8", 7, "monospace");
            VI.label("pa_dat_w", "transition inside T_W!", 122, 326, "#f44336", 8, "sans-serif");
            VI.label("pa_sw_n",  "Data in T_W may cause metastability.", 22, 348, "#37474f", 7, "sans-serif");

            // ---- MTBF Calculator (right column of panel A) ----
            VI.rect("pa_mtbf_bg", 258, 40, 250, 420, "#080c10", "#2a4a6b", 1, 4);
            VI.label("pa_mtbf_t", "MTBF CALCULATOR", 383, 47, "#4fc3f7", 12, "sans-serif", "center");

            const MT_PARAMS = [
               ["tau",  "tau = 35 ps",     "28nm TSMC FF constant",      "#ce93d8"],
               ["tw",   "T_W = 60 ps",      "setup+hold danger window",  "#ff9800"],
               ["tclk", "T_CLK = 5 ns",     "200 MHz clock period",      "#4fc3f7"],
               ["fd",   "f_data = 100 MHz", "data toggle rate",           "#81c784"],
               ["tl",   "t_logic = 1 ns",   "combinational budget",       "#fff176"],
               ["tr",   "T_resolve = 4 ns", "T_CLK - t_logic - t_setup", "#ffd54f"]
            ];
            const MY0 = 64;
            for (let pi = 0; pi < MT_PARAMS.length; pi++) {
               (function(i) {
                  const p = MT_PARAMS[i];
                  VI.rect("mtbf_r_" + p[0], 263, MY0 + i * 29, 240, 26, "#101820", "#33445a", 1, 3);
                  VI.label("mtbf_m_" + p[0], p[1], 268, MY0 + i * 29 + 4,  p[3], 10, "monospace");
                  VI.label("mtbf_s_" + p[0], p[2], 268, MY0 + i * 29 + 15, "#546e7a", 7, "sans-serif");
               })(pi);
            }

            const FY = MY0 + 6 * 29 + 6;
            VI.rect("pa_fb", 263, FY, 240, 58, "#0c1000", "#ffd54f", 1, 3);
            VI.label("pa_f1", "MTBF = (T_CLK / (f_data * T_W))", 383, FY +  4, "#ffd54f", 8, "monospace", "center");
            VI.label("pa_f2", "     * e^(T_resolve / tau)",       383, FY + 15, "#ffd54f", 8, "monospace", "center");
            VI.label("pa_f3", "= (5ns / (1e8 * 60ps)) * e^114",  383, FY + 28, "#a0c0a0", 8, "monospace", "center");
            VI.label("pa_f4", "= 2.9 x 10^49  seconds",          383, FY + 40, "#4caf50", 10, "monospace", "center");

            VI.rect("pa_rb", 263, FY + 63, 240, 28, "#001500", "#4caf50", 2, 3);
            VI.label("pa_r1", "~9 x 10^41  YEARS",                         383, FY + 67, "#4caf50", 12, "monospace", "center");
            VI.label("pa_r2", "2-FF synchronizer is universally sufficient",383, FY + 80, "#81c784", 7, "sans-serif", "center");

            VI.rect("pa_3ffb", 263, FY + 96, 240, 70, "#0a0a20", "#7e57c2", 1, 3);
            VI.label("pa_3t",  "ADD A THIRD FF:",                         383, FY +  99, "#7e57c2", 10, "sans-serif", "center");
            VI.label("pa_3l1", "T_resolve increases by T_CLK",            383, FY + 110, "#b39ddb",  8, "monospace", "center");
            VI.label("pa_3l2", "MTBF *= e^(T_CLK/tau) = e^142",          383, FY + 121, "#b39ddb",  8, "monospace", "center");
            VI.label("pa_3l3", "e^142 ~ 10^62  additional orders",         383, FY + 132, "#7e57c2",  8, "monospace", "center");
            VI.label("pa_3l4", "+62 orders of magnitude to MTBF!",        383, FY + 143, "#9c27b0",  9, "sans-serif", "center");
            VI.label("pa_3l5", "Reserve 3rd FF for ultra-critical paths.", 383, FY + 155, "#37474f",  7, "sans-serif", "center");

            VI.label("pa_cv1", "tau is per-cell from silicon characterization.", 268, FY + 172, "#263238", 7, "sans-serif");
            VI.label("pa_cv2", "Real T_W from library NLDM timing models.",      268, FY + 181, "#263238", 7, "sans-serif");

            // ================================================================
            // PANEL B: TWO-FF SYNCHRONIZER (LIVE)
            // x=15, y=470, w=500, h=470
            // ================================================================
            VI.rect("pb_bg", 15, 470, 500, 470, "#0d1117", "#2a4a6b", 2, 6);
            VI.label("pb_title", "2-FF SYNCHRONIZER  (LIVE SIMULATION)", 265, 477, "#4fc3f7", 12, "sans-serif", "center");

            // Domain A box
            VI.rect("pb_da", 22, 497, 110, 88, "#0a1a0a", "#4caf50", 1, 4);
            VI.label("pb_dat",  "DOMAIN A",           77, 502, "#4caf50", 10, "sans-serif", "center");
            VI.label("pb_dclk", "clk_a = " + clk_a,  27, 516, "#81c784", 9, "monospace");
            VI.label("pb_dtgl", "toggle = " + toggle, 27, 527, "#a5d6a7", 9, "monospace");
            VI.label("pb_dn1",  "cyc_cnt[0] = clk_a", 27, 539, "#37474f", 7, "monospace");
            VI.label("pb_dn2",  "cyc_cnt[1] = clk_b", 27, 548, "#37474f", 7, "monospace");
            VI.label("pb_dn3",  "clk_b is 2x slower", 27, 557, "#37474f", 7, "sans-serif");
            VI.label("pb_dn4",  "toggle flips on rising clk_a", 27, 566, "#37474f", 7, "sans-serif");

            // Async crossing arrow
            VI.rect("pb_axw",   132, 538, 52, 2, "#ff9800");
            VI.rect("pb_axarr", 180, 534,  4, 10, "#ff9800");
            VI.label("pb_ax1", "ASYNC",      137, 522, "#ff9800", 8, "monospace");
            VI.label("pb_ax2", "CROSSING",   137, 532, "#ff9800", 8, "monospace");
            VI.label("pb_ax3", "may violate",137, 542, "#f44336", 7, "sans-serif");
            VI.label("pb_ax4", "setup time!", 137, 551, "#f44336", 7, "sans-serif");

            // FF1
            const ff1Fill = meta_win ? "#2a0808" : "#101c2c";
            const ff1Str  = meta_win ? "#f44336" : "#4fc3f7";
            VI.rect("pb_ff1", 184, 508, 72, 66, ff1Fill, ff1Str, meta_win ? 2 : 1, 4);
            VI.label("pb_f1t",  "FF1",             220, 512, "#4fc3f7", 11, "monospace", "center");
            VI.label("pb_f1v",  "Q=" + ff1,        220, 526, ff1 ? "#f44336" : "#4caf50", 12, "monospace", "center");
            VI.label("pb_f1a1", "(* ASYNC_REG *)",  220, 540, "#b39ddb",  7, "monospace", "center");
            VI.label("pb_f1a2", "(* DONT_TOUCH *)", 220, 549, "#9c27b0",  7, "monospace", "center");
            VI.label("pb_f1ck", "clk_b=" + clk_b,  220, 558, "#8892b0",  8, "monospace", "center");
            if (meta_win) {
               VI.rect("pb_mwb", 184, 575, 72, 13, "#1a0000", "#f44336", 1, 2);
               VI.label("pb_mwl", "METASTABLE!", 220, 577, "#f44336", 8, "sans-serif", "center");
            }

            // FF1 -> FF2 wire
            VI.rect("pb_f12w", 256, 539, 32, 2, "#4fc3f7");

            // FF2
            VI.rect("pb_ff2", 288, 508, 72, 66, "#101c2c", "#4fc3f7", 1, 4);
            VI.label("pb_f2t",  "FF2",             324, 512, "#4fc3f7", 11, "monospace", "center");
            VI.label("pb_f2v",  "Q=" + ff2,        324, 526, ff2 ? "#f44336" : "#4caf50", 12, "monospace", "center");
            VI.label("pb_f2a1", "(* ASYNC_REG *)",  324, 540, "#b39ddb",  7, "monospace", "center");
            VI.label("pb_f2a2", "(* DONT_TOUCH *)", 324, 549, "#9c27b0",  7, "monospace", "center");
            VI.label("pb_f2ck", "clk_b=" + clk_b,  324, 558, "#8892b0",  8, "monospace", "center");

            // Slice placement outline
            VI.rect("pb_slc", 179, 503, 186, 76, "transparent", "#7e57c2", 1, 0);
            VI.label("pb_slcl1", "SAME SLICE -- maximizes T_resolve", 272, 582, "#7e57c2", 7, "sans-serif", "center");
            VI.label("pb_slcl2", "Minimizes routing delay FF1->FF2",  272, 591, "#7e57c2", 7, "sans-serif", "center");

            // Output + Domain B
            VI.rect("pb_ow",  360, 539, 36,   2, "#4fc3f7");
            VI.rect("pb_db",  396, 506, 104, 50, "#0a1a0a", "#4caf50", 1, 4);
            VI.label("pb_dbt", "DOMAIN B",             448, 512, "#4caf50", 9, "sans-serif", "center");
            VI.label("pb_dbv", "sync_out=" + sync_out, 448, 524, "#a5d6a7", 9, "monospace", "center");
            VI.label("pb_dba", "async_in=" + async_in, 448, 535, "#78909c", 8, "monospace", "center");
            VI.label("pb_dbl", "+2 clk_b latency",     448, 546, "#546e7a", 7, "sans-serif", "center");

            // Constraints section
            VI.rect("pb_conbg", 22, 610, 490, 132, "#08080e", "#446", 1, 4);
            VI.label("pb_cont", "VIVADO XDC CONSTRAINTS", 27, 616, "#ffd54f", 10, "monospace");

            VI.rect("pb_fpc", 27, 630, 480, 16, "#0a1010", "#334", 1, 2);
            VI.label("pb_fpl", "set_false_path -from [get_clocks clk_a] -to [get_clocks clk_b]", 32, 632, "#a5d6a7", 8, "monospace");
            VI.label("pb_fpn1", "Ignores setup check on FF1 input. Synchronizer handles metastability.", 27, 649, "#78909c", 7, "sans-serif");
            VI.label("pb_fpn2", "Raw crossing timing is irrelevant -- the 2-FF chain is the protocol.",  27, 658, "#78909c", 7, "sans-serif");

            VI.rect("pb_mdc", 27, 670, 480, 16, "#100a00", "#554", 1, 2);
            VI.label("pb_mdl", "set_max_delay -datapath_only 5 -from clk_a -to clk_b",              32, 672, "#ffd54f", 8, "monospace");
            VI.label("pb_mdn1", "Used when path delay itself must be bounded. Removes clock skew.",   27, 690, "#78909c", 7, "sans-serif");
            VI.label("pb_mdn2", "Still routes with timing awareness. Use for MCP-protected crossings.",27, 699, "#78909c", 7, "sans-serif");

            VI.label("pb_diff_t", "KEY DIFFERENCE:", 27, 709, "#ff9800", 8, "monospace");
            VI.label("pb_diff1",  "false_path: Vivado ignores routing delay. Best for pure CDC sync chains.", 27, 719, "#546e7a", 7, "sans-serif");
            VI.label("pb_diff2",  "max_delay: Vivado minimizes delay. Use if delay affects correctness.",     27, 729, "#546e7a", 7, "sans-serif");

            // Clickable expand: ASYNC_REG placement
            const expAFill = this._expandA ? "#1a1030" : "#0d0d1a";
            VI.rect("pb_expA_btn", 22, 745, 490, 16, expAFill, "#7e57c2", 1, 3);
            VI.label("pb_expA_lbl", (this._expandA ? "[-]" : "[+]") + " ASYNC_REG physical placement effect", 27, 747, "#b39ddb", 8, "monospace");
            const self = this;
            VI.onClick("pb_expA_btn", 22, 745, 490, 16, function() { self._expandA = !self._expandA; VI.redraw(); });
            if (this._expandA) {
               VI.rect("pb_expA_bg", 22, 762, 490, 50, "#08060e", "#7e57c2", 1, 3);
               VI.label("pb_expA_l1", "ASYNC_REG=TRUE tells Vivado placer: FF1 and FF2 must share a Slice.", 27, 765, "#b39ddb", 8, "sans-serif");
               VI.label("pb_expA_l2", "Purpose: local routing from FF1.Q -> FF2.D has zero routing stage.", 27, 776, "#9c27b0", 8, "sans-serif");
               VI.label("pb_expA_l3", "This maximizes T_resolve (time between FF1 clock edge and FF2 setup)", 27, 787, "#7e57c2", 8, "sans-serif");
               VI.label("pb_expA_l4", "without adding a pipeline stage. Critical for high-freq crossings.", 27, 798, "#546e7a", 8, "sans-serif");
            }

            // Clickable expand: DONT_TOUCH
            const expBFill = this._expandB ? "#1a1030" : "#0d0d1a";
            VI.rect("pb_expB_btn", 22, 816, 490, 16, expBFill, "#7e57c2", 1, 3);
            VI.label("pb_expB_lbl", (this._expandB ? "[-]" : "[+]") + " Why DONT_TOUCH on synchronizer chains", 27, 818, "#b39ddb", 8, "monospace");
            VI.onClick("pb_expB_btn", 22, 816, 490, 16, function() { self._expandB = !self._expandB; VI.redraw(); });
            if (this._expandB) {
               VI.rect("pb_expB_bg", 22, 833, 490, 40, "#08060e", "#7e57c2", 1, 3);
               VI.label("pb_expB_l1", "DONT_TOUCH prevents Vivado from duplicating, merging or absorbing", 27, 836, "#b39ddb", 8, "sans-serif");
               VI.label("pb_expB_l2", "synchronizer FFs into SRL16/SRL32 shift registers -- which have no", 27, 847, "#9c27b0", 8, "sans-serif");
               VI.label("pb_expB_l3", "metastability resolution path and would silently break CDC safety.", 27, 858, "#7e57c2", 8, "sans-serif");
            }

            // ================================================================
            // PANEL C: GRAY CODE FIFO POINTER CDC
            // x=525, y=15, w=1010, h=925
            // ================================================================
            VI.rect("pc_bg", 525, 15, 1010, 925, "#0d1117", "#2a4a6b", 2, 6);
            VI.label("pc_title", "GRAY CODE FIFO POINTER CDC", 1030, 22, "#4fc3f7", 14, "sans-serif", "center");

            // ---- Binary counter danger ----
            VI.rect("pc_bind_bg", 530, 40, 480, 200, "#100808", "#8b2020", 2, 5);
            VI.label("pc_bind_t",  "BINARY COUNTER DANGER", 770, 47, "#f44336", 13, "sans-serif", "center");
            VI.label("pc_bind_ex", "Transition 0111 -> 1000: all 4 bits change simultaneously!", 770, 63, "#ef9a9a", 9, "sans-serif", "center");

            // Bit transition table header
            VI.label("pc_bh0", "BIT",    540, 80, "#546e7a", 9, "monospace");
            VI.label("pc_bh1", "BEFORE", 580, 80, "#546e7a", 9, "monospace");
            VI.label("pc_bh2", "AFTER",  640, 80, "#546e7a", 9, "monospace");
            VI.label("pc_bh3", "CHANGED?", 700, 80, "#546e7a", 9, "monospace");
            VI.label("pc_bh4", "RISK",   780, 80, "#546e7a", 9, "monospace");

            const binBefore = "0111";
            const binAfter  = "1000";
            for (let bi = 0; bi < 4; bi++) {
               (function(i) {
                  const bbit = 3 - i;
                  const before = parseInt(binBefore[i], 10);
                  const after  = parseInt(binAfter[i],  10);
                  const changed = before !== after;
                  const ry = 92 + i * 22;
                  VI.rect("pc_brow_" + i, 535, ry, 460, 20, changed ? "#1a0505" : "#05100a", changed ? "#f44336" : "#1b3a1b", 1, 2);
                  VI.label("pc_bbit_" + i, "bit[" + bbit + "]", 540, ry + 3, "#8892b0", 9, "monospace");
                  VI.label("pc_bbef_" + i, String(before), 600, ry + 3, before ? "#f44336" : "#4caf50", 11, "monospace", "center");
                  VI.label("pc_baft_" + i, String(after),  660, ry + 3, after  ? "#f44336" : "#4caf50", 11, "monospace", "center");
                  VI.label("pc_bchg_" + i, changed ? "YES" : "no", 730, ry + 3, changed ? "#f44336" : "#4caf50", 9, "monospace", "center");
                  VI.label("pc_brsk_" + i, changed ? "METASTABLE" : "safe", 790, ry + 3, changed ? "#f44336" : "#4caf50", 9, "monospace");
               })(bi);
            }

            VI.rect("pc_corrupt_bg", 535, 185, 460, 46, "#1a0000", "#f44336", 1, 3);
            VI.label("pc_corr1", "Any intermediate captured value is possible:", 770, 190, "#f44336", 9, "sans-serif", "center");
            VI.label("pc_corr2", "1010, 0110, 1110, 0010 ... all are garbage!",  770, 202, "#ef9a9a", 9, "monospace", "center");
            VI.label("pc_corr3", "2-FF sync with binary counter = DATA CORRUPTION", 770, 214, "#f44336", 10, "sans-serif", "center");
            VI.label("pc_corr4", "Each bit resolves independently -> arbitrary result", 770, 226, "#ef9a9a", 8, "sans-serif", "center");

            // ---- Gray code solution ----
            VI.rect("pc_gray_bg", 530, 248, 480, 200, "#071207", "#4caf50", 2, 5);
            VI.label("pc_gray_t", "GRAY CODE SOLUTION", 770, 255, "#4caf50", 13, "sans-serif", "center");
            VI.label("pc_gray_ex","Only 1 bit changes per step -- safe to synchronize!", 770, 271, "#a5d6a7", 9, "sans-serif", "center");

            // Gray code conversion formula
            VI.rect("pc_gfbg", 535, 285, 460, 20, "#0a1a0a", "#4caf50", 1, 3);
            VI.label("pc_gf1", "GRAY = BIN XOR (BIN >> 1)  -- e.g. 0111 -> 0100 (Gray for 7)", 770, 289, "#81c784", 8, "monospace", "center");

            // Live values
            VI.rect("pc_live_bg", 535, 310, 460, 48, "#050e05", "#335533", 1, 3);
            VI.label("pc_live_t",  "LIVE VALUES (current cycle " + cyc + ")", 770, 313, "#546e7a", 8, "monospace", "center");
            VI.label("pc_wrb_l",  "wr_ptr_bin  = " + toBin4(wr_bin)  + "  (" + wr_bin + ")",  540, 325, "#ffd54f", 10, "monospace");
            VI.label("pc_wrg_l",  "wr_ptr_gray = " + toBin4(wr_gray) + "  (" + wr_gray + ")", 540, 338, "#4fc3f7", 10, "monospace");
            VI.label("pc_rdb_l",  "rd_ptr_bin  = " + toBin4(rd_bin)  + "  (" + rd_bin + ")",  770, 325, "#ffd54f", 10, "monospace");
            VI.label("pc_rdg_l",  "rd_ptr_gray = " + toBin4(rd_gray) + "  (" + rd_gray + ")", 770, 338, "#4fc3f7", 10, "monospace");
            VI.label("pc_emp_l",  "empty = " + fifo_empty,                                    540, 351, fifo_empty ? "#f44336" : "#4caf50", 10, "monospace");

            // Bit change comparison
            VI.label("pc_bin_chg_lbl",  "Binary bits changed this cycle:", 540, 367, "#546e7a", 9, "sans-serif");
            VI.label("pc_bin_chg_val",  String(binBitsChg),               780, 367, binBitsChg > 1 ? "#f44336" : "#4caf50", 12, "monospace");
            VI.label("pc_gray_chg_lbl", "Gray bits changed this cycle:",   540, 380, "#546e7a", 9, "sans-serif");
            VI.label("pc_gray_chg_val", String(grayBitsChg),              780, 380, grayBitsChg > 1 ? "#f44336" : "#4caf50", 12, "monospace");
            VI.label("pc_gray_ok",      grayBitsChg <= 1 ? "SAFE" : "VIOLATION!", 810, 380, grayBitsChg <= 1 ? "#4caf50" : "#f44336", 10, "monospace");

            VI.rect("pc_gray_note", 535, 393, 460, 46, "#071207", "#335533", 1, 3);
            VI.label("pc_gn1", "Gray code: exactly 1 bit changes per step.", 770, 397, "#a5d6a7",  9, "sans-serif", "center");
            VI.label("pc_gn2", "2-FF synchronizer resolves at most 1 metastable bit.", 770, 408, "#4caf50",  9, "sans-serif", "center");
            VI.label("pc_gn3", "The synchronized value is always wr_ptr_gray +/- 1 or exact.", 770, 419, "#81c784", 8, "sans-serif", "center");
            VI.label("pc_gn4", "Off-by-one is tolerable: FIFO is slightly pessimistic, never corrupt.", 770, 430, "#546e7a", 8, "sans-serif", "center");

            // ---- Full FIFO scheme ----
            VI.rect("pc_fifo_bg", 530, 452, 1000, 240, "#080c10", "#334466", 2, 5);
            VI.label("pc_fifo_t", "FULL ASYNC FIFO POINTER SYNCHRONIZATION SCHEME", 1030, 459, "#4fc3f7", 12, "sans-serif", "center");

            // Write domain
            VI.rect("pc_wd_bg", 536, 476, 310, 180, "#071007", "#4caf50", 1, 4);
            VI.label("pc_wd_t",  "WRITE DOMAIN (clk_a)", 691, 482, "#4caf50", 10, "sans-serif", "center");
            VI.label("pc_wd_1",  "wr_ptr_bin++",          545, 498, "#a5d6a7", 9, "monospace");
            VI.rect("pc_wd_arr1", 625, 504, 14, 2, "#81c784");
            VI.label("pc_wd_2",  "gray_conv",             640, 498, "#ffd54f", 9, "monospace");
            VI.rect("pc_wd_arr2", 700, 504, 14, 2, "#4fc3f7");
            VI.label("pc_wd_3",  "wr_ptr_gray",           715, 498, "#4fc3f7", 9, "monospace");

            VI.rect("pc_2ff_wd", 545, 516, 140, 30, "#0a1a2a", "#4fc3f7", 1, 3);
            VI.label("pc_2ffw_t", "2-FF SYNC -> read domain", 615, 521, "#4fc3f7", 8, "monospace", "center");
            VI.label("pc_2ffw_2", "synced_wr_gray_rd",        615, 531, "#81c784", 8, "monospace", "center");

            VI.label("pc_full_t",   "FULL detection (write domain):", 545, 557, "#ffd54f", 8, "sans-serif");
            VI.label("pc_full_1",   "top 2 bits inverted comparison", 545, 568, "#ff9800", 8, "monospace");
            VI.label("pc_full_2",   "between wr_gray and synced_rd_gray", 545, 579, "#ff9800", 8, "monospace");
            VI.rect("pc_full_box", 545, 590, 295, 18, "#1a0a00", "#ff9800", 1, 3);
            VI.label("pc_full_3",   "full = (wr[3]!=rd[3]) & (wr[2]!=rd[2]) & (wr[1:0]==rd[1:0])", 548, 593, "#ffc107", 7, "monospace");

            VI.label("pc_empt_t",   "EMPTY detection (read domain):", 545, 618, "#a5d6a7", 8, "sans-serif");
            VI.rect("pc_empt_box", 545, 628, 295, 18, "#001500", "#4caf50", 1, 3);
            VI.label("pc_empt_1",   "empty = (synced_wr_gray_rd == rd_ptr_gray)", 548, 631, "#81c784", 7, "monospace");
            VI.label("pc_empt_lv",  "current: empty = " + fifo_empty, 545, 650, fifo_empty ? "#f44336" : "#4caf50", 9, "monospace");

            // Read domain
            VI.rect("pc_rd_bg", 1025, 476, 498, 180, "#071007", "#2196f3", 1, 4);
            VI.label("pc_rd_t",  "READ DOMAIN (clk_b)", 1274, 482, "#2196f3", 10, "sans-serif", "center");
            VI.label("pc_rd_1",  "rd_ptr_bin++",         1034, 498, "#90caf9", 9, "monospace");
            VI.rect("pc_rd_arr1", 1114, 504, 14, 2, "#64b5f6");
            VI.label("pc_rd_2",  "gray_conv",             1129, 498, "#ffd54f", 9, "monospace");
            VI.rect("pc_rd_arr2", 1189, 504, 14, 2, "#4fc3f7");
            VI.label("pc_rd_3",  "rd_ptr_gray",           1204, 498, "#4fc3f7", 9, "monospace");

            VI.rect("pc_2ff_rd", 1034, 516, 140, 30, "#0a1a2a", "#2196f3", 1, 3);
            VI.label("pc_2ffr_t", "2-FF SYNC -> write domain", 1104, 521, "#64b5f6", 8, "monospace", "center");
            VI.label("pc_2ffr_2", "synced_rd_gray_wr",         1104, 531, "#90caf9", 8, "monospace", "center");

            VI.label("pc_rn1", "Both pointer sync chains are independent.", 1034, 568, "#546e7a", 8, "sans-serif");
            VI.label("pc_rn2", "Write domain syncs WR ptr into read domain", 1034, 579, "#546e7a", 8, "sans-serif");
            VI.label("pc_rn3", "for EMPTY. Read domain syncs RD ptr into",    1034, 590, "#546e7a", 8, "sans-serif");
            VI.label("pc_rn4", "write domain for FULL.",                       1034, 601, "#546e7a", 8, "sans-serif");
            VI.label("pc_rn5", "2 cycles of latency on each path.",            1034, 612, "#37474f", 8, "sans-serif");
            VI.label("pc_rn6", "Gray code ensures at most 1 bit meta-stable.", 1034, 623, "#37474f", 8, "sans-serif");

            // Cross-domain arrows
            VI.rect("pc_cross1a", 688, 547, 2, 10, "#4caf50");
            VI.rect("pc_cross1b", 688, 557, 337, 2, "#ff9800");
            VI.rect("pc_cross1c", 1025, 546, 2, 13, "#2196f3");
            VI.label("pc_cross1l", "synced_wr_gray_rd", 810, 545, "#78909c", 7, "monospace");

            VI.rect("pc_cross2a", 1104, 547, 2, 80, "#2196f3");
            VI.rect("pc_cross2b", 688, 625, 416, 2, "#ff9800");
            VI.rect("pc_cross2c", 688, 614, 2, 13, "#4caf50");
            VI.label("pc_cross2l", "synced_rd_gray_wr", 810, 617, "#78909c", 7, "monospace");

            // ---- Waveform strip: last 16 cycles ----
            VI.rect("pc_wave_bg", 530, 698, 1000, 140, "#06090c", "#334466", 1, 5);
            VI.label("pc_wave_t", "WAVEFORM: wr_ptr_bin and wr_ptr_gray (last 16 cycles)", 1030, 705, "#4fc3f7", 10, "sans-serif", "center");

            const W_START_X = 540;
            const W_CELL_W  = 58;
            const W_ROW1_Y  = 720;
            const W_ROW2_Y  = 754;
            const W_ROW3_Y  = 788;
            const W_ROWS    = 16;

            VI.label("pc_wbin_lbl",  "bin: ", 542, W_ROW1_Y + 4, "#ffd54f", 8, "monospace");
            VI.label("pc_wgray_lbl", "gray:", 542, W_ROW2_Y + 4, "#4fc3f7", 8, "monospace");
            VI.label("pc_wchg_lbl",  "chg: ", 542, W_ROW3_Y + 4, "#ff9800", 8, "monospace");

            for (let wi = 0; wi < W_ROWS; wi++) {
               (function(i) {
                  const wc  = safeCyc(cyc - (W_ROWS - 1 - i));
                  const wb  = getSig("TLV|gray_fifo$wr_ptr_bin",  wc, 0);
                  const wg  = getSig("TLV|gray_fifo$wr_ptr_gray", wc, 0);
                  const pwb = getSig("TLV|gray_fifo$wr_ptr_bin",  safeCyc(wc - 1), 0);
                  const pwg = getSig("TLV|gray_fifo$wr_ptr_gray", safeCyc(wc - 1), 0);
                  const bchg = popcount(wb ^ pwb);
                  const gchg = popcount(wg ^ pwg);
                  const wx  = W_START_X + 30 + i * W_CELL_W;
                  const isCur = (wc === cyc);

                  // Background highlight for current cycle
                  if (isCur) {
                     VI.rect("pc_wcur_" + i, wx - 1, W_ROW1_Y - 3, W_CELL_W - 2, 110, "#101820", "#4fc3f7", 1, 0);
                  }

                  VI.label("pc_wbin_" + i,  toBin4(wb),  wx + W_CELL_W/2, W_ROW1_Y + 3, "#ffd54f", 8, "monospace", "center");
                  VI.label("pc_wgray_" + i, toBin4(wg),  wx + W_CELL_W/2, W_ROW2_Y + 3, "#4fc3f7", 8, "monospace", "center");
                  VI.label("pc_wbchg_" + i, "b:" + bchg, wx + W_CELL_W/2, W_ROW3_Y + 3, bchg > 1 ? "#f44336" : "#81c784", 8, "monospace", "center");
                  VI.label("pc_wgchg_" + i, "g:" + gchg, wx + W_CELL_W/2, W_ROW3_Y + 14, gchg > 1 ? "#f44336" : "#4caf50", 8, "monospace", "center");
                  VI.label("pc_wcyc_" + i,  String(wc),  wx + W_CELL_W/2, W_ROW3_Y + 27, "#37474f", 7, "monospace", "center");

                  // Divider
                  if (i > 0) {
                     VI.rect("pc_wdiv_" + i, wx - 1, W_ROW1_Y - 2, 1, 100, "#1a2a3a");
                  }
               })(wi);
            }

            // ---- Hardened FIFO note ----
            VI.rect("pc_fifo36_bg", 530, 844, 1000, 90, "#070710", "#7e57c2", 2, 5);
            VI.label("pc_f36_t",  "FIFO36E1 -- HARDENED CDC SOLUTION (XC7S50 BRAM tile)", 1030, 851, "#7e57c2", 12, "sans-serif", "center");
            VI.label("pc_f36_1",  "This entire gray-code synchronization scheme is implemented in hardened silicon within the BRAM tile.", 1030, 867, "#b39ddb", 9, "sans-serif", "center");
            VI.label("pc_f36_2",  "FIFO36E1 gives you: gray-code pointers, 2-FF sync chains, EMPTY/FULL flags -- all metastability-safe.", 1030, 879, "#9c27b0", 9, "sans-serif", "center");
            VI.label("pc_f36_3",  "Always prefer FIFO36E1/FIFO18E1 for CDC data transfer. Never roll your own FIFO across clock domains.", 1030, 891, "#7e57c2", 9, "sans-serif", "center");
            VI.label("pc_f36_4",  "Instantiate via XPM_FIFO_ASYNC for portable, vendor-supported CDC FIFO in UltraScale and 7-series.", 1030, 903, "#4a148c", 9, "sans-serif", "center");
            VI.label("pc_f36_5",  "Depth: 512 to 32768 bits. Width: 4-72 bits. ECC optional. 2-cycle EMPTY/FULL latency.", 1030, 915, "#37474f", 8, "sans-serif", "center");

            // ---- CDC pattern expand buttons (right panel) ----
            const expCFill = this._expandC ? "#0e0a20" : "#080610";
            VI.rect("pc_expC_btn", 1025, 480, 480, 16, expCFill, "#ab47bc", 1, 3);
            VI.label("pc_expC_lbl", (this._expandC ? "[-]" : "[+]") + " CDC Pattern Comparison: sync vs handshake vs pulse vs gray", 1030, 482, "#ce93d8", 7, "monospace");
            VI.onClick("pc_expC_btn", 1025, 480, 480, 16, function() { self._expandC = !self._expandC; VI.redraw(); });

            if (this._expandC) {
               VI.rect("pc_expC_bg", 1025, 497, 480, 90, "#07040e", "#ab47bc", 1, 3);
               VI.label("pc_ec1", "SINGLE-BIT SYNC: 2-FF chain. Use for control signals (valid, req, ack).", 1030, 500, "#ce93d8", 8, "sans-serif");
               VI.label("pc_ec2", "HANDSHAKE: req -> sync -> ack -> sync. Use for wide data bursts.", 1030, 512, "#ce93d8", 8, "sans-serif");
               VI.label("pc_ec3", "PULSE SYNC: req toggle -> 2-FF -> edge detect. Single-cycle pulses.", 1030, 524, "#ce93d8", 8, "sans-serif");
               VI.label("pc_ec4", "GRAY CODE FIFO: multi-word stream. Throughput: 1 word per wr_clk.", 1030, 536, "#ce93d8", 8, "sans-serif");
               VI.label("pc_ec5", "CAUTION: Never synchronize multi-bit binary values directly.", 1030, 548, "#f44336", 8, "sans-serif");
               VI.label("pc_ec6", "Always use gray code, handshake, or hardened FIFO for wide buses.", 1030, 560, "#ff9800", 8, "sans-serif");
               VI.label("pc_ec7", "MUX select signals are multi-bit: must use handshake or FIFO.", 1030, 572, "#78909c", 8, "sans-serif");
               VI.label("pc_ec8", "AXI4 crossings: use AXI CDC bridge IP (Xilinx). Never raw wires.", 1030, 584, "#37474f", 8, "sans-serif");
            }

            // ================================================================
            // GLOBAL CYCLE SCRUBBER
            // ================================================================
            VI.rect("sc_bg", 15, 943, 1520, 3, "#1a2a3a");
            const scX = 15 + (cyc - wd.startCycle) * 1520 / Math.max(1, wd.endCycle - wd.startCycle);
            VI.rect("sc_h", Math.min(scX, 1520), 940, 4, 8, "#4fc3f7");

            // ================================================================
            // CAMERA AUTO-CENTERING
            // ================================================================
            if (this._firstRender) {
               this._firstRender = false;
               try {
                  pane.content.contentScale = 0.85;
                  pane.content.userFocus    = {x: 780, y: 475};
                  pane.content.refreshContentPosition();
               } catch(e) {}
            }
         }
\SV
   endmodule
