// CUDA WebShader 0.1.1. Generated from kernel updateLeafMotion.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read> b_objects: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read> b_order: array<u32>;
@group(0) @binding(2) var<storage, read_write> b_rayGeometry: array<vec4<f32>>;
struct CWParams {
  p_time: f32,
  cw_pad_4: u32,
  cw_pad_8: u32,
  cw_pad_12: u32,
}
@group(0) @binding(3) var<uniform> cw_params: CWParams;
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









fn f_windOffset(cw_arg_p: vec3<f32>, cw_arg_time: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_p: vec3<f32> = cw_arg_p;
  var v_time: f32 = cw_arg_time;
  var v_phase: f32 = ((v_p.x * 0.31f) + (v_p.z * 0.17f));
  return f_v3(((sin((v_phase + (v_time * 1.5f))) - sin(v_phase)) * 0.045f), ((cos((v_phase + (v_time * 1.1f))) - cos(v_phase)) * 0.008f), ((sin(((v_phase * 1.3f) + (v_time * 1.24f))) - sin((v_phase * 1.3f))) * 0.025f), cw_thread, cw_block, cw_grid);
}




































@compute @workgroup_size(128, 1, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  var v_rank: i32 = i32(((cw_block.x * cw_block_size.x) + cw_thread.x));
  if ((v_rank >= 524288i)) {
    return;
  }
  let cw_argument_index_6 = v_rank;
  var v_id: i32 = i32(b_order[cw_argument_index_6]);
  var v_mat: i32 = i32(b_objects[((v_id * 4i) + 2i)].w);
  if (((v_mat == 2i) || (v_mat == 8i))) {
    var v_a: vec4<f32> = b_objects[(v_id * 4i)];
    b_rayGeometry[(v_rank * 4i)] = f_v4((f_xyz(v_a, cw_thread, cw_block, cw_grid) + f_windOffset(f_xyz(v_a, cw_thread, cw_block, cw_grid), cw_params.p_time, cw_thread, cw_block, cw_grid)), v_a.w, cw_thread, cw_block, cw_grid);
  }
}
