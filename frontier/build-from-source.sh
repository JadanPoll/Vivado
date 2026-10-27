#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
output="${2:-$repo_root/Frontier_Grade}"
jobs="${FRONTIER_JOBS:-$(nproc)}"
lock="$repo_root/frontier/source-lock.json"

if [[ "$(uname -s)" != Linux ]]; then
  echo "build-from-source.sh requires Linux (use the frontier-grade-source workflow)." >&2
  exit 2
fi
if [[ -e "$output" ]]; then
  echo "Refusing to replace existing output: $output" >&2
  exit 2
fi
for tool in git cmake python3 node curl tar; do command -v "$tool" >/dev/null; done

work="${FRONTIER_BUILD_ROOT:-$(mktemp -d)}"
if [[ -z "${FRONTIER_KEEP_WORK:-}" ]]; then trap 'rm -rf -- "$work"' EXIT; fi
mkdir -p "$work"

lock_value() {
  node -e "const x=require(process.argv[1]);let v=x;for(const k of process.argv[2].split('.'))v=v[k];process.stdout.write(String(v))" "$lock" "$1"
}
checkout() {
  local url="$1" commit="$2" destination="$3"
  git clone --filter=blob:none --no-checkout "$url" "$destination"
  git -C "$destination" checkout --detach "$commit"
}

nextpnr_commit="$(lock_value nextpnrXilinx.commit)"
db_commit="$(lock_value nextpnrXilinx.submodules.xilinx/external/prjxray-db)"
prjxray_commit="$(lock_value prjxray.commit)"
emsdk_commit="$(lock_value hostTools.emsdk.tagCommit)"
emsdk_version="$(lock_value hostTools.emsdk.version)"

nextpnr="$work/nextpnr-xilinx"
git clone --filter=blob:none --no-checkout "$(lock_value nextpnrXilinx.repository)" "$nextpnr"
git -C "$nextpnr" sparse-checkout init --no-cone
git -C "$nextpnr" sparse-checkout set --no-cone '/*' \
  '!/build-wasm/' '!/build-native/' '!/Nathan_Serv/' \
  '!/xilinx/xc7s50.bin' '!/xc7s50.bin.br' '!/xc7s50_fasm_map.json.br'
git -C "$nextpnr" checkout --detach "$nextpnr_commit"

db="$nextpnr/xilinx/external/prjxray-db"
meta="$nextpnr/xilinx/external/nextpnr-xilinx-meta"
rm -rf -- "$db" "$meta"
git clone --filter=blob:none --no-checkout https://github.com/f4pga/prjxray-db.git "$db"
git -C "$db" sparse-checkout init --cone
git -C "$db" sparse-checkout set spartan7
git -C "$db" checkout --detach "$db_commit"
# The historical 770ee6b gitlink was never published. 491aefc plus the
# superproject's XADC metadata is the reconstructible content closure.
checkout "$(lock_value nextpnrXilinx.metadataReconstruction.baseRepository)" \
  "$(lock_value nextpnrXilinx.metadataReconstruction.baseCommit)" "$meta"
cp -a "$meta/artix7" "$meta/spartan7"
cp "$nextpnr/xilinx/site_type_XADC_meta.json" "$meta/spartan7/site_type_XADC.json"
# Keep the mixed-tile overlay out of the Project X-Ray database. The map
# generator consumes it explicitly below; installing it as MONITOR_BOT data
# also misclassifies its LIOI3_TBYTESRC records before the overlay pass.

native="$work/nextpnr-native"
cmake -S "$nextpnr" -B "$native" -DARCH=xilinx -DWITH_PYTHON=OFF \
  -DBUILD_PYTHON=OFF -DBUILD_TESTS=OFF -DBUILD_GUI=OFF \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$native" --target bbasm --parallel "$jobs"
python3 "$nextpnr/xilinx/python/bbaexport.py" \
  --device xc7s50csga324-1 --xray "$db/spartan7" \
  --metadata "$meta/artix7" --bba "$work/xc7s50.bba"
"$native/bba/bbasm" -l "$work/xc7s50.bba" "$work/xc7s50.bin"

emsdk="$work/emsdk"
checkout https://github.com/emscripten-core/emsdk.git "$emsdk_commit" "$emsdk"
"$emsdk/emsdk" install "$emsdk_version"
"$emsdk/emsdk" activate "$emsdk_version"
set +u
source "$emsdk/emsdk_env.sh"
set -u
wasm_opt="$emsdk/upstream/bin/wasm-opt"
test -x "$wasm_opt"

boost="$work/boost_1_83_0"
curl -fsSL https://archives.boost.io/release/1.83.0/source/boost_1_83_0.tar.gz \
  -o "$work/boost.tar.gz"
tar -xzf "$work/boost.tar.gz" -C "$work"
(
  cd "$boost"
  ./bootstrap.sh --with-libraries=filesystem,program_options,iostreams,system
  sed -i 's/type.set-generated-target-suffix OBJ : <toolset>emscripten : "bc" ;/type.set-generated-target-suffix OBJ : <toolset>emscripten : "o" ;/' tools/build/src/tools/emscripten.jam
  sed -i 's/type.set-generated-target-suffix STATIC_LIB : <toolset>emscripten : "bc" ;/type.set-generated-target-suffix STATIC_LIB : <toolset>emscripten : "a" ;/' tools/build/src/tools/emscripten.jam
  sed -i 's|    "$(CONFIG_COMMAND)" $(AROPTIONS) -r -o "$(<)" "$(>)"|    "emar" rc "$(<)" "$(>)"|' tools/build/src/tools/emscripten.jam
  grep -q 'OBJ : <toolset>emscripten : "o"' tools/build/src/tools/emscripten.jam
  grep -q 'STATIC_LIB : <toolset>emscripten : "a"' tools/build/src/tools/emscripten.jam
  grep -q '"emar" rc' tools/build/src/tools/emscripten.jam
  printf '%s\n' 'using emscripten : : em++ : <cxxflags>"-Os" <archiver>emar <ranlib>emranlib <object-suffix>.o ;' > "$work/user-config.jam"
  ./b2 --user-config="$work/user-config.jam" toolset=emscripten variant=release \
    link=static threading=single target-os=linux \
    --prefix="$work/boost-wasm" --with-filesystem --with-program_options \
    --with-iostreams --with-system -j"$jobs" install
)

wasm_build="$work/nextpnr-wasm"
mkdir -p "$wasm_build/cmake-fakes"
cat > "$wasm_build/cmake-fakes/FindBoost.cmake" <<EOF
set(BOOST_LIB "$work/boost-wasm/lib")
set(Boost_FOUND TRUE)
set(Boost_INCLUDE_DIRS "$work/boost-wasm/include")
set(Boost_LIBRARY_DIRS "\${BOOST_LIB}")
foreach(lib filesystem program_options iostreams system)
  string(TOUPPER "\${lib}" LIB)
  set(Boost_\${LIB}_LIBRARY "\${BOOST_LIB}/libboost_\${lib}.a")
  set(Boost_\${LIB}_LIBRARY_RELEASE "\${BOOST_LIB}/libboost_\${lib}.a")
  list(APPEND Boost_LIBRARIES "\${BOOST_LIB}/libboost_\${lib}.a")
endforeach()
set(Boost_VERSION "1.83.0")
set(Boost_VERSION_STRING "1.83.0")
EOF
cat > "$wasm_build/cmake-fakes/FindPython3.cmake" <<EOF
set(Python3_FOUND TRUE)
set(Python3_Interpreter_FOUND TRUE)
set(Python3_EXECUTABLE "$(command -v python3)")
set(Python3_INCLUDE_DIRS "")
set(Python3_LIBRARIES "")
set(Python3_VERSION "3")
EOF

emcmake cmake -S "$nextpnr" -B "$wasm_build" -DARCH=xilinx \
  -DWITH_PYTHON=OFF -DBUILD_PYTHON=OFF -DBUILD_TESTS=OFF -DBUILD_GUI=OFF \
  -DBBA_IMPORT="$native/bba-export.cmake" \
  -DCMAKE_MODULE_PATH="$wasm_build/cmake-fakes" -DBoost_NO_BOOST_CMAKE=ON \
  -DEigen3_DIR=/usr/share/eigen3/cmake \
  -DCMAKE_CXX_FLAGS='-Os -g0 -msimd128 -mbulk-memory -mnontrapping-fptoint -DNPNR_DISABLE_THREADS' \
  -DCMAKE_EXE_LINKER_FLAGS='-Os -msimd128 -mbulk-memory -mnontrapping-fptoint -s ALLOW_MEMORY_GROWTH=1 -s MAXIMUM_MEMORY=4gb -s INITIAL_MEMORY=268435456 -s MALLOC=emmalloc -s ASSERTIONS=0 -s ENVIRONMENT=worker -s EXPORTED_FUNCTIONS=[_main] -s EXIT_RUNTIME=0 -s DISABLE_EXCEPTION_CATCHING=1 -Wl,-allow-multiple-definition' \
  -DCMAKE_CXX_FLAGS_RELEASE='' -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$wasm_build" --target nextpnr-xilinx --parallel "$jobs"
"$wasm_opt" -Oz --enable-simd --enable-bulk-memory --enable-nontrapping-float-to-int \
  --enable-sign-ext --enable-mutable-globals --strip-debug --strip-producers \
  "$wasm_build/nextpnr-xilinx.wasm" -o "$work/nextpnr-xilinx.opt.wasm"

prjxray="$work/prjxray"
git clone --filter=blob:none --no-checkout "$(lock_value prjxray.repository)" "$prjxray"
git -C "$prjxray" sparse-checkout init --no-cone
git -C "$prjxray" sparse-checkout set --no-cone '/*' \
  '!/.github/' '!/database/' '!/docs/' '!/experiments/' '!/fuzzers/' \
  '!/gridinfo/' '!/htmlgen/' '!/minitests/' '!/settings/' '!/tests/' '!/vagrant/'
git -C "$prjxray" checkout --detach "$prjxray_commit"
git -C "$prjxray" submodule update --init --depth 1 \
  third_party/abseil-cpp third_party/cctz third_party/gflags \
  third_party/googletest third_party/sanitizers-cmake third_party/yaml-cpp
frames_build="$work/prjxray-wasm"
emcmake cmake -S "$prjxray" -B "$frames_build" -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF -DPRJXRAY_BUILD_TESTING=OFF \
  -DCMAKE_CXX_FLAGS='-Os -fexceptions -mbulk-memory -mnontrapping-fptoint -Wno-error -Wno-deprecated-pragma -Wno-deprecated-builtins' \
  -DCMAKE_EXE_LINKER_FLAGS="-Os -fexceptions -mbulk-memory -mnontrapping-fptoint -s ALLOW_MEMORY_GROWTH=1 -s INITIAL_MEMORY=67108864 -s MALLOC=emmalloc -s ENVIRONMENT=worker -s EXPORTED_FUNCTIONS=['_main'] -s EXIT_RUNTIME=0 -s ERROR_ON_UNDEFINED_SYMBOLS=0" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
cmake --build "$frames_build" --target xc7frames2bit --parallel "$jobs"
"$wasm_opt" -Oz --enable-bulk-memory --enable-nontrapping-float-to-int \
  --enable-sign-ext --enable-mutable-globals --strip-debug --strip-producers \
  "$frames_build/tools/xc7frames2bit.wasm" -o "$work/xc7frames2bit.opt.wasm"

python3 -m venv "$work/map-venv"
"$work/map-venv/bin/python" -m pip install --quiet intervaltree simplejson pyyaml
"$work/map-venv/bin/python" "$repo_root/frontier/generate-fasm-map-v7.py" \
  --prjxray-root "$prjxray" --db-root "$db/spartan7" \
  --overlay-segbits "$nextpnr/xilinx/segbits_monitor_bot.db" \
  --output "$work/xc7s50_fasm_map_v7.json"

stage="$work/source-assets"
mkdir -p "$stage"
for file in index.html pnr-worker.js synth-worker.js frames-worker.js \
  fasm2frames2.js ftdi-jtag.js ftdi-uart.js urbana-ble.js; do
  cp "$repo_root/PRODUCTION_GRADE/$file" "$stage/$file"
done
cp -a "$repo_root/PRODUCTION_GRADE/DEFAULTS" "$repo_root/PRODUCTION_GRADE/TESTS" "$stage/"
cp "$wasm_build/nextpnr-xilinx.js" "$stage/nextpnr-xilinx.js"
cp "$frames_build/tools/xc7frames2bit.js" "$stage/xc7frames2bit.js"
cp "$db/spartan7/xc7s50csga324-1/part.yaml" "$stage/part.yaml"
cp "$work/nextpnr-xilinx.opt.wasm" "$stage/"
cp "$work/xc7frames2bit.opt.wasm" "$stage/"
cp "$work/xc7s50.bin" "$stage/"
cp "$work/xc7s50_fasm_map_v7.json" "$stage/"

node "$repo_root/frontier/package-frontier.mjs" "$stage" "$output"
echo "FRONTIER_SOURCE_BUILD=PASS"
