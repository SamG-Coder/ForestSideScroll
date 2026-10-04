// CUDA WebShader 0.1.1. Generated from kernel materialMip.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read_write> b_atlas: array<u32>;
struct CWParams {
  p_level: i32,
  cw_pad_4: u32,
  cw_pad_8: u32,
  cw_pad_12: u32,
}
@group(0) @binding(1) var<uniform> cw_params: CWParams;
const cw_block_size: vec3<u32> = vec3<u32>(8u, 8u, 1u);



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
fn f_sat(cw_arg_x: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: f32 = cw_arg_x;
  return f_clampf(v_x, 0.0f, 1.0f, cw_thread, cw_block, cw_grid);
}





































fn f_packMaterial(cw_arg_c: vec4<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> u32 {
  var v_c: vec4<f32> = cw_arg_c;
  return (((u32(((f_sat(v_c.x, cw_thread, cw_block, cw_grid) * 255.0f) + 0.5f)) | (u32(((f_sat(v_c.y, cw_thread, cw_block, cw_grid) * 255.0f) + 0.5f)) << u32(8i))) | (u32(((f_sat(v_c.z, cw_thread, cw_block, cw_grid) * 255.0f) + 0.5f)) << u32(16i))) | (u32(((f_sat(v_c.w, cw_thread, cw_block, cw_grid) * 255.0f) + 0.5f)) << u32(24i)));
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












@compute @workgroup_size(8, 8, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  var v_x: i32 = i32(((cw_block.x * cw_block_size.x) + cw_thread.x));
  var v_y: i32 = i32(((cw_block.y * cw_block_size.y) + cw_thread.y));
  var v_size: i32 = (2048i >> u32(cw_params.p_level));
  if (((v_x >= v_size) || (v_y >= v_size))) {
    return;
  }
  var v_previous: i32 = f_mipOffset((cw_params.p_level - 1i), cw_thread, cw_block, cw_grid);
  var v_current: i32 = f_mipOffset(cw_params.p_level, cw_thread, cw_block, cw_grid);
  var v_i: i32 = ((v_previous + ((v_y * 4i) * v_size)) + (v_x * 2i));
  {
    var v_kind: i32 = 0i;
    loop {
      if (!(v_kind < 2i)) { break; }
      var v_base: i32 = (v_kind * 5592405i);
      let cw_argument_index_6 = (v_base + v_i);
      let cw_argument_index_7 = ((v_base + v_i) + 1i);
      let cw_argument_index_8 = ((v_base + v_i) + (v_size * 2i));
      let cw_argument_index_9 = (((v_base + v_i) + (v_size * 2i)) + 1i);
      var v_c: vec4<f32> = (((f_unpackMaterial(b_atlas[cw_argument_index_6], cw_thread, cw_block, cw_grid) + f_unpackMaterial(b_atlas[cw_argument_index_7], cw_thread, cw_block, cw_grid)) + f_unpackMaterial(b_atlas[cw_argument_index_8], cw_thread, cw_block, cw_grid)) + f_unpackMaterial(b_atlas[cw_argument_index_9], cw_thread, cw_block, cw_grid));
      b_atlas[(((v_base + v_current) + (v_y * v_size)) + v_x)] = f_packMaterial((v_c * vec4<f32>(0.25f)), cw_thread, cw_block, cw_grid);
      continuing {
        v_kind += i32(1);
      }
    }
  }
}
