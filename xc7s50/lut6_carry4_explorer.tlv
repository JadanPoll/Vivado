\m5_TLV_version 1d: tl-x.org
\m5
   use(m5-1.0)
\SV
   m5_makerchip_module
\TLV
   // =============================================================================
   // LUT6 INTERNAL SRAM + CARRY4 CHAIN EXPLORER
   // Teaches: LUT6 SRAM structure, fractured LUT5, CARRY4 chain, adder timing
   // XC7S50 / Vivado context
   // =============================================================================

   |lut
      @1
         $reset = *reset;
         $a_in[5:0] = *cyc_cnt[5:0];
         $init[63:0] = 64'hDEADBEEFCAFEBABE;
         $lut_out = $init[$a_in];
         $o5_func[4:0] = $a_in[4:0];
         $o5_out = $init[{1'b0,$o5_func}];
         $o6_out = $init[{1'b1,$o5_func}];
         $frac_valid = ($o5_out ^ $o6_out);
         `BOGUS_USE($lut_out $o5_out $o6_out $frac_valid)

   |adder
      @1
         $reset = *reset;
         $a_in[7:0] = *cyc_cnt[7:0];
         $b_in[7:0] = ~*cyc_cnt[7:0];
         $p[7:0] = $a_in ^ $b_in;
         $g[7:0] = $a_in & $b_in;
         $sum[8:0] = {1'b0,$a_in} + {1'b0,$b_in};
         $carry_out = $sum[8];
         $result[7:0] = $sum[7:0];
         `BOGUS_USE($p $g $carry_out $result)

   *passed = *cyc_cnt > 200;
   *failed = 1'b0;

   /viz
      \viz_js
         box: {width: 1550, height: 950, fill: "#07090f"},

         init() {
            const self = this;
            const VI = {};
            this._VI = VI;

            VI._labels    = {};
            VI._objects   = {};
            VI._clickZones = [];
            VI._hotkeys   = {};

            // ----------------------------------------------------------------
            // VI.redraw
            // ----------------------------------------------------------------
            VI.redraw = function() {
               if (self._viz && self._viz.pane) {
                  self._viz.pane.unrender();
                  self._viz.pane.render();
               }
               self.getCanvas().renderAll();
            };

            // ----------------------------------------------------------------
            // Canvas coordinate helper
            // ----------------------------------------------------------------
            const canvasEl = fabric.document.querySelector("canvas");
            VI.toCanvasCoords = function(cx, cy) {
               if (!canvasEl) return {x: 0, y: 0};
               const r   = canvasEl.getBoundingClientRect();
               const vpt = self.getCanvas().viewportTransform || [1, 0, 0, 1, 0, 0];
               return {
                  x: Math.round((cx - r.left - vpt[4]) / vpt[0]),
                  y: Math.round((cy - r.top  - vpt[5]) / vpt[3])
               };
            };

            // ----------------------------------------------------------------
            // VI.label
            // ----------------------------------------------------------------
            VI.label = function(id, text, x, y, color, fz, ff, align) {
               const c   = self.getCanvas();
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
                  if (color) VI._labels[id].set("fill",     color);
                  if (fz)    VI._labels[id].set("fontSize", fz);
               }
            };

            // ----------------------------------------------------------------
            // VI.rect
            // ----------------------------------------------------------------
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

            // ----------------------------------------------------------------
            // VI.onClick / VI.clearAll
            // ----------------------------------------------------------------
            VI.onClick = function(id, x, y, w, h, cb) {
               VI._clickZones = VI._clickZones.filter(function(z) { return z.id !== id; });
               VI._clickZones.push({id: id, x: x, y: y, w: w, h: h, cb: cb});
            };

            VI.clearAll = function() {
               self.getCanvas().clear();
               self.getCanvas().selection = false;
               VI._labels    = {};
               VI._objects   = {};
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

            // ----------------------------------------------------------------
            // Hotkeys  (registered once in init)
            // ----------------------------------------------------------------
            const _editorHasFocus = function() {
               const a   = fabric.document.activeElement;
               const tag = a ? a.tagName.toLowerCase() : "none";
               return tag === "textarea" || tag === "input" || (a && a.isContentEditable);
            };

            fabric.window.addEventListener("keydown", function(e) {
               if (_editorHasFocus()) return;
               if (VI._hotkeys[e.key]) VI._hotkeys[e.key](e);
            });

            // A / S  — step address (cycle) forward / backward
            VI._hotkeys["a"] = function() {
               const pane = self._viz.pane;
               try { pane.session.setCycle(Math.min(pane.waveData.endCycle, pane.cyc + 1)); } catch(ex) {}
               VI.redraw();
            };
            VI._hotkeys["s"] = function() {
               const pane = self._viz.pane;
               try { pane.session.setCycle(Math.max(pane.waveData.startCycle, pane.cyc - 1)); } catch(ex) {}
               VI.redraw();
            };
            VI._hotkeys["r"] = function() {
               const pane = self._viz.pane;
               try { pane.session.setCycle(pane.waveData.startCycle); } catch(ex) {}
               VI.redraw();
            };
            VI._hotkeys["h"] = function() {
               const pane = self._viz.pane;
               try { pane.highlightLogicalElement("|adder$result"); } catch(ex) {}
            };

            // cycle-update sync
            const pane0 = this._viz.pane;
            pane0.session.on("cycle-update", function() { VI.redraw(); });

            this._firstRender = true;
            this._expLUT      = false;
            this._expCarry    = false;
            this._expFrac     = false;
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

            // ----------------------------------------------------------------
            // Signal helpers
            // ----------------------------------------------------------------
            const getSig = function(name, c, def) {
               try { return wd.getSignalValueAtCycleByName(name, c).asInt(def); } catch(e) { return def; }
            };
            const getBig = function(name, c, def) {
               try { return wd.getSignalValueAtCycleByName(name, c).asBigInt(def); } catch(e) { return def; }
            };
            const safeCyc = function(c) {
               return Math.max(wd.startCycle, Math.min(wd.endCycle, c));
            };
            const toHex2 = function(v) {
               return "0x" + (v & 0xFF).toString(16).toUpperCase().padStart(2, "0");
            };
            const toHex16 = function(big) {
               return "0x" + big.toString(16).toUpperCase().padStart(16, "0");
            };
            const bit = function(big, i) {
               return Number((big >> BigInt(i)) & 1n);
            };

            // ----------------------------------------------------------------
            // Live signals — |lut
            // ----------------------------------------------------------------
            const a_in      = getSig("TLV|lut$a_in",      cyc, 0);
            const lut_out   = getSig("TLV|lut$lut_out",   cyc, 0);
            const o5_out    = getSig("TLV|lut$o5_out",    cyc, 0);
            const o6_out    = getSig("TLV|lut$o6_out",    cyc, 0);
            const frac_valid = getSig("TLV|lut$frac_valid", cyc, 0);
            const init_big  = getBig("TLV|lut$init",      cyc, 0xDEADBEEFCAFEBABEn);

            // ----------------------------------------------------------------
            // Live signals — |adder
            // ----------------------------------------------------------------
            const a8   = getSig("TLV|adder$a_in",    cyc, 0);
            const b8   = getSig("TLV|adder$b_in",    cyc, 0);
            const p8   = getSig("TLV|adder$p",       cyc, 0);
            const g8   = getSig("TLV|adder$g",       cyc, 0);
            const res8 = getSig("TLV|adder$result",  cyc, 0);
            const cout = getSig("TLV|adder$carry_out", cyc, 0);

            // ================================================================
            // ================================================================
            // PANEL L  — LUT6 INTERNAL SRAM EXPLORER
            // x=10, y=10, w=745, h=930
            // ================================================================
            // ================================================================
            VI.rect("pl_bg", 10, 10, 745, 930, "#0b0e14", "#2a4a6b", 2, 6);
            VI.label("pl_title", "LUT6 INTERNAL SRAM EXPLORER", 382, 18, "#4fc3f7", 14, "sans-serif", "center");

            // INIT hex display
            VI.rect("pl_init_bg", 15, 36, 736, 18, "#060810", "#334466", 1, 3);
            VI.label("pl_init_l",  "INIT[63:0] = ", 20, 39, "#546e7a", 9, "monospace");
            VI.label("pl_init_v",  toHex16(init_big), 105, 39, "#ffd54f", 9, "monospace");

            // ----------------------------------------------------------------
            // 8x8 SRAM grid  (64 cells)
            // row 0 = bits 0..7 (A[5:0] = 0..7), row 7 = bits 56..63
            // ----------------------------------------------------------------
            const GRID_X0 = 130;
            const GRID_Y0 = 62;
            const CELL    = 52;
            const GAP     = 2;

            // Address bus labels (A1-A6) on left
            VI.label("pl_abus_t", "ADDRESS BUS", 15, GRID_Y0 + 2, "#546e7a", 8, "sans-serif");
            const A_LABELS = ["A1", "A2", "A3", "A4", "A5", "A6"];
            for (let ai = 0; ai < 6; ai++) {
               (function(i) {
                  const ay = GRID_Y0 + 10 + i * 36;
                  VI.rect("pl_aw_" + i, 70, ay + 6, GRID_X0 - 72, 2, "#4fc3f7");
                  VI.label("pl_al_" + i, A_LABELS[i], 18, ay, "#4fc3f7", 10, "monospace");
                  const av = (a_in >> i) & 1;
                  VI.label("pl_av_" + i, "=" + av, 44, ay, av ? "#f44336" : "#81c784", 10, "monospace");
               })(ai);
            }

            // Row / col headers
            for (let col = 0; col < 8; col++) {
               (function(c) {
                  VI.label("pl_ch_" + c, String(c), GRID_X0 + c * (CELL + GAP) + CELL / 2, GRID_Y0 - 14, "#37474f", 8, "monospace", "center");
               })(col);
            }
            for (let row = 0; row < 8; row++) {
               (function(r) {
                  VI.label("pl_rh_" + r, String(r * 8), GRID_X0 - 28, GRID_Y0 + r * (CELL + GAP) + CELL / 2 - 6, "#37474f", 8, "monospace", "right");
               })(row);
            }

            // Cells
            for (let row = 0; row < 8; row++) {
               for (let col = 0; col < 8; col++) {
                  (function(r, c) {
                     const idx    = r * 8 + c;
                     const bv     = bit(init_big, idx);
                     const isSel  = (idx === a_in);
                     const isO5   = (idx < 32);
                     const cx     = GRID_X0 + c * (CELL + GAP);
                     const cy     = GRID_Y0 + r * (CELL + GAP);

                     let fill, stroke, sw;
                     if (isSel) {
                        fill   = "#1a3a10";
                        stroke = "#76ff03";
                        sw     = 2;
                     } else if (bv) {
                        fill   = isO5 ? "#0d2035" : "#0d1e35";
                        stroke = isO5 ? "#4fc3f7" : "#7e57c2";
                        sw     = 1;
                     } else {
                        fill   = "#080a0e";
                        stroke = "#1a2030";
                        sw     = 1;
                     }
                     VI.rect("pl_cell_" + idx, cx, cy, CELL, CELL, fill, stroke, sw, 3);
                     VI.label("pl_cbv_" + idx, String(bv), cx + CELL / 2, cy + CELL / 2 - 7, bv ? (isO5 ? "#4fc3f7" : "#ce93d8") : "#334455", 14, "monospace", "center");
                     VI.label("pl_cid_" + idx, String(idx), cx + CELL / 2, cy + CELL - 14, isSel ? "#76ff03" : "#263238", 7, "monospace", "center");
                  })(row, col);
               }
            }

            // Dividing line at row 4 (bit 32) — fractured LUT boundary
            const divY = GRID_Y0 + 4 * (CELL + GAP) - 3;
            VI.rect("pl_frac_div", GRID_X0 - 2, divY, 8 * (CELL + GAP) + 2, 3, "#ff9800");
            VI.label("pl_frac_dl", "A6=0 (O5 domain)", GRID_X0 + 8 * (CELL + GAP) + 6, GRID_Y0 + 1 * (CELL + GAP) + 12, "#4fc3f7", 8, "monospace");
            VI.label("pl_frac_dh", "A6=1 (O6 domain)", GRID_X0 + 8 * (CELL + GAP) + 6, GRID_Y0 + 5 * (CELL + GAP) + 12, "#7e57c2", 8, "monospace");

            // Selected cell pointer + output
            const selRow  = Math.floor(a_in / 8);
            const selCol  = a_in % 8;
            const selCX   = GRID_X0 + selCol * (CELL + GAP) + CELL / 2;
            const selCY   = GRID_Y0 + selRow * (CELL + GAP);
            VI.rect("pl_sel_ptr", selCX - 1, selCY - 12, 2, 12, "#76ff03");
            VI.label("pl_sel_lbl", "A[5:0]=" + a_in, selCX, selCY - 22, "#76ff03", 8, "monospace", "center");

            // O6 output wire on right
            const outX = GRID_X0 + 8 * (CELL + GAP) + 6;
            VI.rect("pl_o6_wire", GRID_X0 + 8 * (CELL + GAP), GRID_Y0 + selRow * (CELL + GAP) + CELL / 2, 50, 2, lut_out ? "#76ff03" : "#334466");
            VI.rect("pl_o6_bg",   outX + 44, GRID_Y0 + 200, 100, 32, "#060a06", "#76ff03", 2, 4);
            VI.label("pl_o6_tl",  "O6 OUT", outX + 94, GRID_Y0 + 204, "#76ff03", 9, "monospace", "center");
            VI.label("pl_o6_val", String(lut_out), outX + 94, GRID_Y0 + 216, lut_out ? "#76ff03" : "#334466", 16, "monospace", "center");

            // Address formula
            VI.rect("pl_form_bg", 15, GRID_Y0 + 8 * (CELL + GAP) + 8, 736, 36, "#060810", "#334466", 1, 3);
            VI.label("pl_form_t",  "INIT address = A6*32 + A5*16 + A4*8 + A3*4 + A2*2 + A1", 382, GRID_Y0 + 8 * (CELL + GAP) + 12, "#ffd54f", 9, "monospace", "center");
            VI.label("pl_form_v",  "Current: A[5:0]=" + a_in.toString(2).padStart(6, "0") + " (decimal " + a_in + ")  INIT[" + a_in + "]=" + lut_out, 382, GRID_Y0 + 8 * (CELL + GAP) + 23, "#81c784", 9, "monospace", "center");

            // ----------------------------------------------------------------
            // Fractured LUT5 illustration
            // ----------------------------------------------------------------
            const FRAC_Y = GRID_Y0 + 8 * (CELL + GAP) + 52;
            VI.rect("pl_frac_bg",  15, FRAC_Y, 736, 140, "#07080c", "#ff9800", 2, 5);
            VI.label("pl_frac_t",  "FRACTURED LUT5 MODE", 382, FRAC_Y + 6, "#ff9800", 12, "sans-serif", "center");

            // O5 strip (lower 32 bits)
            VI.rect("pl_o5_bg", 20, FRAC_Y + 24, 348, 48, "#060d10", "#4fc3f7", 1, 4);
            VI.label("pl_o5_t",  "O5 output  (A6=0, bits [31:0])", 194, FRAC_Y + 28, "#4fc3f7", 9, "monospace", "center");
            for (let bi = 0; bi < 32; bi++) {
               (function(i) {
                  const bv  = bit(init_big, i);
                  const bx  = 24 + i * 10;
                  const sel = ((a_in & 0x1F) === i && (a_in & 0x20) === 0);
                  VI.rect("pl_o5b_" + i, bx, FRAC_Y + 40, 8, 18, bv ? "#0d2035" : "#080a10", bv ? (sel ? "#76ff03" : "#4fc3f7") : "#1a2030", sel ? 2 : 1, 1);
               })(bi);
            }
            VI.label("pl_o5_v", "O5=" + o5_out, 20, FRAC_Y + 62, o5_out ? "#4fc3f7" : "#546e7a", 10, "monospace");

            // O6 strip (upper 32 bits)
            VI.rect("pl_o6s_bg", 378, FRAC_Y + 24, 348, 48, "#0a0610", "#7e57c2", 1, 4);
            VI.label("pl_o6s_t",  "O6 output  (A6=1, bits [63:32])", 552, FRAC_Y + 28, "#7e57c2", 9, "monospace", "center");
            for (let bi = 0; bi < 32; bi++) {
               (function(i) {
                  const bv  = bit(init_big, i + 32);
                  const bx  = 382 + i * 10;
                  const sel = ((a_in & 0x1F) === i && (a_in & 0x20) !== 0);
                  VI.rect("pl_o6b_" + i, bx, FRAC_Y + 40, 8, 18, bv ? "#0d0d20" : "#080a10", bv ? (sel ? "#76ff03" : "#7e57c2") : "#1a1a30", sel ? 2 : 1, 1);
               })(bi);
            }
            VI.label("pl_o6s_v", "O6=" + o6_out, 378, FRAC_Y + 62, o6_out ? "#7e57c2" : "#546e7a", 10, "monospace");

            VI.label("pl_frac_n1", "FRACTURED LUT5: two independent 5-input functions sharing one LUT site.", 382, FRAC_Y + 80, "#ff9800", 8, "sans-serif", "center");
            VI.label("pl_frac_n2", "Constraint: both functions MUST share the same A1-A5 inputs.", 382, FRAC_Y + 91, "#ffd54f", 8, "sans-serif", "center");
            VI.label("pl_frac_n3", "frac_valid (O5 XOR O6) = " + frac_valid + "  -- outputs differ = truly independent functions", 382, FRAC_Y + 102, frac_valid ? "#4caf50" : "#546e7a", 8, "monospace", "center");
            VI.label("pl_frac_n4", "Synthesis uses fractured LUT when carry chain needs P (O6) and G (O5) simultaneously.", 382, FRAC_Y + 113, "#546e7a", 8, "sans-serif", "center");
            VI.label("pl_frac_n5", "Resource impact: 2x effective LUT utilization from same BEL site.", 382, FRAC_Y + 124, "#4fc3f7", 8, "sans-serif", "center");

            // ----------------------------------------------------------------
            // LUT detail expand panel
            // ----------------------------------------------------------------
            const EXP_Y = FRAC_Y + 148;
            const self  = this;

            VI.rect("pl_exp_btn", 15, EXP_Y, 736, 18, this._expLUT ? "#0d1a0d" : "#070e07", this._expLUT ? "#4caf50" : "#335533", 1, 3);
            VI.label("pl_exp_lbl", (this._expLUT ? "[-]" : "[+]") + " LUT6 delay theory: mux tree, 63 transistors, why K=6", 20, EXP_Y + 2, "#81c784", 9, "monospace");
            VI.onClick("pl_exp_btn", 15, EXP_Y, 736, 18, function() { self._expLUT = !self._expLUT; VI.redraw(); });

            if (this._expLUT) {
               VI.rect("pl_exp_bg", 15, EXP_Y + 20, 736, 88, "#050e05", "#335533", 1, 3);
               VI.label("pl_el1", "CONSTANT DELAY: LUT output delay is fixed regardless of function (unlike gate networks).", 20, EXP_Y + 24, "#81c784", 8, "sans-serif");
               VI.label("pl_el2", "STRUCTURE: 63-transistor pass-transistor mux tree. 64 SRAM cells -> 6 mux stages -> 1 output.", 20, EXP_Y + 35, "#4fc3f7", 8, "sans-serif");
               VI.label("pl_el3", "STAGE DELAY: each mux stage ~0.08ns. Total I->O ~0.52ns (Artix-7 -1 speed grade).", 20, EXP_Y + 46, "#ffd54f", 8, "sans-serif");
               VI.label("pl_el4", "WHY K=6: Rose et al. 1990 showed K=4..6 optimal for area-delay. K=6 was validated for", 20, EXP_Y + 57, "#ce93d8", 8, "sans-serif");
               VI.label("pl_el5", "  deep sub-micron processes. K=4 wastes routing resources. K=8 increases mux depth.", 20, EXP_Y + 68, "#ce93d8", 8, "sans-serif");
               VI.label("pl_el6", "SRAM retention: config SRAM holds bits as long as power is applied. Not flash -- volatile.", 20, EXP_Y + 79, "#ff9800", 8, "sans-serif");
               VI.label("pl_el7", "RECONFIGURATION: SRAM can be rewritten by partial reconfiguration (PR) in <1ms.", 20, EXP_Y + 90, "#546e7a", 8, "sans-serif");
            }

            // Fractured expand
            const EXP_Y2 = EXP_Y + 20 + (this._expLUT ? 90 : 0);
            VI.rect("pl_exp2_btn", 15, EXP_Y2, 736, 18, this._expFrac ? "#100d00" : "#0a0800", this._expFrac ? "#ff9800" : "#554400", 1, 3);
            VI.label("pl_exp2_lbl", (this._expFrac ? "[-]" : "[+]") + " Synthesis rules for fractured LUT5 inference", 20, EXP_Y2 + 2, "#ffc107", 9, "monospace");
            VI.onClick("pl_exp2_btn", 15, EXP_Y2, 736, 18, function() { self._expFrac = !self._expFrac; VI.redraw(); });

            if (this._expFrac) {
               VI.rect("pl_exp2_bg", 15, EXP_Y2 + 20, 736, 68, "#0a0800", "#554400", 1, 3);
               VI.label("pl_ef1", "Vivado automatically uses fractured LUT when two 5-input functions share inputs A1-A5.", 20, EXP_Y2 + 24, "#ffc107", 8, "sans-serif");
               VI.label("pl_ef2", "Carry chain inference is primary trigger: P=A^B uses O6, G=A&B uses O5, same A1-A5.", 20, EXP_Y2 + 35, "#ffd54f", 8, "sans-serif");
               VI.label("pl_ef3", "Constraint (* KEEP *) prevents packing: forces two separate LUT sites.", 20, EXP_Y2 + 46, "#ff9800", 8, "sans-serif");
               VI.label("pl_ef4", "SliceM and SliceL both support fractured LUT5. Distinct from SRL (SliceM only).", 20, EXP_Y2 + 57, "#ff9800", 8, "sans-serif");
               VI.label("pl_ef5", "O5 is available only if CE and SR inputs of the FF in the same slice are unused.", 20, EXP_Y2 + 68, "#546e7a", 8, "sans-serif");
               VI.label("pl_ef6", "Check utilization report for LUT as Logic 5-input vs 6-input for packing efficiency.", 20, EXP_Y2 + 79, "#546e7a", 7, "sans-serif");
            }

            // ================================================================
            // ================================================================
            // PANEL R  — CARRY4 CHAIN EXPLORER
            // x=765, y=10, w=775, h=930
            // ================================================================
            // ================================================================
            VI.rect("pr_bg", 765, 10, 775, 930, "#0b0e14", "#2a4a6b", 2, 6);
            VI.label("pr_title", "CARRY4 CHAIN EXPLORER  (8-bit adder)", 1152, 18, "#4fc3f7", 14, "sans-serif", "center");

            // Live adder values header
            VI.rect("pr_hdr_bg", 770, 36, 766, 20, "#060810", "#334466", 1, 3);
            VI.label("pr_hdr_a",  "A=" + toHex2(a8) + " (" + a8 + ")", 775,  39, "#ffd54f", 9, "monospace");
            VI.label("pr_hdr_b",  "B=" + toHex2(b8) + " (" + b8 + ")", 885,  39, "#ce93d8", 9, "monospace");
            VI.label("pr_hdr_r",  "A+B=" + toHex2(res8) + " (" + res8 + ")", 995, 39, "#4caf50", 9, "monospace");
            VI.label("pr_hdr_co", "COUT=" + cout, 1180, 39, cout ? "#f44336" : "#546e7a", 9, "monospace");

            // ----------------------------------------------------------------
            // CARRY4 chain — 8 bit positions, 2 CARRY4 primitives
            // Laid out vertically.  Carry flows upward (North).
            // ----------------------------------------------------------------
            const CY0   = 630;    // top of bit-7 row (highest bit, top of page visually)
            const CSTEP = 68;     // px per bit row
            const CX0   = 820;    // left edge of bit diagrams

            // Column headers
            VI.label("pr_ch_bit", "BIT",  CX0,      CY0 - 24, "#546e7a", 9, "monospace");
            VI.label("pr_ch_p",   "P",    CX0 + 62,  CY0 - 24, "#4fc3f7", 9, "monospace");
            VI.label("pr_ch_g",   "G",    CX0 + 122, CY0 - 24, "#ff9800", 9, "monospace");
            VI.label("pr_ch_ci",  "CI",   CX0 + 182, CY0 - 24, "#ce93d8", 9, "monospace");
            VI.label("pr_ch_s",   "S",    CX0 + 242, CY0 - 24, "#81c784", 9, "monospace");
            VI.label("pr_ch_co",  "CO",   CX0 + 302, CY0 - 24, "#f44336", 9, "monospace");

            // Compute carry chain manually
            let carry = 0;
            const carries = [0];
            for (let bi2 = 0; bi2 < 8; bi2++) {
               const pBit = (p8 >> bi2) & 1;
               const gBit = (g8 >> bi2) & 1;
               carry = gBit | (pBit & carry);
               carries.push(carry);
            }

            // Draw CARRY4 boundary boxes
            VI.rect("pr_c4_0_bg", CX0 - 8, CY0 - 4 + 4 * CSTEP, 380, 4 * CSTEP + 4, "#070a10", "#334466", 1, 4);
            VI.label("pr_c4_0_t", "CARRY4 [0]  (bits 0-3)", CX0 - 4, CY0 + 4 * CSTEP + 8, "#334466", 8, "monospace");
            VI.rect("pr_c4_1_bg", CX0 - 8, CY0 - 4,            380, 4 * CSTEP + 4, "#070a10", "#334466", 1, 4);
            VI.label("pr_c4_1_t", "CARRY4 [1]  (bits 4-7)", CX0 - 4, CY0 + 8,             "#334466", 8, "monospace");

            // Per-bit rows
            for (let bi2 = 0; bi2 < 8; bi2++) {
               (function(b) {
                  const row   = 7 - b;
                  const ry    = CY0 + row * CSTEP;
                  const pBit  = (p8 >> b) & 1;
                  const gBit  = (g8 >> b) & 1;
                  const ciBit = carries[b];
                  const sBit  = (res8 >> b) & 1;
                  const coBit = carries[b + 1];

                  const pc = pBit  ? "#4fc3f7" : "#1a2a3a";
                  const gc = gBit  ? "#ff9800" : "#2a1a0a";
                  const cc = ciBit ? "#ce93d8" : "#1a1030";
                  const sc = sBit  ? "#81c784" : "#0a1a0a";
                  const oc = coBit ? "#f44336" : "#1a0808";

                  // Bit index
                  VI.rect("pr_bit_bg_" + b, CX0, ry, 52, 52, "#060810", "#263238", 1, 3);
                  VI.label("pr_bit_n_" + b, "bit[" + b + "]", CX0 + 26, ry + 14, "#8892b0", 9, "monospace", "center");
                  const aBit = (a8 >> b) & 1;
                  const bBit = (b8 >> b) & 1;
                  VI.label("pr_bit_ab_" + b, "A=" + aBit + " B=" + bBit, CX0 + 26, ry + 28, "#546e7a", 8, "monospace", "center");

                  // P box
                  VI.rect("pr_p_" + b, CX0 + 60, ry + 10, 48, 30, pBit ? "#0d2035" : "#080a10", pc, 1, 3);
                  VI.label("pr_pv_" + b, String(pBit), CX0 + 84, ry + 19, pc, 14, "monospace", "center");

                  // G box
                  VI.rect("pr_g_" + b, CX0 + 116, ry + 10, 48, 30, gBit ? "#1a1000" : "#080a10", gc, 1, 3);
                  VI.label("pr_gv_" + b, String(gBit), CX0 + 140, ry + 19, gc, 14, "monospace", "center");

                  // CI wire
                  VI.rect("pr_ci_" + b, CX0 + 172, ry + 10, 48, 30, ciBit ? "#0e0a14" : "#06060a", cc, 1, 3);
                  VI.label("pr_civ_" + b, String(ciBit), CX0 + 196, ry + 19, cc, 14, "monospace", "center");

                  // S (sum) box
                  VI.rect("pr_s_" + b, CX0 + 228, ry + 10, 48, 30, sBit ? "#0a140a" : "#060a06", sc, 1, 3);
                  VI.label("pr_sv_" + b, String(sBit), CX0 + 252, ry + 19, sc, 14, "monospace", "center");

                  // CO box
                  VI.rect("pr_co_" + b, CX0 + 284, ry + 10, 48, 30, coBit ? "#140808" : "#0a0606", oc, 1, 3);
                  VI.label("pr_cov_" + b, String(coBit), CX0 + 308, ry + 19, oc, 14, "monospace", "center");

                  // Carry chain vertical wire
                  if (b < 7) {
                     const prevRow = 7 - (b + 1);
                     const wireY   = ry - CSTEP + 40;
                     const wireC   = coBit ? "#f44336" : "#2a0a0a";
                     VI.rect("pr_cchain_" + b, CX0 + 196, wireY, 2, CSTEP, wireC);
                  }

                  // LUT fractured feed annotation
                  VI.rect("pr_lut_feed_" + b, CX0 + 344, ry + 4, 168, 44, "#070812", "#263238", 1, 2);
                  VI.label("pr_lf1_" + b, "LUT O6 -> P = A^B", CX0 + 428, ry + 11, "#4fc3f7", 7, "monospace", "center");
                  VI.label("pr_lf2_" + b, "LUT O5 -> G = A&B", CX0 + 428, ry + 24, "#ff9800", 7, "monospace", "center");
                  VI.label("pr_lf3_" + b, "shared A1-A5",      CX0 + 428, ry + 35, "#546e7a", 7, "sans-serif", "center");
                  // Wires from LUT box to P and G
                  VI.rect("pr_lfw_p_" + b, CX0 + 344, ry + 15, 12, 2, "#4fc3f7");
                  VI.rect("pr_lfw_g_" + b, CX0 + 344, ry + 28, 12, 2, "#ff9800");
                  VI.rect("pr_lfw_pb_" + b, CX0 + 108, ry + 22, 8, 2, "#4fc3f7");
                  VI.rect("pr_lfw_gb_" + b, CX0 + 164, ry + 22, 8, 2, "#ff9800");
               })(bi2);
            }

            // CYINIT at bottom (bit 0 carry-in = 0)
            VI.rect("pr_cyinit_bg", CX0 + 180, CY0 + 7 * CSTEP + 58, 38, 18, "#060a0e", "#4fc3f7", 1, 3);
            VI.label("pr_cyinit_l", "CYINIT=0", CX0 + 199, CY0 + 7 * CSTEP + 62, "#4fc3f7", 8, "monospace", "center");
            VI.rect("pr_cyinit_w", CX0 + 197, CY0 + 7 * CSTEP + 44, 2, 14, "#4fc3f7");

            // Final COUT at top
            VI.rect("pr_cout_bg", CX0 + 180, CY0 - 42, 38, 18, cout ? "#1a0808" : "#060a0e", "#f44336", 1, 3);
            VI.label("pr_cout_l",  "COUT=" + cout, CX0 + 199, CY0 - 38, cout ? "#f44336" : "#546e7a", 9, "monospace", "center");
            VI.rect("pr_cout_w",   CX0 + 197, CY0 - 24, 2, 20, cout ? "#f44336" : "#2a0a0a");

            // ----------------------------------------------------------------
            // Strictly-North constraint diagram
            // ----------------------------------------------------------------
            VI.rect("pr_north_bg", 770, 64, 766, 120, "#06060a", "#2a4a6b", 1, 4);
            VI.label("pr_north_t",  "CARRY CHAIN: STRICTLY NORTH DIRECTION", 1152, 70, "#4fc3f7", 11, "sans-serif", "center");

            // Arrow pointing north
            VI.rect("pr_n_arr_v", 870, 82, 4, 72, "#4fc3f7");
            VI.rect("pr_n_arr_l", 858, 82, 12, 4, "#4fc3f7");
            VI.rect("pr_n_arr_r", 874, 82, 12, 4, "#4fc3f7");
            VI.label("pr_n_north",  "NORTH", 866, 72, "#4fc3f7", 8, "monospace");
            VI.label("pr_n_only",   "ONLY", 868, 160, "#4fc3f7", 8, "monospace");

            VI.label("pr_n1", "Hardwired silicon connections, not PIPs.", 900, 76, "#e0e0e0", 8, "sans-serif");
            VI.label("pr_n2", "Horizontal span: impossible for CARRY4.", 900, 87, "#f44336", 8, "sans-serif");
            VI.label("pr_n3", "64-bit adder = 16 CARRY4 stacked, same column.", 900, 98, "#ffd54f", 8, "sans-serif");
            VI.label("pr_n4", "Crosses Slice boundary every 4 bits (2 Slices/CARRY4).", 900, 109, "#81c784", 8, "sans-serif");
            VI.label("pr_n5", "Placement constraint: keep adder bits in same column.", 900, 120, "#546e7a", 8, "sans-serif");
            VI.label("pr_n6", "Vivado auto-places in column; Pblock needed for DSP proximity.", 900, 131, "#546e7a", 8, "sans-serif");
            VI.label("pr_n7", "Column boundary = IOB, BRAM, DSP column: chain cannot cross.", 900, 142, "#f44336", 8, "sans-serif");
            VI.label("pr_n8", "Design rule: Pblock adder + multiplier = critical for tight timing.", 900, 153, "#546e7a", 7, "sans-serif");
            VI.label("pr_n9", "Artix-7: XC7S50 has 32 CLB columns usable for CARRY chains.", 900, 163, "#37474f", 7, "sans-serif");

            // ----------------------------------------------------------------
            // Timing comparison
            // ----------------------------------------------------------------
            VI.rect("pr_time_bg", 770, 192, 766, 58, "#060a06", "#334466", 1, 4);
            VI.label("pr_time_t",  "TIMING COMPARISON: CARRY4 vs LUT arithmetic", 1152, 198, "#4fc3f7", 11, "sans-serif", "center");

            VI.rect("pr_t_c4",  775, 212, 260, 32, "#060a06", "#4caf50", 1, 3);
            VI.label("pr_t_c41", "CARRY4  CI -> CO", 905, 216, "#4caf50", 10, "monospace", "center");
            VI.label("pr_t_c42", "0.10 ns  (Artix-7 -1)", 905, 229, "#4caf50", 10, "monospace", "center");

            VI.rect("pr_t_lut", 1044, 212, 260, 32, "#0a0606", "#f44336", 1, 3);
            VI.label("pr_t_lut1", "LUT6  I -> O", 1174, 216, "#f44336", 10, "monospace", "center");
            VI.label("pr_t_lut2", "0.52 ns  (5.2x slower)", 1174, 229, "#f44336", 10, "monospace", "center");

            VI.label("pr_t_ratio", "5x faster than LUT-based ripple carry. 8-bit CARRY4 chain total: ~0.45ns end-to-end.", 1152, 246, "#ffd54f", 8, "sans-serif", "center");

            // ----------------------------------------------------------------
            // Carry chain expand panel
            // ----------------------------------------------------------------
            const CR_EXP_Y = 256;
            VI.rect("pr_exp_btn", 770, CR_EXP_Y, 766, 18, this._expCarry ? "#0d1a0d" : "#070e07", this._expCarry ? "#4caf50" : "#335533", 1, 3);
            VI.label("pr_exp_lbl", (this._expCarry ? "[-]" : "[+]") + " CARRY4 advanced: popcount, CYINIT seeding, Pblock constraint", 775, CR_EXP_Y + 2, "#81c784", 9, "monospace");
            VI.onClick("pr_exp_btn", 770, CR_EXP_Y, 766, 18, function() { self._expCarry = !self._expCarry; VI.redraw(); });

            if (this._expCarry) {
               VI.rect("pr_exp_bg", 770, CR_EXP_Y + 20, 766, 88, "#050e05", "#335533", 1, 3);
               VI.label("pr_ec1", "POPCOUNT: CARRY4 used to count set bits. P=partial_sum, G=carry_generate from LUT XOR/AND.", 775, CR_EXP_Y + 24, "#81c784", 8, "sans-serif");
               VI.label("pr_ec2", "  Compressor tree maps N bits to log2(N) CARRY4 stages. 64-bit popcount = 6 stages.", 775, CR_EXP_Y + 35, "#4fc3f7", 8, "sans-serif");
               VI.label("pr_ec3", "CYINIT: seeds the first carry. CYINIT=0 for adders. CYINIT=1 for subtractors (two's complement).", 775, CR_EXP_Y + 46, "#ffd54f", 8, "sans-serif");
               VI.label("pr_ec4", "  Mux selects between CIN pin (cascade) and CYINIT (seeding). Only the first primitive uses CYINIT.", 775, CR_EXP_Y + 57, "#ffd54f", 8, "sans-serif");
               VI.label("pr_ec5", "PBLOCK: if CARRY4 chain spans > half the device height, Vivado may route poorly.", 775, CR_EXP_Y + 68, "#ff9800", 8, "sans-serif");
               VI.label("pr_ec6", "  Use PBLOCK constraints to pin arithmetic logic near the bottom of the die.", 775, CR_EXP_Y + 79, "#ff9800", 8, "sans-serif");
               VI.label("pr_ec7", "  XC7S50: 50K LUTs, device height ~200 CLB rows. 64-bit adder = 16 CARRY4 = 32 CLB rows.", 775, CR_EXP_Y + 90, "#546e7a", 8, "sans-serif");
               VI.label("pr_ec8", "  Pblock covers carry column + adjacent LUT columns for P/G inputs.", 775, CR_EXP_Y + 99, "#546e7a", 7, "sans-serif");
            }

            // ================================================================
            // HOTKEY LEGEND
            // ================================================================
            VI.rect("pr_key_bg", 770, 912, 766, 20, "#06080c", "#263238", 1, 3);
            VI.label("pr_key_l",  "Keys: [A] step forward  [S] step back  [R] reset to cycle 0  [H] highlight carry result", 1152, 916, "#37474f", 8, "sans-serif", "center");

            // ================================================================
            // GLOBAL CYCLE SCRUBBER
            // ================================================================
            VI.rect("sc_bg", 10, 944, 1530, 3, "#1a2a3a");
            const scRange = Math.max(1, wd.endCycle - wd.startCycle);
            const scX = 10 + (cyc - wd.startCycle) * 1530 / scRange;
            VI.rect("sc_h", Math.min(scX, 1530), 941, 4, 8, "#4fc3f7");
            VI.onClick("sc_bg", 10, 941, 1530, 11, function(x) {
               const nc = Math.round(wd.startCycle + (x - 10) * scRange / 1530);
               try { pane.session.setCycle(Math.max(wd.startCycle, Math.min(wd.endCycle, nc))); } catch(e) {}
               VI.redraw();
            });

            // LUT grid cell click -> highlight lut_out
            VI.onClick("pl_grid_click", GRID_X0, GRID_Y0, 8 * (CELL + GAP), 8 * (CELL + GAP), function() {
               try { pane.highlightLogicalElement("|lut$lut_out"); } catch(e) {}
            });

            // ================================================================
            // CAMERA
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
