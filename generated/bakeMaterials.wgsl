// CUDA WebShader 0.1.1. Generated from kernel bakeMaterials.
struct cw_struct_Hit {
  cw_field_t: f32,
  cw_field_id: i32,
  cw_field_normal: vec3<f32>,
}
@group(0) @binding(0) var<storage, read_write> b_atlas: array<u32>;
const cw_block_size: vec3<u32> = vec3<u32>(8u, 8u, 1u);

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

fn f_v4(cw_arg_a: vec3<f32>, cw_arg_w: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec4<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  var v_w: f32 = cw_arg_w;
  return vec4<f32>(v_a.x, v_a.y, v_a.z, v_w);
}







fn f_mix3(cw_arg_a: vec3<f32>, cw_arg_b: vec3<f32>, cw_arg_t: f32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> vec3<f32> {
  var v_a: vec3<f32> = cw_arg_a;
  var v_b: vec3<f32> = cw_arg_b;
  var v_t: f32 = cw_arg_t;
  return (v_a + ((v_b - v_a) * vec3<f32>(v_t)));
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
















fn f_tileNoise(cw_arg_x: f32, cw_arg_y: f32, cw_arg_cells: i32, cw_arg_seed: u32, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> f32 {
  var v_x: f32 = cw_arg_x;
  var v_y: f32 = cw_arg_y;
  var v_cells: i32 = cw_arg_cells;
  var v_seed: u32 = cw_arg_seed;
  var v_px: f32 = (v_x * f32(v_cells));
  var v_py: f32 = (v_y * f32(v_cells));
  var v_ix: i32 = i32(floor(v_px));
  var v_iy: i32 = i32(floor(v_py));
  var v_fx: f32 = f_smoothf(f32(0i), f32(1i), f_fractf(v_px, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_fy: f32 = f_smoothf(f32(0i), f32(1i), f_fractf(v_py, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_mask: i32 = (v_cells - 1i);
  var v_a: f32 = f_rnd((((u32((v_ix & v_mask)) * 7177u) ^ (u32((v_iy & v_mask)) * 313u)) ^ v_seed), cw_thread, cw_block, cw_grid);
  var v_b: f32 = f_rnd((((u32(((v_ix + 1i) & v_mask)) * 7177u) ^ (u32((v_iy & v_mask)) * 313u)) ^ v_seed), cw_thread, cw_block, cw_grid);
  var v_c: f32 = f_rnd((((u32((v_ix & v_mask)) * 7177u) ^ (u32(((v_iy + 1i) & v_mask)) * 313u)) ^ v_seed), cw_thread, cw_block, cw_grid);
  var v_d: f32 = f_rnd((((u32(((v_ix + 1i) & v_mask)) * 7177u) ^ (u32(((v_iy + 1i) & v_mask)) * 313u)) ^ v_seed), cw_thread, cw_block, cw_grid);
  return f_mixf(f_mixf(v_a, v_b, v_fx, cw_thread, cw_block, cw_grid), f_mixf(v_c, v_d, v_fx, cw_thread, cw_block, cw_grid), v_fy, cw_thread, cw_block, cw_grid);
}
fn f_packMaterial(cw_arg_c: vec4<f32>, cw_thread: vec3<u32>, cw_block: vec3<u32>, cw_grid: vec3<u32>) -> u32 {
  var v_c: vec4<f32> = cw_arg_c;
  return (((u32(((f_sat(v_c.x, cw_thread, cw_block, cw_grid) * 255.0f) + 0.5f)) | (u32(((f_sat(v_c.y, cw_thread, cw_block, cw_grid) * 255.0f) + 0.5f)) << u32(8i))) | (u32(((f_sat(v_c.z, cw_thread, cw_block, cw_grid) * 255.0f) + 0.5f)) << u32(16i))) | (u32(((f_sat(v_c.w, cw_thread, cw_block, cw_grid) * 255.0f) + 0.5f)) << u32(24i)));
}














@compute @workgroup_size(8, 8, 1)
fn main(
  @builtin(local_invocation_id) cw_thread: vec3<u32>,
  @builtin(workgroup_id) cw_block: vec3<u32>,
  @builtin(num_workgroups) cw_grid: vec3<u32>
) {
  var v_x: i32 = i32(((cw_block.x * cw_block_size.x) + cw_thread.x));
  var v_y: i32 = i32(((cw_block.y * cw_block_size.y) + cw_thread.y));
  if (((v_x >= 2048i) || (v_y >= 2048i))) {
    return;
  }
  var v_u: f32 = cw_divide_f32(f32(v_x), f32(2048i));
  var v_v: f32 = cw_divide_f32(f32(v_y), f32(2048i));
  var v_broad: f32 = f_tileNoise(v_u, v_v, 4i, 7381u, cw_thread, cw_block, cw_grid);
  var v_clods: f32 = f_tileNoise(v_u, v_v, 32i, 371u, cw_thread, cw_block, cw_grid);
  var v_grit: f32 = f_tileNoise(v_u, v_v, 256i, 191u, cw_thread, cw_block, cw_grid);
  var v_fine: f32 = f_tileNoise(v_u, v_v, 1024i, 621u, cw_thread, cw_block, cw_grid);
  var v_pebbles: f32 = f_smoothf(0.66f, 0.83f, f_tileNoise(v_u, v_v, 128i, 824u, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_cracks: f32 = (f32(1i) - f_smoothf(0.014f, 0.049f, abs((f_tileNoise(v_u, v_v, 16i, 44u, cw_thread, cw_block, cw_grid) - 0.5f)), cw_thread, cw_block, cw_grid));
  var v_soil: vec3<f32> = f_mix3(f_v3(0.11f, 0.068f, 0.028f, cw_thread, cw_block, cw_grid), f_v3(0.29f, 0.2f, 0.104f, cw_thread, cw_block, cw_grid), ((v_broad * 0.55f) + (v_clods * 0.45f)), cw_thread, cw_block, cw_grid);
  v_soil = v_soil * vec3<f32>(((0.68f + (0.48f * v_grit)) + (v_fine * 0.18f)));
  v_soil = v_soil * vec3<f32>((f32(1i) - (v_cracks * 0.25f)));
  v_soil = f_mix3(v_soil, (f_v3(0.3f, 0.24f, 0.16f, cw_thread, cw_block, cw_grid) * vec3<f32>((0.85f + (v_fine * 0.25f)))), (v_pebbles * 0.4f), cw_thread, cw_block, cw_grid);
  b_atlas[((v_y * 2048i) + v_x)] = f_packMaterial(f_v4(v_soil, f_sat(((((v_clods * 0.45f) + (v_grit * 0.26f)) + (v_pebbles * 0.29f)) - (v_cracks * 0.2f)), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_layers: f32 = sin((((v_v * 6.28318530718f) * 24.0f) + (f_tileNoise(v_u, v_v, 8i, 493u, cw_thread, cw_block, cw_grid) * 5.0f)));
  var v_seams: f32 = f_smoothf(0.85f, 0.97f, v_layers, cw_thread, cw_block, cw_grid);
  var v_mineral: f32 = f_tileNoise(v_u, v_v, 512i, 274u, cw_thread, cw_block, cw_grid);
  var v_pits: f32 = f_smoothf(0.68f, 0.86f, f_tileNoise(v_u, v_v, 256i, 3177u, cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
  var v_stone: vec3<f32> = f_mix3(f_v3(0.35f, 0.26f, 0.155f, cw_thread, cw_block, cw_grid), f_v3(0.6f, 0.49f, 0.33f, cw_thread, cw_block, cw_grid), v_broad, cw_thread, cw_block, cw_grid);
  v_stone = v_stone * vec3<f32>(((0.77f + (0.3f * v_mineral)) + (0.12f * v_fine)));
  v_stone = v_stone * vec3<f32>(((f32(1i) - (v_seams * 0.29f)) - (v_pits * 0.23f)));
  v_stone = f_mix3(v_stone, f_v3(0.25f, 0.115f, 0.038f, cw_thread, cw_block, cw_grid), (f_smoothf(0.68f, 0.86f, v_clods, cw_thread, cw_block, cw_grid) * 0.32f), cw_thread, cw_block, cw_grid);
  b_atlas[((5592405i + (v_y * 2048i)) + v_x)] = f_packMaterial(f_v4(v_stone, f_sat(((((0.5f + (v_grit * 0.24f)) + (v_mineral * 0.12f)) - (v_seams * 0.22f)) - (v_pits * 0.27f)), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid), cw_thread, cw_block, cw_grid);
}
