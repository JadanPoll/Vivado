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
               VI._clickZones = VI._clickZones.filter(z => z.id !== id);
               VI._clickZones.push({id, x, y, w, h, cb});
            };

            VI.onHover = function(id, x, y, w, h, enter, leave) {
               VI._hoverZones[id] = {x, y, w, h, enter, leave, inside: false};
            };

            VI.clearAll = function() {
               self.getCanvas().clear();
               VI._labels = {}; VI._objects = {};
               VI._clickZones = []; VI._hoverZones = {};
            };

            const _hit = (z, cx, cy) =>
               cx >= z.x && cx <= z.x+z.w && cy >= z.y && cy <= z.y+z.h;

            fabric.document.addEventListener("mouseup", function(e) {
               const pos = VI.toCanvasCoords(e.clientX, e.clientY);
               VI._clickZones.forEach(z => { if (_hit(z,pos.x,pos.y)) z.cb(pos.x,pos.y); });
            });

            fabric.document.addEventListener("mousemove", function(e) {
               const pos = VI.toCanvasCoords(e.clientX, e.clientY);
               Object.keys(VI._hoverZones).forEach(id => {
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
            // selected: null | "bufg" | "bufr" | "bufio" | "mmcm" | "pll"
            //           | "htree" | "hrow" | "region0".."region5"
            self.selected = null;
            self.tooltip  = null;

            // Session cycle sync
            const pane = self._viz.pane;
            if (pane && pane.session) {
               pane.session.on("cycle-update", function() { VI.redraw(); });
            }

            // Hotkeys
            VI._hotkeys["Escape"] = function() { self.selected = null; VI.redraw(); };
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
            VI.label("title", "XC7S50 CLOCK DISTRIBUTION NETWORK — INTERACTIVE TOPOLOGY EXPLORER",
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
               "REGION\n[COL0,ROW0]", "REGION\n[COL1,ROW0]",
               "REGION\n[COL0,ROW1]", "REGION\n[COL1,ROW1]",
               "REGION\n[COL0,ROW2]", "REGION\n[COL1,ROW2]"
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
                     self.selected = "region" + ridx;
                     self.tooltip = {
                        title: "CLOCK REGION [" + col + "," + row + "]",
                        lines: [
                           "One of 6 clock regions on XC7S50 (2 col x 3 row).",
                           "Max 12 global BUFG clocks active here simultaneously.",
                           "Exceeding 12 → Vivado DRC error CLOCK-012.",
                           "Regional BUFR can only drive FFs in THIS region.",
                           "Global BUFG can drive FFs in ALL 6 regions.",
                           "HROW runs horizontally at the vertical midpoint.",
                        ]
                     };
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
               VI.label("hrow_lbl_"+hi, "HROW " + hi + "  (horizontal clock row — full die width)",
                  DIE_X + 5, hy - 14, hcolor, 9, "sans-serif");

               VI.onClick("hrow_clk_"+hi, DIE_X, hy-8, DIE_W, 16, function() {
                  self.selected = "hrow";
                  self.tooltip = {
                     title: "HROW — Horizontal Clock Row",
                     lines: [
                        "Physical copper wire running full die width.",
                        "Sits at vertical midpoint of each clock region row.",
                        "Receives clock from the vertical H-Tree spine.",
                        "Distributes clock horizontally to vertical column spines.",
                        "One HROW per row of clock regions = 3 HROWs on XC7S50.",
                        "Chip-wide skew via BUFG: < 200 ps FF-to-FF.",
                        "NOT routed through INT fabric — hardwired copper.",
                     ]
                  };
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
               self.selected = "htree";
               self.tooltip = {
                  title: "H-TREE  (Global Clock Distribution Spine)",
                  lines: [
                     "Balanced binary tree of copper wires — NOT routed through PIPs.",
                     "Physical design ensures equal path length to every leaf node.",
                     "Chip-wide clock skew via BUFG: < 200 ps FF-to-FF.",
                     "The name H-Tree comes from the H-shaped branching at each level.",
                     "Level 0: Full-width root bar at vertical die center.",
                     "Level 1: Vertical bars split left and right halves.",
                     "Level 2: Horizontal bars feed each HROW tap.",
                     "Contrast: routing CLK through INT fabric → ns-level skew.",
                     "32 BUFGs on XC7S50, each drives one independent H-Tree path.",
                  ]
               };
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
                  self.selected = "mmcm";
                  self.tooltip = {
                     title: "MMCME2_BASE / MMCME2_ADV",
                     lines: [
                        "XC7S50 has 5 MMCMs total, located in the CMT column.",
                        "VCO must run 600 – 1600 MHz (hard constraint — DRC if violated).",
                        "F_VCO = F_IN * CLKFBOUT_MULT / DIVCLK_DIVIDE",
                        "F_OUT = F_VCO / CLKOUT_DIVIDE",
                        "7 output clocks: CLKOUT0-6.",
                        "CLKOUT0 supports fractional divide (0.125 step).",
                        "Dynamic phase shift via PSEN/PSINCDEC: ~15 ps per step.",
                        "Spread spectrum for EMI reduction.",
                        "Higher intrinsic jitter than PLL — use PLL for ADC/SERDES clocks.",
                        "MMCM output MUST be buffered by BUFG before driving fabric.",
                        "!! Before LOCKED=1: output frequency is undefined !!",
                        "!! Always hold reset until LOCKED asserts !!",
                     ]
                  };
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
                  self.selected = "pll";
                  self.tooltip = {
                     title: "PLLE2_BASE / PLLE2_ADV",
                     lines: [
                        "XC7S50 has 5 PLLs total, in the CMT column.",
                        "VCO must run 600 – 1600 MHz (same as MMCM).",
                        "6 output clocks: CLKOUT0-5 (one fewer than MMCM).",
                        "Integer divide ONLY — no fractional divide.",
                        "No dynamic phase shift.",
                        "LOWER intrinsic jitter than MMCM.",
                        "Use PLL when: ADC sampling clock, SERDES reference,",
                        "  or any application where jitter is the primary constraint.",
                        "Use MMCM when: fractional divide needed, dynamic phase shift",
                        "  needed, or spread spectrum required.",
                        "PLL output MUST also be buffered by BUFG before fabric.",
                     ]
                  };
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
               self.selected = "bufg";
               self.tooltip = {
                  title: "BUFG — Global Clock Buffer (32 total)",
                  lines: [
                     "Drives the H-Tree: delivers clock to entire die, all FFs.",
                     "Chip-wide skew < 200 ps when using BUFG.",
                     "32 BUFGs available on XC7S50.",
                     "Max 12 active simultaneously in any one clock region.",
                     "Exceeding 12 active in one region → Vivado DRC: CLOCK-012.",
                     "Variants: BUFG (always on), BUFGCE (enable gate),",
                     "  BUFGMUX (glitch-free 2-input mux), BUFGCTRL (generalized).",
                     "BUFGCE: CE must be SYNCHRONOUS with the gated clock.",
                     "  Async CE change → partial pulse → FF state corruption.",
                     "BUFGMUX: provides glitch-free clock switching.",
                     "MMCM/PLL outputs MUST pass through BUFG before fabric.",
                     "  Using MMCM output directly → nanoseconds of skew.",
                  ]
               };
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
                     self.selected = "bufr";
                     self.tooltip = {
                        title: "BUFR — Regional Clock Buffer",
                        lines: [
                           "Drives CLB FFs and IOB logic within ONE clock region only.",
                           "Cannot cross clock region boundaries — DRC error if attempted.",
                           "Does NOT consume a BUFG slot.",
                           "Provides integer clock division: divide by 1, 2, 4, 6, or 8.",
                           "Useful for: clock division within a region, gating regional clocks,",
                           "  deriving slower clocks from a fast regional source.",
                           "Source: can be driven from IBUF, IBUFG, BUFMR, or MMCM.",
                           "6 BUFRs total on XC7S50 (one per clock region).",
                           "BUFR skew within one region: < 500 ps (vs < 200 ps for BUFG).",
                        ]
                     };
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
                  self.selected = "bufio";
                  self.tooltip = {
                     title: "BUFIO — I/O Clock Buffer",
                     lines: [
                        "Drives ONLY ILOGIC and OLOGIC within its I/O bank.",
                        "CANNOT drive CLB flip-flops — hard architectural constraint.",
                        "Lowest skew for I/O capture: < 100 ps within bank.",
                        "Optimized for source-synchronous capture (ISERDES).",
                        "Used with ISERDESE2 for high-speed serial deserialization.",
                        "Source: must come from the dedicated clock-capable I/O pin (MRCC/SRCC).",
                        "BUFMR (multi-region buffer) can drive BUFIOs in adjacent regions.",
                        "6 BUFIOs on XC7S50 (one per I/O bank).",
                        "Do NOT use BUFIO for any CLB logic — use BUFR or BUFG instead.",
                     ]
                  };
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
            VI.label("tap_hardwire_note",
               "taps = hardwired,\nnot PIPs",
               spX + INSET_W*0.5, INSET_Y + INSET_H - 18, "#405060", 7, "sans-serif", "center");

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
               {color: CLR.BUFG,  label: "BUFG / H-Tree   global, full-die, < 200ps skew"},
               {color: CLR.BUFR,  label: "BUFR            regional, one region, ÷1/2/4/6/8"},
               {color: CLR.BUFIO, label: "BUFIO           I/O only, ILOGIC/OLOGIC, < 100ps"},
               {color: CLR.MMCM,  label: "MMCM output     must pass BUFG before fabric"},
               {color: CLR.PLL,   label: "PLL output      lower jitter, must pass BUFG"},
               {color: CLR.HROW,  label: "HROW            horizontal clock row copper wire"},
               {color: CLR.SPINE, label: "Clock Spine     vertical column distribution wire"},
               {color: CLR.EXT,   label: "External path   pad → IBUF → BUFG/MMCM"},
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
            VI.label("vco_title", "VCO CONSTRAINT  (600 – 1600 MHz)",
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
               "F_VCO = F_IN * MULT / DIVCLK_DIVIDE   must be 600-1600 MHz",
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
               {n:"1", lbl:"VCCAUX\n1.8V", color:"#4fc3f7"},
               {n:"2", lbl:"VCCINT\n1.0V", color:"#66bb6a"},
               {n:"3", lbl:"VCCO\n1.2-3.3V", color:"#ff9800"},
               {n:"4", lbl:"Config\nLoads", color:"#8090a0"},
               {n:"5", lbl:"MMCM/PLL\nRamping", color:"#ce93d8"},
               {n:"6", lbl:"LOCKED\n=1  !!!", color:"#f44336"},
               {n:"7", lbl:"Release\nReset", color:"#66bb6a"},
               {n:"8", lbl:"EOS\nAsserts", color:"#4fc3f7"},
            ];
            const stepW = (FP_W - 20) / steps.length;
            steps.forEach(function(s, si) {
               const sx = FP_X + 10 + si * stepW;
               VI.rect("ps_step_"+si, sx, PS_Y+18, stepW-4, 36,
                  "#0a1018", s.color, 2, 3);
               VI.label("ps_n_"+si, s.n, sx + stepW/2, PS_Y+19,
                  s.color, 8, "monospace", "center");
               VI.label("ps_lbl_"+si, s.lbl.split("\n")[0], sx + stepW/2, PS_Y+29,
                  "#c0d0e0", 8, "sans-serif", "center");
               VI.label("ps_lbl2_"+si, s.lbl.split("\n")[1], sx + stepW/2, PS_Y+41,
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
         }
\SV
   endmodule
