// CUDA WebShader 0.1.1. Generated from kernel spatialKeys.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read> b_objects: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read_write> b_keys: array<u32>;
@group(0) @binding(2) var<storage, read_write> b_order: array<u32>;
const cw_block_size: vec3<u32> = vec3<u32>(128u, 1u, 1u);

fn cw_divide_f32(a: f32, b: f32) -> f32 { let q = a / b; if ((bitcast<u32>(q) & 0x7f800000u) == 0x7f800000u || (bitcast<u32>(q) & 0x7fffffffu) == 0u || (bitcast<u32>(b) & 0x7f800000u) == 0x7f800000u) { return q; } let residual = fma(-q, b, a); return q + residual / b; }

alias cw_f64 = vec2<u32>;










struct CWDoubleParts { significand: vec2<u32>, exponent: i32, }

// Input has its leading bit at bit 55 and three guard/round/sticky bits.














// Restoring square root: 56 root bits include guard/round/sticky for binary64.





fn f_clampf(cw_arg_x: f32, cw_arg_a: f32, cw_arg_b: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: f32 = cw_arg_x;
  var v_a: f32 = cw_arg_a;
  var v_b: f32 = cw_arg_b;
  return min(v_b, max(v_a, v_x));
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






























fn f_spreadBits(cw_arg_n: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> u32 {
  var v_n: u32 = cw_arg_n;
  var v_x: u32 = (v_n & 1023u);
  v_x = ((v_x | (v_x << u32(16i))) & 50331903u);
  v_x = ((v_x | (v_x << u32(8i))) & 50393103u);
  v_x = ((v_x | (v_x << u32(4i))) & 51130563u);
  v_x = ((v_x | (v_x << u32(2i))) & 153391689u);
  return v_x;
}
















@compute @workgroup_size(128, 1, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  var v_id: i32 = i32(((cw_block.x * cw_block_size.x) + cw_thread.x));
  if ((v_id >= 524288i)) {
    return;
  }
  let cw_argument_index_6 = (v_id * 4i);
  var v_p: vec3<f32> = f_xyz(b_objects[cw_argument_index_6], cw_thread, cw_block, cw_grid);
  if ((b_objects[((v_id * 4i) + 3i)].w > 0.5f)) {
    let cw_argument_index_7 = ((v_id * 4i) + 1i);
    v_p = ((v_p + f_xyz(b_objects[cw_argument_index_7], cw_thread, cw_block, cw_grid)) * vec3<f32>(0.5f));
  }
  var v_q: vec3<f32> = ((v_p + f_v3(f32(144i), f32(8i), f32(16i), cw_thread, cw_block, cw_grid)) * vec3<f32>(cw_divide_f32(1023.0f, 288.0f)));
  b_keys[v_id] = ((f_spreadBits(u32(f_clampf(v_q.x, f32(0i), f32(1023i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid) | (f_spreadBits(u32(f_clampf(v_q.y, f32(0i), f32(1023i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid) << u32(1i))) | (f_spreadBits(u32(f_clampf(v_q.z, f32(0i), f32(1023i), cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid) << u32(2i)));
  b_order[v_id] = u32(v_id);
}
