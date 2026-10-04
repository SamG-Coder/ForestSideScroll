// CUDA WebShader 0.1.1. Generated from kernel tracePaths.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read> b_objects: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read> b_bounds: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read> b_rayGeometry: array<vec4<f32>>;
@group(0) @binding(3) var<storage, read> b_rockPlanes: array<vec4<f32>>;
@group(0) @binding(4) var<storage, read> b_terrain: array<f32>;
@group(0) @binding(5) var<storage, read> b_atlas: array<u32>;
@group(0) @binding(6) var<storage, read> b_state: array<f32>;
@group(0) @binding(7) var<storage, read> b_oldGuide: array<vec4<f32>>;
@group(0) @binding(8) var<storage, read> b_oldNormals: array<vec4<f32>>;
@group(0) @binding(9) var<storage, read> b_oldHistory: array<vec4<f32>>;
@group(0) @binding(10) var<storage, read_write> b_radiance: array<vec4<f32>>;
@group(0) @binding(11) var<storage, read_write> b_guide: array<vec4<f32>>;
@group(0) @binding(12) var<storage, read_write> b_normals: array<vec4<f32>>;
@group(0) @binding(13) var<storage, read_write> b_albedo: array<vec4<f32>>;
struct CWParams {
  p_width: i32,
  p_height: i32,
  p_frame: i32,
  p_bounces: i32,
  p_reuseLighting: i32,
  cw_pad_20: u32,
  cw_pad_24: u32,
  cw_pad_28: u32,
}
@group(0) @binding(14) var<uniform> cw_params: CWParams;
const cw_block_size: vec3<u32> = vec3<u32>(8u, 4u, 1u);

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




fn f_rockIndex(cw_arg_id: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> i32 {
  var v_id: i32 = cw_arg_id;
  return ((((v_id / 2048i) * 16i) + (v_id % 2048i)) - 1984i);
}
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
fn f_xyz(cw_arg_a: vec4<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec4<f32> = cw_arg_a;
  return f_v3(v_a.x, v_a.y, v_a.z, cw_thread, cw_block, cw_grid);
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
fn f_cross3(cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  return f_v3(((v_a.y * v_b.z) - (v_a.z * v_b.y)), ((v_a.z * v_b.x) - (v_a.x * v_b.z)), ((v_a.x * v_b.y) - (v_a.y * v_b.x)), cw_thread, cw_block, cw_grid);
}
fn f_len3(cw_arg_a: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_a: vec3<f32> = cw_arg_a;
  return sqrt(f_dot3(v_a, v_a, cw_thread, cw_block, cw_grid));
}
fn f_unit(cw_arg_a: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  return (v_a / vec3<f32>(sqrt(max(1e-16f, f_dot3(v_a, v_a, cw_thread, cw_block, cw_grid)))));
}
fn f_min3(cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  return f_v3(min(v_a.x, v_b.x), min(v_a.y, v_b.y), min(v_a.z, v_b.z), cw_thread, cw_block, cw_grid);
}
fn f_max3(cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  return f_v3(max(v_a.x, v_b.x), max(v_a.y, v_b.y), max(v_a.z, v_b.z), cw_thread, cw_block, cw_grid);
}
fn f_abs3(cw_arg_a: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  return f_v3(abs(v_a.x), abs(v_a.y), abs(v_a.z), cw_thread, cw_block, cw_grid);
}
fn f_mix3(cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_arg_t: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  var v_t: f32 = cw_arg_t;
  return (v_a + ((v_b - v_a) * vec3<f32>(v_t)));
}
fn f_reflect3(cw_arg_d: vec3<f32>, cw_arg_n: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_d: vec3<f32> = cw_arg_d;
  var v_n: vec3<f32> = cw_arg_n;
  return (v_d - (v_n * vec3<f32>((2.0f * f_dot3(v_d, v_n, cw_thread, cw_block, cw_grid)))));
}
fn f_windOffset(cw_arg_p: vec3<f32>, cw_arg_time: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_p: vec3<f32> = cw_arg_p;
  var v_time: f32 = cw_arg_time;
  var v_phase: f32 = ((v_p.x * 0.31f) + (v_p.z * 0.17f));
  return f_v3(((sin((v_phase + (v_time * 1.5f))) - sin(v_phase)) * 0.045f), ((cos((v_phase + (v_time * 1.1f))) - cos(v_phase)) * 0.008f), ((sin(((v_phase * 1.3f) + (v_time * 1.24f))) - sin((v_phase * 1.3f))) * 0.025f), cw_thread, cw_block, cw_grid);
}
fn f_tangent(cw_arg_n: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_n: vec3<f32> = cw_arg_n;
  var cw_tmp_0: vec3<f32>;
  if ((abs(v_n.y) < 0.95f)) {
    cw_tmp_0 = f_v3(f32(0i), f32(1i), f32(0i), cw_thread, cw_block, cw_grid);
  } else {
    cw_tmp_0 = f_v3(f32(1i), f32(0i), f32(0i), cw_thread, cw_block, cw_grid);
  }
  return f_unit(f_cross3(v_n, cw_tmp_0, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
}
fn f_basisU(cw_arg_axis: vec3<f32>, cw_arg_twist: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_axis: vec3<f32> = cw_arg_axis;
  var v_twist: f32 = cw_arg_twist;
  var v_u: vec3<f32> = f_tangent(v_axis, cw_thread, cw_block, cw_grid);
  return ((v_u * vec3<f32>(cos(v_twist))) + (f_cross3(v_axis, v_u, cw_thread, cw_block, cw_grid) * vec3<f32>(sin(v_twist))));
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

fn f_sunDirection(cw_arg_hour: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_hour: f32 = cw_arg_hour;
  var v_phase: f32 = (cw_divide_f32((v_hour - 6.0f), 12.0f) * 3.14159265359f);
  return f_unit(f_v3(((-cos(v_phase)) * 0.83f), sin(v_phase), (-0.38f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
}
fn f_sunColour(cw_arg_hour: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_hour: f32 = cw_arg_hour;
  var v_y: f32 = f_sunDirection(v_hour, cw_thread, cw_block, cw_grid).y;
  return (f_mix3(f_v3(4.2f, 1.45f, 0.42f, cw_thread, cw_block, cw_grid), f_v3(4.0f, 3.68f, 2.94f, cw_thread, cw_block, cw_grid), f_smoothf(0.04f, 0.65f, v_y, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid) * vec3<f32>(f_smoothf((-0.07f), 0.07f, v_y, cw_thread, cw_block, cw_grid)));
}
fn f_sky(cw_arg_d: vec3<f32>, cw_arg_hour: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_d: vec3<f32> = cw_arg_d;
  var v_hour: f32 = cw_arg_hour;
  var v_day: f32 = f_smoothf((-0.16f), 0.18f, f_sunDirection(v_hour, cw_thread, cw_block, cw_grid).y, cw_thread, cw_block, cw_grid);
  var v_horizon: vec3<f32> = f_mix3(f_v3(0.024f, 0.04f, 0.084f, cw_thread, cw_block, cw_grid), f_v3(0.49f, 0.62f, 0.76f, cw_thread, cw_block, cw_grid), v_day, cw_thread, cw_block, cw_grid);
  var v_zenith: vec3<f32> = f_mix3(f_v3(0.008f, 0.02f, 0.048f, cw_thread, cw_block, cw_grid), f_v3(0.16f, 0.34f, 0.56f, cw_thread, cw_block, cw_grid), v_day, cw_thread, cw_block, cw_grid);
  var v_c: vec3<f32> = f_mix3(v_horizon, v_zenith, f_smoothf((-0.03f), 0.85f, v_d.y, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_glow: f32 = cw_pow_f32(max(0.0f, f_dot3(v_d, f_sunDirection(v_hour, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid)), 32.0f);
  v_c = v_c + ((f_sunColour(v_hour, cw_thread, cw_block, cw_grid) * vec3<f32>(v_glow)) * vec3<f32>(0.035f));
  return v_c;
}








fn f_unpackMaterial(cw_arg_c: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec4<f32> {
  var v_c: u32 = cw_arg_c;
  return (vec4<f32>(f32((v_c & 255u)), f32(((v_c >> u32(8i)) & 255u)), f32(((v_c >> u32(16i)) & 255u)), f32(((v_c >> u32(24i)) & 255u))) / vec4<f32>(255.0f));
}
fn f_mipOffset(cw_arg_level: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> i32 {
  var v_level: i32 = cw_arg_level;
  var v_size: i32 = (2048i >> u32(v_level));
  return ((((2048i * 2048i) - (v_size * v_size)) * 4i) / 3i);
}
fn f_boundsHit(cw_arg_ro: vec3<f32>, cw_arg_inv: vec3<f32>, cw_arg_lo: vec3<f32>, cw_arg_hi: vec3<f32>, cw_arg_limit: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_ro: vec3<f32> = cw_arg_ro;
  var v_inv: vec3<f32> = cw_arg_inv;
  var v_lo: vec3<f32> = cw_arg_lo;
  var v_hi: vec3<f32> = cw_arg_hi;
  var v_limit: f32 = cw_arg_limit;
  var v_a: vec3<f32> = ((v_lo - v_ro) * v_inv);
  var v_b: vec3<f32> = ((v_hi - v_ro) * v_inv);
  var v_nearV: vec3<f32> = f_min3(v_a, v_b, cw_thread, cw_block, cw_grid);
  var v_farV: vec3<f32> = f_max3(v_a, v_b, cw_thread, cw_block, cw_grid);
  var v_t0: f32 = max(0.001f, max(v_nearV.x, max(v_nearV.y, v_nearV.z)));
  var v_t1: f32 = min(v_limit, min(v_farV.x, min(v_farV.y, v_farV.z)));
  var cw_tmp_3: f32;
  if ((v_t0 <= v_t1)) {
    cw_tmp_3 = v_t0;
  } else {
    cw_tmp_3 = 100000000000000000000.0f;
  }
  return cw_tmp_3;
}
fn f_safeInv(cw_arg_x: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: f32 = cw_arg_x;
  var cw_tmp_5: f32;
  if ((abs(v_x) < 1e-8f)) {
    var cw_tmp_4: f32;
    if ((v_x < f32(0i))) {
      cw_tmp_4 = (-1e-8f);
    } else {
      cw_tmp_4 = 1e-8f;
    }
    cw_tmp_5 = cw_tmp_4;
  } else {
    cw_tmp_5 = v_x;
  }
  return cw_divide_f32(1.0f, cw_tmp_5);
}
fn f_waterNormal(cw_arg_p: vec3<f32>, cw_arg_time: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_p: vec3<f32> = cw_arg_p;
  var v_time: f32 = cw_arg_time;
  var v_ax: f32 = (((v_p.x * 2.0f) + (v_p.z * 0.85f)) + (v_time * 1.3f));
  var v_az: f32 = (((v_p.z * 3.8f) - (v_p.x * 0.44f)) - (v_time * 1.12f));
  return f_unit(f_v3(((((-0.014f) * cos(v_ax)) * 2.0f) - ((0.005f * cos(v_az)) * (-0.44f))), f32(1i), ((((-0.014f) * cos(v_ax)) * 0.85f) - ((0.005f * cos(v_az)) * 3.8f)), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
}
fn f_cosineRay(cw_arg_n: vec3<f32>, cw_arg_r1: f32, cw_arg_r2: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_n: vec3<f32> = cw_arg_n;
  var v_r1: f32 = cw_arg_r1;
  var v_r2: f32 = cw_arg_r2;
  var v_r: f32 = sqrt(v_r1);
  var v_a: f32 = (6.28318530718f * v_r2);
  var v_u: vec3<f32> = f_tangent(v_n, cw_thread, cw_block, cw_grid);
  var v_v: vec3<f32> = f_cross3(v_n, v_u, cw_thread, cw_block, cw_grid);
  return f_unit((((v_u * vec3<f32>((cos(v_a) * v_r))) + (v_v * vec3<f32>((sin(v_a) * v_r)))) + (v_n * vec3<f32>(sqrt((f32(1i) - v_r1))))), cw_thread, cw_block, cw_grid);
}
fn f_cameraForward(cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  return f_unit(f_v3(f32(0i), 0.095f, f32(1i), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
}
fn f_cameraUp(cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_f: vec3<f32> = f_cameraForward(cw_thread, cw_block, cw_grid);
  return f_v3(f32(0i), v_f.z, (-v_f.y), cw_thread, cw_block, cw_grid);
}
fn f_cameraOrigin(cw_arg_x: f32, cw_arg_z: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_x: f32 = cw_arg_x;
  var v_z: f32 = cw_arg_z;
  return f_v3(v_x, 1.65f, (v_z - 26.0f), cw_thread, cw_block, cw_grid);
}


fn f_cw_buffer_helper_0(cw_buffer_arg_0: i32, cw_buffer_arg_1: i32, cw_buffer_arg_2: i32, cw_buffer_arg_3: i32, cw_buffer_arg_4: i32, cw_arg_ro: vec3<f32>, cw_arg_rd: vec3<f32>, cw_arg_limit: f32, cw_arg_loc: i32, cw_arg_time: f32, cw_arg_shadow: i32, cw_arg_reference: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> cw_struct_Hit {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var cw_buffer_offset_1: i32 = cw_buffer_arg_1;
  var cw_buffer_offset_2: i32 = cw_buffer_arg_2;
  var cw_buffer_offset_3: i32 = cw_buffer_arg_3;
  var cw_buffer_offset_4: i32 = cw_buffer_arg_4;
  var v_ro: vec3<f32> = cw_arg_ro;
  var v_rd: vec3<f32> = cw_arg_rd;
  var v_limit: f32 = cw_arg_limit;
  var v_loc: i32 = cw_arg_loc;
  var v_time: f32 = cw_arg_time;
  var v_shadow: i32 = cw_arg_shadow;
  var v_reference: i32 = cw_arg_reference;
  var v_best: cw_struct_Hit;
  v_best.cw_field_t = v_limit;
  v_best.cw_field_id = (-9i);
  v_best.cw_field_normal = f_v3(f32(0i), f32(1i), f32(0i), cw_thread, cw_block, cw_grid);
  if ((v_shadow == 0i)) {
    if ((abs(v_rd.y) > 0.00001f)) {
      var v_t: f32 = cw_divide_f32((0.16f - v_ro.y), v_rd.y);
      if (((v_t > 0.005f) && (v_t < v_best.cw_field_t))) {
        var v_p: vec3<f32> = (v_ro + (v_rd * vec3<f32>(v_t)));
        if ((f_cw_buffer_helper_2((cw_buffer_offset_4 + 0i), v_p.x, v_p.z, v_loc, cw_thread, cw_block, cw_grid) < 0.159f)) {
          v_best.cw_field_t = v_t;
          v_best.cw_field_id = (-2i);
          v_best.cw_field_normal = f_waterNormal(v_p, v_time, cw_thread, cw_block, cw_grid);
        }
      }
    }
    let cw_value_copy_22 = f_cw_buffer_helper_5((cw_buffer_offset_4 + 0i), v_ro, v_rd, v_best.cw_field_t, v_loc, v_shadow, cw_thread, cw_block, cw_grid);
    var v_ground: cw_struct_Hit = cw_struct_Hit(cw_value_copy_22.cw_field_t, cw_value_copy_22.cw_field_id, cw_value_copy_22.cw_field_normal);
    if ((v_ground.cw_field_id == (-1i))) {
      let cw_value_copy_23 = v_ground;
      v_best = cw_struct_Hit(cw_value_copy_23.cw_field_t, cw_value_copy_23.cw_field_id, cw_value_copy_23.cw_field_normal);
    }
  }
  let cw_value_copy_24 = f_cw_buffer_helper_6((cw_buffer_offset_0 + 0i), (cw_buffer_offset_1 + 0i), (cw_buffer_offset_2 + 0i), (cw_buffer_offset_3 + 0i), v_ro, v_rd, v_best.cw_field_t, v_time, v_shadow, v_reference, cw_thread, cw_block, cw_grid);
  var v_tree: cw_struct_Hit = cw_struct_Hit(cw_value_copy_24.cw_field_t, cw_value_copy_24.cw_field_id, cw_value_copy_24.cw_field_normal);
  if ((v_tree.cw_field_id >= 0i)) {
    let cw_value_copy_25 = v_tree;
    v_best = cw_struct_Hit(cw_value_copy_25.cw_field_t, cw_value_copy_25.cw_field_id, cw_value_copy_25.cw_field_normal);
  }
  if (((v_shadow != 0i) && (v_best.cw_field_id >= 0i))) {
    return v_best;
  }
  if ((v_shadow != 0i)) {
    let cw_value_copy_26 = f_cw_buffer_helper_5((cw_buffer_offset_4 + 0i), v_ro, v_rd, v_best.cw_field_t, v_loc, v_shadow, cw_thread, cw_block, cw_grid);
    var v_ground: cw_struct_Hit = cw_struct_Hit(cw_value_copy_26.cw_field_t, cw_value_copy_26.cw_field_id, cw_value_copy_26.cw_field_normal);
    if ((v_ground.cw_field_id == (-1i))) {
      let cw_value_copy_27 = v_ground;
      v_best = cw_struct_Hit(cw_value_copy_27.cw_field_t, cw_value_copy_27.cw_field_id, cw_value_copy_27.cw_field_normal);
    }
  }
  return v_best;
}
fn f_cw_buffer_helper_1(cw_buffer_arg_0: i32, cw_arg_id: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> i32 {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_id: i32 = cw_arg_id;
  if ((v_id < 0i)) {
    return v_id;
  }
  return i32(b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 2i))].w);
}
fn f_cw_buffer_helper_2(cw_buffer_arg_0: i32, cw_arg_x: f32, cw_arg_z: f32, cw_arg_loc: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_x: f32 = cw_arg_x;
  var v_z: f32 = cw_arg_z;
  var v_loc: i32 = cw_arg_loc;
  var v_u: f32 = cw_divide_f32(((v_x + 144.0f) * f32((4096i - 1i))), 288.0f);
  var v_v: f32 = cw_divide_f32(((v_z + 16.0f) * f32((2048i - 1i))), 144.0f);
  if (((((v_u < f32(0i)) || (v_v < f32(0i))) || (v_u >= f32((4096i - 1i)))) || (v_v >= f32((2048i - 1i))))) {
    return f_groundHeight(v_x, v_z, v_loc, cw_thread, cw_block, cw_grid);
  }
  var v_ix: i32 = i32(floor(v_u));
  var v_iy: i32 = i32(floor(v_v));
  var v_fx: f32 = f_fractf(v_u, cw_thread, cw_block, cw_grid);
  var v_fy: f32 = f_fractf(v_v, cw_thread, cw_block, cw_grid);
  var v_i: i32 = ((v_iy * 4096i) + v_ix);
  let cw_argument_index_28 = (cw_buffer_offset_0 + v_i);
  let cw_argument_index_29 = (cw_buffer_offset_0 + (v_i + 1i));
  let cw_argument_index_30 = (cw_buffer_offset_0 + (v_i + 4096i));
  let cw_argument_index_31 = (cw_buffer_offset_0 + ((v_i + 4096i) + 1i));
  return f_mixf(f_mixf(b_terrain[cw_argument_index_28], b_terrain[cw_argument_index_29], v_fx, cw_thread, cw_block, cw_grid), f_mixf(b_terrain[cw_argument_index_30], b_terrain[cw_argument_index_31], v_fx, cw_thread, cw_block, cw_grid), v_fy, cw_thread, cw_block, cw_grid);
}
fn f_cw_buffer_helper_3(cw_buffer_arg_0: i32, cw_buffer_arg_1: i32, cw_arg_h: cw_struct_Hit, cw_arg_p: vec3<f32>, cw_arg_loc: i32, cw_arg_footprint: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var cw_buffer_offset_1: i32 = cw_buffer_arg_1;
  var v_h: cw_struct_Hit = cw_arg_h;
  var v_p: vec3<f32> = cw_arg_p;
  var v_loc: i32 = cw_arg_loc;
  var v_footprint: f32 = cw_arg_footprint;
  if ((v_h.cw_field_id == (-2i))) {
    return f_v3(0.94f, 0.98f, 0.96f, cw_thread, cw_block, cw_grid);
  }
  if ((v_h.cw_field_id == (-1i))) {
    var v_soil: vec3<f32> = f_xyz(f_cw_buffer_helper_4((cw_buffer_offset_1 + 0i), (v_p.x * 0.25f), (v_p.z * 0.25f), 0i, (v_footprint * 0.25f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
    var v_detail: f32 = f_fbm((v_p * vec3<f32>(0.7f)), cw_thread, cw_block, cw_grid);
    v_soil = v_soil * vec3<f32>((0.73f + (v_detail * 0.6f)));
    var v_wet: f32 = (f32(1i) - f_smoothf(0.13f, 0.7f, v_p.y, cw_thread, cw_block, cw_grid));
    v_soil = v_soil * vec3<f32>((f32(1i) - (v_wet * 0.24f)));
    v_soil = f_mix3(v_soil, (v_soil * f_v3(1.4f, 1.45f, 1.32f, cw_thread, cw_block, cw_grid)), (f_smoothf(0.25f, (-0.7f), v_p.y, cw_thread, cw_block, cw_grid) * 0.6f), cw_thread, cw_block, cw_grid);
    var v_grass: f32 = (f_smoothf(22.8f, 27.5f, v_p.z, cw_thread, cw_block, cw_grid) * f_smoothf(0.42f, 0.68f, f_noise3((v_p * vec3<f32>(0.55f)), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid));
    v_soil = f_mix3(v_soil, f_v3(0.15f, 0.18f, 0.07f, cw_thread, cw_block, cw_grid), (v_grass * 0.7f), cw_thread, cw_block, cw_grid);
    var v_cell: vec2<f32> = vec2<f32>(floor((v_p.x * f32(6i))), floor((v_p.z * f32(6i))));
    var v_q: vec2<f32> = vec2<f32>((f_fractf((v_p.x * f32(6i)), cw_thread, cw_block, cw_grid) - 0.5f), (f_fractf((v_p.z * f32(6i)), cw_thread, cw_block, cw_grid) - 0.5f));
    var v_key: u32 = ((u32(i32(v_cell.x)) * 7177u) ^ (u32(i32(v_cell.y)) * 313u));
    var v_angle: f32 = (f_rnd(v_key, cw_thread, cw_block, cw_grid) * 6.28318530718f);
    var v_u: f32 = ((v_q.x * cos(v_angle)) + (v_q.y * sin(v_angle)));
    var v_v: f32 = (((-v_q.x) * sin(v_angle)) + (v_q.y * cos(v_angle)));
    var cw_tmp_32: f32;
    if ((f_rnd((v_key + 1u), cw_thread, cw_block, cw_grid) > 0.52f)) {
      cw_tmp_32 = 1.0f;
    } else {
      cw_tmp_32 = 0.0f;
    }
    var v_leaf: f32 = (f_smoothf(1.08f, 0.87f, (cw_divide_f32((v_u * v_u), 0.23f) + cw_divide_f32((v_v * v_v), 0.006f)), cw_thread, cw_block, cw_grid) * cw_tmp_32);
    v_soil = f_mix3(v_soil, (f_v3(0.2f, 0.095f, 0.026f, cw_thread, cw_block, cw_grid) * vec3<f32>((0.7f + (f_rnd((v_key + 2u), cw_thread, cw_block, cw_grid) * 0.6f)))), (v_leaf * (f32(1i) - f_sat((v_footprint * f32(8i)), cw_thread, cw_block, cw_grid))), cw_thread, cw_block, cw_grid);
    return v_soil;
  }
  var v_id: i32 = v_h.cw_field_id;
  var v_mat: vec4<f32> = b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 2i))];
  var v_colour: vec3<f32> = f_xyz(v_mat, cw_thread, cw_block, cw_grid);
  if ((i32(v_mat.w) == 1i)) {
    var v_patch: f32 = f_fbm((v_p * f_v3(5.0f, 1.6f, 5.0f, cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid);
    var v_strip: f32 = f_noise3(((v_p * f_v3(23.0f, 1.8f, 23.0f, cw_thread, cw_block, cw_grid)) + f_v3((v_patch * 3.0f), f32(0i), f32(0i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid);
    v_colour = f_mix3((v_colour * vec3<f32>(0.44f)), (v_colour * vec3<f32>(1.12f)), f_smoothf(0.29f, 0.64f, v_patch, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
    v_colour = f_mix3(v_colour, f_v3(0.19f, 0.1f, 0.049f, cw_thread, cw_block, cw_grid), (f_smoothf(0.53f, 0.65f, v_strip, cw_thread, cw_block, cw_grid) * 0.78f), cw_thread, cw_block, cw_grid);
    var v_scars: f32 = f_smoothf(0.67f, 0.73f, f_noise3((v_p * f_v3(f32(37i), 3.0f, f32(37i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
    v_colour = v_colour * vec3<f32>((f32(1i) - ((v_scars * 0.32f) * (f32(1i) - f_sat((v_footprint * f32(10i)), cw_thread, cw_block, cw_grid)))));
  } else {
    if ((i32(v_mat.w) == 4i)) {
      v_colour = ((f_xyz(f_cw_buffer_helper_7((cw_buffer_offset_1 + 0i), v_p, v_h.cw_field_normal, v_footprint, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid) * v_colour) / f_v3(0.46f, 0.35f, 0.22f, cw_thread, cw_block, cw_grid));
      v_colour = v_colour * vec3<f32>((f32(1i) - ((f32(1i) - f_smoothf(0.13f, 0.36f, v_p.y, cw_thread, cw_block, cw_grid)) * 0.3f)));
      var v_lichen: f32 = (f_smoothf(0.62f, 0.8f, f_noise3((v_p * vec3<f32>(12.0f)), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid) * f_smoothf(0.25f, 0.8f, v_h.cw_field_normal.y, cw_thread, cw_block, cw_grid));
      v_colour = f_mix3(v_colour, f_v3(0.25f, 0.29f, 0.12f, cw_thread, cw_block, cw_grid), (v_lichen * 0.35f), cw_thread, cw_block, cw_grid);
    } else {
      if (((i32(v_mat.w) == 2i) || (i32(v_mat.w) == 8i))) {
        var v_a: vec4<f32> = b_objects[(cw_buffer_offset_0 + (v_id * 4i))];
        var v_b: vec4<f32> = b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 1i))];
        let cw_argument_index_33 = (cw_buffer_offset_0 + ((v_id * 4i) + 3i));
        var v_axis: vec3<f32> = f_xyz(b_objects[cw_argument_index_33], cw_thread, cw_block, cw_grid);
        var v_u: vec3<f32> = f_basisU(v_axis, v_b.w, cw_thread, cw_block, cw_grid);
        var v_q: vec3<f32> = (v_p - f_xyz(v_a, cw_thread, cw_block, cw_grid));
        var v_across: f32 = cw_divide_f32(f_dot3(v_q, v_u, cw_thread, cw_block, cw_grid), v_b.x);
        var v_along: f32 = cw_divide_f32(f_dot3(v_q, v_axis, cw_thread, cw_block, cw_grid), v_b.y);
        var v_vein: f32 = (f32(1i) - f_smoothf(0.025f, 0.11f, abs(v_across), cw_thread, cw_block, cw_grid));
        var v_ribs: f32 = cw_pow_f32(max(f32(0i), sin(((v_along * f32(52i)) + (abs(v_across) * f32(13i))))), f32(16i));
        v_colour = v_colour * vec3<f32>((0.8f + (f_noise3((v_p * vec3<f32>(f32(20i))), cw_thread, cw_block, cw_grid) * 0.28f)));
        v_colour = f_mix3(v_colour, (v_colour * vec3<f32>(1.4f)), (((v_vein * 0.34f) + (v_ribs * 0.09f)) * (f32(1i) - f_sat((v_footprint * f32(4i)), cw_thread, cw_block, cw_grid))), cw_thread, cw_block, cw_grid);
      }
    }
  }
  return v_colour;
}
fn f_cw_buffer_helper_4(cw_buffer_arg_0: i32, cw_arg_u: f32, cw_arg_v: f32, cw_arg_kind: i32, cw_arg_footprint: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec4<f32> {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_u: f32 = cw_arg_u;
  var v_v: f32 = cw_arg_v;
  var v_kind: i32 = cw_arg_kind;
  var v_footprint: f32 = cw_arg_footprint;
  var v_lod: f32 = f_clampf((log(max(1.0f, (v_footprint * f32(2048i)))) * 1.442695f), f32(0i), f32(11i), cw_thread, cw_block, cw_grid);
  var v_level: i32 = i32(v_lod);
  var v_a: vec4<f32> = f_cw_buffer_helper_8((cw_buffer_offset_0 + 0i), v_u, v_v, v_kind, v_level, cw_thread, cw_block, cw_grid);
  var cw_tmp_34: i32;
  if ((v_level < 11i)) {
    cw_tmp_34 = (v_level + 1i);
  } else {
    cw_tmp_34 = 11i;
  }
  var v_b: vec4<f32> = f_cw_buffer_helper_8((cw_buffer_offset_0 + 0i), v_u, v_v, v_kind, cw_tmp_34, cw_thread, cw_block, cw_grid);
  return (v_a + ((v_b - v_a) * vec4<f32>(f_fractf(v_lod, cw_thread, cw_block, cw_grid))));
}
fn f_cw_buffer_helper_5(cw_buffer_arg_0: i32, cw_arg_ro: vec3<f32>, cw_arg_rd: vec3<f32>, cw_arg_limit: f32, cw_arg_loc: i32, cw_arg_shadow: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> cw_struct_Hit {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_ro: vec3<f32> = cw_arg_ro;
  var v_rd: vec3<f32> = cw_arg_rd;
  var v_limit: f32 = cw_arg_limit;
  var v_loc: i32 = cw_arg_loc;
  var v_shadow: i32 = cw_arg_shadow;
  var v_h: cw_struct_Hit;
  v_h.cw_field_t = v_limit;
  v_h.cw_field_id = (-9i);
  v_h.cw_field_normal = f_v3(f32(0i), f32(1i), f32(0i), cw_thread, cw_block, cw_grid);
  var v_t: f32 = 0.03f;
  var v_prev: f32 = 0.0f;
  {
    var v_k: i32 = 0i;
    loop {
      if (!(v_k < 256i)) { break; }
      var v_p: vec3<f32> = (v_ro + (v_rd * vec3<f32>(v_t)));
      if (((v_t >= v_limit) || (v_p.y > 54.0f))) {
        break;
      }
      var v_d: f32 = (v_p.y - f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), v_p.x, v_p.z, v_loc, cw_thread, cw_block, cw_grid));
      if ((v_d < 0.003f)) {
        if ((v_shadow != 0i)) {
          v_h.cw_field_t = v_t;
          v_h.cw_field_id = (-1i);
          return v_h;
        }
        var v_a: f32 = v_prev;
        var v_b: f32 = v_t;
        {
          var v_j: i32 = 0i;
          loop {
            if (!(v_j < 7i)) { break; }
            var v_m: f32 = ((v_a + v_b) * 0.5f);
            var v_v: vec3<f32> = (v_ro + (v_rd * vec3<f32>(v_m)));
            if ((v_v.y > f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), v_v.x, v_v.z, v_loc, cw_thread, cw_block, cw_grid))) {
              v_a = v_m;
            } else {
              v_b = v_m;
            }
            continuing {
              v_j += i32(1);
            }
          }
        }
        v_h.cw_field_t = ((v_a + v_b) * 0.5f);
        v_h.cw_field_id = (-1i);
        v_h.cw_field_normal = f_cw_buffer_helper_9((cw_buffer_offset_0 + 0i), (v_ro + (v_rd * vec3<f32>(v_h.cw_field_t))), v_loc, cw_thread, cw_block, cw_grid);
        return v_h;
      }
      v_prev = v_t;
      v_t = (v_t + min(5.5f, max((v_d * 0.62f), (0.13f + (v_t * 0.004f)))));
      continuing {
        v_k += i32(1);
      }
    }
  }
  return v_h;
}
fn f_cw_buffer_helper_6(cw_buffer_arg_0: i32, cw_buffer_arg_1: i32, cw_buffer_arg_2: i32, cw_buffer_arg_3: i32, cw_arg_ro: vec3<f32>, cw_arg_rd: vec3<f32>, cw_arg_limit: f32, cw_arg_time: f32, cw_arg_shadow: i32, cw_arg_reference: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> cw_struct_Hit {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var cw_buffer_offset_1: i32 = cw_buffer_arg_1;
  var cw_buffer_offset_2: i32 = cw_buffer_arg_2;
  var cw_buffer_offset_3: i32 = cw_buffer_arg_3;
  var v_ro: vec3<f32> = cw_arg_ro;
  var v_rd: vec3<f32> = cw_arg_rd;
  var v_limit: f32 = cw_arg_limit;
  var v_time: f32 = cw_arg_time;
  var v_shadow: i32 = cw_arg_shadow;
  var v_reference: i32 = cw_arg_reference;
  var v_best: cw_struct_Hit;
  v_best.cw_field_t = v_limit;
  v_best.cw_field_id = (-9i);
  v_best.cw_field_normal = f_v3(f32(0i), f32(1i), f32(0i), cw_thread, cw_block, cw_grid);
  var v_inv: vec3<f32> = f_v3(f_safeInv(v_rd.x, cw_thread, cw_block, cw_grid), f_safeInv(v_rd.y, cw_thread, cw_block, cw_grid), f_safeInv(v_rd.z, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_stack: array<i32, 32>;
  var v_top: i32 = 0i;
  var v_node: i32 = 1i;
  var v_needsTest: i32 = 1i;
  {
    var v_iteration: i32 = 0i;
    loop {
      if (!(v_iteration < 4096i)) { break; }
      var cw_tmp_37: bool = (v_needsTest == 0i);
      if (!cw_tmp_37) {
        let cw_argument_index_35 = (cw_buffer_offset_1 + (v_node * 2i));
        let cw_argument_index_36 = (cw_buffer_offset_1 + ((v_node * 2i) + 1i));
        cw_tmp_37 = (f_boundsHit(v_ro, v_inv, f_xyz(b_bounds[cw_argument_index_35], cw_thread, cw_block, cw_grid), f_xyz(b_bounds[cw_argument_index_36], cw_thread, cw_block, cw_grid), v_best.cw_field_t, cw_thread, cw_block, cw_grid) < v_best.cw_field_t);
      }
      if (cw_tmp_37) {
        if ((v_node >= 524288i)) {
          let cw_value_copy_38 = f_cw_buffer_helper_10((cw_buffer_offset_0 + 0i), (cw_buffer_offset_2 + 0i), (cw_buffer_offset_3 + 0i), i32(b_bounds[(cw_buffer_offset_1 + (v_node * 2i))].w), (v_node - 524288i), v_ro, v_rd, v_best.cw_field_t, v_time, v_shadow, v_reference, cw_thread, cw_block, cw_grid);
          var v_h: cw_struct_Hit = cw_struct_Hit(cw_value_copy_38.cw_field_t, cw_value_copy_38.cw_field_id, cw_value_copy_38.cw_field_normal);
          if ((v_h.cw_field_id >= 0i)) {
            let cw_value_copy_39 = v_h;
            v_best = cw_struct_Hit(cw_value_copy_39.cw_field_t, cw_value_copy_39.cw_field_id, cw_value_copy_39.cw_field_normal);
            if ((v_shadow != 0i)) {
              return v_best;
            }
          }
        } else {
          var v_l: i32 = (v_node * 2i);
          var v_r: i32 = (v_l + 1i);
          let cw_argument_index_40 = (cw_buffer_offset_1 + (v_l * 2i));
          let cw_argument_index_41 = (cw_buffer_offset_1 + ((v_l * 2i) + 1i));
          var v_dl: f32 = f_boundsHit(v_ro, v_inv, f_xyz(b_bounds[cw_argument_index_40], cw_thread, cw_block, cw_grid), f_xyz(b_bounds[cw_argument_index_41], cw_thread, cw_block, cw_grid), v_best.cw_field_t, cw_thread, cw_block, cw_grid);
          let cw_argument_index_42 = (cw_buffer_offset_1 + (v_r * 2i));
          let cw_argument_index_43 = (cw_buffer_offset_1 + ((v_r * 2i) + 1i));
          var v_dr: f32 = f_boundsHit(v_ro, v_inv, f_xyz(b_bounds[cw_argument_index_42], cw_thread, cw_block, cw_grid), f_xyz(b_bounds[cw_argument_index_43], cw_thread, cw_block, cw_grid), v_best.cw_field_t, cw_thread, cw_block, cw_grid);
          if (((v_dl < v_best.cw_field_t) || (v_dr < v_best.cw_field_t))) {
            if ((v_dl < v_dr)) {
              if ((v_dr < v_best.cw_field_t)) {
                v_stack[v_top] = v_r;
                v_top += i32(1);
              }
              v_node = v_l;
            } else {
              if ((v_dl < v_best.cw_field_t)) {
                v_stack[v_top] = v_l;
                v_top += i32(1);
              }
              v_node = v_r;
            }
            v_needsTest = v_reference;
            continue;
          }
        }
      }
      if ((v_top == 0i)) {
        break;
      }
      v_top -= i32(1);
      v_node = v_stack[v_top];
      v_needsTest = 1i;
      continuing {
        v_iteration += i32(1);
      }
    }
  }
  return v_best;
}
fn f_cw_buffer_helper_7(cw_buffer_arg_0: i32, cw_arg_p: vec3<f32>, cw_arg_n: vec3<f32>, cw_arg_footprint: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec4<f32> {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_p: vec3<f32> = cw_arg_p;
  var v_n: vec3<f32> = cw_arg_n;
  var v_footprint: f32 = cw_arg_footprint;
  var v_w: vec3<f32> = f_abs3(v_n, cw_thread, cw_block, cw_grid);
  v_w = (((v_w * v_w) * v_w) * v_w);
  v_w = v_w / vec3<f32>(((v_w.x + v_w.y) + v_w.z));
  return (((f_cw_buffer_helper_4((cw_buffer_offset_0 + 0i), (v_p.z * 0.5f), (v_p.y * 0.5f), 1i, (v_footprint * 0.5f), cw_thread, cw_block, cw_grid) * vec4<f32>(v_w.x)) + (f_cw_buffer_helper_4((cw_buffer_offset_0 + 0i), (v_p.x * 0.5f), (v_p.z * 0.5f), 1i, (v_footprint * 0.5f), cw_thread, cw_block, cw_grid) * vec4<f32>(v_w.y))) + (f_cw_buffer_helper_4((cw_buffer_offset_0 + 0i), (v_p.x * 0.5f), (v_p.y * 0.5f), 1i, (v_footprint * 0.5f), cw_thread, cw_block, cw_grid) * vec4<f32>(v_w.z)));
}
fn f_cw_buffer_helper_8(cw_buffer_arg_0: i32, cw_arg_u: f32, cw_arg_v: f32, cw_arg_kind: i32, cw_arg_level: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec4<f32> {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_u: f32 = cw_arg_u;
  var v_v: f32 = cw_arg_v;
  var v_kind: i32 = cw_arg_kind;
  var v_level: i32 = cw_arg_level;
  var v_size: i32 = (2048i >> u32(v_level));
  var v_mask: i32 = (v_size - 1i);
  var v_offset: i32 = ((v_kind * 5592405i) + f_mipOffset(v_level, cw_thread, cw_block, cw_grid));
  var v_x: f32 = ((f_fractf(v_u, cw_thread, cw_block, cw_grid) * f32(v_size)) - 0.5f);
  var v_y: f32 = ((f_fractf(v_v, cw_thread, cw_block, cw_grid) * f32(v_size)) - 0.5f);
  var v_ix: i32 = i32(floor(v_x));
  var v_iy: i32 = i32(floor(v_y));
  var v_fx: f32 = f_fractf(v_x, cw_thread, cw_block, cw_grid);
  var v_fy: f32 = f_fractf(v_y, cw_thread, cw_block, cw_grid);
  let cw_argument_index_44 = (cw_buffer_offset_0 + ((v_offset + ((v_iy & v_mask) * v_size)) + (v_ix & v_mask)));
  var v_a: vec4<f32> = f_unpackMaterial(b_atlas[cw_argument_index_44], cw_thread, cw_block, cw_grid);
  let cw_argument_index_45 = (cw_buffer_offset_0 + ((v_offset + ((v_iy & v_mask) * v_size)) + ((v_ix + 1i) & v_mask)));
  var v_b: vec4<f32> = f_unpackMaterial(b_atlas[cw_argument_index_45], cw_thread, cw_block, cw_grid);
  let cw_argument_index_46 = (cw_buffer_offset_0 + ((v_offset + (((v_iy + 1i) & v_mask) * v_size)) + (v_ix & v_mask)));
  var v_c: vec4<f32> = f_unpackMaterial(b_atlas[cw_argument_index_46], cw_thread, cw_block, cw_grid);
  let cw_argument_index_47 = (cw_buffer_offset_0 + ((v_offset + (((v_iy + 1i) & v_mask) * v_size)) + ((v_ix + 1i) & v_mask)));
  var v_d: vec4<f32> = f_unpackMaterial(b_atlas[cw_argument_index_47], cw_thread, cw_block, cw_grid);
  return (((v_a + ((v_b - v_a) * vec4<f32>(v_fx))) * vec4<f32>((f32(1i) - v_fy))) + ((v_c + ((v_d - v_c) * vec4<f32>(v_fx))) * vec4<f32>(v_fy)));
}
fn f_cw_buffer_helper_9(cw_buffer_arg_0: i32, cw_arg_p: vec3<f32>, cw_arg_loc: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var v_p: vec3<f32> = cw_arg_p;
  var v_loc: i32 = cw_arg_loc;
  var v_e: f32 = 0.07f;
  return f_unit(f_v3((f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), (v_p.x - v_e), v_p.z, v_loc, cw_thread, cw_block, cw_grid) - f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), (v_p.x + v_e), v_p.z, v_loc, cw_thread, cw_block, cw_grid)), (f32(2i) * v_e), (f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), v_p.x, (v_p.z - v_e), v_loc, cw_thread, cw_block, cw_grid) - f_cw_buffer_helper_2((cw_buffer_offset_0 + 0i), v_p.x, (v_p.z + v_e), v_loc, cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
}
fn f_cw_buffer_helper_10(cw_buffer_arg_0: i32, cw_buffer_arg_1: i32, cw_buffer_arg_2: i32, cw_arg_id: i32, cw_arg_rank: i32, cw_arg_ro: vec3<f32>, cw_arg_rd: vec3<f32>, cw_arg_limit: f32, cw_arg_time: f32, cw_arg_shadow: i32, cw_arg_reference: i32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> cw_struct_Hit {
  var cw_buffer_offset_0: i32 = cw_buffer_arg_0;
  var cw_buffer_offset_1: i32 = cw_buffer_arg_1;
  var cw_buffer_offset_2: i32 = cw_buffer_arg_2;
  var v_id: i32 = cw_arg_id;
  var v_rank: i32 = cw_arg_rank;
  var v_ro: vec3<f32> = cw_arg_ro;
  var v_rd: vec3<f32> = cw_arg_rd;
  var v_limit: f32 = cw_arg_limit;
  var v_time: f32 = cw_arg_time;
  var v_shadow: i32 = cw_arg_shadow;
  var v_reference: i32 = cw_arg_reference;
  var v_hit: cw_struct_Hit;
  v_hit.cw_field_t = v_limit;
  v_hit.cw_field_id = (-9i);
  v_hit.cw_field_normal = f_v3(f32(0i), f32(1i), f32(0i), cw_thread, cw_block, cw_grid);
  var v_aa: vec4<f32>;
  var v_bb: vec4<f32>;
  var v_cc: vec4<f32>;
  var v_dd: vec4<f32>;
  if ((v_reference != 0i)) {
    v_aa = b_objects[(cw_buffer_offset_0 + (v_id * 4i))];
    var v_b: vec4<f32> = b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 1i))];
    var v_d: vec4<f32> = b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 3i))];
    var v_mat: i32 = i32(b_objects[(cw_buffer_offset_0 + ((v_id * 4i) + 2i))].w);
    if ((v_d.w > 0.5f)) {
      var v_ba: vec3<f32> = (f_xyz(v_b, cw_thread, cw_block, cw_grid) - f_xyz(v_aa, cw_thread, cw_block, cw_grid));
      var v_length: f32 = f_len3(v_ba, cw_thread, cw_block, cw_grid);
      v_bb = v_b;
      v_cc = f_v4((v_ba / vec3<f32>(max(v_length, 1e-8f))), v_length, cw_thread, cw_block, cw_grid);
      v_dd = vec4<f32>(cw_divide_f32((v_b.w - v_aa.w), max(v_length, 1e-8f)), f32(0i), f32(0i), f32((v_mat + 16i)));
    } else {
      var v_axis: vec3<f32> = f_xyz(v_d, cw_thread, cw_block, cw_grid);
      var v_u: vec3<f32> = f_basisU(v_axis, v_b.w, cw_thread, cw_block, cw_grid);
      var v_v: vec3<f32> = f_cross3(v_axis, v_u, cw_thread, cw_block, cw_grid);
      v_bb = f_v4((v_u / vec3<f32>(v_b.x)), f32(0i), cw_thread, cw_block, cw_grid);
      v_cc = f_v4((v_axis / vec3<f32>(v_b.y)), f32(0i), cw_thread, cw_block, cw_grid);
      v_dd = f_v4((v_v / vec3<f32>(v_b.z)), f32(v_mat), cw_thread, cw_block, cw_grid);
      if (((v_mat == 2i) || (v_mat == 8i))) {
        v_aa = f_v4((f_xyz(v_aa, cw_thread, cw_block, cw_grid) + f_windOffset(f_xyz(v_aa, cw_thread, cw_block, cw_grid), v_time, cw_thread, cw_block, cw_grid)), v_aa.w, cw_thread, cw_block, cw_grid);
      }
    }
  } else {
    v_aa = b_rayGeometry[(cw_buffer_offset_1 + (v_rank * 4i))];
    v_bb = b_rayGeometry[(cw_buffer_offset_1 + ((v_rank * 4i) + 1i))];
    v_cc = b_rayGeometry[(cw_buffer_offset_1 + ((v_rank * 4i) + 2i))];
    v_dd = b_rayGeometry[(cw_buffer_offset_1 + ((v_rank * 4i) + 3i))];
  }
  var v_q: vec3<f32> = (v_ro - f_xyz(v_aa, cw_thread, cw_block, cw_grid));
  var v_material: i32 = i32(v_dd.w);
  if ((v_material >= 16i)) {
    var v_axis: vec3<f32> = f_xyz(v_cc, cw_thread, cw_block, cw_grid);
    var v_length: f32 = v_cc.w;
    var v_y0: f32 = f_dot3(v_q, v_axis, cw_thread, cw_block, cw_grid);
    var v_yd: f32 = f_dot3(v_rd, v_axis, cw_thread, cw_block, cw_grid);
    var v_slope: f32 = v_dd.x;
    var v_radius: f32 = (v_aa.w + (v_slope * v_y0));
    var v_op: vec3<f32> = (v_q - (v_axis * vec3<f32>(v_y0)));
    var v_dp: vec3<f32> = (v_rd - (v_axis * vec3<f32>(v_yd)));
    var v_qa: f32 = (f_dot3(v_dp, v_dp, cw_thread, cw_block, cw_grid) - (((v_slope * v_slope) * v_yd) * v_yd));
    var v_qb: f32 = (f_dot3(v_op, v_dp, cw_thread, cw_block, cw_grid) - ((v_radius * v_slope) * v_yd));
    var v_qc: f32 = (f_dot3(v_op, v_op, cw_thread, cw_block, cw_grid) - (v_radius * v_radius));
    var v_disc: f32 = ((v_qb * v_qb) - (v_qa * v_qc));
    if (((v_disc >= f32(0i)) && (v_qa > 1e-10f))) {
      var v_t: f32 = cw_divide_f32(((-v_qb) - sqrt(v_disc)), v_qa);
      var v_y: f32 = (v_y0 + (v_t * v_yd));
      if (((((v_t > 0.002f) && (v_t < v_hit.cw_field_t)) && (v_y > f32(0i))) && (v_y < v_length))) {
        v_hit.cw_field_t = v_t;
        v_hit.cw_field_id = v_id;
        if ((v_shadow != 0i)) {
          return v_hit;
        }
        v_hit.cw_field_normal = f_unit((((v_q + (v_rd * vec3<f32>(v_t))) - (v_axis * vec3<f32>(v_y))) - (v_axis * vec3<f32>(((v_aa.w + (v_slope * v_y)) * v_slope)))), cw_thread, cw_block, cw_grid);
      }
    }
    {
      var v_k: i32 = 0i;
      loop {
        if (!(v_k < 2i)) { break; }
        var cw_tmp_48: vec3<f32>;
        if ((v_k == 0i)) {
          cw_tmp_48 = f_xyz(v_aa, cw_thread, cw_block, cw_grid);
        } else {
          cw_tmp_48 = f_xyz(v_bb, cw_thread, cw_block, cw_grid);
        }
        var v_oc: vec3<f32> = (v_ro - cw_tmp_48);
        var cw_tmp_49: f32;
        if ((v_k == 0i)) {
          cw_tmp_49 = v_aa.w;
        } else {
          cw_tmp_49 = v_bb.w;
        }
        var v_r: f32 = cw_tmp_49;
        var v_bs: f32 = f_dot3(v_oc, v_rd, cw_thread, cw_block, cw_grid);
        var v_cs: f32 = (f_dot3(v_oc, v_oc, cw_thread, cw_block, cw_grid) - (v_r * v_r));
        var v_ds: f32 = ((v_bs * v_bs) - v_cs);
        if ((v_ds >= f32(0i))) {
          var v_t: f32 = ((-v_bs) - sqrt(v_ds));
          if (((v_t > 0.002f) && (v_t < v_hit.cw_field_t))) {
            v_hit.cw_field_t = v_t;
            v_hit.cw_field_id = v_id;
            if ((v_shadow != 0i)) {
              return v_hit;
            }
            v_hit.cw_field_normal = f_unit((v_oc + (v_rd * vec3<f32>(v_t))), cw_thread, cw_block, cw_grid);
          }
        }
        continuing {
          v_k += i32(1);
        }
      }
    }
  } else {
    var v_u: vec3<f32> = f_xyz(v_bb, cw_thread, cw_block, cw_grid);
    var v_axis: vec3<f32> = f_xyz(v_cc, cw_thread, cw_block, cw_grid);
    var v_v: vec3<f32> = f_xyz(v_dd, cw_thread, cw_block, cw_grid);
    var v_o: vec3<f32> = f_v3(f_dot3(v_q, v_u, cw_thread, cw_block, cw_grid), f_dot3(v_q, v_axis, cw_thread, cw_block, cw_grid), f_dot3(v_q, v_v, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
    var v_d: vec3<f32> = f_v3(f_dot3(v_rd, v_u, cw_thread, cw_block, cw_grid), f_dot3(v_rd, v_axis, cw_thread, cw_block, cw_grid), f_dot3(v_rd, v_v, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
    if ((v_material == 4i)) {
      var v_enter: f32 = 0.002f;
      var v_leave: f32 = v_limit;
      var v_normal: vec3<f32> = f_v3(f32(0i), f32(1i), f32(0i), cw_thread, cw_block, cw_grid);
      var v_base: i32 = (f_rockIndex(v_id, cw_thread, cw_block, cw_grid) * 104i);
      {
        var v_plane: i32 = 0i;
        loop {
          if (!(v_plane < 104i)) { break; }
          var v_face: vec4<f32> = b_rockPlanes[(cw_buffer_offset_2 + (v_base + v_plane))];
          var v_pn: vec3<f32> = f_xyz(v_face, cw_thread, cw_block, cw_grid);
          var v_denominator: f32 = f_dot3(v_pn, v_d, cw_thread, cw_block, cw_grid);
          var v_numerator: f32 = (v_face.w - f_dot3(v_pn, v_o, cw_thread, cw_block, cw_grid));
          if ((abs(v_denominator) < 1e-9f)) {
            if ((v_numerator < f32(0i))) {
              v_leave = f32((-1i));
            }
          } else {
            var v_t: f32 = cw_divide_f32(v_numerator, v_denominator);
            if ((v_denominator < f32(0i))) {
              if ((v_t > v_enter)) {
                v_enter = v_t;
                v_normal = v_pn;
              }
            } else {
              v_leave = min(v_leave, v_t);
            }
          }
          if ((v_enter > v_leave)) {
            return v_hit;
          }
          continuing {
            v_plane += i32(1);
          }
        }
      }
      if ((((v_enter <= v_leave) && (v_enter > 0.002f)) && (v_enter < v_limit))) {
        v_hit.cw_field_t = v_enter;
        v_hit.cw_field_id = v_id;
        if ((v_shadow == 0i)) {
          v_hit.cw_field_normal = f_unit((((v_u * vec3<f32>(v_normal.x)) + (v_axis * vec3<f32>(v_normal.y))) + (v_v * vec3<f32>(v_normal.z))), cw_thread, cw_block, cw_grid);
        }
      }
      return v_hit;
    }
    var v_qa: f32 = f_dot3(v_d, v_d, cw_thread, cw_block, cw_grid);
    var v_qb: f32 = f_dot3(v_o, v_d, cw_thread, cw_block, cw_grid);
    var v_qc: f32 = (f_dot3(v_o, v_o, cw_thread, cw_block, cw_grid) - f32(1i));
    var v_disc: f32 = ((v_qb * v_qb) - (v_qa * v_qc));
    if ((v_disc >= f32(0i))) {
      var v_t: f32 = cw_divide_f32(((-v_qb) - sqrt(v_disc)), v_qa);
      if ((v_t <= 0.002f)) {
        v_t = cw_divide_f32(((-v_qb) + sqrt(v_disc)), v_qa);
      }
      if (((v_t > 0.002f) && (v_t < v_hit.cw_field_t))) {
        var v_p: vec3<f32> = (v_o + (v_d * vec3<f32>(v_t)));
        v_hit.cw_field_t = v_t;
        v_hit.cw_field_id = v_id;
        if ((v_shadow == 0i)) {
          v_hit.cw_field_normal = f_unit((((v_u * vec3<f32>(v_p.x)) + (v_axis * vec3<f32>(v_p.y))) + (v_v * vec3<f32>(v_p.z))), cw_thread, cw_block, cw_grid);
        }
      }
    }
  }
  return v_hit;
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

@compute @workgroup_size(8, 4, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  var v_referenceGeometry: i32 = 0i;
  var v_x: i32 = i32(((cw_block.x * cw_block_size.x) + cw_thread.x));
  var v_y: i32 = i32(((cw_block.y * cw_block_size.y) + cw_thread.y));
  if (((v_x >= cw_params.p_width) || (v_y >= cw_params.p_height))) {
    return;
  }
  var v_pixel: i32 = ((v_y * cw_params.p_width) + v_x);
  var v_seed: u32 = f_hashU((((u32(v_pixel) * 9781u) + (u32(cw_params.p_frame) * 6271u)) + 381u), cw_thread, cw_block, cw_grid);
  var v_jx: f32 = (f_rnd((v_seed + 1u), cw_thread, cw_block, cw_grid) - 0.5f);
  var v_jy: f32 = (f_rnd((v_seed + 2u), cw_thread, cw_block, cw_grid) - 0.5f);
  var v_scale: f32 = 0.4f;
  var v_aspect: f32 = cw_divide_f32(f32(cw_params.p_width), f32(cw_params.p_height));
  var v_sx: f32 = ((((cw_divide_f32(((f32(v_x) + 0.5f) + v_jx), f32(cw_params.p_width)) * f32(2i)) - f32(1i)) * v_aspect) * v_scale);
  var v_sy: f32 = ((f32(1i) - (cw_divide_f32(((f32(v_y) + 0.5f) + v_jy), f32(cw_params.p_height)) * f32(2i))) * v_scale);
  let cw_argument_index_6 = 11i;
  let cw_argument_index_7 = 12i;
  var v_ro: vec3<f32> = f_cameraOrigin(b_state[cw_argument_index_6], b_state[cw_argument_index_7], cw_thread, cw_block, cw_grid);
  var v_rd: vec3<f32> = f_unit(((f_cameraForward(cw_thread, cw_block, cw_grid) + f_v3(v_sx, f32(0i), f32(0i), cw_thread, cw_block, cw_grid)) + (f_cameraUp(cw_thread, cw_block, cw_grid) * vec3<f32>(v_sy))), cw_thread, cw_block, cw_grid);
  var v_throughput: vec3<f32> = f_v3(f32(1i), f32(1i), f32(1i), cw_thread, cw_block, cw_grid);
  var v_light: vec3<f32> = f_v3(f32(0i), f32(0i), f32(0i), cw_thread, cw_block, cw_grid);
  let cw_argument_index_8 = 7i;
  var v_loc: i32 = i32(b_state[cw_argument_index_8]);
  var v_hour: f32 = b_state[10i];
  var v_tm: f32 = b_state[15i];
  var v_sun: vec3<f32> = f_sunDirection(v_hour, cw_thread, cw_block, cw_grid);
  var v_sunE: vec3<f32> = f_sunColour(v_hour, cw_thread, cw_block, cw_grid);
  if ((v_sun.y < f32(0i))) {
    var v_moon: f32 = f_smoothf(0.0f, 0.22f, (-v_sun.y), cw_thread, cw_block, cw_grid);
    v_sun = f_unit(f_v3((-0.52f), 0.74f, (-0.43f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
    v_sunE = (f_v3(0.18f, 0.25f, 0.39f, cw_thread, cw_block, cw_grid) * vec3<f32>(v_moon));
  }
  var v_firstPoint: vec3<f32> = (v_ro + (v_rd * vec3<f32>(f32(350i))));
  var v_firstNormal: vec3<f32> = f_v3(f32(0i), f32(0i), f32(0i), cw_thread, cw_block, cw_grid);
  var v_firstMat: f32 = f32((-9i));
  var v_firstDistance: f32 = f32(350i);
  var v_under: i32 = 0i;
  b_albedo[v_pixel] = vec4<f32>(f32(0i), f32(0i), f32(0i), f32(0i));
  {
    var v_bounce: i32 = 0i;
    loop {
      if (!(v_bounce < 6i)) { break; }
      if ((v_bounce >= cw_params.p_bounces)) {
        break;
      }
      let cw_value_copy_9 = f_cw_buffer_helper_0(0i, 0i, 0i, 0i, 0i, v_ro, v_rd, f32(350i), v_loc, v_tm, 0i, v_referenceGeometry, cw_thread, cw_block, cw_grid);
      var v_hit: cw_struct_Hit = cw_struct_Hit(cw_value_copy_9.cw_field_t, cw_value_copy_9.cw_field_id, cw_value_copy_9.cw_field_normal);
      if ((v_hit.cw_field_id == (-9i))) {
        v_light = v_light + (v_throughput * f_sky(v_rd, v_hour, cw_thread, cw_block, cw_grid));
        break;
      }
      var v_p: vec3<f32> = (v_ro + (v_rd * vec3<f32>(v_hit.cw_field_t)));
      var v_n: vec3<f32> = v_hit.cw_field_normal;
      var v_mat: i32 = f_cw_buffer_helper_1(0i, v_hit.cw_field_id, cw_thread, cw_block, cw_grid);
      if ((v_bounce == 0i)) {
        v_firstPoint = v_p;
        v_firstNormal = v_n;
        v_firstMat = f32(v_hit.cw_field_id);
        v_firstDistance = v_hit.cw_field_t;
      }
      if ((v_under != 0i)) {
        var v_trans: vec3<f32> = f_v3(exp(((-v_hit.cw_field_t) * 0.32f)), exp(((-v_hit.cw_field_t) * 0.17f)), exp(((-v_hit.cw_field_t) * 0.48f)), cw_thread, cw_block, cw_grid);
        var v_scatter: vec3<f32> = (f_sky(f_v3(f32(0i), 0.4f, f32(1i), cw_thread, cw_block, cw_grid), v_hour, cw_thread, cw_block, cw_grid) * f_v3(0.075f, 0.16f, 0.052f, cw_thread, cw_block, cw_grid));
        v_light = v_light + ((v_throughput * (f_v3(f32(1i), f32(1i), f32(1i), cw_thread, cw_block, cw_grid) - v_trans)) * v_scatter);
        v_throughput = v_throughput * v_trans;
      }
      if ((v_hit.cw_field_id == (-2i))) {
        if ((f_dot3(v_rd, v_n, cw_thread, cw_block, cw_grid) > f32(0i))) {
          v_n = (v_n * vec3<f32>((-1.0f)));
        }
        var v_cosI: f32 = f_clampf((-f_dot3(v_rd, v_n, cw_thread, cw_block, cw_grid)), f32(0i), f32(1i), cw_thread, cw_block, cw_grid);
        var v_fresnel: f32 = (0.0204f + (0.9796f * cw_pow_f32((f32(1i) - v_cosI), f32(5i))));
        var v_waterDepth: f32 = max(f32(0i), (0.16f - f_cw_buffer_helper_2(0i, v_p.x, v_p.z, v_loc, cw_thread, cw_block, cw_grid)));
        v_fresnel = (v_fresnel * f_mixf(0.1f, 1.0f, f_smoothf(0.025f, 1.15f, v_waterDepth, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid));
        var v_probability: f32 = f_clampf(v_fresnel, 0.18f, 0.88f, cw_thread, cw_block, cw_grid);
        var v_refl: vec3<f32> = f_unit(f_reflect3(v_rd, v_n, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
        var v_highlight: f32 = cw_pow_f32(max(0.0f, f_dot3(v_refl, v_sun, cw_thread, cw_block, cw_grid)), 1400.0f);
        if (((v_highlight > 0.001f) && (v_sun.y > f32(0i)))) {
          let cw_value_copy_10 = f_cw_buffer_helper_0(0i, 0i, 0i, 0i, 0i, (v_p + (v_n * vec3<f32>(0.01f))), v_sun, f32(160i), v_loc, v_tm, 1i, v_referenceGeometry, cw_thread, cw_block, cw_grid);
          var v_sh: cw_struct_Hit = cw_struct_Hit(cw_value_copy_10.cw_field_t, cw_value_copy_10.cw_field_id, cw_value_copy_10.cw_field_normal);
          if ((v_sh.cw_field_id == (-9i))) {
            v_light = v_light + ((v_throughput * v_sunE) * vec3<f32>(((v_highlight * v_fresnel) * 8.0f)));
          }
        }
        if ((f_rnd(((v_seed + (u32(v_bounce) * 131u)) + 10u), cw_thread, cw_block, cw_grid) < v_probability)) {
          v_throughput = v_throughput * vec3<f32>(cw_divide_f32(v_fresnel, v_probability));
          v_rd = v_refl;
          v_ro = (v_p + (v_n * vec3<f32>(0.013f)));
          v_under = 0i;
        } else {
          var cw_tmp_11: f32;
          if ((v_under != 0i)) {
            cw_tmp_11 = 1.333f;
          } else {
            cw_tmp_11 = 0.75019f;
          }
          var v_eta: f32 = cw_tmp_11;
          var v_k: f32 = (f32(1i) - ((v_eta * v_eta) * (f32(1i) - (v_cosI * v_cosI))));
          if ((v_k < f32(0i))) {
            v_rd = v_refl;
            v_ro = (v_p + (v_n * vec3<f32>(0.013f)));
          } else {
            v_rd = f_unit(((v_rd * vec3<f32>(v_eta)) + (v_n * vec3<f32>(((v_eta * v_cosI) - sqrt(v_k))))), cw_thread, cw_block, cw_grid);
            v_ro = (v_p - (v_n * vec3<f32>(0.013f)));
            var cw_tmp_12: i32;
            if ((v_under == 0i)) {
              cw_tmp_12 = 1i;
            } else {
              cw_tmp_12 = 0i;
            }
            v_under = cw_tmp_12;
            v_throughput = v_throughput * vec3<f32>(cw_divide_f32((f32(1i) - v_fresnel), (f32(1i) - v_probability)));
          }
        }
        continue;
      }
      var cw_tmp_13: i32;
      if ((f_dot3(v_n, v_rd, cw_thread, cw_block, cw_grid) > f32(0i))) {
        cw_tmp_13 = 1i;
      } else {
        cw_tmp_13 = 0i;
      }
      var v_back: i32 = cw_tmp_13;
      if ((v_back != 0i)) {
        v_n = (v_n * vec3<f32>((-1.0f)));
      }
      var v_footprint: f32 = cw_divide_f32((v_firstDistance * 0.8f), f32(cw_params.p_height));
      var v_colour: vec3<f32> = f_cw_buffer_helper_3(0i, 0i, v_hit, v_p, v_loc, v_footprint, cw_thread, cw_block, cw_grid);
      if ((v_bounce == 0i)) {
        b_albedo[v_pixel] = f_v4(v_colour, f32(v_mat), cw_thread, cw_block, cw_grid);
      }
      if ((((v_bounce == 0i) && (cw_params.p_reuseLighting != 0i)) && ((((v_x + v_y) + cw_params.p_frame) & 1i) == 0i))) {
        let cw_argument_index_14 = 13i;
        let cw_argument_index_15 = 14i;
        var v_q: vec3<f32> = (v_p - f_cameraOrigin(b_state[cw_argument_index_14], b_state[cw_argument_index_15], cw_thread, cw_block, cw_grid));
        var v_depth: f32 = f_dot3(v_q, f_cameraForward(cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
        var v_px: i32 = i32(floor((((cw_divide_f32(v_q.x, ((v_depth * 0.4f) * v_aspect)) * 0.5f) + 0.5f) * f32(cw_params.p_width))));
        var v_py: i32 = i32(floor(((0.5f - cw_divide_f32(f_dot3(v_q, f_cameraUp(cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid), (v_depth * 0.8f))) * f32(cw_params.p_height))));
        if ((((((v_px >= 0i) && (v_py >= 0i)) && (v_px < cw_params.p_width)) && (v_py < cw_params.p_height)) && (v_depth > f32(0i)))) {
          var v_j: i32 = ((v_py * cw_params.p_width) + v_px);
          var v_og: vec4<f32> = b_oldGuide[v_j];
          var v_on: vec4<f32> = b_oldNormals[v_j];
          var v_oh: vec4<f32> = b_oldHistory[v_j];
          var v_age: f32 = (f_fractf(v_oh.w, cw_thread, cw_block, cw_grid) * 16.0f);
          if ((((((v_og.w == f32(v_hit.cw_field_id)) && (f_dot3(f_xyz(v_on, cw_thread, cw_block, cw_grid), v_firstNormal, cw_thread, cw_block, cw_grid) > 0.96f)) && (f_len3((f_xyz(v_og, cw_thread, cw_block, cw_grid) - v_p), cw_thread, cw_block, cw_grid) < (0.015f + (v_hit.cw_field_t * 0.0014f)))) && (floor(v_oh.w) >= f32(1i))) && (v_age < 0.5f))) {
            b_radiance[v_pixel] = f_v4(f_xyz(v_oh, cw_thread, cw_block, cw_grid), f32((-1i)), cw_thread, cw_block, cw_grid);
            b_guide[v_pixel] = f_v4(v_firstPoint, v_firstMat, cw_thread, cw_block, cw_grid);
            b_normals[v_pixel] = f_v4(v_firstNormal, v_firstDistance, cw_thread, cw_block, cw_grid);
            return;
          }
        }
      }
      if (((v_mat == 1i) || (v_mat == 4i))) {
        var cw_tmp_16: f32;
        if ((v_mat == 1i)) {
          cw_tmp_16 = 18.0f;
        } else {
          cw_tmp_16 = 48.0f;
        }
        var v_freq: f32 = cw_tmp_16;
        var v_q: vec3<f32> = (v_p * vec3<f32>(v_freq));
        var v_e: f32 = 0.08f;
        var v_gradient: vec3<f32> = f_v3((f_noise3((v_q + f_v3(v_e, f32(0i), f32(0i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid) - f_noise3((v_q - f_v3(v_e, f32(0i), f32(0i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid)), (f_noise3((v_q + f_v3(f32(0i), v_e, f32(0i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid) - f_noise3((v_q - f_v3(f32(0i), v_e, f32(0i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid)), (f_noise3((v_q + f_v3(f32(0i), f32(0i), v_e, cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid) - f_noise3((v_q - f_v3(f32(0i), f32(0i), v_e, cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid);
        v_gradient = v_gradient - (v_n * vec3<f32>(f_dot3(v_gradient, v_n, cw_thread, cw_block, cw_grid)));
        var cw_tmp_17: f32;
        if ((v_mat == 1i)) {
          cw_tmp_17 = 1.2f;
        } else {
          cw_tmp_17 = 0.85f;
        }
        v_n = f_unit((v_n - (v_gradient * vec3<f32>(cw_tmp_17))), cw_thread, cw_block, cw_grid);
      }
      if ((v_mat == (-1i))) {
        var v_e: f32 = 0.001f;
        var v_gx: f32 = (f_cw_buffer_helper_4(0i, ((v_p.x * 0.25f) + v_e), (v_p.z * 0.25f), 0i, (v_footprint * 0.25f), cw_thread, cw_block, cw_grid).w - f_cw_buffer_helper_4(0i, ((v_p.x * 0.25f) - v_e), (v_p.z * 0.25f), 0i, (v_footprint * 0.25f), cw_thread, cw_block, cw_grid).w);
        var v_gz: f32 = (f_cw_buffer_helper_4(0i, (v_p.x * 0.25f), ((v_p.z * 0.25f) + v_e), 0i, (v_footprint * 0.25f), cw_thread, cw_block, cw_grid).w - f_cw_buffer_helper_4(0i, (v_p.x * 0.25f), ((v_p.z * 0.25f) - v_e), 0i, (v_footprint * 0.25f), cw_thread, cw_block, cw_grid).w);
        v_n = f_unit((v_n - (f_v3(v_gx, f32(0i), v_gz, cw_thread, cw_block, cw_grid) * vec3<f32>(1.1f))), cw_thread, cw_block, cw_grid);
      }
      var cw_tmp_18: f32;
      if (((v_mat == 2i) || (v_mat == 8i))) {
        cw_tmp_18 = 0.22f;
      } else {
        cw_tmp_18 = 0.0f;
      }
      var v_transmission: f32 = cw_tmp_18;
      var v_su: vec3<f32> = f_tangent(v_sun, cw_thread, cw_block, cw_grid);
      var v_sv: vec3<f32> = f_cross3(v_sun, v_su, cw_thread, cw_block, cw_grid);
      var v_a: f32 = (6.28318530718f * f_rnd(((v_seed + (u32(v_bounce) * 117u)) + 34u), cw_thread, cw_block, cw_grid));
      var v_rad: f32 = (sqrt(f_rnd(((v_seed + (u32(v_bounce) * 83u)) + 22u), cw_thread, cw_block, cw_grid)) * 0.017f);
      var v_ld: vec3<f32> = f_unit(((v_sun + (v_su * vec3<f32>((cos(v_a) * v_rad)))) + (v_sv * vec3<f32>((sin(v_a) * v_rad)))), cw_thread, cw_block, cw_grid);
      var v_nd: f32 = f_dot3(v_n, v_ld, cw_thread, cw_block, cw_grid);
      var v_cosine: f32 = ((max(f32(0i), v_nd) * (f32(1i) - v_transmission)) + (max(f32(0i), (-v_nd)) * v_transmission));
      if (((v_cosine > 0.001f) && (v_sun.y > (-0.03f)))) {
        var cw_tmp_19: vec3<f32>;
        if ((v_nd >= f32(0i))) {
          cw_tmp_19 = v_n;
        } else {
          cw_tmp_19 = (v_n * vec3<f32>(f32((-1i))));
        }
        var v_side: vec3<f32> = cw_tmp_19;
        let cw_value_copy_20 = f_cw_buffer_helper_0(0i, 0i, 0i, 0i, 0i, (v_p + (v_side * vec3<f32>(0.008f))), v_ld, f32(180i), v_loc, v_tm, 1i, v_referenceGeometry, cw_thread, cw_block, cw_grid);
        var v_shadow: cw_struct_Hit = cw_struct_Hit(cw_value_copy_20.cw_field_t, cw_value_copy_20.cw_field_id, cw_value_copy_20.cw_field_normal);
        var cw_tmp_21: f32;
        if ((v_under != 0i)) {
          cw_tmp_21 = cw_divide_f32(max(f32(0i), (0.16f - v_p.y)), max(0.12f, v_ld.y));
        } else {
          cw_tmp_21 = f32(0i);
        }
        var v_sunPath: f32 = cw_tmp_21;
        var v_waterSun: vec3<f32> = f_v3(exp(((-v_sunPath) * 0.32f)), exp(((-v_sunPath) * 0.17f)), exp(((-v_sunPath) * 0.48f)), cw_thread, cw_block, cw_grid);
        if ((v_shadow.cw_field_id == (-9i))) {
          v_light = v_light + ((((v_throughput * v_colour) * v_sunE) * v_waterSun) * vec3<f32>(cw_divide_f32(v_cosine, 3.14159265359f)));
        }
      }
      if (((v_bounce + 1i) >= cw_params.p_bounces)) {
        break;
      }
      v_throughput = v_throughput * v_colour;
      var v_hemisphere: vec3<f32> = v_n;
      if ((((v_mat == 2i) || (v_mat == 8i)) && (f_rnd(((v_seed + (u32(v_bounce) * 197u)) + 54u), cw_thread, cw_block, cw_grid) < v_transmission))) {
        v_hemisphere = (v_n * vec3<f32>(f32((-1i))));
      }
      v_rd = f_cosineRay(v_hemisphere, f_rnd(((v_seed + (u32(v_bounce) * 71u)) + 61u), cw_thread, cw_block, cw_grid), f_rnd(((v_seed + (u32(v_bounce) * 97u)) + 89u), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
      v_ro = (v_p + (v_hemisphere * vec3<f32>(0.008f)));
      if ((v_bounce >= 1i)) {
        var v_survival: f32 = f_clampf(max(v_throughput.x, max(v_throughput.y, v_throughput.z)), 0.1f, 0.95f, cw_thread, cw_block, cw_grid);
        if ((f_rnd(((v_seed + (u32(v_bounce) * 353u)) + 17u), cw_thread, cw_block, cw_grid) > v_survival)) {
          break;
        }
        v_throughput = v_throughput / vec3<f32>(v_survival);
      }
      continuing {
        v_bounce += i32(1);
      }
    }
  }
  var v_fog: f32 = (f32(1i) - exp(((-max(f32(0i), (v_firstDistance - f32(20i)))) * 0.0028f)));
  v_light = f_mix3(v_light, (f_sky(f_v3(f32(0i), 0.06f, f32(1i), cw_thread, cw_block, cw_grid), v_hour, cw_thread, cw_block, cw_grid) * vec3<f32>(0.56f)), v_fog, cw_thread, cw_block, cw_grid);
  b_radiance[v_pixel] = f_v4(f_max3(v_light, f_v3(f32(0i), f32(0i), f32(0i), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid), f32(1i), cw_thread, cw_block, cw_grid);
  b_guide[v_pixel] = f_v4(v_firstPoint, v_firstMat, cw_thread, cw_block, cw_grid);
  b_normals[v_pixel] = f_v4(v_firstNormal, v_firstDistance, cw_thread, cw_block, cw_grid);
}
