/* ===== <script> #1 ===== */
/* ═══════════ tiện ích ═══════════ */
                                                                                          const $ = s => document.querySelector(s);
                                                                                          const hx = n => n.toString(16);
                                                                                          const esc = s => String(s).replace(/[&<>]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]));
                                                                                          const a4 = n => (n + 3) & ~3;
                                                                                          const CRC_TAB = (() => {
                                                                                          const t = new Uint32Array(256);
                                                                                          for (let n = 0; n < 256; n++){
                                                                                          let c = n;
                                                                                          for (let k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
                                                                                          t[n] = c >>> 0;
                                                                                          }
                                                                                          return t;
                                                                                          })();
                                                                                          const crc32 = b => {
                                                                                          let c = 0xFFFFFFFF;
                                                                                          for (let i = 0; i < b.length; i++) c = CRC_TAB[(c ^ b[i]) & 0xFF] ^ (c >>> 8);
                                                                                          return (c ^ 0xFFFFFFFF) >>> 0;
                                                                                          };
                                                                                          const enc = s => new TextEncoder().encode(s);
                                                                                          /* ═══════════ LZ4 ═══════════ */
                                                                                          function lz4dec(src, outSize){
                                                                                          const dst = new Uint8Array(outSize);
                                                                                          const n = src.length;
                                                                                          let i = 0, o = 0;
                                                                                          while (i < n){
                                                                                          const tok = src[i++];
                                                                                          let lit = tok >> 4;
                                                                                          if (lit === 15){
                                                                                          let b;
                                                                                          do { if (i >= n) throw new Error('LZ4: hết dữ liệu ở độ dài literal'); b = src[i++]; lit += b; }
                                                                                          while (b === 255);
                                                                                          }
                                                                                          if (lit){
                                                                                          if (i + lit > n) throw new Error('LZ4: literal vượt biên');
                                                                                          if (o + lit > outSize) throw new Error('LZ4: literal vượt kích thước đầu ra');
                                                                                          dst.set(src.subarray(i, i + lit), o);
                                                                                          i += lit; o += lit;
                                                                                          }
                                                                                          if (i >= n) break;
                                                                                          const off = src[i] | (src[i+1] << 8); i += 2;
                                                                                          if (off === 0 || off > o) throw new Error(`LZ4: offset không hợp lệ (${off})`);
                                                                                          let ml = tok & 15;
                                                                                          if (ml === 15){
                                                                                          let b;
                                                                                          do { if (i >= n) throw new Error('LZ4: hết dữ liệu ở độ dài match'); b = src[i++]; ml += b; }
                                                                                          while (b === 255);
                                                                                          }
                                                                                          ml += 4;
                                                                                          if (o + ml > outSize) throw new Error('LZ4: match vượt kích thước đầu ra');
                                                                                          let sp = o - off;
                                                                                          for (let k = 0; k < ml; k++) dst[o++] = dst[sp++];
                                                                                          }
                                                                                          if (o !== outSize) throw new Error(`LZ4: giải ra ${o} byte, cần ${outSize}`);
                                                                                          return dst;
                                                                                          }
                                                                                          function lz4enc(src){
                                                                                          const n = src.length;
                                                                                          if (!n) return new Uint8Array(0);
                                                                                          const out = [];
                                                                                          const HLOG = 16, HSIZE = 1 << HLOG;
                                                                                          const head = new Int32Array(HSIZE).fill(-1);
                                                                                          const prev = new Int32Array(n).fill(-1);
                                                                                          const MFLIMIT = 12, LASTLIT = 5, MAXDIST = 65535, CHAIN = 32;
                                                                                          const h4 = i => {
                                                                                          const v = (src[i] | (src[i+1]<<8) | (src[i+2]<<16) | (src[i+3]<<24)) >>> 0;
                                                                                          return (Math.imul(v, 2654435761) >>> (32 - HLOG));
                                                                                          };
                                                                                          const same4 = (a, b) =>
                                                                                          src[a]===src[b] && src[a+1]===src[b+1] && src[a+2]===src[b+2] && src[a+3]===src[b+3];
                                                                                          const emit = (ls, le, mlen, moff) => {
                                                                                          const litlen = le - ls;
                                                                                          const ml = mlen ? mlen - 4 : 0;
                                                                                          out.push(((litlen >= 15 ? 15 : litlen) << 4) | (ml >= 15 ? 15 : ml));
                                                                                          if (litlen >= 15){
                                                                                          let r = litlen - 15;
                                                                                          while (r >= 255){ out.push(255); r -= 255; }
                                                                                          out.push(r);
                                                                                          }
                                                                                          for (let k = ls; k < le; k++) out.push(src[k]);
                                                                                          if (mlen){
                                                                                          out.push(moff & 255, (moff >> 8) & 255);
                                                                                          if (ml >= 15){
                                                                                          let r = ml - 15;
                                                                                          while (r >= 255){ out.push(255); r -= 255; }
                                                                                          out.push(r);
                                                                                          }
                                                                                          }
                                                                                          };
                                                                                          let anchor = 0, i = 0;
                                                                                          while (i < n - MFLIMIT){
                                                                                          const hv = h4(i);
                                                                                          let bestLen = 0, bestOff = 0, cur = head[hv], cnt = 0;
                                                                                          while (cur >= 0 && cnt < CHAIN){
                                                                                          const off = i - cur;
                                                                                          if (off > MAXDIST) break;
                                                                                          if (same4(cur, i)){
                                                                                          let l = 4;
                                                                                          const lim = n - LASTLIT - i;
                                                                                          while (l < lim && src[cur+l] === src[i+l]) l++;
                                                                                          if (l > bestLen){ bestLen = l; bestOff = off; if (l >= 255) break; }
                                                                                          }
                                                                                          cur = prev[cur]; cnt++;
                                                                                          }
                                                                                          prev[i] = head[hv]; head[hv] = i;
                                                                                          if (bestLen >= 4){
                                                                                          emit(anchor, i, bestLen, bestOff);
                                                                                          const stop = Math.min(i + bestLen, n - 3);
                                                                                          for (let k = i + 1; k < stop; k++){ const hk = h4(k); prev[k] = head[hk]; head[hk] = k; }
                                                                                          i += bestLen; anchor = i;
                                                                                          } else i++;
                                                                                          }
                                                                                          const litlen = n - anchor;
                                                                                          out.push((litlen >= 15 ? 15 : litlen) << 4);
                                                                                          if (litlen >= 15){
                                                                                          let r = litlen - 15;
                                                                                          while (r >= 255){ out.push(255); r -= 255; }
                                                                                          out.push(r);
                                                                                          }
                                                                                          for (let k = anchor; k < n; k++) out.push(src[k]);
                                                                                          return new Uint8Array(out);
                                                                                          }
                                                                                          function lz4Trace(src, outSize){
                                                                                          const litOf  = new Int32Array(outSize).fill(-1);
                                                                                          const copyOf = new Int32Array(outSize).fill(-1);
                                                                                          let i = 0, o = 0;
                                                                                          while (i < src.length && o < outSize){
                                                                                          const tok = src[i++];
                                                                                          let lit = tok >> 4;
                                                                                          if (lit === 15){ let b; do { b = src[i++]; lit += b; } while (b === 255); }
                                                                                          for (let k = 0; k < lit; k++){ litOf[o++] = i++; }
                                                                                          if (i >= src.length) break;
                                                                                          const off = src[i] | (src[i+1] << 8); i += 2;
                                                                                          let ml = tok & 15;
                                                                                          if (ml === 15){ let b; do { b = src[i++]; ml += b; } while (b === 255); }
                                                                                          ml += 4;
                                                                                          let sp = o - off;
                                                                                          for (let k = 0; k < ml; k++){ copyOf[o] = sp; o++; sp++; }
                                                                                          }
                                                                                          const root = new Int32Array(outSize).fill(-1);
                                                                                          for (let k = 0; k < outSize; k++){
                                                                                          let cur = k, guard = 0;
                                                                                          while (litOf[cur] < 0 && copyOf[cur] >= 0 && guard++ < outSize) cur = copyOf[cur];
                                                                                          root[k] = litOf[cur] >= 0 ? litOf[cur] : -1;
                                                                                          }
                                                                                          return root;
                                                                                          }
                                                                                          /* ═══════════ UnityFS ═══════════ */
                                                                                          function parseBundle(u8){
                                                                                          const dv = new DataView(u8.buffer, u8.byteOffset, u8.byteLength);
                                                                                          let p = 0;
                                                                                          const cstr = () => { let s = ''; while (u8[p]) s += String.fromCharCode(u8[p++]); p++; return s; };
                                                                                          const sig = cstr();
                                                                                          if (sig !== 'UnityFS') throw new Error(`Không phải UnityFS bundle (signature "${sig}")`);
                                                                                          const fmt = dv.getUint32(p, false); p += 4;
                                                                                          const uv = cstr(), rev = cstr();
                                                                                          const declared = Number(dv.getBigInt64(p, false)); p += 8;
                                                                                          const ciSize = dv.getUint32(p, false); p += 4;
                                                                                          const uiSize = dv.getUint32(p, false); p += 4;
                                                                                          const flags  = dv.getUint32(p, false); p += 4;
                                                                                          const headerEnd = p;
                                                                                          const ic = flags & 0x3F;
                                                                                          let infoOff, info, dataStart;
                                                                                          if (flags & 0x80){
                                                                                          dataStart = (headerEnd + 15) & ~15;
                                                                                          infoOff = null;
                                                                                          const from = Math.min(declared, u8.length) - ciSize;
                                                                                          for (let off = from; off >= Math.max(0, from - 80000); off--){
                                                                                          try {
                                                                                          const cand = (ic === 2 || ic === 3)
                                                                                          ? lz4dec(u8.subarray(off, off + ciSize), uiSize)
                                                                                          : u8.subarray(off, off + ciSize).slice();
                                                                                          info = cand; infoOff = off; break;
                                                                                          } catch (e) { }
                                                                                          }
                                                                                          if (infoOff === null) throw new Error('Không tìm được blocksInfo ở cuối file.');
                                                                                          } else {
                                                                                          if (fmt >= 7 || (flags & 0x200)) p = (p + 15) & ~15;
                                                                                          infoOff = p;
                                                                                          const infoRaw = u8.subarray(p, p + ciSize);
                                                                                          if (ic === 2 || ic === 3) info = lz4dec(infoRaw, uiSize);
                                                                                          else if (ic === 0) info = infoRaw.slice();
                                                                                          else throw new Error(`blocksInfo nén kiểu ${ic} (chưa hỗ trợ)`);
                                                                                          dataStart = infoOff + ciSize;
                                                                                          if (flags & 0x200) dataStart = (dataStart + 15) & ~15;
                                                                                          }
                                                                                          const idv = new DataView(info.buffer, info.byteOffset, info.byteLength);
                                                                                          let q = 16;
                                                                                          const nB = idv.getUint32(q, false); q += 4;
                                                                                          const blocks = [];
                                                                                          for (let i = 0; i < nB; i++){
                                                                                          blocks.push({ u: idv.getUint32(q,false), c: idv.getUint32(q+4,false), f: idv.getUint16(q+8,false) });
                                                                                          q += 10;
                                                                                          }
                                                                                          const nN = idv.getUint32(q, false); q += 4;
                                                                                          const nodes = [];
                                                                                          for (let i = 0; i < nN; i++){
                                                                                          const off = Number(idv.getBigInt64(q,false)), sz = Number(idv.getBigInt64(q+8,false));
                                                                                          const nf = idv.getUint32(q+16,false); q += 20;
                                                                                          let nm = ''; while (info[q]) nm += String.fromCharCode(info[q++]); q++;
                                                                                          nodes.push({ off, size: sz, flags: nf, name: nm });
                                                                                          }
                                                                                          return { fmt, uv, rev, declared, ciSize, uiSize, flags, blocks, nodes,
                                                                                          dataStart, infoOff, info, headerEnd };
                                                                                          }
                                                                                          /* ═══════════ SerializedFile ═══════════ */
                                                                                          function parseSF(cab){
                                                                                          const dv = new DataView(cab.buffer, cab.byteOffset, cab.byteLength);
                                                                                          const version = dv.getUint32(8, false);
                                                                                          if (version !== 22) throw new Error(`SerializedFile v${version} (tool chỉ hỗ trợ v22)`);
                                                                                          const metaSize = dv.getUint32(20, false);
                                                                                          const fileSize = Number(dv.getBigInt64(24, false));
                                                                                          const dataOffset = Number(dv.getBigInt64(32, false));
                                                                                          let p = 48;
                                                                                          const cstr = () => { let s=''; while (cab[p]) s += String.fromCharCode(cab[p++]); p++; return s; };
                                                                                          const unityVer = cstr();
                                                                                          const target = dv.getInt32(p, true); p += 4;
                                                                                          const hasTT = cab[p]; p += 1;
                                                                                          const i32 = () => { const v = dv.getInt32(p, true); p += 4; return v; };
                                                                                          const u32 = () => { const v = dv.getUint32(p, true); p += 4; return v; };
                                                                                          const tcount = i32();
                                                                                          const types = [];
                                                                                          for (let i = 0; i < tcount; i++){
                                                                                          const cid = i32();
                                                                                          p += 1;
                                                                                          p += 2;
                                                                                          if (cid === 114) p += 16;
                                                                                          const th = cab.slice(p, p+16); p += 16;
                                                                                          let nodes = null, sb = null;
                                                                                          if (hasTT){
                                                                                          const nn = i32(), sbs = i32();
                                                                                          nodes = [];
                                                                                          for (let k = 0; k < nn; k++){
                                                                                          const ver = dv.getUint16(p, true);
                                                                                          const level = cab[p+2], tflags = cab[p+3];
                                                                                          const to = dv.getUint32(p+4, true), no = dv.getUint32(p+8, true);
                                                                                          const bsize = dv.getInt32(p+12, true), idx = dv.getInt32(p+16, true), meta = dv.getInt32(p+20, true);
                                                                                          p += 32;
                                                                                          nodes.push({ ver, level, tflags, to, no, bsize, idx, meta });
                                                                                          }
                                                                                          sb = cab.slice(p, p + sbs); p += sbs;
                                                                                          const nd = i32(); p += nd * 4;
                                                                                          }
                                                                                          types.push({ cid, th, nodes, sb });
                                                                                          }
                                                                                          const ocount = i32();
                                                                                          const objs = [];
                                                                                          for (let i = 0; i < ocount; i++){
                                                                                          p = a4(p);
                                                                                          const ent = p;
                                                                                          const pid = dv.getBigInt64(p, true);
                                                                                          const off = Number(dv.getBigInt64(p+8, true));
                                                                                          const size = dv.getUint32(p+16, true);
                                                                                          const tid = dv.getInt32(p+20, true);
                                                                                          p += 24;
                                                                                          objs.push({ pid, off, size, tid, cid: types[tid].cid, ent });
                                                                                          }
                                                                                          return { version, metaSize, fileSize, dataOffset, unityVer, target, hasTT, types, objs, cab };
                                                                                          }
                                                                                          /* ═══════════ typetree reader ═══════════ */
                                                                                          const COMMON = "AABB\0AnimationClip\0AnimationCurve\0AnimationState\0Array\0Base\0BitField\0bitset\0bool\0char\0ColorRGBA\0Component\0data\0deque\0double\0dynamic_array\0FastPropertyName\0first\0float\0Font\0GameObject\0Generic Mono\0GradientNEW\0GUID\0GUIStyle\0int\0list\0long long\0map\0Matrix4x4f\0MdFour\0MonoBehaviour\0MonoScript\0m_ByteSize\0m_Curve\0m_EditorClassIdentifier\0m_EditorHideFlags\0m_Enabled\0m_ExtensionPtr\0m_GameObject\0m_Index\0m_IsArray\0m_IsStatic\0m_MetaFlag\0m_Name\0m_ObjectHideFlags\0m_PrefabInternal\0m_PrefabParentObject\0m_Script\0m_StaticEditorFlags\0m_Type\0m_Version\0Object\0pair\0PPtr<Component>\0PPtr<GameObject>\0PPtr<Material>\0PPtr<MonoBehaviour>\0PPtr<MonoScript>\0PPtr<Object>\0PPtr<Prefab>\0PPtr<Sprite>\0PPtr<TextAsset>\0PPtr<Texture>\0PPtr<Texture2D>\0PPtr<Transform>\0Prefab\0Quaternionf\0Rectf\0RectInt\0RectOffset\0second\0set\0short\0size\0SInt16\0SInt32\0SInt64\0SInt8\0staticvector\0string\0TextAsset\0TextMesh\0Texture\0Texture2D\0Transform\0TypelessData\0UInt16\0UInt32\0UInt64\0UInt8\0unsigned int\0unsigned long long\0unsigned short\0vector\0Vector2f\0Vector3f\0Vector4f\0m_ScriptingClassIdentifier\0Gradient\0Type*\0int2_storage\0int3_storage\0BoundsInt\0m_CorrespondingSourceObject\0m_PrefabInstance\0m_PrefabAsset\0FileSize\0Hash128\0";
                                                                                          const COMMON_B = enc(COMMON);
                                                                                          function sname(sb, off){
                                                                                          const buf = (off & 0x80000000) ? COMMON_B : sb;
                                                                                          let o = off & 0x7fffffff, s = '';
                                                                                          while (buf[o]) s += String.fromCharCode(buf[o++]);
                                                                                          return s;
                                                                                          }
                                                                                          function buildNodes(t){
                                                                                          return t.nodes.map(n => ({
                                                                                          type: sname(t.sb, n.to), name: sname(t.sb, n.no),
                                                                                          level: n.level, meta: n.meta
                                                                                          }));
                                                                                          }
                                                                                          function makeReader(data){
                                                                                          const dv = new DataView(data.buffer, data.byteOffset, data.byteLength);
                                                                                          return { data, dv, p: 0, align(){ this.p = a4(this.p); } };
                                                                                          }
                                                                                          function readVal(nodes, i, r, trace){
                                                                                          const n = nodes[i];
                                                                                          const t = n.type;
                                                                                          const doAlign = (n.meta & 0x4000) !== 0;
                                                                                          const kids = [];
                                                                                          let j = i + 1;
                                                                                          while (j < nodes.length && nodes[j].level > n.level){
                                                                                          if (nodes[j].level === n.level + 1) kids.push(j);
                                                                                          j++;
                                                                                          }
                                                                                          let v;
                                                                                          switch (t){
                                                                                          case 'SInt8':  v = r.dv.getInt8(r.p);  r.p += 1; break;
                                                                                          case 'UInt8': case 'char': v = r.data[r.p]; r.p += 1; break;
                                                                                          case 'SInt16': case 'short': v = r.dv.getInt16(r.p,true); r.p += 2; break;
                                                                                          case 'UInt16': case 'unsigned short': v = r.dv.getUint16(r.p,true); r.p += 2; break;
                                                                                          case 'SInt32': case 'int': case 'Type*': v = r.dv.getInt32(r.p,true); r.p += 4; break;
                                                                                          case 'UInt32': case 'unsigned int': v = r.dv.getUint32(r.p,true); r.p += 4; break;
                                                                                          case 'SInt64': case 'long long': v = r.dv.getBigInt64(r.p,true); r.p += 8; break;
                                                                                          case 'UInt64': case 'unsigned long long': case 'FileSize':
                                                                                          v = r.dv.getBigUint64(r.p,true); r.p += 8; break;
                                                                                          case 'float':  v = r.dv.getFloat32(r.p,true); r.p += 4; break;
                                                                                          case 'double': v = r.dv.getFloat64(r.p,true); r.p += 8; break;
                                                                                          case 'bool':   v = r.data[r.p] !== 0; r.p += 1; break;
                                                                                          case 'string': {
                                                                                          const st = r.p;
                                                                                          const ln = r.dv.getInt32(r.p,true); r.p += 4;
                                                                                          v = new TextDecoder().decode(r.data.subarray(r.p, r.p+ln)); r.p += ln;
                                                                                          r.align();
                                                                                          if (trace) trace.push({ node: n.name, start: st, len: ln, val: v });
                                                                                          break;
                                                                                          }
                                                                                          case 'TypelessData': {
                                                                                          const ln = r.dv.getInt32(r.p,true); r.p += 4;
                                                                                          v = r.data.slice(r.p, r.p+ln); r.p += ln;
                                                                                          break;
                                                                                          }
                                                                                          default: {
                                                                                          if (kids.length && nodes[kids[0]].type === 'Array'){
                                                                                          const ai = kids[0];
                                                                                          const ak = [];
                                                                                          let k = ai + 1;
                                                                                          while (k < nodes.length && nodes[k].level > nodes[ai].level){
                                                                                          if (nodes[k].level === nodes[ai].level + 1) ak.push(k);
                                                                                          k++;
                                                                                          }
                                                                                          const size = r.dv.getInt32(r.p,true); r.p += 4;
                                                                                          v = [];
                                                                                          for (let m = 0; m < size; m++) v.push(readVal(nodes, ak[1], r, trace));
                                                                                          if (nodes[ai].meta & 0x4000) r.align();
                                                                                          } else {
                                                                                          v = {};
                                                                                          for (const c of kids) v[nodes[c].name] = readVal(nodes, c, r, trace);
                                                                                          }
                                                                                          }
                                                                                          }
                                                                                          if (doAlign) r.align();
                                                                                          return v;
                                                                                          }
                                                                                          function objBody(sf, o){ return sf.cab.subarray(sf.dataOffset + o.off, sf.dataOffset + o.off + o.size); }
                                                                                          function readObj(sf, o, trace){
                                                                                          const nodes = buildNodes(sf.types[o.tid]);
                                                                                          const r = makeReader(objBody(sf, o));
                                                                                          return readVal(nodes, 0, r, trace);
                                                                                          }
                                                                                          /* ═══════════ PRESET 3: shader định vị + đổi màu ═══════════ */
                                                                                          const XRAY_BLOB = {"backweapon":{"pid":"-3333330928057165289","size":8560,"z":"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"},"brmobilebumpspecdecal":{"pid":"893500320385684910","size":4656,"z":"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"},"brmobilebumpspec":{"pid":"3504935391519681939","size":8560,"z":"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"}};
                                                                                          async function loadXray(key){
                                                                                          const e = XRAY_BLOB[key];
                                                                                          if (!e) throw new Error(`Không có shader nhúng tên "${key}".`);
                                                                                          const raw = Uint8Array.from(atob(e.z), c => c.charCodeAt(0));
                                                                                          const ds = new DecompressionStream('deflate');
                                                                                          const buf = new Uint8Array(await new Response(
                                                                                          new Blob([raw]).stream().pipeThrough(ds)).arrayBuffer());
                                                                                          if (buf.length !== e.size)
                                                                                          throw new Error(`Shader nhúng "${key}" giải ra ${buf.length} byte, cần ${e.size}.`);
                                                                                          return { body: buf, pid: BigInt(e.pid) };
                                                                                          }
                                                                                          function readShaderProps(body){
                                                                                          const dv = new DataView(body.buffer, body.byteOffset, body.byteLength);
                                                                                          let p = 0;
                                                                                          const rd = () => { const v = dv.getInt32(p, true); p += 4; return v; };
                                                                                          const str = () => {
                                                                                          const n = rd();
                                                                                          if (n < 0 || p + n > body.length) throw new Error('chuỗi hỏng trong shader');
                                                                                          const s = new TextDecoder().decode(body.subarray(p, p + n));
                                                                                          p = a4(p + n);
                                                                                          return s;
                                                                                          };
                                                                                          str();
                                                                                          const cnt = rd();
                                                                                          if (cnt < 0 || cnt > 500) throw new Error(`số property bất thường: ${cnt}`);
                                                                                          const props = [];
                                                                                          for (let i = 0; i < cnt; i++){
                                                                                          const name = str(), desc = str();
                                                                                          const na = rd();
                                                                                          if (na < 0 || na > 100) throw new Error('m_Attributes hỏng');
                                                                                          for (let k = 0; k < na; k++) str();
                                                                                          const type = rd();
                                                                                          p += 4;
                                                                                          const valOff = p;
                                                                                          const val = [dv.getFloat32(p,true), dv.getFloat32(p+4,true),
                                                                                          dv.getFloat32(p+8,true), dv.getFloat32(p+12,true)];
                                                                                          p += 16;
                                                                                          str();
                                                                                          p += 4;
                                                                                          props.push({ name, desc, type, valOff, val });
                                                                                          }
                                                                                          return props;
                                                                                          }
                                                                                          const hex2rgb = h => {
                                                                                          const m = /^#?([0-9a-f]{6})$/i.exec(h.trim());
                                                                                          if (!m) return null;
                                                                                          const n = parseInt(m[1], 16);
                                                                                          return [((n>>16)&255)/255, ((n>>8)&255)/255, (n&255)/255];
                                                                                          };
                                                                                          const rgb2hex = v =>
                                                                                          '#' + v.slice(0,3).map(x => Math.round(Math.max(0,Math.min(1,x))*255)
                                                                                          .toString(16).padStart(2,'0')).join('').toUpperCase();
                                                                                          const COLOR_MAP = {
                                                                                          _XRayColor:    { kind:'color', src:'xray', label:'màu súng' },
                                                                                          _OutLineColor: { kind:'color', src:'line', label:'màu viền súng' },
                                                                                          _DimColor:     { kind:'color', src:'dim',  label:'màu keo' },
                                                                                          _OutLineWidth: { kind:'float', src:'width',label:'độ dày viền' }
                                                                                          };
                                                                                          const XRAY_SHADERS = ['backweapon', 'brmobilebumpspec', 'brmobilebumpspecdecal'];
                                                                                          const isXrayShader = path => {
                                                                                          const f = path.split('/').pop().replace(/\.shader$/, '');
                                                                                          return XRAY_SHADERS.includes(f);
                                                                                          };
                                                                                          function paintShader(body, opt, short, rows){
                                                                                          const props = readShaderProps(body);
                                                                                          const dv = new DataView(body.buffer, body.byteOffset, body.byteLength);
                                                                                          let n = 0;
                                                                                          for (const p of props){
                                                                                          const spec = COLOR_MAP[p.name];
                                                                                          if (!spec) continue;
                                                                                          let next;
                                                                                          if (spec.kind === 'color'){
                                                                                          const rgb = opt[spec.src];
                                                                                          const alpha = (p.name === '_XRayColor') ? opt.alpha : p.val[3];
                                                                                          next = [rgb[0], rgb[1], rgb[2], alpha];
                                                                                          } else {
                                                                                          next = [opt.width, p.val[1], p.val[2], p.val[3]];
                                                                                          }
                                                                                          const before = spec.kind === 'color' ? rgb2hex(p.val) : p.val[0].toFixed(2);
                                                                                          const after  = spec.kind === 'color' ? rgb2hex(next)  : next[0].toFixed(2);
                                                                                          for (let i = 0; i < 4; i++) dv.setFloat32(p.valOff + i*4, next[i], true);
                                                                                          n++;
                                                                                          if (rows){
                                                                                          const sw  = spec.kind === 'color' ? `<span class="swatch" style="background:${before}">
                                                                                        </span>` : '';
                                                                                        const sw2 = spec.kind === 'color' ? `<span class="swatch" style="background:${after}">
                                                                                      </span>` : '';
                                                                                      rows.push([short, p.name, sw + before, sw2 + after]);
                                                                                      }
                                                                                      }
                                                                                      return n;
                                                                                      }
                                                                                      async function applyPreset3(orig, b, opt){
                                                                                      const node = b.nodes[0];
                                                                                      if (!node) throw new Error('Bundle không có node nào.');
                                                                                      const { data, blockAt } = decompressAll(orig, b);
                                                                                      const cab = data.subarray(node.off, node.off + node.size);
                                                                                      const sf = parseSF(cab);
                                                                                      const abObj = sf.objs.find(o => o.cid === 142);
                                                                                      const nameOf = new Map();
                                                                                      if (abObj){
                                                                                      const v = readObj(sf, abObj, null);
                                                                                      for (const c of v.m_Container) nameOf.set(c.second.asset.m_PathID, c.first);
                                                                                      }
                                                                                      const slots = new Map();
                                                                                      for (const o of sf.objs){
                                                                                      if (o.cid !== 48) continue;
                                                                                      const path = nameOf.get(o.pid);
                                                                                      if (!path || !isXrayShader(path)) continue;
                                                                                      slots.set(path.split('/').pop().replace(/\.shader$/, ''), o);
                                                                                      }
                                                                                      if (!slots.size)
                                                                                      throw new Error('Không tìm thấy backweapon / brmobilebumpspec / brmobilebumpspecdecal ' +
                                                                                      'trong bundle này. Đây có phải file shaders của game không?');
                                                                                      const rows = [];
                                                                                      const repl = new Map();
                                                                                      let swapped = 0, painted = 0;
                                                                                      for (const [key, o] of slots){
                                                                                      const bodyStart = sf.dataOffset + o.off;
                                                                                      const cur = cab.subarray(bodyStart, bodyStart + o.size);
                                                                                      let isXray = false;
                                                                                      try {
                                                                                      isXray = readShaderProps(cur).some(p => p.name === '_XRayColor' || p.name === '_DimColor');
                                                                                      } catch (e) { }
                                                                                      let body;
                                                                                      if (isXray){
                                                                                      body = cur.slice();
                                                                                      } else {
                                                                                      const x = await loadXray(key);
                                                                                      if (x.pid !== o.pid)
                                                                                      throw new Error(`pathID của ${key} không khớp shader nhúng ` +
                                                                                      `(${o.pid} ≠ ${x.pid}) — bundle này khác phiên bản.`);
                                                                                      if (x.body.length > o.size)
                                                                                      throw new Error(`Shader X-Ray của ${key} (${x.body.length} B) lớn hơn shader gốc ` +
                                                                                      `(${o.size} B) — không đệm vừa.`);
                                                                                      body = new Uint8Array(o.size);
                                                                                      body.set(x.body, 0);
                                                                                      swapped++;
                                                                                      rows.push([key + '.shader', '(toàn bộ shader)',
                                                                                      `gốc ${o.size.toLocaleString('vi-VN')} B`,
                                                                                      `X-Ray ${x.body.length.toLocaleString('vi-VN')} B + đệm`]);
                                                                                      }
                                                                                      painted += paintShader(body, opt, key + '.shader', rows);
                                                                                      repl.set(o.pid, body);
                                                                                      }
                                                                                      const out = rebuildShaders(orig, b, data, blockAt, sf, node, repl);
                                                                                      const what = swapped
                                                                                      ? `Đã thay <b>${swapped}</b> shader gốc bằng bản X-Ray và đặt màu`
                                                                                      : `Đã đổi màu <b>${slots.size}</b> shader định vị`;
                                                                                      return {
                                                                                      out,
                                                                                      note: `${what} — ${painted} giá trị, dung lượng giữ nguyên ` +
                                                                                      `${out.length.toLocaleString('vi-VN')} byte.`,
                                                                                      cols: ['Shader','Property','Trước','Sau'], rows, html: true
                                                                                      };
                                                                                      }
                                                                                      function decompressAll(orig, b){
                                                                                      const parts = [];
                                                                                      const blockAt = [];
                                                                                      let pos = b.dataStart, outPos = 0;
                                                                                      for (const blk of b.blocks){
                                                                                      const raw = orig.subarray(pos, pos + blk.c);
                                                                                      const ct = blk.f & 0x3F;
                                                                                      const dec = (ct === 2 || ct === 3) ? lz4dec(raw, blk.u) : raw.slice();
                                                                                      parts.push(dec);
                                                                                      blockAt.push({ start: outPos, end: outPos + blk.u, comp: blk.c, ct, srcOff: pos });
                                                                                      outPos += blk.u; pos += blk.c;
                                                                                      }
                                                                                      const data = new Uint8Array(outPos);
                                                                                      let w = 0;
                                                                                      for (const p of parts){ data.set(p, w); w += p.length; }
                                                                                      return { data, blockAt };
                                                                                      }
                                                                                      function rebuildShaders(orig, b, data, blockAt, sf, node, repl){
                                                                                      const touched = new Set();
                                                                                      for (const o of sf.objs){
                                                                                      const body = repl.get(o.pid);
                                                                                      if (!body) continue;
                                                                                      if (body.length !== o.size)
                                                                                      throw new Error(`Object ${o.pid} đổi kích thước (${o.size} → ${body.length}) — chưa hỗ trợ.`);
                                                                                      const abs = node.off + sf.dataOffset + o.off;
                                                                                      data.set(body, abs);
                                                                                      for (let i = 0; i < blockAt.length; i++){
                                                                                      const s = blockAt[i];
                                                                                      if (abs < s.end && abs + body.length > s.start) touched.add(i);
                                                                                      }
                                                                                      }
                                                                                      if (!touched.size) throw new Error('Không có gì thay đổi.');
                                                                                      const parts = [], newBlocks = [];
                                                                                      for (let i = 0; i < b.blocks.length; i++){
                                                                                      const blk = b.blocks[i], at = blockAt[i];
                                                                                      if (!touched.has(i)){
                                                                                      parts.push(orig.subarray(at.srcOff, at.srcOff + blk.c));
                                                                                      newBlocks.push({ u: blk.u, c: blk.c, f: blk.f });
                                                                                      continue;
                                                                                      }
                                                                                      const raw = data.subarray(at.start, at.end);
                                                                                      let comp, flags = blk.f;
                                                                                      if ((blk.f & 0x3F) === 0){
                                                                                      comp = raw;
                                                                                      } else {
                                                                                      comp = lz4enc(raw);
                                                                                      const back = lz4dec(comp, raw.length);
                                                                                      for (let k = 0; k < raw.length; k++)
                                                                                      if (back[k] !== raw[k]) throw new Error(`Nén lại block ${i} sai ở byte ${k}.`);
                                                                                      if (comp.length >= raw.length){ comp = raw; flags = blk.f & ~0x3F; }
                                                                                      }
                                                                                      parts.push(comp);
                                                                                      newBlocks.push({ u: blk.u, c: comp.length, f: flags });
                                                                                      }
                                                                                      const info = b.info.slice();
                                                                                      const idv = new DataView(info.buffer, info.byteOffset, info.byteLength);
                                                                                      let q = 20;
                                                                                      for (const nb of newBlocks){
                                                                                      idv.setUint32(q, nb.u, false);
                                                                                      idv.setUint32(q + 4, nb.c, false);
                                                                                      idv.setUint16(q + 8, nb.f, false);
                                                                                      q += 10;
                                                                                      }
                                                                                      const infoOut = ((b.flags & 0x3F) === 0) ? info : lz4enc(info);
                                                                                      const dataLen = parts.reduce((a, x) => a + x.length, 0);
                                                                                      const atEnd = !!(b.flags & 0x80);
                                                                                      const headLen = atEnd ? b.dataStart : b.infoOff;
                                                                                      let core = headLen + dataLen + infoOut.length;
                                                                                      if (!atEnd && (b.flags & 0x200))
                                                                                      core = ((headLen + infoOut.length + 15) & ~15) + dataLen;
                                                                                      if (core > orig.length)
                                                                                      throw new Error(`Nén lại phình ${(core - orig.length).toLocaleString('vi-VN')} byte so với ` +
                                                                                      `dung lượng gốc — không đủ chỗ đệm.`);
                                                                                      const out = new Uint8Array(orig.length);
                                                                                      if (atEnd){
                                                                                      out.set(orig.subarray(0, headLen), 0);
                                                                                      let p = headLen;
                                                                                      for (const x of parts){ out.set(x, p); p += x.length; }
                                                                                      out.set(infoOut, p);
                                                                                      } else {
                                                                                      out.set(orig.subarray(0, b.infoOff), 0);
                                                                                      out.set(infoOut, b.infoOff);
                                                                                      let p = b.infoOff + infoOut.length;
                                                                                      if (b.flags & 0x200) p = (p + 15) & ~15;
                                                                                      for (const x of parts){ out.set(x, p); p += x.length; }
                                                                                      }
                                                                                      const sp = findSizePos(out);
                                                                                      const odv = new DataView(out.buffer);
                                                                                      odv.setBigInt64(sp, BigInt(atEnd ? core : out.length), false);
                                                                                      odv.setUint32(sp + 8, infoOut.length, false);
                                                                                      odv.setUint32(sp + 12, info.length, false);
                                                                                      return out;
                                                                                      }
                                                                                      function findSizePos(u8){
                                                                                      let p = 0;
                                                                                      while (u8[p]) p++;
                                                                                      p++; p += 4;
                                                                                      while (u8[p]) p++; p++;
                                                                                      while (u8[p]) p++; p++;
                                                                                      return p;
                                                                                      }
                                                                                      /* ═══════════ PRESET 4: định vị nhân vật (hologram) ═══════════ */
                                                                                      const HOLO_BLOB = {"hologram":{"pid":"-8478029966577821520","size":7072,"z":"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"}};
                                                                                      const HOLO_PROPS = {
                                                                                      _TintColor:     { kind:'color',  src:'tint', label:'màu nhân vật' },
                                                                                      _RimColor:      { kind:'color',  src:'rim',  label:'màu sáng mép' },
                                                                                      _ScanColor:     { kind:'color',  src:'scan', label:'màu quét' },
                                                                                      _Line:          { kind:'vec4', src:'line',   on:[100,100,50,50], off:[0,0,0,0] },
                                                                                      _LineAndGlitch: { kind:'vec4', src:'glitch', on:[0.5,0.5,5,0.1], off:[0,0,0,0] }
                                                                                      };
                                                                                      async function loadHolo(){
                                                                                      const e = HOLO_BLOB.hologram;
                                                                                      const raw = Uint8Array.from(atob(e.z), c => c.charCodeAt(0));
                                                                                      const ds = new DecompressionStream('deflate');
                                                                                      const buf = new Uint8Array(await new Response(
                                                                                      new Blob([raw]).stream().pipeThrough(ds)).arrayBuffer());
                                                                                      if (buf.length !== e.size)
                                                                                      throw new Error(`Shader hologram giải ra ${buf.length} byte, cần ${e.size}.`);
                                                                                      return { body: buf, pid: BigInt(e.pid) };
                                                                                      }
                                                                                      const ZTEST_NAMES = { 0:'Disabled',1:'Never',2:'Less',3:'Equal',4:'LEqual',
                                                                                      5:'Greater',6:'NotEqual',7:'GEqual',8:'Always' };
                                                                                      function findZTest(body, type){
                                                                                      const nodes = buildNodes(type);
                                                                                      const r = makeReader(body);
                                                                                      const hits = [];
                                                                                      const walk = (i, inState) => {
                                                                                      const n = nodes[i];
                                                                                      const align = (n.meta & 0x4000) !== 0;
                                                                                      const kids = [];
                                                                                      let j = i + 1;
                                                                                      while (j < nodes.length && nodes[j].level > n.level){
                                                                                      if (nodes[j].level === n.level + 1) kids.push(j);
                                                                                      j++;
                                                                                      }
                                                                                      const start = r.p;
                                                                                      const t = n.type;
                                                                                      if (t === 'SInt8' || t === 'UInt8' || t === 'char' || t === 'bool') r.p += 1;
                                                                                      else if (t === 'SInt16' || t === 'UInt16' || t === 'short' || t === 'unsigned short') r.p += 2;
                                                                                      else if (t === 'SInt32' || t === 'int' || t === 'Type*' || t === 'UInt32' ||
                                                                                      t === 'unsigned int' || t === 'float') r.p += 4;
                                                                                      else if (t === 'SInt64' || t === 'UInt64' || t === 'long long' ||
                                                                                      t === 'unsigned long long' || t === 'FileSize' || t === 'double') r.p += 8;
                                                                                      else if (t === 'string'){
                                                                                      const ln = r.dv.getInt32(r.p, true); r.p += 4 + ln; r.align();
                                                                                      } else if (t === 'TypelessData'){
                                                                                      const ln = r.dv.getInt32(r.p, true); r.p += 4 + ln;
                                                                                      } else if (kids.length && nodes[kids[0]].type === 'Array'){
                                                                                      const ai = kids[0];
                                                                                      const ak = [];
                                                                                      let k = ai + 1;
                                                                                      while (k < nodes.length && nodes[k].level > nodes[ai].level){
                                                                                      if (nodes[k].level === nodes[ai].level + 1) ak.push(k);
                                                                                      k++;
                                                                                      }
                                                                                      const size = r.dv.getInt32(r.p, true); r.p += 4;
                                                                                      for (let m = 0; m < size; m++) walk(ak[1], inState);
                                                                                      if (nodes[ai].meta & 0x4000) r.align();
                                                                                      } else {
                                                                                      for (const c of kids) walk(c, inState || n.name === 'm_State');
                                                                                      }
                                                                                      if (align) r.align();
                                                                                      if (n.name === 'zTest' && inState) hits.push(start);
                                                                                      };
                                                                                      walk(0, false);
                                                                                      return hits;
                                                                                      }
                                                                                      function paintHolo(body, opt, rows, label){
                                                                                      const props = readShaderProps(body);
                                                                                      const dv = new DataView(body.buffer, body.byteOffset, body.byteLength);
                                                                                      let n = 0;
                                                                                      for (const p of props){
                                                                                      const spec = HOLO_PROPS[p.name];
                                                                                      if (!spec) continue;
                                                                                      let next, before, after;
                                                                                      if (spec.kind === 'color'){
                                                                                      const rgb = opt[spec.src];
                                                                                      const a   = opt[spec.src + 'A'];
                                                                                      next   = [rgb[0], rgb[1], rgb[2], a];
                                                                                      before = rgb2hex(p.val);
                                                                                      after  = rgb2hex(next);
                                                                                      } else {
                                                                                      next   = opt[spec.src] ? spec.on : spec.off;
                                                                                      before = `(${p.val.map(x => +x.toFixed(2)).join(', ')})`;
                                                                                      after  = `(${next.join(', ')})`;
                                                                                      }
                                                                                      for (let i = 0; i < 4; i++) dv.setFloat32(p.valOff + i*4, next[i], true);
                                                                                      n++;
                                                                                      if (rows){
                                                                                      const sw  = spec.kind === 'color' ? `<span class="swatch" style="background:${before}">
                                                                                    </span>` : '';
                                                                                    const sw2 = spec.kind === 'color' ? `<span class="swatch" style="background:${after}">
                                                                                  </span>` : '';
                                                                                  rows.push([label, p.name, sw + before, sw2 + after]);
                                                                                  }
                                                                                  }
                                                                                  return n;
                                                                                  }
                                                                                  async function applyPreset4(orig, b, opt){
                                                                                  const node = b.nodes[0];
                                                                                  if (!node) throw new Error('Bundle không có node nào.');
                                                                                  const { data, blockAt } = decompressAll(orig, b);
                                                                                  const cab = data.subarray(node.off, node.off + node.size);
                                                                                  const sf  = parseSF(cab);
                                                                                  const holo = await loadHolo();
                                                                                  const rows = [], repl = new Map();
                                                                                  let swapped = 0, painted = 0, zset = 0, skipped = 0;
                                                                                  for (const o of sf.objs){
                                                                                  if (o.cid !== 48) continue;
                                                                                  if (holo.body.length > o.size){ skipped++; continue; }
                                                                                  const body = new Uint8Array(o.size);
                                                                                  body.set(holo.body, 0);
                                                                                  swapped++;
                                                                                  painted += paintHolo(body, opt, rows, `shader ${o.pid}`);
                                                                                  try {
                                                                                  const zt = findZTest(body, sf.types[o.tid]);
                                                                                  const dv = new DataView(body.buffer, body.byteOffset, body.byteLength);
                                                                                  const zVal = opt.xray ? 8 : 4;
                                                                                  for (const off of zt) dv.setFloat32(off, zVal, true);
                                                                                  zset += zt.length;
                                                                                  if (zt.length && rows)
                                                                                  rows.push([`shader ${o.pid}`, 'zTest', '?', `${zVal} (${ZTEST_NAMES[zVal]})`]);
                                                                                  } catch(e){ console.warn('zTest patch:', e); }
                                                                                  repl.set(o.pid, body);
                                                                                  }
                                                                                  if (!repl.size)
                                                                                  throw new Error(`Không shader nào vừa hologram (${holo.body.length} B) — ` +
                                                                                  `shader gốc đều nhỏ hơn.`);
                                                                                  const out = rebuildShaders(orig, b, data, blockAt, sf, node, repl);
                                                                                  return {
                                                                                  out,
                                                                                  note: `Đã thay <b>${swapped}</b> shader bằng hologram` +
                                                                                  (skipped ? ` · bỏ qua ${skipped} shader < ${holo.body.length} B` : '') +
                                                                                  ` · đặt ${painted} màu · ${zset} zTest = ` +
                                                                                  `${opt.xray ? 'Always (xuyên tường)' : 'LEqual'} — dung lượng giữ nguyên ` +
                                                                                  `${out.length.toLocaleString('vi-VN')} byte.`,
                                                                                  cols: ['Shader', 'Property', 'Trước', 'Sau'], rows, html: true
                                                                                  };
                                                                                  }
                                                                                  /* ═══════════ UI / NẠP FILE ═══════════ */
                                                                                  const $file = $('#file'), $drop = $('#drop'),
                                                                                  $info = $('#info'), $out  = $('#out'), $go = $('#go');
                                                                                  let curFile = null, curBundle = null, curName = '';
                                                                                  $drop.addEventListener('click', (e) => {
                                                                                  if (e.target === $file) return;
                                                                                  e.preventDefault();
                                                                                  $file.click();
                                                                                  });
                                                                                  ['dragenter','dragover'].forEach(ev =>
                                                                                  $drop.addEventListener(ev, e => { e.preventDefault(); $drop.classList.add('over'); }));
                                                                                  ['dragleave','drop'].forEach(ev =>
                                                                                  $drop.addEventListener(ev, e => { e.preventDefault(); $drop.classList.remove('over'); }));
                                                                                  $drop.addEventListener('drop', e => {
                                                                                  const f = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
                                                                                  if (f) loadFile(f);
                                                                                  });
                                                                                  $file.addEventListener('change', () => {
                                                                                  const f = $file.files && $file.files[0];
                                                                                  if (f) loadFile(f);
                                                                                  });
                                                                                  async function loadFile(f){
                                                                                  curName = f.name;
                                                                                  $out.innerHTML = '';
                                                                                  $info.innerHTML = '';
                                                                                  $drop.classList.add('has');
                                                                                  $('#dropText').innerHTML = `<b>${esc(f.name)}</b>
                                                                                  <span>${(f.size/1024).toFixed(1)} KB · đang đọc…</span>`;
                                                                                    try {
                                                                                    const buf = new Uint8Array(await f.arrayBuffer());
                                                                                    const b = parseBundle(buf);
                                                                                    curFile = buf;
                                                                                    curBundle = b;
                                                                                    const isHolo = /optionalavatarres|commonab/i.test(f.name);
                                                                                    const val = isHolo ? '4' : '3';
                                                                                    const radio = document.querySelector(`input[name="p"][value="${val}"]`);
                                                                                    if (radio){ radio.checked = true; onPresetChange(); }
                                                                                    $info.innerHTML = `<div class="panel">
                                                                                    <h2>Bundle</h2>
                                                                                      <table>
                                                                                        <tr>
                                                                                          <td>File</td>
                                                                                            <td>${esc(f.name)}</td>
                                                                                            </tr>
                                                                                            <tr>
                                                                                              <td>Kích thước</td>
                                                                                                <td>${buf.length.toLocaleString('vi-VN')} byte</td>
                                                                                                </tr>
                                                                                                <tr>
                                                                                                  <td>Unity</td>
                                                                                                    <td>${esc(b.uv)} rev ${esc(b.rev)}</td>
                                                                                                    </tr>
                                                                                                    <tr>
                                                                                                      <td>Format</td>
                                                                                                        <td>v${b.fmt} · flags 0x${b.flags.toString(16)}</td>
                                                                                                        </tr>
                                                                                                        <tr>
                                                                                                          <td>Blocks</td>
                                                                                                            <td>${b.blocks.length}</td>
                                                                                                            </tr>
                                                                                                            <tr>
                                                                                                              <td>Nodes</td>
                                                                                                                <td>${b.nodes.map(n => esc(n.name)).join(', ')}</td>
                                                                                                                </tr>
                                                                                                              </table>
                                                                                                            </div>`;
                                                                                                            $go.disabled = false;
                                                                                                            $('#dropText').innerHTML = `<b>${esc(f.name)}</b>
                                                                                                            <span>${buf.length.toLocaleString('vi-VN')} byte · bấm để đổi file</span>`;
                                                                                                              } catch (e) {
                                                                                                              console.error(e);
                                                                                                              curFile = null; curBundle = null;
                                                                                                              $go.disabled = true;
                                                                                                              $info.innerHTML = `<div class="msg bad">Lỗi đọc file: ${esc(e.message)}</div>`;
                                                                                                              $('#dropText').innerHTML = `<b>Bấm để chọn file bundle</b>
                                                                                                              <span>shaders / optionalavatarres_commonab_shader</span>`;
                                                                                                                $drop.classList.remove('has');
                                                                                                                }
                                                                                                                $file.value = '';
                                                                                                                }
                                                                                                                document.querySelectorAll('input[name="p"]').forEach(r =>
                                                                                                                r.addEventListener('change', onPresetChange));
                                                                                                                function onPresetChange(){
                                                                                                                const v = document.querySelector('input[name="p"]:checked')?.value;
                                                                                                                document.querySelectorAll('.pre').forEach(el => {
                                                                                                                const inp = el.querySelector('input');
                                                                                                                el.classList.toggle('sel', inp.checked);
                                                                                                                });
                                                                                                                $('#colBox').classList.toggle('hide', v !== '3');
                                                                                                                $('#holoBox').classList.toggle('hide', v !== '4');
                                                                                                                }
                                                                                                                function syncColor(cid, tid){
                                                                                                                const c = $(cid), t = $(tid);
                                                                                                                if (!c || !t) return;
                                                                                                                c.addEventListener('input', () => { t.value = c.value.toUpperCase(); t.classList.remove('bad'); });
                                                                                                                t.addEventListener('input', () => {
                                                                                                                const rgb = hex2rgb(t.value);
                                                                                                                if (rgb){
                                                                                                                c.value = '#' + [rgb[0],rgb[1],rgb[2]]
                                                                                                                .map(x => Math.round(x*255).toString(16).padStart(2,'0')).join('');
                                                                                                                t.classList.remove('bad');
                                                                                                                } else {
                                                                                                                t.classList.add('bad');
                                                                                                                }
                                                                                                                });
                                                                                                                }
                                                                                                                syncColor('#cXray', '#tXray');
                                                                                                                syncColor('#cLine', '#tLine');
                                                                                                                syncColor('#cDim',  '#tDim');
                                                                                                                syncColor('#cTint', '#tTint');
                                                                                                                syncColor('#cRim',  '#tRim');
                                                                                                                syncColor('#cScan', '#tScan');
                                                                                                                function bindRange(rid, vid, fix = 2){
                                                                                                                const r = $(rid), v = $(vid);
                                                                                                                if (!r || !v) return;
                                                                                                                const upd = () => v.textContent = Number(r.value).toFixed(fix);
                                                                                                                r.addEventListener('input', upd); upd();
                                                                                                                }
                                                                                                                bindRange('#rWidth', '#wVal', 1);
                                                                                                                bindRange('#rAlpha', '#aVal', 2);
                                                                                                                bindRange('#rTintA', '#tintAVal', 2);
                                                                                                                bindRange('#rRimA',  '#rimAVal', 2);
                                                                                                                bindRange('#rScanA', '#scanAVal', 2);
                                                                                                                $go.addEventListener('click', async () => {
                                                                                                                if (!curFile || !curBundle) return;
                                                                                                                $go.disabled = true;
                                                                                                                $out.innerHTML = `<div class="msg warn">Đang xử lý…</div>`;
                                                                                                                try {
                                                                                                                const v = document.querySelector('input[name="p"]:checked')?.value;
                                                                                                                if (!v) throw new Error('Chưa chọn preset.');
                                                                                                                let res;
                                                                                                                if (v === '3'){
                                                                                                                const x = hex2rgb($('#tXray').value) || [0,0,0];
                                                                                                                const l = hex2rgb($('#tLine').value) || [1,1,1];
                                                                                                                const d = hex2rgb($('#tDim').value)  || [0,0,0];
                                                                                                                res = await applyPreset3(curFile, curBundle, {
                                                                                                                xray: x, line: l, dim: d,
                                                                                                                width: +$('#rWidth').value,
                                                                                                                alpha: +$('#rAlpha').value
                                                                                                                });
                                                                                                                } else {
                                                                                                                const t = hex2rgb($('#tTint').value) || [0,1,1];
                                                                                                                const r = hex2rgb($('#tRim').value)  || [0,1,1];
                                                                                                                const s = hex2rgb($('#tScan').value) || [0,0,0];
                                                                                                                res = await applyPreset4(curFile, curBundle, {
                                                                                                                tint: t, tintA: +$('#rTintA').value,
                                                                                                                rim:  r, rimA:  +$('#rRimA').value,
                                                                                                                scan: s, scanA: +$('#rScanA').value,
                                                                                                                xray:   $('#kXray').checked,
                                                                                                                line:   $('#kLine').checked,
                                                                                                                glitch: $('#kGlitch').checked
                                                                                                                });
                                                                                                                }
                                                                                                                renderResult(res);
                                                                                                                } catch (e) {
                                                                                                                console.error(e);
                                                                                                                $out.innerHTML = `<div class="msg bad">
                                                                                                                <b>Lỗi:</b> ${esc(e.message)}</div>`;
                                                                                                                  } finally {
                                                                                                                  $go.disabled = false;
                                                                                                                  }
                                                                                                                  });
                                                                                                                  function renderResult(res){
                                                                                                                  const blob = new Blob([res.out], { type: 'application/octet-stream' });
                                                                                                                  const url  = URL.createObjectURL(blob);
                                                                                                                  let html = `<div class="msg ok">${res.note}</div>`;
                                                                                                                  html += `<div class="row" style="margin-bottom:14px">
                                                                                                                  <a href="${url}" download="${esc(curName)}" style="text-decoration:none;width:100%">
                                                                                                                    <button type="button" class="btn-primary">Tải file đã sửa (${res.out.length.toLocaleString('vi-VN')} B)</button>
                                                                                                                    </a>
                                                                                                                  </div>`;
                                                                                                                  if (res.rows && res.rows.length){
                                                                                                                  html += `<div class="panel">
                                                                                                                  <h2>Thay đổi</h2>
                                                                                                                    <div class="hexwrap">
                                                                                                                      <table class="hex">`;
                                                                                                                        html += `<tr>${res.cols.map(c => `<th>${esc(c)}</th>`).join('')}</tr>`;
                                                                                                                        for (const row of res.rows){
                                                                                                                        html += `<tr>${row.map(c => `<td>${res.html ? c : esc(c)}</td>`).join('')}</tr>`;
                                                                                                                        }
                                                                                                                        html += `</table>
                                                                                                                      </div>
                                                                                                                    </div>`;
                                                                                                                    }
                                                                                                                    $out.innerHTML = html;
                                                                                                                    }