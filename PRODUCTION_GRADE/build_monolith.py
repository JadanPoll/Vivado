#!/usr/bin/env python3
import base64
import re
import os

print("Building ZeroLabs God Mode (Monolithic HTML)...")
print("This will take a few moments to encode the heavy silicon binaries.")

def get_b64(filepath):
    with open(filepath, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

def get_data_uri(filepath, mime="application/javascript"):
    return f"data:{mime};base64,{get_b64(filepath)}"

try:
    with open("index.html", "r", encoding="utf-8") as f:
        html = f.read()
except Exception as e:
    print("Error reading index.html. Ensure you are in the PRODUCTION_GRADE folder.")
    exit(1)

# 1. Inline the standard JS tags
print("Inlining FTDI JTAG library...")
jtag_code = open("ftdi-jtag.js", "r", encoding="utf-8").read()
html = html.replace('<script src="ftdi-jtag.js"></script>', f"<script>\n{jtag_code}\n</script>")

# 2. Patch the ES6 imports to pull from Data URIs
print("Encoding UART and BLE Modules...")
html = html.replace("'./ftdi-uart.js'", f"'{get_data_uri('ftdi-uart.js')}'")
html = html.replace("'./urbana-ble.js'", f"'{get_data_uri('urbana-ble.js')}'")

# 3. Create the Virtual File System (VFS) for the heavy binaries
print("Encoding Silicon Databases and WASM Engines...")
assets = [
    ('nextpnr-xilinx.opt.wasm.br', 'application/octet-stream'),
    ('xc7frames2bit.opt.wasm.br', 'application/octet-stream'),
    ('xc7s50.bin.br', 'application/octet-stream'),
    ('xc7s50_fasm_map_v7.json.br', 'application/octet-stream'),
    ('part.yaml', 'text/plain')
]

vfs_script = "const VFS = {};\n"
for filename, mime in assets:
    print(f"  -> Packing {filename}...")
    vfs_script += f"VFS['{filename}'] = '{get_data_uri(filename, mime)}';\n"

# 4. Process Web Workers (and inline their internal importScripts dependencies!)
print("Encoding Web Workers and resolving internal dependencies...")
def process_worker(filename):
    worker_code = open(filename, "r", encoding="utf-8").read()
    
    # Catch things like importScripts('nextpnr-xilinx.js')
    import_calls = re.findall(r"importScripts\((.*?)\)", worker_code)
    for call in import_calls:
        files = re.findall(r"['\"](.*?)['\"]", call)
        for imp in files:
            if not imp.startswith("http") and not imp.startswith("data"):
                print(f"    -> Resolving internal worker import: {imp} inside {filename}")
                imp_uri = get_data_uri(imp)
                worker_code = worker_code.replace(f"'{imp}'", f"'{imp_uri}'").replace(f'"{imp}"', f"'{imp_uri}'")
    
    b64 = base64.b64encode(worker_code.encode("utf-8")).decode("utf-8")
    return f"data:application/javascript;base64,{b64}"

vfs_script += f"VFS['pnr-worker.js'] = '{process_worker('pnr-worker.js')}';\n"
vfs_script += f"VFS['fasm2frames2.js'] = '{process_worker('fasm2frames2.js')}';\n"
vfs_script += f"VFS['frames-worker.js'] = '{process_worker('frames-worker.js')}';\n"

# 5. Inject the VFS and the fetch() interceptor
fetch_override = """
// --- GOD MODE: VIRTUAL FILE SYSTEM OVERRIDE ---
const originalFetch = window.fetch;
window.fetch = async function(resource, init) {
    let urlStr = resource instanceof Request ? resource.url : resource.toString();
    let filename = urlStr.split('/').pop();
    if (VFS[filename]) {
        return originalFetch(VFS[filename]); // Chrome natively decodes Data URIs!
    }
    return originalFetch(resource, init);
};
// ----------------------------------------------
"""

# Fix the regex in your HTML so it doesn't accidentally alter our new Data URIs
html = html.replace("(?!http)", "(?!http|data)")

# Inject our payload right at the start of your main module
html = html.replace('<script type="module">', f'<script type="module">\n{vfs_script}\n{fetch_override}\n')

# 6. Save the Monolith
out_file = "ZeroLabs_God_Mode.html"
with open(out_file, "w", encoding="utf-8") as f:
    f.write(html)

print(f"\\n✅ SUCCESS! Monolith generated: {out_file}")
print(f"File Size: {os.path.getsize(out_file) / (1024*1024):.2f} MB")