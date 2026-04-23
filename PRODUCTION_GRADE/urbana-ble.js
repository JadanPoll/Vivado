/**
 * @file urbana-ble.js
 * @description WebBluetooth GATT driver for the Urbana Board's RN4871 BLE Module.
 * Built for the ZeroLabs Web IDE architecture.
 */

export class UrbanaBLE {
    constructor() {
        this.device = null;
        this.server = null;
        this.rxCharacteristic = null; // Board's TX, Browser's RX
        this.txCharacteristic = null; // Board's RX, Browser's TX

        // Microchip RN4871 Transparent UART UUIDs
        this.SERVICE_UUID = '49535343-fe7d-4ae5-8fa9-9fafd205e455';
        this.RX_CHAR_UUID = '49535343-1e4d-4bd9-ba61-23c647249616'; 
        this.TX_CHAR_UUID = '49535343-8841-43f4-a8d4-ecbe34729bb3';

        // Internal buffer for line-by-line parsing
        this._lineBuffer = '';

        // Event Hooks (Override these in your index.js)
        this.onConnect = () => {};
        this.onDisconnect = () => {};
        this.onData = (chunk) => {};
        this.onLine = (line) => {};
        this.onError = (err) => {};
    }

    /**
     * Triggers the browser's BLE pairing UI and connects to the GATT server.
     */
    async connect() {
        try {
            this.device = await navigator.bluetooth.requestDevice({
                filters: [{ services: [this.SERVICE_UUID] }],
                // Fallback if the board broadcasts a different service initially:
                // acceptAllDevices: true,
                // optionalServices: [this.SERVICE_UUID]
            });

            this.device.addEventListener('gattserverdisconnected', this._handleDisconnect.bind(this));

            this.server = await this.device.gatt.connect();
            const service = await this.server.getPrimaryService(this.SERVICE_UUID);

            this.rxCharacteristic = await service.getCharacteristic(this.RX_CHAR_UUID);
            this.txCharacteristic = await service.getCharacteristic(this.TX_CHAR_UUID);

            // Subscribe to incoming FPGA data
            await this.rxCharacteristic.startNotifications();
            this.rxCharacteristic.addEventListener('characteristicvaluechanged', this._processIncoming.bind(this));

            this.onConnect();

        } catch (err) {
            this.onError(`BLE Connection Failed: ${err.message}`);
            throw err;
        }
    }

    /**
     * Drops the GATT connection.
     */
    disconnect() {
        if (this.device && this.device.gatt.connected) {
            this.device.gatt.disconnect();
        }
    }

    /**
     * Writes a string to the FPGA over BLE.
     * Safely chunks the payload to respect BLE MTU limits (usually 20 bytes).
     * @param {string} data 
     */
    async write(data) {
        if (!this.txCharacteristic) {
            this.onError("Cannot write: BLE characteristic not available.");
            return;
        }

        try {
            const encoder = new TextEncoder();
            const payload = encoder.encode(data);
            const chunkSize = 20; // Safe MTU default for BLE 4.2

            for (let i = 0; i < payload.length; i += chunkSize) {
                const chunk = payload.slice(i, i + chunkSize);
                await this.txCharacteristic.writeValueWithoutResponse(chunk);
                // Small delay to prevent overflowing the RN4871's buffer
                await new Promise(resolve => setTimeout(resolve, 10)); 
            }
        } catch (err) {
            this.onError(`BLE Write Error: ${err.message}`);
        }
    }

    /**
     * Internal handler for GATT notification events.
     * @param {Event} event 
     */
    _processIncoming(event) {
        const value = new TextDecoder().decode(event.target.value);
        
        // Fire raw data event
        this.onData(value);

        // Process line-buffer
        this._lineBuffer += value;
        const lines = this._lineBuffer.split('\n');
        
        this._lineBuffer = lines.pop();

        for (const line of lines) {
            this.onLine(line.replace('\r', ''));
        }
    }

    _handleDisconnect() {
        this.server = null;
        this.rxCharacteristic = null;
        this.txCharacteristic = null;
        this.onDisconnect();
    }
}
