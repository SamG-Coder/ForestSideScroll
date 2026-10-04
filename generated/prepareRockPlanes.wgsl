// CUDA WebShader 0.1.1. Generated from kernel prepareRockPlanes.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read> b_objects: array<vec4<f32>>;
@group(0) @binding(1) var<storage, read_write> b_rockPlanes: array<vec4<f32>>;
const cw_block_size: vec3<u32> = vec3<u32>(64u, 1u, 1u);

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


fn f_unit(cw_arg_a: vec3<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  return (v_a / vec3<f32>(sqrt(max(1e-16f, f_dot3(v_a, v_a, cw_thread, cw_block, cw_grid)))));
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
































@compute @workgroup_size(64, 1, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  var v_rock: i32 = i32(((cw_block.x * cw_block_size.x) + cw_thread.x));
  if ((v_rock >= 2048i)) {
    return;
  }
  var v_id: i32 = ((((v_rock / 16i) * 2048i) + 1984i) + (v_rock % 16i));
  var v_form: i32 = i32(b_objects[(v_id * 4i)].w);
  var v_seed: u32 = f_hashU(((u32(v_id) * 1771u) + (u32(v_form) * 4291u)), cw_thread, cw_block, cw_grid);
  var v_index: i32 = 0i;
  {
    var v_i: i32 = 0i;
    loop {
      if (!(v_i < 125i)) { break; }
      var v_xx: i32 = ((v_i % 5i) - 2i);
      var v_yy: i32 = (((v_i / 5i) % 5i) - 2i);
      var v_zz: i32 = ((v_i / 25i) - 2i);
      if (((((((v_xx > (-2i)) && (v_xx < 2i)) && (v_yy > (-2i))) && (v_yy < 2i)) && (v_zz > (-2i))) && (v_zz < 2i))) {
        continue;
      }
      var v_n: vec3<f32> = f_unit(f_v3(f32(v_xx), f32(v_yy), f32(v_zz), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
      var v_l1: f32 = ((abs(v_n.x) + abs(v_n.y)) + abs(v_n.z));
      var v_distance: f32 = ((0.57f * v_l1) + 0.25f);
      v_distance = (v_distance + ((f_rnd((v_seed + (u32(v_i) * 43u)), cw_thread, cw_block, cw_grid) - 0.5f) * 0.09f));
      v_distance = (v_distance + (((v_n.x * (f_rnd((v_seed + 51u), cw_thread, cw_block, cw_grid) - 0.5f)) * 0.18f) + ((v_n.z * (f_rnd((v_seed + 71u), cw_thread, cw_block, cw_grid) - 0.5f)) * 0.14f)));
      b_rockPlanes[((v_rock * 104i) + v_index)] = f_v4(v_n, v_distance, cw_thread, cw_block, cw_grid);
      v_index += i32(1);
      continuing {
        v_i += i32(1);
      }
    }
  }
  {
    var v_cut: i32 = 0i;
    loop {
      if (!(v_cut < 6i)) { break; }
      var cw_tmp_6: f32;
      if (((v_cut & 1i) == 0i)) {
        cw_tmp_6 = 1.0f;
      } else {
        cw_tmp_6 = (-1.0f);
      }
      var v_sx: f32 = cw_tmp_6;
      var cw_tmp_7: f32;
      if (((v_cut & 2i) == 0i)) {
        cw_tmp_7 = 1.0f;
      } else {
        cw_tmp_7 = (-1.0f);
      }
      var v_sz: f32 = cw_tmp_7;
      var v_n: vec3<f32> = f_unit(f_v3((v_sx * (0.48f + (f_rnd((v_seed + (u32(v_cut) * 53u)), cw_thread, cw_block, cw_grid) * 0.44f))), (0.58f + (f_rnd((v_seed + (u32(v_cut) * 131u)), cw_thread, cw_block, cw_grid) * 0.5f)), (v_sz * (0.24f + (f_rnd((v_seed + (u32(v_cut) * 71u)), cw_thread, cw_block, cw_grid) * 0.43f))), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
      var v_distance: f32 = (0.75f + (f_rnd((v_seed + (u32(v_cut) * 29u)), cw_thread, cw_block, cw_grid) * 0.22f));
      if ((v_form == 0i)) {
        v_n = f_unit(f_v3((v_sx * 0.21f), f32(1i), (v_sz * 0.12f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
        v_distance = (0.68f + (f_rnd((v_seed + (u32(v_cut) * 13u)), cw_thread, cw_block, cw_grid) * 0.16f));
      }
      if (((v_form == 1i) && (v_cut == 0i))) {
        v_n = f_unit(f_v3(0.73f, f32(1i), (-0.17f), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
        v_distance = 0.46f;
      }
      if (((v_form == 3i) && (v_cut == 0i))) {
        v_n = f_unit(f_v3(0.6f, 0.33f, f32(1i), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
        v_distance = 0.58f;
      }
      b_rockPlanes[(((v_rock * 104i) + 98i) + v_cut)] = f_v4(v_n, v_distance, cw_thread, cw_block, cw_grid);
      continuing {
        v_cut += i32(1);
      }
    }
  }
}
