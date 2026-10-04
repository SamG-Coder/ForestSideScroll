// CUDA WebShader 0.1.1. Generated from kernel accumulate.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read> b_radiance: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read> b_guide: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read> b_normals: array<vec4<f32>>;
@group(0) @binding(3) var<storage, read> b_oldGuide: array<vec4<f32>>;
@group(0) @binding(4) var<storage, read> b_oldNormals: array<vec4<f32>>;
@group(0) @binding(5) var<storage, read> b_oldHistory: array<vec4<f32>>;
@group(0) @binding(6) var<storage, read_write> b_history: array<vec4<f32>>;
@group(0) @binding(7) var<storage, read> b_state: array<f32>;
struct CWParams {
  p_width: i32,
  p_height: i32,
  p_reset: i32,
  p_frozen: i32,
}
@group(0) @binding(8) var<uniform> cw_params: CWParams;
const cw_block_size: vec3<u32> = vec3<u32>(8u, 8u, 1u);

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
  var v_g: vec4<f32> = b_guide[v_i];
  var v_n: vec4<f32> = b_normals[v_i];
  let cw_argument_index_6 = v_i;
  var v_value: vec3<f32> = f_xyz(b_radiance[cw_argument_index_6], cw_thread, cw_block, cw_grid);
  var v_count: f32 = f32(1i);
  if ((cw_params.p_reset == 0i)) {
    let cw_argument_index_7 = 13i;
    let cw_argument_index_8 = 14i;
    var v_q: vec3<f32> = (f_xyz(v_g, cw_thread, cw_block, cw_grid) - f_cameraOrigin(b_state[cw_argument_index_7], b_state[cw_argument_index_8], cw_thread, cw_block, cw_grid));
    var v_depth: f32 = f_dot3(v_q, f_cameraForward(cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
    var v_u: f32 = ((((cw_divide_f32(v_q.x, ((v_depth * 0.4f) * cw_divide_f32(f32(cw_params.p_width), f32(cw_params.p_height)))) * 0.5f) + 0.5f) * f32(cw_params.p_width)) - 0.5f);
    var v_v: f32 = (((0.5f - cw_divide_f32(f_dot3(v_q, f_cameraUp(cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid), (v_depth * 0.8f))) * f32(cw_params.p_height)) - 0.5f);
    var v_px: i32 = i32(floor((v_u + 0.5f)));
    var v_py: i32 = i32(floor((v_v + 0.5f)));
    if ((((((v_px >= 0i) && (v_py >= 0i)) && (v_px < cw_params.p_width)) && (v_py < cw_params.p_height)) && (v_depth > f32(0i)))) {
      var v_j: i32 = ((v_py * cw_params.p_width) + v_px);
      var v_og: vec4<f32> = b_oldGuide[v_j];
      var v_on: vec4<f32> = b_oldNormals[v_j];
      var v_h: vec4<f32> = b_oldHistory[v_j];
      var v_threshold: f32 = (0.06f + (v_n.w * 0.008f));
      var v_dist: f32 = f_len3((f_xyz(v_og, cw_thread, cw_block, cw_grid) - f_xyz(v_g, cw_thread, cw_block, cw_grid)), cw_thread, cw_block, cw_grid);
      if ((((v_g.w == v_og.w) && ((v_g.w == f32((-9i))) || (f_dot3(f_xyz(v_n, cw_thread, cw_block, cw_grid), f_xyz(v_on, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid) > 0.82f))) && (v_dist < v_threshold))) {
        var cw_tmp_9: f32;
        if ((cw_params.p_frozen != 0i)) {
          cw_tmp_9 = 256.0f;
        } else {
          cw_tmp_9 = 12.0f;
        }
        var v_cap: f32 = cw_tmp_9;
        if (((v_g.w == f32((-2i))) && (cw_params.p_frozen == 0i))) {
          v_cap = f32(5i);
        }
        if ((b_radiance[v_i].w < f32(0i))) {
          v_count = (floor(v_h.w) + 0.0625f);
          let cw_argument_index_10 = v_i;
          v_value = f_xyz(b_radiance[cw_argument_index_10], cw_thread, cw_block, cw_grid);
        } else {
          v_count = min((floor(v_h.w) + f32(1i)), v_cap);
          v_value = f_mix3(f_xyz(v_h, cw_thread, cw_block, cw_grid), v_value, cw_divide_f32(f32(1i), v_count), cw_thread, cw_block, cw_grid);
        }
      }
    }
  }
  b_history[v_i] = f_v4(v_value, v_count, cw_thread, cw_block, cw_grid);
}
