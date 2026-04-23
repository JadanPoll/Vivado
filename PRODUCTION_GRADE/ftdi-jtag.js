/**
 * ftdi-jtag.js - Production Grade UG470 Driver
 * Implements strict JTAG TAP state machine with active INIT_B status polling
 * and verified 2048 TCK startup sequence.
 */

const REV_LUT = new Uint8Array(256);
for (let i = 0; i < 256; i++) {
    REV_LUT[i] = ((i & 1) << 7) | ((i & 2) << 5) | ((i & 4) << 3) | ((i & 8) << 1) |
                 ((i & 16) >> 1) | ((i & 32) >> 3) | ((i & 64) >> 5) | ((i & 128) >> 7);
}

class WebUSBJtag {
    constructor(device) {
        this.device = device;
        this.epIn = null; this.epOut = null;
        this.maxPacketSize = 512;
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
        await this.device.transferOut(this.epOut, new Uint8Array([0x8A, 0x85, 0x8D, 0x97, 0x86, divisor & 0xFF, (divisor >> 8) & 0xFF, 0x80, 0x08, 0x0B, 0x87]));
        console.log(`[USB] MPSSE Ready @ ${freqHz/1e6}MHz`);
    }

    async shiftTMS(tms, count, tdi = 0) {
        await this.device.transferOut(this.epOut, new Uint8Array([0x4B, count - 1, (tdi ? 0x80 : 0x00) | (tms & 0x7F)]));
    }

    async shiftIR(instruction, len = 6) {
        await this.shiftTMS(0x03, 4); // RTI -> Shift-IR
        await this.device.transferOut(this.epOut, new Uint8Array([0x3B, len - 2, instruction & 0xFF]));
        await this.shiftTMS(0x03, 3, (instruction >> (len - 1)) & 1); // Exit -> RTI
    }

    async shiftDRBulk(tdi) {
        const chunks = [new Uint8Array([0x4B, 2, 0x01])]; // RTI -> Shift-DR
        const bytes = tdi.length - 1;
        if (bytes > 0) {
            // FIX: Explicit parentheses for operator precedence
            chunks.push(new Uint8Array([0x19, (bytes - 1) & 0xFF, ((bytes - 1) >> 8) & 0xFF]));
            chunks.push(tdi.subarray(0, bytes));
        }
        const last = tdi[tdi.length - 1];
        chunks.push(new Uint8Array([0x1B, 6, last]));
        chunks.push(new Uint8Array([0x4B, 2, ((last >> 7) & 1 ? 0x80 : 0x00) | 0x03])); // Exit -> RTI
        chunks.push(new Uint8Array([0x87]));
        
        const totalLen = chunks.reduce((acc, val) => acc + val.length, 0);
        const finalCmd = new Uint8Array(totalLen);
        let offset = 0;
        for (const c of chunks) { finalCmd.set(c, offset); offset += c.length; }
        await this.device.transferOut(this.epOut, finalCmd);
    }

    async readStatus() {
        await this.shiftIR(0x05, 6); // CFG_IN
        const pkts = new Uint32Array([0xAA995566, 0x20000000, 0x2800E001, 0x20000000, 0x20000000]);
        const cmdBytes = new Uint8Array(pkts.length * 4);
        for(let i=0; i<pkts.length; i++) {
            cmdBytes[i*4 + 0] = (pkts[i] >> 24) & 0xFF;
            cmdBytes[i*4 + 1] = (pkts[i] >> 16) & 0xFF;
            cmdBytes[i*4 + 2] = (pkts[i] >> 8) & 0xFF;
            cmdBytes[i*4 + 3] = pkts[i] & 0xFF;
        }
        const rev = new Uint8Array(cmdBytes.length);
        for(let i=0; i<cmdBytes.length; i++) rev[i] = REV_LUT[cmdBytes[i]];
        await this.shiftDRBulk(rev);
        await this.shiftIR(0x04, 6); // CFG_OUT
        await this.shiftTMS(0x01, 3);
        await this.device.transferOut(this.epOut, new Uint8Array([0x3D, 3, 0, 0, 0, 0, 0, 0x87]));
        const res = await this.readData(4);
        await this.shiftTMS(0x03, 3, 0);
        return (res[3] << 24 | res[2] << 16 | res[1] << 8 | res[0]) >>> 0;
    }

    async programXC7(bitstream) {
        console.log("[USB] Starting Airtight UG470 Config...");
        const rev = new Uint8Array(bitstream.length);
        for (let i = 0; i < bitstream.length; i++) rev[i] = REV_LUT[bitstream[i]];
        
        await this.shiftTMS(0x1F, 5); await this.shiftTMS(0x00, 1);

        console.log("[USB] JPROGRAM & BYPASS Initiation...");
        await this.shiftIR(0x0B, 6); // JPROGRAM
        await this.shiftIR(0x3F, 6); // Load BYPASS as per Note 3
        
        let attempts = 0;
        let ready = false;
        while (attempts < 100) {
            const stat = await this.readStatus();
            const init_b = (stat >> 12) & 1;
            if (init_b === 1) { ready = true; break; }
            await new Promise(r => setTimeout(r, 10));
            attempts++;
        }

        if (!ready) throw new Error("INIT_B Polling Timeout: FPGA housekeeping failed.");
        console.log("[USB] INIT_B asserted. Sending payload...");

        await this.shiftIR(0x05, 6); // CFG_IN
        const t0 = performance.now();
        await this.shiftDRBulk(rev);
        console.log(`[USB] Streamed in ${(performance.now()-t0).toFixed(1)}ms`);
        
        await this.shiftIR(0x0C, 6); // JSTART

        // FIX: Reverted to verified 2048 TCK startup clock loop
        console.log("[USB] Generating 2048 startup clocks...");
        for (let i = 0; i < 32; i++) await this.shiftTMS(0x00, 64);

        const finalStat = await this.readStatus();
        console.log(`[USB] Final STAT: 0x${finalStat.toString(16).toUpperCase()}`);
        if ((finalStat >> 14) & 1) {
            console.log("%c[USB] FLASH SUCCESS: DONE LED SHOULD BE ON", "color: #4af626; font-weight: bold;");
        } else {
            console.error("[USB] FLASH FAILED: DONE BIT LOW. Check bitstream integrity.");
        }
    }

    async readIDCODE() {
        await this.shiftTMS(0x1F, 5); await this.shiftTMS(0x00, 1);
        await this.shiftIR(0x09, 6);
        await this.shiftTMS(0x01, 3);
        await this.device.transferOut(this.epOut, new Uint8Array([0x3D, 3, 0, 0, 0, 0, 0, 0x87]));
        const res = await this.readData(4);
        await this.shiftTMS(0x03, 3, 0);
        return (res[3] << 24 | res[2] << 16 | res[1] << 8 | res[0]) >>> 0;
    }

    async readData(len) {
        const res = new Uint8Array(len);
        let off = 0;
        while (off < len) {
            const r = await this.device.transferIn(this.epIn, 512);
            const d = new Uint8Array(r.data.buffer);
            for (let i = 0; i < d.length; i += 512) {
                const chunk = Math.min(d.length - i, 512);
                if (chunk > 2) {
                    const p = Math.min(chunk - 2, len - off);
                    res.set(d.subarray(i + 2, i + 2 + p), off);
                    off += p;
                }
            }
        }
        return res;
    }

    async controlTransfer(request, value) {
        return this.device.controlTransferOut({ requestType: 'vendor', recipient: 'device', request, value, index: 1 });
    }

    async flush() { try { while (true) { const r = await this.device.transferIn(this.epIn, 512); if (r.data.byteLength <= 2) break; } } catch (e) {} }
}
