// CUDA WebShader 0.1.1. Generated from kernel generateScene.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read_write> b_objects: array<vec4<f32>>;
struct CWParams {
  p_location: i32,
  p_masterSeed: u32,
  cw_pad_8: u32,
  cw_pad_12: u32,
}
@group(0) @binding(1) var<uniform> cw_params: CWParams;
const cw_block_size: vec3<u32> = vec3<u32>(64u, 1u, 1u);

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

fn f_v3(cw_arg_x: f32, cw_arg_y: f32, cw_arg_z: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_x: f32 = cw_arg_x;
  var v_y: f32 = cw_arg_y;
  var v_z: f32 = cw_arg_z;
  return vec3<f32>(v_x, v_y, v_z);
}

fn f_v4(cw_arg_a: vec3<f32>, cw_arg_w: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec4<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  var v_w: f32 = cw_arg_w;
  return vec4<f32>(v_a.x, v_a.y, v_a.z, v_w);
}
fn f_dot3(cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  return (((v_a.x * v_b.x) + (v_a.y * v_b.y)) + (v_a.z * v_b.z));
}

fn f_len3(cw_arg_a: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_a: vec3<f32> = cw_arg_a;
  return sqrt(f_dot3(v_a, v_a, cw_thread, cw_block, cw_grid));
}
fn f_unit(cw_arg_a: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  return (v_a / vec3<f32>(sqrt(max(1e-16f, f_dot3(v_a, v_a, cw_thread, cw_block, cw_grid)))));
}



fn f_mix3(cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_arg_t: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  var v_t: f32 = cw_arg_t;
  return (v_a + ((v_b - v_a) * vec3<f32>(v_t)));
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




fn f_treeForm(cw_arg_seed: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> i32 {
  var v_seed: u32 = cw_arg_seed;
  return i32((f_rnd((v_seed + 89u), cw_thread, cw_block, cw_grid) * 4.0f));
}
fn f_trunkPoint(cw_arg_root: vec3<f32>, cw_arg_height: f32, cw_arg_lean: f32, cw_arg_phase: f32, cw_arg_t: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_root: vec3<f32> = cw_arg_root;
  var v_height: f32 = cw_arg_height;
  var v_lean: f32 = cw_arg_lean;
  var v_phase: f32 = cw_arg_phase;
  var v_t: f32 = cw_arg_t;
  return (v_root + f_v3(((v_lean * v_t) + ((sin(((v_t * 5.0f) + v_phase)) * 0.67f) * v_t)), (v_height * v_t), ((cos(((v_t * 3.4f) + v_phase)) * 0.87f) * v_t), cw_thread, cw_block, cw_grid));
}
fn f_limbPoint(cw_arg_root: vec3<f32>, cw_arg_h: f32, cw_arg_lean: f32, cw_arg_phase: f32, cw_arg_branch: i32, cw_arg_t: f32, cw_arg_seed: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_root: vec3<f32> = cw_arg_root;
  var v_h: f32 = cw_arg_h;
  var v_lean: f32 = cw_arg_lean;
  var v_phase: f32 = cw_arg_phase;
  var v_branch: i32 = cw_arg_branch;
  var v_t: f32 = cw_arg_t;
  var v_seed: u32 = cw_arg_seed;
  var v_form: i32 = f_treeForm(v_seed, cw_thread, cw_block, cw_grid);
  var v_group: i32 = (v_branch / 3i);
  var v_fork: i32 = (v_branch - (v_group * 3i));
  var v_mainAngle: f32 = ((f32(v_group) * 2.399963f) + v_phase);
  var v_angle: f32 = (v_mainAngle + ((f32(v_fork) - f32(1i)) * 0.68f));
  var v_attach: f32 = (0.24f + (f32(v_group) * 0.1f));
  if ((v_form == 0i)) {
    v_attach = (0.48f + (f32(v_branch) * 0.029f));
  }
  if ((v_form == 2i)) {
    v_attach = (0.48f + (f32(v_branch) * 0.036f));
  }
  if ((v_form == 3i)) {
    v_group = (v_branch / 4i);
    v_mainAngle = ((f32(v_group) * 2.14f) + v_phase);
    v_angle = (v_mainAngle + (f32(((v_branch % 4i) - 1i)) * 0.5f));
    v_attach = (0.15f + (f32(v_group) * 0.12f));
  }
  var v_start: vec3<f32> = f_trunkPoint(v_root, v_h, v_lean, v_phase, v_attach, cw_thread, cw_block, cw_grid);
  var v_spread: f32 = ((0.24f + (f_rnd((v_seed + (u32(v_branch) * 67u)), cw_thread, cw_block, cw_grid) * 0.19f)) * v_h);
  if ((v_form == 0i)) {
    v_spread = (v_spread * 0.68f);
  }
  if ((v_form == 1i)) {
    v_spread = (v_spread * 1.15f);
  }
  if ((v_form == 2i)) {
    v_spread = (v_spread * 0.43f);
  }
  if ((v_form == 3i)) {
    v_spread = (v_spread * 0.79f);
  }
  var v_endHeight: f32 = (0.69f + (f_rnd((v_seed + (u32(v_branch) * 313u)), cw_thread, cw_block, cw_grid) * 0.32f));
  if ((v_form == 0i)) {
    v_endHeight = (0.76f + (f_rnd((v_seed + (u32(v_branch) * 313u)), cw_thread, cw_block, cw_grid) * 0.27f));
  }
  if ((v_form == 2i)) {
    v_endHeight = (v_attach + 0.17f);
  }
  v_endHeight = max(v_endHeight, (v_attach + 0.27f));
  var v_end: vec3<f32> = (f_trunkPoint(v_root, v_h, v_lean, v_phase, v_endHeight, cw_thread, cw_block, cw_grid) + f_v3((cos(v_angle) * v_spread), f32(0i), ((sin(v_angle) * v_spread) * 0.72f), cw_thread, cw_block, cw_grid));
  var cw_tmp_2: f32;
  if ((v_form == 1i)) {
    cw_tmp_2 = 0.12f;
  } else {
    cw_tmp_2 = 0.18f;
  }
  var v_junction: vec3<f32> = (f_trunkPoint(v_root, v_h, v_lean, v_phase, (v_attach + cw_tmp_2), cw_thread, cw_block, cw_grid) + f_v3(((cos(v_mainAngle) * v_spread) * 0.42f), f32(0i), ((sin(v_mainAngle) * v_spread) * 0.31f), cw_thread, cw_block, cw_grid));
  var v_p: vec3<f32>;
  if ((v_t < 0.45f)) {
    var v_u: f32 = cw_divide_f32(v_t, 0.45f);
    var v_control: vec3<f32> = (v_start + f_v3(((cos(v_mainAngle) * v_spread) * 0.08f), (v_h * 0.13f), ((sin(v_mainAngle) * v_spread) * 0.06f), cw_thread, cw_block, cw_grid));
    v_p = (((v_start * vec3<f32>(((f32(1i) - v_u) * (f32(1i) - v_u)))) + (v_control * vec3<f32>(((f32(2i) * v_u) * (f32(1i) - v_u))))) + (v_junction * vec3<f32>((v_u * v_u))));
  } else {
    var v_u: f32 = cw_divide_f32((v_t - 0.45f), 0.55f);
    var v_control: vec3<f32> = f_mix3(v_junction, v_end, 0.6f, cw_thread, cw_block, cw_grid);
    v_control.y = f_mixf(v_junction.y, v_end.y, 0.35f, cw_thread, cw_block, cw_grid);
    v_p = (((v_junction * vec3<f32>(((f32(1i) - v_u) * (f32(1i) - v_u)))) + (v_control * vec3<f32>(((f32(2i) * v_u) * (f32(1i) - v_u))))) + (v_end * vec3<f32>((v_u * v_u))));
  }
  v_p.x = (v_p.x + ((sin((v_t * 3.14159265359f)) * sin(v_mainAngle)) * 0.1f));
  return v_p;
}
fn f_twigPoint(cw_arg_root: vec3<f32>, cw_arg_h: f32, cw_arg_lean: f32, cw_arg_phase: f32, cw_arg_branch: i32, cw_arg_twig: i32, cw_arg_t: f32, cw_arg_seed: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_root: vec3<f32> = cw_arg_root;
  var v_h: f32 = cw_arg_h;
  var v_lean: f32 = cw_arg_lean;
  var v_phase: f32 = cw_arg_phase;
  var v_branch: i32 = cw_arg_branch;
  var v_twig: i32 = cw_arg_twig;
  var v_t: f32 = cw_arg_t;
  var v_seed: u32 = cw_arg_seed;
  var v_start: vec3<f32> = f_limbPoint(v_root, v_h, v_lean, v_phase, v_branch, (0.6f + (f32(v_twig) * 0.05f)), v_seed, cw_thread, cw_block, cw_grid);
  var v_angle: f32 = (((f32(v_branch) * 2.399963f) + v_phase) + (f32(v_twig) * 1.83f));
  var v_length: f32 = (v_h * (0.1f + (0.06f * f_rnd((v_seed + (u32(((v_branch * 71i) + v_twig)) * 11u)), cw_thread, cw_block, cw_grid))));
  if ((f_treeForm(v_seed, cw_thread, cw_block, cw_grid) == 2i)) {
    v_length = (v_length * 0.57f);
  }
  return (v_start + (f_v3((cos(v_angle) * v_length), (((sin((f32(v_twig) * 2.7f)) * v_length) * 0.32f) + (v_length * 0.33f)), ((sin(v_angle) * v_length) * 0.76f), cw_thread, cw_block, cw_grid) * vec3<f32>(v_t)));
}
fn f_fernCurve(cw_arg_root: vec3<f32>, cw_arg_angle: f32, cw_arg_length: f32, cw_arg_t: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_root: vec3<f32> = cw_arg_root;
  var v_angle: f32 = cw_arg_angle;
  var v_length: f32 = cw_arg_length;
  var v_t: f32 = cw_arg_t;
  return (v_root + f_v3(((cos(v_angle) * v_length) * v_t), ((v_length * ((2.0f * v_t) - ((1.55f * v_t) * v_t))) + 0.035f), ((sin(v_angle) * v_length) * v_t), cw_thread, cw_block, cw_grid));
}














fn f_cw_buffer_helper_0(cw_buffer_arg_0: i32, cw_arg_id: i32, cw_arg_location: i32, cw_arg_masterSeed: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_id: i32 = cw_arg_id;
  var v_location: i32 = cw_arg_location;
  var v_masterSeed: u32 = cw_arg_masterSeed;
  var v_index: i32 = ((v_id - 262144i) / 512i);
  var v_slot: i32 = ((v_id - 262144i) - (v_index * 512i));
  var v_col: i32 = (v_index / 8i);
  var v_row: i32 = (v_index - (v_col * 8i));
  var v_seed: u32 = f_hashU(((((u32(v_index) * 9973u) + v_masterSeed) + (u32(v_location) * 31033u)) + 71471u), cw_thread, cw_block, cw_grid);
  var v_form: i32 = f_treeForm(v_seed, cw_thread, cw_block, cw_grid);
  var v_x: f32 = (((f32(v_col) - 31.5f) * 4.0f) + ((f_rnd((v_seed + 1u), cw_thread, cw_block, cw_grid) - 0.5f) * 3.3f));
  var v_z: f32 = ((33.0f + (f32(v_row) * 8.3f)) + ((f_rnd((v_seed + 2u), cw_thread, cw_block, cw_grid) - 0.5f) * 5.7f));
  var v_height: f32 = (12.0f + (f_rnd((v_seed + 3u), cw_thread, cw_block, cw_grid) * 13.0f));
  if ((v_form == 2i)) {
    v_height = (v_height * 0.71f);
  }
  var v_phase: f32 = (f_rnd((v_seed + 4u), cw_thread, cw_block, cw_grid) * 6.28318530718f);
  var cw_tmp_12: f32;
  if ((v_form == 1i)) {
    cw_tmp_12 = 5.5f;
  } else {
    cw_tmp_12 = 3.0f;
  }
  var v_lean: f32 = ((f_rnd((v_seed + 5u), cw_thread, cw_block, cw_grid) - 0.5f) * cw_tmp_12);
  var v_root: vec3<f32> = f_v3(v_x, (f_groundHeight(v_x, v_z, v_location, cw_thread, cw_block, cw_grid) - 0.1f), v_z, cw_thread, cw_block, cw_grid);
  var cw_tmp_13: f32;
  if ((v_form == 2i)) {
    cw_tmp_13 = 0.57f;
  } else {
    cw_tmp_13 = 1.0f;
  }
  var v_radius: f32 = ((0.1f + (v_height * 0.009f)) * cw_tmp_13);
  var v_bark: vec3<f32> = f_mix3(f_v3(0.28f, 0.24f, 0.16f, cw_thread, cw_block, cw_grid), f_v3(0.61f, 0.59f, 0.47f, cw_thread, cw_block, cw_grid), f_rnd((v_seed + 6u), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  if ((v_form == 3i)) {
    v_bark = v_bark * vec3<f32>(0.5f);
  }
  var v_green: vec3<f32> = f_mix3(f_v3(0.19f, 0.22f, 0.09f, cw_thread, cw_block, cw_grid), f_v3(0.35f, 0.34f, 0.155f, cw_thread, cw_block, cw_grid), f_rnd((v_seed + 7u), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  if ((v_slot < 16i)) {
    var v_a: f32 = cw_divide_f32(f32(v_slot), f32(16i));
    var v_b: f32 = cw_divide_f32(f32((v_slot + 1i)), f32(16i));
    var cw_tmp_14: f32;
    if (((v_form == 1i) || (v_form == 3i))) {
      cw_tmp_14 = 0.69f;
    } else {
      cw_tmp_14 = 0.94f;
    }
    var v_top: f32 = cw_tmp_14;
    f_cw_buffer_helper_1((cw_buffer_offset_0 + 0i), v_id, f_trunkPoint(v_root, v_height, v_lean, v_phase, (v_a * v_top), cw_thread, cw_block, cw_grid), f_trunkPoint(v_root, v_height, v_lean, v_phase, (v_b * v_top), cw_thread, cw_block, cw_grid), ((v_radius * cw_pow_f32((f32(1i) - v_a), 0.8f)) + 0.01f), ((v_radius * cw_pow_f32((f32(1i) - v_b), 0.8f)) + 0.01f), v_bark, cw_thread, cw_block, cw_grid);
  } else {
    if ((v_slot < 48i)) {
      var v_branch: i32 = ((v_slot - 16i) / 4i);
      var v_seg: i32 = ((v_slot - 16i) - (v_branch * 4i));
      var v_a: f32 = cw_divide_f32(f32(v_seg), f32(4i));
      var v_b: f32 = cw_divide_f32(f32((v_seg + 1i)), f32(4i));
      f_cw_buffer_helper_1((cw_buffer_offset_0 + 0i), v_id, f_limbPoint(v_root, v_height, v_lean, v_phase, v_branch, v_a, v_seed, cw_thread, cw_block, cw_grid), f_limbPoint(v_root, v_height, v_lean, v_phase, v_branch, v_b, v_seed, cw_thread, cw_block, cw_grid), (v_radius * (0.6f - (0.5f * v_a))), (v_radius * (0.6f - (0.5f * v_b))), v_bark, cw_thread, cw_block, cw_grid);
    } else {
      if ((v_slot < 80i)) {
        var v_branch: i32 = ((v_slot - 48i) / 4i);
        var v_twig: i32 = ((v_slot - 48i) - (v_branch * 4i));
        f_cw_buffer_helper_1((cw_buffer_offset_0 + 0i), v_id, f_twigPoint(v_root, v_height, v_lean, v_phase, v_branch, (v_twig * 2i), f32(0i), v_seed, cw_thread, cw_block, cw_grid), f_twigPoint(v_root, v_height, v_lean, v_phase, v_branch, (v_twig * 2i), f32(1i), v_seed, cw_thread, cw_block, cw_grid), 0.024f, 0.01f, v_bark, cw_thread, cw_block, cw_grid);
      } else {
        var v_n: i32 = (v_slot - 80i);
        var v_branch: i32 = (v_n / 54i);
        var v_twig: i32 = ((v_n - (v_branch * 54i)) / 14i);
        var v_ls: u32 = f_hashU((v_seed + (u32(v_n) * 881u)), cw_thread, cw_block, cw_grid);
        var v_t: f32 = (0.38f + (f_rnd((v_ls + 9u), cw_thread, cw_block, cw_grid) * 0.77f));
        var v_p: vec3<f32> = f_twigPoint(v_root, v_height, v_lean, v_phase, v_branch, (v_twig * 2i), v_t, v_seed, cw_thread, cw_block, cw_grid);
        var v_angle: f32 = (f_rnd((v_ls + 1u), cw_thread, cw_block, cw_grid) * 6.28318530718f);
        var v_length: f32 = ((0.21f + (f_rnd((v_ls + 2u), cw_thread, cw_block, cw_grid) * 0.28f)) * (1.0f + (f32(v_row) * 0.08f)));
        var v_axis: vec3<f32> = f_unit(f_v3((cos(v_angle) * 0.5f), ((-0.45f) - (f_rnd((v_ls + 3u), cw_thread, cw_block, cw_grid) * 0.65f)), (sin(v_angle) * 0.5f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
        v_p = v_p + f_v3(((f_rnd((v_ls + 4u), cw_thread, cw_block, cw_grid) - 0.5f) * 1.45f), ((f_rnd((v_ls + 5u), cw_thread, cw_block, cw_grid) - 0.5f) * 0.85f), ((f_rnd((v_ls + 6u), cw_thread, cw_block, cw_grid) - 0.5f) * 1.45f), cw_thread, cw_block, cw_grid);
        f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), v_id, v_p, f_v3((v_length * 0.26f), v_length, 0.015f, cw_thread, cw_block, cw_grid), v_axis, (v_green * vec3<f32>((0.67f + (f_rnd((v_ls + 7u), cw_thread, cw_block, cw_grid) * 0.48f)))), 2i, cw_thread, cw_block, cw_grid);
      }
    }
  }
}
fn f_cw_buffer_helper_1(cw_buffer_arg_0: i32, cw_arg_id: i32, cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_arg_r0: f32, cw_arg_r1: f32, cw_arg_colour: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_id: i32 = cw_arg_id;
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  var v_r0: f32 = cw_arg_r0;
  var v_r1: f32 = cw_arg_r1;
  var v_colour: vec3<f32> = cw_arg_colour;
  f_cw_buffer_helper_4((cw_buffer_offset_0 + 0i), v_id, v_a, v_b, v_r0, v_colour, 1i, cw_thread, cw_block, cw_grid);
  b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 1i))] = f_v4(v_b, v_r1, cw_thread, cw_block, cw_grid);
}
fn f_cw_buffer_helper_2(cw_buffer_arg_0: i32, cw_arg_id: i32, cw_arg_centre: vec3<f32>, cw_arg_radii: vec3<f32>, cw_arg_axis: vec3<f32>, cw_arg_colour: vec3<f32>, cw_arg_mat: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_id: i32 = cw_arg_id;
  var v_centre: vec3<f32> = cw_arg_centre;
  var v_radii: vec3<f32> = cw_arg_radii;
  var v_axis: vec3<f32> = cw_arg_axis;
  var v_colour: vec3<f32> = cw_arg_colour;
  var v_mat: i32 = cw_arg_mat;
  b_objects[(cw_buffer_offset_0 + (v_id * 4i))] = f_v4(v_centre, f32(0i), cw_thread, cw_block, cw_grid);
  var cw_tmp_15: f32;
  if (((v_mat == 2i) || (v_mat == 3i))) {
    cw_tmp_15 = (f_rnd((u32(v_id) * 17171u), cw_thread, cw_block, cw_grid) * 6.28318530718f);
  } else {
    cw_tmp_15 = 0.0f;
  }
  b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 1i))] = f_v4(v_radii, cw_tmp_15, cw_thread, cw_block, cw_grid);
  b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 2i))] = f_v4(v_colour, f32(v_mat), cw_thread, cw_block, cw_grid);
  b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 3i))] = f_v4(f_unit(v_axis, cw_thread, cw_block, cw_grid), f32(0i), cw_thread, cw_block, cw_grid);
}
fn f_cw_buffer_helper_3(cw_buffer_arg_0: i32, cw_arg_id: i32, cw_arg_slot: i32, cw_arg_cellX: f32, cw_arg_row: i32, cw_arg_loc: i32, cw_arg_seed: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_id: i32 = cw_arg_id;
  var v_slot: i32 = cw_arg_slot;
  var v_cellX: f32 = cw_arg_cellX;
  var v_row: i32 = cw_arg_row;
  var v_loc: i32 = cw_arg_loc;
  var v_seed: u32 = cw_arg_seed;
  if ((v_slot < 288i)) {
    var v_plant: i32 = (v_slot / 144i);
    var v_part: i32 = (v_slot - (v_plant * 144i));
    var v_frond: i32 = (v_part / 24i);
    var v_pinna: i32 = (v_part - (v_frond * 24i));
    var v_fs: u32 = f_hashU(((v_seed + 881u) + (u32(v_plant) * 3719u)), cw_thread, cw_block, cw_grid);
    var v_fx: f32 = (v_cellX + ((f_rnd(v_fs, cw_thread, cw_block, cw_grid) - 0.5f) * 6.7f));
    var v_fz: f32 = ((f_shore(v_fx, v_loc, cw_thread, cw_block, cw_grid) + 3.1f) + (f_rnd((v_fs + 1u), cw_thread, cw_block, cw_grid) * 5.0f));
    if ((v_row > 0i)) {
      v_fz = ((20.7f + (f32((v_row - 1i)) * 4.5f)) + (f_rnd((v_fs + 1u), cw_thread, cw_block, cw_grid) * 3.7f));
    }
    var v_root: vec3<f32> = f_v3(v_fx, f_groundHeight(v_fx, v_fz, v_loc, cw_thread, cw_block, cw_grid), v_fz, cw_thread, cw_block, cw_grid);
    var v_length: f32 = ((0.85f + (f_rnd((v_fs + 2u), cw_thread, cw_block, cw_grid) * 0.8f)) * (0.79f + (f_rnd((v_fs + (u32(v_frond) * 53u)), cw_thread, cw_block, cw_grid) * 0.3f)));
    var v_angle: f32 = ((f32(v_frond) * 2.399963f) + (f_rnd((v_fs + 3u), cw_thread, cw_block, cw_grid) * 6.28318530718f));
    var v_direction: vec3<f32> = f_v3(cos(v_angle), f32(0i), sin(v_angle), cw_thread, cw_block, cw_grid);
    var v_side: vec3<f32> = f_v3((-sin(v_angle)), f32(0i), cos(v_angle), cw_thread, cw_block, cw_grid);
    var v_green: vec3<f32> = f_mix3(f_v3(0.065f, 0.16f, 0.03f, cw_thread, cw_block, cw_grid), f_v3(0.19f, 0.3f, 0.064f, cw_thread, cw_block, cw_grid), f_rnd((v_fs + 4u), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
    if ((v_pinna < 4i)) {
      var v_a: f32 = (f32(v_pinna) * 0.25f);
      var v_b: f32 = (f32((v_pinna + 1i)) * 0.25f);
      f_cw_buffer_helper_4((cw_buffer_offset_0 + 0i), v_id, f_fernCurve(v_root, v_angle, v_length, v_a, cw_thread, cw_block, cw_grid), f_fernCurve(v_root, v_angle, v_length, v_b, cw_thread, cw_block, cw_grid), ((0.008f * (f32(1i) - v_a)) + 0.002f), (v_green * vec3<f32>(0.65f)), 3i, cw_thread, cw_block, cw_grid);
    } else {
      var v_pair: i32 = ((v_pinna - 4i) / 2i);
      var cw_tmp_16: f32;
      if (((v_pinna % 2i) == 0i)) {
        cw_tmp_16 = 1.0f;
      } else {
        cw_tmp_16 = (-1.0f);
      }
      var v_sign: f32 = cw_tmp_16;
      var v_t: f32 = (0.16f + (f32(v_pair) * 0.084f));
      var v_leafLength: f32 = ((v_length * (0.075f + (0.18f * cw_pow_f32(sin((v_t * 3.14159265359f)), 0.7f)))) * (f32(1i) - (v_t * 0.52f)));
      var v_axis: vec3<f32> = f_unit((((v_side * vec3<f32>(v_sign)) + (v_direction * vec3<f32>(0.42f))) + f_v3(f32(0i), (0.18f - (v_t * 0.36f)), f32(0i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid);
      var v_p: vec3<f32> = (f_fernCurve(v_root, v_angle, v_length, v_t, cw_thread, cw_block, cw_grid) + ((v_axis * vec3<f32>(v_leafLength)) * vec3<f32>(0.71f)));
      var cw_tmp_17: f32;
      if ((v_plant == 0i)) {
        cw_tmp_17 = 0.21f;
      } else {
        cw_tmp_17 = 0.31f;
      }
      f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), v_id, v_p, f_v3((v_leafLength * cw_tmp_17), v_leafLength, 0.005f, cw_thread, cw_block, cw_grid), v_axis, (v_green * vec3<f32>((0.8f + (0.26f * f_rnd((v_fs + (u32(v_part) * 113u)), cw_thread, cw_block, cw_grid))))), 8i, cw_thread, cw_block, cw_grid);
    }
  } else {
    if ((v_slot < 352i)) {
      var v_patch: i32 = ((v_slot - 288i) / 16i);
      var v_blade: i32 = (((v_slot - 288i) % 16i) / 2i);
      var v_segment: i32 = (v_slot % 2i);
      var v_ps: u32 = f_hashU(((v_seed + (u32(v_patch) * 7121u)) + 51u), cw_thread, cw_block, cw_grid);
      var v_kind: i32 = i32((f_rnd((v_ps + 8u), cw_thread, cw_block, cw_grid) * 3.0f));
      var v_px: f32 = (v_cellX + ((f_rnd(v_ps, cw_thread, cw_block, cw_grid) - 0.5f) * 8.0f));
      var v_pz: f32 = ((f_shore(v_px, v_loc, cw_thread, cw_block, cw_grid) + 2.4f) + (f_rnd((v_ps + 1u), cw_thread, cw_block, cw_grid) * 6.8f));
      if ((v_row > 0i)) {
        v_pz = ((23.0f + (f32(v_row) * 4.0f)) + (f_rnd((v_ps + 1u), cw_thread, cw_block, cw_grid) * f32(5i)));
      }
      var v_h: f32 = (0.42f + (f_rnd((v_ps + 2u), cw_thread, cw_block, cw_grid) * 0.66f));
      var v_angle: f32 = ((f32(v_blade) * 2.399963f) + (f_rnd((v_ps + 3u), cw_thread, cw_block, cw_grid) * 6.28318530718f));
      var v_root: vec3<f32> = f_v3(v_px, f_groundHeight(v_px, v_pz, v_loc, cw_thread, cw_block, cw_grid), v_pz, cw_thread, cw_block, cw_grid);
      var cw_tmp_19: f32;
      if ((v_kind == 0i)) {
        cw_tmp_19 = 0.7f;
      } else {
        var cw_tmp_18: f32;
        if ((v_kind == 1i)) {
          cw_tmp_18 = 0.31f;
        } else {
          cw_tmp_18 = 0.55f;
        }
        cw_tmp_19 = cw_tmp_18;
      }
      var v_spread: f32 = cw_tmp_19;
      var v_a: f32 = (f32(v_segment) * 0.5f);
      var v_b: f32 = (f32((v_segment + 1i)) * 0.5f);
      var v_pa: vec3<f32> = (v_root + f_v3(((((cos(v_angle) * v_h) * v_a) * v_a) * v_spread), ((v_h * v_a) * (f32(1i) - (v_a * 0.26f))), ((((sin(v_angle) * v_h) * v_a) * v_a) * v_spread), cw_thread, cw_block, cw_grid));
      var v_pb: vec3<f32> = (v_root + f_v3(((((cos(v_angle) * v_h) * v_b) * v_b) * v_spread), ((v_h * v_b) * (f32(1i) - (v_b * 0.26f))), ((((sin(v_angle) * v_h) * v_b) * v_b) * v_spread), cw_thread, cw_block, cw_grid));
      var v_colour: vec3<f32> = f_mix3(f_v3(0.15f, 0.22f, 0.055f, cw_thread, cw_block, cw_grid), f_v3(0.39f, 0.3f, 0.12f, cw_thread, cw_block, cw_grid), f_rnd((v_ps + 4u), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
      if ((((v_kind == 2i) && (v_segment == 1i)) && ((v_blade % 2i) == 0i))) {
        f_cw_buffer_helper_4((cw_buffer_offset_0 + 0i), v_id, v_pa, v_pb, 0.025f, f_v3(0.43f, 0.31f, 0.055f, cw_thread, cw_block, cw_grid), 3i, cw_thread, cw_block, cw_grid);
      } else {
        var cw_tmp_20: f32;
        if ((v_kind == 1i)) {
          cw_tmp_20 = 0.014f;
        } else {
          cw_tmp_20 = 0.025f;
        }
        f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), v_id, ((v_pa + v_pb) * vec3<f32>(0.5f)), f_v3(cw_tmp_20, (f_len3((v_pb - v_pa), cw_thread, cw_block, cw_grid) * 0.58f), 0.004f, cw_thread, cw_block, cw_grid), f_unit((v_pb - v_pa), cw_thread, cw_block, cw_grid), v_colour, 3i, cw_thread, cw_block, cw_grid);
      }
    } else {
      if ((v_slot < 368i)) {
        var v_rs: u32 = f_hashU((v_seed + (u32(v_slot) * 3149u)), cw_thread, cw_block, cw_grid);
        var v_rx: f32 = (v_cellX + ((f_rnd(v_rs, cw_thread, cw_block, cw_grid) - 0.5f) * f32(8i)));
        var v_rz: f32 = (f_shore(v_rx, v_loc, cw_thread, cw_block, cw_grid) + ((f_rnd((v_rs + 1u), cw_thread, cw_block, cw_grid) - 0.3f) * 8.0f));
        if ((v_row > 0i)) {
          v_rz = ((34.0f + (f32(v_row) * 7.0f)) + (f_rnd((v_rs + 1u), cw_thread, cw_block, cw_grid) * f32(28i)));
        }
        var v_size: f32 = (0.1f + (cw_pow_f32(f_rnd((v_rs + 2u), cw_thread, cw_block, cw_grid), 4.0f) * 0.95f));
        var v_form: i32 = i32((f_rnd((v_rs + 10u), cw_thread, cw_block, cw_grid) * 4.0f));
        var v_radii: vec3<f32> = f_v3(v_size, (v_size * 0.6f), (v_size * 0.77f), cw_thread, cw_block, cw_grid);
        if ((v_form == 0i)) {
          v_radii = f_v3((v_size * (1.35f + (f_rnd((v_rs + 11u), cw_thread, cw_block, cw_grid) * 0.45f))), (v_size * (0.2f + (f_rnd((v_rs + 3u), cw_thread, cw_block, cw_grid) * 0.12f))), (v_size * (0.69f + (f_rnd((v_rs + 7u), cw_thread, cw_block, cw_grid) * 0.45f))), cw_thread, cw_block, cw_grid);
        }
        if ((v_form == 1i)) {
          v_radii = f_v3((v_size * (1.15f + (f_rnd((v_rs + 11u), cw_thread, cw_block, cw_grid) * 0.35f))), (v_size * (0.48f + (f_rnd((v_rs + 3u), cw_thread, cw_block, cw_grid) * 0.3f))), (v_size * (0.48f + (f_rnd((v_rs + 7u), cw_thread, cw_block, cw_grid) * 0.35f))), cw_thread, cw_block, cw_grid);
        }
        if ((v_form == 2i)) {
          v_radii = f_v3((v_size * (0.88f + (f_rnd((v_rs + 11u), cw_thread, cw_block, cw_grid) * 0.32f))), (v_size * (0.63f + (f_rnd((v_rs + 3u), cw_thread, cw_block, cw_grid) * 0.4f))), (v_size * (0.72f + (f_rnd((v_rs + 7u), cw_thread, cw_block, cw_grid) * 0.37f))), cw_thread, cw_block, cw_grid);
        }
        if ((v_form == 3i)) {
          v_radii = f_v3((v_size * (1.55f + (f_rnd((v_rs + 11u), cw_thread, cw_block, cw_grid) * 0.5f))), (v_size * (0.31f + (f_rnd((v_rs + 3u), cw_thread, cw_block, cw_grid) * 0.32f))), (v_size * (0.34f + (f_rnd((v_rs + 7u), cw_thread, cw_block, cw_grid) * 0.26f))), cw_thread, cw_block, cw_grid);
        }
        var v_axis: vec3<f32> = f_unit(f_v3(((f_rnd((v_rs + 5u), cw_thread, cw_block, cw_grid) - 0.5f) * 0.53f), f32(1i), ((f_rnd((v_rs + 6u), cw_thread, cw_block, cw_grid) - 0.5f) * 0.43f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
        f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), v_id, f_v3(v_rx, (f_groundHeight(v_rx, v_rz, v_loc, cw_thread, cw_block, cw_grid) - (v_radii.y * 0.14f)), v_rz, cw_thread, cw_block, cw_grid), v_radii, v_axis, (f_v3(0.43f, 0.33f, 0.22f, cw_thread, cw_block, cw_grid) * vec3<f32>((0.76f + (0.5f * f_rnd((v_rs + 4u), cw_thread, cw_block, cw_grid))))), 4i, cw_thread, cw_block, cw_grid);
        b_objects[(cw_buffer_offset_0 + (v_id * 4i))].w = f32(v_form);
        b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 1i))].w = (f_rnd((v_rs + 9u), cw_thread, cw_block, cw_grid) * 6.28318530718f);
      } else {
        var v_bs: u32 = f_hashU((v_seed + (u32(v_slot) * 1669u)), cw_thread, cw_block, cw_grid);
        var v_lx: f32 = (v_cellX + ((f_rnd(v_bs, cw_thread, cw_block, cw_grid) - 0.5f) * f32(8i)));
        var v_lz: f32 = ((f_shore(v_lx, v_loc, cw_thread, cw_block, cw_grid) + 3.0f) + (f_rnd((v_bs + 1u), cw_thread, cw_block, cw_grid) * 8.0f));
        var v_angle: f32 = (f_rnd((v_bs + 2u), cw_thread, cw_block, cw_grid) * 6.28318530718f);
        var v_p: vec3<f32> = f_v3(v_lx, (f_groundHeight(v_lx, v_lz, v_loc, cw_thread, cw_block, cw_grid) + 0.017f), v_lz, cw_thread, cw_block, cw_grid);
        f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), v_id, v_p, f_v3(0.028f, (0.11f + (f_rnd((v_bs + 3u), cw_thread, cw_block, cw_grid) * 0.13f)), 0.005f, cw_thread, cw_block, cw_grid), f_unit(f_v3(cos(v_angle), 0.04f, sin(v_angle), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid), (f_v3(0.19f, 0.11f, 0.045f, cw_thread, cw_block, cw_grid) * vec3<f32>((0.6f + f_rnd((v_bs + 4u), cw_thread, cw_block, cw_grid)))), 3i, cw_thread, cw_block, cw_grid);
      }
    }
  }
}
fn f_cw_buffer_helper_4(cw_buffer_arg_0: i32, cw_arg_id: i32, cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_arg_r: f32, cw_arg_colour: vec3<f32>, cw_arg_mat: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_id: i32 = cw_arg_id;
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  var v_r: f32 = cw_arg_r;
  var v_colour: vec3<f32> = cw_arg_colour;
  var v_mat: i32 = cw_arg_mat;
  b_objects[(cw_buffer_offset_0 + (v_id * 4i))] = f_v4(v_a, v_r, cw_thread, cw_block, cw_grid);
  b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 1i))] = f_v4(v_b, v_r, cw_thread, cw_block, cw_grid);
  b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 2i))] = f_v4(v_colour, f32(v_mat), cw_thread, cw_block, cw_grid);
  b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 3i))] = vec4<f32>(f32(0i), f32(1i), f32(0i), f32(1i));
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

@compute @workgroup_size(64, 1, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  var v_id: i32 = i32(((cw_block.x * cw_block_size.x) + cw_thread.x));
  if ((v_id >= 524288i)) {
    return;
  }
  if ((v_id >= 262144i)) {
    f_cw_buffer_helper_0(0i, v_id, cw_params.p_location, cw_params.p_masterSeed, cw_thread, cw_block, cw_grid);
    return;
  }
  var v_cell: i32 = (v_id / 2048i);
  var v_slot: i32 = (v_id - (v_cell * 2048i));
  var v_col: i32 = (v_cell / 4i);
  var v_row: i32 = (v_cell - (v_col * 4i));
  var v_seed: u32 = f_hashU((((u32(v_cell) * 7213u) + cw_params.p_masterSeed) + (u32(cw_params.p_location) * 7919u)), cw_thread, cw_block, cw_grid);
  var v_form: i32 = f_treeForm(v_seed, cw_thread, cw_block, cw_grid);
  var v_cellX: f32 = ((f32(v_col) - 15.5f) * 8.0f);
  var v_x: f32 = (v_cellX + ((f_rnd((v_seed + 1u), cw_thread, cw_block, cw_grid) - 0.5f) * 5.6f));
  var v_z: f32 = ((27.2f + (f32(v_row) * 10.5f)) + ((f_rnd((v_seed + 2u), cw_thread, cw_block, cw_grid) - 0.5f) * 6.5f));
  if ((v_row >= 2i)) {
    v_z = (v_z + (f32((v_row - 1i)) * 9.0f));
  }
  var v_root: vec3<f32> = f_v3(v_x, (f_groundHeight(v_x, v_z, cw_params.p_location, cw_thread, cw_block, cw_grid) - 0.08f), v_z, cw_thread, cw_block, cw_grid);
  var v_height: f32 = ((11.0f + (f_rnd((v_seed + 3u), cw_thread, cw_block, cw_grid) * 10.0f)) + (f32(v_row) * 0.5f));
  if ((v_form == 0i)) {
    v_height = (v_height * 1.12f);
  }
  if ((v_form == 1i)) {
    v_height = (v_height * 0.85f);
  }
  if ((v_form == 2i)) {
    v_height = (v_height * 0.65f);
  }
  var v_phase: f32 = (f_rnd((v_seed + 4u), cw_thread, cw_block, cw_grid) * 6.28318530718f);
  var cw_tmp_6: f32;
  if ((v_form == 1i)) {
    cw_tmp_6 = 5.6f;
  } else {
    cw_tmp_6 = 2.3f;
  }
  var v_lean: f32 = ((f_rnd((v_seed + 5u), cw_thread, cw_block, cw_grid) - 0.5f) * cw_tmp_6);
  var cw_tmp_8: f32;
  if ((v_form == 1i)) {
    cw_tmp_8 = 1.45f;
  } else {
    var cw_tmp_7: f32;
    if ((v_form == 2i)) {
      cw_tmp_7 = 0.44f;
    } else {
      cw_tmp_7 = 1.0f;
    }
    cw_tmp_8 = cw_tmp_7;
  }
  var v_trunkRadius: f32 = ((0.16f + (v_height * 0.015f)) * cw_tmp_8);
  var v_bark: vec3<f32> = f_mix3(f_v3(0.32f, 0.27f, 0.2f, cw_thread, cw_block, cw_grid), f_v3(0.61f, 0.58f, 0.49f, cw_thread, cw_block, cw_grid), f_rnd((v_seed + 6u), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  if ((f_rnd((v_seed + 8u), cw_thread, cw_block, cw_grid) < 0.22f)) {
    v_bark = f_v3(0.33f, 0.19f, 0.1f, cw_thread, cw_block, cw_grid);
  }
  if ((v_form == 3i)) {
    v_bark = v_bark * vec3<f32>(0.46f);
  }
  var v_green: vec3<f32> = f_mix3(f_v3(0.13f, 0.17f, 0.071f, cw_thread, cw_block, cw_grid), f_v3(0.28f, 0.3f, 0.14f, cw_thread, cw_block, cw_grid), f_rnd((v_seed + 7u), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  if ((v_form == 2i)) {
    v_green = f_mix3(v_green, f_v3(0.25f, 0.31f, 0.21f, cw_thread, cw_block, cw_grid), 0.6f, cw_thread, cw_block, cw_grid);
  }
  if ((v_slot < 24i)) {
    var v_a: f32 = cw_divide_f32(f32(v_slot), 24.0f);
    var v_b: f32 = cw_divide_f32(f32((v_slot + 1i)), 24.0f);
    var cw_tmp_9: f32;
    if (((v_form == 1i) || (v_form == 3i))) {
      cw_tmp_9 = 0.7f;
    } else {
      cw_tmp_9 = 0.94f;
    }
    var v_top: f32 = cw_tmp_9;
    f_cw_buffer_helper_1(0i, v_id, f_trunkPoint(v_root, v_height, v_lean, v_phase, (v_a * v_top), cw_thread, cw_block, cw_grid), f_trunkPoint(v_root, v_height, v_lean, v_phase, (v_b * v_top), cw_thread, cw_block, cw_grid), ((v_trunkRadius * cw_pow_f32((f32(1i) - v_a), 0.8f)) + 0.016f), ((v_trunkRadius * cw_pow_f32((f32(1i) - v_b), 0.8f)) + 0.016f), v_bark, cw_thread, cw_block, cw_grid);
  } else {
    if ((v_slot < 96i)) {
      var v_branch: i32 = ((v_slot - 24i) / 6i);
      var v_seg: i32 = ((v_slot - 24i) - (v_branch * 6i));
      var v_a: f32 = cw_divide_f32(f32(v_seg), 6.0f);
      var v_b: f32 = cw_divide_f32(f32((v_seg + 1i)), 6.0f);
      f_cw_buffer_helper_1(0i, v_id, f_limbPoint(v_root, v_height, v_lean, v_phase, v_branch, v_a, v_seed, cw_thread, cw_block, cw_grid), f_limbPoint(v_root, v_height, v_lean, v_phase, v_branch, v_b, v_seed, cw_thread, cw_block, cw_grid), ((v_trunkRadius * (0.55f - (0.45f * v_a))) * (1.0f - (f32(v_branch) * 0.02f))), ((v_trunkRadius * (0.55f - (0.45f * v_b))) * (1.0f - (f32(v_branch) * 0.02f))), v_bark, cw_thread, cw_block, cw_grid);
    } else {
      if ((v_slot < 288i)) {
        var v_branch: i32 = ((v_slot - 96i) / 16i);
        var v_twig: i32 = (((v_slot - 96i) - (v_branch * 16i)) / 2i);
        var v_seg: i32 = (((v_slot - 96i) - (v_branch * 16i)) - (v_twig * 2i));
        var cw_tmp_10: f32;
        if ((v_seg == 0i)) {
          cw_tmp_10 = 1.0f;
        } else {
          cw_tmp_10 = 0.6f;
        }
        var cw_tmp_11: f32;
        if ((v_seg == 0i)) {
          cw_tmp_11 = 0.6f;
        } else {
          cw_tmp_11 = 0.2f;
        }
        f_cw_buffer_helper_1(0i, v_id, f_twigPoint(v_root, v_height, v_lean, v_phase, v_branch, v_twig, (f32(v_seg) * 0.5f), v_seed, cw_thread, cw_block, cw_grid), f_twigPoint(v_root, v_height, v_lean, v_phase, v_branch, v_twig, (f32((v_seg + 1i)) * 0.5f), v_seed, cw_thread, cw_block, cw_grid), ((0.026f + (v_height * 0.0011f)) * cw_tmp_10), ((0.026f + (v_height * 0.0011f)) * cw_tmp_11), (v_bark * vec3<f32>(0.8f)), cw_thread, cw_block, cw_grid);
      } else {
        if ((v_slot < 1632i)) {
          var v_n: i32 = (v_slot - 288i);
          var v_branch: i32 = (v_n / 112i);
          var v_twig: i32 = ((v_n - (v_branch * 112i)) / 16i);
          var v_ls: u32 = f_hashU((v_seed + (u32(v_n) * 3719u)), cw_thread, cw_block, cw_grid);
          var v_t: f32 = (0.5f + (f_rnd((v_ls + 9u), cw_thread, cw_block, cw_grid) * 0.55f));
          var v_centre: vec3<f32> = f_twigPoint(v_root, v_height, v_lean, v_phase, v_branch, v_twig, v_t, v_seed, cw_thread, cw_block, cw_grid);
          var v_a: f32 = (f_rnd((v_ls + 1u), cw_thread, cw_block, cw_grid) * 6.28318530718f);
          var v_length: f32 = (0.12f + (f_rnd((v_ls + 2u), cw_thread, cw_block, cw_grid) * 0.17f));
          var v_axis: vec3<f32> = f_unit(f_v3((cos(v_a) * 0.45f), ((-0.6f) - (f_rnd((v_ls + 3u), cw_thread, cw_block, cw_grid) * 0.4f)), (sin(v_a) * 0.4f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
          v_centre = v_centre + (((v_axis * vec3<f32>(v_length)) * vec3<f32>(0.65f)) + f_v3(((f_rnd((v_ls + 4u), cw_thread, cw_block, cw_grid) - 0.5f) * 1.05f), ((f_rnd((v_ls + 8u), cw_thread, cw_block, cw_grid) - 0.5f) * 0.55f), ((f_rnd((v_ls + 5u), cw_thread, cw_block, cw_grid) - 0.5f) * 1.05f), cw_thread, cw_block, cw_grid));
          f_cw_buffer_helper_2(0i, v_id, v_centre, f_v3((v_length * 0.16f), v_length, 0.007f, cw_thread, cw_block, cw_grid), v_axis, (v_green * vec3<f32>((0.65f + (f_rnd((v_ls + 6u), cw_thread, cw_block, cw_grid) * 0.55f)))), 2i, cw_thread, cw_block, cw_grid);
        } else {
          f_cw_buffer_helper_3(0i, v_id, (v_slot - 1632i), v_cellX, v_row, cw_params.p_location, v_seed, cw_thread, cw_block, cw_grid);
        }
      }
    }
  }
}
