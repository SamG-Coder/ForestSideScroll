// CUDA WebShader 0.1.1. Generated from kernel buildLevel.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read_write> b_bounds: array<vec4<f32>>;
struct CWParams {
  p_start: i32,
  p_count: i32,
  cw_pad_8: u32,
  cw_pad_12: u32,
}
@group(0) @binding(1) var<uniform> cw_params: CWParams;
const cw_block_size: vec3<u32> = vec3<u32>(128u, 1u, 1u);



alias cw_f64 = vec2<u32>;










struct CWDoubleParts { significand: vec2<u32>, exponent: i32, }

// Input has its leading bit at bit 55 and three guard/round/sticky bits.














// Restoring square root: 56 root bits include guard/round/sticky for binary64.










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








































@compute @workgroup_size(128, 1, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  var v_i: i32 = i32(((cw_block.x * cw_block_size.x) + cw_thread.x));
  if ((v_i >= cw_params.p_count)) {
    return;
  }
  var v_n: i32 = (cw_params.p_start + v_i);
  let cw_argument_index_6 = (v_n * 4i);
  let cw_argument_index_7 = ((v_n * 4i) + 2i);
  b_bounds[(v_n * 2i)] = f_v4(f_min3(f_xyz(b_bounds[cw_argument_index_6], cw_thread, cw_block, cw_grid), f_xyz(b_bounds[cw_argument_index_7], cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid), f32(0i), cw_thread, cw_block, cw_grid);
  let cw_argument_index_8 = ((v_n * 4i) + 1i);
  let cw_argument_index_9 = ((v_n * 4i) + 3i);
  b_bounds[((v_n * 2i) + 1i)] = f_v4(f_max3(f_xyz(b_bounds[cw_argument_index_8], cw_thread, cw_block, cw_grid), f_xyz(b_bounds[cw_argument_index_9], cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid), f32(0i), cw_thread, cw_block, cw_grid);
}
