
\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
\SV
   m5_makerchip_module
\TLV
   // ==============================================================================
   // XC7S50 CLOCK TREE EXPLORER
   // Static topology visualization — no simulation signals needed.
   // All educational value is in the viz_js rendering.
   // ==============================================================================
   |clk
      @1
         $reset = *reset;
         // Minimal signals to drive minor UI state
         $cyc[15:0] = *cyc_cnt[15:0];
         `BOGUS_USE($reset $cyc)

   *passed = *cyc_cnt > 100;
   *failed = 1'b0;

   /viz
      \viz_js
         box: {width: 1500, height: 1000, fill: "#07090f"},

         init() {
            // ================================================================
            // VizInteract v2.0 Boilerplate
            // ================================================================
            const self = this;
            const VI = {};
            this._VI = VI;

            VI._labels = {}; VI._objects = {}; VI._clickZones = [];
            VI._hoverZones = {}; VI._hotkeys = {};

            VI.redraw = function() {
               if (self._viz && self._viz.pane) {
                  self._viz.pane.unrender();
                  self._viz.pane.render();
               }
               self.getCanvas().renderAll();
            };

            const canvasEl = fabric.document.querySelector("canvas");
            const focusTarget = canvasEl ? canvasEl.closest("div") : null;
            if (focusTarget) {
               focusTarget.setAttribute("tabindex", "0");
               setTimeout(function() { focusTarget.focus(); }, 400);
            }

            VI.toCanvasCoords = function(cx, cy) {
               if (!canvasEl) return {x: 0, y: 0};
               const rect = canvasEl.getBoundingClientRect();
               const vpt = self.getCanvas().viewportTransform || [1,0,0,1,0,0];
               return {
                  x: Math.round((cx - rect.left - vpt[4]) / vpt[0]),
                  y: Math.round((cy - rect.top  - vpt[5]) / vpt[3])
               };
            };

            VI.label = function(id, text, x, y, color, fz, ff, align) {
               const c = self.getCanvas();
               if (!VI._labels[id]) {
                  const obj = new fabric.Text(String(text), {
                     left: x, top: y, fontSize: fz||13, fill: color||"#c8d0e0",
                     selectable: false, evented: false,
                     fontFamily: ff||"monospace", originX: align||"left"
                  });
                  c.add(obj); VI._labels[id] = obj;
               } else {
                  VI._labels[id].set({
                     text: String(text), left: x, top: y,
                     fill: color || VI._labels[id].fill
                  });
               }
               return VI._labels[id];
            };

            VI.rect = function(id, x, y, w, h, fill, stroke, sw, rx) {
               const c = self.getCanvas();
               sw = (sw === undefined) ? 0 : sw;
               rx = (rx === undefined) ? 0 : rx;
               if (!VI._objects[id]) {
                  const obj = new fabric.Rect({
                     left: x, top: y, width: w, height: h,
                     fill: fill||"#1a2030",
                     stroke: stroke||"transparent",
                     strokeWidth: sw, rx: rx, ry: rx,
                     selectable: false, evented: false
                  });
                  c.add(obj); VI._objects[id] = obj;
               } else {
                  VI._objects[id].set({
                     left: x, top: y, width: w, height: h,
                     fill: fill||VI._objects[id].fill,
                     stroke: stroke||VI._objects[id].stroke,
                     strokeWidth: sw
                  });
               }
               return VI._objects[id];
            };

            VI.line = function(id, x1, y1, x2, y2, color, sw) {
               const c = self.getCanvas();
               sw = sw || 2;
               if (!VI._objects[id]) {
                  const obj = new fabric.Line([x1,y1,x2,y2], {
                     stroke: color||"#4fc3f7", strokeWidth: sw,
                     selectable: false, evented: false
                  });
                  c.add(obj); VI._objects[id] = obj;
               } else {
                  VI._objects[id].set({
                     x1:x1, y1:y1, x2:x2, y2:y2,
                     stroke: color||VI._objects[id].stroke, strokeWidth: sw
                  });
               }
               return VI._objects[id];
            };

            VI.onClick = function(id, x, y, w, h, cb) {
               VI._clickZones = VI._clickZones.filter(function(z) { return z.id !== id; });
               VI._clickZones.push({id:id, x:x, y:y, w:w, h:h, cb:cb});
            };

            VI.onHover = function(id, x, y, w, h, enter, leave) {
               VI._hoverZones[id] = {x:x, y:y, w:w, h:h, enter:enter, leave:leave, inside: false};
            };

            VI.clearAll = function() {
               self.getCanvas().clear();
               VI._labels = {}; VI._objects = {};
               VI._clickZones = []; VI._hoverZones = {};
            };

            const _hit = function(z, cx, cy) {
               return cx >= z.x && cx <= z.x+z.w && cy >= z.y && cy <= z.y+z.h;
            };

            fabric.document.addEventListener("mouseup", function(e) {
               const pos = VI.toCanvasCoords(e.clientX, e.clientY);
               VI._clickZones.forEach(function(z) { if (_hit(z,pos.x,pos.y)) z.cb(pos.x,pos.y); });
            });

            fabric.document.addEventListener("mousemove", function(e) {
               const pos = VI.toCanvasCoords(e.clientX, e.clientY);
               Object.keys(VI._hoverZones).forEach(function(id) {
                  const z = VI._hoverZones[id];
                  const inside = _hit(z, pos.x, pos.y);
                  if (inside && !z.inside) { z.inside = true; if(z.enter) z.enter(); }
                  else if (!inside && z.inside) { z.inside = false; if(z.leave) z.leave(); }
               });
            });

            fabric.window.addEventListener("keydown", function(e) {
               if (VI._hotkeys[e.key]) VI._hotkeys[e.key](e);
            });

            // Camera helpers (direct pane.content access)
            self._cam = {
               set: function(scale, fx, fy) {
                  const p = self._viz.pane;
                  if (!p || !p.content) return;
                  p.content.contentScale = scale;
                  p.content.userFocus = {x: fx, y: fy};
                  p.content.refreshContentPosition();
               }
            };

            // ================================================================
            // UI STATE
            // ================================================================
            self.selected = null;
            self.tooltip  = null;
            self.expandedId   = null;
            self.expandRect   = null;
            self.expandType   = null;

            // Session cycle sync
            const pane = self._viz.pane;
            if (pane && pane.session) {
               pane.session.on("cycle-update", function() { VI.redraw(); });
            }

            // Hotkeys
            VI._hotkeys["Escape"] = function() { 
               self.selected = null; 
               self.expandedId = null;
               self.expandRect = null;
               self.expandType = null;
               VI.redraw(); 
            };
            VI._hotkeys["1"] = function() { self.selected = "bufg";  VI.redraw(); };
            VI._hotkeys["2"] = function() { self.selected = "bufr";  VI.redraw(); };
            VI._hotkeys["3"] = function() { self.selected = "bufio"; VI.redraw(); };
            VI._hotkeys["4"] = function() { self.selected = "mmcm";  VI.redraw(); };
            VI._hotkeys["5"] = function() { self.selected = "pll";   VI.redraw(); };
            VI._hotkeys["h"] = function() { self.selected = "htree"; VI.redraw(); };

            this._firstRender = true;
         },

         onTraceData() { this._firstRender = true; },

         render() {
            const VI = this._VI; if (!VI) return;
            VI.clearAll();

            const pane = this._viz.pane;
            const self = this;
            const C    = self.getCanvas();

            // ================================================================
            // DRAW EXPANSION FUNCTIONS (defined before rendering)
            // ================================================================
            const drawExpand_BUFG = function(px, py, pw, ph) {
               VI.label("ex_bufg_title", "BUFG " + String.fromCharCode(8212) + " INTERNAL STRUCTURE", px+pw/2, py+12, "#4fc3f7", 13, "sans-serif", "center");
               
               // CLK_IN
               VI.rect("ex_bufg_clkin", px+0.05*pw, py+0.12*ph, 0.18*pw, 0.12*ph, "#0a1a2a", "#4fc3f7", 1);
               VI.label("ex_bufg_clkin_l", "CLK_IN", px+0.14*pw, py+0.16*ph, "#4fc3f7", 11, "sans-serif", "center");
               VI.rect("ex_bufg_a1", px+0.23*pw, py+0.17*ph, 0.08*pw, 3, "#4fc3f7");

               // CE_GATE
               VI.rect("ex_bufg_ceg", px+0.31*pw, py+0.10*ph, 0.20*pw, 0.16*ph, "#0d1f0d", "#66bb6a", 1);
               VI.label("ex_bufg_ceg_l1", "CE GATE", px+0.41*pw, py+0.13*ph, "#66bb6a", 11, "sans-serif", "center");
               VI.label("ex_bufg_ceg_l2", "AND logic", px+0.41*pw, py+0.10*ph + 0.07*ph, "#405060", 9, "sans-serif", "center");
               VI.rect("ex_bufg_a2", px+0.51*pw, py+0.17*ph, 0.14*pw, 3, "#4fc3f7");

               // H-TREE OUTPUT
               VI.rect("ex_bufg_out", px+0.65*pw, py+0.12*ph, 0.28*pw, 0.12*ph, "#0a1a2a", "#4fc3f7", 1);
               VI.label("ex_bufg_out_l", "H-TREE OUTPUT", px+0.79*pw, py+0.16*ph, "#4fc3f7", 11, "sans-serif", "center");

               // CE input
               VI.rect("ex_bufg_cea", px+0.41*pw, py+0.30*ph, 3, 0.10*ph, "#66bb6a");
               VI.label("ex_bufg_cea_l", "CE (must be sync)", px+0.41*pw+5, py+0.38*ph, "#66bb6a", 9, "sans-serif");

               // Timing
               for(let i=0; i<8; i++) {
                  VI.rect("ex_bufg_t_h_"+i, px+0.15*pw + i*0.08*pw, py+0.50*ph, 0.04*pw, 2, "#4fc3f7");
                  VI.rect("ex_bufg_t_l_"+i, px+0.19*pw + i*0.08*pw, py+0.55*ph, 0.04*pw, 2, "#4fc3f7");
                  VI.rect("ex_bufg_t_v1_"+i, px+0.15*pw + i*0.08*pw, py+0.50*ph, 2, 0.05*ph, "#4fc3f7");
                  if (i < 7) VI.rect("ex_bufg_t_v2_"+i, px+0.19*pw + i*0.08*pw, py+0.50*ph, 2, 0.05*ph, "#4fc3f7");
               }
               VI.label("ex_bufg_t_lclk", "CLK", px+0.14*pw, py+0.52*ph, "#4fc3f7", 10, "sans-serif", "right");

               VI.rect("ex_bufg_t_sy", px+0.35*pw, py+0.62*ph, 0.08*pw, 4, "#66bb6a");
               VI.label("ex_bufg_t_lsy", "CE_SYNC", px+0.14*pw, py+0.61*ph, "#66bb6a", 10, "sans-serif", "right");

               VI.rect("ex_bufg_t_as", px+0.65*pw, py+0.72*ph, 0.08*pw, 4, "#f44336");
               VI.label("ex_bufg_t_las", "CE_ASYNC", px+0.14*pw, py+0.71*ph, "#f44336", 10, "sans-serif", "right");
               VI.rect("ex_bufg_t_warnb", px+0.63*pw, py+0.68*ph, 0.28*pw, 0.10*ph, "transparent", "#f44336", 1);
               VI.label("ex_bufg_t_warnl", "PARTIAL PULSE = CORRUPTION", px+0.77*pw, py+0.71*ph, "#f44336", 9, "sans-serif", "center");

               // Counter
               VI.label("ex_bufg_cnt_l", "MAX 12 ACTIVE PER REGION", px+0.05*pw, py+0.78*ph, "#607080", 9, "sans-serif");
               for(let i=0; i<13; i++) {
                  let bx = px+0.05*pw + i*(0.06*pw + 2);
                  let c = (i<8) ? "#4fc3f7" : (i<12) ? "#ff9800" : "#f44336";
                  VI.rect("ex_bufg_cb_"+i, bx, py+0.82*ph, 0.06*pw, 0.08*ph, c);
                  if (i===12) VI.label("ex_bufg_ce", "13th = DRC ERROR", bx+0.03*pw, py+0.92*ph, "#f44336", 9, "sans-serif", "center");
               }
            };

            const drawExpand_BUFR = function(px, py, pw, ph) {
               VI.label("ex_bufr_title", "BUFR " + String.fromCharCode(8212) + " REGIONAL CLOCK BUFFER", px+pw/2, py+12, "#ff9800", 13, "sans-serif", "center");
               
               // Divider chain
               VI.rect("ex_bufr_in", px+0.05*pw, py+0.20*ph, 0.10*pw, 0.08*ph, "#1a0a00", "#ff9800", 1);
               VI.label("ex_bufr_in_l", "CLK_IN", px+0.10*pw, py+0.23*ph, "#ff9800", 10, "sans-serif", "center");
               VI.rect("ex_bufr_a1", px+0.15*pw, py+0.24*ph, 0.10*pw, 2, "#ff9800");

               VI.rect("ex_bufr_cnt", px+0.25*pw, py+0.12*ph, 0.18*pw, 0.25*ph, "#1a1000", "#ff9800", 1);
               VI.label("ex_bufr_cnt_l1", "3-BIT DIVIDER", px+0.34*pw, py+0.16*ph, "#ff9800", 10, "sans-serif", "center");
               VI.label("ex_bufr_cnt_l2", "" + String.fromCharCode(247) + "1 " + String.fromCharCode(247) + "2 " + String.fromCharCode(247) + "4 " + String.fromCharCode(247) + "6 " + String.fromCharCode(247) + "8", px+0.34*pw, py+0.28*ph, "#ff9800", 9, "sans-serif", "center");

               const taps = ["1", "2", "4", "6", "8"];
               taps.forEach(function(t, i) {
                  let ty = py + 0.15*ph + i*0.04*ph;
                  VI.rect("ex_bufr_t_"+i, px+0.43*pw, ty, 0.19*pw, 2, "#ff9800");
                  VI.label("ex_bufr_tl_"+i, String.fromCharCode(247) + t, px+0.52*pw, ty-10, "#ff9800", 10, "sans-serif", "center");
               });

               VI.rect("ex_bufr_mux", px+0.62*pw, py+0.12*ph, 0.12*pw, 0.25*ph, "#1a1000", "#ff9800", 1);
               VI.label("ex_bufr_mux_l", "OUTPUT SEL", px+0.68*pw, py+0.23*ph, "#ff9800", 10, "sans-serif", "center");

               // Region illustration
               VI.rect("ex_bufr_r1", px+0.05*pw, py+0.52*ph, 0.40*pw, 0.20*ph, "#0a1a0a", "#ff9800", 2);
               VI.label("ex_bufr_r1_l", "THIS REGION", px+0.25*pw, py+0.60*ph, "#ff9800", 11, "sans-serif", "center");
               
               VI.rect("ex_bufr_hb", px+0.49*pw, py+0.50*ph, 4, 0.25*ph, "#f44336");
               VI.label("ex_bufr_hb_l", "HARD BOUNDARY", px+0.49*pw, py+0.46*ph, "#f44336", 9, "sans-serif", "center");

               VI.rect("ex_bufr_r2", px+0.55*pw, py+0.52*ph, 0.40*pw, 0.20*ph, "#0a0a0a", "#333333", 2);
               VI.label("ex_bufr_r2_l", "OTHER REGION (forbidden)", px+0.75*pw, py+0.60*ph, "#333333", 11, "sans-serif", "center");

               VI.rect("ex_bufr_x1", px+0.65*pw, py+0.57*ph, 0.20*pw, 4, "#f44336");
               VI.rect("ex_bufr_x2", px+0.65*pw, py+0.67*ph, 0.20*pw, -4, "#f44336");

               // BUFMR
               VI.rect("ex_bufr_mr", px+0.05*pw, py+0.78*ph, 0.10*pw, 0.08*ph, "#1a1a2a", "#8090a0", 1);
               VI.label("ex_bufr_mr_l", "BUFMR", px+0.10*pw, py+0.81*ph, "#8090a0", 9, "sans-serif", "center");
               VI.rect("ex_bufr_mra", px+0.10*pw, py+0.86*ph, 2, 0.05*ph, "#8090a0");
               VI.label("ex_bufr_mr_n", "Can feed BUFRs across adjacent regions", px+0.15*pw, py+0.86*ph, "#607080", 9, "sans-serif", "left");
            };

            const drawExpand_BUFIO = function(px, py, pw, ph) {
               VI.label("ex_bufio_title", "BUFIO " + String.fromCharCode(8212) + " I/O CLOCK BUFFER (I/O ONLY)", px+pw/2, py+12, "#66bb6a", 13, "sans-serif", "center");
               
               // ALLOWED zone
               VI.rect("ex_bufio_z1", px+0.05*pw, py+0.14*ph, 0.40*pw, 0.55*ph, "#081408", "#66bb6a", 2);
               VI.label("ex_bufio_z1_l", "ILOGIC / OLOGIC", px+0.25*pw, py+0.18*ph, "#66bb6a", 10, "sans-serif", "center");
               for(let i=0; i<4; i++) {
                  VI.rect("ex_bufio_is_"+i, px+0.15*pw, py+0.28*ph + i*0.10*ph, 0.20*pw, 0.06*ph, "#0a200a", "#66bb6a", 1);
                  VI.label("ex_bufio_isl_"+i, "ISERDESE2", px+0.25*pw, py+0.30*ph + i*0.10*ph, "#66bb6a", 8, "sans-serif", "center");
               }

               // FORBIDDEN zone
               VI.rect("ex_bufio_z2", px+0.55*pw, py+0.14*ph, 0.40*pw, 0.55*ph, "#140808", "#f44336", 2);
               VI.label("ex_bufio_z2_l", "CLB FLIP-FLOPS", px+0.75*pw, py+0.18*ph, "#f44336", 10, "sans-serif", "center");
               for(let i=0; i<4; i++) {
                  VI.rect("ex_bufio_ff_"+i, px+0.65*pw, py+0.28*ph + i*0.10*ph, 0.20*pw, 0.06*ph, "#200a0a", "#f44336", 1);
                  VI.label("ex_bufio_ffl_"+i, "FDRE", px+0.75*pw, py+0.30*ph + i*0.10*ph, "#f44336", 8, "sans-serif", "center");
               }
               
               VI.rect("ex_bufio_x1", px+0.60*pw, py+0.25*ph, 0.30*pw, 4, "#f44336");
               VI.rect("ex_bufio_x2", px+0.60*pw, py+0.60*ph, 0.30*pw, -4, "#f44336");
               VI.label("ex_bufio_warn", "CANNOT DRIVE", px+0.75*pw, py+0.40*ph, "#f44336", 11, "sans-serif", "center");

               // BUFIO block
               VI.rect("ex_bufio_blk", px+0.05*pw, py+0.72*ph, 0.20*pw, 0.14*ph, "#0a1a0a", "#66bb6a", 1);
               VI.label("ex_bufio_blkl", "BUFIO", px+0.15*pw, py+0.78*ph, "#66bb6a", 10, "sans-serif", "center");

               // Arrows
               VI.rect("ex_bufio_a1", px+0.25*pw, py+0.78*ph, 0.30*pw, 4, "#66bb6a");
               VI.rect("ex_bufio_a1v", px+0.40*pw, py+0.69*ph, 4, 0.09*ph, "#66bb6a");

               VI.rect("ex_bufio_a2", px+0.55*pw, py+0.78*ph, 0.10*pw, 4, "#f44336");
               VI.rect("ex_bufio_a2b", px+0.65*pw, py+0.74*ph, 4, 0.08*ph, "#f44336");

               VI.label("ex_bufio_n1", "Source: must use MRCC/SRCC clock-capable I/O pin", px+0.05*pw, py+0.88*ph, "#607080", 9, "sans-serif", "left");
               VI.label("ex_bufio_n2", "Within-bank skew: < 100 ps  (best for SERDES capture)", px+0.05*pw, py+0.93*ph, "#66bb6a", 9, "sans-serif", "left");
            };

            const drawExpand_MMCM = function(px, py, pw, ph) {
               VI.label("ex_mmcm_title", "MMCME2 " + String.fromCharCode(8212) + " PHASE-LOCKED LOOP ARCHITECTURE", px+pw/2, py+12, "#ce93d8", 13, "sans-serif", "center");
               
               VI.rect("ex_mmcm_ref", px+0.02*pw, py+0.20*ph, 0.12*pw, 0.10*ph, "#0f0a1a", "#ce93d8", 1);
               VI.label("ex_mmcm_refl1", "REF_CLK", px+0.08*pw, py+0.23*ph, "#ce93d8", 9, "sans-serif", "center");
               VI.label("ex_mmcm_refl2", "DIVCLK_DIV", px+0.08*pw, py+0.27*ph, "#ce93d8", 9, "sans-serif", "center");

               VI.rect("ex_mmcm_a1", px+0.14*pw, py+0.25*ph, 0.03*pw, 3, "#ce93d8");

               VI.rect("ex_mmcm_pd", px+0.17*pw, py+0.20*ph, 0.14*pw, 0.10*ph, "#1a0f2a", "#ce93d8", 1);
               VI.label("ex_mmcm_pdl1", "PHASE", px+0.24*pw, py+0.23*ph, "#ce93d8", 9, "sans-serif", "center");
               VI.label("ex_mmcm_pdl2", "DETECTOR", px+0.24*pw, py+0.27*ph, "#ce93d8", 9, "sans-serif", "center");

               VI.rect("ex_mmcm_a2", px+0.31*pw, py+0.25*ph, 0.04*pw, 3, "#ce93d8");

               VI.rect("ex_mmcm_lf", px+0.35*pw, py+0.20*ph, 0.13*pw, 0.10*ph, "#1a0f2a", "#ce93d8", 1);
               VI.label("ex_mmcm_lfl1", "LOOP", px+0.415*pw, py+0.23*ph, "#ce93d8", 9, "sans-serif", "center");
               VI.label("ex_mmcm_lfl2", "FILTER", px+0.415*pw, py+0.27*ph, "#ce93d8", 9, "sans-serif", "center");

               VI.rect("ex_mmcm_a3", px+0.48*pw, py+0.25*ph, 0.04*pw, 3, "#ce93d8");

               VI.rect("ex_mmcm_vco", px+0.52*pw, py+0.18*ph, 0.14*pw, 0.14*ph, "#2a1a0f", "#ff9800", 1);
               VI.label("ex_mmcm_vcol1", "VCO", px+0.59*pw, py+0.21*ph, "#ff9800", 9, "sans-serif", "center");
               VI.label("ex_mmcm_vcol2", "600-1600", px+0.59*pw, py+0.25*ph, "#ff9800", 9, "sans-serif", "center");
               VI.label("ex_mmcm_vcol3", "MHz", px+0.59*pw, py+0.29*ph, "#ff9800", 9, "sans-serif", "center");

               VI.rect("ex_mmcm_a4", px+0.66*pw, py+0.25*ph, 0.04*pw, 3, "#ce93d8");

               VI.rect("ex_mmcm_outd", px+0.70*pw, py+0.20*ph, 0.13*pw, 0.10*ph, "#0f1a2a", "#4fc3f7", 1);
               VI.label("ex_mmcm_outl1", "OUT DIV", px+0.765*pw, py+0.23*ph, "#4fc3f7", 9, "sans-serif", "center");
               VI.label("ex_mmcm_outl2", "CLKOUTn", px+0.765*pw, py+0.27*ph, "#4fc3f7", 9, "sans-serif", "center");

               VI.rect("ex_mmcm_fb", px+0.35*pw, py+0.52*ph, 0.14*pw, 0.10*ph, "#1a0f2a", "#ce93d8", 1);
               VI.label("ex_mmcm_fbl1", "FB DIV", px+0.42*pw, py+0.55*ph, "#ce93d8", 9, "sans-serif", "center");
               VI.label("ex_mmcm_fbl2", "MULT_F", px+0.42*pw, py+0.59*ph, "#ce93d8", 9, "sans-serif", "center");

               // Feedback path
               VI.rect("ex_mmcm_fba1", px+0.765*pw, py+0.30*ph, 3, 0.27*ph, "#ce93d8");
               VI.rect("ex_mmcm_fba2", px+0.49*pw, py+0.57*ph, 0.275*pw, 3, "#ce93d8");
               VI.rect("ex_mmcm_fba3", px+0.42*pw, py+0.30*ph, 3, 0.22*ph, "#ce93d8");
               VI.rect("ex_mmcm_fba4", px+0.24*pw, py+0.30*ph, 3, 0.27*ph, "#ce93d8");
               VI.rect("ex_mmcm_fba5", px+0.24*pw, py+0.57*ph, 0.11*pw, 3, "#ce93d8");

               // VCO bar
               VI.rect("ex_mmcm_vb", px+0.52*pw, py+0.38*ph, 0.14*pw, 0.08*ph, "#1a1000", "#333333", 1);
               VI.rect("ex_mmcm_vg", px+0.53*pw, py+0.39*ph, 0.12*pw, 0.06*ph, "#2a4a00");
               VI.label("ex_mmcm_vbl1", "600", px+0.53*pw, py+0.42*ph, "#ff9800", 8, "sans-serif", "left");
               VI.label("ex_mmcm_vbl2", "1600", px+0.65*pw, py+0.42*ph, "#ff9800", 8, "sans-serif", "right");
               VI.label("ex_mmcm_vbl3", "MHz", px+0.59*pw, py+0.48*ph, "#ff9800", 8, "sans-serif", "center");

               // Outputs
               for(let i=0; i<7; i++) {
                  let oy = py + 0.15*ph + i*0.04*ph;
                  VI.rect("ex_mmcm_o_"+i, px+0.83*pw, oy, 0.08*pw, 2, "#4fc3f7");
                  let lstr = (i===0) ? "CLKOUT0 (frac)" : "CLKOUT"+i;
                  let lc = (i===0) ? "#66bb6a" : "#4fc3f7";
                  VI.label("ex_mmcm_ol_"+i, lstr, px+0.92*pw, oy-4, lc, 8, "sans-serif", "left");
               }

               // LOCKED
               VI.rect("ex_mmcm_lck", px+0.70*pw, py+0.52*ph, 0.16*pw, 0.10*ph, "#0a1a0a", "#66bb6a", 1);
               VI.label("ex_mmcm_lckl", "LOCKED", px+0.78*pw, py+0.58*ph, "#66bb6a", 10, "sans-serif", "center");
               VI.rect("ex_mmcm_lcka", px+0.24*pw, py+0.62*ph, 0.46*pw, 2, "#66bb6a");
               VI.rect("ex_mmcm_lckav", px+0.24*pw, py+0.57*ph, 2, 0.05*ph, "#66bb6a");
               VI.label("ex_mmcm_lckwarn", "!! Use clock ONLY after LOCKED=1 !!", px+0.78*pw, py+0.65*ph, "#f44336", 9, "sans-serif", "center");

               VI.label("ex_mmcm_dyn", "PSEN/PSINCDEC: ~15 ps per step  (1/56th of VCO period at 1200 MHz)", px+0.05*pw, py+0.88*ph, "#607080", 9, "sans-serif", "left");
            };

            const drawExpand_PLL = function(px, py, pw, ph) {
               VI.label("ex_pll_title", "PLLE2 " + String.fromCharCode(8212) + " PHASE-LOCKED LOOP (LOWER JITTER)", px+pw/2, py+12, "#ef9a9a", 13, "sans-serif", "center");
               
               // Blocks
               VI.rect("ex_pll_ref", px+0.02*pw, py+0.20*ph, 0.12*pw, 0.10*ph, "#1a0a0f", "#ef9a9a", 1);
               VI.label("ex_pll_refl1", "REF_CLK", px+0.08*pw, py+0.23*ph, "#ef9a9a", 9, "sans-serif", "center");
               VI.label("ex_pll_refl2", "DIVCLK_DIV", px+0.08*pw, py+0.27*ph, "#ef9a9a", 9, "sans-serif", "center");
               VI.rect("ex_pll_a1", px+0.14*pw, py+0.25*ph, 0.03*pw, 3, "#ef9a9a");

               VI.rect("ex_pll_pd", px+0.17*pw, py+0.20*ph, 0.14*pw, 0.10*ph, "#2a0f1a", "#ef9a9a", 1);
               VI.label("ex_pll_pdl1", "PHASE", px+0.24*pw, py+0.23*ph, "#ef9a9a", 9, "sans-serif", "center");
               VI.label("ex_pll_pdl2", "DETECTOR", px+0.24*pw, py+0.27*ph, "#ef9a9a", 9, "sans-serif", "center");
               VI.rect("ex_pll_a2", px+0.31*pw, py+0.25*ph, 0.04*pw, 3, "#ef9a9a");

               VI.rect("ex_pll_lf", px+0.35*pw, py+0.20*ph, 0.13*pw, 0.10*ph, "#2a0f1a", "#ef9a9a", 1);
               VI.label("ex_pll_lfl1", "LOOP", px+0.415*pw, py+0.23*ph, "#ef9a9a", 9, "sans-serif", "center");
               VI.label("ex_pll_lfl2", "FILTER", px+0.415*pw, py+0.27*ph, "#ef9a9a", 9, "sans-serif", "center");
               VI.rect("ex_pll_a3", px+0.48*pw, py+0.25*ph, 0.04*pw, 3, "#ef9a9a");

               VI.rect("ex_pll_vco", px+0.52*pw, py+0.18*ph, 0.14*pw, 0.14*ph, "#2a1a0f", "#ff9800", 1);
               VI.label("ex_pll_vcol1", "VCO", px+0.59*pw, py+0.21*ph, "#ff9800", 9, "sans-serif", "center");
               VI.label("ex_pll_vcol2", "600-1600", px+0.59*pw, py+0.25*ph, "#ff9800", 9, "sans-serif", "center");
               VI.label("ex_pll_vcol3", "MHz", px+0.59*pw, py+0.29*ph, "#ff9800", 9, "sans-serif", "center");
               VI.rect("ex_pll_a4", px+0.66*pw, py+0.25*ph, 0.04*pw, 3, "#ef9a9a");

               VI.rect("ex_pll_outd", px+0.70*pw, py+0.20*ph, 0.13*pw, 0.10*ph, "#0f1a2a", "#4fc3f7", 1);
               VI.label("ex_pll_outl1", "OUT DIV", px+0.765*pw, py+0.23*ph, "#4fc3f7", 9, "sans-serif", "center");
               VI.label("ex_pll_outl2", "CLKOUTn", px+0.765*pw, py+0.27*ph, "#4fc3f7", 9, "sans-serif", "center");

               VI.rect("ex_pll_fb", px+0.35*pw, py+0.52*ph, 0.14*pw, 0.10*ph, "#2a0f1a", "#ef9a9a", 1);
               VI.label("ex_pll_fbl1", "FB DIV", px+0.42*pw, py+0.55*ph, "#ef9a9a", 9, "sans-serif", "center");
               VI.label("ex_pll_fbl2", "MULT_F", px+0.42*pw, py+0.59*ph, "#ef9a9a", 9, "sans-serif", "center");

               // Feedback path
               VI.rect("ex_pll_fba1", px+0.765*pw, py+0.30*ph, 3, 0.27*ph, "#ef9a9a");
               VI.rect("ex_pll_fba2", px+0.49*pw, py+0.57*ph, 0.275*pw, 3, "#ef9a9a");
               VI.rect("ex_pll_fba3", px+0.42*pw, py+0.30*ph, 3, 0.22*ph, "#ef9a9a");
               VI.rect("ex_pll_fba4", px+0.24*pw, py+0.30*ph, 3, 0.27*ph, "#ef9a9a");
               VI.rect("ex_pll_fba5", px+0.24*pw, py+0.57*ph, 0.11*pw, 3, "#ef9a9a");

               // Outputs (only 6)
               for(let i=0; i<6; i++) {
                  let oy = py + 0.15*ph + i*0.045*ph;
                  VI.rect("ex_pll_o_"+i, px+0.83*pw, oy, 0.08*pw, 2, "#4fc3f7");
                  VI.label("ex_pll_ol_"+i, "CLKOUT"+i, px+0.92*pw, oy-4, "#4fc3f7", 8, "sans-serif", "left");
               }

               // LOCKED
               VI.rect("ex_pll_lck", px+0.70*pw, py+0.52*ph, 0.16*pw, 0.10*ph, "#0a1a0a", "#66bb6a", 1);
               VI.label("ex_pll_lckl", "LOCKED", px+0.78*pw, py+0.58*ph, "#66bb6a", 10, "sans-serif", "center");

               // Jitter panel
               VI.label("ex_pll_jit_t", "INTRINSIC OUTPUT JITTER COMPARISON", px+pw/2, py+0.70*ph, "#607080", 9, "sans-serif", "center");
               VI.rect("ex_pll_jit_m", px+0.40*pw, py+0.85*ph - 0.10*ph, 0.08*pw, 0.10*ph, "#ce93d8");
               VI.label("ex_pll_jit_ml1", "MMCM", px+0.44*pw, py+0.86*ph, "#ce93d8", 8, "sans-serif", "center");
               VI.label("ex_pll_jit_ml2", "higher jitter", px+0.44*pw, py+0.89*ph, "#ce93d8", 8, "sans-serif", "center");

               VI.rect("ex_pll_jit_p", px+0.52*pw, py+0.85*ph - 0.06*ph, 0.08*pw, 0.06*ph, "#ef9a9a");
               VI.label("ex_pll_jit_pl1", "PLL", px+0.56*pw, py+0.86*ph, "#ef9a9a", 8, "sans-serif", "center");
               VI.label("ex_pll_jit_pl2", "lower jitter", px+0.56*pw, py+0.89*ph, "#ef9a9a", 8, "sans-serif", "center");

               VI.label("ex_pll_use1", "Use PLL for: ADC sampling clocks, SERDES reference clocks", px+0.05*pw, py+0.90*ph, "#ef9a9a", 9, "sans-serif", "left");
               VI.label("ex_pll_use2", "Use MMCM for: fractional divide, dynamic phase shift, spread spectrum", px+0.05*pw, py+0.94*ph, "#607080", 9, "sans-serif", "left");
            };

            const drawExpand_HROW = function(px, py, pw, ph) {
               VI.label("ex_hrow_title", "HROW " + String.fromCharCode(8212) + " HORIZONTAL CLOCK ROW (cross-section)", px+pw/2, py+12, "#80deea", 13, "sans-serif", "center");
               
               const cols = [
                  {n:"IOB", w:0.07, c:"#1a2a1a"}, {n:"CLB", w:0.10, c:"#0f1a2a"},
                  {n:"BRAM",w:0.08, c:"#1a1520"}, {n:"CLB", w:0.10, c:"#0f1a2a"},
                  {n:"DSP", w:0.08, c:"#201a10"}, {n:"CMT", w:0.08, c:"#1a1a10"},
                  {n:"CLB", w:0.10, c:"#0f1a2a"}, {n:"BRAM",w:0.08, c:"#1a1520"},
                  {n:"CLB", w:0.10, c:"#0f1a2a"}, {n:"IOB", w:0.07, c:"#1a2a1a"}
               ];
               
               let cx = px + 0.07*pw;
               let clbCenters = [];
               cols.forEach(function(c, i) {
                  let cw = c.w * pw;
                  VI.rect("ex_hrow_c_"+i, cx, py+0.20*ph, cw, 0.60*ph, c.c);
                  VI.label("ex_hrow_cl_"+i, c.n, cx+cw/2, py+0.18*ph, "#607080", 8, "sans-serif", "center");
                  if(c.n === "CLB") clbCenters.push(cx + cw/2);
                  cx += cw;
               });

               VI.rect("ex_hrow_wire", px+0.05*pw, py+0.50*ph, 0.90*pw, 6, "#80deea");
               VI.label("ex_hrow_wirel", "HROW COPPER WIRE (hardwired " + String.fromCharCode(8212) + " not routed through PIPs)", px+pw/2, py+0.46*ph, "#80deea", 9, "sans-serif", "center");

               clbCenters.forEach(function(cc, i) {
                  VI.rect("ex_hrow_tap_"+i, cc-5, py+0.50*ph-2, 10, 10, "#80deea", "transparent", 0, 5);
                  VI.rect("ex_hrow_tapa_"+i, cc-1, py+0.50*ph+8, 2, 20, "#4dd0e1");
               });

               VI.label("ex_hrow_n1", "C_wire: distributed capacitance along full die width", px+0.05*pw, py+0.82*ph, "#405060", 9, "sans-serif", "left");
               VI.label("ex_hrow_n2", "All tap points: equal path length from BUFG root", px+0.05*pw, py+0.87*ph, "#80deea", 9, "sans-serif", "left");
               VI.label("ex_hrow_n3", "Chip-wide skew via BUFG H-Tree: < 200 ps FF-to-FF", px+0.05*pw, py+0.92*ph, "#80deea", 9, "sans-serif", "left");
            };

            const drawExpand_HTREE = function(px, py, pw, ph) {
               VI.label("ex_ht_title", "H-TREE " + String.fromCharCode(8212) + " RECURSIVE BALANCED CLOCK DISTRIBUTION", px+pw/2, py+12, "#4fc3f7", 13, "sans-serif", "center");
               
               let cx = px + pw*0.45;
               let cy = py + ph*0.45;

               // Level 0
               VI.rect("ex_ht_l0", px+0.10*pw, cy-2, 0.70*pw, 4, "#4fc3f7");
               VI.label("ex_ht_l0l", "BUFG OUTPUT " + String.fromCharCode(8212) + " H-TREE ROOT", cx, cy-8, "#4fc3f7", 9, "sans-serif", "center");

               // Level 1
               let l1lx = px+0.10*pw+2;
               let l1rx = px+0.80*pw-6;
               VI.rect("ex_ht_l1_l", l1lx, py+0.22*ph, 4, 0.46*ph, "#4fc3f7");
               VI.rect("ex_ht_l1_r", l1rx, py+0.22*ph, 4, 0.46*ph, "#4fc3f7");

               // Level 2
               VI.rect("ex_ht_l2_lu", px+0.05*pw, py+0.22*ph, 0.12*pw, 3, "#4fc3f7");
               VI.rect("ex_ht_l2_lb", px+0.05*pw, py+0.68*ph, 0.12*pw, 3, "#4fc3f7");
               VI.rect("ex_ht_l2_ru", px+0.73*pw, py+0.22*ph, 0.12*pw, 3, "#4fc3f7");
               VI.rect("ex_ht_l2_rb", px+0.73*pw, py+0.68*ph, 0.12*pw, 3, "#4fc3f7");

               // Taps
               const tps = [
                  {x:px+0.05*pw, y:py+0.22*ph}, {x:px+0.17*pw, y:py+0.22*ph},
                  {x:px+0.05*pw, y:py+0.68*ph}, {x:px+0.17*pw, y:py+0.68*ph},
                  {x:px+0.73*pw, y:py+0.22*ph}, {x:px+0.85*pw, y:py+0.22*ph},
                  {x:px+0.73*pw, y:py+0.68*ph}, {x:px+0.85*pw, y:py+0.68*ph}
               ];
               tps.forEach(function(t, i) {
                  VI.rect("ex_ht_tap_"+i, t.x-4, t.y-4, 8, 8, "#80deea");
                  VI.label("ex_ht_tapl_"+i, "HROW tap", t.x, t.y-10, "#80deea", 8, "sans-serif", "center");
               });

               // Path annotations
               VI.label("ex_ht_p1", "path length = L", px+0.05*pw, py+0.18*ph, "#ffeb3b", 9, "sans-serif", "center");
               VI.label("ex_ht_p2", "path length = L", px+0.85*pw, py+0.18*ph, "#ffeb3b", 9, "sans-serif", "center");
               VI.label("ex_ht_pe", "EQUAL " + String.fromCharCode(8212) + " guarantees < 200ps skew", cx, py+0.15*ph, "#ffeb3b", 9, "sans-serif", "center");

               // Level labels
               VI.label("ex_ht_ll0", "Level 0: Root", px+0.90*pw, cy, "#607080", 9, "sans-serif", "left");
               VI.label("ex_ht_ll1", "Level 1: L/R split", px+0.90*pw, py+0.35*ph, "#607080", 9, "sans-serif", "left");
               VI.label("ex_ht_ll2", "Level 2: HROW feeds", px+0.90*pw, py+0.22*ph, "#607080", 9, "sans-serif", "left");

               VI.label("ex_ht_warn", "INT fabric routing: ns-level skew (NOT used for clocks)", cx, py+0.88*ph, "#f44336", 9, "sans-serif", "center");
            };

            const drawExpand_REGION = function(px, py, pw, ph) {
               VI.label("ex_reg_title", "CLOCK REGION " + String.fromCharCode(8212) + " INTERNAL STRUCTURE", px+pw/2, py+12, "#4fc3f7", 13, "sans-serif", "center");
               
               VI.rect("ex_reg_hrow", px+0.02*pw, py+0.48*ph, 0.96*pw, 5, "#80deea");
               VI.label("ex_reg_hrowl", "HROW (vertical midpoint of region)", px+pw/2, py+0.45*ph, "#80deea", 9, "sans-serif", "center");
               
               VI.rect("ex_reg_spine", px+0.45*pw, py+0.08*ph, 4, 0.84*ph, "#4dd0e1");
               VI.label("ex_reg_spinel", "CLK SPINE", px+0.45*pw+10, py+0.10*ph, "#4dd0e1", 9, "sans-serif", "left");

               for(let row=0; row<8; row++) {
                  let rowY = (row < 4) ? py + (0.10 + row*0.09)*ph : py + (0.52 + (row-4)*0.09)*ph;
                  VI.rect("ex_reg_r_"+row, px+0.05*pw, rowY, 0.85*pw, 0.07*ph, "#0f1a2a", "#1e4a7a", 1, 2);
                  VI.label("ex_reg_rl_"+row, "CLB ROW " + row, px+0.06*pw, rowY+ph*0.035, "#2a5a9a", 8, "sans-serif", "left");
                  VI.rect("ex_reg_t_"+row, px+0.45*pw, rowY+0.035*ph, 0.15*pw, 2, "#4dd0e1");
                  VI.label("ex_reg_tl_"+row, "tap", px+0.52*pw, rowY+0.035*ph-8, "#4dd0e1", 7, "sans-serif", "center");
                  for(let f=0; f<3; f++) {
                     VI.rect("ex_reg_ff_"+row+"_"+f, px+0.75*pw + f*16, rowY+ph*0.015, 12, 8, "#1a3a5a");
                     VI.label("ex_reg_ffl_"+row+"_"+f, "FF", px+0.75*pw + f*16 + 6, rowY+ph*0.015+4, "#ffffff", 6, "sans-serif", "center");
                  }
               }

               VI.rect("ex_reg_bufr", px+0.05*pw, py+0.12*ph, 0.15*pw, 0.08*ph, "#1a0f00", "#ff9800", 1);
               VI.label("ex_reg_bufrl", "BUFR", px+0.125*pw, py+0.14*ph, "#ff9800", 9, "sans-serif", "center");
               VI.rect("ex_reg_bufra", px+0.20*pw, py+0.16*ph, 0.25*pw, 2, "#ff9800");
               VI.label("ex_reg_bufrn", "regional only", px+0.125*pw, py+0.22*ph, "#ff9800", 8, "sans-serif", "center");

               VI.rect("ex_reg_cbg", px+0.02*pw, py+0.88*ph, 0.96*pw, 0.10*ph, "#080c14", "#2a3a50", 1);
               VI.label("ex_reg_ct", "MAX 12 BUFG CLOCKS ACTIVE PER REGION (DRC: CLOCK-012)", px+pw/2, py+0.85*ph, "#607080", 8, "sans-serif", "center");
               for(let i=0; i<13; i++) {
                  let bx = px+0.05*pw + i*(0.065*pw);
                  let bc = (i<12) ? "#4fc3f7" : "#f44336";
                  VI.rect("ex_reg_cb_"+i, bx, py+0.90*ph, 0.05*pw, 0.06*ph, bc);
                  if (i===12) VI.label("ex_reg_cbl", "13", bx+0.025*pw, py+0.93*ph, "#ffffff", 8, "sans-serif", "center");
               }
            };


            // ================================================================
            // LAYOUT CONSTANTS
            // Proportional to real XC7S50 die topology.
            // Die is taller than wide. Columns listed L→R in real order:
            // IOB | CLB | BRAM | CLB | DSP | CLB | CMT | CLB | BRAM | CLB | IOB
            // ================================================================

            // Canvas dims
            const CW = 1500, CH = 1000;

            // Floorplan panel occupies left 2/3
            const FP_X = 20, FP_Y = 60;
            const FP_W = 820, FP_H = 880;

            // Die inner area (inside floorplan panel border)
            const DIE_X = FP_X + 10;
            const DIE_Y = FP_Y + 10;
            const DIE_W = FP_W - 20;
            const DIE_H = FP_H - 20;

            // Three horizontal clock region rows (bottom → top in die Y space)
            // We draw top-of-canvas = top of die
            const ROW_H  = DIE_H / 3;        // each clock region row height
            const HROW_Y = [
               DIE_Y + ROW_H * 1,  // HROW between row0 and row1
               DIE_Y + ROW_H * 2,  // HROW between row1 and row2
            ];
            // Two columns of clock regions
            const COL_W = DIE_W / 2;

            // Approximate column type X positions within die (proportional)
            // Real order: IOB CLB BRAM CLB DSP CLB/CMT CLB BRAM CLB IOB
            const COL_TYPES = [
               {name:"IOB",   xf:0.00, w:0.07, fill:"#1a2a1a", stroke:"#2e6b2e"},
               {name:"CLB",   xf:0.07, w:0.10, fill:"#0f1a2a", stroke:"#1e4a7a"},
               {name:"BRAM",  xf:0.17, w:0.08, fill:"#1a1520", stroke:"#5a3a8a"},
               {name:"CLB",   xf:0.25, w:0.10, fill:"#0f1a2a", stroke:"#1e4a7a"},
               {name:"DSP",   xf:0.35, w:0.08, fill:"#201a10", stroke:"#8a6a20"},
               {name:"CMT",   xf:0.43, w:0.08, fill:"#1a1a10", stroke:"#8a8a20"},
               {name:"CLB",   xf:0.51, w:0.10, fill:"#0f1a2a", stroke:"#1e4a7a"},
               {name:"BRAM",  xf:0.61, w:0.08, fill:"#1a1520", stroke:"#5a3a8a"},
               {name:"CLB",   xf:0.69, w:0.10, fill:"#0f1a2a", stroke:"#1e4a7a"},
               {name:"IOB",   xf:0.79, w:0.07, fill:"#1a2a1a", stroke:"#2e6b2e"},
               // right side mirror (columns 86-100%)
               {name:"CLB",   xf:0.86, w:0.07, fill:"#0f1a2a", stroke:"#1e4a7a"},
               {name:"IOB",   xf:0.93, w:0.07, fill:"#1a2a1a", stroke:"#2e6b2e"},
            ];

            // Clock colors (consistent across entire viz)
            const CLR = {
               BUFG:    "#4fc3f7",   // light blue — global clock
               BUFR:    "#ff9800",   // orange     — regional clock
               BUFIO:   "#66bb6a",   // green      — I/O only clock
               MMCM:    "#ce93d8",   // purple     — MMCM output
               PLL:     "#ef9a9a",   // red-pink   — PLL output
               HTREE:   "#4fc3f7",   // same as BUFG (H-Tree carries BUFG signal)
               HROW:    "#80deea",   // teal       — horizontal clock row
               SPINE:   "#4dd0e1",   // cyan       — vertical spine
               EXT:     "#a5d6a7",   // pale green — external input
               WARN:    "#f44336",   // red        — illegal/warning
               DIM:     "#1a2030",   // very dark  — dimmed region
               SEL:     "#fff9c4",   // yellow     — selected highlight
            };

            const sel = self.selected;

            // Helper: is this primitive type currently highlighted?
            const isHighlighted = function(type) {
               if (!sel) return true; // nothing selected → all visible
               if (sel === type) return true;
               // logical connections
               if (sel === "htree" && type === "bufg")  return true;
               if (sel === "htree" && type === "hrow")  return true;
               if (sel === "bufg"  && type === "htree") return true;
               if (sel === "bufg"  && type === "hrow")  return true;
               if (sel === "bufg"  && type === "spine") return true;
               if (sel === "hrow"  && type === "bufg")  return true;
               if (sel === "hrow"  && type === "htree") return true;
               if (sel === "hrow"  && type === "spine") return true;
               if (sel === "mmcm"  && type === "bufg")  return true;
               if (sel === "pll"   && type === "bufg")  return true;
               if (sel === "bufr"  && type === "hrow")  return false;
               return false;
            };

            const dimColor = function(type, activeColor) {
               return isHighlighted(type) ? activeColor : CLR.DIM;
            };

            // ================================================================
            // BACKGROUND + TITLE
            // ================================================================
            VI.rect("bg", 0, 0, CW, CH, "#07090f");
            VI.label("title", "XC7S50 CLOCK DISTRIBUTION NETWORK " + String.fromCharCode(8212) + " INTERACTIVE TOPOLOGY EXPLORER",
               CW/2, 18, "#e0e8f0", 15, "sans-serif", "center");
            VI.label("sub", "Click primitives or press 1-5, H to explore. ESC to clear.",
               CW/2, 38, "#607080", 11, "sans-serif", "center");

            // ================================================================
            // FLOORPLAN PANEL
            // ================================================================
            VI.rect("fp_bg", FP_X, FP_Y, FP_W, FP_H, "#0c0f18", "#2a3a50", 2, 4);
            VI.label("fp_title", "PHYSICAL DIE FLOORPLAN (proportional column widths)",
               FP_X+10, FP_Y+14, "#607080", 10, "sans-serif");

            // Draw column type stripes across full die height
            COL_TYPES.forEach(function(col, ci) {
               const cx = DIE_X + col.xf * DIE_W;
               const cw = col.w * DIE_W;
               VI.rect("col_"+ci, cx, DIE_Y, cw, DIE_H, col.fill, col.stroke, 1);
               // Column type label at top
               if (cw > 18) {
                  VI.label("col_lbl_"+ci, col.name,
                     cx + cw/2, DIE_Y + 3, "#405060", 8, "sans-serif", "center");
               }
            });

            // ================================================================
            // CLOCK REGIONS (6 rectangles — 2 col × 3 row)
            // ================================================================
            const regionNames = [
               "REGION[COL0,ROW0]", "REGION[COL1,ROW0]",
               "REGION[COL0,ROW1]", "REGION[COL1,ROW1]",
               "REGION[COL0,ROW2]", "REGION[COL1,ROW2]"
            ];
            for (let row = 0; row < 3; row++) {
               for (let col = 0; col < 2; col++) {
                  const ridx = row * 2 + col;
                  const rx   = DIE_X + col * COL_W;
                  const ry   = DIE_Y + (2 - row) * ROW_H; // top of canvas = top of die
                  const rsel = (sel === "region" + ridx);
                  const rstroke = rsel ? CLR.SEL : "#2a3a50";
                  const rsw     = rsel ? 3 : 1;
                  VI.rect("reg_"+ridx, rx, ry, COL_W, ROW_H,
                     "transparent", rstroke, rsw);
                  VI.label("reg_lbl_"+ridx,
                     "CLK REGION [" + col + "," + row + "]",
                     rx + COL_W/2, ry + 8, "#2a4060", 9, "sans-serif", "center");

                  VI.onClick("reg_"+ridx, rx, ry, COL_W, ROW_H, function() {
                     if (self.expandedId === "reg_"+ridx) {
                        self.expandedId = null; self.expandRect = null; self.expandType = null;
                     } else {
                        self.selected = "region" + ridx;
                        self.expandedId = "reg_"+ridx;
                        self.expandType = "region";
                        const OW = 480, OH = 380;
                        let ox = Math.min(rx + COL_W + 10, 1500 - OW - 10);
                        let oy = Math.max(10, Math.min(ry - 20, 1000 - OH - 10));
                        self.expandRect = {x: ox, y: oy, w: OW, h: OH};
                        self.tooltip = null;
                     }
                     VI.redraw();
                  });
               }
            }

            // ================================================================
            // HROW LINES — horizontal clock rows at region row boundaries
            // These are physical copper wires running full die width
            // ================================================================
            [0, 1].forEach(function(hi) {
               const hy = DIE_Y + (2 - hi) * ROW_H;  // boundary between row hi and hi+1
               const hcolor = isHighlighted("hrow") ? CLR.HROW : CLR.DIM;
               VI.rect("hrow_stripe_"+hi, DIE_X, hy-3, DIE_W, 6, hcolor);
               VI.label("hrow_lbl_"+hi, "HROW " + hi + "  (horizontal clock row " + String.fromCharCode(8212) + " full die width)",
                  DIE_X + 5, hy - 14, hcolor, 9, "sans-serif");

               VI.onClick("hrow_clk_"+hi, DIE_X, hy-8, DIE_W, 16, function() {
                  if (self.expandedId === "hrow_clk_"+hi) {
                     self.expandedId = null; self.expandRect = null; self.expandType = null;
                  } else {
                     self.selected = "hrow";
                     self.expandedId = "hrow_clk_"+hi;
                     self.expandType = "hrow";
                     const OW = 480, OH = 380;
                     let ox = Math.min(DIE_X + DIE_W + 10, 1500 - OW - 10);
                     let oy = Math.max(10, Math.min(hy - 20, 1000 - OH - 10));
                     self.expandRect = {x: ox, y: oy, w: OW, h: OH};
                     self.tooltip = null;
                  }
                  VI.redraw();
               });
            });

            // ================================================================
            // VERTICAL CLOCK SPINES
            // Run N and S from the HROW tap point down each CLB column
            // ================================================================
            // CMT column center X (approximately)
            const CMT_X_FRAC = 0.47;
            const spineCenterX = DIE_X + CMT_X_FRAC * DIE_W;
            const spineColor = dimColor("spine", CLR.SPINE);

            for (let col = 0; col < 2; col++) {
               const sx = DIE_X + (col === 0 ? 0.28 : 0.72) * DIE_W;
               for (let row = 0; row < 3; row++) {
                  const ry = DIE_Y + (2 - row) * ROW_H;
                  // spine runs full height of the region from HROW
                  VI.rect("spine_"+col+"_"+row, sx-1, ry, 3, ROW_H, spineColor);
               }
            }

            // ================================================================
            // H-TREE — recursive H-shaped branching geometry
            // BUFG centroid → H-Tree → feeds HROWs
            // The H-Tree is drawn as nested H structures
            // ================================================================
            const htColor  = dimColor("htree", CLR.HTREE);
            const HT_ROOT_Y = DIE_Y + DIE_H / 2;   // vertical center of die
            const HT_ROOT_X = DIE_X + DIE_W / 2;   // horizontal center

            // Level 0: Root horizontal bar (full die width)
            // This is the first H crossbar — connects left and right halves
            VI.rect("ht_l0_bar", DIE_X + 10, HT_ROOT_Y - 2, DIE_W - 20, 4, htColor);
            VI.label("ht_root_lbl", "H-TREE ROOT  (BUFG drives here)",
               HT_ROOT_X, HT_ROOT_Y - 14, htColor, 9, "sans-serif", "center");

            // Level 1: Two vertical bars (left half and right half)
            // Each vertical bar spans from root to upper and lower midpoints
            const L1_LEFT_X  = DIE_X + DIE_W * 0.25;
            const L1_RIGHT_X = DIE_X + DIE_W * 0.75;
            const L1_TOP_Y   = DIE_Y + ROW_H * 0.5;
            const L1_BOT_Y   = DIE_Y + ROW_H * 2.5;
            VI.rect("ht_l1_vl", L1_LEFT_X-2,  L1_TOP_Y, 4, L1_BOT_Y - L1_TOP_Y, htColor);
            VI.rect("ht_l1_vr", L1_RIGHT_X-2, L1_TOP_Y, 4, L1_BOT_Y - L1_TOP_Y, htColor);

            // Level 2: Four horizontal bars (the "H" crossbars at each quadrant)
            const L2_TOP_Y = L1_TOP_Y;
            const L2_MID_Y = DIE_Y + ROW_H * 1.5;
            const L2_BOT_Y = L1_BOT_Y;

            // Left column, upper quadrant crossbar
            VI.rect("ht_l2_lu", DIE_X + 10, L2_TOP_Y - 2, DIE_W*0.5 - 20, 4, htColor);
            // Left column, lower quadrant crossbar
            VI.rect("ht_l2_lb", DIE_X + 10, L2_BOT_Y - 2, DIE_W*0.5 - 20, 4, htColor);
            // Right column, upper quadrant crossbar
            VI.rect("ht_l2_ru", DIE_X + DIE_W*0.5 + 10, L2_TOP_Y - 2, DIE_W*0.5 - 20, 4, htColor);
            // Right column, lower quadrant crossbar
            VI.rect("ht_l2_rb", DIE_X + DIE_W*0.5 + 10, L2_BOT_Y - 2, DIE_W*0.5 - 20, 4, htColor);

            // Level 2 midpoint connectors to HROW
            // Where H-Tree delivers clock to the HROW
            [[L1_LEFT_X, HROW_Y[0]], [L1_LEFT_X, HROW_Y[1]],
             [L1_RIGHT_X, HROW_Y[0]], [L1_RIGHT_X, HROW_Y[1]]].forEach(function(pt, pi) {
               VI.rect("ht_tap_"+pi, pt[0]-4, pt[1]-4, 9, 9, htColor);
            });

            // H-Tree click zone
            VI.onClick("ht_root_click", DIE_X, HT_ROOT_Y - 10, DIE_W, 20, function() {
               if (self.expandedId === "ht_root_click") {
                  self.expandedId = null; self.expandRect = null; self.expandType = null;
               } else {
                  self.selected = "htree";
                  self.expandedId = "ht_root_click";
                  self.expandType = "htree";
                  const OW = 480, OH = 380;
                  let ox = Math.min(DIE_X + DIE_W + 10, 1500 - OW - 10);
                  let oy = Math.max(10, Math.min(HT_ROOT_Y - 20, 1000 - OH - 10));
                  self.expandRect = {x: ox, y: oy, w: OW, h: OH};
                  self.tooltip = null;
               }
               VI.redraw();
            });

            // ================================================================
            // CMT COLUMN — MMCMs and PLLs
            // Located in the CMT tile column (proportional position shown)
            // ================================================================
            const CMT_CX = DIE_X + CMT_X_FRAC * DIE_W;
            const mmcmColor = dimColor("mmcm", CLR.MMCM);
            const pllColor  = dimColor("pll",  CLR.PLL);

            // Draw 5 MMCMs stacked in the CMT column (one per ~1/5 of die height)
            for (let mi = 0; mi < 5; mi++) {
               const my = DIE_Y + (mi / 5) * DIE_H + 4;
               VI.rect("mmcm_"+mi, CMT_CX - 28, my, 56, (DIE_H/5) - 8,
                  "#1a0f20", mmcmColor, 2, 4);
               VI.label("mmcm_lbl_"+mi, "MMCM", CMT_CX, my + 10,
                  mmcmColor, 9, "sans-serif", "center");
               VI.onClick("mmcm_"+mi, CMT_CX-28, my, 56, (DIE_H/5)-8, function() {
                  if (self.expandedId === "mmcm_"+mi) {
                     self.expandedId = null; self.expandRect = null; self.expandType = null;
                  } else {
                     self.selected = "mmcm";
                     self.expandedId = "mmcm_"+mi;
                     self.expandType = "mmcm";
                     const OW = 480, OH = 380;
                     let ox = Math.min(CMT_CX + 28 + 10, 1500 - OW - 10);
                     let oy = Math.max(10, Math.min(my - 20, 1000 - OH - 10));
                     self.expandRect = {x: ox, y: oy, w: OW, h: OH};
                     self.tooltip = null;
                  }
                  VI.redraw();
               });
            }

            // Draw 5 PLLs interleaved (shown on right side of CMT column)
            for (let pi = 0; pi < 5; pi++) {
               const py = DIE_Y + ((pi + 0.5) / 5) * DIE_H + 4;
               VI.rect("pll_"+pi, CMT_CX + 32, py, 40, (DIE_H/5) - 30,
                  "#20100f", pllColor, 2, 4);
               VI.label("pll_lbl_"+pi, "PLL", CMT_CX + 52, py + 6,
                  pllColor, 8, "sans-serif", "center");
               VI.onClick("pll_"+pi, CMT_CX+32, py, 40, (DIE_H/5)-30, function() {
                  if (self.expandedId === "pll_"+pi) {
                     self.expandedId = null; self.expandRect = null; self.expandType = null;
                  } else {
                     self.selected = "pll";
                     self.expandedId = "pll_"+pi;
                     self.expandType = "pll";
                     const OW = 480, OH = 380;
                     let ox = Math.min(CMT_CX + 32 + 40 + 10, 1500 - OW - 10);
                     let oy = Math.max(10, Math.min(py - 20, 1000 - OH - 10));
                     self.expandRect = {x: ox, y: oy, w: OW, h: OH};
                     self.tooltip = null;
                  }
                  VI.redraw();
               });
            }

            // ================================================================
            // BUFG BANK — shown at center of die (physical location)
            // 32 BUFGs, located near die center to minimize H-Tree asymmetry
            // ================================================================
            const BUFG_Y = FP_Y - 52;
            const bufgColor = dimColor("bufg", CLR.BUFG);

            VI.rect("bufg_bank", DIE_X, BUFG_Y, DIE_W, 44, "#050d18", bufgColor, 2, 4);
            VI.label("bufg_bank_lbl", "GLOBAL CLOCK BUFFER BANK  (32 x BUFG / BUFGCE / BUFGMUX)",
               DIE_X + DIE_W/2, BUFG_Y + 4, bufgColor, 11, "sans-serif", "center");

            // Draw individual BUFG tiles
            const bufgTileW = DIE_W / 32;
            for (let bi = 0; bi < 32; bi++) {
               const bx = DIE_X + bi * bufgTileW;
               const isActive = (bi < 12); // show first 12 as "active" to illustrate limit
               VI.rect("bufg_tile_"+bi, bx+1, BUFG_Y+18, bufgTileW-2, 20,
                  isActive ? "#0a2a3a" : "#080f18",
                  isActive ? bufgColor : "#1a2a3a", 1, 2);
               if (bi < 12) {
                  VI.label("bufg_n_"+bi, String(bi), bx + bufgTileW/2, BUFG_Y+22,
                     bufgColor, 7, "monospace", "center");
               }
            }
            VI.label("bufg_limit_note",
               "0-11: example active clocks (max 12 per region)    12-31: available",
               DIE_X + DIE_W/2, BUFG_Y + 40, "#405060", 8, "sans-serif", "center");

            VI.onClick("bufg_bank_click", DIE_X, BUFG_Y, DIE_W, 44, function() {
               if (self.expandedId === "bufg_bank_click") {
                  self.expandedId = null; self.expandRect = null; self.expandType = null;
               } else {
                  self.selected = "bufg";
                  self.expandedId = "bufg_bank_click";
                  self.expandType = "bufg";
                  const OW = 480, OH = 380;
                  let ox = Math.min(DIE_X + DIE_W + 10, 1500 - OW - 10);
                  let oy = Math.max(10, Math.min(BUFG_Y - 20, 1000 - OH - 10));
                  self.expandRect = {x: ox, y: oy, w: OW, h: OH};
                  self.tooltip = null;
               }
               VI.redraw();
            });

            // Arrow from BUFG bank down into die (representing H-Tree distribution)
            VI.rect("bufg_to_die", DIE_X + DIE_W/2 - 2, BUFG_Y+44, 4, 16, bufgColor);
            VI.rect("bufg_arrow", DIE_X + DIE_W/2 - 6, BUFG_Y+56, 12, 6, bufgColor);

            // ================================================================
            // BUFR INDICATORS — per clock region (regional clock)
            // ================================================================
            const bufrColor = dimColor("bufr", CLR.BUFR);
            for (let row = 0; row < 3; row++) {
               for (let col = 0; col < 2; col++) {
                  const rx = DIE_X + col * COL_W + 6;
                  const ry = DIE_Y + (2-row) * ROW_H + ROW_H - 28;
                  VI.rect("bufr_"+row+"_"+col, rx, ry, 52, 22,
                     "#1a0f00", bufrColor, 2, 3);
                  VI.label("bufr_lbl_"+row+"_"+col, "BUFR",
                     rx+26, ry+5, bufrColor, 9, "sans-serif", "center");
                  VI.onClick("bufr_"+row+"_"+col, rx, ry, 52, 22, function() {
                     if (self.expandedId === "bufr_"+row+"_"+col) {
                        self.expandedId = null; self.expandRect = null; self.expandType = null;
                     } else {
                        self.selected = "bufr";
                        self.expandedId = "bufr_"+row+"_"+col;
                        self.expandType = "bufr";
                        const OW = 480, OH = 380;
                        let ox = Math.min(rx + 52 + 10, 1500 - OW - 10);
                        let oy = Math.max(10, Math.min(ry - 20, 1000 - OH - 10));
                        self.expandRect = {x: ox, y: oy, w: OW, h: OH};
                        self.tooltip = null;
                     }
                     VI.redraw();
                  });
               }
            }

            // ================================================================
            // BUFIO INDICATORS — per I/O bank (I/O clock only)
            // Located at the bottom of each IOB column
            // ================================================================
            const bufioColor = dimColor("bufio", CLR.BUFIO);
            const iobXPositions = [
               DIE_X + 0.00 * DIE_W + 4,
               DIE_X + 0.79 * DIE_W + 4,
               DIE_X + 0.93 * DIE_W + 4,
            ];
            iobXPositions.forEach(function(bix, bii) {
               const biy = DIE_Y + DIE_H - 30;
               VI.rect("bufio_"+bii, bix, biy, 48, 22,
                  "#0a1a0a", bufioColor, 2, 3);
               VI.label("bufio_lbl_"+bii, "BUFIO",
                  bix+24, biy+5, bufioColor, 8, "sans-serif", "center");
               VI.onClick("bufio_"+bii, bix, biy, 48, 22, function() {
                  if (self.expandedId === "bufio_"+bii) {
                     self.expandedId = null; self.expandRect = null; self.expandType = null;
                  } else {
                     self.selected = "bufio";
                     self.expandedId = "bufio_"+bii;
                     self.expandType = "bufio";
                     const OW = 480, OH = 380;
                     let ox = Math.min(bix + 48 + 10, 1500 - OW - 10);
                     let oy = Math.max(10, Math.min(biy - 20, 1000 - OH - 10));
                     self.expandRect = {x: ox, y: oy, w: OW, h: OH};
                     self.tooltip = null;
                  }
                  VI.redraw();
               });
            });

            // ================================================================
            // EXTERNAL INPUT PATH — IOB → IBUF → BUFG/MMCM
            // Show the path from pin to H-Tree
            // ================================================================
            const EXT_X = DIE_X + 0.035 * DIE_W;
            const EXT_Y = DIE_Y + 10;
            const extColor = dimColor("bufg", CLR.EXT);
            VI.rect("ext_pin", EXT_X-8, FP_Y - 85, 16, 25, "#0a200a", extColor, 2, 3);
            VI.label("ext_pin_lbl", "PAD", EXT_X, FP_Y-88, extColor, 8, "monospace", "center");
            VI.rect("ext_ibuf", EXT_X - 22, FP_Y - 55, 44, 20, "#0a1a0a", extColor, 2, 3);
            VI.label("ext_ibuf_lbl", "IBUF", EXT_X, FP_Y-52, extColor, 9, "sans-serif", "center");
            VI.rect("ext_to_bufg", EXT_X-1, FP_Y-35, 3, 33, extColor);
            VI.label("ext_arrow", "→ BUFG →", EXT_X + 8, FP_Y-25, extColor, 8, "sans-serif");
            VI.label("ext_note", "or MMCM", EXT_X + 8, FP_Y-13, "#405060", 8, "sans-serif");

            // ================================================================
            // CARRY4 and CLB ROW CLOCK TAP illustration (inset in one region)
            // Shows the clock spine feeding individual CLB rows via hardwired taps
            // ================================================================
            const INSET_X = DIE_X + COL_W * 0.3;
            const INSET_Y = DIE_Y + ROW_H * 0.5;
            const INSET_H = ROW_H * 0.85;
            const INSET_W = COL_W * 0.35;
            const spX = INSET_X;
            const tapColor = dimColor("spine", CLR.SPINE);

            VI.rect("inset_bg", INSET_X, INSET_Y, INSET_W, INSET_H,
               "#060a14", tapColor, 1, 2);
            VI.label("inset_title", "CLOCK SPINE → CLB ROWS",
               INSET_X + INSET_W/2, INSET_Y+3, tapColor, 8, "sans-serif", "center");

            const numTaps = 6;
            for (let ti = 0; ti < numTaps; ti++) {
               const ty = INSET_Y + 20 + ti * (INSET_H - 30) / numTaps;
               // Spine vertical line
               VI.rect("tap_spine_"+ti, spX + INSET_W*0.2, ty, 2, (INSET_H-30)/numTaps, tapColor);
               // Horizontal tap to FF row
               VI.rect("tap_h_"+ti, spX + INSET_W*0.2, ty+4, INSET_W*0.5, 2, tapColor);
               // FF symbol
               VI.rect("tap_ff_"+ti, spX + INSET_W*0.72, ty, 14, 12,
                  "#1a2a3a", CLR.BUFG, 1, 2);
               VI.label("tap_ff_lbl_"+ti, "FF",
                  spX + INSET_W*0.72 + 7, ty+1, CLR.BUFG, 7, "sans-serif", "center");
               VI.label("tap_note_"+ti, "CLK",
                  spX + INSET_W*0.72 + 7, ty+13, "#405060", 6, "sans-serif", "center");
            }
            VI.label("tap_hardwire_notel1", "taps = hardwired,", spX + INSET_W*0.5, INSET_Y + INSET_H - 24, "#405060", 7, "sans-serif", "center");
            VI.label("tap_hardwire_notel2", "not PIPs", spX + INSET_W*0.5, INSET_Y + INSET_H - 14, "#405060", 7, "sans-serif", "center");

            // ================================================================
            // RIGHT PANEL — Info / Tooltip + Legend + Constraint Table
            // ================================================================
            const RP_X = FP_X + FP_W + 20;
            const RP_W = CW - RP_X - 20;

            // LEGEND
            VI.rect("legend_bg", RP_X, FP_Y, RP_W, 220, "#0c0f18", "#2a3a50", 2, 4);
            VI.label("legend_title", "CLOCK SIGNAL LEGEND",
               RP_X+10, FP_Y+10, "#8090a0", 11, "sans-serif");

            const legendItems = [
               {color: CLR.BUFG,  label: "BUFG / H-Tree    global, full-die, < 200ps skew"},
               {color: CLR.BUFR,  label: "BUFR             regional, one region, " + String.fromCharCode(247) + "1/2/4/6/8"},
               {color: CLR.BUFIO, label: "BUFIO            I/O only, ILOGIC/OLOGIC, < 100ps"},
               {color: CLR.MMCM,  label: "MMCM output      must pass BUFG before fabric"},
               {color: CLR.PLL,   label: "PLL output       lower jitter, must pass BUFG"},
               {color: CLR.HROW,  label: "HROW             horizontal clock row copper wire"},
               {color: CLR.SPINE, label: "Clock Spine      vertical column distribution wire"},
               {color: CLR.EXT,   label: "External path    pad → IBUF → BUFG/MMCM"},
            ];
            legendItems.forEach(function(item, li) {
               const ly = FP_Y + 30 + li * 22;
               VI.rect("leg_clr_"+li, RP_X+10, ly+2, 18, 10, item.color);
               VI.label("leg_lbl_"+li, item.label, RP_X+34, ly, "#8090a0", 10, "monospace");
            });

            // CONSTRAINT TABLE
            VI.rect("con_bg", RP_X, FP_Y+228, RP_W, 260, "#0c0f18", "#2a3a50", 2, 4);
            VI.label("con_title", "LEGAL / ILLEGAL ROUTING",
               RP_X+10, FP_Y+238, "#8090a0", 11, "sans-serif");

            const constraints = [
               {ok:true,  text:"BUFG  → any FF, BRAM, DSP on entire die"},
               {ok:true,  text:"BUFR  → CLB FFs within same clock region"},
               {ok:true,  text:"BUFIO → ILOGIC/OLOGIC within same I/O bank"},
               {ok:true,  text:"MMCM/PLL → BUFG → fabric  (correct path)"},
               {ok:false, text:"BUFR  → FFs in DIFFERENT clock region"},
               {ok:false, text:"BUFIO → CLB flip-flops (any region)"},
               {ok:false, text:"MMCM  → fabric directly (no BUFG)"},
               {ok:false, text:">12 BUFGs active in one region → CLOCK-012"},
               {ok:false, text:"CLK routed through INT fabric → ns skew"},
               {ok:false, text:"BUFGCE.CE changes asynchronously → glitch"},
            ];
            constraints.forEach(function(c, ci) {
               const cy = FP_Y + 258 + ci * 22;
               const color = c.ok ? "#66bb6a" : "#f44336";
               VI.label("con_sym_"+ci, c.ok ? "✓" : "✗", RP_X+10, cy, color, 13, "monospace");
               VI.label("con_txt_"+ci, c.text, RP_X+26, cy, c.ok ? "#4a8a4a" : "#8a3a3a", 10, "monospace");
            });

            // VCO CONSTRAINT CALCULATOR
            VI.rect("vco_bg", RP_X, FP_Y+496, RP_W, 180, "#0c0f18", "#2a3a50", 2, 4);
            VI.label("vco_title", "VCO CONSTRAINT  (600 " + String.fromCharCode(8212) + " 1600 MHz)",
               RP_X+10, FP_Y+506, "#8090a0", 11, "sans-serif");

            const vcoExamples = [
               {fin:"24MHz",  mult:50, div:1, outdiv:6,  fvco:1200, fout:200, ok:true},
               {fin:"24MHz",  mult:25, div:1, outdiv:12, fvco:600,  fout:50,  ok:true},
               {fin:"100MHz", mult:12, div:1, outdiv:6,  fvco:1200, fout:200, ok:true},
               {fin:"100MHz", mult:5,  div:1, outdiv:5,  fvco:500,  fout:100, ok:false},
               {fin:"24MHz",  mult:67, div:1, outdiv:8,  fvco:1608, fout:201, ok:false},
            ];
            VI.label("vco_hdr",
               "F_IN    MULT  DIV  OUT_DIV  F_VCO    F_OUT    OK?",
               RP_X+10, FP_Y+522, "#405060", 9, "monospace");
            vcoExamples.forEach(function(ex, ei) {
               const ey = FP_Y + 536 + ei * 22;
               const c  = ex.ok ? "#4a8a4a" : "#8a3a3a";
               const sym = ex.ok ? "✓" : "✗";
               const row = ex.fin.padEnd(7) + " " +
                  String(ex.mult).padStart(4) + "  " +
                  String(ex.div).padStart(3) + "  " +
                  String(ex.outdiv).padStart(7) + "  " +
                  (ex.fvco + "MHz").padStart(8) + "  " +
                  (ex.fout + "MHz").padStart(7) + "  " + sym;
               VI.label("vco_ex_"+ei, row, RP_X+10, ey, c, 9, "monospace");
            });
            VI.label("vco_formula",
               "F_VCO = F_IN * MULT / DIVCLK_DIVIDE    must be 600-1600 MHz",
               RP_X+10, FP_Y+648, "#405060", 9, "monospace");

            // MTBF PANEL
            VI.rect("mtbf_bg", RP_X, FP_Y+684, RP_W, 120, "#0c0f18", "#2a3a50", 2, 4);
            VI.label("mtbf_title", "METASTABILITY  (Two-FF Synchronizer)",
               RP_X+10, FP_Y+694, "#8090a0", 11, "sans-serif");
            VI.label("mtbf_l1", "τ = 35 ps (28nm)  T_W = 60 ps  T_resolve = 4 ns (at 200 MHz)",
               RP_X+10, FP_Y+712, "#607080", 10, "monospace");
            VI.label("mtbf_l2", "MTBF = (T_CLK/(f_data*T_W)) * e^(T_resolve/τ)",
               RP_X+10, FP_Y+728, "#607080", 10, "monospace");
            VI.label("mtbf_l3", "     = 2.9 x 10^49 seconds  ≈ 10^42 years",
               RP_X+10, FP_Y+744, "#4fc3f7", 10, "monospace");
            VI.label("mtbf_l4", "Two-FF synchronizer is universally sufficient.",
               RP_X+10, FP_Y+760, "#4a8a4a", 10, "monospace");
            VI.label("mtbf_l5", "Both FFs MUST be in the SAME SLICE — maximizes T_resolve.",
               RP_X+10, FP_Y+776, "#8a6a20", 10, "monospace");

            // ================================================================
            // TOOLTIP / SELECTION PANEL
            // ================================================================
            const TP_Y = FP_Y + FP_H - 220;
            VI.rect("tp_bg", RP_X, TP_Y, RP_W, 215, "#0a1020", "#4fc3f7", 2, 4);

            if (self.tooltip) {
               VI.label("tp_title", self.tooltip.title,
                  RP_X + RP_W/2, TP_Y + 10, "#4fc3f7", 12, "sans-serif", "center");
               self.tooltip.lines.forEach(function(line, li) {
                  VI.label("tp_line_"+li, line,
                     RP_X + 10, TP_Y + 28 + li * 17, "#a0b8c8", 10, "monospace");
               });
            } else {
               VI.label("tp_prompt",
                  "Click any primitive on the floorplan to see its",
                  RP_X+RP_W/2, TP_Y+80, "#405060", 12, "sans-serif", "center");
               VI.label("tp_prompt2",
                  "architectural constraints, timing specs,",
                  RP_X+RP_W/2, TP_Y+100, "#405060", 12, "sans-serif", "center");
               VI.label("tp_prompt3",
                  "and legal/illegal use cases.",
                  RP_X+RP_W/2, TP_Y+120, "#405060", 12, "sans-serif", "center");
               VI.label("tp_hotkeys",
                  "1=BUFG  2=BUFR  3=BUFIO  4=MMCM  5=PLL  H=H-Tree  ESC=clear",
                  RP_X+RP_W/2, TP_Y+155, "#2a3a50", 10, "monospace", "center");
            }

            // ================================================================
            // POWER-ON SEQUENCE STRIP (bottom of floorplan)
            // ================================================================
            const PS_Y = FP_Y + FP_H + 10;
            VI.rect("ps_bg", FP_X, PS_Y, FP_W, 60, "#0c0f18", "#2a3a50", 2, 4);
            VI.label("ps_title", "POWER-ON SEQUENCE (mandatory):",
               FP_X+10, PS_Y+5, "#607080", 10, "sans-serif");

            const steps = [
               {n:"1", lbl:"VCCAUX", lbl2:"1.8V", color:"#4fc3f7"},
               {n:"2", lbl:"VCCINT", lbl2:"1.0V", color:"#66bb6a"},
               {n:"3", lbl:"VCCO", lbl2:"1.2-3.3V", color:"#ff9800"},
               {n:"4", lbl:"Config", lbl2:"Loads", color:"#8090a0"},
               {n:"5", lbl:"MMCM/PLL", lbl2:"Ramping", color:"#ce93d8"},
               {n:"6", lbl:"LOCKED", lbl2:"=1  !!!", color:"#f44336"},
               {n:"7", lbl:"Release", lbl2:"Reset", color:"#66bb6a"},
               {n:"8", lbl:"EOS", lbl2:"Asserts", color:"#4fc3f7"},
            ];
            const stepW = (FP_W - 20) / steps.length;
            steps.forEach(function(s, si) {
               const sx = FP_X + 10 + si * stepW;
               VI.rect("ps_step_"+si, sx, PS_Y+18, stepW-4, 36,
                  "#0a1018", s.color, 2, 3);
               VI.label("ps_n_"+si, s.n, sx + stepW/2, PS_Y+19,
                  s.color, 8, "monospace", "center");
               VI.label("ps_lbl_"+si, s.lbl, sx + stepW/2, PS_Y+29,
                  "#c0d0e0", 8, "sans-serif", "center");
               VI.label("ps_lbl2_"+si, s.lbl2, sx + stepW/2, PS_Y+41,
                  s.color, 8, "sans-serif", "center");
               if (si < steps.length - 1) {
                  VI.rect("ps_arr_"+si, sx + stepW - 4, PS_Y+32, 8, 2, "#405060");
               }
            });

            // ================================================================
            // CAMERA — first render centers the view
            // ================================================================
            if (self._firstRender) {
               self._firstRender = false;
               if (pane && pane.content) {
                  pane.content.contentScale = 0.88;
                  pane.content.userFocus    = {x: 750, y: 500};
                  pane.content.refreshContentPosition();
               }
            }

            // ================================================================
            // OVERLAY RENDERING
            // ================================================================
            if (self.expandedId && self.expandRect) {
               const er = self.expandRect;
               // Overlay background
               VI.rect("ovl_bg", er.x, er.y, er.w, er.h, "#080c14", "#4fc3f7", 2, 6);
               // Close button
               VI.rect("ovl_close", er.x + er.w - 26, er.y + 6, 20, 20, "#1a2a3a", "#f44336", 2, 4);
               VI.label("ovl_close_x", "X", er.x + er.w - 16, er.y + 8, "#f44336", 11, "sans-serif", "center");
               
               VI.onClick("ovl_close_btn", er.x + er.w - 26, er.y + 6, 20, 20, function() {
                  self.expandedId = null; self.expandRect = null; self.expandType = null;
                  VI.redraw();
               });

               // Dispatch to the correct expansion function
               if      (self.expandType === "bufg")   drawExpand_BUFG(er.x, er.y, er.w, er.h);
               else if (self.expandType === "bufr")   drawExpand_BUFR(er.x, er.y, er.w, er.h);
               else if (self.expandType === "bufio")  drawExpand_BUFIO(er.x, er.y, er.w, er.h);
               else if (self.expandType === "mmcm")   drawExpand_MMCM(er.x, er.y, er.w, er.h);
               else if (self.expandType === "pll")    drawExpand_PLL(er.x, er.y, er.w, er.h);
               else if (self.expandType === "hrow")   drawExpand_HROW(er.x, er.y, er.w, er.h);
               else if (self.expandType === "htree")  drawExpand_HTREE(er.x, er.y, er.w, er.h);
               else if (self.expandType === "region") drawExpand_REGION(er.x, er.y, er.w, er.h);
            }

         }
\SV
   endmodule
