/**
 * ftdi-jtag.js - Production Grade UG470 Driver
 * Implements strict JTAG TAP state machine, active flushing,
 * safe 0x39 reads, and atomic debugging telemetry.
 */

const REV_LUT = new Uint8Array(256);
for (let i = 0; i < 256; i++) {
    REV_LUT[i] = ((i & 1) << 7) | ((i & 2) << 5) | ((i & 4) << 3) | ((i & 8) << 1) |
                 ((i & 16) >> 1) | ((i & 32) >> 3) | ((i & 64) >> 5) | ((i & 128) >> 7);
}

const JTAG_DEBUG = true; // Set to false to silence telemetry in production

class WebUSBJtag {
    constructor(device) {
        this.device = device;
        this.epIn = null; this.epOut = null;
        this.maxPacketSize = 512;
    }

    _logTransfer(direction, data, label = "") {
        if (!JTAG_DEBUG) return;
        const slice = data.slice(0, 16);
        const hex = Array.from(slice).map(b => ('0' + b.toString(16)).slice(-2).toUpperCase()).join(' ');
        const truncated = data.length > 16 ? ' ...' : '';
        console.log(`[JTAG ${direction}] ${label ? label.padEnd(8) + '| ' : ''}${hex}${truncated} (${data.length}B)`);
    }

    async _transferOut(data, label = "") {
        this._logTransfer("OUT", data, label);
        await this.device.transferOut(this.epOut, data);
    }

    async init(freqHz = 30000000) {
        await this.device.open();
        if (this.device.configuration === null) await this.device.selectConfiguration(1);
        await this.device.claimInterface(0);
        const alt = this.device.configuration.interfaces[0].alternates[0];
        for (const ep of alt.endpoints) {
            if (ep.direction === 'in') this.epIn = ep.endpointNumber;
            if (ep.direction === 'out') this.epOut = ep.endpointNumber;
        }
        await this.controlTransfer(0x00, 0x0000);
        await this.controlTransfer(0x09, 0x0002);
        await this.controlTransfer(0x0B, 0x0200);
        await this.flush();
        const divisor = Math.max(0, Math.floor(60000000 / (freqHz * 2) - 1));
        await this._transferOut(new Uint8Array([0x8A, 0x85, 0x8D, 0x97, 0x86, divisor & 0xFF, (divisor >> 8) & 0xFF, 0x80, 0x08, 0x0B, 0x87]), "INIT");
        console.log(`[USB] MPSSE Ready @ ${freqHz/1e6}MHz`);
    }

    async shiftTMS(tms, count, tdi = 0) {
        await this._transferOut(new Uint8Array([0x4A, count-1, (tdi ? 0x80 : 0x00)|(tms & 0x7F)]), "TMS");
    }

    async shiftIR(instruction, len = 6) {
        await this.shiftTMS(0x03, 4);
        await this._transferOut(new Uint8Array([0x1B, len-2, instruction & 0xFF]), `IR(0x${instruction.toString(16)})`);
        await this.shiftTMS(0x03, 3, (instruction>>(len-1)) & 1);
    }

    async shiftDRBulk(tdi) {
        const bytes = tdi.length - 1; // Leave 1 byte for the TMS exit
        const maxChunk = 65536;       // 16-bit length limit per FTDI spec
        const numChunks = Math.ceil(bytes / maxChunk);
        
        // Calculate exact buffer size needed:
        // 3B (Enter) + [3B header + Data] per chunk + 7B (Exit)
        const totalSize = 3 + (numChunks * 3) + bytes + 7;
        const cmd = new Uint8Array(totalSize);
        let ptr = 0;
        
        // 1. Enter Shift-DR
        cmd.set([0x4A, 2, 0x01], ptr); 
        ptr += 3;
        
        // 2. Pack the 2MB payload into safe 64KB MPSSE chunks
        let offset = 0;
        while (offset < bytes) {
            const chunkBytes = Math.min(maxChunk, bytes - offset);
            const len = chunkBytes - 1;
            
            cmd.set([0x19, len & 0xFF, (len >> 8) & 0xFF], ptr); 
            ptr += 3;
            
            cmd.set(tdi.subarray(offset, offset + chunkBytes), ptr); 
            ptr += chunkBytes;
            
            offset += chunkBytes;
        }
        
        // 3. Shift the very last byte, set TMS=1 to exit Shift-DR, and Flush
        const last = tdi[tdi.length - 1];
        cmd.set([
            0x1B, 6, last, 
            0x4A, 2, ((last >> 7) & 1 ? 0x80 : 0x00) | 0x03, 
            0x87
        ], ptr);
        
        // Fire the entire perfectly-segmented array to the OS USB stack
        await this._transferOut(cmd, "DR_BULK");
    }
    async flush() { 
        if (JTAG_DEBUG) console.log("[JTAG] Executing Active Flush");
        await this.device.transferOut(this.epOut, new Uint8Array([0x87])); // Active Flush
        try { 
            while (true) { 
                const r = await this.device.transferIn(this.epIn, 512); 
                if (r.data.byteLength <= 2) break; 
            } 
        } catch (e) {} 
    }

    async readIDCODE() {
        await this.shiftTMS(0x1F, 5); await this.shiftTMS(0x00, 1);
        await this.shiftIR(0x09, 6);
        await this.shiftTMS(0x01, 3);
        
        await this.flush();
        
        await this._transferOut(new Uint8Array([0x39, 3, 0, 0, 0, 0, 0, 0x87]), "READ_ID"); // Safe 0x39 Opcode
        const res = await this.readData(4);
        await this.shiftTMS(0x03, 3, 0);
        return (res[3]<<24|res[2]<<16|res[1]<<8|res[0]) >>> 0;
    }

    async readStatus() {
        await this.shiftIR(0x05, 6);
        const pkts = new Uint32Array([0xAA995566, 0x20000000, 0x2800E001, 0x20000000, 0x20000000]);
        const cmdBytes = new Uint8Array(pkts.length * 4);
        for(let i=0; i<pkts.length; i++) {
            cmdBytes[i*4+0]=(pkts[i]>>24)&0xFF; cmdBytes[i*4+1]=(pkts[i]>>16)&0xFF;
            cmdBytes[i*4+2]=(pkts[i]>>8)&0xFF;  cmdBytes[i*4+3]=pkts[i]&0xFF;
        }
        const rev = new Uint8Array(cmdBytes.length);
        for(let i=0; i<cmdBytes.length; i++) rev[i] = REV_LUT[cmdBytes[i]];
        await this.shiftDRBulk(rev);
        await this.shiftIR(0x04, 6);
        await this.shiftTMS(0x01, 3);
        
        await this.flush();
        
        await this._transferOut(new Uint8Array([0x39, 3, 0, 0, 0, 0, 0, 0x87]), "READ_STAT");
        const res = await this.readData(4);
        await this.shiftTMS(0x03, 3, 0);

        // FIXED: Decode Xilinx CFG_OUT (MSB-first + Bit-reversed)
        return (REV_LUT[res[0]] << 24 | REV_LUT[res[1]] << 16 | REV_LUT[res[2]] << 8 | REV_LUT[res[3]]) >>> 0;
    }
async programXC7(bitstream) {
        console.log("[USB] Starting Airtight UG470 Config...");
        const rev = new Uint8Array(bitstream.length);
        for (let i = 0; i < bitstream.length; i++) rev[i] = REV_LUT[bitstream[i]];
        
        await this.shiftTMS(0x1F, 5); await this.shiftTMS(0x00, 1);

        console.log("[USB] JPROGRAM & BYPASS Initiation...");
        await this.shiftIR(0x0B, 6); // JPROGRAM
        await this.shiftIR(0x3F, 6); // Load BYPASS 
        
        // FIXED: DO NOT use readStatus() to poll. 
        // It injects a sync word and ruins the configuration engine's clean state.
        // The FPGA memory clearing takes ~10ms. Wait 100ms to be perfectly safe.
        console.log("[USB] Waiting 100ms for FPGA housekeeping (INIT_B)...");
        await new Promise(r => setTimeout(r, 100));

        console.log("[USB] Sending payload...");
        await this.shiftIR(0x05, 6); // CFG_IN
        const t0 = performance.now();
        await this.shiftDRBulk(rev);
        console.log(`[USB] Streamed in ${(performance.now()-t0).toFixed(1)}ms`);
        
        await this.shiftIR(0x0C, 6); // JSTART

        console.log("[USB] Generating 2048 startup clocks in Run-Test/Idle...");
        const clkCmd = new Uint8Array(3 + 256);
        clkCmd[0] = 0x19; // Clock Data Bytes Out (LSB First)
        clkCmd[1] = 255;  // Length Low (256 bytes - 1 = 255)
        clkCmd[2] = 0;    // Length High
        await this._transferOut(clkCmd, "CLOCKS");

        const finalStat = await this.readStatus();
        console.log(`[USB] Final STAT: 0x${finalStat.toString(16).padStart(8, '0').toUpperCase()}`);
        if ((finalStat >> 14) & 1) {
            console.log("%c[USB] FLASH SUCCESS: DONE LED SHOULD BE ON", "color: #4af626; font-weight: bold;");
        } else {
            console.error("[USB] FLASH FAILED: DONE BIT LOW. Check bitstream integrity.");
        }
    }

    async readData(len) {
        const res = new Uint8Array(len);
        let off = 0;
        while (off < len) {
            const r = await this.device.transferIn(this.epIn, 512);
            const d = new Uint8Array(r.data.buffer);
            for (let i = 0; i < d.length; i += 512) {
                const chunk = Math.min(d.length - i, 512);
                if (chunk > 2) { // Strip 2-byte FTDI Modem Status Header
                    const p = Math.min(chunk - 2, len - off);
                    res.set(d.subarray(i + 2, i + 2 + p), off);
                    off += p;
                }
            }
        }
        this._logTransfer("IN ", res, "DATA");
        return res;
    }

    async controlTransfer(request, value) {
        return this.device.controlTransferOut({ requestType: 'vendor', recipient: 'device', request, value, index: 1 });
    }
}
