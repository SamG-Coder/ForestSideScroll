// CUDA WebShader 0.1.1. Generated from kernel filterImage.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read> b_source: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read> b_guide: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read> b_normals: array<vec4<f32>>;
@group(0) @binding(3) var<storage, read> b_albedo: array<vec4<f32>>;
@group(0) @binding(4) var<storage, read> b_oldImage: array<vec4<f32>>;
@group(0) @binding(5) var<storage, read> b_oldGuide: array<vec4<f32>>;
@group(0) @binding(6) var<storage, read> b_oldNormals: array<vec4<f32>>;
@group(0) @binding(7) var<storage, read> b_oldCoverage: array<vec4<f32>>;
@group(0) @binding(8) var<storage, read> b_state: array<f32>;
@group(0) @binding(9) var<storage, read_write> b_filtered: array<vec4<f32>>;
@group(0) @binding(10) var<storage, read_write> b_coverage: array<vec4<f32>>;
struct CWParams {
  p_width: i32,
  p_height: i32,
  p_step: i32,
  p_reset: i32,
  p_frozen: i32,
  cw_pad_20: u32,
  cw_pad_24: u32,
  cw_pad_28: u32,
}
@group(0) @binding(11) var<uniform> cw_params: CWParams;
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
fn f_mixf(cw_arg_a: f32, cw_arg_b: f32, cw_arg_t: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_a: f32 = cw_arg_a;
  var v_b: f32 = cw_arg_b;
  var v_t: f32 = cw_arg_t;
  return (v_a + ((v_b - v_a) * v_t));
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

fn f_mix3(cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_arg_t: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  var v_t: f32 = cw_arg_t;
  return (v_a + ((v_b - v_a) * vec3<f32>(v_t)));
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
  var v_centre: vec4<f32> = b_source[v_i];
  var v_g: vec4<f32> = b_guide[v_i];
  var v_n: vec4<f32> = b_normals[v_i];
  var v_sum: vec3<f32> = (f_xyz(v_centre, cw_thread, cw_block, cw_grid) * vec3<f32>(f32(4i)));
  var v_weights: f32 = f32(4i);
  {
    var v_yy: i32 = (-1i);
    loop {
      if (!(v_yy <= 1i)) { break; }
      {
        var v_xx: i32 = (-1i);
        loop {
          if (!(v_xx <= 1i)) { break; }
          if (((v_xx == 0i) && (v_yy == 0i))) {
            continue;
          }
          var v_px: i32 = (v_x + (v_xx * cw_params.p_step));
          var v_py: i32 = (v_y + (v_yy * cw_params.p_step));
          if (((((v_px < 0i) || (v_py < 0i)) || (v_px >= cw_params.p_width)) || (v_py >= cw_params.p_height))) {
            continue;
          }
          var v_j: i32 = ((v_py * cw_params.p_width) + v_px);
          var v_ng: vec4<f32> = b_guide[v_j];
          var v_nn: vec4<f32> = b_normals[v_j];
          var v_mat: i32 = i32(b_albedo[v_i].w);
          var cw_tmp_6: i32;
          if ((((v_mat == 2i) || (v_mat == 3i)) || (v_mat == 8i))) {
            cw_tmp_6 = 1i;
          } else {
            cw_tmp_6 = 0i;
          }
          var v_foliage: i32 = cw_tmp_6;
          if (((v_ng.w != v_g.w) && ((v_foliage == 0i) || (b_albedo[v_j].w != b_albedo[v_i].w)))) {
            continue;
          }
          var cw_tmp_7: f32;
          if ((v_g.w < f32(0i))) {
            cw_tmp_7 = f32(1i);
          } else {
            cw_tmp_7 = cw_pow_f32(max(f32(0i), f_dot3(f_xyz(v_n, cw_thread, cw_block, cw_grid), f_xyz(v_nn, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid)), f32(24i));
          }
          var v_normalWeight: f32 = cw_tmp_7;
          if ((v_foliage != 0i)) {
            v_normalWeight = (0.35f + (0.65f * abs(f_dot3(f_xyz(v_n, cw_thread, cw_block, cw_grid), f_xyz(v_nn, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid))));
          }
          var cw_tmp_8: f32;
          if ((v_foliage != 0i)) {
            cw_tmp_8 = 0.016f;
          } else {
            cw_tmp_8 = 0.006f;
          }
          var v_depthWeight: f32 = exp(cw_divide_f32((-abs((v_nn.w - v_n.w))), (0.05f + ((v_n.w * cw_tmp_8) * f32(cw_params.p_step)))));
          let cw_argument_index_13 = v_i;
          let cw_argument_index_14 = v_j;
          var v_colourWeight: f32 = exp(((-f_len3((f_xyz(b_albedo[cw_argument_index_13], cw_thread, cw_block, cw_grid) - f_xyz(b_albedo[cw_argument_index_14], cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid)) * 14.0f));
          var cw_tmp_15: f32;
          if (((v_xx == 0i) || (v_yy == 0i))) {
            cw_tmp_15 = 2.0f;
          } else {
            cw_tmp_15 = 1.0f;
          }
          var v_w: f32 = (((v_normalWeight * v_depthWeight) * v_colourWeight) * cw_tmp_15);
          let cw_argument_index_16 = v_j;
          v_sum = v_sum + (f_xyz(b_source[cw_argument_index_16], cw_thread, cw_block, cw_grid) * vec3<f32>(v_w));
          v_weights = (v_weights + v_w);
          continuing {
            v_xx += i32(1);
          }
        }
      }
      continuing {
        v_yy += i32(1);
      }
    }
  }
  var v_strength: f32 = f_mixf(0.95f, 0.15f, f_sat(cw_divide_f32(v_centre.w, 100.0f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_colour: vec3<f32> = f_mix3(f_xyz(v_centre, cw_thread, cw_block, cw_grid), (v_sum / vec3<f32>(v_weights)), v_strength, cw_thread, cw_block, cw_grid);
  var v_samples: f32 = v_centre.w;
  if ((cw_params.p_step == 2i)) {
    var v_mask: vec4<f32> = vec4<f32>(f32(0i), f32(0i), f32(0i), f32(0i));
    var v_mat: i32 = i32(b_albedo[v_i].w);
    if ((v_g.w == f32((-2i)))) {
      v_mask.w = f32(1i);
    } else {
      if (((v_g.w == f32((-1i))) || (v_mat == 1i))) {
        v_mask.x = f32(1i);
      } else {
        if ((v_mat == 4i)) {
          v_mask.y = f32(1i);
        } else {
          if ((((v_mat == 2i) || (v_mat == 3i)) || (v_mat == 8i))) {
            v_mask.z = f32(1i);
          }
        }
      }
    }
    v_samples = f32(1i);
    if ((cw_params.p_reset == 0i)) {
      var v_cameraMotion: f32 = (abs((b_state[11i] - b_state[13i])) + abs((b_state[12i] - b_state[14i])));
      var v_previous: vec3<f32> = f_v3(f32(0i), f32(0i), f32(0i), cw_thread, cw_block, cw_grid);
      var v_previousMask: vec4<f32> = vec4<f32>(f32(0i), f32(0i), f32(0i), f32(0i));
      var v_previousCount: f32 = f32(0i);
      var v_validWeight: f32 = f32(0i);
      if ((v_cameraMotion < 0.000001f)) {
        var v_h: vec4<f32> = b_oldImage[v_i];
        v_previous = f_xyz(v_h, cw_thread, cw_block, cw_grid);
        v_previousMask = b_oldCoverage[v_i];
        v_previousCount = v_h.w;
        var cw_tmp_17: f32;
        if ((v_h.w >= f32(1i))) {
          cw_tmp_17 = 1.0f;
        } else {
          cw_tmp_17 = 0.0f;
        }
        v_validWeight = cw_tmp_17;
      } else {
        let cw_argument_index_18 = 13i;
        let cw_argument_index_19 = 14i;
        var v_q: vec3<f32> = (f_xyz(v_g, cw_thread, cw_block, cw_grid) - f_cameraOrigin(b_state[cw_argument_index_18], b_state[cw_argument_index_19], cw_thread, cw_block, cw_grid));
        var v_depth: f32 = f_dot3(v_q, f_cameraForward(cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
        var v_u: f32 = ((((cw_divide_f32(v_q.x, ((v_depth * 0.4f) * cw_divide_f32(f32(cw_params.p_width), f32(cw_params.p_height)))) * 0.5f) + 0.5f) * f32(cw_params.p_width)) - 0.5f);
        var v_v: f32 = (((0.5f - cw_divide_f32(f_dot3(v_q, f_cameraUp(cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid), (v_depth * 0.8f))) * f32(cw_params.p_height)) - 0.5f);
        var v_px: i32 = i32(floor(v_u));
        var v_py: i32 = i32(floor(v_v));
        var v_fx: f32 = f_fractf(v_u, cw_thread, cw_block, cw_grid);
        var v_fy: f32 = f_fractf(v_v, cw_thread, cw_block, cw_grid);
        {
          var v_yy: i32 = 0i;
          loop {
            if (!(v_yy < 2i)) { break; }
            {
              var v_xx: i32 = 0i;
              loop {
                if (!(v_xx < 2i)) { break; }
                var v_hx: i32 = (v_px + v_xx);
                var v_hy: i32 = (v_py + v_yy);
                if ((((((v_depth <= f32(0i)) || (v_hx < 0i)) || (v_hy < 0i)) || (v_hx >= cw_params.p_width)) || (v_hy >= cw_params.p_height))) {
                  continue;
                }
                var v_j: i32 = ((v_hy * cw_params.p_width) + v_hx);
                var v_og: vec4<f32> = b_oldGuide[v_j];
                var v_on: vec4<f32> = b_oldNormals[v_j];
                var v_h: vec4<f32> = b_oldImage[v_j];
                var v_distance: f32 = f_len3((f_xyz(v_og, cw_thread, cw_block, cw_grid) - f_xyz(v_g, cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid);
                var v_normal: f32 = f_dot3(f_xyz(v_n, cw_thread, cw_block, cw_grid), f_xyz(v_on, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
                if ((((v_h.w < f32(1i)) || (v_distance > (0.08f + (v_n.w * 0.01f)))) || ((v_g.w != v_og.w) && (v_normal < 0.65f)))) {
                  continue;
                }
                var cw_tmp_20: f32;
                if ((v_xx == 0i)) {
                  cw_tmp_20 = (f32(1i) - v_fx);
                } else {
                  cw_tmp_20 = v_fx;
                }
                var cw_tmp_21: f32;
                if ((v_yy == 0i)) {
                  cw_tmp_21 = (f32(1i) - v_fy);
                } else {
                  cw_tmp_21 = v_fy;
                }
                var v_w: f32 = (cw_tmp_20 * cw_tmp_21);
                v_previous = v_previous + (f_xyz(v_h, cw_thread, cw_block, cw_grid) * vec3<f32>(v_w));
                v_previousMask = v_previousMask + (b_oldCoverage[v_j] * vec4<f32>(v_w));
                v_previousCount = (v_previousCount + (v_h.w * v_w));
                v_validWeight = (v_validWeight + v_w);
                continuing {
                  v_xx += i32(1);
                }
              }
            }
            continuing {
              v_yy += i32(1);
            }
          }
        }
        if ((v_validWeight > f32(0i))) {
          v_previous = v_previous / vec3<f32>(v_validWeight);
          v_previousMask = v_previousMask / vec4<f32>(v_validWeight);
          v_previousCount = cw_divide_f32(v_previousCount, v_validWeight);
        }
      }
      if ((v_validWeight > 0.2f)) {
        if ((v_cameraMotion >= 0.000001f)) {
          var v_lo: vec3<f32> = v_colour;
          var v_hi: vec3<f32> = v_colour;
          {
            var v_yy: i32 = (-1i);
            loop {
              if (!(v_yy <= 1i)) { break; }
              {
                var v_xx: i32 = (-1i);
                loop {
                  if (!(v_xx <= 1i)) { break; }
                  var v_px: i32 = (v_x + v_xx);
                  var v_py: i32 = (v_y + v_yy);
                  if (((((v_px < 0i) || (v_py < 0i)) || (v_px >= cw_params.p_width)) || (v_py >= cw_params.p_height))) {
                    continue;
                  }
                  let cw_argument_index_22 = ((v_py * cw_params.p_width) + v_px);
                  var v_c: vec3<f32> = f_xyz(b_source[cw_argument_index_22], cw_thread, cw_block, cw_grid);
                  v_lo = f_min3(v_lo, v_c, cw_thread, cw_block, cw_grid);
                  v_hi = f_max3(v_hi, v_c, cw_thread, cw_block, cw_grid);
                  continuing {
                    v_xx += i32(1);
                  }
                }
              }
              continuing {
                v_yy += i32(1);
              }
            }
          }
          var v_margin: vec3<f32> = (((v_hi - v_lo) * vec3<f32>(0.08f)) + f_v3(0.002f, 0.002f, 0.002f, cw_thread, cw_block, cw_grid));
          v_previous = f_max3((v_lo - v_margin), f_min3((v_hi + v_margin), v_previous, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
        }
        var cw_tmp_24: f32;
        if ((cw_params.p_frozen != 0i)) {
          cw_tmp_24 = 128.0f;
        } else {
          var cw_tmp_23: f32;
          if ((v_g.w == f32((-2i)))) {
            cw_tmp_23 = 6.0f;
          } else {
            cw_tmp_23 = 12.0f;
          }
          cw_tmp_24 = cw_tmp_23;
        }
        var v_cap: f32 = cw_tmp_24;
        if ((v_cameraMotion >= 0.000001f)) {
          v_cap = f32(8i);
        }
        v_samples = min((v_previousCount + f32(1i)), v_cap);
        v_colour = f_mix3(v_previous, v_colour, cw_divide_f32(f32(1i), v_samples), cw_thread, cw_block, cw_grid);
        v_mask = (v_previousMask + ((v_mask - v_previousMask) / vec4<f32>(v_samples)));
      }
    }
    b_coverage[v_i] = v_mask;
  }
  b_filtered[v_i] = f_v4(v_colour, v_samples, cw_thread, cw_block, cw_grid);
}
