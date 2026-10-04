// CUDA WebShader 0.1.1. Generated from kernel stepGame.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read_write> b_state: array<f32>;
struct CWParams {
  p_dt: f32,
  p_inputX: f32,
  p_inputZ: f32,
  p_sprint: i32,
  p_interact: i32,
  p_paused: i32,
  p_clockRate: f32,
  p_setHour: f32,
}
@group(0) @binding(1) var<uniform> cw_params: CWParams;
const cw_block_size: vec3<u32> = vec3<u32>(1u, 1u, 1u);

fn cw_divide_f32(a: f32, b: f32) -> f32 { let q = a / b; if ((bitcast<u32>(q) & 0x7f800000u) == 0x7f800000u || (bitcast<u32>(q) & 0x7fffffffu) == 0u || (bitcast<u32>(b) & 0x7f800000u) == 0x7f800000u) { return q; } let residual = fma(-q, b, a); return q + residual / b; }

alias cw_f64 = vec2<u32>;
fn cw_d_shl(a: vec2<u32>, n: u32) -> vec2<u32> {
  if(n == 0u) { return a; }
  if(n >= 64u) { return vec2<u32>(0u); }
  if(n >= 32u) { return vec2<u32>(0u, a.x << (n - 32u)); }
  return vec2<u32>(a.x << n, (a.y << n) | (a.x >> (32u - n)));
}
fn cw_d_shr(a: vec2<u32>, n: u32) -> vec2<u32> {
  if(n == 0u) { return a; }
  if(n >= 64u) { return vec2<u32>(0u); }
  if(n >= 32u) { return vec2<u32>(a.y >> (n - 32u), 0u); }
  return vec2<u32>((a.x >> n) | (a.y << (32u - n)), a.y >> n);
}
fn cw_d_jam(a: vec2<u32>, n: u32) -> vec2<u32> {
  let shifted = cw_d_shr(a, n);
  return shifted | vec2<u32>(select(0u, 1u, any(cw_d_shl(shifted, n) != a)), 0u);
}
fn cw_d_uadd(a: vec2<u32>, b: vec2<u32>) -> vec2<u32> {
  let low = a.x + b.x;
  return vec2<u32>(low, a.y + b.y + select(0u, 1u, low < a.x));
}
fn cw_d_usub(a: vec2<u32>, b: vec2<u32>) -> vec2<u32> {
  return vec2<u32>(a.x - b.x, a.y - b.y - select(0u, 1u, a.x < b.x));
}
fn cw_d_uless(a: vec2<u32>, b: vec2<u32>) -> bool {
  return a.y < b.y || (a.y == b.y && a.x < b.x);
}
fn cw_d_nan(a: cw_f64) -> bool { return (a.y & 2147483647u) > 2146435072u || ((a.y & 2147483647u) == 2146435072u && a.x != 0u); }
fn cw_d_inf(a: cw_f64) -> bool { return (a.y & 2147483647u) == 2146435072u && a.x == 0u; }
fn cw_d_zero(a: cw_f64) -> bool { return (a.y & 2147483647u) == 0u && a.x == 0u; }

struct CWDoubleParts { significand: vec2<u32>, exponent: i32, }
fn cw_d_parts(a: cw_f64) -> CWDoubleParts {
  let raw = (a.y >> 20u) & 2047u;
  var s = vec2<u32>(a.x, a.y & 1048575u);
  var e = i32(raw) - 1023i;
  if(raw != 0u) { s.y |= 1048576u; }
  else {
    e = -1022i;
    if(any(s != vec2<u32>(0u))) {
      loop { if((s.y & 1048576u) != 0u) { break; } s = cw_d_shl(s, 1u); e--; }
    }
  }
  return CWDoubleParts(s,e);
}
// Input has its leading bit at bit 55 and three guard/round/sticky bits.
fn cw_d_pack(sign: u32, exponent: i32, value: vec2<u32>) -> cw_f64 {
  var e = exponent; var v = value;
  if(e < -1022i) { v = cw_d_jam(v, u32(-1022i-e)); e = -1022i; }
  let tail = v.x & 7u;
  var s = cw_d_shr(v, 3u);
  if(tail > 4u || (tail == 4u && (s.x & 1u) != 0u)) { s = cw_d_uadd(s,vec2<u32>(1u,0u)); }
  if((s.y & 2097152u) != 0u) { s = cw_d_shr(s,1u); e++; }
  if(e > 1023i) { return vec2<u32>(0u,sign | 2146435072u); }
  let field = select(0u, u32(e+1023i), (s.y & 1048576u) != 0u);
  return vec2<u32>(s.x, sign | (field << 20u) | (s.y & 1048575u));
}
fn cw_d_from_f32(a: f32) -> cw_f64 {
  let bits = bitcast<u32>(a); let sign = bits & 2147483648u;
  let field = (bits >> 23u) & 255u; var mantissa = bits & 8388607u;
  if(field == 255u) { return vec2<u32>(0u,sign | 2146435072u | select(0u,524288u,mantissa != 0u)); }
  if(field == 0u && mantissa == 0u) { return vec2<u32>(0u,sign); }
  var e = i32(field)-127i;
  if(field == 0u) { e = -126i; loop { if((mantissa & 8388608u) != 0u) { break; } mantissa <<= 1u; e--; } }
  let s = cw_d_shl(vec2<u32>(mantissa & 8388607u,0u),29u);
  return vec2<u32>(s.x,sign | (u32(e+1023i) << 20u) | s.y);
}
fn cw_d_from_u32(a: u32) -> cw_f64 {
  if(a == 0u) { return vec2<u32>(0u); }
  let e = 31u-countLeadingZeros(a); let s = cw_d_shl(vec2<u32>(a,0u),52u-e);
  return vec2<u32>(s.x,((e+1023u) << 20u) | (s.y & 1048575u));
}

fn cw_d_to_f32(a: cw_f64) -> f32 {
  let sign = a.y & 2147483648u;
  if(cw_d_nan(a)) { return bitcast<f32>(sign | 2143289344u); }
  if(cw_d_inf(a)) { return bitcast<f32>(sign | 2139095040u); }
  if(cw_d_zero(a)) { return bitcast<f32>(sign); }
  let p = cw_d_parts(a); var e = p.exponent;
  let shift = 29u + u32(max(-126i-e,0i));
  // Keep three rounding bits while reducing the 53-bit significand to 24 bits.
  let v = cw_d_jam(p.significand,shift-3u); let tail = v.x & 7u;
  var s = cw_d_shr(v,3u).x;
  if(tail > 4u || (tail == 4u && (s & 1u) != 0u)) { s++; }
  e = max(e,-126i);
  if(s >= 16777216u) { s >>= 1u; e++; }
  if(e > 127i) { return bitcast<f32>(sign | 2139095040u); }
  let field = select(0u,u32(e+127i),s >= 8388608u);
  return bitcast<f32>(sign | (field << 23u) | (s & 8388607u));
}






fn cw_d_mul(a: cw_f64,b: cw_f64) -> cw_f64 {
  let sign = (a.y ^ b.y) & 2147483648u;
  if(cw_d_nan(a) || cw_d_nan(b) || (cw_d_inf(a) && cw_d_zero(b)) || (cw_d_inf(b) && cw_d_zero(a))) { return vec2<u32>(0u,2146959360u); }
  if(cw_d_inf(a) || cw_d_inf(b)) { return vec2<u32>(0u,sign | 2146435072u); }
  if(cw_d_zero(a) || cw_d_zero(b)) { return vec2<u32>(0u,sign); }
  let pa = cw_d_parts(a); let pb = cw_d_parts(b);
  if(all(pa.significand == vec2<u32>(0u,1048576u))) { return cw_d_pack(sign,pa.exponent+pb.exponent,cw_d_shl(pb.significand,3u)); }
  if(all(pb.significand == vec2<u32>(0u,1048576u))) { return cw_d_pack(sign,pa.exponent+pb.exponent,cw_d_shl(pa.significand,3u)); }
  var product = vec4<u32>(0u); var term = vec4<u32>(pa.significand,0u,0u); var multiplier = pb.significand;
  for(var i = 0u; i < 53u; i++) {
    if((multiplier.x & 1u) != 0u) {
      var carry = 0u;
      for(var j = 0u; j < 4u; j++) {
        let p = product[j]; let s = p + term[j]; let t = s + carry;
        carry = select(0u,1u,s < p || t < s); product[j] = t;
      }
    }
    term = vec4<u32>(term.x << 1u,(term.y << 1u) | (term.x >> 31u),(term.z << 1u) | (term.y >> 31u),(term.w << 1u) | (term.z >> 31u));
    multiplier = cw_d_shr(multiplier,1u);
  }
  let extra = select(0u,1u,(product.w & 512u) != 0u);
  for(var i = 0u; i < 49u+extra; i++) {
    product = vec4<u32>((product.x >> 1u) | (product.y << 31u) | (product.x & 1u),(product.y >> 1u) | (product.z << 31u),(product.z >> 1u) | (product.w << 31u),product.w >> 1u);
  }
  return cw_d_pack(sign,pa.exponent+pb.exponent+i32(extra),product.xy);
}
fn cw_d_div(a: cw_f64,b: cw_f64) -> cw_f64 {
  let sign = (a.y ^ b.y) & 2147483648u;
  if(cw_d_nan(a) || cw_d_nan(b) || (cw_d_inf(a) && cw_d_inf(b)) || (cw_d_zero(a) && cw_d_zero(b))) { return vec2<u32>(0u,2146959360u); }
  if(cw_d_inf(a) || cw_d_zero(b)) { return vec2<u32>(0u,sign | 2146435072u); }
  if(cw_d_zero(a) || cw_d_inf(b)) { return vec2<u32>(0u,sign); }
  let pa = cw_d_parts(a); let pb = cw_d_parts(b); var e = pa.exponent-pb.exponent;
  var remainder = pa.significand; var q = vec2<u32>(0u);
  if(cw_d_uless(remainder,pb.significand)) { remainder = cw_d_shl(remainder,1u); e--; }
  for(var i = 0u; i < 56u; i++) {
    q = cw_d_shl(q,1u);
    if(!cw_d_uless(remainder,pb.significand)) { remainder = cw_d_usub(remainder,pb.significand); q.x |= 1u; }
    if(i < 55u) { remainder = cw_d_shl(remainder,1u); }
  }
  if(any(remainder != vec2<u32>(0u))) { q.x |= 1u; }
  return cw_d_pack(sign,e,q);
}

// Restoring square root: 56 root bits include guard/round/sticky for binary64.





fn f_clampf(cw_arg_x: f32, cw_arg_a: f32, cw_arg_b: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: f32 = cw_arg_x;
  var v_a: f32 = cw_arg_a;
  var v_b: f32 = cw_arg_b;
  return min(v_b, max(v_a, v_x));
}
fn f_sat(cw_arg_x: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: f32 = cw_arg_x;
  return f_clampf(v_x, 0.0f, 1.0f, cw_thread, cw_block, cw_grid);
}
fn f_mixf(cw_arg_a: f32, cw_arg_b: f32, cw_arg_t: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_a: f32 = cw_arg_a;
  var v_b: f32 = cw_arg_b;
  var v_t: f32 = cw_arg_t;
  return (v_a + ((v_b - v_a) * v_t));
}
fn f_smoothf(cw_arg_a: f32, cw_arg_b: f32, cw_arg_x: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_a: f32 = cw_arg_a;
  var v_b: f32 = cw_arg_b;
  var v_x: f32 = cw_arg_x;
  var v_t: f32 = f_sat(cw_divide_f32((v_x - v_a), (v_b - v_a)), cw_thread, cw_block, cw_grid);
  return ((v_t * v_t) * (3.0f - (2.0f * v_t)));
}
fn f_fractf(cw_arg_x: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: f32 = cw_arg_x;
  return (v_x - floor(v_x));
}
fn f_v3(cw_arg_x: f32, cw_arg_y: f32, cw_arg_z: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_x: f32 = cw_arg_x;
  var v_y: f32 = cw_arg_y;
  var v_z: f32 = cw_arg_z;
  return vec3<f32>(v_x, v_y, v_z);
}














fn f_hashU(cw_arg_x: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> u32 {
  var v_x: u32 = cw_arg_x;
  v_x = (v_x ^ (v_x >> u32(16i)));
  v_x = (v_x * 2146121005u);
  v_x = (v_x ^ (v_x >> u32(15i)));
  v_x = (v_x * 2221713035u);
  v_x = (v_x ^ (v_x >> u32(16i)));
  return v_x;
}
fn f_rnd(cw_arg_x: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: u32 = cw_arg_x;
  return (f32((f_hashU(v_x, cw_thread, cw_block, cw_grid) & 16777215u)) * cw_divide_f32(1.0f, 16777216.0f));
}
fn f_lattice(cw_arg_x: i32, cw_arg_y: i32, cw_arg_z: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: i32 = cw_arg_x;
  var v_y: i32 = cw_arg_y;
  var v_z: i32 = cw_arg_z;
  return f_rnd((((u32(v_x) * 73856093u) ^ (u32(v_y) * 19349663u)) ^ (u32(v_z) * 83492791u)), cw_thread, cw_block, cw_grid);
}
fn f_noise3(cw_arg_p: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_p: vec3<f32> = cw_arg_p;
  var v_i: vec3<f32> = f_v3(floor(v_p.x), floor(v_p.y), floor(v_p.z), cw_thread, cw_block, cw_grid);
  var v_f: vec3<f32> = (v_p - v_i);
  v_f = ((v_f * v_f) * (f_v3(f32(3i), f32(3i), f32(3i), cw_thread, cw_block, cw_grid) - (v_f * vec3<f32>(2.0f))));
  var v_x: i32 = i32(v_i.x);
  var v_y: i32 = i32(v_i.y);
  var v_z: i32 = i32(v_i.z);
  var v_a: f32 = f_mixf(f_lattice(v_x, v_y, v_z, cw_thread, cw_block, cw_grid), f_lattice((v_x + 1i), v_y, v_z, cw_thread, cw_block, cw_grid), v_f.x, cw_thread, cw_block, cw_grid);
  var v_b: f32 = f_mixf(f_lattice(v_x, (v_y + 1i), v_z, cw_thread, cw_block, cw_grid), f_lattice((v_x + 1i), (v_y + 1i), v_z, cw_thread, cw_block, cw_grid), v_f.x, cw_thread, cw_block, cw_grid);
  var v_c: f32 = f_mixf(f_lattice(v_x, v_y, (v_z + 1i), cw_thread, cw_block, cw_grid), f_lattice((v_x + 1i), v_y, (v_z + 1i), cw_thread, cw_block, cw_grid), v_f.x, cw_thread, cw_block, cw_grid);
  var v_d: f32 = f_mixf(f_lattice(v_x, (v_y + 1i), (v_z + 1i), cw_thread, cw_block, cw_grid), f_lattice((v_x + 1i), (v_y + 1i), (v_z + 1i), cw_thread, cw_block, cw_grid), v_f.x, cw_thread, cw_block, cw_grid);
  return f_mixf(f_mixf(v_a, v_b, v_f.y, cw_thread, cw_block, cw_grid), f_mixf(v_c, v_d, v_f.y, cw_thread, cw_block, cw_grid), v_f.z, cw_thread, cw_block, cw_grid);
}
fn f_fbm(cw_arg_p: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_p: vec3<f32> = cw_arg_p;
  return (((f_noise3(v_p, cw_thread, cw_block, cw_grid) * 0.57f) + (f_noise3(((v_p * vec3<f32>(2.03f)) + f_v3(3.2f, 1.1f, 5.4f, cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid) * 0.28f)) + (f_noise3((v_p * vec3<f32>(4.17f)), cw_thread, cw_block, cw_grid) * 0.15f));
}
fn f_profile(cw_arg_x: f32, cw_arg_location: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec4<f32> {
  var v_x: f32 = cw_arg_x;
  var v_location: i32 = cw_arg_location;
  var v_a: vec4<f32> = vec4<f32>(f32((-96i)), 20.25f, 13.4f, 1.78f);
  var v_b: vec4<f32> = vec4<f32>(f32((-48i)), 19.55f, 12.0f, 1.84f);
  var v_c: vec4<f32> = vec4<f32>(f32(0i), 19.85f, 10.6f, 1.9f);
  var v_d: vec4<f32> = vec4<f32>(f32(48i), 20.35f, 13.2f, 1.95f);
  var v_e: vec4<f32> = vec4<f32>(f32(96i), 19.1f, 13.9f, 1.99f);
  if ((v_location == 1i)) {
    v_a = vec4<f32>(f32((-96i)), 20.8f, f32(14i), 1.7f);
    v_b = vec4<f32>(f32((-52i)), 21.4f, 12.6f, 1.76f);
    v_c = vec4<f32>(f32((-8i)), 20.7f, 11.4f, 1.82f);
    v_d = vec4<f32>(f32(40i), 19.9f, 10.2f, 1.88f);
    v_e = vec4<f32>(f32(96i), 20.5f, 13.1f, 1.93f);
  }
  if ((v_x > v_b.x)) {
    v_a = v_b;
    v_b = v_c;
    if ((v_x > v_c.x)) {
      v_a = v_c;
      v_b = v_d;
      if ((v_x > v_d.x)) {
        v_a = v_d;
        v_b = v_e;
      }
    }
  }
  var v_t: f32 = f_smoothf(v_a.x, v_b.x, v_x, cw_thread, cw_block, cw_grid);
  return (v_a + ((v_b - v_a) * vec4<f32>(v_t)));
}
fn f_shore(cw_arg_x: f32, cw_arg_loc: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: f32 = cw_arg_x;
  var v_loc: i32 = cw_arg_loc;
  return ((f_profile(v_x, v_loc, cw_thread, cw_block, cw_grid).z + (0.24f * sin((v_x * 0.43f)))) + (0.12f * sin((v_x * 1.27f))));
}
fn f_groundHeight(cw_arg_x: f32, cw_arg_z: f32, cw_arg_loc: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: f32 = cw_arg_x;
  var v_z: f32 = cw_arg_z;
  var v_loc: i32 = cw_arg_loc;
  var v_p: vec4<f32> = f_profile(v_x, v_loc, cw_thread, cw_block, cw_grid);
  var v_s: f32 = (v_z - f_shore(v_x, v_loc, cw_thread, cw_block, cw_grid));
  var v_shelf: f32 = f_fbm(f_v3((v_x * 0.19f), (2.1f + (f32(v_loc) * 4.0f)), (v_z * 0.23f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_channel: f32 = f_fbm(f_v3((v_x * 0.075f), (8.7f + f32(v_loc)), (v_z * 0.16f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_ledge: f32 = ((-0.14f) - (cw_pow_f32(v_shelf, 1.7f) * 1.9f));
  var v_deep: f32 = ((-2.5f) - (v_channel * 2.6f));
  var v_bed: f32 = f_mixf(v_deep, v_ledge, f_smoothf((-10.0f), (-0.3f), v_s, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_shoreOffset: f32 = ((v_shelf - 0.5f) * 1.6f);
  var v_h: f32 = f_mixf(v_bed, v_p.w, f_smoothf((0.0f + v_shoreOffset), 4.5f, v_s, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_n: f32 = (f_fbm(f_v3((v_x * 0.35f), 1.7f, (v_z * 0.35f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid) - 0.5f);
  v_h = (v_h + ((v_n * 0.22f) * f_smoothf(f32(0i), f32(3i), v_s, cw_thread, cw_block, cw_grid)));
  v_h = (v_h + (((f_noise3(f_v3((v_x * 7.1f), 3.4f, (v_z * 7.1f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid) - 0.5f) * 0.032f) * f_smoothf(0.5f, 3.0f, v_s, cw_thread, cw_block, cw_grid)));
  var cw_tmp_1: f32;
  if ((v_loc == 1i)) {
    cw_tmp_1 = 0.049f;
  } else {
    cw_tmp_1 = 0.023f;
  }
  v_h = (v_h + (max(0.0f, (v_z - 26.0f)) * cw_tmp_1));
  v_h = (v_h + (f_smoothf(f32(52i), f32(95i), v_z, cw_thread, cw_block, cw_grid) * (9.0f + (12.0f * f_fbm(f_v3((v_x * 0.025f), f32(2i), (v_z * 0.035f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid)))));
  return v_h;
}
























fn cw_pow_f32(base: f32, exponent: f32) -> f32 {
  if(exponent >= -64.0f && exponent <= 64.0f && exponent == trunc(exponent)) {
    var count=u32(abs(exponent));
    var value=cw_d_from_f32(base);var product=cw_d_from_u32(1u);
    loop {
      if(count == 0u) { break; }
      if((count & 1u) != 0u) { product=cw_d_mul(product,value); }
      count >>= 1u;
      if(count != 0u) { value=cw_d_mul(value,value); }
    }
    if(exponent < 0.0f) { product=cw_d_div(cw_d_from_u32(1u),product); }
    return cw_d_to_f32(product);
  }
  return pow(base,exponent);
}

@compute @workgroup_size(1, 1, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  b_state[13i] = b_state[11i];
  b_state[14i] = b_state[12i];
  b_state[18i] = f32(0i);
  if ((cw_params.p_setHour >= f32(0i))) {
    b_state[10i] = cw_params.p_setHour;
  }
  if ((cw_params.p_paused != 0i)) {
    return;
  }
  var v_t: f32 = f_clampf(cw_params.p_dt, f32(0i), 0.1f, cw_thread, cw_block, cw_grid);
  let cw_argument_index_6 = 7i;
  var v_loc: i32 = i32(b_state[cw_argument_index_6]);
  var v_ix: f32 = cw_params.p_inputX;
  var v_iz: f32 = cw_params.p_inputZ;
  var v_il: f32 = sqrt(((v_ix * v_ix) + (v_iz * v_iz)));
  if ((v_il > f32(1i))) {
    v_ix = cw_divide_f32(v_ix, v_il);
    v_iz = cw_divide_f32(v_iz, v_il);
  }
  var cw_tmp_7: f32;
  if ((cw_params.p_sprint != 0i)) {
    cw_tmp_7 = 3.8f;
  } else {
    cw_tmp_7 = 2.3f;
  }
  var v_speed: f32 = cw_tmp_7;
  var cw_tmp_8: f32;
  if ((v_il > f32(0i))) {
    cw_tmp_8 = 13.5f;
  } else {
    cw_tmp_8 = 16.5f;
  }
  var v_response: f32 = (f32(1i) - exp(((-v_t) * cw_tmp_8)));
  let cw_argument_index_9 = 3i;
  b_state[3i] = f_mixf(b_state[cw_argument_index_9], (v_ix * v_speed), v_response, cw_thread, cw_block, cw_grid);
  let cw_argument_index_10 = 4i;
  b_state[4i] = f_mixf(b_state[cw_argument_index_10], (v_iz * v_speed), v_response, cw_thread, cw_block, cw_grid);
  let cw_argument_index_11 = 3i;
  if ((abs(b_state[cw_argument_index_11]) < 0.005f)) {
    b_state[3i] = f32(0i);
  }
  let cw_argument_index_12 = 4i;
  if ((abs(b_state[cw_argument_index_12]) < 0.005f)) {
    b_state[4i] = f32(0i);
  }
  var v_oldX: f32 = b_state[0i];
  var v_oldZ: f32 = b_state[2i];
  b_state[0i] = f_clampf((b_state[0i] + (b_state[3i] * v_t)), f32((-96i)), f32(96i), cw_thread, cw_block, cw_grid);
  var cw_tmp_13: f32;
  if ((v_loc == 0i)) {
    cw_tmp_13 = 16.2f;
  } else {
    cw_tmp_13 = 16.4f;
  }
  var cw_tmp_14: f32;
  if ((v_loc == 0i)) {
    cw_tmp_14 = 24.4f;
  } else {
    cw_tmp_14 = 24.8f;
  }
  b_state[2i] = f_clampf((b_state[2i] + (b_state[4i] * v_t)), cw_tmp_13, cw_tmp_14, cw_thread, cw_block, cw_grid);
  let cw_argument_index_15 = 0i;
  let cw_argument_index_16 = 2i;
  b_state[1i] = f_groundHeight(b_state[cw_argument_index_15], b_state[cw_argument_index_16], v_loc, cw_thread, cw_block, cw_grid);
  b_state[5i] = (b_state[5i] + sqrt((((b_state[0i] - v_oldX) * (b_state[0i] - v_oldX)) + ((b_state[2i] - v_oldZ) * (b_state[2i] - v_oldZ)))));
  let cw_argument_index_17 = 3i;
  if ((abs(b_state[cw_argument_index_17]) > 0.03f)) {
    var cw_tmp_18: i32;
    if ((b_state[3i] > f32(0i))) {
      cw_tmp_18 = 1i;
    } else {
      cw_tmp_18 = (-1i);
    }
    b_state[6i] = f32(cw_tmp_18);
  }
  b_state[15i] = (b_state[15i] + v_t);
  b_state[10i] = (f_fractf(cw_divide_f32((b_state[10i] + (v_t * cw_params.p_clockRate)), 24.0f), cw_thread, cw_block, cw_grid) * 24.0f);
  let cw_argument_index_19 = 8i;
  var v_mask: i32 = i32(b_state[cw_argument_index_19]);
  var cw_tmp_20: f32;
  if ((v_loc == 0i)) {
    cw_tmp_20 = 72.0f;
  } else {
    cw_tmp_20 = 70.0f;
  }
  var v_tx: f32 = cw_tmp_20;
  var cw_tmp_21: f32;
  if ((v_loc == 0i)) {
    cw_tmp_21 = 19.72f;
  } else {
    cw_tmp_21 = 20.15f;
  }
  var v_tz: f32 = cw_tmp_21;
  var v_distance: f32 = sqrt((((b_state[0i] - v_tx) * (b_state[0i] - v_tx)) + ((b_state[2i] - v_tz) * (b_state[2i] - v_tz))));
  b_state[19i] = v_distance;
  let cw_argument_index_22 = 9i;
  if ((i32(b_state[cw_argument_index_22]) == 1i)) {
    if (((v_distance <= f32(5i)) && ((v_loc == 0i) || ((v_mask & 1i) != 0i)))) {
      var cw_tmp_23: i32;
      if ((v_loc == 0i)) {
        cw_tmp_23 = 1i;
      } else {
        cw_tmp_23 = 2i;
      }
      v_mask = (v_mask | cw_tmp_23);
      b_state[8i] = f32(v_mask);
    }
    if (((((cw_params.p_interact != 0i) && (v_loc == 0i)) && (b_state[0i] >= 91.2f)) && ((v_mask & 1i) != 0i))) {
      b_state[7i] = f32(1i);
      b_state[0i] = f32((-89i));
      b_state[2i] = 20.92f;
      b_state[16i] = f32(1i);
      b_state[18i] = f32(1i);
    } else {
      if (((((cw_params.p_interact != 0i) && (v_loc == 1i)) && (b_state[0i] <= (-91.2f))) && ((v_mask & 2i) != 0i))) {
        b_state[7i] = f32(0i);
        b_state[0i] = f32(89i);
        b_state[2i] = 19.28f;
        b_state[6i] = f32((-1i));
        b_state[17i] = f32(1i);
        b_state[18i] = f32(1i);
      }
    }
  }
  if ((b_state[18i] > f32(0i))) {
    b_state[3i] = f32(0i);
    b_state[4i] = f32(0i);
    let cw_argument_index_24 = 0i;
    let cw_argument_index_25 = 2i;
    let cw_argument_index_26 = 7i;
    b_state[1i] = f_groundHeight(b_state[cw_argument_index_24], b_state[cw_argument_index_25], i32(b_state[cw_argument_index_26]), cw_thread, cw_block, cw_grid);
    b_state[11i] = b_state[0i];
    b_state[12i] = b_state[2i];
    b_state[13i] = b_state[0i];
    b_state[14i] = b_state[2i];
  }
  let cw_argument_index_27 = 11i;
  b_state[11i] = f_mixf(b_state[cw_argument_index_27], (b_state[0i] + (b_state[3i] * 0.16f)), (f32(1i) - exp(((-v_t) * 6.4f))), cw_thread, cw_block, cw_grid);
  let cw_argument_index_28 = 12i;
  b_state[12i] = f_mixf(b_state[cw_argument_index_28], (b_state[2i] + (b_state[4i] * 0.12f)), (f32(1i) - exp(((-v_t) * 6.4f))), cw_thread, cw_block, cw_grid);
}
