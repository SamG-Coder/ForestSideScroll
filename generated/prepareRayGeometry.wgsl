// CUDA WebShader 0.1.1. Generated from kernel prepareRayGeometry.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read> b_objects: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read> b_order: array<u32>;
@group(0) @binding(2) var<storage, read_write> b_rayGeometry: array<vec4<f32>>;
const cw_block_size: vec3<u32> = vec3<u32>(128u, 1u, 1u);

fn cw_divide_f32(a: f32, b: f32) -> f32 { let q = a / b; if ((bitcast<u32>(q) & 0x7f800000u) == 0x7f800000u || (bitcast<u32>(q) & 0x7fffffffu) == 0u || (bitcast<u32>(b) & 0x7f800000u) == 0x7f800000u) { return q; } let residual = fma(-q, b, a); return q + residual / b; }

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
  var v_a: vec4<f32> = b_objects[(v_id * 4i)];
  var v_b: vec4<f32> = b_objects[((v_id * 4i) + 1i)];
  var v_d: vec4<f32> = b_objects[((v_id * 4i) + 3i)];
  var v_mat: i32 = i32(b_objects[((v_id * 4i) + 2i)].w);
  b_rayGeometry[(v_rank * 4i)] = v_a;
  if ((v_d.w > 0.5f)) {
    var v_ba: vec3<f32> = (f_xyz(v_b, cw_thread, cw_block, cw_grid) - f_xyz(v_a, cw_thread, cw_block, cw_grid));
    var v_length: f32 = f_len3(v_ba, cw_thread, cw_block, cw_grid);
    b_rayGeometry[((v_rank * 4i) + 1i)] = v_b;
    b_rayGeometry[((v_rank * 4i) + 2i)] = f_v4((v_ba / vec3<f32>(max(v_length, 1e-8f))), v_length, cw_thread, cw_block, cw_grid);
    b_rayGeometry[((v_rank * 4i) + 3i)] = vec4<f32>(cw_divide_f32((v_b.w - v_a.w), max(v_length, 1e-8f)), f32(0i), f32(0i), f32((v_mat + 16i)));
  } else {
    var v_axis: vec3<f32> = f_xyz(v_d, cw_thread, cw_block, cw_grid);
    var v_u: vec3<f32> = f_basisU(v_axis, v_b.w, cw_thread, cw_block, cw_grid);
    var v_v: vec3<f32> = f_cross3(v_axis, v_u, cw_thread, cw_block, cw_grid);
    b_rayGeometry[((v_rank * 4i) + 1i)] = f_v4((v_u / vec3<f32>(v_b.x)), f32(0i), cw_thread, cw_block, cw_grid);
    b_rayGeometry[((v_rank * 4i) + 2i)] = f_v4((v_axis / vec3<f32>(v_b.y)), f32(0i), cw_thread, cw_block, cw_grid);
    b_rayGeometry[((v_rank * 4i) + 3i)] = f_v4((v_v / vec3<f32>(v_b.z)), f32(v_mat), cw_thread, cw_block, cw_grid);
  }
}
