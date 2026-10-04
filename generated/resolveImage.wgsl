// CUDA WebShader 0.1.1. Generated from kernel resolveImage.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read> b_source: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read_write> b_pixels: array<u32>;
struct CWParams {
  p_width: i32,
  p_height: i32,
  p_exposure: f32,
  p_bgra: i32,
}
@group(0) @binding(2) var<uniform> cw_params: CWParams;
const cw_block_size: vec3<u32> = vec3<u32>(8u, 8u, 1u);

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










































fn f_film(cw_arg_v: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_v: f32 = cw_arg_v;
  v_v = max(f32(0i), v_v);
  return f_sat(cw_divide_f32((v_v * ((2.51f * v_v) + 0.03f)), ((v_v * ((2.43f * v_v) + 0.59f)) + 0.14f)), cw_thread, cw_block, cw_grid);
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

@compute @workgroup_size(8, 8, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  var v_x: i32 = i32(((cw_block.x * cw_block_size.x) + cw_thread.x));
  var v_y: i32 = i32(((cw_block.y * cw_block_size.y) + cw_thread.y));
  if (((v_x >= cw_params.p_width) || (v_y >= cw_params.p_height))) {
    return;
  }
  var v_i: i32 = ((v_y * cw_params.p_width) + v_x);
  let cw_argument_index_6 = v_i;
  var v_c: vec3<f32> = (f_xyz(b_source[cw_argument_index_6], cw_thread, cw_block, cw_grid) * vec3<f32>(cw_params.p_exposure));
  v_c = f_v3(cw_pow_f32(f_film(v_c.x, cw_thread, cw_block, cw_grid), cw_divide_f32(1.0f, 2.2f)), cw_pow_f32(f_film(v_c.y, cw_thread, cw_block, cw_grid), cw_divide_f32(1.0f, 2.2f)), cw_pow_f32(f_film(v_c.z, cw_thread, cw_block, cw_grid), cw_divide_f32(1.0f, 2.2f)), cw_thread, cw_block, cw_grid);
  var v_r: u32 = u32(((v_c.x * f32(255i)) + 0.5f));
  var v_g: u32 = u32(((v_c.y * f32(255i)) + 0.5f));
  var v_b: u32 = u32(((v_c.z * f32(255i)) + 0.5f));
  var cw_tmp_7: u32;
  if ((cw_params.p_bgra != 0i)) {
    cw_tmp_7 = (((v_b | (v_g << u32(8i))) | (v_r << u32(16i))) | 4278190080u);
  } else {
    cw_tmp_7 = (((v_r | (v_g << u32(8i))) | (v_b << u32(16i))) | 4278190080u);
  }
  b_pixels[v_i] = cw_tmp_7;
}
