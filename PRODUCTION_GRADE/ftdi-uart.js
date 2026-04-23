/**
 * @file ftdi-uart.js
 * @description Robust WebSerial driver for the FT2232H UART interface.
 * Built for the ZeroLabs Web IDE architecture.
 */

export class WebSerialUART {
    constructor() {
        this.port = null;
        this.reader = null;
        this.writer = null;
        this.keepReading = false;
        this.readPromise = null;

        // Internal buffer for line-by-line parsing
        this._lineBuffer = '';

        // Event Hooks (Override these in your index.js)
        this.onConnect = () => {};
        this.onDisconnect = () => {};
        this.onData = (chunk) => {};     // Raw string chunks
        this.onLine = (line) => {};      // Complete lines (separated by \n)
        this.onError = (err) => {};
    }

    /**
     * Requests the FTDI port and opens the data streams.
     * @param {number} baudRate - Default 115200 for SERV/RISC-V
     */
    async connect(baudRate = 115200) {
        try {
            this.port = await navigator.serial.requestPort({
                filters: [{ usbVendorId: 0x0403, usbProductId: 0x6010 }]
            });

            await this.port.open({ baudRate });
            
            // Monitor physical disconnects
            this.port.addEventListener('disconnect', this._handleDisconnect.bind(this));

            // Set up Text Encoders/Decoders so we deal in Strings, not Uint8Arrays
            const textDecoder = new TextDecoderStream();
            this.readableStreamClosed = this.port.readable.pipeTo(textDecoder.writable);
            this.reader = textDecoder.readable.getReader();

            const textEncoder = new TextEncoderStream();
            this.writableStreamClosed = textEncoder.readable.pipeTo(this.port.writable);
            this.writer = textEncoder.writable.getWriter();

            this.keepReading = true;
            this.onConnect();

            // Fire and forget the read loop
            this.readPromise = this._readLoop();
            
        } catch (err) {
            this.onError(`Serial Connection Failed: ${err.message}`);
            throw err;
        }
    }

    /**
     * Gracefully tears down the streams and releases the USB interface.
     */
    async disconnect() {
        this.keepReading = false;
        
        if (this.reader) {
            await this.reader.cancel();
            await this.readPromise;
            this.reader.releaseLock();
        }
        if (this.writer) {
            await this.writer.close();
            this.writer.releaseLock();
        }
        if (this.port) {
            await this.port.close();
            this.port = null;
        }
        
        this.onDisconnect();
    }

    /**
     * Writes a string to the FPGA via UART.
     * @param {string} data 
     */
    async write(data) {
        if (!this.writer) {
            this.onError("Cannot write: Serial port not open.");
            return;
        }
        try {
            await this.writer.write(data);
        } catch (err) {
            this.onError(`Write Error: ${err.message}`);
        }
    }

    /**
     * Internal loop to process incoming USB bulk packets.
     */
    async _readLoop() {
        try {
            while (this.keepReading) {
                const { value, done } = await this.reader.read();
                if (done) break;
                if (value) {
                    // Fire raw data event
                    this.onData(value);

                    // Process line-buffer for terminal convenience
                    this._lineBuffer += value;
                    const lines = this._lineBuffer.split('\n');
                    
                    // If the last element isn't empty, it means the line is incomplete.
                    // Keep it in the buffer. Otherwise, the buffer is empty.
                    this._lineBuffer = lines.pop();

                    for (const line of lines) {
                        this.onLine(line.replace('\r', ''));
                    }
                }
            }
        } catch (err) {
            this.onError(`Read Loop Error: ${err.message}`);
        }
    }

    _handleDisconnect() {
        this.keepReading = false;
        this.port = null;
        this.onDisconnect();
    }
}
